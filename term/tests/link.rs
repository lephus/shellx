#![cfg(feature = "test-hooks")]

mod common;

use common::fake_agent::{Attempt, Behavior, FakeAgent};
use shellx_term::link::{Link, LinkEvents, Timing};
use shellx_term::proto::endpoint::endpoint_path_in;
use shellx_term::proto::messages::{AgentMsg, TermInfo, TermMsg};
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

const T: Duration = Duration::from_secs(5);

#[derive(Default)]
struct Events {
    input: Mutex<Vec<u8>>,
    log: Mutex<Vec<String>>,
}

impl LinkEvents for Events {
    fn info(&self) -> TermInfo {
        TermInfo {
            term_id: [9; 16],
            app: "Terminal".into(),
            shell: "zsh".into(),
            pid: 77,
            cols: 80,
            rows: 24,
            started_at: 5,
        }
    }
    fn input(&self, data: &[u8]) {
        self.input.lock().unwrap().extend_from_slice(data);
    }
    fn phone_resize(&self, cols: u16, rows: u16) {
        self.log
            .lock()
            .unwrap()
            .push(format!("resize {cols}x{rows}"));
    }
    fn phone_left(&self) {
        self.log.lock().unwrap().push("left".into());
    }
}

fn start(home: &std::path::Path) -> (Link, Arc<Events>) {
    let events = Arc::new(Events::default());
    let link = Link::start(Some(endpoint_path_in(home)), Timing::fast(), events.clone());
    (link, events)
}

fn wait_for(cond: impl Fn() -> bool, what: &str) {
    let until = Instant::now() + T;
    while !cond() {
        assert!(Instant::now() < until, "timed out waiting for {what}");
        std::thread::sleep(Duration::from_millis(20));
    }
}

#[test]
fn output_from_before_the_agent_arrives_in_the_snapshot_then_live() {
    let home = common::temp_dir("link-snapshot");
    let (link, _events) = start(&home);
    link.output(b"before\r\n");
    let agent = FakeAgent::start(&home, Behavior::Normal);
    let mut s = agent.next_session(T);
    assert_eq!(s.info.term_id, [9; 16]);
    assert_eq!(s.snapshot(T), b"before\r\n");
    link.output(b"after\r\n");
    s.expect_out("after", T);
}

#[test]
fn a_large_snapshot_comes_in_pieces_under_the_frame_limit() {
    let home = common::temp_dir("link-pieces");
    let (link, _events) = start(&home);
    let big: Vec<u8> = (0..300_000u32).map(|i| b'a' + (i % 26) as u8).collect();
    link.output(&big);
    let agent = FakeAgent::start(&home, Behavior::Normal);
    let mut s = agent.next_session(T);
    let snap = s.snapshot(T);
    assert_eq!(snap.len(), 262_144);
    assert_eq!(snap, big[big.len() - 262_144..]);
}

#[test]
fn the_agent_restarting_gets_the_same_terminal_and_a_fresh_snapshot() {
    let home = common::temp_dir("link-restart");
    let (link, _events) = start(&home);
    let first = FakeAgent::start(&home, Behavior::Normal);
    let mut s1 = first.next_session(T);
    s1.snapshot(T);
    link.output(b"one\r\n");
    s1.expect_out("one", T);
    s1.close();
    let second = FakeAgent::start(&home, Behavior::Normal); // new port + secret
    let mut s2 = second.next_session(T);
    assert_eq!(s2.info.term_id, [9; 16]);
    assert!(String::from_utf8_lossy(&s2.snapshot(T)).contains("one"));
}

#[test]
fn an_impostor_never_receives_terminal_bytes() {
    let home = common::temp_dir("link-impostor");
    let (link, _events) = start(&home);
    link.output(b"secret stuff\r\n");
    let agent = FakeAgent::start(&home, Behavior::WrongProof);
    for _ in 0..2 {
        match agent.next_attempt(T) {
            Attempt::Ended { after_hello } => assert!(after_hello.is_empty(), "{after_hello:?}"),
            Attempt::Session(_) => panic!("impostor got a session"),
        }
    }
}

