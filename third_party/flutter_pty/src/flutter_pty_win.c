#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <Windows.h>

#include "flutter_pty.h"

#include "include/dart_api.h"
#include "include/dart_api_dl.h"
#include "include/dart_native_api.h"

// ShellX: the command line, environment block and working directory arrive as
// UTF-8 and are converted with MultiByteToWideChar (upstream widened every
// byte on its own, which mangled any non-ASCII text).
static LPWSTR utf8_to_wide(const char *text)
{
    int length = MultiByteToWideChar(CP_UTF8, 0, text, -1, NULL, 0);

    if (length <= 0)
    {
        return NULL;
    }

    LPWSTR wide = malloc(length * sizeof(WCHAR));

    if (wide == NULL)
    {
        return NULL;
    }

    if (MultiByteToWideChar(CP_UTF8, 0, text, -1, wide, length) != length)
    {
        free(wide);
        return NULL;
    }

    return wide;
}

// ShellX: arguments[0] duplicates executable (the Dart side builds argv the
// POSIX way), so it is skipped; upstream put the executable on the command
// line twice. The executable and the arguments are written exactly as given:
// the caller quotes them (CommandLineToArgvW rules).
static LPWSTR build_command(char *executable, char **arguments)
{
    size_t command_length = 0;

    if (executable != NULL)
    {
        command_length += strlen(executable);
    }

    if (arguments != NULL && arguments[0] != NULL)
    {
        int i = 1;

        while (arguments[i] != NULL)
        {
            command_length += strlen(arguments[i]) + 1;
            i++;
        }
    }

    char *command = malloc(command_length + 1);

    if (command == NULL)
    {
        return NULL;
    }

    size_t length = 0;

    if (executable != NULL)
    {
        memcpy(command, executable, strlen(executable));
        length += strlen(executable);
    }

    if (arguments != NULL && arguments[0] != NULL)
    {
        int i = 1;

        while (arguments[i] != NULL)
        {
            command[length++] = ' ';
            memcpy(command + length, arguments[i], strlen(arguments[i]));
            length += strlen(arguments[i]);
            i++;
        }
    }

    command[length] = 0;

    LPWSTR wide = utf8_to_wide(command);

    free(command);

    return wide;
}

static LPWSTR build_environment(char **environment)
{
    size_t environment_block_length = 0;

    int i = 0;

    while (environment[i] != NULL)
    {
        int length = MultiByteToWideChar(CP_UTF8, 0, environment[i], -1, NULL, 0);

        if (length <= 0)
        {
            return NULL;
        }

        environment_block_length += length;
        i++;
    }

    // Each entry ends with its own NUL; the block ends with one more. The
    // extra element keeps an empty block double-NUL terminated.
    LPWSTR environment_block = calloc(environment_block_length + 2, sizeof(WCHAR));

    if (environment_block == NULL)
    {
        return NULL;
    }

    size_t offset = 0;

    i = 0;

    while (environment[i] != NULL)
    {
        int length = MultiByteToWideChar(CP_UTF8, 0, environment[i], -1, NULL, 0);

        if (length <= 0 ||
            MultiByteToWideChar(CP_UTF8, 0, environment[i], -1, environment_block + offset, length) != length)
        {
            free(environment_block);
            return NULL;
        }

        offset += length;
        i++;
    }

    return environment_block;
}

typedef struct PtyHandle
{
    HANDLE inputWriteSide;

    // ShellX: closed by the exit thread as soon as the process exits;
    // guarded by lock so pty_resize never uses a closed pseudo console.
    HPCON hPty;

    SRWLOCK lock;

    // ShellX: job object holding the process and everything it starts, or
    // NULL when it could not be set up (jobError says why).
    HANDLE job;

    DWORD jobError;

    // ShellX: set by pty_kill; see pty_release.
    BOOL killed;

    // ShellX: kept open until pty_release so pty_kill can still use it.
    HANDLE hProcess;

    DWORD dwProcessId;

    BOOL ackRead;

    HANDLE hMutex;

} PtyHandle;

