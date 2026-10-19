//! HTTP client for the ShellX API (K1).
//!
//! * `ureq` with rustls and the `ring` provider passed explicitly, server
//!   certificates checked by the OS verifier (`RootCerts::PlatformVerifier`).
//! * Connect timeout 10 s, global timeout 20 s (a caller may pass a shorter one).
//! * No redirects are followed (the API never redirects; a bearer must not
//!   travel to another URL). A 3xx is an `http_<status>` error.
//! * Every request carries `X-ShellX-Version`, `X-ShellX-Platform`,
//!   `X-ShellX-OS-Version` (omitted when unknown), `User-Agent:
//!   ShellX/<app_version> (<platform>)` and, when a session exists,
//!   `Authorization: Bearer <token>`.
//! * Errors: transport failure → `network`; non-2xx with `{"error":{"code"}}` →
//!   that code verbatim; other non-2xx → `http_<status>`; a 2xx body that does not
//!   parse → `server`. Messages never contain request or response bodies.
//! * Response bodies are read into `Zeroizing` buffers (the login reply holds the token).

use crate::config::Config;
use crate::envelope::CoreError;
use serde::de::DeserializeOwned;
use std::sync::Arc;
use std::time::Duration;
use ureq::Agent;
use ureq::config::AutoHeaderValue;
use ureq::tls::{RootCerts, TlsConfig, TlsProvider};
use zeroize::Zeroizing;

pub const CONNECT_TIMEOUT: Duration = Duration::from_secs(10);
pub const GLOBAL_TIMEOUT: Duration = Duration::from_secs(20);
/// Responses are tiny JSON documents.
const MAX_RESPONSE_BYTES: u64 = 1 << 20;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Method {
    Get,
    Post,
}

/// A finished HTTP exchange. `Debug` shows the status and body length only.
pub struct Reply {
    pub status: u16,
    pub body: Zeroizing<Vec<u8>>,
}

impl std::fmt::Debug for Reply {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("Reply").field("status", &self.status).field("body_len", &self.body.len()).finish()
    }
}

pub fn new_agent() -> Agent {
    let tls = TlsConfig::builder()
        .provider(TlsProvider::Rustls)
        .root_certs(RootCerts::PlatformVerifier)
        .unversioned_rustls_crypto_provider(Arc::new(rustls::crypto::ring::default_provider()))
        .build();
    Agent::config_builder()
        .tls_config(tls)
        .timeout_connect(Some(CONNECT_TIMEOUT))
        .timeout_global(Some(GLOBAL_TIMEOUT))
        .http_status_as_error(false)
        .max_redirects(0)
        // ureq reads ALL_PROXY/HTTPS_PROXY/HTTP_PROXY by default; no proxy support is
        // required, and a stray env proxy must not see the bearer or tickets.
        .proxy(None)
        .user_agent(AutoHeaderValue::None)
        .build()
        .new_agent()
}

pub fn user_agent(cfg: &Config) -> String {
    format!("ShellX/{} ({})", cfg.app_version, cfg.platform)
}

/// Send one request. `bearer` is the session token when logged in; `timeout`
/// overrides the global timeout (e.g. 2 s for the best-effort logout).
pub fn send(
    agent: &Agent,
    cfg: &Config,
    bearer: Option<&str>,
    method: Method,
    path: &str,
    json_body: Option<&[u8]>,
    timeout: Option<Duration>,
) -> Result<Reply, CoreError> {
    let url = format!("{}{}", cfg.api_base, path);
    let auth = bearer.map(|t| Zeroizing::new(format!("Bearer {t}")));
    macro_rules! common {
        ($rb:expr) => {{
            let mut rb = $rb
                .header("X-ShellX-Version", cfg.app_version.as_str())
                .header("X-ShellX-Platform", cfg.platform.as_str())
                .header("User-Agent", user_agent(cfg));
            if !cfg.os_version.is_empty() {
                rb = rb.header("X-ShellX-OS-Version", cfg.os_version.as_str());
            }
            if let Some(a) = &auth {
                rb = rb.header("Authorization", a.as_str());
            }
            if let Some(t) = timeout {
                rb = rb.config().timeout_global(Some(t)).build();
            }
            rb
        }};
    }
    let result = match method {
        Method::Get => common!(agent.get(&url)).call(),
        Method::Post => {
            let rb = common!(agent.post(&url)).header("Content-Type", "application/json");
            rb.send(json_body.unwrap_or(b"{}"))
        }
    };
    let mut resp = result.map_err(|e| transport_error(path, &e))?;
    let status = resp.status().as_u16();
    let body = resp
        .body_mut()
        .with_config()
        .limit(MAX_RESPONSE_BYTES)
        .read_to_vec()
        .map(Zeroizing::new)
        .map_err(|e| transport_error(path, &e))?;
    Ok(Reply { status, body })
}

