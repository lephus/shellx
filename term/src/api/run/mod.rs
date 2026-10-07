//! Runs one parsed command (A7 §3.1). Everything outside the process is in
//! [Ctx], so tests use buffers and a scripted session. What can fail
//! locally (usage, targets, sizes) fails before connecting.

use super::args::Parsed;
use super::client::{ApiError, Session};
use super::output;
use super::skills;
use super::value::{to_json, Value};
use super::wire::Message;
use std::io::{Read, Write};
use std::path::PathBuf;
use std::sync::{Arc, Mutex};

mod notify;
mod prepare;
mod targets;
#[cfg(test)]
mod tests;

use notify::notify;
use prepare::{prepare, timeout_ms, Prepared};

/// Connects and authenticates; the argument is `--socket`.
pub type Connect<'a> = dyn Fn(Option<&str>) -> Result<Box<dyn Session>, ApiError> + 'a;

pub struct Ctx<'a> {
    pub env: &'a dyn Fn(&str) -> Option<String>,
    pub out: &'a mut dyn Write,
    pub err: &'a mut dyn Write,
    pub stdin: &'a mut dyn Read,
    pub stdin_is_tty: bool,
    pub cwd: PathBuf,
    pub home: Option<PathBuf>,
    /// The controlling terminal (`/dev/tty`, `CONOUT$`), for OSC 777.
    pub tty: Option<&'a mut dyn Write>,
    /// D23 (2): this terminal window is shared with the phone.
    pub shared_terminal: bool,
    /// Connects and authenticates; the argument is `--socket`.
    pub connect: &'a Connect<'a>,
}

/// D32: a text field of a request.
const MAX_TEXT: usize = 49_152;
/// D16: `--cmd`.
const MAX_CMD: usize = 16_384;
/// D21: `wait --match`.
const MAX_PATTERN: usize = 1024;
/// A6: `browser eval`.
const MAX_SCRIPT: usize = 32 * 1024;
/// D23: what the host keeps of a notification (characters).
const MAX_BODY: usize = 1024;
const MAX_TITLE: usize = 128;

const NO_BROWSER: &str = "this ShellX has no browser panes yet (update ShellX when available)";

fn usage(m: impl Into<String>) -> ApiError {
    ApiError::Usage(m.into())
}

/// Runs `p`; returns the exit code (D10). Errors go to stderr as
/// `shellx: <message> (<code>)`, or with `--json` to stdout as
/// `{"error":{"code","message"}}` (D11).
pub fn run(p: &Parsed, ctx: &mut Ctx) -> i32 {
    match execute(p, ctx) {
        Ok(()) => 0,
        Err(e) => {
            let (code, message) = describe(&e);
            if p.json {
                let v = Value::map(vec![(
                    "error",
                    Value::map(vec![
                        ("code", Value::text(code)),
                        ("message", Value::text(message)),
                    ]),
                )]);
                let _ = writeln!(ctx.out, "{}", to_json(&v));
            } else {
                let message = output::plain(&message);
                let _ = writeln!(ctx.err, "shellx: {message} ({})", output::plain(&code));
            }
            e.exit_code()
        }
    }
}

fn describe(e: &ApiError) -> (String, String) {
    match e {
        ApiError::NotRunning(m) => ("not_running".into(), m.clone()),
        ApiError::Incompatible(m) => ("incompatible".into(), m.clone()),
        ApiError::Usage(m) => ("usage".into(), m.clone()),
        ApiError::Io(m) => ("io".into(), m.clone()),
        ApiError::Remote { code, message } => (
            code.clone(),
            if message.is_empty() {
                code.replace('_', " ")
            } else {
                message.clone()
            },
        ),
    }
}

/// A connection that asked `api.version` (D4).
struct Api {
    s: Box<dyn Session>,
    caps: Vec<String>,
}

impl Api {
    fn open(p: &Parsed, ctx: &mut Ctx) -> Result<Api, ApiError> {
        let mut s = (ctx.connect)(p.socket.as_deref())?;
        let v = s.request("api.version", vec![])?;
        if v.get("api").and_then(Value::as_i64) != Some(1) {
            return Err(ApiError::Incompatible(
                "ShellX speaks another command-line API: update shellx or ShellX".into(),
            ));
        }
        let caps = v
            .get("caps")
            .and_then(Value::as_array)
            .map(|a| {
                a.iter()
                    .filter_map(|x| x.as_str().map(String::from))
                    .collect()
            })
            .unwrap_or_default();
        Ok(Api { s, caps })
    }

