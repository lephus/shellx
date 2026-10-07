//! Human and JSON renderings (D11, spec §3.4). Ids go out in the form users
//! type back: `p12`, `t7`, `w:x`. Optional keys may be `null` (the host
//! sends `cwd`, `branch`, `exitCode`… as null when unknown).

use super::value::Value;
use super::wire::Message;
use std::path::Path;

fn prefixed(key: &str, v: &Value) -> Value {
    match (key, v) {
        ("pane" | "focusedPane", Value::Int(n)) => Value::text(format!("p{n}")),
        ("tab" | "selectedTab", Value::Int(n)) => Value::text(format!("t{n}")),
        ("workspace", Value::Text(s)) => Value::text(format!("w:{s}")),
        _ => v.clone(),
    }
}

/// A result's fields with top-level ids prefixed.
pub fn result_json(m: &Message) -> Value {
    Value::Map(
        m.fields
            .iter()
            .map(|(k, v)| (k.clone(), prefixed(k, v)))
            .collect(),
    )
}

/// An event's fields (`kind`, ids prefixed).
pub fn event_json(m: &Message) -> Value {
    result_json(m)
}

fn map_ids(v: &Value, prefix: &str) -> Value {
    let Value::Map(m) = v else {
        return v.clone();
    };
    Value::Map(
        m.iter()
            .map(|(k, x)| {
                let x = match (k.as_str(), x) {
                    ("id", Value::Int(n)) => Value::text(format!("{prefix}{n}")),
                    ("id", Value::Text(s)) if prefix == "w:" => Value::text(format!("w:{s}")),
                    ("tabs", Value::Array(a)) => {
                        Value::Array(a.iter().map(|t| map_ids(t, "t")).collect())
                    }
                    ("panes", Value::Array(a)) => {
                        Value::Array(a.iter().map(|p| map_ids(p, "p")).collect())
                    }
                    _ => x.clone(),
                };
                (k.clone(), x)
            })
            .collect(),
    )
}

/// `ls --json` (§3.4): every workspace, tab and pane id prefixed.
pub fn ls_json(m: &Message) -> Value {
    Value::Map(
        m.fields
            .iter()
            .map(|(k, v)| match (k.as_str(), v) {
                ("workspaces", Value::Array(a)) => (
                    k.clone(),
                    Value::Array(a.iter().map(|w| map_ids(w, "w:")).collect()),
                ),
                (_, v) => (k.clone(), prefixed(k, v)),
            })
            .collect(),
    )
}

fn arr(v: Option<&Value>) -> &[Value] {
    v.and_then(Value::as_array).unwrap_or(&[])
}

/// Text from the host or a page, for a terminal: control characters
/// (C0, DEL, C1 — escape sequences, bells) are dropped (review M8).
pub fn plain(s: &str) -> String {
    s.chars().filter(|c| !c.is_control()).collect()
}

fn text(v: &Value, key: &str) -> String {
    plain(v.get(key).and_then(Value::as_str).unwrap_or(""))
}

fn tilde(path: &str, home: Option<&Path>) -> String {
    match home.and_then(|h| h.to_str()).filter(|h| !h.is_empty()) {
        Some(h) if path == h => "~".into(),
        Some(h) if path.starts_with(h) && path[h.len()..].starts_with(['/', '\\']) => {
            format!("~{}", &path[h.len()..])
        }
        _ => path.into(),
    }
}

/// `~/cwd  branch  :port  url`, skipping what is unknown.
fn context(v: &Value, home: Option<&Path>) -> String {
    let mut parts = Vec::new();
    if let Some(c) = v.get("cwd").and_then(Value::as_str) {
        parts.push(plain(&tilde(c, home)));
    }
    if let Some(b) = v.get("branch").and_then(Value::as_str) {
        parts.push(plain(b));
    }
    for p in arr(v.get("ports")) {
        if let Some(n) = p.as_i64() {
            parts.push(format!(":{n}"));
        }
    }
    if let Some(u) = v.get("url").and_then(Value::as_str) {
        parts.push(plain(u));
    }
    parts.join("  ")
}

