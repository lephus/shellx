# Terminal Sharing P1 — `shellx-term` macOS Spike Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the macOS core of `shellx-term` (wrap an interactive shell in a PTY, relay bytes, never lose the user's terminal) plus the zsh/bash integration blocks, then measure startup cost and check real terminal apps to settle risks R1–R3 before plans P2–P5.

**Architecture:** A new Rust crate `term/` produces one binary, `shellx-term`. `shellx-term wrap [--login] -- <shell>` puts the window's TTY in raw mode, opens a PTY with `portable-pty`, runs the shell in it with `SHELLX_TERM=1`, copies bytes both ways on two threads, forwards `SIGWINCH`, and exits with the shell's exit code. Every failure path ends in `exec` of a plain shell (with `SHELLX_TERM=0`) because, on macOS, `shellx-term` *is* the window's process. There is no agent link in P1 (that is P2); the code is production code that P2 extends, not throwaway.

**Tech Stack:** Rust stable (1.95 on the dev Mac), `portable-pty 0.9.0`, `signal-hook 0.4.4`, `libc 0.2.189`; zsh 5.9 and bash 3.2 (macOS system shells); AppleScript for driving Terminal.app during the manual pass.

**Spec:** `docs/superpowers/specs/2026-10-01-desktop-terminal-sharing-design.md` (P1 = §14 row P1; behaviour from §5.1, §5.2, §5.4; risks §13 R1–R3).

## Global Constraints

