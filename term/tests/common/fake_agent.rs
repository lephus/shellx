//! Plays the ShellX agent's side of the local link, with the real protocol
//! code from the library. Writes the endpoint file under a test HOME.
#![allow(dead_code)]

use shellx_term::proto::auth;
use shellx_term::proto::endpoint::{endpoint_path_in, format_endpoint};
use shellx_term::proto::frame::{read_frame, write_frame};
use shellx_term::proto::messages::{AgentMsg, RejectReason, TermInfo, TermMsg, PROTOCOL_VERSION};
use std::net::{TcpListener, TcpStream};
use std::path::Path;
use std::sync::mpsc;
use std::time::{Duration, Instant};

#[derive(Clone, Copy, Debug)]
pub enum Behavior {
    /// Correct challenge, accept the terminal.
    Normal,
    /// Send a challenge whose proof is wrong.
    WrongProof,
    /// Read `hello`, then say nothing.
    Silent,
    RejectLimit,
    RejectVersion,
}

pub enum Attempt {
    Session(AgentSession),
    /// The connection ended without a session; what the terminal sent after
    /// `hello`.
    Ended {
        after_hello: Vec<TermMsg>,
    },
}

pub struct FakeAgent {
    pub port: u16,
    pub secret: [u8; 32],
    attempts: mpsc::Receiver<Attempt>,
}

impl FakeAgent {
    /// Listens on 127.0.0.1 and (re)writes `<home>/…/ShellX/term/endpoint`.
    pub fn start(home: &Path, behavior: Behavior) -> FakeAgent {
        let listener = TcpListener::bind("127.0.0.1:0").expect("bind");
        let port = listener.local_addr().unwrap().port();
        let mut secret = [0u8; 32];
        getrandom::fill(&mut secret).unwrap();
        let path = endpoint_path_in(home);
        std::fs::create_dir_all(path.parent().unwrap()).unwrap();
        let tmp = path.with_extension("tmp");
        std::fs::write(&tmp, format_endpoint(port, &secret)).unwrap();
        std::fs::rename(&tmp, &path).unwrap();
        let (tx, rx) = mpsc::channel();
        std::thread::spawn(move || {
            for conn in listener.incoming() {
                let Ok(stream) = conn else { break };
                if tx.send(serve(stream, secret, behavior)).is_err() {
                    break;
                }
            }
        });
        FakeAgent {
            port,
            secret,
            attempts: rx,
        }
    }

    pub fn next_attempt(&self, timeout: Duration) -> Attempt {
        self.attempts
            .recv_timeout(timeout)
            .expect("no connection attempt in time")
    }

    pub fn next_session(&self, timeout: Duration) -> AgentSession {
        match self.next_attempt(timeout) {
            Attempt::Session(s) => s,
            Attempt::Ended { after_hello } => panic!("no session; terminal sent {after_hello:?}"),
        }
    }

    /// True if no connection arrives within `wait`.
    pub fn quiet_for(&self, wait: Duration) -> bool {
        self.attempts.recv_timeout(wait).is_err()
    }
}

fn recv_msg(stream: &mut TcpStream) -> Option<TermMsg> {
    let frame = read_frame(stream).ok()?;
    TermMsg::decode(&frame).ok().flatten()
}

fn send_msg(stream: &mut TcpStream, msg: &AgentMsg) {
    let _ = write_frame(stream, &msg.encode());
}

fn drain(mut stream: TcpStream) -> Vec<TermMsg> {
    stream
        .set_read_timeout(Some(Duration::from_secs(3)))
        .unwrap();
    let mut seen = Vec::new();
    while let Some(msg) = recv_msg(&mut stream) {
        seen.push(msg);
    }
    seen
}

