//! `api::client::connect` against a fake host over a real Unix socket: the
//! host plays the Dart side (`serverHandshake` + `CliHost`).
#![cfg(unix)]
use shellx_term::api::client::{client_proof, connect, daemon_proof, ApiError, Session};
use shellx_term::api::endpoint::MuxEndpoint;
use shellx_term::api::value::Value;
use shellx_term::api::wire::{recv, send, Message};
use std::io::Write;
use std::os::unix::net::{UnixListener, UnixStream};
use std::path::{Path, PathBuf};
use std::time::{Duration, Instant};

const SECRET: [u8; 32] = [7; 32];
const TOKEN: &str = "5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a";

/// How the fake host answers the client's `hello`.
#[derive(Clone, Copy)]
enum Daemon {
    Honest,
    /// Does not know the secret: proof of zeros.
    Squatter,
    /// Knows the secret but sends a 16-byte nonce.
    ShortNonce,
    /// Knows the secret but speaks protocol 2.
    Protocol2,
}

struct Host {
    daemon: Daemon,
    /// The token the host must find in `auth`.
    expect_token: Option<&'static str>,
}

fn honest() -> Host {
    Host {
        daemon: Daemon::Honest,
        expect_token: None,
    }
}

fn host(path: &Path, h: Host, script: fn(&mut UnixStream)) -> std::thread::JoinHandle<()> {
    let listener = UnixListener::bind(path).unwrap();
    std::thread::spawn(move || {
        let (mut s, _) = listener.accept().unwrap();
        let hello = recv(&mut s).unwrap();
        assert_eq!(hello.t, "hello");
        assert_eq!(hello.get("role").and_then(Value::as_str), Some("cli"));
        // The amendment token never travels before the host proves the secret.
        assert_eq!(hello.get("token"), None);
        assert!(!format!("{hello:?}").contains(TOKEN));
        let nc: [u8; 32] = hello
            .get("nonce")
            .and_then(Value::as_bytes)
            .unwrap()
            .try_into()
            .unwrap();
        let nd = [9u8; 32];
        let (proof, nonce, protocol) = match h.daemon {
            Daemon::Squatter => ([0; 32], nd.to_vec(), 1),
            Daemon::ShortNonce => (daemon_proof(&SECRET, &nc, &nd), nd[..16].to_vec(), 1),
            Daemon::Honest | Daemon::Protocol2 => (
                daemon_proof(&SECRET, &nc, &nd),
                nd.to_vec(),
                if matches!(h.daemon, Daemon::Protocol2) {
                    2
                } else {
                    1
                },
            ),
        };
        send(
            &mut s,
            &Message::new(
                "hello",
                vec![
                    ("protocol", Value::Int(protocol)),
                    ("app", Value::text("1.7.0")),
                    ("nonce", Value::Bytes(nonce)),
                    ("proof", Value::Bytes(proof.to_vec())),
                ],
            ),
        )
        .unwrap();
        if !matches!(h.daemon, Daemon::Honest) {
            // The client must close without sending auth (and its token).
            assert!(recv(&mut s).is_err());
            return;
        }
        let auth = recv(&mut s).unwrap();
        assert_eq!(auth.t, "auth");
        assert_eq!(
            auth.get("proof").and_then(Value::as_bytes).unwrap(),
            &client_proof(&SECRET, &nd, &nc)
        );
        assert_eq!(auth.get("token").and_then(Value::as_str), h.expect_token);
        script(&mut s);
    })
}

fn ready(s: &mut UnixStream) {
    send(s, &Message::new("ready", vec![])).unwrap();
}

fn endpoint(path: &Path) -> MuxEndpoint {
    MuxEndpoint {
        address: path.display().to_string(),
        secret: SECRET,
        protocol: 1,
        app: "1.7.0".into(),
    }
}

fn temp_sock(name: &str) -> PathBuf {
    let p = std::env::temp_dir().join(format!("shellx-cli-{}-{name}.sock", std::process::id()));
    let _ = std::fs::remove_file(&p);
    p
}

fn dial(p: &Path, timeout: Duration, token: Option<&str>) -> Result<impl Session, ApiError> {
    connect(&endpoint(p), &p.display().to_string(), timeout, token)
}

