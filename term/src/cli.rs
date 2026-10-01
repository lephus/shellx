//! Command line of `shellx-term` (spec §5.1).

use std::ffi::OsString;
use std::path::Path;

#[derive(Debug, PartialEq, Eq)]
pub struct WrapArgs {
    /// Start the inner shell as a login shell (`-l`).
    pub login: bool,
    /// Absolute path of the shell to run inside the PTY.
    pub shell: OsString,
    /// Extra arguments for the shell.
    pub shell_args: Vec<OsString>,
    /// Started by a ShellX block (no arguments, shell named in the
    /// environment): the window's shell has just been replaced by us, so we
    /// behave like the interactive shell we replace (ignore SIGTERM).
    pub from_block: bool,
}

#[derive(Debug, PartialEq, Eq)]
pub enum Command {
    Wrap(WrapArgs),
    Version,
    /// Print the parent process's executable path (used by the shell blocks).
    Probe,
    /// Anything else. `main` never refuses the user a shell: it falls back
    /// to a plain one for this.
    Invalid,
}

/// Parses the arguments after the program name, reading the environment.
pub fn parse<I: IntoIterator<Item = OsString>>(args: I) -> Command {
    parse_with_env(args, |k| std::env::var_os(k))
}

/// `parse` with an injectable environment (tests).
pub fn parse_with_env<I: IntoIterator<Item = OsString>>(
    args: I,
    get: impl Fn(&str) -> Option<OsString>,
) -> Command {
    let mut args = args.into_iter();
    match args.next() {
        // The blocks pass the shell through the environment so the
        // window's title shows the shell, not our arguments (spec §5.2).
        None => match get("SHELLX_TERM_WRAP") {
            Some(shell) if Path::new(&shell).is_absolute() => Command::Wrap(WrapArgs {
                login: get("SHELLX_TERM_WRAP_LOGIN").is_some_and(|v| v == "1"),
                shell,
                shell_args: Vec::new(),
                from_block: true,
            }),
            _ => Command::Invalid,
        },
        Some(first) if first == "--version" => match args.next() {
            None => Command::Version,
            Some(_) => Command::Invalid,
        },
        Some(first) if first == "probe" => match args.next() {
            None => Command::Probe,
            Some(_) => Command::Invalid,
        },
        Some(first) if first == "wrap" => parse_wrap(args),
        Some(_) => Command::Invalid,
    }
}

/// Executable of our parent process: the shell running the block (its
/// `$(...)` subshell is a fork of the same binary).
#[cfg(target_os = "macos")]
pub fn parent_executable() -> Option<std::path::PathBuf> {
    use std::os::unix::ffi::OsStringExt;
    let ppid = unsafe { libc::getppid() };
    let mut buf = vec![0u8; 4096];
    let n = unsafe { libc::proc_pidpath(ppid, buf.as_mut_ptr().cast(), buf.len() as u32) };
    if n <= 0 {
        return None;
    }
    buf.truncate(n as usize);
    Some(std::path::PathBuf::from(OsString::from_vec(buf)))
}

#[cfg(all(unix, not(target_os = "macos")))]
pub fn parent_executable() -> Option<std::path::PathBuf> {
    std::fs::read_link(format!("/proc/{}/exe", unsafe { libc::getppid() })).ok()
}

