//! `shellx agent-event AGENT EVENT` — the hook receiver (A12 D4–D6).
//!
//! An agent's hook runs this command; it reduces the hook's JSON to the
//! few fields ShellX uses and sends one `ui.agent.event` over the CLI
//! socket. The hook must never hurt the agent (D5): the command exits 0
//! whatever happens, prints nothing unless stdout is a terminal, does
//! nothing outside a ShellX pane, and is cut off after [`BUDGET`] by the
//! caller (`api::main`).
//!
//! The agent, event and payload come from a process the user does not
//! control, so they are normalised and limited here and checked again by
//! the app. Nothing here is logged: no prompt, path or session id is ever
//! written anywhere, and the `Debug` of a payload or a wire event hides
//! its contents.

use crate::api::args::Parsed;
use crate::api::integrations::json::top_level_strings;
use crate::api::run::{canonical, Api, Ctx};
use crate::api::value::Value;
use std::io::Read;

/// D26: most of the hook's stdin that is read.
pub const MAX_STDIN: usize = 64 * 1024;
/// D26: the whole command, connect included.
pub const BUDGET: std::time::Duration = std::time::Duration::from_secs(2);
const MAX_SESSION: usize = 128;
const MAX_MESSAGE: usize = 1024;

/// The string members of the hook's top-level JSON object (nothing else
/// of it is ever kept).
#[derive(Default, Clone, PartialEq)]
pub struct Payload(Vec<(String, String)>);

impl Payload {
    pub fn from_json(text: &str) -> Payload {
        Payload(top_level_strings(text))
    }

    #[cfg(test)]
    pub fn from_pairs(pairs: &[(&str, &str)]) -> Payload {
        Payload(
            pairs
                .iter()
                .map(|(k, v)| (k.to_string(), v.to_string()))
                .collect(),
        )
    }

    fn get(&self, key: &str) -> Option<&str> {
        self.0
            .iter()
            .find(|(k, _)| k == key)
            .map(|(_, v)| v.as_str())
    }
}

impl std::fmt::Debug for Payload {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "Payload(…)")
    }
}

/// `--session` and `--message`; they win over the payload.
#[derive(Debug, Default, Clone)]
pub struct Flags {
    pub session: Option<String>,
    pub message: Option<String>,
}

/// What goes on the wire (`event` is the D4 vocabulary).
#[derive(Clone, PartialEq)]
pub struct Wire {
    pub event: &'static str,
    pub session: Option<String>,
    pub message: Option<String>,
    /// `false` when the turn failed (no hook says so yet).
    pub ok: bool,
    pub at: i64,
}

impl std::fmt::Debug for Wire {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "Wire({}, …)", self.event)
    }
}

/// `^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$`: needs no quoting and cannot
/// start with `-`.
fn session_ok(s: &str) -> bool {
    let b = s.as_bytes();
    !b.is_empty()
        && b.len() <= MAX_SESSION
        && b[0].is_ascii_alphanumeric()
        && b[1..]
            .iter()
            .all(|c| c.is_ascii_alphanumeric() || matches!(c, b'.' | b'_' | b':' | b'-'))
}

/// Controls become spaces, at most [`MAX_MESSAGE`] characters; blank is none.
fn clean_message(s: &str) -> Option<String> {
    let t: String = s
        .chars()
        .map(|c| if c.is_control() { ' ' } else { c })
        .take(MAX_MESSAGE)
        .collect();
    let t = t.trim();
    (!t.is_empty()).then(|| t.to_string())
}

fn notification(payload: &Payload) -> &'static str {
    match payload.get("notification_type") {
        Some("permission_prompt" | "elicitation_dialog") => return "needs_input",
        Some("idle_prompt") => return "idle",
        _ => {}
    }
    let m = payload.get("message").unwrap_or("").to_lowercase();
    if m.contains("permission") {
        "needs_input"
    } else if m.contains("waiting for your input") {
        "idle"
    } else {
        "notice"
    }
}

