//! The authenticated, synchronous client (A7 D30, D31): one request at a
//! time, never reading and writing at once (Windows serializes I/O on a
//! synchronous pipe handle).
//!
//! Handshake (A5b D6, mirrors `clientHandshake` in
//! packages/shellx_agent/lib/src/mux/mux_handshake.dart): hello → verify
//! the host's proof → auth (+ the A7 amendment token) → ready, all under ONE
//! deadline. The host proves the endpoint secret first, so a process
//! squatting on the address never receives our proof or the token.

use super::endpoint::MuxEndpoint;
use super::value::Value;
use super::wire::{recv, send, Message};
use hmac::{Hmac, KeyInit, Mac};
use sha2::Sha256;
use std::io::{Read, Write};
use std::time::{Duration, Instant};

pub const CLI_APP: &str = concat!("shellx-cli/", env!("CARGO_PKG_VERSION"));
pub const MUX_PROTOCOL: i64 = 1;

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ApiError {
    NotRunning(String),
    Incompatible(String),
    Remote { code: String, message: String },
    Usage(String),
    Io(String),
}

impl ApiError {
    /// Spec D10.
    pub fn exit_code(&self) -> i32 {
        match self {
            ApiError::NotRunning(_) => 3,
            ApiError::Incompatible(_) => 7,
            ApiError::Usage(_) => 2,
            ApiError::Io(_) => 1,
            ApiError::Remote { code, .. } => match code.as_str() {
                "bad_request" => 2,
                "not_found" | "ambiguous" => 4,
                "timeout" => 5,
                "cli_disabled" | "forbidden" | "forbidden_origin" | "running_command" => 6,
                "unknown_type" | "unsupported_role" => 7,
                "no_ui" => 8,
                _ => 1,
            },
        }
    }
}

type HmacSha256 = Hmac<Sha256>;

fn proof(secret: &[u8; 32], label: &[u8], a: &[u8; 32], b: &[u8; 32]) -> [u8; 32] {
    let mut m = <HmacSha256 as KeyInit>::new_from_slice(secret).expect("HMAC takes any key length");
    m.update(label);
    m.update(a);
    m.update(b);
    let mut out = [0u8; 32];
    out.copy_from_slice(&m.finalize().into_bytes());
    out
}

/// HMAC(secret, "shellx-mux/daemon" ‖ nonceClient ‖ nonceDaemon).
pub fn daemon_proof(secret: &[u8; 32], nc: &[u8; 32], nd: &[u8; 32]) -> [u8; 32] {
    proof(secret, b"shellx-mux/daemon", nc, nd)
}

/// HMAC(secret, "shellx-mux/client" ‖ nonceDaemon ‖ nonceClient).
pub fn client_proof(secret: &[u8; 32], nd: &[u8; 32], nc: &[u8; 32]) -> [u8; 32] {
    proof(secret, b"shellx-mux/client", nd, nc)
}

fn hello_message(nc: &[u8; 32]) -> Message {
    Message::new(
        "hello",
        vec![
            ("protocol", Value::Int(MUX_PROTOCOL)),
            ("app", Value::text(CLI_APP)),
            ("role", Value::text("cli")),
            ("nonce", Value::Bytes(nc.to_vec())),
        ],
    )
}

/// `token` (A7 amendment) is only ever put here, after the host's proof.
fn auth_message(secret: &[u8; 32], nd: &[u8; 32], nc: &[u8; 32], token: Option<&str>) -> Message {
    let mut fields = vec![("proof", Value::Bytes(client_proof(secret, nd, nc).to_vec()))];
    if let Some(t) = token {
        fields.push(("token", Value::text(t)));
    }
    Message::new("auth", fields)
}

const REFUSED: &str = "ShellX refused the connection";

/// A host-level refusal (`error` with no q: `busy`, `unsupported_role`, the
/// amendment's `forbidden`): the host's own message when it sends one
/// (preflight R8 — it carries the "Allow other terminals" hint).
fn refusal(m: &Message) -> ApiError {
    ApiError::Remote {
        code: m
            .get("code")
            .and_then(Value::as_str)
            .unwrap_or("internal")
            .into(),
        message: m
            .get("message")
            .and_then(Value::as_str)
            .filter(|s| !s.is_empty())
            .unwrap_or(REFUSED)
            .into(),
    }
}

/// The host's proof, checked in constant time (`verify_slice`).
fn daemon_proof_ok(secret: &[u8; 32], nc: &[u8; 32], nd: &[u8; 32], got: &[u8]) -> bool {
    let mut m = <HmacSha256 as KeyInit>::new_from_slice(secret).expect("HMAC takes any key length");
    m.update(b"shellx-mux/daemon");
    m.update(nc);
    m.update(nd);
    m.verify_slice(got).is_ok()
}

