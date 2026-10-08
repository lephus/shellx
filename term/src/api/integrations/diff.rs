//! Unified diff and the masking of secret-looking values (D7 (1)).
//!
//! The diff is what the person is asked to approve, so it is shown as it
//! will be written — except that anything that looks like a secret is
//! replaced by `"…"` in the *display* (the file is never touched by this).

/// D26: a diff over this many lines is not shown (so not asked about).
pub const MAX_LINES: usize = 5000;
/// The LCS table is skipped above this many cells: the changed middle is
/// then shown as a whole removal and addition, which is still correct.
const MAX_CELLS: usize = 4_000_000;

#[derive(Clone, Copy, PartialEq, Eq)]
enum Op {
    Same,
    Del,
    Add,
}

/// Lines of `s` (each with its terminator, so a missing final newline is a
/// difference too).
fn lines(s: &str) -> Vec<&str> {
    s.split_inclusive('\n').collect()
}

fn script<'a>(a: &[&'a str], b: &[&'a str]) -> Vec<(Op, &'a str)> {
    let pre = a.iter().zip(b).take_while(|(x, y)| x == y).count();
    let suf = a[pre..]
        .iter()
        .rev()
        .zip(b[pre..].iter().rev())
        .take_while(|(x, y)| x == y)
        .count();
    let (ma, mb) = (&a[pre..a.len() - suf], &b[pre..b.len() - suf]);
    let mut ops: Vec<(Op, &str)> = a[..pre].iter().map(|l| (Op::Same, *l)).collect();
    let (n, m) = (ma.len(), mb.len());
    if n * m <= MAX_CELLS {
        // lcs[i][j]: the common run of ma[i..] and mb[j..].
        let w = m + 1;
        let mut lcs = vec![0u32; (n + 1) * w];
        for i in (0..n).rev() {
            for j in (0..m).rev() {
                lcs[i * w + j] = if ma[i] == mb[j] {
                    lcs[(i + 1) * w + j + 1] + 1
                } else {
                    lcs[(i + 1) * w + j].max(lcs[i * w + j + 1])
                };
            }
        }
        let (mut i, mut j) = (0, 0);
        while i < n || j < m {
            if i < n && j < m && ma[i] == mb[j] {
                ops.push((Op::Same, ma[i]));
                i += 1;
                j += 1;
            } else if i < n && (j == m || lcs[(i + 1) * w + j] >= lcs[i * w + j + 1]) {
                ops.push((Op::Del, ma[i]));
                i += 1;
            } else {
                ops.push((Op::Add, mb[j]));
                j += 1;
            }
        }
    } else {
        ops.extend(ma.iter().map(|l| (Op::Del, *l)));
        ops.extend(mb.iter().map(|l| (Op::Add, *l)));
    }
    ops.extend(a[a.len() - suf..].iter().map(|l| (Op::Same, *l)));
    ops
}

/// The hunks that turn `before` into `after` (no `---`/`+++` header), with
/// `context` unchanged lines around each change; empty when equal; `None`
/// when the diff is over [`MAX_LINES`] lines.
pub fn unified_diff(before: &str, after: &str, context: usize) -> Option<String> {
    let ops = script(&lines(before), &lines(after));
    let changes: Vec<usize> = (0..ops.len()).filter(|&i| ops[i].0 != Op::Same).collect();
    // Runs of ops to show: each change widened by `context`, merged.
    let mut runs: Vec<(usize, usize)> = Vec::new();
    for c in changes {
        let (from, to) = (c.saturating_sub(context), (c + context + 1).min(ops.len()));
        match runs.last_mut() {
            Some(last) if from <= last.1 => last.1 = to,
            _ => runs.push((from, to)),
        }
    }
    let mut out = String::new();
    let mut count = 0usize;
    for (from, to) in runs {
        let old_before = ops[..from].iter().filter(|o| o.0 != Op::Add).count();
        let new_before = ops[..from].iter().filter(|o| o.0 != Op::Del).count();
        let slice = &ops[from..to];
        let old_n = slice.iter().filter(|o| o.0 != Op::Add).count();
        let new_n = slice.iter().filter(|o| o.0 != Op::Del).count();
        let old_start = if old_n == 0 {
            old_before
        } else {
            old_before + 1
        };
        let new_start = if new_n == 0 {
            new_before
        } else {
            new_before + 1
        };
        count += slice.len() + 1;
        if count > MAX_LINES {
            return None;
        }
        out.push_str(&format!(
            "@@ -{old_start},{old_n} +{new_start},{new_n} @@\n"
        ));
        for (op, line) in slice {
            out.push(match op {
                Op::Same => ' ',
                Op::Del => '-',
                Op::Add => '+',
            });
            out.push_str(line.trim_end_matches(['\n', '\r']));
            out.push('\n');
        }
    }
    Some(out)
}

