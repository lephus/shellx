//! A12 D6–D7: install ShellX's agent hooks into the agents' own files.
//!
//! Everything here is a pure planner over the file's text (`plan_install`,
//! `plan_uninstall`); [`cli`] is the driver that reads, shows the diff,
//! asks, re-reads and writes, through the [`Fs`] and [`Prompt`] seams so
//! tests never touch a real home folder. The planners edit only the
//! entries ShellX owns, found by the exact `shellx agent-event` command,
//! and refuse (never guess) on anything they do not understand.

pub mod cli;
pub mod diff;
pub mod json;
pub mod nested_json;
pub mod real;

use std::io;
use std::path::{Path, PathBuf};

/// The agents ShellX installs hooks for.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Agent {
    Claude,
}

impl Agent {
    pub const ALL: [Agent; 1] = [Agent::Claude];

    /// The name used on the command line and in `agent-event`.
    pub fn name(self) -> &'static str {
        match self {
            Agent::Claude => "claude",
        }
    }

    pub fn from_name(name: &str) -> Option<Agent> {
        Agent::ALL.into_iter().find(|a| a.name() == name)
    }

    /// What the agent calls itself, for the sentences shown to the user.
    pub fn product(self) -> &'static str {
        match self {
            Agent::Claude => "Claude Code",
        }
    }

    /// The program looked for on `PATH`.
    pub fn binary(self) -> &'static str {
        match self {
            Agent::Claude => "claude",
        }
    }
}

/// Why a file is left alone. The messages are fixed sentences (A7 D11):
/// nothing the user wrote is ever echoed.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Refusal {
    /// Comments, trailing commas, a duplicate key or not JSON at all.
    Invalid,
    /// Valid, but a node ShellX must extend is not of the expected type.
    WrongType,
    /// The user owns this already (`"notify"`, `"plugin file"`).
    Foreign(&'static str),
    /// Over 1 MiB.
    TooBig,
    /// A file of ours that has been edited since (OpenCode's plugin).
    Edited,
}

pub fn refusal_message(a: Agent, r: Refusal) -> String {
    match r {
        Refusal::Invalid | Refusal::WrongType => match a {
            Agent::Claude => "refusing: the file has comments, is not valid JSON or does not have the expected shape (use --print to see what to add)".into(),
        },
        Refusal::Foreign(what) => {
            format!("refusing: a {what} of yours is already there (shellx will not replace it; see --print)")
        }
        Refusal::TooBig => "refusing: the file is over 1 MiB".into(),
        Refusal::Edited => {
            "refusing: the file was edited after ShellX wrote it; delete it yourself".into()
        }
    }
}

/// The text of a file before and after a change.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Plan {
    pub before: Option<String>,
    pub after: String,
    pub changed: bool,
}

pub fn plan_install(a: Agent, current: Option<&str>) -> Result<Plan, Refusal> {
    match a {
        Agent::Claude => nested_json::install(&nested_json::CLAUDE, current),
    }
}

/// Removes only ShellX's entries from `current`.
pub fn plan_uninstall(a: Agent, current: &str) -> Result<Plan, Refusal> {
    match a {
        Agent::Claude => nested_json::uninstall(&nested_json::CLAUDE, current),
    }
}

/// Every one of ShellX's entries is present.
pub fn installed(a: Agent, current: Option<&str>) -> bool {
    match a {
        Agent::Claude => nested_json::installed(&nested_json::CLAUDE, current),
    }
}

/// After an uninstall, nothing of the file is left (an empty document), so
/// a file ShellX created can go.
pub fn leaves_nothing(a: Agent, after: &str) -> bool {
    match a {
        Agent::Claude => after.trim_start_matches('\u{feff}').trim() == "{}",
    }
}

/// The agent's file is wholly ShellX's: uninstall deletes it.
pub fn owns_file(a: Agent) -> bool {
    match a {
        Agent::Claude => false,
    }
}

/// What `--print` shows: the part to add by hand.
pub fn snippet(a: Agent) -> String {
    match a {
        Agent::Claude => nested_json::snippet(&nested_json::CLAUDE),
    }
}