pub trait Session {
    fn request(&mut self, t: &str, fields: Vec<(&str, Value)>) -> Result<Message, ApiError>;
    fn next_event(&mut self) -> Result<Message, ApiError>;
}

#[cfg(unix)]
type RawStream = std::os::unix::net::UnixStream;
#[cfg(windows)]
type RawStream = std::fs::File;

pub struct Conn {
    stream: RawStream,
    next_q: i64,
}

fn not_running(why: &str) -> ApiError {
    ApiError::NotRunning(format!(
        "ShellX is not running (open ShellX and try again) [{why}]"
    ))
}

/// Steps 1–4 of the handshake over any byte stream. Messages read before
/// the host's proof is verified are never shown to the user.
fn handshake(
    s: &mut (impl Read + Write),
    secret: &[u8; 32],
    token: Option<&str>,
) -> Result<(), ApiError> {
    let mut nc = [0u8; 32];
    getrandom::fill(&mut nc).map_err(|_| ApiError::Io("no randomness".into()))?;
    send(s, &hello_message(&nc)).map_err(|_| not_running("hello"))?;
    let theirs = recv(s).map_err(|_| not_running("handshake"))?;
    if theirs.t != "hello" {
        return Err(not_running("handshake"));
    }
    // Exactly 32 bytes, as the Dart side requires of both nonces.
    let nd: [u8; 32] = theirs
        .get("nonce")
        .and_then(Value::as_bytes)
        .and_then(|b| b.try_into().ok())
        .ok_or_else(|| not_running("handshake"))?;
    let got = theirs.get("proof").and_then(Value::as_bytes).unwrap_or(&[]);
    if !daemon_proof_ok(secret, &nc, &nd, got) {
        return Err(not_running("proof"));
    }
    if theirs.get("protocol").and_then(Value::as_i64) != Some(MUX_PROTOCOL) {
        return Err(ApiError::Incompatible(
            "this ShellX speaks another protocol: update shellx or ShellX".into(),
        ));
    }
    send(s, &auth_message(secret, &nd, &nc, token)).map_err(|_| not_running("auth"))?;
    let ready = recv(s).map_err(|_| not_running("ready"))?;
    match ready.t.as_str() {
        "ready" => Ok(()),
        // The host proved the secret: its refusal text may be shown.
        "error" if ready.q.is_none() => Err(refusal(&ready)),
        _ => Err(not_running("ready")),
    }
}

/// Unix: every read and write gets only what is left of the one deadline,
/// so a host trickling bytes cannot stretch the handshake (D6).
#[cfg(unix)]
struct Deadline<'a> {
    s: &'a RawStream,
    until: Instant,
}

#[cfg(unix)]
impl Deadline<'_> {
    fn left(&self) -> std::io::Result<Duration> {
        let left = self.until.saturating_duration_since(Instant::now());
        if left.is_zero() {
            Err(std::io::ErrorKind::TimedOut.into())
        } else {
            Ok(left)
        }
    }
}

/// macOS refuses `SO_RCVTIMEO`/`SO_SNDTIMEO` with EINVAL once the peer has
/// closed, even while its last messages are still buffered. Nothing can
/// block then (reads drain the buffer, then EOF), so that error is ignored.
#[cfg(unix)]
fn tolerate_closed_peer(r: std::io::Result<()>) -> std::io::Result<()> {
    #[cfg(target_os = "macos")]
    if matches!(&r, Err(e) if e.raw_os_error() == Some(libc::EINVAL)) {
        return Ok(());
    }
    r
}

#[cfg(unix)]
impl Read for Deadline<'_> {
    fn read(&mut self, buf: &mut [u8]) -> std::io::Result<usize> {
        tolerate_closed_peer(self.s.set_read_timeout(Some(self.left()?)))?;
        (&*self.s).read(buf)
    }
}

#[cfg(unix)]
impl Write for Deadline<'_> {
    fn write(&mut self, buf: &[u8]) -> std::io::Result<usize> {
        tolerate_closed_peer(self.s.set_write_timeout(Some(self.left()?)))?;
        (&*self.s).write(buf)
    }
    fn flush(&mut self) -> std::io::Result<()> {
        (&*self.s).flush()
    }
}

#[cfg(unix)]
fn open_and_handshake(
    address: &str,
    until: Instant,
    secret: &[u8; 32],
    token: Option<&str>,
) -> Result<RawStream, ApiError> {
    let stream = RawStream::connect(address).map_err(|_| not_running("connect"))?;
    handshake(&mut Deadline { s: &stream, until }, secret, token)?;
    // `wait` and `events` may block for a long time.
    stream.set_read_timeout(None).ok();
    stream.set_write_timeout(None).ok();
    Ok(stream)
}

