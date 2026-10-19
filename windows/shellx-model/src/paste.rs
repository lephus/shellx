//! Safe paste encoding: clipboard text always arrives as data.

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
}
