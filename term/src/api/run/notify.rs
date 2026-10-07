//! D23: `notify` and its OSC 777 fallbacks.

use super::targets::{canonical, pane};
use super::{print_json, usage, Api, Ctx, MAX_BODY, MAX_TITLE};
use crate::api::args::Parsed;
use crate::api::client::ApiError;
use crate::api::value::Value;
use std::io::Write;

pub(super) fn clean(s: &str) -> String {
    s.chars().filter(|c| !c.is_control()).collect()
}

pub(super) fn clip(s: &str, max: usize) -> String {
    s.chars().take(max).collect()
}

/// D23: pane → API; shared window without a pane → OSC 777 on the tty;
/// otherwise the API without a pane; API unreachable inside a ShellX pane →
/// OSC 777 on the tty. The text is never logged.
pub(super) fn notify(p: &Parsed, ctx: &mut Ctx) -> Result<(), ApiError> {
    let body = clip(&p.positionals.join(" "), MAX_BODY);
    if clean(&body).trim().is_empty() {
        return Err(usage("notify needs text"));
    }
    let title = p.flag("title").map(|t| clip(t, MAX_TITLE));
    let pane_id = match p.flag("pane") {
        Some(r) => pane(r, ctx)?.as_i64(),
        None => (ctx.env)("SHELLX_PANE_ID").and_then(|v| canonical(&v, false)),
    };
    let done = |ctx: &mut Ctx| {
        if p.json {
            print_json(ctx, &Value::Map(vec![]));
        }
    };
    if pane_id.is_none() && ctx.shared_terminal && ctx.tty.is_some() {
        osc(ctx, title.as_deref(), &body)?;
        done(ctx);
        return Ok(());
    }
    let attempt = Api::open(p, ctx).and_then(|mut api| {
        api.call(
            "cli.notify",
            vec![
                ("pane", pane_id.map(Value::Int)),
                ("title", title.clone().map(Value::text)),
                ("body", Some(Value::text(body.clone()))),
            ],
        )
    });
    match attempt {
        Ok(_) => {}
        Err(ApiError::NotRunning(_)) if pane_id.is_some() && ctx.tty.is_some() => {
            osc(ctx, title.as_deref(), &body)?
        }
        Err(e) => return Err(e),
    }
    done(ctx);
    Ok(())
}

pub(super) fn osc(ctx: &mut Ctx, title: Option<&str>, body: &str) -> Result<(), ApiError> {
    let t = clean(title.unwrap_or("")).replace(';', ",");
    let line = format!("\u{1b}]777;notify;{t};{}\u{7}", clean(body));
    let tty = ctx
        .tty
        .as_mut()
        .ok_or_else(|| ApiError::NotRunning("no terminal".into()))?;
    tty.write_all(line.as_bytes())
        .and_then(|_| tty.flush())
        .map_err(|e| ApiError::Io(e.to_string()))
}
