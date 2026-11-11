//! Redactor for log, crash and report lines: emails, tokens, one-time codes and Resend keys.
//!
//! Hand-written scanning (no regex crate). The four passes run in this order and repeat
//! until the text no longer changes.
//!
//! Known limits (kept on purpose; each would cost more readable text than it protects):
//! - A prefix glued to a UUID (`machine-0e7a...`) is one run: it is kept when it is hex and
//!   dashes only, hidden when the prefix has other letters and the run is 32+ characters.
//! - Constant names such as `D3D11_CREATE_DEVICE_BGRA_SUPPORT` (32+ characters, with a
//!   digit) read as tokens.
//! - A code more than 24 characters away from its keyword, or split (`123 456`), is not hidden;
//!   neither is an email written `%40` or `\u0040`.
//! - Hex-only secrets are kept; the relay's secrets are base64url.

/// Shortest run of token characters (without a trailing `=`) that counts as a secret.
const TOKEN_MIN_CHARS: usize = 32;
/// A code is hidden when one of these words stands this near it on the same line.
const CODE_CONTEXT_CHARS: usize = 24;

/// Replaces emails with `<email>`, Resend keys with `<key>`, long token-like runs with
/// `<token>` and six-digit codes near the words "code", "otp" or "mã" with `<code>`.
/// Paths, machine ids, commit hashes and version numbers stay readable.
///
/// A replacement can change what the next pass sees (a shorter text brings a keyword within
/// reach, `<code>` ends a word), so the four passes repeat until nothing changes. That makes
/// the result stable, `redact(redact(s)) == redact(s)`, which matters because the report
/// formatter runs over log lines the logger already redacted. Every round only turns text
/// into markers, so it ends after a few rounds (the cap is a guard).
pub fn redact(text: &str) -> String {
    const MAX_ROUNDS: usize = 8;
    let mut current = redact_once(text);
    for _ in 0..MAX_ROUNDS {
        let next = redact_once(&current);
        if next == current {
            break;
        }
        current = next;
    }
    current
}

fn redact_once(text: &str) -> String {
    let s = redact_emails(text);
    let s = redact_keys(&s);
    let s = redact_tokens(&s);
    redact_codes(&s)
}

fn is_local_char(c: char) -> bool {
    c.is_alphanumeric() || matches!(c, '.' | '_' | '%' | '+' | '-')
}

fn is_domain_char(c: char) -> bool {
    c.is_alphanumeric() || c == '-'
}

/// The end (exclusive) of the domain that starts at `start`: labels of alphanumeric or `-`
/// joined by `.`, at least two, a trailing `.` or `-` not taken.
fn domain_end(chars: &[char], start: usize) -> Option<usize> {
    let n = chars.len();
    let mut i = start;
    let mut labels = 0;
    let mut end = start;
    loop {
        let label_start = i;
        while i < n && is_domain_char(chars[i]) {
            i += 1;
        }
        let mut label_end = i;
        while label_end > label_start && chars[label_end - 1] == '-' {
            label_end -= 1;
        }
        if label_end == label_start {
            break;
        }
        labels += 1;
        end = label_end;
        if label_end != i {
            break; // a trailing hyphen ends the domain
        }
        if i + 1 < n && chars[i] == '.' {
            i += 1;
        } else {
            break;
        }
    }
    (labels >= 2).then_some(end)
}

fn redact_emails(text: &str) -> String {
    if !text.contains('@') {
        return text.to_string();
    }
    let chars: Vec<char> = text.chars().collect();
    let mut spans: Vec<(usize, usize)> = Vec::new();
    for at in 0..chars.len() {
        if chars[at] != '@' {
            continue;
        }
        let mut start = at;
        while start > 0 && is_local_char(chars[start - 1]) {
            start -= 1;
        }
        if start == at {
            continue;
        }
        let Some(end) = domain_end(&chars, at + 1) else {
            continue;
        };
        match spans.last_mut() {
            Some(last) if start < last.1 => last.1 = last.1.max(end),
            _ => spans.push((start, end)),
        }
    }
    let mut out = String::with_capacity(text.len());
    let mut pos = 0;
    for (start, end) in spans {
        out.extend(&chars[pos..start]);
        out.push_str("<email>");
        pos = end;
    }
    out.extend(&chars[pos..]);
    out
}

fn is_key_char(c: char) -> bool {
    c.is_ascii_alphanumeric() || c == '_'
}

