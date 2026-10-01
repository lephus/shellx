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

/// Name prefix of every thread of the link; see `is_link_thread`.
pub const LINK_THREAD: &str = "shellx-link";

/// True on a thread that belongs to the link. A panic there must not take
/// the terminal down (the panic hook ignores it).
pub fn is_link_thread() -> bool {
    std::thread::current()
        .name()
        .is_some_and(|name| name.starts_with(LINK_THREAD))
}

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
        if faults::fast_timing() {
            Timing::fast()
        } else {
            Timing::standard()
        }
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
            output: Mutex::new(OutputState {
                ring: RingBuffer::new(CAPACITY),
                live: false,
            }),
            outbox: Outbox::new(LIMIT),
            finishing: AtomicBool::new(false),
            wake: (Mutex::new(()), Condvar::new()),
        });
        if let Some(path) = endpoint {
            let shared = shared.clone();
            let timing = timing.clone();
            // Named so the panic hook can tell a link bug (the link stops, the
            // terminal carries on) from a bug on the window path. If the
            // thread cannot start there is simply no session this time.
            let _ = std::thread::Builder::new()
                .name(LINK_THREAD.into())
                .spawn(move || connection_loop(path, timing, shared, events));
        }
        Link { shared, timing }
    }

    /// The shell printed `bytes`. Never blocks on the agent.
    pub fn output(&self, bytes: &[u8]) {
        let mut state = lock(&self.shared.output);
        state.ring.push(bytes);
        if state.live {
            for piece in bytes.chunks(SNAPSHOT_PIECE) {
                self.shared.outbox.push(
                    TermMsg::Out {
                        data: piece.to_vec(),
                    }
                    .encode(),
                );
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
            // `live` ends in the same locked block as `exit` is queued, so
            // no `out` or notice frame can follow it.
            let mut state = lock(&self.shared.output);
            if state.live {
                self.shared.outbox.push(TermMsg::Exit { code }.encode());
                state.live = false;
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

fn connection_loop(
    path: PathBuf,
    timing: Timing,
    shared: Arc<Shared>,
    events: Arc<dyn LinkEvents>,
) {
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
        if faults::hit("link-panic") {
            panic!("injected link fault");
        }
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
        match handshake(
            &mut stream,
            &endpoint.secret,
            &events.info(),
            timing.handshake,
        ) {
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
            std::thread::Builder::new()
                .name(format!("{LINK_THREAD}-reader"))
                .spawn(move || read_agent(r, events))
                .ok()
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
        return write_frame(
            writer,
            &TermMsg::Snapshot {
                data: vec![],
                last: true,
            }
            .encode(),
        )
        .is_ok();
    }
    while let Some(piece) = pieces.next() {
        let last = pieces.peek().is_none();
        if write_frame(
            writer,
            &TermMsg::Snapshot {
                data: piece.to_vec(),
                last,
            }
            .encode(),
        )
        .is_err()
        {
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
            Err(_) => break,
        }
    }
    // The session is over (EOF, error or a frame we cannot decode): fail
    // the writer's next write at once instead of waiting for its poll.
    let _ = stream.shutdown(Shutdown::Both);
}
