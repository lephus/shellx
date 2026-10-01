# Terminal Sharing P2a — `shellx-term` Agent Link (macOS) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give `shellx-term` its side of the local link to the ShellX agent (spec §6): authenticate over `127.0.0.1`, stream a 256 KiB snapshot plus live output, apply the phone's input and size, report exit. Also fold in the P2 items recorded after P1 (window title, `SHELLX_TERM` per tty, `setopt login`, `probe`, bash manual `source`, SIGTERM-ignore inheritance). macOS only; Windows is plan P2b.

**Architecture:** The crate becomes lib + bin (`src/lib.rs` holds every module; `src/main.rs` is thin) so integration tests can play the agent with the real protocol code. New pure modules — `proto/{cbor,frame,messages,auth,endpoint,handshake}`, `ring`, `outbox`, `size` — are unit-tested in isolation; `link` runs one background thread that connects, authenticates and pumps frames, and is tested against an in-process fake agent; `wrap` tees PTY output into the link and routes phone input/size through a shared PTY writer and a size state machine. Nothing on the terminal's path waits for the agent: output goes into a bounded outbox that drops the session (never the terminal) when full.

**Tech Stack:** Rust 1.95; `portable-pty 0.9.0`, `signal-hook 0.4.4`, `libc 0.2.189`, `hmac 0.13.0`, `sha2 0.11.0`, `getrandom 0.4.3`; zsh 5.9 / bash 3.2.

**Spec:** `docs/superpowers/specs/2026-10-01-desktop-terminal-sharing-design.md` (§5.1–5.5, §6). P1 results and the P2 list: `docs/superpowers/ledgers/terminal-sharing.md` ("Quyết định sau P1", "Ghi cho P2").

## Global Constraints

- Work on branch `feat/terminal-sharing-p2a` in worktree `.claude/worktrees/terminal-sharing-p2a`, cut from `feat/shellx-v1`. Merge locally after the final review. **Never push.**
- Dependencies are exactly `portable-pty = "0.9.0"`, `signal-hook = "0.4.4"`, `libc = "0.2.189"`, `hmac = "0.13.0"`, `sha2 = "0.11.0"`, `getrandom = "0.4.3"`. No others.
- macOS only. Non-Unix builds stay the stub that exits 222.
- Protocol constants (spec §6, amended in Task 8):
  - `PROTOCOL_VERSION = 1`.
  - Frame: 4-byte big-endian length + CBOR map; payload ≤ 65536 bytes.
  - `snapshot`/`out` data pieces ≤ 60 KiB (`61440` bytes).
  - Ring buffer 256 KiB (`262144`); outbox limit 1 MiB (`1048576` encoded bytes).
  - Handshake deadline 5 s; reconnect backoff 1, 2, 4, 8, then 10 s; `reject limit` retry 30 s; `reject version` re-reads the endpoint every 10 s and retries only when its contents change.
  - Socket write timeout 1 s; on exit, at most 200 ms to flush `exit`.
- HMAC-SHA256 with labels exactly `shellx-term/agent` (agent proves first: label ‖ nonce_term ‖ nonce_agent) and `shellx-term/term` (label ‖ nonce_agent ‖ nonce_term).
- Endpoint file: `$HOME/Library/Application Support/ShellX/term/endpoint`, UTF-8 text, exactly three lines `v=1`, `port=<decimal 1..65535>`, `secret=<64 lowercase hex>` (a trailing newline is allowed).
- Environment variables:
  - `SHELLX_TERM` = the inner PTY's tty path (was `1`; the fallback sets it to the window's own tty, or `0` when there is no tty).
  - `SHELLX_TERM_WRAP` = absolute path of the shell to wrap; `SHELLX_TERM_WRAP_LOGIN=1` for a login inner shell. Both are set by the bash block and removed from the inner shell's environment.
  - `SHELLX_TERM_LOGIN=1` is the zsh marker that makes the inner zsh run `setopt login`.
  - `SHELLX_TERM_TIMING=fast` and `SHELLX_TERM_FAULT` work only with feature `test-hooks`.
- The terminal never waits for the agent: no lock or I/O on the window↔PTY path may block on the socket.
- Never touch the real `~/.zshrc`, `~/.bashrc`, `~/.bash_profile` or `~/Library/Application Support/ShellX`. Tests use temp HOMEs only.
- Startup budget: the zsh block plus `shellx-term` adds < 50 ms median to opening a window (re-measured in Task 7).
- Gate for every task, from `term/`: `cargo fmt --check && cargo clippy --all-targets --features test-hooks -- -D warnings && cargo test --features test-hooks`. Run the full suite 3× in a row before each commit; flakiness is a bug.
- Commit messages: `feat(term): …`, `test(term): …`, `docs: …`.

## Review Focus

1. **A hung agent (accepts but stops reading)** must not slow the terminal at all. The link drops the session and resyncs later from the snapshot. Pinned in Task 5 (`link.rs` tests) and Task 6 (end-to-end flood test).
2. **The agent restarting mid-session** (new port and secret in the endpoint file) must not affect the terminal. It reconnects with the same `term_id` and a fresh snapshot. Pinned in Task 5.
3. **A process on the endpoint port that does not know the secret** must never receive a terminal byte; only `hello` leaves. Pinned in Task 2 and Task 5.
4. **Phone and desktop typing at the same moment** must keep each side's bytes intact, and both commands must run. Pinned in Task 6.
5. **The shell exiting while the agent is hung or gone** must close the window promptly: ≤ 200 ms flush on top of the existing 500 ms output drain. Pinned in Task 6.

---

### Task 1: Library split, CBOR codec, frames, messages, golden vectors

**Files:**
- Create: `term/src/lib.rs`, `term/src/proto/mod.rs`, `term/src/proto/cbor.rs`, `term/src/proto/frame.rs`, `term/src/proto/messages.rs`, `term/protocol/vectors.txt`
- Modify: `term/src/main.rs` (use the library instead of `mod` declarations)
- Test: unit tests inside the three new proto files

**Interfaces:**
- Produces:
  - `shellx_term::proto::cbor::{Value, Map, CborError, encode_map, decode_map}`
  - `shellx_term::proto::frame::{MAX_FRAME, write_frame, read_frame}`
  - `shellx_term::proto::messages::{PROTOCOL_VERSION, TermInfo, TermMsg, AgentMsg, RejectReason, ProtoError}` with `TermMsg::{encode, decode}` and `AgentMsg::{encode, decode}`; `decode` returns `Ok(None)` for an unknown `t`
  - `term/protocol/vectors.txt` (`name=hex` lines), the reference bytes for the agent's Dart side (plan P3)

- [ ] **Step 1: Worktree and dependencies**

```bash
cd /Users/lehuuphu/Documents/myProjects/shellx
git worktree add .claude/worktrees/terminal-sharing-p2a -b feat/terminal-sharing-p2a feat/shellx-v1
cd .claude/worktrees/terminal-sharing-p2a/term
cargo add hmac@0.13.0 sha2@0.11.0 getrandom@0.4.3
mkdir -p src/proto protocol
```

(The controller may already have created the worktree; skip the `git worktree add` line if so.)

- [ ] **Step 2: Split into library + binary**

`term/src/lib.rs`:

```rust
//! `shellx-term` as a library. The binary (`src/main.rs`) is a thin
//! wrapper; integration tests use the protocol modules to play the ShellX
//! agent's side of the local link.
//! Spec: docs/superpowers/specs/2026-10-01-desktop-terminal-sharing-design.md

pub mod cli;
pub mod proto;
#[cfg(unix)]
pub mod fallback;
#[cfg(unix)]
pub mod faults;
#[cfg(unix)]
pub mod tty;
#[cfg(unix)]
pub mod wrap;
```

In `term/src/main.rs`, delete the `mod cli;` … `mod wrap;` lines (all six module declarations with their `#[cfg(unix)]` attributes) and put this right after the file's doc comment:

```rust
#[cfg(unix)]
use shellx_term::{cli, fallback, tty, wrap};
```

`term/src/proto/mod.rs`:

```rust
//! The local link between `shellx-term` and the ShellX agent (spec §6).

pub mod cbor;
pub mod frame;
pub mod messages;
```

Run: `cd term && cargo test --features test-hooks`
Expected: compile error until Steps 3–7 create `cbor.rs`, `frame.rs`, `messages.rs`. Create them as empty files containing only their `//!` doc line to confirm the split itself builds and all existing tests still pass, then continue.

- [ ] **Step 3: CBOR codec — failing tests**

`term/src/proto/cbor.rs`:

```rust
//! The small CBOR subset the local link uses (spec §6.2): one map with text
//! keys whose values are unsigned integers, byte strings, text strings or
//! booleans. Definite lengths only; integers in their shortest form.

use std::collections::BTreeMap;

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Value {
    Uint(u64),
    Bytes(Vec<u8>),
    Text(String),
    Bool(bool),
}

/// Keys sorted, so encodings are deterministic.
pub type Map = BTreeMap<String, Value>;

#[derive(Debug, PartialEq, Eq)]
pub struct CborError(pub &'static str);

pub fn encode_map(map: &Map) -> Vec<u8> {
    let _ = map;
    todo!("Step 4")
}

pub fn decode_map(bytes: &[u8]) -> Result<Map, CborError> {
    let _ = bytes;
    todo!("Step 4")
}

#[cfg(test)]
mod tests {
    use super::*;

    fn hex(bytes: &[u8]) -> String {
        bytes.iter().map(|b| format!("{b:02x}")).collect()
    }

    fn map(entries: &[(&str, Value)]) -> Map {
        entries.iter().map(|(k, v)| (k.to_string(), v.clone())).collect()
    }

    #[test]
    fn encodes_a_one_key_map_exactly() {
        // {"t": "local"} — a1, 61 74, 65 6c 6f 63 61 6c
        let m = map(&[("t", Value::Text("local".into()))]);
        assert_eq!(hex(&encode_map(&m)), "a16174656c6f63616c");
    }

    #[test]
    fn integers_use_the_shortest_form() {
        for (n, expected) in [
            (0u64, "a1616e00"),
            (23, "a1616e17"),
            (24, "a1616e1818"),
            (255, "a1616e18ff"),
            (256, "a1616e190100"),
            (65536, "a1616e1a00010000"),
            (1u64 << 32, "a1616e1b0000000100000000"),
        ] {
            assert_eq!(hex(&encode_map(&map(&[("n", Value::Uint(n))]))), expected, "{n}");
        }
    }

    #[test]
    fn round_trips_every_value_type() {
        let m = map(&[
            ("a", Value::Uint(4242)),
            ("b", Value::Bytes(vec![0, 1, 2, 255])),
            ("c", Value::Text("tiếng Việt".into())),
            ("d", Value::Bool(true)),
            ("e", Value::Bool(false)),
            ("f", Value::Bytes(vec![7; 70_000])),
        ]);
        assert_eq!(decode_map(&encode_map(&m)).unwrap(), m);
    }

    #[test]
    fn rejects_malformed_input() {
        for bad in [
            &[][..],                 // empty
            &[0xa1][..],             // map with a missing entry
            &[0x61, 0x74][..],       // not a map
            &[0xa1, 0x01, 0x01][..], // key is not text
            &[0xbf][..],             // indefinite-length map
            &[0xa1, 0x61, 0x74, 0x5a, 0xff, 0xff, 0xff, 0xff][..], // byte string longer than input
            &[0xa1, 0x61, 0x74, 0x80][..], // array value (unsupported)
            &[0xa1, 0x61, 0x74, 0x01, 0x00][..], // trailing byte
            &[0xa2, 0x61, 0x74, 0x01, 0x61, 0x74, 0x02][..], // duplicate key
        ] {
            assert!(decode_map(bad).is_err(), "{}", hex(bad));
        }
    }
}
```

Run: `cd term && cargo test --features test-hooks proto::cbor`
Expected: 4 tests FAIL with "not yet implemented: Step 4".

- [ ] **Step 4: CBOR codec — implementation**

Replace the two `todo!` functions in `term/src/proto/cbor.rs`:

```rust
pub fn encode_map(map: &Map) -> Vec<u8> {
    let mut out = Vec::new();
    head(&mut out, 5, map.len() as u64);
    for (key, value) in map {
        head(&mut out, 3, key.len() as u64);
        out.extend_from_slice(key.as_bytes());
        match value {
            Value::Uint(n) => head(&mut out, 0, *n),
            Value::Bytes(b) => {
                head(&mut out, 2, b.len() as u64);
                out.extend_from_slice(b);
            }
            Value::Text(s) => {
                head(&mut out, 3, s.len() as u64);
                out.extend_from_slice(s.as_bytes());
            }
            Value::Bool(b) => out.push(if *b { 0xf5 } else { 0xf4 }),
        }
    }
    out
}

fn head(out: &mut Vec<u8>, major: u8, n: u64) {
    let m = major << 5;
    if n < 24 {
        out.push(m | n as u8);
    } else if n <= 0xff {
        out.push(m | 24);
        out.push(n as u8);
    } else if n <= 0xffff {
        out.push(m | 25);
        out.extend_from_slice(&(n as u16).to_be_bytes());
    } else if n <= 0xffff_ffff {
        out.push(m | 26);
        out.extend_from_slice(&(n as u32).to_be_bytes());
    } else {
        out.push(m | 27);
        out.extend_from_slice(&n.to_be_bytes());
    }
}

pub fn decode_map(bytes: &[u8]) -> Result<Map, CborError> {
    let mut r = Reader { bytes, pos: 0 };
    let (major, len) = r.head()?;
    if major != 5 {
        return Err(CborError("not a map"));
    }
    let mut map = Map::new();
    for _ in 0..len {
        let (key_major, key_len) = r.head()?;
        if key_major != 3 {
            return Err(CborError("map key is not text"));
        }
        let key = String::from_utf8(r.take(key_len)?.to_vec())
            .map_err(|_| CborError("key is not UTF-8"))?;
        let value = r.value()?;
        if map.insert(key, value).is_some() {
            return Err(CborError("duplicate key"));
        }
    }
    if r.pos != bytes.len() {
        return Err(CborError("trailing bytes"));
    }
    Ok(map)
}

struct Reader<'a> {
    bytes: &'a [u8],
    pos: usize,
}

impl<'a> Reader<'a> {
    fn byte(&mut self) -> Result<u8, CborError> {
        let b = *self.bytes.get(self.pos).ok_or(CborError("truncated"))?;
        self.pos += 1;
        Ok(b)
    }

    fn take(&mut self, n: u64) -> Result<&'a [u8], CborError> {
        let n = usize::try_from(n).map_err(|_| CborError("too long"))?;
        let end = self
            .pos
            .checked_add(n)
            .filter(|end| *end <= self.bytes.len())
            .ok_or(CborError("truncated"))?;
        let slice = &self.bytes[self.pos..end];
        self.pos = end;
        Ok(slice)
    }

    fn head(&mut self) -> Result<(u8, u64), CborError> {
        let b = self.byte()?;
        let n = match b & 0x1f {
            info @ 0..=23 => u64::from(info),
            24 => u64::from(self.byte()?),
            25 => u64::from(u16::from_be_bytes(self.take(2)?.try_into().unwrap())),
            26 => u64::from(u32::from_be_bytes(self.take(4)?.try_into().unwrap())),
            27 => u64::from_be_bytes(self.take(8)?.try_into().unwrap()),
            _ => return Err(CborError("indefinite or reserved length")),
        };
        Ok((b >> 5, n))
    }

    fn value(&mut self) -> Result<Value, CborError> {
        match self.bytes.get(self.pos) {
            Some(0xf4) => {
                self.pos += 1;
                return Ok(Value::Bool(false));
            }
            Some(0xf5) => {
                self.pos += 1;
                return Ok(Value::Bool(true));
            }
            _ => {}
        }
        let (major, n) = self.head()?;
        match major {
            0 => Ok(Value::Uint(n)),
            2 => Ok(Value::Bytes(self.take(n)?.to_vec())),
            3 => String::from_utf8(self.take(n)?.to_vec())
                .map(Value::Text)
                .map_err(|_| CborError("text is not UTF-8")),
            _ => Err(CborError("unsupported value type")),
        }
    }
}
```

