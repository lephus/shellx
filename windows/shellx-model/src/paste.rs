//! Safe paste encoding: clipboard text always arrives as data. A paste of several lines into
//! a shell without bracketed paste asks first (`needs_paste_confirmation`, `confirm_key`).

use crate::keys::KeyIn;

const START: &str = "\x1b[200~";
const END: &str = "\x1b[201~";

/// Normalizes newlines to CR, strips bracketed-paste markers (repeatedly, so a splice
/// cannot rebuild one), and wraps in markers when `bracketed`. Empty input gives empty output.
pub fn encode_paste(text: &str, bracketed: bool) -> Vec<u8> {
    let mut s = text.replace("\r\n", "\r").replace('\n', "\r");
    while s.contains(START) || s.contains(END) {
        s = s.replace(START, "").replace(END, "");
    }
    if s.is_empty() {
        return Vec::new();
    }
    if bracketed {
        let mut out = Vec::with_capacity(s.len() + START.len() + END.len());
        out.extend_from_slice(START.as_bytes());
        out.extend_from_slice(s.as_bytes());
        out.extend_from_slice(END.as_bytes());
        out
    } else {
        s.into_bytes()
    }
}

/// Largest encoded paste a remote pane sends: one relay send of more than
/// about 12 MB fails, so a bigger paste is refused whole (never cut).
pub const REMOTE_PASTE_MAX_BYTES: usize = 8 * 1024 * 1024;

/// Whether a remote paste of `encoded_len` bytes (`encode_paste` output,
/// markers included) may be sent.
pub fn remote_paste_fits(encoded_len: usize) -> bool {
    encoded_len <= REMOTE_PASTE_MAX_BYTES
}

/// Whether pasting `text` into a pane must be confirmed first: more than one line would run
/// as several commands at once. A newline is `\n` or `\r`; a trailing newline, or only
/// whitespace after one, is still one line. A pane in bracketed-paste mode (`bracketed`,
/// mode 2004) receives the text as data, so it never asks.
pub fn needs_paste_confirmation(text: &str, bracketed: bool) -> bool {
    if bracketed {
        return false;
    }
    match text.find(['\n', '\r']) {
        Some(i) => text[i..].chars().any(|c| !c.is_whitespace()),
        None => false,
    }
}

/// How many command lines `text` holds, as the confirmation counts them: segments split at
/// `\r\n`, `\n` or `\r`, less one empty segment at the end (a final newline ends the last
/// line, it does not start a new one).
pub fn paste_line_count(text: &str) -> usize {
    let segments = text
        .split("\r\n")
        .flat_map(|s| s.split(['\n', '\r']))
        .count();
    let trailing_newline = text.ends_with(['\n', '\r']);
    segments - usize::from(trailing_newline && segments > 1)
}

/// What a key does while the paste confirmation shows.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ConfirmKey {
    /// Enter: paste.
    Confirm,
    /// Esc: drop the paste.
    Cancel,
    /// Any other key: drop the paste, then the key does what it always does.
    CancelAndPass,
}

