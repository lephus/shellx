//! A small, strict JSON reader that edits by byte span (A12 D8).
//!
//! The installer changes a few lines of a file the user owns (an agent's
//! settings). Re-serialising the whole document would reorder keys, drop
//! formatting and lose anything the reader did not understand, so this
//! reader reports where every value and key sits (byte offsets into the
//! original text) and the edit functions splice new text in or cut a run
//! out: every byte outside the edit is copied unchanged.
//!
//! Strict RFC 8259 on purpose. What we cannot edit without guessing is
//! refused instead: comments (JSONC), trailing commas, duplicate keys
//! (which value would an edit mean?), nesting deeper than [`MAX_DEPTH`]
//! and text over [`MAX_BYTES`]. One leniency: a leading UTF-8 BOM is
//! skipped (spans still index the original text, so an edit keeps it).
//! Never panics on hostile input; never logs.

use crate::api::value::json_string;
use std::collections::HashSet;

/// Largest text [`parse`] reads.
pub const MAX_BYTES: usize = 1 << 20;
/// Deepest nesting [`parse`] reads (the recursion bound).
pub const MAX_DEPTH: usize = 64;
/// Longest string member [`top_level_strings`] returns whole.
const MAX_PAYLOAD_STRING: usize = 4096;
/// A `message` over that is clipped to this many characters, not dropped.
const MAX_CLIPPED_MESSAGE: usize = 1024;

/// Byte offsets into the parsed text; `end` is exclusive.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Span {
    pub start: usize,
    pub end: usize,
}

#[derive(Debug, Clone, PartialEq)]
pub enum Kind {
    Null,
    Bool(bool),
    /// A number; read it from the text with the node's span.
    Num,
    Str(String),
    Arr(Vec<Node>),
    Obj(Vec<Member>),
}

#[derive(Debug, Clone, PartialEq)]
pub struct Node {
    pub kind: Kind,
    pub span: Span,
}

#[derive(Debug, Clone, PartialEq)]
pub struct Member {
    pub key: String,
    /// The quoted key, quotes included.
    pub key_span: Span,
    pub value: Node,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum JsonError {
    Syntax,
    TooDeep,
    TooBig,
    Duplicate,
    Comment,
}

struct Reader<'a> {
    b: &'a [u8],
    i: usize,
    depth: usize,
}

type Res<T> = Result<T, JsonError>;