#[test]
fn request_matches_q_and_skips_events() {
    let p = temp_sock("ok");
    let h = host(&p, honest(), |s| {
        ready(s);
        let req = recv(s).unwrap();
        assert_eq!(req.t, "ui.ls");
        let q = req.q.unwrap();
        send(
            s,
            &Message::new("event", vec![("kind", Value::text("tab.opened"))]),
        )
        .unwrap();
        let mut stale = Message::new("result", vec![]);
        stale.q = Some(q + 100);
        send(s, &stale).unwrap();
        let mut res = Message::new("result", vec![("workspaces", Value::Array(vec![]))]);
        res.q = Some(q);
        send(s, &res).unwrap();
        let next = recv(s).unwrap();
        assert_eq!(next.q, Some(q + 1));
        let mut res = Message::new("result", vec![]);
        res.q = next.q;
        send(s, &res).unwrap();
    });
    let mut c = dial(&p, Duration::from_secs(2), None).unwrap();
    let res = c.request("ui.ls", vec![]).unwrap();
    assert!(res.get("workspaces").is_some());
    c.request("api.version", vec![]).unwrap();
    h.join().unwrap();
}

#[test]
fn the_token_reaches_an_honest_host_in_auth() {
    let p = temp_sock("token");
    let h = host(
        &p,
        Host {
            daemon: Daemon::Honest,
            expect_token: Some(TOKEN),
        },
        |s| {
            ready(s);
            let req = recv(s).unwrap();
            let mut res = Message::new("result", vec![]);
            res.q = req.q;
            send(s, &res).unwrap();
        },
    );
    let mut c = dial(&p, Duration::from_secs(2), Some(TOKEN)).unwrap();
    c.request("ui.ls", vec![]).unwrap();
    h.join().unwrap();
}

#[test]
fn events_skip_results() {
    let p = temp_sock("events");
    let h = host(&p, honest(), |s| {
        ready(s);
        send(s, &Message::new("result", vec![])).unwrap();
        send(
            s,
            &Message::new("event", vec![("kind", Value::text("pane.exited"))]),
        )
        .unwrap();
    });
    let mut c = dial(&p, Duration::from_secs(2), None).unwrap();
    let e = c.next_event().unwrap();
    assert_eq!(e.get("kind").and_then(Value::as_str), Some("pane.exited"));
    h.join().unwrap();
    assert!(matches!(c.next_event(), Err(ApiError::NotRunning(_))));
}

#[test]
fn remote_errors_become_api_errors() {
    let p = temp_sock("err");
    let h = host(&p, honest(), |s| {
        ready(s);
        let req = recv(s).unwrap();
        let mut e = Message::new(
            "error",
            vec![
                ("code", Value::text("not_found")),
                ("message", Value::text("no pane p1")),
            ],
        );
        e.q = req.q;
        send(s, &e).unwrap();
    });
    let mut c = dial(&p, Duration::from_secs(2), None).unwrap();
    match c.request("ui.pane.read", vec![("pane", Value::Int(1))]) {
        Err(ApiError::Remote { code, message }) => {
            assert_eq!(code, "not_found");
            assert_eq!(message, "no pane p1");
        }
        other => panic!("{other:?}"),
    }
    h.join().unwrap();
}

const HINT: &str = "This terminal is not a ShellX shell. Allow it in the ShellX tray: Command line → Allow other terminals";

fn forbidden() -> Message {
    Message::new(
        "error",
        vec![
            ("code", Value::text("forbidden")),
            ("message", Value::text(HINT)),
        ],
    )
}

/// Preflight R8: a q-less refusal after `ready` carries the host's message.
#[test]
fn a_refusal_after_ready_carries_the_hosts_message() {
    let p = temp_sock("refused");
    let h = host(&p, honest(), |s| {
        ready(s);
        let _ = recv(s).unwrap();
        send(s, &forbidden()).unwrap();
    });
    let mut c = dial(&p, Duration::from_secs(2), None).unwrap();
    let e = c.request("ui.ls", vec![]).unwrap_err();
    assert_eq!(
        e,
        ApiError::Remote {
            code: "forbidden".into(),
            message: HINT.into()
        }
    );
    assert_eq!(e.exit_code(), 6);
    h.join().unwrap();
}

#[test]
fn a_refusal_in_place_of_ready_carries_the_hosts_message() {
    let p = temp_sock("noready");
    let h = host(&p, honest(), |s| {
        let mut busy = forbidden();
        busy.fields = vec![
            ("code".into(), Value::text("busy")),
            ("message".into(), Value::text("too many clients")),
        ];
        send(s, &busy).unwrap();
    });
    let r = dial(&p, Duration::from_secs(2), None);
    match r {
        Err(ApiError::Remote { code, message }) => {
            assert_eq!(code, "busy");
            assert_eq!(message, "too many clients");
        }
        Err(e) => panic!("{e:?}"),
        Ok(_) => panic!("connected"),
    }
    h.join().unwrap();
}

