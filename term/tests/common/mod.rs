//! Test harness: runs a program as if it were the shell of a terminal
//! window, with a real PTY as its stdin/stdout.
#![allow(dead_code)]

use portable_pty::{native_pty_system, Child, CommandBuilder, MasterPty, PtySize};
use shellx_term::proto::endpoint::ENDPOINT_BASE_VAR;
use std::io::{Read, Write};
#[cfg(unix)]
use std::os::unix::process::ExitStatusExt;
use std::path::PathBuf;
use std::sync::atomic::{AtomicBool, AtomicUsize, Ordering};
use std::sync::mpsc::{channel, Receiver};
use std::sync::Arc;
use std::sync::Mutex;
use std::thread::JoinHandle;
use std::time::{Duration, Instant};

pub const BIN: &str = env!("CARGO_BIN_EXE_shellx-term");

pub struct Harness {
    master: Option<Box<dyn MasterPty + Send>>,
    /// Shared with the Windows reader, which answers ConPTY's cursor query.
    writer: Option<Arc<Mutex<Box<dyn Write + Send>>>>,
    stop_reader: Arc<AtomicBool>,
    reader_thread: Option<JoinHandle<()>>,
    rx: Receiver<Vec<u8>>,
    output: Vec<u8>,
    child: Box<dyn Child + Send + Sync>,
    /// The window's own temporary per-user base directory (when the caller
    /// did not pass one), kept until the window is dropped.
    _base: Option<TempDir>,
}