fn parse_wrap(mut args: impl Iterator<Item = OsString>) -> Command {
    let mut login = false;
    loop {
        match args.next() {
            Some(arg) if arg == "--login" && !login => login = true,
            Some(arg) if arg == "--" => break,
            _ => return Command::Invalid,
        }
    }
    let Some(shell) = args.next() else {
        return Command::Invalid;
    };
    if !Path::new(&shell).is_absolute() {
        return Command::Invalid;
    }
    Command::Wrap(WrapArgs {
        login,
        shell,
        shell_args: args.collect(),
        from_block: false,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    fn parse_strs(args: &[&str]) -> Command {
        parse(args.iter().map(OsString::from))
    }

    fn wrap(login: bool, shell: &str, shell_args: &[&str]) -> Command {
        Command::Wrap(WrapArgs {
            login,
            shell: shell.into(),
            shell_args: shell_args.iter().map(OsString::from).collect(),
            from_block: false,
        })
    }

    fn from_block(command: Command) -> Command {
        match command {
            Command::Wrap(args) => Command::Wrap(WrapArgs {
                from_block: true,
                ..args
            }),
            other => other,
        }
    }

    fn env_of(vars: &'static [(&'static str, &'static str)]) -> impl Fn(&str) -> Option<OsString> {
        move |k| {
            vars.iter()
                .find(|(name, _)| *name == k)
                .map(|(_, v)| OsString::from(v))
        }
    }

    #[test]
    fn no_arguments_wrap_the_shell_named_in_the_environment() {
        assert_eq!(
            parse_with_env(
                Vec::<OsString>::new(),
                env_of(&[
                    ("SHELLX_TERM_WRAP", "/bin/bash"),
                    ("SHELLX_TERM_WRAP_LOGIN", "1")
                ])
            ),
            from_block(wrap(true, "/bin/bash", &[]))
        );
        assert_eq!(
            parse_with_env(
                Vec::<OsString>::new(),
                env_of(&[("SHELLX_TERM_WRAP", "/bin/zsh")])
            ),
            from_block(wrap(false, "/bin/zsh", &[]))
        );
    }

    #[test]
    fn an_explicit_wrap_is_not_from_a_block() {
        // Even with the block's variable set, arguments mean an explicit call.
        assert_eq!(
            parse_with_env(
                ["wrap", "--", "/bin/zsh"].map(OsString::from),
                env_of(&[("SHELLX_TERM_WRAP", "/bin/bash")])
            ),
            wrap(false, "/bin/zsh", &[])
        );
    }

    #[test]
    fn no_arguments_without_a_valid_shell_are_invalid() {
        assert_eq!(
            parse_with_env(Vec::<OsString>::new(), env_of(&[])),
            Command::Invalid
        );
        assert_eq!(
            parse_with_env(
                Vec::<OsString>::new(),
                env_of(&[("SHELLX_TERM_WRAP", "zsh")])
            ),
            Command::Invalid
        );
    }

    #[test]
    fn probe() {
        assert_eq!(parse_strs(&["probe"]), Command::Probe);
        assert_eq!(parse_strs(&["probe", "x"]), Command::Invalid);
    }

    #[test]
    fn the_parent_executable_is_this_test_runner_s_parent() {
        let parent = parent_executable().expect("parent path");
        assert!(parent.is_absolute(), "{parent:?}");
    }

    #[test]
    fn wrap_with_a_shell() {
        assert_eq!(
            parse_strs(&["wrap", "--", "/bin/zsh"]),
            wrap(false, "/bin/zsh", &[])
        );
    }

    #[test]
    fn wrap_login_with_shell_arguments() {
        assert_eq!(
            parse_strs(&["wrap", "--login", "--", "/bin/bash", "-x"]),
            wrap(true, "/bin/bash", &["-x"])
        );
    }

    #[test]
    fn version() {
        assert_eq!(parse_strs(&["--version"]), Command::Version);
    }

    #[test]
    fn version_with_extra_arguments_is_invalid() {
        assert_eq!(parse_strs(&["--version", "x"]), Command::Invalid);
    }

    #[test]
    fn invalid_forms() {
        for args in [
            &["bogus"][..],
            &["wrap"][..],
            &["wrap", "/bin/zsh"][..],
            &["wrap", "--"][..],
            &["wrap", "--", "zsh"][..],
            &["wrap", "--nope", "--", "/bin/zsh"][..],
            &["wrap", "--login", "--login", "--", "/bin/zsh"][..],
        ] {
            assert_eq!(parse_strs(args), Command::Invalid, "{args:?}");
        }
    }
}
