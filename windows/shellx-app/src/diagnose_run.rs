//! `--diagnose`: the diagnostics report (spec §4.7, Rulings 30, 36, 38; plan 3b §6).
//!
//! Every probe runs on its own thread (`bounded`); `run` waits for each at most 10 s (60 s
//! for the shell checks, whose steps keep their own 10 s bound), so a probe that hangs on a
//! driver, the network or a shell writes `timed out after …` in its field and the report
//! still completes. The report is written twice under one name: after the probes that cannot
//! hang (`slow_checks_pending`), then complete. `format_report` redacts every line; nothing
//! here reads the account's email, the machine list or the installer mutex's name.
//!
//! The decisions are the pure helpers below (tested on the Mac); the Windows probes at the
//! end are thin `cfg(windows)` shells around the Win32 calls of 3b §6.

use std::path::{Path, PathBuf};
use std::sync::mpsc;
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

use shellx_model::core_api::{self, CoreCall};
use shellx_model::crash_report::{self, CrashFileKind};
use shellx_model::diagnose::{
    self, Check, DiagnosticsReport, DisplayInfo, GpuInfo, LOG_TAIL_LINES,
};
use shellx_model::log_file::{compact_utc, utc_timestamp};
use shellx_model::shell::{ShellChoice, ShellError, kind_label, launch_label};
use shellx_model::start_guard::{self, RenderMode};

use crate::core_service::{ConfiguredCore, MachineFacts};
use crate::local_pty::{self, settings};
use crate::startup::StartPaths;
use crate::{build_info, crash, os_info, paths, smoke};

/// Each probe's bound (Ruling 30).
const PROBE_BOUND: Duration = Duration::from_secs(10);
/// The shell checks' bound; each of their steps waits at most `SHELL_STEP_BOUND`.
const SHELL_BOUND: Duration = Duration::from_secs(60);
const SHELL_STEP_BOUND: Duration = Duration::from_secs(10);
/// Crash files listed, newest first.
const CRASH_FILES_LISTED: usize = 20;

/// A probe running on its own thread.
struct Pending<T> {
    rx: mpsc::Receiver<Result<T, String>>,
}

fn panic_text(payload: &(dyn std::any::Any + Send)) -> String {
    if let Some(s) = payload.downcast_ref::<&str>() {
        (*s).to_string()
    } else if let Some(s) = payload.downcast_ref::<String>() {
        s.clone()
    } else {
        "<non-string panic payload>".to_string()
    }
}

/// Starts `probe` on its own thread, inside `expect_caught` (a panic leaves a crash file and
/// starts no reporter) and `catch_unwind` (it becomes `failed: <message>`).
fn start<T: Send + 'static>(probe: impl FnOnce() -> T + Send + 'static) -> Pending<T> {
    let (tx, rx) = mpsc::channel();
    let _ = std::thread::Builder::new()
        .name("diagnose-probe".into())
        .spawn(move || {
            let result = crash::expect_caught(|| {
                std::panic::catch_unwind(std::panic::AssertUnwindSafe(probe))
            });
            let _ = tx.send(result.map_err(|payload| format!("failed: {}", panic_text(&*payload))));
        });
    // A thread that did not start dropped `tx`: `wait_until` reads that as a failure.
    Pending { rx }
}

fn timed_out(bound: Duration) -> String {
    if bound >= Duration::from_secs(1) {
        format!("timed out after {} s", bound.as_secs())
    } else {
        format!("timed out after {} ms", bound.as_millis())
    }
}

impl<T> Pending<T> {
    /// The answer, or why there is none, by `deadline` (`bound` names it).
    fn wait_until(self, deadline: Instant, bound: Duration) -> Result<T, String> {
        match self
            .rx
            .recv_timeout(deadline.saturating_duration_since(Instant::now()))
        {
            Ok(answer) => answer,
            Err(mpsc::RecvTimeoutError::Timeout) => Err(timed_out(bound)),
            Err(mpsc::RecvTimeoutError::Disconnected) => {
                Err("failed: the probe thread did not answer".to_string())
            }
        }
    }
}

/// Runs `probe` on its own thread and waits at most `bound`: `Err("timed out after …")` (the
/// thread is abandoned; `run` ends the process with `exit`), `Err("failed: <panic message>")`,
/// or the value. `run` uses the same `start` and `wait_until` to let several probes run
/// together under one deadline.
#[cfg_attr(not(test), allow(dead_code))]
pub fn bounded<T: Send + 'static>(
    bound: Duration,
    probe: impl FnOnce() -> T + Send + 'static,
) -> Result<T, String> {
    start(probe).wait_until(Instant::now() + bound, bound)
}

/// `signed in with <method>`, `signed out`, or `unknown (<code>)`. The session's email is
/// never read.
pub(crate) fn sign_in_line(core: &dyn CoreCall) -> String {
    match core_api::session_info(core) {
        Ok(session) => format!("signed in with {}", session.auth_method),
        Err(error) if error.code == "not_logged_in" => "signed out".to_string(),
        Err(error) => format!("unknown ({})", error.code),
    }
}

/// `version.check`, timed (spec §4.7: the existing call, no new RPC).
fn relay_check(core: &dyn CoreCall) -> Check {
    let started = Instant::now();
    let answer = core_api::version_check(core);
    let millis = Some(started.elapsed().as_millis().try_into().unwrap_or(u64::MAX));
    match answer {
        Ok(info) => Check {
            name: "version check".into(),
            ok: true,
            millis,
            detail: format!("status {}", info.status),
        },
        Err(error) => Check {
            name: "version check".into(),
            ok: false,
            millis,
            detail: error.code,
        },
    }
}

/// The lines of a text file (lossy UTF-8); none when it cannot be read.
fn lines_of(path: &Path) -> Vec<String> {
    std::fs::read(path)
        .map(|bytes| {
            String::from_utf8_lossy(&bytes)
                .lines()
                .map(str::to_string)
                .collect()
        })
        .unwrap_or_default()
}

/// `shellx.log.1` then `shellx.log`, oldest first.
fn log_lines_in(dir: &Path) -> Vec<String> {
    let mut lines = lines_of(&dir.join("shellx.log.1"));
    lines.extend(lines_of(&dir.join("shellx.log")));
    lines
}

