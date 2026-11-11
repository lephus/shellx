//! Email code sign-in for the desktop: a 6-digit code mailed by the relay.
//!
//! `begin` asks the relay to mail a code and returns the challenge to verify it against; it writes nothing.
//! `finish` verifies the code and signs this device in, writing `session.json` with `auth_method = "email"`.
//! Both refuse locally what the relay would refuse (an address outside ASCII, a code that is not six digits),
//! so no request is sent and no guess is spent. Neither sends a bearer. The address, the code and the
//! challenge id never reach a result, an error message or a `Debug`.

use crate::api::{EmailCodeRequest, EmailCodeResponse, EmailVerifyRequest, GoogleAuthResponse, LoginDevice, SessionFile};
use crate::config::Config;
use crate::envelope::CoreError;
use crate::fingerprint::fingerprint;
use crate::http::{self, Method};
use crate::store::StateStore;
use base64::Engine;
use base64::engine::general_purpose::URL_SAFE_NO_PAD;
use serde_json::{Value, json};
use std::sync::Mutex;
use zeroize::Zeroizing;

pub const CODE_PATH: &str = "/v1/auth/email/code";
pub const VERIFY_PATH: &str = "/v1/auth/email/verify";
/// The relay's limit for a whole address.
pub const MAX_EMAIL_BYTES: usize = 254;

/// The first code point of every run of ten Unicode decimal digits (General_Category Nd, Unicode 13), from
/// `python3 -I -c "import unicodedata as u; print([hex(c) for c in range(0x110000) if u.category(chr(c)) == 'Nd' and u.decimal(chr(c)) == 0])"`.
/// Digits of scripts added after Unicode 13 are not mapped, and are refused like letters.
pub const DECIMAL_ZEROS: &[u32] = &[
    0x0030, 0x0660, 0x06F0, 0x07C0, 0x0966, 0x09E6, 0x0A66, 0x0AE6, 0x0B66, 0x0BE6, 0x0C66, 0x0CE6, 0x0D66, 0x0DE6, 0x0E50, 0x0ED0,
    0x0F20, 0x1040, 0x1090, 0x17E0, 0x1810, 0x1946, 0x19D0, 0x1A80, 0x1A90, 0x1B50, 0x1BB0, 0x1C40, 0x1C50, 0xA620, 0xA8D0, 0xA900,
    0xA9D0, 0xA9F0, 0xAA50, 0xABF0, 0xFF10, 0x104A0, 0x10D30, 0x11066, 0x110F0, 0x11136, 0x111D0, 0x112F0, 0x11450, 0x114D0, 0x11650,
    0x116C0, 0x11730, 0x118E0, 0x11950, 0x11C50, 0x11D50, 0x11DA0, 0x16A60, 0x16B50, 0x1D7CE, 0x1D7D8, 0x1D7E2, 0x1D7EC, 0x1D7F6,
    0x1E140, 0x1E2F0, 0x1E950, 0x1FBF0,
];

/// A value starting with "vi" (any case) is "vi"; anything else, or nothing, is "en". The relay mails
/// Vietnamese only for exactly "vi", so the core sends nothing else.
pub fn locale_of(raw: Option<&str>) -> &'static str {
    match raw {
        Some(l) if l.as_bytes().get(..2).is_some_and(|b| b.eq_ignore_ascii_case(b"vi")) => "vi",
        _ => "en",
    }
}

/// `raw` trimmed, when that is not empty, ASCII only and at most `MAX_EMAIL_BYTES` long (else the relay would
/// refuse it, after spending one of the ten per-IP requests a minute).
pub fn sendable_email(raw: &str) -> Option<&str> {
    let t = raw.trim();
    (!t.is_empty() && t.is_ascii() && t.len() <= MAX_EMAIL_BYTES).then_some(t)
}

/// The value of a Unicode decimal digit (ASCII, full-width, Arabic-Indic, Devanagari, ...).
pub fn decimal_digit(c: char) -> Option<u32> {
    let n = c as u32;
    DECIMAL_ZEROS.iter().find(|&&z| (z..z + 10).contains(&n)).map(|&z| n - z)
}

