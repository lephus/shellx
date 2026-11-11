//! The diagnostics report: what a person sends when something does not work, as plain text.
//!
//! The window fills a `DiagnosticsReport` (the Windows calls live in `shellx-app`);
//! `format_report` writes it. Every output line goes through `redact`, so a secret that
//! reaches any field still does not reach the text.

use crate::redact::redact;

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

    let mut gpu = vec![
        format!("chosen gpu: {}", value(&r.chosen_gpu)),
        format!("render mode: {}", value(&r.render_mode)),
        format!("dwm timing: {}", value(&r.dwm_timing)),
    ];
    if r.gpus.is_empty() {
        gpu.push("gpus: none".to_string());
    }
    for (i, g) in r.gpus.iter().enumerate() {
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
        format!("found: {}", list(&r.shells_found)),
        format!("chosen: {}", value(&r.shell_chosen)),
    ];
    if r.shell_checks.is_empty() {
        shells.push("checks: none".to_string());
    }
    for c in &r.shell_checks {
        shells.push(check_line(&value(&c.name), c));
    }
    section("shells", shells);

    section("state", vec![check_line("state dir", &r.state_dir)]);
    section("account", vec![format!("sign-in: {}", value(&r.sign_in))]);
    section("relay", vec![check_line("version check", &r.relay)]);

    let crash = if r.crash_files.is_empty() {
        vec!["none".to_string()]
    } else {
        r.crash_files.iter().map(|f| value(f)).collect()
    };
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

#[cfg(test)]
mod tests {
    use super::*;

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
}
