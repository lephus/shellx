//! The local byte link: a ConPTY (via cmux-pty / portable-pty) running a
//! shell. `TermCore` talks to it only through `PtyLink`.

use std::io::{Read, Write};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};

use anyhow::{Context as _, Result};
use cmux_pty::{Child, MasterPty, PtyCommand, PtySize};

use crate::term_core::PtyLink;

pub struct LocalPty {
    writer: Mutex<Box<dyn Write + Send>>,
    master: Mutex<Box<dyn MasterPty + Send>>,
    child: Mutex<Box<dyn Child + Send + Sync>>,
    write_failed: AtomicBool,
}

impl LocalPty {
    pub fn spawn(
        program: &str,
        args: &[&str],
        cols: u16,
        rows: u16,
    ) -> Result<(Arc<LocalPty>, Box<dyn Read + Send>)> {
        let size = PtySize {
            rows,
            cols,
            pixel_width: 0,
            pixel_height: 0,
        };
        let pair = cmux_pty::open(size).context("failed to open the pseudoconsole")?;
        let mut command = PtyCommand::new(program);
        command.args(args.iter().copied());
        command.env("TERM", "xterm-256color");
        command.env("COLORTERM", "truecolor");
        if let Some(home) = std::env::var_os("USERPROFILE").or_else(|| std::env::var_os("HOME")) {
            command.cwd(std::path::PathBuf::from(home));
        }
        let spawned = pair
            .spawn(command)
            .with_context(|| format!("failed to start {program}"))?;
        let reader = spawned
            .master
            .try_clone_reader()
            .context("failed to clone PTY reader")?;
        let writer = spawned
            .master
            .take_writer()
            .context("failed to take PTY writer")?;
        let link = Arc::new(LocalPty {
            writer: Mutex::new(writer),
            master: Mutex::new(spawned.master),
            child: Mutex::new(spawned.child),
            write_failed: AtomicBool::new(false),
        });
        Ok((link, reader))
    }
}

impl PtyLink for LocalPty {
    fn write(&self, bytes: &[u8]) {
        if let Ok(mut writer) = self.writer.lock() {
            let ok = writer.write_all(bytes).and_then(|()| writer.flush()).is_ok();
            if !ok {
                self.write_failed.store(true, Ordering::Relaxed);
            }
        }
    }

    fn resize(&self, cols: u16, rows: u16, cell_w_px: u32, cell_h_px: u32) -> Result<()> {
        let master = self
            .master
            .lock()
            .map_err(|_| anyhow::anyhow!("pty master lock poisoned"))?;
        master
            .resize(PtySize {
                rows,
                cols,
                pixel_width: (u32::from(cols) * cell_w_px).min(u32::from(u16::MAX)) as u16,
                pixel_height: (u32::from(rows) * cell_h_px).min(u32::from(u16::MAX)) as u16,
            })
            .context("ConPTY resize failed")
    }

    /// True once the child exited or a write failed. ConPTY keeps its output
    /// pipe open after the shell exits, so the reader alone cannot tell.
    fn is_closed(&self) -> bool {
        if self.write_failed.load(Ordering::Relaxed) {
            return true;
        }
        match self.child.lock() {
            Ok(mut child) => matches!(child.try_wait(), Ok(Some(_))),
            Err(_) => true,
        }
    }
}

impl Drop for LocalPty {
    fn drop(&mut self) {
        if let Ok(mut child) = self.child.lock() {
            let _ = child.kill();
        }
    }
}

/// Pump PTY output on a dedicated thread. `sink` returns false to stop.
pub fn spawn_reader(
    mut reader: Box<dyn Read + Send>,
    mut sink: impl FnMut(Vec<u8>) -> bool + Send + 'static,
) {
    std::thread::Builder::new()
        .name("pty-reader".into())
        .spawn(move || {
            let mut buf = vec![0u8; 64 * 1024];
            loop {
                match reader.read(&mut buf) {
                    Ok(0) | Err(_) => break,
                    Ok(n) => {
                        if !sink(buf[..n].to_vec()) {
                            break;
                        }
                    }
                }
            }
        })
        .expect("failed to spawn the PTY reader thread");
}

/// PowerShell on Windows (override with SHELLX_SHELL), sh elsewhere.
pub fn default_shell() -> (String, Vec<&'static str>) {
    if let Ok(shell) = std::env::var("SHELLX_SHELL")
        && !shell.trim().is_empty()
    {
        return (shell, Vec::new());
    }
    if cfg!(windows) {
        ("powershell.exe".to_string(), vec!["-NoLogo"])
    } else {
        ("/bin/sh".to_string(), Vec::new())
    }
}
