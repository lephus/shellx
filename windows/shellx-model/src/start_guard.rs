//! The compatible display mode's start rules (spec §4.2, Rulings 4 to 7): which mode a start
//! uses and why, what an open failure does, what the first frame remembers, and the log lines
//! for each decision. The files and the Win32 mutex are `shellx-app`'s `startup`.

use serde::{Deserialize, Serialize};

/// The installer's `AppMutex` and the app's "another ShellX is running" test (Ruling 27): the
/// native AppId in the name, session namespace (no `Global\`).
pub const APP_MUTEX_NAME: &str = "ShellXNative-D322DA97-3B0D-49C7-BDB2-8EBFADBA1004";

/// `ERROR_ALREADY_EXISTS` and `ERROR_ACCESS_DENIED` (WinError.h).
const ERROR_ALREADY_EXISTS: u32 = 183;
const ERROR_ACCESS_DENIED: u32 = 5;

/// Whether another ShellX holds the app mutex, from `CreateMutexW`'s result: with a handle,
/// when the last error is `ERROR_ALREADY_EXISTS` ("the object existed before this function
/// call"); without one, when it is `ERROR_ACCESS_DENIED`: the mutex exists but this start may
/// not open it (an elevated ShellX created it, and the call asks for `MUTEX_ALL_ACCESS`;
/// B-1b review m-3). Any other failure counts as no other instance.
pub fn another_instance_runs(got_handle: bool, last_error: u32) -> bool {
    if got_handle {
        last_error == ERROR_ALREADY_EXISTS
    } else {
        last_error == ERROR_ACCESS_DENIED
    }
}

/// How GPUI draws: `Standard` (DirectComposition) or `Compatible`
/// (`GPUI_DISABLE_DIRECT_COMPOSITION=1`: a plain HWND swap chain).
#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum RenderMode {
    Standard,
    Compatible,
}

impl RenderMode {
    fn word(self) -> &'static str {
        match self {
            RenderMode::Standard => "standard",
            RenderMode::Compatible => "compatible",
        }
    }
}

/// Why a start uses its mode.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum StartReason {
    /// Nothing remembered: standard.
    Default,
    /// `render.json` said so.
    Remembered,
    /// The person set `GPUI_DISABLE_DIRECT_COMPOSITION`.
    UserEnvironment,
    /// This start is the relaunch after the standard mode could not open the window.
    RetryAfterOpenFailed,
    /// The marker of a start that died before its first frame was found.
    PreviousStartDied,
}

/// What a start knows before GPUI exists.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct StartInput {
    pub remembered: RenderMode,
    pub env_forces_compatible: bool,
    pub is_retry: bool,
    /// The mode of a marker left by an earlier start (`None`: no marker).
    pub stale_marker: Option<RenderMode>,
    /// The app mutex already existed.
    pub other_instance: bool,
}

/// The decision: the mode, why, and whether this start writes the marker.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct StartPlan {
    pub mode: RenderMode,
    pub reason: StartReason,
    pub write_marker: bool,
}

/// Ruling 7, in order: a relaunched retry → compatible (it writes its own marker even though
/// its parent may still hold the mutex); the variable set by the person → compatible; another
/// instance running → the remembered mode, the marker neither judged nor written; a stale
/// marker from a standard start → compatible; from a compatible start → standard; else the
/// remembered mode.
pub fn plan_start(input: &StartInput) -> StartPlan {
    let remembered_reason = match input.remembered {
        RenderMode::Standard => StartReason::Default,
        RenderMode::Compatible => StartReason::Remembered,
    };
    let write_marker = !input.other_instance;
    let (mode, reason, write_marker) = if input.is_retry {
        (
            RenderMode::Compatible,
            StartReason::RetryAfterOpenFailed,
            true,
        )
    } else if input.env_forces_compatible {
        (
            RenderMode::Compatible,
            StartReason::UserEnvironment,
            write_marker,
        )
    } else if input.other_instance {
        (input.remembered, remembered_reason, false)
    } else {
        match input.stale_marker {
            Some(RenderMode::Standard) => {
                (RenderMode::Compatible, StartReason::PreviousStartDied, true)
            }
            Some(RenderMode::Compatible) => {
                (RenderMode::Standard, StartReason::PreviousStartDied, true)
            }
            None => (input.remembered, remembered_reason, true),
        }
    };
    StartPlan {
        mode,
        reason,
        write_marker,
    }
}

