mod common;

use common::fake_agent::{Attempt, Behavior, FakeAgent};
use shellx_term::proto::endpoint::{endpoint_path_in, read_endpoint};
use shellx_term::proto::handshake::{handshake, HandshakeError, HandshakeOutcome};
use shellx_term::proto::messages::{RejectReason, TermInfo};
use std::net::TcpStream;
use std::time::{Duration, Instant};

const T: Duration = Duration::from_secs(5);

fn info() -> TermInfo {
    TermInfo {
        term_id: [7; 16],
        app: "Terminal".into(),
        shell: "zsh".into(),
        pid: 1,
        cols: 80,
        rows: 24,
        started_at: 1,
    }
}

fn connect(home: &std::path::Path) -> (TcpStream, [u8; 32]) {
    let ep = read_endpoint(&endpoint_path_in(home)).expect("endpoint");
    (
        TcpStream::connect(("127.0.0.1", ep.port)).unwrap(),
        ep.secret,
    )
}

#[test]
fn a_real_agent_accepts_the_terminal() {
    let home = common::temp_dir("hs-ok");
    let agent = FakeAgent::start(&home, Behavior::Normal);
    let (mut s, secret) = connect(&home);
    assert!(matches!(
        handshake(&mut s, &secret, &info(), T),
        Ok(HandshakeOutcome::Ready)
    ));
    let session = agent.next_session(T);
    assert_eq!(session.info, info());
}

#[test]
fn an_impostor_without_the_secret_gets_nothing_after_hello() {
    let home = common::temp_dir("hs-impostor");
    let agent = FakeAgent::start(&home, Behavior::WrongProof);
    let (mut s, secret) = connect(&home);
    assert!(matches!(
        handshake(&mut s, &secret, &info(), T),
        Err(HandshakeError::BadAgentProof)
    ));
    drop(s);
    match agent.next_attempt(T) {
        Attempt::Ended { after_hello } => assert!(after_hello.is_empty(), "leaked {after_hello:?}"),
        Attempt::Session(_) => panic!("impostor got a session"),
    }
}

#[test]
fn a_silent_agent_times_out() {
    let home = common::temp_dir("hs-silent");
    let _agent = FakeAgent::start(&home, Behavior::Silent);
    let (mut s, secret) = connect(&home);
    let start = Instant::now();
    let result = handshake(&mut s, &secret, &info(), Duration::from_millis(400));
    assert!(matches!(result, Err(HandshakeError::Timeout)), "{result:?}");
    assert!(start.elapsed() < Duration::from_secs(2));
}

#[test]
fn rejections_are_reported() {
    for (behavior, reason) in [
        (Behavior::RejectLimit, RejectReason::Limit),
        (Behavior::RejectVersion, RejectReason::Version),
    ] {
        let home = common::temp_dir("hs-reject");
        let _agent = FakeAgent::start(&home, behavior);
        let (mut s, secret) = connect(&home);
        match handshake(&mut s, &secret, &info(), T) {
            Ok(HandshakeOutcome::Rejected(r)) => assert_eq!(r, reason),
            other => panic!("{other:?}"),
        }
    }
}
