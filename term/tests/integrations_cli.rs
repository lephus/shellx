//! `shellx integrations …` through the real binary, in a temporary HOME.
//! The user's real agent files are never read or written: the environment
//! is cleared and HOME (and USERPROFILE) point into a temp folder.
#![cfg(unix)]

use std::os::unix::fs::PermissionsExt;
use std::os::unix::process::CommandExt;
use std::path::{Path, PathBuf};
use std::process::{Command, Output};

fn bin() -> PathBuf {
    PathBuf::from(env!("CARGO_BIN_EXE_shellx-term"))
}

fn home(name: &str) -> PathBuf {
    let d = std::env::temp_dir().join(format!("shellx-integ-{}-{name}", std::process::id()));
    let _ = std::fs::remove_dir_all(&d);
    std::fs::create_dir_all(&d).unwrap();
    d
}

/// `shellx integrations ARGS` with a cleared environment; `no_tty` also
/// leaves the controlling terminal (so `/dev/tty` cannot be opened).
fn run(home: &Path, args: &[&str], no_tty: bool) -> Output {
    let mut c = Command::new(bin());
    c.arg("cli")
        .arg("integrations")
        .args(args)
        .env_clear()
        .env("HOME", home)
        .env("USERPROFILE", home)
        .env("PATH", "/usr/bin:/bin")
        .stdin(std::process::Stdio::null());
    if no_tty {
        // SAFETY: setsid between fork and exec touches no Rust state.
        unsafe {
            c.pre_exec(|| {
                libc::setsid();
                Ok(())
            });
        }
    }
    c.output().unwrap()
}

fn text(b: &[u8]) -> String {
    String::from_utf8_lossy(b).into_owned()
}

const ORIGINAL: &str = "{\n  \"model\": \"sonnet\",\n  \"env\": {\n    \"ANTHROPIC_API_KEY\": \"sk-ant-FAKE\"\n  }\n}\n";

fn seed(home: &Path) -> PathBuf {
    let dir = home.join(".claude");
    std::fs::create_dir_all(&dir).unwrap();
    let f = dir.join("settings.json");
    std::fs::write(&f, ORIGINAL).unwrap();
    std::fs::set_permissions(&f, std::fs::Permissions::from_mode(0o600)).unwrap();
    f
}

#[test]
fn install_then_uninstall_restores_the_exact_bytes() {
    let h = home("roundtrip");
    let f = seed(&h);
    let out = run(&h, &["install", "claude", "--yes"], true);
    assert_eq!(out.status.code(), Some(0), "{}", text(&out.stderr));
    let after = std::fs::read_to_string(&f).unwrap();
    assert!(after.contains("shellx agent-event claude session-start"));
    assert!(
        !text(&out.stdout).contains("sk-ant-FAKE"),
        "{}",
        text(&out.stdout)
    );
    let bak = h.join(".claude/settings.json.shellx-bak");
    assert_eq!(std::fs::read_to_string(&bak).unwrap(), ORIGINAL);
    assert_eq!(
        std::fs::metadata(&bak).unwrap().permissions().mode() & 0o777,
        0o600
    );
    assert_eq!(
        std::fs::metadata(&f).unwrap().permissions().mode() & 0o777,
        0o600
    );
    // Twice: nothing happens.
    let again = run(&h, &["install", "claude", "--yes"], true);
    assert!(text(&again.stdout).contains("Already installed."));
    assert_eq!(std::fs::read_to_string(&f).unwrap(), after);
    let out = run(&h, &["uninstall", "claude", "--yes"], true);
    assert_eq!(out.status.code(), Some(0), "{}", text(&out.stderr));
    assert_eq!(std::fs::read_to_string(&f).unwrap(), ORIGINAL);
    let _ = std::fs::remove_dir_all(&h);
}

#[test]
fn nothing_is_written_without_consent() {
    let h = home("consent");
    let f = seed(&h);
    let out = run(&h, &["install", "claude"], true);
    assert_eq!(out.status.code(), Some(2));
    assert!(text(&out.stderr).contains("needs --yes when not interactive"));
    assert_eq!(std::fs::read_to_string(&f).unwrap(), ORIGINAL);
    let out = run(&h, &["install", "claude", "--dry-run"], true);
    assert_eq!(out.status.code(), Some(0));
    let shown = text(&out.stdout);
    assert!(
        shown.contains("--- ~/.claude/settings.json") && shown.contains("+    \"SessionStart\"")
    );
    assert!(!shown.contains("sk-ant-FAKE"), "{shown}");
    assert_eq!(std::fs::read_to_string(&f).unwrap(), ORIGINAL);
    assert!(!h.join(".claude/settings.json.shellx-bak").exists());
    let _ = std::fs::remove_dir_all(&h);
}

#[test]
fn a_symlinked_settings_file_keeps_its_link() {
    let h = home("symlink");
    let dotfiles = h.join("dotfiles");
    std::fs::create_dir_all(&dotfiles).unwrap();
    std::fs::write(dotfiles.join("settings.json"), ORIGINAL).unwrap();
    std::fs::create_dir_all(h.join(".claude")).unwrap();
    let link = h.join(".claude/settings.json");
    std::os::unix::fs::symlink(dotfiles.join("settings.json"), &link).unwrap();
    let out = run(&h, &["install", "claude", "--yes"], true);
    assert_eq!(out.status.code(), Some(0), "{}", text(&out.stderr));
    assert!(std::fs::symlink_metadata(&link)
        .unwrap()
        .file_type()
        .is_symlink());
    assert!(std::fs::read_to_string(dotfiles.join("settings.json"))
        .unwrap()
        .contains("agent-event"));
    assert_eq!(
        std::fs::read_to_string(dotfiles.join("settings.json.shellx-bak")).unwrap(),
        ORIGINAL
    );
    let _ = std::fs::remove_dir_all(&h);
}