/// What a failed `open_window` does.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum OpenFailed {
    /// Start this exe again in compatible mode (at most once per start the person makes).
    RelaunchCompatible,
    /// Write the start-failure file and show the dialog.
    Report,
}

/// Only a standard start that is not a retry relaunches; anything else reports (Ruling 7).
pub fn on_open_failed(plan: &StartPlan) -> OpenFailed {
    if plan.mode == RenderMode::Standard && plan.reason != StartReason::RetryAfterOpenFailed {
        OpenFailed::RelaunchCompatible
    } else {
        OpenFailed::Report
    }
}

/// The mode to write to `render.json` once this start drew its first frame: only a rescue
/// (`RetryAfterOpenFailed`, `PreviousStartDied`) that differs from what is remembered.
pub fn remember_after_first_frame(plan: &StartPlan, remembered: RenderMode) -> Option<RenderMode> {
    let rescue = matches!(
        plan.reason,
        StartReason::RetryAfterOpenFailed | StartReason::PreviousStartDied
    );
    (rescue && plan.mode != remembered).then_some(plan.mode)
}

/// The log line for the decision (no digits: it survives the redactor as it is).
pub fn start_line(plan: &StartPlan) -> String {
    let why = match plan.reason {
        StartReason::Default => "default",
        StartReason::Remembered => "remembered",
        StartReason::UserEnvironment => "set by GPUI_DISABLE_DIRECT_COMPOSITION",
        StartReason::RetryAfterOpenFailed => "the standard mode could not open the window",
        StartReason::PreviousStartDied => "previous start died before its first frame",
    };
    let other = if plan.write_marker {
        ""
    } else {
        "; another ShellX is running"
    };
    format!("render mode: {} ({why}{other})", plan.mode.word())
}

/// The log line once the first frame was drawn.
pub fn first_frame_line(mode: RenderMode) -> String {
    format!("first frame drawn in {} display mode", mode.word())
}

/// `render.json`: `{"mode":"standard"}` or `{"mode":"compatible"}`.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct RenderFile {
    pub mode: RenderMode,
}

/// `starting.json`: `{"pid":n,"mode":"standard"}`, written before GPUI starts and removed by
/// the first frame or an orderly quit.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct StartMarker {
    pub pid: u32,
    pub mode: RenderMode,
}

/// Whether the marker's text was written by the process `pid` (an unreadable or missing one
/// was not): a start removes only its own marker (B-1b review m-4).
pub fn marker_written_by(text: Option<&str>, pid: u32) -> bool {
    text.and_then(|t| serde_json::from_str::<StartMarker>(t).ok())
        .is_some_and(|m| m.pid == pid)
}

/// The remembered mode from `render.json`'s text: missing or unreadable is standard.
pub fn remembered_mode(text: Option<&str>) -> RenderMode {
    text.and_then(|t| serde_json::from_str::<RenderFile>(t).ok())
        .map_or(RenderMode::Standard, |f| f.mode)
}

