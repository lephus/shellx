//! The diagnostics report: what a person sends when something does not work, as plain text.
//!
//! The window fills a `DiagnosticsReport` (the Windows calls live in `shellx-app`);
//! `format_report` writes it. Every output line goes through `redact`, so a secret that
//! reaches any field still does not reach the text.

use crate::redact::redact;
use crate::shell::ShellKind;

/// How many of the newest log lines the report carries.
pub const LOG_TAIL_LINES: usize = 200;

/// One probe: did it work, how long did it take, what did it say.
#[derive(Clone, Debug, Default)]
pub struct Check {
    pub name: String,
    pub ok: bool,
    pub millis: Option<u64>,
    pub detail: String,
}

#[derive(Clone, Debug, Default)]
pub struct DisplayInfo {
    pub name: String,
    pub width_px: u32,
    pub height_px: u32,
    pub scale_percent: u32,
    /// `x, y, width, height` of the work area in physical pixels.
    pub work_area: (i32, i32, u32, u32),
}

#[derive(Clone, Debug, Default)]
pub struct GpuInfo {
    pub name: String,
    pub driver: String,
    pub feature_level: String,
}

#[derive(Clone, Debug, Default)]
pub struct DiagnosticsReport {
    pub app_version: String,
    pub commit: String,
    pub build_kind: String,
    pub created_utc: String,
    pub windows_version: String,
    pub cpu: String,
    pub cpu_features: Vec<String>,
    pub displays: Vec<DisplayInfo>,
    pub first_window: String,
    pub chosen_gpu: String,
    pub render_mode: String,
    pub dwm_timing: String,
    pub gpus: Vec<GpuInfo>,
    pub keyboard_layouts: Vec<String>,
    pub input_methods: Vec<String>,
    pub typing_tools_running: Vec<String>,
    pub shells_found: Vec<String>,
    pub shell_chosen: String,
    pub shell_checks: Vec<Check>,
    pub state_dir: Check,
    /// "signed out" or the sign-in method; never the address.
    pub sign_in: String,
    /// The `version.check` answer and its time.
    pub relay: Check,
    pub crash_files: Vec<String>,
    pub log_tail: Vec<String>,
    /// The last "Application Error" events Windows recorded for ShellX (Ruling 38): `None`
    /// off Windows (no line), `Some(Err(reason))` when they could not be read.
    pub windows_error_events: Option<Result<Vec<String>, String>>,
    /// The first of the two writes (Ruling 30): the probes that can hang on a driver, the
    /// network or a shell have not run yet, and their lines say so.
    pub slow_checks_pending: bool,
}

/// One value on one line: blank reads `unknown`.
fn value(text: &str) -> String {
    let one_line = text
        .split(['\r', '\n'])
        .map(str::trim)
        .collect::<Vec<_>>()
        .join(" ");
    let one_line = one_line.trim();
    if one_line.is_empty() {
        "unknown".to_string()
    } else {
        one_line.to_string()
    }
}

/// A list on one line: nothing reads `none`.
fn list(items: &[String]) -> String {
    let items: Vec<String> = items
        .iter()
        .map(|i| value(i))
        .filter(|i| i != "unknown")
        .collect();
    if items.is_empty() {
        "none".to_string()
    } else {
        items.join(", ")
    }
}

fn check_line(label: &str, check: &Check) -> String {
    let status = if check.ok { "ok" } else { "failed" };
    let time = match check.millis {
        Some(ms) => format!("{ms} ms"),
        None => "time unknown".to_string(),
    };
    let detail = value(&check.detail);
    if detail == "unknown" {
        format!("{label}: {status}, {time}")
    } else {
        format!("{label}: {status}, {time}, {detail}")
    }
}

