//! Codex (A12 D6): one top-level `notify = [...]` key in `config.toml`.
//!
//! No TOML parser exists here, so this is the smallest safe edit: a
//! line-based scan that understands just enough TOML (strings, comments,
//! brackets across lines) to know which lines are top-level, and that
//! refuses anything it is not sure about. ShellX's block is exactly two
//! lines, a marker comment and the `notify` line; a `notify` that is not
//! that block is the user's and is never touched.

use super::{Plan, Refusal};

/// The first line of ShellX's block.
pub const MARKER: &str = "# shellx: agent events (managed by \"shellx integrations\"; remove with \"shellx integrations uninstall codex\")";
/// The second: the whole of what Codex runs.
pub const NOTIFY: &str = "notify = [\"shellx\", \"agent-event\", \"codex\", \"turn-complete\"]";
/// D26: a file over this is left alone.
const MAX_BYTES: usize = 1 << 20;

/// What the line scanner knows between lines.
#[derive(Default)]
struct State {
    /// `[`/`{` opened and not closed.
    depth: i32,
    /// Inside a `"""` or `'''` string: its quote.
    multi: Option<char>,
}

impl State {
    fn clean(&self) -> bool {
        self.depth == 0 && self.multi.is_none()
    }

    /// Reads one line (strings, comments, brackets).
    fn advance(&mut self, line: &str) {
        let c: Vec<char> = line.chars().collect();
        let n = c.len();
        let mut i = 0;
        while i < n {
            if let Some(q) = self.multi {
                if q == '"' && c[i] == '\\' {
                    i += 2;
                } else if c[i] == q && c.get(i + 1) == Some(&q) && c.get(i + 2) == Some(&q) {
                    self.multi = None;
                    i += 3;
                } else {
                    i += 1;
                }
                continue;
            }
            match c[i] {
                '#' => break,
                q @ ('"' | '\'') => {
                    if c.get(i + 1) == Some(&q) && c.get(i + 2) == Some(&q) {
                        self.multi = Some(q);
                        i += 3;
                    } else {
                        i += 1;
                        while i < n && c[i] != q {
                            i += if q == '"' && c[i] == '\\' { 2 } else { 1 };
                        }
                        i += 1;
                    }
                }
                '[' | '{' => {
                    self.depth += 1;
                    i += 1;
                }
                ']' | '}' => {
                    self.depth -= 1;
                    i += 1;
                }
                _ => i += 1,
            }
        }
    }
}

/// The first segment of the key a line starts (`None`: not a key line)
/// and whether it is a dotted key.
fn key_of(line: &str) -> Option<(String, bool)> {
    let t = line.trim_start();
    let cs: Vec<char> = t.chars().collect();
    let mut i = 0;
    let key: String = match cs.first()? {
        &q @ ('"' | '\'') => {
            i = 1;
            let start = i;
            while i < cs.len() && cs[i] != q {
                i += 1;
            }
            let k = cs[start..i.min(cs.len())].iter().collect();
            i += 1;
            k
        }
        c if c.is_ascii_alphanumeric() || *c == '_' || *c == '-' => {
            while i < cs.len() && (cs[i].is_ascii_alphanumeric() || cs[i] == '_' || cs[i] == '-') {
                i += 1;
            }
            cs[..i].iter().collect()
        }
        _ => return None,
    };
    while cs.get(i).is_some_and(|c| *c == ' ' || *c == '\t') {
        i += 1;
    }
    match cs.get(i) {
        Some('=') => Some((key, false)),
        Some('.') => Some((key, true)),
        _ => None,
    }
}

/// `[notify]`, `[notify.x]`, `[[notify]]`: a table of the user's with our key's name.
fn is_notify_table(line: &str) -> bool {
    let h = line.trim_start();
    if !h.starts_with('[') {
        return false;
    }
    let h = h.trim_start_matches('[').trim_start();
    h.strip_prefix("notify")
        .is_some_and(|r| r.trim_start().starts_with([']', '.']))
}

struct Scan<'a> {
    lines: Vec<&'a str>,
    /// The top-level `notify` key: its line, and whether the line stands
    /// alone (no value continues on the next).
    notify: Option<(usize, bool)>,
    /// A table of the user's named `notify`.
    notify_table: bool,
    /// Where a new top-level key can go: the first line that is neither
    /// blank nor a comment (the end of the file when there is none).
    insert_at: usize,
}

