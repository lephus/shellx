//! `shellx-term wrap` on Windows (spec §5.3): the shell runs in a ConPTY;
//! this process relays the console window and joins the agent link. It exits
//! with the shell's code, or 222 ("could not wrap, carry on") before the
//! shell starts.

use crate::cli::WrapArgs;
use crate::session::{
    copy_pty_to_window, lock, now_ms, wait_for_exit, Wiring, WrapError, DRAIN_AFTER_EXIT,
};
use crate::{faults, wincon};
use portable_pty::{native_pty_system, CommandBuilder, PtySize};
use std::sync::{Arc, Mutex};
use std::time::Duration;

/// "Could not wrap": the PowerShell block carries on in the outer shell.
pub const COULD_NOT_WRAP: i32 = 222;

/// How often the window size is checked: classic conhost reports only
/// buffer resizes, so a height change with a long scrollback sends no event.
const SIZE_CHECK: Duration = Duration::from_millis(250);

fn current_size() -> (u16, u16) {
    wincon::window_size().unwrap_or((80, 24))
}

/// The last window size forwarded to the session.
struct LastSize(Mutex<(u16, u16)>);

impl LastSize {
    /// Forwards the window's size if it changed since the last call.
    fn check(&self, wiring: &Wiring) {
        let now = current_size();
        let mut last = lock(&self.0);
        if *last != now {
            *last = now;
            wiring.window_resized(now);
        }
    }
}

/// Runs the shell until it exits and returns its exit code. `Err` is only
/// returned before the shell started.
pub fn run(args: &WrapArgs) -> Result<i32, WrapError> {
    // Tests only: a binary that dies at start, as a loader failure does. On Windows, abort exits with a negative NTSTATUS-style code.
    if faults::hit("abort") {
        std::process::abort();
    }
    if !wincon::is_console() {
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
    // Raw mode before the shell starts; an early return drops it, which puts
    // the console back before the outer PowerShell carries on.
    let raw = wincon::RawConsole::enable().map_err(|e| WrapError::Pty(e.to_string()))?;
    wincon::install_close_handler();

    if faults::hit("spawn") {
        return Err(WrapError::Spawn("injected fault".into()));
    }
    let mut cmd = CommandBuilder::new(&args.shell);
    // On Windows the builder lays the registry environment over ours (PATH,
    // TEMP, PSModulePath…); the inner shell must get the window's own, as it
    // would without ShellX (a venv, `conda activate`, VS Code's env settings).
    cmd.env_clear();
    for (key, value) in std::env::vars_os() {
        cmd.env(key, value);
    }
    cmd.args(&args.shell_args);
    // The PowerShell block skips any shell that carries a marker.
    cmd.env("SHELLX_TERM", format!("conpty:{}", std::process::id()));
    cmd.env_remove("SHELLX_TERM_WRAP");
    cmd.env_remove("SHELLX_TERM_WRAP_LOGIN");
    if let Ok(dir) = std::env::current_dir() {
        cmd.cwd(dir);
    }
    let mut child = pair
        .slave
        .spawn_command(cmd)
        .map_err(|e| WrapError::Spawn(e.to_string()))?;
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
    let output_done = copy_pty_to_window(
        from_pty,
        Box::new(wincon::ConsoleOut::default()),
        wiring.link.clone(),
    );
    let last_size = Arc::new(LastSize(Mutex::new((cols, rows))));
    let input = wiring.clone();
    let input_last = last_size.clone();
    std::thread::spawn(move || {
        wincon::read_window(|event| match event {
            wincon::WindowEvent::Bytes(bytes) => input.window_input(&bytes),
            wincon::WindowEvent::Resized => {
                input_last.check(&input);
                true
            }
            wincon::WindowEvent::Gone => {
                // The window went away: end the shell as closing it would.
                let _ = killer.kill();
                false
            }
        });
    });
    let poller = wiring.clone();
    std::thread::spawn(move || loop {
        std::thread::sleep(SIZE_CHECK);
        last_size.check(&poller);
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
