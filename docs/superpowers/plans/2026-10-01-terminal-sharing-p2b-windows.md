# Terminal Sharing P2b — `shellx-term` on Windows Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `shellx-term` runs on Windows. It wraps PowerShell 7 or Windows PowerShell 5.1 in a ConPTY, relays the console window and joins the same agent link as on macOS. Whenever it cannot wrap, it exits with code 222 so the PowerShell profile carries on. This plan also closes the three items left open after the P2a final review.

**Architecture:**
- **`session.rs` (new, every platform):** everything both platforms share moves here from the Unix-only `wrap.rs` — link wiring, size control, the PTY→window copy, the exit code and the "could not wrap" error.
- **`wrap.rs` (Unix):** keeps only file descriptors and signals.
- **`winwrap.rs` (new, Windows):** the Windows wrapper, built on a small console layer, `wincon.rs`, that calls winapi.
- **`wincodec.rs` (new, every platform):** the text conversions Windows needs, kept pure so they compile and are unit-tested everywhere. Console UTF-16 keystrokes become UTF-8 bytes, and UTF-8 output becomes UTF-16 for `WriteConsoleW`.
- **`term/shell/block.ps1` (new):** the PowerShell block, mirroring the zsh and bash blocks.
- **`windows-check` workflow (new):** runs the suite on `windows-latest` and `macos-latest`.

**Tech Stack:**
- Rust 1.95, edition 2021, with unchanged dependencies.
- `winapi 0.3.9` as a Windows-only dependency. portable-pty already pulls it in on Windows.
- PowerShell 7 and 5.1.
- GitHub Actions `windows-latest`.

**Spec:** `docs/superpowers/specs/2026-10-01-desktop-terminal-sharing-design.md` (§5.3, §5.4, §6.1, §11.1, §12, §14). P2a results and open items: `docs/superpowers/ledgers/terminal-sharing.md`, sections "P2a" and "Còn mở sau review cuối P2a".

## Global Constraints

- **Branch and merge:**
  - Work on branch `feat/terminal-sharing-p2b`, in worktree `.claude/worktrees/terminal-sharing-p2b`, cut from `feat/shellx-v1`.
  - Merge locally after the final review.
  - **Never push.** Task 8 asks the user before the single push it needs.
- **No Windows toolchain on the dev Mac (user decision).**
  - No `rustup target add`, no PowerShell install, no other installer.
  - `#[cfg(windows)]` code cannot be compiled or run locally. Keep it small and isolated.
  - Everything platform-neutral must compile and be tested on macOS.
  - The first compile of the Windows code happens in the `windows-check` workflow (Task 8).
  - Check every winapi name against the crate source already in the local cargo registry: `~/.cargo/registry/src/*/winapi-0.3.9/src/um/*.rs`. Reading files is allowed; installing is not.
- **Dependencies:**
  - Keep the P2a crates and versions.
  - Move `signal-hook 0.4.4` and `libc 0.2.189` under `[target.'cfg(unix)'.dependencies]`.
  - Add, under `[target.'cfg(windows)'.dependencies]` only:
    `winapi = { version = "0.3.9", features = ["consoleapi", "minwindef", "processenv", "winbase", "wincon", "wincontypes", "winnt"] }`.
  - No other new crates.
- **Exit code 222 means "could not wrap — carry on".** On Windows `shellx-term` exits 222 in all of these cases:
  - invalid arguments, or `probe` (which only the Unix blocks use);
  - no console;
  - ConPTY or spawn failure;
  - any panic outside a link thread.
- **Windows inner-shell marker:**
  - The value is `SHELLX_TERM=conpty:<shellx-term pid>`.
  - The PowerShell block skips whenever `SHELLX_TERM` or `SHELLX` is non-empty.
  - Unlike Unix, there is no per-tty comparison. A terminal app launched from a wrapped Windows window therefore does not wrap its own terminals. This is a documented limit.
- **Windows endpoint file:** `%LOCALAPPDATA%\ShellX\term\endpoint`. Same format as on macOS.
- **Installed binary the block calls:** `%LOCALAPPDATA%\ShellX\bin\shellx-term.exe`.
- **Block files:** markers are exactly `# >>> ShellX >>>` / `# <<< ShellX <<<`, and the files contain ASCII only.
- **macOS gate, from `term/`:**
  ```
  cargo fmt --check && cargo clippy --all-targets --features test-hooks -- -D warnings && cargo test --features test-hooks
  ```
  - Run the full suite 3× before each commit.
  - `cargo fmt` also formats `#[cfg(windows)]` files, so they must be rustfmt-clean.
- **Real per-user state is off limits:** never touch the real HOME, `~/.zshrc` and the other startup files, or `~/Library/Application Support/ShellX`.
- **Commit message prefixes:** `feat(term): …`, `fix(term): …`, `refactor(term): …`, `test(term): …`, `ci: …`, `docs: …`.

## Review Focus

1. **A `shellx-term.exe` that cannot start must leave the PowerShell window working.** Causes include a corrupt file, the wrong architecture, or a policy block. The profile must continue and the window must stay open. Pinned by Task 6, `a_corrupt_binary_leaves_the_window_working` (CI).
2. **Keystrokes outside the BMP and keystrokes from an IME must reach the shell byte-exact.** Examples: emoji, which arrive as surrogate pairs split across console events, and Vietnamese composed characters. Pinned by Task 3 (unit tests on macOS) and Task 6, `typed_vietnamese_reaches_the_shell` (CI).
3. **UTF-8 output split mid-character across PTY reads must render correctly**, with no replacement characters at chunk boundaries. Pinned by Task 3, `utf8_split_at_every_point_decodes_the_same`.
4. **Killing the `shellx-term.exe` process while a command runs must end the inner shell, not orphan it.** This happens when a tab is closed or the process is killed. Pinned by Task 5 (the close handler, and the kill when the console is lost) and Task 6, `killing_shellx_term_ends_the_inner_shell` (CI).
5. **After a failed wrap, the bash fallback shell and its children must get SIGTERM at its original disposition.** This is the open P2a item. Pinned by Task 1, `a_failed_wrap_leaves_sigterm_as_it_was_for_the_fallback_shell`.

---

### Task 1: P2a leftovers — SIGTERM restored before fallback, poison-proof locks, reader shutdown on panic

**Files:**
- Modify: `term/src/fallback.rs`, `term/src/main.rs`, `term/src/wrap.rs`, `term/src/link.rs`
- Modify: `term/tests/block.rs`, `term/tests/link.rs` (comment layout only)
- Create: `term/tests/link_reader_panic.rs`
- Modify: `docs/superpowers/ledgers/terminal-sharing.md`

**Interfaces:**
- Produces:
  - `fallback::remember_sigterm()`. Unix `main` calls it first. It saves the SIGTERM disposition the process started with.
  - `fallback::exec_shell` restores that saved disposition before every `exec`. The panic hook goes through `exec_shell`, so it is covered too.
  - A new fault point `reader-panic` (feature `test-hooks`): the link reader panics on an agent `in` message.

- [ ] **Step 1: Failing tests**

In `term/tests/block.rs`, add the test below right after `a_wrapped_bash_window_ignores_sigterm_like_a_plain_interactive_shell`. It uses the existing helpers `real_home`, `run_shell`, `T` and `Harness::wait_number_after`.

```rust
/// When wrapping fails in a block-started bash window, the plain bash that
/// takes over, and what it runs, get SIGTERM as the window had it: bash
/// passes an ignored SIGTERM on to every command.
#[cfg(feature = "test-hooks")]
#[test]
fn a_failed_wrap_leaves_sigterm_as_it_was_for_the_fallback_shell() {
    let home = real_home("fallback-sigterm");
    let mut h = run_shell("/bin/bash", &["-il"], &home, &[("SHELLX_TERM_FAULT", "spawn")]);
    h.expect("could not share this terminal", T);
    h.send("/bin/sh -c 'kill -TERM $$; echo SUR''VIVED'; echo co''de=$?\r");
    let code = h.wait_number_after("code=", T);
    assert_eq!(code, 143, "the command kept an ignored SIGTERM: {:?}", h.text());
    assert!(!h.text().contains("SURVIVED"), "{:?}", h.text());
    h.send("exit\r");
    h.wait_exit(T);
}
```

Create `term/tests/link_reader_panic.rs`. It is a separate test binary because it sets `SHELLX_TERM_FAULT` for the whole process, and that would race the other link tests.

```rust
#![cfg(feature = "test-hooks")]
//! Its own test binary: it sets SHELLX_TERM_FAULT for the whole process.

mod common;

use common::fake_agent::{Behavior, FakeAgent};
use shellx_term::link::{Link, LinkEvents, Timing};
use shellx_term::proto::endpoint::endpoint_path_in;
use shellx_term::proto::messages::{AgentMsg, TermInfo};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use std::time::Duration;

const T: Duration = Duration::from_secs(5);

struct Events;

impl LinkEvents for Events {
    fn info(&self) -> TermInfo {
        TermInfo {
            term_id: [3; 16],
            app: String::new(),
            shell: "zsh".into(),
            pid: 1,
            cols: 80,
            rows: 24,
            started_at: 1,
        }
    }
    fn input(&self, _data: &[u8]) {}
    fn phone_resize(&self, _cols: u16, _rows: u16) {}
    fn phone_left(&self) {}
}

#[test]
fn a_reader_panic_ends_the_session_even_while_output_flows() {
    std::env::set_var("SHELLX_TERM_FAULT", "reader-panic");
    let home = common::temp_dir("link-reader-panic");
    let link = Arc::new(Link::start(Some(endpoint_path_in(&home)), Timing::fast(), Arc::new(Events)));
    let agent = FakeAgent::start(&home, Behavior::Normal);
    let mut first = agent.next_session(T);
    first.snapshot(T);
    let stop = Arc::new(AtomicBool::new(false));
    let pump = {
        let (link, stop) = (link.clone(), stop.clone());
        std::thread::spawn(move || {
            while !stop.load(Ordering::SeqCst) {
                link.output(b"tick\r\n");
                std::thread::sleep(Duration::from_millis(5));
            }
        })
    };
    first.send(&AgentMsg::In { data: b"x".to_vec() }); // the reader panics here
    // Without the guard the session lives on (output keeps its writer busy)
    // and phone input is lost; with it the session ends and the link
    // reconnects.
    let _second = agent.next_session(T);
    stop.store(true, Ordering::SeqCst);
    pump.join().unwrap();
}
```

