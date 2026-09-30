//! `shellx-term`: wraps an interactive shell so ShellX can share the
//! terminal with a paired phone.
//! Spec: docs/superpowers/specs/2026-10-01-desktop-terminal-sharing-design.md

mod cli;
#[cfg(unix)]
mod fallback;
#[cfg(unix)]
mod faults;
#[cfg(unix)]
mod tty;
#[cfg(unix)]
mod wrap;

#[cfg(unix)]
fn main() {
    let command = cli::parse(std::env::args_os().skip(1));
    let target = fallback::Target::for_command(&command);
    match command {
        cli::Command::Version => println!("shellx-term {}", env!("CARGO_PKG_VERSION")),
        cli::Command::Invalid => fallback::exec_shell(&target),
        cli::Command::Wrap(args) => match wrap::run(&args) {
            Ok(code) => std::process::exit(code),
            Err(error) => {
                if let Some(notice) = error.notice() {
                    eprintln!("{notice}");
                }
                fallback::exec_shell(&target)
            }
        },
    }
}

#[cfg(not(unix))]
fn main() {
    // Windows arrives in plan P2 (spec §5.3). 222 tells the PowerShell block
    // "could not wrap, carry on".
    std::process::exit(222);
}
