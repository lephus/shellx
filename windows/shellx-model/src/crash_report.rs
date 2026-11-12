//! Crash files, the start-failure file and the crash reporter's dialog: file names, report
//! texts, dialog sentences (Ruling 1: Part B's sentences live here, not in `strings`) and the
//! reporter's command line. The panic hook and the reporter process are `shellx-app`'s
//! `crash`.
//!
//! Every report line goes through `redact`. File names join their parts with `.` (Ruling 13):
//! the redactor hides a 32+ character run of letters, digits and `-` that holds a digit, which
//! a `-`-joined name with a large pid would reach.

use crate::redact::redact;
use crate::strings::Lang;

/// What a file in the logs folder holds.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum CrashFileKind {
    Panic,
    Native,
    WindowFailed,
    Diagnostics,
}

/// `crash.20261112-081530.1234.txt`, `crash-native.…`, `start-failed.…`, `diagnostics.…`:
/// the kind, the UTC time (`log_file::compact_utc`) and the pid, joined with `.`.
pub fn crash_file_name(kind: CrashFileKind, compact_utc: &str, pid: u32) -> String {
    let prefix = match kind {
        CrashFileKind::Panic => "crash",
        CrashFileKind::Native => "crash-native",
        CrashFileKind::WindowFailed => "start-failed",
        CrashFileKind::Diagnostics => "diagnostics",
    };
    format!("{prefix}.{compact_utc}.{pid}.txt")
}

/// The `n`th file of the same name (n ≥ 2): `crash.X.P.txt` → `crash.X.P.<n>.txt`, for two
/// panics in the same second.
pub fn numbered_file_name(name: &str, n: u32) -> String {
    let stem = name.strip_suffix(".txt").unwrap_or(name);
    format!("{stem}.{n}.txt")
}

/// The messages std gives the second hook call when a panic unwinds into a function that
/// cannot unwind (Ruling 9); the process aborts right after.
const ABORT_MESSAGES: [&str; 2] = [
    "panic in a function that cannot unwind",
    "panic in a destructor during cleanup",
];

/// Most characters of a panic message a report keeps (plan review M-16).
pub const PANIC_MESSAGE_MAX_CHARS: usize = 300;

/// `Some("then: <message> (the process aborts)")` for a message that is, or starts with, one
/// of std's abort messages: the line the hook appends to the report of the real panic.
pub fn follow_up_line(message: &str) -> Option<String> {
    if !ABORT_MESSAGES.iter().any(|m| message.starts_with(m)) {
        return None;
    }
    let first = message.lines().next().unwrap_or("");
    let first: String = first.chars().take(PANIC_MESSAGE_MAX_CHARS).collect();
    Some(redact(&format!("then: {first} (the process aborts)")))
}

/// What a panic report says. `utc` is `log_file::compact_utc` (the file name's time);
/// `backtrace` is `format!("{bt:#}")`, which keeps every frame's address (Ruling 11).
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct PanicFacts {
    pub utc: String,
    pub version: String,
    pub commit: String,
    pub build: String,
    pub windows: String,
    pub exe_base: Option<u64>,
    pub thread_id: Option<u32>,
    pub main_thread: bool,
    pub location: String,
    pub message: String,
    pub backtrace: String,
}

/// What a start-failure file says (`start-failed.….txt`): the header facts, the optional
/// `render mode: …` line (B6) and the error chain, outermost first.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct WindowFailureFacts {
    pub utc: String,
    pub version: String,
    pub commit: String,
    pub build: String,
    pub windows: String,
    pub exe_base: Option<u64>,
    pub render: Option<String>,
    pub errors: Vec<String>,
}

/// One value on one line; blank reads `unknown`.
fn value(text: &str) -> String {
    let one_line = text.split(['\r', '\n']).collect::<Vec<_>>().join(" ");
    let one_line = one_line.trim();
    if one_line.is_empty() {
        "unknown".to_string()
    } else {
        one_line.to_string()
    }
}