- Work on branch `feat/terminal-sharing-p1` in worktree `.claude/worktrees/terminal-sharing-p1`, cut from `feat/shellx-v1`. After the final review, merge locally into `feat/shellx-v1`. **Never push.**
- The crate lives in `term/` at the repo root; package name `shellx-term`; binary name `shellx-term`.
- Out of P1 (later plans): the agent link and the 256 KiB output buffer (P2), Windows (P2), the `shellx-term uninstall` subcommand (P4, it needs the installer's file rules).
- Dependencies are exactly `portable-pty = "0.9.0"`, `signal-hook = "0.4.4"`, `libc = "0.2.189"`. No other crates (dev or normal).
- Feature `test-hooks` enables fault injection through env var `SHELLX_TERM_FAULT` (`openpty`, `spawn`, `panic`). Without the feature, faults compile to `false`.
- Inner shell environment: `SHELLX_TERM=1`. Fallback (plain) shell environment: `SHELLX_TERM=0`.
- Installed binary path (used by the blocks): `$HOME/Library/Application Support/ShellX/bin/shellx-term`.
- Block markers are exactly `# >>> ShellX >>>` (first line) and `# <<< ShellX <<<` (last line); block files are ASCII only.
- On Unix, `shellx-term` must never end without either running the wrapped shell to completion or `exec`-ing a plain shell. Exit codes: the shell's code, or 128 + n when signal n killed it.
- Non-Unix builds compile to a stub that exits with 222 ("could not wrap"; spec §5.3).
- `MACOSX_DEPLOYMENT_TARGET=12.0`.
- Startup budget: wrapping adds **< 50 ms median** to opening a window (spec §1 criterion 5).
- Gate for every task, run from `term/`: `cargo fmt --check && cargo clippy --all-targets --features test-hooks -- -D warnings && cargo test --features test-hooks`.
- **Do not touch the user's real `~/.zshrc`, `~/.bash_profile`, `~/.bashrc`, or `~/Library/Application Support/ShellX/` outside Task 7**, and in Task 7 only after the user says yes in the session. Task 7 always ends by restoring them.
- Commit messages: `feat(term): …`, `test(term): …`, `docs: …`.

## Review Focus

1. **Editors read the login environment by running `$SHELL -i -l -c '…'`** (VS Code, Cursor). The block must not wrap such a shell, or the editor hangs at startup. Pinned by the `-ilc` block tests in Task 5.
2. **Closing a window while a command runs** must hang up the command like it does today, with no orphan processes. Pinned by the SIGHUP test in Task 4.
3. **Huge, fast output** (`yes`, `cat` of a big log) must not stall the window, and Ctrl+C must stop it promptly. Pinned by the `yes` + Ctrl+C test in Task 4 and the 5 MB test in Task 3.
4. **Multi-byte UTF-8 (Vietnamese text)** must pass through unchanged, even when a character is split across reads. Pinned by the UTF-8 test in Task 3; IME typing is checked by hand in Task 7.
5. **A startup file that is a symlink** (dotfile managers) must stay a symlink after the block is added and removed. Pinned by the dev-script symlink test in Task 6, and recorded for P4's real installer in the ledger (Task 8).

---

### Task 1: Crate scaffold, CLI, and the "always a shell" fallback

**Files:**
- Create: `term/Cargo.toml`, `term/.gitignore`, `term/.cargo/config.toml`, `term/README.md`
- Create: `term/src/main.rs`, `term/src/cli.rs`, `term/src/fallback.rs`
- Create: `term/tests/common/mod.rs`, `term/tests/fallback.rs`

**Interfaces:**
- Produces:
  - `cli::parse(args: impl IntoIterator<Item = OsString>) -> cli::Command`
  - `enum cli::Command { Wrap(WrapArgs), Version, Invalid }`
  - `struct cli::WrapArgs { pub login: bool, pub shell: OsString, pub shell_args: Vec<OsString> }`
  - `struct fallback::Target { pub shell: Option<OsString>, pub login: bool, pub args: Vec<OsString> }` with `Target::for_command(&Command) -> Target`
  - `fallback::candidates(requested: Option<&OsStr>, shell_env: Option<&OsStr>) -> Vec<OsString>`
  - `fallback::arg0(shell: &OsStr, login: bool) -> OsString`
  - `fallback::exec_shell(target: &Target) -> !`
  - Test harness `tests/common/mod.rs`: `BIN`, `Harness::{spawn, wrap_sh, send, send_bytes, expect, text, output_bytes, resize, pid, wait_exit, number_after, wait_number_after}`, `wait_with_timeout`, `temp_dir`

- [ ] **Step 1: Create the worktree and the crate skeleton**

```bash
cd /Users/lehuuphu/Documents/myProjects/shellx
git worktree add .claude/worktrees/terminal-sharing-p1 -b feat/terminal-sharing-p1 feat/shellx-v1
cd .claude/worktrees/terminal-sharing-p1
mkdir -p term/src term/tests/common term/.cargo term/shell term/scripts term/examples
```

`term/Cargo.toml`:

```toml
[package]
name = "shellx-term"
version = "0.1.0"
edition = "2021"
publish = false
description = "Wraps an interactive shell in a PTY so ShellX can share the terminal with a paired phone."

[dependencies]
portable-pty = "0.9.0"
signal-hook = "0.4.4"
libc = "0.2.189"

[features]
# Fault injection for integration tests only: `cargo test --features test-hooks`.
test-hooks = []

[profile.release]
lto = true
codegen-units = 1
strip = true
```

`term/.gitignore`:

```
/target/
```

`term/.cargo/config.toml`:

```toml
[env]
MACOSX_DEPLOYMENT_TARGET = "12.0"
```

`term/README.md`:

```markdown
# shellx-term

Wraps an interactive shell in a PTY so ShellX can share that terminal window
with a paired phone. Design: `docs/superpowers/specs/2026-10-01-desktop-terminal-sharing-design.md`.

    cargo test --features test-hooks        # unit + integration tests (real PTYs, /bin/sh)
    cargo build --release                   # target/release/shellx-term

`shell/block.zsh` and `shell/block.bash` are the canonical startup-file blocks.
`scripts/` holds development helpers; the ShellX app installs everything for real.
```

- [ ] **Step 2: Write the CLI with failing tests**

`term/src/cli.rs`:

```rust
//! Command line of `shellx-term` (spec §5.1).

use std::ffi::OsString;
use std::path::Path;

#[derive(Debug, PartialEq, Eq)]
pub struct WrapArgs {
    /// Start the inner shell as a login shell (`-l`).
    pub login: bool,
    /// Absolute path of the shell to run inside the PTY.
    pub shell: OsString,
    /// Extra arguments for the shell.
    pub shell_args: Vec<OsString>,
}

#[derive(Debug, PartialEq, Eq)]
pub enum Command {
    Wrap(WrapArgs),
    Version,
    /// Anything else. `main` never refuses the user a shell: it falls back
    /// to a plain one for this.
    Invalid,
}

/// Parses the arguments after the program name.
pub fn parse<I: IntoIterator<Item = OsString>>(args: I) -> Command {
    let _ = args;
    todo!("Step 3")
}

#[cfg(test)]
mod tests {
    use super::*;

    fn parse_strs(args: &[&str]) -> Command {
        parse(args.iter().map(OsString::from))
    }

    fn wrap(login: bool, shell: &str, shell_args: &[&str]) -> Command {
        Command::Wrap(WrapArgs {
            login,
            shell: shell.into(),
            shell_args: shell_args.iter().map(OsString::from).collect(),
        })
    }

    #[test]
    fn wrap_with_a_shell() {
        assert_eq!(parse_strs(&["wrap", "--", "/bin/zsh"]), wrap(false, "/bin/zsh", &[]));
    }

    #[test]
    fn wrap_login_with_shell_arguments() {
        assert_eq!(
            parse_strs(&["wrap", "--login", "--", "/bin/bash", "-x"]),
            wrap(true, "/bin/bash", &["-x"])
        );
    }

    #[test]
    fn version() {
        assert_eq!(parse_strs(&["--version"]), Command::Version);
    }

    #[test]
    fn version_with_extra_arguments_is_invalid() {
        assert_eq!(parse_strs(&["--version", "x"]), Command::Invalid);
    }

    #[test]
    fn invalid_forms() {
        for args in [
            &[][..],
            &["bogus"][..],
            &["wrap"][..],
            &["wrap", "/bin/zsh"][..],
            &["wrap", "--"][..],
            &["wrap", "--", "zsh"][..],
            &["wrap", "--nope", "--", "/bin/zsh"][..],
            &["wrap", "--login", "--login", "--", "/bin/zsh"][..],
        ] {
            assert_eq!(parse_strs(args), Command::Invalid, "{args:?}");
        }
    }
}
```

`term/src/main.rs` (minimal until Step 6):

```rust
mod cli;

fn main() {
    let _ = cli::parse(std::env::args_os().skip(1));
}
```

Run: `cd term && cargo test --features test-hooks cli::`
Expected: the 5 `cli::tests` FAIL with "not yet implemented: Step 3".

- [ ] **Step 3: Implement the parser**

Replace the `parse` stub in `term/src/cli.rs` with:

```rust
/// Parses the arguments after the program name.
pub fn parse<I: IntoIterator<Item = OsString>>(args: I) -> Command {
    let mut args = args.into_iter();
    match args.next() {
        Some(first) if first == "--version" => match args.next() {
            None => Command::Version,
            Some(_) => Command::Invalid,
        },
        Some(first) if first == "wrap" => parse_wrap(args),
        _ => Command::Invalid,
    }
}

fn parse_wrap(mut args: impl Iterator<Item = OsString>) -> Command {
    let mut login = false;
    loop {
        match args.next() {
            Some(arg) if arg == "--login" && !login => login = true,
            Some(arg) if arg == "--" => break,
            _ => return Command::Invalid,
        }
    }
    let Some(shell) = args.next() else {
        return Command::Invalid;
    };
    if !Path::new(&shell).is_absolute() {
        return Command::Invalid;
    }
    Command::Wrap(WrapArgs {
        login,
        shell,
        shell_args: args.collect(),
    })
}
```

Run: `cd term && cargo test --features test-hooks cli::`
Expected: 5 passed.

- [ ] **Step 4: Write the fallback unit tests (failing)**

Add `#[cfg(unix)] mod fallback;` below `mod cli;` in `term/src/main.rs`, and create `term/src/fallback.rs` with the tests module only:

```rust
//! Last resort: replace this process with a plain shell (spec §5.4 item 2).

#[cfg(test)]
mod tests {
    use super::*;
    use crate::cli::{Command, WrapArgs};
    use std::ffi::{OsStr, OsString};

    #[test]
    fn candidates_in_order_without_duplicates_or_relative_paths() {
        assert_eq!(
            candidates(Some(OsStr::new("/opt/homebrew/bin/zsh")), Some(OsStr::new("/bin/zsh"))),
            vec![
                OsString::from("/opt/homebrew/bin/zsh"),
                OsString::from("/bin/zsh"),
                OsString::from("/bin/sh"),
            ]
        );
        assert_eq!(
            candidates(None, Some(OsStr::new("zsh"))),
            vec![OsString::from("/bin/zsh"), OsString::from("/bin/sh")]
        );
    }

    #[test]
    fn arg0_marks_login_shells_with_a_dash() {
        assert_eq!(arg0(OsStr::new("/bin/zsh"), true), OsString::from("-zsh"));
        assert_eq!(arg0(OsStr::new("/bin/zsh"), false), OsString::from("zsh"));
    }

    #[test]
    fn target_keeps_what_wrap_asked_for() {
        let target = Target::for_command(&Command::Wrap(WrapArgs {
            login: true,
            shell: "/bin/bash".into(),
            shell_args: vec!["-x".into()],
        }));
        assert_eq!(target.shell, Some(OsString::from("/bin/bash")));
        assert!(target.login);
        assert_eq!(target.args, vec![OsString::from("-x")]);
        let invalid = Target::for_command(&Command::Invalid);
        assert_eq!(invalid.shell, None);
        assert!(!invalid.login);
    }
}
```

Run: `cd term && cargo test --features test-hooks fallback::`
Expected: FAIL to compile (`candidates`, `arg0`, `Target` not found).

- [ ] **Step 5: Implement the fallback**

Put this above the tests module in `term/src/fallback.rs` (replace the placeholder doc line):

```rust
//! Last resort: replace this process with a plain shell (spec §5.4 item 2).
//!
//! On macOS the ShellX block `exec`s the window's shell into `shellx-term`,
//! so `shellx-term` *is* the window's process: exiting early would close the
//! window. Every path that cannot wrap ends here instead.

use crate::cli::Command;
use std::ffi::{OsStr, OsString};
use std::os::unix::process::CommandExt;
use std::path::Path;

/// What to start when wrapping is impossible.
#[derive(Debug, Clone, Default)]
pub struct Target {
    pub shell: Option<OsString>,
    pub login: bool,
    pub args: Vec<OsString>,
}

impl Target {
    pub fn for_command(command: &Command) -> Target {
        match command {
            Command::Wrap(wrap) => Target {
                shell: Some(wrap.shell.clone()),
                login: wrap.login,
                args: wrap.shell_args.clone(),
            },
            _ => Target::default(),
        }
    }
}

/// Shells to try, in order: the requested one, `$SHELL`, `/bin/zsh`,
/// `/bin/sh`. Absolute paths only, no duplicates.
pub fn candidates(requested: Option<&OsStr>, shell_env: Option<&OsStr>) -> Vec<OsString> {
    let fixed = [Some(OsStr::new("/bin/zsh")), Some(OsStr::new("/bin/sh"))];
    let mut out: Vec<OsString> = Vec::new();
    for candidate in [requested, shell_env].into_iter().chain(fixed).flatten() {
        if Path::new(candidate).is_absolute() && !out.iter().any(|seen| seen == candidate) {
            out.push(candidate.to_os_string());
        }
    }
    out
}

/// `argv[0]` for `shell`: `-zsh` for a login shell, as login(1) does.
pub fn arg0(shell: &OsStr, login: bool) -> OsString {
    let name = Path::new(shell).file_name().unwrap_or(shell);
    if login {
        let mut dashed = OsString::from("-");
        dashed.push(name);
        dashed
    } else {
        name.to_os_string()
    }
}

/// Replaces this process with the first shell that starts. `SHELLX_TERM=0`
/// stops the ShellX block in that shell's startup file from sending it back
/// here (the block only acts when `SHELLX_TERM` is empty).
pub fn exec_shell(target: &Target) -> ! {
    let shell_env = std::env::var_os("SHELL");
    for shell in candidates(target.shell.as_deref(), shell_env.as_deref()) {
        let args: &[OsString] = if target.shell.as_ref() == Some(&shell) {
            &target.args
        } else {
            &[]
        };
        // `exec` only returns on failure: try the next candidate.
        let _error = std::process::Command::new(&shell)
            .arg0(arg0(&shell, target.login))
            .args(args)
            .env("SHELLX_TERM", "0")
            .exec();
    }
    std::process::exit(127)
}
```

Replace `term/src/main.rs` with (every `wrap` falls back until Task 3):

```rust
//! `shellx-term`: wraps an interactive shell so ShellX can share the
//! terminal with a paired phone.
//! Spec: docs/superpowers/specs/2026-10-01-desktop-terminal-sharing-design.md

mod cli;
#[cfg(unix)]
mod fallback;

#[cfg(unix)]
fn main() {
    let command = cli::parse(std::env::args_os().skip(1));
    let target = fallback::Target::for_command(&command);
    match command {
        cli::Command::Version => println!("shellx-term {}", env!("CARGO_PKG_VERSION")),
        // Task 3 runs the wrapper for `Wrap`; until then it falls back too.
        cli::Command::Wrap(_) | cli::Command::Invalid => fallback::exec_shell(&target),
    }
}

#[cfg(not(unix))]
fn main() {
    // Windows arrives in plan P2 (spec §5.3). 222 tells the PowerShell block
    // "could not wrap, carry on".
    std::process::exit(222);
}
```

Run: `cd term && cargo test --features test-hooks fallback::`
Expected: 3 passed.

- [ ] **Step 6: Write the PTY test harness**

`term/tests/common/mod.rs`:

```rust
//! Test harness: runs a program as if it were the shell of a terminal
//! window, with a real PTY as its stdin/stdout.
#![allow(dead_code)]

use portable_pty::{native_pty_system, Child, CommandBuilder, MasterPty, PtySize};
use std::io::{Read, Write};
use std::os::unix::process::ExitStatusExt;
use std::path::PathBuf;
use std::sync::mpsc::{channel, Receiver};
use std::time::{Duration, Instant};

pub const BIN: &str = env!("CARGO_BIN_EXE_shellx-term");

pub struct Harness {
    master: Box<dyn MasterPty + Send>,
    writer: Box<dyn Write + Send>,
    rx: Receiver<Vec<u8>>,
    output: Vec<u8>,
    child: Box<dyn Child + Send + Sync>,
}

impl Harness {
    /// Runs `program args` in a fresh `cols`x`rows` PTY ("the window").
    /// `PS1` is `$ ` and ShellX variables are cleared unless `env` sets them.
    pub fn spawn(program: &str, args: &[&str], env: &[(&str, &str)], cols: u16, rows: u16) -> Harness {
        let pair = native_pty_system()
            .openpty(PtySize { rows, cols, pixel_width: 0, pixel_height: 0 })
            .expect("openpty");
        let mut cmd = CommandBuilder::new(program);
        cmd.args(args);
        cmd.cwd(std::env::temp_dir());
        for name in ["SHELLX_TERM", "SHELLX", "TMUX", "STY", "SHELLX_TERM_FAULT", "TERM_PROGRAM"] {
            cmd.env_remove(name);
        }
        cmd.env("PS1", "$ ");
        cmd.env("ENV", "");
        cmd.env("TERM", "xterm-256color");
        for (key, value) in env {
            cmd.env(key, value);
        }
        let child = pair.slave.spawn_command(cmd).expect("spawn");
        drop(pair.slave);
        let mut reader = pair.master.try_clone_reader().expect("reader");
        let writer = pair.master.take_writer().expect("writer");
        let (tx, rx) = channel();
        std::thread::spawn(move || {
            let mut buf = [0u8; 16384];
            loop {
                match reader.read(&mut buf) {
                    Ok(0) | Err(_) => break,
                    Ok(n) => {
                        if tx.send(buf[..n].to_vec()).is_err() {
                            break;
                        }
                    }
                }
            }
        });
        Harness { master: pair.master, writer, rx, output: Vec::new(), child }
    }

    /// `shellx-term wrap -- /bin/sh` in an 80x24 window.
    pub fn wrap_sh(env: &[(&str, &str)]) -> Harness {
        Harness::spawn(BIN, &["wrap", "--", "/bin/sh"], env, 80, 24)
    }

    pub fn send(&mut self, text: &str) {
        self.send_bytes(text.as_bytes());
    }

    pub fn send_bytes(&mut self, bytes: &[u8]) {
        self.writer.write_all(bytes).expect("write to window");
        self.writer.flush().expect("flush window");
    }

    /// Everything the window has shown so far (lossy UTF-8).
    pub fn text(&self) -> String {
        String::from_utf8_lossy(&self.output).into_owned()
    }

    pub fn output_bytes(&self) -> &[u8] {
        &self.output
    }

    /// Receives one chunk; false on timeout or when the window closed.
    fn pump(&mut self, until: Instant) -> bool {
        let now = Instant::now();
        if now >= until {
            return false;
        }
        match self.rx.recv_timeout(until - now) {
            Ok(chunk) => {
                self.output.extend_from_slice(&chunk);
                true
            }
            Err(_) => false,
        }
    }

    /// Waits until the output contains `needle`. Type commands so their
    /// echo does not contain the needle (`echo he''llo`, expect `hello`).
    /// Only newly arrived bytes are searched, so floods of output stay cheap.
    pub fn expect(&mut self, needle: &str, timeout: Duration) {
        let until = Instant::now() + timeout;
        let needle = needle.as_bytes();
        let mut from = 0;
        loop {
            if find(&self.output[from..], needle).is_some() {
                return;
            }
            from = self.output.len().saturating_sub(needle.len());
            if !self.pump(until) {
                let tail_start = self.output.len().saturating_sub(2000);
                panic!(
                    "did not see {:?} within {timeout:?}; last output: {:?}",
                    String::from_utf8_lossy(needle),
                    String::from_utf8_lossy(&self.output[tail_start..])
                );
            }
        }
    }

    /// The digits after the first `prefix` that is followed by digits (the
    /// echo of a typed `echo pid=$$` has no digits and is skipped).
    pub fn number_after(&self, prefix: &str) -> Option<i64> {
        let text = self.text();
        text.match_indices(prefix).find_map(|(at, _)| {
            let digits: String = text[at + prefix.len()..]
                .chars()
                .take_while(|c| c.is_ascii_digit())
                .collect();
            digits.parse().ok()
        })
    }

    /// Like [`Harness::number_after`], waiting for the number to appear.
    pub fn wait_number_after(&mut self, prefix: &str, timeout: Duration) -> i64 {
        let until = Instant::now() + timeout;
        loop {
            if let Some(number) = self.number_after(prefix) {
                return number;
            }
            if !self.pump(until) {
                panic!("no number after {prefix:?} within {timeout:?}; output so far: {:?}", self.text());
            }
        }
    }

    pub fn resize(&self, cols: u16, rows: u16) {
        self.master
            .resize(PtySize { rows, cols, pixel_width: 0, pixel_height: 0 })
            .expect("resize");
    }

    /// PID of the program running in the window.
    pub fn pid(&self) -> i32 {
        self.child.process_id().expect("pid") as i32
    }

    /// Waits for the program to exit; returns its code (128 + n for signal n).
    pub fn wait_exit(&mut self, timeout: Duration) -> i32 {
        let until = Instant::now() + timeout;
        loop {
            // Not `use`-ing `Downcast`: the call must resolve on the trait object.
            let child = self
                .child
                .as_any_mut()
                .downcast_mut::<std::process::Child>()
                .expect("portable-pty spawns std::process::Child on Unix");
            if let Some(status) = child.try_wait().expect("try_wait") {
                let drain_until = Instant::now() + Duration::from_millis(300);
                while self.pump(drain_until) {}
                return status.code().unwrap_or_else(|| 128 + status.signal().unwrap_or(0));
            }
            assert!(Instant::now() < until, "process did not exit; output so far: {:?}", self.text());
            let _ = self.pump(Instant::now() + Duration::from_millis(50));
        }
    }
}

fn find(haystack: &[u8], needle: &[u8]) -> Option<usize> {
    if needle.is_empty() {
        return Some(0);
    }
    haystack.windows(needle.len()).position(|window| window == needle)
}

/// `child.wait()` with a deadline; kills the child and panics on timeout.
pub fn wait_with_timeout(child: &mut std::process::Child, timeout: Duration) -> std::process::ExitStatus {
    let until = Instant::now() + timeout;
    loop {
        if let Some(status) = child.try_wait().expect("try_wait") {
            return status;
        }
        if Instant::now() >= until {
            let _ = child.kill();
            panic!("process did not exit within {timeout:?}");
        }
        std::thread::sleep(Duration::from_millis(20));
    }
}

/// A fresh, empty directory for one test.
pub fn temp_dir(name: &str) -> PathBuf {
    let dir = std::env::temp_dir().join(format!("shellx-term-test-{}-{name}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).expect("create temp dir");
    dir
}
```

- [ ] **Step 7: Write the fallback integration tests**

`term/tests/fallback.rs`:

```rust
mod common;

use common::{Harness, BIN};
use std::process::{Command, Stdio};
use std::time::Duration;

const T: Duration = Duration::from_secs(5);

#[test]
fn version_prints_the_crate_version() {
    let out = Command::new(BIN).arg("--version").output().expect("run");
    assert!(out.status.success());
    assert_eq!(
        String::from_utf8_lossy(&out.stdout).trim(),
        format!("shellx-term {}", env!("CARGO_PKG_VERSION"))
    );
}

#[test]
fn bad_arguments_still_give_the_user_a_shell() {
    let mut h = Harness::spawn(BIN, &["bogus"], &[("SHELL", "/bin/sh")], 80, 24);
    h.send("echo m=$SHELLX_TERM\r");
    h.expect("m=0", T);
    h.send("exit 4\r");
    assert_eq!(h.wait_exit(T), 4);
}

#[test]
fn a_missing_shell_falls_back_to_the_shell_variable() {
    let mut h = Harness::spawn(BIN, &["wrap", "--", "/nonexistent/zsh"], &[("SHELL", "/bin/sh")], 80, 24);
    h.send("echo m=$SHELLX_TERM\r");
    h.expect("m=0", T);
    h.send("exit 6\r");
    assert_eq!(h.wait_exit(T), 6);
}

#[test]
fn without_a_terminal_it_runs_the_shell_directly_and_does_not_hang() {
    let mut child = Command::new(BIN)
        .args(["wrap", "--", "/bin/sh"])
        .env("SHELL", "/bin/sh")
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .expect("spawn");
    let status = common::wait_with_timeout(&mut child, T);
    assert_eq!(status.code(), Some(0));
}
```

- [ ] **Step 8: Run the whole gate**

Run: `cd term && cargo fmt && cargo fmt --check && cargo clippy --all-targets --features test-hooks -- -D warnings && cargo test --features test-hooks`
Expected: all pass (8 unit tests, 4 integration tests). If clippy flags `fallback` items as unused under `cfg(not(unix))`, that is fine on macOS; the gate runs on macOS.

- [ ] **Step 9: Commit**

```bash
git add term
git commit -m "feat(term): shellx-term crate with CLI and always-a-shell fallback"
```

---

### Task 2: Window side — raw mode and window size

**Files:**
- Create: `term/src/tty.rs`
- Modify: `term/src/main.rs` (declare the module)

**Interfaces:**
- Consumes: nothing from Task 1.
- Produces:
  - `tty::is_tty(fd: RawFd) -> bool`
  - `tty::window_size(fd: RawFd) -> Option<(u16, u16)>` as `(cols, rows)`
  - `tty::RawMode::enable(fd: RawFd) -> io::Result<RawMode>`; `Drop` restores the saved modes
  - `tty::restore_saved()`: restores the modes saved by the last `enable` without blocking (panic hook, SIGTERM)

- [ ] **Step 1: Write the failing tests**

`term/src/tty.rs` (tests first):

```rust
//! The terminal window's side: raw mode and size (Unix).

#[cfg(test)]
mod tests {
    use super::*;
    use std::os::unix::io::{AsRawFd, RawFd};
    use std::sync::Mutex;

    /// `SAVED` is global: tests that enable raw mode run one at a time.
    static SERIAL: Mutex<()> = Mutex::new(());

    struct Pty {
        master: RawFd,
        slave: RawFd,
    }

    impl Pty {
        fn open(cols: u16, rows: u16) -> Pty {
            let (mut master, mut slave) = (0, 0);
            let mut size = libc::winsize { ws_row: rows, ws_col: cols, ws_xpixel: 0, ws_ypixel: 0 };
            let rc = unsafe {
                libc::openpty(&mut master, &mut slave, std::ptr::null_mut(), std::ptr::null_mut(), &mut size)
            };
            assert_eq!(rc, 0, "openpty");
            Pty { master, slave }
        }
    }

    impl Drop for Pty {
        fn drop(&mut self) {
            unsafe {
                libc::close(self.slave);
                libc::close(self.master);
            }
        }
    }

    fn local_flags(fd: RawFd) -> libc::tcflag_t {
        let mut modes: libc::termios = unsafe { std::mem::zeroed() };
        assert_eq!(unsafe { libc::tcgetattr(fd, &mut modes) }, 0);
        modes.c_lflag
    }

    #[test]
    fn reads_the_window_size() {
        let pty = Pty::open(100, 30);
        assert!(is_tty(pty.slave));
        assert_eq!(window_size(pty.slave), Some((100, 30)));
    }

    #[test]
    fn a_file_is_not_a_terminal() {
        let null = std::fs::File::open("/dev/null").unwrap();
        assert!(!is_tty(null.as_raw_fd()));
        assert_eq!(window_size(null.as_raw_fd()), None);
        assert!(RawMode::enable(null.as_raw_fd()).is_err());
    }

    #[test]
    fn raw_mode_turns_off_echo_line_editing_and_signals_then_restores() {
        let _serial = SERIAL.lock().unwrap_or_else(|e| e.into_inner());
        let pty = Pty::open(80, 24);
        let before = local_flags(pty.slave);
        assert_ne!(before & (libc::ECHO | libc::ICANON | libc::ISIG), 0);
        {
            let _raw = RawMode::enable(pty.slave).unwrap();
            assert_eq!(local_flags(pty.slave) & (libc::ECHO | libc::ICANON | libc::ISIG), 0);
        }
        assert_eq!(local_flags(pty.slave), before);
    }

    #[test]
    fn restore_saved_works_without_drop() {
        let _serial = SERIAL.lock().unwrap_or_else(|e| e.into_inner());
        let pty = Pty::open(80, 24);
        let before = local_flags(pty.slave);
        std::mem::forget(RawMode::enable(pty.slave).unwrap());
        restore_saved();
        assert_eq!(local_flags(pty.slave), before);
    }
}
```

In `term/src/main.rs`, below `mod fallback;`, add:

```rust
#[cfg(unix)]
#[allow(dead_code)] // wired in by Task 3
mod tty;
```

Run: `cd term && cargo test --features test-hooks tty::`
Expected: FAIL to compile (`is_tty`, `window_size`, `RawMode`, `restore_saved` not found).

- [ ] **Step 2: Implement**

Add above the tests module in `term/src/tty.rs`:

```rust
use std::io;
use std::os::unix::io::RawFd;
use std::sync::Mutex;

/// Modes to put back if we die without running `RawMode`'s `Drop` (panic
/// hook, SIGTERM).
static SAVED: Mutex<Option<(RawFd, libc::termios)>> = Mutex::new(None);

pub fn is_tty(fd: RawFd) -> bool {
    unsafe { libc::isatty(fd) == 1 }
}

/// `(cols, rows)` of the terminal on `fd`, if it is one and reports a size.
pub fn window_size(fd: RawFd) -> Option<(u16, u16)> {
    let mut size: libc::winsize = unsafe { std::mem::zeroed() };
    let rc = unsafe { libc::ioctl(fd, libc::TIOCGWINSZ, &mut size) };
    if rc != 0 || size.ws_col == 0 || size.ws_row == 0 {
        return None;
    }
    Some((size.ws_col, size.ws_row))
}

/// The window's terminal in raw mode until dropped: keys such as Ctrl+C
/// reach the inner shell as bytes instead of signalling `shellx-term`.
pub struct RawMode {
    fd: RawFd,
    original: libc::termios,
}

impl RawMode {
    pub fn enable(fd: RawFd) -> io::Result<RawMode> {
        let mut original: libc::termios = unsafe { std::mem::zeroed() };
        if unsafe { libc::tcgetattr(fd, &mut original) } != 0 {
            return Err(io::Error::last_os_error());
        }
        let mut raw = original;
        unsafe { libc::cfmakeraw(&mut raw) };
        if unsafe { libc::tcsetattr(fd, libc::TCSANOW, &raw) } != 0 {
            return Err(io::Error::last_os_error());
        }
        *SAVED.lock().unwrap_or_else(|e| e.into_inner()) = Some((fd, original));
        Ok(RawMode { fd, original })
    }
}

impl Drop for RawMode {
    fn drop(&mut self) {
        unsafe { libc::tcsetattr(self.fd, libc::TCSANOW, &self.original) };
        *SAVED.lock().unwrap_or_else(|e| e.into_inner()) = None;
    }
}

/// Restores the modes saved by [`RawMode::enable`]. Never blocks: it runs
/// from the panic hook and the SIGTERM path.
pub fn restore_saved() {
    if let Ok(mut saved) = SAVED.try_lock() {
        if let Some((fd, original)) = saved.take() {
            unsafe { libc::tcsetattr(fd, libc::TCSANOW, &original) };
        }
    }
}
```

- [ ] **Step 3: Run the gate**

Run: `cd term && cargo fmt && cargo fmt --check && cargo clippy --all-targets --features test-hooks -- -D warnings && cargo test --features test-hooks`
Expected: all pass (4 new `tty::tests`).

- [ ] **Step 4: Commit**

```bash
git add term
git commit -m "feat(term): raw mode guard and window size for the terminal window"
```

---

### Task 3: `wrap` — shell in a PTY, byte relay, exit codes, fault fallback

**Files:**
- Create: `term/src/wrap.rs`, `term/src/faults.rs`
- Modify: `term/src/main.rs` (run the wrapper; remove the `dead_code` allow on `tty`)
- Create: `term/tests/wrap.rs`, `term/tests/faults.rs`

**Interfaces:**
- Consumes: `cli::WrapArgs`, `fallback::{Target, exec_shell}` (Task 1); `tty::{is_tty, window_size, RawMode}` (Task 2).
- Produces:
  - `wrap::run(args: &WrapArgs) -> Result<i32, WrapError>`; `Err` only before the shell started
  - `enum wrap::WrapError { NotATerminal, Pty(String), Spawn(String) }` with `WrapError::notice(&self) -> Option<String>` (the one line `main` prints before falling back)
  - `wrap::STDIN`, `wrap::STDOUT` (`0`, `1`)
  - `faults::hit(point: &str) -> bool`
  - Task 4 relies on `run` having a local `pair.master` it can hand to a signal thread, and on `current_size()` in `wrap.rs`.

- [ ] **Step 1: Write the failing integration tests**

`term/tests/wrap.rs`:

```rust
mod common;

use common::Harness;
use std::time::Duration;

const T: Duration = Duration::from_secs(5);

#[test]
fn typed_commands_run_in_the_wrapped_shell() {
    let mut h = Harness::wrap_sh(&[]);
    h.send("echo he''llo\r");
    h.expect("hello", T);
    h.send("exit 0\r");
    assert_eq!(h.wait_exit(T), 0);
}

#[test]
fn the_wrapped_shell_is_marked() {
    let mut h = Harness::wrap_sh(&[]);
    h.send("echo m=$SHELLX_TERM\r");
    h.expect("m=1", T);
    h.send("exit\r");
    h.wait_exit(T);
}

#[test]
fn the_exit_code_of_the_shell_is_kept() {
    let mut h = Harness::wrap_sh(&[]);
    h.send("exit 7\r");
    assert_eq!(h.wait_exit(T), 7);
}

#[test]
fn a_shell_killed_by_a_signal_reports_128_plus_the_signal() {
    let mut h = Harness::wrap_sh(&[]);
    h.send("kill -KILL $$\r");
    assert_eq!(h.wait_exit(T), 128 + 9);
}

#[test]
fn the_shell_starts_in_the_same_directory() {
    let mut h = Harness::wrap_sh(&[]);
    h.send("pwd -P; echo pw''d-done\r");
    h.expect("pwd-done", T);
    let expected = std::fs::canonicalize(std::env::temp_dir()).unwrap();
    assert!(
        h.text().contains(expected.to_str().unwrap()),
        "expected {} in {:?}",
        expected.display(),
        h.text()
    );
    h.send("exit\r");
    h.wait_exit(T);
}

#[test]
fn vietnamese_text_passes_through_unchanged() {
    let mut h = Harness::wrap_sh(&[]);
    h.send("printf '%s-%s\\n' 'ti\u{1ebf}ng' 'Vi\u{1ec7}t'\r");
    h.expect("ti\u{1ebf}ng-Vi\u{1ec7}t", T);
    h.send("exit\r");
    h.wait_exit(T);
}

#[test]
fn five_megabytes_of_output_arrive_complete() {
    let mut h = Harness::wrap_sh(&[]);
    h.send("head -c 5000000 /dev/zero | tr '\\0' a; echo; echo do''ne\r");
    h.expect("done", Duration::from_secs(30));
    let count = h.output_bytes().iter().filter(|&&b| b == b'a').count();
    assert!(count >= 5_000_000, "only {count} bytes arrived");
    h.send("exit\r");
    h.wait_exit(T);
}

#[test]
fn output_written_just_before_exit_is_not_lost() {
    let mut h = Harness::wrap_sh(&[]);
    h.send("head -c 300000 /dev/zero | tr '\\0' b; exit 0\r");
    assert_eq!(h.wait_exit(Duration::from_secs(15)), 0);
    let count = h.output_bytes().iter().filter(|&&b| b == b'b').count();
    assert!(count >= 300_000, "only {count} bytes arrived");
}
```

`term/tests/faults.rs`:

```rust
#![cfg(feature = "test-hooks")]

mod common;

use common::Harness;
use std::time::Duration;

const T: Duration = Duration::from_secs(5);

fn plain_shell_after_fault(fault: &str) {
    let mut h = Harness::wrap_sh(&[("SHELLX_TERM_FAULT", fault), ("SHELL", "/bin/sh")]);
    h.expect("could not share this terminal", T);
    h.send("echo m=$SHELLX_TERM\r");
    h.expect("m=0", T);
    h.send("exit 5\r");
    assert_eq!(h.wait_exit(T), 5);
}

#[test]
fn when_the_pty_cannot_open_the_user_gets_a_plain_shell() {
    plain_shell_after_fault("openpty");
}

#[test]
fn when_the_shell_cannot_start_in_the_pty_the_user_gets_a_plain_shell() {
    plain_shell_after_fault("spawn");
}
```

Run: `cd term && cargo test --features test-hooks --test wrap --test faults`
Expected: `the_wrapped_shell_is_marked` FAILS (the fallback sets `m=0`), and so do `a_shell_killed_by_a_signal…` and the large-output tests, because nothing wraps yet. `faults` tests pass trivially (fallback already happens). That is expected; they become meaningful once `wrap` exists.

- [ ] **Step 2: Implement faults**

`term/src/faults.rs`:

```rust
//! Fault injection for integration tests (feature `test-hooks`, env var
//! `SHELLX_TERM_FAULT`). Always false in real builds.

#[cfg(feature = "test-hooks")]
pub fn hit(point: &str) -> bool {
    std::env::var("SHELLX_TERM_FAULT").is_ok_and(|value| value == point)
}

#[cfg(not(feature = "test-hooks"))]
#[inline(always)]
pub fn hit(_point: &str) -> bool {
    false
}
```

- [ ] **Step 3: Implement `wrap`**

`term/src/wrap.rs`:

```rust
//! `shellx-term wrap`: runs the shell inside a PTY and relays bytes between
//! the terminal window and that PTY (spec §5.1, §5.4).

use crate::cli::WrapArgs;
use crate::{faults, tty};
use portable_pty::{native_pty_system, Child, CommandBuilder, PtySize};
use std::fs::File;
use std::io::{ErrorKind, Read, Write};
use std::mem::ManuallyDrop;
use std::os::unix::io::FromRawFd;
use std::sync::mpsc;
use std::time::Duration;

pub const STDIN: i32 = 0;
pub const STDOUT: i32 = 1;

/// How long output keeps flowing after the shell exits (the tail of
/// `cat big.log; exit`). Background jobs that keep the PTY open cannot hold
/// the window open longer than this.
const DRAIN_AFTER_EXIT: Duration = Duration::from_millis(500);

/// Why wrapping did not start; `main` then falls back to a plain shell.
#[derive(Debug)]
pub enum WrapError {
    NotATerminal,
    Pty(String),
    Spawn(String),
}

impl WrapError {
    /// One line for the window before the plain shell starts. None when
    /// there is no window to talk to.
    pub fn notice(&self) -> Option<String> {
        match self {
            WrapError::NotATerminal => None,
            WrapError::Pty(reason) | WrapError::Spawn(reason) => Some(format!(
                "shellx-term: could not share this terminal ({reason}); starting a plain shell"
            )),
        }
    }
}

/// Runs the shell until it exits and returns its exit code (128 + n when
/// signal n killed it). `Err` is only returned before the shell started.
pub fn run(args: &WrapArgs) -> Result<i32, WrapError> {
    if !tty::is_tty(STDIN) || !tty::is_tty(STDOUT) {
        return Err(WrapError::NotATerminal);
    }
    let (cols, rows) = current_size();
    if faults::hit("openpty") {
        return Err(WrapError::Pty("injected fault".into()));
    }
    let pair = native_pty_system()
        .openpty(PtySize { rows, cols, pixel_width: 0, pixel_height: 0 })
        .map_err(|e| WrapError::Pty(e.to_string()))?;
    let from_pty = pair.master.try_clone_reader().map_err(|e| WrapError::Pty(e.to_string()))?;
    let to_pty = pair.master.take_writer().map_err(|e| WrapError::Pty(e.to_string()))?;
    // Raw mode before the shell starts; any early return below drops it,
    // which puts the window's modes back before the fallback shell runs.
    let raw = tty::RawMode::enable(STDIN).map_err(|e| WrapError::Pty(e.to_string()))?;

    if faults::hit("spawn") {
        return Err(WrapError::Spawn("injected fault".into()));
    }
    let mut child = pair
        .slave
        .spawn_command(shell_command(args))
        .map_err(|e| WrapError::Spawn(e.to_string()))?;
    drop(pair.slave);

    copy_window_to_pty(to_pty);
    let output_done = copy_pty_to_window(from_pty);
    let _master = pair.master; // keeps the PTY open; Task 4 moves it to the signal thread

    let code = wait_for_exit(&mut *child);
    let _ = output_done.recv_timeout(DRAIN_AFTER_EXIT);
    drop(raw);
    Ok(code)
}

/// Size of the window, or 80x24 if it does not say.
fn current_size() -> (u16, u16) {
    tty::window_size(STDOUT)
        .or_else(|| tty::window_size(STDIN))
        .unwrap_or((80, 24))
}

fn shell_command(args: &WrapArgs) -> CommandBuilder {
    let mut cmd = CommandBuilder::new(&args.shell);
    if args.login {
        cmd.arg("-l");
    }
    cmd.args(&args.shell_args);
    cmd.env("SHELLX_TERM", "1");
    if let Ok(dir) = std::env::current_dir() {
        cmd.cwd(dir);
    }
    cmd
}

/// The window's keystrokes → the shell, until the window goes away.
fn copy_window_to_pty(mut to_pty: Box<dyn Write + Send>) {
    std::thread::spawn(move || {
        // fd 0 lives as long as the process; ManuallyDrop keeps it open.
        let mut window = ManuallyDrop::new(unsafe { File::from_raw_fd(STDIN) });
        let mut buf = [0u8; 8192];
        loop {
            match window.read(&mut buf) {
                Ok(0) => break,
                Ok(n) => {
                    if to_pty.write_all(&buf[..n]).is_err() {
                        break;
                    }
                }
                Err(e) if e.kind() == ErrorKind::Interrupted => continue,
                Err(_) => break,
            }
        }
        // Dropping portable-pty's writer types "\n^D" into the shell.
        std::mem::forget(to_pty);
    });
}

/// The shell's output → the window. The receiver fires once the PTY closes.
fn copy_pty_to_window(mut from_pty: Box<dyn Read + Send>) -> mpsc::Receiver<()> {
    let (done_tx, done_rx) = mpsc::channel();
    std::thread::spawn(move || {
        let mut window = ManuallyDrop::new(unsafe { File::from_raw_fd(STDOUT) });
        let mut buf = [0u8; 16384];
        loop {
            match from_pty.read(&mut buf) {
                Ok(0) => break,
                Ok(n) => {
                    if window.write_all(&buf[..n]).is_err() {
                        break;
                    }
                }
                Err(e) if e.kind() == ErrorKind::Interrupted => continue,
                // EIO once the shell and everything it started closed the PTY.
                Err(_) => break,
            }
        }
        let _ = done_tx.send(());
    });
    done_rx
}

/// The shell's exit code, or 128 + signal like shells report it.
fn wait_for_exit(child: &mut (dyn Child + Send + Sync)) -> i32 {
    use std::os::unix::process::ExitStatusExt;
    // portable-pty's exit status keeps only a signal *name*; the std child
    // underneath has the number.
    if let Some(std_child) = child.as_any_mut().downcast_mut::<std::process::Child>() {
        return match std_child.wait() {
            Ok(status) => status.code().unwrap_or_else(|| 128 + status.signal().unwrap_or(0)),
            Err(_) => 1,
        };
    }
    child.wait().map(|status| status.exit_code() as i32).unwrap_or(1)
}
```

Replace `term/src/main.rs` with:

```rust
//! `shellx-term`: wraps an interactive shell so ShellX can share the
//! terminal with a paired phone.
//! Spec: docs/superpowers/specs/2026-10-01-desktop-terminal-sharing-design.md

mod cli;
#[cfg(unix)]
mod fallback;
#[cfg(unix)]
mod faults;
#[cfg(unix)]
mod tty;
#[cfg(unix)]
mod wrap;

#[cfg(unix)]
fn main() {
    let command = cli::parse(std::env::args_os().skip(1));
    let target = fallback::Target::for_command(&command);
    match command {
        cli::Command::Version => println!("shellx-term {}", env!("CARGO_PKG_VERSION")),
        cli::Command::Invalid => fallback::exec_shell(&target),
        cli::Command::Wrap(args) => match wrap::run(&args) {
            Ok(code) => std::process::exit(code),
            Err(error) => {
                if let Some(notice) = error.notice() {
                    eprintln!("{notice}");
                }
                fallback::exec_shell(&target)
            }
        },
    }
}

#[cfg(not(unix))]
fn main() {
    // Windows arrives in plan P2 (spec §5.3). 222 tells the PowerShell block
    // "could not wrap, carry on".
    std::process::exit(222);
}
```

- [ ] **Step 4: Run the gate**

Run: `cd term && cargo fmt && cargo fmt --check && cargo clippy --all-targets --features test-hooks -- -D warnings && cargo test --features test-hooks`
Expected: all pass, including the 8 `wrap` tests and 2 `faults` tests. Run the suite 3 times (`for i in 1 2 3; do cargo test --features test-hooks -q || break; done`) to catch flakiness; any failure is a bug to fix, not to retry away.

- [ ] **Step 5: Commit**

```bash
git add term
git commit -m "feat(term): wrap the shell in a PTY and relay the window's bytes"
```

---

### Task 4: Signals, window resize, crash safety

**Files:**
- Modify: `term/src/wrap.rs` (signal thread; `panic` fault)
- Modify: `term/src/main.rs` (panic hook)
- Modify: `term/src/fallback.rs` (add `close_on_exec_above_stderr`)
- Create: `term/tests/signals.rs`
- Modify: `term/tests/faults.rs` (panic test)

**Interfaces:**
- Consumes: `wrap::run`, `current_size`, `tty::restore_saved`, `fallback::{Target, exec_shell}`.
- Produces: `fallback::close_on_exec_above_stderr()`. Behaviour: SIGWINCH resizes the PTY; SIGTERM restores the window's modes and exits 143; a panic restores the modes and `exec`s a plain shell.

- [ ] **Step 1: Write the failing tests**

`term/tests/signals.rs`:

```rust
mod common;

use common::{Harness, BIN};
use std::time::{Duration, Instant};

const T: Duration = Duration::from_secs(5);

#[test]
fn resizing_the_window_resizes_the_shell() {
    let mut h = Harness::wrap_sh(&[]);
    h.send("echo rea''dy\r");
    h.expect("ready", T);
    h.resize(100, 40);
    let until = Instant::now() + T;
    loop {
        h.send("stty size\r");
        std::thread::sleep(Duration::from_millis(300));
        if h.text().contains("40 100") {
            break;
        }
        assert!(Instant::now() < until, "size never reached the shell: {:?}", h.text());
    }
    h.send("exit\r");
    h.wait_exit(T);
}

#[test]
fn ctrl_c_interrupts_the_foreground_command() {
    let mut h = Harness::wrap_sh(&[]);
    h.send("sleep 30\r");
    std::thread::sleep(Duration::from_millis(300));
    h.send_bytes(b"\x03");
    h.send("echo after''int\r");
    h.expect("afterint", T);
    h.send("exit\r");
    h.wait_exit(T);
}

#[test]
fn ctrl_z_stops_the_foreground_command() {
    let mut h = Harness::wrap_sh(&[]);
    h.send("sleep 30\r");
    std::thread::sleep(Duration::from_millis(300));
    h.send_bytes(b"\x1a");
    h.expect("Stopped", T);
    // SIGKILL ends a stopped job; the shell reports it before its next prompt.
    h.send("kill -KILL %1\r");
    h.expect("Killed", T);
    h.send("exit\r");
    h.wait_exit(T);
}

#[test]
fn a_flood_of_output_can_be_interrupted() {
    let mut h = Harness::wrap_sh(&[]);
    h.send("yes\r");
    std::thread::sleep(Duration::from_millis(500));
    h.send_bytes(b"\x03");
    h.send("echo after''yes\r");
    h.expect("afteryes", Duration::from_secs(10));
    h.send("exit\r");
    h.wait_exit(T);
}

#[test]
fn the_window_modes_are_restored_after_the_shell_exits() {
    let dir = common::temp_dir("modes-exit");
    let d = dir.display();
    let mut h = Harness::spawn("/bin/sh", &[], &[], 80, 24);
    h.send(&format!("stty -g > {d}/before; {BIN} wrap -- /bin/sh; stty -g > {d}/after; echo sa''ved\r"));
    h.send("echo in''side\r");
    h.expect("inside", T);
    h.send("exit 0\r");
    h.expect("saved", T);
    assert_eq!(
        std::fs::read_to_string(dir.join("before")).unwrap(),
        std::fs::read_to_string(dir.join("after")).unwrap()
    );
}

#[test]
fn sigterm_restores_the_window_and_exits_143() {
    let dir = common::temp_dir("modes-term");
    let d = dir.display();
    let mut h = Harness::spawn("/bin/sh", &[], &[], 80, 24);
    h.send(&format!(
        "stty -g > {d}/before; {BIN} wrap -- /bin/sh; echo code=$?; stty -g > {d}/after; echo sa''ved\r"
    ));
    h.send("echo in''side\r");
    h.expect("inside", T);
    h.send("kill -TERM $PPID\r");
    h.expect("saved", T);
    assert_eq!(h.number_after("code="), Some(143));
    assert_eq!(
        std::fs::read_to_string(dir.join("before")).unwrap(),
        std::fs::read_to_string(dir.join("after")).unwrap()
    );
}

#[test]
fn closing_the_window_hangs_up_the_running_command() {
    let mut h = Harness::wrap_sh(&[]);
    h.send("sh -c 'echo pid=$$; exec sleep 1000'\r");
    let sleeper = h.wait_number_after("pid=", T) as i32;
    std::thread::sleep(Duration::from_millis(200)); // let `exec sleep` happen
    // What the kernel does to a window's process when the window closes.
    unsafe { libc::kill(h.pid(), libc::SIGHUP) };
    h.wait_exit(T);
    let until = Instant::now() + T;
    while unsafe { libc::kill(sleeper, 0) } == 0 {
        assert!(Instant::now() < until, "sleep {sleeper} survived the window closing");
        std::thread::sleep(Duration::from_millis(50));
    }
}
```

Append to `term/tests/faults.rs`:

```rust
#[test]
fn a_crash_restores_the_window_and_leaves_a_plain_shell() {
    let dir = common::temp_dir("modes-panic");
    let d = dir.display();
    let bin = common::BIN;
    let mut h = Harness::spawn("/bin/sh", &[], &[("SHELL", "/bin/sh")], 80, 24);
    h.send(&format!(
        "stty -g > {d}/before; SHELLX_TERM_FAULT=panic {bin} wrap -- /bin/sh; stty -g > {d}/after; echo sa''ved\r"
    ));
    h.expect("starting a plain shell", T);
    h.send("echo m=$SHELLX_TERM\r");
    h.expect("m=0", T);
    h.send("exit\r");
    h.expect("saved", T);
    assert_eq!(
        std::fs::read_to_string(dir.join("before")).unwrap(),
        std::fs::read_to_string(dir.join("after")).unwrap()
    );
}
```

Run: `cd term && cargo test --features test-hooks --test signals --test faults`
Expected: `resizing_the_window_resizes_the_shell` FAILS (no SIGWINCH forwarding), `sigterm_restores…` FAILS (exit without restoring: the modes differ, or the code is not 143), and `a_crash_restores…` FAILS (no `panic` fault and no hook). The Ctrl+C, Ctrl+Z, flood, restore-after-exit and hang-up tests may already pass; they pin behaviour that must not regress.

- [ ] **Step 2: Forward signals in `wrap.rs`**

Add these imports at the top of `term/src/wrap.rs`:

```rust
use portable_pty::MasterPty;
use signal_hook::consts::{SIGTERM, SIGWINCH};
use signal_hook::iterator::Signals;
```

In `run`, right after the `let raw = tty::RawMode::enable(...)` line, register the signals (before the shell starts, so no resize is missed):

```rust
    let signals = Signals::new([SIGWINCH, SIGTERM]).map_err(|e| WrapError::Pty(e.to_string()))?;
```

Replace the line `let _master = pair.master; // keeps the PTY open; Task 4 moves it to the signal thread` with:

```rust
    forward_signals(signals, pair.master);
    if faults::hit("panic") {
        panic!("injected fault");
    }
```

Add this function to `term/src/wrap.rs`:

```rust
/// Window resized → resize the PTY (the kernel then sends the shell
/// SIGWINCH). SIGTERM → put the window's modes back and exit; the kernel
/// closes the PTY, which hangs up the shell as closing a window does.
/// The thread owns the PTY master, keeping the PTY open for the process's
/// life.
fn forward_signals(mut signals: Signals, master: Box<dyn MasterPty + Send>) {
    std::thread::spawn(move || {
        for signal in signals.forever() {
            match signal {
                SIGWINCH => {
                    let (cols, rows) = current_size();
                    let _ = master.resize(PtySize { rows, cols, pixel_width: 0, pixel_height: 0 });
                }
                SIGTERM => {
                    tty::restore_saved();
                    std::process::exit(128 + SIGTERM);
                }
                _ => {}
            }
        }
    });
}
```

- [ ] **Step 3: Panic hook**

Add to `term/src/fallback.rs` (above the tests module):

```rust
/// Marks every descriptor above stderr close-on-exec, so a shell started
/// from the panic hook does not keep the old PTY open (the old inner shell
/// then gets its hang-up).
pub fn close_on_exec_above_stderr() {
    let max = unsafe { libc::sysconf(libc::_SC_OPEN_MAX) }.clamp(0, 4096) as i32;
    for fd in 3..max {
        unsafe { libc::fcntl(fd, libc::F_SETFD, libc::FD_CLOEXEC) };
    }
}
```

Replace the `#[cfg(unix)] fn main()` in `term/src/main.rs` with:

```rust
#[cfg(unix)]
fn main() {
    use std::sync::OnceLock;
    static TARGET: OnceLock<fallback::Target> = OnceLock::new();

    let command = cli::parse(std::env::args_os().skip(1));
    let target = TARGET.get_or_init(|| fallback::Target::for_command(&command));
    // A bug must never cost the user their terminal: restore the window and
    // replace this process with a plain shell.
    std::panic::set_hook(Box::new(|info| {
        tty::restore_saved();
        eprint!("\r\nshellx-term: internal error ({info}); starting a plain shell\r\n");
        fallback::close_on_exec_above_stderr();
        match TARGET.get() {
            Some(target) => fallback::exec_shell(target),
            None => fallback::exec_shell(&fallback::Target::default()),
        }
    }));
    match command {
        cli::Command::Version => println!("shellx-term {}", env!("CARGO_PKG_VERSION")),
        cli::Command::Invalid => fallback::exec_shell(target),
        cli::Command::Wrap(args) => match wrap::run(&args) {
            Ok(code) => std::process::exit(code),
            Err(error) => {
                if let Some(notice) = error.notice() {
                    eprintln!("{notice}");
                }
                fallback::exec_shell(target)
            }
        },
    }
}
```

- [ ] **Step 4: Run the gate**

Run: `cd term && cargo fmt && cargo fmt --check && cargo clippy --all-targets --features test-hooks -- -D warnings && cargo test --features test-hooks`
Expected: all pass (7 `signals` tests, 3 `faults` tests). Then run it 3 times in a row as in Task 3 Step 4.

- [ ] **Step 5: Commit**

```bash
git add term
git commit -m "feat(term): forward window resizes, restore the window on SIGTERM and on crash"
```

---

### Task 5: zsh and bash integration blocks

**Files:**
- Create: `term/shell/block.zsh`, `term/shell/block.bash`
- Create: `term/tests/block.rs`
- Modify: `docs/superpowers/specs/2026-10-01-desktop-terminal-sharing-design.md` §5.2 (conditions found while planning)

**Interfaces:**
- Consumes: the harness (`Harness::spawn`, `expect`, `wait_exit`, `text`, `temp_dir`), `BIN` (Task 1).
- Produces: `term/shell/block.zsh` and `term/shell/block.bash`, the canonical block text that P4's installer embeds unchanged, plus `include_str!` users in tests and in Task 6.

- [ ] **Step 1: Write the blocks**

`term/shell/block.zsh`:

```zsh
# >>> ShellX >>>
# Lets your paired phone see this terminal. Managed by ShellX: turn it off from the ShellX menu instead of editing it.
if [[ -o interactive && -o shinstdin && -t 0 && -t 1 \
      && -z "${SHELLX_TERM-}${SHELLX-}${TMUX-}${STY-}" \
      && "${TERM_PROGRAM-}" != WarpTerminal \
      && -x "$HOME/Library/Application Support/ShellX/bin/shellx-term" ]]; then
  __shellx_shell=${ZSH_ARGZERO#-}
  if [[ $__shellx_shell != /* ]]; then
    if [[ ${SHELL:t} == zsh ]]; then __shellx_shell=$SHELL; else __shellx_shell=${__shellx_shell:c}; fi
  fi
  if [[ -o login ]]; then
    exec "$HOME/Library/Application Support/ShellX/bin/shellx-term" wrap --login -- "$__shellx_shell"
  else
    exec "$HOME/Library/Application Support/ShellX/bin/shellx-term" wrap -- "$__shellx_shell"
  fi
  unset __shellx_shell
fi
# <<< ShellX <<<
```

`term/shell/block.bash` (bash 3.2 compatible):

```bash
# >>> ShellX >>>
# Lets your paired phone see this terminal. Managed by ShellX: turn it off from the ShellX menu instead of editing it.
if [[ $- == *i* && -z "${BASH_EXECUTION_STRING-}" && -t 0 && -t 1 \
      && -z "${SHELLX_TERM-}${SHELLX-}${TMUX-}${STY-}" \
      && "${TERM_PROGRAM-}" != WarpTerminal \
      && -x "$HOME/Library/Application Support/ShellX/bin/shellx-term" ]]; then
  if shopt -q login_shell; then
    exec "$HOME/Library/Application Support/ShellX/bin/shellx-term" wrap --login -- "$BASH"
  else
    exec "$HOME/Library/Application Support/ShellX/bin/shellx-term" wrap -- "$BASH"
  fi
fi
# <<< ShellX <<<
```

Why each condition exists (keep this knowledge in the spec, Step 5):
- `-o shinstdin` (zsh) / `BASH_EXECUTION_STRING` (bash): skip `zsh -i -l -c '…'`, which VS Code and Cursor run to read the login environment. Wrapping it would start an interactive shell and hang the editor.
- `WarpTerminal`: excluded until checked (Warp bootstraps shells its own way; not installed on the dev Mac).
- zsh path: `ZSH_ARGZERO` is `-zsh` for login shells started by Terminal.app. When it is not absolute, `$SHELL` is the login shell those apps start; `:c` resolves any other bare name through `PATH`.
- `unset __shellx_shell` only runs if `exec` failed (interactive zsh keeps going after a failed `exec`).

- [ ] **Step 2: Write the failing block tests**

`term/tests/block.rs`:

```rust
mod common;

use common::{Harness, BIN};
use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::time::Duration;

const T: Duration = Duration::from_secs(5);
const ZSH_BLOCK: &str = include_str!("../shell/block.zsh");
const BASH_BLOCK: &str = include_str!("../shell/block.bash");

/// A fake HOME whose "installed" shellx-term just reports how it was called.
fn home(name: &str) -> PathBuf {
    let home = common::temp_dir(name);
    let bin = home.join("Library/Application Support/ShellX/bin");
    std::fs::create_dir_all(&bin).unwrap();
    let fake = bin.join("shellx-term");
    std::fs::write(&fake, "#!/bin/sh\nprintf 'WRAPPED'\nfor a in \"$@\"; do printf ' [%s]' \"$a\"; done\nprintf '\\n'\nexit 0\n").unwrap();
    std::fs::set_permissions(&fake, std::fs::Permissions::from_mode(0o755)).unwrap();
    std::fs::write(home.join(".zshrc"), format!("{ZSH_BLOCK}echo AFTER-BLOCK\n")).unwrap();
    std::fs::write(home.join(".bashrc"), format!("{BASH_BLOCK}echo AFTER-BLOCK\n")).unwrap();
    std::fs::write(home.join(".bash_profile"), format!("{BASH_BLOCK}echo AFTER-BLOCK\n")).unwrap();
    home
}

fn env_for(home: &Path) -> Vec<(&'static str, String)> {
    let h = home.to_str().unwrap().to_string();
    vec![("HOME", h.clone()), ("ZDOTDIR", h), ("SHELL", "/bin/zsh".to_string())]
}

fn run_shell(program: &str, args: &[&str], home: &Path, extra: &[(&str, &str)]) -> Harness {
    let base = env_for(home);
    let mut env: Vec<(&str, &str)> = base.iter().map(|(k, v)| (*k, v.as_str())).collect();
    env.extend_from_slice(extra);
    Harness::spawn(program, args, &env, 80, 24)
}

fn assert_wrapped(program: &str, args: &[&str], expected: &str) {
    let home = home(&format!("wrap-{}-{}", program.replace('/', "_"), args.join("")));
    let mut h = run_shell(program, args, &home, &[]);
    h.expect(expected, T);
    assert_eq!(h.wait_exit(T), 0);
    assert!(!h.text().contains("AFTER-BLOCK"), "rest of the file ran: {:?}", h.text());
}

fn assert_not_wrapped(program: &str, args: &[&str], extra: &[(&str, &str)], tag: &str) {
    let home = home(&format!("skip-{tag}"));
    let mut h = run_shell(program, args, &home, extra);
    h.expect("AFTER-BLOCK", T);
    assert!(!h.text().contains("WRAPPED"), "{tag}: wrapped anyway: {:?}", h.text());
    h.send("exit\r");
    h.wait_exit(T);
}

#[test]
fn blocks_are_ascii_with_exact_markers() {
    for block in [ZSH_BLOCK, BASH_BLOCK] {
        assert!(block.is_ascii());
        let lines: Vec<&str> = block.lines().collect();
        assert_eq!(lines.first(), Some(&"# >>> ShellX >>>"));
        assert_eq!(lines.last(), Some(&"# <<< ShellX <<<"));
        assert!(block.ends_with('\n'));
    }
}

#[test]
fn zsh_interactive_is_wrapped() {
    assert_wrapped("/bin/zsh", &["-i"], "WRAPPED [wrap] [--] [/bin/zsh]");
}

#[test]
fn zsh_login_is_wrapped_as_login() {
    assert_wrapped("/bin/zsh", &["-il"], "WRAPPED [wrap] [--login] [--] [/bin/zsh]");
}

#[test]
fn zsh_started_by_bare_name_resolves_to_the_login_shell() {
    // argv[0] is "zsh" (not absolute): the block uses $SHELL.
    assert_wrapped("zsh", &["-i"], "WRAPPED [wrap] [--] [/bin/zsh]");
}

#[test]
fn bash_interactive_is_wrapped() {
    assert_wrapped("/bin/bash", &["-i"], "WRAPPED [wrap] [--] [/bin/bash]");
}

#[test]
fn bash_login_is_wrapped_as_login() {
    assert_wrapped("/bin/bash", &["-il"], "WRAPPED [wrap] [--login] [--] [/bin/bash]");
}

#[test]
fn editor_environment_probes_are_not_wrapped() {
    for (program, tag) in [("/bin/zsh", "zsh-ilc"), ("/bin/bash", "bash-ilc")] {
        let home = home(tag);
        let mut h = run_shell(program, &["-ilc", "echo pl''ain"], &home, &[]);
        h.expect("plain", T);
        assert_eq!(h.wait_exit(T), 0);
        assert!(!h.text().contains("WRAPPED"), "{tag}: {:?}", h.text());
    }
}

#[test]
fn nested_and_excluded_shells_are_not_wrapped() {
    let cases = [
        ("SHELLX_TERM", "1"),
        ("SHELLX_TERM", "0"),
        ("SHELLX", "1"),
        ("TMUX", "/tmp/tmux-1/default,1,0"),
        ("STY", "1.pts"),
        ("TERM_PROGRAM", "WarpTerminal"),
    ];
    for (i, (name, value)) in cases.into_iter().enumerate() {
        assert_not_wrapped("/bin/zsh", &["-i"], &[(name, value)], &format!("zsh-{i}"));
        assert_not_wrapped("/bin/bash", &["-i"], &[(name, value)], &format!("bash-{i}"));
    }
}

#[test]
fn a_missing_binary_leaves_the_shell_alone() {
    let home = home("missing");
    std::fs::remove_file(home.join("Library/Application Support/ShellX/bin/shellx-term")).unwrap();
    let mut h = run_shell("/bin/zsh", &["-i"], &home, &[]);
    h.expect("AFTER-BLOCK", T);
    h.send("exit\r");
    h.wait_exit(T);
}

#[test]
fn no_terminal_means_no_wrapping() {
    let home = home("no-tty");
    let out = Command::new("/bin/zsh")
        .arg("-i")
        .envs(env_for(&home))
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .output()
        .unwrap();
    let stdout = String::from_utf8_lossy(&out.stdout);
    assert!(stdout.contains("AFTER-BLOCK"), "{stdout:?}");
    assert!(!stdout.contains("WRAPPED"), "{stdout:?}");
}

#[test]
fn with_the_real_binary_the_rest_of_the_file_runs_once_inside() {
    let home = home("real");
    std::fs::copy(BIN, home.join("Library/Application Support/ShellX/bin/shellx-term")).unwrap();
    let mut h = run_shell("/bin/zsh", &["-i"], &home, &[]);
    h.send("echo m=$SHELLX_TERM\r");
    h.expect("m=1", T);
    assert_eq!(h.text().matches("AFTER-BLOCK").count(), 1, "{:?}", h.text());
    h.send("exit 3\r");
    assert_eq!(h.wait_exit(T), 3);
}
```

Note on `zsh_started_by_bare_name…`: `Harness::spawn("zsh", …)` goes through portable-pty's `PATH` search, which resolves `/bin/zsh` and keeps `argv[0] = "zsh"`.

Run: `cd term && cargo test --features test-hooks --test block`
Expected: compile error (`../shell/block.zsh` missing) if Step 1 was skipped; with Step 1 done, run it and fix any failing case by correcting the block, never by loosening a test. A likely first failure is `zsh_started_by_bare_name…` if `$SHELL` handling is wrong.

- [ ] **Step 3: Run the gate**

Run: `cd term && cargo fmt && cargo fmt --check && cargo clippy --all-targets --features test-hooks -- -D warnings && cargo test --features test-hooks`
Expected: all pass (11 block tests).

- [ ] **Step 4: Update the spec §5.2**

In `docs/superpowers/specs/2026-10-01-desktop-terminal-sharing-design.md` §5.2, replace the first bullet (`shell đang ở chế độ tương tác ($- chứa i);`) with:

```markdown
- shell đang tương tác **và không chạy chuỗi lệnh hay script**: zsh `[[ -o interactive && -o shinstdin ]]`; bash `$-` chứa `i` và `$BASH_EXECUTION_STRING` rỗng. VS Code/Cursor chạy `$SHELL -i -l -c '…'` để đọc biến môi trường khi khởi động; bọc shell đó sẽ làm editor treo;
```

Replace the bullet about the exclusion list with:

```markdown
- ứng dụng terminal không nằm trong danh sách loại trừ theo `TERM_PROGRAM`. Hiện có `WarpTerminal` (loại trừ trước vì Warp tự khởi tạo shell; chưa kiểm được vì máy phát triển chưa cài). Danh sách chốt sau kiểm tra ở §13;
```

And replace the sentence starting `Khối truyền cho shellx-term đường dẫn tuyệt đối` with:

```markdown
Khối truyền cho `shellx-term` đường dẫn tuyệt đối của **chính shell đang chạy**: bash dùng `$BASH`; zsh dùng `${ZSH_ARGZERO#-}` nếu đã tuyệt đối, nếu không thì `$SHELL` khi `$SHELL` là zsh (trường hợp Terminal.app/iTerm2 mở login shell `-zsh`), còn lại tìm theo `PATH`. Kèm cờ `--login` nếu shell là login shell (bash: `shopt -q login_shell`; zsh: `[[ -o login ]]`). Nhờ `exec`, `shellx-term` giữ đúng PID của shell ban đầu. Nội dung chuẩn của khối nằm ở `term/shell/block.zsh` và `term/shell/block.bash`; bộ cài (P4) chèn đúng nội dung đó.
```

- [ ] **Step 5: Commit**

```bash
git add term docs/superpowers/specs/2026-10-01-desktop-terminal-sharing-design.md
git commit -m "feat(term): zsh and bash integration blocks that skip editor probes and nested shells"
```

---

### Task 6: Startup benchmark (R3) and development helpers

**Files:**
- Create: `term/examples/startup_bench.rs`
- Create: `term/scripts/dev-install.sh`, `term/scripts/dev-block.sh`
- Create: `term/tests/dev_scripts.rs`

**Interfaces:**
- Consumes: `term/shell/block.zsh` (Task 5); the release binary.
- Produces: benchmark numbers (median/p90 of time-to-ready for baseline, wrapped with login inner shell, wrapped with non-login inner shell); `dev-install.sh install|remove`; `dev-block.sh on|off|status [file]`. Task 7 uses both scripts.

- [ ] **Step 1: Write the dev scripts' failing tests**

`term/tests/dev_scripts.rs`:

```rust
mod common;

use std::os::unix::fs::symlink;
use std::path::Path;
use std::process::Command;

const BLOCK_SCRIPT: &str = concat!(env!("CARGO_MANIFEST_DIR"), "/scripts/dev-block.sh");

fn block(args: &[&str]) -> String {
    let out = Command::new("/bin/bash").arg(BLOCK_SCRIPT).args(args).output().unwrap();
    assert!(out.status.success(), "{args:?}: {}", String::from_utf8_lossy(&out.stderr));
    String::from_utf8_lossy(&out.stdout).trim().to_string()
}

fn read(path: &Path) -> String {
    std::fs::read_to_string(path).unwrap()
}

#[test]
fn on_is_idempotent_and_off_restores_the_file_exactly() {
    let dir = common::temp_dir("dev-block");
    let rc = dir.join(".zshrc");
    std::fs::write(&rc, "export A=1\n# user stuff\n").unwrap();
    let rc_s = rc.to_str().unwrap();

    block(&["on", rc_s]);
    block(&["on", rc_s]);
    let content = read(&rc);
    assert_eq!(content.matches("# >>> ShellX >>>").count(), 1);
    assert!(content.starts_with("# >>> ShellX >>>\n"));
    assert!(content.ends_with("export A=1\n# user stuff\n"));
    assert_eq!(block(&["status", rc_s]), "on");
    assert_eq!(read(&dir.join(".zshrc.shellx-backup")), "export A=1\n# user stuff\n");

    block(&["off", rc_s]);
    block(&["off", rc_s]);
    assert_eq!(read(&rc), "export A=1\n# user stuff\n");
    assert_eq!(block(&["status", rc_s]), "off");
}

#[test]
fn a_missing_file_is_created_and_a_bash_file_gets_the_bash_block() {
    let dir = common::temp_dir("dev-block-new");
    let rc = dir.join(".bashrc");
    block(&["on", rc.to_str().unwrap()]);
    assert!(read(&rc).contains("BASH_EXECUTION_STRING"));
    assert!(!dir.join(".bashrc.shellx-backup").exists());
}

#[test]
fn a_symlinked_file_stays_a_symlink() {
    let dir = common::temp_dir("dev-block-link");
    let real = dir.join("dotfiles-zshrc");
    std::fs::write(&real, "export B=2\n").unwrap();
    let link = dir.join(".zshrc");
    symlink(&real, &link).unwrap();
    block(&["on", link.to_str().unwrap()]);
    assert!(std::fs::symlink_metadata(&link).unwrap().file_type().is_symlink());
    assert!(read(&real).starts_with("# >>> ShellX >>>"));
    block(&["off", link.to_str().unwrap()]);
    assert!(std::fs::symlink_metadata(&link).unwrap().file_type().is_symlink());
    assert_eq!(read(&real), "export B=2\n");
}
```

Run: `cd term && cargo test --features test-hooks --test dev_scripts`
Expected: FAIL (script missing).

- [ ] **Step 2: Write the scripts**

`term/scripts/dev-block.sh`:

```bash
#!/bin/bash
# Development only: adds or removes the ShellX block at the top of a shell
# startup file, keeping a one-time backup. The ShellX app does this for real
# (plan P4). Writes through symlinks so dotfile managers keep working.
# Usage: dev-block.sh on|off|status [file]   (default file: ~/.zshrc)
set -euo pipefail
here="$(cd "$(dirname "$0")/.." && pwd)"
file="${2:-$HOME/.zshrc}"
case "$(basename "$file")" in
  *bash*) block="$here/shell/block.bash" ;;
  *) block="$here/shell/block.zsh" ;;
