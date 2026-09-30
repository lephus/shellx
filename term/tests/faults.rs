#![cfg(feature = "test-hooks")]

mod common;

use common::Harness;
use std::time::Duration;

const T: Duration = Duration::from_secs(5);

fn plain_shell_after_fault(fault: &str) {
    let mut h = Harness::wrap_sh(&[("SHELLX_TERM_FAULT", fault), ("SHELL", "/bin/sh")]);
    h.expect("could not share this terminal", T);
    h.send("echo m=$SHELLX_TERM\r");
    h.expect("m=0", T);
    h.send("exit 5\r");
    assert_eq!(h.wait_exit(T), 5);
}

#[test]
fn when_the_pty_cannot_open_the_user_gets_a_plain_shell() {
    plain_shell_after_fault("openpty");
}

#[test]
fn when_the_shell_cannot_start_in_the_pty_the_user_gets_a_plain_shell() {
    plain_shell_after_fault("spawn");
}
