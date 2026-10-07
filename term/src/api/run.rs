//! Runs one parsed command (A7 §3.1). Everything outside the process is in
//! [Ctx], so tests use buffers and a scripted session. What can fail
//! locally (usage, targets, sizes) fails before connecting.

use super::args::Parsed;
use super::browser_js;
use super::client::{ApiError, Session};
use super::output;
use super::skills;
use super::value::{to_json, Value};
use super::wire::Message;
use std::io::{Read, Write};
use std::path::PathBuf;
use std::sync::{Arc, Mutex};

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
                let _ = writeln!(ctx.err, "shellx: {message} ({code})");
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

#[derive(Clone, Copy, PartialEq)]
enum Want {
    Pane,
    Tab,
    Any,
}

/// The host's canonical id forms (`^p(0|-?[1-9]\d{0,14})$`,
/// `^t([1-9]\d{0,14})$`): no sign but `-`, no leading zeros, no `-0`, at
/// most 15 digits. A tab id is positive.
fn canonical(s: &str, tab: bool) -> Option<i64> {
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

fn env_id(ctx: &Ctx, var: &str, what: &str, tab: bool) -> Result<i64, ApiError> {
    (ctx.env)(var)
        .and_then(|v| canonical(&v, tab))
        .ok_or_else(|| usage(format!("{what} needs {var} (run inside a ShellX pane)")))
}

const FORMS: &str = "p<id>, t<id>, @self, @tab, @focused";

/// D12: user text → (`pane` | `tab`, wire value). Ids go out as numbers;
/// `@focused` as is (the window resolves it).
fn target(raw: &str, want: Want, ctx: &Ctx) -> Result<(&'static str, Value), ApiError> {
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

fn pane(raw: &str, ctx: &Ctx) -> Result<Value, ApiError> {
    Ok(target(raw, Want::Pane, ctx)?.1)
}

fn tab(raw: &str, ctx: &Ctx) -> Result<Value, ApiError> {
    Ok(target(raw, Want::Tab, ctx)?.1)
}

fn text(s: Option<&str>) -> Option<Value> {
    s.map(Value::text)
}

fn flag(p: &Parsed, name: &str) -> Option<Value> {
    Some(Value::Bool(p.has(name)))
}

/// D14: a relative `--cwd` is taken from the CLI's directory.
fn abs_dir(d: Option<&str>, ctx: &Ctx) -> Option<Value> {
    d.map(|d| {
        let path = PathBuf::from(d);
        let full = if path.is_absolute() {
            path
        } else {
            ctx.cwd.join(path)
        };
        Value::text(full.to_string_lossy())
    })
}

fn cmd(p: &Parsed) -> Result<Option<Value>, ApiError> {
    match p.flag("cmd") {
        Some(c) if c.len() > MAX_CMD => Err(usage("--cmd is over 16 KiB")),
        c => Ok(text(c)),
    }
}

fn timeout_ms(p: &Parsed, max_s: f64) -> Result<Option<Value>, ApiError> {
    let Some(s) = p.flag("timeout") else {
        return Ok(None);
    };
    let secs: f64 = s.parse().map_err(|_| usage("--timeout takes seconds"))?;
    if !(secs > 0.0 && secs <= max_s) {
        return Err(usage(format!("--timeout is between 0 and {max_s} seconds")));
    }
    Ok(Some(Value::Int(((secs * 1000.0).round() as i64).max(1))))
}

fn int_flag(p: &Parsed, name: &str) -> Result<Option<Value>, ApiError> {
    p.flag(name)
        .map(|s| {
            s.parse::<i64>()
                .map(Value::Int)
                .map_err(|_| usage(format!("--{name} takes a number")))
        })
        .transpose()
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
                writeln!(ctx.out, "{}", to_json(&output::event_json(&e))).ok();
                ctx.out.flush().ok();
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
            let json = r.get("json").and_then(Value::as_str).unwrap_or("null");
            if print || p.json {
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
                let s = |k: &str| e.get(k).and_then(Value::as_str).unwrap_or("").to_string();
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
                let s = |k: &str| x.get(k).and_then(Value::as_str).unwrap_or("").to_string();
                writeln!(ctx.out, "p{id}  t{t}  {}  {}", s("title"), s("url")).ok();
            }
            Ok(())
        }
    }
}