typedef struct ReadLoopOptions
{
    HANDLE fd;

    Dart_Port port;

    HANDLE hMutex;

    BOOL ackRead;

} ReadLoopOptions;

static DWORD WINAPI read_loop(LPVOID arg)
{
    ReadLoopOptions *options = (ReadLoopOptions *)arg;

    char buffer[1024];

    while (1)
    {
        DWORD readlen = 0;

        if (options->ackRead)
        {
            WaitForSingleObject(options->hMutex, INFINITE);
        }

        BOOL ok = ReadFile(options->fd, buffer, sizeof(buffer), &readlen, NULL);

        // ShellX: fails (ERROR_BROKEN_PIPE) once the pseudo console has been
        // closed and conhost has written its last output.
        if (!ok)
        {
            break;
        }

        if (readlen == 0)
        {
            if (options->ackRead)
            {
                ReleaseSemaphore(options->hMutex, 1, NULL);
            }
            continue;
        }

        Dart_CObject result;
        result.type = Dart_CObject_kTypedData;
        result.value.as_typed_data.type = Dart_TypedData_kUint8;
        result.value.as_typed_data.length = readlen;
        result.value.as_typed_data.values = (uint8_t *)buffer;

        Dart_PostCObject_DL(options->port, &result);
    }

    // ShellX: the reader owns the read side of the output pipe. Then tell
    // Dart the output has ended (a null message); the handle may be released
    // as soon as Dart has this and the exit code.
    CloseHandle(options->fd);

    Dart_CObject end;
    end.type = Dart_CObject_kNull;
    Dart_PostCObject_DL(options->port, &end);

    free(options);

    return 0;
}

typedef struct WaitExitOptions
{
    HANDLE pid;

    Dart_Port port;

    PtyHandle *pty;

} WaitExitOptions;

static DWORD WINAPI wait_exit_thread(LPVOID arg)
{
    WaitExitOptions *options = (WaitExitOptions *)arg;

    DWORD exit_code = 0;

    WaitForSingleObject(options->pid, INFINITE);

    GetExitCodeProcess(options->pid, &exit_code);

    // ShellX: close the pseudo console once the process has exited, so conhost
    // ends and the output pipe reaches end of file (upstream never closed it
    // and leaked a conhost.exe per session). ClosePseudoConsole may wait for
    // conhost to flush; the reader thread keeps draining meanwhile.
    AcquireSRWLockExclusive(&options->pty->lock);
    HPCON hPty = options->pty->hPty;
    options->pty->hPty = NULL;
    ReleaseSRWLockExclusive(&options->pty->lock);

    if (hPty != NULL)
    {
        ClosePseudoConsole(hPty);
    }

    // Last access to the handle is above: once Dart has the exit code and the
    // end of output it may release the handle.
    Dart_PostInteger_DL(options->port, exit_code);

    free(options);

    return 0;
}

char *error_message = NULL;

// ShellX: pty_error() reports the failing step with its Win32 error code.
static char error_buffer[160];

static void set_error(const char *what, DWORD code)
{
    snprintf(error_buffer, sizeof(error_buffer), "%s (error %lu)", what, (unsigned long)code);
    error_message = error_buffer;
}

static void set_error_hresult(const char *what, HRESULT code)
{
    snprintf(error_buffer, sizeof(error_buffer), "%s (HRESULT 0x%08lx)", what, (unsigned long)code);
    error_message = error_buffer;
}

static DWORD last_error_or_failure(void)
{
    DWORD error = GetLastError();

    return error != 0 ? error : ERROR_GEN_FAILURE;
}

// ShellX: the whole job, or only the process when it has no job.
static BOOL terminate_tree(HANDLE job, HANDLE process)
{
    return job != NULL ? TerminateJobObject(job, 1) : TerminateProcess(process, 1);
}