impl Reader<'_> {
    fn peek(&self) -> Option<u8> {
        self.b.get(self.i).copied()
    }

    fn ws(&mut self) {
        while matches!(self.peek(), Some(b' ' | b'\t' | b'\n' | b'\r')) {
            self.i += 1;
        }
    }

    /// What the byte at the cursor is wrong for: a `/` is a comment.
    fn bad(&self) -> JsonError {
        if self.peek() == Some(b'/') {
            JsonError::Comment
        } else {
            JsonError::Syntax
        }
    }

    fn eat(&mut self, c: u8) -> Res<()> {
        if self.peek() == Some(c) {
            self.i += 1;
            Ok(())
        } else {
            Err(self.bad())
        }
    }

    fn value(&mut self) -> Res<Node> {
        self.ws();
        let start = self.i;
        let kind = match self.peek() {
            Some(b'{') => self.object()?,
            Some(b'[') => self.array()?,
            Some(b'"') => Kind::Str(self.string()?),
            Some(b't') => self.literal("true", Kind::Bool(true))?,
            Some(b'f') => self.literal("false", Kind::Bool(false))?,
            Some(b'n') => self.literal("null", Kind::Null)?,
            Some(b'-' | b'0'..=b'9') => {
                self.number()?;
                Kind::Num
            }
            _ => return Err(self.bad()),
        };
        Ok(Node {
            kind,
            span: Span { start, end: self.i },
        })
    }

    fn literal(&mut self, word: &str, kind: Kind) -> Res<Kind> {
        if self.b[self.i..].starts_with(word.as_bytes()) {
            self.i += word.len();
            Ok(kind)
        } else {
            Err(JsonError::Syntax)
        }
    }

    fn enter(&mut self) -> Res<()> {
        self.depth += 1;
        if self.depth > MAX_DEPTH {
            Err(JsonError::TooDeep)
        } else {
            Ok(())
        }
    }

    fn object(&mut self) -> Res<Kind> {
        self.enter()?;
        self.i += 1; // {
        let mut members = Vec::new();
        let mut seen = HashSet::new();
        self.ws();
        if self.peek() == Some(b'}') {
            self.i += 1;
        } else {
            loop {
                self.ws();
                if self.peek() != Some(b'"') {
                    return Err(self.bad());
                }
                let key_start = self.i;
                let key = self.string()?;
                let key_span = Span {
                    start: key_start,
                    end: self.i,
                };
                self.ws();
                self.eat(b':')?;
                let value = self.value()?;
                if !seen.insert(key.clone()) {
                    return Err(JsonError::Duplicate);
                }
                members.push(Member {
                    key,
                    key_span,
                    value,
                });
                self.ws();
                match self.peek() {
                    Some(b',') => self.i += 1,
                    Some(b'}') => {
                        self.i += 1;
                        break;
                    }
                    _ => return Err(self.bad()),
                }
            }
        }
        self.depth -= 1;
        Ok(Kind::Obj(members))
    }

    fn array(&mut self) -> Res<Kind> {
        self.enter()?;
        self.i += 1; // [
        let mut items = Vec::new();
        self.ws();
        if self.peek() == Some(b']') {
            self.i += 1;
        } else {
            loop {
                items.push(self.value()?);
                self.ws();
                match self.peek() {
                    Some(b',') => self.i += 1,
                    Some(b']') => {
                        self.i += 1;
                        break;
                    }
                    _ => return Err(self.bad()),
                }
            }
        }
        self.depth -= 1;
        Ok(Kind::Arr(items))
    }

    fn digits(&mut self) -> Res<()> {
        let from = self.i;
        while matches!(self.peek(), Some(b'0'..=b'9')) {
            self.i += 1;
        }
        if self.i == from {
            Err(JsonError::Syntax)
        } else {
            Ok(())
        }
    }

    /// `-? (0 | [1-9][0-9]*) (. [0-9]+)? ([eE] [+-]? [0-9]+)?`
    fn number(&mut self) -> Res<()> {
        if self.peek() == Some(b'-') {
            self.i += 1;
        }
        match self.peek() {
            Some(b'0') => self.i += 1,
            Some(b'1'..=b'9') => self.digits()?,
            _ => return Err(JsonError::Syntax),
        }
        if self.peek() == Some(b'.') {
            self.i += 1;
            self.digits()?;
        }
        if matches!(self.peek(), Some(b'e' | b'E')) {
            self.i += 1;
            if matches!(self.peek(), Some(b'+' | b'-')) {
                self.i += 1;
            }
            self.digits()?;
        }
        Ok(())
    }

    fn hex4(&mut self) -> Res<u32> {
        let digits = self.b.get(self.i..self.i + 4).ok_or(JsonError::Syntax)?;
        let mut n = 0u32;
        for &d in digits {
            let v = (d as char).to_digit(16).ok_or(JsonError::Syntax)?;
            n = n * 16 + v;
        }
        self.i += 4;
        Ok(n)
    }

    /// A string at the opening quote; the cursor ends after the closing
    /// one. A lone surrogate escape is refused (it has no `String`).
    fn string(&mut self) -> Res<String> {
        self.i += 1; // "
        let mut out = String::new();
        loop {
            let run = self.i;
            while matches!(self.peek(), Some(c) if c != b'"' && c != b'\\' && c >= 0x20) {
                self.i += 1;
            }
            // The text is a &str and the run ends at an ASCII byte or the
            // end, so it is on char boundaries.
            out.push_str(std::str::from_utf8(&self.b[run..self.i]).map_err(|_| JsonError::Syntax)?);
            match self.peek() {
                Some(b'"') => {
                    self.i += 1;
                    return Ok(out);
                }
                Some(b'\\') => {
                    self.i += 1;
                    let c = self.peek().ok_or(JsonError::Syntax)?;
                    self.i += 1;
                    match c {
                        b'"' => out.push('"'),
                        b'\\' => out.push('\\'),
                        b'/' => out.push('/'),
                        b'b' => out.push('\u{8}'),
                        b'f' => out.push('\u{c}'),
                        b'n' => out.push('\n'),
                        b'r' => out.push('\r'),
                        b't' => out.push('\t'),
                        b'u' => {
                            let hi = self.hex4()?;
                            let cp = match hi {
                                0xD800..=0xDBFF => {
                                    if !self.b[self.i..].starts_with(b"\\u") {
                                        return Err(JsonError::Syntax);
                                    }
                                    self.i += 2;
                                    let lo = self.hex4()?;
                                    if !(0xDC00..=0xDFFF).contains(&lo) {
                                        return Err(JsonError::Syntax);
                                    }
                                    0x10000 + ((hi - 0xD800) << 10) + (lo - 0xDC00)
                                }
                                0xDC00..=0xDFFF => return Err(JsonError::Syntax),
                                _ => hi,
                            };
                            out.push(char::from_u32(cp).ok_or(JsonError::Syntax)?);
                        }
                        _ => return Err(JsonError::Syntax),
                    }
                }
                // End of text, or a raw control character.
                _ => return Err(JsonError::Syntax),
            }
        }
    }
}

