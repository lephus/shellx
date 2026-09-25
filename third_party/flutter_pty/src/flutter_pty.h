#ifndef FLUTTER_PTY_H_
#define FLUTTER_PTY_H_

#if _WIN32
#define FFI_PLUGIN_EXPORT __declspec(dllexport)
#else
#define FFI_PLUGIN_EXPORT
#endif

#if defined(__linux__) || defined(__GLIBC__) || defined(__GNU__)
#define _GNU_SOURCE /* GNU glibc grantpt() prototypes */
#endif

#include "include/dart_api_dl.h"

typedef struct PtyOptions
{
    int rows;

    int cols;

    char *executable;

    char **arguments;

    char **environment;

    char *working_directory;

    Dart_Port stdout_port;

    Dart_Port exit_port;

    bool ackRead;

} PtyOptions;

typedef struct PtyHandle PtyHandle;

FFI_PLUGIN_EXPORT PtyHandle *pty_create(PtyOptions *options);

// ShellX: never blocks the caller (POSIX: queued for a writer thread, at
// most 1 MiB waiting; Windows: written to conhost's input pipe without a
// flush). Returns non-zero when the input was accepted, 0 when it was
// dropped (upstream returned void).
FFI_PLUGIN_EXPORT int pty_write(PtyHandle *handle, char *buffer, int length);

FFI_PLUGIN_EXPORT void pty_ack_read(PtyHandle *handle);

FFI_PLUGIN_EXPORT int pty_resize(PtyHandle *handle, int rows, int cols);

FFI_PLUGIN_EXPORT int pty_getpid(PtyHandle *handle);

FFI_PLUGIN_EXPORT char *pty_error(void);

// ShellX: frees everything the handle still holds (POSIX: the master fd;
// Windows: the job object, the process handle and the input pipe). Call
// once, only after the exit code and the end-of-output message (a null
// posted to stdout_port) have both arrived; the handle is invalid
// afterwards.
FFI_PLUGIN_EXPORT void pty_release(PtyHandle *handle);

#if !_WIN32
// ShellX, tests only (apps/desktop/integration_test/pty_test.dart): the next
// pty_create fails as if [step] had failed: 1 allocating the handle, 2
// starting the writer thread, 3 starting the exit thread, 4 starting the
// output reader. 0 turns it off; pty_create resets it.
FFI_PLUGIN_EXPORT void pty_debug_fail(int step);
#endif

#if _WIN32
// ShellX: terminates the job object the process was started in, i.e. the
// process and every process it started, or only the process when it has no
// job (see pty_job_error). Returns non-zero on success.
FFI_PLUGIN_EXPORT int pty_kill(PtyHandle *handle);

// ShellX: 0 when the process runs in the pty's job object; otherwise the
// Win32 error that prevented it (the process runs without one).
FFI_PLUGIN_EXPORT int pty_job_error(PtyHandle *handle);
#endif

#endif