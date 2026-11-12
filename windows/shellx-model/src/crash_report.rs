//! Crash files, the start-failure file and the crash reporter's dialog: file names, report
//! texts, dialog sentences (Ruling 1: Part B's sentences live here, not in `strings`) and the
//! reporter's command line. The panic hook and the reporter process are `shellx-app`'s
//! `crash`.

#[cfg(test)]
mod tests {
    use super::*;
    use crate::redact::redact;
    use crate::strings::Lang;

    const T43: &str = "AbCdEfGhIjKlMnOpQrStUvWxYz0123456789_-AbCdE"; // 43 chars, base64url
    const COMMIT: &str = "5dd1e2dc6a0123456789abcdef0123456789abcd";

    fn facts() -> PanicFacts {
        PanicFacts {
            utc: "20261112-081530".into(),
            version: "1.7.0".into(),
            commit: COMMIT.into(),
            build: "release".into(),
            windows: "10.0.26100".into(),
            exe_base: Some(0x7FF6_A000_0000),
            thread_id: Some(4242),
            main_thread: true,
            location: "src/ui/app.rs:120:13".into(),
            message: "crash test: a panic on the UI thread".into(),
            backtrace: "   0:     0x7ff6a1b2c3d4 - <unknown>".into(),
        }
    }

    #[test]
    fn crash_file_names_survive_the_redactor() {
        let kinds = [
            CrashFileKind::Panic,
            CrashFileKind::Native,
            CrashFileKind::WindowFailed,
            CrashFileKind::Diagnostics,
        ];
        for kind in kinds {
            for pid in [0, 1234, u32::MAX] {
                let name = crash_file_name(kind, "20261112-081530", pid);
                assert_eq!(redact(&name), name);
                let numbered = numbered_file_name(&name, 99);
                assert_eq!(redact(&numbered), numbered);
                assert!(numbered.ends_with(&format!(".{pid}.99.txt")), "{numbered}");
            }
        }
        assert_eq!(
            crash_file_name(CrashFileKind::Diagnostics, "20261112-081530", 1234),
            "diagnostics.20261112-081530.1234.txt"
        );
        assert_eq!(
            crash_file_name(CrashFileKind::Panic, "20261112-081530", 42),
            "crash.20261112-081530.42.txt"
        );
        assert_eq!(
            crash_file_name(CrashFileKind::Native, "20261112-081530", 42),
            "crash-native.20261112-081530.42.txt"
        );
        assert_eq!(
            crash_file_name(CrashFileKind::WindowFailed, "20261112-081530", 42),
            "start-failed.20261112-081530.42.txt"
        );
        assert_eq!(
            numbered_file_name("crash.20261112-081530.42.txt", 2),
            "crash.20261112-081530.42.2.txt"
        );
    }

    #[test]
    fn panic_report_is_redacted_line_by_line() {
        let f = PanicFacts {
            message: format!("login failed for a@b.co\nwith {T43} and code 123456"),
            backtrace: format!(
                "   0:     0x7ff6a1b2c3d4 - shellx_desktop::ui::app::run\n   1: user a@b.co\n   2: {T43}\n   3:     0x7ff6a1b2c3d4 - <unknown>\n   4: the code 123456"
            ),
            ..facts()
        };
        let text = panic_report(&f);
        for secret in ["a@b.co", T43, "123456"] {
            assert!(!text.contains(secret), "{secret} in {text}");
        }
        let lines: Vec<&str> = text.lines().collect();
        assert_eq!(lines[0], "ShellX crash report");
        for line in [
            "kind: panic",
            "version: 1.7.0",
            "commit: 5dd1e2dc6a0123456789abcdef0123456789abcd",
            "build: release",
            "windows: 10.0.26100",
            "exe base: 0x00007FF6A0000000",
            "time: 2026-11-12 08:15:30 UTC",
            "thread: 4242 (main: yes)",
            "location: src/ui/app.rs:120:13",
            "backtrace:",
            "   3:     0x7ff6a1b2c3d4 - <unknown>",
        ] {
            assert!(lines.contains(&line), "{line:?} missing in {text}");
        }
        assert!(lines.iter().any(|l| l.starts_with("message: login failed for ")));
        assert!(text.ends_with('\n'));
        let unknown = panic_report(&PanicFacts {
            exe_base: None,
            thread_id: None,
            main_thread: false,
            commit: String::new(),
            ..facts()
        });
        for line in ["exe base: unknown", "thread: unknown (main: no)", "commit: unknown"] {
            assert!(unknown.lines().any(|l| l == line), "{line:?} in {unknown}");
        }
    }

