//! `--diagnose`: the diagnostics report (spec §4.7, Rulings 30, 36, 38; plan 3b §6).

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
}
