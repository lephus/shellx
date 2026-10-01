mod common;

use common::{Harness, BIN};
use std::process::{Command, Stdio};
use std::time::Duration;

const T: Duration = Duration::from_secs(5);

#[test]
fn version_prints_the_crate_version() {
    let out = Command::new(BIN).arg("--version").output().expect("run");
    assert!(out.status.success());
    assert_eq!(
        String::from_utf8_lossy(&out.stdout).trim(),
        format!("shellx-term {}", env!("CARGO_PKG_VERSION"))
    );
}

#[test]
fn bad_arguments_still_give_the_user_a_shell() {
    let mut h = Harness::spawn(BIN, &["bogus"], &[("SHELL", "/bin/sh")], 80, 24);
    h.expect("shellx-term: unknown arguments; starting a plain shell", T);
    h.send("echo m=$SHELLX_TERM\r");
    h.expect("m=0", T);
    h.send("exit 4\r");
    assert_eq!(h.wait_exit(T), 4);
}

#[test]
fn a_missing_shell_falls_back_to_the_shell_variable() {
    let mut h = Harness::spawn(
        BIN,
        &["wrap", "--", "/nonexistent/zsh"],
        &[("SHELL", "/bin/sh")],
        80,
        24,
    );
    h.send("echo m=$SHELLX_TERM\r");
    h.expect("m=0", T);
    h.send("exit 6\r");
    assert_eq!(h.wait_exit(T), 6);
}

#[test]
fn without_a_terminal_it_runs_the_shell_directly_and_does_not_hang() {
    let mut child = Command::new(BIN)
        .args(["wrap", "--", "/bin/sh"])
        .env("SHELL", "/bin/sh")
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .expect("spawn");
    let status = common::wait_with_timeout(&mut child, T);
    assert_eq!(status.code(), Some(0));
}

// stdout is a pipe whose reader is gone: every write fails (EPIPE).
#[test]
fn version_with_a_failing_stdout_does_not_start_a_shell() {
    use std::os::unix::io::FromRawFd;
    let mut fds = [0i32; 2];
    assert_eq!(unsafe { libc::pipe(fds.as_mut_ptr()) }, 0);
    unsafe { libc::close(fds[0]) };
    let broken = unsafe { std::fs::File::from_raw_fd(fds[1]) };
    let out = Command::new(BIN)
        .arg("--version")
        .env("SHELL", "/bin/sh")
        .stdin(Stdio::null())
        .stdout(Stdio::from(broken))
        .output()
        .expect("run");
    let stderr = String::from_utf8_lossy(&out.stderr);
    assert!(
        !stderr.contains("plain shell"),
        "--version fell back to a shell: {stderr:?}"
    );
}
