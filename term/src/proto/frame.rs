//! Frames on the local link: a 4-byte big-endian length, then that many
//! bytes of CBOR (spec §6.2). At most 64 KiB per frame.

use std::io::{self, Read, Write};

pub const MAX_FRAME: usize = 64 * 1024;

/// Writes one frame with a single `write_all`.
pub fn write_frame(w: &mut impl Write, payload: &[u8]) -> io::Result<()> {
    if payload.len() > MAX_FRAME {
        return Err(io::Error::new(
            io::ErrorKind::InvalidInput,
            "frame too large",
        ));
    }
    let mut buf = Vec::with_capacity(4 + payload.len());
    buf.extend_from_slice(&(payload.len() as u32).to_be_bytes());
    buf.extend_from_slice(payload);
    w.write_all(&buf)
}

/// Reads one frame; `InvalidData` for a length over `MAX_FRAME`.
pub fn read_frame(r: &mut impl Read) -> io::Result<Vec<u8>> {
    let mut len = [0u8; 4];
    r.read_exact(&mut len)?;
    let len = u32::from_be_bytes(len) as usize;
    if len > MAX_FRAME {
        return Err(io::Error::new(
            io::ErrorKind::InvalidData,
            "frame too large",
        ));
    }
    let mut payload = vec![0u8; len];
    r.read_exact(&mut payload)?;
    Ok(payload)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn round_trips_and_prefixes_the_length() {
        let mut wire = Vec::new();
        write_frame(&mut wire, b"abc").unwrap();
        assert_eq!(wire, [0, 0, 0, 3, b'a', b'b', b'c']);
        assert_eq!(read_frame(&mut &wire[..]).unwrap(), b"abc");
    }

    #[test]
    fn refuses_oversized_frames_both_ways() {
        let big = vec![0u8; MAX_FRAME + 1];
        assert!(write_frame(&mut Vec::new(), &big).is_err());
        let wire = ((MAX_FRAME + 1) as u32).to_be_bytes();
        assert_eq!(
            read_frame(&mut &wire[..]).unwrap_err().kind(),
            io::ErrorKind::InvalidData
        );
    }

    #[test]
    fn a_truncated_frame_is_an_error() {
        let wire = [0, 0, 0, 5, b'a'];
        assert!(read_frame(&mut &wire[..]).is_err());
    }
}