/// The newest `LOG_TAIL_LINES` lines, across the rotation, oldest first.
pub(crate) fn log_tail_in(dir: &Path) -> Vec<String> {
    let lines = log_lines_in(dir);
    lines[lines.len().saturating_sub(LOG_TAIL_LINES)..].to_vec()
}

/// The time part of `<kind>.<utc>.<pid>[.<n>].txt`.
fn time_part(name: &str) -> &str {
    name.split('.').nth(1).unwrap_or("")
}

/// A ShellX crash, native crash or start-failure file name: the kind, a `20261112-081530`
/// time, then the pid (so another program's `crash.txt` in the temp folder is not listed).
fn is_crash_file(name: &str) -> bool {
    let kind = ["crash.", "crash-native.", "start-failed."]
        .iter()
        .any(|prefix| name.starts_with(prefix));
    let time = time_part(name).as_bytes();
    let time_ok = time.len() == 15
        && time[8] == b'-'
        && time
            .iter()
            .enumerate()
            .all(|(i, b)| i == 8 || b.is_ascii_digit());
    kind && time_ok && name.ends_with(".txt")
}

/// The crash, native crash and start-failure files among `names`, newest first by the time in
/// the name (ties by name), at most 20.
pub(crate) fn crash_files_newest_first(mut names: Vec<String>) -> Vec<String> {
    names.retain(|n| is_crash_file(n));
    names.sort();
    names.sort_by(|a, b| time_part(b).cmp(time_part(a)));
    names.truncate(CRASH_FILES_LISTED);
    names
}

/// The logs folder's crash files, then those the hook had to write to the temp folder when
/// the logs folder failed (B-1a review §6), marked as such.
fn crash_files_now(logs: &Path) -> Vec<String> {
    let mut files = crash_files_in(logs);
    let temp = std::env::temp_dir();
    if temp != logs {
        files.extend(
            crash_files_in(&temp)
                .into_iter()
                .map(|name| format!("{name} (in the temp folder)")),
        );
    }
    files
}

fn crash_files_in(dir: &Path) -> Vec<String> {
    let names = std::fs::read_dir(dir)
        .map(|entries| {
            entries
                .filter_map(Result::ok)
                .map(|e| e.file_name().to_string_lossy().into_owned())
                .collect()
        })
        .unwrap_or_default();
    crash_files_newest_first(names)
}

/// The display mode as a separate `--diagnose` process can know it (Ruling 36): the
/// remembered mode (`render.json`), whether a start marker exists, and the last start's
/// `render mode:` line with whether a `first frame drawn` line followed it.
pub(crate) fn render_mode_text(remembered: RenderMode, marker: bool, log: &[String]) -> String {
    let remembered = match remembered {
        RenderMode::Standard => "standard",
        RenderMode::Compatible => "compatible",
    };
    let marker = if marker {
        "start marker present"
    } else {
        "no start marker"
    };
    let last = log.iter().rposition(|l| l.contains("render mode: "));
    let start = match last {
        None => "last start: not in the log".to_string(),
        Some(at) => {
            let decision = log[at]
                .split_once("render mode: ")
                .map_or("", |(_, d)| d.trim());
            let drawn = log[at + 1..]
                .iter()
                .any(|l| l.contains("first frame drawn"));
            let frame = if drawn {
                "first frame drawn"
            } else {
                "no first frame logged"
            };
            format!("last start: {decision}, {frame}")
        }
    };
    format!("remembered {remembered}, {marker}, {start}")
}

fn render_mode_now(logs: &Path) -> String {
    let files = StartPaths::this_pc();
    let render = files
        .as_ref()
        .and_then(|p| std::fs::read_to_string(&p.render).ok());
    let remembered = start_guard::remembered_mode(render.as_deref());
    let marker = files.as_ref().is_some_and(|p| p.marker.exists());
    render_mode_text(remembered, marker, &log_lines_in(logs))
}

/// Writes, reads and deletes `diag.<pid>.tmp` in the core's state folder, timed.
fn state_dir_check() -> Check {
    let started = Instant::now();
    let outcome = (|| -> std::io::Result<PathBuf> {
        let dir = paths::core_dir()?;
        let file = dir.join(format!("diag.{}.tmp", std::process::id()));
        let written = b"shellx diagnostics";
        std::fs::write(&file, written)?;
        let read = std::fs::read(&file);
        let removed = std::fs::remove_file(&file);
        if read? != written {
            return Err(std::io::Error::other("read back something else"));
        }
        removed?;
        Ok(dir)
    })();
    let millis = Some(started.elapsed().as_millis().try_into().unwrap_or(u64::MAX));
    match outcome {
        Ok(dir) => Check {
            name: "state dir".into(),
            ok: true,
            millis,
            detail: dir.display().to_string(),
        },
        Err(error) => Check {
            name: "state dir".into(),
            ok: false,
            millis,
            detail: error.to_string(),
        },
    }
}

/// `<label>: <program>` per shell found, and the choice with what a new tab starts. A custom
/// command line is never written (only that there is one and its program).
fn shells_now() -> (Vec<String>, String) {
    let snapshot = settings::shells().refresh_now();
    let found = snapshot
        .found
        .iter()
        .map(|l| format!("{}: {}", launch_label(l), l.program))
        .collect();
    let choice = match &snapshot.choice {
        ShellChoice::Auto => "automatic".to_string(),
        ShellChoice::Known { shell } => kind_label(*shell).to_string(),
        ShellChoice::Custom { .. } => "custom command line".to_string(),
    };
    let choice = match &snapshot.env_override {
        Some(_) => format!("{choice}, overridden by SHELLX_SHELL"),
        None => choice,
    };
    let starts = match &snapshot.plan {
        None => "not looked up".to_string(),
        Some(Ok(plan)) => format!("{} ({})", launch_label(&plan.first), plan.first.program),
        Some(Err(ShellError::NoShellFound)) => "no shell found".to_string(),
        Some(Err(ShellError::Custom(_))) => "the custom command line cannot start".to_string(),
        Some(Err(ShellError::Override(_))) => "SHELLX_SHELL cannot start".to_string(),
    };
    (found, format!("{choice}; new tabs start {starts}"))
}