/// Reads one JSON document (RFC 8259, plus the refusals in the module doc).
pub fn parse(text: &str) -> Result<Node, JsonError> {
    if text.len() > MAX_BYTES {
        return Err(JsonError::TooBig);
    }
    let mut r = Reader {
        b: text.as_bytes(),
        i: if text.starts_with('\u{feff}') { 3 } else { 0 },
        depth: 0,
    };
    let node = r.value()?;
    r.ws();
    if r.i != r.b.len() {
        return Err(r.bad());
    }
    Ok(node)
}

/// The value of `key` in an object node.
pub fn get<'a>(obj: &'a Node, key: &str) -> Option<&'a Node> {
    match &obj.kind {
        Kind::Obj(ms) => ms.iter().find(|m| m.key == key).map(|m| &m.value),
        _ => None,
    }
}

/// How the file is laid out, so inserted text looks like the user's.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Style {
    pub indent: String,
    pub eol: &'static str,
}

impl Default for Style {
    fn default() -> Style {
        Style {
            indent: "  ".into(),
            eol: "\n",
        }
    }
}

/// The dominant indentation (tabs if most indented lines start with one,
/// else the smallest space indent, default two spaces) and `"\r\n"` when
/// the first line break of the file is one.
pub fn detect_style(text: &str) -> Style {
    let eol = match text.find('\n') {
        Some(i) if i > 0 && text.as_bytes()[i - 1] == b'\r' => "\r\n",
        _ => "\n",
    };
    let (mut tabs, mut spaces) = (0usize, 0usize);
    let mut smallest: Option<usize> = None;
    for line in text.lines() {
        let rest = line.trim_start_matches([' ', '\t']);
        if rest.is_empty() {
            continue;
        }
        match line.as_bytes().first() {
            Some(b'\t') => tabs += 1,
            Some(b' ') => {
                spaces += 1;
                let n = line.len() - line.trim_start_matches(' ').len();
                smallest = Some(smallest.map_or(n, |s| s.min(n)));
            }
            _ => {}
        }
    }
    let indent = if tabs > spaces {
        "\t".to_string()
    } else {
        " ".repeat(smallest.unwrap_or(2).clamp(1, 8))
    };
    Style { indent, eol }
}

/// A value we write ourselves (objects keep insertion order).
#[derive(Debug, Clone, PartialEq)]
pub enum Json {
    Null,
    Bool(bool),
    Num(i64),
    Str(String),
    Arr(Vec<Json>),
    Obj(Vec<(String, Json)>),
}