/// `raw` without whitespace (`char::is_whitespace`) and with every decimal digit as ASCII, when that is exactly
/// six digits.
pub fn clean_code(raw: &str) -> Option<String> {
    let mut out = String::with_capacity(6);
    for c in raw.chars().filter(|c| !c.is_whitespace()) {
        let d = decimal_digit(c)?;
        if out.len() == 6 {
            return None;
        }
        out.push(char::from_digit(d, 10)?);
    }
    (out.len() == 6).then_some(out)
}

/// A relay without the feature (a 404, with or without the error envelope, or a 503 `email_sign_in_disabled`)
/// is one code for the apps. Every other error is returned as it came.
fn map_relay(path: &str, e: CoreError) -> CoreError {
    match e.code.as_str() {
        "not_found" | "http_404" | "email_sign_in_disabled" => {
            CoreError::new("email_sign_in_disabled", format!("{path}: this relay has no email sign-in"))
        }
        _ => e,
    }
}

/// `auth.email.begin {email, locale?}` -> `{challenge_id, expires_in, resend_in, email}`.
pub fn begin(agent: &ureq::Agent, cfg: &Config, params: &Value) -> Result<Value, CoreError> {
    if !params.is_object() {
        return Err(CoreError::invalid_params("params must be an object"));
    }
    let raw = params
        .get("email")
        .and_then(Value::as_str)
        .ok_or_else(|| CoreError::invalid_params("email is required and must be a string"))?;
    let Some(email) = sendable_email(raw) else {
        return Err(CoreError::new("invalid_email", "the address is empty, too long or not plain ASCII"));
    };
    let locale = locale_of(params.get("locale").and_then(Value::as_str));
    let body = Zeroizing::new(
        serde_json::to_vec(&EmailCodeRequest { email, locale }).map_err(|_| CoreError::new("io", "request body is not serializable"))?,
    );
    let resp: EmailCodeResponse = http::send(agent, cfg, None, Method::Post, CODE_PATH, Some(&body), None)
        .and_then(|reply| http::parse_json(CODE_PATH, &reply))
        .map_err(|e| map_relay(CODE_PATH, e))?;
    if resp.challenge_id.is_empty() {
        return Err(CoreError::new("server", format!("{CODE_PATH}: response has no challenge_id")));
    }
    let shown = if resp.email.is_empty() { email.to_string() } else { resp.email };
    Ok(json!({
        "challenge_id": resp.challenge_id,
        "expires_in": resp.expires_in,
        "resend_in": resp.resend_in,
        "email": shown,
    }))
}

