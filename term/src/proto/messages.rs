//! Messages on the local link (spec §6.3, §6.4). Each message is one CBOR
//! map with key `t`. Reference bytes: `term/protocol/vectors.txt`.

use super::cbor::{decode_map, encode_map, CborError, Map, Value};

/// Version of the local-link protocol this binary speaks (`hello.v`).
pub const PROTOCOL_VERSION: u64 = 1;

#[derive(Debug, PartialEq, Eq)]
pub struct ProtoError(pub String);

impl From<CborError> for ProtoError {
    fn from(e: CborError) -> Self {
        ProtoError(format!("cbor: {}", e.0))
    }
}

/// What `shellx-term` tells the agent about its terminal in `auth`.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct TermInfo {
    /// Random per window; the same across reconnects (spec §6.5).
    pub term_id: [u8; 16],
    /// Terminal app shown on the phone ("Terminal", "Cursor", …); may be empty.
    pub app: String,
    /// Shell name, e.g. "zsh".
    pub shell: String,
    /// Process id of the wrapped shell.
    pub pid: u32,
    pub cols: u16,
    pub rows: u16,
    /// Unix milliseconds when the window's shell started.
    pub started_at: u64,
}

/// `shellx-term` → agent.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum TermMsg {
    Hello {
        v: u64,
        nonce: [u8; 32],
    },
    Auth {
        mac: [u8; 32],
        info: TermInfo,
    },
    /// One piece of the output buffer; `last` marks the final piece. The
    /// pieces are always the first frames after `ready` (spec §6.4).
    Snapshot {
        data: Vec<u8>,
        last: bool,
    },
    Out {
        data: Vec<u8>,
    },
    Size {
        cols: u16,
        rows: u16,
    },
    Local,
    Exit {
        code: u32,
    },
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum RejectReason {
    Limit,
    Version,
    Other(String),
}

/// Agent → `shellx-term`.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum AgentMsg {
    Challenge { nonce: [u8; 32], mac: [u8; 32] },
    Ready,
    Reject { reason: RejectReason },
    In { data: Vec<u8> },
    Resize { cols: u16, rows: u16 },
    LocalSize,
}

fn text(s: &str) -> Value {
    Value::Text(s.to_string())
}

fn message(t: &str, fields: Vec<(&str, Value)>) -> Vec<u8> {
    let mut map = Map::new();
    map.insert("t".to_string(), text(t));
    for (key, value) in fields {
        map.insert(key.to_string(), value);
    }
    encode_map(&map)
}

/// A decoded map plus typed, error-reporting field access.
struct Fields {
    map: Map,
    t: String,
}

impl Fields {
    fn parse(bytes: &[u8]) -> Result<Fields, ProtoError> {
        let map = decode_map(bytes)?;
        let t = match map.get("t") {
            Some(Value::Text(t)) => t.clone(),
            _ => return Err(ProtoError("missing \"t\"".into())),
        };
        Ok(Fields { map, t })
    }

    fn bad(&self, key: &str) -> ProtoError {
        ProtoError(format!("{}: \"{key}\" missing or wrong type", self.t))
    }

    fn uint(&self, key: &str) -> Result<u64, ProtoError> {
        match self.map.get(key) {
            Some(Value::Uint(n)) => Ok(*n),
            _ => Err(self.bad(key)),
        }
    }

    fn u32(&self, key: &str) -> Result<u32, ProtoError> {
        u32::try_from(self.uint(key)?).map_err(|_| self.bad(key))
    }

    /// A terminal dimension: 1..=65535.
    fn dim(&self, key: &str) -> Result<u16, ProtoError> {
        u16::try_from(self.uint(key)?)
            .ok()
            .filter(|n| *n > 0)
            .ok_or_else(|| self.bad(key))
    }

    fn bytes(&self, key: &str) -> Result<Vec<u8>, ProtoError> {
        match self.map.get(key) {
            Some(Value::Bytes(b)) => Ok(b.clone()),
            _ => Err(self.bad(key)),
        }
    }

    fn array<const N: usize>(&self, key: &str) -> Result<[u8; N], ProtoError> {
        self.bytes(key)?.try_into().map_err(|_| self.bad(key))
    }

