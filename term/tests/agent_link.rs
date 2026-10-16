#![cfg(all(unix, feature = "test-hooks"))]

mod common;

use common::fake_agent::{Behavior, FakeAgent};
use common::{Harness, BIN};
use shellx_term::proto::messages::{AgentMsg, TermMsg};
use std::path::Path;
use std::time::{Duration, Instant};

const T: Duration = Duration::from_secs(5);

fn wrapped_sh(home: &Path) -> Harness {
    let home = home.to_str().unwrap();
    Harness::spawn(
        BIN,
        &["wrap", "--", "/bin/sh"],
        &[
            ("HOME", home),
            ("SHELLX_TERM_TIMING", "fast"),
            ("__CFBundleIdentifier", "com.apple.Terminal"),
        ],
        80,
        24,
    )
}

#[test]
fn the_phone_sees_earlier_output_then_live_output_and_the_terminal_facts() {
    let home = common::temp_dir("e2e-snapshot");
    let mut h = wrapped_sh(&home);
    h.send("echo be''fore\r");
    h.expect("before", T);
    let agent = FakeAgent::start(&home, Behavior::Normal);
    let mut s = agent.next_session(T);
    assert!(String::from_utf8_lossy(&s.snapshot(T)).contains("before"));
    assert_eq!(
        (
            s.info.app.as_str(),
            s.info.shell.as_str(),
            s.info.cols,
            s.info.rows
        ),
        ("Terminal", "sh", 80, 24)
    );
    h.send("echo af''ter\r");
    s.expect_out("after", T);
    h.send("exit\r");
    h.wait_exit(T);
}

#[test]
fn phone_input_runs_in_the_shell() {
    let home = common::temp_dir("e2e-input");
    let mut h = wrapped_sh(&home);
    let agent = FakeAgent::start(&home, Behavior::Normal);
    let mut s = agent.next_session(T);
    s.snapshot(T);
    s.send(&AgentMsg::In {
        data: b"echo from''phone\r".to_vec(),
    });
    h.expect("fromphone", T);
    s.expect_out("fromphone", T);
    h.send("exit\r");
    h.wait_exit(T);
}

#[test]
fn both_sides_typing_at_once_keep_their_commands_intact() {
    let home = common::temp_dir("e2e-both");
    let mut h = wrapped_sh(&home);
    let agent = FakeAgent::start(&home, Behavior::Normal);
    let mut s = agent.next_session(T);
    s.snapshot(T);
    s.send(&AgentMsg::In {
        data: b"echo pho''ne-side\r".to_vec(),
    });
    h.send("echo desk''top-side\r");
    h.expect("phone-side", T);
    h.expect("desktop-side", T);
    h.send("exit\r");
    h.wait_exit(T);
}

#[test]
fn the_phone_drives_the_size_until_the_desktop_types_or_resizes() {
    let home = common::temp_dir("e2e-size");
    let mut h = wrapped_sh(&home);
    let agent = FakeAgent::start(&home, Behavior::Normal);
    let mut s = agent.next_session(T);
    s.snapshot(T);
    s.send(&AgentMsg::Resize { cols: 50, rows: 20 });
    s.send(&AgentMsg::In {
        data: b"stty size\r".to_vec(),
    });
    s.expect_out("20 50", T);
    h.send("stty size\r"); // a desktop keystroke takes the size back
    assert_eq!(
        s.expect_msg(|m| matches!(m, TermMsg::Local), T),
        TermMsg::Local
    );
    h.expect("24 80", T);
    s.send(&AgentMsg::Resize { cols: 60, rows: 22 });
    std::thread::sleep(Duration::from_millis(200));
    h.resize(100, 30); // window resize while the phone drives
    assert_eq!(
        s.expect_msg(|m| matches!(m, TermMsg::Size { .. }), T),
        TermMsg::Size {
            cols: 100,
            rows: 30
        }
    );
    s.expect_msg(|m| matches!(m, TermMsg::Local), T);
    h.send("stty size\r");
    h.expect("30 100", T);
    h.send("exit\r");
    h.wait_exit(T);
}