const SECRET_WORDS: [&str; 6] = ["key", "token", "secret", "password", "auth", "credential"];
/// Starts of well-known credentials, in case the key does not say so.
const SECRET_PREFIXES: [&str; 9] = [
    "sk-",
    "ghp_",
    "gho_",
    "ghu_",
    "ghs_",
    "github_pat_",
    "xox",
    "AIza",
    "ya29.",
];

fn secret_key(key: &str) -> bool {
    let k = key.to_lowercase();
    SECRET_WORDS.iter().any(|w| k.contains(w))
}

/// `chars[at]` is a quote: the index after the closing one (or the end).
fn string_end(chars: &[char], at: usize) -> usize {
    let q = chars[at];
    let mut i = at + 1;
    while i < chars.len() {
        match chars[i] {
            '\\' if q == '"' => i += 2,
            c if c == q => return i + 1,
            _ => i += 1,
        }
    }
    chars.len()
}

/// A string literal with credentials inside it removed: a token-looking
/// value, or `user:password@` in a URL.
fn clean_literal(lit: &str) -> String {
    let q = lit.chars().next().unwrap_or('"');
    let inner: String = lit.chars().skip(1).collect();
    let inner = inner.strip_suffix(q).unwrap_or(&inner);
    if inner.len() >= 10 && SECRET_PREFIXES.iter().any(|p| inner.starts_with(p)) {
        return format!("{q}…{q}");
    }
    if let Some(scheme) = inner.find("://") {
        let rest = &inner[scheme + 3..];
        let authority = rest.split(['/', '?', '#']).next().unwrap_or("");
        if let Some(at) = authority.rfind('@') {
            let masked = format!("{}://…@{}", &inner[..scheme], &rest[at + 1..]);
            return format!("{q}{masked}{q}");
        }
    }
    lit.to_string()
}

/// Brackets opened and not closed in `chars` (strings skipped).
fn open_brackets(chars: &[char], mut depth: i32) -> i32 {
    let mut i = 0;
    while i < chars.len() {
        match chars[i] {
            '"' | '\'' => i = string_end(chars, i),
            '[' | '{' => {
                depth += 1;
                i += 1;
            }
            ']' | '}' => {
                depth -= 1;
                i += 1;
            }
            _ => i += 1,
        }
    }
    depth.max(0)
}

/// The value after a secret key, replaced by `"…"`.
fn mask_value(chars: &[char], i: &mut usize, out: &mut String, hide: &mut i32) {
    let n = chars.len();
    match chars.get(*i) {
        Some(&q @ ('"' | '\'')) => {
            *i = string_end(chars, *i);
            out.push_str(&format!("{q}…{q}"));
        }
        Some('[' | '{') => {
            let (start, mut depth) = (*i, 0i32);
            let mut j = start;
            while j < n {
                match chars[j] {
                    '"' | '\'' => {
                        j = string_end(chars, j);
                        continue;
                    }
                    '[' | '{' => depth += 1,
                    ']' | '}' => {
                        depth -= 1;
                        if depth == 0 {
                            j += 1;
                            break;
                        }
                    }
                    _ => {}
                }
                j += 1;
            }
            if depth > 0 {
                *hide = depth;
            }
            *i = j.min(n);
            out.push_str("\"…\"");
        }
        Some(_) => {
            let start = *i;
            while *i < n
                && !matches!(chars[*i], ',' | '}' | ']' | '#')
                && !chars[*i].is_whitespace()
            {
                *i += 1;
            }
            if *i > start {
                out.push_str("\"…\"");
            }
        }
        None => {}
    }
}

/// A bare TOML-style key at the start of `chars`: where its `=` is.
fn bare_key(chars: &[char]) -> Option<(String, usize)> {
    let start = chars.iter().take_while(|c| c.is_whitespace()).count();
    let len = chars[start..]
        .iter()
        .take_while(|c| c.is_ascii_alphanumeric() || matches!(c, '_' | '.' | '-'))
        .count();
    if len == 0 {
        return None;
    }
    let mut j = start + len;
    while chars.get(j).is_some_and(|c| c.is_whitespace()) {
        j += 1;
    }
    (chars.get(j) == Some(&'=') && chars.get(j + 1) != Some(&'='))
        .then(|| (chars[start..start + len].iter().collect(), j))
}