    fn text(&self, key: &str) -> Result<String, ProtoError> {
        match self.map.get(key) {
            Some(Value::Text(s)) => Ok(s.clone()),
            _ => Err(self.bad(key)),
        }
    }

    fn boolean(&self, key: &str) -> Result<bool, ProtoError> {
        match self.map.get(key) {
            Some(Value::Bool(b)) => Ok(*b),
            _ => Err(self.bad(key)),
        }
    }
}

impl TermMsg {
    pub fn encode(&self) -> Vec<u8> {
        match self {
            TermMsg::Hello { v, nonce } => message(
                "hello",
                vec![
                    ("v", Value::Uint(*v)),
                    ("nonce", Value::Bytes(nonce.to_vec())),
                ],
            ),
            TermMsg::Auth { mac, info } => message(
                "auth",
                vec![
                    ("mac", Value::Bytes(mac.to_vec())),
                    ("term_id", Value::Bytes(info.term_id.to_vec())),
                    ("app", text(&info.app)),
                    ("shell", text(&info.shell)),
                    ("pid", Value::Uint(info.pid.into())),
                    ("cols", Value::Uint(info.cols.into())),
                    ("rows", Value::Uint(info.rows.into())),
                    ("started_at", Value::Uint(info.started_at)),
                ],
            ),
            TermMsg::Snapshot { data, last } => message(
                "snapshot",
                vec![
                    ("data", Value::Bytes(data.clone())),
                    ("last", Value::Bool(*last)),
                ],
            ),
            TermMsg::Out { data } => message("out", vec![("data", Value::Bytes(data.clone()))]),
            TermMsg::Size { cols, rows } => message(
                "size",
                vec![
                    ("cols", Value::Uint((*cols).into())),
                    ("rows", Value::Uint((*rows).into())),
                ],
            ),
            TermMsg::Local => message("local", vec![]),
            TermMsg::Exit { code } => message("exit", vec![("code", Value::Uint((*code).into()))]),
        }
    }

    /// `Ok(None)` for a message type this version does not know.
    pub fn decode(bytes: &[u8]) -> Result<Option<TermMsg>, ProtoError> {
        let f = Fields::parse(bytes)?;
        Ok(Some(match f.t.as_str() {
            "hello" => TermMsg::Hello {
                v: f.uint("v")?,
                nonce: f.array("nonce")?,
            },
            "auth" => TermMsg::Auth {
                mac: f.array("mac")?,
                info: TermInfo {
                    term_id: f.array("term_id")?,
                    app: f.text("app")?,
                    shell: f.text("shell")?,
                    pid: f.u32("pid")?,
                    cols: f.dim("cols")?,
                    rows: f.dim("rows")?,
                    started_at: f.uint("started_at")?,
                },
            },
            "snapshot" => TermMsg::Snapshot {
                data: f.bytes("data")?,
                last: f.boolean("last")?,
            },
            "out" => TermMsg::Out {
                data: f.bytes("data")?,
            },
            "size" => TermMsg::Size {
                cols: f.dim("cols")?,
                rows: f.dim("rows")?,
            },
            "local" => TermMsg::Local,
            "exit" => TermMsg::Exit {
                code: f.u32("code")?,
            },
            _ => return Ok(None),
        }))
    }
}

impl AgentMsg {
    pub fn encode(&self) -> Vec<u8> {
        match self {
            AgentMsg::Challenge { nonce, mac } => message(
                "challenge",
                vec![
                    ("nonce", Value::Bytes(nonce.to_vec())),
                    ("mac", Value::Bytes(mac.to_vec())),
                ],
            ),
            AgentMsg::Ready => message("ready", vec![]),
            AgentMsg::Reject { reason } => {
                let reason = match reason {
                    RejectReason::Limit => "limit",
                    RejectReason::Version => "version",
                    RejectReason::Other(s) => s.as_str(),
                };
                message("reject", vec![("reason", text(reason))])
            }
            AgentMsg::In { data } => message("in", vec![("data", Value::Bytes(data.clone()))]),
            AgentMsg::Resize { cols, rows } => message(
                "resize",
                vec![
                    ("cols", Value::Uint((*cols).into())),
                    ("rows", Value::Uint((*rows).into())),
                ],
            ),
            AgentMsg::LocalSize => message("local_size", vec![]),
        }
    }

