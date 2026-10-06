//! The CBOR subset `shellx_core.encodeCbor` writes: null, bool, 64-bit
//! integers, byte and text strings, arrays, maps with text keys. Definite
//! lengths only, nesting ≤ 8 (A5b D6). Plus JSON output for `--json`.
//!
//! Hostile input: the decoder works on one frame (≤ `MAX_FRAME`), refuses
//! any declared length that the remaining input cannot hold before it
//! allocates, and stops at `MAX_DEPTH` — it never panics.

#[derive(Debug, Clone, PartialEq)]
pub enum Value {
    Null,
    Bool(bool),
    Int(i64),
    Bytes(Vec<u8>),
    Text(String),
    Array(Vec<Value>),
    Map(Vec<(String, Value)>),
}

pub const MAX_DEPTH: usize = 8;

#[derive(Debug, PartialEq, Eq)]
pub struct DecodeError(pub &'static str);

impl Value {
    pub fn text(s: impl Into<String>) -> Value {
        Value::Text(s.into())
    }
    pub fn map(entries: Vec<(&str, Value)>) -> Value {
        Value::Map(
            entries
                .into_iter()
                .map(|(k, v)| (k.to_string(), v))
                .collect(),
        )
    }
    pub fn get(&self, key: &str) -> Option<&Value> {
        match self {
            Value::Map(m) => m.iter().find(|(k, _)| k == key).map(|(_, v)| v),
            _ => None,
        }
    }
    pub fn as_i64(&self) -> Option<i64> {
        if let Value::Int(n) = self {
            Some(*n)
        } else {
            None
        }
    }
    pub fn as_str(&self) -> Option<&str> {
        if let Value::Text(s) = self {
            Some(s)
        } else {
            None
        }
    }
    pub fn as_bool(&self) -> Option<bool> {
        if let Value::Bool(b) = self {
            Some(*b)
        } else {
            None
        }
    }
    pub fn as_array(&self) -> Option<&[Value]> {
        if let Value::Array(a) = self {
            Some(a)
        } else {
            None
        }
    }
    pub fn as_bytes(&self) -> Option<&[u8]> {
        if let Value::Bytes(b) = self {
            Some(b)
        } else {
            None
        }
    }
}

fn head(out: &mut Vec<u8>, major: u8, n: u64) {
    let m = major << 5;
    if n < 24 {
        out.push(m | n as u8);
    } else if n <= 0xff {
        out.extend_from_slice(&[m | 24, n as u8]);
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

pub fn encode(v: &Value) -> Vec<u8> {
    let mut out = Vec::new();
    put(&mut out, v);
    out
}

fn put(out: &mut Vec<u8>, v: &Value) {
    match v {
        Value::Null => out.push(0xf6),
        Value::Bool(b) => out.push(if *b { 0xf5 } else { 0xf4 }),
        Value::Int(n) if *n >= 0 => head(out, 0, *n as u64),
        // -1 - n, computed without overflow for i64::MIN.
        Value::Int(n) => head(out, 1, !(*n as u64)),
        Value::Bytes(b) => {
            head(out, 2, b.len() as u64);
            out.extend_from_slice(b);
        }
        Value::Text(s) => {
            head(out, 3, s.len() as u64);
            out.extend_from_slice(s.as_bytes());
        }
        Value::Array(a) => {
            head(out, 4, a.len() as u64);
            a.iter().for_each(|x| put(out, x));
        }
        Value::Map(m) => {
            head(out, 5, m.len() as u64);
            for (k, x) in m {
                head(out, 3, k.len() as u64);
                out.extend_from_slice(k.as_bytes());
                put(out, x);
            }
        }
    }
}

pub fn decode(bytes: &[u8]) -> Result<Value, DecodeError> {
    let mut r = Reader { b: bytes, pos: 0 };
    let v = r.value(0)?;
    if r.pos != bytes.len() {
        return Err(DecodeError("trailing bytes"));
    }
    Ok(v)
}

struct Reader<'a> {
    b: &'a [u8],
    pos: usize,
}

impl<'a> Reader<'a> {
    fn left(&self) -> u64 {
        (self.b.len() - self.pos) as u64
    }
    fn byte(&mut self) -> Result<u8, DecodeError> {
        let x = *self.b.get(self.pos).ok_or(DecodeError("truncated"))?;
        self.pos += 1;
        Ok(x)
    }
    fn take(&mut self, n: u64) -> Result<&'a [u8], DecodeError> {
        if n > self.left() {
            return Err(DecodeError("truncated"));
        }
        let end = self.pos + n as usize;
        let s = &self.b[self.pos..end];
        self.pos = end;
        Ok(s)
    }
    fn array<const N: usize>(&mut self) -> Result<[u8; N], DecodeError> {
        let mut a = [0u8; N];
        a.copy_from_slice(self.take(N as u64)?);
        Ok(a)
    }
    fn head(&mut self) -> Result<(u8, u64), DecodeError> {
        let x = self.byte()?;
        let n = match x & 0x1f {
            i @ 0..=23 => u64::from(i),
            24 => u64::from(self.byte()?),
            25 => u64::from(u16::from_be_bytes(self.array()?)),
            26 => u64::from(u32::from_be_bytes(self.array()?)),
            27 => u64::from_be_bytes(self.array()?),
            _ => return Err(DecodeError("indefinite or reserved length")),
        };
        Ok((x >> 5, n))
    }
    fn text(&mut self, n: u64) -> Result<String, DecodeError> {
        String::from_utf8(self.take(n)?.to_vec()).map_err(|_| DecodeError("text is not UTF-8"))
    }
    /// `depth` = containers already open around this value.
    fn value(&mut self, depth: usize) -> Result<Value, DecodeError> {
        match self.b.get(self.pos) {
            Some(0xf4) => {
                self.pos += 1;
                return Ok(Value::Bool(false));
            }
            Some(0xf5) => {
                self.pos += 1;
                return Ok(Value::Bool(true));
            }
            Some(0xf6) => {
                self.pos += 1;
                return Ok(Value::Null);
            }
            _ => {}
        }
        let (major, n) = self.head()?;
        match major {
            0 => i64::try_from(n)
                .map(Value::Int)
                .map_err(|_| DecodeError("integer too large")),
            1 => i64::try_from(n)
                .map(|n| Value::Int(-1 - n))
                .map_err(|_| DecodeError("integer too small")),
            2 => Ok(Value::Bytes(self.take(n)?.to_vec())),
            3 => self.text(n).map(Value::Text),
            4 | 5 if depth >= MAX_DEPTH => Err(DecodeError("nested too deeply")),
            // Every item takes at least one byte (two per map entry): a
            // count the input cannot hold is refused before looping.
            4 if n > self.left() => Err(DecodeError("truncated")),
            5 if n > self.left() / 2 => Err(DecodeError("truncated")),
            4 => {
                let mut a = Vec::new();
                for _ in 0..n {
                    a.push(self.value(depth + 1)?);
                }
                Ok(Value::Array(a))
            }
            5 => {
                let mut m: Vec<(String, Value)> = Vec::new();
                for _ in 0..n {
                    let (km, kn) = self.head()?;
                    if km != 3 {
                        return Err(DecodeError("map key is not text"));
                    }
                    let k = self.text(kn)?;
                    let v = self.value(depth + 1)?;
                    m.push((k, v));
                }
                Ok(Value::Map(m))
            }
            _ => Err(DecodeError("unsupported item")),
        }
    }
}

pub fn json_string(s: &str) -> String {
    let mut out = String::with_capacity(s.len() + 2);
    out.push('"');
    for c in s.chars() {
        match c {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            c if (c as u32) < 0x20 => out.push_str(&format!("\\u{:04x}", c as u32)),
            c => out.push(c),
        }
    }
    out.push('"');
    out
}

fn base64(b: &[u8]) -> String {
    const T: &[u8; 64] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    let mut out = String::new();
    for chunk in b.chunks(3) {
        let n = (u32::from(chunk[0]) << 16)
            | (u32::from(*chunk.get(1).unwrap_or(&0)) << 8)
            | u32::from(*chunk.get(2).unwrap_or(&0));
        for i in 0..4 {
            if i <= chunk.len() {
                out.push(T[((n >> (18 - 6 * i)) & 63) as usize] as char);
            } else {
                out.push('=');
            }
        }
    }
    out
}

pub fn to_json(v: &Value) -> String {
    match v {
        Value::Null => "null".into(),
        Value::Bool(b) => b.to_string(),
        Value::Int(n) => n.to_string(),
        Value::Bytes(b) => json_string(&base64(b)),
        Value::Text(s) => json_string(s),
        Value::Array(a) => format!("[{}]", a.iter().map(to_json).collect::<Vec<_>>().join(",")),
        Value::Map(m) => format!(
            "{{{}}}",
            m.iter()
                .map(|(k, x)| format!("{}:{}", json_string(k), to_json(x)))
                .collect::<Vec<_>>()
                .join(",")
        ),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn hex(b: &[u8]) -> String {
        b.iter().map(|x| format!("{x:02x}")).collect()
    }

    fn unhex(s: &str) -> Vec<u8> {
        (0..s.len())
            .step_by(2)
            .map(|i| u8::from_str_radix(&s[i..i + 2], 16).unwrap())
            .collect()
    }

    #[test]
    fn round_trips_every_type() {
        let v = Value::map(vec![
            ("n", Value::Null),
            ("b", Value::Bool(true)),
            ("i", Value::Int(-3)),
            ("big", Value::Int(1 << 40)),
            ("min", Value::Int(i64::MIN)),
            ("max", Value::Int(i64::MAX)),
            ("y", Value::Bytes(vec![0, 255])),
            ("s", Value::text("tiếng Việt")),
            ("a", Value::Array(vec![Value::Int(1), Value::text("x")])),
            ("m", Value::map(vec![("k", Value::Bool(false))])),
        ]);
        assert_eq!(decode(&encode(&v)).unwrap(), v);
    }

    #[test]
    fn shortest_forms() {
        assert_eq!(hex(&encode(&Value::Int(-1))), "20");
        assert_eq!(hex(&encode(&Value::Int(-25))), "3818");
        assert_eq!(hex(&encode(&Value::Int(24))), "1818");
        assert_eq!(hex(&encode(&Value::Null)), "f6");
    }

    #[test]
    fn nesting_beyond_eight_is_refused() {
        let mut v = Value::Int(0);
        for _ in 0..8 {
            v = Value::Array(vec![v]);
        }
        assert!(decode(&encode(&v)).is_ok());
        let deeper = Value::Array(vec![v]);
        assert!(decode(&encode(&deeper)).is_err());
    }

    #[test]
    fn refuses_floats_tags_indefinite_trailing_and_non_text_keys() {
        for bad in ["f93c00", "c100", "9fff", "0000", "a10101", "5f"] {
            assert!(decode(&unhex(bad)).is_err(), "{bad}");
        }
    }

    /// Hostile input (A7 review focus): every malformed shape is an error,
    /// never a panic, and a declared length larger than the input is refused
    /// before anything is allocated for it.
    #[test]
    fn malformed_input_table_is_refused_without_panicking() {
        let table: &[(&str, &str)] = &[
            ("", "empty"),
            ("18", "truncated 1-byte head"),
            ("19ff", "truncated 2-byte head"),
            ("1bffffffff", "truncated 8-byte head"),
            ("1b8000000000000000", "integer above i64::MAX"),
            ("3b8000000000000000", "negative below i64::MIN"),
            ("5bffffffffffffffff", "byte string longer than the input"),
            ("7bffffffffffffffff", "text string longer than the input"),
            ("9bffffffffffffffff", "array longer than the input"),
            ("bbffffffffffffffff", "map longer than the input"),
            ("9a0001000001", "array of 65536 with one item"),
            ("62c328", "invalid UTF-8 text"),
            ("a162c32801", "invalid UTF-8 key"),
            ("a1", "map without entries"),
            ("a16161", "map key without value"),
            ("a1f601", "null key"),
            ("a14100f6", "byte-string key"),
            ("f7", "undefined"),
            ("f820", "simple value"),
            ("fa3f800000", "float32"),
            ("fb3ff0000000000000", "float64"),
            ("1c", "reserved additional info 28"),
            ("1f", "indefinite integer"),
            ("7f", "indefinite text"),
            ("bf", "indefinite map"),
            ("ff", "break"),
            ("c0", "tag without content"),
            ("d8ff00", "tag 255"),
            ("f6f6", "trailing null"),
        ];
        for (bad, why) in table {
            assert!(decode(&unhex(bad)).is_err(), "{why}: {bad}");
        }
    }

    #[test]
    fn deep_nesting_from_the_wire_is_refused_without_recursing_far() {
        // 10,000 nested one-element arrays: depth stops at MAX_DEPTH.
        let mut bytes = vec![0x81; 10_000];
        bytes.push(0x00);
        assert!(decode(&bytes).is_err());
        let mut maps = Vec::new();
        for _ in 0..10_000 {
            maps.extend_from_slice(&[0xa1, 0x61, b'k']);
        }
        maps.push(0x00);
        assert!(decode(&maps).is_err());
    }

    /// Fuzz-style: random bytes and mutations of valid encodings never
    /// panic (deterministic xorshift, so a failure reproduces).
    #[test]
    fn random_and_mutated_input_never_panics() {
        let mut x: u64 = 0x9e37_79b9_7f4a_7c15;
        let mut next = move || {
            x ^= x << 13;
            x ^= x >> 7;
            x ^= x << 17;
            x
        };
        let seed = encode(&Value::map(vec![
            ("t", Value::text("result")),
            ("q", Value::Int(7)),
            (
                "a",
                Value::Array(vec![Value::Int(-1), Value::Bytes(vec![1, 2])]),
            ),
            ("m", Value::map(vec![("k", Value::Null)])),
        ]));
        for _ in 0..20_000 {
            let len = (next() % 48) as usize;
            let random: Vec<u8> = (0..len).map(|_| next() as u8).collect();
            let _ = decode(&random);
            let mut mutated = seed.clone();
            for _ in 0..1 + next() % 4 {
                let i = (next() as usize) % mutated.len();
                mutated[i] = next() as u8;
            }
            let cut = (next() as usize) % (mutated.len() + 1);
            let _ = decode(&mutated);
            let _ = decode(&mutated[..cut]);
        }
    }

    #[test]
    fn json_escapes_and_bytes_as_base64() {
        let v = Value::map(vec![
            ("s", Value::text("a\"b\\c\n\u{1}é")),
            ("y", Value::Bytes(vec![0xfb, 0xff])),
            ("n", Value::Null),
            ("a", Value::Array(vec![Value::Int(-2), Value::Bool(false)])),
        ]);
        assert_eq!(
            to_json(&v),
            r#"{"s":"a\"b\\c\n\u0001é","y":"+/8=","n":null,"a":[-2,false]}"#
        );
    }

    #[test]
    fn base64_pads_every_remainder() {
        let j = |b: &[u8]| to_json(&Value::Bytes(b.to_vec()));
        assert_eq!(j(b""), r#""""#);
        assert_eq!(j(b"f"), r#""Zg==""#);
        assert_eq!(j(b"fo"), r#""Zm8=""#);
        assert_eq!(j(b"foo"), r#""Zm9v""#);
        assert_eq!(j(b"foob"), r#""Zm9vYg==""#);
    }

    #[test]
    fn accessors_return_only_their_own_type() {
        let v = Value::map(vec![("i", Value::Int(1)), ("s", Value::text("x"))]);
        assert_eq!(v.get("i").and_then(Value::as_i64), Some(1));
        assert_eq!(v.get("s").and_then(Value::as_str), Some("x"));
        assert_eq!(v.get("i").and_then(Value::as_str), None);
        assert_eq!(v.get("missing"), None);
        assert_eq!(Value::Int(1).get("i"), None);
        assert_eq!(Value::Bool(true).as_bool(), Some(true));
        assert_eq!(Value::Bytes(vec![1]).as_bytes(), Some(&[1u8][..]));
        assert_eq!(Value::Array(vec![]).as_array(), Some(&[][..]));
    }
}
