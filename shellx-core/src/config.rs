//! `config.set` parameters and validation.

use crate::envelope::CoreError;
use serde_json::Value;
use std::path::PathBuf;

pub const GOOGLE_AUTH_URL: &str = "https://accounts.google.com/o/oauth2/v2/auth";
pub const GOOGLE_TOKEN_URL: &str = "https://oauth2.googleapis.com/token";

#[derive(Clone, PartialEq, Eq)]
pub struct Config {
    pub api_base: String,
    pub state_dir: PathBuf,
    pub app_version: String,
    pub os_version: String,
    pub platform: String,
    pub device_name: String,
    pub google_auth_url: String,
    pub google_token_url: String,
    pub google_client_id: String,
    pub google_client_secret: String,
}

/// Prints everything except the Google client secret.
impl std::fmt::Debug for Config {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("Config")
            .field("api_base", &self.api_base)
            .field("state_dir", &self.state_dir)
            .field("app_version", &self.app_version)
            .field("os_version", &self.os_version)
            .field("platform", &self.platform)
            .field("device_name", &self.device_name)
            .field("google_auth_url", &self.google_auth_url)
            .field("google_token_url", &self.google_token_url)
            .field("google_client_id", &self.google_client_id)
            .field("google_client_secret", &"<redacted>")
            .finish()
    }
}

/// Compiled default, then the process environment (same variable name).
fn google_client_default(compiled: Option<&'static str>, var: &str) -> String {
    std::env::var(var).ok().or_else(|| compiled.map(str::to_string)).unwrap_or_default()
}

fn opt_str(obj: &serde_json::Map<String, Value>, key: &str) -> Result<Option<String>, CoreError> {
    match obj.get(key) {
        None | Some(Value::Null) => Ok(None),
        Some(Value::String(s)) => Ok(Some(s.clone())),
        Some(_) => Err(CoreError::invalid_params(format!("{key} must be a string"))),
    }
}

/// `api_base` must be `https://host...`, or `http://` only for host 127.0.0.1 / localhost.
fn validate_api_base(raw: &str) -> Result<String, CoreError> {
    validate_url("api_base", raw)
}

fn validate_url(name: &str, raw: &str) -> Result<String, CoreError> {
    let bad = |m: &str| CoreError::invalid_params(format!("{name}: {m}"));
    let (secure, rest) = if let Some(r) = raw.strip_prefix("https://") {
        (true, r)
    } else if let Some(r) = raw.strip_prefix("http://") {
        (false, r)
    } else {
        return Err(bad("must start with https://"));
    };
    let authority = rest.split(['/', '?', '#']).next().unwrap_or("");
    if authority.is_empty() {
        return Err(bad("missing host"));
    }
    if authority.contains('@') || authority.contains(char::is_whitespace) || authority.contains('\\') {
        return Err(bad("invalid authority"));
    }
    let host = if authority.starts_with('[') {
        authority.split(']').next().unwrap_or("").trim_start_matches('[')
    } else {
        authority.split(':').next().unwrap_or("")
    };
    if host.is_empty() {
        return Err(bad("missing host"));
    }
    if !secure && host != "127.0.0.1" && host != "localhost" {
        return Err(bad("plain http is allowed only for 127.0.0.1 or localhost"));
    }
    Ok(raw.trim_end_matches('/').to_string())
}

impl Config {
    pub fn from_params(params: &Value) -> Result<Config, CoreError> {
        let obj = params
            .as_object()
            .ok_or_else(|| CoreError::invalid_params("params must be an object"))?;
        let api_base = opt_str(obj, "api_base")?
            .ok_or_else(|| CoreError::invalid_params("api_base is required"))?;
        let api_base = validate_api_base(&api_base)?;
        let state_dir = opt_str(obj, "state_dir")?
            .ok_or_else(|| CoreError::invalid_params("state_dir is required"))?;
        let state_dir = PathBuf::from(state_dir);
        if !state_dir.is_absolute() {
            return Err(CoreError::invalid_params("state_dir must be an absolute path"));
        }
        if !crate::store::root_path_ok(&state_dir) {
            return Err(CoreError::invalid_params(
                "state_dir must name a directory without a trailing slash, '.' or '..'",
            ));
        }
        let default_platform = if cfg!(target_os = "windows") { "windows" } else { "macos" };
        let platform = opt_str(obj, "platform")?.unwrap_or_else(|| default_platform.to_string());
        if platform != "macos" && platform != "windows" {
            return Err(CoreError::invalid_params("platform must be macos or windows"));
        }
        Ok(Config {
            api_base,
            state_dir,
            app_version: opt_str(obj, "app_version")?.unwrap_or_else(|| "2.0.0".to_string()),
            os_version: opt_str(obj, "os_version")?.unwrap_or_default(),
            platform,
            device_name: opt_str(obj, "device_name")?.unwrap_or_default(),
            google_auth_url: match opt_str(obj, "google_auth_url")? {
                Some(u) => validate_url("google_auth_url", &u)?,
                None => GOOGLE_AUTH_URL.to_string(),
            },
            google_token_url: match opt_str(obj, "google_token_url")? {
                Some(u) => validate_url("google_token_url", &u)?,
                None => GOOGLE_TOKEN_URL.to_string(),
            },
            google_client_id: opt_str(obj, "google_client_id")?.unwrap_or_else(|| {
                google_client_default(option_env!("SHELLX_GOOGLE_DESKTOP_CLIENT_ID"), "SHELLX_GOOGLE_DESKTOP_CLIENT_ID")
            }),
            google_client_secret: opt_str(obj, "google_client_secret")?.unwrap_or_else(|| {
                google_client_default(
                    option_env!("SHELLX_GOOGLE_DESKTOP_CLIENT_SECRET"),
                    "SHELLX_GOOGLE_DESKTOP_CLIENT_SECRET",
                )
            }),
        })
    }
}
