//! The nested hook shape Claude Code and Gemini CLI share (A12 D6):
//! `hooks.<Event>` is an array of groups, a group is
//! `{"hooks":[{"type":"command","command":"…","timeout":N}]}`.
//!
//! ShellX's entries are the hook commands that start with
//! `shellx agent-event `. Every edit is one byte-span primitive of
//! [`super::json`] and the text is parsed again after each, so nothing
//! outside the edited span can change; uninstall is the exact inverse.

use super::json::{
    append_element, detect_style, get, insert_member, parse, remove_element, remove_member, render,
    Json, JsonError, Kind, Node, Style,
};
use super::{Plan, Refusal};

pub struct NestedSpec {
    pub agent: &'static str,
    /// The unit the agent reads `timeout` in is part of the number.
    pub timeout: u32,
    /// (the agent's event name, the `agent-event` subcommand)
    pub events: &'static [(&'static str, &'static str)],
}

pub const CLAUDE: NestedSpec = NestedSpec {
    agent: "claude",
    timeout: 5,
    events: &[
        ("SessionStart", "session-start"),
        ("UserPromptSubmit", "prompt-submit"),
        ("Notification", "notification"),
        ("Stop", "stop"),
        ("SessionEnd", "session-end"),
    ],
};

/// What marks a hook command as ShellX's for this agent.
fn prefix(spec: &NestedSpec) -> String {
    format!("shellx agent-event {} ", spec.agent)
}

fn command(spec: &NestedSpec, sub: &str) -> String {
    format!("{}{sub}", prefix(spec))
}

fn group(spec: &NestedSpec, sub: &str) -> Json {
    Json::Obj(vec![(
        "hooks".into(),
        Json::Arr(vec![Json::Obj(vec![
            ("type".into(), Json::Str("command".into())),
            ("command".into(), Json::Str(command(spec, sub))),
            ("timeout".into(), Json::Num(i64::from(spec.timeout))),
        ])]),
    )])
}

fn refuse(e: JsonError) -> Refusal {
    match e {
        JsonError::TooBig => Refusal::TooBig,
        _ => Refusal::Invalid,
    }
}

fn read(text: &str) -> Result<Node, Refusal> {
    let root = parse(text).map_err(refuse)?;
    match root.kind {
        Kind::Obj(_) => Ok(root),
        _ => Err(Refusal::WrongType),
    }
}

/// The `command` string node of a hook entry, when it is ShellX's.
fn ours<'a>(entry: &'a Node, prefix: &str) -> Option<(&'a Node, &'a str)> {
    match get(entry, "command") {
        Some(
            n @ Node {
                kind: Kind::Str(c), ..
            },
        ) if c.starts_with(prefix) => Some((n, c)),
        _ => None,
    }
}

/// `hooks.<event>`'s groups, `None` when the event is absent.
fn event_groups<'a>(hooks: &'a Node, event: &str) -> Result<Option<&'a [Node]>, Refusal> {
    match get(hooks, event) {
        None => Ok(None),
        Some(Node {
            kind: Kind::Arr(groups),
            ..
        }) => Ok(Some(groups)),
        Some(_) => Err(Refusal::WrongType),
    }
}

/// The hook entries of a group (anything else in it is the user's).
fn entries(group: &Node) -> &[Node] {
    match get(group, "hooks") {
        Some(Node {
            kind: Kind::Arr(es),
            ..
        }) => es,
        _ => &[],
    }
}

fn splice(text: &str, n: &Node, with: &str) -> String {
    format!("{}{with}{}", &text[..n.span.start], &text[n.span.end..])
}

fn done(before: Option<&str>, after: String) -> Plan {
    let changed = before != Some(after.as_str());
    Plan {
        before: before.map(String::from),
        after,
        changed,
    }
}