// ShellX: rewritten for correctness; every failure path releases what was
// created before it (upstream leaked the pseudo console, i.e. a conhost.exe,
// and the pipes whenever a step failed).
//
// Order: pipes -> pseudo console -> job object -> process created suspended
// -> process assigned to the job -> exit thread -> output reader -> resume.
// A job object that cannot be set up does not fail the spawn: the process
// runs without one, pty_kill ends the process only, and pty_job_error tells.
// The shell runs no instruction before the reader is running, which is what
// upstream's Sleep(1000) on the calling (UI) thread tried to approximate; the
// sleep is gone.
FFI_PLUGIN_EXPORT PtyHandle *pty_create(PtyOptions *options)
{
    HANDLE inputReadSide = NULL;
    HANDLE inputWriteSide = NULL;
    HANDLE outputReadSide = NULL;
    HANDLE outputWriteSide = NULL;
    HPCON hPty = NULL;
    HANDLE job = NULL;
    DWORD job_error = 0;
    HANDLE mutex = NULL;
    LPWSTR command = NULL;
    LPWSTR environment_block = NULL;
    LPWSTR working_directory = NULL;
    BOOL attributes_initialized = FALSE;
    BOOL process_created = FALSE;
    STARTUPINFOEXW startupInfo;
    PROCESS_INFORMATION processInfo;
    JOBOBJECT_EXTENDED_LIMIT_INFORMATION jobLimits;
    SIZE_T bytesRequired = 0;
    COORD size;
    HRESULT result;
    PtyHandle *pty = NULL;
    ReadLoopOptions *readOptions = NULL;
    WaitExitOptions *waitOptions = NULL;
    HANDLE waitThread = NULL;
    HANDLE readThread = NULL;

    ZeroMemory(&startupInfo, sizeof(startupInfo));
    ZeroMemory(&processInfo, sizeof(processInfo));
    ZeroMemory(&jobLimits, sizeof(jobLimits));

    if (!CreatePipe(&inputReadSide, &inputWriteSide, NULL, 0))
    {
        set_error("Failed to create input pipe", GetLastError());
        goto fail;
    }

    if (!CreatePipe(&outputReadSide, &outputWriteSide, NULL, 0))
    {
        set_error("Failed to create output pipe", GetLastError());
        goto fail;
    }

    size.X = (SHORT)options->cols;
    size.Y = (SHORT)options->rows;

    result = CreatePseudoConsole(size, inputReadSide, outputWriteSide, 0, &hPty);

    if (FAILED(result))
    {
        hPty = NULL;
        set_error_hresult("Failed to create pseudo console", result);
        goto fail;
    }

    // The pseudo console has its own duplicates of these. Keeping ours open
    // would keep the output pipe from ever reporting end of file.
    CloseHandle(inputReadSide);
    inputReadSide = NULL;
    CloseHandle(outputWriteSide);
    outputWriteSide = NULL;

    command = build_command(options->executable, options->arguments);

    if (command == NULL)
    {
        set_error("Failed to build the command line", GetLastError());
        goto fail;
    }

    if (options->environment != NULL)
    {
        environment_block = build_environment(options->environment);

        if (environment_block == NULL)
        {
            set_error("Failed to build the environment block", GetLastError());
            goto fail;
        }
    }

    if (options->working_directory != NULL && options->working_directory[0] != 0)
    {
        working_directory = utf8_to_wide(options->working_directory);

        if (working_directory == NULL)
        {
            set_error("Failed to convert the working directory", GetLastError());
            goto fail;
        }
    }

    startupInfo.StartupInfo.cb = sizeof(startupInfo);
    startupInfo.StartupInfo.dwFlags = STARTF_USESTDHANDLES;
    startupInfo.StartupInfo.hStdInput = NULL;
    startupInfo.StartupInfo.hStdOutput = NULL;
    startupInfo.StartupInfo.hStdError = NULL;

    InitializeProcThreadAttributeList(NULL, 1, 0, &bytesRequired);
    startupInfo.lpAttributeList = (LPPROC_THREAD_ATTRIBUTE_LIST)malloc(bytesRequired);

    if (startupInfo.lpAttributeList == NULL)
    {
        set_error("Failed to allocate proc thread attribute list", ERROR_NOT_ENOUGH_MEMORY);
        goto fail;
    }

    if (!InitializeProcThreadAttributeList(startupInfo.lpAttributeList, 1, 0, &bytesRequired))
    {
        set_error("Failed to initialize proc thread attribute list", GetLastError());
        goto fail;
    }

    attributes_initialized = TRUE;

    if (!UpdateProcThreadAttribute(startupInfo.lpAttributeList,
                                   0,
                                   PROC_THREAD_ATTRIBUTE_PSEUDOCONSOLE,
                                   hPty,
                                   sizeof(hPty),
                                   NULL,
                                   NULL))
    {
        set_error("Failed to update proc thread attribute list", GetLastError());
        goto fail;
    }

    // ShellX: a job object that kills everything in it when its last handle
    // closes: pty_kill terminates the whole tree, and nothing outlives the
    // released pty (or the agent, if it crashes).
    job = CreateJobObjectW(NULL, NULL);

    if (job == NULL)
    {
        job_error = last_error_or_failure();
    }
    else
    {
        jobLimits.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;

        if (!SetInformationJobObject(job, JobObjectExtendedLimitInformation, &jobLimits, sizeof(jobLimits)))
        {
            job_error = last_error_or_failure();
            CloseHandle(job);
            job = NULL;
        }
    }

    // Suspended until it is in the job, so it cannot start a child outside it.
    if (!CreateProcessW(NULL,
                        command,
                        NULL,
                        NULL,
                        FALSE,
                        EXTENDED_STARTUPINFO_PRESENT | CREATE_UNICODE_ENVIRONMENT | CREATE_SUSPENDED,
                        environment_block,
                        working_directory,
                        &startupInfo.StartupInfo,
                        &processInfo))
    {
        set_error("Failed to create process", GetLastError());
        goto fail;
    }

    process_created = TRUE;

    // E.g. the agent itself runs in a job that refuses a nested one.
    if (job != NULL && !AssignProcessToJobObject(job, processInfo.hProcess))
    {
        job_error = last_error_or_failure();
        CloseHandle(job);
        job = NULL;
    }

    mutex = CreateSemaphoreW(NULL, 1, 1, NULL);

    if (mutex == NULL)
    {
        set_error("Failed to create semaphore", GetLastError());
        goto fail;
    }

    pty = malloc(sizeof(PtyHandle));
    readOptions = malloc(sizeof(ReadLoopOptions));
    waitOptions = malloc(sizeof(WaitExitOptions));

    if (pty == NULL || readOptions == NULL || waitOptions == NULL)
    {
        set_error("Failed to allocate pty handle", ERROR_NOT_ENOUGH_MEMORY);
        goto fail;
    }

    pty->inputWriteSide = inputWriteSide;
    pty->hPty = hPty;
    InitializeSRWLock(&pty->lock);
    pty->job = job;
    pty->jobError = job_error;
    pty->killed = FALSE;
    pty->hProcess = processInfo.hProcess;
    pty->dwProcessId = processInfo.dwProcessId;
    pty->ackRead = options->ackRead;
    pty->hMutex = mutex;

    waitOptions->pid = processInfo.hProcess;
    waitOptions->port = options->exit_port;
    waitOptions->pty = pty;

    readOptions->fd = outputReadSide;
    readOptions->port = options->stdout_port;
    readOptions->hMutex = mutex;
    readOptions->ackRead = options->ackRead;

    waitThread = CreateThread(NULL, 0, wait_exit_thread, waitOptions, 0, NULL);

    if (waitThread == NULL)
    {
        set_error("Failed to start the exit thread", GetLastError());
        goto fail;
    }

    readThread = CreateThread(NULL, 0, read_loop, readOptions, 0, NULL);

    if (readThread == NULL)
    {
        set_error("Failed to start the output reader", GetLastError());

        // The process never ran. Ending it lets the exit thread close the
        // pseudo console and free its options; closing the output read side
        // first means conhost cannot block writing to it.
        TerminateProcess(processInfo.hProcess, 1);
        CloseHandle(outputReadSide);
        outputReadSide = NULL;
        WaitForSingleObject(waitThread, INFINITE);
        CloseHandle(waitThread);
        hPty = NULL;
        waitOptions = NULL;
        goto fail;
    }

    CloseHandle(waitThread);
    CloseHandle(readThread);

    if (ResumeThread(processInfo.hThread) == (DWORD)-1)
    {
        // Surfaces as an immediate exit with code 1.
        terminate_tree(job, processInfo.hProcess);
    }

    CloseHandle(processInfo.hThread);

    DeleteProcThreadAttributeList(startupInfo.lpAttributeList);
    free(startupInfo.lpAttributeList);
    free(command);
    free(environment_block);
    free(working_directory);

    return pty;

fail:
    if (process_created)
    {
        TerminateProcess(processInfo.hProcess, 1);
        CloseHandle(processInfo.hThread);
        CloseHandle(processInfo.hProcess);
    }

    if (job != NULL)
    {
        CloseHandle(job);
    }

    // Close our read side before the pseudo console so a conhost with output
    // left to write cannot block ClosePseudoConsole.
    if (outputReadSide != NULL)
    {
        CloseHandle(outputReadSide);
    }

    if (hPty != NULL)
    {
        ClosePseudoConsole(hPty);
    }

    if (inputReadSide != NULL)
    {
        CloseHandle(inputReadSide);
    }

    if (inputWriteSide != NULL)
    {
        CloseHandle(inputWriteSide);
    }

    if (outputWriteSide != NULL)
    {
        CloseHandle(outputWriteSide);
    }

    if (mutex != NULL)
    {
        CloseHandle(mutex);
    }

    if (attributes_initialized)
    {
        DeleteProcThreadAttributeList(startupInfo.lpAttributeList);
    }

    free(startupInfo.lpAttributeList);
    free(command);
    free(environment_block);
    free(working_directory);
    free(pty);
    free(readOptions);
    free(waitOptions);

    return NULL;
}