#[test]
fn a_hung_agent_never_slows_output_and_the_link_resyncs_later() {
    let home = common::temp_dir("link-hung");
    let (link, _events) = start(&home);
    let agent = FakeAgent::start(&home, Behavior::Normal);
    let mut hung = agent.next_session(T);
    hung.snapshot(T);
    // The agent never reads again. 8 MiB of output must still be instant.
    let chunk = vec![b'x'; 16 * 1024];
    let began = Instant::now();
    for _ in 0..512 {
        link.output(&chunk);
    }
    link.output(b"TAIL-MARKER");
    assert!(
        began.elapsed() < Duration::from_secs(1),
        "output blocked: {:?}",
        began.elapsed()
    );
    // The link gives up on the hung session and reconnects with a snapshot.
    let mut fresh = agent.next_session(Duration::from_secs(10));
    let snap = fresh.snapshot(T);
    assert!(snap.ends_with(b"TAIL-MARKER"));
    drop(hung);
}

#[test]
fn phone_messages_reach_the_terminal_and_a_drop_counts_as_leaving() {
    let home = common::temp_dir("link-phone");
    let (_link, events) = start(&home);
    let agent = FakeAgent::start(&home, Behavior::Normal);
    let mut s = agent.next_session(T);
    s.snapshot(T);
    s.send(&AgentMsg::In {
        data: b"ls\r".to_vec(),
    });
    s.send(&AgentMsg::Resize { cols: 50, rows: 20 });
    s.send(&AgentMsg::LocalSize);
    wait_for(
        || events.input.lock().unwrap().as_slice() == b"ls\r",
        "input",
    );
    wait_for(|| events.log.lock().unwrap().len() >= 2, "resize + left");
    s.close();
    wait_for(|| events.log.lock().unwrap().len() >= 3, "left after drop");
    assert_eq!(
        *events.log.lock().unwrap(),
        vec!["resize 50x20", "left", "left"]
    );
}

#[test]
fn desktop_notices_are_sent_while_a_session_is_live() {
    let home = common::temp_dir("link-notices");
    let (link, _events) = start(&home);
    link.send(TermMsg::Local); // no session yet: dropped, not queued
    let agent = FakeAgent::start(&home, Behavior::Normal);
    let mut s = agent.next_session(T);
    s.snapshot(T);
    link.send(TermMsg::Size {
        cols: 100,
        rows: 30,
    });
    link.send(TermMsg::Local);
    assert_eq!(
        s.recv(T),
        Some(TermMsg::Size {
            cols: 100,
            rows: 30
        })
    );
    assert_eq!(s.recv(T), Some(TermMsg::Local));
}

#[test]
fn reject_limit_retries_later_and_reject_version_waits_for_a_new_endpoint() {
    let home = common::temp_dir("link-reject");
    let (_link, _events) = start(&home);
    let limit = FakeAgent::start(&home, Behavior::RejectLimit);
    assert!(matches!(limit.next_attempt(T), Attempt::Ended { .. }));
    assert!(
        matches!(limit.next_attempt(T), Attempt::Ended { .. }),
        "retried after a limit"
    );
    let version = FakeAgent::start(&home, Behavior::RejectVersion);
    assert!(matches!(version.next_attempt(T), Attempt::Ended { .. }));
    assert!(
        version.quiet_for(Duration::from_millis(800)),
        "must not retry the same endpoint"
    );
    let normal = FakeAgent::start(&home, Behavior::Normal); // endpoint changed
    normal.next_session(T);
}

#[test]
fn finish_sends_exit_and_returns_quickly_even_if_the_agent_is_hung() {
    let home = common::temp_dir("link-exit");
    let (link, _events) = start(&home);
    let agent = FakeAgent::start(&home, Behavior::Normal);
    let mut s = agent.next_session(T);
    s.snapshot(T);
    let began = Instant::now();
    link.finish(3);
    assert!(began.elapsed() < Duration::from_millis(600));
    assert_eq!(
        s.expect_msg(|m| matches!(m, TermMsg::Exit { .. }), T),
        TermMsg::Exit { code: 3 }
    );
    assert!(s.closed_within(T));

    let home = common::temp_dir("link-exit-hung");
    let (link, _events) = start(&home);
    let agent = FakeAgent::start(&home, Behavior::Normal);
    let mut hung = agent.next_session(T);
    hung.snapshot(T);
    for _ in 0..200 {
        link.output(&vec![b'y'; 16 * 1024]);
    }
    let began = Instant::now();
    link.finish(0);
    assert!(
        began.elapsed() < Duration::from_millis(600),
        "{:?}",
        began.elapsed()
    );
}

#[test]
fn no_endpoint_means_idle_until_one_appears() {
    let home = common::temp_dir("link-idle");
    let (link, _events) = start(&home);
    link.output(b"early\r\n");
    std::thread::sleep(Duration::from_millis(300));
    let agent = FakeAgent::start(&home, Behavior::Normal);
    let mut s = agent.next_session(T);
    assert_eq!(s.snapshot(T), b"early\r\n");
}