/// The report as text: `ShellX diagnostics`, then the sections in a fixed order, each a
/// `[name]` line and `key: value` lines. An empty value reads `unknown`, an empty list
/// `none`. Only the newest `LOG_TAIL_LINES` log lines are written.
pub fn format_report(r: &DiagnosticsReport) -> String {
    let mut lines: Vec<String> = vec!["ShellX diagnostics".to_string()];
    let mut section = |name: &str, body: Vec<String>| {
        lines.push(format!("[{name}]"));
        lines.extend(body);
    };

    section(
        "app",
        vec![
            format!("version: {}", value(&r.app_version)),
            format!("commit: {}", value(&r.commit)),
            format!("build: {}", value(&r.build_kind)),
            format!("created: {}", value(&r.created_utc)),
        ],
    );
    section(
        "windows",
        vec![format!("windows: {}", value(&r.windows_version))],
    );
    section(
        "cpu",
        vec![
            format!("cpu: {}", value(&r.cpu)),
            format!("features: {}", list(&r.cpu_features)),
        ],
    );

    let mut displays = Vec::new();
    if r.displays.is_empty() {
        displays.push("displays: none".to_string());
    }
    for (i, d) in r.displays.iter().enumerate() {
        let (x, y, w, h) = d.work_area;
        displays.push(format!(
            "display {}: {}, {}x{} px, {}%, work area {x},{y} {w}x{h}",
            i + 1,
            value(&d.name),
            d.width_px,
            d.height_px,
            d.scale_percent
        ));
    }
    displays.push(format!("first window: {}", value(&r.first_window)));
    section("displays", displays);

    let pending = r.slow_checks_pending;
    let slow = |line: String, label: &str| {
        if pending {
            format!("{label}: {NOT_RUN_YET}")
        } else {
            line
        }
    };
    let mut gpu = vec![
        slow(
            format!("chosen gpu: {}", value(&r.chosen_gpu)),
            "chosen gpu",
        ),
        format!("render mode: {}", value(&r.render_mode)),
        slow(
            format!("dwm timing: {}", value(&r.dwm_timing)),
            "dwm timing",
        ),
    ];
    if pending {
        gpu.push(format!("gpus: {NOT_RUN_YET}"));
    } else if r.gpus.is_empty() {
        gpu.push("gpus: none".to_string());
    }
    for (i, g) in r.gpus.iter().enumerate().filter(|_| !pending) {
        gpu.push(format!(
            "gpu {}: {}, driver {}, feature level {}",
            i + 1,
            value(&g.name),
            value(&g.driver),
            value(&g.feature_level)
        ));
    }
    section("gpu", gpu);

    section(
        "keyboard",
        vec![
            format!("layouts: {}", list(&r.keyboard_layouts)),
            format!("input methods: {}", list(&r.input_methods)),
            format!("typing tools running: {}", list(&r.typing_tools_running)),
        ],
    );

    let mut shells = vec![
        slow(format!("found: {}", list(&r.shells_found)), "found"),
        slow(format!("chosen: {}", value(&r.shell_chosen)), "chosen"),
    ];
    if pending {
        shells.push(format!("checks: {NOT_RUN_YET}"));
    } else if r.shell_checks.is_empty() {
        shells.push("checks: none".to_string());
    }
    for c in r.shell_checks.iter().filter(|_| !pending) {
        shells.push(check_line(&value(&c.name), c));
    }
    section("shells", shells);

    section("state", vec![check_line("state dir", &r.state_dir)]);
    section("account", vec![format!("sign-in: {}", value(&r.sign_in))]);
    section(
        "relay",
        vec![slow(check_line("version check", &r.relay), "version check")],
    );

    let mut crash: Vec<String> = if r.crash_files.is_empty() {
        vec!["none".to_string()]
    } else {
        r.crash_files.iter().map(|f| value(f)).collect()
    };
    match &r.windows_error_events {
        None => {}
        Some(_) if pending => crash.push(format!("windows error events: {NOT_RUN_YET}")),
        Some(Ok(events)) if events.is_empty() => {
            crash.push("windows error events: none found".to_string())
        }
        Some(Ok(events)) => crash.extend(
            events
                .iter()
                .map(|e| format!("windows error event: {}", value(e))),
        ),
        Some(Err(reason)) => crash.push(format!(
            "windows error events: unavailable ({})",
            value(reason)
        )),
    }
    section("crash files", crash);

    let tail = &r.log_tail[r.log_tail.len().saturating_sub(LOG_TAIL_LINES)..];
    let log: Vec<String> = if tail.is_empty() {
        vec!["none".to_string()]
    } else {
        tail.iter()
            .flat_map(|entry| entry.lines().map(str::to_string).collect::<Vec<_>>())
            .collect()
    };
    section(&format!("log: last {LOG_TAIL_LINES} lines"), log);

    let mut out = String::new();
    for line in lines {
        out.push_str(&redact(&line));
        out.push('\n');
    }
    out
}

/// What a slow probe's line reads in the first write.
const NOT_RUN_YET: &str = "not run yet";

/// The typing tools whose process is running (`[keyboard]`): the names from `exe_names` that
/// are Unikey, EVKey, OpenKey or GoTiengViet, compared without case, each once, in order.
/// No other process name is ever kept.
pub fn typing_tools(exe_names: &[String]) -> Vec<String> {
    const TOOLS: [&str; 9] = [
        "unikeynt.exe",
        "unikey.exe",
        "evkey64.exe",
        "evkey32.exe",
        "evkey.exe",
        "openkey64.exe",
        "openkey32.exe",
        "openkey.exe",
        "gotiengviet.exe",
    ];
    let mut found: Vec<String> = Vec::new();
    for name in exe_names {
        let lower = name.to_lowercase();
        if TOOLS.contains(&lower.as_str()) && !found.iter().any(|f| f.to_lowercase() == lower) {
            found.push(name.clone());
        }
    }
    found
}