/// The ureq error's Display may name the URL (no secrets in our URLs) but never bodies.
fn transport_error(path: &str, e: &ureq::Error) -> CoreError {
    CoreError::new("network", format!("{path}: {e}"))
}

/// Server error codes are passed through only if they look like codes.
fn plausible_code(code: &str) -> bool {
    !code.is_empty()
        && code.len() <= 64
        && code.bytes().all(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || c == b'_')
}

/// Map a non-2xx reply to its `CoreError`; `Ok(())` for 2xx.
pub fn check_status(path: &str, reply: &Reply) -> Result<(), CoreError> {
    if (200..300).contains(&reply.status) {
        return Ok(());
    }
    let parsed: Option<serde_json::Value> = serde_json::from_slice(&reply.body).ok();
    let code = parsed
        .as_ref()
        .and_then(|v| v.get("error")?.get("code")?.as_str())
        .filter(|c| plausible_code(c));
    Err(match code {
        Some(c) => CoreError::new(c, format!("{path}: server answered {} {c}", reply.status)),
        None => {
            let code = format!("http_{}", reply.status);
            CoreError::new(&code, format!("{path}: server answered {}", reply.status))
        }
    })
}

/// 2xx → parse the JSON body as `T`, else the mapped error.
pub fn parse_json<T: DeserializeOwned>(path: &str, reply: &Reply) -> Result<T, CoreError> {
    check_status(path, reply)?;
    serde_json::from_slice(&reply.body)
        .map_err(|_| CoreError::new("server", format!("{path}: unexpected response body ({} bytes)", reply.body.len())))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn reply(status: u16, body: &str) -> Reply {
        Reply { status, body: Zeroizing::new(body.as_bytes().to_vec()) }
    }

    #[test]
    fn maps_server_codes_and_statuses() {
        assert!(check_status("/p", &reply(204, "")).is_ok());
        let e = check_status("/p", &reply(401, r#"{"error":{"code":"invalid_credentials","message":"x"}}"#)).unwrap_err();
        assert_eq!(e.code, "invalid_credentials");
        assert_eq!(check_status("/p", &reply(502, "<html>bad gateway</html>")).unwrap_err().code, "http_502");
        assert_eq!(check_status("/p", &reply(302, "")).unwrap_err().code, "http_302");
        // Implausible codes are not passed through.
        let e = check_status("/p", &reply(400, r#"{"error":{"code":"Bad Code\n"}}"#)).unwrap_err();
        assert_eq!(e.code, "http_400");
        assert_eq!(check_status("/p", &reply(400, r#"{"error":{"code":""}}"#)).unwrap_err().code, "http_400");
    }

    #[test]
    fn error_messages_and_debug_never_carry_bodies() {
        let secret = "tok_SECRET_VALUE";
        let body = format!(r#"{{"error":{{"code":"forbidden","message":"{secret}"}}}}"#);
        let r = reply(403, &body);
        assert!(!format!("{r:?}").contains(secret));
        assert!(!check_status("/p", &r).unwrap_err().message.contains(secret));
        let ok = reply(200, &format!(r#"{{"token":"{secret}""#));
        let e = parse_json::<serde_json::Value>("/p", &ok).unwrap_err();
        assert_eq!(e.code, "server");
        assert!(!e.message.contains(secret));
    }

    #[test]
    fn user_agent_names_version_and_platform() {
        let cfg = Config::from_params(&serde_json::json!({
            "api_base": "https://a.b", "state_dir": "/tmp/sx", "app_version": "2.3.4", "platform": "windows"
        }))
        .unwrap();
        assert_eq!(user_agent(&cfg), "ShellX/2.3.4 (windows)");
    }
}