Run: `cd term && cargo test --features test-hooks proto::cbor`
Expected: 4 passed.

- [ ] **Step 5: Frames — tests and implementation**

`term/src/proto/frame.rs`:

```rust
//! Frames on the local link: a 4-byte big-endian length, then that many
//! bytes of CBOR (spec §6.2). At most 64 KiB per frame.

use std::io::{self, Read, Write};

pub const MAX_FRAME: usize = 64 * 1024;

/// Writes one frame with a single `write_all`.
pub fn write_frame(w: &mut impl Write, payload: &[u8]) -> io::Result<()> {
    if payload.len() > MAX_FRAME {
        return Err(io::Error::new(io::ErrorKind::InvalidInput, "frame too large"));
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
        return Err(io::Error::new(io::ErrorKind::InvalidData, "frame too large"));
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
```

Run: `cd term && cargo test --features test-hooks proto::frame`
Expected: 3 passed.

- [ ] **Step 6: Messages — tests first**

`term/src/proto/messages.rs` with only the types, `todo!` bodies and tests:

```rust
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
    Hello { v: u64, nonce: [u8; 32] },
    Auth { mac: [u8; 32], info: TermInfo },
    /// One piece of the output buffer; `last` marks the final piece. The
    /// pieces are always the first frames after `ready` (spec §6.4).
    Snapshot { data: Vec<u8>, last: bool },
    Out { data: Vec<u8> },
    Size { cols: u16, rows: u16 },
    Local,
    Exit { code: u32 },
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

impl TermMsg {
    pub fn encode(&self) -> Vec<u8> {
        todo!("Step 7")
    }

    /// `Ok(None)` for a message type this version does not know.
    pub fn decode(bytes: &[u8]) -> Result<Option<TermMsg>, ProtoError> {
        let _ = bytes;
        todo!("Step 7")
    }
}

impl AgentMsg {
    pub fn encode(&self) -> Vec<u8> {
        todo!("Step 7")
    }

    /// `Ok(None)` for a message type this version does not know.
    pub fn decode(bytes: &[u8]) -> Result<Option<AgentMsg>, ProtoError> {
        let _ = bytes;
        todo!("Step 7")
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
            ("hello", TermMsg::Hello { v: 1, nonce: nonce_term }),
            ("auth", TermMsg::Auth { mac: [0x55; 32], info: sample_info() }),
            ("snapshot", TermMsg::Snapshot { data: b"$ ls\r\n".to_vec(), last: true }),
            ("out", TermMsg::Out { data: "tiếng Việt\r\n".as_bytes().to_vec() }),
            ("size", TermMsg::Size { cols: 120, rows: 40 }),
            ("local", TermMsg::Local),
            ("exit", TermMsg::Exit { code: 130 }),
        ]
    }

    pub(crate) fn agent_samples() -> Vec<(&'static str, AgentMsg)> {
        let nonce_agent: [u8; 32] = std::array::from_fn(|i| 0x80 + i as u8);
        vec![
            ("challenge", AgentMsg::Challenge { nonce: nonce_agent, mac: [0x66; 32] }),
            ("ready", AgentMsg::Ready),
            ("reject_limit", AgentMsg::Reject { reason: RejectReason::Limit }),
            ("reject_version", AgentMsg::Reject { reason: RejectReason::Version }),
            ("in", AgentMsg::In { data: b"echo hi\r".to_vec() }),
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
            assert_eq!(AgentMsg::decode(&msg.encode()).unwrap(), Some(msg), "{name}");
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
            Some(AgentMsg::Reject { reason: RejectReason::Other("maintenance".into()) })
        );
    }

    /// Writes term/protocol/vectors.txt from the samples. Run once after a
    /// deliberate protocol change, review the diff, commit it:
    /// `cargo test --features test-hooks write_vectors -- --ignored`
    #[test]
    #[ignore]
    fn write_vectors() {
        let mut out = String::from(
            "# Local-link reference bytes (spec §6). name=hex of the CBOR map\n# (frame length prefix not included). Generated by write_vectors; pinned by vectors_match.\n",
        );
        for (name, msg) in term_samples() {
            out.push_str(&format!("term.{name}={}\n", hex(&msg.encode())));
        }
        for (name, msg) in agent_samples() {
            out.push_str(&format!("agent.{name}={}\n", hex(&msg.encode())));
        }
        std::fs::write(concat!(env!("CARGO_MANIFEST_DIR"), "/protocol/vectors.txt"), out).unwrap();
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
```

Create `term/protocol/vectors.txt` containing just the two header lines (so `include_str!` compiles):

```
# Local-link reference bytes (spec §6). name=hex of the CBOR map
# (frame length prefix not included). Generated by write_vectors; pinned by vectors_match.
```

Run: `cd term && cargo test --features test-hooks proto::messages`
Expected: the round-trip/bytes/unknown/field tests FAIL with "not yet implemented: Step 7"; `vectors_match` fails (missing vectors).

- [ ] **Step 7: Messages — implementation, then vectors**

Replace the four `todo!` bodies and add the helpers above the `#[cfg(test)]` module in `messages.rs`:

```rust
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
                vec![("v", Value::Uint(*v)), ("nonce", Value::Bytes(nonce.to_vec()))],
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
                vec![("data", Value::Bytes(data.clone())), ("last", Value::Bool(*last))],
            ),
            TermMsg::Out { data } => message("out", vec![("data", Value::Bytes(data.clone()))]),
            TermMsg::Size { cols, rows } => message(
                "size",
                vec![("cols", Value::Uint((*cols).into())), ("rows", Value::Uint((*rows).into()))],
            ),
            TermMsg::Local => message("local", vec![]),
            TermMsg::Exit { code } => message("exit", vec![("code", Value::Uint((*code).into()))]),
        }
    }

    /// `Ok(None)` for a message type this version does not know.
    pub fn decode(bytes: &[u8]) -> Result<Option<TermMsg>, ProtoError> {
        let f = Fields::parse(bytes)?;
        Ok(Some(match f.t.as_str() {
            "hello" => TermMsg::Hello { v: f.uint("v")?, nonce: f.array("nonce")? },
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
            "snapshot" => TermMsg::Snapshot { data: f.bytes("data")?, last: f.boolean("last")? },
            "out" => TermMsg::Out { data: f.bytes("data")? },
            "size" => TermMsg::Size { cols: f.dim("cols")?, rows: f.dim("rows")? },
            "local" => TermMsg::Local,
            "exit" => TermMsg::Exit { code: f.u32("code")? },
            _ => return Ok(None),
        }))
    }
}

impl AgentMsg {
    pub fn encode(&self) -> Vec<u8> {
        match self {
            AgentMsg::Challenge { nonce, mac } => message(
                "challenge",
                vec![("nonce", Value::Bytes(nonce.to_vec())), ("mac", Value::Bytes(mac.to_vec()))],
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
                vec![("cols", Value::Uint((*cols).into())), ("rows", Value::Uint((*rows).into()))],
            ),
            AgentMsg::LocalSize => message("local_size", vec![]),
        }
    }

    /// `Ok(None)` for a message type this version does not know.
    pub fn decode(bytes: &[u8]) -> Result<Option<AgentMsg>, ProtoError> {
        let f = Fields::parse(bytes)?;
        Ok(Some(match f.t.as_str() {
            "challenge" => AgentMsg::Challenge { nonce: f.array("nonce")?, mac: f.array("mac")? },
            "ready" => AgentMsg::Ready,
            "reject" => AgentMsg::Reject {
                reason: match f.text("reason")?.as_str() {
                    "limit" => RejectReason::Limit,
                    "version" => RejectReason::Version,
                    other => RejectReason::Other(other.to_string()),
                },
            },
            "in" => AgentMsg::In { data: f.bytes("data")? },
            "resize" => AgentMsg::Resize { cols: f.dim("cols")?, rows: f.dim("rows")? },
            "local_size" => AgentMsg::LocalSize,
            _ => return Ok(None),
        }))
    }
}
```

Run: `cd term && cargo test --features test-hooks proto::messages` → all pass except `vectors_match`.
Run: `cd term && cargo test --features test-hooks write_vectors -- --ignored` → writes `term/protocol/vectors.txt`. Check that its `term.local` line is `a16174656c6f63616c`, then run `cargo test --features test-hooks proto::messages` again.
Expected: all pass.

- [ ] **Step 8: Gate and commit**

Run the gate (Global Constraints) and the full suite 3×.

```bash
git add term
git commit -m "feat(term): library split; local-link CBOR codec, frames, messages and reference vectors"
```

---

### Task 2: HMAC proofs, endpoint file, client handshake, fake agent

**Files:**
- Create: `term/src/proto/auth.rs`, `term/src/proto/endpoint.rs`, `term/src/proto/handshake.rs`
- Modify: `term/src/proto/mod.rs` (add the three modules), `term/protocol/vectors.txt` (append proof vectors)
- Create: `term/tests/common/fake_agent.rs`; Modify: `term/tests/common/mod.rs` (add `pub mod fake_agent;`)
- Test: unit tests in `auth.rs`/`endpoint.rs`; `term/tests/handshake.rs`

**Interfaces:**
- Consumes: Task 1 `messages::{TermMsg, AgentMsg, TermInfo, RejectReason, PROTOCOL_VERSION}`, `frame::{read_frame, write_frame}`.
- Produces:
  - `proto::auth::{AGENT_LABEL, TERM_LABEL, agent_proof(&[u8;32], &[u8;32], &[u8;32]) -> [u8;32], term_proof(...) -> [u8;32], verify_agent(secret, nonce_term, nonce_agent, mac: &[u8]) -> bool, verify_term(secret, nonce_agent, nonce_term, mac: &[u8]) -> bool}`
  - `proto::endpoint::{Endpoint { port: u16, secret: [u8;32], raw: Vec<u8> }, EndpointError, parse_endpoint(&[u8]) -> Result<Endpoint, EndpointError>, read_endpoint(&Path) -> Result<Endpoint, EndpointError>, endpoint_path_in(home: &Path) -> PathBuf, default_endpoint_path() -> Option<PathBuf>, format_endpoint(port: u16, secret: &[u8;32]) -> String}`
  - `proto::handshake::{HandshakeOutcome { Ready, Rejected(RejectReason) }, HandshakeError { Io(io::Error), Timeout, BadAgentProof, Protocol(String), Random }, handshake(&mut TcpStream, &[u8;32], &TermInfo, Duration) -> Result<HandshakeOutcome, HandshakeError>}`
  - `tests/common/fake_agent.rs`: `FakeAgent::{start(home, Behavior), next_attempt(Duration) -> Attempt, next_session(Duration) -> AgentSession}`, `Behavior { Normal, WrongProof, Silent, RejectLimit, RejectVersion }`, `Attempt { Session(AgentSession), Ended { after_hello: Vec<TermMsg> } }`, `AgentSession { info: TermInfo, … }` with `recv(Duration) -> Option<TermMsg>`, `send(&AgentMsg)`, `snapshot(Duration) -> Vec<u8>`, `expect_out(&str, Duration) -> String`, `expect_msg(impl Fn(&TermMsg) -> bool, Duration) -> TermMsg`, `close(self)`

- [ ] **Step 1: Proofs — tests then code**

`term/src/proto/auth.rs`:

```rust
//! Mutual proof of the endpoint secret (spec §6.3). The agent proves first,
//! so a process squatting on the port without the secret never receives a
//! terminal byte.

use hmac::{Hmac, KeyInit, Mac};
use sha2::Sha256;

type HmacSha256 = Hmac<Sha256>;

pub const AGENT_LABEL: &[u8] = b"shellx-term/agent";
pub const TERM_LABEL: &[u8] = b"shellx-term/term";

fn mac(secret: &[u8; 32], label: &[u8], first: &[u8; 32], second: &[u8; 32]) -> HmacSha256 {
    let mut m = <HmacSha256 as KeyInit>::new_from_slice(secret).expect("HMAC takes any key length");
    m.update(label);
    m.update(first);
    m.update(second);
    m
}

fn bytes(m: HmacSha256) -> [u8; 32] {
    let mut out = [0u8; 32];
    out.copy_from_slice(&m.finalize().into_bytes());
    out
}

/// HMAC(secret, "shellx-term/agent" ‖ nonce_term ‖ nonce_agent).
pub fn agent_proof(secret: &[u8; 32], nonce_term: &[u8; 32], nonce_agent: &[u8; 32]) -> [u8; 32] {
    bytes(mac(secret, AGENT_LABEL, nonce_term, nonce_agent))
}

/// HMAC(secret, "shellx-term/term" ‖ nonce_agent ‖ nonce_term).
pub fn term_proof(secret: &[u8; 32], nonce_agent: &[u8; 32], nonce_term: &[u8; 32]) -> [u8; 32] {
    bytes(mac(secret, TERM_LABEL, nonce_agent, nonce_term))
}

/// Constant-time check of the agent's proof.
pub fn verify_agent(secret: &[u8; 32], nonce_term: &[u8; 32], nonce_agent: &[u8; 32], proof: &[u8]) -> bool {
    mac(secret, AGENT_LABEL, nonce_term, nonce_agent).verify_slice(proof).is_ok()
}

/// Constant-time check of the terminal's proof (used by the agent; tests).
pub fn verify_term(secret: &[u8; 32], nonce_agent: &[u8; 32], nonce_term: &[u8; 32], proof: &[u8]) -> bool {
    mac(secret, TERM_LABEL, nonce_agent, nonce_term).verify_slice(proof).is_ok()
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::proto::messages::tests::{hex, vector};

    fn inputs() -> ([u8; 32], [u8; 32], [u8; 32]) {
        let secret = [0x42; 32];
        let nonce_term: [u8; 32] = std::array::from_fn(|i| i as u8 + 1);
        let nonce_agent: [u8; 32] = std::array::from_fn(|i| 0x80 + i as u8);
        (secret, nonce_term, nonce_agent)
    }

    #[test]
    fn proofs_verify_and_differ_by_direction() {
        let (s, t, a) = inputs();
        let agent = agent_proof(&s, &t, &a);
        let term = term_proof(&s, &a, &t);
        assert_ne!(agent, term);
        assert!(verify_agent(&s, &t, &a, &agent));
        assert!(verify_term(&s, &a, &t, &term));
        assert!(!verify_agent(&s, &t, &a, &term));
        assert!(!verify_agent(&[0x43; 32], &t, &a, &agent));
        assert!(!verify_agent(&s, &t, &a, &agent[..31]));
    }

    /// Run once: `cargo test --features test-hooks write_proof_vectors -- --ignored`
    #[test]
    #[ignore]
    fn write_proof_vectors() {
        let (s, t, a) = inputs();
        let path = concat!(env!("CARGO_MANIFEST_DIR"), "/protocol/vectors.txt");
        let text = std::fs::read_to_string(path).unwrap();
        let lines: Vec<&str> = text.lines().filter(|l| !l.starts_with("auth.")).collect();
        let mut out = lines.join("\n");
        out.push('\n');
        out.push_str(&format!("auth.secret={}\n", hex(&s)));
        out.push_str(&format!("auth.nonce_term={}\n", hex(&t)));
        out.push_str(&format!("auth.nonce_agent={}\n", hex(&a)));
        out.push_str(&format!("auth.agent_proof={}\n", hex(&agent_proof(&s, &t, &a))));
        out.push_str(&format!("auth.term_proof={}\n", hex(&term_proof(&s, &a, &t))));
        std::fs::write(path, out).unwrap();
    }

    #[test]
    fn proof_vectors_match() {
        let (s, t, a) = inputs();
        assert_eq!(vector("auth.agent_proof").unwrap(), hex(&agent_proof(&s, &t, &a)));
        assert_eq!(vector("auth.term_proof").unwrap(), hex(&term_proof(&s, &a, &t)));
    }
}
```

