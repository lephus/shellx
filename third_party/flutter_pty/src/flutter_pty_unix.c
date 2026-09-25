
#include <errno.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

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

typedef struct PtyHandle
{
    int ptm;

    int pid;

    pthread_mutex_t mutex;

    bool ackRead;

} PtyHandle;

typedef struct ReadLoopOptions
{
    int fd;

    pthread_mutex_t *mutex;

    Dart_Port port;

    bool waitForReadAck;

} ReadLoopOptions;

char *error_message = NULL;

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

static void start_read_thread(int fd, Dart_Port port, pthread_mutex_t *mutex, bool waitForReadAck)
{
    ReadLoopOptions *options = malloc(sizeof(ReadLoopOptions));

    options->fd = fd;

    options->port = port;

    options->mutex = mutex;

    options->waitForReadAck = waitForReadAck;

    pthread_t _thread;

    // ShellX: detached, so the thread's resources are freed when it ends.
    if (pthread_create(&_thread, NULL, &read_loop, options) == 0)
    {
        pthread_detach(_thread);
    }
    else
    {
        free(options);
    }
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

static void start_wait_exit_thread(int pid, int kq, Dart_Port port)
{
    WaitExitOptions *options = malloc(sizeof(WaitExitOptions));

    options->pid = pid;

    options->kq = kq;

    options->port = port;

    pthread_t _thread;

    if (pthread_create(&_thread, NULL, &wait_exit_thread, options) == 0)
    {
        pthread_detach(_thread);
    }
    else
    {
        if (kq >= 0)
        {
            close(kq);
        }
        free(options);
    }
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

FFI_PLUGIN_EXPORT PtyHandle *pty_create(PtyOptions *options)
{
    struct winsize ws;

    ws.ws_row = options->rows;
    ws.ws_col = options->cols;

    int ptm;

    int pts;

    // ShellX: the child waits on this pipe until the parent watches it with
    // kqueue, so it cannot exit (and be reaped by someone else) unwatched.
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

    char go = 1;

    while (write(sync_pipe[1], &go, 1) < 0 && errno == EINTR)
    {
    }

    close(sync_pipe[1]);

    PtyHandle *handle = (PtyHandle *)malloc(sizeof(PtyHandle));

    handle->ptm = ptm;
    handle->pid = pid;
    pthread_mutex_init(&handle->mutex, NULL);
    handle->ackRead = options->ackRead;

    start_read_thread(ptm, options->stdout_port, &handle->mutex, options->ackRead);

    start_wait_exit_thread(pid, kq, options->exit_port);

    return handle;
}

FFI_PLUGIN_EXPORT void pty_write(PtyHandle *handle, char *buffer, int length)
{
    write(handle->ptm, buffer, length);
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
    close(handle->ptm);
    pthread_mutex_destroy(&handle->mutex);
    free(handle);
}