    /// Sends only what the host serves (D4: a missing cap → exit 7). Fields
    /// that are `None` are left out.
    fn call(&mut self, t: &str, fields: Vec<(&str, Option<Value>)>) -> Result<Message, ApiError> {
        let cap = if t.starts_with("ui.browser.") {
            "ui.browser"
        } else {
            t
        };
        if !self.caps.iter().any(|c| c == cap) {
            return Err(ApiError::Incompatible(if cap == "ui.browser" {
                NO_BROWSER.into()
            } else {
                format!("this ShellX is too old for '{t}': update ShellX")
            }));
        }
        self.s.request(
            t,
            fields
                .into_iter()
                .filter_map(|(k, v)| v.map(|v| (k, v)))
                .collect(),
        )
    }
}

fn print_json(ctx: &mut Ctx, v: &Value) {
    writeln!(ctx.out, "{}", to_json(v)).ok();
}

/// D11: creating commands print only the new id.
fn print_result(p: &Parsed, ctx: &mut Ctx, r: &Message, id_key: &str, prefix: &str) {
    if p.json {
        print_json(ctx, &output::result_json(r));
    } else {
        match r.get(id_key) {
            Some(Value::Int(n)) => writeln!(ctx.out, "{prefix}{n}").ok(),
            Some(Value::Text(s)) => writeln!(ctx.out, "{prefix}{s}").ok(),
            _ => None,
        };
    }
}

/// D11: other commands are silent on success (`--json`: the result).
fn quiet(p: &Parsed, ctx: &mut Ctx, r: &Message) {
    if p.json {
        print_json(ctx, &output::result_json(r));
    }
}

fn read_all(ctx: &mut Ctx, max: usize) -> Result<String, ApiError> {
    let mut buf = Vec::new();
    (&mut *ctx.stdin)
        .take(max as u64 + 1)
        .read_to_end(&mut buf)
        .map_err(|e| ApiError::Io(e.to_string()))?;
    if buf.len() > max {
        return Err(usage(format!("input is over {} KiB", max / 1024)));
    }
    String::from_utf8(buf).map_err(|_| usage("input is not UTF-8"))
}

