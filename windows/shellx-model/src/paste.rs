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
}