esac
begin='# >>> ShellX >>>'
end='# <<< ShellX <<<'

has_block() {
  [ -f "$file" ] && grep -qxF "$begin" "$file"
}

case "${1:-}" in
  on)
    if has_block; then echo "already on: $file"; exit 0; fi
    tmp="$(mktemp)"
    cat "$block" > "$tmp"
    if [ -f "$file" ]; then
      if [ ! -e "$file.shellx-backup" ]; then cp -p "$file" "$file.shellx-backup"; fi
      cat "$file" >> "$tmp"
    fi
    cat "$tmp" > "$file"
    rm -f "$tmp"
    echo "on: $file"
    ;;
  off)
    if ! has_block; then echo "already off: $file"; exit 0; fi
    tmp="$(mktemp)"
    awk -v b="$begin" -v e="$end" '$0==b{skip=1;next} $0==e{skip=0;next} !skip' "$file" > "$tmp"
    cat "$tmp" > "$file"
    rm -f "$tmp"
    echo "off: $file"
    ;;
  status)
    if has_block; then echo on; else echo off; fi
    ;;
  *)
    echo "usage: $0 on|off|status [file]" >&2
    exit 2
    ;;
esac
```

`term/scripts/dev-install.sh`:

```bash
#!/bin/bash
# Development only: builds shellx-term and puts it where the ShellX block
# looks for it. The ShellX app does this for real (plan P4).
# Usage: dev-install.sh [install|remove]
set -euo pipefail
here="$(cd "$(dirname "$0")/.." && pwd)"
dest="$HOME/Library/Application Support/ShellX/bin"
case "${1:-install}" in
  install)
    cargo build --release --manifest-path "$here/Cargo.toml"
    mkdir -p "$dest"
    cp "$here/target/release/shellx-term" "$dest/shellx-term.tmp"
    mv -f "$dest/shellx-term.tmp" "$dest/shellx-term"
    echo "installed: $dest/shellx-term"
    ;;
  remove)
    rm -f "$dest/shellx-term"
    rmdir "$dest" 2>/dev/null || true
    echo "removed: $dest/shellx-term"
    ;;
  *)
    echo "usage: $0 [install|remove]" >&2
    exit 2
    ;;
