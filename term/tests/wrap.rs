#![cfg(unix)]

mod common;

use common::Harness;
use std::time::Duration;

const T: Duration = Duration::from_secs(5);

#[test]
fn typed_commands_run_in_the_wrapped_shell() {
    let mut h = Harness::wrap_sh(&[]);
    h.send("echo he''llo\r");
    h.expect("hello", T);
    h.send("exit 0\r");
    assert_eq!(h.wait_exit(T), 0);
}

#[test]
fn the_wrapped_shell_is_marked() {
    let mut h = Harness::wrap_sh(&[]);
    h.send("[ \"$SHELLX_TERM\" = \"$(tty)\" ] && echo m=tty\r");
    h.expect("m=tty", T);
    h.send("exit\r");
    h.wait_exit(T);
}

#[test]
fn the_exit_code_of_the_shell_is_kept() {
    let mut h = Harness::wrap_sh(&[]);
    h.send("exit 7\r");
    assert_eq!(h.wait_exit(T), 7);
}

#[test]
fn a_shell_killed_by_a_signal_reports_128_plus_the_signal() {
    let mut h = Harness::wrap_sh(&[]);
    h.send("kill -KILL $$\r");
    assert_eq!(h.wait_exit(T), 128 + 9);
}

#[test]
fn the_shell_starts_in_the_same_directory() {
    let mut h = Harness::wrap_sh(&[]);
    h.send("pwd -P; echo pw''d-done\r");
    h.expect("pwd-done", T);
    let expected = std::fs::canonicalize(std::env::temp_dir()).unwrap();
    assert!(
        h.text().contains(expected.to_str().unwrap()),
        "expected {} in {:?}",
        expected.display(),
        h.text()
    );
    h.send("exit\r");
    h.wait_exit(T);
}

#[test]
fn vietnamese_text_passes_through_unchanged() {
    let mut h = Harness::wrap_sh(&[]);
    h.send("printf '%s-%s\\n' 'ti\u{1ebf}ng' 'Vi\u{1ec7}t'\r");
    h.expect("ti\u{1ebf}ng-Vi\u{1ec7}t", T);
    h.send("exit\r");
    h.wait_exit(T);
}

#[test]
fn five_megabytes_of_output_arrive_complete() {
    let mut h = Harness::wrap_sh(&[]);
    h.send("head -c 5000000 /dev/zero | tr '\\0' a; echo; echo do''ne\r");
    h.expect("done", Duration::from_secs(30));
    let count = h.output_bytes().iter().filter(|&&b| b == b'a').count();
    assert!(count >= 5_000_000, "only {count} bytes arrived");
    h.send("exit\r");
    h.wait_exit(T);
}

#[test]
fn output_written_just_before_exit_is_not_lost() {
    let mut h = Harness::wrap_sh(&[]);
    h.send("head -c 300000 /dev/zero | tr '\\0' b; exit 0\r");
    assert_eq!(h.wait_exit(Duration::from_secs(15)), 0);
    let count = h.output_bytes().iter().filter(|&&b| b == b'b').count();
    assert!(count >= 300_000, "only {count} bytes arrived");
}

#[test]
fn test_windows_get_a_temporary_home_unless_the_caller_sets_one() {
    let mut h = Harness::wrap_sh(&[]);
    h.send("echo ho''me=$HOME;\r");
    let text = {
        h.expect("home=/", T);
        h.settle(Duration::from_millis(200));
        h.text()
    };
    let at = text.rfind("home=").unwrap() + 5;
    let home: String = text[at..]
        .chars()
        .take_while(|c| !c.is_whitespace() && *c != ';')
        .collect();
    let temp = std::env::temp_dir();
    assert!(
        std::path::Path::new(&home).starts_with(&temp),
        "HOME is {home:?}, not under {temp:?}"
    );
    h.send("exit 0\r");
    h.wait_exit(T);
    let mut h = Harness::wrap_sh(&[("HOME", "/nonexistent-home")]);
    h.send("echo ho''me=$HOME;\r");
    h.expect("home=/nonexistent-home", T);
    h.send("exit 0\r");
    h.wait_exit(T);
}
