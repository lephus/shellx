//! Start-up of the window (spec §4.2, Rulings 4 to 7, 27; plan 3b §5): the display mode this
//! start uses, the start marker and the remembered mode on disk, the installer's mutex, the
//! `GPUI_DISABLE_DIRECT_COMPOSITION` variable, and what an open failure does.
//!
//! The rules are `shellx_model::start_guard`'s; this module reads and writes the two files
//! (`starting.json`, `render.json`, each written to a temp file then renamed), keeps this
//! start's decision in a `OnceLock`, and holds the only Win32 call (`CreateMutexW`). The
//! `*_in` forms take the state explicitly so tests never touch the process-wide one.

use std::io;
use std::path::{Path, PathBuf};
use std::sync::OnceLock;
use std::sync::atomic::{AtomicBool, Ordering};

use shellx_model::crash_report::DialogKind;
use shellx_model::start_guard::{
    self, OpenFailed, RenderFile, RenderMode, StartInput, StartMarker, StartPlan, StartReason,
};
use shellx_model::strings::Str;

use crate::{crash, paths};

/// The variable GPUI reads once, in `WindowsPlatform::new` (`platform.rs:138-139`).
const RENDER_VARIABLE: &str = "GPUI_DISABLE_DIRECT_COMPOSITION";
/// Set by a start for the compatible relaunch it starts.
const RETRY_VARIABLE: &str = "SHELLX_RENDER_RETRY";

/// What Settings › Display shows (A10).
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[allow(dead_code)] // Settings › Display reads `mode` and `reason`; `remembered` is part of the plan's seam (RenderStatus) and has no reader yet
pub struct RenderStatus {
    pub mode: RenderMode,
    pub reason: StartReason,
    pub remembered: RenderMode,
}

/// What Settings › Display shows for a start (A10): the mode's name, the sentence under it,
/// and whether the "try standard" button or the "takes effect" note follows.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct DisplayView {
    pub mode: Str,
    pub explanation: Option<Str>,
    pub offer_standard: bool,
    pub takes_effect_note: bool,
}

/// The pure rule of Settings › Display: `requested` is true once "try standard" was stored.
pub fn display_view(status: &RenderStatus, requested: bool) -> DisplayView {
    match status.mode {
        RenderMode::Standard => DisplayView {
            mode: Str::DisplayStandard,
            explanation: None,
            offer_standard: false,
            takes_effect_note: false,
        },
        RenderMode::Compatible if status.reason == StartReason::UserEnvironment => DisplayView {
            mode: Str::DisplayCompatible,
            explanation: Some(Str::DisplayCompatibleByEnv),
            offer_standard: false,
            takes_effect_note: false,
        },
        RenderMode::Compatible => DisplayView {
            mode: Str::DisplayCompatible,
            explanation: Some(Str::DisplayCompatibleWhy),
            offer_standard: !requested,
            takes_effect_note: requested,
        },
    }
}

/// The start marker and the remembered mode, in `%LOCALAPPDATA%\ShellX\native`.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct StartPaths {
    pub marker: PathBuf,
    pub render: PathBuf,
}

impl StartPaths {
    pub fn in_dir(dir: &Path) -> StartPaths {
        StartPaths {
            marker: dir.join("starting.json"),
            render: dir.join("render.json"),
        }
    }

    /// The native state folder's files; `None` when `LOCALAPPDATA` is unusable (the start
    /// then decides without files).
    pub fn this_pc() -> Option<StartPaths> {
        paths::native_dir().ok().map(|dir| StartPaths::in_dir(&dir))
    }
}

/// This start's decision and what it did on disk.
pub(crate) struct StartState {
    paths: Option<StartPaths>,
    pub plan: StartPlan,
    pub remembered: RenderMode,
    is_retry: bool,
    /// This start's marker is on disk (written, not yet removed).
    marker_on_disk: AtomicBool,
    first_frame_seen: AtomicBool,
    /// This start set `GPUI_DISABLE_DIRECT_COMPOSITION` itself.
    variable_set: AtomicBool,
}

