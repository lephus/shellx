//! D12: what a command acts on, in the host's canonical forms.

use super::{usage, Ctx};
use crate::api::client::ApiError;
use crate::api::value::Value;

#[derive(Clone, Copy, PartialEq)]
pub(super) enum Want {
    Pane,
    Tab,
    Any,
}

/// The host's canonical id forms (`^p(0|-?[1-9]\d{0,14})$`,
/// `^t([1-9]\d{0,14})$`): no sign but `-`, no leading zeros, no `-0`, at
/// most 15 digits. A tab id is positive.
pub(super) fn canonical(s: &str, tab: bool) -> Option<i64> {
    let (negative, digits) = match s.strip_prefix('-') {
        Some(d) if !tab => (true, d),
        Some(_) => return None,
        None => (false, s),
    };
    if digits.is_empty() || digits.len() > 15 || !digits.bytes().all(|b| b.is_ascii_digit()) {
        return None;
    }
    if digits == "0" {
        return (!tab && !negative).then_some(0);
    }
    if digits.starts_with('0') {
        return None;
    }
    let n: i64 = digits.parse().ok()?;
    Some(if negative { -n } else { n })
}

pub(super) fn env_id(ctx: &Ctx, var: &str, what: &str, tab: bool) -> Result<i64, ApiError> {
    (ctx.env)(var)
        .and_then(|v| canonical(&v, tab))
        .ok_or_else(|| usage(format!("{what} needs {var} (run inside a ShellX pane)")))
}

pub(super) const FORMS: &str = "p<id>, t<id>, @self, @tab, @focused";

/// D12: user text → (`pane` | `tab`, wire value). Ids go out as numbers;
/// `@focused` as is (the window resolves it).
pub(super) fn target(raw: &str, want: Want, ctx: &Ctx) -> Result<(&'static str, Value), ApiError> {
    let not_target = || usage(format!("'{raw}' is not a target ({FORMS})"));
    let r = match raw {
        "@self" if want == Want::Tab => (
            "tab",
            Value::Int(env_id(ctx, "SHELLX_TAB_ID", "@self", true)?),
        ),
        "@self" => (
            "pane",
            Value::Int(env_id(ctx, "SHELLX_PANE_ID", "@self", false)?),
        ),
        "@tab" if want == Want::Pane => {
            return Err(usage("@tab names a tab; this command needs a pane"))
        }
        "@tab" => (
            "tab",
            Value::Int(env_id(ctx, "SHELLX_TAB_ID", "@tab", true)?),
        ),
        "@focused" => (
            if want == Want::Tab { "tab" } else { "pane" },
            Value::text("@focused"),
        ),
        s if s.starts_with('p') => {
            let id = canonical(&s[1..], false).ok_or_else(not_target)?;
            if want == Want::Tab {
                return Err(usage(format!(
                    "{s} is a pane; this command needs a tab (t<id>)"
                )));
            }
            ("pane", Value::Int(id))
        }
        s if s.starts_with('t') => {
            let id = canonical(&s[1..], true).ok_or_else(not_target)?;
            if want == Want::Pane {
                return Err(usage(format!(
                    "{s} is a tab; this command needs a pane (p<id>)"
                )));
            }
            ("tab", Value::Int(id))
        }
        // D12: a bare number is a pane, a tab for tab commands.
        s if want == Want::Tab => (
            "tab",
            Value::Int(canonical(s, true).ok_or_else(not_target)?),
        ),
        s => (
            "pane",
            Value::Int(canonical(s, false).ok_or_else(not_target)?),
        ),
    };
    Ok(r)
}

pub(super) fn pane(raw: &str, ctx: &Ctx) -> Result<Value, ApiError> {
    Ok(target(raw, Want::Pane, ctx)?.1)
}

pub(super) fn tab(raw: &str, ctx: &Ctx) -> Result<Value, ApiError> {
    Ok(target(raw, Want::Tab, ctx)?.1)
}