/// The agent's configuration file. `env` is the only environment read.
pub fn config_path(a: Agent, env: &dyn Fn(&str) -> Option<String>, home: &Path) -> PathBuf {
    let var = |k: &str| env(k).filter(|v| !v.is_empty());
    match a {
        Agent::Claude => var("CLAUDE_CONFIG_DIR")
            .map_or_else(|| home.join(".claude"), PathBuf::from)
            .join("settings.json"),
    }
}

/// How the driver sees the file system (a fake in tests).
pub trait Fs {
    /// `None` is an absent file.
    fn read(&self, p: &Path) -> Result<Option<String>, ReadError>;
    fn exists(&self, p: &Path) -> bool;
    /// The file a symlink points to (`p` itself when it is not one).
    fn resolve(&self, p: &Path) -> PathBuf;
    /// A temp file in the same folder, then a rename. Takes the mode of
    /// `like` when given.
    fn write_atomic(&mut self, p: &Path, text: &str, like: Option<&Path>) -> io::Result<()>;
    /// A copy of `from` with the same permissions (the `.shellx-bak`).
    fn copy_mode_file(&mut self, from: &Path, to: &Path) -> io::Result<()>;
    /// A file, or a folder when it is empty.
    fn remove(&mut self, p: &Path) -> io::Result<()>;
    fn create_dir_all(&mut self, p: &Path) -> io::Result<()>;
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ReadError {
    /// Over 1 MiB.
    TooBig,
    /// Not UTF-8 text.
    NotText,
    Io,
}

/// A question to the person at the terminal.
pub trait Prompt {
    /// Whether there is a terminal to ask on.
    fn available(&mut self) -> bool;
    /// One line typed in answer; `None` is no terminal (or end of input).
    fn ask(&mut self, question: &str) -> Option<String>;
}

#[cfg(test)]
mod tests {
    use super::*;
    use json::{get, parse, Kind};

    const FIXTURES: [&str; 7] = [
        "empty",
        "two_space",
        "four_space",
        "tabs",
        "crlf",
        "user_hooks",
        "env_secret",
    ];

    fn fx(name: &str) -> String {
        let p = format!(
            "{}/tests/fixtures/integrations/{name}.json",
            env!("CARGO_MANIFEST_DIR")
        );
        std::fs::read_to_string(p).unwrap()
    }

    const EVENTS: [(&str, &str); 5] = [
        ("SessionStart", "session-start"),
        ("UserPromptSubmit", "prompt-submit"),
        ("Notification", "notification"),
        ("Stop", "stop"),
        ("SessionEnd", "session-end"),
    ];

    /// Every `command` string under `hooks.<event>`.
    fn commands(text: &str, event: &str) -> Vec<String> {
        let root = parse(text).unwrap();
        let Some(Kind::Arr(groups)) = get(&root, "hooks")
            .and_then(|h| get(h, event))
            .map(|n| n.kind.clone())
        else {
            return vec![];
        };
        let mut out = vec![];
        for g in groups {
            if let Some(Kind::Arr(hs)) = get(&g, "hooks").map(|n| n.kind.clone()) {
                for h in hs {
                    if let Some(Kind::Str(c)) = get(&h, "command").map(|n| n.kind.clone()) {
                        out.push(c);
                    }
                }
            }
        }
        out
    }

    #[test]
    fn fresh_install_creates_the_five_groups() {
        let plan = plan_install(Agent::Claude, None).unwrap();
        assert!(plan.changed && plan.before.is_none());
        assert!(plan.after.ends_with("}\n"));
        for (event, sub) in EVENTS {
            assert_eq!(
                commands(&plan.after, event),
                vec![format!("shellx agent-event claude {sub}")],
                "{event}"
            );
        }
        // The group shape of the Claude Code docs, with the 5 s timeout.
        assert!(plan.after.contains("\"type\": \"command\""));
        assert!(plan.after.contains("\"timeout\": 5"));
        let root = parse(&plan.after).unwrap();
        let Some(Kind::Obj(ev)) = get(&root, "hooks").map(|n| n.kind.clone()) else {
            panic!()
        };
        assert_eq!(ev.len(), 5);
    }

