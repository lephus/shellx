//! OpenCode (A12 D6): a plugin file that ShellX owns outright,
//! `…/opencode/plugins/shellx-agent.js`. Its first line is the marker; the
//! body holds no user data, starts `shellx` without a shell and ignores
//! every error, so a missing `shellx` or a closed ShellX never reaches
//! OpenCode's own output.

use super::{Plan, Refusal};

/// What marks the file as ShellX's: its first line starts with this.
const MARKER: &str = "// shellx-agent-integration";
/// D26: a file over this is left alone.
const MAX_BYTES: usize = 1 << 20;

/// The plugin as shipped. Spawns `shellx` without a shell, sends only the
/// event and OpenCode's own session id (at most 128 characters), does
/// nothing outside a ShellX pane and swallows every error.
pub const PLUGIN: &str = r#"// shellx-agent-integration v1 (managed by "shellx integrations"; remove with "shellx integrations uninstall opencode")
import { execFile } from "node:child_process";
const send = (event, session) => {
  if (!process.env.SHELLX_PANE_ID) return;
  const args = ["agent-event", "opencode", event];
  if (typeof session === "string" && session) args.push("--session", session.slice(0, 128));
  try { execFile("shellx", args, { timeout: 3000, windowsHide: true }, () => {}); } catch (_) {}
};
export const ShellxAgent = async () => ({
  event: async ({ event }) => {
    const p = event?.properties ?? {};
    switch (event?.type) {
      case "session.created": return send("session-start", p.info?.id);
      case "session.status": return p.status?.type === "busy" ? send("running", p.sessionID) : undefined;
      case "session.idle": return send("idle", p.sessionID);
      case "permission.asked":
      case "permission.updated": return send("needs-input", p.sessionID);
      case "session.deleted": return send("session-end", p.info?.id);
    }
  },
});
"#;

/// Every text ShellX has shipped (uninstall deletes only one of these).
const SHIPPED: [&str; 1] = [PLUGIN];

fn is_ours(text: &str) -> bool {
    text.starts_with(MARKER)
}

fn done(before: Option<&str>, after: String) -> Plan {
    let changed = before != Some(after.as_str());
    Plan {
        before: before.map(String::from),
        after,
        changed,
    }
}

/// A file of ours that is not a text ShellX shipped was edited: it is
/// replaced only with `force`.
pub fn install(current: Option<&str>, force: bool) -> Result<Plan, Refusal> {
    match current {
        None => Ok(done(None, PLUGIN.to_string())),
        Some(t) if t.len() > MAX_BYTES => Err(Refusal::TooBig),
        Some(t) if is_ours(t) && !force && !SHIPPED.contains(&t) => Err(Refusal::Edited),
        Some(t) if is_ours(t) => Ok(done(current, PLUGIN.to_string())),
        Some(_) => Err(Refusal::Foreign("plugin file")),
    }
}

/// The plan removes the whole file: `after` is empty.
pub fn uninstall(current: &str) -> Result<Plan, Refusal> {
    if current.len() > MAX_BYTES {
        return Err(Refusal::TooBig);
    }
    if !is_ours(current) {
        return Ok(done(Some(current), current.to_string()));
    }
    if SHIPPED.contains(&current) {
        Ok(done(Some(current), String::new()))
    } else {
        Err(Refusal::Edited)
    }
}

/// A plugin of ShellX's is there (an older text counts: it still works).
pub fn installed(current: Option<&str>) -> bool {
    current.is_some_and(is_ours)
}

