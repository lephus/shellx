//! Pure decoding of mux control lines: attach events (`spec/events.md`,
//! "Attach stream v6 PTY") and the `list-workspaces` tree
//! (`spec/commands.md`, "Shared Implemented Result Types").

use anyhow::{Context, anyhow, bail};
use base64::Engine;
use serde_json::Value;

/// One event of an attached remote terminal.
///
/// Every `Snapshot` is preceded by a `Resized` that gives its grid: on
/// `Resized` the viewer replaces its mirror with a fresh terminal of that
/// size, then feeds the `Snapshot` bytes, then later `Output` bytes in order.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum AttachEvent {
    /// VT replay of the current screen (`vt-state` data, or the replay of a
    /// `resized` event). Feed into the fresh mirror created at `Resized`.
    Snapshot(Vec<u8>),
    /// Live PTY bytes after the snapshot.
    Output(Vec<u8>),
    /// The authoritative grid is now `cols` x `rows`; a `Snapshot` follows.
    Resized { cols: u16, rows: u16 },
    /// The surface exited or the daemon detached this view.
    Ended,
    /// The connection to the Mac failed (or the attach stream overflowed);
    /// reconnect with a fresh `RemoteClient` and reattach.
    Disconnected(String),
}

/// A remote terminal (PTY tab) as listed by the daemon.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RemoteTerminal {
    /// Daemon surface id (decimal). Valid for this daemon boot.
    pub id: String,
    pub title: String,
    pub cols: u16,
    pub rows: u16,
}

/// What one daemon line on an attach stream means.
#[derive(Debug, PartialEq)]
pub(crate) enum Line {
    Events(Vec<AttachEvent>),
    Response {
        id: u64,
        result: Result<Value, String>,
    },
    Ignored,
}

pub(crate) fn decode_line(line: &[u8]) -> anyhow::Result<Line> {
    let value: Value = serde_json::from_slice(line).context("daemon sent a non-JSON mux line")?;
    if let Some(event) = value.get("event").and_then(Value::as_str) {
        return decode_event(event, &value).map(Line::Events);
    }
    if let Some(id) = value.get("id").and_then(Value::as_u64) {
        return Ok(Line::Response {
            id,
            result: response_result(&value),
        });
    }
    Ok(Line::Ignored)
}

/// `{"id":N,"ok":true,"data":…}` → `Ok(data)`; `ok:false` → `Err(error)`.
pub(crate) fn response_result(value: &Value) -> Result<Value, String> {
    if value.get("ok").and_then(Value::as_bool) == Some(true) {
        Ok(value.get("data").cloned().unwrap_or(Value::Null))
    } else {
        Err(value
            .get("error")
            .map(|error| match error {
                Value::String(text) => text.clone(),
                Value::Object(object) => object
                    .get("message")
                    .and_then(Value::as_str)
                    .map(str::to_owned)
                    .unwrap_or_else(|| error.to_string()),
                other => other.to_string(),
            })
            .unwrap_or_else(|| "daemon rejected the request".into()))
    }
}

fn decode_event(event: &str, value: &Value) -> anyhow::Result<Vec<AttachEvent>> {
    Ok(match event {
        "vt-state" => {
            let (cols, rows) = grid(value)?;
            let mut replay = base64_field(value, "data")?.unwrap_or_default();
            // Only sent to clients advertising terminal-pending-sequence-v1
            // (we do not); kept for safety: it belongs right after the replay.
            replay.extend(base64_field(value, "pending")?.unwrap_or_default());
            vec![
                AttachEvent::Resized { cols, rows },
                AttachEvent::Snapshot(replay),
            ]
        }
        "resized" => {
            let (cols, rows) = grid(value)?;
            // Protocol v7 carries the replay in `replay`, v6 in `data`.
            let mut replay = match base64_field(value, "replay")? {
                Some(replay) => replay,
                None => base64_field(value, "data")?.unwrap_or_default(),
            };
            replay.extend(base64_field(value, "pending")?.unwrap_or_default());
            vec![
                AttachEvent::Resized { cols, rows },
                AttachEvent::Snapshot(replay),
            ]
        }
        "output" => vec![AttachEvent::Output(
            base64_field(value, "data")?.unwrap_or_default(),
        )],
        "detached" => vec![AttachEvent::Ended],
        "overflow" => vec![AttachEvent::Disconnected("attach stream overflowed".into())],
        _ => Vec::new(),
    })
}

