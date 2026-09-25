
#include <errno.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <fcntl.h>
#include <pthread.h>
#include <unistd.h>
#include <termios.h>
#include <sys/event.h>
#include <sys/ioctl.h>
#include <sys/wait.h>

#include "forkpty.h"
#include "flutter_pty.h"

#include "include/dart_api.h"
#include "include/dart_api_dl.h"
#include "include/dart_native_api.h"

// ShellX: input the writer thread has yet to write, oldest first.
typedef struct WriteChunk
{
    struct WriteChunk *next;

    size_t length;

    char data[];

} WriteChunk;

// ShellX: at most this much input waits for a process that is not reading
// its terminal; pty_write drops (and reports) what does not fit.
#define WRITE_QUEUE_LIMIT (1024 * 1024)

typedef struct PtyHandle
{
    int ptm;

    int pid;

    pthread_mutex_t mutex;

    bool ackRead;

    // ShellX: the writer thread and its queue (guarded by write_lock). A
    // blocking write() on the master blocks for as long as the process does
    // not read its input; upstream did it on the calling (UI) isolate.
    pthread_t writer;

    pthread_mutex_t write_lock;

    pthread_cond_t write_ready;

    WriteChunk *write_head;

    WriteChunk *write_tail;

    size_t write_queued;

    bool write_stop;

} PtyHandle;

typedef struct ReadLoopOptions
{
    int fd;

    pthread_mutex_t *mutex;

    Dart_Port port;

    bool waitForReadAck;

} ReadLoopOptions;

char *error_message = NULL;

// ShellX, tests only: see pty_debug_fail in flutter_pty.h.
static int debug_fail_step = 0;

FFI_PLUGIN_EXPORT void pty_debug_fail(int step)
{
    debug_fail_step = step;
}

// ShellX: pty_error() returns this, with errno, instead of always NULL.
static char error_buffer[128];

static void *read_loop(void *arg)
{
    ReadLoopOptions *options = (ReadLoopOptions *)arg;

    char buffer[1024];

    while (1)
    {
        if (options->waitForReadAck)
        {
            // if we are in ack mode then we get a mutex here that is
            // freed again once the chunk of data has been processed
            pthread_mutex_lock(options->mutex);
        }
        ssize_t n = read(options->fd, buffer, sizeof(buffer));

        if (n < 0 && errno == EINTR)
        {
            if (options->waitForReadAck)
            {
                pthread_mutex_unlock(options->mutex);
            }
            continue;
        }

        // ShellX: EOF (0) or EIO (-1): every process that had the slave open
        // has closed it.
        if (n <= 0)
        {
            if (options->waitForReadAck)
            {
                pthread_mutex_unlock(options->mutex);
            }
            break;
        }

        Dart_CObject result;
        result.type = Dart_CObject_kTypedData;
        result.value.as_typed_data.type = Dart_TypedData_kUint8;
        result.value.as_typed_data.length = n;
        result.value.as_typed_data.values = (uint8_t *)buffer;

        Dart_PostCObject_DL(options->port, &result);
    }

    // ShellX: tell Dart the output has ended (a null message), so it closes
    // the stream only after the last chunk. The handle (options->mutex) may be
    // released as soon as Dart has this and the exit code: no access to it
    // from here on.
    Dart_CObject end;
    end.type = Dart_CObject_kNull;
    Dart_PostCObject_DL(options->port, &end);

    free(options);

    return NULL;
}