fn chosen_gpu_now(logs: &Path) -> String {
    match diagnose::chosen_gpu_from_log(&log_lines_in(logs)) {
        Some(gpu) => format!("{gpu} (last run's log)"),
        None => "unknown (no log)".to_string(),
    }
}

/// The patched vsync interval and whether unpatched GPUI would divide by zero (B7).
#[cfg_attr(not(windows), allow(dead_code))] // the Windows DWM probe is its caller
pub(crate) fn dwm_text(period: u64, frequency: u64, numerator: u32, denominator: u32) -> String {
    let check = diagnose::vsync_check(period, frequency, numerator, denominator);
    let yes_no = if check.unpatched_divides_by_zero {
        "yes"
    } else {
        "no"
    };
    format!(
        "period {:.2} ms (qpc {period} at {frequency} Hz, rate {numerator}/{denominator}); unpatched gpui 0.2.2 would divide by zero: {yes_no}",
        check.interval_us as f64 / 1000.0
    )
}

/// A tool's output as text: UTF-16LE when it starts with that byte order mark or its second
/// byte is 0 (`wevtutil` may write UTF-16 to a pipe; inferred), else UTF-8 (lossy).
#[cfg_attr(not(windows), allow(dead_code))] // the Windows wevtutil probe is its caller
pub(crate) fn decode_tool_output(bytes: &[u8]) -> String {
    let utf16 = bytes.starts_with(&[0xFF, 0xFE]) || (bytes.len() >= 2 && bytes[1] == 0);
    if utf16 {
        let body = bytes.strip_prefix(&[0xFF, 0xFE][..]).unwrap_or(bytes);
        let units: Vec<u16> = body
            .chunks_exact(2)
            .map(|pair| u16::from_le_bytes([pair[0], pair[1]]))
            .collect();
        String::from_utf16_lossy(&units)
    } else {
        String::from_utf8_lossy(bytes).into_owned()
    }
}

fn first_window_text() -> String {
    let fw = os_info::first_window_placement(os_info::primary_work_area());
    let maximized = if fw.maximized { "yes" } else { "no" };
    format!(
        "{}x{} at {},{}, maximized {maximized}",
        fw.width, fw.height, fw.x, fw.y
    )
}

/// One value per field when the probe answered, else its reason.
fn text_or_reason(answer: Result<String, String>) -> String {
    answer.unwrap_or_else(|reason| reason)
}

fn list_or_reason(answer: Result<Vec<String>, String>) -> Vec<String> {
    answer.unwrap_or_else(|reason| vec![reason])
}

fn check_or_reason(name: &str, answer: Result<Check, String>) -> Check {
    answer.unwrap_or_else(|reason| Check {
        name: name.to_string(),
        ok: false,
        millis: None,
        detail: reason,
    })
}

/// Writes the report to `<path>.tmp`, then renames it over `path`.
fn write_report(path: &Path, report: &DiagnosticsReport) -> std::io::Result<()> {
    if let Some(dir) = path.parent() {
        std::fs::create_dir_all(dir)?;
    }
    let mut temp = path.as_os_str().to_owned();
    temp.push(".tmp");
    let temp = PathBuf::from(temp);
    std::fs::write(&temp, diagnose::format_report(report))?;
    std::fs::rename(&temp, path).inspect_err(|_| {
        let _ = std::fs::remove_file(&temp);
    })
}