Run:

```
cd term && cargo test --features test-hooks --test block a_failed_wrap && cargo test --features test-hooks --test link_reader_panic
```

Expected: both FAIL.
- The block test fails on `code=0`, with `SURVIVED` in the output.
- The link test fails with `no session` or a timeout in `next_session`.

- [ ] **Step 2: Put SIGTERM back before the fallback**

In `term/src/fallback.rs` add:

```rust
use std::sync::OnceLock;

/// SIGTERM's disposition when this process started. A block-started window
/// ignores SIGTERM for itself (spec §5.4 item 6); the fallback shell must not
/// inherit that, or bash passes the ignore on to every command it runs.
static START_SIGTERM: OnceLock<libc::sighandler_t> = OnceLock::new();

/// Call first thing in `main`.
pub fn remember_sigterm() {
    let mut old: libc::sigaction = unsafe { std::mem::zeroed() };
    let handler = if unsafe { libc::sigaction(libc::SIGTERM, std::ptr::null(), &mut old) } == 0 {
        old.sa_sigaction
    } else {
        libc::SIG_DFL
    };
    let _ = START_SIGTERM.set(handler);
}

/// Ignored stays ignored; anything else becomes the default.
fn restore_sigterm() {
    let ignored = START_SIGTERM.get() == Some(&libc::SIG_IGN);
    let disposition = if ignored { libc::SIG_IGN } else { libc::SIG_DFL };
    unsafe { libc::signal(libc::SIGTERM, disposition) };
}
```

Then:
- Make `restore_sigterm();` the first statement of `exec_shell`, and mention it in the `exec_shell` doc comment.
- In `term/src/main.rs` (Unix `main`), make `fallback::remember_sigterm();` the very first statement.

- [ ] **Step 3: Poison-proof locks in `wrap.rs`**

Add to `term/src/wrap.rs`:

```rust
/// A panic on another thread must not stop keystrokes or resizes: take the
/// lock even if it was poisoned.
fn lock<T>(m: &Mutex<T>) -> std::sync::MutexGuard<'_, T> {
    m.lock().unwrap_or_else(|e| e.into_inner())
}
```

Replace every `.lock()` on the writer, master and size mutexes in `wrap.rs` with `lock(&…)`. The call sites are:
- `MasterResizer::resize`;
- `WrapEvents::{input, phone_resize, phone_left}`;
- `copy_window_to_pty` (both locks);
- `on_window_resize`.

The `Ok/Err` and `if let Ok` branches go away. In `copy_window_to_pty`:
- the write becomes `let ok = lock(&writer).write_all(&buf[..n]).is_ok();`
- the size check becomes:

```rust
let notices = {
    let mut s = lock(&size);
    if s.driver() == Driver::Phone { s.local_input() } else { Vec::new() }
};
```

- [ ] **Step 4: Reader shutdown on any exit, including a panic**

In `term/src/link.rs`:

```rust
/// Shuts the socket down however the reader ends, including a panic (the
/// panic hook lets link threads die): the session writer then fails at once
/// and the link reconnects, instead of silently dropping phone input.
struct ShutdownOnDrop(TcpStream);

impl Drop for ShutdownOnDrop {
    fn drop(&mut self) {
        let _ = self.0.shutdown(Shutdown::Both);
    }
}
```

Rewrite `read_agent`:
- It starts with `let mut guard = ShutdownOnDrop(stream);` and reads with `read_frame(&mut guard.0)`.
- Delete its trailing explicit `shutdown`, since the guard now does it. Move that comment onto the guard.
- Add the fault point as the first thing in the `In` arm:

```rust
Ok(Some(AgentMsg::In { data })) => {
    if faults::hit("reader-panic") {
        panic!("injected reader fault");
    }
    events.input(&data)
}
```

If the `faults.rs` module doc lists the fault points, add `reader-panic` to that list.

- [ ] **Step 5: Tidy**

- **`term/tests/link.rs`**, in `finish_waits_at_most_the_flush_time_for_a_frame_a_hung_agent_never_reads`: rustfmt pushed the three-line `// About 950 KiB …` comment far right, after `hung.snapshot(T); // then never reads again`.
  - Move the trailing comment onto its own line above `hung.snapshot(T);`.
  - Put the 950 KiB comment on its own lines at normal indentation.
- **`docs/superpowers/ledgers/terminal-sharing.md`:**
  - In the P2a **Test** bullet (line 164), delete the stale clause `test thoát/"finish treo" hiện làm tràn thay vì thử đúng `finish`, `.
  - Under "Còn mở sau review cuối P2a (chuyển sang P2b)", end each of the four bullets with ` — **đã sửa ở P2b Task 1.**`.

- [ ] **Step 6: Gate, 3× suite, commit**

```bash
git add term docs/superpowers/ledgers/terminal-sharing.md
git commit -m "fix(term): restore SIGTERM before the fallback shell; poison-proof locks; link reader shuts the session down even on panic"
```

---

### Task 2: Shared session core; platform-neutral modules and tests; Windows-ready harness

There is no Unix behaviour change: every existing test passes unchanged. This task prepares every platform-neutral piece the Windows code needs, and makes the test suite compile on Windows.

**Files:**
- Create: `term/src/session.rs`
- Modify: `term/Cargo.toml`, `term/src/lib.rs`, `term/src/wrap.rs`, `term/src/cli.rs` (tests only), `term/src/proto/endpoint.rs`, `term/src/appname.rs`
- Modify: `term/tests/common/mod.rs`, and the header line of every Unix-only test file

**Interfaces:**
- Consumes:
  - `link::{Link, LinkEvents, Timing}`
  - `size::{Driver, Resizer, SizeControl}`
  - `appname::terminal_app`
  - `proto::endpoint::default_endpoint_path`
- Produces `session.rs`, compiled on every platform. Moved from `wrap.rs`:
  - `pub const DRAIN_AFTER_EXIT: Duration` (500 ms).
  - `pub type SharedWriter`, `pub type SharedMaster`, `pub type Size`, `pub struct MasterResizer`.
  - `pub fn lock<T>(&Mutex<T>) -> MutexGuard<'_, T>` (added in Task 1).
  - `pub enum WrapError { NotATerminal, Pty(String), Spawn(String) }` and `notice()`. The notice text ends with a per-platform `CARRY_ON` suffix.
  - `pub fn now_ms() -> u64`, `pub fn random_term_id() -> [u8; 16]`.
  - `pub fn wait_for_exit(child: &mut (dyn Child + Send + Sync)) -> i32`. On Unix a signal gives 128 + signal; elsewhere it returns the process exit code.
- Also produced by `session.rs`, new:
  - `pub fn shell_name(shell: &OsStr) -> String`: the file name without a trailing `.exe` (case-insensitive).
  - `pub struct Wiring { pub writer: SharedWriter, pub size: Size, pub link: Arc<Link> }` (Clone).
  - `Wiring::new(shell: &OsStr, writer: Box<dyn Write + Send>, master: Box<dyn MasterPty + Send>, window: (u16, u16), window_size: fn() -> (u16, u16), shell_pid: Option<u32>, started_at: u64) -> (Wiring, SharedMaster)`.
  - `Wiring::window_input(&self, bytes: &[u8]) -> bool`.
  - `Wiring::window_resized(&self, size: (u16, u16))`.
  - `pub fn copy_pty_to_window(from_pty: Box<dyn Read + Send>, window: Box<dyn Write + Send>, link: Arc<Link>) -> mpsc::Receiver<()>`.
- `proto::endpoint`:
  - `pub const ENDPOINT_BASE_VAR: &str` is `"HOME"` on Unix and `"LOCALAPPDATA"` on Windows.
  - `endpoint_path_in(base)` gives `base/Library/Application Support/ShellX/term/endpoint` on Unix and `base\ShellX\term\endpoint` on Windows.
  - `default_endpoint_path()` reads `ENDPOINT_BASE_VAR`.
- `appname`: a non-empty `WT_SESSION` gives `"Windows Terminal"`. It is checked after the bundle id and before `TERM_PROGRAM`.
- Test harness:
  - It runs on Windows ConPTY too.
  - A test window's per-user base (`ENDPOINT_BASE_VAR`) is a fresh temp dir unless the caller sets it.
  - `WT_SESSION` is cleared like `TERM_PROGRAM`.

- [ ] **Step 1: Cargo and lib layout**

In `term/Cargo.toml`, replace `[dependencies]` and everything below it up to `[features]` with:

```toml
[dependencies]
portable-pty = "0.9.0"
hmac = "0.13.0"
sha2 = "0.11.0"
getrandom = "0.4.3"

[target.'cfg(unix)'.dependencies]
signal-hook = "0.4.4"
libc = "0.2.189"

[target.'cfg(windows)'.dependencies]
winapi = { version = "0.3.9", features = ["consoleapi", "minwindef", "processenv", "winbase", "wincon", "wincontypes", "winnt"] }
```

In `term/src/lib.rs`:
- These modules compile on every platform: `appname`, `cli`, `faults`, `link`, `outbox`, `proto`, `ring`, `session` (new) and `size`. They use std only, so drop any `cfg(unix)` on them.
- `fallback`, `tty` and `wrap` stay `#[cfg(unix)]`.

`Cargo.lock` gains the winapi entries. winapi is already in the lock graph through portable-pty, so the diff is small. Commit `Cargo.lock` if it is tracked.

- [ ] **Step 2: Endpoint path per platform — tests first**

In the `term/src/proto/endpoint.rs` tests, replace the Unix path test at line ~180 with:

```rust
    #[cfg(unix)]
    #[test]
    fn the_unix_base_is_home() {
        assert_eq!(ENDPOINT_BASE_VAR, "HOME");
        assert_eq!(
            endpoint_path_in(Path::new("/Users/u")),
            PathBuf::from("/Users/u/Library/Application Support/ShellX/term/endpoint")
        );
    }

    #[cfg(windows)]
    #[test]
    fn the_windows_base_is_localappdata() {
        assert_eq!(ENDPOINT_BASE_VAR, "LOCALAPPDATA");
        assert_eq!(
            endpoint_path_in(Path::new(r"C:\Users\u\AppData\Local")),
            PathBuf::from(r"C:\Users\u\AppData\Local\ShellX\term\endpoint")
        );
    }
```

