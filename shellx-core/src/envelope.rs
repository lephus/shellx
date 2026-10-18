//! JSON envelope: success `{"ok": <value>}`, failure `{"error": {"code", "message"}}`.

use serde_json::{Value, json};
use std::fmt;

/// An error with a stable machine-readable `code` (see K3) and a human message.
/// The message must never contain secret values.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CoreError {
    pub code: String,
    pub message: String,
}

impl CoreError {
    pub fn new(code: &str, message: impl Into<String>) -> CoreError {
        CoreError { code: code.to_string(), message: message.into() }
    }
    pub fn invalid_params(message: impl Into<String>) -> CoreError {
        CoreError::new("invalid_params", message)
    }
}

impl fmt::Display for CoreError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}: {}", self.code, self.message)
    }
}

impl std::error::Error for CoreError {}

/// Serialize a call result into the envelope string.
pub fn to_envelope(result: Result<Value, CoreError>) -> String {
    let v = match result {
        Ok(value) => json!({ "ok": value }),
        Err(e) => json!({ "error": { "code": e.code, "message": e.message } }),
    };
    v.to_string()
}
