//! `shellx` — the ShellX command line (A7 spec:
//! docs/superpowers/specs/2026-10-07-desktop-cli-a7-design.md). Talks to the
//! ShellX window (or the A5b daemon) over the local mux socket. Separate
//! from `proto`, which is the terminal-sharing link and must not change.

pub mod args;
pub mod client;
pub mod endpoint;
pub mod value;
pub mod wire;

/// Entry point of the `shellx` command. Returns the exit code (D10).
pub fn main(args: Vec<std::ffi::OsString>) -> i32 {
    use std::io::Write;
    let args: Vec<String> = match args.into_iter().map(|a| a.into_string()).collect() {
        Ok(a) => a,
        Err(_) => {
            let _ = writeln!(
                std::io::stderr(),
                "shellx: arguments must be valid UTF-8 (usage)"
            );
            return 2;
        }
    };
    match args::parse(&args) {
        Err(msg) => {
            let _ = writeln!(std::io::stderr(), "shellx: {msg} (usage)");
            2
        }
        Ok(args::Invocation::Help(spec)) => {
            let _ = write!(std::io::stdout(), "{}", args::help_text(spec));
            0
        }
        Ok(args::Invocation::HelpGroup(g)) => {
            let _ = write!(
                std::io::stdout(),
                "{}",
                args::group_help(g).unwrap_or_default()
            );
            0
        }
        Ok(args::Invocation::Version) => {
            let _ = writeln!(
                std::io::stdout(),
                "shellx {} (api 1)",
                env!("CARGO_PKG_VERSION")
            );
            0
        }
        Ok(args::Invocation::Completions(sh)) => match args::completion_script(&sh) {
            Some(s) => {
                let _ = write!(std::io::stdout(), "{s}");
                0
            }
            None => {
                let _ = writeln!(
                    std::io::stderr(),
                    "shellx: completions for zsh, bash or pwsh"
                );
                2
            }
        },
        Ok(args::Invocation::Run(_)) => {
            let _ = writeln!(
                std::io::stderr(),
                "shellx: ShellX is not running (open ShellX and try again)"
            );
            3
        }
    }
}