fn mask_line(rest: &str, hide: &mut i32) -> String {
    let chars: Vec<char> = rest.chars().collect();
    let n = chars.len();
    if *hide > 0 {
        *hide = open_brackets(&chars, *hide);
        let lead: String = chars.iter().take_while(|c| c.is_whitespace()).collect();
        return format!("{lead}…");
    }
    let mut out = String::new();
    let mut i = 0;
    // A line that is nothing but a string: its key is out of sight.
    let trimmed: Vec<char> = rest.trim().chars().collect();
    if matches!(trimmed.first(), Some('"' | '\'')) {
        let end = string_end(&trimmed, 0);
        let tail: String = trimmed[end..].iter().collect();
        if end > 0 && matches!(tail.trim(), "" | ",") {
            let lead: String = chars.iter().take_while(|c| c.is_whitespace()).collect();
            let q = trimmed[0];
            return format!("{lead}{q}…{q}{tail}");
        }
    }
    if let Some((key, eq)) = bare_key(&chars) {
        if secret_key(&key) {
            i = eq + 1;
            out.extend(&chars[..i]);
            while i < n && chars[i].is_whitespace() {
                out.push(chars[i]);
                i += 1;
            }
            mask_value(&chars, &mut i, &mut out, hide);
        }
    }
    while i < n {
        let c = chars[i];
        if c == '"' || c == '\'' {
            let end = string_end(&chars, i);
            let literal: String = chars[i..end].iter().collect();
            let mut j = end;
            while j < n && chars[j].is_whitespace() {
                j += 1;
            }
            let key: String = chars[i + 1..end.saturating_sub(1).max(i + 1)]
                .iter()
                .collect();
            if j < n && matches!(chars[j], ':' | '=') && secret_key(&key) {
                out.push_str(&literal);
                out.extend(&chars[end..=j]);
                i = j + 1;
                while i < n && chars[i].is_whitespace() {
                    out.push(chars[i]);
                    i += 1;
                }
                mask_value(&chars, &mut i, &mut out, hide);
            } else {
                out.push_str(&clean_literal(&literal));
                i = end;
            }
        } else if c == '#' {
            out.extend(&chars[i..]);
            break;
        } else {
            out.push(c);
            i += 1;
        }
    }
    out
}