/// Enter or Esc without a modifier answer the confirmation; every other key cancels it and
/// goes on.
pub fn confirm_key(k: &KeyIn) -> ConfirmKey {
    let plain = !(k.ctrl || k.alt || k.shift || k.win);
    match k.key.to_lowercase().as_str() {
        "enter" if plain => ConfirmKey::Confirm,
        "escape" if plain => ConfirmKey::Cancel,
        _ => ConfirmKey::CancelAndPass,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn count(hay: &[u8], needle: &[u8]) -> usize {
        hay.windows(needle.len()).filter(|w| *w == needle).count()
    }

    #[test]
    fn paste_strips_embedded_markers() {
        let out = encode_paste("echo hi\x1b[201~rm -rf ~\n", true);
        assert_eq!(out, b"\x1b[200~echo hirm -rf ~\r\x1b[201~".to_vec());
        assert_eq!(count(&out, b"\x1b[201~"), 1);
        assert!(out.ends_with(b"\x1b[201~"));
    }

    #[test]
    fn paste_strips_spliced_markers() {
        let out = encode_paste("a\x1b[20\x1b[201~1~b", true);
        assert_eq!(out, b"\x1b[200~ab\x1b[201~".to_vec());
        assert_eq!(count(&out, b"\x1b[201~"), 1);
        let out = encode_paste("a\x1b[2\x1b[200~00~b", false);
        assert_eq!(out, b"ab".to_vec());
    }

    #[test]
    fn paste_normalizes_newlines() {
        assert_eq!(encode_paste("a\r\nb\nc\r", false), b"a\rb\rc\r".to_vec());
    }

    #[test]
    fn paste_unbracketed_has_no_markers() {
        assert_eq!(encode_paste("ls", false), b"ls".to_vec());
    }

    #[test]
    fn paste_empty_is_empty() {
        assert!(encode_paste("", true).is_empty());
        assert!(encode_paste("", false).is_empty());
        assert!(encode_paste("\x1b[200~", true).is_empty());
    }

    #[test]
    fn paste_keeps_utf8() {
        assert_eq!(
            encode_paste("tiếng Việt", false),
            "tiếng Việt".as_bytes().to_vec()
        );
    }

    #[test]
    fn remote_paste_cap_is_8_mib_of_encoded_bytes() {
        assert_eq!(REMOTE_PASTE_MAX_BYTES, 8 * 1024 * 1024);
        assert!(remote_paste_fits(0));
        assert!(remote_paste_fits(REMOTE_PASTE_MAX_BYTES));
        assert!(!remote_paste_fits(REMOTE_PASTE_MAX_BYTES + 1));
        // the rule counts encoded bytes: the markers count too
        let text = "a".repeat(REMOTE_PASTE_MAX_BYTES - 6);
        assert!(remote_paste_fits(encode_paste(&text, false).len()));
        assert!(!remote_paste_fits(encode_paste(&text, true).len()));
        // and UTF-8 bytes, not chars
        let vi = "ệ".repeat(REMOTE_PASTE_MAX_BYTES / 2);
        assert!(!remote_paste_fits(encode_paste(&vi, false).len()));
    }

    #[test]
    fn multi_line_means_text_after_a_newline() {
        for t in [
            "echo hi",
            "echo hi\n",
            "echo hi\r\n",
            "a\n  \t\n",
            "a\n\u{00A0}",
            "",
        ] {
            assert!(!needs_paste_confirmation(t, false), "{t:?}");
        }
        for t in [
            "a\nb",
            "a\r\nb\r\n",
            "a\rb",
            "\nb",
            "echo 1\necho 2\necho 3",
        ] {
            assert!(needs_paste_confirmation(t, false), "{t:?}");
        }
    }

    #[test]
    fn paste_line_count_counts_what_the_shell_will_run() {
        for (text, lines) in [
            ("a\nb", 2),
            ("a\r\nb\r\n", 2),
            ("a\rb", 2),
            ("\nb", 2),
            ("echo 1\necho 2\necho 3\n", 3),
            ("a\n\n\nb", 4),
            ("a\nb\n\n", 3),
            ("x", 1),
            // a line copied from Notepad keeps its CRLF: still one line
            ("dir\r\n", 1),
        ] {
            assert_eq!(paste_line_count(text), lines, "{text:?}");
        }
    }

    #[test]
    fn confirm_keys_paste_cancel_or_pass() {
        use crate::keys::KeyIn;
        let key = |key, ctrl, alt, shift| KeyIn {
            key,
            ctrl,
            alt,
            shift,
            win: false,
        };
        assert_eq!(
            confirm_key(&key("enter", false, false, false)),
            ConfirmKey::Confirm
        );
        assert_eq!(
            confirm_key(&key("escape", false, false, false)),
            ConfirmKey::Cancel
        );
        for k in [
            key("enter", true, false, false),
            key("enter", false, false, true),
            key("a", false, false, false),
            key("space", false, false, false),
            key("c", true, false, false),
            key("f4", false, true, false),
            KeyIn {
                win: true,
                ..key("enter", false, false, false)
            },
        ] {
            assert_eq!(confirm_key(&k), ConfirmKey::CancelAndPass, "{k:?}");
        }
    }

    #[test]
    fn a_pending_paste_counts_its_lines_once() {
        // the bar redraws on every output batch: the count is taken when the question opens
        // and read from then on, never taken again (review m5)
        let text = "echo 1\r\necho 2\r\necho 3\r\n".to_string();
        let pending = PendingPaste::new(text.clone());
        assert_eq!(pending.lines(), 3);
        assert_eq!(pending.lines(), paste_line_count(&text));
        // the text comes back as it was copied, without a copy of it
        assert_eq!(pending.into_text(), text);
    }

    #[test]
    fn a_bracketed_paste_never_asks() {
        assert!(!needs_paste_confirmation("a\nb", true));
        assert!(!needs_paste_confirmation("echo 1\necho 2", true));
    }
}
