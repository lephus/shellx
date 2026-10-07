//! A5b messages: `{"t": type, "q": id?, …}` in one CBOR map per frame.
//! Frames are `proto::frame`'s: a 4-byte length (≤ `MAX_FRAME`, checked
//! before the body is allocated) and the CBOR map.

use super::value::{decode, encode, DecodeError, Value};
use crate::proto::frame::{read_frame, write_frame};
use std::io::{self, Read, Write};

#[derive(Debug, Clone, PartialEq)]
pub struct Message {
    pub t: String,
    pub q: Option<i64>,
    pub fields: Vec<(String, Value)>,
}

impl Message {
    pub fn new(t: &str, fields: Vec<(&str, Value)>) -> Message {
        Message {
            t: t.into(),
            q: None,
            fields: fields.into_iter().map(|(k, v)| (k.into(), v)).collect(),
        }
    }
    pub fn get(&self, key: &str) -> Option<&Value> {
        self.fields.iter().find(|(k, _)| k == key).map(|(_, v)| v)
    }
    pub fn to_value(&self) -> Value {
        let mut m = vec![("t".to_string(), Value::Text(self.t.clone()))];
        if let Some(q) = self.q {
            m.push(("q".into(), Value::Int(q)));
        }
        m.extend(self.fields.iter().cloned());
        Value::Map(m)
    }
    pub fn encode(&self) -> Vec<u8> {
        encode(&self.to_value())
    }
    pub fn decode(bytes: &[u8]) -> Result<Message, DecodeError> {
        let Value::Map(entries) = decode(bytes)? else {
            return Err(DecodeError("not a map"));
        };
        let mut t = None;
        let mut q = None;
        let mut fields = Vec::new();
        for (k, v) in entries {
            match (k.as_str(), v) {
                ("t", Value::Text(s)) => t = Some(s),
                ("t", _) => return Err(DecodeError("t is not text")),
                ("q", Value::Int(n)) => q = Some(n),
                ("q", Value::Null) => {}
                ("q", _) => return Err(DecodeError("q is not an integer")),
                (_, v) => fields.push((k, v)),
            }
        }
        Ok(Message {
            t: t.ok_or(DecodeError("no t"))?,
            q,
            fields,
        })
    }
}

pub fn send(w: &mut impl Write, m: &Message) -> io::Result<()> {
    write_frame(w, &m.encode())?;
    w.flush()
}

pub fn recv(r: &mut impl Read) -> io::Result<Message> {
    let payload = read_frame(r)?;
    Message::decode(&payload).map_err(|e| io::Error::new(io::ErrorKind::InvalidData, e.0))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::proto::frame::MAX_FRAME;

    #[test]
    fn messages_round_trip_through_frames() {
        let mut m = Message::new("ui.ls", vec![("pane", Value::Int(3))]);
        m.q = Some(9);
        let mut wire = Vec::new();
        send(&mut wire, &m).unwrap();
        assert_eq!(&wire[..4], &(m.encode().len() as u32).to_be_bytes());
        assert_eq!(recv(&mut &wire[..]).unwrap(), m);
    }

    #[test]
    fn t_comes_first_then_q_then_fields() {
        let mut m = Message::new("x", vec![("a", Value::Null)]);
        m.q = Some(1);
        let Value::Map(entries) = m.to_value() else {
            panic!("not a map")
        };
        let keys: Vec<&str> = entries.iter().map(|(k, _)| k.as_str()).collect();
        assert_eq!(keys, ["t", "q", "a"]);
        assert_eq!(Message::new("x", vec![]).to_value().get("q"), None);
    }

    #[test]
    fn refuses_messages_without_a_text_t_or_with_a_bad_q() {
        let bad = [
            Value::Int(1),
            Value::map(vec![("q", Value::Int(1))]),
            Value::map(vec![("t", Value::Int(1))]),
            Value::map(vec![("t", Value::text("x")), ("q", Value::text("1"))]),
        ];
        for v in bad {
            assert!(Message::decode(&encode(&v)).is_err(), "{v:?}");
        }
        let null_q = Value::map(vec![("t", Value::text("x")), ("q", Value::Null)]);
        assert_eq!(Message::decode(&encode(&null_q)).unwrap().q, None);
    }

    /// A hostile peer announcing a 4 GiB frame is refused from the length
    /// prefix alone (nothing is allocated for it), as is one just over the cap.
    #[test]
    fn oversized_frames_are_refused_before_reading_the_body() {
        for len in [u32::MAX, (MAX_FRAME + 1) as u32] {
            let wire = len.to_be_bytes();
            let e = recv(&mut &wire[..]).unwrap_err();
            assert_eq!(e.kind(), io::ErrorKind::InvalidData);
        }
    }

    #[test]
    fn malformed_payloads_are_invalid_data() {
        for payload in [&b""[..], b"\xff", b"\xa1\x61t", b"\x9f\xff"] {
            let mut wire = (payload.len() as u32).to_be_bytes().to_vec();
            wire.extend_from_slice(payload);
            assert_eq!(
                recv(&mut &wire[..]).unwrap_err().kind(),
                io::ErrorKind::InvalidData
            );
        }
    }
}
