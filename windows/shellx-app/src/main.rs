//! ShellX desktop for Windows: a native GPUI window drawing a libghostty-vt
//! grid fed by ConPTY. Keyboard text and IME composition come through GPUI's
//! `EntityInputHandler`, so a Vietnamese Telex preedit is drawn inline and
//! only committed text reaches the PTY. `--smoke` runs the same session
//! headless (after the `--smoke-ui-assets` checks) and exits;
//! `--smoke-ui-assets` checks the embedded icons and shell strings only;
//! `--smoke-panes` runs only the tabs/splits pane checks of `--smoke`;
//! `--version` prints the version and exits.
#![cfg_attr(all(windows, not(debug_assertions)), windows_subsystem = "windows")]

mod build_info;
mod core_bridge;
mod core_service;
mod crash;
#[cfg(windows)]
mod crash_native;
mod cwd;
mod fonts;
mod icons;
mod ime;
mod links_store;
mod local_pty;
mod logger;
mod os_info;
mod pairing_service;
mod paths;
mod remote_link;
mod remote_session;
mod remote_tabs;
mod shell_info;
mod smoke;
mod term_core;
mod workspace;

// The window also builds on macOS, for development screenshots only.
#[cfg(any(windows, target_os = "macos"))]
mod ui;

use std::path::PathBuf;

use shellx_model::crash_report::DialogKind;

fn main() {
    // `args_os`: `args()` panics on an argument that is not Unicode, before any hook exists;
    // the reporter's file stays an OsString (plan review M-22).
    let args: Vec<std::ffi::OsString> = std::env::args_os().skip(1).collect();
    let has = |flag: &str| args.iter().any(|arg| arg == flag);

    // The crash reporter: a separate process that only shows the dialog. Nothing else runs:
    // no hook, no log (3b §5 step 2).
    for kind in [DialogKind::Crash, DialogKind::WindowFailed] {
        if let Some(i) = args.iter().position(|arg| arg == kind.reporter_flag()) {
            let file = args.get(i + 1).map(PathBuf::from).unwrap_or_default();
            std::process::exit(crash::run_reporter(kind, &file));
        }
    }

    // Every panic from here on leaves a crash file; the window's also starts the reporter.
    let console = ["--version", "--smoke-ui-assets", "--smoke-panes", "--smoke"]
        .iter()
        .any(|flag| has(flag));
    let ctx = crash::CrashContext::this_process();
    let mode = if console {
        crash::HookMode::FileOnly
    } else {
        crash::HookMode::Dialog
    };
    crash::install_panic_hook(ctx.clone(), mode);
    crash::set_crash_test(crash::crash_test_from(&args));

    if has("--version") {
        println!("shellx-desktop {}", shellx_model::VERSION);
        std::process::exit(0);
    }

    if has("--smoke-ui-assets") {
        match smoke::ui_assets() {
            Ok(()) => std::process::exit(0),
            Err(error) => {
                eprintln!("smoke-ui-assets: FAIL: {error:#}");
                std::process::exit(1);
            }
        }
    }

    if has("--smoke-panes") {
        match smoke::panes() {
            Ok(()) => std::process::exit(0),
            Err(error) => {
                eprintln!("smoke-panes: FAIL: {error:#}");
                std::process::exit(1);
            }
        }
    }

    if has("--smoke") {
        match smoke::run() {
            Ok(()) => std::process::exit(0),
            Err(error) => {
                eprintln!("smoke: FAIL: {error:#}");
                std::process::exit(1);
            }
        }
    }

    #[cfg(any(windows, target_os = "macos"))]
    {
        // Only the window writes the log (Ruling 12).
        logger::install(&paths::logs_dir());
        log::info!(
            "{} starting on Windows {}",
            build_info::about_version(),
            ctx.windows
        );
        // Native crashes (access violations, illegal instructions) leave a file and the same
        // dialog (Ruling 10).
        #[cfg(windows)]
        crash_native::install(&ctx, crash::HookMode::Dialog);
        ui::run();
    }

    #[cfg(not(any(windows, target_os = "macos")))]
    {
        eprintln!("the window is Windows-only; use --smoke to exercise the session");
        std::process::exit(2);
    }
}
