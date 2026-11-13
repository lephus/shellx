//! ShellX desktop for Windows: a native GPUI window drawing a libghostty-vt
//! grid fed by ConPTY. Keyboard text and IME composition come through GPUI's
//! `EntityInputHandler`, so a Vietnamese Telex preedit is drawn inline and
//! only committed text reaches the PTY. `--smoke` runs the same session
//! headless (after the `--smoke-ui-assets` checks) and exits;
//! `--smoke-ui-assets` checks the embedded icons and shell strings only;
//! `--smoke-panes` runs only the tabs/splits pane checks of `--smoke`;
//! `--version` prints the version and exits; `--diagnose [--no-open]` writes the
//! diagnostics report (and shows it in Explorer unless `--no-open`). These flags print to
//! the parent's console (Ruling 29).
#![cfg_attr(all(windows, not(debug_assertions)), windows_subsystem = "windows")]

mod build_info;
mod console;
mod core_bridge;
mod core_service;
mod crash;
#[cfg(windows)]
mod crash_native;
mod cwd;
mod diagnose_run;
#[cfg(test)]
mod exe_resource;
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
mod settings_store;
mod shell_info;
mod smoke;
mod startup;
mod term_core;
mod workspace;

// The window also builds on macOS, for development screenshots only.
#[cfg(any(windows, target_os = "macos"))]
mod ui;

use std::io::Write;
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

    // The console flags print to the parent's console (Ruling 29), attached before anything
    // else can print (3b §5 step 3).
    let console_flag = ["--version", "--smoke-ui-assets", "--smoke-panes", "--smoke"]
        .iter()
        .any(|flag| has(flag));
    let diagnose = has("--diagnose");
    let no_open = has("--no-open");
    if console_flag || diagnose {
        console::attach_parent_console();
    }

    // Every panic from here on leaves a crash file; the window's and --diagnose's also start
    // the reporter (FileOnly for --diagnose --no-open, as in CI: plan review M-13).
    let ctx = crash::CrashContext::this_process();
    let mode = crash::hook_mode(console_flag, diagnose, no_open);
    crash::install_panic_hook(ctx.clone(), mode);
    crash::set_crash_test(crash::crash_test_from(&args));

    if has("--version") {
        // `writeln!` with the error ignored: a closed console or pipe must not panic.
        let _ = writeln!(
            std::io::stdout(),
            "shellx-desktop {}",
            shellx_model::VERSION
        );
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

    if diagnose {
        // 3b §5 step 8: the native filter follows the hook's mode; no log is written.
        #[cfg(windows)]
        crash_native::install(&ctx, mode);
        std::process::exit(diagnose_run::run(!no_open));
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
        // The display mode (3b §5 steps 9b to 9f): decided before GPUI exists, because GPUI
        // reads GPUI_DISABLE_DIRECT_COMPOSITION once, when the platform is created.
        let other_instance = startup::acquire_app_mutex();
        let (env_forced, is_retry) = startup::take_start_variables();
        startup::plan_gui_start(
            startup::StartPaths::this_pc().as_ref(),
            env_forced,
            is_retry,
            other_instance,
        );
        startup::set_render_variable(env_forced);
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