fn serve(mut stream: TcpStream, secret: [u8; 32], behavior: Behavior) -> Attempt {
    stream
        .set_read_timeout(Some(Duration::from_secs(5)))
        .unwrap();
    let Some(TermMsg::Hello {
        v,
        nonce: nonce_term,
    }) = recv_msg(&mut stream)
    else {
        return Attempt::Ended {
            after_hello: drain(stream),
        };
    };
    assert_eq!(v, PROTOCOL_VERSION);
    if let Behavior::Silent = behavior {
        return Attempt::Ended {
            after_hello: drain(stream),
        };
    }
    let mut nonce_agent = [0u8; 32];
    getrandom::fill(&mut nonce_agent).unwrap();
    let mut mac = auth::agent_proof(&secret, &nonce_term, &nonce_agent);
    if let Behavior::WrongProof = behavior {
        mac[0] ^= 0xff;
    }
    send_msg(
        &mut stream,
        &AgentMsg::Challenge {
            nonce: nonce_agent,
            mac,
        },
    );
    if let Behavior::WrongProof = behavior {
        return Attempt::Ended {
            after_hello: drain(stream),
        };
    }
    let Some(TermMsg::Auth { mac, info }) = recv_msg(&mut stream) else {
        return Attempt::Ended {
            after_hello: drain(stream),
        };
    };
    assert!(
        auth::verify_term(&secret, &nonce_agent, &nonce_term, &mac),
        "bad terminal proof"
    );
    match behavior {
        Behavior::RejectLimit | Behavior::RejectVersion => {
            let reason = if let Behavior::RejectLimit = behavior {
                RejectReason::Limit
            } else {
                RejectReason::Version
            };
            send_msg(&mut stream, &AgentMsg::Reject { reason });
            Attempt::Ended {
                after_hello: drain(stream),
            }
        }
        _ => {
            send_msg(&mut stream, &AgentMsg::Ready);
            stream.set_read_timeout(None).unwrap();
            Attempt::Session(AgentSession {
                stream,
                info,
                out: Vec::new(),
            })
        }
    }
}

pub struct AgentSession {
    stream: TcpStream,
    pub info: TermInfo,
    /// Every `out` byte received so far.
    out: Vec<u8>,
}

impl AgentSession {
    /// The next message, or None on timeout or a closed connection.
    pub fn recv(&mut self, timeout: Duration) -> Option<TermMsg> {
        self.stream.set_read_timeout(Some(timeout)).unwrap();
        let msg = recv_msg(&mut self.stream);
        if let Some(TermMsg::Out { data }) = &msg {
            self.out.extend_from_slice(data);
        }
        msg
    }

    pub fn send(&mut self, msg: &AgentMsg) {
        write_frame(&mut self.stream, &msg.encode()).expect("send to terminal");
    }

    /// Sends a frame whose payload is not valid protocol data.
    pub fn send_garbage(&mut self) {
        write_frame(&mut self.stream, &[0xff, 0xff, 0xff]).expect("send to terminal");
    }

    /// The snapshot pieces that must open every session.
    pub fn snapshot(&mut self, timeout: Duration) -> Vec<u8> {
        let mut data = Vec::new();
        loop {
            match self.recv(timeout) {
                Some(TermMsg::Snapshot { data: piece, last }) => {
                    data.extend_from_slice(&piece);
                    if last {
                        return data;
                    }
                }
                other => panic!("expected snapshot, got {other:?}"),
            }
        }
    }

    /// Reads messages until the collected `out` text contains `needle`.
    pub fn expect_out(&mut self, needle: &str, timeout: Duration) -> String {
        let until = Instant::now() + timeout;
        while !String::from_utf8_lossy(&self.out).contains(needle) {
            let left = until.saturating_duration_since(Instant::now());
            assert!(
                !left.is_zero(),
                "no {needle:?} in out: {:?}",
                String::from_utf8_lossy(&self.out)
            );
            self.recv(left.min(Duration::from_millis(200)));
        }
        String::from_utf8_lossy(&self.out).into_owned()
    }

    /// Reads (keeping `out` bytes) until a message matches `pred`.
    pub fn expect_msg(&mut self, pred: impl Fn(&TermMsg) -> bool, timeout: Duration) -> TermMsg {
        let until = Instant::now() + timeout;
        loop {
            let left = until.saturating_duration_since(Instant::now());
            assert!(!left.is_zero(), "expected message did not arrive");
            if let Some(msg) = self.recv(left.min(Duration::from_millis(200))) {
                if pred(&msg) {
                    return msg;
                }
            }
        }
    }

    /// True once the terminal closed the connection (EOF) within `timeout`.
    pub fn closed_within(&mut self, timeout: Duration) -> bool {
        let until = Instant::now() + timeout;
        while Instant::now() < until {
            self.stream
                .set_read_timeout(Some(Duration::from_millis(100)))
                .unwrap();
            match read_frame(&mut self.stream) {
                Ok(frame) => {
                    if let Ok(Some(TermMsg::Out { data })) = TermMsg::decode(&frame) {
                        self.out.extend_from_slice(&data);
                    }
                }
                Err(e) if e.kind() == std::io::ErrorKind::UnexpectedEof => return true,
                Err(e)
                    if matches!(
                        e.kind(),
                        std::io::ErrorKind::WouldBlock | std::io::ErrorKind::TimedOut
                    ) => {}
                Err(_) => return true,
            }
        }
        false
    }

    pub fn close(self) {
        let _ = self.stream.shutdown(std::net::Shutdown::Both);
    }
}
