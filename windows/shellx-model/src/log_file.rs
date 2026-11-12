//! The log file's rules: UTC timestamps, one redacted line per text line, repeated records
//! collapsed into a count line. The file itself (rotation, writing) is `shellx-app`'s
//! `logger`.

#[cfg(test)]
mod tests {
    use super::*;

    const T43: &str = "AbCdEfGhIjKlMnOpQrStUvWxYz0123456789_-AbCdE"; // 43 chars, base64url

    #[test]
    fn utc_timestamps_are_iso_8601() {
        assert_eq!(utc_timestamp(0), "1970-01-01T00:00:00.000Z");
        assert_eq!(utc_timestamp(1_762_934_400_123), "2025-11-12T08:00:00.123Z");
        assert_eq!(compact_utc(1_762_934_400), "20251112-080000");
        // 2000-02-29, a leap day of a century leap year
        assert_eq!(utc_timestamp(951_782_400_000), "2000-02-29T00:00:00.000Z");
        assert_eq!(compact_utc(951_782_400 + 86_399), "20000229-235959");
        assert_eq!(compact_utc(0), "19700101-000000");
    }

    #[test]
    fn records_are_one_line_per_text_line_and_redacted() {
        assert_eq!(
            format_record(
                "T",
                "INFO",
                "gpui::platform::windows",
                "Using GPU: Intel(R) UHD Graphics 620"
            ),
            "T INFO gpui::platform::windows: Using GPU: Intel(R) UHD Graphics 620\n"
        );
        let out = format_record(
            "T",
            "WARN",
            "shellx",
            &format!("login failed for a@b.co\ntoken {T43}"),
        );
        let lines: Vec<&str> = out.lines().collect();
        assert_eq!(lines.len(), 2, "{out}");
        assert!(out.ends_with('\n'));
        assert!(lines[0].starts_with("T WARN shellx: login failed for "), "{out}");
        assert!(lines[1].starts_with("  "), "{out}");
        assert!(!out.contains("a@b.co"), "{out}");
        assert!(!out.contains(T43), "{out}");
        // CRLF and a trailing newline make no empty or broken lines
        let out = format_record("T", "INFO", "x", "one\r\ntwo\r\n");
        assert_eq!(out, "T INFO x: one\n  two\n");
        assert_eq!(format_record("T", "INFO", "x", ""), "T INFO x: \n");
        let out = format_record("T", "INFO", "x", "your code 123456");
        assert!(!out.contains("123456"), "{out}");
    }

    #[test]
    fn repeats_collapse_into_one_count_line() {
        let mut d = LineDedup::default();
        let mut written: Vec<String> = Vec::new();
        for _ in 0..5 {
            written.extend(d.push("INFO x", "x line\n".to_string(), "T1"));
        }
        written.extend(d.push("INFO y", "y line\n".to_string(), "T2"));
        assert_eq!(
            written,
            vec![
                "x line\n".to_string(),
                "T2 INFO shellx: the line above repeated 4 more times\n".to_string(),
                "y line\n".to_string(),
            ]
        );

        // 1001 identical records: the first is written, the next 1000 make one count line
        // when the 1000th repeat arrives, and counting starts again.
        let mut d = LineDedup::default();
        let mut written: Vec<String> = Vec::new();
        for i in 0..1001 {
            let out = d.push("INFO x", "x line\n".to_string(), "T");
            if i == 1000 {
                assert_eq!(
                    out,
                    vec!["T INFO shellx: the line above repeated 1000 more times\n".to_string()]
                );
            }
            written.extend(out);
        }
        assert_eq!(written.len(), 2, "{written:?}");
        assert!(d.push("INFO x", "x line\n".to_string(), "T").is_empty());
        assert_eq!(
            d.push("INFO z", "z line\n".to_string(), "T"),
            vec![
                "T INFO shellx: the line above repeated 1 more times\n".to_string(),
                "z line\n".to_string()
            ]
        );
    }

    #[test]
    fn repeat_lines_carry_no_message_text() {
        let key = format!("WARN shellx sign-in failed for a@b.co with {T43}");
        let mut d = LineDedup::default();
        let line = format_record("T", "WARN", "shellx", &key);
        let first = d.push(&key, line, "T");
        assert_eq!(first.len(), 1);
        assert!(d.push(&key, String::new(), "T").is_empty());
        let out = d.push("other", "other\n".to_string(), "T");
        let count = &out[0];
        assert!(count.contains("repeated 1 more times"), "{count}");
        for secret in ["a@b.co", T43, key.as_str(), "sign-in failed"] {
            assert!(!count.contains(secret), "{count}");
        }
    }
}
