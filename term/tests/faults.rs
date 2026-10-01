#![cfg(feature = "test-hooks")]

mod common;

use common::Harness;
use std::time::Duration;

const T: Duration = Duration::from_secs(5);

fn plain_shell_after_fault(fault: &str) {
    let mut h = Harness::wrap_sh(&[("SHELLX_TERM_FAULT", fault), ("SHELL", "/bin/sh")]);
    h.expect("could not share this terminal", T);
    h.send("[ \"$SHELLX_TERM\" = \"$(tty)\" ] && echo m=own''-tty\r");
    h.expect("m=own-tty", T);
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

#[test]
fn a_crash_restores_the_window_and_leaves_a_plain_shell() {
    let dir = common::temp_dir("modes-panic");
    let d = dir.display();
    let bin = common::BIN;
    // Non-interactive outer shell: an interactive one would restore the modes itself.
    let script = format!(
        "stty -g > {d}/before; echo rea''dy; SHELLX_TERM_FAULT=panic {bin} wrap -- /bin/sh; stty -g > {d}/after; echo sa''ved"
    );
    let mut h = Harness::spawn("/bin/sh", &["-c", &script], &[("SHELL", "/bin/sh")], 80, 24);
    h.expect("ready", T);
    h.expect("starting a plain shell", T);
    // The notice is printed just before the exec; keystrokes sent in that gap
    // can still be read by the dying process's input thread.
    std::thread::sleep(Duration::from_millis(300));
    h.send("[ \"$SHELLX_TERM\" = \"$(tty)\" ] && echo m=own''-tty\r");
    h.expect("m=own-tty", T);
    h.send("exit\r");
    h.expect("saved", T);
    common::assert_same_modes(&dir);
}
