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
        ] {
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
        Harness {
            master: pair.master,
            writer,
            rx,
            output: Vec::new(),
            child,
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
                panic!(
                    "no number after {prefix:?} within {timeout:?}; output so far: {:?}",
                    self.text()
                );
            }
        }
    }

    pub fn resize(&self, cols: u16, rows: u16) {
        self.master
            .resize(PtySize {
                rows,
                cols,
                pixel_width: 0,
                pixel_height: 0,
            })
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
                return status
                    .code()
                    .unwrap_or_else(|| 128 + status.signal().unwrap_or(0));
            }
            assert!(
                Instant::now() < until,
                "process did not exit; output so far: {:?}",
                self.text()
            );
            let _ = self.pump(Instant::now() + Duration::from_millis(50));
        }
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

/// A fresh, empty directory for one test.
pub fn temp_dir(name: &str) -> PathBuf {
    let dir = std::env::temp_dir().join(format!("shellx-term-test-{}-{name}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).expect("create temp dir");
    dir
}