    #[test]
    fn user_hooks_on_the_same_event_survive_byte_for_byte() {
        let original = fx("user_hooks");
        let out = plan_install(Agent::Claude, Some(&original)).unwrap();
        assert!(out.changed);
        assert!(out
            .after
            .contains("\"command\": \"~/bin/my-own-hook --flag\""));
        assert_eq!(
            commands(&out.after, "Stop"),
            vec![
                "~/bin/my-own-hook --flag".to_string(),
                "shellx agent-event claude stop".to_string()
            ]
        );
        let back = plan_uninstall(Agent::Claude, &out.after).unwrap();
        assert!(back.changed);
        assert_eq!(
            back.after, original,
            "install then uninstall is the identity"
        );
    }

    #[test]
    fn install_then_uninstall_is_the_identity_for_every_fixture() {
        for name in FIXTURES {
            let original = fx(name);
            let out = plan_install(Agent::Claude, Some(&original)).unwrap_or_else(|e| {
                panic!("{name}: {e:?}");
            });
            assert!(parse(&out.after).is_ok(), "{name} stays valid");
            let back = plan_uninstall(Agent::Claude, &out.after).unwrap();
            assert_eq!(back.after, original, "{name}");
        }
    }

    #[test]
    fn installing_twice_changes_nothing() {
        for name in FIXTURES {
            let a = plan_install(Agent::Claude, Some(&fx(name))).unwrap();
            let b = plan_install(Agent::Claude, Some(&a.after)).unwrap();
            assert!(!b.changed && b.after == a.after, "{name}");
        }
        let fresh = plan_install(Agent::Claude, None).unwrap();
        let again = plan_install(Agent::Claude, Some(&fresh.after)).unwrap();
        assert!(!again.changed && again.after == fresh.after);
    }

    #[test]
    fn an_older_shellx_command_is_updated_in_place() {
        let old = r#"{
  "hooks": {
    "Stop": [
      { "hooks": [ { "type": "command", "command": "shellx agent-event claude stop --old" } ] }
    ]
  }
}
"#;
        let out = plan_install(Agent::Claude, Some(old)).unwrap();
        assert!(out.changed);
        assert_eq!(
            commands(&out.after, "Stop"),
            vec!["shellx agent-event claude stop".to_string()],
            "replaced, not duplicated"
        );
        assert_eq!(commands(&out.after, "SessionEnd").len(), 1);
        // Only the string's span changed in that group.
        assert!(out
            .after
            .contains("{ \"hooks\": [ { \"type\": \"command\", \"command\": \"shellx agent-event claude stop\" } ] }"));
    }