    #[test]
    fn panic_report_cuts_quoted_text_and_long_messages() {
        let text = panic_report(&PanicFacts {
            message: "byte index 3 is not a char boundary; it is inside 'ế' (bytes 2..5) of `tiếng Việt bí mật`".into(),
            ..facts()
        });
        let line = text.lines().find(|l| l.starts_with("message:")).unwrap();
        assert_eq!(
            line,
            "message: byte index 3 is not a char boundary; it is inside 'ế' (bytes 2..5)"
        );
        assert!(!text.contains("bí mật"), "{text}");
        // a quoted part in another message is kept (only the slicing message quotes the text)
        let other = panic_report(&PanicFacts {
            message: "called `Option::unwrap()` on a `None` value".into(),
            ..facts()
        });
        assert!(other.contains("message: called `Option::unwrap()` on a `None` value"));
        // at most 300 characters of message, over all its lines
        let long = "ab ".repeat(333) + "z"; // 1000 characters
        let text = panic_report(&PanicFacts {
            message: long,
            ..facts()
        });
        let line = text.lines().find(|l| l.starts_with("message: ")).unwrap();
        assert!(line.chars().count() <= "message: ".len() + 300, "{line}");
        assert!(!line.contains('z'), "{line}"); // the 1000th character is cut
        let text = panic_report(&PanicFacts {
            message: "x\n".repeat(400),
            ..facts()
        });
        let message_chars: usize = text
            .lines()
            .skip_while(|l| !l.starts_with("message: "))
            .take_while(|l| *l != "backtrace:")
            .map(|l| l.trim_start_matches("message: ").trim().chars().count())
            .sum();
        assert!(message_chars <= 300, "{message_chars}");
    }

    #[test]
    fn abort_follow_ups_are_recognised() {
        assert_eq!(
            follow_up_line("panic in a function that cannot unwind").as_deref(),
            Some("then: panic in a function that cannot unwind (the process aborts)")
        );
        assert_eq!(
            follow_up_line("panic in a destructor during cleanup").as_deref(),
            Some("then: panic in a destructor during cleanup (the process aborts)")
        );
        assert_eq!(follow_up_line("the real panic"), None);
        assert_eq!(follow_up_line(""), None);
        assert_eq!(follow_up_line("not a panic in a function that cannot unwind"), None);
    }

    #[test]
    fn dialog_text_names_the_file_in_both_languages() {
        let path = r"C:\Users\Phú Lê\AppData\Local\ShellX\native\logs\crash.20261112-081530.42.txt";
        assert_eq!(
            report_dialog(Lang::Vi, DialogKind::Crash, path),
            DialogText {
                title: "ShellX gặp lỗi".into(),
                body: format!(
                    "ShellX gặp lỗi và đã lưu chi tiết vào:\n{path}\n\nMở thư mục chứa file này? Hãy gửi file cho đội ShellX để được giúp."
                ),
            }
        );
        assert_eq!(
            report_dialog(Lang::En, DialogKind::Crash, path),
            DialogText {
                title: "ShellX ran into a problem".into(),
                body: format!(
                    "ShellX ran into a problem and saved the details to:\n{path}\n\nOpen the folder that contains it? Send the file to the ShellX team to get help."
                ),
            }
        );
        assert_eq!(
            report_dialog(Lang::Vi, DialogKind::WindowFailed, path),
            DialogText {
                title: "ShellX không mở được cửa sổ".into(),
                body: format!(
                    "ShellX không mở được cửa sổ. Chi tiết nằm trong:\n{path}\n\nMở thư mục chứa file này? Hãy gửi file cho đội ShellX để được giúp."
                ),
            }
        );
        assert_eq!(
            report_dialog(Lang::En, DialogKind::WindowFailed, path),
            DialogText {
                title: "ShellX couldn't open its window".into(),
                body: format!(
                    "ShellX couldn't open its window. The details are in:\n{path}\n\nOpen the folder that contains it? Send the file to the ShellX team to get help."
                ),
            }
        );
    }

    #[test]
    fn reporter_command_line_quotes_paths_with_spaces_and_vietnamese() {
        let exe = r"C:\Users\Phú Lê\AppData\Local\Programs\ShellX Native\shellx-desktop.exe";
        let file = r"C:\Users\Phú Lê\AppData\Local\ShellX\native\logs\crash.20261112-081530.42.txt";
        assert_eq!(
            reporter_command_line(exe, "--report-crash", file),
            r#""C:\Users\Phú Lê\AppData\Local\Programs\ShellX Native\shellx-desktop.exe" --report-crash "C:\Users\Phú Lê\AppData\Local\ShellX\native\logs\crash.20261112-081530.42.txt""#
        );
        assert_eq!(DialogKind::Crash.reporter_flag(), "--report-crash");
        assert_eq!(DialogKind::WindowFailed.reporter_flag(), "--report-window");
    }

    #[test]
    fn the_start_failure_report_has_the_header_the_render_line_and_the_chain() {
        let text = window_failure_report(&WindowFailureFacts {
            utc: "20261112-081530".into(),
            version: "1.7.0".into(),
            commit: COMMIT.into(),
            build: "release test".into(),
            windows: "10.0.26100".into(),
            exe_base: None,
            render: Some("render mode: standard (default)".into()),
            errors: vec![
                "could not open the window".into(),
                format!("signed in as a@b.co\nwith {T43}"),
            ],
        });
        let lines: Vec<&str> = text.lines().collect();
        assert_eq!(lines[0], "ShellX crash report");
        assert_eq!(lines[1], "kind: window not opened");
        assert!(lines.contains(&"render mode: standard (default)"), "{text}");
        assert!(lines.contains(&"error: could not open the window"), "{text}");
        assert!(lines.iter().any(|l| l.starts_with("caused by: signed in as ")), "{text}");
        assert!(!text.contains("a@b.co") && !text.contains(T43), "{text}");
        let none = window_failure_report(&WindowFailureFacts {
            render: None,
            errors: vec![],
            ..WindowFailureFacts::default()
        });
        assert!(!none.contains("render mode"), "{none}");
        assert!(none.lines().any(|l| l == "error: unknown"), "{none}");
    }
}