// ShellX: writes the queued input in order, retrying partial writes and
// EINTR. A write that fails (EIO once the terminal is gone) drops the rest
// of that chunk. Stops when write_stop is set, freeing what is left.
static void *write_loop(void *arg)
{
    PtyHandle *handle = (PtyHandle *)arg;

    pthread_mutex_lock(&handle->write_lock);

    while (1)
    {
        while (!handle->write_stop && handle->write_head == NULL)
        {
            pthread_cond_wait(&handle->write_ready, &handle->write_lock);
        }

        if (handle->write_stop)
        {
            break;
        }

        // Stays at the head (and counted) while it is written, so pty_write
        // only ever appends.
        WriteChunk *chunk = handle->write_head;

        pthread_mutex_unlock(&handle->write_lock);

        size_t offset = 0;

        while (offset < chunk->length)
        {
            ssize_t n = write(handle->ptm, chunk->data + offset, chunk->length - offset);

            if (n < 0 && errno == EINTR)
            {
                continue;
            }

            if (n <= 0)
            {
                break;
            }

            offset += (size_t)n;
        }

        pthread_mutex_lock(&handle->write_lock);

        handle->write_head = chunk->next;

        if (handle->write_head == NULL)
        {
            handle->write_tail = NULL;
        }

        handle->write_queued -= chunk->length;

        free(chunk);
    }

    while (handle->write_head != NULL)
    {
        WriteChunk *chunk = handle->write_head;
        handle->write_head = chunk->next;
        free(chunk);
    }

    handle->write_tail = NULL;
    handle->write_queued = 0;

    pthread_mutex_unlock(&handle->write_lock);

    return NULL;
}

// ShellX: stops the writer thread and waits for it. Called only once the
// process has exited and the output has ended, i.e. no process has the
// terminal open any more: a write() still blocked on the master then fails
// at once (EIO), so this never waits for a process that does not read.
static void stop_writer(PtyHandle *handle)
{
    pthread_mutex_lock(&handle->write_lock);
    handle->write_stop = true;
    pthread_cond_signal(&handle->write_ready);
    pthread_mutex_unlock(&handle->write_lock);

    pthread_join(handle->writer, NULL);
}

typedef struct WaitExitOptions
{
    int pid;

    // ShellX: kqueue watching the process for NOTE_EXIT, or -1.
    int kq;

    Dart_Port port;

} WaitExitOptions;

// ShellX: a kqueue that reports the exit status of child [pid], or -1.
static int watch_exit(pid_t pid)
{
    int kq = kqueue();

    if (kq < 0)
    {
        return -1;
    }

    struct kevent change;
    EV_SET(&change, pid, EVFILT_PROC, EV_ADD | EV_ONESHOT, NOTE_EXIT | NOTE_EXITSTATUS, 0, NULL);

    if (kevent(kq, &change, 1, NULL, 0, NULL) < 0)
    {
        close(kq);
        return -1;
    }

    return kq;
}

// ShellX: waits for the process to exit and stores its wait(2) status;
// returns 0 when the status is lost.
//
// dart:io's exit code thread calls wait() for any child while a Process it
// started is running (the agent always runs caffeinate), so it can reap the
// shell before waitpid() here does. The kqueue (NOTE_EXIT | NOTE_EXITSTATUS)
// reports the status whoever reaps. waitpid() still reaps the zombie when we
// are the reaper (it returns at once with ECHILD when dart:io was), and
// supplies the status when the kqueue could not be set up.
static int wait_for_exit_status(WaitExitOptions *options, int *status)
{
    int have_status = 0;

    if (options->kq >= 0)
    {
        struct kevent event;
        int n;

        do
        {
            n = kevent(options->kq, NULL, 0, &event, 1, NULL);
        } while (n < 0 && errno == EINTR);

        if (n == 1 && (event.fflags & NOTE_EXIT))
        {
            *status = (int)event.data;
            have_status = 1;
        }

        close(options->kq);
    }

    int reaped_status = 0;
    pid_t waited;

    do
    {
        waited = waitpid(options->pid, &reaped_status, 0);
    } while (waited < 0 && errno == EINTR);

    if (!have_status && waited == options->pid)
    {
        *status = reaped_status;
        have_status = 1;
    }

    return have_status;
}

static void *wait_exit_thread(void *arg)
{
    WaitExitOptions *options = (WaitExitOptions *)arg;

    int status = 0;

    if (!wait_for_exit_status(options, &status))
    {
        // ShellX: it has exited but its status is lost; still report the exit.
        Dart_PostInteger_DL(options->port, -1);
    }
    else if (WIFEXITED(status))
    {
        Dart_PostInteger_DL(options->port, WEXITSTATUS(status));
    }
    else if (WIFSIGNALED(status))
    {
        Dart_PostInteger_DL(options->port, -WTERMSIG(status));
    }
    else
    {
        Dart_PostInteger_DL(options->port, -1);
    }

    free(options);

    return NULL;
}