    /// `Ok(None)` for a message type this version does not know.
    pub fn decode(bytes: &[u8]) -> Result<Option<AgentMsg>, ProtoError> {
        let f = Fields::parse(bytes)?;
        Ok(Some(match f.t.as_str() {
            "challenge" => AgentMsg::Challenge {
                nonce: f.array("nonce")?,
                mac: f.array("mac")?,
            },
            "ready" => AgentMsg::Ready,
            "reject" => AgentMsg::Reject {
                reason: match f.text("reason")?.as_str() {
                    "limit" => RejectReason::Limit,
                    "version" => RejectReason::Version,
                    other => RejectReason::Other(other.to_string()),
                },
            },
            "in" => AgentMsg::In {
                data: f.bytes("data")?,
            },
            "resize" => AgentMsg::Resize {
                cols: f.dim("cols")?,
                rows: f.dim("rows")?,
            },
            "local_size" => AgentMsg::LocalSize,
            _ => return Ok(None),
        }))
    }
}

#[cfg(test)]
pub(crate) mod tests {
    use super::*;

    pub(crate) fn hex(bytes: &[u8]) -> String {
        bytes.iter().map(|b| format!("{b:02x}")).collect()
    }

    pub(crate) fn unhex(s: &str) -> Vec<u8> {
        (0..s.len())
            .step_by(2)
            .map(|i| u8::from_str_radix(&s[i..i + 2], 16).unwrap())
            .collect()
    }

    pub(crate) fn sample_info() -> TermInfo {
        TermInfo {
            term_id: [0x11; 16],
            app: "Terminal".into(),
            shell: "zsh".into(),
            pid: 4242,
            cols: 80,
            rows: 24,
            started_at: 1_759_276_800_000,
        }
    }

    /// Every message with fixed values, named as in vectors.txt.
    pub(crate) fn term_samples() -> Vec<(&'static str, TermMsg)> {
        let nonce_term: [u8; 32] = std::array::from_fn(|i| i as u8 + 1);
        vec![
            (
                "hello",
                TermMsg::Hello {
                    v: 1,
                    nonce: nonce_term,
                },
            ),
            (
                "auth",
                TermMsg::Auth {
                    mac: [0x55; 32],
                    info: sample_info(),
                },
            ),
            (
                "snapshot",
                TermMsg::Snapshot {
                    data: b"$ ls\r\n".to_vec(),
                    last: true,
                },
            ),
            (
                "out",
                TermMsg::Out {
                    data: "tiếng Việt\r\n".as_bytes().to_vec(),
                },
            ),
            (
                "size",
                TermMsg::Size {
                    cols: 120,
                    rows: 40,
                },
            ),
            ("local", TermMsg::Local),
            ("exit", TermMsg::Exit { code: 130 }),
        ]
    }

    pub(crate) fn agent_samples() -> Vec<(&'static str, AgentMsg)> {
        let nonce_agent: [u8; 32] = std::array::from_fn(|i| 0x80 + i as u8);
        vec![
            (
                "challenge",
                AgentMsg::Challenge {
                    nonce: nonce_agent,
                    mac: [0x66; 32],
                },
            ),
            ("ready", AgentMsg::Ready),
            (
                "reject_limit",
                AgentMsg::Reject {
                    reason: RejectReason::Limit,
                },
            ),
            (
                "reject_version",
                AgentMsg::Reject {
                    reason: RejectReason::Version,
                },
            ),
            (
                "in",
                AgentMsg::In {
                    data: b"echo hi\r".to_vec(),
                },
            ),
            ("resize", AgentMsg::Resize { cols: 50, rows: 20 }),
            ("local_size", AgentMsg::LocalSize),
        ]
    }

    #[test]
    fn every_term_message_round_trips() {
        for (name, msg) in term_samples() {
            assert_eq!(TermMsg::decode(&msg.encode()).unwrap(), Some(msg), "{name}");
        }
    }

