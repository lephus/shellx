# flutter_pty 0.4.2 — ShellX copy

Vendored from pub.dev `flutter_pty` 0.4.2 (https://github.com/TerminalStudio/flutter_pty,
MIT, see `LICENSE`). `apps/desktop` depends on it by path. The first commit that added
this directory is the pristine package; every later change is listed here and can be
reviewed as a diff on top of that commit. Changed code is marked with `ShellX:` comments.

Upstream 0.4.2 does not survive a long-running agent: on Windows the shell's
command line is broken and every session leaks a conhost.exe; on macOS every
session leaks two file descriptors and the end of the output can be dropped.

## Packaging

| File | Change | Why |
|---|---|---|
| `android/`, `ios/`, `linux/`, `example/` | Removed. | ShellX ships the desktop agent for macOS and Windows only. |
| `pubspec.yaml` | `flutter.plugin.platforms` lists only `macos` and `windows`. | Same. |

## Dart (`lib/flutter_pty.dart`)

| Change | Why |
|---|---|
| `output` is a `StreamController` fed by the stdout port; it closes when the native reader posts a `null` (end of output), not when the exit code arrives. | Upstream closed the port on exit, dropping output still in flight (the last lines before `exit`). |
| New `pty_release` call once both the exit code and the end of output have arrived; `write`, `resize`, `ackRead`, `kill` are no-ops afterwards. | Frees the native handle: POSIX master fd, Windows job object and pipes. Neither native thread touches the handle after posting its final message. |
| `pid` is read once at start. | Stays valid after the handle is released. |
| `kill()` on Windows calls the new `pty_kill` (terminate the job object: the shell and everything it started); after exit it returns false without signalling (POSIX: stale pid). | Upstream `Process.killPid` on Windows killed the shell only; on POSIX after exit it could hit a reused pid. |
| Native strings (argv, environment, executable, working directory) are freed after `pty_create`; the ports are closed when `pty_create` fails. | Upstream leaked them on every spawn. |
| `pty_release` / `pty_kill` are looked up with `lookupFunction` in `flutter_pty.dart`; `lib/src/flutter_pty_bindings_generated.dart` is untouched. | Keeps the generated file as generated. |

## Native, shared (`src/flutter_pty.h`)

| Change | Why |
|---|---|
| Declares `pty_release` (both platforms) and `pty_kill` (Windows). | See above. |

## Native, POSIX (`src/flutter_pty_unix.c`, `src/forkpty.c`)

| Change | Why |
|---|---|
| The parent closes the slave fd after `forkpty`. | Upstream kept it open for the agent's lifetime (fd leak) and, because the parent held it, reading the master never reached end of file. |
| Master and slave are opened with `O_CLOEXEC` (atomically; upstream set `FD_CLOEXEC` on the master with a later `fcntl`, and not at all on the slave). | No process started by another thread or a later session inherits them. |
| The reader treats EOF (0) and EIO as end of output, retries on `EINTR`, posts a `null` to the stdout port, then exits; `pty_release` closes the master. Reader and exit threads are detached and free their options. | End-of-output signal for Dart; no fd or thread leak. |
| The exit thread retries `waitpid` on `EINTR` and always posts an exit code: `-1` when the status is lost. | dart:io's exit-code thread calls `wait()` for any child while a `Process` it started is running (ShellX keeps `caffeinate` running), so it can reap the shell first; upstream then read an uninitialised status or posted nothing. |
| The child calls `_exit(127)` when `execvp` fails and `_exit(1)` when `TIOCSCTTY` fails. | Upstream fell through into the parent's code (starting threads in a forked copy of the VM) or ran `exit()` handlers. |
| `forkpty` closes its fds on every failure path. | Leak on failure. |
| `pty_error()` returns the error message (with `errno`); upstream always returned NULL. | `spawn_failed` gets a reason. |

## Native, Windows (`src/flutter_pty_win.c`)

Not compiled or run on macOS; verified only by Windows CI.

| Change | Why |
|---|---|
| `build_command` skips `arguments[0]` (the Dart side sets it to the executable) and writes the executable and arguments exactly as given; the caller quotes them. | Upstream put the executable on the command line twice (`pwsh.exe pwsh.exe …`), so pwsh exited at once and powershell ran a nested shell. |
| Command line, environment block and working directory are converted with `MultiByteToWideChar(CP_UTF8, …)` (size query, then convert). An empty working directory means "inherit". | Upstream widened each UTF-8 byte into one UTF-16 unit, mangling non-ASCII paths and values (e.g. `C:\Users\Nguyễn`). |
| The parent closes its copies of the pseudo console's pipe ends right after `CreatePseudoConsole`; the reader owns and closes the output read side. | Upstream kept them, so the output pipe never reached end of file. |
| The exit thread calls `ClosePseudoConsole` when the process exits (under an SRW lock shared with `pty_resize`), then posts the exit code; every failure path after `CreatePseudoConsole` closes it too. | Upstream never closed it: one conhost.exe leaked per session, and on failure as well. |
| Job object with `JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE`: the process is created with `CREATE_SUSPENDED`, assigned to the job, then resumed. `pty_kill` = `TerminateJobObject`; `pty_release` closes the job (ending anything left in it). Failing to assign the job fails the spawn. | Kills the whole tree, including orphans and without parent-pid guessing, and nothing outlives the agent if it crashes. |
| `Sleep(1000)` removed. The output reader and exit thread start before `ResumeThread`, so the reader runs before the shell executes anything. | Upstream blocked the calling (UI) isolate for one second per spawn. |
| `hThread`, the thread handles, the attribute list and all buffers are closed/freed; every failure path releases what was created before it; `pty_error()` includes the Win32 error / HRESULT. | Handle leaks; diagnosable `spawn_failed`. |
| Explicit `STARTUPINFOEXW`, `CreateSemaphoreW`, `<stdlib.h>`/`<string.h>`. | Correct types without relying on `UNICODE` or transitive includes. |