Implementation, replacing the current `endpoint_path_in` and `default_endpoint_path`:

```rust
/// The environment variable naming the per-user base directory (spec §6.1).
#[cfg(unix)]
pub const ENDPOINT_BASE_VAR: &str = "HOME";
#[cfg(windows)]
pub const ENDPOINT_BASE_VAR: &str = "LOCALAPPDATA";

#[cfg(unix)]
pub fn endpoint_path_in(base: &Path) -> PathBuf {
    base.join("Library/Application Support/ShellX/term/endpoint")
}

#[cfg(windows)]
pub fn endpoint_path_in(base: &Path) -> PathBuf {
    base.join("ShellX").join("term").join("endpoint")
}

/// The agent's endpoint file for this user: `$HOME/Library/Application
/// Support/ShellX/term/endpoint` on macOS, `%LOCALAPPDATA%\ShellX\term\endpoint`
/// on Windows. None when the base variable is unset or empty.
pub fn default_endpoint_path() -> Option<PathBuf> {
    std::env::var_os(ENDPOINT_BASE_VAR)
        .filter(|b| !b.is_empty())
        .map(|b| endpoint_path_in(Path::new(&b)))
}
```

- [ ] **Step 3: App name for Windows Terminal — test first**

In the `term/src/appname.rs` tests:

```rust
    #[test]
    fn windows_terminal_is_recognised_by_its_session_variable() {
        assert_eq!(app(&[("WT_SESSION", "8e5e2f1c-0000-0000-0000-000000000000")]), "Windows Terminal");
        assert_eq!(app(&[("WT_SESSION", "x"), ("TERM_PROGRAM", "vscode")]), "Windows Terminal");
        assert_eq!(app(&[("WT_SESSION", "")]), "");
    }
```

In `lookup`, right after the `__CFBundleIdentifier` block:

```rust
    if get("WT_SESSION").is_some_and(|v| !v.is_empty()) {
        return "Windows Terminal".to_string();
    }
```

- [ ] **Step 4: `session.rs` — `shell_name` test first, then the move**

Test, at the bottom of `session.rs`:

```rust
#[cfg(test)]
mod tests {
    use super::shell_name;
    use std::ffi::OsStr;

    #[test]
    fn the_shell_name_is_the_file_name_without_exe() {
        assert_eq!(shell_name(OsStr::new("/bin/zsh")), "zsh");
        assert_eq!(shell_name(OsStr::new("/opt/bash-5.2")), "bash-5.2");
        assert_eq!(shell_name(OsStr::new("/x/pwsh.exe")), "pwsh");
        assert_eq!(shell_name(OsStr::new("/x/POWERSHELL.EXE")), "POWERSHELL");
        assert_eq!(shell_name(OsStr::new("/x/.exe")), "");
    }
}
```

Move these items from `wrap.rs` into `session.rs` unchanged, making them `pub` per the interface list:
- `SharedWriter`, `SharedMaster`, `MasterResizer`, `Size`
- `DRAIN_AFTER_EXIT`, `WrapError`, `lock`, `now_ms`, `random_term_id`, `wait_for_exit`
- `WrapEvents`, renamed to a private `Events`. It gains a `window_size: fn() -> (u16, u16)` field, which `info()` calls instead of the Unix `current_size()`.

Then add:

```rust
/// Last words of the notice: what happens instead of sharing.
#[cfg(unix)]
const CARRY_ON: &str = "starting a plain shell";
#[cfg(not(unix))]
const CARRY_ON: &str = "carrying on without sharing";

// WrapError::notice becomes:
//     WrapError::Pty(reason) | WrapError::Spawn(reason) => Some(format!(
//         "shellx-term: could not share this terminal ({reason}); {CARRY_ON}"
//     )),

/// The shell's name for the phone: its file name without `.exe`.
pub fn shell_name(shell: &OsStr) -> String {
    let name = Path::new(shell)
        .file_name()
        .map(|n| n.to_string_lossy().into_owned())
        .unwrap_or_default();
    match name.len().checked_sub(4) {
        Some(stem) if name.is_char_boundary(stem) && name[stem..].eq_ignore_ascii_case(".exe") => {
            name[..stem].to_string()
        }
        _ => name,
    }
}

/// Everything a window's threads need to talk to the shell and the agent.
#[derive(Clone)]
pub struct Wiring {
    pub writer: SharedWriter,
    pub size: Size,
    pub link: Arc<Link>,
}

impl Wiring {
    /// Shares the PTY writer and master, starts size control and the agent
    /// link. The returned master keeps the PTY open while it lives.
    pub fn new(
        shell: &OsStr,
        writer: Box<dyn Write + Send>,
        master: Box<dyn MasterPty + Send>,
        window: (u16, u16),
        window_size: fn() -> (u16, u16),
        shell_pid: Option<u32>,
        started_at: u64,
    ) -> (Wiring, SharedMaster) {
        let writer: SharedWriter = Arc::new(Mutex::new(writer));
        // Never let the last writer go: dropping portable-pty's writer types
        // "\n^D" into the shell. Leaked on purpose.
        std::mem::forget(writer.clone());
        let master: SharedMaster = Arc::new(Mutex::new(master));
        let size: Size = Arc::new(Mutex::new(SizeControl::new(MasterResizer(master.clone()), window)));
        let base = TermInfo {
            term_id: random_term_id(),
            app: terminal_app(|k| std::env::var(k).ok()),
            shell: shell_name(shell),
            pid: shell_pid.unwrap_or(0),
            cols: window.0,
            rows: window.1,
            started_at,
        };
        let events = Arc::new(Events {
            writer: writer.clone(),
            size: size.clone(),
            base,
            window_size,
        });
        let link = Arc::new(Link::start(default_endpoint_path(), Timing::from_env(), events));
        (Wiring { writer, size, link }, master)
    }

    /// Bytes typed in the window. A keystroke takes the size back from the
    /// phone first (spec §5.5). False once the PTY can no longer be written.
    pub fn window_input(&self, bytes: &[u8]) -> bool {
        let notices = {
            let mut s = lock(&self.size);
            if s.driver() == Driver::Phone {
                s.local_input()
            } else {
                Vec::new()
            }
        };
        for notice in notices {
            self.link.send(notice.to_msg());
        }
        lock(&self.writer).write_all(bytes).is_ok()
    }

    /// The window now measures `size`.
    pub fn window_resized(&self, size: (u16, u16)) {
        let notices = lock(&self.size).window_resized(size);
        for notice in notices {
            self.link.send(notice.to_msg());
        }
    }
}

/// The shell's output → the window and the link. The receiver fires once
/// the PTY closes.
pub fn copy_pty_to_window(
    mut from_pty: Box<dyn Read + Send>,
    mut window: Box<dyn Write + Send>,
    link: Arc<Link>,
) -> mpsc::Receiver<()> {
    let (done_tx, done_rx) = mpsc::channel();
    std::thread::spawn(move || {
        let mut buf = [0u8; 16384];
        loop {
            match from_pty.read(&mut buf) {
                Ok(0) => break,
                Ok(n) => {
                    if window.write_all(&buf[..n]).is_err() {
                        break;
                    }
                    link.output(&buf[..n]);
                }
                Err(e) if e.kind() == ErrorKind::Interrupted => continue,
                // Unix: EIO once everything closed the PTY.
                Err(_) => break,
            }
        }
        let _ = done_tx.send(());
    });
    done_rx
}
```

`wait_for_exit` keeps the `std::process::Child` downcast and the `ExitStatusExt` import inside a `#[cfg(unix)]` block. The portable-pty fallback, `child.wait().map(|s| s.exit_code() as i32).unwrap_or(1)`, serves Windows.

Rewrite `term/src/wrap.rs` (Unix) on top of the session core:
- **`run`** keeps every Unix step: the tty checks, `RawMode`, the SIGTERM and `from_block` handling, `Signals`, `tty_name`, `shell_command` and the fault points. After spawning it builds `Wiring::new(&args.shell, to_pty, pair.master, (cols, rows), current_size, child.process_id(), started_at)`.
- **`copy_window_to_pty(wiring: Wiring, shell_pid: Option<u32>)`** keeps its read loop and the hang-up on EOF. Each chunk is handled with `if !wiring.window_input(&buf[..n]) { break false; }`. The trailing `std::mem::forget(writer)` goes away, because `Wiring::new` already leaks one writer.
- **`forward_signals(signals, master, wiring)`** calls `wiring.window_resized(current_size())` on SIGWINCH and keeps the master as before.
- **Output** goes through `copy_pty_to_window(from_pty, Box::new(WindowOut(ManuallyDrop::new(unsafe { File::from_raw_fd(STDOUT) }))), wiring.link.clone())`, with:

  ```rust
  /// fd 1 as a writer that never closes it (it lives as long as the process).
  struct WindowOut(ManuallyDrop<File>);

  impl Write for WindowOut {
      fn write(&mut self, buf: &[u8]) -> std::io::Result<usize> {
          self.0.write(buf)
      }
      fn flush(&mut self) -> std::io::Result<()> {
          self.0.flush()
      }
  }
  ```
- **The end** becomes `wiring.link.finish(code as u32)`. A Unix code is never negative, so this is the same as the old `.max(0)`. On Windows it keeps an NTSTATUS crash code.
- Add `pub use crate::session::WrapError;` so existing paths keep working.

- [ ] **Step 5: `cli.rs` unit tests on every platform**

The tests use Unix absolute paths, which are relative on Windows. At the top of `mod tests` add:

```rust
    /// Absolute paths on the platform running the tests.
    #[cfg(unix)]
    const ZSH: &str = "/bin/zsh";
    #[cfg(unix)]
    const BASH: &str = "/bin/bash";
    #[cfg(windows)]
    const ZSH: &str = r"C:\shells\zsh.exe";
    #[cfg(windows)]
    const BASH: &str = r"C:\shells\bash.exe";
```

