//! Turns a parsed command into its request; everything that can fail
//! locally fails here, before connecting.

use super::targets::{canonical, pane, tab, target, Want};
use super::{read_all, usage, Ctx, MAX_CMD, MAX_PATTERN, MAX_SCRIPT, MAX_TEXT};
use crate::api::args::Parsed;
use crate::api::browser_js;
use crate::api::client::ApiError;
use crate::api::value::Value;
use std::path::PathBuf;

pub(super) fn text(s: Option<&str>) -> Option<Value> {
    s.map(Value::text)
}

pub(super) fn flag(p: &Parsed, name: &str) -> Option<Value> {
    Some(Value::Bool(p.has(name)))
}

/// D14: a relative `--cwd` is taken from the CLI's directory.
/// A11 D26: where the caller lives. Without `--workspace`, a command run
/// inside a ShellX pane sends that pane (`fromPane`, from
/// `SHELLX_PANE_ID`) and its original tab (`fromTab`); the window looks the
/// pane up *now* (a pane may have moved to another tab), then the tab, then
/// falls back to its current workspace. Ids that are not canonical are
/// dropped, never forwarded.
pub(super) fn caller(p: &Parsed, ctx: &Ctx) -> Fields {
    if p.flag("workspace").is_some() {
        return vec![];
    }
    let id = |var: &str, tab: bool| {
        (ctx.env)(var)
            .and_then(|v| canonical(&v, tab))
            .map(Value::Int)
    };
    vec![
        ("fromPane", id("SHELLX_PANE_ID", false)),
        ("fromTab", id("SHELLX_TAB_ID", true)),
    ]
}

pub(super) fn abs_dir(d: Option<&str>, ctx: &Ctx) -> Option<Value> {
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

pub(super) fn cmd(p: &Parsed) -> Result<Option<Value>, ApiError> {
    match p.flag("cmd") {
        Some(c) if c.len() > MAX_CMD => Err(usage("--cmd is over 16 KiB")),
        c => Ok(text(c)),
    }
}

pub(super) fn timeout_ms(p: &Parsed, max_s: f64) -> Result<Option<Value>, ApiError> {
    let Some(s) = p.flag("timeout") else {
        return Ok(None);
    };
    let secs: f64 = s.parse().map_err(|_| usage("--timeout takes seconds"))?;
    if !(secs > 0.0 && secs <= max_s) {
        return Err(usage(format!("--timeout is between 0 and {max_s} seconds")));
    }
    Ok(Some(Value::Int(((secs * 1000.0).round() as i64).max(1))))
}

pub(super) fn int_flag(p: &Parsed, name: &str) -> Result<Option<Value>, ApiError> {
    p.flag(name)
        .map(|s| {
            s.parse::<i64>()
                .map(Value::Int)
                .map_err(|_| usage(format!("--{name} takes a number")))
        })
        .transpose()
}

pub(super) type Fields = Vec<(&'static str, Option<Value>)>;

pub(super) enum Prepared {
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
    TmuxList {
        host: Option<Value>,
    },
}

pub(super) fn simple(t: &'static str, fields: Fields) -> Prepared {
    Prepared::Simple {
        t,
        fields,
        id_key: None,
        prefix: "",
    }
}

pub(super) fn prepare(p: &Parsed, ctx: &mut Ctx, path: &str) -> Result<Prepared, ApiError> {
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
            ]
            .into_iter()
            .chain(caller(p, ctx))
            .collect(),
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
        "tab describe" => simple(
            "ui.tab.meta",
            vec![
                ("tab", Some(tab(pos(0), ctx)?)),
                (
                    "description",
                    Some(Value::text(rest(1).chars().take(1024).collect::<String>())),
                ),
            ],
        ),
        "tab status" => {
            let state = pos(1);
            if !["none", "in_progress", "review", "blocked", "done"].contains(&state) {
                return Err(usage("STATE is none, in_progress, review, blocked or done"));
            }
            simple(
                "ui.tab.meta",
                vec![
                    ("tab", Some(tab(pos(0), ctx)?)),
                    ("status", Some(Value::text(state))),
                ],
            )
        }
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
        "ssh" if p.has("no-hook") && p.flag("cmd").is_some() => {
            return Err(usage("--cmd needs the server hook (drop --no-hook)"))
        }
        "ssh" if p.has("no-hook") && p.flag("cwd").is_some() => {
            return Err(usage("--cwd needs the server hook (drop --no-hook)"))
        }
        "ssh" => Prepared::Simple {
            t: "ui.ssh.open",
            fields: vec![
                ("target", Some(Value::text(pos(0)))),
                ("workspace", text(p.flag("workspace"))),
                // A server path: never made absolute against the local directory.
                ("cwd", text(p.flag("cwd"))),
                ("cmd", cmd(p)?),
                ("hook", Some(Value::Bool(!p.has("no-hook")))),
                ("focus", flag(p, "focus")),
            ],
            id_key: Some("tab"),
            prefix: "t",
        },
        "tmux attach" => Prepared::Simple {
            t: "ui.tmux.attach",
            fields: vec![
                ("name", Some(Value::text(pos(0)))),
                ("host", text(p.flag("host"))),
                ("create", flag(p, "create")),
                ("focus", flag(p, "focus")),
            ],
            id_key: Some("tab"),
            prefix: "t",
        },
        "tmux ls" => Prepared::TmuxList {
            host: text(p.flag("host")),
        },
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
                (None, Some(f)) => read_file(&ctx.cwd.join(f), MAX_SCRIPT)
                    .map_err(|e| usage(format!("cannot read {f}: {e}")))?,
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

/// At most `max` bytes (review M4): a huge or endless file (a FIFO,
/// /dev/zero) is refused, never read to its end.
fn read_file(path: &std::path::Path, max: usize) -> Result<String, String> {
    use std::io::Read;
    let f = std::fs::File::open(path).map_err(|e| e.kind().to_string())?;
    let mut buf = Vec::new();
    f.take(max as u64 + 1)
        .read_to_end(&mut buf)
        .map_err(|e| e.kind().to_string())?;
    if buf.len() > max {
        return Err(format!("it is over {} KiB", max / 1024));
    }
    String::from_utf8(buf).map_err(|_| "it is not UTF-8".into())
}