static void set_environment(char **environment)
{
    if (environment == NULL)
    {
        return;
    }

    while (*environment != NULL)
    {
        putenv(*environment);
        environment++;
    }
}

// ShellX: every thread the pty needs (writer, exit, output reader) is
// started while the child still waits on the sync pipe; if anything fails
// (memory, pthread_create), the child is killed before it runs anything,
// everything is released and the spawn fails (upstream reported success
// with a pty that never delivered output or its exit).
FFI_PLUGIN_EXPORT PtyHandle *pty_create(PtyOptions *options)
{
    struct winsize ws;

    ws.ws_row = options->rows;
    ws.ws_col = options->cols;

    int fail_step = debug_fail_step;

    debug_fail_step = 0;

    int ptm;

    int pts;

    // ShellX: the child waits on this pipe until the parent watches it with
    // kqueue and has started its threads, so it cannot exit (and be reaped
    // by someone else) unwatched, and it never runs without them.
    int sync_pipe[2];

    if (pipe(sync_pipe) < 0)
    {
        snprintf(error_buffer, sizeof(error_buffer), "pipe failed (errno %d)", errno);
        error_message = error_buffer;
        return NULL;
    }

    fcntl(sync_pipe[0], F_SETFD, FD_CLOEXEC);
    fcntl(sync_pipe[1], F_SETFD, FD_CLOEXEC);

    int pid = pty_forkpty(&ptm, &pts, NULL, &ws);

    if (pid < 0)
    {
        snprintf(error_buffer, sizeof(error_buffer), "pty_forkpty failed (errno %d)", errno);
        error_message = error_buffer;
        close(sync_pipe[0]);
        close(sync_pipe[1]);
        return NULL;
    }

    if (pid == 0)
    {
        char go;

        close(sync_pipe[1]);

        while (read(sync_pipe[0], &go, 1) < 0 && errno == EINTR)
        {
        }

        close(sync_pipe[0]);

        set_environment(options->environment);

        if (options->working_directory != NULL && strlen(options->working_directory) > 0)
        {
            chdir(options->working_directory);
        }

        execvp(options->executable, options->arguments);

        // ShellX: never fall through into the parent's code in the child.
        perror("execvp");
        _exit(127);
    }

    // ShellX: the parent never uses the slave. Keeping it open leaked it and
    // meant reading the master could never reach end of file.
    close(pts);

    close(sync_pipe[0]);

    int kq = watch_exit(pid);

    PtyHandle *handle = fail_step == 1 ? NULL : (PtyHandle *)calloc(1, sizeof(PtyHandle));
    ReadLoopOptions *read_options = malloc(sizeof(ReadLoopOptions));
    WaitExitOptions *wait_options = malloc(sizeof(WaitExitOptions));
    bool handle_ready = false;
    bool writer_started = false;
    bool exit_thread_started = false;
    pthread_t thread;

    if (handle == NULL || read_options == NULL || wait_options == NULL)
    {
        snprintf(error_buffer, sizeof(error_buffer), "out of memory");
        error_message = error_buffer;
        goto fail;
    }

    handle->ptm = ptm;
    handle->pid = pid;
    pthread_mutex_init(&handle->mutex, NULL);
    handle->ackRead = options->ackRead;
    pthread_mutex_init(&handle->write_lock, NULL);
    pthread_cond_init(&handle->write_ready, NULL);
    handle_ready = true;

    if (fail_step == 2 || pthread_create(&handle->writer, NULL, &write_loop, handle) != 0)
    {
        snprintf(error_buffer, sizeof(error_buffer), "cannot start the writer thread");
        error_message = error_buffer;
        goto fail;
    }

    writer_started = true;

    wait_options->pid = pid;
    wait_options->kq = kq;
    wait_options->port = options->exit_port;

    if (fail_step == 3 || pthread_create(&thread, NULL, &wait_exit_thread, wait_options) != 0)
    {
        snprintf(error_buffer, sizeof(error_buffer), "cannot start the exit thread");
        error_message = error_buffer;
        goto fail;
    }

    // Detached: its resources are freed when it ends. It owns the kqueue
    // and its options from here on, and reaps the child.
    pthread_detach(thread);
    wait_options = NULL;
    kq = -1;
    exit_thread_started = true;

    read_options->fd = ptm;
    read_options->port = options->stdout_port;
    read_options->mutex = &handle->mutex;
    read_options->waitForReadAck = options->ackRead;

    if (fail_step == 4 || pthread_create(&thread, NULL, &read_loop, read_options) != 0)
    {
        snprintf(error_buffer, sizeof(error_buffer), "cannot start the output reader");
        error_message = error_buffer;
        goto fail;
    }

    pthread_detach(thread);

    // Let the child go on.
    char go = 1;

    while (write(sync_pipe[1], &go, 1) < 0 && errno == EINTR)
    {
    }

    close(sync_pipe[1]);

    return handle;

fail:
    // The child still waits on the sync pipe: kill it before closing the
    // pipe (end of file would let it run).
    kill(pid, SIGKILL);
    close(sync_pipe[1]);

    if (!exit_thread_started)
    {
        if (kq >= 0)
        {
            close(kq);
        }

        while (waitpid(pid, NULL, 0) < 0 && errno == EINTR)
        {
        }
    }

    // Otherwise the exit thread reaps it and posts to the exit port, which
    // Dart closes when this returns NULL. It never touches the handle.

    if (writer_started)
    {
        stop_writer(handle);
    }

    close(ptm);

    if (handle_ready)
    {
        pthread_cond_destroy(&handle->write_ready);
        pthread_mutex_destroy(&handle->write_lock);
        pthread_mutex_destroy(&handle->mutex);
    }

    free(handle);
    free(read_options);
    free(wait_options);

    return NULL;
}

