//! What every platform's wrapper shares (spec §5.4): the PTY writer and
//! master, size control, the agent link, the shell's output path and its
//! exit code.

use crate::appname::terminal_app;
use crate::link::{Link, LinkEvents, Timing};
use crate::proto::endpoint::default_endpoint_path;
use crate::proto::messages::TermInfo;
use crate::size::{Driver, Resizer, SizeControl};
use portable_pty::{Child, MasterPty, PtySize};
use std::ffi::OsStr;
use std::io::{ErrorKind, Read, Write};
use std::path::Path;
use std::sync::mpsc;
use std::sync::{Arc, Mutex, MutexGuard};
use std::time::Duration;
use std::time::{SystemTime, UNIX_EPOCH};

/// A panic on another thread must not stop keystrokes or resizes: take the
/// lock even if it was poisoned.
pub fn lock<T>(m: &Mutex<T>) -> MutexGuard<'_, T> {
    m.lock().unwrap_or_else(|e| e.into_inner())
}

pub type SharedWriter = Arc<Mutex<Box<dyn Write + Send>>>;
pub type SharedMaster = Arc<Mutex<Box<dyn MasterPty + Send>>>;

/// Resizes the PTY through the shared master.
pub struct MasterResizer(SharedMaster);

impl Resizer for MasterResizer {
    fn resize(&self, cols: u16, rows: u16) {
        let _ = lock(&self.0).resize(PtySize {
            rows,
            cols,
            pixel_width: 0,
            pixel_height: 0,
        });
    }
}

pub type Size = Arc<Mutex<SizeControl<MasterResizer>>>;

/// The link's view of this terminal.
struct Events {
    writer: SharedWriter,
    size: Size,
    base: TermInfo,
    /// The window's size now (cols, rows).
    window_size: fn() -> (u16, u16),
}

impl LinkEvents for Events {
    fn info(&self) -> TermInfo {
        let (cols, rows) = (self.window_size)();
        TermInfo {
            cols,
            rows,
            ..self.base.clone()
        }
    }

    fn input(&self, data: &[u8]) {
        let _ = lock(&self.writer).write_all(data);
    }

    fn phone_resize(&self, cols: u16, rows: u16) {
        lock(&self.size).phone_resize((cols, rows));
    }

    fn phone_left(&self) {
        lock(&self.size).phone_left();
    }
}

pub fn now_ms() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_millis() as u64)
        .unwrap_or(0)
}

pub fn random_term_id() -> [u8; 16] {
    let mut id = [0u8; 16];
    let _ = getrandom::fill(&mut id);
    id
}

/// How long output keeps flowing after the shell exits (the tail of
/// `cat big.log; exit`). Background jobs that keep the PTY open cannot hold
/// the window open longer than this.
pub const DRAIN_AFTER_EXIT: Duration = Duration::from_millis(500);

/// Last words of the notice: what happens instead of sharing.
#[cfg(unix)]
const CARRY_ON: &str = "starting a plain shell";
#[cfg(not(unix))]
const CARRY_ON: &str = "carrying on without sharing";

/// Why wrapping did not start; `main` then carries on without sharing (on
/// Unix, in a plain shell).
#[derive(Debug)]
pub enum WrapError {
    NotATerminal,
    Pty(String),
    Spawn(String),
}

impl WrapError {
    /// One line for the window before `main` carries on. None when there is
    /// no window to talk to.
    pub fn notice(&self) -> Option<String> {
        match self {
            WrapError::NotATerminal => None,
            WrapError::Pty(reason) | WrapError::Spawn(reason) => Some(format!(
                "shellx-term: could not share this terminal ({reason}); {CARRY_ON}"
            )),
        }
    }
}

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
        let size: Size = Arc::new(Mutex::new(SizeControl::new(
            MasterResizer(master.clone()),
            window,
        )));
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
        let link = Arc::new(Link::start(
            default_endpoint_path(),
            Timing::from_env(),
            events,
        ));
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

/// The shell's exit code, or (on Unix) 128 + signal like shells report it.
pub fn wait_for_exit(child: &mut (dyn Child + Send + Sync)) -> i32 {
    #[cfg(unix)]
    {
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
    }
    child
        .wait()
        .map(|status| status.exit_code() as i32)
        .unwrap_or(1)
}

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