/// `20261112-081530` → `2026-11-12 08:15:30 UTC`; anything else as it is.
fn readable_utc(compact: &str) -> String {
    let b = compact.as_bytes();
    let digits = |r: std::ops::Range<usize>| b[r].iter().all(u8::is_ascii_digit);
    if b.len() == 15 && b[8] == b'-' && digits(0..8) && digits(9..15) {
        format!(
            "{}-{}-{} {}:{}:{} UTC",
            &compact[0..4],
            &compact[4..6],
            &compact[6..8],
            &compact[9..11],
            &compact[11..13],
            &compact[13..15]
        )
    } else {
        value(compact)
    }
}

/// The lines every ShellX crash file starts with; the native report (B5) has the same order.
fn header(
    kind: &str,
    utc: &str,
    version: &str,
    commit: &str,
    build: &str,
    windows: &str,
    exe_base: Option<u64>,
) -> Vec<String> {
    vec![
        "ShellX crash report".to_string(),
        format!("kind: {kind}"),
        format!("version: {}", value(version)),
        format!("commit: {}", value(commit)),
        format!("build: {}", value(build)),
        format!("windows: {}", value(windows)),
        match exe_base {
            Some(base) => format!("exe base: 0x{base:016X}"),
            None => "exe base: unknown".to_string(),
        },
        format!("time: {}", readable_utc(utc)),
    ]
}

/// The lines joined with `\n`, each redacted, ending in `\n`.
fn redacted_text(lines: &[String]) -> String {
    let mut out = String::new();
    for line in lines {
        out.push_str(&redact(line));
        out.push('\n');
    }
    out
}

/// A message as a report keeps it (plan review M-16): std's string-slicing message quotes the
/// text it sliced after " of `", so a message starting with "byte index" is cut there; then
/// every message is capped at `PANIC_MESSAGE_MAX_CHARS` characters. The redactor does not
/// catch typed or terminal text, so this runs before it.
fn kept_message(message: &str) -> String {
    let cut = if message.starts_with("byte index") {
        message.find(" of `").map_or(message, |i| &message[..i])
    } else {
        message
    };
    cut.chars().take(PANIC_MESSAGE_MAX_CHARS).collect()
}

/// The panic crash file: the header, `thread:`, `location:`, `message:` (further lines
/// indented), `backtrace:` and its lines unchanged; every line redacted.
pub fn panic_report(f: &PanicFacts) -> String {
    let mut lines = header(
        "panic", &f.utc, &f.version, &f.commit, &f.build, &f.windows, f.exe_base,
    );
    let main = if f.main_thread { "yes" } else { "no" };
    lines.push(match f.thread_id {
        Some(id) => format!("thread: {id} (main: {main})"),
        None => format!("thread: unknown (main: {main})"),
    });
    lines.push(format!("location: {}", value(&f.location)));
    let message = kept_message(&f.message);
    let mut message_lines = message.lines();
    lines.push(format!("message: {}", message_lines.next().unwrap_or("")));
    lines.extend(message_lines.map(|l| format!("  {l}")));
    lines.push("backtrace:".to_string());
    lines.extend(f.backtrace.lines().map(str::to_string));
    redacted_text(&lines)
}

/// The start-failure file: the header, the `render mode:` line when given, `error: <outer>`
/// and `caused by: <inner>` for the rest of the chain (further lines indented); every line
/// redacted.
pub fn window_failure_report(f: &WindowFailureFacts) -> String {
    let mut lines = header(
        "window not opened",
        &f.utc,
        &f.version,
        &f.commit,
        &f.build,
        &f.windows,
        f.exe_base,
    );
    if let Some(render) = &f.render {
        lines.push(value(render));
    }
    if f.errors.is_empty() {
        lines.push("error: unknown".to_string());
    }
    for (i, error) in f.errors.iter().enumerate() {
        let label = if i == 0 { "error" } else { "caused by" };
        let mut error_lines = error.lines();
        lines.push(format!("{label}: {}", error_lines.next().unwrap_or("")));
        lines.extend(error_lines.map(|l| format!("  {l}")));
    }
    redacted_text(&lines)
}

