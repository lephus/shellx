//! Gemini CLI (A12 D6): the same nested hook shape as Claude Code in
//! `~/.gemini/settings.json`, but `timeout` is in milliseconds and the
//! events have Gemini's names (`BeforeAgent` is a prompt being submitted,
//! `AfterAgent` the end of a turn).

use super::nested_json::NestedSpec;

pub const GEMINI: NestedSpec = NestedSpec {
    agent: "gemini",
    timeout: 5000,
    events: &[
        ("SessionStart", "session-start"),
        ("BeforeAgent", "prompt-submit"),
        ("AfterAgent", "stop"),
        ("Notification", "notification"),
        ("SessionEnd", "session-end"),
    ],
};
