//! Last resort: replace this process with a plain shell (spec §5.4 item 2).
//!
//! On macOS the ShellX block `exec`s the window's shell into `shellx-term`,
//! so `shellx-term` *is* the window's process: exiting early would close the
//! window. Every path that cannot wrap ends here instead.

use crate::cli::Command;
use std::ffi::{OsStr, OsString};
use std::os::unix::process::CommandExt;
use std::path::Path;

/// What to start when wrapping is impossible.
#[derive(Debug, Clone, Default)]
pub struct Target {
    pub shell: Option<OsString>,
    pub login: bool,
    pub args: Vec<OsString>,
}

impl Target {
    pub fn for_command(command: &Command) -> Target {
        match command {
            Command::Wrap(wrap) => Target {
                shell: Some(wrap.shell.clone()),
                login: wrap.login,
                args: wrap.shell_args.clone(),
            },
            _ => Target::default(),
        }
    }
}

/// Shells to try, in order: the requested one, `$SHELL`, `/bin/zsh`,
/// `/bin/sh`. Absolute paths only, no duplicates.
pub fn candidates(requested: Option<&OsStr>, shell_env: Option<&OsStr>) -> Vec<OsString> {
    let fixed = [Some(OsStr::new("/bin/zsh")), Some(OsStr::new("/bin/sh"))];
    let mut out: Vec<OsString> = Vec::new();
    for candidate in [requested, shell_env].into_iter().chain(fixed).flatten() {
        if Path::new(candidate).is_absolute() && !out.iter().any(|seen| seen == candidate) {
            out.push(candidate.to_os_string());
        }
    }
    out
}

/// `argv[0]` for `shell`: `-zsh` for a login shell, as login(1) does.
pub fn arg0(shell: &OsStr, login: bool) -> OsString {
    let name = Path::new(shell).file_name().unwrap_or(shell);
    if login {
        let mut dashed = OsString::from("-");
        dashed.push(name);
        dashed
    } else {
        name.to_os_string()
    }
}

/// Replaces this process with the first shell that starts. `SHELLX_TERM` is
/// set to the window's own tty (`0` without one): the ShellX block in that
/// shell's startup file sees it is already in its window and does not send
/// it back here.
pub fn exec_shell(target: &Target) -> ! {
    let shell_env = std::env::var_os("SHELL");
    for shell in candidates(target.shell.as_deref(), shell_env.as_deref()) {
        let args: &[OsString] = if target.shell.as_ref() == Some(&shell) {
            &target.args
        } else {
            &[]
        };
        // `exec` only returns on failure: try the next candidate.
        let _error = std::process::Command::new(&shell)
            .arg0(arg0(&shell, target.login))
            .args(args)
            .env("SHELLX_TERM", own_tty())
            // The block's hand-over variables: the new shell must not see
            // them (SHELLX_TERM_LOGIN stays, the zsh block reads it).
            .env_remove("SHELLX_TERM_WRAP")
            .env_remove("SHELLX_TERM_WRAP_LOGIN")
            .exec();
    }
    std::process::exit(127)
}

/// The window's tty, so the ShellX block in the new shell sees it is
/// already in its own window and does not wrap again; "0" without a tty.
fn own_tty() -> OsString {
    use std::os::unix::ffi::OsStrExt;
    let mut buf = [0 as libc::c_char; 256];
    let ok = unsafe { libc::ttyname_r(0, buf.as_mut_ptr(), buf.len()) } == 0;
    if !ok {
        return OsString::from("0");
    }
    let name = unsafe { std::ffi::CStr::from_ptr(buf.as_ptr()) };
    OsStr::from_bytes(name.to_bytes()).to_os_string()
}

/// Marks every descriptor above stderr close-on-exec, so a shell started
/// from the panic hook does not keep the old PTY open (the old inner shell
/// then gets its hang-up).
pub fn close_on_exec_above_stderr() {
    let max = unsafe { libc::sysconf(libc::_SC_OPEN_MAX) }.clamp(0, 4096) as i32;
    for fd in 3..max {
        unsafe { libc::fcntl(fd, libc::F_SETFD, libc::FD_CLOEXEC) };
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::cli::{Command, WrapArgs};
    use std::ffi::{OsStr, OsString};

    #[test]
    fn candidates_in_order_without_duplicates_or_relative_paths() {
        assert_eq!(
            candidates(
                Some(OsStr::new("/opt/homebrew/bin/zsh")),
                Some(OsStr::new("/bin/zsh"))
            ),
            vec![
                OsString::from("/opt/homebrew/bin/zsh"),
                OsString::from("/bin/zsh"),
                OsString::from("/bin/sh"),
            ]
        );
        assert_eq!(
            candidates(None, Some(OsStr::new("zsh"))),
            vec![OsString::from("/bin/zsh"), OsString::from("/bin/sh")]
        );
    }

    #[test]
    fn arg0_marks_login_shells_with_a_dash() {
        assert_eq!(arg0(OsStr::new("/bin/zsh"), true), OsString::from("-zsh"));
        assert_eq!(arg0(OsStr::new("/bin/zsh"), false), OsString::from("zsh"));
    }

    #[test]
    fn target_keeps_what_wrap_asked_for() {
        let target = Target::for_command(&Command::Wrap(WrapArgs {
            login: true,
            shell: "/bin/bash".into(),
            shell_args: vec!["-x".into()],
            from_block: false,
        }));
        assert_eq!(target.shell, Some(OsString::from("/bin/bash")));
        assert!(target.login);
        assert_eq!(target.args, vec![OsString::from("-x")]);
        let invalid = Target::for_command(&Command::Invalid);
        assert_eq!(invalid.shell, None);
        assert!(!invalid.login);
    }
}