/// D7 (1): for display only, the value of a key that looks like a secret
/// (`key`, `token`, `secret`, `password`, `auth`, `credential`, any case)
/// becomes `"…"`, as do token-looking strings, `user:pass@` in URLs and
/// the lines of a secret list or object. Hunk headers are left alone.
pub fn mask_secrets(diff: &str) -> String {
    let mut hide = 0i32;
    let mut out = String::with_capacity(diff.len());
    for line in diff.split_inclusive('\n') {
        let (body, eol) = match line.strip_suffix('\n') {
            Some(b) => (b, "\n"),
            None => (line, ""),
        };
        if body.starts_with("@@") {
            out.push_str(line);
            continue;
        }
        let mut cs = body.chars();
        match cs.next() {
            Some(p @ (' ' | '+' | '-')) => {
                out.push(p);
                out.push_str(&mask_line(cs.as_str(), &mut hide));
            }
            _ => out.push_str(&mask_line(body, &mut hide)),
        }
        out.push_str(eol);
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn one_insertion_is_a_small_hunk_with_two_lines_of_context() {
        let before = "a\nb\nc\nd\ne\nf\ng\n";
        let after = "a\nb\nc\nX\nd\ne\nf\ng\n";
        assert_eq!(
            unified_diff(before, after, 2).unwrap(),
            "@@ -2,4 +2,5 @@\n b\n c\n+X\n d\n e\n"
        );
    }

    #[test]
    fn a_new_file_is_all_additions_and_no_change_is_empty() {
        assert_eq!(
            unified_diff("", "x\ny\n", 2).unwrap(),
            "@@ -0,0 +1,2 @@\n+x\n+y\n"
        );
        assert_eq!(unified_diff("x\n", "x\n", 2).unwrap(), "");
    }

    #[test]
    fn replacements_and_removals_show_both_sides() {
        let d = unified_diff("a\nb\nc\n", "a\nB\nc\n", 1).unwrap();
        assert_eq!(d, "@@ -1,3 +1,3 @@\n a\n-b\n+B\n c\n");
        let d = unified_diff("a\nb\n", "a\n", 2).unwrap();
        assert_eq!(d, "@@ -1,2 +1,1 @@\n a\n-b\n");
    }

    #[test]
    fn distant_changes_make_two_hunks() {
        let before: String = (1..=20).map(|i| format!("l{i}\n")).collect();
        let after = before.replace("l2\n", "L2\n").replace("l19\n", "L19\n");
        let d = unified_diff(&before, &after, 2).unwrap();
        assert_eq!(d.matches("@@").count(), 4, "{d}");
    }

    #[test]
    fn crlf_lines_are_shown_without_their_carriage_return() {
        let d = unified_diff("a\r\nb\r\n", "a\r\nX\r\nb\r\n", 2).unwrap();
        assert!(!d.contains('\r'), "{d:?}");
        assert!(d.contains("+X\n"));
    }

    #[test]
    fn over_five_thousand_lines_there_is_no_diff() {
        let big: String = (0..6000).map(|i| format!("{i}\n")).collect();
        assert!(unified_diff("", &big, 2).is_none());
        assert!(unified_diff(&big, "", 2).is_none());
        let small: String = (0..4000).map(|i| format!("{i}\n")).collect();
        assert!(unified_diff("", &small, 2).is_some());
        // A small change in a huge file is still small.
        let edited = big.replace("3000\n", "three thousand\n");
        let d = unified_diff(&big, &edited, 2).unwrap();
        assert!(d.lines().count() < 20, "{d}");
    }

    #[test]
    fn secret_values_are_masked_in_the_display() {
        let d = "@@ -1,3 +1,4 @@\n   \"env\": {\n-    \"ANTHROPIC_API_KEY\": \"sk-ant-FAKE\",\n+    \"My_Token\": 12345,\n     \"password\" : \"hunter2\"\n     \"X_AUTH\": true,\n     \"credentials\": null\n";
        let m = mask_secrets(d);
        assert!(
            !m.contains("sk-ant") && !m.contains("12345") && !m.contains("hunter2"),
            "{m}"
        );
        assert!(m.contains("\"ANTHROPIC_API_KEY\": \"…\","), "{m}");
        assert!(m.contains("\"My_Token\": \"…\""), "{m}");
        assert!(m.contains("\"password\" : \"…\""), "{m}");
        assert!(m.contains("\"X_AUTH\": \"…\""), "{m}");
        assert!(m.contains("\"credentials\": \"…\""), "{m}");
        // Keys that do not look secret keep their values.
        let keep =
            "     \"model\": \"sonnet\",\n+    \"command\": \"shellx agent-event claude stop\",\n";
        assert_eq!(mask_secrets(keep), keep);
    }

    #[test]
    fn masking_keeps_the_diff_prefix_and_other_pairs_on_the_line() {
        let m = mask_secrets("+  { \"name\": \"a\", \"apiKey\": \"zzz\", \"n\": 1 }\n");
        assert_eq!(m, "+  { \"name\": \"a\", \"apiKey\": \"…\", \"n\": 1 }\n");
        assert_eq!(mask_secrets("-api_key = \"abc\"\n"), "-api_key = \"…\"\n");
        assert_eq!(mask_secrets(" token = 'abc' # c\n"), " token = '…' # c\n");
    }

    #[test]
    fn a_secret_list_or_object_is_masked_to_its_end() {
        let d = " \"apiKeys\": [\n   \"sk-live-1\",\n   \"sk-live-2\"\n ],\n \"model\": \"x\"\n";
        let m = mask_secrets(d);
        assert!(!m.contains("sk-live"), "{m}");
        assert!(m.contains("\"model\": \"x\""), "{m}");
        // A bare string line (the key is out of the hunk) is masked too.
        let m = mask_secrets("   \"sk-ant-api03-zzz\",\n");
        assert!(!m.contains("sk-ant"), "{m}");
    }

    #[test]
    fn a_url_with_credentials_loses_them() {
        let m = mask_secrets(" \"HTTPS_PROXY\": \"http://user:FAKEPASS@proxy.example:8080\",\n");
        assert!(!m.contains("FAKEPASS") && !m.contains("user:"), "{m}");
        assert!(m.contains("proxy.example"), "{m}");
    }

    #[test]
    fn hunk_headers_are_untouched() {
        let h = "@@ -1,3 +1,4 @@\n";
        assert_eq!(mask_secrets(h), h);
    }
}