// ShellX: never blocks. Queues a copy of the input for the writer thread;
// returns 0 (the input is dropped) when that would put more than
// WRITE_QUEUE_LIMIT bytes in the queue or memory runs out, else 1.
FFI_PLUGIN_EXPORT int pty_write(PtyHandle *handle, char *buffer, int length)
{
    if (length <= 0)
    {
        return 1;
    }

    WriteChunk *chunk = malloc(sizeof(WriteChunk) + (size_t)length);

    if (chunk == NULL)
    {
        return 0;
    }

    chunk->next = NULL;
    chunk->length = (size_t)length;
    memcpy(chunk->data, buffer, (size_t)length);

    int accepted = 0;

    pthread_mutex_lock(&handle->write_lock);

    if (!handle->write_stop && handle->write_queued + chunk->length <= WRITE_QUEUE_LIMIT)
    {
        if (handle->write_tail != NULL)
        {
            handle->write_tail->next = chunk;
        }
        else
        {
            handle->write_head = chunk;
        }

        handle->write_tail = chunk;
        handle->write_queued += chunk->length;
        pthread_cond_signal(&handle->write_ready);
        accepted = 1;
    }

    pthread_mutex_unlock(&handle->write_lock);

    if (!accepted)
    {
        free(chunk);
    }

    return accepted;
}

FFI_PLUGIN_EXPORT void pty_ack_read(PtyHandle *handle)
{
    if (handle->ackRead)
    {
        // frees the mutex so that the next chunk of data can be read
        pthread_mutex_unlock(&handle->mutex);
    }
}

FFI_PLUGIN_EXPORT int pty_resize(PtyHandle *handle, int rows, int cols)
{
    struct winsize ws;

    ws.ws_row = rows;
    ws.ws_col = cols;

    return ioctl(handle->ptm, TIOCSWINSZ, &ws);
}

FFI_PLUGIN_EXPORT int pty_getpid(PtyHandle *handle)
{
    return handle->pid;
}

FFI_PLUGIN_EXPORT char *pty_error(void)
{
    return error_message;
}

FFI_PLUGIN_EXPORT void pty_release(PtyHandle *handle)
{
    stop_writer(handle);
    close(handle->ptm);
    pthread_cond_destroy(&handle->write_ready);
    pthread_mutex_destroy(&handle->write_lock);
    pthread_mutex_destroy(&handle->mutex);
    free(handle);
}