#[cfg(windows)]
fn open(address: &str, until: Instant) -> Result<RawStream, ApiError> {
    use std::os::windows::fs::OpenOptionsExt;
    // Identification level: the host may learn who we are but can never
    // impersonate us (ledger: A7 Task 2 obligation). Without these flags a
    // pipe server gets impersonation-level access to the client's token.
    const SECURITY_SQOS_PRESENT: u32 = 0x0010_0000;
    const SECURITY_IDENTIFICATION: u32 = 1 << 16; // SecurityIdentification << 16
    const ERROR_PIPE_BUSY: i32 = 231;
    // D31: ERROR_PIPE_BUSY → retry every 50 ms until the deadline.
    loop {
        match std::fs::OpenOptions::new()
            .read(true)
            .write(true)
            .security_qos_flags(SECURITY_SQOS_PRESENT | SECURITY_IDENTIFICATION)
            .open(address)
        {
            Ok(f) => return Ok(f),
            Err(e) if e.raw_os_error() == Some(ERROR_PIPE_BUSY) && Instant::now() < until => {
                std::thread::sleep(Duration::from_millis(50))
            }
            Err(_) => return Err(not_running("connect")),
        }
    }
}

/// Windows: a synchronous pipe handle has no read timeout, so the handshake
/// runs on a helper thread and the deadline is a channel timeout. On
/// timeout the helper (blocked in ReadFile) is abandoned; the CLI process
/// exits right after (recorded residual).
#[cfg(windows)]
fn open_and_handshake(
    address: &str,
    until: Instant,
    secret: &[u8; 32],
    token: Option<&str>,
) -> Result<RawStream, ApiError> {
    let mut stream = open(address, until)?;
    let secret = *secret;
    let token = token.map(String::from);
    let (tx, rx) = std::sync::mpsc::channel();
    std::thread::spawn(move || {
        let r = handshake(&mut stream, &secret, token.as_deref()).map(|()| stream);
        let _ = tx.send(r);
    });
    rx.recv_timeout(until.saturating_duration_since(Instant::now()))
        .unwrap_or_else(|_| Err(not_running("handshake")))
}

/// Connects to `address` and authenticates with `endpoint`'s secret.
/// `timeout` bounds the whole connect + handshake (D6, D30: 2 s). `token`
/// is `SHELLX_CLI_TOKEN` (A7 amendment); it is sent only in `auth`, after
/// the host proved the secret, and never logged.
pub fn connect(
    endpoint: &MuxEndpoint,
    address: &str,
    timeout: Duration,
    token: Option<&str>,
) -> Result<Conn, ApiError> {
    let until = Instant::now() + timeout;
    let stream = open_and_handshake(address, until, &endpoint.secret, token)?;
    // A refusal after `ready` (busy, unsupported_role, forbidden) is an
    // error with no q: `request` returns it (D10: busy → 1, unsupported_role
    // → 7, forbidden → 6).
    Ok(Conn { stream, next_q: 1 })
}

fn closed() -> ApiError {
    ApiError::NotRunning("ShellX closed the connection".into())
}

impl Session for Conn {
    fn request(&mut self, t: &str, fields: Vec<(&str, Value)>) -> Result<Message, ApiError> {
        let q = self.next_q;
        self.next_q += 1;
        let mut m = Message::new(t, fields);
        m.q = Some(q);
        if send(&mut self.stream, &m).is_err() {
            // The host may have refused and hung up: its message is still
            // buffered. Anything else is a dead link.
            return match recv(&mut self.stream) {
                Ok(r) if r.t == "error" && r.q.is_none() => Err(refusal(&r)),
                _ => Err(closed()),
            };
        }
        loop {
            let r = recv(&mut self.stream).map_err(|_| closed())?;
            if r.q != Some(q) {
                if r.t == "error" && r.q.is_none() {
                    return Err(refusal(&r));
                }
                continue; // events and stale answers
            }
            match r.t.as_str() {
                "result" => return Ok(r),
                "error" => {
                    return Err(ApiError::Remote {
                        code: r
                            .get("code")
                            .and_then(Value::as_str)
                            .unwrap_or("internal")
                            .into(),
                        message: r
                            .get("message")
                            .and_then(Value::as_str)
                            .unwrap_or("")
                            .into(),
                    })
                }
                _ => continue,
            }
        }
    }