fn blank_or_comment(line: &str) -> bool {
    let t = line.trim();
    t.is_empty() || t.starts_with('#')
}

fn scan(body: &str) -> Result<Scan<'_>, Refusal> {
    let lines: Vec<&str> = body.split_inclusive('\n').collect();
    let insert_at = lines
        .iter()
        .position(|l| !blank_or_comment(l))
        .unwrap_or(lines.len());
    let mut st = State::default();
    let mut notify = None;
    let mut notify_table = false;
    let mut in_tables = false;
    for (i, line) in lines.iter().enumerate() {
        if st.clean() {
            let t = line.trim_start();
            if t.starts_with('[') {
                in_tables = true;
            }
            if in_tables {
                notify_table |= is_notify_table(line);
            } else if let Some((key, dotted)) = key_of(line) {
                if key == "notify" && notify.is_none() {
                    notify = Some((i, !dotted));
                }
            }
        }
        st.advance(line);
        if st.depth < 0 {
            return Err(Refusal::Invalid);
        }
        if let Some((at, single)) = notify.as_mut() {
            if *at == i {
                *single &= st.clean();
            }
        }
    }
    if !st.clean() {
        return Err(Refusal::Invalid);
    }
    Ok(Scan {
        lines,
        notify,
        notify_table,
        insert_at,
    })
}

fn eol_of(text: &str) -> &'static str {
    match text.find('\n') {
        Some(i) if i > 0 && text.as_bytes()[i - 1] == b'\r' => "\r\n",
        _ => "\n",
    }
}

fn strip_eol(line: &str) -> &str {
    line.trim_end_matches(['\n', '\r'])
}

fn split_bom(text: &str) -> (&str, &str) {
    match text.strip_prefix('\u{feff}') {
        Some(rest) => ("\u{feff}", rest),
        None => ("", text),
    }
}

/// Line `i` is the `notify` of ShellX's block: the marker is the line
/// before it and it stands alone.
fn is_ours(scan: &Scan, i: usize, single: bool) -> bool {
    single
        && i > 0
        && strip_eol(scan.lines[i - 1]).trim() == MARKER
        && scan.lines[i].contains("\"agent-event\"")
}

fn done(before: Option<&str>, after: String) -> Plan {
    let changed = before != Some(after.as_str());
    Plan {
        before: before.map(String::from),
        after,
        changed,
    }
}

pub fn install(current: Option<&str>) -> Result<Plan, Refusal> {
    let Some(text) = current else {
        return Ok(done(None, format!("{MARKER}\n{NOTIFY}\n")));
    };
    if text.len() > MAX_BYTES {
        return Err(Refusal::TooBig);
    }
    let (bom, body) = split_bom(text);
    let scan = scan(body)?;
    if scan.notify_table {
        return Err(Refusal::Foreign("notify"));
    }
    let eol = eol_of(body);
    let after = match scan.notify {
        Some((i, single)) if is_ours(&scan, i, single) => {
            let mut lines: Vec<String> = scan.lines.iter().map(|l| l.to_string()).collect();
            let end = &scan.lines[i][strip_eol(scan.lines[i]).len()..];
            lines[i] = format!("{NOTIFY}{end}");
            format!("{bom}{}", lines.concat())
        }
        Some(_) => return Err(Refusal::Foreign("notify")),
        None => {
            let at = scan.insert_at;
            let head: String = scan.lines[..at].concat();
            let tail: String = scan.lines[at..].concat();
            let block = if at == scan.lines.len() {
                // The end of the file: no blank line after; a last line
                // without a terminator gets one first (uninstall takes
                // it away again).
                if body.is_empty() || body.ends_with('\n') {
                    format!("{MARKER}{eol}{NOTIFY}{eol}")
                } else {
                    format!("{eol}{MARKER}{eol}{NOTIFY}")
                }
            } else {
                format!("{MARKER}{eol}{NOTIFY}{eol}{eol}")
            };
            format!("{bom}{head}{block}{tail}")
        }
    };
    Ok(done(current, after))
}