Add `pub mod auth;` (and `pub mod endpoint;`, `pub mod handshake;` as you create them) to `term/src/proto/mod.rs`.
Run: `cargo test --features test-hooks proto::auth` → `proof_vectors_match` FAILS (no vectors). Run `cargo test --features test-hooks write_proof_vectors -- --ignored`, then again `proto::auth` → pass.

- [ ] **Step 2: Endpoint file — tests then code**

`term/src/proto/endpoint.rs`:

```rust
//! Where the agent listens: `endpoint` file (spec §6.1). Three lines:
//! `v=1`, `port=<1..65535>`, `secret=<64 lowercase hex>`.

use std::path::{Path, PathBuf};

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Endpoint {
    pub port: u16,
    pub secret: [u8; 32],
    /// The file's exact bytes (to notice when the agent rewrites it).
    pub raw: Vec<u8>,
}

#[derive(Debug, PartialEq, Eq)]
pub enum EndpointError {
    Missing,
    Malformed(&'static str),
    UnsupportedVersion,
}

pub fn endpoint_path_in(home: &Path) -> PathBuf {
    home.join("Library/Application Support/ShellX/term/endpoint")
}

/// `$HOME/Library/Application Support/ShellX/term/endpoint`, if HOME is set.
pub fn default_endpoint_path() -> Option<PathBuf> {
    std::env::var_os("HOME").filter(|h| !h.is_empty()).map(|h| endpoint_path_in(Path::new(&h)))
}

pub fn read_endpoint(path: &Path) -> Result<Endpoint, EndpointError> {
    let raw = std::fs::read(path).map_err(|_| EndpointError::Missing)?;
    parse_endpoint(&raw)
}

pub fn parse_endpoint(raw: &[u8]) -> Result<Endpoint, EndpointError> {
    let text = std::str::from_utf8(raw).map_err(|_| EndpointError::Malformed("not UTF-8"))?;
    let mut lines = text.strip_suffix('\n').unwrap_or(text).split('\n');
    match lines.next() {
        Some("v=1") => {}
        Some(v) if v.starts_with("v=") => return Err(EndpointError::UnsupportedVersion),
        _ => return Err(EndpointError::Malformed("first line must be v=")),
    }
    let port = lines
        .next()
        .and_then(|l| l.strip_prefix("port="))
        .and_then(|p| p.parse::<u16>().ok())
        .filter(|p| *p > 0)
        .ok_or(EndpointError::Malformed("port"))?;
    let hex = lines
        .next()
        .and_then(|l| l.strip_prefix("secret="))
        .filter(|h| h.len() == 64 && h.bytes().all(|b| b.is_ascii_digit() || (b'a'..=b'f').contains(&b)))
        .ok_or(EndpointError::Malformed("secret"))?;
    if lines.next().is_some() {
        return Err(EndpointError::Malformed("extra lines"));
    }
    let mut secret = [0u8; 32];
    for (i, byte) in secret.iter_mut().enumerate() {
        *byte = u8::from_str_radix(&hex[2 * i..2 * i + 2], 16).expect("validated hex");
    }
    Ok(Endpoint { port, secret, raw: raw.to_vec() })
}

/// The file the agent writes (used by tests and, in P3, mirrored in Dart).
pub fn format_endpoint(port: u16, secret: &[u8; 32]) -> String {
    let hex: String = secret.iter().map(|b| format!("{b:02x}")).collect();
    format!("v=1\nport={port}\nsecret={hex}\n")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn round_trips() {
        let secret: [u8; 32] = std::array::from_fn(|i| i as u8 * 7);
        let text = format_endpoint(49152, &secret);
        let ep = parse_endpoint(text.as_bytes()).unwrap();
        assert_eq!((ep.port, ep.secret), (49152, secret));
        assert_eq!(ep.raw, text.as_bytes());
        assert!(parse_endpoint(text.trim_end().as_bytes()).is_ok()); // no final newline
    }

    #[test]
    fn rejects_bad_files() {
        let ok_secret = "ab".repeat(32);
        for (bad, expected) in [
            ("v=2\nport=1\nsecret=00\n".to_string(), EndpointError::UnsupportedVersion),
            ("port=1\n".to_string(), EndpointError::Malformed("first line must be v=")),
            (format!("v=1\nport=0\nsecret={ok_secret}\n"), EndpointError::Malformed("port")),
            (format!("v=1\nport=70000\nsecret={ok_secret}\n"), EndpointError::Malformed("port")),
            ("v=1\nport=5\nsecret=AB\n".to_string(), EndpointError::Malformed("secret")),
            (format!("v=1\nport=5\nsecret={}\n", "AB".repeat(32)), EndpointError::Malformed("secret")),
            (format!("v=1\nport=5\nsecret={ok_secret}\nx=1\n"), EndpointError::Malformed("extra lines")),
        ] {
            assert_eq!(parse_endpoint(bad.as_bytes()).unwrap_err(), expected, "{bad:?}");
        }
        assert_eq!(read_endpoint(Path::new("/nonexistent/endpoint")).unwrap_err(), EndpointError::Missing);
    }

    #[test]
    fn the_path_is_under_application_support() {
        assert_eq!(
            endpoint_path_in(Path::new("/Users/u")),
            PathBuf::from("/Users/u/Library/Application Support/ShellX/term/endpoint")
        );
    }
}
```

Run: `cargo test --features test-hooks proto::endpoint` → 3 passed (write the tests first, run them against a stub returning `Err(EndpointError::Missing)` to see them fail, then the implementation above).

- [ ] **Step 3: Fake agent for integration tests**

`term/tests/common/fake_agent.rs`:

```rust
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
    Ended { after_hello: Vec<TermMsg> },
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
        FakeAgent { port, secret, attempts: rx }
    }

    pub fn next_attempt(&self, timeout: Duration) -> Attempt {
        self.attempts.recv_timeout(timeout).expect("no connection attempt in time")
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
    stream.set_read_timeout(Some(Duration::from_secs(3))).unwrap();
    let mut seen = Vec::new();
    while let Some(msg) = recv_msg(&mut stream) {
        seen.push(msg);
    }
    seen
}

fn serve(mut stream: TcpStream, secret: [u8; 32], behavior: Behavior) -> Attempt {
    stream.set_read_timeout(Some(Duration::from_secs(5))).unwrap();
    let Some(TermMsg::Hello { v, nonce: nonce_term }) = recv_msg(&mut stream) else {
        return Attempt::Ended { after_hello: drain(stream) };
    };
    assert_eq!(v, PROTOCOL_VERSION);
    if let Behavior::Silent = behavior {
        return Attempt::Ended { after_hello: drain(stream) };
    }
    let mut nonce_agent = [0u8; 32];
    getrandom::fill(&mut nonce_agent).unwrap();
    let mut mac = auth::agent_proof(&secret, &nonce_term, &nonce_agent);
    if let Behavior::WrongProof = behavior {
        mac[0] ^= 0xff;
    }
    send_msg(&mut stream, &AgentMsg::Challenge { nonce: nonce_agent, mac });
    if let Behavior::WrongProof = behavior {
        return Attempt::Ended { after_hello: drain(stream) };
    }
    let Some(TermMsg::Auth { mac, info }) = recv_msg(&mut stream) else {
        return Attempt::Ended { after_hello: drain(stream) };
    };
    assert!(auth::verify_term(&secret, &nonce_agent, &nonce_term, &mac), "bad terminal proof");
    match behavior {
        Behavior::RejectLimit | Behavior::RejectVersion => {
            let reason = if let Behavior::RejectLimit = behavior { RejectReason::Limit } else { RejectReason::Version };
            send_msg(&mut stream, &AgentMsg::Reject { reason });
            Attempt::Ended { after_hello: drain(stream) }
        }
        _ => {
            send_msg(&mut stream, &AgentMsg::Ready);
            stream.set_read_timeout(None).unwrap();
            Attempt::Session(AgentSession { stream, info, out: Vec::new() })
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
            assert!(!left.is_zero(), "no {needle:?} in out: {:?}", String::from_utf8_lossy(&self.out));
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
            self.stream.set_read_timeout(Some(Duration::from_millis(100))).unwrap();
            match read_frame(&mut self.stream) {
                Ok(frame) => {
                    if let Ok(Some(TermMsg::Out { data })) = TermMsg::decode(&frame) {
                        self.out.extend_from_slice(&data);
                    }
                }
                Err(e) if e.kind() == std::io::ErrorKind::UnexpectedEof => return true,
                Err(e) if matches!(e.kind(), std::io::ErrorKind::WouldBlock | std::io::ErrorKind::TimedOut) => {}
                Err(_) => return true,
            }
        }
        false
    }

    pub fn close(self) {
        let _ = self.stream.shutdown(std::net::Shutdown::Both);
    }
}
```

Add `pub mod fake_agent;` at the end of `term/tests/common/mod.rs`.

- [ ] **Step 4: Handshake — failing tests**

`term/tests/handshake.rs`:

```rust
mod common;

use common::fake_agent::{Attempt, Behavior, FakeAgent};
use shellx_term::proto::endpoint::{endpoint_path_in, read_endpoint};
use shellx_term::proto::handshake::{handshake, HandshakeError, HandshakeOutcome};
use shellx_term::proto::messages::{RejectReason, TermInfo};
use std::net::TcpStream;
use std::time::{Duration, Instant};

const T: Duration = Duration::from_secs(5);

fn info() -> TermInfo {
    TermInfo { term_id: [7; 16], app: "Terminal".into(), shell: "zsh".into(), pid: 1, cols: 80, rows: 24, started_at: 1 }
}

fn connect(home: &std::path::Path) -> (TcpStream, [u8; 32]) {
    let ep = read_endpoint(&endpoint_path_in(home)).expect("endpoint");
    (TcpStream::connect(("127.0.0.1", ep.port)).unwrap(), ep.secret)
}

#[test]
fn a_real_agent_accepts_the_terminal() {
    let home = common::temp_dir("hs-ok");
    let agent = FakeAgent::start(&home, Behavior::Normal);
    let (mut s, secret) = connect(&home);
    assert!(matches!(handshake(&mut s, &secret, &info(), T), Ok(HandshakeOutcome::Ready)));
    let session = agent.next_session(T);
    assert_eq!(session.info, info());
}

#[test]
fn an_impostor_without_the_secret_gets_nothing_after_hello() {
    let home = common::temp_dir("hs-impostor");
    let agent = FakeAgent::start(&home, Behavior::WrongProof);
    let (mut s, secret) = connect(&home);
    assert!(matches!(handshake(&mut s, &secret, &info(), T), Err(HandshakeError::BadAgentProof)));
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
    for (behavior, reason) in [(Behavior::RejectLimit, RejectReason::Limit), (Behavior::RejectVersion, RejectReason::Version)] {
        let home = common::temp_dir("hs-reject");
        let _agent = FakeAgent::start(&home, behavior);
        let (mut s, secret) = connect(&home);
        match handshake(&mut s, &secret, &info(), T) {
            Ok(HandshakeOutcome::Rejected(r)) => assert_eq!(r, reason),
            other => panic!("{other:?}"),
        }
    }
}
```

Run: `cargo test --features test-hooks --test handshake` → compile error (no `handshake` module).

- [ ] **Step 5: Handshake — implementation**

`term/src/proto/handshake.rs`:

```rust
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
    send(stream, &TermMsg::Hello { v: PROTOCOL_VERSION, nonce: nonce_term }, deadline)?;
    let (nonce_agent, proof) = match recv(stream, deadline)? {
        AgentMsg::Challenge { nonce, mac } => (nonce, mac),
        AgentMsg::Reject { reason } => return Ok(HandshakeOutcome::Rejected(reason)),
        other => return Err(HandshakeError::Protocol(format!("expected challenge, got {other:?}"))),
    };
    if !auth::verify_agent(secret, &nonce_term, &nonce_agent, &proof) {
        return Err(HandshakeError::BadAgentProof);
    }
    let mac = auth::term_proof(secret, &nonce_agent, &nonce_term);
    send(stream, &TermMsg::Auth { mac, info: info.clone() }, deadline)?;
    match recv(stream, deadline)? {
        AgentMsg::Ready => {
            stream.set_read_timeout(None).map_err(HandshakeError::Io)?;
            stream.set_write_timeout(None).map_err(HandshakeError::Io)?;
            Ok(HandshakeOutcome::Ready)
        }
        AgentMsg::Reject { reason } => Ok(HandshakeOutcome::Rejected(reason)),
        other => Err(HandshakeError::Protocol(format!("expected ready, got {other:?}"))),
    }
}

fn left(deadline: Instant) -> Result<Duration, HandshakeError> {
    let left = deadline.saturating_duration_since(Instant::now());
    if left.is_zero() { Err(HandshakeError::Timeout) } else { Ok(left) }
}

fn io_error(e: io::Error) -> HandshakeError {
    match e.kind() {
        io::ErrorKind::WouldBlock | io::ErrorKind::TimedOut => HandshakeError::Timeout,
        _ => HandshakeError::Io(e),
    }
}

fn send(stream: &mut TcpStream, msg: &TermMsg, deadline: Instant) -> Result<(), HandshakeError> {
    stream.set_write_timeout(Some(left(deadline)?)).map_err(HandshakeError::Io)?;
    write_frame(stream, &msg.encode()).map_err(io_error)
}

fn recv(stream: &mut TcpStream, deadline: Instant) -> Result<AgentMsg, HandshakeError> {
    stream.set_read_timeout(Some(left(deadline)?)).map_err(HandshakeError::Io)?;
    let frame = read_frame(stream).map_err(io_error)?;
    AgentMsg::decode(&frame)
        .map_err(|e| HandshakeError::Protocol(e.0))?
        .ok_or_else(|| HandshakeError::Protocol("unknown message during handshake".into()))
}
```

Run: `cargo test --features test-hooks --test handshake` → 4 passed.

- [ ] **Step 6: Gate and commit**

Gate + 3× suite.

```bash
git add term
git commit -m "feat(term): mutual HMAC handshake, endpoint file, fake agent for tests"
```

---