fn execute(p: &Parsed, ctx: &mut Ctx) -> Result<(), ApiError> {
    let path = p.spec.path.join(" ");
    match path.as_str() {
        "skills install" => return skills::install(p, ctx),
        "skills print" => return skills::print(p, ctx),
        "notify" => return notify(p, ctx),
        _ => {}
    }
    let prepared = prepare(p, ctx, &path)?;
    let mut api = Api::open(p, ctx)?;
    match prepared {
        Prepared::Simple {
            t,
            fields,
            id_key,
            prefix,
        } => {
            let r = api.call(t, fields)?;
            match id_key {
                Some(k) => print_result(p, ctx, &r, k, prefix),
                None => quiet(p, ctx, &r),
            }
            Ok(())
        }
        Prepared::Ls => {
            let r = api.call("ui.ls", vec![])?;
            if p.json {
                print_json(ctx, &output::ls_json(&r));
            } else if p.has("ids") {
                write!(ctx.out, "{}", output::ls_ids(&r)).ok();
            } else {
                let home = ctx.home.clone();
                write!(ctx.out, "{}", output::ls_human(&r, home.as_deref())).ok();
            }
            Ok(())
        }
        Prepared::Read { pane, lines, ansi } => {
            // D20: pages of ≤ 48 KiB chained by `next`.
            let mut offset = 0i64;
            let mut all = String::new();
            loop {
                let r = api.call(
                    "ui.pane.read",
                    vec![
                        ("pane", Some(pane.clone())),
                        ("lines", lines.clone()),
                        ("ansi", Some(Value::Bool(ansi))),
                        ("offset", (offset > 0).then_some(Value::Int(offset))),
                    ],
                )?;
                let page = r.get("text").and_then(Value::as_str).unwrap_or("");
                if p.json {
                    all.push_str(page);
                } else {
                    write!(ctx.out, "{page}").ok();
                }
                match r.get("next").and_then(Value::as_i64) {
                    // A next page that does not move on would loop forever.
                    Some(n) if n > offset => offset = n,
                    _ => break,
                }
            }
            if p.json {
                print_json(ctx, &Value::map(vec![("text", Value::text(all))]));
            }
            Ok(())
        }
        Prepared::Wait { fields, mode } => {
            let r = api.call("ui.pane.wait", fields)?;
            if p.json {
                print_json(ctx, &output::result_json(&r));
            } else if mode == "exit" {
                let code = r
                    .get("exitCode")
                    .and_then(Value::as_i64)
                    .map(|c| c.to_string())
                    .unwrap_or_else(|| "null".into());
                writeln!(ctx.out, "{code}").ok();
            } else if mode == "match" {
                let line = r.get("line").and_then(Value::as_str).unwrap_or("");
                writeln!(ctx.out, "{line}").ok();
            }
            Ok(())
        }
        Prepared::Events { kinds, seconds } => {
            api.call("cli.events.subscribe", vec![("kinds", kinds)])?;
            // A whole line is written and flushed under this lock; the
            // `--for` timer takes it before exiting, so no line is cut.
            let writing = Arc::new(Mutex::new(()));
            match seconds {
                Some(secs) => {
                    let w = writing.clone();
                    std::thread::spawn(move || {
                        std::thread::sleep(std::time::Duration::from_secs_f64(secs));
                        let _held = w.lock();
                        std::process::exit(0);
                    });
                }
                None if !p.has("follow") => return Ok(()),
                None => {}
            }
            loop {
                let e = api.s.next_event()?;
                let _held = writing.lock();
                let line = format!("{}\n", to_json(&output::event_json(&e)));
                // Review I1: nobody reads any more (`| head -1`: Rust
                // ignores SIGPIPE, so this is EPIPE) — stop; returning
                // drops the connection, which frees the host's listener.
                match ctx
                    .out
                    .write_all(line.as_bytes())
                    .and_then(|()| ctx.out.flush())
                {
                    Ok(()) => {}
                    Err(e) if e.kind() == std::io::ErrorKind::BrokenPipe => return Ok(()),
                    Err(e) => return Err(ApiError::Io(format!("cannot write events: {e}"))),
                }
            }
        }
        Prepared::Eval {
            pane,
            script,
            print,
        } => {
            let r = api.call(
                "ui.browser.eval",
                vec![
                    ("pane", Some(pane)),
                    ("script", Some(Value::text(script))),
                    ("timeoutMs", timeout_ms(p, 30.0)?),
                ],
            )?;
            // The page's JSON, as the host produced it (A6: JSON.stringify).
            let json = r.get("json").and_then(Value::as_str).unwrap_or("null");
            if p.json {
                writeln!(ctx.out, "{{\"json\":{json}}}").ok();
            } else if print {
                writeln!(ctx.out, "{json}").ok();
            }
            Ok(())
        }
        Prepared::Screenshot { pane } => {
            let r = api.call("ui.browser.screenshot", vec![("pane", Some(pane))])?;
            let from = r
                .get("path")
                .and_then(Value::as_str)
                .unwrap_or("")
                .to_string();
            let shown = match p.flag("out") {
                Some(out) => {
                    let dest = ctx.cwd.join(out);
                    std::fs::copy(&from, &dest).map_err(|e| ApiError::Io(e.to_string()))?;
                    dest.to_string_lossy().into_owned()
                }
                None => from,
            };
            if p.json {
                let mut v = output::result_json(&r);
                if let Value::Map(m) = &mut v {
                    m.retain(|(k, _)| k != "path");
                    m.push(("path".into(), Value::text(shown)));
                }
                print_json(ctx, &v);
            } else {
                writeln!(ctx.out, "{shown}").ok();
            }
            Ok(())
        }
        Prepared::Entries { t, fields } => {
            let r = api.call(t, fields)?;
            if p.json {
                print_json(ctx, &output::result_json(&r));
                return Ok(());
            }
            for e in r.get("entries").and_then(Value::as_array).unwrap_or(&[]) {
                let seq = e.get("seq").and_then(Value::as_i64).unwrap_or(0);
                let s = |k: &str| output::plain(e.get(k).and_then(Value::as_str).unwrap_or(""));
                if t == "ui.browser.console" {
                    writeln!(ctx.out, "{seq}  {:<5}  {}", s("level"), s("text")).ok();
                } else {
                    let status = e
                        .get("status")
                        .and_then(Value::as_i64)
                        .map(|s| s.to_string())
                        .unwrap_or_default();
                    writeln!(
                        ctx.out,
                        "{seq}  {:<6} {status:<3}  {}",
                        s("method"),
                        s("url")
                    )
                    .ok();
                }
            }
            Ok(())
        }
        Prepared::BrowserList => {
            let r = api.call("ui.browser.list", vec![])?;
            if p.json {
                print_json(ctx, &output::result_json(&r));
                return Ok(());
            }
            for x in r.get("panes").and_then(Value::as_array).unwrap_or(&[]) {
                let id = x.get("pane").and_then(Value::as_i64).unwrap_or(0);
                let t = x.get("tab").and_then(Value::as_i64).unwrap_or(0);
                let s = |k: &str| output::plain(x.get(k).and_then(Value::as_str).unwrap_or(""));
                writeln!(ctx.out, "p{id}  t{t}  {}  {}", s("title"), s("url")).ok();
            }
            Ok(())
        }
    }
}