/// `--diagnose [--no-open]`: writes `logs/diagnostics.<utc>.<pid>.txt` twice, prints its path
/// and (unless `open_folder` is false) shows it in Explorer. 0 when the complete report was
/// written, else 1. Takes at most about 70 s.
pub fn run(open_folder: bool) -> i32 {
    let now = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default();
    let logs = paths::logs_dir();
    let name = crash_report::crash_file_name(
        CrashFileKind::Diagnostics,
        &compact_utc(now.as_secs()),
        std::process::id(),
    );
    let path = logs.join(name);
    let mut report = DiagnosticsReport {
        app_version: build_info::about_version(),
        commit: build_info::commit().unwrap_or("unknown").to_string(),
        build_kind: build_info::build_kind().to_string(),
        created_utc: utc_timestamp(now.as_millis().try_into().unwrap_or(u64::MAX)),
        windows_error_events: cfg!(windows).then(|| Ok(Vec::new())),
        slow_checks_pending: true,
        ..DiagnosticsReport::default()
    };

    // Phase 1: the probes that cannot hang on a driver, the network or a shell, together.
    let deadline = Instant::now() + PROBE_BOUND;
    let windows = start(windows_version_text);
    let cpu = start(cpu_info);
    let displays = start(displays_info);
    let first_window = start(first_window_text);
    let render = start({
        let logs = logs.clone();
        move || render_mode_now(&logs)
    });
    let layouts = start(keyboard_layouts);
    let methods = start(input_methods);
    let tools = start(|| diagnose::typing_tools(&running_exe_names()));
    let state = start(state_dir_check);
    let sign_in = start(|| sign_in_line(&ConfiguredCore::this_pc(MachineFacts::this_pc())));
    let crash_files = start({
        let logs = logs.clone();
        move || crash_files_now(&logs)
    });
    let log_tail = start({
        let logs = logs.clone();
        move || log_tail_in(&logs)
    });
    report.windows_version = text_or_reason(windows.wait_until(deadline, PROBE_BOUND));
    match cpu.wait_until(deadline, PROBE_BOUND) {
        Ok((name, features)) => {
            report.cpu = name;
            report.cpu_features = features;
        }
        Err(reason) => report.cpu = reason,
    }
    report.displays = displays
        .wait_until(deadline, PROBE_BOUND)
        .unwrap_or_else(|reason| {
            vec![DisplayInfo {
                name: reason,
                ..DisplayInfo::default()
            }]
        });
    report.first_window = text_or_reason(first_window.wait_until(deadline, PROBE_BOUND));
    report.render_mode = text_or_reason(render.wait_until(deadline, PROBE_BOUND));
    report.keyboard_layouts = list_or_reason(layouts.wait_until(deadline, PROBE_BOUND));
    report.input_methods = list_or_reason(methods.wait_until(deadline, PROBE_BOUND));
    report.typing_tools_running = list_or_reason(tools.wait_until(deadline, PROBE_BOUND));
    report.state_dir = check_or_reason("state dir", state.wait_until(deadline, PROBE_BOUND));
    report.sign_in = text_or_reason(sign_in.wait_until(deadline, PROBE_BOUND));
    report.crash_files = list_or_reason(crash_files.wait_until(deadline, PROBE_BOUND));
    report.log_tail = list_or_reason(log_tail.wait_until(deadline, PROBE_BOUND));
    // A hang or a native crash in phase 2 still leaves this report.
    let _ = write_report(&path, &report);

    // Phase 2: GPU, DWM, shells, relay, Windows error events, together.
    let deadline = Instant::now() + PROBE_BOUND;
    let shell_deadline = Instant::now() + SHELL_BOUND;
    let chosen_gpu = start({
        let logs = logs.clone();
        move || chosen_gpu_now(&logs)
    });
    let gpus = start(gpus_info);
    let dwm = start(dwm_timing);
    let shells = start(shells_now);
    let checks = start(|| smoke::shell_checks(&local_pty::default_shell(), SHELL_STEP_BOUND));
    let relay = start(|| relay_check(&ConfiguredCore::this_pc(MachineFacts::this_pc())));
    let events = start(windows_error_events);
    report.chosen_gpu = text_or_reason(chosen_gpu.wait_until(deadline, PROBE_BOUND));
    report.gpus = gpus
        .wait_until(deadline, PROBE_BOUND)
        .unwrap_or_else(|reason| {
            vec![GpuInfo {
                name: reason,
                ..GpuInfo::default()
            }]
        });
    report.dwm_timing = text_or_reason(dwm.wait_until(deadline, PROBE_BOUND));
    match shells.wait_until(deadline, PROBE_BOUND) {
        Ok((found, chosen)) => {
            report.shells_found = found;
            report.shell_chosen = chosen;
        }
        Err(reason) => report.shell_chosen = reason,
    }
    report.relay = check_or_reason("version check", relay.wait_until(deadline, PROBE_BOUND));
    report.windows_error_events = match events.wait_until(deadline, PROBE_BOUND) {
        Ok(events) => events,
        Err(reason) => cfg!(windows).then_some(Err(reason)),
    };
    report.shell_checks = checks
        .wait_until(shell_deadline, SHELL_BOUND)
        .unwrap_or_else(|reason| {
            vec![Check {
                name: "shell checks".into(),
                ok: false,
                millis: None,
                detail: reason,
            }]
        });
    report.slow_checks_pending = false;
    let written = write_report(&path, &report);

    let mut out = std::io::stdout();
    match &written {
        Ok(()) => {
            let _ = std::io::Write::write_fmt(
                &mut out,
                format_args!("Diagnostics report: {}\n", path.display()),
            );
        }
        Err(error) => {
            let _ = std::io::Write::write_fmt(
                &mut out,
                format_args!("Diagnostics report not written: {error}\n"),
            );
        }
    }
    if written.is_ok() && open_folder {
        show_in_folder(&path);
    }
    if written.is_ok() { 0 } else { 1 }
}

/// Starts `<this exe> --diagnose`: the help menu's "Tạo báo cáo chẩn đoán" (A10), the same
/// code as the Start entry, so the window stays responsive (Ruling 35).
pub fn spawn_report_process() -> std::io::Result<()> {
    std::process::Command::new(std::env::current_exe()?)
        .arg("--diagnose")
        .spawn()
        .map(|_| ())
}

/// `explorer.exe /select,"<file>"` (Windows; nothing elsewhere). A start that fails is ignored.
fn show_in_folder(file: &Path) {
    #[cfg(windows)]
    {
        use std::os::windows::process::CommandExt;
        let mut arg = std::ffi::OsString::from("/select,\"");
        arg.push(file.as_os_str());
        arg.push("\"");
        let root = settings::system_root(&settings::probe_from_system()).to_string();
        let _ = std::process::Command::new(PathBuf::from(root).join("explorer.exe"))
            .raw_arg(arg)
            .spawn();
    }
    #[cfg(not(windows))]
    let _ = file;
}

// ---- The Windows probes (3b §6): Win32 calls only; empty or None elsewhere. ----

/// `10.0.26100.2314 (24H2)`: `os_version()` (RtlGetVersion) with the registry's `UBR` and
/// `DisplayVersion`, the parts that were read. Empty (unknown) off Windows.
fn windows_version_text() -> String {
    #[cfg(windows)]
    {
        use winreg::RegKey;
        use winreg::enums::HKEY_LOCAL_MACHINE;
        let mut text = os_info::os_version();
        if let Ok(key) = RegKey::predef(HKEY_LOCAL_MACHINE)
            .open_subkey(r"SOFTWARE\Microsoft\Windows NT\CurrentVersion")
        {
            if let Ok(ubr) = key.get_value::<u32, _>("UBR") {
                text.push_str(&format!(".{ubr}"));
            }
            if let Ok(display) = key.get_value::<String, _>("DisplayVersion")
                && !display.trim().is_empty()
            {
                text.push_str(&format!(" ({})", display.trim()));
            }
        }
        text
    }
    #[cfg(not(windows))]
    {
        String::new()
    }
}

