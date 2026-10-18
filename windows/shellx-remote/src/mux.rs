//! Line framing for the daemon's mux control service, in process.
//!
//! Ported (MIT, cmux-tui workspace) from
//! `cmux-tui/crates/cmux-remote/src/mux_codec.rs` (`encode_line`,
//! `MuxLineAssembler`), `mux_lanes.rs` (`classify_client_line`) and
//! `bridge.rs` (`await_opened`). Those items are `pub(crate)` upstream: the
//! Mac sidecar only reaches them through its Unix-socket bridge, which
//! Windows does not have. The wire format is unchanged: each JSON line is
//! split into `CMXL` packets (magic, message id, part, parts, payload).

use std::collections::{HashMap, VecDeque};

use anyhow::{Context, anyhow, bail};
use bytes::{BufMut, Bytes, BytesMut};
use cmux_remote::service::{ServiceStream, StreamChunk};
use cmux_remote_protocol::{
    Lane, MAX_FRAME_PAYLOAD, REMOTE_SESSION_MESSAGE_MAX_BYTES, Service, ServiceControl,
};

const MAGIC: [u8; 4] = *b"CMXL";
const HEADER_BYTES: usize = 4 + 8 + 4 + 4;
const CHUNK_BYTES: usize = MAX_FRAME_PAYLOAD - HEADER_BYTES;
/// Largest line the daemon may send (its session message cap plus the LF).
const MAX_DOWNLOAD_LINE_BYTES: usize = REMOTE_SESSION_MESSAGE_MAX_BYTES + 1;
const MAX_PARTS_PER_LINE: usize = MAX_DOWNLOAD_LINE_BYTES.div_ceil(CHUNK_BYTES);
const MAX_IN_FLIGHT_LINES: usize = 256;

/// Split one JSON line (with its trailing LF) into mux packets.
pub(crate) fn encode_line(message: u64, line: &[u8]) -> Vec<Bytes> {
    let parts = line.len().max(1).div_ceil(CHUNK_BYTES);
    let mut encoded = Vec::with_capacity(parts);
    if line.is_empty() {
        encoded.push(encode_part(message, 0, 1, &[]));
    } else {
        for (part, chunk) in line.chunks(CHUNK_BYTES).enumerate() {
            encoded.push(encode_part(message, part as u32, parts as u32, chunk));
        }
    }
    encoded
}

fn encode_part(message: u64, part: u32, parts: u32, payload: &[u8]) -> Bytes {
    let mut encoded = BytesMut::with_capacity(HEADER_BYTES + payload.len());
    encoded.extend_from_slice(&MAGIC);
    encoded.put_u64(message);
    encoded.put_u32(part);
    encoded.put_u32(parts);
    encoded.extend_from_slice(payload);
    encoded.freeze()
}

/// Reassembles daemon lines from packets that may interleave across lanes.
#[derive(Default)]
pub(crate) struct LineAssembler {
    lines: HashMap<u64, Partial>,
}

struct Partial {
    lane: Lane,
    parts: Vec<Option<Bytes>>,
    received: usize,
    bytes: usize,
}

impl LineAssembler {
    pub(crate) fn push(&mut self, lane: Lane, packet: Bytes) -> anyhow::Result<Option<Bytes>> {
        if packet.len() < HEADER_BYTES || packet[..4] != MAGIC {
            bail!("invalid mux line packet");
        }
        let message = u64::from_be_bytes(packet[4..12].try_into().expect("8 bytes"));
        let part = u32::from_be_bytes(packet[12..16].try_into().expect("4 bytes")) as usize;
        let parts = u32::from_be_bytes(packet[16..20].try_into().expect("4 bytes")) as usize;
        if parts == 0 || part >= parts || parts > MAX_PARTS_PER_LINE {
            bail!("invalid mux line packet");
        }
        if !self.lines.contains_key(&message) {
            if self.lines.len() >= MAX_IN_FLIGHT_LINES {
                bail!("too many incomplete mux lines");
            }
            self.lines.insert(
                message,
                Partial {
                    lane,
                    parts: vec![None; parts],
                    received: 0,
                    bytes: 0,
                },
            );
        }
        let line = self.lines.get_mut(&message).expect("inserted above");
        if line.lane != lane || line.parts.len() != parts || line.parts[part].is_some() {
            bail!("invalid mux line packet");
        }
        let payload = packet.slice(HEADER_BYTES..);
        line.bytes = line.bytes.saturating_add(payload.len());
        if line.bytes > MAX_DOWNLOAD_LINE_BYTES {
            bail!("mux line is too large: {}", line.bytes);
        }
        line.received += 1;
        line.parts[part] = Some(payload);
        if line.received != line.parts.len() {
            return Ok(None);
        }
        let line = self.lines.remove(&message).expect("complete line exists");
        if line.parts.len() == 1 {
            return Ok(line.parts.into_iter().next().flatten());
        }
        let mut joined = BytesMut::with_capacity(line.bytes);
        for part in line.parts {
            joined.extend_from_slice(&part.expect("all parts received"));
        }
        Ok(Some(joined.freeze()))
    }
}