    fn next_event(&mut self) -> Result<Message, ApiError> {
        loop {
            let r = recv(&mut self.stream).map_err(|_| closed())?;
            match r.t.as_str() {
                "event" => return Ok(r),
                "error" if r.q.is_none() => return Err(refusal(&r)),
                _ => {}
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn vector(name: &str) -> Vec<u8> {
        let text = include_str!("../../protocol/mux_vectors.txt");
        let hex = text
            .lines()
            .find_map(|l| l.strip_prefix(&format!("{name}=")))
            .unwrap_or_else(|| panic!("no vector {name}"));
        (0..hex.len())
            .step_by(2)
            .map(|i| u8::from_str_radix(&hex[i..i + 2], 16).unwrap())
            .collect()
    }

    fn arr(name: &str) -> [u8; 32] {
        vector(name).try_into().unwrap()
    }

    #[test]
    fn proofs_match_dart() {
        let (s, nc, nd) = (
            arr("auth.secret"),
            arr("auth.nonce_client"),
            arr("auth.nonce_daemon"),
        );
        assert_eq!(
            daemon_proof(&s, &nc, &nd).to_vec(),
            vector("auth.daemon_proof")
        );
        assert_eq!(
            client_proof(&s, &nd, &nc).to_vec(),
            vector("auth.client_proof")
        );
    }

    #[test]
    fn dart_frames_decode() {
        let m = Message::decode(&vector("host.api_version")).unwrap();
        assert_eq!(m.t, "result");
        assert_eq!(m.q, Some(1));
        assert_eq!(m.get("host").and_then(Value::as_str), Some("ui"));
        let e = Message::decode(&vector("host.event")).unwrap();
        assert_eq!(e.get("tab").and_then(Value::as_i64), Some(-3));
        assert_eq!(e.get("exitCode"), Some(&Value::Null));
        let err = Message::decode(&vector("host.error")).unwrap();
        assert_eq!(err.get("code").and_then(Value::as_str), Some("not_found"));
        // Our api.version request is byte-identical to the one Dart wrote.
        let ours = Message {
            t: "api.version".into(),
            q: Some(1),
            fields: vec![],
        };
        assert_eq!(ours.encode(), vector("cli.api_version"));
    }

    /// The handshake messages `connect` sends are byte-identical to Dart's
    /// `clientHandshake` (golden vectors), with and without the token.
    #[test]
    fn handshake_messages_match_dart() {
        let (s, nc, nd) = (
            arr("auth.secret"),
            arr("auth.nonce_client"),
            arr("auth.nonce_daemon"),
        );
        // The vector was written with app "shellx-cli/0.1.0".
        assert_eq!(CLI_APP, "shellx-cli/0.1.0");
        assert_eq!(hello_message(&nc).encode(), vector("cli.hello"));
        assert_eq!(
            auth_message(&s, &nd, &nc, None).encode(),
            vector("cli.auth")
        );
        let token = "0123456789abcdef".repeat(4);
        let with_token = auth_message(&s, &nd, &nc, Some(&token));
        assert_eq!(with_token.encode(), vector("cli.auth_token"));
        assert_eq!(
            Message::decode(&vector("cli.auth_token"))
                .unwrap()
                .get("token")
                .and_then(Value::as_str),
            Some(token.as_str())
        );
    }

    #[test]
    fn exit_codes_follow_d10() {
        let r = |c: &str| {
            ApiError::Remote {
                code: c.into(),
                message: String::new(),
            }
            .exit_code()
        };
        assert_eq!(r("eval_error"), 1);
        assert_eq!(r("busy"), 1);
        assert_eq!(r("not_found"), 4);
        assert_eq!(r("ambiguous"), 4);
        assert_eq!(r("timeout"), 5);
        assert_eq!(r("cli_disabled"), 6);
        assert_eq!(r("forbidden"), 6);
        assert_eq!(r("forbidden_origin"), 6);
        assert_eq!(r("running_command"), 6);
        assert_eq!(r("unknown_type"), 7);
        assert_eq!(r("unsupported_role"), 7);
        assert_eq!(r("no_ui"), 8);
        assert_eq!(r("bad_request"), 2);
        assert_eq!(ApiError::NotRunning("x".into()).exit_code(), 3);
        assert_eq!(ApiError::Incompatible("x".into()).exit_code(), 7);
        assert_eq!(ApiError::Usage("x".into()).exit_code(), 2);
        assert_eq!(ApiError::Io("x".into()).exit_code(), 1);
    }

    #[test]
    fn a_refusal_carries_the_hosts_message_or_a_fallback() {
        let mut m = Message::new(
            "error",
            vec![
                ("code", Value::text("forbidden")),
                ("message", Value::text("Allow other terminals")),
            ],
        );
        assert_eq!(
            refusal(&m),
            ApiError::Remote {
                code: "forbidden".into(),
                message: "Allow other terminals".into()
            }
        );
        m.fields.retain(|(k, _)| k != "message");
        assert_eq!(
            refusal(&m),
            ApiError::Remote {
                code: "forbidden".into(),
                message: "ShellX refused the connection".into()
            }
        );
        assert_eq!(
            refusal(&Message::new("error", vec![])),
            ApiError::Remote {
                code: "internal".into(),
                message: "ShellX refused the connection".into()
            }
        );
    }
}