/// D6: the agent's own event → the wire event; `None` sends nothing.
pub fn normalize(
    agent: &str,
    event: &str,
    payload: &Payload,
    flags: &Flags,
    now_ms: i64,
) -> Option<Wire> {
    let (wire, session, message): (&'static str, Option<&str>, bool) = match (agent, event) {
        ("claude" | "gemini", _) => {
            let w = match event {
                "session-start" => "start",
                "prompt-submit" => "running",
                "notification" => notification(payload),
                "stop" => "idle",
                "session-end" => "end",
                _ => return None,
            };
            (w, payload.get("session_id"), event == "notification")
        }
        ("codex", "turn-complete") => (
            "idle",
            payload
                .get("thread-id")
                .or_else(|| payload.get("thread_id")),
            false,
        ),
        ("opencode", _) => {
            let w = match event {
                "session-start" => "start",
                "running" => "running",
                "needs-input" => "needs_input",
                "idle" => "idle",
                "session-end" => "end",
                _ => return None,
            };
            (w, None, false)
        }
        _ => return None,
    };
    let session = flags
        .session
        .as_deref()
        .or(session)
        .filter(|s| session_ok(s))
        .map(String::from);
    let message = if message {
        flags
            .message
            .as_deref()
            .or_else(|| payload.get("message"))
            .and_then(clean_message)
    } else {
        None
    };
    Some(Wire {
        event: wire,
        session,
        message,
        ok: true,
        at: now_ms,
    })
}

fn read_bounded(input: &mut dyn Read) -> String {
    let mut buf = Vec::new();
    let _ = input.take(MAX_STDIN as u64).read_to_end(&mut buf);
    String::from_utf8(buf).unwrap_or_default()
}