type Fields = Vec<(&'static str, Option<Value>)>;

enum Prepared {
    Simple {
        t: &'static str,
        fields: Fields,
        id_key: Option<&'static str>,
        prefix: &'static str,
    },
    Ls,
    Read {
        pane: Value,
        lines: Option<Value>,
        ansi: bool,
    },
    Wait {
        fields: Fields,
        mode: &'static str,
    },
    Events {
        kinds: Option<Value>,
        seconds: Option<f64>,
    },
    Eval {
        pane: Value,
        script: String,
        print: bool,
    },
    Screenshot {
        pane: Value,
    },
    Entries {
        t: &'static str,
        fields: Fields,
    },
    BrowserList,
}

fn simple(t: &'static str, fields: Fields) -> Prepared {
    Prepared::Simple {
        t,
        fields,
        id_key: None,
        prefix: "",
    }
}

fn prepare(p: &Parsed, ctx: &mut Ctx, path: &str) -> Result<Prepared, ApiError> {
    let pos = |i: usize| p.pos(i).unwrap_or("");
    let rest = |i: usize| p.positionals[i.min(p.positionals.len())..].join(" ");
    Ok(match path {
        "ls" => Prepared::Ls,
        "new-tab" => Prepared::Simple {
            t: "ui.tab.new",
            fields: vec![
                ("workspace", text(p.flag("workspace"))),
                ("cwd", abs_dir(p.flag("cwd"), ctx)),
                ("cmd", cmd(p)?),
                ("focus", flag(p, "focus")),
            ],
            id_key: Some("tab"),
            prefix: "t",
        },
        "split" => {
            if p.has("right") && p.has("down") {
                return Err(usage("choose --right or --down"));
            }
            let target = match p.flag("pane") {
                Some(r) => pane(r, ctx)?,
                None if (ctx.env)("SHELLX_PANE_ID").is_some() => pane("@self", ctx)?,
                None => Value::text("@focused"),
            };
            Prepared::Simple {
                t: "ui.pane.split",
                fields: vec![
                    ("pane", Some(target)),
                    (
                        "direction",
                        Some(Value::text(if p.has("down") { "down" } else { "right" })),
                    ),
                    ("cwd", abs_dir(p.flag("cwd"), ctx)),
                    ("cmd", cmd(p)?),
                    ("focus", flag(p, "focus")),
                ],
                id_key: Some("pane"),
                prefix: "p",
            }
        }
        "focus" | "close" => {
            let (k, v) = target(pos(0), Want::Any, ctx)?;
            let (t, extra) = if path == "focus" {
                ("ui.focus", ("raise", flag(p, "raise")))
            } else {
                ("ui.close", ("force", flag(p, "force")))
            };
            simple(t, vec![(k, Some(v)), extra])
        }
        "send" => {
            let pane = pane(pos(0), ctx)?;
            let body = match (p.flag("text"), p.has("stdin")) {
                (Some(_), true) => return Err(usage("use --text or --stdin, not both")),
                (Some(t), false) => Some(t.to_string()),
                (None, true) => Some(read_all(ctx, MAX_TEXT)?),
                (None, false) => None,
            };
            if body.as_ref().is_some_and(|b| b.len() > MAX_TEXT) {
                return Err(usage("text is over 48 KiB"));
            }
            let keys: Vec<Value> = p.all("key").into_iter().map(Value::text).collect();
            if body.as_ref().is_none_or(|b| b.is_empty()) && keys.is_empty() && !p.has("enter") {
                return Err(usage("nothing to send: --text, --stdin, --key or --enter"));
            }
            simple(
                "ui.pane.send",
                vec![
                    ("pane", Some(pane)),
                    ("text", body.map(Value::text)),
                    ("keys", (!keys.is_empty()).then_some(Value::Array(keys))),
                    ("enter", flag(p, "enter")),
                ],
            )
        }
        "read" => {
            let lines = int_flag(p, "lines")?;
            if let Some(Value::Int(n)) = lines {
                if !(1..=10_000).contains(&n) {
                    return Err(usage("--lines is 1–10000"));
                }
            }
            Prepared::Read {
                pane: pane(pos(0), ctx)?,
                lines,
                ansi: p.has("ansi"),
            }
        }
        "rename" => simple(
            "ui.tab.rename",
            vec![
                ("tab", Some(tab(pos(0), ctx)?)),
                ("name", Some(Value::text(rest(1)))),
            ],
        ),
        "workspace new" => Prepared::Simple {
            t: "ui.workspace.new",
            fields: vec![
                (
                    "name",
                    (!p.positionals.is_empty()).then(|| Value::text(rest(0))),
                ),
                ("focus", flag(p, "focus")),
            ],
            id_key: Some("workspace"),
            prefix: "w:",
        },
        "workspace rename" => simple(
            "ui.workspace.rename",
            vec![
                ("workspace", Some(Value::text(pos(0)))),
                ("name", Some(Value::text(rest(1)))),
            ],
        ),
        "workspace move" => simple(
            "ui.workspace.move",
            vec![
                ("tab", Some(tab(pos(0), ctx)?)),
                ("workspace", Some(Value::text(pos(1)))),
            ],
        ),
        "wait" => {
            let modes: Vec<&'static str> = [
                ("idle", p.has("idle")),
                ("exit", p.has("exit")),
                ("match", p.flag("match").is_some()),
            ]
            .into_iter()
            .filter(|(_, on)| *on)
            .map(|(m, _)| m)
            .collect();
            let [mode] = modes[..] else {
                return Err(usage("choose exactly one of --idle, --exit, --match REGEX"));
            };
            if p.flag("match").is_some_and(|r| r.len() > MAX_PATTERN) {
                return Err(usage("--match is over 1 KiB"));
            }
            if p.has("from-now") && mode != "match" {
                return Err(usage("--from-now goes with --match"));
            }
            if p.has("quiet") && mode != "idle" {
                return Err(usage("--quiet goes with --idle"));
            }
            Prepared::Wait {
                fields: vec![
                    ("pane", Some(pane(pos(0), ctx)?)),
                    ("mode", Some(Value::text(mode))),
                    ("pattern", text(p.flag("match"))),
                    ("quietMs", int_flag(p, "quiet")?),
                    ("timeoutMs", timeout_ms(p, 3600.0)?),
                    ("fromNow", flag(p, "from-now")),
                ],
                mode,
            }
        }
        "events" => {
            let seconds = match p.flag("for") {
                None => None,
                Some(s) => match s.parse::<f64>() {
                    Ok(0.0) => None,
                    Ok(x) if x > 0.0 && x <= 86_400.0 => Some(x),
                    _ => return Err(usage("--for takes seconds (0–86400)")),
                },
            };
            Prepared::Events {
                kinds: p.flag("kinds").map(|k| {
                    Value::Array(
                        k.split(',')
                            .map(str::trim)
                            .filter(|s| !s.is_empty())
                            .map(Value::text)
                            .collect(),
                    )
                }),
                seconds,
            }
        }
        "browser ls" => Prepared::BrowserList,
        "browser open" => {
            let (k, v) = match (p.flag("tab"), p.flag("pane")) {
                (Some(_), Some(_)) => return Err(usage("use --tab or --pane, not both")),
                (Some(t), None) => ("tab", Some(tab(t, ctx)?)),
                (None, Some(x)) => ("target", Some(pane(x, ctx)?)),
                (None, None) => ("tab", None),
            };
            Prepared::Simple {
                t: "ui.browser.open",
                fields: vec![
                    ("url", Some(Value::text(pos(0)))),
                    (k, v),
                    (
                        "direction",
                        Some(Value::text(if p.has("down") { "down" } else { "right" })),
                    ),
                    ("focus", flag(p, "focus")),
                ],
                id_key: Some("pane"),
                prefix: "p",
            }
        }
        "browser nav" => simple(
            "ui.browser.navigate",
            vec![
                ("pane", Some(pane(pos(0), ctx)?)),
                ("url", Some(Value::text(pos(1)))),
                (
                    "wait",
                    Some(Value::text(if p.has("no-wait") { "none" } else { "load" })),
                ),
                ("timeoutMs", timeout_ms(p, 60.0)?),
            ],
        ),
        "browser back" | "browser forward" | "browser reload" | "browser stop"
        | "browser close" => {
            let t = match path {
                "browser back" => "ui.browser.back",
                "browser forward" => "ui.browser.forward",
                "browser reload" => "ui.browser.reload",
                "browser stop" => "ui.browser.stop",
                _ => "ui.browser.close",
            };
            simple(t, vec![("pane", Some(pane(pos(0), ctx)?))])
        }
        "browser wait" => simple(
            "ui.browser.wait",
            vec![
                ("pane", Some(pane(pos(0), ctx)?)),
                ("timeoutMs", timeout_ms(p, 60.0)?),
            ],
        ),
        "browser eval" => {
            let script = match (p.flag("script"), p.flag("file")) {
                (Some(s), None) => s.to_string(),
                (None, Some("-")) => read_all(ctx, MAX_SCRIPT)?,
                (None, Some(f)) => std::fs::read_to_string(ctx.cwd.join(f))
                    .map_err(|e| usage(format!("cannot read {f}: {}", e.kind())))?,
                _ => return Err(usage("give exactly one of --script or --file")),
            };
            if script.len() > MAX_SCRIPT {
                return Err(usage("the script is over 32 KiB"));
            }
            Prepared::Eval {
                pane: pane(pos(0), ctx)?,
                script,
                print: true,
            }
        }
        "browser query" => {
            let limit = match int_flag(p, "limit")? {
                Some(Value::Int(n)) if (1..=200).contains(&n) => n,
                Some(_) => return Err(usage("--limit is 1–200")),
                None => 50,
            };
            Prepared::Eval {
                pane: pane(pos(0), ctx)?,
                script: browser_js::query(pos(1), limit),
                print: true,
            }
        }
        "browser click" => Prepared::Eval {
            pane: pane(pos(0), ctx)?,
            script: browser_js::click(pos(1)),
            print: false,
        },
        "browser fill" => Prepared::Eval {
            pane: pane(pos(0), ctx)?,
            script: browser_js::fill(pos(1), &rest(2)),
            print: false,
        },
        "browser screenshot" => Prepared::Screenshot {
            pane: pane(pos(0), ctx)?,
        },
        "browser console" => Prepared::Entries {
            t: "ui.browser.console",
            fields: vec![
                ("pane", Some(pane(pos(0), ctx)?)),
                ("since", int_flag(p, "since")?),
                ("level", text(p.flag("level"))),
                ("limit", int_flag(p, "limit")?),
            ],
        },
        "browser network" => Prepared::Entries {
            t: "ui.browser.network",
            fields: vec![
                ("pane", Some(pane(pos(0), ctx)?)),
                ("since", int_flag(p, "since")?),
                ("limit", int_flag(p, "limit")?),
            ],
        },
        other => return Err(usage(format!("'{other}' is not a command to run"))),
    })
}