/// Pretty text for `value` placed at nesting `depth` (its first line is
/// not indented: the caller put it after a key or a comma).
pub fn render(value: &Json, depth: usize, st: &Style) -> String {
    let pad = |d: usize| st.indent.repeat(d);
    match value {
        Json::Null => "null".into(),
        Json::Bool(b) => b.to_string(),
        Json::Num(n) => n.to_string(),
        Json::Str(s) => json_string(s),
        Json::Arr(a) if a.is_empty() => "[]".into(),
        Json::Obj(o) if o.is_empty() => "{}".into(),
        Json::Arr(a) => {
            let items: Vec<String> = a
                .iter()
                .map(|v| format!("{}{}", pad(depth + 1), render(v, depth + 1, st)))
                .collect();
            format!(
                "[{eol}{}{eol}{}]",
                items.join(&format!(",{}", st.eol)),
                pad(depth),
                eol = st.eol
            )
        }
        Json::Obj(o) => {
            let items: Vec<String> = o
                .iter()
                .map(|(k, v)| {
                    format!(
                        "{}{}: {}",
                        pad(depth + 1),
                        json_string(k),
                        render(v, depth + 1, st)
                    )
                })
                .collect();
            format!(
                "{{{eol}{}{eol}{}}}",
                items.join(&format!(",{}", st.eol)),
                pad(depth),
                eol = st.eol
            )
        }
    }
}

/// The items of a container as (start, end) byte runs plus the container's
/// inner bounds (after `{`/`[`, at `}`/`]`). `None` for a scalar.
struct Parts {
    items: Vec<(usize, usize)>,
    open_end: usize,
    close: usize,
}

fn parts(node: &Node, want_obj: bool) -> Option<Parts> {
    let items: Vec<(usize, usize)> = match (&node.kind, want_obj) {
        (Kind::Obj(ms), true) => ms
            .iter()
            .map(|m| (m.key_span.start, m.value.span.end))
            .collect(),
        (Kind::Arr(a), false) => a.iter().map(|n| (n.span.start, n.span.end)).collect(),
        _ => return None,
    };
    Some(Parts {
        items,
        open_end: node.span.start + 1,
        close: node.span.end - 1,
    })
}

/// Splices `item` (already rendered) in as the last member/element.
fn append(text: &str, p: &Parts, depth: usize, item: &str, st: &Style) -> String {
    let splice = |at: usize, ins: &str| format!("{}{}{}", &text[..at], ins, &text[at..]);
    let Some(&(first, _)) = p.items.first() else {
        // Empty: the whitespace between the brackets becomes a block.
        let ins = format!(
            "{eol}{}{item}{eol}{}",
            st.indent.repeat(depth + 1),
            st.indent.repeat(depth),
            eol = st.eol
        );
        return format!("{}{}{}", &text[..p.open_end], ins, &text[p.close..]);
    };
    let &(last_start, last_end) = p.items.last().unwrap_or(&(first, first));
    let multi_line = text[p.open_end..first].contains('\n');
    if !multi_line {
        return splice(last_end, &format!(", {item}"));
    }
    // The last item's own indentation, if it starts its line.
    let line = text[..last_start].rfind('\n').map_or(0, |i| i + 1);
    let lead = &text[line..last_start];
    let indent = if lead.chars().all(|c| c == ' ' || c == '\t') {
        lead.to_string()
    } else {
        st.indent.repeat(depth + 1)
    };
    splice(last_end, &format!(",{}{indent}{item}", st.eol))
}

/// Adds `"key": value_json` as the last member of `obj` (at nesting
/// `depth`); `value_json` is already rendered. Anything but an object is
/// returned unchanged.
pub fn insert_member(
    text: &str,
    obj: &Node,
    depth: usize,
    key: &str,
    value_json: &str,
    st: &Style,
) -> String {
    match parts(obj, true) {
        Some(p) => append(
            text,
            &p,
            depth,
            &format!("{}: {value_json}", json_string(key)),
            st,
        ),
        None => text.to_string(),
    }
}

/// Adds `value_json` as the last element of `arr`.
pub fn append_element(
    text: &str,
    arr: &Node,
    depth: usize,
    value_json: &str,
    st: &Style,
) -> String {
    match parts(arr, false) {
        Some(p) => append(text, &p, depth, value_json, st),
        None => text.to_string(),
    }
}