/// The command. Returns nothing: every failure is swallowed (D5), and a
/// terminal gets one fixed sentence on stderr.
pub(crate) fn command(p: &Parsed, ctx: &mut Ctx) {
    // Inside a ShellX pane only: its pane id, the socket and the token of
    // the launch are all in the environment.
    let env = |k: &str| (ctx.env)(k).filter(|v| !v.is_empty());
    let Some(pane) = env("SHELLX_PANE_ID").and_then(|v| canonical(&v, false)) else {
        return;
    };
    if env("SHELLX_SOCKET").is_none() || env("SHELLX_CLI_TOKEN").is_none() {
        return;
    }
    let (Some(agent), Some(event)) = (p.pos(0), p.pos(1)) else {
        return;
    };
    let flags = Flags {
        session: p.flag("session").map(String::from),
        message: p.flag("message").map(String::from),
    };
    // Unknown agent or event: nothing to send, so nothing to read either.
    if normalize(agent, event, &Payload::default(), &flags, 0).is_none() {
        return;
    }
    let payload = match p.pos(2) {
        Some(argv) if argv.len() <= MAX_STDIN => Payload::from_json(argv),
        Some(_) => Payload::default(),
        None if matches!(agent, "claude" | "gemini") && !ctx.stdin_is_tty => {
            Payload::from_json(&read_bounded(ctx.stdin))
        }
        None => Payload::default(),
    };
    let now = (ctx.now_ms)();
    let Some(w) = normalize(agent, event, &payload, &flags, now) else {
        return;
    };
    let sent = Api::open(p, ctx).and_then(|mut api| {
        api.call(
            "ui.agent.event",
            vec![
                ("pane", Some(Value::Int(pane))),
                ("agent", Some(Value::text(agent))),
                ("event", Some(Value::text(w.event))),
                ("at", Some(Value::Int(w.at))),
                ("session", w.session.map(Value::text)),
                ("message", w.message.map(Value::text)),
                ("ok", (!w.ok).then_some(Value::Bool(false))),
            ],
        )
    });
    if let (Err(e), true) = (sent, ctx.stdout_is_tty) {
        use crate::api::client::ApiError::*;
        let why = match e {
            NotRunning(_) => "ShellX is not running",
            Incompatible(_) => "this ShellX is too old for agent events",
            Remote { .. } | Reported(_) => "ShellX refused the event",
            Usage(_) | Io(_) => "could not send the event",
        };
        let _ = writeln!(ctx.err, "shellx: agent-event: {why}");
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn fx(name: &str) -> String {
        let p = format!(
            "{}/tests/agent_event_fixtures/{name}.json",
            env!("CARGO_MANIFEST_DIR")
        );
        std::fs::read_to_string(p).unwrap()
    }
    fn payload(json: &str) -> Payload {
        Payload::from_json(json)
    }
    fn norm(agent: &str, event: &str, p: &Payload) -> Option<Wire> {
        normalize(agent, event, p, &Flags::default(), 1000)
    }

    #[test]
    fn claude_notification_permission_is_needs_input_with_message() {
        let p = payload(&fx("claude_notification_permission"));
        let w = normalize("claude", "notification", &p, &Flags::default(), 1000).unwrap();
        assert_eq!(
            (w.event, w.session.as_deref(), w.ok),
            ("needs_input", Some("7a1c"), true)
        );
        assert!(w.message.unwrap().contains("permission"));
        assert_eq!(w.at, 1000);
    }

    #[test]
    fn idle_prompt_is_idle_not_needs_input() {
        let p = payload(&fx("claude_notification_idle"));
        assert_eq!(norm("claude", "notification", &p).unwrap().event, "idle");
        assert_eq!(norm("gemini", "notification", &p).unwrap().event, "idle");
        let ask = payload(
            r#"{"session_id":"s","notification_type":"elicitation_dialog","message":"waiting for your input"}"#,
        );
        assert_eq!(
            norm("claude", "notification", &ask).unwrap().event,
            "needs_input"
        );
    }

    #[test]
    fn old_claude_without_type_falls_back_to_the_message() {
        let ev = |name: &str| {
            norm("claude", "notification", &payload(&fx(name)))
                .unwrap()
                .event
        };
        assert_eq!(ev("claude_notification_old_permission"), "needs_input");
        assert_eq!(ev("claude_notification_old_idle"), "idle");
        assert_eq!(ev("claude_notification_other"), "notice");
        // An unknown type is treated like an absent one.
        let p = payload(r#"{"notification_type":"auth_success","message":"Needs PERMISSION"}"#);
        assert_eq!(
            norm("claude", "notification", &p).unwrap().event,
            "needs_input"
        );
    }

    #[test]
    fn claude_and_gemini_lifecycle_events() {
        let p = payload(&fx("claude_stop"));
        for agent in ["claude", "gemini"] {
            for (arg, wire) in [
                ("session-start", "start"),
                ("prompt-submit", "running"),
                ("stop", "idle"),
                ("session-end", "end"),
            ] {
                let w = norm(agent, arg, &p).unwrap();
                assert_eq!((w.event, w.session.as_deref()), (wire, Some("7a1c")));
                assert_eq!(w.message, None, "only a notification carries text");
            }
        }
    }

    #[test]
    fn hostile_session_ids_are_dropped_but_the_event_survives() {
        let long = "x".repeat(129);
        for bad in [
            "",
            "-rf",
            "a b",
            "a;rm -rf ~",
            "$(x)",
            "a\nb",
            "é",
            ".a",
            long.as_str(),
        ] {
            let p = Payload::from_pairs(&[("session_id", bad)]);
            let w = norm("claude", "stop", &p).unwrap();
            assert_eq!((w.event, w.session), ("idle", None), "{bad:?}");
        }
        for good in ["a", "7a1c", "A.b_c:d-e", &"x".repeat(128)] {
            let p = Payload::from_pairs(&[("session_id", good)]);
            assert_eq!(
                norm("claude", "stop", &p).unwrap().session.as_deref(),
                Some(good)
            );
        }
    }

    #[test]
    fn codex_session_comes_from_the_argv_json() {
        let p = payload(&fx("codex_turn_complete"));
        let w = norm("codex", "turn-complete", &p).unwrap();
        assert_eq!(w.event, "idle");
        assert_eq!(
            w.session.as_deref(),
            Some("019a1b2c-3d4e-7f80-9a1b-2c3d4e5f6a7b")
        );
        assert_eq!(w.message, None, "the assistant's text is never taken");
        let snake = payload(r#"{"thread_id":"abc"}"#);
        assert_eq!(
            norm("codex", "turn-complete", &snake)
                .unwrap()
                .session
                .as_deref(),
            Some("abc")
        );
        assert!(norm("codex", "stop", &p).is_none());
    }

    #[test]
    fn opencode_events_and_session_flag() {
        let flags = Flags {
            session: Some("ses_1".into()),
            message: None,
        };
        for (arg, wire) in [
            ("session-start", "start"),
            ("running", "running"),
            ("needs-input", "needs_input"),
            ("idle", "idle"),
            ("session-end", "end"),
        ] {
            let w = normalize("opencode", arg, &Payload::default(), &flags, 5).unwrap();
            assert_eq!((w.event, w.session.as_deref()), (wire, Some("ses_1")));
        }
    }

    #[test]
    fn unknown_agent_or_event_sends_nothing() {
        let p = payload(&fx("claude_stop"));
        assert!(norm("cursor", "stop", &p).is_none());
        assert!(norm("claude", "subagent-stop", &p).is_none());
        assert!(norm("claude", "SubagentStop", &p).is_none());
        assert!(norm("Claude", "stop", &p).is_none());
        assert!(norm("", "", &p).is_none());
        assert!(norm("opencode", "stop", &p).is_none());
    }

    #[test]
    fn message_is_cleaned_and_clipped() {
        let p = Payload::from_pairs(&[
            ("message", "a\u{1b}[31mb\nc\td\u{7}"),
            ("notification_type", "permission_prompt"),
        ]);
        let m = norm("claude", "notification", &p).unwrap().message.unwrap();
        assert_eq!(m, "a [31mb c d");
        let long = "é".repeat(2000);
        let p = Payload::from_pairs(&[("message", &long)]);
        let m = norm("claude", "notification", &p).unwrap().message.unwrap();
        assert_eq!(m.chars().count(), 1024);
        let blank = Payload::from_pairs(&[("message", " \n ")]);
        assert_eq!(
            norm("claude", "notification", &blank).unwrap().message,
            None
        );
    }

    #[test]
    fn flags_override_the_payload() {
        let p = payload(&fx("claude_notification_permission"));
        let flags = Flags {
            session: Some("from-flag".into()),
            message: Some("from flag".into()),
        };
        let w = normalize("claude", "notification", &p, &flags, 1).unwrap();
        assert_eq!(w.session.as_deref(), Some("from-flag"));
        assert_eq!(w.message.as_deref(), Some("from flag"));
        // A bad flag is dropped, not replaced by the payload's.
        let bad = Flags {
            session: Some("-x".into()),
            message: None,
        };
        assert_eq!(
            normalize("claude", "stop", &p, &bad, 1).unwrap().session,
            None
        );
    }

    #[test]
    fn payload_that_is_not_an_object_is_empty() {
        for t in ["", "[]", "nope", "{\"a\":", "\u{0}"] {
            let p = payload(t);
            let w = norm("claude", "stop", &p).unwrap();
            assert_eq!((w.event, w.session), ("idle", None), "{t:?}");
        }
    }

    #[test]
    fn debug_of_a_wire_event_hides_its_contents() {
        let p = payload(&fx("claude_notification_permission"));
        let w = norm("claude", "notification", &p).unwrap();
        let shown = format!("{w:?}");
        assert!(
            !shown.contains("7a1c") && !shown.contains("permission"),
            "{shown}"
        );
        let shown = format!("{p:?}");
        assert!(!shown.contains("7a1c"), "{shown}");
    }
}