/// The end (exclusive) of a Resend key that starts at `i`: `re_` and at least 8 key chars.
fn key_end(chars: &[char], i: usize) -> Option<usize> {
    if !chars[i..].starts_with(&['r', 'e', '_']) {
        return None;
    }
    let mut j = i + 3;
    while j < chars.len() && is_key_char(chars[j]) {
        j += 1;
    }
    (j - (i + 3) >= 8).then_some(j)
}

fn redact_keys(text: &str) -> String {
    if !text.contains("re_") {
        return text.to_string();
    }
    let chars: Vec<char> = text.chars().collect();
    let mut out = String::with_capacity(text.len());
    let mut i = 0;
    while i < chars.len() {
        let after_word = i > 0 && (chars[i - 1].is_alphanumeric() || chars[i - 1] == '_');
        if !after_word && let Some(end) = key_end(&chars, i) {
            out.push_str("<key>");
            i = end;
            continue;
        }
        out.push(chars[i]);
        i += 1;
    }
    out
}

/// Characters of a token in the URL-safe alphabet (and of the pieces of a path).
fn is_url_safe_char(c: char) -> bool {
    c.is_ascii_alphanumeric() || c == '_' || c == '-'
}

/// Characters of a standard base64 value (without the `=` padding).
fn is_base64_char(c: char) -> bool {
    is_url_safe_char(c) || c == '+' || c == '/'
}

/// Looks random rather than like a name: a digit, or both cases well represented (at least
/// 8 upper-case and 8 lower-case ASCII letters). Random base64url values have a digit in all
/// but about 1 in 1 600; `SOME_LONG_CONSTANT_NAME` has no lower case and
/// `CreateSwapChainForCompositionSurfaceHandle` has only 7 capitals.
fn looks_random(run: &[char]) -> bool {
    let upper = run.iter().filter(|c| c.is_ascii_uppercase()).count();
    let lower = run.iter().filter(|c| c.is_ascii_lowercase()).count();
    run.iter().any(char::is_ascii_digit) || (upper >= 8 && lower >= 8)
}

/// A URL-safe token: at least 32 characters with a letter, `looks_random`, and not only hex
/// digits and dashes (machine ids, commit ids and checksums stay readable).
fn is_url_safe_token(run: &[char]) -> bool {
    run.len() >= TOKEN_MIN_CHARS
        && run.iter().any(char::is_ascii_alphabetic)
        && looks_random(run)
        && !run.iter().all(|c| c.is_ascii_hexdigit() || *c == '-')
}

/// `/` never joins a token, so a path or URL is judged piece by piece. Two kinds of secret
/// are hidden: (a) a URL-safe run (`[A-Za-z0-9_-]`, 43 characters for the relay's tokens)
/// that `is_url_safe_token`; (b) a standard base64 run (`[A-Za-z0-9+/_-]`, then any `=`
/// padding) of at least 32 characters that `looks_random` and contains `+` or ends with `=`.
fn redact_tokens(text: &str) -> String {
    let chars: Vec<char> = text.chars().collect();
    let mut out = String::with_capacity(text.len());
    let mut i = 0;
    while i < chars.len() {
        if !is_base64_char(chars[i]) {
            out.push(chars[i]);
            i += 1;
            continue;
        }
        let mut j = i;
        while j < chars.len() && is_base64_char(chars[j]) {
            j += 1;
        }
        let mut k = j;
        while k < chars.len() && chars[k] == '=' {
            k += 1;
        }
        let run = &chars[i..j];
        let standard_base64 =
            run.len() >= TOKEN_MIN_CHARS && looks_random(run) && (run.contains(&'+') || k > j);
        if standard_base64 {
            out.push_str("<token>");
        } else {
            // judge each piece between `+` and `/` on its own
            let mut p = i;
            while p < j {
                if !is_url_safe_char(chars[p]) {
                    out.push(chars[p]);
                    p += 1;
                    continue;
                }
                let mut q = p;
                while q < j && is_url_safe_char(chars[q]) {
                    q += 1;
                }
                if is_url_safe_token(&chars[p..q]) {
                    out.push_str("<token>");
                } else {
                    out.extend(&chars[p..q]);
                }
                p = q;
            }
            out.extend(&chars[j..k]);
        }
        i = k;
    }
    out
}

/// The words that make a nearby six-digit number a code: `code`, `otp`, Vietnamese `mã`
/// (composed or with a combining tilde), compared without regard to case.
const CODE_WORDS: [&[char]; 4] = [
    &['c', 'o', 'd', 'e'],
    &['o', 't', 'p'],
    &['m', '\u{e3}'],
    &['m', 'a', '\u{303}'],
];

fn lower(c: char) -> char {
    c.to_lowercase().next().unwrap_or(c)
}

