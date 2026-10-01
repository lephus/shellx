//! Text conversions the Windows console needs, kept pure so they are
//! tested on every platform (spec §5.3). The console hands keystrokes over
//! as UTF-16 code units, one per event; output goes to `WriteConsoleW` as
//! UTF-16 while the PTY produces UTF-8 in arbitrary chunks.

/// Console key events → UTF-8 bytes for the shell.
#[derive(Default)]
pub struct KeyInput {
    high: Option<u16>,
}

/// UTF-8 chunks from the PTY → UTF-16 for the console.
#[derive(Default)]
pub struct Utf8Stream {
    pending: Vec<u8>,
}

impl KeyInput {
    /// One console KEY_EVENT: appends its character's UTF-8 to `out`.
    pub fn push(&mut self, key_down: bool, repeat: u16, unit: u16, out: &mut Vec<u8>) {
        if !key_down || unit == 0 {
            return;
        }
        let ch = match (self.high.take(), unit) {
            (None, 0xD800..=0xDBFF) => {
                self.high = Some(unit);
                return;
            }
            (Some(high), 0xDC00..=0xDFFF) => {
                let code =
                    0x10000 + ((u32::from(high) - 0xD800) << 10) + (u32::from(unit) - 0xDC00);
                char::from_u32(code).unwrap_or('\u{FFFD}')
            }
            (Some(_), _) => {
                // A high surrogate without its pair, then this unit on its own.
                out.extend_from_slice("\u{FFFD}".as_bytes());
                return self.push(key_down, repeat, unit, out);
            }
            (None, u) => char::from_u32(u32::from(u)).unwrap_or('\u{FFFD}'),
        };
        let mut buf = [0u8; 4];
        let encoded = ch.encode_utf8(&mut buf).as_bytes();
        for _ in 0..repeat.max(1) {
            out.extend_from_slice(encoded);
        }
    }
}

impl Utf8Stream {
    /// Decodes `bytes` after any bytes kept from the last call.
    pub fn push(&mut self, bytes: &[u8], out: &mut Vec<u16>) {
        let mut input = std::mem::take(&mut self.pending);
        input.extend_from_slice(bytes);
        let mut rest: &[u8] = &input;
        loop {
            match std::str::from_utf8(rest) {
                Ok(text) => {
                    out.extend(text.encode_utf16());
                    return;
                }
                Err(e) => {
                    let (good, bad) = rest.split_at(e.valid_up_to());
                    out.extend(
                        std::str::from_utf8(good)
                            .expect("valid prefix")
                            .encode_utf16(),
                    );
                    match e.error_len() {
                        Some(n) => {
                            out.push(0xFFFD);
                            rest = &bad[n..];
                        }
                        None => {
                            // An incomplete sequence at the end: keep it.
                            self.pending = bad.to_vec();
                            return;
                        }
                    }
                }
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn keys(events: &[(bool, u16, u16)]) -> Vec<u8> {
        let mut k = KeyInput::default();
        let mut out = Vec::new();
        for &(down, repeat, unit) in events {
            k.push(down, repeat, unit, &mut out);
        }
        out
    }

    fn utf16(chunks: &[&[u8]]) -> String {
        let mut s = Utf8Stream::default();
        let mut out = Vec::new();
        for chunk in chunks {
            s.push(chunk, &mut out);
        }
        String::from_utf16(&out).unwrap()
    }

    #[test]
    fn ascii_and_control_keys() {
        let l = b'l' as u16;
        assert_eq!(
            keys(&[
                (true, 1, l),
                (false, 1, l),
                (true, 1, 0x03),
                (true, 1, 0x1b)
            ]),
            b"l\x03\x1b"
        );
    }

    #[test]
    fn repeat_counts_and_modifier_only_keys() {
        assert_eq!(
            keys(&[(true, 3, b'a' as u16), (true, 0, b'b' as u16), (true, 1, 0)]),
            b"aaab"
        );
    }

    #[test]
    fn vietnamese_from_an_ime() {
        let units: Vec<(bool, u16, u16)> =
            "tiếng Việt".encode_utf16().map(|u| (true, 1, u)).collect();
        assert_eq!(keys(&units), "tiếng Việt".as_bytes());
    }

    #[test]
    fn surrogate_pairs_across_events_and_lone_surrogates() {
        let emoji: Vec<u16> = "😀".encode_utf16().collect();
        assert_eq!(
            keys(&[
                (true, 1, emoji[0]),
                (false, 1, emoji[0]),
                (true, 1, emoji[1])
            ]),
            "😀".as_bytes()
        );
        assert_eq!(
            keys(&[(true, 1, 0xD83D), (true, 1, b'x' as u16)]),
            "\u{FFFD}x".as_bytes()
        );
        assert_eq!(keys(&[(true, 1, 0xDE00)]), "\u{FFFD}".as_bytes());
    }

    #[test]
    fn utf8_split_at_every_point_decodes_the_same() {
        let text = "a ế 😀 z";
        let bytes = text.as_bytes();
        for split in 0..=bytes.len() {
            assert_eq!(
                utf16(&[&bytes[..split], &bytes[split..]]),
                text,
                "split at {split}"
            );
        }
        assert_eq!(utf16(&bytes.chunks(1).collect::<Vec<_>>()), text);
    }

    #[test]
    fn invalid_utf8_becomes_replacement_characters() {
        assert_eq!(utf16(&[b"a\xffb"]), "a\u{FFFD}b");
        // A kept incomplete sequence that the next chunk breaks.
        assert_eq!(utf16(&[b"\xe1\x80", b"z"]), "\u{FFFD}z");
    }
}
