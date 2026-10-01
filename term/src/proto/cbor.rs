//! The small CBOR subset the local link uses (spec §6.2): one map with text
//! keys whose values are unsigned integers, byte strings, text strings or
//! booleans. Definite lengths only. The encoder writes integers and lengths
//! in their shortest form; the decoder accepts any valid length form.

use std::collections::BTreeMap;

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Value {
    Uint(u64),
    Bytes(Vec<u8>),
    Text(String),
    Bool(bool),
}

/// Keys sorted, so encodings are deterministic.
pub type Map = BTreeMap<String, Value>;

#[derive(Debug, PartialEq, Eq)]
pub struct CborError(pub &'static str);

pub fn encode_map(map: &Map) -> Vec<u8> {
    let mut out = Vec::new();
    head(&mut out, 5, map.len() as u64);
    for (key, value) in map {
        head(&mut out, 3, key.len() as u64);
        out.extend_from_slice(key.as_bytes());
        match value {
            Value::Uint(n) => head(&mut out, 0, *n),
            Value::Bytes(b) => {
                head(&mut out, 2, b.len() as u64);
                out.extend_from_slice(b);
            }
            Value::Text(s) => {
                head(&mut out, 3, s.len() as u64);
                out.extend_from_slice(s.as_bytes());
            }
            Value::Bool(b) => out.push(if *b { 0xf5 } else { 0xf4 }),
        }
    }
    out
}

fn head(out: &mut Vec<u8>, major: u8, n: u64) {
    let m = major << 5;
    if n < 24 {
        out.push(m | n as u8);
    } else if n <= 0xff {
        out.push(m | 24);
        out.push(n as u8);
    } else if n <= 0xffff {
        out.push(m | 25);
        out.extend_from_slice(&(n as u16).to_be_bytes());
    } else if n <= 0xffff_ffff {
        out.push(m | 26);
        out.extend_from_slice(&(n as u32).to_be_bytes());
    } else {
        out.push(m | 27);
        out.extend_from_slice(&n.to_be_bytes());
    }
}

pub fn decode_map(bytes: &[u8]) -> Result<Map, CborError> {
    let mut r = Reader { bytes, pos: 0 };
    let (major, len) = r.head()?;
    if major != 5 {
        return Err(CborError("not a map"));
    }
    let mut map = Map::new();
    for _ in 0..len {
        let (key_major, key_len) = r.head()?;
        if key_major != 3 {
            return Err(CborError("map key is not text"));
        }
        let key = String::from_utf8(r.take(key_len)?.to_vec())
            .map_err(|_| CborError("key is not UTF-8"))?;
        let value = r.value()?;
        if map.insert(key, value).is_some() {
            return Err(CborError("duplicate key"));
        }
    }
    if r.pos != bytes.len() {
        return Err(CborError("trailing bytes"));
    }
    Ok(map)
}

struct Reader<'a> {
    bytes: &'a [u8],
    pos: usize,
}

impl<'a> Reader<'a> {
    fn byte(&mut self) -> Result<u8, CborError> {
        let b = *self.bytes.get(self.pos).ok_or(CborError("truncated"))?;
        self.pos += 1;
        Ok(b)
    }

    fn take(&mut self, n: u64) -> Result<&'a [u8], CborError> {
        let n = usize::try_from(n).map_err(|_| CborError("too long"))?;
        let end = self
            .pos
            .checked_add(n)
            .filter(|end| *end <= self.bytes.len())
            .ok_or(CborError("truncated"))?;
        let slice = &self.bytes[self.pos..end];
        self.pos = end;
        Ok(slice)
    }

    fn head(&mut self) -> Result<(u8, u64), CborError> {
        let b = self.byte()?;
        let n = match b & 0x1f {
            info @ 0..=23 => u64::from(info),
            24 => u64::from(self.byte()?),
            25 => u64::from(u16::from_be_bytes(self.take(2)?.try_into().unwrap())),
            26 => u64::from(u32::from_be_bytes(self.take(4)?.try_into().unwrap())),
            27 => u64::from_be_bytes(self.take(8)?.try_into().unwrap()),
            _ => return Err(CborError("indefinite or reserved length")),
        };
        Ok((b >> 5, n))
    }

    fn value(&mut self) -> Result<Value, CborError> {
        match self.bytes.get(self.pos) {
            Some(0xf4) => {
                self.pos += 1;
                return Ok(Value::Bool(false));
            }
            Some(0xf5) => {
                self.pos += 1;
                return Ok(Value::Bool(true));
            }
            _ => {}
        }
        let (major, n) = self.head()?;
        match major {
            0 => Ok(Value::Uint(n)),
            2 => Ok(Value::Bytes(self.take(n)?.to_vec())),
            3 => String::from_utf8(self.take(n)?.to_vec())
                .map(Value::Text)
                .map_err(|_| CborError("text is not UTF-8")),
            _ => Err(CborError("unsupported value type")),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn hex(bytes: &[u8]) -> String {
        bytes.iter().map(|b| format!("{b:02x}")).collect()
    }

    fn map(entries: &[(&str, Value)]) -> Map {
        entries
            .iter()
            .map(|(k, v)| (k.to_string(), v.clone()))
            .collect()
    }

    #[test]
    fn encodes_a_one_key_map_exactly() {
        // {"t": "local"} — a1, 61 74, 65 6c 6f 63 61 6c
        let m = map(&[("t", Value::Text("local".into()))]);
        assert_eq!(hex(&encode_map(&m)), "a16174656c6f63616c");
    }

    #[test]
    fn integers_use_the_shortest_form() {
        for (n, expected) in [
            (0u64, "a1616e00"),
            (23, "a1616e17"),
            (24, "a1616e1818"),
            (255, "a1616e18ff"),
            (256, "a1616e190100"),
            (65536, "a1616e1a00010000"),
            (1u64 << 32, "a1616e1b0000000100000000"),
        ] {
            assert_eq!(
                hex(&encode_map(&map(&[("n", Value::Uint(n))]))),
                expected,
                "{n}"
            );
        }
    }

    #[test]
    fn round_trips_every_value_type() {
        let m = map(&[
            ("a", Value::Uint(4242)),
            ("b", Value::Bytes(vec![0, 1, 2, 255])),
            ("c", Value::Text("tiếng Việt".into())),
            ("d", Value::Bool(true)),
            ("e", Value::Bool(false)),
            ("f", Value::Bytes(vec![7; 70_000])),
        ]);
        assert_eq!(decode_map(&encode_map(&m)).unwrap(), m);
    }

    #[test]
    fn rejects_malformed_input() {
        for bad in [
            &[][..],                                               // empty
            &[0xa1][..],                                           // map with a missing entry
            &[0x61, 0x74][..],                                     // not a map
            &[0xa1, 0x01, 0x01][..],                               // key is not text
            &[0xbf][..],                                           // indefinite-length map
            &[0xa1, 0x61, 0x74, 0x5a, 0xff, 0xff, 0xff, 0xff][..], // byte string longer than input
            &[0xa1, 0x61, 0x74, 0x80][..],                         // array value (unsupported)
            &[0xa1, 0x61, 0x74, 0x01, 0x00][..],                   // trailing byte
            &[0xa2, 0x61, 0x74, 0x01, 0x61, 0x74, 0x02][..],       // duplicate key
        ] {
            assert!(decode_map(bad).is_err(), "{}", hex(bad));
        }
    }
}