### Task 3: Output ring buffer and bounded outbox

**Files:**
- Create: `term/src/ring.rs`, `term/src/outbox.rs`
- Modify: `term/src/lib.rs` (`pub mod ring;`, `pub mod outbox;`)

**Interfaces:**
- Produces:
  - `ring::{CAPACITY = 262144, RingBuffer::{new(usize), push(&[u8]), snapshot() -> Vec<u8>, len() -> usize, is_empty() -> bool}}`
  - `outbox::{LIMIT = 1048576, Pop { Frame(Vec<u8>), Timeout, Overflowed, Closed }, Outbox::{new(usize), push(Vec<u8>) -> bool, pop(Duration) -> Pop, written(), reset(), close(), wait_drained(Duration) -> bool}}`

- [ ] **Step 1: Ring buffer — tests, then code**

`term/src/ring.rs`:

```rust
//! The last 256 KiB of the shell's output (spec §5.4 item 8): what a phone
//! sees first, including output from before the agent was reachable.

use std::collections::VecDeque;

pub const CAPACITY: usize = 256 * 1024;

pub struct RingBuffer {
    bytes: VecDeque<u8>,
    capacity: usize,
}

impl RingBuffer {
    pub fn new(capacity: usize) -> RingBuffer {
        RingBuffer { bytes: VecDeque::with_capacity(capacity), capacity }
    }

    /// Appends `data`, dropping the oldest bytes beyond the capacity.
    pub fn push(&mut self, data: &[u8]) {
        let data = &data[data.len().saturating_sub(self.capacity)..];
        let overflow = (self.bytes.len() + data.len()).saturating_sub(self.capacity);
        self.bytes.drain(..overflow);
        self.bytes.extend(data);
    }

    /// Oldest to newest.
    pub fn snapshot(&self) -> Vec<u8> {
        self.bytes.iter().copied().collect()
    }

    pub fn len(&self) -> usize {
        self.bytes.len()
    }

    pub fn is_empty(&self) -> bool {
        self.bytes.is_empty()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn keeps_everything_below_capacity() {
        let mut r = RingBuffer::new(8);
        r.push(b"abc");
        r.push(b"de");
        assert_eq!(r.snapshot(), b"abcde");
    }

    #[test]
    fn drops_the_oldest_bytes() {
        let mut r = RingBuffer::new(8);
        r.push(b"abcdef");
        r.push(b"ghij");
        assert_eq!(r.snapshot(), b"cdefghij");
        assert_eq!(r.len(), 8);
    }

    #[test]
    fn a_huge_push_keeps_its_tail() {
        let mut r = RingBuffer::new(4);
        r.push(b"x");
        r.push(b"0123456789");
        assert_eq!(r.snapshot(), b"6789");
    }

    #[test]
    fn default_capacity_is_256_kib() {
        let mut r = RingBuffer::new(CAPACITY);
        r.push(&vec![1u8; CAPACITY + 10]);
        assert_eq!(r.len(), 262_144);
    }
}
```

Run: `cargo test --features test-hooks ring::` → 4 passed (write the tests against an empty `push` first and see `drops_the_oldest_bytes` fail).

- [ ] **Step 2: Outbox — tests, then code**

`term/src/outbox.rs`:

```rust
//! Frames waiting for the agent (spec §5.4 item 1). Pushing never blocks:
//! past the limit the outbox drops everything and reports overflow, and the
//! link ends the session and resyncs later from the ring buffer.

use std::collections::VecDeque;
use std::sync::{Condvar, Mutex, MutexGuard};
use std::time::{Duration, Instant};

pub const LIMIT: usize = 1024 * 1024;

#[derive(Debug, PartialEq, Eq)]
pub enum Pop {
    Frame(Vec<u8>),
    Timeout,
    Overflowed,
    Closed,
}

#[derive(Default)]
struct State {
    frames: VecDeque<Vec<u8>>,
    bytes: usize,
    overflowed: bool,
    closed: bool,
    /// A popped frame is being written.
    in_flight: bool,
}

pub struct Outbox {
    state: Mutex<State>,
    changed: Condvar,
    limit: usize,
}

impl Outbox {
    pub fn new(limit: usize) -> Outbox {
        Outbox { state: Mutex::new(State::default()), changed: Condvar::new(), limit }
    }

    fn lock(&self) -> MutexGuard<'_, State> {
        self.state.lock().unwrap_or_else(|e| e.into_inner())
    }

    /// Queues a frame. False (and nothing queued) when closed, overflowed,
    /// or when this frame would pass the limit — which marks overflow.
    pub fn push(&self, frame: Vec<u8>) -> bool {
        let mut s = self.lock();
        if s.closed || s.overflowed {
            return false;
        }
        if s.bytes + frame.len() > self.limit {
            s.overflowed = true;
            s.frames.clear();
            s.bytes = 0;
            self.changed.notify_all();
            return false;
        }
        s.bytes += frame.len();
        s.frames.push_back(frame);
        self.changed.notify_all();
        true
    }

    /// Next frame, or why there is none. `Closed` only once drained.
    pub fn pop(&self, timeout: Duration) -> Pop {
        let until = Instant::now() + timeout;
        let mut s = self.lock();
        loop {
            if s.overflowed {
                return Pop::Overflowed;
            }
            if let Some(frame) = s.frames.pop_front() {
                s.bytes -= frame.len();
                s.in_flight = true;
                return Pop::Frame(frame);
            }
            if s.closed {
                return Pop::Closed;
            }
            let left = until.saturating_duration_since(Instant::now());
            if left.is_zero() {
                return Pop::Timeout;
            }
            s = self.changed.wait_timeout(s, left).unwrap_or_else(|e| e.into_inner()).0;
        }
    }

    /// The frame from the last `pop` has been written (or failed).
    pub fn written(&self) {
        self.lock().in_flight = false;
        self.changed.notify_all();
    }

    /// Empties the queue and clears overflow for a new session.
    pub fn reset(&self) {
        let mut s = self.lock();
        s.frames.clear();
        s.bytes = 0;
        s.overflowed = false;
        s.in_flight = false;
        self.changed.notify_all();
    }

    pub fn close(&self) {
        self.lock().closed = true;
        self.changed.notify_all();
    }

    /// Waits until every queued frame was written; false on timeout.
    pub fn wait_drained(&self, timeout: Duration) -> bool {
        let until = Instant::now() + timeout;
        let mut s = self.lock();
        loop {
            if (s.frames.is_empty() && !s.in_flight) || s.overflowed {
                return true;
            }
            let left = until.saturating_duration_since(Instant::now());
            if left.is_zero() {
                return false;
            }
            s = self.changed.wait_timeout(s, left).unwrap_or_else(|e| e.into_inner()).0;
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::Arc;

    const SHORT: Duration = Duration::from_millis(50);

    #[test]
    fn frames_come_out_in_order() {
        let o = Outbox::new(100);
        assert!(o.push(vec![1]));
        assert!(o.push(vec![2, 2]));
        assert_eq!(o.pop(SHORT), Pop::Frame(vec![1]));
        assert_eq!(o.pop(SHORT), Pop::Frame(vec![2, 2]));
        assert_eq!(o.pop(SHORT), Pop::Timeout);
    }

    #[test]
    fn passing_the_limit_drops_everything_and_reports_overflow() {
        let o = Outbox::new(10);
        assert!(o.push(vec![0; 6]));
        assert!(!o.push(vec![0; 6]));
        assert_eq!(o.pop(SHORT), Pop::Overflowed);
        assert!(!o.push(vec![1]), "stays overflowed until reset");
        o.reset();
        assert!(o.push(vec![1]));
        assert_eq!(o.pop(SHORT), Pop::Frame(vec![1]));
    }

    #[test]
    fn push_never_blocks_even_when_nobody_pops() {
        let o = Outbox::new(LIMIT);
        let start = Instant::now();
        for _ in 0..10_000 {
            o.push(vec![0; 1024]);
        }
        assert!(start.elapsed() < Duration::from_millis(500));
    }

    #[test]
    fn close_lets_queued_frames_out_first() {
        let o = Outbox::new(100);
        o.push(vec![9]);
        o.close();
        assert!(!o.push(vec![1]));
        assert_eq!(o.pop(SHORT), Pop::Frame(vec![9]));
        assert_eq!(o.pop(SHORT), Pop::Closed);
    }

    #[test]
    fn a_waiting_pop_wakes_on_push() {
        let o = Arc::new(Outbox::new(100));
        let o2 = o.clone();
        let t = std::thread::spawn(move || o2.pop(Duration::from_secs(5)));
        std::thread::sleep(Duration::from_millis(50));
        o.push(vec![5]);
        assert_eq!(t.join().unwrap(), Pop::Frame(vec![5]));
    }

    #[test]
    fn wait_drained_counts_the_frame_being_written() {
        let o = Outbox::new(100);
        o.push(vec![1]);
        assert!(!o.wait_drained(SHORT));
        assert_eq!(o.pop(SHORT), Pop::Frame(vec![1]));
        assert!(!o.wait_drained(SHORT), "still being written");
        o.written();
        assert!(o.wait_drained(SHORT));
    }
}
```

Run: `cargo test --features test-hooks outbox::` → 6 passed (tests first against `todo!()` bodies, then the code).

- [ ] **Step 3: Gate and commit**

```bash
git add term
git commit -m "feat(term): 256 KiB output ring and a never-blocking 1 MiB outbox"
```

---

### Task 4: Size control (who drives the PTY size)

**Files:**
- Create: `term/src/size.rs`
- Modify: `term/src/lib.rs` (`pub mod size;`)

**Interfaces:**
- Consumes: `proto::messages::TermMsg` (for `Notice::to_msg`).
- Produces: `size::{Resizer (trait: fn resize(&self, cols: u16, rows: u16)), Driver { Desktop, Phone }, Notice { Size { cols, rows }, Local } with to_msg(self) -> TermMsg, SizeControl<R: Resizer>::{new(R, (u16, u16)), window_resized((u16,u16)) -> Vec<Notice>, local_input() -> Vec<Notice>, phone_resize((u16,u16)), phone_left(), driver() -> Driver, applied() -> (u16,u16)}}`

- [ ] **Step 1: Tests**

`term/src/size.rs` (types + `todo!` bodies first, tests below):

```rust
//! Who decides the PTY's size when desktop and phone share it (spec §5.5):
//! the side that acted last. The desktop takes over without waiting for
//! the agent.

use crate::proto::messages::TermMsg;

pub trait Resizer {
    fn resize(&self, cols: u16, rows: u16);
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Driver {
    Desktop,
    Phone,
}

/// What to tell the agent after a desktop-side change.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Notice {
    Size { cols: u16, rows: u16 },
    Local,
}

impl Notice {
    pub fn to_msg(self) -> TermMsg {
        match self {
            Notice::Size { cols, rows } => TermMsg::Size { cols, rows },
            Notice::Local => TermMsg::Local,
        }
    }
}

pub struct SizeControl<R: Resizer> {
    resizer: R,
    driver: Driver,
    window: (u16, u16),
    applied: (u16, u16),
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::cell::RefCell;

    #[derive(Default)]
    struct Log(RefCell<Vec<(u16, u16)>>);
    impl Resizer for &Log {
        fn resize(&self, cols: u16, rows: u16) {
            self.0.borrow_mut().push((cols, rows));
        }
    }

    #[test]
    fn starts_with_the_desktop_at_window_size() {
        let log = Log::default();
        let s = SizeControl::new(&log, (80, 24));
        assert_eq!((s.driver(), s.applied()), (Driver::Desktop, (80, 24)));
        assert!(log.0.borrow().is_empty());
    }

    #[test]
    fn the_phone_takes_over_with_its_size() {
        let log = Log::default();
        let mut s = SizeControl::new(&log, (80, 24));
        s.phone_resize((50, 20));
        assert_eq!((s.driver(), s.applied()), (Driver::Phone, (50, 20)));
        assert_eq!(*log.0.borrow(), vec![(50, 20)]);
    }

    #[test]
    fn a_desktop_keystroke_takes_the_size_back_and_tells_the_agent() {
        let log = Log::default();
        let mut s = SizeControl::new(&log, (80, 24));
        s.phone_resize((50, 20));
        assert_eq!(s.local_input(), vec![Notice::Local]);
        assert_eq!((s.driver(), s.applied()), (Driver::Desktop, (80, 24)));
        assert_eq!(s.local_input(), vec![], "already the desktop's");
    }

    #[test]
    fn a_window_resize_while_the_phone_drives_restores_the_desktop() {
        let log = Log::default();
        let mut s = SizeControl::new(&log, (80, 24));
        s.phone_resize((50, 20));
        assert_eq!(s.window_resized((100, 30)), vec![Notice::Size { cols: 100, rows: 30 }, Notice::Local]);
        assert_eq!((s.driver(), s.applied()), (Driver::Desktop, (100, 30)));
        assert_eq!(s.window_resized((90, 30)), vec![Notice::Size { cols: 90, rows: 30 }]);
    }

    #[test]
    fn the_phone_leaving_restores_the_window_size() {
        let log = Log::default();
        let mut s = SizeControl::new(&log, (80, 24));
        s.phone_resize((50, 20));
        s.phone_left();
        assert_eq!((s.driver(), s.applied()), (Driver::Desktop, (80, 24)));
    }

    #[test]
    fn changing_driver_at_the_same_size_bounces_to_force_a_redraw() {
        let log = Log::default();
        let mut s = SizeControl::new(&log, (80, 24));
        s.phone_resize((80, 24));
        assert_eq!(*log.0.borrow(), vec![(80, 23), (80, 24)]);
        log.0.borrow_mut().clear();
        s.phone_resize((80, 24)); // same driver, same size: nothing
        assert!(log.0.borrow().is_empty());
        s.local_input();
        assert_eq!(*log.0.borrow(), vec![(80, 23), (80, 24)]);
    }

    #[test]
    fn a_one_row_terminal_bounces_upwards() {
        let log = Log::default();
        let mut s = SizeControl::new(&log, (80, 1));
        s.phone_resize((80, 1));
        assert_eq!(*log.0.borrow(), vec![(80, 2), (80, 1)]);
    }

    #[test]
    fn notices_become_link_messages() {
        assert_eq!(Notice::Size { cols: 3, rows: 4 }.to_msg(), TermMsg::Size { cols: 3, rows: 4 });
        assert_eq!(Notice::Local.to_msg(), TermMsg::Local);
    }
}
```

Run: `cargo test --features test-hooks size::` → compile error (`new`, `driver`, … missing).

- [ ] **Step 2: Implementation**

Add to `size.rs` above the tests:

```rust
impl<R: Resizer> SizeControl<R> {
    /// The PTY starts at the window's size, driven by the desktop.
    pub fn new(resizer: R, window: (u16, u16)) -> SizeControl<R> {
        SizeControl { resizer, driver: Driver::Desktop, window, applied: window }
    }

    pub fn driver(&self) -> Driver {
        self.driver
    }

    pub fn applied(&self) -> (u16, u16) {
        self.applied
    }

    /// The window was resized (SIGWINCH): the desktop drives.
    pub fn window_resized(&mut self, size: (u16, u16)) -> Vec<Notice> {
        self.window = size;
        let was_phone = self.driver == Driver::Phone;
        self.driver = Driver::Desktop;
        self.apply(size, was_phone);
        let mut notices = vec![Notice::Size { cols: size.0, rows: size.1 }];
        if was_phone {
            notices.push(Notice::Local);
        }
        notices
    }

    /// The user typed in the window. Cheap when the desktop already drives.
    pub fn local_input(&mut self) -> Vec<Notice> {
        if self.driver == Driver::Desktop {
            return vec![];
        }
        self.driver = Driver::Desktop;
        self.apply(self.window, true);
        vec![Notice::Local]
    }

    /// The phone attached, typed or resized (agent `resize`).
    pub fn phone_resize(&mut self, size: (u16, u16)) {
        let was_desktop = self.driver == Driver::Desktop;
        self.driver = Driver::Phone;
        self.apply(size, was_desktop);
    }

    /// The phone left (agent `local_size`, or the link dropped).
    pub fn phone_left(&mut self) {
        if self.driver == Driver::Phone {
            self.driver = Driver::Desktop;
            self.apply(self.window, true);
        }
    }

    /// Resizes to `size`. When the size does not change but the driver did,
    /// shrink by one row and back so full-screen programs redraw.
    fn apply(&mut self, size: (u16, u16), driver_changed: bool) {
        let (cols, rows) = size;
        if size != self.applied {
            self.resizer.resize(cols, rows);
            self.applied = size;
        } else if driver_changed {
            let bounce = if rows > 1 { rows - 1 } else { rows + 1 };
            self.resizer.resize(cols, bounce);
            self.resizer.resize(cols, rows);
        }
    }
}
```

Run: `cargo test --features test-hooks size::` → 8 passed.

- [ ] **Step 3: Gate and commit**

```bash
git add term
git commit -m "feat(term): size control — last side to act drives the PTY size"
```

---

### Task 5: The link — connect, authenticate, stream, reconnect

**Files:**
- Create: `term/src/link.rs`
- Modify: `term/src/lib.rs` (`pub mod link;`), `term/src/faults.rs` (add `fast_timing()`)
- Test: `term/tests/link.rs` (feature `test-hooks`)

**Interfaces:**
- Consumes: Task 1–3 (`messages`, `frame`, `endpoint::read_endpoint`, `handshake::{handshake, HandshakeOutcome}`, `RingBuffer`, `Outbox`, `Pop`).
- Produces:
  - `link::Timing { handshake, backoff: Vec<Duration>, limit_retry, version_poll, exit_flush, write_timeout }` with `Timing::standard()`, `Timing::fast()`, `Timing::from_env()`
  - `link::LinkEvents` (trait, `Send + Sync + 'static`): `fn info(&self) -> TermInfo; fn input(&self, data: &[u8]); fn phone_resize(&self, cols: u16, rows: u16); fn phone_left(&self);`
  - `link::Link::{start(Option<PathBuf>, Timing, Arc<dyn LinkEvents>) -> Link, output(&self, &[u8]), send(&self, TermMsg), finish(&self, code: u32)}`
  - `link::SNAPSHOT_PIECE = 61440`
  - `faults::fast_timing() -> bool` (true only with feature `test-hooks` and `SHELLX_TERM_TIMING=fast`)

- [ ] **Step 1: Timing switch in faults.rs**

Append to `term/src/faults.rs`:

```rust
/// Short link timers for integration tests (`SHELLX_TERM_TIMING=fast`).
#[cfg(feature = "test-hooks")]
pub fn fast_timing() -> bool {
    std::env::var("SHELLX_TERM_TIMING").is_ok_and(|v| v == "fast")
}

#[cfg(not(feature = "test-hooks"))]
#[inline(always)]
pub fn fast_timing() -> bool {
    false
}
```

`faults` is `#[cfg(unix)]` in `lib.rs`; `link` is also Unix-only for now (`#[cfg(unix)] pub mod link;`).

- [ ] **Step 2: Failing tests**

`term/tests/link.rs`:

```rust
#![cfg(feature = "test-hooks")]

mod common;

use common::fake_agent::{Attempt, Behavior, FakeAgent};
use shellx_term::link::{Link, LinkEvents, Timing};
use shellx_term::proto::endpoint::endpoint_path_in;
use shellx_term::proto::messages::{AgentMsg, TermInfo, TermMsg};
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

const T: Duration = Duration::from_secs(5);

#[derive(Default)]
struct Events {
    input: Mutex<Vec<u8>>,
    log: Mutex<Vec<String>>,
}

impl LinkEvents for Events {
    fn info(&self) -> TermInfo {
        TermInfo { term_id: [9; 16], app: "Terminal".into(), shell: "zsh".into(), pid: 77, cols: 80, rows: 24, started_at: 5 }
    }
    fn input(&self, data: &[u8]) {
        self.input.lock().unwrap().extend_from_slice(data);
    }
    fn phone_resize(&self, cols: u16, rows: u16) {
        self.log.lock().unwrap().push(format!("resize {cols}x{rows}"));
    }
    fn phone_left(&self) {
        self.log.lock().unwrap().push("left".into());
    }
}

fn start(home: &std::path::Path) -> (Link, Arc<Events>) {
    let events = Arc::new(Events::default());
    let link = Link::start(Some(endpoint_path_in(home)), Timing::fast(), events.clone());
    (link, events)
}

fn wait_for(cond: impl Fn() -> bool, what: &str) {
    let until = Instant::now() + T;
    while !cond() {
        assert!(Instant::now() < until, "timed out waiting for {what}");
        std::thread::sleep(Duration::from_millis(20));
    }
}

#[test]
fn output_from_before_the_agent_arrives_in_the_snapshot_then_live() {
    let home = common::temp_dir("link-snapshot");
    let (link, _events) = start(&home);
    link.output(b"before\r\n");
    let agent = FakeAgent::start(&home, Behavior::Normal);
    let mut s = agent.next_session(T);
    assert_eq!(s.info.term_id, [9; 16]);
    assert_eq!(s.snapshot(T), b"before\r\n");
    link.output(b"after\r\n");
    s.expect_out("after", T);
}

#[test]
fn a_large_snapshot_comes_in_pieces_under_the_frame_limit() {
    let home = common::temp_dir("link-pieces");
    let (link, _events) = start(&home);
    let big: Vec<u8> = (0..300_000u32).map(|i| b'a' + (i % 26) as u8).collect();
    link.output(&big);
    let agent = FakeAgent::start(&home, Behavior::Normal);
    let mut s = agent.next_session(T);
    let snap = s.snapshot(T);
    assert_eq!(snap.len(), 262_144);
    assert_eq!(snap, big[big.len() - 262_144..]);
}

#[test]
fn the_agent_restarting_gets_the_same_terminal_and_a_fresh_snapshot() {
    let home = common::temp_dir("link-restart");
    let (link, _events) = start(&home);
    let first = FakeAgent::start(&home, Behavior::Normal);
    let mut s1 = first.next_session(T);
    s1.snapshot(T);
    link.output(b"one\r\n");
    s1.expect_out("one", T);
    s1.close();
    let second = FakeAgent::start(&home, Behavior::Normal); // new port + secret
    let mut s2 = second.next_session(T);
    assert_eq!(s2.info.term_id, [9; 16]);
    assert!(String::from_utf8_lossy(&s2.snapshot(T)).contains("one"));
}

#[test]
fn an_impostor_never_receives_terminal_bytes() {
    let home = common::temp_dir("link-impostor");
    let (link, _events) = start(&home);
    link.output(b"secret stuff\r\n");
    let agent = FakeAgent::start(&home, Behavior::WrongProof);
    for _ in 0..2 {
        match agent.next_attempt(T) {
            Attempt::Ended { after_hello } => assert!(after_hello.is_empty(), "{after_hello:?}"),
            Attempt::Session(_) => panic!("impostor got a session"),
        }
    }
}

#[test]
fn a_hung_agent_never_slows_output_and_the_link_resyncs_later() {
    let home = common::temp_dir("link-hung");
    let (link, _events) = start(&home);
    let agent = FakeAgent::start(&home, Behavior::Normal);
    let mut hung = agent.next_session(T);
    hung.snapshot(T);
    // The agent never reads again. 8 MiB of output must still be instant.
    let chunk = vec![b'x'; 16 * 1024];
    let start = Instant::now();
    for _ in 0..512 {
        link.output(&chunk);
    }
    link.output(b"TAIL-MARKER");
    assert!(start.elapsed() < Duration::from_secs(1), "output blocked: {:?}", start.elapsed());
    // The link gives up on the hung session and reconnects with a snapshot.
    let mut fresh = agent.next_session(Duration::from_secs(10));
    let snap = fresh.snapshot(T);
    assert!(snap.ends_with(b"TAIL-MARKER"));
    drop(hung);
}

#[test]
fn phone_messages_reach_the_terminal_and_a_drop_counts_as_leaving() {
    let home = common::temp_dir("link-phone");
    let (_link, events) = start(&home);
    let agent = FakeAgent::start(&home, Behavior::Normal);
    let mut s = agent.next_session(T);
    s.snapshot(T);
    s.send(&AgentMsg::In { data: b"ls\r".to_vec() });
    s.send(&AgentMsg::Resize { cols: 50, rows: 20 });
    s.send(&AgentMsg::LocalSize);
    wait_for(|| events.input.lock().unwrap().as_slice() == b"ls\r", "input");
    wait_for(|| events.log.lock().unwrap().len() >= 2, "resize + left");
    s.close();
    wait_for(|| events.log.lock().unwrap().len() >= 3, "left after drop");
    assert_eq!(*events.log.lock().unwrap(), vec!["resize 50x20", "left", "left"]);
}

#[test]
fn desktop_notices_are_sent_while_a_session_is_live() {
    let home = common::temp_dir("link-notices");
    let (link, _events) = start(&home);
    link.send(TermMsg::Local); // no session yet: dropped, not queued
    let agent = FakeAgent::start(&home, Behavior::Normal);
    let mut s = agent.next_session(T);
    s.snapshot(T);
    link.send(TermMsg::Size { cols: 100, rows: 30 });
    link.send(TermMsg::Local);
    assert_eq!(s.recv(T), Some(TermMsg::Size { cols: 100, rows: 30 }));
    assert_eq!(s.recv(T), Some(TermMsg::Local));
}

#[test]
fn reject_limit_retries_later_and_reject_version_waits_for_a_new_endpoint() {
    let home = common::temp_dir("link-reject");
    let (_link, _events) = start(&home);
    let limit = FakeAgent::start(&home, Behavior::RejectLimit);
    assert!(matches!(limit.next_attempt(T), Attempt::Ended { .. }));
    assert!(matches!(limit.next_attempt(T), Attempt::Ended { .. }), "retried after a limit");
    let version = FakeAgent::start(&home, Behavior::RejectVersion);
    assert!(matches!(version.next_attempt(T), Attempt::Ended { .. }));
    assert!(version.quiet_for(Duration::from_millis(800)), "must not retry the same endpoint");
    let normal = FakeAgent::start(&home, Behavior::Normal); // endpoint changed
    normal.next_session(T);
}

#[test]
fn finish_sends_exit_and_returns_quickly_even_if_the_agent_is_hung() {
    let home = common::temp_dir("link-exit");
    let (link, _events) = start(&home);
    let agent = FakeAgent::start(&home, Behavior::Normal);
    let mut s = agent.next_session(T);
    s.snapshot(T);
    let start = Instant::now();
    link.finish(3);
    assert!(start.elapsed() < Duration::from_millis(600));
    assert_eq!(s.expect_msg(|m| matches!(m, TermMsg::Exit { .. }), T), TermMsg::Exit { code: 3 });
    assert!(s.closed_within(T));

    let home = common::temp_dir("link-exit-hung");
    let (link, _events) = start(&home);
    let agent = FakeAgent::start(&home, Behavior::Normal);
    let mut hung = agent.next_session(T);
    hung.snapshot(T);
    for _ in 0..200 {
        link.output(&vec![b'y'; 16 * 1024]);
    }
    let start = Instant::now();
    link.finish(0);
    assert!(start.elapsed() < Duration::from_millis(600), "{:?}", start.elapsed());
}

#[test]
fn no_endpoint_means_idle_until_one_appears() {
    let home = common::temp_dir("link-idle");
    let (link, _events) = start(&home);
    link.output(b"early\r\n");
    std::thread::sleep(Duration::from_millis(300));
    let agent = FakeAgent::start(&home, Behavior::Normal);
    let mut s = agent.next_session(T);
    assert_eq!(s.snapshot(T), b"early\r\n");
}
```

Run: `cargo test --features test-hooks --test link` → compile error (`link` missing).

- [ ] **Step 3: Implementation**

`term/src/link.rs`:

```rust
//! The local link to the ShellX agent (spec §6): one background thread that
//! finds the agent, proves the secret, sends a snapshot then live output,
//! and applies the phone's input and size. Nothing here may block or slow
//! the terminal itself (spec §5.4): output only touches the ring and the
//! never-blocking outbox.

use crate::faults;
use crate::outbox::{Outbox, Pop, LIMIT};
use crate::proto::endpoint::read_endpoint;
use crate::proto::frame::{read_frame, write_frame};
use crate::proto::handshake::{handshake, HandshakeOutcome};
use crate::proto::messages::{AgentMsg, RejectReason, TermInfo, TermMsg};
use crate::ring::{RingBuffer, CAPACITY};
use std::net::{Ipv4Addr, Shutdown, SocketAddr, TcpStream};
use std::path::PathBuf;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Condvar, Mutex, MutexGuard};
use std::time::Duration;

/// Largest `snapshot`/`out` data piece: a frame stays under 64 KiB.
pub const SNAPSHOT_PIECE: usize = 60 * 1024;

#[derive(Clone, Debug)]
pub struct Timing {
    pub handshake: Duration,
    /// Waits between failed attempts; the last one repeats.
    pub backoff: Vec<Duration>,
    pub limit_retry: Duration,
    pub version_poll: Duration,
    pub exit_flush: Duration,
    pub write_timeout: Duration,
}

impl Timing {
    pub fn standard() -> Timing {
        Timing {
            handshake: Duration::from_secs(5),
            backoff: [1, 2, 4, 8, 10].map(Duration::from_secs).to_vec(),
            limit_retry: Duration::from_secs(30),
            version_poll: Duration::from_secs(10),
            exit_flush: Duration::from_millis(200),
            write_timeout: Duration::from_secs(1),
        }
    }

    /// For tests: everything short so suites stay fast.
    pub fn fast() -> Timing {
        Timing {
            handshake: Duration::from_millis(500),
            backoff: vec![Duration::from_millis(50)],
            limit_retry: Duration::from_millis(200),
            version_poll: Duration::from_millis(100),
            exit_flush: Duration::from_millis(200),
            write_timeout: Duration::from_millis(300),
        }
    }

    /// `fast()` only for test builds that ask for it.
    pub fn from_env() -> Timing {
        if faults::fast_timing() { Timing::fast() } else { Timing::standard() }
    }

    fn backoff(&self, attempt: usize) -> Duration {
        self.backoff[attempt.min(self.backoff.len() - 1)]
    }
}

/// What the link needs from the wrapper.
pub trait LinkEvents: Send + Sync + 'static {
    /// Sent with `auth` at every (re)connect.
    fn info(&self) -> TermInfo;
    /// Phone keystrokes (agent `in`).
    fn input(&self, data: &[u8]);
    /// Agent `resize`.
    fn phone_resize(&self, cols: u16, rows: u16);
    /// Agent `local_size`, or the session ended.
    fn phone_left(&self);
}

struct OutputState {
    ring: RingBuffer,
    /// A session is live: output also goes to the outbox.
    live: bool,
}

struct Shared {
    /// Ring and `live` under one lock: a snapshot and the live stream never
    /// overlap or miss bytes.
    output: Mutex<OutputState>,
    outbox: Outbox,
    finishing: AtomicBool,
    wake: (Mutex<()>, Condvar),
}

fn lock<T>(m: &Mutex<T>) -> MutexGuard<'_, T> {
    m.lock().unwrap_or_else(|e| e.into_inner())
}

pub struct Link {
    shared: Arc<Shared>,
    timing: Timing,
}

impl Link {
    /// Starts the background thread unless `endpoint` is None (no HOME):
    /// then the link only keeps the ring buffer.
    pub fn start(endpoint: Option<PathBuf>, timing: Timing, events: Arc<dyn LinkEvents>) -> Link {
        let shared = Arc::new(Shared {
            output: Mutex::new(OutputState { ring: RingBuffer::new(CAPACITY), live: false }),
            outbox: Outbox::new(LIMIT),
            finishing: AtomicBool::new(false),
            wake: (Mutex::new(()), Condvar::new()),
        });
        if let Some(path) = endpoint {
            let shared = shared.clone();
            let timing = timing.clone();
            std::thread::spawn(move || connection_loop(path, timing, shared, events));
        }
        Link { shared, timing }
    }

    /// The shell printed `bytes`. Never blocks on the agent.
    pub fn output(&self, bytes: &[u8]) {
        let mut state = lock(&self.shared.output);
        state.ring.push(bytes);
        if state.live {
            for piece in bytes.chunks(SNAPSHOT_PIECE) {
                self.shared.outbox.push(TermMsg::Out { data: piece.to_vec() }.encode());
            }
        }
    }

    /// A desktop notice for a live session; dropped otherwise (the next
    /// session starts from `auth` and a snapshot).
    pub fn send(&self, msg: TermMsg) {
        let state = lock(&self.shared.output);
        if state.live {
            self.shared.outbox.push(msg.encode());
        }
    }

    /// The shell exited: send `exit`, wait at most `exit_flush`, stop.
    pub fn finish(&self, code: u32) {
        self.shared.finishing.store(true, Ordering::SeqCst);
        {
            let state = lock(&self.shared.output);
            if state.live {
                self.shared.outbox.push(TermMsg::Exit { code }.encode());
            }
        }
        self.shared.outbox.wait_drained(self.timing.exit_flush);
        self.shared.outbox.close();
        self.shared.wake.1.notify_all();
    }
}

/// Sleeps `d` unless the link is finishing.
fn nap(shared: &Shared, d: Duration) {
    let guard = lock(&shared.wake.0);
    if !shared.finishing.load(Ordering::SeqCst) {
        let _ = shared.wake.1.wait_timeout(guard, d);
    }
}

fn connection_loop(path: PathBuf, timing: Timing, shared: Arc<Shared>, events: Arc<dyn LinkEvents>) {
    let mut attempt = 0usize;
    // Endpoint contents that rejected our protocol version.
    let mut blocked: Option<Vec<u8>> = None;
    while !shared.finishing.load(Ordering::SeqCst) {
        let endpoint = match read_endpoint(&path) {
            Ok(e) => e,
            Err(_) => {
                nap(&shared, timing.backoff(attempt));
                attempt += 1;
                continue;
            }
        };
        if blocked.as_deref() == Some(endpoint.raw.as_slice()) {
            nap(&shared, timing.version_poll);
            continue;
        }
        blocked = None;
        let addr = SocketAddr::from((Ipv4Addr::LOCALHOST, endpoint.port));
        let mut stream = match TcpStream::connect_timeout(&addr, timing.handshake) {
            Ok(s) => s,
            Err(_) => {
                nap(&shared, timing.backoff(attempt));
                attempt += 1;
                continue;
            }
        };
        let _ = stream.set_nodelay(true);
        match handshake(&mut stream, &endpoint.secret, &events.info(), timing.handshake) {
            Ok(HandshakeOutcome::Ready) => {
                attempt = 0;
                run_session(stream, &shared, &events, &timing);
                nap(&shared, timing.backoff(0));
            }
            Ok(HandshakeOutcome::Rejected(RejectReason::Limit)) => nap(&shared, timing.limit_retry),
            Ok(HandshakeOutcome::Rejected(RejectReason::Version)) => blocked = Some(endpoint.raw),
            Ok(HandshakeOutcome::Rejected(RejectReason::Other(_))) | Err(_) => {
                nap(&shared, timing.backoff(attempt));
                attempt += 1;
            }
        }
    }
}

fn run_session(stream: TcpStream, shared: &Shared, events: &Arc<dyn LinkEvents>, timing: &Timing) {
    let mut writer = stream;
    let snapshot = {
        let mut state = lock(&shared.output);
        shared.outbox.reset();
        state.live = true;
        state.ring.snapshot()
    };
    let _ = writer.set_write_timeout(Some(timing.write_timeout));
    let reader = match writer.try_clone() {
        Ok(r) if send_snapshot(&mut writer, &snapshot) => {
            let events = events.clone();
            Some(std::thread::spawn(move || read_agent(r, events)))
        }
        _ => None,
    };
    if let Some(reader) = reader {
        loop {
            match shared.outbox.pop(Duration::from_millis(250)) {
                Pop::Frame(frame) => {
                    let ok = write_frame(&mut writer, &frame).is_ok();
                    shared.outbox.written();
                    if !ok {
                        break;
                    }
                }
                Pop::Timeout => {
                    if reader.is_finished() {
                        break;
                    }
                }
                Pop::Overflowed | Pop::Closed => break,
            }
        }
        let _ = writer.shutdown(Shutdown::Both);
        let _ = reader.join();
    }
    {
        let mut state = lock(&shared.output);
        state.live = false;
        shared.outbox.reset();
    }
    events.phone_left();
}

fn send_snapshot(writer: &mut TcpStream, snapshot: &[u8]) -> bool {
    let mut pieces = snapshot.chunks(SNAPSHOT_PIECE).peekable();
    if pieces.peek().is_none() {
        return write_frame(writer, &TermMsg::Snapshot { data: vec![], last: true }.encode()).is_ok();
    }
    while let Some(piece) = pieces.next() {
        let last = pieces.peek().is_none();
        if write_frame(writer, &TermMsg::Snapshot { data: piece.to_vec(), last }.encode()).is_err() {
            return false;
        }
    }
    true
}

fn read_agent(mut stream: TcpStream, events: Arc<dyn LinkEvents>) {
    while let Ok(frame) = read_frame(&mut stream) {
        match AgentMsg::decode(&frame) {
            Ok(Some(AgentMsg::In { data })) => events.input(&data),
            Ok(Some(AgentMsg::Resize { cols, rows })) => events.phone_resize(cols, rows),
            Ok(Some(AgentMsg::LocalSize)) => events.phone_left(),
            // Handshake-only or unknown messages are ignored.
            Ok(_) => {}
            Err(_) => return,
        }
    }
}
```

Note for the implementer: `finish` closes the outbox after the flush wait. A session whose writer is blocked in `write_frame` ends within `write_timeout`; `finish` itself returns after at most `exit_flush`.

Run: `cargo test --features test-hooks --test link` → 10 passed. Run it 5× (`for i in 1 2 3 4 5; do cargo test -q --features test-hooks --test link || break; done`); any intermittent failure is a bug to fix.

- [ ] **Step 4: Gate and commit**

```bash
git add term
git commit -m "feat(term): agent link — snapshot then live output, phone input/size, reconnect, never blocks"
```

---

### Task 6: Wire the link into `wrap`; terminal app name; per-tty marker; SIGTERM inheritance

**Files:**
- Create: `term/src/appname.rs`
- Modify: `term/src/lib.rs` (`pub mod appname;` under `#[cfg(unix)]`), `term/src/wrap.rs`
- Modify: `term/tests/wrap.rs` (`the_wrapped_shell_is_marked` now expects a tty path)
- Create: `term/tests/agent_link.rs` (feature `test-hooks`)

**Interfaces:**
- Consumes: `link::{Link, LinkEvents, Timing}`, `size::{SizeControl, Resizer, Notice, Driver}`, `proto::endpoint::default_endpoint_path`, `proto::messages::TermInfo`.
- Produces:
  - `appname::terminal_app(get: impl Fn(&str) -> Option<String>) -> String`
  - Behaviour:
    - The inner shell gets `SHELLX_TERM=<inner tty path>`; `SHELLX_TERM_WRAP` and `SHELLX_TERM_WRAP_LOGIN` are removed from its environment.
    - Output is teed to the link; phone input goes to the PTY; size follows `SizeControl`.
    - On exit the link gets `finish(code)`.
    - SIGTERM stays ignored if it was ignored at start.

- [ ] **Step 1: Terminal app name — tests then code**

`term/src/appname.rs`:

```rust
//! Which terminal app hosts this window, for the phone's session list
//! (spec §6.3 `app`). macOS hands every app's processes its bundle id in
//! `__CFBundleIdentifier`; `TERM_PROGRAM` and JetBrains' variable are
//! fallbacks.

const BY_BUNDLE: &[(&str, &str)] = &[
    ("com.apple.Terminal", "Terminal"),
    ("com.googlecode.iterm2", "iTerm2"),
    ("com.microsoft.VSCode", "VS Code"),
    ("com.microsoft.VSCodeInsiders", "VS Code Insiders"),
    ("com.todesktop.230313mzl4w4u92", "Cursor"),
    ("com.google.android.studio", "Android Studio"),
    ("com.jetbrains.intellij", "IntelliJ IDEA"),
    ("com.jetbrains.intellij.ce", "IntelliJ IDEA CE"),
    ("dev.warp.Warp-Stable", "Warp"),
    ("com.mitchellh.ghostty", "Ghostty"),
    ("net.kovidgoyal.kitty", "kitty"),
    ("org.alacritty", "Alacritty"),
    ("com.github.wez.wezterm", "WezTerm"),
];

const BY_TERM_PROGRAM: &[(&str, &str)] = &[
    ("Apple_Terminal", "Terminal"),
    ("iTerm.app", "iTerm2"),
    ("vscode", "VS Code"),
    ("WarpTerminal", "Warp"),
    ("ghostty", "Ghostty"),
    ("WezTerm", "WezTerm"),
];

/// A display name, or "" when unknown. `get` reads an environment variable.
pub fn terminal_app(get: impl Fn(&str) -> Option<String>) -> String {
    if let Some(id) = get("__CFBundleIdentifier") {
        if let Some((_, name)) = BY_BUNDLE.iter().find(|(bundle, _)| *bundle == id) {
            return name.to_string();
        }
    }
    if let Some(program) = get("TERM_PROGRAM").filter(|p| !p.is_empty()) {
        return BY_TERM_PROGRAM
            .iter()
            .find(|(raw, _)| *raw == program)
            .map(|(_, name)| name.to_string())
            .unwrap_or(program);
    }
    if get("TERMINAL_EMULATOR").as_deref() == Some("JetBrains-JediTerm") {
        return "JetBrains".to_string();
    }
    String::new()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn app(vars: &[(&str, &str)]) -> String {
        terminal_app(|k| vars.iter().find(|(name, _)| *name == k).map(|(_, v)| v.to_string()))
    }

    #[test]
    fn the_bundle_id_wins() {
        assert_eq!(app(&[("__CFBundleIdentifier", "com.todesktop.230313mzl4w4u92"), ("TERM_PROGRAM", "vscode")]), "Cursor");
        assert_eq!(app(&[("__CFBundleIdentifier", "com.apple.Terminal")]), "Terminal");
    }

    #[test]
    fn falls_back_to_term_program_then_jetbrains() {
        assert_eq!(app(&[("__CFBundleIdentifier", "com.unknown"), ("TERM_PROGRAM", "iTerm.app")]), "iTerm2");
        assert_eq!(app(&[("TERM_PROGRAM", "Hyper")]), "Hyper");
        assert_eq!(app(&[("TERMINAL_EMULATOR", "JetBrains-JediTerm")]), "JetBrains");
        assert_eq!(app(&[]), "");
    }
}
```

Run: `cargo test --features test-hooks appname::` → 2 passed.

- [ ] **Step 2: End-to-end tests (failing)**

`term/tests/agent_link.rs`:

```rust
#![cfg(feature = "test-hooks")]

mod common;

use common::fake_agent::{Behavior, FakeAgent};
use common::{Harness, BIN};
use shellx_term::proto::messages::{AgentMsg, TermMsg};
use std::path::Path;
use std::time::{Duration, Instant};

const T: Duration = Duration::from_secs(5);

fn wrapped_sh(home: &Path) -> Harness {
    let home = home.to_str().unwrap();
    Harness::spawn(
        BIN,
        &["wrap", "--", "/bin/sh"],
        &[("HOME", home), ("SHELLX_TERM_TIMING", "fast"), ("__CFBundleIdentifier", "com.apple.Terminal")],
        80,
        24,
    )
}

#[test]
fn the_phone_sees_earlier_output_then_live_output_and_the_terminal_facts() {
    let home = common::temp_dir("e2e-snapshot");
    let mut h = wrapped_sh(&home);
    h.send("echo be''fore\r");
    h.expect("before", T);
    let agent = FakeAgent::start(&home, Behavior::Normal);
    let mut s = agent.next_session(T);
    assert!(String::from_utf8_lossy(&s.snapshot(T)).contains("before"));
    assert_eq!((s.info.app.as_str(), s.info.shell.as_str(), s.info.cols, s.info.rows), ("Terminal", "sh", 80, 24));
    h.send("echo af''ter\r");
    s.expect_out("after", T);
    h.send("exit\r");
    h.wait_exit(T);
}

#[test]
fn phone_input_runs_in_the_shell() {
    let home = common::temp_dir("e2e-input");
    let mut h = wrapped_sh(&home);
    let agent = FakeAgent::start(&home, Behavior::Normal);
    let mut s = agent.next_session(T);
    s.snapshot(T);
    s.send(&AgentMsg::In { data: b"echo from''phone\r".to_vec() });
    h.expect("fromphone", T);
    s.expect_out("fromphone", T);
    h.send("exit\r");
    h.wait_exit(T);
}

#[test]
fn both_sides_typing_at_once_keep_their_commands_intact() {
    let home = common::temp_dir("e2e-both");
    let mut h = wrapped_sh(&home);
    let agent = FakeAgent::start(&home, Behavior::Normal);
    let mut s = agent.next_session(T);
    s.snapshot(T);
    s.send(&AgentMsg::In { data: b"echo pho''ne-side\r".to_vec() });
    h.send("echo desk''top-side\r");
    h.expect("phone-side", T);
    h.expect("desktop-side", T);
    h.send("exit\r");
    h.wait_exit(T);
}

#[test]
fn the_phone_drives_the_size_until_the_desktop_types_or_resizes() {
    let home = common::temp_dir("e2e-size");
    let mut h = wrapped_sh(&home);
    let agent = FakeAgent::start(&home, Behavior::Normal);
    let mut s = agent.next_session(T);
    s.snapshot(T);
    s.send(&AgentMsg::Resize { cols: 50, rows: 20 });
    s.send(&AgentMsg::In { data: b"stty size\r".to_vec() });
    s.expect_out("20 50", T);
    h.send("stty size\r"); // a desktop keystroke takes the size back
    assert_eq!(s.expect_msg(|m| matches!(m, TermMsg::Local), T), TermMsg::Local);
    h.expect("24 80", T);
    s.send(&AgentMsg::Resize { cols: 60, rows: 22 });
    std::thread::sleep(Duration::from_millis(200));
    h.resize(100, 30); // window resize while the phone drives
    assert_eq!(s.expect_msg(|m| matches!(m, TermMsg::Size { .. }), T), TermMsg::Size { cols: 100, rows: 30 });
    s.expect_msg(|m| matches!(m, TermMsg::Local), T);
    h.send("stty size\r");
    h.expect("30 100", T);
    h.send("exit\r");
    h.wait_exit(T);
}

#[test]
fn a_hung_agent_never_slows_the_terminal() {
    let home = common::temp_dir("e2e-hung");
    let mut h = wrapped_sh(&home);
    let agent = FakeAgent::start(&home, Behavior::Normal);
    let mut hung = agent.next_session(T);
    hung.snapshot(T); // then never reads again
    let start = Instant::now();
    h.send("head -c 5000000 /dev/zero | tr '\\0' a; echo; echo do''ne\r");
    h.expect("done", Duration::from_secs(30));
    assert!(start.elapsed() < Duration::from_secs(15), "{:?}", start.elapsed());
    h.send("exit\r");
    h.wait_exit(T);
    drop(hung);
}

#[test]
fn exit_reaches_the_agent_and_a_hung_agent_does_not_hold_the_window() {
    let home = common::temp_dir("e2e-exit");
    let mut h = wrapped_sh(&home);
    let agent = FakeAgent::start(&home, Behavior::Normal);
    let mut s = agent.next_session(T);
    s.snapshot(T);
    h.send("exit 3\r");
    assert_eq!(h.wait_exit(T), 3);
    assert_eq!(s.expect_msg(|m| matches!(m, TermMsg::Exit { .. }), T), TermMsg::Exit { code: 3 });

    let home = common::temp_dir("e2e-exit-hung");
    let mut h = wrapped_sh(&home);
    let agent = FakeAgent::start(&home, Behavior::Normal);
    let mut hung = agent.next_session(T);
    hung.snapshot(T);
    h.send("head -c 3000000 /dev/zero | tr '\\0' b; exit 4\r");
    let start = Instant::now();
    assert_eq!(h.wait_exit(Duration::from_secs(30)), 4);
    let after_output = start.elapsed();
    assert!(after_output < Duration::from_secs(20), "{after_output:?}");
    drop(hung);
}

#[test]
fn the_inner_shell_is_marked_with_its_own_tty() {
    let home = common::temp_dir("e2e-marker");
    let mut h = wrapped_sh(&home);
    h.send("[ \"$SHELLX_TERM\" = \"$(tty)\" ] && echo same''-tty\r");
    h.expect("same-tty", T);
    h.send("echo wrap=[${SHELLX_TERM_WRAP-}]\r");
    h.expect("wrap=[]", T);
    h.send("exit\r");
    h.wait_exit(T);
}

#[test]
fn an_ignored_sigterm_stays_ignored() {
    let home = common::temp_dir("e2e-sigterm");
    let script = format!("trap '' TERM; exec {BIN} wrap -- /bin/sh");
    let mut h = Harness::spawn("/bin/sh", &["-c", &script], &[("HOME", home.to_str().unwrap())], 80, 24);
    h.send("kill -TERM $PPID; sleep 0.3; echo sur''vived\r");
    h.expect("survived", T);
    h.send("exit 0\r");
    assert_eq!(h.wait_exit(T), 0);
}
```

Change `the_wrapped_shell_is_marked` in `term/tests/wrap.rs` to send `[ "$SHELLX_TERM" = "$(tty)" ] && echo m=tty\r` and expect `m=tty`.

Run: `cargo test --features test-hooks --test agent_link --test wrap` → failures (no link yet; marker still `1`).

- [ ] **Step 3: Wire it into `wrap.rs`**

Changes to `term/src/wrap.rs`. Keep the structure of `run()`; add the pieces below.

New imports:

```rust
use crate::appname::terminal_app;
use crate::link::{Link, LinkEvents, Timing};
use crate::proto::endpoint::default_endpoint_path;
use crate::proto::messages::TermInfo;
use crate::size::{Driver, Resizer, SizeControl};
use std::sync::{Arc, Mutex};
use std::time::{SystemTime, UNIX_EPOCH};
```

Shared pieces and the events adapter (add near the top of the file):

```rust
type SharedWriter = Arc<Mutex<Box<dyn Write + Send>>>;
type SharedMaster = Arc<Mutex<Box<dyn MasterPty + Send>>>;

/// Resizes the PTY through the shared master.
struct MasterResizer(SharedMaster);

impl Resizer for MasterResizer {
    fn resize(&self, cols: u16, rows: u16) {
        if let Ok(master) = self.0.lock() {
            let _ = master.resize(PtySize { rows, cols, pixel_width: 0, pixel_height: 0 });
        }
    }
}

type Size = Arc<Mutex<SizeControl<MasterResizer>>>;

/// The link's view of this terminal.
struct WrapEvents {
    writer: SharedWriter,
    size: Size,
    base: TermInfo,
}

impl LinkEvents for WrapEvents {
    fn info(&self) -> TermInfo {
        let (cols, rows) = current_size();
        TermInfo { cols, rows, ..self.base.clone() }
    }

    fn input(&self, data: &[u8]) {
        if let Ok(mut w) = self.writer.lock() {
            let _ = w.write_all(data);
        }
    }

    fn phone_resize(&self, cols: u16, rows: u16) {
        if let Ok(mut size) = self.size.lock() {
            size.phone_resize((cols, rows));
        }
    }

    fn phone_left(&self) {
        if let Ok(mut size) = self.size.lock() {
            size.phone_left();
        }
    }
}

/// True if SIGTERM was ignored when we started (an interactive shell's
/// parent may do that); we keep ignoring it then.
fn sigterm_ignored() -> bool {
    unsafe {
        let mut old: libc::sigaction = std::mem::zeroed();
        libc::sigaction(libc::SIGTERM, std::ptr::null(), &mut old) == 0 && old.sa_sigaction == libc::SIG_IGN
    }
}

fn now_ms() -> u64 {
    SystemTime::now().duration_since(UNIX_EPOCH).map(|d| d.as_millis() as u64).unwrap_or(0)
}

fn random_term_id() -> [u8; 16] {
    let mut id = [0u8; 16];
    let _ = getrandom::fill(&mut id);
    id
}
```

In `run()`:

1. Before `openpty`, record `let started_at = now_ms();`.
2. Replace `let signals = Signals::new([SIGWINCH, SIGTERM])…` with:
   ```rust
   let watched: &[i32] = if sigterm_ignored() { &[SIGWINCH] } else { &[SIGWINCH, SIGTERM] };
   let signals = Signals::new(watched).map_err(|e| WrapError::Pty(e.to_string()))?;
   ```
3. `shell_command(args)` gets the inner tty: change its signature to `shell_command(args: &WrapArgs, tty: Option<std::path::PathBuf>)` and call it with `pair.master.tty_name()`. Inside it, replace `cmd.env("SHELLX_TERM", "1");` with:
   ```rust
   cmd.env("SHELLX_TERM", tty.map(|p| p.into_os_string()).unwrap_or_else(|| "1".into()));
   cmd.env_remove("SHELLX_TERM_WRAP");
   cmd.env_remove("SHELLX_TERM_WRAP_LOGIN");
   ```
4. After `drop(pair.slave);`:
   ```rust
   let writer: SharedWriter = Arc::new(Mutex::new(to_pty));
   let master: SharedMaster = Arc::new(Mutex::new(pair.master));
   let size: Size = Arc::new(Mutex::new(SizeControl::new(MasterResizer(master.clone()), (cols, rows))));
   let shell_name = std::path::Path::new(&args.shell)
       .file_name()
       .map(|n| n.to_string_lossy().into_owned())
       .unwrap_or_default();
   let base = TermInfo {
       term_id: random_term_id(),
       app: terminal_app(|k| std::env::var(k).ok()),
       shell: shell_name,
       pid: child.process_id().unwrap_or(0),
       cols,
       rows,
       started_at,
   };
   let events = Arc::new(WrapEvents { writer: writer.clone(), size: size.clone(), base });
   let link = Arc::new(Link::start(default_endpoint_path(), Timing::from_env(), events));
   copy_window_to_pty(writer, size.clone(), link.clone(), child.process_id());
   let output_done = copy_pty_to_window(from_pty, link.clone());
   forward_signals(signals, master, size, link.clone());
   ```
   (These replace the existing `copy_window_to_pty(…)`, `copy_pty_to_window(…)` and `forward_signals(…)` calls; `pair.master` is now moved into `master`.)
5. After `let _ = output_done.recv_timeout(DRAIN_AFTER_EXIT);` add `link.finish(code.max(0) as u32);` before `drop(raw)`.

`copy_window_to_pty` — new signature and loop body (hang-up logic unchanged):

```rust
fn copy_window_to_pty(writer: SharedWriter, size: Size, link: Arc<Link>, shell_pid: Option<u32>) {
    std::thread::spawn(move || {
        let mut window = ManuallyDrop::new(unsafe { File::from_raw_fd(STDIN) });
        let mut buf = [0u8; 8192];
        let window_gone = loop {
            match window.read(&mut buf) {
                Ok(0) => break true,
                Ok(n) => {
                    // A desktop keystroke takes the size back from the phone.
                    let notices = match size.lock() {
                        Ok(mut s) if s.driver() == Driver::Phone => s.local_input(),
                        _ => Vec::new(),
                    };
                    for notice in notices {
                        link.send(notice.to_msg());
                    }
                    let ok = match writer.lock() {
                        Ok(mut w) => w.write_all(&buf[..n]).is_ok(),
                        Err(_) => false,
                    };
                    if !ok {
                        break false;
                    }
                }
                Err(e) if e.kind() == ErrorKind::Interrupted => continue,
                Err(_) => break true,
            }
        };
        if window_gone {
            if let Some(pid) = shell_pid {
                unsafe {
                    libc::kill(-(pid as i32), libc::SIGHUP);
                    libc::kill(pid as i32, libc::SIGHUP);
                }
            }
        }
        // The writer stays alive in the shared Arc: dropping portable-pty's
        // writer would type "\n^D" into the shell.
    });
}
```

At the end of `run()`, keep the writer from being dropped (it is still owned by `events` inside the link, which lives until exit; `std::process::exit` follows without running destructors). Add a comment saying so where `writer` is created.

`copy_pty_to_window` — add `link: Arc<Link>` and call `link.output(&buf[..n]);` right after a successful `window.write_all`.

`forward_signals` — new signature `fn forward_signals(mut signals: Signals, master: SharedMaster, size: Size, link: Arc<Link>)`:

```rust
fn forward_signals(mut signals: Signals, master: SharedMaster, size: Size, link: Arc<Link>) {
    std::thread::spawn(move || {
        let _keep_master_open = master;
        // A resize between reading the initial size and registering the
        // signals would otherwise be lost.
        on_window_resize(&size, &link);
        for signal in signals.forever() {
            match signal {
                SIGWINCH => on_window_resize(&size, &link),
                SIGTERM => {
                    tty::restore_saved();
                    std::process::exit(128 + SIGTERM);
                }
                _ => {}
            }
        }
    });
}

fn on_window_resize(size: &Size, link: &Link) {
    let notices = match size.lock() {
        Ok(mut s) => s.window_resized(current_size()),
        Err(_) => return,
    };
    for notice in notices {
        link.send(notice.to_msg());
    }
}
```

Delete the now-unused `resize_to_window` function.

Run: `cargo test --features test-hooks` → all suites pass (the `the_inner_shell_is_marked_with_its_own_tty` test checks that `tty_name()` gives the inner tty; if it returns None, use `libc::ttyname_r` on the slave fd before dropping it, and say so in the report).

- [ ] **Step 4: Gate, 3× suite, commit**

```bash
git add term
git commit -m "feat(term): wrap streams to the agent link; phone input and size; per-tty marker; app name; keep an ignored SIGTERM"
```

---

### Task 7: CLI via environment + `probe`, fallback marker, shell blocks (title, login marker, manual source), bench

**Files:**
- Modify: `term/src/cli.rs`, `term/src/main.rs`, `term/src/fallback.rs`
- Modify: `term/shell/block.zsh`, `term/shell/block.bash`
- Modify: `term/tests/block.rs`, `term/tests/fallback.rs`, `term/examples/startup_bench.rs`

**Interfaces:**
- Consumes: `wrap::run`, `fallback::{Target, exec_shell}`.
- Produces:
  - `cli::Command::Probe`
  - `cli::parse_with_env(args, get: impl Fn(&str) -> Option<OsString>) -> Command`: when there are no arguments and `SHELLX_TERM_WRAP` is an absolute path, the result is `Wrap { login: SHELLX_TERM_WRAP_LOGIN == "1", shell, shell_args: [] }`. `cli::parse(args)` uses the real environment.
  - `cli::parent_executable() -> Option<PathBuf>`
  - Fallback environment: `SHELLX_TERM` = the window's tty (`ttyname_r(0)`), or `0` if there is none.

- [ ] **Step 1: CLI tests (failing)**

Add to the tests module of `term/src/cli.rs`:

```rust
    fn env_of(vars: &'static [(&'static str, &'static str)]) -> impl Fn(&str) -> Option<OsString> {
        move |k| vars.iter().find(|(name, _)| *name == k).map(|(_, v)| OsString::from(v))
    }

    #[test]
    fn no_arguments_wrap_the_shell_named_in_the_environment() {
        assert_eq!(
            parse_with_env(Vec::<OsString>::new(), env_of(&[("SHELLX_TERM_WRAP", "/bin/bash"), ("SHELLX_TERM_WRAP_LOGIN", "1")])),
            wrap(true, "/bin/bash", &[])
        );
        assert_eq!(
            parse_with_env(Vec::<OsString>::new(), env_of(&[("SHELLX_TERM_WRAP", "/bin/zsh")])),
            wrap(false, "/bin/zsh", &[])
        );
    }

    #[test]
    fn no_arguments_without_a_valid_shell_are_invalid() {
        assert_eq!(parse_with_env(Vec::<OsString>::new(), env_of(&[])), Command::Invalid);
        assert_eq!(parse_with_env(Vec::<OsString>::new(), env_of(&[("SHELLX_TERM_WRAP", "zsh")])), Command::Invalid);
    }

    #[test]
    fn probe() {
        assert_eq!(parse_strs(&["probe"]), Command::Probe);
        assert_eq!(parse_strs(&["probe", "x"]), Command::Invalid);
    }

    #[test]
    fn the_parent_executable_is_this_test_runner_s_parent() {
        let parent = parent_executable().expect("parent path");
        assert!(parent.is_absolute(), "{parent:?}");
    }
```

Run: `cargo test --features test-hooks cli::` → compile errors.

- [ ] **Step 2: CLI implementation**

In `term/src/cli.rs`:
- Add the `Probe` variant to `Command`: `/// Print the parent process's executable path (used by the shell blocks).`
- Rename the current `parse` body to `parse_with_env` and add the environment parameter. Make `parse` delegate:

```rust
/// Parses the arguments after the program name, reading the environment.
pub fn parse<I: IntoIterator<Item = OsString>>(args: I) -> Command {
    parse_with_env(args, |k| std::env::var_os(k))
}

/// `parse` with an injectable environment (tests).
pub fn parse_with_env<I: IntoIterator<Item = OsString>>(
    args: I,
    get: impl Fn(&str) -> Option<OsString>,
) -> Command {
    let mut args = args.into_iter();
    match args.next() {
        // The blocks pass the shell through the environment so the
        // window's title shows the shell, not our arguments (spec §5.2).
        None => match get("SHELLX_TERM_WRAP") {
            Some(shell) if Path::new(&shell).is_absolute() => Command::Wrap(WrapArgs {
                login: get("SHELLX_TERM_WRAP_LOGIN").is_some_and(|v| v == "1"),
                shell,
                shell_args: Vec::new(),
            }),
            _ => Command::Invalid,
        },
        Some(first) if first == "--version" => match args.next() {
            None => Command::Version,
            Some(_) => Command::Invalid,
        },
        Some(first) if first == "probe" => match args.next() {
            None => Command::Probe,
            Some(_) => Command::Invalid,
        },
        Some(first) if first == "wrap" => parse_wrap(args),
        Some(_) => Command::Invalid,
    }
}

/// Executable of our parent process: the shell running the block (its
/// `$(…)` subshell is a fork of the same binary).
#[cfg(target_os = "macos")]
pub fn parent_executable() -> Option<std::path::PathBuf> {
    use std::os::unix::ffi::OsStringExt;
    let ppid = unsafe { libc::getppid() };
    let mut buf = vec![0u8; 4096];
    let n = unsafe { libc::proc_pidpath(ppid, buf.as_mut_ptr().cast(), buf.len() as u32) };
    if n <= 0 {
        return None;
    }
    buf.truncate(n as usize);
    Some(std::path::PathBuf::from(OsString::from_vec(buf)))
}

#[cfg(all(unix, not(target_os = "macos")))]
pub fn parent_executable() -> Option<std::path::PathBuf> {
    std::fs::read_link(format!("/proc/{}/exe", unsafe { libc::getppid() })).ok()
}
```

Existing tests that call `parse(…)` with no arguments (`&[]` in `invalid_forms`) now read the real environment; move the empty case into `no_arguments_without_a_valid_shell_are_invalid` and delete it from `invalid_forms`.

In `term/src/main.rs` add the arm:

```rust
        cli::Command::Probe => {
            use std::io::Write;
            match cli::parent_executable() {
                Some(path) => {
                    let _ = writeln!(std::io::stdout(), "{}", path.display());
                }
                None => std::process::exit(1),
            }
        }
```

Run: `cargo test --features test-hooks cli::` → pass.

- [ ] **Step 3: Fallback marks the window's own tty**

In `term/src/fallback.rs`, replace `.env("SHELLX_TERM", "0")` with `.env("SHELLX_TERM", own_tty())` and add:

```rust
/// The window's tty, so the ShellX block in the new shell sees it is
/// already in its own window and does not wrap again; "0" without a tty.
fn own_tty() -> OsString {
    use std::os::unix::ffi::OsStrExt;
    let mut buf = [0 as libc::c_char; 256];
    let ok = unsafe { libc::ttyname_r(0, buf.as_mut_ptr(), buf.len()) } == 0;
    if !ok {
        return OsString::from("0");
    }
    let name = unsafe { std::ffi::CStr::from_ptr(buf.as_ptr()) };
    OsStr::from_bytes(name.to_bytes()).to_os_string()
}
```

Update the doc comment of `exec_shell` accordingly. In `term/tests/fallback.rs` and `term/tests/faults.rs`, the expectations `m=0` become a tty check: send `[ "$SHELLX_TERM" = "$(tty)" ] && echo m=own-tty\r` and expect `m=own-tty`. The no-terminal test stays as is.

- [ ] **Step 4: Blocks**

`term/shell/block.zsh`:

```zsh
# >>> ShellX >>>
# Lets your paired phone see this terminal. Managed by ShellX: turn it off from the ShellX menu instead of editing it.
if [[ -o interactive && -z "${ZSH_EXECUTION_STRING-}" && -z "${ZSH_SCRIPT-}" \
      && $ZSH_EVAL_CONTEXT != toplevel* && -t 0 && -t 1 \
      && -z "${SHELLX-}${TMUX-}${STY-}" && "${SHELLX_TERM-}" != "$TTY" \
      && "${TERM_PROGRAM-}" != WarpTerminal \
      && -f "$HOME/Library/Application Support/ShellX/bin/shellx-term" \
      && -x "$HOME/Library/Application Support/ShellX/bin/shellx-term" ]]; then
  # One run: proves the binary works (zsh exits if exec fails) and names this exact shell binary.
  __shellx_shell=$("$HOME/Library/Application Support/ShellX/bin/shellx-term" probe 2>/dev/null)
  if [[ $__shellx_shell == /* ]]; then
    # VS Code/Cursor and JetBrains start zsh with ZDOTDIR pointing at their own dir; point it back
    # there so the inner shell re-runs their integration.
    if [[ -n "${VSCODE_ZDOTDIR-}" ]]; then export ZDOTDIR=$VSCODE_ZDOTDIR
    elif [[ -n "${_INTELLIJ_ZDOTDIR-}" ]]; then export ZDOTDIR=$_INTELLIJ_ZDOTDIR; fi
    [[ -o login ]] && export SHELLX_TERM_LOGIN=1
    export SHELLX_TERM_WRAP=$__shellx_shell
    exec -a "$ZSH_ARGZERO" "$HOME/Library/Application Support/ShellX/bin/shellx-term"
  fi
  unset __shellx_shell
elif [[ -n "${SHELLX_TERM_LOGIN-}" && "${SHELLX_TERM-}" == "$TTY" ]]; then
  # Inside the wrapped shell: act as the login shell this window started (zsh then reads ~/.zlogin).
  unset SHELLX_TERM_LOGIN
  setopt login
fi
# <<< ShellX <<<
```

`term/shell/block.bash` (bash 3.2):

```bash
# >>> ShellX >>>
# Lets your paired phone see this terminal. Managed by ShellX: turn it off from the ShellX menu instead of editing it.
if [[ $- == *i* && -z "${BASH_EXECUTION_STRING-}" && "${BASH_LINENO[0]-0}" == 0 && -t 0 && -t 1 \
      && -z "${SHELLX-}${TMUX-}${STY-}" \
      && "${TERM_PROGRAM-}" != WarpTerminal \
      && "${TERM_PROGRAM-}" != vscode \
      && "${TERMINAL_EMULATOR-}" != JetBrains-JediTerm \
      && -f "$HOME/Library/Application Support/ShellX/bin/shellx-term" \
      && -x "$HOME/Library/Application Support/ShellX/bin/shellx-term" ]] \
   && { [[ -z "${SHELLX_TERM-}" ]] || [[ "$SHELLX_TERM" != "$(tty)" ]]; }; then
  __shellx_shell=$("$HOME/Library/Application Support/ShellX/bin/shellx-term" probe 2>/dev/null)
  if [[ $__shellx_shell == /* ]]; then
    export SHELLX_TERM_WRAP=$__shellx_shell
    if shopt -q login_shell; then export SHELLX_TERM_WRAP_LOGIN=1; fi
    exec -a "$0" "$HOME/Library/Application Support/ShellX/bin/shellx-term"
    unset SHELLX_TERM_WRAP SHELLX_TERM_WRAP_LOGIN
  fi
  unset __shellx_shell
fi
# <<< ShellX <<<
```

Why each change (copy into the spec in Task 8):
- `"${SHELLX_TERM-}" != "$TTY"` (zsh; bash compares with `$(tty)` only when the variable is set). A shell is skipped only when it sits in the very tty `shellx-term` created. Terminal apps launched from a wrapped window (`code .`) now wrap their own terminals, and a `zsh` typed inside a wrapped window still does not wrap.
- `probe` replaces `--version`: one spawn both proves the binary runs and returns the exact shell binary, which fixes the wrong-zsh case.
- `exec -a "$ZSH_ARGZERO"` / `exec -a "$0"` with no arguments: Terminal.app's title shows `-zsh` again (the shell is passed in `SHELLX_TERM_WRAP`).
- `SHELLX_TERM_LOGIN` + `setopt login`: `logout`, `[[ -o login ]]` and `~/.zlogin` behave as in a normal window, without re-running `/etc/zprofile` (which reorders PATH).
- `BASH_LINENO[0] == 0`: a manual `. ~/.bashrc` (line ≠ 0) no longer replaces the running bash.

- [ ] **Step 5: Update the block tests**

In `term/tests/block.rs`:

- The fake binary becomes:

```rust
    std::fs::write(
        &fake,
        "#!/bin/sh\n\
         printf '%s\\n' \"$*\" >> \"$HOME/calls.log\"\n\
         if [ \"$1\" = probe ]; then printf '%s\\n' \"${SHELLX_FAKE_PROBE:-/bin/zsh}\"; exit 0; fi\n\
         printf 'WRAPPED'; for a in \"$@\"; do printf ' [%s]' \"$a\"; done\n\
         printf ' wrap=[%s] login=[%s] marker=[%s]\\n' \"${SHELLX_TERM_WRAP-}\" \"${SHELLX_TERM_WRAP_LOGIN-}\" \"${SHELLX_TERM_LOGIN-}\"\n\
         printf 'ZDOTDIR=[%s]\\n' \"${ZDOTDIR-unset}\"\n\
         exit 0\n",
    )
    .unwrap();
```

- Expected wrap lines change from `WRAPPED [wrap] [--] [/bin/zsh]` to `WRAPPED wrap=[/bin/zsh] login=[] marker=[]`. For `zsh -il` the line is `WRAPPED wrap=[/bin/zsh] login=[] marker=[1]`. For bash tests (set `SHELLX_FAKE_PROBE=/bin/bash`) it is `WRAPPED wrap=[/bin/bash] login=[]`, or `login=[1]` for `bash -il`.
- The probe-order test now expects `calls.log` to read `probe` then an empty line (the wrap call has no arguments).
- The unrunnable-binary and directory tests stay. They now exercise `probe` failing.
- New tests:
  - `a_terminal_app_launched_from_a_wrapped_window_wraps_its_own_terminals`: `SHELLX_TERM=/dev/ttys999` in the environment → zsh is wrapped.
  - `bash_manual_source_does_not_replace_the_running_bash`: write the bash block to `~/blk.sh`; start `/bin/bash -i` (its `.bashrc` holds only `echo AFTER-BLOCK`); send `. ~/blk.sh; echo after''-src\r`; expect `after-src`; assert no `WRAPPED`.
  - With the real binary copied in:
    1. `zsh -i`: inside, `[[ $SHELLX_TERM == $TTY ]] && echo SAME''-TTY` prints `SAME-TTY`, and `ps -o args= -p $PPID` does not contain `wrap`, i.e. `shellx-term` runs with only its argv0.
    2. `zsh -il` with `~/.zlogin` = `echo ZLOGIN-RAN`: `ZLOGIN-RAN` appears exactly once, `[[ -o login ]] && echo LOGIN''-ON` prints `LOGIN-ON`, and `logout` ends the window with exit code 0.
    3. Inside the wrapped shell, type `zsh -i` then `ps -o comm= -p $PPID; exit`: the printed parent is `zsh`, not `shellx-term` (no nested wrap).

- [ ] **Step 6: Bench**

In `term/examples/startup_bench.rs` keep two variants: `baseline` and `wrapped (shipped block)`. Remove the login-variant replacement and its assert, and keep the assert that the block contains the installed path. Build and run it (it only reads the real startup files through a temporary ZDOTDIR):

```bash
cd term && cargo build --release && cargo run --release --example startup_bench
```

Record both lines in the report. The overhead median must be < 50 ms; if it is not, report DONE_WITH_CONCERNS with the numbers. Do not tune.

- [ ] **Step 7: Gate, 3× suite, commit**

```bash
git add term
git commit -m "feat(term): env-based wrap with the shell's own argv0, probe, per-tty skip, zsh login marker, bash manual-source guard"
```

---

### Task 8: Spec, ledger and handoff

**Files:**
- Modify: `docs/superpowers/specs/2026-10-01-desktop-terminal-sharing-design.md`
- Modify: `docs/superpowers/ledgers/terminal-sharing.md`, `docs/superpowers/HANDOFF.md`

**Interfaces:**
- Consumes: everything above; the numbers from Task 7's bench.

- [ ] **Step 1: Spec amendments (Vietnamese, the spec's style)**

1. **§5.1:** add the ways `shellx-term` is invoked.
   - `shellx-term` with no arguments + `SHELLX_TERM_WRAP` (+ `SHELLX_TERM_WRAP_LOGIN`): this is how the blocks call it, so the window title shows the shell.
   - `shellx-term probe` prints the executable of the parent process.
   - The inner shell's `SHELLX_TERM` holds the inner tty's path.
2. **§5.2:** replace the conditions and steps with what the Task 7 blocks do:
   - `SHELLX_TERM` compared with `$TTY` / `$(tty)`;
   - `probe` instead of `--version`;
   - `exec -a`;
   - `SHELLX_TERM_LOGIN` + `setopt login`, and remove the login-related cost added in P1;
   - `BASH_LINENO[0] == 0`;
   - the "known gap" sentence: `bash -i script` is still a gap; manual `source` is now handled for both shells.
3. **§5.4:** if SIGTERM was ignored when `shellx-term` started, it stays ignored. The fallback's `SHELLX_TERM` is the window's tty.
4. **§6.1:** the endpoint file format, exactly as in Global Constraints.
5. **§6.2/§6.4:** `snapshot` has fields `data` and `last`, is sent in pieces of ≤ 60 KiB, is always first after `ready`, and is sent as one piece with empty `data` and `last: true` when there is no output yet. `out` is also sent in pieces of ≤ 60 KiB.
6. **§6.3:** `pid` is the inner shell's pid. `started_at` is Unix ms when `shellx-term` started. `app` comes from `__CFBundleIdentifier` first (list the table), then `TERM_PROGRAM`, then `TERMINAL_EMULATOR`. A `reject` may also come instead of `challenge`. Reference bytes are in `term/protocol/vectors.txt` (plan P3 must match them byte for byte).
7. **§6.5:** reconnect timings (backoff 1/2/4/8/10 s, limit 30 s, version: wait for the endpoint to change, polled every 10 s); socket write timeout 1 s; a hung agent ends the session when its write times out or the 1 MiB outbox overflows; `exit` flush ≤ 200 ms.

- [ ] **Step 2: Ledger and handoff**

- In `docs/superpowers/ledgers/terminal-sharing.md`, add a "P2a" section.
  - The bench line from Task 7.
  - Each item from "Ghi cho P2", marked done (with commit) or still open:
    - JetBrains with a custom ZDOTDIR: still open.
    - Terminal.app session restore: still open; manual check.
- In `docs/superpowers/HANDOFF.md` §9, record that P2a is done and that P2b (Windows) and P3 (agent) come next.

- [ ] **Step 3: Commit**

```bash
git add docs
git commit -m "docs: terminal sharing P2a — link protocol details, blocks, timings, vectors; ledger and handoff"
```