static START: OnceLock<StartState> = OnceLock::new();

/// GPUI's own test of the variable: `"1"` or `"true"`.
pub fn env_forces_compatible(value: Option<&str>) -> bool {
    matches!(value, Some("1") | Some("true"))
}

/// A relaunched retry carries `SHELLX_RENDER_RETRY=1`.
pub fn is_retry_value(value: Option<&str>) -> bool {
    value == Some("1")
}

/// 3b §5 steps 9c and 9d: whether the person (or a parent) forced compatible mode and whether
/// this start is a relaunched retry; on Windows the retry variable is then removed, so
/// nothing this start launches inherits it.
pub fn take_start_variables() -> (bool, bool) {
    let env_forced = env_forces_compatible(std::env::var(RENDER_VARIABLE).ok().as_deref());
    let is_retry = is_retry_value(std::env::var(RETRY_VARIABLE).ok().as_deref());
    #[cfg(windows)]
    {
        // SAFETY: `remove_var` is always safe on Windows, in single- and multi-threaded
        // programs (Rust documentation; plan review M-11).
        unsafe { std::env::remove_var(RETRY_VARIABLE) };
    }
    (env_forced, is_retry)
}

/// A compatible start sets the variable itself unless the person already did.
pub(crate) fn needs_render_variable(plan: &StartPlan, env_forced: bool) -> bool {
    plan.mode == RenderMode::Compatible && !env_forced
}

/// After GPUI read it, the variable goes when this start set it or a parent did (a retry), so
/// the shells in the window never inherit it; one the person set stays (plan review M-11).
pub(crate) fn forgets_render_variable(set_by_this_start: bool, is_retry: bool) -> bool {
    set_by_this_start || is_retry
}

/// `on_open_failed`, except off Windows, where GPUI ignores the variable and a relaunch would
/// change nothing: always a report.
pub(crate) fn open_failure_action(plan: &StartPlan, on_windows: bool) -> OpenFailed {
    if on_windows {
        start_guard::on_open_failed(plan)
    } else {
        OpenFailed::Report
    }
}

/// Writes `bytes` to `<path>.tmp`, then renames it over `path` (folder created).
fn write_replacing(path: &Path, bytes: &[u8]) -> io::Result<()> {
    if let Some(dir) = path.parent() {
        std::fs::create_dir_all(dir)?;
    }
    let mut temp = path.as_os_str().to_owned();
    temp.push(".tmp");
    let temp = PathBuf::from(temp);
    std::fs::write(&temp, bytes)?;
    std::fs::rename(&temp, path).inspect_err(|_| {
        let _ = std::fs::remove_file(&temp);
    })
}

fn read_text(path: &Path) -> Option<String> {
    match std::fs::read(path) {
        Ok(bytes) => Some(String::from_utf8_lossy(&bytes).into_owned()),
        Err(error) if error.kind() == io::ErrorKind::NotFound => None,
        // Present but unreadable: as an unreadable marker (a standard start that died).
        Err(_) => Some(String::new()),
    }
}

/// Reads `render.json` and the marker, decides (Ruling 7), writes this start's marker when the
/// plan says so, and logs the decision.
pub(crate) fn start_in(
    paths: Option<&StartPaths>,
    env_forces_compatible: bool,
    is_retry: bool,
    other_instance: bool,
) -> StartState {
    let remembered =
        start_guard::remembered_mode(paths.and_then(|p| read_text(&p.render)).as_deref());
    // Another instance's marker is not judged (it may be starting right now).
    let stale = if other_instance {
        None
    } else {
        start_guard::stale_marker(paths.and_then(|p| read_text(&p.marker)).as_deref())
    };
    let plan = start_guard::plan_start(&StartInput {
        remembered,
        env_forces_compatible,
        is_retry,
        stale_marker: stale,
        other_instance,
    });
    log::info!("{}", start_guard::start_line(&plan));
    let mut marker_on_disk = false;
    if plan.write_marker
        && let Some(p) = paths
    {
        let marker = StartMarker {
            pid: std::process::id(),
            mode: plan.mode,
        };
        match write_replacing(&p.marker, &serde_json::to_vec(&marker).unwrap_or_default()) {
            Ok(()) => marker_on_disk = true,
            Err(error) => log::warn!("the start marker could not be written: {error}"),
        }
    }
    StartState {
        paths: paths.cloned(),
        plan,
        remembered,
        is_retry,
        marker_on_disk: AtomicBool::new(marker_on_disk),
        first_frame_seen: AtomicBool::new(false),
        variable_set: AtomicBool::new(false),
    }
}