/// `auth.email.finish {challenge_id, code}` -> the six fields of `auth.google.finish`, `auth_method: "email"`.
pub fn finish(agent: &ureq::Agent, cfg: &Config, store: &StateStore, params: &Value, auth_lock: &Mutex<()>) -> Result<Value, CoreError> {
    if !params.is_object() {
        return Err(CoreError::invalid_params("params must be an object"));
    }
    let challenge_id = params
        .get("challenge_id")
        .and_then(Value::as_str)
        .filter(|c| !c.is_empty())
        .ok_or_else(|| CoreError::invalid_params("challenge_id is required and must be a non-empty string"))?;
    let raw_code = params
        .get("code")
        .and_then(Value::as_str)
        .ok_or_else(|| CoreError::invalid_params("code is required and must be a string"))?;
    // Not six digits: refused here, so a typo never burns one of the five guesses.
    let code = Zeroizing::new(clean_code(raw_code).ok_or_else(|| CoreError::new("invalid_code", "the code is not six digits"))?);
    let public = crate::auth::device_public(store)?;
    let public_b64 = URL_SAFE_NO_PAD.encode(public);
    let name = crate::auth::device_name(cfg);
    let body = Zeroizing::new(
        serde_json::to_vec(&EmailVerifyRequest {
            challenge_id,
            code: &code,
            device: LoginDevice { kind: "desktop", name: &name, platform: &cfg.platform, public_key: &public_b64 },
        })
        .map_err(|_| CoreError::new("io", "request body is not serializable"))?,
    );
    let resp: GoogleAuthResponse = http::send(agent, cfg, None, Method::Post, VERIFY_PATH, Some(&body), None)
        .and_then(|reply| http::parse_json(VERIFY_PATH, &reply))
        .map_err(|e| map_relay(VERIFY_PATH, e))?;
    if resp.token.is_empty() || resp.user_id.is_empty() || resp.device_id.is_empty() || resp.email.is_empty() {
        return Err(CoreError::new("server", "email sign-in response is missing token, user_id, device_id or email"));
    }
    {
        // Never held during a request.
        let _g = auth_lock.lock().unwrap_or_else(|p| p.into_inner());
        // Read under the lock: a sign-in that finished during the request must decide whether `machine.json` goes.
        let previous_user = crate::auth::load_session(store).ok().flatten().map(|s| s.user_id.clone());
        let session = SessionFile {
            token: resp.token.clone(),
            user_id: resp.user_id.clone(),
            device_id: resp.device_id.clone(),
            auth_method: Some("email".to_string()),
            email: Some(resp.email.clone()),
        };
        crate::auth::save_session(store, &session, previous_user.as_deref())?;
    }
    Ok(json!({
        "user_id": resp.user_id,
        "device_id": resp.device_id,
        "device_public_key_b64": public_b64,
        "fingerprint": fingerprint(&public),
        "email": resp.email,
        "auth_method": "email",
    }))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn locale_of_is_vi_only_for_a_vi_prefix() {
        assert_eq!(locale_of(Some("vi")), "vi");
        assert_eq!(locale_of(Some("Vi-VN")), "vi");
        for other in [Some("en"), Some("ja"), None] {
            assert_eq!(locale_of(other), "en");
        }
    }

    #[test]
    fn sendable_email_trims_and_refuses_what_the_relay_would() {
        assert_eq!(sendable_email("  a@b.cd "), Some("a@b.cd"));
        let max = format!("{}@b.cd", "a".repeat(MAX_EMAIL_BYTES - "@b.cd".len()));
        assert_eq!(max.len(), 254);
        assert_eq!(sendable_email(&max), Some(max.as_str()));
        let over = format!("{}@b.cd", "a".repeat(MAX_EMAIL_BYTES - "@b.cd".len() + 1));
        assert_eq!(over.len(), 255);
        for bad in ["", "   ", "phu@ẽample.com", over.as_str()] {
            assert_eq!(sendable_email(bad), None, "{bad:?}");
        }
    }

    #[test]
    fn decimal_digit_maps_unicode_decimal_digits() {
        assert_eq!(decimal_digit('7'), Some(7));
        assert_eq!(decimal_digit('\u{0663}'), Some(3));
        assert_eq!(decimal_digit('\u{06F5}'), Some(5));
        assert_eq!(decimal_digit('\u{096B}'), Some(5));
        assert_eq!(decimal_digit('\u{FF15}'), Some(5));
        for not in ['a', '½', '²', '四', 'Ⅳ'] {
            assert_eq!(decimal_digit(not), None, "{not}");
        }
        for &z in DECIMAL_ZEROS {
            for i in 0..10 {
                let c = char::from_u32(z + i).unwrap();
                assert!(c.is_numeric(), "U+{:04X}", z + i);
                assert_eq!(decimal_digit(c), Some(i), "U+{:04X}", z + i);
            }
        }
    }

    #[test]
    fn clean_code_keeps_six_digits_as_ascii() {
        for ok in ["123456", " 123 456\n", "１２３４５６", "١٢٣٤٥٦"] {
            assert_eq!(clean_code(ok).as_deref(), Some("123456"), "{ok:?}");
        }
        assert_eq!(clean_code("004217").as_deref(), Some("004217"));
        for bad in ["12345", "1234567", "12a456", "123-456", "四五六七八九"] {
            assert_eq!(clean_code(bad), None, "{bad:?}");
        }
    }
}