/// `[ssh host]`, `[tmux host:name state]`: where a pane really runs.
fn remote_label(p: &Value) -> String {
    let Some(r) = p.get("remote") else {
        return String::new();
    };
    let kind = text(r, "kind");
    let host = text(r, "host");
    let tmux = text(r, "tmux");
    let target = match (host.is_empty(), tmux.is_empty()) {
        (false, false) => format!("{host}:{tmux}"),
        (false, true) => host,
        (true, false) => tmux,
        (true, true) => String::new(),
    };
    let state = text(r, "state");
    let inner = [
        kind,
        target,
        if state == "connected" {
            String::new()
        } else {
            state
        },
    ]
    .into_iter()
    .filter(|s| !s.is_empty())
    .collect::<Vec<_>>()
    .join(" ");
    format!("[{inner}]")
}

fn line(parts: &[String]) -> String {
    let mut s = parts
        .iter()
        .filter(|p| !p.is_empty())
        .cloned()
        .collect::<Vec<_>>()
        .join("  ");
    s.push('\n');
    s
}

/// The indented tree (D13): workspace → tab → pane.
pub fn ls_human(m: &Message, home: Option<&Path>) -> String {
    let mut s = String::new();
    if m.get("ui").and_then(Value::as_bool) == Some(false) {
        s.push_str("ShellX window is closed; shells still running:\n");
        for x in arr(m.get("sessions")) {
            let id = x.get("id").and_then(Value::as_i64).unwrap_or(0);
            s.push_str("  ");
            s.push_str(&line(&[
                format!("p{id}"),
                text(x, "title"),
                context(x, home),
            ]));
        }
        return s;
    }
    for w in arr(m.get("workspaces")) {
        let current = w.get("current").and_then(Value::as_bool) == Some(true);
        s.push_str(&line(&[
            text(w, "name"),
            format!("w:{}", text(w, "id")),
            if current {
                "(current)".into()
            } else {
                String::new()
            },
        ]));
        for t in arr(w.get("tabs")) {
            let tid = t.get("id").and_then(Value::as_i64).unwrap_or(0);
            let unread = t.get("unread").and_then(Value::as_i64).filter(|n| *n > 0);
            let flag = |k: &str, label: &str| {
                if t.get(k).and_then(Value::as_bool) == Some(true) {
                    label.to_string()
                } else {
                    String::new()
                }
            };
            s.push_str("  ");
            s.push_str(&line(&[
                format!("t{tid}"),
                text(t, "title"),
                unread.map(|n| format!("●{n}")).unwrap_or_default(),
                flag("selected", "(selected)"),
                flag("agent", "[agent]"),
            ]));
            for p in arr(t.get("panes")) {
                let pid = p.get("id").and_then(Value::as_i64).unwrap_or(0);
                let browser = text(p, "kind") == "browser";
                let focused = p.get("focused").and_then(Value::as_bool) == Some(true);
                let exited = p
                    .get("exitCode")
                    .and_then(Value::as_i64)
                    .map(|c| format!("[exited {c}]"));
                s.push_str("    ");
                s.push_str(&line(&[
                    if browser {
                        format!("p{pid} browser")
                    } else {
                        format!("p{pid}")
                    },
                    text(p, "title"),
                    context(p, home),
                    remote_label(p),
                    if focused {
                        "(focused)".into()
                    } else {
                        String::new()
                    },
                    exited.unwrap_or_default(),
                ]));
            }
        }
    }
    s
}

/// `ls --ids`: tab and pane ids, one per line (completion, D36).
pub fn ls_ids(m: &Message) -> String {
    let mut s = String::new();
    for w in arr(m.get("workspaces")) {
        for t in arr(w.get("tabs")) {
            if let Some(id) = t.get("id").and_then(Value::as_i64) {
                s.push_str(&format!("t{id}\n"));
            }
            for p in arr(t.get("panes")) {
                if let Some(id) = p.get("id").and_then(Value::as_i64) {
                    s.push_str(&format!("p{id}\n"));
                }
            }
        }
    }
    s
}