/// Removes this start's marker, once; never another start's: the file is removed only while
/// it still holds this process's pid (a retry may have written its own over it, B-1b review
/// m-4).
fn remove_own_marker(state: &StartState) {
    if !state.marker_on_disk.swap(false, Ordering::SeqCst) {
        return;
    }
    let Some(p) = &state.paths else {
        return;
    };
    let text = read_text(&p.marker);
    if !start_guard::marker_written_by(text.as_deref(), std::process::id()) {
        return;
    }
    if let Err(error) = std::fs::remove_file(&p.marker)
        && error.kind() != io::ErrorKind::NotFound
    {
        log::warn!("the start marker could not be removed: {error}");
    }
}

/// The first frame was drawn: remove the marker, remember a rescue's mode, log it. Once.
pub(crate) fn first_frame_in(state: &StartState) {
    if state.first_frame_seen.swap(true, Ordering::SeqCst) {
        return;
    }
    remove_own_marker(state);
    if let Some(mode) = start_guard::remember_after_first_frame(&state.plan, state.remembered)
        && let Some(p) = &state.paths
        && let Err(error) = write_replacing(
            &p.render,
            &serde_json::to_vec(&RenderFile { mode }).unwrap_or_default(),
        )
    {
        log::warn!("the display mode could not be remembered: {error}");
    }
    log::info!("{}", start_guard::first_frame_line(state.plan.mode));
}

/// An orderly end (or a crash test, or a failed open): this start's marker goes.
pub(crate) fn orderly_quit_in(state: &StartState) {
    remove_own_marker(state);
}

/// A start that reports a failed open: a remembered compatible mode is forgotten, so the next
/// start tries standard (B-1b review m-5).
pub(crate) fn after_report_in(state: &StartState) {
    if start_guard::forget_remembered_after_report(&state.plan)
        && let Some(p) = &state.paths
    {
        match request_standard_in(p) {
            Ok(()) => log::info!("the remembered compatible display mode is forgotten"),
            Err(error) => log::warn!("the display mode could not be reset: {error}"),
        }
    }
}

/// "Try standard display mode again": the next start is standard.
pub(crate) fn request_standard_in(paths: &StartPaths) -> io::Result<()> {
    let standard = RenderFile {
        mode: RenderMode::Standard,
    };
    write_replacing(
        &paths.render,
        &serde_json::to_vec(&standard).unwrap_or_default(),
    )
}

/// 3b §5 step 9e: decides this start's mode and keeps the decision for the rest of the
/// process. Returns the plan and the remembered mode.
pub fn plan_gui_start(
    paths: Option<&StartPaths>,
    env_forces_compatible: bool,
    is_retry: bool,
    other_instance: bool,
) -> (StartPlan, RenderMode) {
    let state = start_in(paths, env_forces_compatible, is_retry, other_instance);
    let decided = (state.plan, state.remembered);
    let _ = START.set(state);
    decided
}

/// 3b §5 step 9f (Windows): a compatible start the person did not force sets
/// `GPUI_DISABLE_DIRECT_COMPOSITION=1` before `Application::new()` reads it.
pub fn set_render_variable(env_forced: bool) {
    let Some(state) = START.get() else {
        return;
    };
    if !needs_render_variable(&state.plan, env_forced) {
        return;
    }
    #[cfg(windows)]
    {
        // SAFETY: `set_var` is always safe on Windows, in single- and multi-threaded programs
        // (Rust documentation). macOS GPUI ignores the variable, so it is not set there.
        unsafe { std::env::set_var(RENDER_VARIABLE, "1") };
        state.variable_set.store(true, Ordering::SeqCst);
    }
}

