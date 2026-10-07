#![cfg(unix)]

mod common;

use common::BIN;
use std::os::unix::fs::PermissionsExt;
use std::process::Command;

const ZSH_BLOCK: &str = include_str!("../shell/block.zsh");
const BASH_BLOCK: &str = include_str!("../shell/block.bash");

fn run(home: &std::path::Path) -> std::process::Output {
    Command::new(BIN)
        .arg("uninstall")
        .env("HOME", home)
        .output()
        .unwrap()
}

#[test]
fn uninstall_cleans_every_file_and_the_shellx_directories() {
    let home = common::temp_dir("uninstall");
    let zshrc = format!("# mine\n{ZSH_BLOCK}\nexport A=1\n");
    let bashrc = format!("{BASH_BLOCK}\nalias l=ls\r\n");
    std::fs::write(home.join(".zshrc"), &zshrc).unwrap();
    std::fs::write(home.join(".bashrc"), &bashrc).unwrap();
    let shellx = home.join("Library/Application Support/ShellX");
    for d in ["bin", "term", "cli"] {
        std::fs::create_dir_all(shellx.join(d)).unwrap();
    }
    std::fs::write(shellx.join("bin/shellx-term"), "x").unwrap();
    // A7 D7: the command-line copy goes too.
    std::fs::write(shellx.join("cli/shellx"), "x").unwrap();

    let out = run(&home);
    assert!(out.status.success(), "{out:?}");
    let stdout = String::from_utf8_lossy(&out.stdout);
    assert!(
        stdout.contains(".zshrc") && stdout.contains("Deleted"),
        "{stdout}"
    );
    let zshrc_after = std::fs::read_to_string(home.join(".zshrc")).unwrap();
    assert!(!zshrc_after.contains("ShellX"), "{zshrc_after}");
    assert!(zshrc_after.starts_with("# mine\n") && zshrc_after.ends_with("export A=1\n"));
    let bashrc_after = std::fs::read_to_string(home.join(".bashrc")).unwrap();
    assert!(!bashrc_after.contains("ShellX") && bashrc_after.ends_with("alias l=ls\r\n"));
    assert!(!home.join(".bash_profile").exists());
    assert!(!shellx.join("bin").exists() && !shellx.join("term").exists());
    assert!(!shellx.join("cli").exists());
    assert!(stdout.contains("ShellX/cli"), "{stdout}");

    let again = run(&home);
    assert!(again.status.success());
    assert!(String::from_utf8_lossy(&again.stdout).contains("nothing to remove"));
}

#[test]
fn uninstall_cleans_a_latin1_profile() {
    let home = common::temp_dir("uninstall-latin1");
    let mut content = b"# caf\xe9\n".to_vec();
    content.extend_from_slice(ZSH_BLOCK.as_bytes());
    std::fs::write(home.join(".zshrc"), &content).unwrap();
    let out = run(&home);
    assert!(out.status.success(), "{out:?}");
    assert_eq!(std::fs::read(home.join(".zshrc")).unwrap(), b"# caf\xe9\n");
}

#[test]
fn a_file_that_cannot_be_updated_fails_the_run_and_keeps_bin() {
    // Read-only directory: neither a temp file nor an in-place write works
    // for root, so skip when running as root.
    let home = common::temp_dir("uninstall-fail");
    let file = home.join(".zshrc");
    std::fs::write(&file, ZSH_BLOCK).unwrap();
    std::fs::set_permissions(&file, std::fs::Permissions::from_mode(0o444)).unwrap();
    std::fs::set_permissions(&*home, std::fs::Permissions::from_mode(0o555)).unwrap();
    let writable = std::fs::OpenOptions::new().write(true).open(&file).is_ok();
    let bin = home.join("Library/Application Support/ShellX/bin");
    // bin lives under the read-only home, so create it first.
    std::fs::set_permissions(&*home, std::fs::Permissions::from_mode(0o755)).unwrap();
    std::fs::create_dir_all(&bin).unwrap();
    std::fs::set_permissions(&*home, std::fs::Permissions::from_mode(0o555)).unwrap();
    let out = run(&home);
    std::fs::set_permissions(&*home, std::fs::Permissions::from_mode(0o755)).unwrap();
    if !writable {
        assert_eq!(out.status.code(), Some(1), "{out:?}");
        let stderr = String::from_utf8_lossy(&out.stderr);
        assert!(
            stderr.contains("Could not update") && stderr.contains("Kept"),
            "{stderr}"
        );
        assert!(bin.exists());
    }
}

#[test]
fn an_unterminated_block_exits_non_zero_and_is_reported() {
    let home = common::temp_dir("uninstall-skip");
    std::fs::write(home.join(".bashrc"), "# >>> ShellX >>>\nfoo\n").unwrap();
    let out = run(&home);
    assert_eq!(out.status.code(), Some(1), "{out:?}");
    assert!(String::from_utf8_lossy(&out.stderr).contains("Skipped"));
}

#[test]
fn uninstall_without_home_fails_with_a_message() {
    let out = Command::new(BIN)
        .arg("uninstall")
        .env_remove("HOME")
        .output()
        .unwrap();
    assert!(!out.status.success());
    assert!(String::from_utf8_lossy(&out.stderr).contains("HOME"));
}