/// Removes exactly the two lines (and the blank line install put after
/// them).
pub fn uninstall(current: &str) -> Result<Plan, Refusal> {
    if current.len() > MAX_BYTES {
        return Err(Refusal::TooBig);
    }
    let (bom, body) = split_bom(current);
    let scan = scan(body)?;
    let Some((i, _)) = scan.notify.filter(|(i, s)| is_ours(&scan, *i, *s)) else {
        return Ok(done(Some(current), current.to_string()));
    };
    let from = i - 1;
    let mut to = i + 1; // exclusive
    if scan.lines.get(to).is_some_and(|l| l.trim().is_empty()) {
        to += 1;
    }
    let head: String = scan.lines[..from].concat();
    let mut tail: String = scan.lines[to..].concat();
    // The block ended the file without a terminator: so did the file before.
    let ended_bare = to == scan.lines.len() && !body.ends_with('\n');
    let mut head = head;
    if ended_bare && from > 0 {
        let cut = head.trim_end_matches(['\n', '\r']).len();
        head.truncate(cut);
        tail.clear();
    }
    Ok(done(Some(current), format!("{bom}{head}{tail}")))
}

/// ShellX's block is there as written.
pub fn installed(current: Option<&str>) -> bool {
    let Some(text) = current else { return false };
    let (_, body) = split_bom(text);
    let Ok(scan) = scan(body) else { return false };
    matches!(scan.notify, Some((i, single))
        if is_ours(&scan, i, single) && strip_eol(scan.lines[i]).trim() == NOTIFY)
}

