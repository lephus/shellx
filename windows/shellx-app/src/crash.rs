//! Crash files and the crash reporter (spec §4.2 "Không lỗi nào im lặng", Rulings 8, 9, 13).

#[cfg(test)]
mod tests {
    use std::cell::RefCell;
    use std::path::{Path, PathBuf};

    use super::*;

    const T43: &str = "AbCdEfGhIjKlMnOpQrStUvWxYz0123456789_-AbCdE"; // 43 chars, base64url

    fn ctx(dir: &Path) -> CrashContext {
        CrashContext {
            logs_dir: dir.join("logs"),
            exe: PathBuf::from("/nowhere/shellx-desktop"),
            version: "1.7.0".into(),
            commit: "unknown".into(),
            build: "release".into(),
            windows: "10.0.26100".into(),
            exe_base: Some(0x7FF6_A000_0000),
            main_thread_id: Some(7),
        }
    }

    fn parts(message: &str, location: &str) -> PanicParts {
        PanicParts {
            utc: "20261112-081530".into(),
            location: location.into(),
            message: message.into(),
            backtrace: "   0:     0x7ff6a1b2c3d4 - <unknown>".into(),
            thread_id: Some(7),
            main_thread: true,
        }
    }

    fn files_in(dir: &Path) -> Vec<String> {
        let mut names: Vec<String> = std::fs::read_dir(dir)
            .unwrap()
            .map(|e| e.unwrap().file_name().to_string_lossy().into_owned())
            .collect();
        names.sort();
        names
    }

    #[test]
    fn the_hook_writes_a_file_and_asks_for_one_reporter() {
        let tmp = tempfile::tempdir().unwrap();
        let ctx = ctx(tmp.path());
        let state = HookState::new();
        let spawned: RefCell<Vec<PathBuf>> = RefCell::new(Vec::new());
        let spawn = |file: &Path| {
            spawned.borrow_mut().push(file.to_path_buf());
            true
        };
        let pid = std::process::id();
        let first = handle_panic(
            &ctx,
            &parts("the first panic", "src/a.rs:1:1"),
            HookMode::Dialog,
            &state,
            &spawn,
        )
        .unwrap();
        let second = handle_panic(
            &ctx,
            &parts("another panic", "src/b.rs:2:2"),
            HookMode::Dialog,
            &state,
            &spawn,
        )
        .unwrap();
        assert_eq!(
            first,
            ctx.logs_dir.join(format!("crash.20261112-081530.{pid}.txt"))
        );
        assert_eq!(
            second,
            ctx.logs_dir.join(format!("crash.20261112-081530.{pid}.2.txt"))
        );
        let one = std::fs::read_to_string(&first).unwrap();
        let two = std::fs::read_to_string(&second).unwrap();
        assert!(one.lines().any(|l| l == "location: src/a.rs:1:1"), "{one}");
        assert!(two.lines().any(|l| l == "location: src/b.rs:2:2"), "{two}");
        assert!(one.lines().any(|l| l == "message: the first panic"), "{one}");
        assert_eq!(*spawned.borrow(), vec![first]);
    }

    #[test]
    fn an_abort_follow_up_is_appended_to_the_first_report() {
        let tmp = tempfile::tempdir().unwrap();
        let ctx = ctx(tmp.path());
        let state = HookState::new();
        let spawned = RefCell::new(0);
        let spawn = |_: &Path| {
            *spawned.borrow_mut() += 1;
            true
        };
        let first = handle_panic(
            &ctx,
            &parts("the real panic", "src/ui/app.rs:9:9"),
            HookMode::Dialog,
            &state,
            &spawn,
        )
        .unwrap();
        let second = handle_panic(
            &ctx,
            &parts(
                "panic in a function that cannot unwind",
                "/rustc/0000/library/core/src/panicking.rs:225:5",
            ),
            HookMode::Dialog,
            &state,
            &spawn,
        )
        .unwrap();
        assert_eq!(second, first);
        assert_eq!(files_in(&ctx.logs_dir).len(), 1);
        let text = std::fs::read_to_string(&first).unwrap();
        let locations: Vec<&str> = text.lines().filter(|l| l.starts_with("location:")).collect();
        assert_eq!(locations, vec!["location: src/ui/app.rs:9:9"]);
        let thens: Vec<&str> = text.lines().filter(|l| l.starts_with("then:")).collect();
        assert_eq!(
            thens,
            vec!["then: panic in a function that cannot unwind (the process aborts)"]
        );
        assert_eq!(text.lines().last(), Some(thens[0]));
        assert_eq!(*spawned.borrow(), 1);
    }

