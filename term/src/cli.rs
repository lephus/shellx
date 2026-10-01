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
}

#[derive(Debug, PartialEq, Eq)]
pub enum Command {
    Wrap(WrapArgs),
    Version,
    /// Anything else. `main` never refuses the user a shell: it falls back
    /// to a plain one for this.
    Invalid,
}

/// Parses the arguments after the program name.
pub fn parse<I: IntoIterator<Item = OsString>>(args: I) -> Command {
    let mut args = args.into_iter();
    match args.next() {
        Some(first) if first == "--version" => match args.next() {
            None => Command::Version,
            Some(_) => Command::Invalid,
        },
        Some(first) if first == "wrap" => parse_wrap(args),
        _ => Command::Invalid,
    }
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
        })
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
            &[][..],
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
