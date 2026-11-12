//! The local byte link: a ConPTY (via cmux-pty / portable-pty) running a
//! shell. `TermCore` talks to it only through `PtyLink`. Which shell, and the
//! one to try instead: `settings` and `PanePlan`.

use std::io::{Read, Write};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};

use anyhow::{Context as _, Result};
use cmux_pty::{Child, MasterPty, PtyCommand, PtySize};
use shellx_model::shell::{
    LaunchPlan, ShellKind, ShellLaunch, ShellProbe, is_absolute, known_launch, launch_label,
};

use crate::term_core::PtyLink;

pub mod settings;

pub struct LocalPty {
    writer: Mutex<Box<dyn Write + Send>>,
    master: Mutex<Box<dyn MasterPty + Send>>,
    child: SharedChild,
    write_failed: AtomicBool,
}

type SharedChild = Arc<Mutex<Box<dyn Child + Send + Sync>>>;

/// Watches a pane's shell after its `LocalPty` is gone: dropping the link
/// kills the child, and `exited()` confirms it (`--smoke` pane checks).
#[derive(Clone)]
pub struct ExitProbe(SharedChild);

impl ExitProbe {
    pub fn exited(&self) -> bool {
        match self.0.lock() {
            Ok(mut child) => matches!(child.try_wait(), Ok(Some(_))),
            Err(_) => true,
        }
    }
}

impl LocalPty {
    pub fn spawn(
        program: &str,
        args: &[&str],
        env: &[(&str, &str)],
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
        for (key, value) in env {
            command.env(*key, *value);
        }
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
            child: Arc::new(Mutex::new(spawned.child)),
            write_failed: AtomicBool::new(false),
        });
        Ok((link, reader))
    }

    pub fn exit_probe(&self) -> ExitProbe {
        ExitProbe(self.child.clone())
    }
}

impl PtyLink for LocalPty {
    fn write(&self, bytes: &[u8]) {
        if let Ok(mut writer) = self.writer.lock() {
            let ok = writer
                .write_all(bytes)
                .and_then(|()| writer.flush())
                .is_ok();
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

/// What to run in a new local pane.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ShellCmd {
    pub program: String,
    pub args: Vec<String>,
    pub env: Vec<(String, String)>,
    /// The name a person knows it by: "PowerShell 7", or a custom line's file ("bash.exe").
    pub label: String,
    /// `None`: a custom command line, `SHELLX_SHELL`, or the Mac's bash.
    pub kind: Option<ShellKind>,
}

impl ShellCmd {
    /// A catalogue entry or a custom line as given (PowerShell's arguments carry the OSC 7
    /// prompt hook); no extra environment.
    pub fn from_launch(l: &ShellLaunch) -> ShellCmd {
        ShellCmd {
            program: l.program.clone(),
            args: l.args.clone(),
            env: Vec::new(),
            label: launch_label(l),
            kind: l.kind,
        }
    }

    /// `args` with `extra` added. PowerShell's `-Command` takes everything
    /// after it as the script, so `extra` goes before that flag.
    fn args_with(&self, extra: &[&str]) -> Vec<String> {
        let at = self
            .args
            .iter()
            .position(|a| a == "-Command")
            .unwrap_or(self.args.len());
        let mut args = self.args.clone();
        args.splice(at..at, extra.iter().map(|a| a.to_string()));
        args
    }

    /// Starts this shell with `extra_args` on a `cols` x `rows` pseudoconsole.
    pub fn spawn(
        &self,
        extra_args: &[&str],
        cols: u16,
        rows: u16,
    ) -> Result<(Arc<LocalPty>, Box<dyn Read + Send>)> {
        let args = self.args_with(extra_args);
        let args: Vec<&str> = args.iter().map(String::as_str).collect();
        let env: Vec<(&str, &str)> = self
            .env
            .iter()
            .map(|(key, value)| (key.as_str(), value.as_str()))
            .collect();
        LocalPty::spawn(&self.program, &args, &env, cols, rows)
    }
}

/// What a new pane starts, and the one shell it starts instead when that program cannot be
/// started (Ruling 15: a shell that starts and exits is `RespawnGuard`'s).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PanePlan {
    pub first: ShellCmd,
    pub fallback: Option<ShellCmd>,
}

impl PanePlan {
    pub fn from_plan(plan: &LaunchPlan) -> PanePlan {
        PanePlan {
            first: ShellCmd::from_launch(&plan.first),
            fallback: plan.fallback.as_ref().map(ShellCmd::from_launch),
        }
    }
}

/// bash (the macOS dev harness): the same OSC 7 before every prompt.
const BASH_PROMPT_COMMAND: &str = r#"printf '\033]7;file://%s%s\033\\' "$HOSTNAME" "$PWD""#;

/// The macOS development harness's shell (Ruling 19): bash with the OSC 7
/// `PROMPT_COMMAND`, or `override_shell` (`SHELLX_SHELL`): that program, no
/// arguments, no environment.
pub(crate) fn dev_bash(override_shell: Option<&str>) -> ShellCmd {
    if let Some(shell) = override_shell.filter(|s| !s.trim().is_empty()) {
        return ShellCmd::from_launch(&ShellLaunch {
            kind: None,
            program: shell.to_string(),
            args: Vec::new(),
            osc7_hook: false,
        });
    }
    ShellCmd {
        program: "/bin/bash".to_string(),
        args: ["--noprofile", "--norc", "-i"].map(String::from).to_vec(),
        env: vec![(
            "PROMPT_COMMAND".to_string(),
            BASH_PROMPT_COMMAND.to_string(),
        )],
        label: "bash".to_string(),
        kind: None,
    }
}

/// What a new tab starts first (`--smoke` runs it): the first shell of
/// `shells().plan_for_new_pane()`, or Windows PowerShell by its System32
/// path when the plan is an error. On the Mac: bash.
pub fn default_shell() -> ShellCmd {
    let shells = settings::shells();
    match shells.plan_for_new_pane() {
        Ok(plan) => plan.first,
        Err(_) => settings::startup_plan(&shells.probe()).first,
    }
}

/// Command Prompt, for a pane whose shell cannot start: the catalogue's, as
/// cached by the last lookup. On the Mac: `/bin/sh -i`.
pub fn command_prompt() -> ShellCmd {
    if cfg!(windows) {
        let shells = settings::shells();
        command_prompt_for(&shells.snapshot().found, &shells.probe())
    } else {
        ShellCmd {
            program: "/bin/sh".to_string(),
            args: vec!["-i".to_string()],
            env: Vec::new(),
            label: "sh".to_string(),
            kind: None,
        }
    }
}

/// The catalogue's Command Prompt, else `%ComSpec%` when it is an absolute
/// path, else `%SystemRoot%\System32\cmd.exe` (`C:\Windows` when SystemRoot
/// is not absolute). No file is checked: CreateProcess says when it is missing.
pub fn command_prompt_for(found: &[ShellLaunch], probe: &ShellProbe) -> ShellCmd {
    if let Some(cmd) = found.iter().find(|l| l.kind == Some(ShellKind::Cmd)) {
        return ShellCmd::from_launch(cmd);
    }
    let program = probe
        .comspec
        .as_deref()
        .map(str::trim)
        .filter(|c| is_absolute(c))
        .map(String::from)
        .unwrap_or_else(|| format!(r"{}\System32\cmd.exe", settings::system_root(probe)));
    ShellCmd::from_launch(&known_launch(ShellKind::Cmd, program))
}

#[cfg(test)]
mod tests {
    use super::*;
    use shellx_model::shell::POWERSHELL_PROMPT_HOOK;