/// The mode of a marker an earlier start left: `None` without a file; an unreadable marker
/// counts as a standard start that died (Ruling 4).
pub fn stale_marker(text: Option<&str>) -> Option<RenderMode> {
    let text = text?;
    Some(serde_json::from_str::<StartMarker>(text).map_or(RenderMode::Standard, |m| m.mode))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::redact::redact;
    use RenderMode::{Compatible, Standard};
    use StartReason::*;

    fn input(remembered: RenderMode) -> StartInput {
        StartInput {
            remembered,
            env_forces_compatible: false,
            is_retry: false,
            stale_marker: None,
            other_instance: false,
        }
    }

    fn plan(mode: RenderMode, reason: StartReason, write_marker: bool) -> StartPlan {
        StartPlan {
            mode,
            reason,
            write_marker,
        }
    }

    #[test]
    fn start_plan_follows_the_rules_in_order() {
        // 1. A relaunched retry is compatible whatever else holds, and writes its own marker
        //    (its parent may still hold the mutex).
        for remembered in [Standard, Compatible] {
            for env in [false, true] {
                for stale in [None, Some(Standard), Some(Compatible)] {
                    for other in [false, true] {
                        let i = StartInput {
                            remembered,
                            env_forces_compatible: env,
                            is_retry: true,
                            stale_marker: stale,
                            other_instance: other,
                        };
                        assert_eq!(
                            plan_start(&i),
                            plan(Compatible, RetryAfterOpenFailed, true),
                            "{i:?}"
                        );
                    }
                }
            }
        }
        // 2. The variable set by the person: compatible, before every other rule.
        let i = StartInput {
            env_forces_compatible: true,
            stale_marker: Some(Compatible),
            ..input(Standard)
        };
        assert_eq!(plan_start(&i), plan(Compatible, UserEnvironment, true));
        let i = StartInput {
            other_instance: true,
            ..i
        };
        assert_eq!(plan_start(&i), plan(Compatible, UserEnvironment, false));
        // 3. Another instance: the remembered mode; the marker is neither judged nor written.
        let i = StartInput {
            other_instance: true,
            stale_marker: Some(Standard),
            ..input(Standard)
        };
        assert_eq!(plan_start(&i), plan(Standard, Default, false));
        let i = StartInput {
            remembered: Compatible,
            ..i
        };
        assert_eq!(plan_start(&i), plan(Compatible, Remembered, false));
        // 4. A stale marker from a standard start: compatible.
        let i = StartInput {
            stale_marker: Some(Standard),
            ..input(Standard)
        };
        assert_eq!(plan_start(&i), plan(Compatible, PreviousStartDied, true));
        let i = StartInput {
            remembered: Compatible,
            ..i
        };
        assert_eq!(plan_start(&i), plan(Compatible, PreviousStartDied, true));
        // 5. A stale marker from a compatible start: standard.
        let i = StartInput {
            stale_marker: Some(Compatible),
            ..input(Compatible)
        };
        assert_eq!(plan_start(&i), plan(Standard, PreviousStartDied, true));
        // 6. Otherwise the remembered mode.
        assert_eq!(plan_start(&input(Standard)), plan(Standard, Default, true));
        assert_eq!(
            plan_start(&input(Compatible)),
            plan(Compatible, Remembered, true)
        );
    }

    #[test]
    fn open_failure_relaunches_once_then_reports() {
        assert_eq!(
            on_open_failed(&plan(Standard, Default, true)),
            OpenFailed::RelaunchCompatible
        );
        assert_eq!(
            on_open_failed(&plan(Standard, PreviousStartDied, true)),
            OpenFailed::RelaunchCompatible
        );
        assert_eq!(
            on_open_failed(&plan(Standard, Default, false)),
            OpenFailed::RelaunchCompatible
        );
        assert_eq!(
            on_open_failed(&plan(Compatible, RetryAfterOpenFailed, true)),
            OpenFailed::Report
        );
        assert_eq!(
            on_open_failed(&plan(Compatible, Remembered, true)),
            OpenFailed::Report
        );
        assert_eq!(
            on_open_failed(&plan(Compatible, UserEnvironment, true)),
            OpenFailed::Report
        );
        assert_eq!(
            on_open_failed(&plan(Compatible, PreviousStartDied, true)),
            OpenFailed::Report
        );
    }

    #[test]
    fn only_a_rescue_is_remembered() {
        for reason in [RetryAfterOpenFailed, PreviousStartDied] {
            assert_eq!(
                remember_after_first_frame(&plan(Compatible, reason, true), Standard),
                Some(Compatible)
            );
            assert_eq!(
                remember_after_first_frame(&plan(Compatible, reason, true), Compatible),
                None
            );
        }
        assert_eq!(
            remember_after_first_frame(&plan(Standard, PreviousStartDied, true), Compatible),
            Some(Standard)
        );
        for reason in [Default, Remembered, UserEnvironment] {
            for mode in [Standard, Compatible] {
                for remembered in [Standard, Compatible] {
                    assert_eq!(
                        remember_after_first_frame(&plan(mode, reason, true), remembered),
                        None,
                        "{reason:?} {mode:?} {remembered:?}"
                    );
                }
            }
        }
    }

    #[test]
    fn start_decisions_read_as_plain_lines() {
        let rows = [
            (
                plan(Standard, Default, true),
                "render mode: standard (default)",
            ),
            (
                plan(Standard, Remembered, true),
                "render mode: standard (remembered)",
            ),
            (
                plan(Compatible, Remembered, true),
                "render mode: compatible (remembered)",
            ),
            (
                plan(Compatible, UserEnvironment, true),
                "render mode: compatible (set by GPUI_DISABLE_DIRECT_COMPOSITION)",
            ),
            (
                plan(Compatible, RetryAfterOpenFailed, true),
                "render mode: compatible (the standard mode could not open the window)",
            ),
            (
                plan(Standard, PreviousStartDied, true),
                "render mode: standard (previous start died before its first frame)",
            ),
            (
                plan(Compatible, PreviousStartDied, true),
                "render mode: compatible (previous start died before its first frame)",
            ),
            (
                plan(Standard, Default, false),
                "render mode: standard (default; another ShellX is running)",
            ),
            (
                plan(Compatible, Remembered, false),
                "render mode: compatible (remembered; another ShellX is running)",
            ),
        ];
        for (p, line) in rows {
            assert_eq!(start_line(&p), line);
            assert_eq!(redact(line), line);
        }
        assert_eq!(
            first_frame_line(Standard),
            "first frame drawn in standard display mode"
        );
        assert_eq!(
            first_frame_line(Compatible),
            "first frame drawn in compatible display mode"
        );
        for mode in [Standard, Compatible] {
            assert_eq!(redact(&first_frame_line(mode)), first_frame_line(mode));
        }
    }

    #[test]
    fn render_files_are_small_json() {
        assert_eq!(
            serde_json::to_string(&RenderFile { mode: Compatible }).unwrap(),
            r#"{"mode":"compatible"}"#
        );
        assert_eq!(
            serde_json::to_string(&StartMarker {
                pid: 42,
                mode: Standard
            })
            .unwrap(),
            r#"{"pid":42,"mode":"standard"}"#
        );
        assert_eq!(
            remembered_mode(Some(r#"{"mode":"compatible"}"#)),
            Compatible
        );
        assert_eq!(remembered_mode(Some(r#"{"mode":"standard"}"#)), Standard);
        for unusable in [None, Some(""), Some("garbage"), Some(r#"{"mode":"other"}"#)] {
            assert_eq!(remembered_mode(unusable), Standard, "{unusable:?}");
        }
        assert_eq!(stale_marker(None), None);
        assert_eq!(
            stale_marker(Some(r#"{"pid":1,"mode":"compatible"}"#)),
            Some(Compatible)
        );
        assert_eq!(
            stale_marker(Some(r#"{"pid":1,"mode":"standard"}"#)),
            Some(Standard)
        );
        // An unreadable marker counts as a standard start that died (Ruling 4).
        for unreadable in ["garbage", "", r#"{"pid":1}"#, r#"{"mode":"other"}"#] {
            assert_eq!(
                stale_marker(Some(unreadable)),
                Some(Standard),
                "{unreadable}"
            );
        }
    }

    #[test]
    fn a_mutex_that_exists_means_another_shellx_runs() {
        // CreateMutexW: a handle plus ERROR_ALREADY_EXISTS (183) means it existed; no handle
        // with ERROR_ACCESS_DENIED (5) means it exists but this start may not open it (an
        // elevated ShellX holds it, B-1b review m-3).
        assert!(another_instance_runs(true, 183));
        assert!(!another_instance_runs(true, 0));
        assert!(another_instance_runs(false, 5));
        assert!(!another_instance_runs(false, 87));
        assert!(!another_instance_runs(false, 0));
    }

    #[test]
    fn only_a_marker_with_this_pid_is_this_starts() {
        assert!(marker_written_by(Some(r#"{"pid":42,"mode":"standard"}"#), 42));
        assert!(!marker_written_by(Some(r#"{"pid":43,"mode":"compatible"}"#), 42));
        assert!(!marker_written_by(Some("garbage"), 42));
        assert!(!marker_written_by(None, 42));
    }

    #[test]
    fn a_remembered_compatible_mode_that_cannot_open_is_forgotten() {
        // B-1b review m-5: otherwise every start is compatible and fails, with no way back
        // from inside the app.
        assert!(forget_remembered_after_report(&plan(Compatible, Remembered, true)));
        assert!(forget_remembered_after_report(&plan(Compatible, Remembered, false)));
        for p in [
            plan(Standard, Default, true),
            plan(Compatible, RetryAfterOpenFailed, true),
            plan(Compatible, UserEnvironment, true),
            plan(Compatible, PreviousStartDied, true),
            plan(Standard, PreviousStartDied, true),
        ] {
            assert!(!forget_remembered_after_report(&p), "{p:?}");
        }
    }
}