Then:
- Replace every `"/bin/zsh"` / `"/bin/bash"` literal in the tests with `ZSH` / `BASH`. `env_of` takes `&'static` pairs, and `const` strings work there.
- Leave relative-path cases such as `"zsh"` unchanged; they are relative on both platforms.
- Gate `the_parent_executable_is_this_test_runner_s_parent` with `#[cfg(unix)]`.

- [ ] **Step 6: Test harness on Windows**

Changes to `term/tests/common/mod.rs`. None of them change behaviour on Unix.

1. Gate `use std::os::unix::process::ExitStatusExt;` with `#[cfg(unix)]`. Add `use shellx_term::proto::endpoint::ENDPOINT_BASE_VAR;` and `use std::sync::Mutex;`.
2. Add `"WT_SESSION"` to the list of variables `Harness::spawn` clears.
3. Replace the HOME block with the same logic keyed on `ENDPOINT_BASE_VAR`. On Unix that is still `HOME`, so nothing changes there. Update the doc comment to: "The per-user base directory (`HOME` on Unix, `LOCALAPPDATA` on Windows) is a fresh temporary directory unless `env` sets it…".
4. Store the writer as `writer: Option<Arc<Mutex<Box<dyn Write + Send>>>>`. `send_bytes` locks it, and `close_window` drops the `Option`.
5. Put the existing reader thread (the `poll` loop with `master_fd` and `libc`) under `#[cfg(unix)]`. Add a `#[cfg(windows)]` reader that reads blocking and answers ConPTY's start-up cursor query. These threads stay detached: the harness has no `Drop` that joins them.

   ```rust
   #[cfg(windows)]
   let reader_thread = {
       let answer = writer.clone();
       std::thread::spawn(move || {
           let _ = stop; // Windows reads block; the thread ends with the pipe.
           let mut buf = [0u8; 16384];
           loop {
               match reader.read(&mut buf) {
                   Ok(0) | Err(_) => break,
                   Ok(n) => {
                       // A ConPTY made with PSEUDOCONSOLE_INHERIT_CURSOR (as
                       // portable-pty makes them) asks where the cursor is
                       // and waits for the answer.
                       if find(&buf[..n], b"\x1b[6n").is_some() {
                           let _ = answer.lock().unwrap().write_all(b"\x1b[1;1R");
                       }
                       if tx.send(buf[..n].to_vec()).is_err() {
                           break;
                       }
                   }
               }
           }
       })
   };
   ```
6. Move the platform-specific part of `wait_exit` into a helper. `wait_exit` then reads the same on both platforms:

   ```rust
   /// The exit code if the program has exited (128 + n for signal n on Unix).
   #[cfg(unix)]
   fn exited(&mut self) -> Option<i32> {
       // Not `use`-ing `Downcast`: the call must resolve on the trait object.
       let child = self
           .child
           .as_any_mut()
           .downcast_mut::<std::process::Child>()
           .expect("portable-pty spawns std::process::Child on Unix");
       child
           .try_wait()
           .expect("try_wait")
           .map(|status| status.code().unwrap_or_else(|| 128 + status.signal().unwrap_or(0)))
   }

   #[cfg(windows)]
   fn exited(&mut self) -> Option<i32> {
       self.child.try_wait().expect("try_wait").map(|status| status.exit_code() as i32)
   }
   ```

`term/tests/common/fake_agent.rs` is already platform-neutral and stays as it is. It writes `endpoint_path_in(home)`, which now follows the platform.

- [ ] **Step 7: Gate the Unix-only test files**

Change the first line of these test files:
- `term/tests/wrap.rs`, `signals.rs`, `fallback.rs`, `block.rs`, `dev_scripts.rs`: add `#![cfg(unix)]`.
- `term/tests/faults.rs`, `agent_link.rs`: change `#![cfg(feature = "test-hooks")]` to `#![cfg(all(unix, feature = "test-hooks"))]`.

These stay cross-platform: `link.rs`, `link_reader_panic.rs`, `handshake.rs`. `examples/startup_bench.rs` uses only portable-pty and std, so it compiles on Windows as it is; leave it.

- [ ] **Step 8: Gate, 3× suite, commit**

On macOS the full suite must pass with the same test count as before, plus the new unit tests (`shell_name` and the Windows Terminal name). Check the `cargo test` output: no new skipped or failed tests.

```bash
git add term
git commit -m "refactor(term): shared session core; endpoint path and app name per platform; tests and harness ready for Windows"
```

---

### Task 3: Pure Windows codecs (tested on macOS)

**Files:**
- Create: `term/src/wincodec.rs`
- Modify: `term/src/lib.rs` (add `pub mod wincodec;` on every platform)

**Interfaces:**
- Produces `wincodec::KeyInput` (`Default`), with `push(&mut self, key_down: bool, repeat: u16, unit: u16, out: &mut Vec<u8>)`. It appends the UTF-8 for one console KEY_EVENT:
  - key-ups and `unit == 0` (modifier-only keys) are ignored;
  - a surrogate pair is joined across calls;
  - a lone surrogate becomes U+FFFD;
  - a `repeat` of 0 counts as 1.
- Produces `wincodec::Utf8Stream` (`Default`), with `push(&mut self, bytes: &[u8], out: &mut Vec<u16>)`. It decodes UTF-8 to UTF-16:
  - an incomplete trailing sequence is kept for the next call;
  - invalid bytes become U+FFFD.

- [ ] **Step 1: Tests**

`term/src/wincodec.rs`:

```rust
//! Text conversions the Windows console needs, kept pure so they are
//! tested on every platform (spec §5.3). The console hands keystrokes over
//! as UTF-16 code units, one per event; output goes to `WriteConsoleW` as
//! UTF-16 while the PTY produces UTF-8 in arbitrary chunks.

/// Console key events → UTF-8 bytes for the shell.
#[derive(Default)]
pub struct KeyInput {
    high: Option<u16>,
}

/// UTF-8 chunks from the PTY → UTF-16 for the console.
#[derive(Default)]
pub struct Utf8Stream {
    pending: Vec<u8>,
}

#[cfg(test)]
mod tests {
    use super::*;

    fn keys(events: &[(bool, u16, u16)]) -> Vec<u8> {
        let mut k = KeyInput::default();
        let mut out = Vec::new();
        for &(down, repeat, unit) in events {
            k.push(down, repeat, unit, &mut out);
        }
        out
    }

    fn utf16(chunks: &[&[u8]]) -> String {
        let mut s = Utf8Stream::default();
        let mut out = Vec::new();
        for chunk in chunks {
            s.push(chunk, &mut out);
        }
        String::from_utf16(&out).unwrap()
    }

    #[test]
    fn ascii_and_control_keys() {
        let l = b'l' as u16;
        assert_eq!(keys(&[(true, 1, l), (false, 1, l), (true, 1, 0x03), (true, 1, 0x1b)]), b"l\x03\x1b");
    }

    #[test]
    fn repeat_counts_and_modifier_only_keys() {
        assert_eq!(keys(&[(true, 3, b'a' as u16), (true, 0, b'b' as u16), (true, 1, 0)]), b"aaab");
    }

    #[test]
    fn vietnamese_from_an_ime() {
        let units: Vec<(bool, u16, u16)> = "tiếng Việt".encode_utf16().map(|u| (true, 1, u)).collect();
        assert_eq!(keys(&units), "tiếng Việt".as_bytes());
    }

    #[test]
    fn surrogate_pairs_across_events_and_lone_surrogates() {
        let emoji: Vec<u16> = "😀".encode_utf16().collect();
        assert_eq!(keys(&[(true, 1, emoji[0]), (false, 1, emoji[0]), (true, 1, emoji[1])]), "😀".as_bytes());
        assert_eq!(keys(&[(true, 1, 0xD83D), (true, 1, b'x' as u16)]), "\u{FFFD}x".as_bytes());
        assert_eq!(keys(&[(true, 1, 0xDE00)]), "\u{FFFD}".as_bytes());
    }

    #[test]
    fn utf8_split_at_every_point_decodes_the_same() {
        let text = "a ế 😀 z";
        let bytes = text.as_bytes();
        for split in 0..=bytes.len() {
            assert_eq!(utf16(&[&bytes[..split], &bytes[split..]]), text, "split at {split}");
        }
        assert_eq!(utf16(&bytes.chunks(1).collect::<Vec<_>>()), text);
    }

    #[test]
    fn invalid_utf8_becomes_replacement_characters() {
        assert_eq!(utf16(&[b"a\xffb"]), "a\u{FFFD}b");
        // A kept incomplete sequence that the next chunk breaks.
        assert_eq!(utf16(&[b"\xe1\x80", b"z"]), "\u{FFFD}z");
    }
}
```

Run: `cd term && cargo test --features test-hooks wincodec::`. Expected: a compile error, because `push` does not exist yet.

- [ ] **Step 2: Implementation**

Add above the tests:

```rust
impl KeyInput {
    /// One console KEY_EVENT: appends its character's UTF-8 to `out`.
    pub fn push(&mut self, key_down: bool, repeat: u16, unit: u16, out: &mut Vec<u8>) {
        if !key_down || unit == 0 {
            return;
        }
        let ch = match (self.high.take(), unit) {
            (None, 0xD800..=0xDBFF) => {
                self.high = Some(unit);
                return;
            }
            (Some(high), 0xDC00..=0xDFFF) => {
                let code = 0x10000 + ((u32::from(high) - 0xD800) << 10) + (u32::from(unit) - 0xDC00);
                char::from_u32(code).unwrap_or('\u{FFFD}')
            }
            (Some(_), _) => {
                // A high surrogate without its pair, then this unit on its own.
                out.extend_from_slice("\u{FFFD}".as_bytes());
                return self.push(key_down, repeat, unit, out);
            }
            (None, u) => char::from_u32(u32::from(u)).unwrap_or('\u{FFFD}'),
        };
        let mut buf = [0u8; 4];
        let encoded = ch.encode_utf8(&mut buf).as_bytes();
        for _ in 0..repeat.max(1) {
            out.extend_from_slice(encoded);
        }
    }
}

impl Utf8Stream {
    /// Decodes `bytes` after any bytes kept from the last call.
    pub fn push(&mut self, bytes: &[u8], out: &mut Vec<u16>) {
        let mut input = std::mem::take(&mut self.pending);
        input.extend_from_slice(bytes);
        let mut rest: &[u8] = &input;
        loop {
            match std::str::from_utf8(rest) {
                Ok(text) => {
                    out.extend(text.encode_utf16());
                    return;
                }
                Err(e) => {
                    let (good, bad) = rest.split_at(e.valid_up_to());
                    out.extend(std::str::from_utf8(good).expect("valid prefix").encode_utf16());
                    match e.error_len() {
                        Some(n) => {
                            out.push(0xFFFD);
                            rest = &bad[n..];
                        }
                        None => {
                            // An incomplete sequence at the end: keep it.
                            self.pending = bad.to_vec();
                            return;
                        }
                    }
                }
            }
        }
    }
}
```