/// The processor's name (registry) and its instruction sets (R1 F8).
fn cpu_info() -> (String, Vec<String>) {
    #[cfg(any(target_arch = "x86", target_arch = "x86_64"))]
    let features: Vec<String> = [
        ("sse4.2", std::arch::is_x86_feature_detected!("sse4.2")),
        ("avx", std::arch::is_x86_feature_detected!("avx")),
        ("avx2", std::arch::is_x86_feature_detected!("avx2")),
        ("fma", std::arch::is_x86_feature_detected!("fma")),
        ("bmi2", std::arch::is_x86_feature_detected!("bmi2")),
        ("avx512f", std::arch::is_x86_feature_detected!("avx512f")),
    ]
    .into_iter()
    .filter(|(_, present)| *present)
    .map(|(name, _)| name.to_string())
    .collect();
    #[cfg(not(any(target_arch = "x86", target_arch = "x86_64")))]
    let features: Vec<String> = Vec::new();
    #[cfg(windows)]
    let name = {
        use winreg::RegKey;
        use winreg::enums::HKEY_LOCAL_MACHINE;
        RegKey::predef(HKEY_LOCAL_MACHINE)
            .open_subkey(r"HARDWARE\DESCRIPTION\System\CentralProcessor\0")
            .and_then(|key| key.get_value::<String, _>("ProcessorNameString"))
            .map(|n| n.trim().to_string())
            .unwrap_or_default()
    };
    #[cfg(not(windows))]
    let name = String::new();
    (name, features)
}

/// Every monitor: device name (and `primary`), size, scale, work area.
fn displays_info() -> Vec<DisplayInfo> {
    #[cfg(windows)]
    {
        windows_probes::displays()
    }
    #[cfg(not(windows))]
    {
        Vec::new()
    }
}

fn keyboard_layouts() -> Vec<String> {
    #[cfg(windows)]
    {
        windows_probes::keyboard_layouts()
    }
    #[cfg(not(windows))]
    {
        Vec::new()
    }
}

/// `HKCU\Control Panel\International\User Profile`: each language's input methods, and the
/// override.
fn input_methods() -> Vec<String> {
    #[cfg(windows)]
    {
        use winreg::RegKey;
        use winreg::enums::HKEY_CURRENT_USER;
        let Ok(profile) = RegKey::predef(HKEY_CURRENT_USER)
            .open_subkey(r"Control Panel\International\User Profile")
        else {
            return Vec::new();
        };
        let mut methods = Vec::new();
        for language in profile.enum_keys().filter_map(Result::ok) {
            let Ok(key) = profile.open_subkey(&language) else {
                continue;
            };
            let names: Vec<String> = key
                .enum_values()
                .filter_map(Result::ok)
                .map(|(name, _)| name)
                .filter(|name| name.contains(':'))
                .collect();
            if !names.is_empty() {
                methods.push(format!("{language}: {}", names.join(" ")));
            }
        }
        if let Ok(over) = profile.get_value::<String, _>("InputMethodOverride")
            && !over.trim().is_empty()
        {
            methods.push(format!("override: {}", over.trim()));
        }
        methods
    }
    #[cfg(not(windows))]
    {
        Vec::new()
    }
}

/// The executable names of running processes (only the typing tools among them are kept).
fn running_exe_names() -> Vec<String> {
    #[cfg(windows)]
    {
        windows_probes::running_exe_names()
    }
    #[cfg(not(windows))]
    {
        Vec::new()
    }
}

fn gpus_info() -> Vec<GpuInfo> {
    #[cfg(windows)]
    {
        windows_probes::gpus()
    }
    #[cfg(not(windows))]
    {
        Vec::new()
    }
}

fn dwm_timing() -> String {
    #[cfg(windows)]
    {
        windows_probes::dwm_timing()
    }
    #[cfg(not(windows))]
    {
        String::new()
    }
}

/// The last five "Application Error" events for `shellx-desktop.exe` (Ruling 38); `None` off
/// Windows.
fn windows_error_events() -> Option<Result<Vec<String>, String>> {
    #[cfg(windows)]
    {
        use std::os::windows::process::CommandExt;
        use windows_sys::Win32::System::Threading::CREATE_NO_WINDOW;
        let root = settings::system_root(&settings::probe_from_system()).to_string();
        let wevtutil = PathBuf::from(root).join("System32").join("wevtutil.exe");
        let output = std::process::Command::new(wevtutil)
            .args([
                "qe",
                "Application",
                "/c:5",
                "/rd:true",
                "/f:xml",
                "/q:*[System[Provider[@Name='Application Error']] and EventData[Data='shellx-desktop.exe']]",
            ])
            .stdin(std::process::Stdio::null())
            .creation_flags(CREATE_NO_WINDOW)
            .output();
        Some(match output {
            Err(error) => Err(format!("could not start wevtutil: {error}")),
            Ok(out) if out.status.success() => Ok(diagnose::windows_error_summaries(
                &decode_tool_output(&out.stdout),
            )),
            Ok(out) => {
                let stderr = decode_tool_output(&out.stderr);
                let first = stderr.lines().find(|l| !l.trim().is_empty()).unwrap_or("");
                Err(format!(
                    "wevtutil exit {}: {}",
                    out.status.code().unwrap_or(-1),
                    first.trim()
                ))
            }
        })
    }
    #[cfg(not(windows))]
    {
        None
    }
}

#[cfg(windows)]
mod windows_probes {
    use shellx_model::diagnose::{DisplayInfo, GpuInfo};
    use windows_sys::Win32::Foundation::{
        CloseHandle, HANDLE, INVALID_HANDLE_VALUE, LPARAM, RECT, S_OK,
    };
    use windows_sys::Win32::Graphics::Gdi::{
        EnumDisplayMonitors, GetMonitorInfoW, HDC, HMONITOR, MONITORINFO, MONITORINFOEXW,
    };
    use windows_sys::Win32::UI::HiDpi::{GetDpiForMonitor, MDT_EFFECTIVE_DPI};
    use windows_sys::Win32::UI::WindowsAndMessaging::MONITORINFOF_PRIMARY;

    fn from_wide(units: &[u16]) -> String {
        let end = units.iter().position(|&u| u == 0).unwrap_or(units.len());
        String::from_utf16_lossy(&units[..end])
    }

    /// The enumeration callback only stores the handle (plan review M-26: a panic in an
    /// `extern "system"` function would abort whatever surrounds the probe).
    unsafe extern "system" fn collect(
        monitor: HMONITOR,
        _hdc: HDC,
        _rect: *mut RECT,
        data: LPARAM,
    ) -> windows_sys::core::BOOL {
        // SAFETY: `data` is the `&mut Vec<usize>` `displays` passes, alive for the call.
        let list = unsafe { &mut *(data as *mut Vec<usize>) };
        list.push(monitor as usize);
        1
    }