    /// Themes (oh-my-posh, starship) read `$?` first in their prompt, so the
    /// wrapper must call the original before it runs any statement of its own.
    /// (The hook now comes with the model's PowerShell launch arguments.)
    #[test]
    fn powershell_hook_runs_the_users_prompt_first() {
        let (_, wrapped) = POWERSHELL_PROMPT_HOOK
            .split_once("function global:prompt { ")
            .unwrap();
        assert!(
            wrapped.starts_with("$p = & $__shellxPrompt; "),
            "the wrapped prompt must start with the original call: {wrapped}"
        );
        // OSC 7 is written after it, and the original's string is the result.
        let called = wrapped.find("$p = &").unwrap();
        let osc7 = wrapped.find("]7;file://").unwrap();
        assert!(called < osc7);
        assert!(wrapped.contains("}; $p }"));
        // Without a prompt function the fallback still reports the directory.
        let (_, fallback) = POWERSHELL_PROMPT_HOOK.split_once("} else { ").unwrap();
        assert!(fallback.contains("]7;file://") && fallback.contains("\"PS $($l.Path)> \""));
    }

    /// The dev-harness bash end to end: `cd` makes the prompt hook write an
    /// OSC 7 URL that the terminal keeps and `cwd_from_osc7` reads back.
    #[cfg(unix)]
    #[test]
    fn bash_reports_the_directory_after_cd() {
        use std::sync::mpsc;
        use std::time::{Duration, Instant};

        use crate::cwd::cwd_from_osc7;
        use crate::term_core::TermCore;

        let tmp = tempfile::tempdir().unwrap();
        let dir = std::fs::canonicalize(tmp.path()).unwrap();
        let (link, reader) = dev_bash(None).spawn(&[], 80, 24).unwrap();
        let (tx, rx) = mpsc::channel();
        spawn_reader(reader, move |bytes| tx.send(bytes).is_ok());
        let mut core = TermCore::new(link.clone(), 80, 24).unwrap();

        link.write(format!("cd '{}'\n", dir.display()).as_bytes());
        let deadline = Instant::now() + Duration::from_secs(10);
        let want = Some(dir.display().to_string());
        while core.pwd().as_deref().and_then(cwd_from_osc7) != want {
            assert!(
                Instant::now() < deadline,
                "no OSC 7 for {dir:?}: {:?}",
                core.pwd()
            );
            if let Ok(bytes) = rx.recv_timeout(Duration::from_millis(100)) {
                core.feed(&bytes);
            }
        }
    }

    #[test]
    fn the_mac_shellx_shell_overrides_without_args_or_env() {
        let shell = dev_bash(Some("/opt/homebrew/bin/nu"));
        assert_eq!(shell.program, "/opt/homebrew/bin/nu");
        assert!(shell.args.is_empty() && shell.env.is_empty());
        assert_eq!(shell.label, "nu");
        // A blank override is no override.
        assert_eq!(dev_bash(Some("  ")).program, "/bin/bash");
    }

    #[test]
    fn extra_args_go_before_the_command_script() {
        let shell = ShellCmd {
            program: "powershell.exe".into(),
            args: ["-NoLogo", "-NoExit", "-Command", "script"]
                .map(String::from)
                .to_vec(),
            env: Vec::new(),
            label: "Windows PowerShell".into(),
            kind: Some(ShellKind::WindowsPowerShell),
        };
        assert_eq!(
            shell.args_with(&["-NoProfile"]),
            ["-NoLogo", "-NoExit", "-NoProfile", "-Command", "script"]
        );
        let bash = dev_bash(Some("/bin/zsh"));
        assert_eq!(bash.args_with(&["-x"]), ["-x"]);
    }
}