#[test]
fn a_file_with_comments_is_refused_untouched() {
    let h = home("refuse");
    let dir = h.join(".claude");
    std::fs::create_dir_all(&dir).unwrap();
    let f = dir.join("settings.json");
    std::fs::write(&f, "{ // mine\n}\n").unwrap();
    let out = run(&h, &["install", "claude", "--yes"], true);
    assert_eq!(out.status.code(), Some(1));
    assert!(
        text(&out.stderr).contains("refusing:"),
        "{}",
        text(&out.stderr)
    );
    assert_eq!(std::fs::read_to_string(&f).unwrap(), "{ // mine\n}\n");
    let _ = std::fs::remove_dir_all(&h);
}

#[test]
fn a_new_file_is_marked_and_uninstall_removes_it_and_the_folder() {
    let h = home("created");
    let out = run(&h, &["install", "claude", "--yes"], true);
    assert_eq!(out.status.code(), Some(0), "{}", text(&out.stderr));
    assert!(h.join(".claude/settings.json").exists());
    assert!(h.join(".claude/settings.json.shellx-created").exists());
    let out = run(&h, &["uninstall", "claude", "--yes"], true);
    assert_eq!(out.status.code(), Some(0), "{}", text(&out.stderr));
    assert!(!h.join(".claude").exists());
    let _ = std::fs::remove_dir_all(&h);
}

#[test]
fn status_json_has_no_file_content_and_claude_config_dir_is_followed() {
    let h = home("status");
    seed(&h);
    let out = run(&h, &["status", "claude", "--json"], true);
    let j = text(&out.stdout);
    assert_eq!(
        j,
        "{\"agents\":[{\"agent\":\"claude\",\"installed\":false,\"path\":\"~/.claude/settings.json\",\"found\":false}]}\n"
    );
    let mut c = Command::new(bin());
    c.args(["cli", "integrations", "install", "claude", "--yes"])
        .env_clear()
        .env("HOME", &h)
        .env("PATH", "/usr/bin:/bin")
        .env("CLAUDE_CONFIG_DIR", h.join("elsewhere"))
        .stdin(std::process::Stdio::null());
    assert_eq!(c.output().unwrap().status.code(), Some(0));
    assert!(h.join("elsewhere/settings.json").exists());
    assert_eq!(
        std::fs::read_to_string(h.join(".claude/settings.json")).unwrap(),
        ORIGINAL
    );
    let _ = std::fs::remove_dir_all(&h);
}

#[test]
fn opencode_gets_a_plugin_file_and_uninstall_removes_it_and_the_folders_made() {
    let h = home("opencode");
    let out = run(&h, &["install", "opencode", "--yes"], true);
    assert_eq!(out.status.code(), Some(0), "{}", text(&out.stderr));
    let plugin = h.join(".config/opencode/plugins/shellx-agent.js");
    let body = std::fs::read_to_string(&plugin).unwrap();
    assert!(body.starts_with("// shellx-agent-integration v1"));
    let again = run(&h, &["install", "opencode", "--yes"], true);
    assert!(text(&again.stdout).contains("Already installed."));
    // A plugin file of the user's is never replaced.
    std::fs::write(&plugin, "export const Mine = 1\n").unwrap();
    let out = run(&h, &["install", "opencode", "--yes"], true);
    assert_eq!(out.status.code(), Some(1));
    assert_eq!(
        std::fs::read_to_string(&plugin).unwrap(),
        "export const Mine = 1\n"
    );
    std::fs::write(&plugin, &body).unwrap();
    let out = run(&h, &["uninstall", "opencode", "--yes"], true);
    assert_eq!(out.status.code(), Some(0), "{}", text(&out.stderr));
    assert!(!plugin.exists() && !h.join(".config").exists());
    assert!(h.exists());
    let _ = std::fs::remove_dir_all(&h);
}

#[test]
fn codex_refuses_a_users_notify_and_installs_into_a_clean_file() {
    let h = home("codex");
    let dir = h.join(".codex");
    std::fs::create_dir_all(&dir).unwrap();
    let f = dir.join("config.toml");
    std::fs::write(&f, "notify = [\"mine\"]\n").unwrap();
    let out = run(&h, &["install", "codex", "--yes"], true);
    assert_eq!(out.status.code(), Some(1));
    assert!(text(&out.stderr).contains("\"notify\" is already set in config.toml"));
    assert_eq!(
        std::fs::read_to_string(&f).unwrap(),
        "notify = [\"mine\"]\n"
    );
    std::fs::write(&f, "model = \"o3\"\n").unwrap();
    assert_eq!(
        run(&h, &["install", "codex", "--yes"], true).status.code(),
        Some(0)
    );
    assert!(std::fs::read_to_string(&f)
        .unwrap()
        .contains("\"agent-event\""));
    assert_eq!(
        run(&h, &["uninstall", "codex", "--yes"], true)
            .status
            .code(),
        Some(0)
    );
    assert_eq!(std::fs::read_to_string(&f).unwrap(), "model = \"o3\"\n");
    let _ = std::fs::remove_dir_all(&h);
}