pub fn snippet() -> String {
    PLUGIN.to_string()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_plugin_is_marked_and_does_what_the_spec_says() {
        assert!(PLUGIN.starts_with(
            "// shellx-agent-integration v1 (managed by \"shellx integrations\"; remove with \"shellx integrations uninstall opencode\")\n"
        ));
        assert!(PLUGIN.ends_with("\n"));
        // No shell: execFile with an argument list, never a command line.
        assert!(PLUGIN.contains("execFile(\"shellx\", args"));
        assert!(
            !PLUGIN.contains("exec(") && !PLUGIN.contains("spawn(") && !PLUGIN.contains("shell:")
        );
        // Only inside a ShellX pane; errors are ignored; the id is capped.
        assert!(PLUGIN.contains("if (!process.env.SHELLX_PANE_ID) return;"));
        assert!(PLUGIN.contains("catch (_) {}"));
        assert!(PLUGIN.contains("session.slice(0, 128)"));
        for e in [
            "session.created",
            "session.status",
            "session.idle",
            "permission.asked",
            "permission.updated",
            "session.deleted",
        ] {
            assert!(PLUGIN.contains(e), "{e}");
        }
        for sub in [
            "session-start",
            "running",
            "idle",
            "needs-input",
            "session-end",
        ] {
            assert!(PLUGIN.contains(&format!("send(\"{sub}\"")), "{sub}");
        }
        // Nothing of the user's: no path, no prompt, no message.
        assert!(
            !PLUGIN.contains("--message")
                && !PLUGIN.contains("directory")
                && !PLUGIN.contains("cwd")
        );
        assert!(PLUGIN.is_ascii());
    }

    #[test]
    fn install_creates_the_file_and_is_idempotent() {
        let p = install(None, false).unwrap();
        assert!(p.changed && p.before.is_none() && p.after == PLUGIN);
        let again = install(Some(PLUGIN), false).unwrap();
        assert!(!again.changed && again.after == PLUGIN);
        assert!(installed(Some(PLUGIN)));
        assert!(!installed(None));
        assert!(!installed(Some("export const Mine = async () => ({})\n")));
    }

    #[test]
    fn an_older_file_of_ours_is_replaced_and_a_foreign_one_never() {
        let old = "// shellx-agent-integration v0 (managed by \"shellx integrations\")\nexport const Old = 1\n";
        // Unknown text with our marker was edited (or is from a version we
        // cannot vouch for): not replaced silently.
        assert_eq!(install(Some(old), false), Err(Refusal::Edited));
        let p = install(Some(old), true).unwrap();
        assert!(p.changed && p.after == PLUGIN);
        assert!(installed(Some(old)), "status: a plugin of ours is there");
        let edited = format!("{PLUGIN}// tweak\n");
        assert_eq!(install(Some(&edited), false), Err(Refusal::Edited));
        assert!(install(Some(&edited), true).unwrap().changed);
        assert!(!install(Some(PLUGIN), false).unwrap().changed);
        for foreign in [
            "export const Mine = async () => ({})\n",
            "",
            "\n// shellx-agent-integration v1\n",
            "/* // shellx-agent-integration */\n",
            " // shellx-agent-integration v1\n",
        ] {
            assert_eq!(
                install(Some(foreign), true),
                Err(Refusal::Foreign("plugin file")),
                "{foreign:?}"
            );
        }
        let big = format!("{}{}", PLUGIN, "x".repeat(1 << 20));
        assert_eq!(install(Some(&big), false), Err(Refusal::TooBig));
    }

    #[test]
    fn uninstall_deletes_only_a_file_we_shipped_unedited() {
        let p = uninstall(PLUGIN).unwrap();
        assert!(p.changed && p.after.is_empty());
        let edited = format!("{PLUGIN}// my tweak\n");
        assert_eq!(uninstall(&edited), Err(Refusal::Edited));
        let older = "// shellx-agent-integration v0 (managed by \"shellx integrations\")\nexport const Old = 1\n";
        assert_eq!(
            uninstall(older),
            Err(Refusal::Edited),
            "an unknown body is kept"
        );
        // Not ours: nothing to remove.
        let theirs = "export const Mine = async () => ({})\n";
        let p = uninstall(theirs).unwrap();
        assert!(!p.changed && p.after == theirs);
    }

    #[test]
    fn the_snippet_is_the_plugin() {
        assert_eq!(snippet(), PLUGIN);
    }
}