/// The adapter GPUI chose in the last start the log shows (Ruling 36): the last
/// `Using GPU: <name>` line before the last `Created device with Direct3D` line. GPUI logs
/// every adapter it tries (`directx_devices.rs:121-131`), then the device it created.
pub fn chosen_gpu_from_log(lines: &[String]) -> Option<String> {
    let created = lines
        .iter()
        .rposition(|l| l.contains("Created device with Direct3D"))?;
    lines[..created].iter().rev().find_map(|l| {
        l.split_once("Using GPU: ")
            .map(|(_, name)| name.trim().to_string())
            .filter(|name| !name.is_empty())
    })
}

/// One step of a shell check: resize to `columns` first when set, type `input` and Enter,
/// then wait until `lines` lines of the grid contain `expect`.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct ProbeStep {
    pub name: &'static str,
    pub columns: Option<u16>,
    pub input: &'static str,
    pub expect: &'static str,
    pub lines: usize,
}

/// What `--diagnose` types into a shell after it started and printed.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ProbeScript {
    pub steps: Vec<ProbeStep>,
}

/// The script for a kind of shell: PowerShell (7 and Windows) and Command Prompt have one;
/// the others (Git Bash, WSL, a custom line, the Mac's bash) are checked for start and first
/// output only. The computed marker (`shellx-ok-42`) proves the command ran: the typed text
/// never holds it; the Vietnamese text must appear twice (typed, then echoed).
pub fn probe_script(kind: Option<ShellKind>) -> Option<ProbeScript> {
    let step = |name, columns, input, expect, lines| ProbeStep {
        name,
        columns,
        input,
        expect,
        lines,
    };
    match kind? {
        ShellKind::Pwsh | ShellKind::WindowsPowerShell => Some(ProbeScript {
            steps: vec![
                // The first line also turns PSReadLine's history saving off for this session,
                // so the checks do not land in the person's history (B-2 review m4; that one
                // line itself may still be saved). Harmless without PSReadLine.
                step(
                    "echo",
                    None,
                    "if (Get-Module PSReadLine) { Set-PSReadLineOption -HistorySaveStyle SaveNothing }; Write-Output ('shellx-ok-' + (6*7))",
                    "shellx-ok-42",
                    1,
                ),
                step(
                    "unicode",
                    None,
                    "Write-Output 'tiếng Việt'",
                    "tiếng Việt",
                    2,
                ),
                step(
                    "resize",
                    Some(120),
                    "Write-Output ('cols-' + $Host.UI.RawUI.WindowSize.Width)",
                    "cols-120",
                    1,
                ),
            ],
        }),
        ShellKind::Cmd => Some(ProbeScript {
            steps: vec![
                // `call` expands %x% after the assignment; the typed text holds `%x%`, never
                // `shellx-ok-42`, and the banner or a prompt cannot hold it either (m5).
                step(
                    "echo",
                    None,
                    "set /a x=6*7 >nul & call echo shellx-ok-%x%",
                    "shellx-ok-42",
                    1,
                ),
                step("unicode", None, "echo tiếng Việt", "tiếng Việt", 2),
            ],
        }),
        ShellKind::GitBash | ShellKind::Wsl => None,
    }
}

/// Longest Windows error event line, in characters.
const EVENT_LINE_MAX_CHARS: usize = 300;

/// `&amp; &lt; &gt; &quot; &apos; &#N; &#xH;` decoded; anything else kept as written.
fn decode_entities(text: &str) -> String {
    let mut out = String::with_capacity(text.len());
    let mut rest = text;
    while let Some(at) = rest.find('&') {
        out.push_str(&rest[..at]);
        let after = &rest[at..];
        let decoded = after.find(';').and_then(|end| {
            let name = &after[1..end];
            let c = match name {
                "amp" => Some('&'),
                "lt" => Some('<'),
                "gt" => Some('>'),
                "quot" => Some('"'),
                "apos" => Some('\''),
                _ => {
                    let number = if let Some(hex) =
                        name.strip_prefix("#x").or_else(|| name.strip_prefix("#X"))
                    {
                        u32::from_str_radix(hex, 16).ok()
                    } else {
                        name.strip_prefix('#').and_then(|d| d.parse::<u32>().ok())
                    };
                    number.and_then(char::from_u32)
                }
            };
            c.map(|c| (c, end + 1))
        });
        match decoded {
            Some((c, len)) => {
                out.push(c);
                rest = &after[len..];
            }
            None => {
                out.push('&');
                rest = &after[1..];
            }
        }
    }
    out.push_str(rest);
    out
}