A lone low surrogate (in `0xDC00..=0xDFFF`, with no pending high surrogate) falls through to the last arm. `char::from_u32` rejects it, so it becomes U+FFFD.

Run: `cargo test --features test-hooks wincodec::`. Expected: 6 passed.

- [ ] **Step 3: Gate, 3× suite, commit**

```bash
git add term
git commit -m "feat(term): pure UTF-16 key and UTF-8 stream codecs for the Windows console"
```

---

### Task 4: Windows console layer (`wincon.rs`, Windows only)

This module cannot be compiled on the dev Mac. Its first compile is Task 8's workflow. Every winapi name below was checked against `winapi-0.3.9/src` in the local cargo registry:

| winapi module | Names used |
|---|---|
| `consoleapi` | `GetConsoleMode`, `SetConsoleMode`, `ReadConsoleInputW`, `WriteConsoleW`, `SetConsoleCtrlHandler` |
| `wincon` | `GetConsoleScreenBufferInfo`, `CONSOLE_SCREEN_BUFFER_INFO`, `CTRL_*_EVENT`, `ENABLE_*`, `DISABLE_NEWLINE_AUTO_RETURN` |
| `wincontypes` | `INPUT_RECORD`, `KEY_EVENT`, `WINDOW_BUFFER_SIZE_EVENT` |
| `processenv` | `GetStdHandle` |
| `winbase` | `STD_INPUT_HANDLE`, `STD_OUTPUT_HANDLE` |
| `minwindef` | `BOOL`, `DWORD`, `TRUE`, `FALSE` |
| `winnt` | `HANDLE` |

If you change any name, re-check it the same way.

**Files:**
- Create: `term/src/wincon.rs`
- Modify: `term/src/lib.rs` (`#[cfg(windows)] pub mod wincon;`)

**Interfaces:**
- Consumes: `wincodec::{KeyInput, Utf8Stream}`.
- Produces (Windows only):
  - `is_console() -> bool`
  - `window_size() -> Option<(u16, u16)>`
  - `RawConsole::enable() -> io::Result<RawConsole>`, which restores the console on `Drop`
  - `restore_saved()`, which never blocks
  - `ConsoleOut` (`Default`, `io::Write`)
  - `enum WindowEvent { Bytes(Vec<u8>), Resized, Gone }`
  - `read_window(on_event: impl FnMut(WindowEvent) -> bool)`
  - `install_close_handler()`

- [ ] **Step 1: Write the module**

`term/src/wincon.rs`:

```rust
//! The Windows console side of `shellx-term` (spec §5.3): raw VT mode,
//! window size, keystrokes and resize events, UTF-16 output, close events.
//! Windows only; the text conversions live in `wincodec` (tested everywhere).

use crate::wincodec::{KeyInput, Utf8Stream};
use std::io;
use std::sync::Mutex;
use winapi::shared::minwindef::{BOOL, DWORD, FALSE, TRUE};
use winapi::um::consoleapi::{
    GetConsoleMode, ReadConsoleInputW, SetConsoleCtrlHandler, SetConsoleMode, WriteConsoleW,
};
use winapi::um::processenv::GetStdHandle;
use winapi::um::winbase::{STD_INPUT_HANDLE, STD_OUTPUT_HANDLE};
use winapi::um::wincon::{
    GetConsoleScreenBufferInfo, CONSOLE_SCREEN_BUFFER_INFO, CTRL_BREAK_EVENT, CTRL_C_EVENT,
    DISABLE_NEWLINE_AUTO_RETURN, ENABLE_ECHO_INPUT, ENABLE_LINE_INPUT, ENABLE_MOUSE_INPUT,
    ENABLE_PROCESSED_INPUT, ENABLE_PROCESSED_OUTPUT, ENABLE_VIRTUAL_TERMINAL_INPUT,
    ENABLE_VIRTUAL_TERMINAL_PROCESSING, ENABLE_WINDOW_INPUT,
};
use winapi::um::wincontypes::{INPUT_RECORD, KEY_EVENT, WINDOW_BUFFER_SIZE_EVENT};
use winapi::um::winnt::HANDLE;

fn stdin() -> HANDLE {
    unsafe { GetStdHandle(STD_INPUT_HANDLE) }
}

fn stdout() -> HANDLE {
    unsafe { GetStdHandle(STD_OUTPUT_HANDLE) }
}

fn mode(h: HANDLE) -> Option<DWORD> {
    let mut m: DWORD = 0;
    (unsafe { GetConsoleMode(h, &mut m) } != 0).then_some(m)
}

/// Both stdin and stdout are a console (not a pipe or a file).
pub fn is_console() -> bool {
    mode(stdin()).is_some() && mode(stdout()).is_some()
}

/// `(cols, rows)` of the visible window.
pub fn window_size() -> Option<(u16, u16)> {
    let mut info: CONSOLE_SCREEN_BUFFER_INFO = unsafe { std::mem::zeroed() };
    if unsafe { GetConsoleScreenBufferInfo(stdout(), &mut info) } == 0 {
        return None;
    }
    let w = info.srWindow;
    let cols = i32::from(w.Right) - i32::from(w.Left) + 1;
    let rows = i32::from(w.Bottom) - i32::from(w.Top) + 1;
    let clamp = |n: i32| n.clamp(1, i32::from(u16::MAX)) as u16;
    (cols > 0 && rows > 0).then(|| (clamp(cols), clamp(rows)))
}

/// Modes to put back if we die without `Drop` (panic, close event).
static SAVED: Mutex<Option<(DWORD, DWORD)>> = Mutex::new(None);

/// Raw VT mode until dropped: every keystroke (Ctrl+C included) arrives as
/// bytes, resizes are reported, and output understands VT sequences.
pub struct RawConsole {
    input: DWORD,
    output: DWORD,
}

impl RawConsole {
    pub fn enable() -> io::Result<RawConsole> {
        let input = mode(stdin()).ok_or_else(io::Error::last_os_error)?;
        let output = mode(stdout()).ok_or_else(io::Error::last_os_error)?;
        let off = ENABLE_PROCESSED_INPUT | ENABLE_LINE_INPUT | ENABLE_ECHO_INPUT | ENABLE_MOUSE_INPUT;
        let raw_in = (input & !off) | ENABLE_VIRTUAL_TERMINAL_INPUT | ENABLE_WINDOW_INPUT;
        let raw_out = output
            | ENABLE_PROCESSED_OUTPUT
            | ENABLE_VIRTUAL_TERMINAL_PROCESSING
            | DISABLE_NEWLINE_AUTO_RETURN;
        if unsafe { SetConsoleMode(stdin(), raw_in) } == 0 {
            return Err(io::Error::last_os_error());
        }
        if unsafe { SetConsoleMode(stdout(), raw_out) } == 0 {
            let err = io::Error::last_os_error();
            unsafe { SetConsoleMode(stdin(), input) };
            return Err(err);
        }
        *SAVED.lock().unwrap_or_else(|e| e.into_inner()) = Some((input, output));
        Ok(RawConsole { input, output })
    }
}

impl Drop for RawConsole {
    fn drop(&mut self) {
        unsafe {
            SetConsoleMode(stdin(), self.input);
            SetConsoleMode(stdout(), self.output);
        }
        *SAVED.lock().unwrap_or_else(|e| e.into_inner()) = None;
    }
}

/// Puts back the modes `RawConsole::enable` saved; never blocks.
pub fn restore_saved() {
    if let Ok(mut saved) = SAVED.try_lock() {
        if let Some((input, output)) = saved.take() {
            unsafe {
                SetConsoleMode(stdin(), input);
                SetConsoleMode(stdout(), output);
            }
        }
    }
}

/// The window's output: UTF-8 from the PTY, written as UTF-16.
#[derive(Default)]
pub struct ConsoleOut {
    stream: Utf8Stream,
    units: Vec<u16>,
}

impl io::Write for ConsoleOut {
    fn write(&mut self, buf: &[u8]) -> io::Result<usize> {
        self.units.clear();
        self.stream.push(buf, &mut self.units);
        let mut rest: &[u16] = &self.units;
        while !rest.is_empty() {
            let mut written: DWORD = 0;
            let ok = unsafe {
                WriteConsoleW(
                    stdout(),
                    rest.as_ptr().cast(),
                    rest.len() as DWORD,
                    &mut written,
                    std::ptr::null_mut(),
                )
            };
            if ok == 0 || written == 0 {
                return Err(io::Error::last_os_error());
            }
            rest = &rest[written as usize..];
        }
        Ok(buf.len())
    }

    fn flush(&mut self) -> io::Result<()> {
        Ok(())
    }
}

pub enum WindowEvent {
    /// Keystrokes as UTF-8 (VT sequences for special keys).
    Bytes(Vec<u8>),
    /// The window changed size; read `window_size()`.
    Resized,
    /// The console is gone.
    Gone,
}

/// Reads the window until `on_event` returns false or the console goes
/// away (then reports `Gone` once).
pub fn read_window(mut on_event: impl FnMut(WindowEvent) -> bool) {
    let mut records: [INPUT_RECORD; 64] = unsafe { std::mem::zeroed() };
    let mut keys = KeyInput::default();
    loop {
        let mut n: DWORD = 0;
        let ok = unsafe { ReadConsoleInputW(stdin(), records.as_mut_ptr(), records.len() as DWORD, &mut n) };
        if ok == 0 {
            on_event(WindowEvent::Gone);
            return;
        }
        let mut bytes = Vec::new();
        let mut resized = false;
        for record in &records[..n as usize] {
            match record.EventType {
                KEY_EVENT => {
                    let key = unsafe { record.Event.KeyEvent() };
                    let unit = unsafe { *key.uChar.UnicodeChar() };
                    keys.push(key.bKeyDown != 0, key.wRepeatCount, unit, &mut bytes);
                }
                WINDOW_BUFFER_SIZE_EVENT => resized = true,
                _ => {}
            }
        }
        if !bytes.is_empty() && !on_event(WindowEvent::Bytes(bytes)) {
            return;
        }
        if resized && !on_event(WindowEvent::Resized) {
            return;
        }
    }
}

unsafe extern "system" fn on_ctrl(kind: DWORD) -> BOOL {
    match kind {
        // Processed input is off, so these should not arrive; never let
        // them end us.
        CTRL_C_EVENT | CTRL_BREAK_EVENT => TRUE,
        // Close, logoff, shutdown: put the console back, then let the default
        // handler end the process; the ConPTY closes and its shell ends.
        _ => {
            restore_saved();
            FALSE
        }
    }
}

pub fn install_close_handler() {
    unsafe { SetConsoleCtrlHandler(Some(on_ctrl), TRUE) };
}
```