pub fn install(spec: &NestedSpec, current: Option<&str>) -> Result<Plan, Refusal> {
    let st = current.map_or_else(Style::default, detect_style);
    let Some(text) = current else {
        let events = spec
            .events
            .iter()
            .map(|(e, sub)| ((*e).to_string(), Json::Arr(vec![group(spec, sub)])))
            .collect();
        let root = Json::Obj(vec![("hooks".into(), Json::Obj(events))]);
        return Ok(done(None, format!("{}{}", render(&root, 0, &st), st.eol)));
    };
    let mut text = text.to_string();
    let own = prefix(spec);
    let root = read(&text)?;
    let Some(hooks) = get(&root, "hooks") else {
        let events = spec
            .events
            .iter()
            .map(|(e, sub)| ((*e).to_string(), Json::Arr(vec![group(spec, sub)])))
            .collect();
        let value = render(&Json::Obj(events), 1, &st);
        text = insert_member(&text, &root, 0, "hooks", &value, &st);
        read(&text)?;
        return Ok(done(current, text));
    };
    if !matches!(hooks.kind, Kind::Obj(_)) {
        return Err(Refusal::WrongType);
    }
    // Check every event's type before the first edit.
    for (event, _) in spec.events {
        event_groups(hooks, event)?;
    }
    for (event, sub) in spec.events {
        let root = read(&text)?;
        let hooks = get(&root, "hooks").ok_or(Refusal::Invalid)?;
        let want = command(spec, sub);
        match event_groups(hooks, event)? {
            None => {
                let value = render(&Json::Arr(vec![group(spec, sub)]), 2, &st);
                text = insert_member(&text, hooks, 1, event, &value, &st);
            }
            Some(groups) => {
                let mine: Vec<(&Node, &str)> = groups
                    .iter()
                    .flat_map(entries)
                    .filter_map(|e| ours(e, &own))
                    .collect();
                if mine.is_empty() {
                    let arr = get(hooks, event).ok_or(Refusal::Invalid)?;
                    let value = render(&group(spec, sub), 3, &st);
                    text = append_element(&text, arr, 2, &value, &st);
                } else if let Some((node, _)) = mine.iter().find(|(_, c)| *c != want) {
                    text = splice(&text, node, &crate::api::value::json_string(&want));
                }
            }
        }
    }
    read(&text)?;
    Ok(done(current, text))
}

/// The first entry of ShellX's, as the nodes to cut: the highest ancestor
/// that would be left empty (the entry's group, the event, `hooks`).
fn first_ours<'a>(root: &'a Node, own: &str) -> Option<Cut<'a>> {
    let hooks = get(root, "hooks")?;
    let Kind::Obj(events) = &hooks.kind else {
        return None;
    };
    for ev in events {
        let Kind::Arr(groups) = &ev.value.kind else {
            continue;
        };
        for (gi, g) in groups.iter().enumerate() {
            let es = entries(g);
            let Some(ei) = es.iter().position(|e| ours(e, own).is_some()) else {
                continue;
            };
            let Some(inner) = get(g, "hooks") else {
                continue;
            };
            if es.len() > 1 {
                return Some(Cut::Element(inner, ei));
            }
            if groups.len() > 1 {
                return Some(Cut::Element(&ev.value, gi));
            }
            if events.len() > 1 {
                return Some(Cut::Member(hooks, &ev.key));
            }
            return Some(Cut::Member(root, "hooks"));
        }
    }
    None
}

enum Cut<'a> {
    Element(&'a Node, usize),
    Member(&'a Node, &'a str),
}

pub fn uninstall(spec: &NestedSpec, current: &str) -> Result<Plan, Refusal> {
    let own = prefix(spec);
    let mut text = current.to_string();
    // Each pass removes one of ours, so the count of entries bounds it.
    for _ in 0..=text.matches(own.as_str()).count() {
        let root = read(&text)?;
        let Some(cut) = first_ours(&root, &own) else {
            break;
        };
        text = match cut {
            Cut::Element(arr, i) => remove_element(&text, arr, i),
            Cut::Member(obj, key) => remove_member(&text, obj, key),
        };
    }
    read(&text)?;
    Ok(done(Some(current), text))
}

/// Every event has one of ShellX's hooks.
pub fn installed(spec: &NestedSpec, current: Option<&str>) -> bool {
    let Some(Ok(root)) = current.map(read) else {
        return false;
    };
    let Some(hooks) = get(&root, "hooks") else {
        return false;
    };
    let own = prefix(spec);
    spec.events.iter().all(|(event, sub)| {
        let want = command(spec, sub);
        matches!(event_groups(hooks, event), Ok(Some(groups))
            if groups.iter().flat_map(entries).filter_map(|e| ours(e, &own)).any(|(_, c)| c == want))
    })
}

/// What to paste by hand.
pub fn snippet(spec: &NestedSpec) -> String {
    let st = Style::default();
    let events = spec
        .events
        .iter()
        .map(|(e, sub)| ((*e).to_string(), Json::Arr(vec![group(spec, sub)])))
        .collect();
    let root = Json::Obj(vec![("hooks".into(), Json::Obj(events))]);
    format!("{}{}", render(&root, 0, &st), st.eol)
}
