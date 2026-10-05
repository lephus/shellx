#![cfg(unix)]

mod common;

use common::BIN;
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
fn uninstall_cleans_every_file_and_the_bin_directory() {
    let home = common::temp_dir("uninstall");
    let zshrc = format!("# mine\n{ZSH_BLOCK}\nexport A=1\n");
    let bashrc = format!("{BASH_BLOCK}\nalias l=ls\r\n");
    std::fs::write(home.join(".zshrc"), &zshrc).unwrap();
    std::fs::write(home.join(".bashrc"), &bashrc).unwrap();
    let bin = home.join("Library/Application Support/ShellX/bin");
    std::fs::create_dir_all(&bin).unwrap();
    std::fs::write(bin.join("shellx-term"), "x").unwrap();

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
    assert!(!bin.exists());

    // Second run: nothing left, still success.
    let again = run(&home);
    assert!(again.status.success());
    assert!(String::from_utf8_lossy(&again.stdout).contains("nothing to remove"));
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
