#![cfg(unix)]
use std::process::Command;

fn bin() -> std::path::PathBuf {
    std::path::PathBuf::from(env!("CARGO_BIN_EXE_shellx-term"))
}

fn shellx_link() -> std::path::PathBuf {
    let dir = std::env::temp_dir().join(format!("shellx-dispatch-{}", std::process::id()));
    std::fs::create_dir_all(&dir).unwrap();
    let link = dir.join("shellx");
    let _ = std::fs::remove_file(&link);
    std::os::unix::fs::symlink(bin(), &link).unwrap();
    link
}

#[test]
fn shellx_name_is_the_cli_and_never_starts_a_shell() {
    let out = Command::new(shellx_link()).arg("bogus").output().unwrap();
    assert_eq!(out.status.code(), Some(2));
    assert!(String::from_utf8_lossy(&out.stderr).contains("unknown command"));
    let v = Command::new(shellx_link())
        .arg("--version")
        .output()
        .unwrap();
    assert!(String::from_utf8_lossy(&v.stdout).starts_with("shellx "));
}

#[test]
fn shellx_term_cli_subcommand_and_old_paths_unchanged() {
    let out = Command::new(bin()).args(["cli", "help"]).output().unwrap();
    assert_eq!(out.status.code(), Some(0));
    assert!(String::from_utf8_lossy(&out.stdout).contains("Usage: shellx"));
    let v = Command::new(bin()).arg("--version").output().unwrap();
    assert!(String::from_utf8_lossy(&v.stdout).starts_with("shellx-term "));
}

#[test]
#[ignore = "enabled in Task 10"]
fn not_running_is_exit_3() {
    let out = Command::new(shellx_link())
        .arg("ls")
        .env("SHELLX_ENDPOINT", "/nonexistent/endpoint")
        .output()
        .unwrap();
    assert_eq!(out.status.code(), Some(3));
    assert!(String::from_utf8_lossy(&out.stderr).contains("ShellX is not running"));
}