/// The value of attribute `name` in the first tag `<tag ...>` of `xml`, quoted with `'` or `"`.
fn attribute(xml: &str, tag: &str, name: &str) -> Option<String> {
    let start = xml.find(&format!("<{tag}"))?;
    let tag_text = &xml[start..start + xml[start..].find('>')?];
    let at = tag_text.find(&format!("{name}="))? + name.len() + 1;
    let quote = tag_text[at..].chars().next()?;
    if quote != '\'' && quote != '"' {
        return None;
    }
    let value = &tag_text[at + 1..];
    let end = value.find(quote)?;
    Some(decode_entities(&value[..end]))
}

/// The text of every `<Data …>…</Data>` element (an empty `<Data/>` is skipped), decoded, on
/// one line.
fn data_values(event: &str) -> Vec<String> {
    let mut values = Vec::new();
    let mut rest = event;
    while let Some(at) = rest.find("<Data") {
        let after = &rest[at + "<Data".len()..];
        // `<DataItem>` or similar is not a Data element.
        if !after.starts_with(['>', ' ', '/', '\t', '\r', '\n']) {
            rest = after;
            continue;
        }
        let Some(close) = after.find('>') else { break };
        if after[..close].ends_with('/') {
            rest = &after[close + 1..];
            continue;
        }
        let body = &after[close + 1..];
        let Some(end) = body.find("</Data>") else {
            break;
        };
        let text = decode_entities(&body[..end]);
        let text = text.split_whitespace().collect::<Vec<_>>().join(" ");
        if !text.is_empty() {
            values.push(text);
        }
        rest = &body[end + "</Data>".len()..];
    }
    values
}

/// `wevtutil qe … /f:xml` output → one line per complete `<Event>`, in the order given (newest
/// first with `/rd:true`): `<TimeCreated SystemTime> <the Data values, comma-separated>`, at
/// most 300 characters. Only the time and the event data are read (never `<Computer>`).
pub fn windows_error_summaries(xml: &str) -> Vec<String> {
    let mut lines = Vec::new();
    let mut rest = xml;
    while let Some(at) = rest.find("<Event") {
        let after = &rest[at..];
        // `<Event>` or `<Event xmlns=…>`, not `<EventData>` or `<EventID>`.
        if !after["<Event".len()..].starts_with(['>', ' ', '\t', '\r', '\n']) {
            rest = &after["<Event".len()..];
            continue;
        }
        let Some(end) = after.find("</Event>") else {
            break;
        };
        let event = &after[..end];
        let time = attribute(event, "TimeCreated", "SystemTime").unwrap_or_default();
        let values = data_values(event).join(", ");
        let line = format!("{time} {values}").trim().to_string();
        if !line.is_empty() {
            lines.push(line.chars().take(EVENT_LINE_MAX_CHARS).collect());
        }
        rest = &after[end + "</Event>".len()..];
    }
    lines
}

/// What GPUI's vsync thread does with this PC's DWM timing (report `[gpu]`, patch (b)).
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct VsyncCheck {
    /// The sleep the patched GPUI uses when `DwmFlush` returns early, in µs (truncated).
    pub interval_us: u64,
    /// Whether unpatched GPUI 0.2.2 would divide by zero on this PC (its vsync thread then
    /// panics and the window stops repainting, R1 F6).
    pub unpatched_divides_by_zero: bool,
}

/// GPUI's `VSYNC_INTERVAL_THRESHOLD` and `DEFAULT_VSYNC_INTERVAL` (`vsync.rs`).
const VSYNC_THRESHOLD_US: u64 = 1_000;
const DEFAULT_VSYNC_US: u64 = 16_666;

/// Mirrors `get_dwm_interval` in `vendor/gpui-0.2.2/src/platform/windows/vsync.rs`: the flag
/// with the unpatched arithmetic, the interval with the patched one (3b §3). The inputs are
/// `DWM_TIMING_INFO.qpcRefreshPeriod`, `QueryPerformanceFrequency` and `rateRefresh`.
pub fn vsync_check(
    qpc_refresh_period: u64,
    qpc_frequency: u64,
    rate_numerator: u32,
    rate_denominator: u32,
) -> VsyncCheck {
    let ticks_per_us = qpc_frequency / 1_000_000;
    // Patched `retrieve_duration`: 0 for a QPC under 1 MHz, which sends it to the rate.
    let measured_us = qpc_refresh_period.checked_div(ticks_per_us).unwrap_or(0);
    let falls_back = measured_us < VSYNC_THRESHOLD_US;
    // Unpatched: `counts / (ticks_per_second / 1_000_000)` in the first call, then the
    // fallback passes the rate (Hz, far below 1 000 000) as ticks per second.
    let unpatched_divides_by_zero =
        ticks_per_us == 0 || (falls_back && u64::from(rate_numerator) / 1_000_000 == 0);
    let interval_us = if falls_back {
        refresh_rate_interval_us(rate_numerator, rate_denominator)
    } else {
        measured_us
    };
    VsyncCheck {
        interval_us,
        unpatched_divides_by_zero,
    }
}

