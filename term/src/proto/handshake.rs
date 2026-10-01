//! The terminal's side of the mutual proof (spec §6.3), bounded by one
//! deadline for the whole exchange.

use super::auth;
use super::frame::{read_frame, write_frame};
use super::messages::{AgentMsg, RejectReason, TermInfo, TermMsg, PROTOCOL_VERSION};
use std::io;
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

fn send(stream: &mut TcpStream, msg: &TermMsg, deadline: Instant) -> Result<(), HandshakeError> {
    stream
        .set_write_timeout(Some(left(deadline)?))
        .map_err(HandshakeError::Io)?;
    write_frame(stream, &msg.encode()).map_err(io_error)
}

fn recv(stream: &mut TcpStream, deadline: Instant) -> Result<AgentMsg, HandshakeError> {
    stream
        .set_read_timeout(Some(left(deadline)?))
        .map_err(HandshakeError::Io)?;
    let frame = read_frame(stream).map_err(io_error)?;
    AgentMsg::decode(&frame)
        .map_err(|e| HandshakeError::Protocol(e.0))?
        .ok_or_else(|| HandshakeError::Protocol("unknown message during handshake".into()))
}
