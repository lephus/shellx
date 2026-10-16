//! `shellx-term wrap`: runs the shell inside a PTY and relays bytes between
//! the terminal window and that PTY (spec §5.1, §5.4).

use crate::cli::WrapArgs;
use crate::session::{
    copy_pty_to_window, now_ms, wait_for_exit, SharedMaster, Wiring, DRAIN_AFTER_EXIT,
};
use crate::{faults, tty};
use portable_pty::{native_pty_system, CommandBuilder, PtySize};
use signal_hook::consts::{SIGTERM, SIGWINCH};
use signal_hook::iterator::Signals;
use std::fs::File;
use std::io::{ErrorKind, Read, Write};
use std::mem::ManuallyDrop;
use std::os::unix::io::FromRawFd;

pub use crate::session::WrapError;

/// True if SIGTERM was ignored when we started (an interactive shell's
/// parent may do that); we keep ignoring it then.
fn sigterm_ignored() -> bool {
    unsafe {
        let mut old: libc::sigaction = std::mem::zeroed();
        libc::sigaction(libc::SIGTERM, std::ptr::null(), &mut old) == 0
            && old.sa_sigaction == libc::SIG_IGN
    }
}

pub const STDIN: i32 = 0;
pub const STDOUT: i32 = 1;

/// Runs the shell until it exits and returns its exit code (128 + n when
/// signal n killed it). `Err` is only returned before the shell started.
pub fn run(args: &WrapArgs) -> Result<i32, WrapError> {
    if !tty::is_tty(STDIN) || !tty::is_tty(STDOUT) {
        return Err(WrapError::NotATerminal);
    }
    let started_at = now_ms();
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
    // An interactive shell ignores SIGTERM, but its `exec` of the block hands
    // us the default disposition: a block-started window keeps ignoring it.
    if args.from_block {
        unsafe { libc::signal(libc::SIGTERM, libc::SIG_IGN) };
    }
    let watched: &[i32] = if args.from_block || sigterm_ignored() {
        &[SIGWINCH]
    } else {
        &[SIGWINCH, SIGTERM]
    };
    let signals = Signals::new(watched).map_err(|e| WrapError::Pty(e.to_string()))?;

    if faults::hit("spawn") {
        return Err(WrapError::Spawn("injected fault".into()));
    }
    // The marker must be this PTY's path: "1" would not stop the inner
    // shell's block from wrapping again.
    let tty_name = pair
        .master
        .tty_name()
        .ok_or_else(|| WrapError::Pty("no tty name for the PTY".into()))?;
    let mut child = pair
        .slave
        .spawn_command(shell_command(args, tty_name))
        .map_err(|e| WrapError::Spawn(e.to_string()))?;
    drop(pair.slave);

    let (wiring, master) = Wiring::new(
        &args.shell,
        to_pty,
        pair.master,
        (cols, rows),
        current_size,
        child.process_id(),
        started_at,
    );
    copy_window_to_pty(wiring.clone(), child.process_id());
    let output_done = copy_pty_to_window(
        from_pty,
        Box::new(WindowOut(ManuallyDrop::new(unsafe {
            File::from_raw_fd(STDOUT)
        }))),
        wiring.link.clone(),
    );
    forward_signals(signals, master, wiring.clone());
    if faults::hit("panic") {
        panic!("injected fault");
    }

    let code = wait_for_exit(&mut *child);
    let _ = output_done.recv_timeout(DRAIN_AFTER_EXIT);
    wiring.link.finish(code as u32);
    drop(raw);
    Ok(code)
}

/// Window resized → resize the PTY (the kernel then sends the shell
/// SIGWINCH). SIGTERM → put the window's modes back and exit; the kernel
/// closes the PTY, which hangs up the shell as closing a window does.
/// The thread owns the PTY master, keeping the PTY open for the process's
/// life.
fn forward_signals(mut signals: Signals, master: SharedMaster, wiring: Wiring) {
    std::thread::spawn(move || {
        let _keep_master_open = master;
        // A resize between reading the initial size and registering the
        // signals would otherwise be lost.
        wiring.window_resized(current_size());
        for signal in signals.forever() {
            match signal {
                SIGWINCH => wiring.window_resized(current_size()),
                SIGTERM => {
                    tty::restore_saved();
                    std::process::exit(128 + SIGTERM);
                }
                _ => {}
            }
        }
    });
}

/// Size of the window, or 80x24 if it does not say.
fn current_size() -> (u16, u16) {
    tty::window_size(STDOUT)
        .or_else(|| tty::window_size(STDIN))
        .unwrap_or((80, 24))
}

fn shell_command(args: &WrapArgs, tty: std::path::PathBuf) -> CommandBuilder {
    let mut cmd = CommandBuilder::new(&args.shell);
    if args.login {
        cmd.arg("-l");
    }
    cmd.args(&args.shell_args);
    cmd.env("SHELLX_TERM", tty.into_os_string());
    cmd.env_remove("SHELLX_TERM_WRAP");
    cmd.env_remove("SHELLX_TERM_WRAP_LOGIN");
    if let Ok(dir) = std::env::current_dir() {
        cmd.cwd(dir);
    }
    cmd
}

/// The window's keystrokes → the shell, until the window goes away. When
/// reading the window fails (its app was killed without a SIGHUP reaching
/// us), hang the inner session up the way closing a window does; the main
/// thread then sees the shell exit and takes the normal exit path.
fn copy_window_to_pty(wiring: Wiring, shell_pid: Option<u32>) {
    std::thread::spawn(move || {
        // fd 0 lives as long as the process; ManuallyDrop keeps it open.
        let mut window = ManuallyDrop::new(unsafe { File::from_raw_fd(STDIN) });
        let mut buf = [0u8; 8192];
        let window_gone = loop {
            match window.read(&mut buf) {
                Ok(0) => break true,
                Ok(n) => {
                    // A desktop keystroke takes the size back from the phone.
                    if !wiring.window_input(&buf[..n]) {
                        break false;
                    }
                }
                Err(e) if e.kind() == ErrorKind::Interrupted => continue,
                Err(_) => break true,
            }
        };
        if window_gone {
            if let Some(pid) = shell_pid {
                // The shell is a session leader (its own process group): the
                // group gets the hang-up, then the shell itself.
                unsafe {
                    libc::kill(-(pid as i32), libc::SIGHUP);
                    libc::kill(pid as i32, libc::SIGHUP);
                }
            }
        }
    });
}

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