/// Patched `refresh_rate_interval`: denominator / numerator seconds, the default when either
/// is 0 or the period is under 1 ms or over 1 s.
fn refresh_rate_interval_us(numerator: u32, denominator: u32) -> u64 {
    if numerator == 0 || denominator == 0 {
        return DEFAULT_VSYNC_US;
    }
    let interval =
        std::time::Duration::from_secs_f64(f64::from(denominator) / f64::from(numerator));
    let us = interval.as_micros();
    if us < u128::from(VSYNC_THRESHOLD_US) || interval > std::time::Duration::from_secs(1) {
        DEFAULT_VSYNC_US
    } else {
        us as u64
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::shell::ShellKind;

    const T43: &str = "AbCdEfGhIjKlMnOpQrStUvWxYz0123456789_-AbCdE"; // 43 chars, base64url

    fn planted() -> String {
        format!("phu@example.com {T43} code 123456 re_AbCdEfGh123")
    }

    fn check(ok: bool) -> Check {
        Check {
            name: planted(),
            ok,
            millis: Some(42),
            detail: planted(),
        }
    }

    fn full_report() -> DiagnosticsReport {
        let p = planted;
        DiagnosticsReport {
            app_version: p(),
            commit: p(),
            build_kind: p(),
            created_utc: p(),
            windows_version: p(),
            cpu: p(),
            cpu_features: vec![p(), p()],
            displays: vec![DisplayInfo {
                name: p(),
                width_px: 1920,
                height_px: 1080,
                scale_percent: 150,
                work_area: (0, 0, 1280, 672),
            }],
            first_window: p(),
            chosen_gpu: p(),
            render_mode: p(),
            dwm_timing: p(),
            gpus: vec![GpuInfo {
                name: p(),
                driver: p(),
                feature_level: p(),
            }],
            keyboard_layouts: vec![p()],
            input_methods: vec![p()],
            typing_tools_running: vec![p()],
            shells_found: vec![p()],
            shell_chosen: p(),
            shell_checks: vec![check(true), check(false)],
            state_dir: check(true),
            sign_in: p(),
            relay: check(false),
            crash_files: vec![p()],
            log_tail: vec![p(), format!("panicked:\n{}", p())],
            windows_error_events: Some(Ok(vec![p()])),
            slow_checks_pending: false,
        }
    }

    const HEADERS: [&str; 12] = [
        "[app]",
        "[windows]",
        "[cpu]",
        "[displays]",
        "[gpu]",
        "[keyboard]",
        "[shells]",
        "[state]",
        "[account]",
        "[relay]",
        "[crash files]",
        "[log: last 200 lines]",
    ];

    #[test]
    fn report_lists_every_section_in_order() {
        let text = format_report(&full_report());
        assert_eq!(text.lines().next(), Some("ShellX diagnostics"));
        let found: Vec<&str> = text
            .lines()
            .filter(|l| l.starts_with('[') && l.ends_with(']'))
            .collect();
        assert_eq!(found, HEADERS);
        assert_eq!(LOG_TAIL_LINES, 200);
    }

    #[test]
    fn report_redacts_planted_secrets_everywhere() {
        let text = format_report(&full_report());
        for secret in [
            "phu@example.com",
            T43,
            "code 123456",
            "123456",
            "re_AbCdEfGh123",
        ] {
            assert!(!text.contains(secret), "{secret} leaked:\n{text}");
        }
        assert!(text.contains("<email>"));
        // the structure survived the redaction
        assert!(text.contains("[log: last 200 lines]"));
    }

    #[test]
    fn report_keeps_only_the_last_200_log_lines() {
        let report = DiagnosticsReport {
            log_tail: (0..250).map(|i| format!("line {i}")).collect(),
            ..DiagnosticsReport::default()
        };
        let text = format_report(&report);
        let lines: Vec<&str> = text.lines().collect();
        assert!(lines.contains(&"line 249"));
        assert!(lines.contains(&"line 50"));
        assert!(!lines.contains(&"line 49"));
        assert!(!lines.contains(&"line 0"));
        let at = lines.iter().position(|l| *l == "line 50").unwrap();
        assert_eq!(
            &lines[at..],
            (50..250).map(|i| format!("line {i}")).collect::<Vec<_>>()
        );
    }

    #[test]
    fn empty_values_read_unknown_or_none() {
        let text = format_report(&DiagnosticsReport::default());
        let lines: Vec<&str> = text.lines().collect();
        assert!(lines.contains(&"windows: unknown"), "{text}");
        let at = lines.iter().position(|l| *l == "[crash files]").unwrap();
        assert_eq!(lines[at + 1], "none");
        assert!(lines.contains(&"version: unknown"), "{text}");
        assert!(lines.contains(&"input methods: none"), "{text}");
    }

    #[test]
    fn checks_read_ok_or_failed_with_time_and_detail() {
        let report = DiagnosticsReport {
            state_dir: Check {
                name: "state dir".into(),
                ok: true,
                millis: Some(3),
                detail: "C:\\Users\\Phú\\AppData\\Roaming\\ShellX".into(),
            },
            relay: Check {
                name: "version.check".into(),
                ok: false,
                millis: None,
                detail: "timed out".into(),
            },
            ..DiagnosticsReport::default()
        };
        let text = format_report(&report);
        assert!(
            text.contains("state dir: ok, 3 ms, C:\\Users\\Phú\\AppData\\Roaming\\ShellX"),
            "{text}"
        );
        assert!(
            text.contains("version check: failed, time unknown, timed out"),
            "{text}"
        );
    }

    #[test]
    fn vsync_check_matches_gpui_0_2_2() {
        let check = |period, frequency, numerator, denominator| {
            let c = vsync_check(period, frequency, numerator, denominator);
            (c.interval_us, c.unpatched_divides_by_zero)
        };
        // Normal PCs: QPC at 10 MHz, DWM periods of 60, 59.94 and 240 Hz.
        assert_eq!(check(166_667, 10_000_000, 60, 1), (16_666, false));
        assert_eq!(check(166_833, 10_000_000, 60_000, 1001), (16_683, false));
        assert_eq!(check(41_667, 10_000_000, 240, 1), (4_166, false));
        // The 29 µs case GPUI's comment cites: the rate fallback divided by zero.
        assert_eq!(check(60, 10_000_000, 60, 1), (16_666, true));
        // Nothing usable: the default interval.
        assert_eq!(check(0, 10_000_000, 0, 0), (16_666, true));
        // A QPC frequency under 1 MHz divided by zero at once.
        assert_eq!(check(166_667, 500_000, 60, 1), (16_666, true));
        // A rate the patched fallback refuses (above 1 s per frame): the default.
        assert_eq!(check(60, 10_000_000, 1, 2), (16_666, true));
    }

    fn strings(items: &[&str]) -> Vec<String> {
        items.iter().map(|s| s.to_string()).collect()
    }

    #[test]
    fn typing_tools_are_found_by_exe_name() {
        assert_eq!(
            typing_tools(&strings(&["UniKeyNT.exe", "explorer.exe", "EVKey64.exe"])),
            strings(&["UniKeyNT.exe", "EVKey64.exe"])
        );
        for tool in [
            "unikeynt.exe",
            "unikey.exe",
            "evkey64.exe",
            "evkey32.exe",
            "evkey.exe",
            "openkey64.exe",
            "openkey32.exe",
            "openkey.exe",
            "gotiengviet.exe",
        ] {
            assert_eq!(typing_tools(&strings(&[tool])), strings(&[tool]));
            let upper = tool.to_uppercase();
            assert_eq!(typing_tools(std::slice::from_ref(&upper)), vec![upper]);
        }
        // Only the tools: no other process name, and one line per tool.
        assert!(
            typing_tools(&strings(&[
                "shellx-desktop.exe",
                "unikey.exe.bak",
                "myunikey.exe"
            ]))
            .is_empty()
        );
        assert_eq!(
            typing_tools(&strings(&["UniKeyNT.exe", "unikeynt.exe"])),
            strings(&["UniKeyNT.exe"])
        );
    }

    #[test]
    fn chosen_gpu_is_the_last_adapter_tried_before_the_device_was_created() {
        const DEV: &str = "T INFO gpui::platform::windows::directx_devices:";
        let lines = vec![
            "T INFO shellx_desktop: ShellX 1.7.0 starting on Windows 10.0.26100".to_string(),
            format!("{DEV} Using GPU: Microsoft Basic Render Driver"),
            "T ERROR gpui: Required feature StructuredBuffer is not supported by GPU/driver"
                .to_string(),
            format!("{DEV} Using GPU: Intel(R) UHD Graphics 620"),
            format!("{DEV} Created device with Direct3D 11.1 feature level."),
        ];
        assert_eq!(
            chosen_gpu_from_log(&lines).as_deref(),
            Some("Intel(R) UHD Graphics 620")
        );
        // A later start's choice wins; a start that tried an adapter but created no device
        // after the last one that did does not.
        let mut later = lines.clone();
        later.push(format!("{DEV} Using GPU: NVIDIA GeForce RTX 3050"));
        later.push(format!(
            "{DEV} Created device with Direct3D 11.0 feature level."
        ));
        later.push(format!("{DEV} Using GPU: Broken Adapter"));
        assert_eq!(
            chosen_gpu_from_log(&later).as_deref(),
            Some("NVIDIA GeForce RTX 3050")
        );
        assert_eq!(chosen_gpu_from_log(&lines[..3]), None);
        assert_eq!(chosen_gpu_from_log(&[]), None);
    }

    #[test]
    fn probe_scripts_exist_for_powershell_and_cmd_only() {
        for kind in [ShellKind::Pwsh, ShellKind::WindowsPowerShell] {
            let script = probe_script(Some(kind)).unwrap();
            let names: Vec<&str> = script.steps.iter().map(|s| s.name).collect();
            assert_eq!(names, ["echo", "unicode", "resize"]);
            // B-2 review m4: the first line turns PSReadLine's history saving off for this
            // session (guarded, so it is harmless without PSReadLine).
            assert_eq!(
                script.steps[0].input,
                "if (Get-Module PSReadLine) { Set-PSReadLineOption -HistorySaveStyle SaveNothing }; Write-Output ('shellx-ok-' + (6*7))"
            );
            assert_eq!(script.steps[0].expect, "shellx-ok-42");
            assert_eq!(script.steps[1].input, "Write-Output 'tiếng Việt'");
            assert_eq!(
                (script.steps[1].expect, script.steps[1].lines),
                ("tiếng Việt", 2)
            );
            assert_eq!(script.steps[2].columns, Some(120));
            assert_eq!(script.steps[2].expect, "cols-120");
        }
        let cmd = probe_script(Some(ShellKind::Cmd)).unwrap();
        let names: Vec<&str> = cmd.steps.iter().map(|s| s.name).collect();
        assert_eq!(names, ["echo", "unicode"]);
        // B-2 review m5: the cmd banner and prompts often hold "42"; the marker cannot.
        // Final review m-b: the variable is a name no environment holds (not `x`).
        assert_eq!(
            (cmd.steps[0].input, cmd.steps[0].expect),
            (
                "set /a SHELLX_PROBE_7f3a=6*7 >nul & call echo shellx-ok-%SHELLX_PROBE_7f3a%",
                "shellx-ok-42"
            )
        );
        // No one-line step can pass on the typed text alone.
        for script in [
            probe_script(Some(ShellKind::Pwsh)).unwrap(),
            probe_script(Some(ShellKind::Cmd)).unwrap(),
        ] {
            for step in script.steps.iter().filter(|s| s.lines == 1) {
                assert!(!step.input.contains(step.expect), "{step:?}");
            }
        }
        assert_eq!(
            (cmd.steps[1].input, cmd.steps[1].expect, cmd.steps[1].lines),
            ("echo tiếng Việt", "tiếng Việt", 2)
        );
        for other in [Some(ShellKind::GitBash), Some(ShellKind::Wsl), None] {
            assert_eq!(probe_script(other), None, "{other:?}");
        }
    }

    #[test]
    fn the_cmd_probe_variable_is_not_a_short_name() {
        let cmd = probe_script(Some(ShellKind::Cmd)).unwrap();
        let line = cmd.steps[0].input;
        assert_eq!(cmd.steps[0].expect, "shellx-ok-42");
        // `set /a NAME=` and `%NAME%`: the name must be long and unusual, never `x`/`X`.
        let name = line
            .split("set /a ")
            .nth(1)
            .and_then(|rest| rest.split('=').next())
            .unwrap();
        assert!(name.len() >= 12 && name.starts_with("SHELLX_PROBE_"), "{line}");
        assert!(line.contains(&format!("%{name}%")), "{line}");
        assert!(!line.contains("%x%") && !line.contains("%X%"), "{line}");
    }

    #[test]
    fn windows_error_events_are_read_from_the_event_xml() {
        let newest = "<Event xmlns='http://schemas.microsoft.com/win/2004/08/events/event'><System>\
            <Provider Name='Application Error'/><EventID Qualifiers='0'>1000</EventID>\
            <TimeCreated SystemTime='2026-11-12T08:15:31.1234567Z'/><Computer>DESKTOP-OTHER</Computer>\
            </System><EventData><Data Name='AppName'>shellx-desktop.exe</Data>\
            <Data Name='ExceptionCode'>c0000409</Data>\
            <Data Name='AppPath'>C:\\Users\\A &amp; B\\shellx-desktop.exe</Data></EventData></Event>";
        let older = "<Event xmlns='http://schemas.microsoft.com/win/2004/08/events/event'><System>\
            <TimeCreated SystemTime=\"2026-11-11T07:00:00.0000000Z\"/></System><EventData>\
            <Data>shellx-desktop.exe</Data><Data></Data><Data/><Data>  c0000005\r\n  </Data>\
            <Data>&lt;x&gt; &quot;q&quot; &apos;a&apos; &#65;&#x42;</Data></EventData></Event>";
        let lines = windows_error_summaries(&format!("{newest}\r\n{older}\r\n"));
        assert_eq!(
            lines,
            strings(&[
                "2026-11-12T08:15:31.1234567Z shellx-desktop.exe, c0000409, C:\\Users\\A & B\\shellx-desktop.exe",
                "2026-11-11T07:00:00.0000000Z shellx-desktop.exe, c0000005, <x> \"q\" 'a' AB",
            ])
        );
        assert!(!lines.iter().any(|l| l.contains("DESKTOP-OTHER")));
        assert!(windows_error_summaries("").is_empty());
        assert!(
            windows_error_summaries(
                "<Event><System><TimeCreated SystemTime='x'/></System><EventData><Data>a</Data>"
            )
            .is_empty()
        );
        let long = format!(
            "<Event><System><TimeCreated SystemTime='t'/></System><EventData><Data>{}</Data></EventData></Event>",
            "v".repeat(400)
        );
        let lines = windows_error_summaries(&long);
        assert_eq!(lines.len(), 1);
        assert_eq!(lines[0].chars().count(), 300);
    }

    fn section_after<'a>(text: &'a str, header: &str) -> Vec<&'a str> {
        text.lines()
            .skip_while(|l| *l != header)
            .skip(1)
            .take_while(|l| !l.starts_with('['))
            .collect()
    }

    fn headers(text: &str) -> Vec<&str> {
        text.lines()
            .filter(|l| l.starts_with('[') && l.ends_with(']'))
            .collect()
    }

    #[test]
    fn windows_error_events_are_listed_under_crash_files() {
        let base = DiagnosticsReport {
            crash_files: strings(&["crash.20261112-081530.1.txt"]),
            ..DiagnosticsReport::default()
        };
        let text = format_report(&base);
        assert!(!text.contains("windows error event"), "{text}");
        assert_eq!(
            section_after(&text, "[crash files]"),
            ["crash.20261112-081530.1.txt"]
        );
        let with = |events| {
            format_report(&DiagnosticsReport {
                windows_error_events: Some(events),
                ..base.clone()
            })
        };
        let text = with(Ok(vec![]));
        assert_eq!(
            section_after(&text, "[crash files]"),
            [
                "crash.20261112-081530.1.txt",
                "windows error events: none found"
            ]
        );
        assert_eq!(headers(&text), HEADERS);
        let text = with(Ok(strings(&["a", "b"])));
        assert_eq!(
            section_after(&text, "[crash files]"),
            [
                "crash.20261112-081530.1.txt",
                "windows error event: a",
                "windows error event: b"
            ]
        );
        assert_eq!(headers(&text), HEADERS);
        let text = with(Err("x".to_string()));
        assert_eq!(
            section_after(&text, "[crash files]"),
            [
                "crash.20261112-081530.1.txt",
                "windows error events: unavailable (x)"
            ]
        );
        assert_eq!(headers(&text), HEADERS);
        // No crash files: `none`, then the events.
        let text = format_report(&DiagnosticsReport {
            windows_error_events: Some(Ok(vec![])),
            ..DiagnosticsReport::default()
        });
        assert_eq!(
            section_after(&text, "[crash files]"),
            ["none", "windows error events: none found"]
        );
    }

    #[test]
    fn a_first_pass_report_marks_the_slow_checks_not_run_yet() {
        let text = format_report(&DiagnosticsReport {
            slow_checks_pending: true,
            ..full_report()
        });
        let lines: Vec<&str> = text.lines().collect();
        for pending in [
            "chosen gpu: not run yet",
            "dwm timing: not run yet",
            "gpus: not run yet",
            "found: not run yet",
            "chosen: not run yet",
            "checks: not run yet",
            "version check: not run yet",
            "windows error events: not run yet",
        ] {
            assert!(lines.contains(&pending), "{pending:?} missing:\n{text}");
        }
        assert!(!lines.iter().any(|l| l.starts_with("gpu 1:")), "{text}");
        assert!(
            !lines.iter().any(|l| l.starts_with("windows error event:")),
            "{text}"
        );
        // The fast sections keep their values.
        for kept in [
            "render mode: ",
            "display 1: ",
            "sign-in: ",
            "state dir: ok",
            "layouts: ",
        ] {
            assert!(
                lines
                    .iter()
                    .any(|l| l.starts_with(kept) && !l.ends_with("not run yet")),
                "{kept:?}:\n{text}"
            );
        }
        assert_eq!(headers(&text), HEADERS);
        // Without Windows events (the Mac), no events line at all.
        let text = format_report(&DiagnosticsReport {
            slow_checks_pending: true,
            windows_error_events: None,
            ..full_report()
        });
        assert!(!text.contains("windows error event"), "{text}");
    }
}
