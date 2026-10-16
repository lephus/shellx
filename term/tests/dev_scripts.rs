#![cfg(unix)]

mod common;

use std::os::unix::fs::symlink;
use std::path::Path;
use std::process::Command;

const BLOCK_SCRIPT: &str = concat!(env!("CARGO_MANIFEST_DIR"), "/scripts/dev-block.sh");

fn block(args: &[&str]) -> String {
    let out = Command::new("/bin/bash")
        .arg(BLOCK_SCRIPT)
        .args(args)
        .output()
        .unwrap();
    assert!(
        out.status.success(),
        "{args:?}: {}",
        String::from_utf8_lossy(&out.stderr)
    );
    String::from_utf8_lossy(&out.stdout).trim().to_string()
}

fn read(path: &Path) -> String {
    std::fs::read_to_string(path).unwrap()
}

#[test]
fn on_is_idempotent_and_off_restores_the_file_exactly() {
    let dir = common::temp_dir("dev-block");
    let rc = dir.join(".zshrc");
    std::fs::write(&rc, "export A=1\n# user stuff\n").unwrap();
    let rc_s = rc.to_str().unwrap();

    block(&["on", rc_s]);
    block(&["on", rc_s]);
    let content = read(&rc);
    assert_eq!(content.matches("# >>> ShellX >>>").count(), 1);
    assert!(content.starts_with("# >>> ShellX >>>\n"));
    assert!(content.ends_with("export A=1\n# user stuff\n"));
    assert_eq!(block(&["status", rc_s]), "on");
    assert_eq!(
        read(&dir.join(".zshrc.shellx-backup")),
        "export A=1\n# user stuff\n"
    );

    block(&["off", rc_s]);
    block(&["off", rc_s]);
    assert_eq!(read(&rc), "export A=1\n# user stuff\n");
    assert_eq!(block(&["status", rc_s]), "off");
}

#[test]
fn a_missing_file_is_created_and_a_bash_file_gets_the_bash_block() {
    let dir = common::temp_dir("dev-block-new");
    let rc = dir.join(".bashrc");
    block(&["on", rc.to_str().unwrap()]);
    assert!(read(&rc).contains("BASH_EXECUTION_STRING"));
    assert!(!dir.join(".bashrc.shellx-backup").exists());
}

#[test]
fn a_symlinked_file_stays_a_symlink() {
    let dir = common::temp_dir("dev-block-link");
    let real = dir.join("dotfiles-zshrc");
    std::fs::write(&real, "export B=2\n").unwrap();
    let link = dir.join(".zshrc");
    symlink(&real, &link).unwrap();
    block(&["on", link.to_str().unwrap()]);
    assert!(std::fs::symlink_metadata(&link)
        .unwrap()
        .file_type()
        .is_symlink());
    assert!(read(&real).starts_with("# >>> ShellX >>>"));
    block(&["off", link.to_str().unwrap()]);
    assert!(std::fs::symlink_metadata(&link)
        .unwrap()
        .file_type()
        .is_symlink());
    assert_eq!(read(&real), "export B=2\n");
}

fn block_fails(args: &[&str]) -> String {
    let out = Command::new("/bin/bash")
        .arg(BLOCK_SCRIPT)
        .args(args)
        .output()
        .unwrap();
    assert!(!out.status.success(), "{args:?} should have failed");
    String::from_utf8_lossy(&out.stderr).to_string()
}

#[test]
fn a_block_without_its_end_marker_is_refused_and_left_untouched() {
    let dir = common::temp_dir("dev-block-broken");
    let rc = dir.join(".zshrc");
    let original = "keep1\n# >>> ShellX >>>\nkeep2\nkeep3\n";
    std::fs::write(&rc, original).unwrap();
    let rc_s = rc.to_str().unwrap();
    assert!(block_fails(&["off", rc_s]).contains("damaged"));
    assert_eq!(read(&rc), original);
    assert!(block_fails(&["on", rc_s]).contains("damaged"));
    assert_eq!(read(&rc), original);
    assert_eq!(block(&["status", rc_s]), "broken");
    assert!(!dir.join(".zshrc.shellx-backup").exists());
}

#[test]
fn out_of_order_markers_are_refused() {
    let dir = common::temp_dir("dev-block-order");
    let rc = dir.join(".zshrc");
    let original = "# <<< ShellX <<<\nx\n# >>> ShellX >>>\ny\n";
    std::fs::write(&rc, original).unwrap();
    assert!(block_fails(&["off", rc.to_str().unwrap()]).contains("damaged"));
    assert_eq!(read(&rc), original);
}

fn round_trip(name: &str, original: &[u8]) {
    let dir = common::temp_dir(name);
    let rc = dir.join(".zshrc");
    std::fs::write(&rc, original).unwrap();
    let rc_s = rc.to_str().unwrap();
    block(&["on", rc_s]);
    assert_eq!(block(&["status", rc_s]), "on");
    block(&["off", rc_s]);
    assert_eq!(std::fs::read(&rc).unwrap(), original);
}

#[test]
fn a_file_without_a_trailing_newline_round_trips_byte_exactly() {
    round_trip("dev-block-nonl", b"a\nb");
}

#[test]
fn a_crlf_file_round_trips_byte_exactly() {
    round_trip("dev-block-crlf", b"export A=1\r\n# x\r\n");
}

#[test]
fn an_empty_file_round_trips_byte_exactly() {
    round_trip("dev-block-empty", b"");
}
