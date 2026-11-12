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
    /// "password" | "google" | "email"; absent in files written before Google sign-in (read as password).
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub auth_method: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub email: Option<String>,
}

impl fmt::Debug for SessionFile {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("SessionFile")
            .field("user_id", &self.user_id)
            .field("device_id", &self.device_id)
            .field("auth_method", &self.auth_method)
            .field("email", &self.email.as_ref().map(|_| "<redacted>"))
            .field("token", &format_args!("<{} bytes>", self.token.len()))
            .finish()
    }
}

/// `POST /v1/auth/nonce` 201 response. `Debug` hides the nonce.
#[derive(Deserialize)]
pub struct NonceResponse {
    pub nonce: String,
    #[serde(default)]
    pub expires_in: u64,
}

impl fmt::Debug for NonceResponse {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("NonceResponse").field("nonce", &"<redacted>").field("expires_in", &self.expires_in).finish()
    }
}

/// `POST /v1/auth/google` body. Not `Debug` (holds the id_token).
#[derive(Serialize)]
pub struct GoogleSignInRequest<'a> {
    pub id_token: &'a str,
    pub nonce: &'a str,
    pub device: LoginDevice<'a>,
}

/// `POST /v1/auth/google/link` body. Not `Debug`.
#[derive(Serialize)]
pub struct GoogleLinkRequest<'a> {
    pub id_token: &'a str,
    pub nonce: &'a str,
}

/// 200 response of `/v1/auth/google` and `/v1/auth/google/link`. `Debug` redacts token and email.
#[derive(Deserialize)]
pub struct GoogleAuthResponse {
    pub user_id: String,
    pub device_id: String,
    pub token: String,
    #[serde(default)]
    pub email: String,
}

impl fmt::Debug for GoogleAuthResponse {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("GoogleAuthResponse")
            .field("user_id", &self.user_id)
            .field("device_id", &self.device_id)
            .field("token", &format_args!("<{} bytes>", self.token.len()))
            .field("email", &"<redacted>")
            .finish()
    }
}

/// `POST /v1/auth/email/code` body. Not `Debug` (holds the address).
#[derive(Serialize)]
pub struct EmailCodeRequest<'a> {
    pub email: &'a str,
    pub locale: &'a str,
}

fn default_email_expires_in() -> u64 {
    600
}

fn default_email_resend_in() -> u64 {
    60
}

/// 202 of `/v1/auth/email/code`. `Debug` shows `expires_in` and `resend_in` only.
#[derive(Deserialize)]
pub struct EmailCodeResponse {
    pub challenge_id: String,
    #[serde(default = "default_email_expires_in")]
    pub expires_in: u64,
    #[serde(default = "default_email_resend_in")]
    pub resend_in: u64,
    #[serde(default)]
    pub email: String,
}

impl fmt::Debug for EmailCodeResponse {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("EmailCodeResponse").field("expires_in", &self.expires_in).field("resend_in", &self.resend_in).finish_non_exhaustive()
    }
}

/// `POST /v1/auth/email/verify` body. Not `Debug` (holds the code). Its 200 is `GoogleAuthResponse`.
#[derive(Serialize)]
pub struct EmailVerifyRequest<'a> {
    pub challenge_id: &'a str,
    pub code: &'a str,
    pub device: LoginDevice<'a>,
}

/// Google's token endpoint answer (other fields ignored). `Debug` redacts.
#[derive(Deserialize)]
pub struct GoogleTokenResponse {
    #[serde(default)]
    pub id_token: String,
}

impl fmt::Debug for GoogleTokenResponse {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("GoogleTokenResponse").field("id_token", &"<redacted>").finish()
    }
}

/// `machine.json` in the state dir.
#[derive(Debug, Serialize, Deserialize)]
pub struct MachineFile {
    pub machine_id: String,
    pub slot: String,
    /// ShellX Link relay slot. Absent in files written before it existed; `machines.register` refreshes it.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub link_slot: Option<String>,
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
    /// Missing from a relay that predates ShellX Link.
    #[serde(default)]
    pub link_slot: Option<String>,
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
    /// The relay's word that this machine accepts connections from other desktops (absent today). Only
    /// JSON `true` is true; absent, null or any other value is false and never fails the list. The relay's
    /// own `fingerprint` is not read at all (D1: the core computes it from the key), so its type cannot
    /// fail the list either.
    #[serde(default, deserialize_with = "true_only")]
    pub can_host: bool,
}

fn true_only<'de, D: serde::Deserializer<'de>>(d: D) -> Result<bool, D::Error> {
    Ok(matches!(serde_json::Value::deserialize(d)?, serde_json::Value::Bool(true)))
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
    /// `"link"` selects the machine's ShellX Link slot.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub lane: Option<&'a str>,
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
        let s = SessionFile { token: "tok_SECRET".into(), user_id: "u".into(), device_id: "d".into(), auth_method: None, email: None };
        assert!(!format!("{s:?}").contains("tok_SECRET"));
        let r: LoginResponse = serde_json::from_str(r#"{"user_id":"u","device_id":"d","token":"tok_SECRET"}"#).unwrap();
        assert!(!format!("{r:?}").contains("tok_SECRET"));
    }
}