/// Whether `text[from..to]` holds one of the code words as a whole word. A word starts after
/// a non-letter or at a lower-to-upper case change (`signInCode`, `otpCode`), and ends before
/// a non-letter, or before one `s`/`S` and then a non-letter (`codes`, `OTPs`). The characters
/// just outside the window count too, so `encoder`, `decode`, `Unicode`, `barcode` and
/// `codesign` do not match, while `error_code` and `code=` do.
fn mentions_code(text: &[char], from: usize, to: usize) -> bool {
    (from..to).any(|a| {
        CODE_WORDS.iter().any(|word| {
            let b = a + word.len();
            if b > to
                || !text[a..b]
                    .iter()
                    .zip(word.iter())
                    .all(|(c, w)| lower(*c) == *w)
            {
                return false;
            }
            let starts = a == 0
                || !text[a - 1].is_alphabetic()
                || (text[a - 1].is_lowercase() && text[a].is_uppercase());
            let ends = text.get(b).is_none_or(|c| !c.is_alphabetic())
                || (matches!(text[b], 's' | 'S')
                    && text.get(b + 1).is_none_or(|c| !c.is_alphabetic()));
            starts && ends
        })
    })
}

const CODE_MARKER: [char; 6] = ['<', 'c', 'o', 'd', 'e', '>'];

/// The text with every `<code>` marker blanked out (same length): our own marker must not
/// count as the word "code", or a second pass would hide more than the first.
fn without_code_markers(chars: &[char]) -> Vec<char> {
    let mut masked = chars.to_vec();
    let mut i = 0;
    while i + CODE_MARKER.len() <= masked.len() {
        if masked[i..i + CODE_MARKER.len()] == CODE_MARKER {
            masked[i..i + CODE_MARKER.len()].fill('\u{1}');
            i += CODE_MARKER.len();
        } else {
            i += 1;
        }
    }
    masked
}

