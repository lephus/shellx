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