FFI_PLUGIN_EXPORT void pty_write(PtyHandle *handle, char *buffer, int length)
{
    DWORD bytesWritten;

    WriteFile(handle->inputWriteSide, buffer, length, &bytesWritten, NULL);

    FlushFileBuffers(handle->inputWriteSide);

    return;
}

FFI_PLUGIN_EXPORT void pty_ack_read(PtyHandle *handle)
{
    if (handle->ackRead)
    {
        ReleaseSemaphore(handle->hMutex, 1, NULL);
    }
}

FFI_PLUGIN_EXPORT int pty_resize(PtyHandle *handle, int rows, int cols)
{
    COORD size;

    size.X = cols;
    size.Y = rows;

    HRESULT result = E_HANDLE;

    AcquireSRWLockShared(&handle->lock);

    if (handle->hPty != NULL)
    {
        result = ResizePseudoConsole(handle->hPty, size);
    }

    ReleaseSRWLockShared(&handle->lock);

    return (int)result;
}

FFI_PLUGIN_EXPORT int pty_getpid(PtyHandle *handle)
{
    return (int)handle->dwProcessId;
}

FFI_PLUGIN_EXPORT char *pty_error()
{
    return error_message;
}

FFI_PLUGIN_EXPORT int pty_kill(PtyHandle *handle)
{
    handle->killed = TRUE;

    return terminate_tree(handle->job, handle->hProcess) ? 1 : 0;
}

FFI_PLUGIN_EXPORT int pty_job_error(PtyHandle *handle)
{
    return (int)handle->jobError;
}

FFI_PLUGIN_EXPORT void pty_release(PtyHandle *handle)
{
    // The exit thread has closed the pseudo console, and the reader the
    // output pipe.
    if (handle->job != NULL)
    {
        if (!handle->killed)
        {
            // The process exited on its own: what it left behind keeps
            // running, as on POSIX, instead of KILL_ON_JOB_CLOSE ending it.
            // After pty_kill the flag stays, so closing the job also ends
            // anything that slipped past TerminateJobObject.
            JOBOBJECT_EXTENDED_LIMIT_INFORMATION limits;
            ZeroMemory(&limits, sizeof(limits));
            SetInformationJobObject(handle->job, JobObjectExtendedLimitInformation, &limits, sizeof(limits));
        }

        CloseHandle(handle->job);
    }

    CloseHandle(handle->hProcess);
    CloseHandle(handle->inputWriteSide);
    CloseHandle(handle->hMutex);
    free(handle);
}