#[test]
fn a_host_without_the_secret_never_gets_auth() {
    let p = temp_sock("squat");
    let h = host(
        &p,
        Host {
            daemon: Daemon::Squatter,
            expect_token: None,
        },
        |_| {},
    );
    let r = dial(&p, Duration::from_secs(2), Some(TOKEN));
    assert!(matches!(r, Err(ApiError::NotRunning(_))));
    h.join().unwrap();
}

#[test]
fn a_daemon_nonce_that_is_not_32_bytes_is_refused() {
    let p = temp_sock("short");
    let h = host(
        &p,
        Host {
            daemon: Daemon::ShortNonce,
            expect_token: None,
        },
        |_| {},
    );
    let r = dial(&p, Duration::from_secs(2), Some(TOKEN));
    assert!(matches!(r, Err(ApiError::NotRunning(_))));
    h.join().unwrap();
}

#[test]
fn another_protocol_is_incompatible() {
    let p = temp_sock("proto2");
    let h = host(
        &p,
        Host {
            daemon: Daemon::Protocol2,
            expect_token: None,
        },
        |_| {},
    );
    let r = dial(&p, Duration::from_secs(2), Some(TOKEN));
    let Err(e) = r else { panic!("connected") };
    assert!(matches!(e, ApiError::Incompatible(_)), "{e:?}");
    assert_eq!(e.exit_code(), 7);
    h.join().unwrap();
}

#[test]
fn nothing_listening_is_not_running() {
    let p = temp_sock("none");
    let r = dial(&p, Duration::from_millis(300), None);
    assert!(matches!(r, Err(ApiError::NotRunning(_))));
}

#[test]
fn silence_times_out_as_not_running() {
    let p = temp_sock("silent");
    let listener = UnixListener::bind(&p).unwrap();
    let h = std::thread::spawn(move || {
        let (_s, _) = listener.accept().unwrap();
        std::thread::sleep(Duration::from_millis(800));
    });
    let t = Instant::now();
    let r = dial(&p, Duration::from_millis(300), None);
    assert!(matches!(r, Err(ApiError::NotRunning(_))));
    assert!(t.elapsed() < Duration::from_millis(700));
    h.join().unwrap();
}

/// D6 (mirrors the Dart fix): one deadline for the whole handshake. A host
/// that trickles its hello a byte at a time cannot stretch it.
#[test]
fn a_trickling_host_cannot_stretch_the_deadline() {
    let p = temp_sock("trickle");
    let listener = UnixListener::bind(&p).unwrap();
    let h = std::thread::spawn(move || {
        let (mut s, _) = listener.accept().unwrap();
        let _ = recv(&mut s).unwrap();
        let mut frame = Vec::new();
        let hello = Message::new(
            "hello",
            vec![
                ("protocol", Value::Int(1)),
                ("nonce", Value::Bytes(vec![0; 32])),
                ("proof", Value::Bytes(vec![0; 32])),
            ],
        );
        send(&mut frame, &hello).unwrap();
        for b in frame {
            if s.write_all(&[b]).is_err() {
                return;
            }
            std::thread::sleep(Duration::from_millis(100));
        }
    });
    let t = Instant::now();
    let r = dial(&p, Duration::from_millis(300), None);
    assert!(matches!(r, Err(ApiError::NotRunning(_))));
    assert!(
        t.elapsed() < Duration::from_millis(700),
        "{:?}",
        t.elapsed()
    );
    h.join().unwrap();
}

/// A hostile host announcing a 4 GiB frame is refused at once.
#[test]
fn an_oversized_frame_is_not_running() {
    let p = temp_sock("huge");
    let listener = UnixListener::bind(&p).unwrap();
    let h = std::thread::spawn(move || {
        let (mut s, _) = listener.accept().unwrap();
        let _ = recv(&mut s).unwrap();
        let _ = s.write_all(&u32::MAX.to_be_bytes());
        let _ = recv(&mut s);
    });
    let r = dial(&p, Duration::from_secs(2), None);
    assert!(matches!(r, Err(ApiError::NotRunning(_))));
    h.join().unwrap();
}