fn redact_codes(text: &str) -> String {
    let chars: Vec<char> = text.chars().collect();
    let masked = without_code_markers(&chars);
    let is_break = |c: char| c == '\n' || c == '\r';
    let mut out = String::with_capacity(text.len());
    let mut i = 0;
    while i < chars.len() {
        if !chars[i].is_ascii_digit() {
            out.push(chars[i]);
            i += 1;
            continue;
        }
        let mut j = i;
        while j < chars.len() && chars[j].is_ascii_digit() {
            j += 1;
        }
        if j - i == 6 {
            let mut before = i;
            while before > 0 && i - before < CODE_CONTEXT_CHARS && !is_break(chars[before - 1]) {
                before -= 1;
            }
            let mut after = j;
            while after < chars.len() && after - j < CODE_CONTEXT_CHARS && !is_break(chars[after]) {
                after += 1;
            }
            if mentions_code(&masked, before, i) || mentions_code(&masked, j, after) {
                out.push_str("<code>");
                i = j;
                continue;
            }
        }
        out.extend(&chars[i..j]);
        i = j;
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    const T43: &str = "AbCdEfGhIjKlMnOpQrStUvWxYz0123456789_-AbCdE"; // 43 chars, base64url

    #[test]
    fn redacts_each_kind() {
        assert_eq!(
            redact("signed in as phu.le+test@gmail.com via email"),
            "signed in as <email> via email"
        );
        assert_eq!(redact("user Phú@ví-dụ.vn"), "user <email>");
        assert_eq!(
            redact("RESEND_API_KEY=re_AbCdEf123_xyz"),
            "RESEND_API_KEY=<key>"
        );
        assert_eq!(redact("your code is 123456"), "your code is <code>");
        assert_eq!(redact("Mã: 112233"), "Mã: <code>");
        assert_eq!(redact("OTP 654321 sent"), "OTP <code> sent");
        // an address that ends a sentence, and two on one line
        assert_eq!(redact("mail a@b.co."), "mail <email>.");
        assert_eq!(redact("a@b.co, c@d.org"), "<email>, <email>");
    }

    #[test]
    fn redacts_secrets_in_json_urls_and_headers() {
        assert_eq!(
            redact(&format!("Authorization: Bearer {T43}")),
            "Authorization: Bearer <token>"
        );
        assert_eq!(
            redact(&format!(r#"{{"token":"{T43}"}}"#)),
            r#"{"token":"<token>"}"#
        );
        assert_eq!(
            redact(&format!("GET /cb?code=123456&state={T43}")),
            "GET /cb?code=<code>&state=<token>"
        );
        assert_eq!(redact(&format!("{T43}.{T43}")), "<token>.<token>");
        let out = redact(&format!(
            "panicked at src/ui/account.rs:12:5:\nlogin failed for a@b.co with {T43}"
        ));
        assert!(!out.contains("a@b.co"), "{out}");
        assert!(!out.contains(T43), "{out}");
        assert!(
            out.starts_with("panicked at src/ui/account.rs:12:5:\n"),
            "{out}"
        );
        let padded = format!("{}+/s=", "+/v7".repeat(10));
        assert_eq!(redact(&padded), "<token>");
        // a 44-character standard base64 value, in the same places
        const B44: &str = "Zm9vYmFyYmF6+/Zm9vYmFyYmF6Zm9vYmFyYmF6Zm9vA=";
        assert_eq!(B44.len(), 44);
        assert_eq!(redact(B44), "<token>");
        assert_eq!(redact(&format!("sig={B44}&x=1")), "sig=<token>&x=1");
        assert_eq!(
            redact(&format!(r#"{{"secret":"{B44}"}}"#)),
            r#"{"secret":"<token>"}"#
        );
        // a 43-character base64url value alone, in a URL query and after Bearer
        assert_eq!(redact(T43), "<token>");
        assert_eq!(
            redact(&format!("/cb?state={T43}&x=1")),
            "/cb?state=<token>&x=1"
        );
        // a token that sits in a path segment is still hidden, its neighbours are not
        assert_eq!(
            redact(&format!("/v2/links/{T43}/open")),
            "/v2/links/<token>/open"
        );
    }

    #[test]
    fn keeps_paths_ids_and_versions_readable() {
        for text in [
            r"C:\Users\Phú\Tài liệu\dự án",
            "machine 0e7a1c2b-3d4e-4f50-8a9b-0c1d2e3f4a5b online",
            "commit c06834ec4e5f7a8b9c0d1e2f3a4b5c6d7e8f9a0b",
            "GPU Intel(R) UHD Graphics 620 driver 31.0.101.2125",
            "https://relay.shellx.pro/v2/relay",
            "/Users/richard/Documents/helper/shellx",
            "1920x1080 150%",
            "pid 123456 started",
            "1234567 code",
            "prepare_something re_x",
            // request paths and crash locations keep their ids and file names
            "/v2/machines/0e7a1c2b-3d4e-4f50-8a9b-0c1d2e3f4a5b/heartbeat: server answered 404 not_found",
            "network: /v2/shares/0e7a1c2b-3d4e-4f50-8a9b-0c1d2e3f4a5b/host-ticket: timed out",
            "https://relay.shellx.pro/v2/machines/0e7a1c2b-3d4e-4f50-8a9b-0c1d2e3f4a5b",
            "panicked at /Users/x/.cargo/registry/src/index.crates.io-1949cf8c6b5b557f/gpui-0.2.2/src/platform/windows/directx_renderer.rs:1557:5",
            "windows/vendor/gpui-0.2.2/src/platform/windows/directx_renderer.rs:1557:5",
            "/home/u/.local/share/shellx/2026-11-12.log",
            "0e7a1c2b-3d4e-4f50-8a9b-0c1d2e3f4a5b",
            "gpui-0.2.2",
            "driver 31.0.101.2125",
            "da39a3ee5e6b4b0d3255bfef95601890afd80709da39a3ee5e6b4b0d3255bfef",
        ] {
            assert_eq!(redact(text), text);
        }
    }

    #[test]
    fn the_code_word_matches_whole_words_only() {
        for text in [
            "code 123456",
            "CODE: 123456",
            "code=123456",
            "error_code 123456",
            "Your OTP is 123456",
            "otp=123456",
            "Mã xác nhận 123456",
            "MÃ 123456",
            "ma\u{303} 123456",
            "123456 is your code",
        ] {
            assert!(!redact(text).contains("123456"), "{text}");
        }
        for text in [
            "encoder 654321 frames",
            "Unicode decode 123456",
            "barcode 123456",
            "hotplug 123456",
            "encoding 123456 bytes",
            "codec 123456",
            "mãi 123456",
            // the 24-character window must not cut a longer word down to "code"
            &format!("de{}123456", "code".to_string() + &" ".repeat(20)),
            &format!("123456{}coded", " ".repeat(20)),
        ] {
            assert_eq!(redact(text), text, "{text}");
        }
    }

    #[test]
    fn a_token_without_a_digit_is_still_hidden() {
        // 43 base64url characters, mixed case with `-` and `_`, no digit
        const NO_DIGIT: &str = "AbCdEfGhIjKlMnOpQrStUvWxYz-_aBcDeFgHiJkLmNo";
        assert_eq!(NO_DIGIT.len(), 43);
        assert!(!NO_DIGIT.chars().any(|c| c.is_ascii_digit()));
        assert_eq!(redact(NO_DIGIT), "<token>");
        assert_eq!(
            redact(&format!("Authorization: Bearer {NO_DIGIT}")),
            "Authorization: Bearer <token>"
        );
        assert_eq!(
            redact(&format!(r#"{{"token":"{NO_DIGIT}"}}"#)),
            r#"{"token":"<token>"}"#
        );
        assert_eq!(
            redact(&format!("/cb?state={NO_DIGIT}&x=1")),
            "/cb?state=<token>&x=1"
        );
        // a standard base64 value without a digit: it has `+` and mixed case
        let b64 = "AbCdEfGhIjKlMnOpQrSt+UvWxYzaBcDeFgHiJkLm/No=";
        assert_eq!(redact(b64), "<token>");
        // names stay readable: no digit and not mixed case enough
        for text in [
            "ERROR_GRAPHICS_OPM_PROTECTED_OUTPUT_DOES_NOT_HAVE_COPP_SEMANTICS",
            "some_very_long_snake_case_identifier_name_here",
            "CreateSwapChainForCompositionSurfaceHandle",
            "failed in CreateSwapChainForCompositionSurfaceHandle: 0x887A0005",
        ] {
            assert_eq!(redact(text), text);
        }
    }

    #[test]
    fn camel_case_and_plural_code_words_count() {
        for text in [
            "signInCode: 123456",
            "emailCode=123456",
            r#"{"otpCode":"123456"}"#,
            "codes: 123456",
            "OTPs 123456",
            "otps 123456",
            "Mãs 123456",
        ] {
            assert!(!redact(text).contains("123456"), "{text}");
        }
        for text in [
            "encoder 654321 frames",
            "decode 123456",
            "Unicode 123456",
            "barcode 123456",
            "codesign 123456",
            "decodes 123456",
            "Unicodes 123456",
            "barcodes 123456",
            "codec 123456",
            "hotplugs 123456",
        ] {
            assert_eq!(redact(text), text, "{text}");
        }
    }

    #[test]
    fn redaction_is_idempotent_and_total() {
        let samples = [
            "signed in as phu.le+test@gmail.com via email",
            "user Phú@ví-dụ.vn",
            "RESEND_API_KEY=re_AbCdEf123_xyz",
            "your code is 123456",
            "Mã: 112233",
            "GET /cb?code=123456&state=AbCdEfGhIjKlMnOpQrStUvWxYz0123456789_-AbCdE",
            "panicked at src/ui/account.rs:12:5:\nlogin failed for a@b.co with AbCdEfGhIjKlMnOpQrStUvWxYz0123456789_-AbCdE",
            r"C:\Users\Phú\Tài liệu\dự án",
            "commit c06834ec4e5f7a8b9c0d1e2f3a4b5c6d7e8f9a0b",
            "a@b.co@@c.de",
            "x@<email>",
            "<email>@a.bc",
            // found by the generator below: a replacement that shortens the text
            "123456/123456re_123456re__>code\n>=",
            "123456re_abcdefgh near the code",
        ];
        for s in samples {
            let once = redact(s);
            assert_eq!(redact(&once), once, "{s:?}");
        }
        for s in ["@", "@@@", "a@", "@b.c", "ế@ê.ễ", "re_", ""] {
            let once = redact(s);
            assert_eq!(redact(&once), once, "{s:?}");
        }
        let long = "a".repeat(10_000);
        assert_eq!(redact(&redact(&long)), redact(&long));
        // pieces that can build every pattern in odd orders
        let x32 = "x".repeat(32);
        let pieces = [
            "a",
            "Z",
            "1",
            "123456",
            "_",
            "-",
            "+",
            "/",
            "=",
            ".",
            "@",
            " ",
            "\n",
            ":",
            "<",
            ">",
            "é",
            "re_",
            "code",
            "mã",
            "otp",
            "<email>",
            "<token>",
            x32.as_str(),
        ];
        let mut seed: u64 = 0x2545_F491_4F6C_DD1D;
        for _ in 0..4000 {
            let mut s = String::new();
            for _ in 0..14 {
                seed = seed
                    .wrapping_mul(6364136223846793005)
                    .wrapping_add(1442695040888963407);
                s.push_str(pieces[(seed >> 33) as usize % pieces.len()]);
            }
            let once = redact(&s);
            assert_eq!(redact(&once), once, "{s:?}");
        }
    }
}