fn clean(s: &str) -> String {
    s.chars().filter(|c| !c.is_control()).collect()
}

fn clip(s: &str, max: usize) -> String {
    s.chars().take(max).collect()
}

/// D23: pane → API; shared window without a pane → OSC 777 on the tty;
/// otherwise the API without a pane; API unreachable inside a ShellX pane →
/// OSC 777 on the tty. The text is never logged.
fn notify(p: &Parsed, ctx: &mut Ctx) -> Result<(), ApiError> {
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

fn osc(ctx: &mut Ctx, title: Option<&str>, body: &str) -> Result<(), ApiError> {
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

#[cfg(test)]
mod tests {
    use super::*;
    use crate::api::args::{parse, Invocation};
    use std::cell::RefCell;
    use std::collections::VecDeque;
    use std::rc::Rc;

    type Log = Rc<RefCell<Vec<Message>>>;

    struct Fake {
        log: Log,
        caps: Vec<&'static str>,
        answers: VecDeque<(&'static str, Result<Message, ApiError>)>,
        events: VecDeque<Message>,
    }

    impl Session for Fake {
        fn request(&mut self, t: &str, fields: Vec<(&str, Value)>) -> Result<Message, ApiError> {
            self.log.borrow_mut().push(Message::new(t, fields));
            if t == "api.version" {
                let caps = self.caps.iter().map(|c| Value::text(*c)).collect();
                return Ok(Message::new(
                    "result",
                    vec![("api", Value::Int(1)), ("caps", Value::Array(caps))],
                ));
            }
            match self.answers.iter().position(|(n, _)| *n == t) {
                Some(i) => self.answers.remove(i).unwrap().1,
                None => Ok(Message::new("result", vec![])),
            }
        }
        fn next_event(&mut self) -> Result<Message, ApiError> {
            self.events
                .pop_front()
                .ok_or(ApiError::NotRunning("closed".into()))
        }
    }

    const ALL: &[&str] = &[
        "cli.notify",
        "cli.events.subscribe",
        "ui.ls",
        "ui.tab.new",
        "ui.tab.rename",
        "ui.pane.split",
        "ui.focus",
        "ui.close",
        "ui.pane.send",
        "ui.pane.read",
        "ui.pane.wait",
        "ui.workspace.new",
        "ui.workspace.rename",
        "ui.workspace.move",
        "ui.browser",
    ];

    struct Out {
        code: i32,
        out: String,
        err: String,
        log: Vec<Message>,
        tty: String,
        connected: bool,
    }

    fn ok(fields: Vec<(&str, Value)>) -> Result<Message, ApiError> {
        Ok(Message::new("result", fields))
    }
    fn remote(code: &str, message: &str) -> Result<Message, ApiError> {
        Err(ApiError::Remote {
            code: code.into(),
            message: message.into(),
        })
    }

    type Opts = (bool, bool, Option<ApiError>); // (has tty, shared terminal, connect error)

    fn go_caps(
        args: &[&str],
        env: &[(&str, &str)],
        answers: Vec<(&'static str, Result<Message, ApiError>)>,
        stdin: &str,
        opts: Opts,
        caps: &[&'static str],
    ) -> Out {
        let args: Vec<String> = args.iter().map(|s| s.to_string()).collect();
        let Ok(Invocation::Run(p)) = parse(&args) else {
            panic!("not a run")
        };
        let env: Vec<(String, String)> = env
            .iter()
            .map(|(k, v)| (k.to_string(), v.to_string()))
            .collect();
        let get = move |k: &str| env.iter().find(|(n, _)| n == k).map(|(_, v)| v.clone());
        let log: Log = Rc::new(RefCell::new(vec![]));
        let connected = Rc::new(RefCell::new(false));
        let answers = RefCell::new(Some(answers));
        let caps = caps.to_vec();
        let (log2, connected2, err) = (log.clone(), connected.clone(), opts.2.clone());
        let connect = move |_: Option<&str>| -> Result<Box<dyn Session>, ApiError> {
            *connected2.borrow_mut() = true;
            if let Some(e) = err.clone() {
                return Err(e);
            }
            Ok(Box::new(Fake {
                log: log2.clone(),
                caps: caps.clone(),
                answers: answers.borrow_mut().take().unwrap_or_default().into(),
                events: VecDeque::new(),
            }))
        };
        let (mut out, mut errb, mut tty) = (Vec::new(), Vec::new(), Vec::new());
        let mut input = stdin.as_bytes();
        let code = {
            let mut ctx = Ctx {
                env: &get,
                out: &mut out,
                err: &mut errb,
                stdin: &mut input,
                stdin_is_tty: false,
                cwd: PathBuf::from("/work"),
                home: Some(PathBuf::from("/Users/me")),
                tty: if opts.0 {
                    Some(&mut tty as &mut dyn Write)
                } else {
                    None
                },
                shared_terminal: opts.1,
                connect: &connect,
            };
            run(&p, &mut ctx)
        };
        let log = log.borrow().clone();
        let connected = *connected.borrow();
        Out {
            code,
            out: String::from_utf8(out).unwrap(),
            err: String::from_utf8(errb).unwrap(),
            log,
            tty: String::from_utf8(tty).unwrap(),
            connected,
        }
    }

    fn go(
        args: &[&str],
        env: &[(&str, &str)],
        answers: Vec<(&'static str, Result<Message, ApiError>)>,
        stdin: &str,
        opts: Opts,
    ) -> Out {
        go_caps(args, env, answers, stdin, opts, ALL)
    }

    const PLAIN: Opts = (false, false, None);

    fn sent<'a>(o: &'a Out, t: &str) -> &'a Message {
        o.log
            .iter()
            .find(|m| m.t == t)
            .unwrap_or_else(|| panic!("no {t} in {:?}", o.log))
    }

    #[test]
    fn split_defaults_to_self_and_prints_only_the_id() {
        let o = go(
            &["split", "--cmd", "npm run dev"],
            &[("SHELLX_PANE_ID", "100")],
            vec![(
                "ui.pane.split",
                ok(vec![("pane", Value::Int(102)), ("tab", Value::Int(100))]),
            )],
            "",
            PLAIN,
        );
        assert_eq!((o.code, o.out.as_str()), (0, "p102\n"));
        let m = sent(&o, "ui.pane.split");
        assert_eq!(m.get("pane"), Some(&Value::Int(100)));
        assert_eq!(m.get("direction"), Some(&Value::text("right")));
        assert_eq!(m.get("cmd"), Some(&Value::text("npm run dev")));
        assert_eq!(m.get("focus"), Some(&Value::Bool(false)));
        let outside = go(&["split", "--down"], &[], vec![], "", PLAIN);
        let m = sent(&outside, "ui.pane.split");
        assert_eq!(m.get("pane"), Some(&Value::text("@focused")));
        assert_eq!(m.get("direction"), Some(&Value::text("down")));
    }

    #[test]
    fn new_tab_absolutizes_cwd_and_json_uses_prefixed_ids() {
        let o = go(
            &["new-tab", "--cwd", "app", "--json"],
            &[],
            vec![(
                "ui.tab.new",
                ok(vec![("tab", Value::Int(101)), ("pane", Value::Int(101))]),
            )],
            "",
            PLAIN,
        );
        assert_eq!(
            sent(&o, "ui.tab.new").get("cwd"),
            Some(&Value::text("/work/app"))
        );
        assert_eq!(o.out, "{\"tab\":\"t101\",\"pane\":\"p101\"}\n");
        let w = go(
            &["workspace", "new", "Build box"],
            &[],
            vec![(
                "ui.workspace.new",
                ok(vec![
                    ("workspace", Value::text("ab12")),
                    ("tab", Value::Int(7)),
                ]),
            )],
            "",
            PLAIN,
        );
        assert_eq!(w.out, "w:ab12\n");
        assert_eq!(
            sent(&w, "ui.workspace.new").get("name"),
            Some(&Value::text("Build box"))
        );
    }

    #[test]
    fn send_refuses_oversize_stdin_before_connecting() {
        let big = "x".repeat(49_153);
        let o = go(&["send", "p1", "--stdin"], &[], vec![], &big, PLAIN);
        assert_eq!(o.code, 2);
        assert!(!o.connected);
        let t = go(&["send", "p1", "--text", &big], &[], vec![], "", PLAIN);
        assert_eq!((t.code, t.connected), (2, false));
        let k = go(
            &["send", "1", "--key", "ctrl-c", "--key", "up", "--enter"],
            &[],
            vec![],
            "",
            PLAIN,
        );
        let m = sent(&k, "ui.pane.send");
        assert_eq!(
            m.get("keys"),
            Some(&Value::Array(vec![
                Value::text("ctrl-c"),
                Value::text("up")
            ]))
        );
        assert_eq!(m.get("enter"), Some(&Value::Bool(true)));
        assert_eq!(go(&["send", "p1"], &[], vec![], "", PLAIN).code, 2);
    }

    #[test]
    fn read_follows_pages() {
        let o = go(
            &["read", "p1", "--lines", "500"],
            &[],
            vec![
                (
                    "ui.pane.read",
                    ok(vec![
                        ("text", Value::text("a\nb\n")),
                        ("next", Value::Int(2)),
                    ]),
                ),
                ("ui.pane.read", ok(vec![("text", Value::text("c\n"))])),
            ],
            "",
            PLAIN,
        );
        assert_eq!(o.out, "a\nb\nc\n");
        let reads: Vec<_> = o.log.iter().filter(|m| m.t == "ui.pane.read").collect();
        assert_eq!(reads[1].get("offset"), Some(&Value::Int(2)));
        assert_eq!(reads[0].get("lines"), Some(&Value::Int(500)));
        assert_eq!(reads[0].get("offset"), None);
        assert_eq!(
            go(&["read", "p1", "--lines", "10001"], &[], vec![], "", PLAIN).code,
            2
        );
        let j = go(
            &["read", "p1", "--json"],
            &[],
            vec![
                (
                    "ui.pane.read",
                    ok(vec![("text", Value::text("a\n")), ("next", Value::Int(1))]),
                ),
                (
                    "ui.pane.read",
                    ok(vec![("text", Value::text("b\n")), ("next", Value::Null)]),
                ),
            ],
            "",
            PLAIN,
        );
        assert_eq!(j.out, "{\"text\":\"a\\nb\\n\"}\n");
    }

    #[test]
    fn wait_modes_and_timeouts() {
        assert_eq!(go(&["wait", "p1"], &[], vec![], "", PLAIN).code, 2);
        assert_eq!(
            go(&["wait", "p1", "--idle", "--exit"], &[], vec![], "", PLAIN).code,
            2
        );
        let e = go(
            &["wait", "p1", "--exit"],
            &[],
            vec![("ui.pane.wait", ok(vec![("exitCode", Value::Int(3))]))],
            "",
            PLAIN,
        );
        assert_eq!((e.code, e.out.as_str()), (0, "3\n"));
        let m = go(
            &[
                "wait",
                "p1",
                "--match",
                "ready",
                "--timeout",
                "1.5",
                "--from-now",
            ],
            &[],
            vec![(
                "ui.pane.wait",
                ok(vec![
                    ("match", Value::text("ready")),
                    ("line", Value::text("ready in 4 ms")),
                ]),
            )],
            "",
            PLAIN,
        );
        assert_eq!(m.out, "ready in 4 ms\n");
        let w = sent(&m, "ui.pane.wait");
        assert_eq!(w.get("timeoutMs"), Some(&Value::Int(1500)));
        assert_eq!(w.get("fromNow"), Some(&Value::Bool(true)));
        assert_eq!(w.get("pattern"), Some(&Value::text("ready")));
        let t = go(
            &["wait", "p1", "--idle"],
            &[],
            vec![("ui.pane.wait", remote("timeout", "timed out"))],
            "",
            PLAIN,
        );
        assert_eq!(t.code, 5);
        assert_eq!(
            go(
                &["wait", "p1", "--idle", "--timeout", "3601"],
                &[],
                vec![],
                "",
                PLAIN
            )
            .code,
            2
        );
        assert_eq!(
            go(
                &["wait", "p1", "--idle", "--timeout", "nan"],
                &[],
                vec![],
                "",
                PLAIN
            )
            .code,
            2
        );
        let slow = go(
            &["wait", "p1", "--match", "(a+)+$"],
            &[],
            vec![("ui.pane.wait", remote("bad_request", "pattern is too slow"))],
            "",
            PLAIN,
        );
        assert_eq!(
            (slow.code, slow.err.as_str()),
            (2, "shellx: pattern is too slow (bad_request)\n")
        );
    }

    #[test]
    fn errors_human_and_json() {
        let h = go(
            &["read", "p1"],
            &[],
            vec![("ui.pane.read", remote("not_found", "no pane p1"))],
            "",
            PLAIN,
        );
        assert_eq!(h.code, 4);
        assert_eq!(h.err, "shellx: no pane p1 (not_found)\n");
        let j = go(
            &["read", "p1", "--json"],
            &[],
            vec![("ui.pane.read", remote("not_found", "no pane p1"))],
            "",
            PLAIN,
        );
        assert_eq!(
            j.out,
            "{\"error\":{\"code\":\"not_found\",\"message\":\"no pane p1\"}}\n"
        );
        assert_eq!(j.err, "");
        let n = go(
            &["ls"],
            &[],
            vec![],
            "",
            (
                false,
                false,
                Some(ApiError::NotRunning("ShellX is not running".into())),
            ),
        );
        assert_eq!(n.code, 3);
        let hint = "This terminal is not a ShellX shell. Allow it in the ShellX tray: Command line → Allow other terminals";
        let f = go(
            &["ls"],
            &[],
            vec![("ui.ls", remote("forbidden", hint))],
            "",
            PLAIN,
        );
        assert_eq!(f.code, 6);
        assert_eq!(f.err, format!("shellx: {hint} (forbidden)\n"));
        let c = go(
            &["close", "p1"],
            &[],
            vec![(
                "ui.close",
                remote("running_command", "a command is running; use --force"),
            )],
            "",
            PLAIN,
        );
        assert_eq!(c.code, 6);
    }

    #[test]
    fn missing_cap_is_incompatible() {
        // A host without ui.browser (A6 absent): no browser panes yet.
        let b = go_caps(&["browser", "ls"], &[], vec![], "", PLAIN, &["ui.ls"]);
        assert_eq!(b.code, 7);
        assert!(
            b.err
                .contains("no browser panes yet (update ShellX when available)"),
            "{}",
            b.err
        );
        // Any other missing cap: too old.
        let w = go_caps(
            &["wait", "p1", "--idle"],
            &[],
            vec![],
            "",
            PLAIN,
            &["ui.ls"],
        );
        assert_eq!(w.code, 7);
        assert!(
            w.err.contains("too old") && w.err.contains("update ShellX"),
            "{}",
            w.err
        );
        assert!(!w.log.iter().any(|m| m.t == "ui.pane.wait"));
    }

    #[test]
    fn targets() {
        assert_eq!(go(&["read", "@self"], &[], vec![], "", PLAIN).code, 2);
        let f = go(&["focus", "12"], &[], vec![], "", PLAIN);
        assert_eq!(sent(&f, "ui.focus").get("pane"), Some(&Value::Int(12)));
        let t = go(&["focus", "t5", "--raise"], &[], vec![], "", PLAIN);
        assert_eq!(sent(&t, "ui.focus").get("tab"), Some(&Value::Int(5)));
        assert_eq!(sent(&t, "ui.focus").get("raise"), Some(&Value::Bool(true)));
        let b = go(&["browser", "reload", "p-3"], &[], vec![], "", PLAIN);
        assert_eq!(
            sent(&b, "ui.browser.reload").get("pane"),
            Some(&Value::Int(-3))
        );
        let r = go(
            &["rename", "@tab", "build", "server"],
            &[("SHELLX_TAB_ID", "7")],
            vec![],
            "",
            PLAIN,
        );
        let m = sent(&r, "ui.tab.rename");
        assert_eq!(
            (m.get("tab"), m.get("name")),
            (Some(&Value::Int(7)), Some(&Value::text("build server")))
        );
        assert_eq!(
            go(&["send", "t5", "--text", "x"], &[], vec![], "", PLAIN).code,
            2
        );
        let s = go(
            &["close", "@self"],
            &[("SHELLX_PANE_ID", "9")],
            vec![],
            "",
            PLAIN,
        );
        assert_eq!(sent(&s, "ui.close").get("pane"), Some(&Value::Int(9)));
        let fo = go(&["focus", "@focused"], &[], vec![], "", PLAIN);
        assert_eq!(
            sent(&fo, "ui.focus").get("pane"),
            Some(&Value::text("@focused"))
        );
        let mv = go(&["workspace", "move", "12", "w:x"], &[], vec![], "", PLAIN);
        let m = sent(&mv, "ui.workspace.move");
        assert_eq!(
            (m.get("tab"), m.get("workspace")),
            (Some(&Value::Int(12)), Some(&Value::text("w:x")))
        );
    }

    #[test]
    fn only_canonical_ids_are_sent() {
        // The host accepts p0, p<n>, p-<n>, t<n> (no leading zeros, no -0,
        // at most 15 digits) and plain numbers: anything else is a usage
        // error before connecting.
        for bad in [
            "p007",
            "p-0",
            "p+5",
            "+5",
            "007",
            "t0",
            "t-1",
            "p1234567890123456",
            "p",
            "t",
            "px",
            "p 1",
            "-0",
        ] {
            let o = go(&["read", bad], &[], vec![], "", PLAIN);
            let f = go(&["focus", bad], &[], vec![], "", PLAIN);
            assert_eq!(
                (o.code, o.connected, f.code, f.connected),
                (2, false, 2, false),
                "{bad}"
            );
        }
        assert_eq!(go(&["rename", "-3", "x"], &[], vec![], "", PLAIN).code, 2);
        for (raw, id) in [
            ("p0", 0),
            ("0", 0),
            ("p-12", -12),
            ("p123456789012345", 123_456_789_012_345),
        ] {
            let o = go(&["read", raw], &[], vec![], "", PLAIN);
            assert_eq!(
                sent(&o, "ui.pane.read").get("pane"),
                Some(&Value::Int(id)),
                "{raw}"
            );
        }
        assert_eq!(
            go(
                &["read", "@self"],
                &[("SHELLX_PANE_ID", "x1")],
                vec![],
                "",
                PLAIN
            )
            .code,
            2
        );
    }

    #[test]
    fn notify_paths() {
        // (1) in a pane: the API with the pane.
        let a = go(
            &["notify", "Build", "xong"],
            &[("SHELLX_PANE_ID", "12")],
            vec![],
            "",
            PLAIN,
        );
        let m = sent(&a, "cli.notify");
        assert_eq!(
            (m.get("pane"), m.get("body")),
            (Some(&Value::Int(12)), Some(&Value::text("Build xong")))
        );
        // (2) a shared terminal without a pane: OSC 777 to the tty, no socket.
        let b = go(
            &["notify", "--title", "CI", "ok\u{7}\u{1b}x"],
            &[],
            vec![],
            "",
            (true, true, None),
        );
        assert!(!b.connected);
        assert_eq!(b.tty, "\u{1b}]777;notify;CI;okx\u{7}");
        // (3) elsewhere: the API without a pane.
        let e = go(&["notify", "done"], &[], vec![], "", (true, false, None));
        let m = sent(&e, "cli.notify");
        assert_eq!((m.get("pane"), e.tty.as_str()), (None, ""));
        // Not running, in a pane with a tty: OSC fallback, exit 0.
        let c = go(
            &["notify", "x"],
            &[("SHELLX_PANE_ID", "12")],
            vec![],
            "",
            (true, false, Some(ApiError::NotRunning("no".into()))),
        );
        assert_eq!((c.code, c.tty.as_str()), (0, "\u{1b}]777;notify;;x\u{7}"));
        // Not running, nowhere to fall back: exit 3.
        let d = go(
            &["notify", "x"],
            &[],
            vec![],
            "",
            (false, false, Some(ApiError::NotRunning("no".into()))),
        );
        assert_eq!(d.code, 3);
        // Blank text: usage.
        assert_eq!(go(&["notify", " "], &[], vec![], "", PLAIN).code, 2);
        // Long text is cut as the host cuts it (body 1024, title 128 characters).
        let long = "é".repeat(5000);
        let l = go(&["notify", "--title", &long, &long], &[], vec![], "", PLAIN);
        let m = sent(&l, "cli.notify");
        assert_eq!(
            m.get("body")
                .and_then(Value::as_str)
                .map(|s| s.chars().count()),
            Some(1024)
        );
        assert_eq!(
            m.get("title")
                .and_then(Value::as_str)
                .map(|s| s.chars().count()),
            Some(128)
        );
    }

    #[test]
    fn browser_eval_prints_raw_json_and_helpers_escape() {
        let e = go(
            &["browser", "eval", "p-1", "--script", "return {a: 1}"],
            &[],
            vec![(
                "ui.browser.eval",
                ok(vec![("json", Value::text("{\"a\":1}"))]),
            )],
            "",
            PLAIN,
        );
        assert_eq!(e.out, "{\"a\":1}\n");
        let f = go(
            &[
                "browser",
                "fill",
                "p-1",
                "input[name=\"q\"]",
                "it's",
                "\"x\"",
            ],
            &[],
            vec![],
            "",
            PLAIN,
        );
        let script = sent(&f, "ui.browser.eval")
            .get("script")
            .and_then(Value::as_str)
            .unwrap()
            .to_string();
        assert!(script.contains(r#""input[name=\"q\"]""#), "{script}");
        assert!(script.contains(r#""it's \"x\"""#), "{script}");
        let big = "x".repeat(32 * 1024 + 1);
        assert_eq!(
            go(
                &["browser", "eval", "p-1", "--script", &big],
                &[],
                vec![],
                "",
                PLAIN
            )
            .code,
            2
        );
    }

    fn tree(cwd: Value, branch: Value, exit: Value) -> Value {
        Value::Array(vec![Value::map(vec![
            ("id", Value::text("default")),
            ("name", Value::text("Default")),
            ("current", Value::Bool(true)),
            (
                "tabs",
                Value::Array(vec![Value::map(vec![
                    ("id", Value::Int(100)),
                    ("title", Value::text("build")),
                    ("selected", Value::Bool(true)),
                    ("unread", Value::Int(2)),
                    ("agent", Value::Bool(false)),
                    (
                        "panes",
                        Value::Array(vec![Value::map(vec![
                            ("id", Value::Int(100)),
                            ("kind", Value::text("terminal")),
                            ("title", Value::text("zsh")),
                            ("cwd", cwd),
                            ("branch", branch),
                            ("ports", Value::Array(vec![Value::Int(3000)])),
                            ("focused", Value::Bool(true)),
                            ("exitCode", exit),
                        ])]),
                    ),
                ])]),
            ),
        ])])
    }

    #[test]
    fn ls_human_and_ids() {
        let t = tree(
            Value::text("/Users/me/app"),
            Value::text("main"),
            Value::Null,
        );
        let o = go(
            &["ls"],
            &[],
            vec![("ui.ls", ok(vec![("workspaces", t.clone())]))],
            "",
            PLAIN,
        );
        assert!(
            o.out.contains("t100")
                && o.out.contains("p100")
                && o.out.contains("~/app")
                && o.out.contains("main")
                && o.out.contains(":3000")
                && o.out.contains("●2"),
            "{}",
            o.out
        );
        assert!(!o.out.contains("exited"), "{}", o.out);
        let ids = go(
            &["ls", "--ids"],
            &[],
            vec![("ui.ls", ok(vec![("workspaces", t)]))],
            "",
            PLAIN,
        );
        assert_eq!(ids.out, "t100\np100\n");
    }

    #[test]
    fn ls_accepts_null_optional_keys() {
        let t = tree(Value::Null, Value::Null, Value::Null);
        let fields = vec![
            ("workspaces", t),
            ("selectedTab", Value::Int(100)),
            ("focusedPane", Value::Null),
        ];
        let h = go(&["ls"], &[], vec![("ui.ls", ok(fields.clone()))], "", PLAIN);
        assert_eq!(h.code, 0);
        assert!(
            h.out.contains("p100") && !h.out.contains("null"),
            "{}",
            h.out
        );
        let j = go(
            &["ls", "--json"],
            &[],
            vec![("ui.ls", ok(fields))],
            "",
            PLAIN,
        );
        assert_eq!(j.code, 0);
        assert!(j.out.contains("\"id\":\"w:default\""), "{}", j.out);
        assert!(
            j.out.contains("\"id\":\"t100\"") && j.out.contains("\"id\":\"p100\""),
            "{}",
            j.out
        );
        assert!(
            j.out.contains("\"cwd\":null,\"branch\":null") && j.out.contains("\"exitCode\":null"),
            "{}",
            j.out
        );
        assert!(
            j.out
                .contains("\"selectedTab\":\"t100\",\"focusedPane\":null"),
            "{}",
            j.out
        );
        let e = go(
            &["ls"],
            &[],
            vec![(
                "ui.ls",
                ok(vec![(
                    "workspaces",
                    tree(Value::Null, Value::Null, Value::Int(-15)),
                )]),
            )],
            "",
            PLAIN,
        );
        assert!(e.out.contains("[exited -15]"), "{}", e.out);
    }

    #[test]
    fn events_print_json_lines_until_closed() {
        let args: Vec<String> = ["events", "--follow", "--kinds", "tab.opened,notice"]
            .iter()
            .map(|s| s.to_string())
            .collect();
        let Ok(Invocation::Run(p)) = parse(&args) else {
            panic!()
        };
        let log: Log = Rc::new(RefCell::new(vec![]));
        let l2 = log.clone();
        let connect = move |_: Option<&str>| -> Result<Box<dyn Session>, ApiError> {
            Ok(Box::new(Fake {
                log: l2.clone(),
                caps: ALL.to_vec(),
                answers: VecDeque::new(),
                events: VecDeque::from(vec![Message::new(
                    "event",
                    vec![
                        ("kind", Value::text("tab.opened")),
                        ("tab", Value::Int(5)),
                        ("workspace", Value::text("default")),
                    ],
                )]),
            }))
        };
        let get = |_: &str| None;
        let (mut out, mut err) = (Vec::new(), Vec::new());
        let mut input: &[u8] = b"";
        let mut ctx = Ctx {
            env: &get,
            out: &mut out,
            err: &mut err,
            stdin: &mut input,
            stdin_is_tty: false,
            cwd: PathBuf::from("/"),
            home: None,
            tty: None,
            shared_terminal: false,
            connect: &connect,
        };
        assert_eq!(run(&p, &mut ctx), 3); // ShellX closed the stream
        assert_eq!(
            String::from_utf8(out).unwrap(),
            "{\"kind\":\"tab.opened\",\"tab\":\"t5\",\"workspace\":\"w:default\"}\n"
        );
        let sub = log
            .borrow()
            .iter()
            .find(|m| m.t == "cli.events.subscribe")
            .unwrap()
            .clone();
        assert_eq!(
            sub.get("kinds"),
            Some(&Value::Array(vec![
                Value::text("tab.opened"),
                Value::text("notice")
            ]))
        );
        // Without --follow/--for: subscribe and exit 0.
        let once = go(&["events"], &[], vec![], "", PLAIN);
        assert_eq!((once.code, once.out.as_str()), (0, ""));
        assert_eq!(
            go(&["events", "--for", "x"], &[], vec![], "", PLAIN).code,
            2
        );
    }
}
