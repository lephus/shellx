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
    use std::sync::OnceLock;
    static TARGET: OnceLock<fallback::Target> = OnceLock::new();

    let command = cli::parse(std::env::args_os().skip(1));
    let target = TARGET.get_or_init(|| fallback::Target::for_command(&command));
    // A bug must never cost the user their terminal: restore the window and
    // replace this process with a plain shell.
    std::panic::set_hook(Box::new(|info| {
        tty::restore_saved();
        use std::io::Write;
        // Never `eprint!`: it panics if stderr is gone, and a panic inside
        // the hook aborts without starting a shell.
        let _ = write!(
            std::io::stderr(),
            "\r\nshellx-term: internal error ({info}); starting a plain shell\r\n"
        );
        fallback::close_on_exec_above_stderr();
        match TARGET.get() {
            Some(target) => fallback::exec_shell(target),
            None => fallback::exec_shell(&fallback::Target::default()),
        }
    }));
    match command {
        cli::Command::Version => println!("shellx-term {}", env!("CARGO_PKG_VERSION")),
        cli::Command::Invalid => fallback::exec_shell(target),
        cli::Command::Wrap(args) => match wrap::run(&args) {
            Ok(code) => std::process::exit(code),
            Err(error) => {
                if let Some(notice) = error.notice() {
                    eprintln!("{notice}");
                }
                fallback::exec_shell(target)
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