esac
```

Run: `chmod +x term/scripts/*.sh && cd term && cargo test --features test-hooks --test dev_scripts`
Expected: 3 passed.

- [ ] **Step 3: Write the benchmark**

`term/examples/startup_bench.rs`:

```rust
//! How much does the ShellX block slow down opening a terminal window?
//! (spec §1 criterion 5, §13 R3). Uses your real zsh startup files through
//! a temporary ZDOTDIR; nothing in $HOME is modified.
//!
//!     cargo build --release && cargo run --release --example startup_bench
//!
//! SHELLX_BENCH_RUNS (default 20) sets the samples per variant.

use portable_pty::{native_pty_system, CommandBuilder, PtySize};
use std::io::Read;
use std::path::{Path, PathBuf};
use std::sync::mpsc;
use std::time::{Duration, Instant};

const READY: &str = "__SHELLX_READY__";
const BLOCK: &str = include_str!("../shell/block.zsh");
const INSTALLED: &str = "$HOME/Library/Application Support/ShellX/bin/shellx-term";

fn main() {
    let runs: usize = std::env::var("SHELLX_BENCH_RUNS")
        .ok()
        .and_then(|value| value.parse().ok())
        .unwrap_or(20);
    let bin = Path::new(env!("CARGO_MANIFEST_DIR")).join("target/release/shellx-term");
    assert!(bin.exists(), "build first: cargo build --release");
    let home = PathBuf::from(std::env::var_os("HOME").expect("HOME"));
    let root = std::env::temp_dir().join(format!("shellx-bench-{}", std::process::id()));
    let wrapped = BLOCK.replace(INSTALLED, bin.to_str().unwrap());
    let variants = [
        ("baseline", setup(&root.join("baseline"), &home, "")),
        ("wrapped, login inner", setup(&root.join("login"), &home, &wrapped)),
        (
            "wrapped, non-login inner",
            setup(&root.join("nologin"), &home, &wrapped.replace("wrap --login --", "wrap --")),
        ),
    ];

    let mut samples: Vec<Vec<f64>> = vec![Vec::new(); variants.len()];
    for round in 0..runs + 2 {
        for (i, (_, zdotdir)) in variants.iter().enumerate() {
            let ms = time_to_ready(zdotdir);
            if round >= 2 {
                samples[i].push(ms); // the first two rounds only warm caches
            }
        }
    }
    let baseline = median(&samples[0]);
    for (i, (name, _)) in variants.iter().enumerate() {
        let m = median(&samples[i]);
        println!(
            "{name:<26} median {m:7.1} ms   p90 {:7.1} ms   overhead {:+7.1} ms",
            percentile(&samples[i], 0.9),
            m - baseline
        );
    }
    let _ = std::fs::remove_dir_all(&root);
}

/// A ZDOTDIR whose files source the real ones, `block` first in .zshrc, and
/// a marker printed when startup is done.
fn setup(dir: &Path, home: &Path, block: &str) -> PathBuf {
    std::fs::create_dir_all(dir).unwrap();
    for name in [".zshenv", ".zprofile", ".zlogin"] {
        let real = home.join(name);
        std::fs::write(dir.join(name), format!("[[ -f '{0}' ]] && source '{0}'\n", real.display())).unwrap();
    }
    let real_rc = home.join(".zshrc");
    let rc = format!(
        "{block}[[ -f '{0}' ]] && source '{0}'\nprint -r -- {READY}\n",
        real_rc.display()
    );
    std::fs::write(dir.join(".zshrc"), rc).unwrap();
    dir.to_path_buf()
}

/// Milliseconds from starting a login zsh in a new PTY to the marker.
fn time_to_ready(zdotdir: &Path) -> f64 {
    let pair = native_pty_system()
        .openpty(PtySize { rows: 40, cols: 120, pixel_width: 0, pixel_height: 0 })
        .unwrap();
    let mut cmd = CommandBuilder::new("/bin/zsh");
    cmd.arg("-l");
    cmd.env("ZDOTDIR", zdotdir);
    for name in ["SHELLX_TERM", "SHELLX", "TMUX", "STY"] {
        cmd.env_remove(name);
    }
    let start = Instant::now();
    let mut child = pair.slave.spawn_command(cmd).unwrap();
    drop(pair.slave);
    let mut reader = pair.master.try_clone_reader().unwrap();
    let (tx, rx) = mpsc::channel();
    std::thread::spawn(move || {
        let mut buf = [0u8; 4096];
        let mut seen = Vec::new();
        while let Ok(n) = reader.read(&mut buf) {
            if n == 0 {
                break;
            }
            seen.extend_from_slice(&buf[..n]);
            if String::from_utf8_lossy(&seen).contains(READY) {
                let _ = tx.send(());
                break;
            }
        }
    });
    let ready = rx.recv_timeout(Duration::from_secs(10)).is_ok();
    let ms = start.elapsed().as_secs_f64() * 1000.0;
    let _ = child.kill();
    let _ = child.wait();
    assert!(ready, "no ready marker within 10 s for {}", zdotdir.display());
    ms
}

fn median(values: &[f64]) -> f64 {
    percentile(values, 0.5)
}

fn percentile(values: &[f64], p: f64) -> f64 {
    let mut sorted = values.to_vec();
    sorted.sort_by(|a, b| a.partial_cmp(b).unwrap());
    sorted[((sorted.len() - 1) as f64 * p).round() as usize]
}
```

- [ ] **Step 4: Run the gate and the benchmark**

Run: `cd term && cargo fmt && cargo fmt --check && cargo clippy --all-targets --features test-hooks -- -D warnings && cargo test --features test-hooks`
Expected: all pass.

Run: `cd term && cargo build --release && cargo run --release --example startup_bench`
Expected: three lines of numbers. Record them verbatim for Task 8. Pass criterion (spec §1 criterion 5): the overhead of at least one wrapped variant is < 50 ms. If both exceed 50 ms, do not tune now; record it, and it becomes a decision in Task 8.

- [ ] **Step 5: Commit**

```bash
git add term
git commit -m "feat(term): startup benchmark and development install/block helpers"
```

---

### Task 7: Manual compatibility pass on real terminal apps (R1, R2, R3) — with the user

This task changes the user's real shell setup. The controller (the main session, not a subagent) runs it together with the user.

**Files:**
- Create: `docs/superpowers/ledgers/terminal-sharing.md` (results; Task 8 finishes it)

**Interfaces:**
- Consumes: `term/scripts/dev-install.sh`, `term/scripts/dev-block.sh` (Task 6).
- Produces: a results table per app, and the list of `TERM_PROGRAM` values to exclude.

- [ ] **Step 1: Ask for consent, then record the "before" state**

Ask the user (in Vietnamese), and continue only on an explicit yes:

> "Để kiểm tra trên ứng dụng terminal thật, tôi cần tạm chèn khối ShellX vào đầu `~/.zshrc` (có sao lưu `~/.zshrc.shellx-backup`) và cài `shellx-term` vào `~/Library/Application Support/ShellX/bin/`. Chỉ các cửa sổ terminal mở mới trong lúc kiểm tra bị ảnh hưởng. Xong tôi gỡ hết và kiểm tra `~/.zshrc` giống hệt ban đầu. Đồng ý không?"

Before any change, open a Terminal.app window and capture the unwrapped reference:

```bash
osascript -e 'tell application "Terminal" to do script "echo PATH=$PATH; echo SHELLX_TERM=[$SHELLX_TERM]"'
sleep 2
osascript -e 'tell application "Terminal" to get {name, processes} of selected tab of front window'
osascript -e 'tell application "Terminal" to get contents of selected tab of front window' | grep -E '^(PATH|SHELLX_TERM)='
```

Record the tab processes and the PATH line in the ledger as "before". Close that window with `osascript -e 'tell application "Terminal" to close front window'` and note whether a "terminate running processes?" sheet appeared (baseline for R2).

- [ ] **Step 2: Enable**

Run from the worktree:

```bash
term/scripts/dev-install.sh install
term/scripts/dev-block.sh on
```

- [ ] **Step 3: Terminal.app (automatable checks)**

```bash
osascript -e 'tell application "Terminal" to do script "echo PATH=$PATH; echo SHELLX_TERM=[$SHELLX_TERM]"'
sleep 2
osascript -e 'tell application "Terminal" to get {name, processes} of selected tab of front window'
osascript -e 'tell application "Terminal" to get contents of selected tab of front window' | grep -E '^(PATH|SHELLX_TERM)='
osascript -e 'tell application "Terminal" to close front window'
sleep 1
osascript -e 'tell application "System Events" to tell process "Terminal" to get name of every sheet of every window'
```

Record: window title (R2: does it say `shellx-term` where it used to say `zsh`/`claude`?), the tab's process list, `SHELLX_TERM=[1]`, whether PATH equals "before" exactly (login inner shell reruns `path_helper`; a different order is a finding), and whether closing raised the sheet (R2). If a sheet is open, dismiss it with `osascript -e 'tell application "System Events" to tell process "Terminal" to click button "Terminate" of sheet 1 of front window'`.

If closing asks for confirmation, try the mitigation and record whether it works: Terminal → Settings → Profiles → (default profile) → Shell → "Ask before closing" → add `shellx-term` to the process list. Undo that setting afterwards unless the user wants to keep it.

- [ ] **Step 4: Interactive checklist (the user types; the controller records)**

In a new Terminal.app window, then in Cursor's integrated terminal (new terminal tab), then in Android Studio's terminal, the user runs through this list and reports each item as OK or what went wrong:

1. The prompt appears as fast as usual (R3 subjective).
2. `echo $SHELLX_TERM` prints `1`.
3. `vim` opens and quits cleanly (`:q`); `top` draws and quits (`q`); `less /etc/services` scrolls and quits.
4. `sleep 100` then Ctrl+C returns to the prompt; `sleep 100` then Ctrl+Z shows "suspended", then `fg` and Ctrl+C.
5. With `top` running, resize the window: `top` redraws to the new size.
6. Paste a long block of text (for example 200 lines copied from a file) at the prompt inside `cat > /dev/null`, then Ctrl+D: nothing is lost or garbled.
7. Type Vietnamese with the Vietnamese input method: `echo "tiếng Việt có dấu"` prints exactly that.
8. `exit 3` closes the window or tab like before.
9. The window or tab title (R2).
10. Cursor only: the terminal's shell integration still works (command decorations in the gutter, cwd shown in the tab). Quit Cursor, open it again from the Dock, and confirm it opens normally and a new terminal works (the `-ilc` environment probe is not wrapped).
11. Android Studio only: the terminal opens in the project folder (`pwd`).

iTerm2, VS Code, and Warp are not installed on the dev Mac. Ask the user whether to install any of them now; otherwise record them as "not checked (not installed)" for the §11.6 list.

- [ ] **Step 5: Restore, always**

Run even if earlier steps failed:

```bash
term/scripts/dev-block.sh off
cmp ~/.zshrc ~/.zshrc.shellx-backup && rm ~/.zshrc.shellx-backup
term/scripts/dev-install.sh remove
term/scripts/dev-block.sh status
```

Expected: `cmp` prints nothing, then `off`. If `cmp` reports a difference, restore with `cp -p ~/.zshrc.shellx-backup ~/.zshrc`, tell the user, and keep the backup.

- [ ] **Step 6: Write the results into the ledger and commit**

`docs/superpowers/ledgers/terminal-sharing.md`:

```markdown
# Ledger — chia sẻ terminal máy tính

Spec: `docs/superpowers/specs/2026-10-01-desktop-terminal-sharing-design.md`

## P1 — bản thử shellx-term trên macOS (YYYY-MM-DD)

### Đo thời gian mở cửa sổ (R3)

<ba dòng in ra từ startup_bench, nguyên văn>

### Kiểm tra theo ứng dụng

| Ứng dụng | Tiêu đề (R2) | Hỏi khi đóng (R2) | Integration (R1) | PATH giống trước | Checklist 1–8 | Ghi chú |
|---|---|---|---|---|---|---|
| Terminal.app | | | — | | | |
| Cursor | | | | | | |
| Android Studio | | | | | | |
| iTerm2 | chưa kiểm (chưa cài) | | | | | |
| VS Code | chưa kiểm (chưa cài) | | | | | |
| Warp | chưa kiểm (chưa cài; đang loại trừ trước) | | | | | |
```

Fill in the rows from Steps 1–4, then:

```bash
git add docs/superpowers/ledgers/terminal-sharing.md
git commit -m "docs: P1 terminal-app compatibility results for shellx-term"
```

---

### Task 8: Findings, spec updates, and the go/no-go for P2

**Files:**
- Modify: `docs/superpowers/ledgers/terminal-sharing.md` (rulings)
- Modify: `docs/superpowers/specs/2026-10-01-desktop-terminal-sharing-design.md` (§5.2 exclusion list, §13 R1–R3 status, and the login/non-login choice for the inner shell)
- Modify: `docs/superpowers/HANDOFF.md` (new section for terminal sharing; pending items)

**Interfaces:**
- Consumes: Task 6 numbers, Task 7 table.
- Produces: final exclusion list, the inner-shell mode decision, and an explicit go/no-go for P2 recorded in the ledger.

- [ ] **Step 1: Rulings in the ledger**

Append to `docs/superpowers/ledgers/terminal-sharing.md` a "Quyết định sau P1" section with one line per item, each stating the evidence:
- R1: per app, whether its shell integration survives; any `TERM_PROGRAM` values to add to the exclusion list.
- R2: whether titles show `shellx-term`; whether closing asks; whether the Terminal.app "Ask before closing" exception works. If R2 is hit, list the options for the user: (a) accept and document; (b) at enable time, offer to add `shellx-term` to Terminal.app's exception list; (c) in P2, have `shellx-term` send the inner foreground process name as the window title (OSC 1/2) while the shell does not set one.
- R3: benchmark numbers and the chosen inner-shell mode (login or non-login), with the PATH finding from Task 7.
- For P4: startup files can be symlinks (dotfile managers); the real installer must write through the link, as `dev-block.sh` does.

- [ ] **Step 2: Update the spec**

In §5.2, set the final exclusion list. In §13, mark R1–R3 with their outcome and a pointer to the ledger. If the inner-shell mode changed to non-login, update §5.2's `--login` sentence and `term/shell/block.zsh`/`block.bash` in the same commit, and re-run the gate.

- [ ] **Step 3: HANDOFF**

Add a section "9. Chia sẻ terminal máy tính (2026-10-01)" to `docs/superpowers/HANDOFF.md` with: link to the spec, plan and ledger; P1 status; the plans that remain (P2–P5, spec §14); the pending Windows interactive check (spec §12) under §4 "Việc chờ người dùng".

- [ ] **Step 4: Commit, then stop for the user's go/no-go**

```bash
git add docs term
git commit -m "docs: P1 findings for shellx-term; spec and handoff updated"
```

Present the rulings to the user in Vietnamese and ask for the go/no-go on P2 (and, if R2 is hit, which option). Do not start P2 without an explicit answer.
