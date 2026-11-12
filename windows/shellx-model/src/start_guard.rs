//! The compatible display mode's start rules (spec §4.2, Rulings 4 to 7): which mode a start
//! uses and why, what an open failure does, what the first frame remembers, and the log lines
//! for each decision. The files and the Win32 mutex are `shellx-app`'s `startup`.

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
            (plan(Standard, Default, true), "render mode: standard (default)"),
            (plan(Standard, Remembered, true), "render mode: standard (remembered)"),
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
        assert_eq!(
            redact(APP_MUTEX_NAME),
            APP_MUTEX_NAME,
            "the mutex name is never logged, but it must not read as a token either"
        );
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
        assert_eq!(remembered_mode(Some(r#"{"mode":"compatible"}"#)), Compatible);
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
            assert_eq!(stale_marker(Some(unreadable)), Some(Standard), "{unreadable}");
        }
    }
}