/// Cuts item `idx` out with one adjacent comma: a first or middle item
/// goes up to the next item's start (its comma, line break and
/// indentation with it); the last goes from the previous item's end; the
/// only one empties the container.
fn remove(text: &str, p: &Parts, idx: usize) -> String {
    let n = p.items.len();
    let (from, to) = match idx {
        _ if idx >= n => return text.to_string(),
        _ if n == 1 => (p.open_end, p.close),
        _ if idx + 1 < n => (p.items[idx].0, p.items[idx + 1].0),
        _ => (p.items[idx - 1].1, p.items[idx].1),
    };
    format!("{}{}", &text[..from], &text[to..])
}

/// Removes element `index` of `arr`; out of range or not an array: unchanged.
pub fn remove_element(text: &str, arr: &Node, index: usize) -> String {
    match parts(arr, false) {
        Some(p) => remove(text, &p, index),
        None => text.to_string(),
    }
}

/// Removes member `key` of `obj`; absent or not an object: unchanged.
pub fn remove_member(text: &str, obj: &Node, key: &str) -> String {
    let Kind::Obj(ms) = &obj.kind else {
        return text.to_string();
    };
    match (parts(obj, true), ms.iter().position(|m| m.key == key)) {
        (Some(p), Some(i)) => remove(text, &p, i),
        _ => text.to_string(),
    }
}

