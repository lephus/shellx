//! ShellX desktop for Windows: a native GPUI window drawing a libghostty-vt
//! grid fed by ConPTY. Keyboard text and IME composition come through GPUI's
//! `EntityInputHandler`, so a Vietnamese Telex preedit is drawn inline and
//! only committed text reaches the PTY. `--smoke` runs the same session
//! headless and exits; `--version` prints the version and exits.
#![cfg_attr(all(windows, not(debug_assertions)), windows_subsystem = "windows")]

mod session;
mod smoke;

#[cfg(windows)]
mod app;

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();

    if args.iter().any(|arg| arg == "--version") {
        println!("shellx-desktop {}", shellx_model::VERSION);
        std::process::exit(0);
    }

    if args.iter().any(|arg| arg == "--smoke") {
        match smoke::run() {
            Ok(()) => std::process::exit(0),
            Err(error) => {
                eprintln!("smoke: FAIL: {error:#}");
                std::process::exit(1);
            }
        }
    }

    #[cfg(windows)]
    app::run();

    #[cfg(not(windows))]
    {
        eprintln!("the window is Windows-only; use --smoke to exercise the session");
        std::process::exit(2);
    }
}
