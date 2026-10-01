//! `shellx-term wrap`: runs the shell inside a PTY and relays bytes between
//! the terminal window and that PTY (spec §5.1, §5.4).

use crate::appname::terminal_app;
use crate::cli::WrapArgs;
use crate::link::{Link, LinkEvents, Timing};
use crate::proto::endpoint::default_endpoint_path;
use crate::proto::messages::TermInfo;
use crate::size::{Driver, Resizer, SizeControl};
use crate::{faults, tty};
use portable_pty::{native_pty_system, Child, CommandBuilder, MasterPty, PtySize};
use signal_hook::consts::{SIGTERM, SIGWINCH};
use signal_hook::iterator::Signals;
use std::fs::File;
use std::io::{ErrorKind, Read, Write};
use std::mem::ManuallyDrop;
use std::os::unix::io::FromRawFd;
use std::sync::mpsc;
use std::sync::{Arc, Mutex};
use std::time::Duration;
use std::time::{SystemTime, UNIX_EPOCH};

/// A panic on another thread must not stop keystrokes or resizes: take the
/// lock even if it was poisoned.
fn lock<T>(m: &Mutex<T>) -> std::sync::MutexGuard<'_, T> {
    m.lock().unwrap_or_else(|e| e.into_inner())
}

type SharedWriter = Arc<Mutex<Box<dyn Write + Send>>>;
type SharedMaster = Arc<Mutex<Box<dyn MasterPty + Send>>>;

/// Resizes the PTY through the shared master.
struct MasterResizer(SharedMaster);

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

type Size = Arc<Mutex<SizeControl<MasterResizer>>>;

/// The link's view of this terminal.
struct WrapEvents {
    writer: SharedWriter,
    size: Size,
    base: TermInfo,
}

impl LinkEvents for WrapEvents {
    fn info(&self) -> TermInfo {
        let (cols, rows) = current_size();
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

/// True if SIGTERM was ignored when we started (an interactive shell's
/// parent may do that); we keep ignoring it then.
fn sigterm_ignored() -> bool {
    unsafe {
        let mut old: libc::sigaction = std::mem::zeroed();
        libc::sigaction(libc::SIGTERM, std::ptr::null(), &mut old) == 0
            && old.sa_sigaction == libc::SIG_IGN
    }
}

fn now_ms() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_millis() as u64)
        .unwrap_or(0)
}

fn random_term_id() -> [u8; 16] {
    let mut id = [0u8; 16];
    let _ = getrandom::fill(&mut id);
    id
}

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

    // The writer lives on inside `events` (owned by the link) until the
    // process exits; dropping portable-pty's writer would type "\n^D" into
    // the shell.
    let writer: SharedWriter = Arc::new(Mutex::new(to_pty));
    let master: SharedMaster = Arc::new(Mutex::new(pair.master));
    let size: Size = Arc::new(Mutex::new(SizeControl::new(
        MasterResizer(master.clone()),
        (cols, rows),
    )));
    let shell_name = std::path::Path::new(&args.shell)
        .file_name()
        .map(|n| n.to_string_lossy().into_owned())
        .unwrap_or_default();
    let base = TermInfo {
        term_id: random_term_id(),
        app: terminal_app(|k| std::env::var(k).ok()),
        shell: shell_name,
        pid: child.process_id().unwrap_or(0),
        cols,
        rows,
        started_at,
    };
    let events = Arc::new(WrapEvents {
        writer: writer.clone(),
        size: size.clone(),
        base,
    });
    let link = Arc::new(Link::start(
        default_endpoint_path(),
        Timing::from_env(),
        events,
    ));
    copy_window_to_pty(writer, size.clone(), link.clone(), child.process_id());
    let output_done = copy_pty_to_window(from_pty, link.clone());
    forward_signals(signals, master, size, link.clone());
    if faults::hit("panic") {
        panic!("injected fault");
    }

    let code = wait_for_exit(&mut *child);
    let _ = output_done.recv_timeout(DRAIN_AFTER_EXIT);
    link.finish(code.max(0) as u32);
    drop(raw);
    Ok(code)
}

/// Window resized → resize the PTY (the kernel then sends the shell
/// SIGWINCH). SIGTERM → put the window's modes back and exit; the kernel
/// closes the PTY, which hangs up the shell as closing a window does.
/// The thread owns the PTY master, keeping the PTY open for the process's
/// life.
fn forward_signals(mut signals: Signals, master: SharedMaster, size: Size, link: Arc<Link>) {
    std::thread::spawn(move || {
        let _keep_master_open = master;
        // A resize between reading the initial size and registering the
        // signals would otherwise be lost.
        on_window_resize(&size, &link);
        for signal in signals.forever() {
            match signal {
                SIGWINCH => on_window_resize(&size, &link),
                SIGTERM => {
                    tty::restore_saved();
                    std::process::exit(128 + SIGTERM);
                }
                _ => {}
            }
        }
    });
}

fn on_window_resize(size: &Size, link: &Link) {
    let notices = lock(size).window_resized(current_size());
    for notice in notices {
        link.send(notice.to_msg());
    }
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
fn copy_window_to_pty(writer: SharedWriter, size: Size, link: Arc<Link>, shell_pid: Option<u32>) {
    std::thread::spawn(move || {
        // fd 0 lives as long as the process; ManuallyDrop keeps it open.
        let mut window = ManuallyDrop::new(unsafe { File::from_raw_fd(STDIN) });
        let mut buf = [0u8; 8192];
        let window_gone = loop {
            match window.read(&mut buf) {
                Ok(0) => break true,
                Ok(n) => {
                    // A desktop keystroke takes the size back from the phone.
                    let notices = {
                        let mut s = lock(&size);
                        if s.driver() == Driver::Phone {
                            s.local_input()
                        } else {
                            Vec::new()
                        }
                    };
                    for notice in notices {
                        link.send(notice.to_msg());
                    }
                    let ok = lock(&writer).write_all(&buf[..n]).is_ok();
                    if !ok {
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
        // Never drop portable-pty's writer: it types "\n^D" into the shell.
        // Other owners (the link's events) may already be gone, e.g. without
        // HOME, so this reference is leaked on purpose.
        std::mem::forget(writer);
    });
}

/// The shell's output → the window. The receiver fires once the PTY closes.
fn copy_pty_to_window(mut from_pty: Box<dyn Read + Send>, link: Arc<Link>) -> mpsc::Receiver<()> {
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
                    link.output(&buf[..n]);
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