fn grid(value: &Value) -> anyhow::Result<(u16, u16)> {
    let field = |name: &str| {
        value
            .get(name)
            .and_then(Value::as_u64)
            .and_then(|number| u16::try_from(number).ok())
            .ok_or_else(|| anyhow!("attach event has no valid {name}"))
    };
    Ok((field("cols")?, field("rows")?))
}

fn base64_field(value: &Value, name: &str) -> anyhow::Result<Option<Vec<u8>>> {
    match value.get(name) {
        None | Some(Value::Null) => Ok(None),
        Some(Value::String(text)) => base64::engine::general_purpose::STANDARD
            .decode(text)
            .map(Some)
            .with_context(|| format!("attach event field {name} is not base64")),
        Some(_) => bail!("attach event field {name} is not a string"),
    }
}

/// Live PTY tabs of a `list-workspaces` tree, in tree order.
pub(crate) fn terminals_from_tree(tree: &Value) -> Vec<RemoteTerminal> {
    let mut out = Vec::new();
    let empty = Vec::new();
    let array = |value: &Value, key: &str| -> Vec<Value> {
        value
            .get(key)
            .and_then(Value::as_array)
            .cloned()
            .unwrap_or_default()
    };
    for workspace in tree
        .get("workspaces")
        .and_then(Value::as_array)
        .unwrap_or(&empty)
    {
        let workspace_name = workspace.get("name").and_then(Value::as_str).unwrap_or("");
        for screen in array(workspace, "screens") {
            for pane in array(&screen, "panes") {
                for tab in array(&pane, "tabs") {
                    if tab.get("kind").and_then(Value::as_str) != Some("pty")
                        || tab.get("dead").and_then(Value::as_bool) == Some(true)
                    {
                        continue;
                    }
                    let Some(surface) = tab.get("surface").and_then(Value::as_u64) else {
                        continue;
                    };
                    let text = |key: &str| {
                        tab.get(key)
                            .and_then(Value::as_str)
                            .filter(|text| !text.is_empty())
                    };
                    let title = text("name")
                        .or_else(|| text("title"))
                        .unwrap_or(workspace_name);
                    let size = tab.get("size");
                    let dim = |key: &str| {
                        size.and_then(|size| size.get(key))
                            .and_then(Value::as_u64)
                            .and_then(|number| u16::try_from(number).ok())
                            .unwrap_or(0)
                    };
                    out.push(RemoteTerminal {
                        id: surface.to_string(),
                        title: title.to_string(),
                        cols: dim("cols"),
                        rows: dim("rows"),
                    });
                }
            }
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    fn b64(bytes: &[u8]) -> String {
        base64::engine::general_purpose::STANDARD.encode(bytes)
    }

    fn events(line: Value) -> Vec<AttachEvent> {
        match decode_line(&serde_json::to_vec(&line).unwrap()).unwrap() {
            Line::Events(events) => events,
            other => panic!("expected events, got {other:?}"),
        }
    }

    #[test]
    fn vt_state_gives_grid_then_snapshot() {
        let line = json!({"event":"vt-state","surface":1,"cols":80,"rows":24,
            "data": b64(b"\x1b[?l"), "colors": {"fg": null}});
        assert_eq!(
            events(line),
            vec![
                AttachEvent::Resized { cols: 80, rows: 24 },
                AttachEvent::Snapshot(b"\x1b[?l".to_vec())
            ]
        );
    }

    #[test]
    fn pending_bytes_follow_the_replay() {
        let line = json!({"event":"vt-state","surface":1,"cols":2,"rows":1,
            "data": b64(b"ab"), "pending": b64(b"\x1b[")});
        assert_eq!(events(line)[1], AttachEvent::Snapshot(b"ab\x1b[".to_vec()));
    }

    #[test]
    fn resized_accepts_replay_or_data() {
        let v7 = json!({"event":"resized","surface":1,"cols":100,"rows":30,"replay": b64(b"R")});
        let v6 = json!({"event":"resized","surface":1,"cols":100,"rows":30,"data": b64(b"D")});
        assert_eq!(events(v7)[1], AttachEvent::Snapshot(b"R".to_vec()));
        assert_eq!(
            events(v6),
            vec![
                AttachEvent::Resized {
                    cols: 100,
                    rows: 30
                },
                AttachEvent::Snapshot(b"D".to_vec())
            ]
        );
    }

    #[test]
    fn output_is_raw_utf8_bytes() {
        let text = "tiếng Việt\r\n";
        let line = json!({"event":"output","surface":1,"data": b64(text.as_bytes())});
        assert_eq!(
            events(line),
            vec![AttachEvent::Output(text.as_bytes().to_vec())]
        );
    }

    #[test]
    fn detached_and_overflow_end_the_view() {
        assert_eq!(
            events(json!({"event":"detached","surface":1})),
            vec![AttachEvent::Ended]
        );
        assert!(matches!(
            events(json!({"event":"overflow","scope":"surface"}))[0],
            AttachEvent::Disconnected(_)
        ));
        assert!(events(json!({"event":"colors-changed","fg":null})).is_empty());
    }

    #[test]
    fn bad_event_payloads_are_errors() {
        let no_grid = json!({"event":"vt-state","surface":1,"data":""});
        assert!(decode_line(&serde_json::to_vec(&no_grid).unwrap()).is_err());
        let bad = json!({"event":"output","surface":1,"data":"*not base64*"});
        assert!(decode_line(&serde_json::to_vec(&bad).unwrap()).is_err());
        assert!(decode_line(b"not json").is_err());
    }

    #[test]
    fn responses_carry_data_or_error() {
        let ok = decode_line(br#"{"id":5,"ok":true,"data":{"lease":"x"}}"#).unwrap();
        assert_eq!(
            ok,
            Line::Response {
                id: 5,
                result: Ok(json!({"lease":"x"}))
            }
        );
        let err = decode_line(br#"{"id":6,"ok":false,"error":"unknown surface 9"}"#).unwrap();
        assert_eq!(
            err,
            Line::Response {
                id: 6,
                result: Err("unknown surface 9".into())
            }
        );
        let structured =
            decode_line(br#"{"id":7,"ok":false,"error":{"code":"x","message":"nope"}}"#).unwrap();
        assert_eq!(
            structured,
            Line::Response {
                id: 7,
                result: Err("nope".into())
            }
        );
    }

    #[test]
    fn tree_lists_live_pty_tabs_only() {
        let tree = json!({"workspace_revision":1,"workspaces":[{"id":4,"name":"ShellX","active":true,
            "screens":[{"id":3,"name":null,"active":true,"active_pane":2,"layout":{"type":"leaf","pane":2},
            "panes":[{"id":2,"name":null,"active_tab":0,"tabs":[
                {"surface":1,"kind":"pty","browser_source":null,"name":null,"title":"zsh","size":{"cols":80,"rows":24},"dead":false},
                {"surface":5,"kind":"browser","browser_source":null,"name":null,"title":"web","size":null,"dead":false},
                {"surface":6,"kind":"pty","browser_source":null,"name":null,"title":"","size":null,"dead":true},
                {"surface":7,"kind":"pty","browser_source":null,"name":"build","title":"make","size":{"cols":120,"rows":40},"dead":false}
            ]},{"id":9,"dead":true}]}]}]});
        assert_eq!(
            terminals_from_tree(&tree),
            vec![
                RemoteTerminal {
                    id: "1".into(),
                    title: "zsh".into(),
                    cols: 80,
                    rows: 24
                },
                RemoteTerminal {
                    id: "7".into(),
                    title: "build".into(),
                    cols: 120,
                    rows: 40
                },
            ]
        );
        assert!(terminals_from_tree(&json!({"workspaces":[]})).is_empty());
    }

    #[test]
    fn untitled_tab_falls_back_to_workspace_name() {
        let tree = json!({"workspaces":[{"name":"ShellX","screens":[{"panes":[{"tabs":[
            {"surface":3,"kind":"pty","name":null,"title":"","size":{"cols":10,"rows":5},"dead":false}]}]}]}]});
        assert_eq!(terminals_from_tree(&tree)[0].title, "ShellX");
    }
}
