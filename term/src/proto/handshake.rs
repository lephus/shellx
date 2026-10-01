//! The terminal's side of the mutual proof (spec §6.3), bounded by one
//! deadline for the whole exchange.

use super::auth;
use super::frame::MAX_FRAME;
use super::messages::{AgentMsg, RejectReason, TermInfo, TermMsg, PROTOCOL_VERSION};
use std::io::{self, Read, Write};
use std::net::TcpStream;
use std::time::{Duration, Instant};

#[derive(Debug)]
pub enum HandshakeOutcome {
    Ready,
    Rejected(RejectReason),
}

#[derive(Debug)]
pub enum HandshakeError {
    Io(io::Error),
    Timeout,
    /// The other side does not know the secret: nothing more is sent.
    BadAgentProof,
    Protocol(String),
    Random,
}

/// Runs hello → challenge → auth → ready/reject on `stream`, all within
/// `timeout`. Leaves the stream with no read/write timeouts on success.
pub fn handshake(
    stream: &mut TcpStream,
    secret: &[u8; 32],
    info: &TermInfo,
    timeout: Duration,
) -> Result<HandshakeOutcome, HandshakeError> {
    let deadline = Instant::now() + timeout;
    let mut nonce_term = [0u8; 32];
    getrandom::fill(&mut nonce_term).map_err(|_| HandshakeError::Random)?;
    send(
        stream,
        &TermMsg::Hello {
            v: PROTOCOL_VERSION,
            nonce: nonce_term,
        },
        deadline,
    )?;
    let (nonce_agent, proof) = match recv(stream, deadline)? {
        AgentMsg::Challenge { nonce, mac } => (nonce, mac),
        AgentMsg::Reject { reason } => return Ok(HandshakeOutcome::Rejected(reason)),
        other => {
            return Err(HandshakeError::Protocol(format!(
                "expected challenge, got {other:?}"
            )))
        }
    };
    if !auth::verify_agent(secret, &nonce_term, &nonce_agent, &proof) {
        return Err(HandshakeError::BadAgentProof);
    }
    let mac = auth::term_proof(secret, &nonce_agent, &nonce_term);
    send(
        stream,
        &TermMsg::Auth {
            mac,
            info: info.clone(),
        },
        deadline,
    )?;
    match recv(stream, deadline)? {
        AgentMsg::Ready => {
            stream.set_read_timeout(None).map_err(HandshakeError::Io)?;
            stream.set_write_timeout(None).map_err(HandshakeError::Io)?;
            Ok(HandshakeOutcome::Ready)
        }
        AgentMsg::Reject { reason } => Ok(HandshakeOutcome::Rejected(reason)),
        other => Err(HandshakeError::Protocol(format!(
            "expected ready, got {other:?}"
        ))),
    }
}

fn left(deadline: Instant) -> Result<Duration, HandshakeError> {
    let left = deadline.saturating_duration_since(Instant::now());
    if left.is_zero() {
        Err(HandshakeError::Timeout)
    } else {
        Ok(left)
    }
}

fn io_error(e: io::Error) -> HandshakeError {
    match e.kind() {
        io::ErrorKind::WouldBlock | io::ErrorKind::TimedOut => HandshakeError::Timeout,
        _ => HandshakeError::Io(e),
    }
}

/// Writes one frame, re-arming the socket timeout before every syscall so a
/// slow peer cannot stretch the exchange past `deadline`.
fn send(stream: &mut TcpStream, msg: &TermMsg, deadline: Instant) -> Result<(), HandshakeError> {
    let payload = msg.encode();
    if payload.len() > MAX_FRAME {
        return Err(HandshakeError::Protocol("frame too large".into()));
    }
    let mut buf = Vec::with_capacity(4 + payload.len());
    buf.extend_from_slice(&(payload.len() as u32).to_be_bytes());
    buf.extend_from_slice(&payload);
    let mut done = 0;
    while done < buf.len() {
        stream
            .set_write_timeout(Some(left(deadline)?))
            .map_err(HandshakeError::Io)?;
        match stream.write(&buf[done..]) {
            Ok(0) => return Err(HandshakeError::Io(io::ErrorKind::WriteZero.into())),
            Ok(n) => done += n,
            Err(e) if e.kind() == io::ErrorKind::Interrupted => {}
            Err(e) => return Err(io_error(e)),
        }
    }
    Ok(())
}

fn read_exact_by(
    stream: &mut TcpStream,
    buf: &mut [u8],
    deadline: Instant,
) -> Result<(), HandshakeError> {
    let mut done = 0;
    while done < buf.len() {
        stream
            .set_read_timeout(Some(left(deadline)?))
            .map_err(HandshakeError::Io)?;
        match stream.read(&mut buf[done..]) {
            Ok(0) => return Err(HandshakeError::Io(io::ErrorKind::UnexpectedEof.into())),
            Ok(n) => done += n,
            Err(e) if e.kind() == io::ErrorKind::Interrupted => {}
            Err(e) => return Err(io_error(e)),
        }
    }
    Ok(())
}

fn recv(stream: &mut TcpStream, deadline: Instant) -> Result<AgentMsg, HandshakeError> {
    let mut len = [0u8; 4];
    read_exact_by(stream, &mut len, deadline)?;
    let len = u32::from_be_bytes(len) as usize;
    if len > MAX_FRAME {
        return Err(HandshakeError::Protocol("frame too large".into()));
    }
    let mut frame = vec![0u8; len];
    read_exact_by(stream, &mut frame, deadline)?;
    AgentMsg::decode(&frame)
        .map_err(|e| HandshakeError::Protocol(e.0))?
        .ok_or_else(|| HandshakeError::Protocol("unknown message during handshake".into()))
}