    pub(super) fn displays() -> Vec<DisplayInfo> {
        let mut monitors: Vec<usize> = Vec::new();
        // SAFETY: null DC and clip: every monitor; the callback writes only to `monitors`,
        // which outlives the call.
        let ok = unsafe {
            EnumDisplayMonitors(
                std::ptr::null_mut(),
                std::ptr::null(),
                Some(collect),
                &mut monitors as *mut Vec<usize> as LPARAM,
            )
        };
        if ok == 0 {
            return Vec::new();
        }
        monitors
            .into_iter()
            .filter_map(|m| {
                let monitor = m as HMONITOR;
                let mut info = MONITORINFOEXW::default();
                info.monitorInfo.cbSize = std::mem::size_of::<MONITORINFOEXW>() as u32;
                // SAFETY: a MONITORINFOEXW whose cbSize says so; it starts with MONITORINFO.
                let got = unsafe {
                    GetMonitorInfoW(
                        monitor,
                        &mut info as *mut MONITORINFOEXW as *mut MONITORINFO,
                    )
                };
                if got == 0 {
                    return None;
                }
                let (mut dpi_x, mut dpi_y) = (0u32, 0u32);
                // SAFETY: live out-pointers.
                let dpi =
                    unsafe { GetDpiForMonitor(monitor, MDT_EFFECTIVE_DPI, &mut dpi_x, &mut dpi_y) };
                let scale_percent = if dpi == S_OK { dpi_x * 100 / 96 } else { 0 };
                let m = info.monitorInfo;
                let primary = if m.dwFlags & MONITORINFOF_PRIMARY != 0 {
                    " (primary)"
                } else {
                    ""
                };
                let size = |r: RECT| {
                    (
                        u32::try_from(r.right - r.left).unwrap_or(0),
                        u32::try_from(r.bottom - r.top).unwrap_or(0),
                    )
                };
                let (width_px, height_px) = size(m.rcMonitor);
                let (work_w, work_h) = size(m.rcWork);
                Some(DisplayInfo {
                    name: format!("{}{primary}", from_wide(&info.szDevice)),
                    width_px,
                    height_px,
                    scale_percent,
                    work_area: (m.rcWork.left, m.rcWork.top, work_w, work_h),
                })
            })
            .collect()
    }

    pub(super) fn keyboard_layouts() -> Vec<String> {
        use windows_sys::Win32::Globalization::LCIDToLocaleName;
        use windows_sys::Win32::UI::Input::KeyboardAndMouse::{GetKeyboardLayoutList, HKL};
        // SAFETY: with 0 and null it returns the count only.
        let count = unsafe { GetKeyboardLayoutList(0, std::ptr::null_mut()) };
        let Ok(len) = usize::try_from(count) else {
            return Vec::new();
        };
        if len == 0 {
            return Vec::new();
        }
        let mut layouts: Vec<HKL> = vec![std::ptr::null_mut(); len];
        // SAFETY: the buffer holds `count` HKLs.
        let filled = unsafe { GetKeyboardLayoutList(count, layouts.as_mut_ptr()) };
        layouts.truncate(usize::try_from(filled).unwrap_or(0));
        layouts
            .into_iter()
            .map(|hkl| {
                let id = hkl as usize as u32;
                let mut name = [0u16; 85];
                // SAFETY: an 85-unit buffer (LOCALE_NAME_MAX_LENGTH); 0 means failure.
                let n = unsafe { LCIDToLocaleName(id & 0xFFFF, name.as_mut_ptr(), 85, 0) };
                let locale = if n > 0 {
                    from_wide(&name)
                } else {
                    "unknown".to_string()
                };
                format!("{locale} 0x{id:08X}")
            })
            .collect()
    }