/// The first seven lines of the native crash file (3b §2), each redacted, each ending in
/// `\n`: the same header as the panic file, without the `time:` line, which the filter writes
/// with the crash's own time. Built once at start-up, when allocating is allowed.
pub fn native_report_header(
    version: &str,
    commit: &str,
    build: &str,
    windows: &str,
    exe_base: Option<u64>,
) -> String {
    let mut lines = header(
        "native exception",
        "",
        version,
        commit,
        build,
        windows,
        exe_base,
    );
    lines.pop(); // the time line
    redacted_text(&lines)
}

/// What the unhandled-exception filter knows about a native crash, all of it borrowed or on
/// the stack: `utc` is `[year, month, day, hour, minute, second]` (`GetSystemTime`), `header`
/// the bytes of `native_report_header`, `module` the UTF-16 name from `GetModuleFileNameW`
/// (empty when unknown).
#[derive(Clone, Copy, Debug)]
pub struct NativeFacts<'a> {
    pub utc: [u16; 6],
    pub header: &'a [u8],
    pub code: u32,
    pub address: u64,
    pub module: &'a [u16],
    pub module_offset: Option<u64>,
    pub thread_id: u32,
}

/// A writer over a fixed buffer for the exception filter: no allocation, no formatting
/// machinery, no slicing that can panic. Once something does not fit, it writes nothing more,
/// so the output is always a prefix of the whole report, cut on a character boundary.
struct FixedWriter<'b> {
    out: &'b mut [u8],
    len: usize,
    full: bool,
}

impl FixedWriter<'_> {
    /// Copies `bytes` (valid UTF-8) or the longest prefix of it that ends on a character
    /// boundary and fits; a cut marks the writer full.
    fn utf8(&mut self, bytes: &[u8]) {
        if self.full {
            return;
        }
        let room = self.out.len().saturating_sub(self.len);
        let mut n = bytes.len();
        if n > room {
            self.full = true;
            n = room;
            // Back up to a character boundary: a UTF-8 continuation byte is 0b10xx_xxxx.
            while n > 0 && bytes.get(n).is_some_and(|b| b & 0xC0 == 0x80) {
                n -= 1;
            }
        }
        if let (Some(dst), Some(src)) = (self.out.get_mut(self.len..), bytes.get(..n)) {
            for (d, s) in dst.iter_mut().zip(src) {
                *d = *s;
            }
            self.len += n;
        }
    }

    /// One character, whole or not at all.
    fn char(&mut self, c: char) {
        let mut scratch = [0u8; 4];
        let encoded = c.encode_utf8(&mut scratch);
        if self.out.len().saturating_sub(self.len) < encoded.len() {
            self.full = true;
        }
        self.utf8(encoded.as_bytes());
    }

    /// `value` in decimal, at least `width` digits (zero-padded).
    fn decimal(&mut self, value: u64, width: usize) {
        let mut digits = [b'0'; 20];
        let mut i = digits.len();
        let mut v = value;
        loop {
            i -= 1;
            if let Some(d) = digits.get_mut(i) {
                *d = b'0' + (v % 10) as u8;
            }
            v /= 10;
            if v == 0 || i == 0 {
                break;
            }
        }
        let start = i.min(digits.len().saturating_sub(width));
        self.utf8(digits.get(start..).unwrap_or(&[]));
    }

    /// `0x` and `value` in upper-case hex: exactly `width` digits when `width` > 0, else as
    /// few as needed.
    fn hex(&mut self, value: u64, width: usize) {
        const HEX: &[u8; 16] = b"0123456789ABCDEF";
        let mut digits = [b'0'; 16];
        for (i, d) in digits.iter_mut().enumerate() {
            let shift = (15 - i) * 4;
            *d = HEX[((value >> shift) & 0xF) as usize];
        }
        let start = if width > 0 {
            16usize.saturating_sub(width)
        } else {
            let leading = (value.leading_zeros() / 4) as usize;
            leading.min(15)
        };
        self.utf8(b"0x");
        self.utf8(digits.get(start..).unwrap_or(&[]));
    }
}

