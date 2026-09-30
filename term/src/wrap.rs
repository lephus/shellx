//! `shellx-term wrap`: runs the shell inside a PTY and relays bytes between
//! the terminal window and that PTY (spec §5.1, §5.4).

use crate::cli::WrapArgs;
use crate::{faults, tty};
use portable_pty::{native_pty_system, Child, CommandBuilder, MasterPty, PtySize};
use signal_hook::consts::{SIGTERM, SIGWINCH};
use signal_hook::iterator::Signals;
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
        .openpty(PtySize {
            rows,
            cols,
            pixel_width: 0,
            pixel_height: 0,
        })
        .map_err(|e| WrapError::Pty(e.to_string()))?;
    let from_pty = pair
        .master
        .try_clone_reader()
        .map_err(|e| WrapError::Pty(e.to_string()))?;
    let to_pty = pair
        .master
        .take_writer()
        .map_err(|e| WrapError::Pty(e.to_string()))?;
    // Raw mode before the shell starts; any early return below drops it,
    // which puts the window's modes back before the fallback shell runs.
    let raw = tty::RawMode::enable(STDIN).map_err(|e| WrapError::Pty(e.to_string()))?;
    let signals = Signals::new([SIGWINCH, SIGTERM]).map_err(|e| WrapError::Pty(e.to_string()))?;

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
    forward_signals(signals, pair.master);
    if faults::hit("panic") {
        panic!("injected fault");
    }

    let code = wait_for_exit(&mut *child);
    let _ = output_done.recv_timeout(DRAIN_AFTER_EXIT);
    drop(raw);
    Ok(code)
}

/// Window resized → resize the PTY (the kernel then sends the shell
/// SIGWINCH). SIGTERM → put the window's modes back and exit; the kernel
/// closes the PTY, which hangs up the shell as closing a window does.
/// The thread owns the PTY master, keeping the PTY open for the process's
/// life.
fn forward_signals(mut signals: Signals, master: Box<dyn MasterPty + Send>) {
    std::thread::spawn(move || {
        // A resize between reading the initial size and registering the
        // signals would otherwise be lost.
        resize_to_window(&*master);
        for signal in signals.forever() {
            match signal {
                SIGWINCH => resize_to_window(&*master),
                SIGTERM => {
                    tty::restore_saved();
                    std::process::exit(128 + SIGTERM);
                }
                _ => {}
            }
        }
    });
}

fn resize_to_window(master: &dyn MasterPty) {
    let (cols, rows) = current_size();
    let _ = master.resize(PtySize {
        rows,
        cols,
        pixel_width: 0,
        pixel_height: 0,
    });
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
            Ok(status) => status
                .code()
                .unwrap_or_else(|| 128 + status.signal().unwrap_or(0)),
            Err(_) => 1,
        };
    }
    child
        .wait()
        .map(|status| status.exit_code() as i32)
        .unwrap_or(1)
}