    #[test]
    fn refuses_comments_wrong_types_and_big_files() {
        let refuse = |t: &str| plan_install(Agent::Claude, Some(t)).unwrap_err();
        assert_eq!(refuse("{ // c\n}"), Refusal::Invalid);
        assert_eq!(refuse("{ /* c */ }"), Refusal::Invalid);
        assert_eq!(refuse(r#"{"a":1,}"#), Refusal::Invalid);
        assert_eq!(refuse("not json"), Refusal::Invalid);
        assert_eq!(refuse(""), Refusal::Invalid);
        assert_eq!(refuse(r#"{"hooks":{},"hooks":{}}"#), Refusal::Invalid);
        assert_eq!(refuse(r#"{"hooks": []}"#), Refusal::WrongType);
        assert_eq!(refuse(r#"{"hooks": {"Stop": {}}}"#), Refusal::WrongType);
        assert_eq!(refuse(r#"{"hooks": {"Stop": "x"}}"#), Refusal::WrongType);
        assert_eq!(refuse("[]"), Refusal::WrongType);
        assert_eq!(refuse("\"x\""), Refusal::WrongType);
        let big = format!("{{\"a\": \"{}\"}}", "x".repeat(1 << 20));
        assert_eq!(refuse(&big), Refusal::TooBig);
        assert!(plan_uninstall(Agent::Claude, "{ // c\n}").is_err());
    }

    #[test]
    fn crlf_tabs_and_a_bom_are_kept() {
        let crlf = plan_install(Agent::Claude, Some(&fx("crlf")))
            .unwrap()
            .after;
        assert!(!crlf.replace("\r\n", "").contains('\n'), "only CRLF breaks");
        let tabs = plan_install(Agent::Claude, Some(&fx("tabs")))
            .unwrap()
            .after;
        assert!(tabs.contains("\n\t\t\"SessionStart\": ["), "{tabs}");
        assert!(!tabs.contains("  \""), "no space indent sneaks in");
        let bom = format!("\u{feff}{}", fx("two_space"));
        let with = plan_install(Agent::Claude, Some(&bom)).unwrap();
        assert!(with.after.starts_with('\u{feff}'));
        assert_eq!(
            plan_uninstall(Agent::Claude, &with.after).unwrap().after,
            bom
        );
    }

    #[test]
    fn uninstall_of_a_file_we_created_leaves_an_empty_object() {
        let made = plan_install(Agent::Claude, None).unwrap();
        let back = plan_uninstall(Agent::Claude, &made.after).unwrap();
        assert!(back.changed);
        assert_eq!(back.after.trim(), "{}");
    }

    #[test]
    fn uninstall_keeps_a_users_command_that_shares_our_group() {
        let t = r#"{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"mine"},{"type":"command","command":"shellx agent-event claude stop","timeout":5}]}]}}"#;
        let back = plan_uninstall(Agent::Claude, t).unwrap();
        assert!(back.changed);
        assert_eq!(commands(&back.after, "Stop"), vec!["mine".to_string()]);
        // A user's own empty array is not ours to remove.
        let t = r#"{"hooks":{"PreToolUse":[],"Stop":[{"hooks":[{"type":"command","command":"shellx agent-event claude stop"}]}]}}"#;
        let back = plan_uninstall(Agent::Claude, t).unwrap();
        assert!(back.after.contains("\"PreToolUse\":[]"), "{}", back.after);
        assert!(!back.after.contains("\"Stop\""));
        // Nothing of ours: unchanged.
        let none = plan_uninstall(Agent::Claude, &fx("user_hooks")).unwrap();
        assert!(!none.changed && none.after == fx("user_hooks"));
    }

    #[test]
    fn installed_means_all_five_are_there() {
        assert!(!installed(Agent::Claude, None));
        assert!(!installed(Agent::Claude, Some(&fx("user_hooks"))));
        assert!(!installed(Agent::Claude, Some("{ // c")));
        let made = plan_install(Agent::Claude, None).unwrap().after;
        assert!(installed(Agent::Claude, Some(&made)));
        let fewer = plan_uninstall(Agent::Claude, &made).unwrap().after;
        assert!(!installed(Agent::Claude, Some(&fewer)));
        let one_missing = made.replace("shellx agent-event claude stop", "other");
        assert!(!installed(Agent::Claude, Some(&one_missing)));
    }

    #[test]
    fn the_config_path_follows_claude_config_dir() {
        let home = Path::new("/h");
        let none = |_: &str| None;
        assert_eq!(
            config_path(Agent::Claude, &none, home),
            PathBuf::from("/h/.claude/settings.json")
        );
        let set = |k: &str| (k == "CLAUDE_CONFIG_DIR").then(|| "/cfg".to_string());
        assert_eq!(
            config_path(Agent::Claude, &set, home),
            PathBuf::from("/cfg/settings.json")
        );
        let empty = |k: &str| (k == "CLAUDE_CONFIG_DIR").then(String::new);
        assert_eq!(
            config_path(Agent::Claude, &empty, home),
            PathBuf::from("/h/.claude/settings.json")
        );
    }

    #[test]
    fn names_round_trip_and_snippet_is_the_group_json() {
        for a in Agent::ALL {
            assert_eq!(Agent::from_name(a.name()), Some(a));
        }
        assert_eq!(Agent::from_name("Claude"), None);
        let s = snippet(Agent::Claude);
        assert!(parse(&s).is_ok());
        assert!(s.contains("shellx agent-event claude session-end"));
    }

    #[test]
    fn the_hook_commands_have_no_shell_syntax() {
        let all = plan_install(Agent::Claude, None).unwrap().after;
        for (event, _) in EVENTS {
            for c in commands(&all, event) {
                assert!(
                    c.chars()
                        .all(|ch| ch.is_ascii_alphanumeric() || ch == ' ' || ch == '-'),
                    "{c}"
                );
            }
        }
    }
}