- [ ] **Step 2: Local checks**

On macOS:
1. Run `cargo fmt`, then the full gate. The gate still passes because the module is `cfg(windows)`.
2. Re-read the module against the winapi sources listed above.
3. Record in the report which names you checked and how you checked them.

- [ ] **Step 3: Commit**

```bash
git add term
git commit -m "feat(term): Windows console layer — raw VT mode, size, keystrokes and resizes, UTF-16 output, close handler"
```

---

### Task 5: Windows wrapper and `main`

**Files:**
- Create: `term/src/winwrap.rs`
- Modify: `term/src/lib.rs` (`#[cfg(windows)] pub mod winwrap;`), `term/src/main.rs` (Windows `main`)

**Interfaces:**
- Consumes:
  - `session::{Wiring, WrapError, copy_pty_to_window, wait_for_exit, now_ms, DRAIN_AFTER_EXIT}`
  - `wincon::*`
  - `cli::{parse, Command, WrapArgs}`
  - `link::is_link_thread`
  - `faults::hit`
- Produces:
  - `winwrap::COULD_NOT_WRAP: i32 = 222`
  - `winwrap::run(&WrapArgs) -> Result<i32, WrapError>`
  - the Windows `main`

- [ ] **Step 1: `winwrap.rs`**

```rust
//! `shellx-term wrap` on Windows (spec §5.3): the shell runs in a ConPTY;
//! this process relays the console window and joins the agent link. It exits
//! with the shell's code, or 222 ("could not wrap, carry on") before the
//! shell starts.

use crate::cli::WrapArgs;
use crate::session::{copy_pty_to_window, now_ms, wait_for_exit, Wiring, WrapError, DRAIN_AFTER_EXIT};
use crate::{faults, wincon};
use portable_pty::{native_pty_system, CommandBuilder, PtySize};

/// "Could not wrap": the PowerShell block carries on in the outer shell.
pub const COULD_NOT_WRAP: i32 = 222;

fn current_size() -> (u16, u16) {
    wincon::window_size().unwrap_or((80, 24))
}

/// Runs the shell until it exits and returns its exit code. `Err` is only
/// returned before the shell started.
pub fn run(args: &WrapArgs) -> Result<i32, WrapError> {
    if !wincon::is_console() {
        return Err(WrapError::NotATerminal);
    }
    let started_at = now_ms();
    let (cols, rows) = current_size();
    if faults::hit("openpty") {
        return Err(WrapError::Pty("injected fault".into()));
    }
    let pair = native_pty_system()
        .openpty(PtySize { rows, cols, pixel_width: 0, pixel_height: 0 })
        .map_err(|e| WrapError::Pty(e.to_string()))?;
    let from_pty = pair.master.try_clone_reader().map_err(|e| WrapError::Pty(e.to_string()))?;
    let to_pty = pair.master.take_writer().map_err(|e| WrapError::Pty(e.to_string()))?;
    // Raw mode before the shell starts; an early return drops it, which puts
    // the console back before the outer PowerShell carries on.
    let raw = wincon::RawConsole::enable().map_err(|e| WrapError::Pty(e.to_string()))?;
    wincon::install_close_handler();

    if faults::hit("spawn") {
        return Err(WrapError::Spawn("injected fault".into()));
    }
    let mut cmd = CommandBuilder::new(&args.shell);
    cmd.args(&args.shell_args);
    // The PowerShell block skips any shell that carries a marker.
    cmd.env("SHELLX_TERM", format!("conpty:{}", std::process::id()));
    cmd.env_remove("SHELLX_TERM_WRAP");
    cmd.env_remove("SHELLX_TERM_WRAP_LOGIN");
    if let Ok(dir) = std::env::current_dir() {
        cmd.cwd(dir);
    }
    let mut child = pair.slave.spawn_command(cmd).map_err(|e| WrapError::Spawn(e.to_string()))?;
    drop(pair.slave);
    let mut killer = child.clone_killer();

    let (wiring, _master) = Wiring::new(
        &args.shell,
        to_pty,
        pair.master,
        (cols, rows),
        current_size,
        child.process_id(),
        started_at,
    );
    let output_done = copy_pty_to_window(from_pty, Box::new(wincon::ConsoleOut::default()), wiring.link.clone());
    let input = wiring.clone();
    std::thread::spawn(move || {
        wincon::read_window(|event| match event {
            wincon::WindowEvent::Bytes(bytes) => input.window_input(&bytes),
            wincon::WindowEvent::Resized => {
                input.window_resized(current_size());
                true
            }
            wincon::WindowEvent::Gone => {
                // The window went away: end the shell as closing it would.
                let _ = killer.kill();
                false
            }
        });
    });
    if faults::hit("panic") {
        panic!("injected fault");
    }

    let code = wait_for_exit(&mut *child);
    // The ConPTY's output pipe stays open until the pseudoconsole closes, so
    // this waits the full drain time; the tail of the output arrives within it.
    let _ = output_done.recv_timeout(DRAIN_AFTER_EXIT);
    wiring.link.finish(code as u32);
    drop(raw);
    Ok(code)
}
```

- [ ] **Step 2: Windows `main`**

In `term/src/main.rs`, replace `#[cfg(not(unix))] fn main` with:

```rust
#[cfg(windows)]
fn main() {
    use shellx_term::{cli, link, wincon, winwrap};
    use std::io::Write;

    let command = cli::parse(std::env::args_os().skip(1));
    if matches!(command, cli::Command::Wrap(_)) {
        // A bug must never cost the user their window: put the console back
        // and exit 222 so the PowerShell profile carries on in the outer shell.
        std::panic::set_hook(Box::new(|info| {
            if link::is_link_thread() {
                return; // only the link dies; the terminal keeps running
            }
            wincon::restore_saved();
            let _ = write!(
                std::io::stderr(),
                "\r\nshellx-term: internal error ({info}); carrying on without sharing\r\n"
            );
            std::process::exit(winwrap::COULD_NOT_WRAP);
        }));
    }
    match command {
        cli::Command::Version => {
            let _ = writeln!(std::io::stdout(), "shellx-term {}", env!("CARGO_PKG_VERSION"));
        }
        cli::Command::Wrap(args) => match winwrap::run(&args) {
            Ok(code) => std::process::exit(code),
            Err(error) => {
                if let Some(notice) = error.notice() {
                    let _ = writeln!(std::io::stderr(), "{notice}");
                }
                std::process::exit(winwrap::COULD_NOT_WRAP);
            }
        },
        // `probe` serves the Unix blocks only.
        cli::Command::Probe | cli::Command::Invalid => {
            let _ = writeln!(std::io::stderr(), "shellx-term: unknown arguments; carrying on without sharing");
            std::process::exit(winwrap::COULD_NOT_WRAP);
        }
    }
}

#[cfg(not(any(unix, windows)))]
fn main() {
    std::process::exit(222);
}
```

Also keep the `#[cfg(unix)] use …` line at the top of `main.rs` from importing anything unused on Windows. The Unix `main` is entirely `cfg(unix)`.

- [ ] **Step 3: Local checks, commit**

1. Run the macOS gate. Unix behaviour is unchanged and the new code is `cfg(windows)`, so it must stay green.
2. Re-read both files once against the `session.rs` and `wincon.rs` signatures.
3. Commit:

```bash
git add term
git commit -m "feat(term): Windows wrapper — ConPTY shell, console relay, agent link, exit 222 when it cannot wrap"
```

---

### Task 6: PowerShell block and Windows tests

**Files:**
- Create: `term/shell/block.ps1`
- Create: `term/tests/blocks_text.rs` (every platform)
- Create: `term/tests/windows.rs` (`#![cfg(all(windows, feature = "test-hooks"))]`)
- Modify: `term/tests/block.rs` (remove `blocks_are_ascii_with_exact_markers`, now covered by `blocks_text.rs`)

**Interfaces:**
- Consumes:
  - harness: `Harness::{spawn, send, send_bytes, expect, wait_number_after, resize, pid, wait_exit}`, `temp_dir`, `BIN`
  - fake agent: `FakeAgent::{start, next_session}`, `AgentSession::{snapshot, send, expect_out, expect_msg, info}`
- Produces: `term/shell/block.ps1`. The P4 installer embeds it unchanged.

- [ ] **Step 1: The block**

`term/shell/block.ps1`:

```powershell
# >>> ShellX >>>
# Lets your paired phone see this terminal. Managed by ShellX: turn it off from the ShellX menu instead of editing it.
if (-not $env:SHELLX_TERM -and -not $env:SHELLX -and $env:LOCALAPPDATA -and $Host.Name -eq 'ConsoleHost' `
    -and -not [Console]::IsInputRedirected -and -not [Console]::IsOutputRedirected `
    -and $null -eq (Get-History -Count 1)) {
  # Only a plain interactive start: any other argument (-Command, -File, a script...) means no.
  $__shellxPlain = -not ([Environment]::GetCommandLineArgs() | Select-Object -Skip 1 |
      Where-Object { $_ -notmatch '^-(nologo|noprofile|noprofileloadtime|noexit|login|l)$' })
  $__shellxExe = Join-Path $env:LOCALAPPDATA 'ShellX\bin\shellx-term.exe'
  if ($__shellxPlain -and (Test-Path -LiteralPath $__shellxExe -PathType Leaf)) {
    # 222 = could not wrap: carry on here. A binary that cannot start leaves it at 222 too.
    $global:LASTEXITCODE = 222
    try { & $__shellxExe wrap -- (Get-Process -Id $PID).Path -NoLogo } catch { $global:LASTEXITCODE = 222 }
    if ($LASTEXITCODE -ne 222) { [Environment]::Exit($LASTEXITCODE) }
    Remove-Variable -Name LASTEXITCODE -Scope Global -ErrorAction SilentlyContinue
  }
  Remove-Variable -Name __shellxPlain, __shellxExe -ErrorAction SilentlyContinue
}
# <<< ShellX <<<
```

Why each piece is there:
- **`Get-History -Count 1`** is `$null` until the first command finishes. That covers profile loading and a dot-source typed as the very first command, which the tests use. A manual `. $PROFILE` later does not wrap the running shell.
- **The argument allowlist** rejects everything spec §5.3 lists (`-Command`, `-File`, `-EncodedCommand`, `-NonInteractive`, abbreviations included), plus any other argument. For example, VS Code's PowerShell integration passes `-NoExit -Command …`. Matching is case-insensitive.
- **`$global:LASTEXITCODE = 222` beforehand:** PowerShell does not set `LASTEXITCODE` when a program fails to start, and that failure may or may not throw. Either way the value stays 222, and the profile carries on.
- **`[Environment]::Exit`** ends the process both from the profile and from a dot-source. A plain `exit` inside a profile script is ambiguous.
- **Known edge:** an inner `exit 222` drops back to the outer shell.

- [ ] **Step 2: Block text checks on every platform**

`term/tests/blocks_text.rs`:

```rust
//! The block files as text: what every installer relies on.

const BLOCKS: [(&str, &str); 3] = [
    ("block.zsh", include_str!("../shell/block.zsh")),
    ("block.bash", include_str!("../shell/block.bash")),
    ("block.ps1", include_str!("../shell/block.ps1")),
];

#[test]
fn every_block_is_ascii_with_exact_markers() {
    for (name, block) in BLOCKS {
        assert!(block.is_ascii(), "{name}");
        let lines: Vec<&str> = block.lines().collect();
        assert_eq!(lines.first(), Some(&"# >>> ShellX >>>"), "{name}");
        assert_eq!(lines.last(), Some(&"# <<< ShellX <<<"), "{name}");
        assert!(block.ends_with('\n'), "{name}");
    }
}

#[test]
fn the_powershell_block_uses_the_installed_path_and_222() {
    let ps1 = BLOCKS[2].1;
    assert!(ps1.contains(r"Join-Path $env:LOCALAPPDATA 'ShellX\bin\shellx-term.exe'"));
    assert!(ps1.contains("$global:LASTEXITCODE = 222"));
    assert!(ps1.contains("if ($LASTEXITCODE -ne 222) { [Environment]::Exit($LASTEXITCODE) }"));
    assert!(ps1.contains("$null -eq (Get-History -Count 1)"));
}
```

Delete `blocks_are_ascii_with_exact_markers` from `term/tests/block.rs`.

Run: `cargo test --features test-hooks --test blocks_text`. Expected: 2 passed.

- [ ] **Step 3: Windows tests (run on CI only)**

ConPTY repaints the screen and may turn runs of spaces into cursor moves. To keep the checks reliable:
- every expected string is a single token with no spaces;
- every expected value is a number that cannot appear in a prompt path (1042 for `6*7+1000`, for example);
- the typed command never contains the expected text.

`term/tests/windows.rs`:

```rust
#![cfg(all(windows, feature = "test-hooks"))]
//! shellx-term.exe in a real ConPTY "window" (spec §11.1, §12).

mod common;

use common::fake_agent::{Behavior, FakeAgent};
use common::{Harness, BIN};
use shellx_term::proto::messages::{AgentMsg, TermMsg};
use std::path::Path;
use std::time::{Duration, Instant};

const T: Duration = Duration::from_secs(30);
const CMD: &str = r"C:\Windows\System32\cmd.exe";
const PWSH: &str = r"C:\Program Files\PowerShell\7\pwsh.exe";
const POWERSHELL: &str = r"C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe";

/// A window whose LOCALAPPDATA is `dir` (endpoint and installed binary live there).
fn spawn(program: &str, args: &[&str], dir: &Path, extra: &[(&str, &str)]) -> Harness {
    let base = dir.to_str().unwrap().to_string();
    let mut env: Vec<(&str, &str)> = vec![("LOCALAPPDATA", base.as_str()), ("SHELLX_TERM_TIMING", "fast")];
    env.extend_from_slice(extra);
    Harness::spawn(program, args, &env, 100, 30)
}

fn wrapped_cmd(dir: &Path) -> Harness {
    spawn(BIN, &["wrap", "--", CMD, "/d"], dir, &[])
}

fn wrapped_pwsh(dir: &Path) -> Harness {
    spawn(BIN, &["wrap", "--", PWSH, "-NoLogo", "-NoProfile"], dir, &[])
}

#[test]
fn cmd_runs_inside_and_its_exit_code_comes_back() {
    let dir = common::temp_dir("win-cmd");
    let mut h = wrapped_cmd(&dir);
    h.send("set /a 6*7+1000\r");
    h.expect("1042", T);
    h.send("exit 7\r");
    assert_eq!(h.wait_exit(T), 7);
}

#[test]
fn the_inner_shell_carries_the_conpty_marker() {
    let dir = common::temp_dir("win-marker");
    let mut h = wrapped_cmd(&dir);
    h.send("echo [%SHELLX_TERM%]\r");
    h.expect("[conpty:", T);
    h.send("exit 0\r");
    h.wait_exit(T);
}

#[test]
fn arrow_keys_reach_the_inner_shell() {
    let dir = common::temp_dir("win-arrows");
    let mut h = wrapped_cmd(&dir);
    h.send("set /a 6*7+1000\r");
    h.expect("1042", T);
    h.send("\x1b[A\r"); // Up: cmd recalls the last command
    h.expect("1042", T); // `expect` only searches output that arrived since
    h.send("exit 0\r");
    h.wait_exit(T);
}

#[test]
fn ctrl_c_stops_the_running_command() {
    let dir = common::temp_dir("win-ctrlc");
    let mut h = wrapped_cmd(&dir);
    h.send("ping -n 60 127.0.0.1\r");
    std::thread::sleep(Duration::from_millis(1500));
    h.send_bytes(b"\x03");
    h.send("set /a 5*5+1000\r");
    h.expect("1025", T);
    h.send("exit 0\r");
    h.wait_exit(T);
}

#[test]
fn resizing_the_window_resizes_the_shell() {
    let dir = common::temp_dir("win-resize");
    let mut h = wrapped_pwsh(&dir);
    h.send("$Host.UI.RawUI.WindowSize.Width + 1000\r");
    h.expect("1100", T);
    h.resize(120, 40);
    std::thread::sleep(Duration::from_millis(500));
    h.send("$Host.UI.RawUI.WindowSize.Width + 1000\r");
    h.expect("1120", T);
    h.send("exit 0\r");
    h.wait_exit(T);
}

#[test]
fn vietnamese_and_emoji_output_arrive_intact() {
    let dir = common::temp_dir("win-utf-out");
    let mut h = wrapped_pwsh(&dir);
    h.send("'[' + 'ti' + [char]0x1EBF + 'ng' + [char]::ConvertFromUtf32(0x1F600) + ']'\r");
    h.expect("[tiếng😀]", T);
    h.send("exit 0\r");
    h.wait_exit(T);
}

#[test]
fn typed_vietnamese_reaches_the_shell() {
    let dir = common::temp_dir("win-utf-in");
    let mut h = wrapped_pwsh(&dir);
    h.send("'L=' + 'Việt'.Length + ',' + [int][char]'ệ'\r");
    h.expect("L=4,7879", T);
    h.send("exit 0\r");
    h.wait_exit(T);
}

#[test]
fn a_fault_or_a_crash_exits_222() {
    for fault in ["openpty", "spawn", "panic"] {
        let dir = common::temp_dir(&format!("win-222-{fault}"));
        let mut h = spawn(BIN, &["wrap", "--", CMD, "/d"], &dir, &[("SHELLX_TERM_FAULT", fault)]);
        assert_eq!(h.wait_exit(T), 222, "{fault}: {:?}", h.text());
    }
}

#[test]
fn the_phone_sees_output_and_types_through_the_agent_link() {
    let dir = common::temp_dir("win-link");
    let mut h = wrapped_cmd(&dir);
    h.send("set /a 6*7+1000\r");
    h.expect("1042", T);
    let agent = FakeAgent::start(&dir, Behavior::Normal);
    let mut s = agent.next_session(T);
    assert!(String::from_utf8_lossy(&s.snapshot(T)).contains("1042"));
    assert_eq!(s.info.shell, "cmd");
    assert_eq!(s.info.app, ""); // the harness clears WT_SESSION
    s.send(&AgentMsg::In { data: b"set /a 7*9+1000\r".to_vec() });
    h.expect("1063", T);
    s.expect_out("1063", T);
    h.send("exit 3\r");
    assert_eq!(h.wait_exit(T), 3);
    assert_eq!(s.expect_msg(|m| matches!(m, TermMsg::Exit { .. }), T), TermMsg::Exit { code: 3 });
}

#[test]
fn killing_shellx_term_ends_the_inner_shell() {
    let dir = common::temp_dir("win-kill");
    let mut h = wrapped_pwsh(&dir);
    h.send("'PID=' + $PID\r");
    let inner = h.wait_number_after("PID=", T);
    h.send("ping -n 300 127.0.0.1\r");
    std::thread::sleep(Duration::from_millis(1500));
    // Only shellx-term.exe, as when its window is torn down; not the tree.
    let status = std::process::Command::new("taskkill")
        .args(["/PID", &h.pid().to_string(), "/F"])
        .status()
        .unwrap();
    assert!(status.success());
    h.wait_exit(T);
    let until = Instant::now() + Duration::from_secs(15);
    loop {
        let out = std::process::Command::new("tasklist")
            .args(["/FI", &format!("PID eq {inner}"), "/NH"])
            .output()
            .unwrap();
        if !String::from_utf8_lossy(&out.stdout).contains(&inner.to_string()) {
            break;
        }
        assert!(Instant::now() < until, "inner shell {inner} outlived shellx-term");
        std::thread::sleep(Duration::from_millis(200));
    }
}

/// `dir\ShellX\bin\shellx-term.exe`: the real binary, or `bytes`.
fn install(dir: &Path, bytes: Option<&[u8]>) {
    let bin = dir.join(r"ShellX\bin");
    std::fs::create_dir_all(&bin).unwrap();
    let exe = bin.join("shellx-term.exe");
    match bytes {
        Some(bytes) => std::fs::write(exe, bytes).unwrap(),
        None => {
            std::fs::copy(BIN, exe).unwrap();
        }
    }
}

const BLOCK: &str = concat!(env!("CARGO_MANIFEST_DIR"), r"\shell\block.ps1");

/// A PowerShell window whose first command dot-sources the block, then
/// prints AFTER-BLOCK (typed in two halves, so only output matches).
fn shell_with_block(program: &str, dir: &Path, extra: &[(&str, &str)]) -> Harness {
    let mut h = spawn(program, &["-NoLogo", "-NoProfile"], dir, extra);
    h.send(&format!(". '{BLOCK}'; 'AFTER' + '-BLOCK'\r"));
    h
}

#[test]
fn the_block_wraps_and_the_inner_exit_code_closes_the_window() {
    for program in [PWSH, POWERSHELL] {
        let dir = common::temp_dir("win-block");
        install(&dir, None);
        let mut h = shell_with_block(program, &dir, &[]);
        h.send("'[' + $env:SHELLX_TERM + ']'\r");
        h.expect("[conpty:", T);
        h.send("exit 5\r");
        assert_eq!(h.wait_exit(T), 5, "{program}: {:?}", h.text());
    }
}

#[test]
fn a_corrupt_binary_leaves_the_window_working() {
    let dir = common::temp_dir("win-corrupt");
    install(&dir, Some(b"MZ this is not a real executable"));
    let mut h = shell_with_block(PWSH, &dir, &[]);
    h.expect("AFTER-BLOCK", T);
    h.send("6*7+1000\r");
    h.expect("1042", T);
    h.send("exit 0\r");
    assert_eq!(h.wait_exit(T), 0);
}

#[test]
fn could_not_wrap_carries_on_in_the_outer_shell() {
    let dir = common::temp_dir("win-carry-on");
    install(&dir, None);
    let mut h = shell_with_block(PWSH, &dir, &[("SHELLX_TERM_FAULT", "spawn")]);
    h.expect("AFTER-BLOCK", T);
    h.send("'[' + $env:SHELLX_TERM + '|' + $LASTEXITCODE + ']'\r");
    h.expect("[|]", T);
    h.send("exit 0\r");
    assert_eq!(h.wait_exit(T), 0);
}

#[test]
fn a_dot_source_after_a_command_does_not_wrap() {
    let dir = common::temp_dir("win-manual");
    install(&dir, None);
    let mut h = spawn(PWSH, &["-NoLogo", "-NoProfile"], &dir, &[]);
    h.send("6*7+1000\r");
    h.expect("1042", T);
    h.send(&format!(". '{BLOCK}'; '[' + $env:SHELLX_TERM + ']'\r"));
    h.expect("[]", T);
    h.send("exit 0\r");
    h.wait_exit(T);
}

#[test]
fn a_command_line_start_is_not_wrapped() {
    let dir = common::temp_dir("win-cmdline");
    install(&dir, None);
    let script = format!(". '{BLOCK}'; '[' + $env:SHELLX_TERM + ']'");
    let mut h = spawn(PWSH, &["-NoLogo", "-NoProfile", "-Command", &script], &dir, &[]);
    h.expect("[]", T);
    assert_eq!(h.wait_exit(T), 0);
}
```