#[test]
fn a_hung_agent_never_slows_the_terminal() {
    let home = common::temp_dir("e2e-hung");
    let mut h = wrapped_sh(&home);
    let agent = FakeAgent::start(&home, Behavior::Normal);
    let mut hung = agent.next_session(T);
    hung.snapshot(T); // then never reads again
    let start = Instant::now();
    h.send("head -c 5000000 /dev/zero | tr '\\0' a; echo; echo do''ne\r");
    h.expect("done", Duration::from_secs(30));
    assert!(
        start.elapsed() < Duration::from_secs(15),
        "{:?}",
        start.elapsed()
    );
    h.send("exit\r");
    h.wait_exit(T);
    drop(hung);
}

#[test]
fn exit_reaches_the_agent_and_a_hung_agent_does_not_hold_the_window() {
    let home = common::temp_dir("e2e-exit");
    let mut h = wrapped_sh(&home);
    let agent = FakeAgent::start(&home, Behavior::Normal);
    let mut s = agent.next_session(T);
    s.snapshot(T);
    h.send("exit 3\r");
    assert_eq!(h.wait_exit(T), 3);
    assert_eq!(
        s.expect_msg(|m| matches!(m, TermMsg::Exit { .. }), T),
        TermMsg::Exit { code: 3 }
    );

    let home = common::temp_dir("e2e-exit-hung");
    let mut h = wrapped_sh(&home);
    let agent = FakeAgent::start(&home, Behavior::Normal);
    let mut hung = agent.next_session(T);
    hung.snapshot(T);
    h.send("head -c 3000000 /dev/zero | tr '\\0' b; exit 4\r");
    let start = Instant::now();
    assert_eq!(h.wait_exit(Duration::from_secs(30)), 4);
    let after_output = start.elapsed();
    assert!(after_output < Duration::from_secs(20), "{after_output:?}");
    drop(hung);
}

#[test]
fn the_inner_shell_is_marked_with_its_own_tty() {
    // The way a block calls us: no arguments, the shell in the environment.
    let home = common::temp_dir("e2e-marker");
    let mut h = Harness::spawn(
        BIN,
        &[],
        &[
            ("HOME", home.to_str().unwrap()),
            ("SHELLX_TERM_TIMING", "fast"),
            ("SHELLX_TERM_WRAP", "/bin/sh"),
            ("SHELLX_TERM_WRAP_LOGIN", "1"),
        ],
        80,
        24,
    );
    h.send("[ \"$SHELLX_TERM\" = \"$(tty)\" ] && echo same''-tty\r");
    h.expect("same-tty", T);
    h.send("echo wrap=[${SHELLX_TERM_WRAP-}][${SHELLX_TERM_WRAP_LOGIN-}]\r");
    h.expect("wrap=[][]", T);
    h.send("exit\r");
    h.wait_exit(T);
}

#[test]
fn an_ignored_sigterm_stays_ignored() {
    let home = common::temp_dir("e2e-sigterm");
    let script = format!("trap '' TERM; exec {BIN} wrap -- /bin/sh");
    let mut h = Harness::spawn(
        "/bin/sh",
        &["-c", &script],
        &[("HOME", home.to_str().unwrap())],
        80,
        24,
    );
    h.send("kill -TERM $PPID; sleep 0.3; echo sur''vived\r");
    h.expect("survived", T);
    h.send("exit 0\r");
    assert_eq!(h.wait_exit(T), 0);
}

#[test]
fn a_panic_in_the_link_thread_does_not_cost_the_terminal_session() {
    let home = common::temp_dir("e2e-link-panic");
    let h = home.to_str().unwrap();
    let mut w = Harness::spawn(
        BIN,
        &["wrap", "--", "/bin/sh"],
        &[
            ("HOME", h),
            ("SHELLX_TERM_TIMING", "fast"),
            ("SHELLX_TERM_FAULT", "link-panic"),
        ],
        80,
        24,
    );
    let _agent = FakeAgent::start(&home, Behavior::Normal);
    std::thread::sleep(Duration::from_millis(500)); // the link thread panics
    w.send("echo st''ill-here\r");
    w.expect("still-here", T);
    w.send("echo pid=$PPID\r");
    w.settle(Duration::from_millis(300));
    assert!(
        !w.text().contains("starting a plain shell"),
        "{:?}",
        w.text()
    );
    // The window process is still shellx-term, not a replacement shell.
    w.send("ps -o ucomm= -p $PPID\r");
    w.expect("shellx-term", T);
    w.send("exit 0\r");
    assert_eq!(w.wait_exit(T), 0);
}