/// Hook payloads: the string members of the root object, in order, each
/// at most 4096 bytes (a longer `message` is clipped to 1024 characters at
/// a character boundary; any other longer string is left out). Anything
/// that is not one valid object gives none.
pub fn top_level_strings(text: &str) -> Vec<(String, String)> {
    let Ok(root) = parse(text) else {
        return Vec::new();
    };
    let Kind::Obj(ms) = root.kind else {
        return Vec::new();
    };
    ms.into_iter()
        .filter_map(|m| match m.value.kind {
            Kind::Str(s) if s.len() <= MAX_PAYLOAD_STRING => Some((m.key, s)),
            Kind::Str(s) if m.key == "message" => {
                Some((m.key, s.chars().take(MAX_CLIPPED_MESSAGE).collect()))
            }
            _ => None,
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    const NAMES: [&str; 7] = [
        "empty",
        "two_space",
        "four_space",
        "tabs",
        "crlf",
        "user_hooks",
        "env_secret",
    ];

    fn fixture(name: &str) -> String {
        let p = format!(
            "{}/tests/fixtures/integrations/{name}.json",
            env!("CARGO_MANIFEST_DIR")
        );
        std::fs::read_to_string(p).unwrap()
    }

    fn fixtures() -> Vec<String> {
        NAMES.iter().map(|n| fixture(n)).collect()
    }

    /// The inserted text is the middle: `out`'s common prefix and suffix
    /// with `original` must cover all of it. Returns `original` rebuilt
    /// from those two runs (cutting the inserted run out of `out`).
    fn strip_inserted(out: &str, original: &str) -> String {
        let (o, t) = (out.as_bytes(), original.as_bytes());
        let pre = o.iter().zip(t).take_while(|(a, b)| a == b).count();
        let suf = o
            .iter()
            .rev()
            .zip(t.iter().rev())
            .take_while(|(a, b)| a == b)
            .count();
        assert!(pre + suf >= t.len(), "bytes outside the edit changed");
        let keep_suffix = t.len() - pre;
        let mut r = o[..pre].to_vec();
        r.extend_from_slice(&o[o.len() - keep_suffix..]);
        String::from_utf8(r).unwrap()
    }

    #[test]
    fn parses_nested_and_reports_spans() {
        let t = r#"{ "a": [1, {"b": "x"}], "c": true }"#;
        let root = parse(t).unwrap();
        let a = get(&root, "a").unwrap();
        assert_eq!(&t[a.span.start..a.span.end], r#"[1, {"b": "x"}]"#);
        let Kind::Obj(ms) = &root.kind else { panic!() };
        assert_eq!(&t[ms[0].key_span.start..ms[0].key_span.end], r#""a""#);
        assert_eq!(ms[1].value.kind, Kind::Bool(true));
    }

    #[test]
    fn rejects_what_we_will_not_edit() {
        assert_eq!(parse("{ // c\n}"), Err(JsonError::Comment));
        assert_eq!(parse("{ /* c */ }"), Err(JsonError::Comment));
        assert_eq!(parse("{} // c"), Err(JsonError::Comment));
        assert_eq!(parse(r#"{"a":1,}"#), Err(JsonError::Syntax));
        assert_eq!(parse("[1,]"), Err(JsonError::Syntax));
        assert_eq!(parse(r#"{"a":1,"a":2}"#), Err(JsonError::Duplicate));
        assert_eq!(parse(&"[".repeat(65)), Err(JsonError::TooDeep));
        assert!(parse("").is_err() && parse("{} x").is_err());
        assert!(parse(&format!("{}{}", "[".repeat(64), "]".repeat(64))).is_ok());
    }

    /// Values RFC 8259 accepts / refuses (also swept by `no_prefix_panics`).
    const STRICT_OK: &[&str] = &[
        "0",
        "-0",
        "1.5e+3",
        "-12E-2",
        "\"\"",
        "null",
        "true",
        "[]",
        "{}",
        " \t\r\n1 ",
        r#""é😀\/\b\f\n\r\t\"\\""#,
    ];
    const STRICT_BAD: &[&str] = &[
        "01",
        "+1",
        ".5",
        "1.",
        "1e",
        "0x10",
        "NaN",
        "Infinity",
        "tru",
        "'a'",
        "\"a\nb\"",
        r#""\x""#,
        r#""\u12""#,
        r#""\ud800""#,
        r#""\udc00""#,
        r#""\ud800A""#,
        "{\"a\" 1}",
        "{1:2}",
        "[1 2]",
        "\u{a0}1",
        "\u{feff}[\u{feff}]",
    ];

    #[test]
    fn strict_rfc8259_values() {
        for ok in STRICT_OK {
            assert!(parse(ok).is_ok(), "{ok}");
        }
        for bad in STRICT_BAD {
            assert!(parse(bad).is_err(), "{bad:?}");
        }
        // A leading BOM is skipped; spans still index the original text.
        let t = "\u{feff}{\"a\":1}";
        let root = parse(t).unwrap();
        assert_eq!((root.span.start, root.span.end), (3, t.len()));
    }

    #[test]
    fn decodes_string_escapes_in_keys_and_values() {
        let root = parse(r#"{"a\nb":"é😀"}"#).unwrap();
        let n = get(&root, "a\nb").unwrap();
        assert_eq!(n.kind, Kind::Str("é\u{1f600}".into()));
        // Duplicates are compared after decoding.
        assert_eq!(parse(r#"{"a":1,"a":2}"#), Err(JsonError::Duplicate));
    }

    #[test]
    fn size_limit() {
        let big = format!("\"{}\"", "x".repeat(MAX_BYTES));
        assert_eq!(parse(&big), Err(JsonError::TooBig));
        let just = format!("\"{}\"", "x".repeat(MAX_BYTES - 2));
        assert!(parse(&just).is_ok());
    }

    #[test]
    fn hostile_input_never_panics() {
        let long_str = format!("\"{}", "a".repeat(500_000));
        let many = format!("[{}]", "0,".repeat(200_000) + "0");
        let deep_obj = "{\"a\":".repeat(1000);
        let escapes = format!("\"{}\"", "\\u0041".repeat(50_000));
        for t in [
            long_str.as_str(),
            many.as_str(),
            deep_obj.as_str(),
            escapes.as_str(),
            "\"\\",
            "\"\\u",
            "\"\\ud83d\\",
            "\u{feff}",
            "\u{feff}\u{feff}{}",
            "{\"a\":\u{1f600}}",
            "\0",
            "[\u{0}]",
            "-",
            "{\"",
            "{\"a\"",
            "{\"a\":",
        ] {
            let _ = parse(t);
            let _ = top_level_strings(t);
        }
        assert!(parse(&many).is_ok());
        assert_eq!(parse(&deep_obj), Err(JsonError::TooDeep));
    }

    #[test]
    fn insert_member_keeps_every_other_byte() {
        for name in NAMES {
            let t = fixture(name);
            let root = parse(&t).unwrap();
            let st = detect_style(&t);
            // user_hooks already owns "hooks": a duplicate key is never inserted.
            let key = if get(&root, "hooks").is_some() {
                "extra"
            } else {
                "hooks"
            };
            let out = insert_member(&t, &root, 0, key, "{}", &st);
            let again = parse(&out).unwrap_or_else(|_| panic!("{name} stays valid"));
            assert!(get(&again, key).is_some(), "{name}");
            assert_eq!(strip_inserted(&out, &t), t, "{name}");
            if t.contains("\r\n") {
                assert!(!out.replace("\r\n", "").contains('\n'), "{name} eol");
            }
        }
    }

    #[test]
    fn insert_member_layouts() {
        let st = detect_style("{}");
        let r = |t: &str| parse(t).unwrap();
        let t = "{}";
        assert_eq!(
            insert_member(t, &r(t), 0, "a", "1", &st),
            "{\n  \"a\": 1\n}"
        );
        let t = "{ }";
        assert_eq!(
            insert_member(t, &r(t), 0, "a", "1", &st),
            "{\n  \"a\": 1\n}"
        );
        let t = "{\"x\": 1}";
        assert_eq!(
            insert_member(t, &r(t), 0, "a", "1", &st),
            "{\"x\": 1, \"a\": 1}"
        );
        let t = "{\n\t\"x\": 1\n}\n";
        let tabs = detect_style(t);
        assert_eq!(
            insert_member(t, &r(t), 0, "a", "1", &tabs),
            "{\n\t\"x\": 1,\n\t\"a\": 1\n}\n"
        );
        // Quotes in the key are escaped.
        let out = insert_member("{}", &r("{}"), 0, "a\"b", "1", &st);
        assert!(get(&parse(&out).unwrap(), "a\"b").is_some());
    }

    #[test]
    fn append_element_into_empty_and_nonempty_arrays() {
        let st = detect_style("{}");
        let go = |t: &str, v: &str, depth: usize| {
            let a = parse(t).unwrap();
            append_element(t, &a, depth, v, &st)
        };
        assert_eq!(go("[]", "1", 0), "[\n  1\n]");
        assert_eq!(go("[0]", "1", 0), "[0, 1]");
        assert_eq!(go("[\n  0\n]", "1", 0), "[\n  0,\n  1\n]");
        assert_eq!(go("[\n    0\n]\n", "1", 0), "[\n    0,\n    1\n]\n");
        let t = "{\"a\": [\n  \"x\"\n]}";
        let root = parse(t).unwrap();
        let arr = get(&root, "a").unwrap();
        assert_eq!(
            append_element(t, arr, 1, "\"y\"", &st),
            "{\"a\": [\n  \"x\",\n  \"y\"\n]}"
        );
    }

    #[test]
    fn remove_element_takes_its_comma_and_line() {
        let rm = |t: &str, i: usize| {
            let a = parse(t).unwrap();
            let out = remove_element(t, &a, i);
            assert!(parse(&out).is_ok(), "{out:?}");
            out
        };
        assert_eq!(rm("[1, 2, 3]", 0), "[2, 3]");
        assert_eq!(rm("[1, 2, 3]", 1), "[1, 3]");
        assert_eq!(rm("[1, 2, 3]", 2), "[1, 2]");
        assert_eq!(rm("[1]", 0), "[]");
        let ml = "[\n  1,\n  2,\n  3\n]";
        assert_eq!(rm(ml, 0), "[\n  2,\n  3\n]");
        assert_eq!(rm(ml, 1), "[\n  1,\n  3\n]");
        assert_eq!(rm(ml, 2), "[\n  1,\n  2\n]");
        assert_eq!(rm("[\n  1\n]", 0), "[]");
        assert_eq!(rm(ml, 9), ml);
    }

    #[test]
    fn remove_member_by_key() {
        let t = "{\n  \"a\": 1,\n  \"b\": {\"c\": 2},\n  \"d\": 3\n}\n";
        let root = parse(t).unwrap();
        assert_eq!(
            remove_member(t, &root, "b"),
            "{\n  \"a\": 1,\n  \"d\": 3\n}\n"
        );
        assert_eq!(
            remove_member(t, &root, "d"),
            "{\n  \"a\": 1,\n  \"b\": {\"c\": 2}\n}\n"
        );
        assert_eq!(remove_member(t, &root, "zz"), t);
        let one = "{\"a\": 1}";
        assert_eq!(remove_member(one, &parse(one).unwrap(), "a"), "{}");
    }

    #[test]
    fn style_detection() {
        let d = detect_style("{\"a\":1}");
        assert_eq!((d.indent.as_str(), d.eol), ("  ", "\n"));
        assert_eq!(detect_style(&fixture("tabs")).indent, "\t");
        assert_eq!(detect_style(&fixture("four_space")).indent, "    ");
        assert_eq!(detect_style(&fixture("two_space")).indent, "  ");
        assert_eq!(detect_style(&fixture("crlf")).eol, "\r\n");
        assert_eq!(detect_style(&fixture("two_space")).eol, "\n");
    }

    #[test]
    fn render_pretty_in_style() {
        let st = Style {
            indent: "\t".into(),
            eol: "\n",
        };
        let v = Json::Obj(vec![
            ("b".into(), Json::Str("x\"y".into())),
            ("a".into(), Json::Arr(vec![Json::Num(1), Json::Null])),
            ("e".into(), Json::Obj(vec![])),
            ("f".into(), Json::Bool(true)),
        ]);
        let s = render(&v, 1, &st);
        assert_eq!(
            s,
            "{\n\t\t\"b\": \"x\\\"y\",\n\t\t\"a\": [\n\t\t\t1,\n\t\t\tnull\n\t\t],\n\t\t\"e\": {},\n\t\t\"f\": true\n\t}"
        );
        assert!(parse(&s).is_ok());
    }

    #[test]
    fn no_prefix_panics() {
        let hostile = STRICT_OK.iter().chain(STRICT_BAD).map(|s| s.to_string());
        for t in fixtures().into_iter().chain(hostile) {
            for i in 0..=t.len() {
                if t.is_char_boundary(i) {
                    let _ = parse(&t[..i]);
                    let _ = top_level_strings(&t[..i]);
                }
            }
        }
    }

    #[test]
    fn edits_on_the_wrong_node_kind_leave_the_text_alone() {
        let t = "{\"a\":[1,2]}";
        let root = parse(t).unwrap();
        let a = get(&root, "a").unwrap();
        assert_eq!(remove_member(t, a, "x"), t);
        assert_eq!(remove_element(t, &root, 0), t);
        let one = Node {
            kind: Kind::Null,
            span: Span { start: 0, end: 1 },
        };
        let st = detect_style(t);
        assert_eq!(insert_member(t, &one, 0, "k", "1", &st), t);
        assert_eq!(append_element(t, &one, 0, "1", &st), t);
    }

    #[test]
    fn top_level_strings_ignores_nested_and_long_values() {
        let t = r#"{"session_id":"s","nested":{"x":"y"},"n":1,"message":"hi"}"#;
        assert_eq!(
            top_level_strings(t),
            vec![
                ("session_id".to_string(), "s".to_string()),
                ("message".to_string(), "hi".to_string())
            ]
        );
        let long = format!(r#"{{"a":"{}","b":"ok"}}"#, "x".repeat(4097));
        assert_eq!(top_level_strings(&long), vec![("b".into(), "ok".into())]);
        let long_message = format!(r#"{{"message":"{}"}}"#, "é".repeat(3000));
        let got = top_level_strings(&long_message);
        assert_eq!(got[0].1.chars().count(), 1024);
        let at_limit = format!(r#"{{"a":"{}"}}"#, "x".repeat(4096));
        assert_eq!(top_level_strings(&at_limit).len(), 1);
        assert!(top_level_strings("[\"a\"]").is_empty());
        assert!(top_level_strings("not json").is_empty());
    }
}