    pub(super) fn running_exe_names() -> Vec<String> {
        use windows_sys::Win32::System::Diagnostics::ToolHelp::{
            CreateToolhelp32Snapshot, PROCESSENTRY32W, Process32FirstW, Process32NextW,
            TH32CS_SNAPPROCESS,
        };
        // SAFETY: plain values; INVALID_HANDLE_VALUE on failure.
        let snapshot: HANDLE = unsafe { CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0) };
        if snapshot == INVALID_HANDLE_VALUE || snapshot.is_null() {
            return Vec::new();
        }
        let mut names = Vec::new();
        let mut entry = PROCESSENTRY32W {
            dwSize: std::mem::size_of::<PROCESSENTRY32W>() as u32,
            ..Default::default()
        };
        // SAFETY: a live entry whose dwSize is set; the snapshot handle is ours.
        let mut more = unsafe { Process32FirstW(snapshot, &mut entry) } != 0;
        while more {
            names.push(from_wide(&entry.szExeFile));
            // SAFETY: as above.
            more = unsafe { Process32NextW(snapshot, &mut entry) } != 0;
        }
        // SAFETY: the snapshot handle is ours.
        unsafe { CloseHandle(snapshot) };
        names
    }

    pub(super) fn dwm_timing() -> String {
        use windows_sys::Win32::Graphics::Dwm::{DWM_TIMING_INFO, DwmGetCompositionTimingInfo};
        use windows_sys::Win32::System::Performance::QueryPerformanceFrequency;
        let mut timing = DWM_TIMING_INFO {
            cbSize: std::mem::size_of::<DWM_TIMING_INFO>() as u32,
            ..Default::default()
        };
        // SAFETY: a null window ("must be NULL" since Windows 8.1, as GPUI passes); a live
        // DWM_TIMING_INFO whose cbSize is set.
        let hr = unsafe { DwmGetCompositionTimingInfo(std::ptr::null_mut(), &mut timing) };
        if hr != S_OK {
            return format!("unknown: 0x{:08X}", hr as u32);
        }
        let mut frequency = 0i64;
        // SAFETY: a live out-value; it cannot fail on XP or later.
        unsafe { QueryPerformanceFrequency(&mut frequency) };
        super::dwm_text(
            timing.qpcRefreshPeriod,
            u64::try_from(frequency).unwrap_or(0),
            timing.rateRefresh.uiNumerator,
            timing.rateRefresh.uiDenominator,
        )
    }

    /// Every adapter, as GPUI would see it (`directx_devices.rs`): name, driver version
    /// (GPUI's `CheckInterfaceSupport` formula), feature level and whether it has the
    /// structured buffers GPUI needs; the first usable one is the one GPUI would use.
    pub(super) fn gpus() -> Vec<GpuInfo> {
        use windows::Win32::Foundation::HMODULE;
        use windows::Win32::Graphics::Direct3D::{
            D3D_DRIVER_TYPE_UNKNOWN, D3D_FEATURE_LEVEL, D3D_FEATURE_LEVEL_10_1,
            D3D_FEATURE_LEVEL_11_0, D3D_FEATURE_LEVEL_11_1,
        };
        use windows::Win32::Graphics::Direct3D11::{
            D3D11_CREATE_DEVICE_BGRA_SUPPORT, D3D11_FEATURE_D3D10_X_HARDWARE_OPTIONS,
            D3D11_FEATURE_DATA_D3D10_X_HARDWARE_OPTIONS, D3D11_SDK_VERSION, D3D11CreateDevice,
            ID3D11Device,
        };
        use windows::Win32::Graphics::Dxgi::{
            CreateDXGIFactory1, DXGI_ADAPTER_FLAG_SOFTWARE, DXGI_ERROR_NOT_FOUND, IDXGIAdapter1,
            IDXGIDevice, IDXGIFactory1,
        };
        use windows::core::Interface;

        // SAFETY: no arguments besides the interface asked for.
        let factory: IDXGIFactory1 = match unsafe { CreateDXGIFactory1() } {
            Ok(factory) => factory,
            Err(error) => {
                return vec![GpuInfo {
                    name: format!("no DXGI factory: {error}"),
                    ..GpuInfo::default()
                }];
            }
        };
        let mut gpus = Vec::new();
        let mut gpui_choice_marked = false;
        for index in 0u32..64 {
            // SAFETY: an index; DXGI_ERROR_NOT_FOUND past the last adapter.
            let adapter: IDXGIAdapter1 = match unsafe { factory.EnumAdapters1(index) } {
                Ok(adapter) => adapter,
                Err(error) if error.code() == DXGI_ERROR_NOT_FOUND => break,
                Err(error) => {
                    gpus.push(GpuInfo {
                        name: format!("adapter {index}: {error}"),
                        ..GpuInfo::default()
                    });
                    break;
                }
            };
            // SAFETY: a live adapter.
            let name = match unsafe { adapter.GetDesc1() } {
                Ok(desc) => {
                    let software = desc.Flags & DXGI_ADAPTER_FLAG_SOFTWARE.0 as u32 != 0;
                    let name = from_wide(&desc.Description).trim().to_string();
                    if software {
                        format!("{name} (software)")
                    } else {
                        name
                    }
                }
                Err(_) => String::new(),
            };
            // SAFETY: a live adapter; IDXGIDevice's IID.
            let driver = match unsafe { adapter.CheckInterfaceSupport(&IDXGIDevice::IID) } {
                Ok(number) => format!(
                    "{}.{}.{}.{}",
                    number >> 48,
                    (number >> 32) & 0xFFFF,
                    (number >> 16) & 0xFFFF,
                    number & 0xFFFF
                ),
                Err(_) => String::new(),
            };
            let mut device: Option<ID3D11Device> = None;
            let mut level = D3D_FEATURE_LEVEL::default();
            // SAFETY: GPUI's own probe arguments (`directx_devices.rs:155-200`), live
            // out-pointers.
            let created = unsafe {
                D3D11CreateDevice(
                    &adapter,
                    D3D_DRIVER_TYPE_UNKNOWN,
                    HMODULE::default(),
                    D3D11_CREATE_DEVICE_BGRA_SUPPORT,
                    Some(&[
                        D3D_FEATURE_LEVEL_11_1,
                        D3D_FEATURE_LEVEL_11_0,
                        D3D_FEATURE_LEVEL_10_1,
                    ]),
                    D3D11_SDK_VERSION,
                    Some(&mut device),
                    Some(&mut level),
                    None,
                )
            };
            let level_text = match level {
                D3D_FEATURE_LEVEL_11_1 => "11.1",
                D3D_FEATURE_LEVEL_11_0 => "11.0",
                D3D_FEATURE_LEVEL_10_1 => "10.1",
                _ => "other",
            };
            let feature_level = match (created, device) {
                (Err(error), _) => format!("not usable: {error}"),
                (Ok(()), None) => "not usable: no device".to_string(),
                (Ok(()), Some(device)) => {
                    let mut data = D3D11_FEATURE_DATA_D3D10_X_HARDWARE_OPTIONS::default();
                    // SAFETY: `data` is the struct this feature asks for, with its size.
                    let checked = unsafe {
                        device.CheckFeatureSupport(
                            D3D11_FEATURE_D3D10_X_HARDWARE_OPTIONS,
                            &mut data as *mut _ as _,
                            std::mem::size_of::<D3D11_FEATURE_DATA_D3D10_X_HARDWARE_OPTIONS>()
                                as u32,
                        )
                    };
                    match checked {
                        Err(error) => format!("{level_text}, not usable: {error}"),
                        Ok(())
                            if data
                                .ComputeShaders_Plus_RawAndStructuredBuffers_Via_Shader_4_x
                                .as_bool() =>
                        {
                            if gpui_choice_marked {
                                format!("{level_text}, structured buffers yes")
                            } else {
                                gpui_choice_marked = true;
                                format!(
                                    "{level_text}, structured buffers yes, GPUI would use this one"
                                )
                            }
                        }
                        Ok(()) => format!("{level_text}, not usable: no structured buffers"),
                    }
                }
            };
            gpus.push(GpuInfo {
                name,
                driver,
                feature_level,
            });
        }
        gpus
    }
}

#[cfg(test)]
mod tests {
    use std::path::Path;
    use std::time::{Duration, Instant};

    use serde_json::{Value, json};
    use shellx_model::core_api::{CoreCall, CoreErr};
    use shellx_model::start_guard::RenderMode;

    use super::*;