/// Top of the `Application::run` closure, once GPUI has read the variable: remove it when this
/// start set it or is a retry, so the shells in the window never inherit it (plan review M-11).
pub fn forget_render_variable() {
    let Some(state) = START.get() else {
        return;
    };
    if !forgets_render_variable(state.variable_set.load(Ordering::SeqCst), state.is_retry) {
        return;
    }
    #[cfg(windows)]
    {
        // SAFETY: `remove_var` is always safe on Windows (Rust documentation).
        unsafe { std::env::remove_var(RENDER_VARIABLE) };
    }
}

/// The second `on_next_frame` callback after the window opened (Ruling 6).
pub fn first_frame_drawn() {
    if let Some(state) = START.get() {
        first_frame_in(state);
    }
}

/// What `orderly_quit` runs first: the settings that still wait for their write
/// (`SettingsService::init` sets it).
static FLUSH_ON_QUIT: OnceLock<Box<dyn Fn() + Send + Sync>> = OnceLock::new();

/// Sets what `orderly_quit` runs first; once per process.
pub fn flush_on_quit(flush: impl Fn() + Send + Sync + 'static) {
    let _ = FLUSH_ON_QUIT.set(Box::new(flush));
}

/// The last window closed, or a crash test is about to crash (Ruling 31): the waiting
/// settings are written, then this start's marker goes.
pub fn orderly_quit() {
    if let Some(flush) = FLUSH_ON_QUIT.get() {
        flush();
    }
    if let Some(state) = START.get() {
        orderly_quit_in(state);
    }
}

/// This start's mode, why, and the remembered mode (standard and default before a GUI start).
pub fn render_status() -> RenderStatus {
    match START.get() {
        Some(state) => RenderStatus {
            mode: state.plan.mode,
            reason: state.plan.reason,
            remembered: state.remembered,
        },
        None => RenderStatus {
            mode: RenderMode::Standard,
            reason: StartReason::Default,
            remembered: RenderMode::Standard,
        },
    }
}

/// Settings › Display, "Try standard display mode again" (A10).
pub fn request_standard_next_start() -> io::Result<()> {
    match StartPaths::this_pc() {
        Some(paths) => request_standard_in(&paths),
        None => Err(io::Error::new(
            io::ErrorKind::NotFound,
            "LOCALAPPDATA is not set",
        )),
    }
}

/// `open_window` failed (3b §5): log it, remove this start's marker, then relaunch in
/// compatible mode (a standard start that is not a retry, Windows only) or write the
/// start-failure file, show the reporter's dialog and exit 1. Never returns.
pub fn window_failed(error: &anyhow::Error) -> ! {
    log::error!("the window could not be opened: {error:#}");
    let plan = START.get().map(|state| {
        orderly_quit_in(state);
        state.plan
    });
    let plan = plan.unwrap_or(StartPlan {
        mode: RenderMode::Standard,
        reason: StartReason::Default,
        write_marker: false,
    });
    if open_failure_action(&plan, cfg!(windows)) == OpenFailed::RelaunchCompatible {
        match relaunch_compatible() {
            Ok(()) => {
                log::info!("relaunched in compatible display mode");
                std::process::exit(0);
            }
            Err(error) => log::warn!("the compatible relaunch did not start: {error}"),
        }
    }
    if let Some(state) = START.get() {
        after_report_in(state);
    }
    let ctx = crash::context()
        .cloned()
        .unwrap_or_else(crash::CrashContext::this_process);
    // The file written, or the intended path when it could not be written anywhere (m8).
    let (Ok(named) | Err(named)) =
        crash::write_window_failure(&ctx, error, Some(&start_guard::start_line(&plan)));
    crash::start_reporter(&ctx, DialogKind::WindowFailed, &named);
    std::process::exit(1);
}

/// This exe again with the same arguments, `SHELLX_RENDER_RETRY=1` and the variable set.
fn relaunch_compatible() -> io::Result<()> {
    let exe = std::env::current_exe()?;
    std::process::Command::new(exe)
        .args(std::env::args_os().skip(1))
        .env(RETRY_VARIABLE, "1")
        .env(RENDER_VARIABLE, "1")
        .spawn()
        .map(|_| ())
}