/// What to paste by hand.
pub fn snippet() -> String {
    format!(
        "{MARKER}\n{NOTIFY}\n\n# Codex runs a single notify command. If you already have one, keep yours and\n# call `shellx agent-event codex turn-complete JSON` from it instead; Codex\n# passes the event as JSON in its last argument.\n"
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    fn inst(t: Option<&str>) -> Plan {
        install(t).unwrap()
    }

    #[test]
    fn no_file_gets_the_two_lines() {
        let p = inst(None);
        assert!(p.changed && p.before.is_none());
        assert_eq!(p.after, format!("{MARKER}\n{NOTIFY}\n"));
        assert!(installed(Some(&p.after)));
        assert!(!installed(None));
        assert!(!installed(Some("model = \"o3\"\n")));
    }

    #[test]
    fn the_block_goes_after_the_leading_comments_and_before_any_table() {
        let t = "# my codex config\n# second line\n\n[model]\nname = \"o3\"\n";
        let p = inst(Some(t));
        assert_eq!(
            p.after,
            format!("# my codex config\n# second line\n\n{MARKER}\n{NOTIFY}\n\n[model]\nname = \"o3\"\n")
        );
        // A first line that is a table.
        let t = "[model]\nname = \"o3\"\n";
        assert_eq!(
            inst(Some(t)).after,
            format!("{MARKER}\n{NOTIFY}\n\n[model]\nname = \"o3\"\n")
        );
        // Top-level keys first: the block goes before them (still top level).
        let t = "model = \"o3\"\n[tui]\nx = 1\n";
        let after = inst(Some(t)).after;
        assert!(after.starts_with(MARKER), "{after}");
        assert!(after.find(NOTIFY).unwrap() < after.find("[tui]").unwrap());
    }

    #[test]
    fn install_then_uninstall_is_the_identity() {
        let cases = [
            "",
            "\n",
            "# only a comment\n",
            "# only a comment",
            "# c\n\n",
            "\n\n# c\n\n[model]\nname = 1\n",
            "[model]\nname = 1\n",
            "[model]\nname = 1",
            "model = \"o3\"\n\n[a]\nb = 1\n",
            "model = \"o3\"\r\n\r\n[a]\r\nb = 1\r\n",
            "# crlf\r\n[a]\r\n",
            "\u{feff}# bom\n[a]\nb = 1\n",
            "\u{feff}[a]\nb = 1\n",
            "a = \"\"\"\nmulti\n[not a table]\n\"\"\"\n",
            "list = [\n  [1, 2],\n  [3],\n]\n[t]\n",
        ];
        for t in cases {
            let p = install(Some(t)).unwrap_or_else(|e| panic!("{t:?}: {e:?}"));
            assert!(p.changed, "{t:?}");
            assert!(installed(Some(&p.after)), "{t:?}");
            let back = uninstall(&p.after).unwrap();
            assert_eq!(back.after, t, "{t:?} -> {:?}", p.after);
        }
    }

    #[test]
    fn crlf_files_get_crlf_lines() {
        let p = inst(Some("# c\r\n[a]\r\n"));
        assert!(!p.after.replace("\r\n", "").contains('\n'), "{:?}", p.after);
        assert!(p.after.contains(&format!("{NOTIFY}\r\n")));
    }

    #[test]
    fn a_second_install_changes_nothing() {
        for t in [None, Some("# c\n[a]\n"), Some("")] {
            let a = inst(t);
            let b = install(Some(&a.after)).unwrap();
            assert!(!b.changed && b.after == a.after, "{t:?}");
        }
    }

    #[test]
    fn an_older_shellx_line_is_updated_in_place() {
        let old = format!(
            "{MARKER}\nnotify = [\"shellx\", \"agent-event\", \"codex\", \"done\"]\n\n[a]\n"
        );
        let p = install(Some(&old)).unwrap();
        assert!(p.changed);
        assert_eq!(p.after, format!("{MARKER}\n{NOTIFY}\n\n[a]\n"));
    }

    #[test]
    fn a_users_notify_is_never_replaced() {
        let cases = [
            "notify = [\"my-script\"]\n",
            "  notify=[\"a\",\"b\"]\n",
            "notify = [\n  \"my-script\",\n  \"--flag\",\n]\n",
            "model = 1\nnotify = [\"a\"]\n[t]\n",
            "\"notify\" = [\"a\"]\n",
            "notify.extra = 1\n",
            "[notify]\nx = 1\n",
            "[a]\nb = 1\n[notify.c]\nx = 1\n",
            // A look-alike without the marker is the user's.
            "notify = [\"shellx\", \"agent-event\", \"codex\", \"turn-complete\"]\n",
            // The marker with a multi-line array is not ours either.
            &format!("{MARKER}\nnotify = [\n  \"shellx\", \"agent-event\",\n]\n"),
        ];
        for t in cases {
            assert_eq!(install(Some(t)), Err(Refusal::Foreign("notify")), "{t:?}");
            // And uninstall leaves it alone.
            let u = uninstall(t).unwrap();
            assert!(!u.changed && u.after == t, "{t:?}");
        }
    }

    #[test]
    fn a_notify_in_a_table_or_a_string_is_not_top_level() {
        // `notify` under [tui] belongs to that table: ours goes in front.
        let t = "[tui]\nnotify = [\"x\"]\n";
        let p = inst(Some(t));
        assert!(p.after.starts_with(MARKER), "{}", p.after);
        let t = "text = \"\"\"\nnotify = [\"x\"]\n\"\"\"\n";
        assert!(install(Some(t)).is_ok(), "inside a multi-line string");
        let t = "# notify = [\"x\"]\n";
        assert!(install(Some(t)).is_ok(), "inside a comment");
        let t = "s = 'notify = 1'\n";
        assert!(install(Some(t)).is_ok());
    }

    #[test]
    fn what_cannot_be_scanned_safely_is_refused() {
        for t in ["a = \"\"\"\nnever closed\n", "a = [\n1,\n", "a = {\n"] {
            assert_eq!(install(Some(t)), Err(Refusal::Invalid), "{t:?}");
        }
        let big = format!("# {}\n", "x".repeat(1 << 20));
        assert_eq!(install(Some(&big)), Err(Refusal::TooBig));
    }

    #[test]
    fn uninstall_removes_exactly_the_block() {
        let t = format!("# keep\n{MARKER}\n{NOTIFY}\n\n[a]\nb = 1\n");
        let u = uninstall(&t).unwrap();
        assert_eq!(u.after, "# keep\n[a]\nb = 1\n");
        let only = format!("{MARKER}\n{NOTIFY}\n");
        assert_eq!(uninstall(&only).unwrap().after, "");
        assert!(!uninstall("model = 1\n").unwrap().changed);
    }

    #[test]
    fn the_snippet_is_the_block_and_a_hint() {
        let s = snippet();
        assert!(s.contains(NOTIFY) && s.contains(MARKER));
        assert!(
            s.lines()
                .skip(2)
                .all(|l| l.starts_with('#') || l.is_empty()),
            "{s}"
        );
        assert!(s.contains("turn-complete"));
    }
}
