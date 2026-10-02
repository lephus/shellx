//! `shellx-term`: wraps an interactive shell so ShellX can share the
//! terminal with a paired phone.
//! Spec: docs/superpowers/specs/2026-10-01-desktop-terminal-sharing-design.md

#[cfg(unix)]
use shellx_term::{cli, fallback, tty, wrap};

#[cfg(unix)]
fn main() {
    fallback::remember_sigterm();
    use std::sync::OnceLock;
    static TARGET: OnceLock<fallback::Target> = OnceLock::new();

    let command = cli::parse(std::env::args_os().skip(1));
    let target = TARGET.get_or_init(|| fallback::Target::for_command(&command));
    if matches!(command, cli::Command::Wrap(_)) {
        // Only `wrap` has a window to protect. A bug must never cost the
        // user their terminal: restore the window and replace this process
        // with a plain shell.
        std::panic::set_hook(Box::new(|info| {
            // A bug in the link thread only stops the link: the terminal
            // goes on. (Replacing the process here would close the PTY.)
            if shellx_term::link::is_link_thread() {
                return;
            }
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
    }
    match command {
        cli::Command::Version => {
            use std::io::Write;
            // No panic on a closed stdout: `--version` never starts a shell.
            let _ = writeln!(
                std::io::stdout(),
                "shellx-term {}",
                env!("CARGO_PKG_VERSION")
            );
        }
        cli::Command::Probe => {
            use std::io::Write;
            match cli::parent_executable() {
                Some(path) => {
                    let _ = writeln!(std::io::stdout(), "{}", path.display());
                }
                None => std::process::exit(1),
            }
        }
        cli::Command::Invalid => {
            // The block may be calling an older or newer binary: still give
            // the user a shell, and say why it is a plain one.
            use std::io::Write;
            let _ = writeln!(
                std::io::stderr(),
                "shellx-term: unknown arguments; starting a plain shell"
            );
            fallback::exec_shell(target)
        }
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

#[cfg(windows)]
fn main() {
    use shellx_term::{cli, link, wincon, winwrap};
    use std::io::Write;

    let command = cli::parse(std::env::args_os().skip(1));
    if matches!(command, cli::Command::Wrap(_)) {
        // A bug must never cost the user their window: put the console back
        // and exit 222 so the PowerShell profile carries on in the outer shell.
        std::panic::set_hook(Box::new(|info| {
            if link::is_link_thread() {
                return; // only the link dies; the terminal keeps running
            }
            wincon::restore_saved();
            let _ = write!(
                std::io::stderr(),
                "\r\nshellx-term: internal error ({info}); carrying on without sharing\r\n"
            );
            std::process::exit(winwrap::COULD_NOT_WRAP);
        }));
    }
    match command {
        cli::Command::Version => {
            let _ = writeln!(
                std::io::stdout(),
                "shellx-term {}",
                env!("CARGO_PKG_VERSION")
            );
        }
        cli::Command::Wrap(args) => match winwrap::run(&args) {
            Ok(code) => std::process::exit(code),
            Err(error) => {
                if let Some(notice) = error.notice() {
                    let _ = writeln!(std::io::stderr(), "{notice}");
                }
                std::process::exit(winwrap::COULD_NOT_WRAP);
            }
        },
        // `probe` serves the Unix blocks only.
        cli::Command::Probe | cli::Command::Invalid => {
            let _ = writeln!(
                std::io::stderr(),
                "shellx-term: unknown arguments; carrying on without sharing"
            );
            std::process::exit(winwrap::COULD_NOT_WRAP);
        }
    }
}

#[cfg(not(any(unix, windows)))]
fn main() {
    std::process::exit(222);
}