/// The installer's mutex (Ruling 27), created by the window only and kept open until exit.
/// True when it already existed: another ShellX is running. False off Windows or when it
/// cannot be created (logged).
pub fn acquire_app_mutex() -> bool {
    #[cfg(windows)]
    {
        use std::sync::atomic::AtomicUsize;
        use windows_sys::Win32::Foundation::{GetLastError, SetLastError};
        use windows_sys::Win32::System::Threading::CreateMutexW;
        static APP_MUTEX: AtomicUsize = AtomicUsize::new(0);
        let name: Vec<u16> = start_guard::APP_MUTEX_NAME
            .encode_utf16()
            .chain(std::iter::once(0))
            .collect();
        // SAFETY: plain value; clears a stale error so the read below is this call's.
        unsafe { SetLastError(0) };
        // SAFETY: null attributes (not inherited by the relaunch), not initially owned, a
        // NUL-terminated name that outlives the call.
        let handle = unsafe { CreateMutexW(std::ptr::null(), 0, name.as_ptr()) };
        // SAFETY: no arguments; read right after the call it describes.
        let error = unsafe { GetLastError() };
        if handle.is_null() {
            // ERROR_ACCESS_DENIED: it exists, held by a ShellX this start may not open
            // (B-1b review m-3); anything else: logged, no other instance.
            let other = start_guard::another_instance_runs(false, error);
            if !other {
                log::warn!("the app mutex could not be created (error {error})");
            }
            return other;
        }
        // Kept for the process lifetime and never closed: Windows closes it at exit.
        APP_MUTEX.store(handle as usize, Ordering::SeqCst);
        start_guard::another_instance_runs(true, error)
    }
    #[cfg(not(windows))]
    {
        false
    }
}

#[cfg(test)]
mod tests {
    use std::path::Path;

    use shellx_model::start_guard::{OpenFailed, RenderMode, StartReason, on_open_failed};

    use super::*;

    fn status(mode: RenderMode, reason: StartReason) -> RenderStatus {
        RenderStatus {
            mode,
            reason,
            remembered: mode,
        }
    }

    #[test]
    fn display_shows_standard_without_a_button_or_a_reason() {
        let view = display_view(&status(RenderMode::Standard, StartReason::Default), false);
        assert_eq!(view.mode, Str::DisplayStandard);
        assert_eq!(view.explanation, None);
        assert!(!view.offer_standard && !view.takes_effect_note);
    }

    #[test]
    fn display_names_the_environment_variable_and_offers_no_button() {
        for requested in [false, true] {
            let view = display_view(
                &status(RenderMode::Compatible, StartReason::UserEnvironment),
                requested,
            );
            assert_eq!(view.mode, Str::DisplayCompatible);
            assert_eq!(view.explanation, Some(Str::DisplayCompatibleByEnv));
            assert!(!view.offer_standard && !view.takes_effect_note);
        }
    }

    #[test]
    fn display_compatible_for_any_other_reason_offers_standard_until_requested() {
        for reason in [
            StartReason::Remembered,
            StartReason::RetryAfterOpenFailed,
            StartReason::PreviousStartDied,
            StartReason::Default,
        ] {
            let before = display_view(&status(RenderMode::Compatible, reason), false);
            assert_eq!(before.mode, Str::DisplayCompatible, "{reason:?}");
            assert_eq!(before.explanation, Some(Str::DisplayCompatibleWhy));
            assert!(before.offer_standard && !before.takes_effect_note);
            let after = display_view(&status(RenderMode::Compatible, reason), true);
            assert_eq!(after.explanation, Some(Str::DisplayCompatibleWhy));
            assert!(!after.offer_standard && after.takes_effect_note);
        }
    }

    fn paths(dir: &Path) -> StartPaths {
        StartPaths::in_dir(dir)
    }

    fn read(path: &Path) -> String {
        std::fs::read_to_string(path).unwrap()
    }

