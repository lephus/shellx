//! Start-up of the window (spec §4.2, Rulings 4 to 7, 27; plan 3b §5): the display mode this
//! start uses, the start marker and the remembered mode on disk, the installer's mutex, the
//! `GPUI_DISABLE_DIRECT_COMPOSITION` variable, and what an open failure does.

#[cfg(test)]
mod tests {
    use std::path::Path;

    use shellx_model::start_guard::{OpenFailed, RenderMode, StartReason, on_open_failed};

    use super::*;

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
            (RenderMode::Compatible, StartReason::RetryAfterOpenFailed, true)
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
}