On macOS this file compiles to nothing. Its first real run is in Task 8.

- [ ] **Step 4: Gate (macOS), commit**

```bash
git add term
git commit -m "feat(term): PowerShell integration block; Windows integration tests; block text checks on every platform"
```

---

### Task 7: `windows-check` workflow; spec, ledger, handoff

**Files:**
- Create: `.github/workflows/windows-check.yml`
- Modify: `docs/superpowers/specs/2026-10-01-desktop-terminal-sharing-design.md` (§5.3, §5.4, §6.1, §12, §14)
- Modify: `docs/superpowers/ledgers/terminal-sharing.md` (new "P2b" section), `docs/superpowers/HANDOFF.md` (§9)

**Interfaces:**
- Produces: a workflow that runs only in two cases:
  - **manual dispatch**, which needs the file on the default branch, so it becomes usable after a later merge to main;
  - **a push to a branch named `windows-check/**`**.

  An ordinary push never runs it, which keeps the "không CI" decision.

- [ ] **Step 1: Workflow**

`.github/workflows/windows-check.yml`:

```yaml
# Runs the shellx-term suite on real Windows (and macOS for parity).
# Never on ordinary pushes: only by hand, or by pushing a branch named
# windows-check/** (workflow_dispatch needs this file on the default branch).
name: windows-check

on:
  workflow_dispatch:
  push:
    branches: ['windows-check/**']

permissions:
  contents: read

jobs:
  term:
    name: shellx-term (${{ matrix.os }})
    strategy:
      fail-fast: false
      matrix:
        os: [windows-latest, macos-latest]
    runs-on: ${{ matrix.os }}
    timeout-minutes: 40
    defaults:
      run:
        working-directory: term
    steps:
      - uses: actions/checkout@v7
      - name: Toolchain
        run: rustup component add clippy rustfmt
      - name: Format
        run: cargo fmt --check
      - name: Clippy
        run: cargo clippy --all-targets --features test-hooks -- -D warnings
      - name: Test
        run: cargo test --features test-hooks -- --test-threads=4
```

`actions/checkout@v7` matches the reference the repository's other workflows use (`release-desktop.yml`, `deploy.yml`).

- [ ] **Step 2: Docs (Vietnamese, full diacritics, matching the code)**

1. **Spec §5.3:** make the text match `term/shell/block.ps1` and the Windows code:
   - **Arguments:** an allowlist — `-NoLogo`, `-NoProfile`, `-NoProfileLoadTime`, `-NoExit`, `-Login`, `-l`. It rejects everything §5.3 listed and any other argument.
   - **History guard:** the `Get-History` check, and why — a manual `. $PROFILE` does not wrap.
   - **Exit:** `$global:LASTEXITCODE = 222` set beforehand, and `[Environment]::Exit`.
   - **Marker:** `conpty:<pid>`, and its limit — a terminal launched from a wrapped Windows window does not wrap.
   - **Console handling in `shellx-term`:**
     - modes, including `ENABLE_WINDOW_INPUT` and `DISABLE_NEWLINE_AUTO_RETURN`;
     - `ReadConsoleInputW` with surrogate joining;
     - UTF-8 written with `WriteConsoleW`;
     - the close handler;
     - a lost console kills the inner shell;
     - a 500 ms drain on exit, because the ConPTY pipe only closes with the pseudoconsole.
2. **Spec §5.4:**
   - Item 2: on Windows, a panic also restores the console and exits 222.
   - Item 6: the SIGTERM disposition is restored before the Unix fallback (P2b Task 1).
3. **Spec §6.1:** change nothing unless the text differs from `%LOCALAPPDATA%\ShellX\term\endpoint`. Check it.
4. **Spec §12:**
   - Triggers: `workflow_dispatch` plus pushes to `windows-check/**`. Dispatch needs the file on main.
   - Scope in P2b: `term/` only (`cargo fmt`, `clippy`, `test` on Windows and macOS). P3 and P4 add the `dart test` and `flutter build windows` steps.
   - The interactive Windows check stays pending.
5. **Spec §14:** the P2b row ends with `(code xong, chờ CI Windows)` until Task 8 is green, then with `(**xong**, ledger `terminal-sharing.md`)`.
6. **Ledger:** add a "P2b" section covering:
   - the commits, the macOS test count, and the CI status ("chờ Task 8");
   - known limits: the per-tty check, an inner `exit 222`, VS Code's PowerShell integration not being wrapped;
   - what the manual Windows check must still cover: real Windows Terminal, IME, closing a tab, and PowerShell 5.1 profile encoding.
7. **HANDOFF:** in §9, the same in two or three lines. In §4, list the manual Windows check if it is not already there.

- [ ] **Step 3: Commit**

```bash
git add .github docs
git commit -m "ci: windows-check workflow (manual or windows-check/** only); docs: terminal sharing P2b"
```

---

### Task 8: First Windows run (controller, with the user)

The controller runs this task, not an implementer subagent. It needs a push that only the user can approve.

- [ ] **Step 1:** Ask the user, in Vietnamese, for permission to push the branch head to a new remote branch `windows-check/p2b` only. Main stays untouched, and the push triggers `windows-check.yml`. Push only on an explicit yes:
  ```bash
  git push origin HEAD:refs/heads/windows-check/p2b
  ```
- [ ] **Step 2:** The repository is private and `gh` is not installed. Ask the user to open the run in GitHub Actions, then either paste the log of each failing step or say that both jobs are green.
- [ ] **Step 3:** For each failure:
  1. Record it in the SDD ledger.
  2. Dispatch a fix implementer with the log, using the normal fix loop and review.
  3. With the user's OK each time, push the fixed head to the same `windows-check/p2b` branch.

  Repeat until both jobs are green.

  If a failure is a ConPTY rendering quirk of the outer test harness rather than `shellx-term` (for example, the harness conhost mangles an emoji), rule on it, record the ruling, and adjust the test to check through the agent link instead. A failure that is plainly in our code gets fixed in the code.
- [ ] **Step 4:** Record the green run, using the link or date the user gives, in the ledger P2b section, spec §12 and spec §14 (docs commit). After the final whole-branch review and the local merge, ask the user whether to delete the remote branch `windows-check/p2b`.