    fn marker_of(mode: &str) -> String {
        format!(r#"{{"pid":{},"mode":"{mode}"}}"#, std::process::id())
    }

    fn no_temp_files(dir: &Path) {
        for entry in std::fs::read_dir(dir).unwrap() {
            let name = entry.unwrap().file_name().to_string_lossy().into_owned();
            assert!(!name.ends_with(".tmp"), "{name}");
        }
    }

    #[test]
    fn a_start_writes_the_marker_and_the_first_frame_clears_it() {
        let tmp = tempfile::tempdir().unwrap();
        let p = paths(&tmp.path().join("native"));
        let state = start_in(Some(&p), false, false, false);
        assert_eq!(
            (state.plan.mode, state.plan.reason, state.plan.write_marker),
            (RenderMode::Standard, StartReason::Default, true)
        );
        assert_eq!(read(&p.marker), marker_of("standard"));
        no_temp_files(&tmp.path().join("native"));
        first_frame_in(&state);
        assert!(!p.marker.exists());
        assert!(!p.render.exists());
        // An orderly quit afterwards removes nothing more and writes nothing.
        orderly_quit_in(&state);
        assert!(!p.marker.exists() && !p.render.exists());
    }

    #[test]
    fn a_stale_marker_starts_compatible_and_the_first_frame_remembers_it() {
        let tmp = tempfile::tempdir().unwrap();
        let p = paths(tmp.path());
        std::fs::write(&p.marker, r#"{"pid":1,"mode":"standard"}"#).unwrap();
        let state = start_in(Some(&p), false, false, false);
        assert_eq!(
            (state.plan.mode, state.plan.reason),
            (RenderMode::Compatible, StartReason::PreviousStartDied)
        );
        assert_eq!(read(&p.marker), marker_of("compatible"));
        first_frame_in(&state);
        assert!(!p.marker.exists());
        assert_eq!(read(&p.render), r#"{"mode":"compatible"}"#);
        no_temp_files(tmp.path());
        // The next start remembers it.
        let next = start_in(Some(&p), false, false, false);
        assert_eq!(
            (next.plan.mode, next.plan.reason),
            (RenderMode::Compatible, StartReason::Remembered)
        );
        // "Try standard display mode again" makes the start after that standard.
        request_standard_in(&p).unwrap();
        assert_eq!(read(&p.render), r#"{"mode":"standard"}"#);
        orderly_quit_in(&next);
        let after = start_in(Some(&p), false, false, false);
        assert_eq!(after.plan.mode, RenderMode::Standard);
    }

    #[test]
    fn another_instance_leaves_the_marker_alone() {
        let tmp = tempfile::tempdir().unwrap();
        let p = paths(tmp.path());
        let theirs = r#"{"pid":1,"mode":"standard"}"#;
        std::fs::write(&p.marker, theirs).unwrap();
        let state = start_in(Some(&p), false, false, true);
        assert_eq!(
            (state.plan.mode, state.plan.reason, state.plan.write_marker),
            (RenderMode::Standard, StartReason::Default, false)
        );
        assert_eq!(read(&p.marker), theirs);
        first_frame_in(&state);
        assert_eq!(read(&p.marker), theirs);
        assert!(!p.render.exists());
        orderly_quit_in(&state);
        assert_eq!(read(&p.marker), theirs);
    }

    #[test]
    fn a_retry_writes_its_own_marker_and_never_relaunches() {
        let tmp = tempfile::tempdir().unwrap();
        let p = paths(tmp.path());
        // The parent still holds the mutex and set the variable.
        let state = start_in(Some(&p), true, true, true);
        assert_eq!(
            (state.plan.mode, state.plan.reason, state.plan.write_marker),
            (
                RenderMode::Compatible,
                StartReason::RetryAfterOpenFailed,
                true
            )
        );
        assert_eq!(read(&p.marker), marker_of("compatible"));
        assert_eq!(on_open_failed(&state.plan), OpenFailed::Report);
        assert_eq!(open_failure_action(&state.plan, true), OpenFailed::Report);
        // A window failure removes the marker this start wrote.
        orderly_quit_in(&state);
        assert!(!p.marker.exists());
    }

    #[test]
    fn an_unreadable_marker_counts_as_a_failed_standard_start() {
        let tmp = tempfile::tempdir().unwrap();
        let p = paths(tmp.path());
        std::fs::write(&p.marker, "garbage").unwrap();
        let state = start_in(Some(&p), false, false, false);
        assert_eq!(
            (state.plan.mode, state.plan.reason),
            (RenderMode::Compatible, StartReason::PreviousStartDied)
        );
    }

    #[test]
    fn without_a_state_folder_the_start_still_decides() {
        let state = start_in(None, false, false, false);
        assert_eq!(
            (state.plan.mode, state.plan.reason),
            (RenderMode::Standard, StartReason::Default)
        );
        first_frame_in(&state);
        orderly_quit_in(&state);
    }

    #[test]
    fn the_variables_are_read_like_gpui_and_set_only_where_needed() {
        assert!(env_forces_compatible(Some("1")));
        assert!(env_forces_compatible(Some("true")));
        for no in [None, Some(""), Some("0"), Some("TRUE"), Some(" 1")] {
            assert!(!env_forces_compatible(no), "{no:?}");
        }
        assert!(is_retry_value(Some("1")));
        for no in [None, Some("0"), Some("true")] {
            assert!(!is_retry_value(no), "{no:?}");
        }
        let tmp = tempfile::tempdir().unwrap();
        let p = paths(tmp.path());
        let standard = start_in(Some(&p), false, false, true).plan;
        std::fs::write(&p.marker, r#"{"pid":1,"mode":"standard"}"#).unwrap();
        let rescue = start_in(Some(&p), false, false, false).plan;
        let user = start_in(Some(&p), true, false, false).plan;
        assert!(!needs_render_variable(&standard, false));
        assert!(needs_render_variable(&rescue, false));
        assert!(!needs_render_variable(&user, true));
        // Removed after GPUI read it when this start set it or a parent did (a retry).
        assert!(forgets_render_variable(true, false));
        assert!(forgets_render_variable(false, true));
        assert!(!forgets_render_variable(false, false));
        // macOS ignores the variable: an open failure is reported, never relaunched.
        assert_eq!(open_failure_action(&standard, false), OpenFailed::Report);
        assert_eq!(
            open_failure_action(&standard, true),
            OpenFailed::RelaunchCompatible
        );
    }

    #[test]
    fn the_marker_of_another_start_is_never_removed() {
        // B-1b review m-4: a retry (which always writes its own marker) replaced this start's.
        let tmp = tempfile::tempdir().unwrap();
        let p = paths(tmp.path());
        let state = start_in(Some(&p), false, false, false);
        assert_eq!(read(&p.marker), marker_of("standard"));
        let theirs = r#"{"pid":4294967294,"mode":"compatible"}"#;
        std::fs::write(&p.marker, theirs).unwrap();
        first_frame_in(&state);
        assert_eq!(read(&p.marker), theirs);
        orderly_quit_in(&state);
        assert_eq!(read(&p.marker), theirs);
    }

    #[test]
    fn a_remembered_compatible_start_that_cannot_open_resets_render_json() {
        let tmp = tempfile::tempdir().unwrap();
        let p = paths(tmp.path());
        std::fs::write(&p.render, r#"{"mode":"compatible"}"#).unwrap();
        let state = start_in(Some(&p), false, false, false);
        assert_eq!(state.plan.reason, StartReason::Remembered);
        after_report_in(&state);
        assert_eq!(read(&p.render), r#"{"mode":"standard"}"#);
        orderly_quit_in(&state);
        let next = start_in(Some(&p), false, false, false);
        assert_eq!(next.plan.mode, RenderMode::Standard);
        // A standard start's report leaves render.json alone.
        let tmp = tempfile::tempdir().unwrap();
        let p = paths(tmp.path());
        let state = start_in(Some(&p), false, false, false);
        after_report_in(&state);
        assert!(!p.render.exists());
    }
}
