//! The terminal window's side: raw mode and size (Unix).

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
        unsafe {
            libc::tcsetattr(self.fd, libc::TCSANOW, &self.original);
            libc::tcflush(self.fd, libc::TCIOFLUSH);
        }
        *SAVED.lock().unwrap_or_else(|e| e.into_inner()) = None;
    }
}

/// Restores the modes saved by [`RawMode::enable`]. Never blocks: it runs
/// from the panic hook and the SIGTERM path.
pub fn restore_saved() {
    if let Ok(mut saved) = SAVED.try_lock() {
        if let Some((fd, original)) = saved.take() {
            unsafe {
                libc::tcsetattr(fd, libc::TCSANOW, &original);
                libc::tcflush(fd, libc::TCIOFLUSH);
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::{is_tty, restore_saved, window_size, RawMode};
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
            let mut size = libc::winsize {
                ws_row: rows,
                ws_col: cols,
                ws_xpixel: 0,
                ws_ypixel: 0,
            };
            let rc = unsafe {
                libc::openpty(
                    &mut master,
                    &mut slave,
                    std::ptr::null_mut(),
                    std::ptr::null_mut(),
                    &mut size,
                )
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
            assert_eq!(
                local_flags(pty.slave) & (libc::ECHO | libc::ICANON | libc::ISIG),
                0
            );
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
