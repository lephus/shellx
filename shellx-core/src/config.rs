//! `config.set` parameters and validation.

use crate::envelope::CoreError;
use serde_json::Value;
use std::path::PathBuf;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Config {
    pub api_base: String,
    pub state_dir: PathBuf,
    pub app_version: String,
    pub os_version: String,
    pub platform: String,
    pub device_name: String,
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
    let bad = |m: &str| CoreError::invalid_params(format!("api_base: {m}"));
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
        })
    }
}