    struct Answer(Result<Value, CoreErr>);
    impl CoreCall for Answer {
        fn call(&self, _method: &str, _params: Value) -> Result<Value, CoreErr> {
            self.0.clone()
        }
    }

    #[test]
    fn the_report_names_only_the_sign_in_method() {
        let session = json!({
            "user_id": "u-1", "device_id": "d-1",
            "email": "phu@example.com", "auth_method": "google"
        });
        let line = sign_in_line(&Answer(Ok(session)));
        assert_eq!(line, "signed in with google");
        assert!(!line.contains("phu@"));
        assert_eq!(
            sign_in_line(&Answer(Err(CoreErr::new("not_logged_in", "no session")))),
            "signed out"
        );
        assert_eq!(
            sign_in_line(&Answer(Err(CoreErr::new("io", "disk of phu@example.com")))),
            "unknown (io)"
        );
    }

    fn write_lines(path: &Path, prefix: &str, n: usize) {
        let text: String = (0..n).map(|i| format!("{prefix} {i}\n")).collect();
        std::fs::write(path, text).unwrap();
    }

    #[test]
    fn the_log_tail_reads_across_rotation() {
        let tmp = tempfile::tempdir().unwrap();
        assert!(log_tail_in(tmp.path()).is_empty());
        write_lines(&tmp.path().join("shellx.log.1"), "old", 150);
        write_lines(&tmp.path().join("shellx.log"), "new", 100);
        let tail = log_tail_in(tmp.path());
        assert_eq!(tail.len(), 200);
        assert_eq!(tail[0], "old 50");
        assert_eq!(tail[99], "old 149");
        assert_eq!(tail[100], "new 0");
        assert_eq!(tail[199], "new 99");
        write_lines(&tmp.path().join("shellx.log"), "new", 250);
        let tail = log_tail_in(tmp.path());
        assert_eq!((tail.len(), tail[0].as_str()), (200, "new 50"));
    }

    #[test]
    fn crash_files_are_listed_newest_first_by_name() {
        let names: Vec<String> = [
            "shellx.log",
            "crash.20261111-090000.5.txt",
            "crash-native.20261112-081530.7.txt",
            "start-failed.20261112-081531.8.txt",
            "diagnostics.20261112-090000.9.txt",
            "crash.20261112-081530.7.2.txt",
            "notes.txt",
        ]
        .map(String::from)
        .to_vec();
        assert_eq!(
            crash_files_newest_first(names),
            [
                "start-failed.20261112-081531.8.txt",
                "crash-native.20261112-081530.7.txt",
                "crash.20261112-081530.7.2.txt",
                "crash.20261111-090000.5.txt",
            ]
        );
        let many: Vec<String> = (0..30)
            .map(|i| format!("crash.20261112-0815{i:02}.1.txt"))
            .collect();
        let listed = crash_files_newest_first(many);
        assert_eq!(listed.len(), 20);
        assert_eq!(listed[0], "crash.20261112-081529.1.txt");
    }

    #[test]
    fn bounded_probes_time_out_and_catch_panics() {
        let started = Instant::now();
        let slow = bounded(Duration::from_millis(100), || {
            std::thread::sleep(Duration::from_secs(2));
            1
        });
        assert!(
            matches!(&slow, Err(e) if e.starts_with("timed out after")),
            "{slow:?}"
        );
        assert!(started.elapsed() < Duration::from_secs(1));
        assert_eq!(
            bounded(Duration::from_secs(5), || -> u32 { panic!("boom") }),
            Err("failed: boom".to_string())
        );
        assert_eq!(bounded(Duration::from_secs(5), || 7), Ok(7));
    }

    #[test]
    fn the_render_mode_reads_the_files_and_the_last_start() {
        let log: Vec<String> = [
            "T INFO shellx_desktop::startup: render mode: standard (default)",
            "T INFO shellx_desktop::startup: first frame drawn in standard display mode",
            "T INFO shellx_desktop::startup: render mode: compatible (previous start died before its first frame)",
        ]
        .map(String::from)
        .to_vec();
        assert_eq!(
            render_mode_text(RenderMode::Compatible, true, &log),
            "remembered compatible, start marker present, last start: compatible (previous start died before its first frame), no first frame logged"
        );
        assert_eq!(
            render_mode_text(RenderMode::Standard, false, &log[..2]),
            "remembered standard, no start marker, last start: standard (default), first frame drawn"
        );
        assert_eq!(
            render_mode_text(RenderMode::Standard, false, &[]),
            "remembered standard, no start marker, last start: not in the log"
        );
    }

    #[test]
    fn tool_output_is_read_as_utf16_or_utf8() {
        let utf16: Vec<u8> = "<Event>ế</Event>"
            .encode_utf16()
            .flat_map(|u| u.to_le_bytes())
            .collect();
        assert_eq!(decode_tool_output(&utf16), "<Event>ế</Event>");
        let mut with_bom = vec![0xFF, 0xFE];
        with_bom.extend(&utf16);
        assert_eq!(decode_tool_output(&with_bom), "<Event>ế</Event>");
        assert_eq!(
            decode_tool_output("<Event>ế</Event>".as_bytes()),
            "<Event>ế</Event>"
        );
        assert_eq!(decode_tool_output(b""), "");
    }

    #[test]
    fn dwm_timing_reads_as_a_sentence_without_codes() {
        let text = dwm_text(166_667, 10_000_000, 60, 1);
        assert_eq!(
            text,
            "period 16.67 ms (qpc 166667 at 10000000 Hz, rate 60/1); unpatched gpui 0.2.2 would divide by zero: no"
        );
        assert_eq!(shellx_model::redact::redact(&text), text);
        assert!(dwm_text(60, 10_000_000, 60, 1).ends_with("would divide by zero: yes"));
    }

    #[test]
    fn only_shellx_crash_files_are_listed() {
        let names: Vec<String> = [
            "crash.txt",
            "crash.log.1.txt",
            "crash.20261112-081530.12.txt",
            "start-failed.2026111-081530.1.txt",
        ]
        .map(String::from)
        .to_vec();
        assert_eq!(
            crash_files_newest_first(names),
            ["crash.20261112-081530.12.txt"]
        );
    }
}