    #[test]
    fn a_caught_panic_writes_a_file_but_starts_no_reporter() {
        let tmp = tempfile::tempdir().unwrap();
        let ctx = ctx(tmp.path());
        let state = HookState::new();
        let spawned = RefCell::new(0);
        let spawn = |_: &Path| {
            *spawned.borrow_mut() += 1;
            true
        };
        let caught = expect_caught(|| {
            handle_panic(
                &ctx,
                &parts("a core call panicked", "src/x.rs:1:1"),
                HookMode::Dialog,
                &state,
                &spawn,
            )
        })
        .unwrap();
        assert!(caught.is_file());
        assert_eq!(*spawned.borrow(), 0);
        // FileOnly writes the file and starts no reporter either.
        let file_only = handle_panic(
            &ctx,
            &parts("in --smoke", "src/y.rs:1:1"),
            HookMode::FileOnly,
            &state,
            &spawn,
        )
        .unwrap();
        assert!(file_only.is_file());
        assert_eq!(*spawned.borrow(), 0);
        // Outside expect_caught, in Dialog mode, the reporter starts.
        handle_panic(
            &ctx,
            &parts("a real one", "src/z.rs:1:1"),
            HookMode::Dialog,
            &state,
            &spawn,
        );
        assert_eq!(*spawned.borrow(), 1);
        assert_eq!(files_in(&ctx.logs_dir).len(), 3);
    }

    #[test]
    fn the_start_failure_file_is_redacted() {
        let tmp = tempfile::tempdir().unwrap();
        let ctx = ctx(tmp.path());
        let error = anyhow::anyhow!("the relay refused token {T43}")
            .context("signed in as a@b.co")
            .context("could not open the window");
        let file =
            write_window_failure(&ctx, &error, Some("render mode: standard (default)")).unwrap();
        let name = file.file_name().unwrap().to_string_lossy().into_owned();
        assert!(name.starts_with("start-failed.") && name.ends_with(".txt"), "{name}");
        let text = std::fs::read_to_string(&file).unwrap();
        assert!(text.lines().any(|l| l == "render mode: standard (default)"), "{text}");
        assert!(text.lines().any(|l| l == "error: could not open the window"), "{text}");
        assert!(!text.contains("a@b.co") && !text.contains(T43), "{text}");
    }

    #[test]
    fn crash_test_flags_are_read_from_the_arguments() {
        use std::ffi::OsString;
        let args = |v: &[&str]| v.iter().map(OsString::from).collect::<Vec<_>>();
        assert_eq!(crash_test_from(&args(&["--crash-test", "panic"])), Some(CrashTest::Panic));
        assert_eq!(crash_test_from(&args(&["--crash-test", "native"])), Some(CrashTest::Native));
        assert_eq!(crash_test_from(&args(&["x", "--crash-test", "window"])), Some(CrashTest::Window));
        assert_eq!(crash_test_from(&args(&["--crash-test", "other"])), None);
        assert_eq!(crash_test_from(&args(&["--crash-test"])), None);
        assert_eq!(crash_test_from(&args(&["panic"])), None);
        set_crash_test(Some(CrashTest::Window));
        assert_eq!(crash_test(), Some(CrashTest::Window));
        set_crash_test(None);
        assert_eq!(crash_test(), None);
    }

    #[test]
    fn explorer_comes_from_the_system_root() {
        assert_eq!(
            explorer_exe(Some(r"D:\Windows".into())),
            PathBuf::from(r"D:\Windows").join("explorer.exe")
        );
        assert_eq!(
            explorer_exe(None),
            PathBuf::from(r"C:\Windows").join("explorer.exe")
        );
        assert_eq!(
            explorer_exe(Some("Windows".into())),
            PathBuf::from(r"C:\Windows").join("explorer.exe")
        );
    }
}