/// Writes the native crash file into `out` and returns the bytes written: `header`, then
/// `time:`, `exception:` (8 hex digits), `address:` (16), `module: <path> +0x<offset>`
/// (`unknown` without a name, no offset when unknown) and `thread:`. Upper-case hex. No
/// allocation and no panic: the exception filter calls it. Output that does not fit is cut on
/// a character boundary, never past `out`. UTF-16 is decoded with `char::decode_utf16`; a
/// lone surrogate becomes U+FFFD.
pub fn write_native_report(out: &mut [u8], f: &NativeFacts) -> usize {
    let mut w = FixedWriter {
        out,
        len: 0,
        full: false,
    };
    w.utf8(f.header);
    let [year, month, day, hour, minute, second] = f.utc;
    w.utf8(b"time: ");
    w.decimal(u64::from(year), 4);
    w.utf8(b"-");
    w.decimal(u64::from(month), 2);
    w.utf8(b"-");
    w.decimal(u64::from(day), 2);
    w.utf8(b" ");
    w.decimal(u64::from(hour), 2);
    w.utf8(b":");
    w.decimal(u64::from(minute), 2);
    w.utf8(b":");
    w.decimal(u64::from(second), 2);
    w.utf8(b" UTC\nexception: ");
    w.hex(u64::from(f.code), 8);
    w.utf8(b"\naddress: ");
    w.hex(f.address, 16);
    w.utf8(b"\nmodule: ");
    if f.module.is_empty() {
        w.utf8(b"unknown");
    } else {
        for c in char::decode_utf16(f.module.iter().copied()) {
            w.char(c.unwrap_or(char::REPLACEMENT_CHARACTER));
        }
        if let Some(offset) = f.module_offset {
            w.utf8(b" +");
            w.hex(offset, 0);
        }
    }
    w.utf8(b"\nthread: ");
    w.decimal(u64::from(f.thread_id), 0);
    w.utf8(b"\n");
    w.len
}

/// Which dialog the reporter shows.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum DialogKind {
    Crash,
    WindowFailed,
}

