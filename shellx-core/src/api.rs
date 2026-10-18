//! Typed K1 request/response bodies and the on-disk session file.
//! Anything holding a token has a `Debug` that redacts it.

use serde::{Deserialize, Serialize};
use std::fmt;

/// `device` object of `POST /v1/auth/login`.
#[derive(Debug, Serialize)]
pub struct LoginDevice<'a> {
    pub kind: &'static str,
    pub name: &'a str,
    pub platform: &'a str,
    /// b64url (no padding) of the raw 32-byte X25519 public key.
    pub public_key: &'a str,
}

/// `POST /v1/auth/login` body. Not `Debug` (holds the password).
#[derive(Serialize)]
pub struct LoginRequest<'a> {
    pub email: &'a str,
    pub password: &'a str,
    pub device: LoginDevice<'a>,
}

/// `POST /v1/auth/login` 200 response.
#[derive(Deserialize)]
pub struct LoginResponse {
    pub user_id: String,
    pub device_id: String,
    pub token: String,
}

impl fmt::Debug for LoginResponse {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("LoginResponse")
            .field("user_id", &self.user_id)
            .field("device_id", &self.device_id)
            .field("token", &format_args!("<{} bytes>", self.token.len()))
            .finish()
    }
}

/// `session.json` in the state dir.
#[derive(Serialize, Deserialize)]
pub struct SessionFile {
    pub token: String,
    pub user_id: String,
    pub device_id: String,
}

impl fmt::Debug for SessionFile {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("SessionFile")
            .field("user_id", &self.user_id)
            .field("device_id", &self.device_id)
            .field("token", &format_args!("<{} bytes>", self.token.len()))
            .finish()
    }
}

/// `machine.json` in the state dir.
#[derive(Debug, Serialize, Deserialize)]
pub struct MachineFile {
    pub machine_id: String,
    pub slot: String,
}

/// `POST /v2/machines` body.
#[derive(Debug, Serialize)]
pub struct RegisterRequest<'a> {
    pub name: &'a str,
    pub platform: &'a str,
    pub os_version: &'a str,
    pub app_version: &'a str,
    pub noise_public_key_b64: &'a str,
}

/// `POST /v2/machines` 200 response.
#[derive(Debug, Deserialize)]
pub struct RegisterResponse {
    pub machine_id: String,
    pub slot: String,
}

/// One item of `GET /v2/machines`.
#[derive(Debug, Deserialize)]
pub struct MachineItem {
    pub machine_id: String,
    #[serde(default)]
    pub name: String,
    #[serde(default)]
    pub platform: String,
    #[serde(default)]
    pub online: bool,
    #[serde(default)]
    pub last_seen_unix: Option<u64>,
    #[serde(default)]
    pub noise_public_key_b64: Option<String>,
    #[serde(default)]
    pub fingerprint: Option<String>,
}

/// `GET /v2/machines` 200 response.
#[derive(Debug, Deserialize)]
pub struct ListResponse {
    pub machines: Vec<MachineItem>,
}

/// `POST /v2/relay/tickets` body.
#[derive(Debug, Serialize)]
pub struct MintRequest<'a> {
    pub machine_id: &'a str,
    pub permission: &'a str,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub target_machine_id: Option<&'a str>,
}

/// `POST /v2/relay/tickets` 200 response. `Debug` hides the ticket.
#[derive(Deserialize)]
pub struct MintResponse {
    pub ticket: String,
    pub expires_at_unix: u64,
    pub relay_url: String,
}

impl fmt::Debug for MintResponse {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("MintResponse")
            .field("ticket", &format_args!("<{} bytes>", self.ticket.len()))
            .field("expires_at_unix", &self.expires_at_unix)
            .field("relay_url", &self.relay_url)
            .finish()
    }
}

/// `latest_agent` of `GET /v1/version`.
#[derive(Debug, Default, Deserialize)]
pub struct LatestAgent {
    #[serde(default)]
    pub version: Option<String>,
    #[serde(default)]
    pub mac_url: Option<String>,
    #[serde(default)]
    pub win_url: Option<String>,
}

/// `GET /v1/version` 200 response (other fields ignored).
#[derive(Debug, Deserialize)]
pub struct VersionResponse {
    #[serde(default)]
    pub min_agent: Option<String>,
    #[serde(default)]
    pub latest_agent: Option<LatestAgent>,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn debug_redacts_tokens() {
        let s = SessionFile { token: "tok_SECRET".into(), user_id: "u".into(), device_id: "d".into() };
        assert!(!format!("{s:?}").contains("tok_SECRET"));
        let r: LoginResponse = serde_json::from_str(r#"{"user_id":"u","device_id":"d","token":"tok_SECRET"}"#).unwrap();
        assert!(!format!("{r:?}").contains("tok_SECRET"));
    }
}