impl Harness {
    /// Runs `program args` in a fresh `cols`x`rows` PTY ("the window").
    /// `PS1` is `$ ` and ShellX variables are cleared unless `env` sets them.
    /// The per-user base directory (`HOME` on Unix, `LOCALAPPDATA` on
    /// Windows) is a fresh temporary directory unless `env` sets it, so no
    /// test window ever reaches the real one or a running agent.
    pub fn spawn(
        program: &str,
        args: &[&str],
        env: &[(&str, &str)],
        cols: u16,
        rows: u16,
    ) -> Harness {
        let pair = native_pty_system()
            .openpty(PtySize {
                rows,
                cols,
                pixel_width: 0,
                pixel_height: 0,
            })
            .expect("openpty");
        let mut cmd = CommandBuilder::new(program);
        cmd.args(args);
        cmd.cwd(std::env::temp_dir());
        for name in [
            "SHELLX_TERM",
            "SHELLX",
            "TMUX",
            "STY",
            "SHELLX_TERM_FAULT",
            "TERM_PROGRAM",
            "WT_SESSION",
        ] {
            cmd.env_remove(name);
        }
        cmd.env("PS1", "$ ");
        cmd.env("ENV", "");
        cmd.env("TERM", "xterm-256color");
        for (key, value) in env {
            cmd.env(key, value);
        }
        let base = if env.iter().any(|(key, _)| *key == ENDPOINT_BASE_VAR) {
            None
        } else {
            static NEXT: AtomicUsize = AtomicUsize::new(0);
            let n = NEXT.fetch_add(1, Ordering::SeqCst);
            let dir = temp_dir(&format!("window-home-{n}"));
            cmd.env(ENDPOINT_BASE_VAR, &*dir);
            Some(dir)
        };
        let child = pair.slave.spawn_command(cmd).expect("spawn");
        drop(pair.slave);
        let mut reader = pair.master.try_clone_reader().expect("reader");
        let writer = Arc::new(Mutex::new(pair.master.take_writer().expect("writer")));
        let (tx, rx) = channel();
        let stop_reader = Arc::new(AtomicBool::new(false));
        let stop = stop_reader.clone();
        #[cfg(unix)]
        let master_fd = pair.master.as_raw_fd().expect("master fd");
        #[cfg(unix)]
        let reader_thread = std::thread::spawn(move || {
            let mut buf = [0u8; 16384];
            // Poll with a timeout instead of a blocking read, so
            // `close_window` can make this thread let go of its descriptor.
            while !stop.load(Ordering::SeqCst) {
                let mut pfd = libc::pollfd {
                    fd: master_fd,
                    events: libc::POLLIN,
                    revents: 0,
                };
                if unsafe { libc::poll(&mut pfd, 1, 50) } <= 0 || pfd.revents & libc::POLLNVAL != 0
                {
                    continue;
                }
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
        Harness {
            master: Some(pair.master),
            writer: Some(writer),
            stop_reader,
            reader_thread: Some(reader_thread),
            rx,
            output: Vec::new(),
            child,
            _base: base,
        }
    }

    /// `shellx-term wrap -- /bin/sh` in an 80x24 window.
    pub fn wrap_sh(env: &[(&str, &str)]) -> Harness {
        Harness::spawn(BIN, &["wrap", "--", "/bin/sh"], env, 80, 24)
    }

    pub fn send(&mut self, text: &str) {
        self.send_bytes(text.as_bytes());
    }

    pub fn send_bytes(&mut self, bytes: &[u8]) {
        let mut writer = self
            .writer
            .as_ref()
            .expect("window is open")
            .lock()
            .unwrap();
        writer.write_all(bytes).expect("write to window");
        writer.flush().expect("flush window");
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

    /// Collects whatever the window shows for `duration` (`text()` only
    /// sees output that was pumped).
    pub fn settle(&mut self, duration: Duration) {
        let until = Instant::now() + duration;
        while self.pump(until) {}
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
                panic!(
                    "no number after {prefix:?} within {timeout:?}; output so far: {:?}",
                    self.text()
                );
            }
        }
    }

    pub fn resize(&self, cols: u16, rows: u16) {
        self.master
            .as_ref()
            .expect("window is open")
            .resize(PtySize {
                rows,
                cols,
                pixel_width: 0,
                pixel_height: 0,
            })
            .expect("resize");
    }

    /// The window goes away the way it does when its app is killed: every
    /// descriptor on the master side is closed. The kernel then hangs up
    /// the window's session (SIGHUP to its foreground group, which a program
    /// may ignore) and reads on the slave side fail.
    pub fn close_window(&mut self) {
        self.stop_reader.store(true, Ordering::SeqCst);
        drop(self.writer.take());
        drop(self.master.take());
        if let Some(thread) = self.reader_thread.take() {
            thread.join().expect("reader thread");
        }
    }

    /// PID of the program running in the window.
    pub fn pid(&self) -> i32 {
        self.child.process_id().expect("pid") as i32
    }

    /// Waits for the program to exit; returns its code (128 + n for signal n
    /// on Unix).
    pub fn wait_exit(&mut self, timeout: Duration) -> i32 {
        let until = Instant::now() + timeout;
        loop {
            if let Some(code) = self.exited() {
                let drain_until = Instant::now() + Duration::from_millis(300);
                while self.pump(drain_until) {}
                return code;
            }
            assert!(
                Instant::now() < until,
                "process did not exit; output so far: {:?}",
                self.text()
            );
            if !self.pump(Instant::now() + Duration::from_millis(50)) {
                std::thread::sleep(Duration::from_millis(10));
            }
        }
    }

    /// The exit code if the program has exited (128 + n for signal n on Unix).
    #[cfg(unix)]
    fn exited(&mut self) -> Option<i32> {
        // Not `use`-ing `Downcast`: the call must resolve on the trait object.
        let child = self
            .child
            .as_any_mut()
            .downcast_mut::<std::process::Child>()
            .expect("portable-pty spawns std::process::Child on Unix");
        child.try_wait().expect("try_wait").map(|status| {
            status
                .code()
                .unwrap_or_else(|| 128 + status.signal().unwrap_or(0))
        })
    }

    #[cfg(windows)]
    fn exited(&mut self) -> Option<i32> {
        self.child
            .try_wait()
            .expect("try_wait")
            .map(|status| status.exit_code() as i32)
    }
}

fn find(haystack: &[u8], needle: &[u8]) -> Option<usize> {
    if needle.is_empty() {
        return Some(0);
    }
    haystack
        .windows(needle.len())
        .position(|window| window == needle)
}

/// `child.wait()` with a deadline; kills the child and panics on timeout.
pub fn wait_with_timeout(
    child: &mut std::process::Child,
    timeout: Duration,
) -> std::process::ExitStatus {
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

/// A fresh, empty directory for one test. It is removed when the guard
/// drops, except when the test is panicking (kept for debugging).
pub struct TempDir(PathBuf);

impl std::ops::Deref for TempDir {
    type Target = std::path::Path;
    fn deref(&self) -> &std::path::Path {
        &self.0
    }
}

impl AsRef<std::path::Path> for TempDir {
    fn as_ref(&self) -> &std::path::Path {
        &self.0
    }
}

impl Drop for TempDir {
    fn drop(&mut self) {
        if !std::thread::panicking() {
            let _ = std::fs::remove_dir_all(&self.0);
        }
    }
}

pub fn temp_dir(name: &str) -> TempDir {
    let dir = std::env::temp_dir().join(format!("shellx-term-test-{}-{name}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).expect("create temp dir");
    TempDir(dir)
}

/// `before` and `after` (saved with `stty -g`) must match. The kernel's
/// transient PENDIN flag (0x20000000 in lflag; "input is being retyped")
/// comes and goes with the shell's own prompt handling, so it is ignored.
/// Relies on macOS `stty -g` output (an `lflag=<hex>` field).
pub fn assert_same_modes(dir: &std::path::Path) {
    fn read(dir: &std::path::Path, name: &str) -> String {
        let text = std::fs::read_to_string(dir.join(name)).unwrap();
        let mut fields: Vec<String> = text.trim().split(':').map(String::from).collect();
        for field in &mut fields {
            if let Some(hex) = field.strip_prefix("lflag=") {
                let bits = u64::from_str_radix(hex, 16).unwrap() & !0x2000_0000;
                *field = format!("lflag={bits:x}");
            }
        }
        fields.join(":")
    }
    assert_eq!(read(dir, "before"), read(dir, "after"));
}
pub mod fake_agent;