impl DialogKind {
    /// The flag that starts the reporter for this dialog: `--report-crash` or
    /// `--report-window`.
    pub fn reporter_flag(self) -> &'static str {
        match self {
            DialogKind::Crash => "--report-crash",
            DialogKind::WindowFailed => "--report-window",
        }
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct DialogText {
    pub title: String,
    pub body: String,
}

/// The reporter's question, naming the file (Yes opens its folder).
pub fn report_dialog(lang: Lang, kind: DialogKind, path: &str) -> DialogText {
    let (title, body) = match (lang, kind) {
        (Lang::Vi, DialogKind::Crash) => (
            "ShellX gặp lỗi",
            format!(
                "ShellX gặp lỗi và đã lưu chi tiết vào:\n{path}\n\nMở thư mục chứa file này? Hãy gửi file cho đội ShellX để được giúp."
            ),
        ),
        (Lang::En, DialogKind::Crash) => (
            "ShellX ran into a problem",
            format!(
                "ShellX ran into a problem and saved the details to:\n{path}\n\nOpen the folder that contains it? Send the file to the ShellX team to get help."
            ),
        ),
        (Lang::Vi, DialogKind::WindowFailed) => (
            "ShellX không mở được cửa sổ",
            format!(
                "ShellX không mở được cửa sổ. Chi tiết nằm trong:\n{path}\n\nMở thư mục chứa file này? Hãy gửi file cho đội ShellX để được giúp."
            ),
        ),
        (Lang::En, DialogKind::WindowFailed) => (
            "ShellX couldn't open its window",
            format!(
                "ShellX couldn't open its window. The details are in:\n{path}\n\nOpen the folder that contains it? Send the file to the ShellX team to get help."
            ),
        ),
    };
    DialogText {
        title: title.to_string(),
        body,
    }
}

/// `"<exe>" <flag> "<file>"`: the reporter's command line for `CreateProcessW` (B5's
/// watchdog). Windows paths cannot hold `"`, and neither path ends in `\` (`.exe`, `.txt`),
/// so plain quotes parse back to the same two paths.
pub fn reporter_command_line(exe: &str, flag: &str, file: &str) -> String {
    format!("\"{exe}\" {flag} \"{file}\"")
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::redact::redact;
    use crate::strings::Lang;

    const T43: &str = "AbCdEfGhIjKlMnOpQrStUvWxYz0123456789_-AbCdE"; // 43 chars, base64url
    const COMMIT: &str = "5dd1e2dc6a9f8e7d6c5b4a39281706f5e4d3c2b1";

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
            "commit: 5dd1e2dc6a9f8e7d6c5b4a39281706f5e4d3c2b1",
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
        assert!(
            lines
                .iter()
                .any(|l| l.starts_with("message: login failed for "))
        );
        assert!(text.ends_with('\n'));
        let unknown = panic_report(&PanicFacts {
            exe_base: None,
            thread_id: None,
            main_thread: false,
            commit: String::new(),
            ..facts()
        });
        for line in [
            "exe base: unknown",
            "thread: unknown (main: no)",
            "commit: unknown",
        ] {
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
        assert_eq!(
            follow_up_line("not a panic in a function that cannot unwind"),
            None
        );
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

    fn native_header() -> String {
        native_report_header(
            "1.7.0",
            COMMIT,
            "release",
            "10.0.26100",
            Some(0x7FF6_A000_0000),
        )
    }

    fn utf16(s: &str) -> Vec<u16> {
        s.encode_utf16().collect()
    }

    /// The report written into a buffer far larger than any report.
    fn full(f: &NativeFacts) -> String {
        let mut big = vec![0u8; 65_536];
        let n = write_native_report(&mut big, f);
        String::from_utf8(big[..n].to_vec()).unwrap()
    }

    #[test]
    fn native_report_formats_codes_addresses_module_and_time() {
        let header = native_header();
        assert_eq!(
            header,
            "ShellX crash report\nkind: native exception\nversion: 1.7.0\n\
             commit: 5dd1e2dc6a9f8e7d6c5b4a39281706f5e4d3c2b1\nbuild: release\n\
             windows: 10.0.26100\nexe base: 0x00007FF6A0000000\n"
        );
        let module =
            utf16(r"C:\Users\Phú Lê\AppData\Local\Programs\ShellX Native\shellx-desktop.exe");
        let f = NativeFacts {
            utc: [2026, 11, 12, 8, 15, 30],
            header: header.as_bytes(),
            code: 0xC000_0005,
            address: 0x0000_7FF6_A1B2_C3D4,
            module: &module,
            module_offset: Some(0x1B2_C3D4),
            thread_id: 4242,
        };
        assert_eq!(
            full(&f),
            format!(
                "{header}time: 2026-11-12 08:15:30 UTC\nexception: 0xC0000005\n\
                 address: 0x00007FF6A1B2C3D4\n\
                 module: C:\\Users\\Phú Lê\\AppData\\Local\\Programs\\ShellX Native\\shellx-desktop.exe +0x1B2C3D4\n\
                 thread: 4242\n"
            )
        );
        // No module name: `unknown`; no offset: no ` +0x…`; zeros keep their width.
        let f = NativeFacts {
            utc: [2026, 1, 2, 3, 4, 5],
            header: b"",
            code: 0,
            address: 0,
            module: &[],
            module_offset: None,
            thread_id: 0,
        };
        assert_eq!(
            full(&f),
            "time: 2026-01-02 03:04:05 UTC\nexception: 0x00000000\n\
             address: 0x0000000000000000\nmodule: unknown\nthread: 0\n"
        );
        let module = utf16("a.dll");
        let f = NativeFacts {
            utc: [2026, 11, 12, 8, 15, 30],
            header: b"",
            code: 0xC000_001D,
            address: u64::MAX,
            module: &module,
            module_offset: Some(0),
            thread_id: u32::MAX,
        };
        let text = full(&f);
        assert!(text.contains("exception: 0xC000001D\n"), "{text}");
        assert!(text.contains("address: 0xFFFFFFFFFFFFFFFF\n"), "{text}");
        assert!(text.contains("module: a.dll +0x0\n"), "{text}");
        assert!(text.ends_with("thread: 4294967295\n"), "{text}");
    }

    #[test]
    fn native_report_never_overruns_its_buffer() {
        let header = native_header();
        // Lone surrogates read as U+FFFD.
        let lone = [0x43, 0xD800, 0x44, 0xDC00];
        let f = NativeFacts {
            utc: [2026, 11, 12, 8, 15, 30],
            header: header.as_bytes(),
            code: 0xC000_0005,
            address: 0x7FF6_A1B2_C3D4,
            module: &lone,
            module_offset: Some(0x1B2_C3D4),
            thread_id: 4242,
        };
        let whole = full(&f);
        assert!(
            whole.contains("module: C\u{FFFD}D\u{FFFD} +0x1B2C3D4\n"),
            "{whole}"
        );
        // Every buffer size: the output is a prefix of the whole report, valid UTF-8, and no
        // byte past the buffer changes.
        for size in [0usize, 1, 10, 100, 250, 400, whole.len() - 1, whole.len()] {
            let mut guarded = vec![0xAAu8; size + 16];
            let n = write_native_report(&mut guarded[..size], &f);
            assert!(n <= size, "{size}: {n}");
            assert!(guarded[size..].iter().all(|&b| b == 0xAA), "{size}");
            let text = std::str::from_utf8(&guarded[..n]).unwrap();
            assert!(whole.starts_with(text), "{size}: {text}");
        }
        // A module path far longer than the filter's buffer (4 000 UTF-16 units of a
        // two-byte letter, and of a surrogate pair) is cut at the buffer's end on a character
        // boundary.
        for unit in [utf16("é"), utf16("😀")] {
            let long: Vec<u16> = unit.iter().copied().cycle().take(4_000).collect();
            let f = NativeFacts { module: &long, ..f };
            let mut guarded = vec![0xAAu8; 1_536 + 16];
            let n = write_native_report(&mut guarded[..1_536], &f);
            assert!(n <= 1_536 && n > header.len(), "{n}");
            assert!(guarded[1_536..].iter().all(|&b| b == 0xAA));
            let text = std::str::from_utf8(&guarded[..n]).unwrap();
            assert!(text.starts_with(&header));
            assert!(
                !text.contains("thread:"),
                "the line after the cut is not written"
            );
        }
        // The longest report the filter can make fits its 1 536-byte buffer: the longest
        // build kind, a 260-unit module path of three-byte characters (GetModuleFileNameW
        // fills at most 260), and the widest numbers.
        let longest_header = native_report_header(
            "1.7.0",
            COMMIT,
            "release abcdefghij",
            "10.0.26100",
            Some(u64::MAX),
        );
        let module: Vec<u16> = utf16("中").into_iter().cycle().take(260).collect();
        let f = NativeFacts {
            utc: [u16::MAX; 6],
            header: longest_header.as_bytes(),
            code: u32::MAX,
            address: u64::MAX,
            module: &module,
            module_offset: Some(u64::MAX),
            thread_id: u32::MAX,
        };
        let mut buf = [0u8; 1_536];
        let n = write_native_report(&mut buf, &f);
        let text = std::str::from_utf8(&buf[..n]).unwrap();
        assert!(text.ends_with("thread: 4294967295\n"), "{n}: {text}");
        assert!(text.contains("time: 65535-65535-65535 65535:65535:65535 UTC\n"));
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
        assert!(
            lines.contains(&"error: could not open the window"),
            "{text}"
        );
        assert!(
            lines
                .iter()
                .any(|l| l.starts_with("caused by: signed in as ")),
            "{text}"
        );
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