    #[test]
    fn every_agent_message_round_trips() {
        for (name, msg) in agent_samples() {
            assert_eq!(
                AgentMsg::decode(&msg.encode()).unwrap(),
                Some(msg),
                "{name}"
            );
        }
    }

    #[test]
    fn local_has_exactly_the_documented_bytes() {
        assert_eq!(hex(&TermMsg::Local.encode()), "a16174656c6f63616c");
    }

    #[test]
    fn unknown_types_are_ignored_not_errors() {
        let mut map = Map::new();
        map.insert("t".into(), Value::Text("from_the_future".into()));
        map.insert("x".into(), Value::Uint(1));
        let bytes = encode_map(&map);
        assert_eq!(TermMsg::decode(&bytes).unwrap(), None);
        assert_eq!(AgentMsg::decode(&bytes).unwrap(), None);
    }

    #[test]
    fn wrong_or_missing_fields_are_errors() {
        let mut map = Map::new();
        map.insert("t".into(), Value::Text("resize".into()));
        map.insert("cols".into(), Value::Uint(0)); // zero columns
        map.insert("rows".into(), Value::Uint(20));
        assert!(AgentMsg::decode(&encode_map(&map)).is_err());
        let mut map = Map::new();
        map.insert("t".into(), Value::Text("challenge".into()));
        map.insert("nonce".into(), Value::Bytes(vec![1; 31])); // 31 bytes
        map.insert("mac".into(), Value::Bytes(vec![1; 32]));
        assert!(AgentMsg::decode(&encode_map(&map)).is_err());
        assert!(TermMsg::decode(&encode_map(&Map::new())).is_err()); // no "t"
    }

    #[test]
    fn unknown_reject_reasons_are_kept() {
        let mut map = Map::new();
        map.insert("t".into(), Value::Text("reject".into()));
        map.insert("reason".into(), Value::Text("maintenance".into()));
        assert_eq!(
            AgentMsg::decode(&encode_map(&map)).unwrap(),
            Some(AgentMsg::Reject {
                reason: RejectReason::Other("maintenance".into())
            })
        );
    }

    /// Writes term/protocol/vectors.txt from the samples. Run once after a
    /// deliberate protocol change, review the diff, commit it:
    /// `cargo test --features test-hooks write_vectors -- --ignored`
    #[test]
    #[ignore]
    fn write_vectors() {
        let mut out = String::from(
            "# Local-link reference bytes (spec §6). name=hex of the CBOR map\n# (frame length prefix not included). Generated by write_vectors; pinned by vectors_match.\n# Map keys are in bytewise-sorted order (Rust BTreeMap), NOT RFC 8949 length-first canonical order; decoders accept any order, but matching these bytes needs this key order.\n",
        );
        for (name, msg) in term_samples() {
            out.push_str(&format!("term.{name}={}\n", hex(&msg.encode())));
        }
        for (name, msg) in agent_samples() {
            out.push_str(&format!("agent.{name}={}\n", hex(&msg.encode())));
        }
        std::fs::write(
            concat!(env!("CARGO_MANIFEST_DIR"), "/protocol/vectors.txt"),
            out,
        )
        .unwrap();
    }

    pub(crate) fn vector(name: &str) -> Option<String> {
        include_str!("../../protocol/vectors.txt")
            .lines()
            .find_map(|line| line.strip_prefix(&format!("{name}=")).map(str::to_string))
    }

    #[test]
    fn vectors_match() {
        for (name, msg) in term_samples() {
            let expected = vector(&format!("term.{name}")).expect(name);
            assert_eq!(hex(&msg.encode()), expected, "term.{name}");
            assert_eq!(TermMsg::decode(&unhex(&expected)).unwrap(), Some(msg));
        }
        for (name, msg) in agent_samples() {
            let expected = vector(&format!("agent.{name}")).expect(name);
            assert_eq!(hex(&msg.encode()), expected, "agent.{name}");
            assert_eq!(AgentMsg::decode(&unhex(&expected)).unwrap(), Some(msg));
        }
    }
}