/// The lane `cmux-remote`'s bridge would pick for a client command.
pub(crate) fn lane_for_command(cmd: &str) -> Lane {
    match cmd {
        "attach-surface" | "read-screen" | "read-scrollback" | "vt-state" => Lane::Bulk,
        "identify" | "ping" | "list-clients" | "list-workspaces" | "subscribe" => Lane::Control,
        // Mutations, input and resizes share one ordered lane, as upstream.
        _ => Lane::Interactive,
    }
}

/// Wait until the daemon has opened the mux control stream on every lane.
/// Chunks that arrive before the last marker are returned for replay.
pub(crate) async fn await_opened(stream: &ServiceStream) -> anyhow::Result<VecDeque<StreamChunk>> {
    let mut seen = 0_u8;
    let mut buffered = VecDeque::new();
    while seen != 0b111 {
        let chunk = stream
            .receive()
            .await
            .context("mux control stream failed while opening")?
            .ok_or_else(|| anyhow!("mux control stream closed before every lane was ready"))?;
        let value = serde_json::from_slice::<serde_json::Value>(&chunk.payload).ok();
        let marker = value
            .as_ref()
            .and_then(|value| value.get("type"))
            .and_then(serde_json::Value::as_str);
        if !matches!(marker, Some("opened") | Some("rejected")) {
            buffered.push_back(chunk);
            continue;
        }
        let control: ServiceControl = serde_json::from_value(value.expect("parsed above"))
            .context("invalid mux service-open response")?;
        match control {
            ServiceControl::Opened {
                service: Service::MuxControl,
            } => {}
            ServiceControl::Rejected { message, .. } => {
                bail!("daemon rejected the mux control stream: {message}")
            }
            _ => bail!("invalid mux service-open response"),
        }
        seen |= match chunk.lane {
            Lane::Interactive => 0b001,
            Lane::Control => 0b010,
            Lane::Bulk => 0b100,
            Lane::Tunnel => bail!("mux open marker arrived on the tunnel lane"),
        };
    }
    Ok(buffered)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn small_line_round_trips_in_one_packet() {
        let line = b"{\"id\":1,\"cmd\":\"identify\"}\n";
        let packets = encode_line(7, line);
        assert_eq!(packets.len(), 1);
        assert_eq!(&packets[0][..4], b"CMXL");
        let mut assembler = LineAssembler::default();
        let out = assembler
            .push(Lane::Control, packets[0].clone())
            .unwrap()
            .unwrap();
        assert_eq!(&out[..], line);
    }

    #[test]
    fn large_line_reassembles_out_of_order() {
        let line = vec![b'x'; CHUNK_BYTES * 2 + 17];
        let mut packets = encode_line(9, &line);
        assert_eq!(packets.len(), 3);
        packets.swap(0, 2);
        let mut assembler = LineAssembler::default();
        assert!(
            assembler
                .push(Lane::Bulk, packets[0].clone())
                .unwrap()
                .is_none()
        );
        assert!(
            assembler
                .push(Lane::Bulk, packets[1].clone())
                .unwrap()
                .is_none()
        );
        let out = assembler
            .push(Lane::Bulk, packets[2].clone())
            .unwrap()
            .unwrap();
        assert_eq!(out.len(), line.len());
        assert!(out.iter().all(|byte| *byte == b'x'));
    }

    #[test]
    fn interleaved_messages_keep_their_own_bytes() {
        let a = vec![b'a'; CHUNK_BYTES + 1];
        let b = b"{\"event\":\"output\"}\n".to_vec();
        let pa = encode_line(1, &a);
        let pb = encode_line(2, &b);
        let mut assembler = LineAssembler::default();
        assert!(assembler.push(Lane::Bulk, pa[0].clone()).unwrap().is_none());
        assert_eq!(
            &assembler.push(Lane::Bulk, pb[0].clone()).unwrap().unwrap()[..],
            &b[..]
        );
        assert_eq!(
            assembler
                .push(Lane::Bulk, pa[1].clone())
                .unwrap()
                .unwrap()
                .len(),
            a.len()
        );
    }

    #[test]
    fn bad_packets_are_rejected() {
        let mut assembler = LineAssembler::default();
        assert!(
            assembler
                .push(Lane::Control, Bytes::from_static(b"nope"))
                .is_err()
        );
        let mut packet = encode_line(1, b"x\n")[0].to_vec();
        packet[16..20].copy_from_slice(&0_u32.to_be_bytes());
        assert!(assembler.push(Lane::Control, Bytes::from(packet)).is_err());
        // The same part twice is a protocol error, not a duplicate line.
        let parts = encode_line(3, &vec![b'y'; CHUNK_BYTES + 1]);
        assembler.push(Lane::Bulk, parts[0].clone()).unwrap();
        assert!(assembler.push(Lane::Bulk, parts[0].clone()).is_err());
    }

    #[test]
    fn commands_use_upstream_lanes() {
        assert_eq!(lane_for_command("attach-surface"), Lane::Bulk);
        assert_eq!(lane_for_command("identify"), Lane::Control);
        assert_eq!(lane_for_command("list-workspaces"), Lane::Control);
        assert_eq!(lane_for_command("send"), Lane::Interactive);
        assert_eq!(lane_for_command("resize-surface"), Lane::Interactive);
        assert_eq!(lane_for_command("new-workspace"), Lane::Interactive);
    }
}
