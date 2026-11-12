//! The log file's rules: UTC timestamps, one redacted line per text line, repeated records
//! collapsed into a count line. The file itself (rotation, writing) is `shellx-app`'s
//! `logger`.

use crate::redact::redact;

/// A write that would take `shellx.log` past this size first rotates it (Ruling 12).
pub const LOG_FILE_MAX_BYTES: u64 = 1_048_576;
/// `shellx.log`, `shellx.log.1`, `shellx.log.2`.
pub const LOG_FILES_KEPT: usize = 3;
/// At most this many repeats are folded into one count line.
const MAX_REPEATS_PER_COUNT_LINE: u32 = 1000;

/// (year, month, day, hour, minute, second) in UTC for seconds since 1970.
fn utc_parts(unix_secs: u64) -> (u64, u64, u64, u64, u64, u64) {
    let days = unix_secs / 86_400;
    let rest = unix_secs % 86_400;
    // Civil date from a day count (H. Hinnant's algorithm), for days >= 0.
    let z = days + 719_468;
    let era = z / 146_097;
    let doe = z - era * 146_097; // [0, 146096]
    let yoe = (doe - doe / 1_460 + doe / 36_524 - doe / 146_096) / 365; // [0, 399]
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100); // [0, 365]
    let mp = (5 * doy + 2) / 153; // [0, 11], March first
    let day = doy - (153 * mp + 2) / 5 + 1;
    let month = if mp < 10 { mp + 3 } else { mp - 9 };
    let year = yoe + era * 400 + u64::from(month <= 2);
    (year, month, day, rest / 3_600, rest % 3_600 / 60, rest % 60)
}

/// `2026-11-12T08:15:30.123Z` for milliseconds since 1970.
pub fn utc_timestamp(unix_millis: u64) -> String {
    let (y, mo, d, h, mi, s) = utc_parts(unix_millis / 1_000);
    format!(
        "{y:04}-{mo:02}-{d:02}T{h:02}:{mi:02}:{s:02}.{:03}Z",
        unix_millis % 1_000
    )
}

/// `20261112-081530` for seconds since 1970: the time part of file names in the logs folder.
pub fn compact_utc(unix_secs: u64) -> String {
    let (y, mo, d, h, mi, s) = utc_parts(unix_secs);
    format!("{y:04}{mo:02}{d:02}-{h:02}{mi:02}{s:02}")
}

/// One log record as text: `<ts> <LEVEL> <target>: <first line>` and `  <next line>` for
/// each further line of the message, each ending in `\n` and each passed through `redact`.
/// CRLF line ends and a trailing newline make no extra lines; a stray `\r` becomes a space.
pub fn format_record(timestamp: &str, level: &str, target: &str, message: &str) -> String {
    let mut lines = message.lines();
    let first = lines.next().unwrap_or("").replace('\r', " ");
    let mut out = redact(&format!("{timestamp} {level} {target}: {first}"));
    out.push('\n');
    for line in lines {
        out.push_str(&redact(&format!("  {}", line.replace('\r', " "))));
        out.push('\n');
    }
    out
}

/// The count line for `n` folded repeats: fixed text, never the record's.
fn count_line(timestamp: &str, n: u32) -> String {
    let mut line = redact(&format!(
        "{timestamp} INFO shellx: the line above repeated {n} more times"
    ));
    line.push('\n');
    line
}

/// Folds identical consecutive records (a GPU error on every frame) so the three files keep
/// what came before them.
#[derive(Debug, Default)]
pub struct LineDedup {
    last: Option<String>,
    repeats: u32,
}

impl LineDedup {
    /// `key` identifies the record (level, target and message); `line` is its formatted text.
    /// Returns what to write, in order: a record whose key equals the previous one writes
    /// nothing and is counted; the next other key writes the count line first, then its own
    /// line; the 1000th repeat writes the count line at once and counting starts again.
    pub fn push(&mut self, key: &str, line: String, timestamp: &str) -> Vec<String> {
        if self.last.as_deref() == Some(key) {
            self.repeats += 1;
            if self.repeats >= MAX_REPEATS_PER_COUNT_LINE {
                let n = std::mem::take(&mut self.repeats);
                return vec![count_line(timestamp, n)];
            }
            return Vec::new();
        }
        let mut out = Vec::with_capacity(2);
        if self.repeats > 0 {
            out.push(count_line(timestamp, std::mem::take(&mut self.repeats)));
        }
        self.last = Some(key.to_string());
        out.push(line);
        out
    }
}

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
        assert!(
            lines[0].starts_with("T WARN shellx: login failed for "),
            "{out}"
        );
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
