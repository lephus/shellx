//! `RemoteSession`: one Mac (one `RemoteClient`) shared by all its panes.
//! GPUI-free. A worker thread owns the `ConnState` machine and runs its
//! actions; every blocking call (ticket mint, connect, list/create/attach,
//! the end check) runs on a job thread, so neither the UI thread nor the
//! worker ever waits on the network. The UI thread only calls the
//! non-blocking methods here, reads `status()` snapshots and drains its
//! pane sinks.
//!
//! Connect path (Task 13 brief, Task 6 carry-over, R17):
//! - `MintTicket` -> `tickets.mint` (permission connect) written to
//!   `connect-<machine_id>.ticket`; `Connect` -> `RemoteClient::connect`
//!   whose ticket callback returns that ticket first and mints a fresh one
//!   on every later call (relay reconnects inside the client).
//! - The invitation is used only while the link is not enrolled. After the
//!   first successful connect whose daemon fingerprint equals the one
//!   `pair.poll` returned (stored in the link), the invitation file is
//!   DELETED and the link saved with `enrolled = true`. A fingerprint
//!   mismatch drops the client and never attaches (`SessionError`).
//! - Then every pane attaches: its terminal if the Mac still lists it, else
//!   the first listed terminal (`Want::First`, or a free one after a daemon
//!   restart), else a new one; `Want::New` (split) creates one on the Mac.
//! - `AttachEvent::Ended` is confirmed with `list_terminals`: the terminal
//!   gone -> the pane ends (last pane -> `RemoteEnded`); the client closed
//!   or the call failing -> disconnect and reconnect (a gracefully stopping
//!   daemon detaches every view first); still listed -> reattach.
//! - A disconnect drops the client and every view (input is refused at
//!   once) and `ConnState` backs off 1, 2, 4, 8, 16, 30 s, each attempt with
//!   a freshly minted ticket.
// Wired into the window by Task 13b; `--smoke` and tests use it today.
#![allow(dead_code)]

use std::collections::BTreeMap;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::mpsc::{self, Receiver, RecvTimeoutError, Sender};
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

use anyhow::{Result, anyhow, bail};
use shellx_model::core_api::{CoreCall, CoreErr, TicketFile, mint_connect_ticket};
use shellx_model::links::RemoteLink as LinkRecord;
use shellx_model::remote_state::{ConnAction, ConnEvent, ConnPhase, ConnState, backoff_ms};
use shellx_model::strings::Str;
use shellx_remote::{AttachEvent, ConnectConfig, RemoteClient, RemoteTerminal};

use crate::links_store::LinksStore;
use crate::remote_link::{PaneEvent, PaneSink, PumpEnd, RemoteLink, ViewInput, pump};

/// How often the worker checks that the live client is still open.
const WATCHDOG: Duration = Duration::from_millis(500);

// ------------------------------------------------------------ seams

/// A connected client of one Mac (`RemoteClient`, or a fake in tests).
pub trait Host: Send + Sync {
    fn daemon_fingerprint(&self) -> String;
    fn list_terminals(&self) -> Result<Vec<RemoteTerminal>>;
    fn create_terminal(&self) -> Result<RemoteTerminal>;
    fn attach(
        &self,
        terminal_id: &str,
        cols: u16,
        rows: u16,
    ) -> Result<(Arc<dyn ViewInput>, Receiver<AttachEvent>)>;
    fn closed(&self) -> bool;
}

impl Host for RemoteClient {
    fn daemon_fingerprint(&self) -> String {
        RemoteClient::daemon_fingerprint(self).to_string()
    }
    fn list_terminals(&self) -> Result<Vec<RemoteTerminal>> {
        RemoteClient::list_terminals(self)
    }
    fn create_terminal(&self) -> Result<RemoteTerminal> {
        RemoteClient::create_terminal(self)
    }
    fn attach(
        &self,
        terminal_id: &str,
        cols: u16,
        rows: u16,
    ) -> Result<(Arc<dyn ViewInput>, Receiver<AttachEvent>)> {
        let (input, events) = RemoteClient::attach(self, terminal_id, cols, rows)?.into_parts();
        Ok((Arc::new(input), events))
    }
    fn closed(&self) -> bool {
        RemoteClient::closed(self)
    }
}

/// Makes `Host`s (`RelayConnector` in the app).
pub trait Connector: Send + Sync {
    fn is_enrolled(&self, state_dir: &Path, daemon_fingerprint: &str) -> bool;
    /// Blocking (up to 300 s while the Mac owner approves an enrollment).
    fn connect(&self, cfg: ConnectConfig) -> Result<Arc<dyn Host>>;
}

/// The real thing: `shellx_remote::RemoteClient` over relay v2.
pub struct RelayConnector;

impl Connector for RelayConnector {
    fn is_enrolled(&self, state_dir: &Path, daemon_fingerprint: &str) -> bool {
        RemoteClient::is_enrolled(state_dir, daemon_fingerprint)
    }
    fn connect(&self, cfg: ConnectConfig) -> Result<Arc<dyn Host>> {
        Ok(Arc::new(RemoteClient::connect(cfg)?))
    }
}

// ------------------------------------------------------------ public API

pub struct SessionConfig {
    /// The saved link (`links.json`) of this Mac.
    pub record: LinkRecord,
    pub core: Arc<dyn CoreCall>,
    pub connector: Arc<dyn Connector>,
    /// cmux-remote client identity dir (`paths::remote_dir()`).
    pub state_dir: PathBuf,
    /// shellx-core's tickets dir (`paths::core_dir()?.join("tickets")`):
    /// an invitation is deleted only from here (and only `invite-*.uri`).
    pub invite_dir: PathBuf,
    /// Shown on the Mac's approval screen (`os_info::device_name()`).
    pub device_name: String,
    /// Where `enrolled = true` is saved after the first connect.
    pub links: Option<LinksStore>,
    /// 1 in the app. Tests run the backoff clock this many times faster.
    pub time_scale: u64,
}

/// A session-ending problem the UI shows instead of reconnecting.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum SessionError {
    /// The Mac's daemon key is not the one approved at pairing: never attach.
    FingerprintMismatch { expected: String, got: String },
    /// Invitation expired or this PC is not enrolled: request access again.
    NeedsPairing(String),
}

/// Snapshot for the UI thread (`RemoteSession::status`).
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct SessionStatus {
    pub phase: ConnPhase,
    /// The pill text of the last `ShowStatus` (Connecting / Reconnecting /
    /// Offline / RemoteEnded).
    pub shown: Option<Str>,
    /// Why the last attempt failed (for a tooltip / log).
    pub reason: Option<String>,
    pub error: Option<SessionError>,
    /// Saving `enrolled` to `links.json` failed (the connect still works;
    /// the next start falls back to the client's own enrollment record).
    pub save_error: Option<String>,
    /// The last attach of a pane failed while the connection is fine; the
    /// pane retries on its own backoff (cleared when every pane attached).
    pub attach_error: Option<String>,
    /// The worker stopped (closed, ended or failed for good): open a new
    /// session for this Mac next time.
    pub finished: bool,
}

impl SessionStatus {
    fn new() -> SessionStatus {
        SessionStatus {
            phase: ConnPhase::Disconnected,
            shown: None,
            reason: None,
            error: None,
            save_error: None,
            attach_error: None,
            finished: false,
        }
    }
}

/// Which remote terminal a new pane shows.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Want {
    /// The first terminal the Mac lists (one is created when it has none).
    First,
    /// This terminal (`PaneTarget::Remote::terminal_id`).
    Terminal(String),
    /// A new terminal on the Mac (a split of a remote pane, spec §8.6 C12).
    New,
}

pub struct RemotePane {
    pub id: u64,
    pub link: Arc<RemoteLink>,
}

pub struct RemoteSession {
    machine_id: String,
    tx: Sender<Msg>,
    status: Arc<Mutex<SessionStatus>>,
    next_pane: AtomicU64,
}

impl RemoteSession {
    /// Start the worker. Nothing connects until the first `open_pane`.
    pub fn start(cfg: SessionConfig) -> Result<RemoteSession> {
        let machine_id = cfg.record.machine_id.clone();
        let (tx, rx) = mpsc::channel();
        let status = Arc::new(Mutex::new(SessionStatus::new()));
        let worker = Worker::new(cfg, tx.clone(), status.clone());
        std::thread::Builder::new()
            .name(format!("shellx-session-{machine_id}"))
            .spawn(move || worker.run(rx))?;
        Ok(RemoteSession {
            machine_id,
            tx,
            status,
            next_pane: AtomicU64::new(1),
        })
    }

    pub fn machine_id(&self) -> &str {
        &self.machine_id
    }

    /// A new remote pane at `cols` x `rows`. Its events (screen bytes,
    /// status changes, end) go to `sink`; type into it through the returned
    /// link (`RemoteMirror` over it). Non-blocking.
    pub fn open_pane(
        &self,
        want: Want,
        cols: u16,
        rows: u16,
        sink: PaneSink,
    ) -> Result<RemotePane> {
        // Checked and sent under the status lock: once the worker published
        // `finished`, no OpenPane can slip in behind its final drain.
        let status = lock(&self.status);
        if status.finished {
            bail!("this remote session has finished");
        }
        let id = self.next_pane.fetch_add(1, Ordering::Relaxed);
        let link = RemoteLink::new(cols, rows);
        self.tx
            .send(Msg::OpenPane {
                pane: id,
                want,
                link: link.clone(),
                sink,
            })
            .map_err(|_| anyhow!("this remote session has finished"))?;
        drop(status);
        Ok(RemotePane { id, link })
    }

    /// The pane was closed in the UI (detaches its view; the last pane
    /// closes the session).
    pub fn close_pane(&self, pane: u64) {
        let _ = self.tx.send(Msg::ClosePane { pane });
    }

    /// From the 15 s machine list poll.
    pub fn set_machine_online(&self, online: bool) {
        let _ = self.tx.send(Msg::MachineOnline(online));
    }

    pub fn status(&self) -> SessionStatus {
        self.status
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner())
            .clone()
    }

    /// Tear everything down (non-blocking).
    pub fn close(&self) {
        let _ = self.tx.send(Msg::Close);
    }
}

impl Drop for RemoteSession {
    fn drop(&mut self) {
        self.close();
    }
}

/// `connect-<machine_id>.ticket`, made a bare name shellx-core accepts
/// (`[a-z0-9._-]`, at most 64 bytes, starting with a letter or digit).
pub fn ticket_file_name(machine_id: &str) -> String {
    let mut id: String = machine_id
        .to_ascii_lowercase()
        .chars()
        .map(|c| {
            if c.is_ascii_lowercase() || c.is_ascii_digit() || matches!(c, '.' | '_' | '-') {
                c
            } else {
                '-'
            }
        })
        .collect();
    id.truncate(64 - "connect-".len() - ".ticket".len());
    format!("connect-{id}.ticket")
}

// ------------------------------------------------------------ worker

enum LinkFail {
    Fingerprint { expected: String, got: String },
    NeedsPairing(String),
    Other(String),
}

struct Linked {
    host: Arc<dyn Host>,
    save_error: Option<String>,
}

type Attached = (
    Arc<dyn ViewInput>,
    Receiver<AttachEvent>,
    String,
    (u16, u16),
);

/// An attached view: its input half, its events and the terminal id.
type View = (Arc<dyn ViewInput>, Receiver<AttachEvent>, String);

/// An attach that failed; `created` is a terminal this attempt opened on the
/// Mac (a retry attaches to it instead of opening another).
struct AttachFail {
    reason: String,
    created: Option<String>,
}

enum EndCheck {
    Gone,
    StillThere,
    Lost(String),
}

enum Msg {
    OpenPane {
        pane: u64,
        want: Want,
        link: Arc<RemoteLink>,
        sink: PaneSink,
    },
    ClosePane {
        pane: u64,
    },
    MachineOnline(bool),
    Close,
    Minted {
        attempt: u32,
        result: Result<TicketFile, CoreErr>,
    },
    Linked {
        attempt: u32,
        result: Result<Linked, LinkFail>,
    },
    Attached {
        attempt: u32,
        pane: u64,
        result: Result<Attached, AttachFail>,
    },
    ViewEnd {
        attempt: u32,
        pane: u64,
        view_gen: u64,
        end: PumpEnd,
    },
    EndChecked {
        attempt: u32,
        pane: u64,
        view_gen: u64,
        check: EndCheck,
    },
}

struct Pane {
    link: Arc<RemoteLink>,
    sink: PaneSink,
    want: Want,
    /// The terminal this pane wants or created (claimed against splits).
    terminal_id: Option<String>,
    /// The terminal id the UI knows: given in `Want::Terminal`, or the last
    /// `Retargeted` its sink took. Differs from the attached id -> announce.
    announced: Option<String>,
    attaching: bool,
    /// Generation of the installed view (`RemoteLink::install`).
    view_gen: Option<u64>,
    /// Consecutive attach failures on an open connection, and when to retry
    /// (same 1, 2, 4, 8, 16, 30 s schedule as reconnects).
    attach_failures: u32,
    retry_at: Option<u64>,
}

/// What a job thread needs to mint and connect (cloned into it).
#[derive(Clone)]
struct Ctx {
    machine_id: String,
    ticket_name: String,
    core: Arc<dyn CoreCall>,
    connector: Arc<dyn Connector>,
    state_dir: PathBuf,
    invite_dir: PathBuf,
    device_name: String,
    links: Option<Arc<LinksStore>>,
    record: Arc<Mutex<LinkRecord>>,
    /// The last ticket file shellx-core wrote (deleted when the session ends).
    last_ticket: Arc<Mutex<Option<PathBuf>>>,
}

/// Why the worker loop stopped.
#[derive(Clone, Copy, PartialEq, Eq)]
enum Stop {
    /// The last pane closed: a queued `OpenPane` revives the session. While
    /// an enrollment job still runs the session is not finished yet (see
    /// `Worker::park`).
    Idle,
    /// Closed by the app, the remote side ended, or a session error.
    Final,
}

struct Worker {
    ctx: Ctx,
    tx: Sender<Msg>,
    status: Arc<Mutex<SessionStatus>>,
    state: ConnState,
    panes: BTreeMap<u64, Pane>,
    /// Attempt whose connect job is running.
    connecting: Option<u32>,
    /// Attempt whose connect job enrolls with the invitation (it may outlive
    /// its attempt: the Mac owner can approve up to 300 s later).
    enrolling: Option<u32>,
    /// A connect held back while `enrolling` runs (one invitation, one
    /// enrollment): (attempt, ticket path).
    deferred: Option<(u32, String)>,
    live: Option<(u32, Arc<dyn Host>)>,
    next_tick: Option<u64>,
    shown: Option<Str>,
    error: Option<SessionError>,
    save_error: Option<String>,
    attach_error: Option<String>,
    started: Instant,
    time_scale: u64,
    stop: Option<Stop>,
}

fn lock<T>(m: &Mutex<T>) -> std::sync::MutexGuard<'_, T> {
    m.lock().unwrap_or_else(|poisoned| poisoned.into_inner())
}

/// Run `job` on its own thread. If the thread cannot start, `on_fail` goes
/// to the worker instead, so the attempt fails (and backs off) rather than
/// hanging.
fn spawn_job(tx: &Sender<Msg>, name: &str, on_fail: Msg, job: impl FnOnce() + Send + 'static) {
    if let Err(error) = std::thread::Builder::new()
        .name(format!("shellx-remote-{name}"))
        .spawn(job)
    {
        eprintln!("shellx: could not start the {name} job: {error}");
        let _ = tx.send(on_fail);
    }
}

fn spawn_failed(name: &str) -> String {
    format!("could not start the {name} thread")
}

impl Worker {
    fn new(cfg: SessionConfig, tx: Sender<Msg>, status: Arc<Mutex<SessionStatus>>) -> Worker {
        Worker {
            ctx: Ctx {
                machine_id: cfg.record.machine_id.clone(),
                ticket_name: ticket_file_name(&cfg.record.machine_id),
                core: cfg.core,
                connector: cfg.connector,
                state_dir: cfg.state_dir,
                invite_dir: cfg.invite_dir,
                device_name: cfg.device_name,
                links: cfg.links.map(Arc::new),
                record: Arc::new(Mutex::new(cfg.record)),
                last_ticket: Arc::new(Mutex::new(None)),
            },
            tx,
            status,
            state: ConnState::new(),
            panes: BTreeMap::new(),
            connecting: None,
            enrolling: None,
            deferred: None,
            live: None,
            next_tick: None,
            shown: None,
            error: None,
            save_error: None,
            attach_error: None,
            started: Instant::now(),
            time_scale: cfg.time_scale.max(1),
            stop: None,
        }
    }

    fn now_ms(&self) -> u64 {
        (self.started.elapsed().as_millis() as u64).saturating_mul(self.time_scale)
    }

    /// The first reason to stop wins (closing the last pane sets Idle
    /// before `ConnEvent::Close` ends the state machine).
    fn stop(&mut self, how: Stop) {
        if self.stop.is_none() {
            self.stop = Some(how);
        }
    }

    fn run(mut self, rx: Receiver<Msg>) {
        loop {
            self.serve(&rx);
            if self.stop == Some(Stop::Idle) && self.enrolling.is_some() && self.park(&rx) {
                continue; // a new pane came while the enrollment ran
            }
            // `finished` is published under the status lock that
            // `open_pane` sends under, so every OpenPane sent before it is
            // already queued here.
            self.publish();
            let mut revived = false;
            let mut late = Vec::new();
            while let Ok(msg) = rx.try_recv() {
                match msg {
                    Msg::OpenPane { .. } if self.stop == Some(Stop::Idle) => {
                        if !revived {
                            revived = true;
                            self.revive();
                        }
                        self.handle(msg);
                    }
                    Msg::OpenPane { link, sink, .. } => late.push((link, sink)),
                    // Handled even while stopped: an enrollment result
                    // must end `enrolling` (else a revived connect waits
                    // for it forever), a `Close` makes the stop final, and
                    // every other late result is ignored by `handle`.
                    other => self.handle(other),
                }
            }
            if revived {
                continue; // serve again (or re-check the stop it reached)
            }
            // Panes opened on a session that ended for good: a session
            // error stays visible on them, otherwise they end at once.
            for (link, sink) in late {
                if self.error.is_some() {
                    sink(PaneEvent::Status);
                } else {
                    link.mark_ended();
                    sink(PaneEvent::Ended);
                }
            }
            break;
        }
        if let Some(path) = lock(&self.ctx.last_ticket).take() {
            let _ = std::fs::remove_file(path);
        }
    }

    /// The last pane closed while the invitation's enrollment still waits
    /// for the Mac owner (up to 300 s). The session stays, NOT finished, so
    /// the app reuses it for its next pane instead of starting a second
    /// session that would enroll the same invitation again (Task 13b review).
    /// Returns true when a new pane revived it (its connect then waits for
    /// the enrollment and takes its host, see `linked`); false when the
    /// enrollment ended with no pane (finish idle, as before) or the session
    /// was closed (sign-out, app exit).
    fn park(&mut self, rx: &Receiver<Msg>) -> bool {
        self.publish(); // not finished: `open_pane` still sends here
        while self.stop == Some(Stop::Idle) && self.enrolling.is_some() {
            match rx.recv() {
                Ok(msg @ Msg::OpenPane { .. }) => {
                    self.revive();
                    self.handle(msg);
                    return true;
                }
                // The enrollment result ends `enrolling` (its client drops:
                // no pane wants it); `Close` makes the stop final.
                Ok(msg) => self.handle(msg),
                Err(_) => self.handle(Msg::Close),
            }
        }
        false
    }

    /// The last pane closed and a new one was already on its way: start over.
    /// Attempt ids continue (`restarted`), so a job of the old incarnation
    /// that reports late (an enrollment can wait 300 s for approval) never
    /// passes for the new attempt's. `enrolling` stays: that job still
    /// runs, and a new connect waits for it (one invitation, one
    /// enrollment); `connecting` and `deferred` were cleared by `serve`.
    fn revive(&mut self) {
        self.state = self.state.restarted();
        self.stop = None;
        self.shown = None;
        self.attach_error = None;
        self.next_tick = None;
        self.publish();
    }

    fn serve(&mut self, rx: &Receiver<Msg>) {
        while self.stop.is_none() {
            let mut wait = WATCHDOG;
            let now = self.now_ms();
            let next = self
                .panes
                .values()
                .filter_map(|p| p.retry_at)
                .chain(self.next_tick)
                .min();
            if let Some(at) = next {
                let left = at.saturating_sub(now) / self.time_scale;
                wait = wait.min(Duration::from_millis(left));
            }
            match rx.recv_timeout(wait) {
                Ok(msg) => self.handle(msg),
                Err(RecvTimeoutError::Timeout) => {}
                Err(RecvTimeoutError::Disconnected) => self.handle(Msg::Close),
            }
            if self.stop.is_some() {
                break;
            }
            let now = self.now_ms();
            if self.next_tick.is_some_and(|at| now >= at) {
                self.next_tick = None;
                self.feed(ConnEvent::Tick);
            }
            let due: Vec<u64> = self
                .panes
                .iter()
                .filter(|(_, p)| p.retry_at.is_some_and(|at| now >= at))
                .map(|(id, _)| *id)
                .collect();
            for pane in due {
                if let Some(p) = self.panes.get_mut(&pane) {
                    p.retry_at = None;
                }
                self.attach(pane);
            }
            let closed = self
                .live
                .as_ref()
                .and_then(|(attempt, host)| host.closed().then_some(*attempt));
            if let Some(attempt) = closed {
                self.lose(attempt, "the connection to the Mac closed".into());
            }
        }
        self.connecting = None;
        self.deferred = None;
        self.drop_live();
    }

    fn publish(&self) {
        let next = SessionStatus {
            phase: self.state.phase().clone(),
            shown: self.shown,
            reason: self.state.last_reason().map(str::to_owned),
            error: self.error.clone(),
            save_error: self.save_error.clone(),
            attach_error: self.attach_error.clone(),
            // Idle with an enrollment in flight is parked, not finished.
            finished: match self.stop {
                None => false,
                Some(Stop::Idle) => self.enrolling.is_none(),
                Some(Stop::Final) => true,
            },
        };
        let changed = {
            let mut status = lock(&self.status);
            let changed = *status != next;
            *status = next;
            changed
        };
        if changed {
            for pane in self.panes.values() {
                (pane.sink)(PaneEvent::Status);
            }
        }
    }

    fn feed(&mut self, event: ConnEvent) {
        let actions = self.state.on(event, self.now_ms());
        for action in actions {
            self.act(action);
        }
        if *self.state.phase() == ConnPhase::Connected {
            // The pill is for the states before Connected only.
            self.shown = None;
        }
        self.publish();
    }

    fn act(&mut self, action: ConnAction) {
        match action {
            ConnAction::MintTicket { attempt } => {
                let (ctx, tx) = (self.ctx.clone(), self.tx.clone());
                let on_fail = Msg::Minted {
                    attempt,
                    result: Err(CoreErr::new("spawn", &spawn_failed("mint"))),
                };
                spawn_job(&self.tx, "mint", on_fail, move || {
                    let result = ctx.mint();
                    let _ = tx.send(Msg::Minted { attempt, result });
                });
            }
            ConnAction::Connect {
                attempt,
                ticket_path,
            } => {
                self.connecting = Some(attempt);
                if self.enrolling.is_some_and(|e| e != attempt) {
                    // The earlier enrollment may still be approved; its
                    // result decides this attempt (see `linked`).
                    self.deferred = Some((attempt, ticket_path));
                } else {
                    self.spawn_connect(attempt, ticket_path);
                }
            }
            ConnAction::ScheduleTick { at_ms } => self.next_tick = Some(at_ms),
            ConnAction::ShowStatus(text) => self.shown = Some(text),
            ConnAction::Drop {
                attempt: Some(attempt),
            } => {
                if self.connecting == Some(attempt) {
                    self.connecting = None;
                }
                if self.deferred.as_ref().is_some_and(|(d, _)| *d == attempt) {
                    self.deferred = None;
                }
                if self.live.as_ref().is_some_and(|(live, _)| *live == attempt) {
                    self.drop_live();
                }
            }
            ConnAction::Drop { attempt: None } => {
                self.connecting = None;
                self.deferred = None;
                self.drop_live();
                if *self.state.phase() == ConnPhase::Ended {
                    self.stop(Stop::Final);
                }
            }
        }
    }

    fn spawn_connect(&mut self, attempt: u32, ticket_path: String) {
        let use_invite = self.ctx.uses_invite();
        if use_invite {
            self.enrolling = Some(attempt);
        }
        let (ctx, tx) = (self.ctx.clone(), self.tx.clone());
        let on_fail = Msg::Linked {
            attempt,
            result: Err(LinkFail::Other(spawn_failed("connect"))),
        };
        spawn_job(&self.tx, "connect", on_fail, move || {
            let result = ctx.connect(PathBuf::from(ticket_path), use_invite);
            let _ = tx.send(Msg::Linked { attempt, result });
        });
    }

    fn live_attempt(&self) -> Option<u32> {
        self.live.as_ref().map(|(attempt, _)| *attempt)
    }

    /// Forget the client and every view: input is refused from now on.
    fn drop_live(&mut self) {
        self.live = None;
        for pane in self.panes.values_mut() {
            pane.link.clear_view();
            pane.view_gen = None;
            pane.attaching = false;
            pane.retry_at = None;
        }
    }

    fn lose(&mut self, attempt: u32, reason: String) {
        if self.live_attempt() == Some(attempt) {
            self.drop_live();
        }
        self.feed(ConnEvent::Disconnected { attempt, reason });
    }

    fn handle(&mut self, msg: Msg) {
        match msg {
            Msg::OpenPane {
                pane,
                want,
                link,
                sink,
            } => {
                let terminal_id = match &want {
                    Want::Terminal(id) => Some(id.clone()),
                    _ => None,
                };
                self.panes.insert(
                    pane,
                    Pane {
                        link,
                        sink,
                        want,
                        announced: terminal_id.clone(),
                        terminal_id,
                        attaching: false,
                        view_gen: None,
                        attach_failures: 0,
                        retry_at: None,
                    },
                );
                if *self.state.phase() == ConnPhase::Disconnected {
                    self.feed(ConnEvent::Open);
                } else if self.live.is_some() {
                    self.attach(pane);
                }
                if let Some(p) = self.panes.get(&pane) {
                    (p.sink)(PaneEvent::Status);
                }
            }
            Msg::ClosePane { pane } => {
                if let Some(p) = self.panes.remove(&pane) {
                    p.link.clear_view();
                }
                if self.panes.is_empty() {
                    self.stop(Stop::Idle);
                    self.feed(ConnEvent::Close);
                } else if self.attach_error.is_some()
                    && self.panes.values().all(|p| p.attach_failures == 0)
                {
                    // The failing pane is gone: its error must not stay on
                    // the panes that work.
                    self.attach_error = None;
                    self.publish();
                }
            }
            Msg::MachineOnline(online) => self.feed(if online {
                ConnEvent::MachineOnline
            } else {
                ConnEvent::MachineOffline
            }),
            Msg::Close => {
                self.stop = Some(Stop::Final);
                self.feed(ConnEvent::Close);
            }
            Msg::Minted { attempt, result } => {
                self.feed(ConnEvent::TicketMinted { attempt, result })
            }
            Msg::Linked { attempt, result } => self.linked(attempt, result),
            Msg::Attached {
                attempt,
                pane,
                result,
            } => self.attached(attempt, pane, result),
            Msg::ViewEnd {
                attempt,
                pane,
                view_gen,
                end,
            } => self.view_end(attempt, pane, view_gen, end),
            Msg::EndChecked {
                attempt,
                pane,
                view_gen,
                check,
            } => {
                if self.live_attempt() != Some(attempt)
                    || self.panes.get(&pane).and_then(|p| p.view_gen) != Some(view_gen)
                {
                    return;
                }
                match check {
                    EndCheck::Lost(reason) => self.lose(attempt, reason),
                    EndCheck::StillThere => {
                        if let Some(p) = self.panes.get_mut(&pane) {
                            p.link.clear_view();
                            p.view_gen = None;
                        }
                        self.attach(pane);
                    }
                    EndCheck::Gone => self.end_pane(pane),
                }
            }
        }
    }

    fn linked(&mut self, attempt: u32, result: Result<Linked, LinkFail>) {
        if self.enrolling == Some(attempt) {
            self.enrolling = None;
            if self.connecting != Some(attempt) {
                // The enrollment outlived its attempt (offline meanwhile).
                // A connect held back for it takes its result, unless it
                // simply failed: then that connect runs now.
                let Some((deferred, ticket_path)) = self.deferred.take() else {
                    return;
                };
                match result {
                    Err(LinkFail::Other(_)) => self.spawn_connect(deferred, ticket_path),
                    result => self.linked(deferred, result),
                }
                return;
            }
        }
        if self.connecting != Some(attempt) || self.stop.is_some() {
            return; // abandoned attempt: its client (if any) drops here
        }
        self.connecting = None;
        match result {
            Ok(linked) => {
                if linked.save_error.is_some() {
                    self.save_error = linked.save_error;
                }
                self.feed(ConnEvent::Connected { attempt });
                if *self.state.phase() == ConnPhase::Connected {
                    self.live = Some((attempt, linked.host));
                    let panes: Vec<u64> = self.panes.keys().copied().collect();
                    for pane in panes {
                        self.attach(pane);
                    }
                }
            }
            Err(LinkFail::Fingerprint { expected, got }) => {
                self.error = Some(SessionError::FingerprintMismatch { expected, got });
                self.feed(ConnEvent::Close);
            }
            Err(LinkFail::NeedsPairing(reason)) => {
                self.error = Some(SessionError::NeedsPairing(reason));
                self.feed(ConnEvent::Close);
            }
            Err(LinkFail::Other(reason)) => self.feed(ConnEvent::Disconnected { attempt, reason }),
        }
    }

    fn attach(&mut self, pane: u64) {
        let Some((attempt, host)) = self.live.clone() else {
            return;
        };
        let claimed: Vec<String> = self
            .panes
            .iter()
            .filter(|(id, _)| **id != pane)
            .filter_map(|(_, p)| p.terminal_id.clone())
            .collect();
        let Some(p) = self.panes.get_mut(&pane) else {
            return;
        };
        if p.attaching {
            return;
        }
        p.attaching = true;
        p.retry_at = None;
        let want = p.want.clone();
        let size = p.link.size();
        let tx = self.tx.clone();
        let on_fail = Msg::Attached {
            attempt,
            pane,
            result: Err(AttachFail {
                reason: spawn_failed("attach"),
                created: None,
            }),
        };
        spawn_job(&self.tx, "attach", on_fail, move || {
            let result = resolve_and_attach(&*host, &want, &claimed, size)
                .map(|(view, events, id)| (view, events, id, size));
            let _ = tx.send(Msg::Attached {
                attempt,
                pane,
                result,
            });
        });
    }

    fn attached(&mut self, attempt: u32, pane: u64, result: Result<Attached, AttachFail>) {
        let Some((live, host)) = self.live.clone() else {
            return; // a view of a dropped client: dropping it here closes it
        };
        if live != attempt {
            return;
        }
        let now = self.now_ms();
        let Some(p) = self.panes.get_mut(&pane) else {
            return;
        };
        p.attaching = false;
        let (view, events, terminal_id, size) = match result {
            Ok(attached) => attached,
            Err(fail) if host.closed() => return self.lose(attempt, fail.reason),
            Err(fail) => {
                // The connection is fine; only this pane's attach failed.
                // Retry it on its own backoff, never reconnect for it, and
                // never open a second terminal on the Mac for it.
                if let Some(created) = fail.created {
                    p.terminal_id = Some(created.clone());
                    p.want = Want::Terminal(created);
                }
                p.attach_failures = p.attach_failures.saturating_add(1);
                p.retry_at = Some(now + backoff_ms(p.attach_failures));
                self.attach_error = Some(fail.reason);
                self.publish();
                return;
            }
        };
        p.attach_failures = 0;
        // Compared with what the UI was told, not with `terminal_id`: a
        // failed attach may have recorded a created terminal the UI has
        // never heard of.
        if p.announced.as_deref() != Some(terminal_id.as_str())
            && (p.sink)(PaneEvent::Retargeted {
                terminal_id: terminal_id.clone(),
            })
        {
            p.announced = Some(terminal_id.clone());
        }
        p.terminal_id = Some(terminal_id.clone());
        p.want = Want::Terminal(terminal_id);
        let view_gen = p.link.install(view, size);
        p.view_gen = Some(view_gen);
        let (link, sink, tx) = (p.link.clone(), p.sink.clone(), self.tx.clone());
        if self.panes.values().all(|p| p.attach_failures == 0) {
            self.attach_error = None;
        }
        let on_fail = Msg::ViewEnd {
            attempt,
            pane,
            view_gen,
            end: PumpEnd::Disconnected(spawn_failed("pump")),
        };
        spawn_job(&self.tx, "pump", on_fail, move || {
            let end = pump(&events, &link, view_gen, &sink);
            let _ = tx.send(Msg::ViewEnd {
                attempt,
                pane,
                view_gen,
                end,
            });
        });
        self.publish();
    }

    fn view_end(&mut self, attempt: u32, pane: u64, view_gen: u64, end: PumpEnd) {
        let Some((live, host)) = self.live.clone() else {
            return;
        };
        if live != attempt || self.panes.get(&pane).and_then(|p| p.view_gen) != Some(view_gen) {
            return;
        }
        match end {
            PumpEnd::Stale => {}
            PumpEnd::Disconnected(reason) => self.lose(attempt, reason),
            PumpEnd::HungUp => {
                if host.closed() {
                    self.lose(attempt, "the connection to the Mac closed".into());
                } else {
                    // The pane's UI is gone.
                    self.handle(Msg::ClosePane { pane });
                }
            }
            PumpEnd::Ended { saw_snapshot } => {
                if host.closed() {
                    return self.lose(attempt, "the Mac closed the connection".into());
                }
                let terminal_id = self.panes.get(&pane).and_then(|p| p.terminal_id.clone());
                let tx = self.tx.clone();
                let on_fail = Msg::EndChecked {
                    attempt,
                    pane,
                    view_gen,
                    check: EndCheck::Lost(spawn_failed("end-check")),
                };
                spawn_job(&self.tx, "end-check", on_fail, move || {
                    let check = match host.list_terminals() {
                        Err(error) => EndCheck::Lost(format!("{error:#}")),
                        Ok(_) if host.closed() => {
                            EndCheck::Lost("the Mac closed the connection".into())
                        }
                        Ok(list) => {
                            let listed = terminal_id
                                .as_ref()
                                .is_some_and(|id| list.iter().any(|t| &t.id == id));
                            // Listed but this view never showed a screen:
                            // do not loop reattaching a terminal that keeps
                            // detaching us.
                            if listed && saw_snapshot {
                                EndCheck::StillThere
                            } else {
                                EndCheck::Gone
                            }
                        }
                    };
                    let _ = tx.send(Msg::EndChecked {
                        attempt,
                        pane,
                        view_gen,
                        check,
                    });
                });
            }
        }
    }

    /// The remote terminal of `pane` really ended.
    fn end_pane(&mut self, pane: u64) {
        let Some(p) = self.panes.remove(&pane) else {
            return;
        };
        p.link.mark_ended();
        (p.sink)(PaneEvent::Ended);
        if self.panes.is_empty() {
            self.feed(ConnEvent::RemoteEnded);
        }
    }
}

/// Pick the pane's terminal on this connection and attach to it.
fn resolve_and_attach(
    host: &dyn Host,
    want: &Want,
    claimed: &[String],
    (cols, rows): (u16, u16),
) -> Result<View, AttachFail> {
    let fail = |error: anyhow::Error, created: Option<String>| AttachFail {
        reason: format!("{error:#}"),
        created,
    };
    let mut created = None;
    let create = |created: &mut Option<String>| -> Result<String, AttachFail> {
        let id = host.create_terminal().map_err(|e| fail(e, None))?.id;
        *created = Some(id.clone());
        Ok(id)
    };
    let id = match want {
        Want::New => create(&mut created)?,
        Want::First => match host
            .list_terminals()
            .map_err(|e| fail(e, None))?
            .into_iter()
            .next()
        {
            Some(terminal) => terminal.id,
            None => create(&mut created)?,
        },
        Want::Terminal(id) => {
            let list = host.list_terminals().map_err(|e| fail(e, None))?;
            if list.iter().any(|t| &t.id == id) {
                id.clone()
            } else {
                // Gone while we were away (the Mac restarted): show a free
                // terminal, or a new one, rather than an empty pane.
                match list.into_iter().find(|t| !claimed.contains(&t.id)) {
                    Some(terminal) => terminal.id,
                    None => create(&mut created)?,
                }
            }
        }
    };
    let (view, events) = host
        .attach(&id, cols, rows)
        .map_err(|e| fail(e, created.clone()))?;
    Ok((view, events, id))
}

impl Ctx {
    fn mint(&self) -> Result<TicketFile, CoreErr> {
        let ticket = mint_connect_ticket(&*self.core, &self.machine_id, &self.ticket_name)?;
        *lock(&self.last_ticket) = Some(PathBuf::from(&ticket.path));
        Ok(ticket)
    }

    /// The next connect enrolls with the invitation (not enrolled yet by the
    /// link or by the client's own record, and an invitation exists).
    fn uses_invite(&self) -> bool {
        let record = lock(&self.record).clone();
        record.invite_path.is_some()
            && !record.enrolled
            && !self
                .connector
                .is_enrolled(&self.state_dir, &record.daemon_fingerprint)
    }

    fn connect(&self, first_ticket: PathBuf, use_invite: bool) -> Result<Linked, LinkFail> {
        let record = lock(&self.record).clone();
        let invite_path = if use_invite {
            record.invite_path.as_ref().map(PathBuf::from)
        } else {
            None
        };
        let first = Mutex::new(Some(first_ticket));
        let ctx = self.clone();
        let ticket = Arc::new(move || -> Result<PathBuf> {
            if let Some(path) = lock(&first).take() {
                return Ok(path);
            }
            // Every later call (relay reconnects) gets a fresh ticket.
            let minted = ctx.mint().map_err(|error| anyhow!("{error}"))?;
            Ok(PathBuf::from(minted.path))
        });
        let connected = self.connector.connect(ConnectConfig {
            state_dir: self.state_dir.clone(),
            device_name: self.device_name.clone(),
            relay_route: record.relay_route.clone(),
            relay_slot: record.relay_slot.clone(),
            invite_path,
            ticket,
        });
        let host = match connected {
            Ok(host) => host,
            Err(error) => {
                let reason = format!("{error:#}");
                if reason.contains("request access again") {
                    // Expired or consumed: the invitation is of no use now.
                    self.forget_invite(&record, false);
                    return Err(LinkFail::NeedsPairing(reason));
                }
                return Err(LinkFail::Other(reason));
            }
        };
        let got = host.daemon_fingerprint();
        if got != record.daemon_fingerprint {
            drop(host);
            return Err(LinkFail::Fingerprint {
                expected: record.daemon_fingerprint,
                got,
            });
        }
        let save_error = if !record.enrolled || record.invite_path.is_some() {
            self.forget_invite(&record, true)
        } else {
            None
        };
        Ok(Linked { host, save_error })
    }

    /// Delete the invitation (PSK + embedded relay ticket), only from
    /// shellx-core's tickets dir and only an `invite-*.uri` file (the path
    /// comes from links.json), and save the link without it; with
    /// `enrolled`, also mark it enrolled. Returns a problem, if any.
    fn forget_invite(&self, record: &LinkRecord, enrolled: bool) -> Option<String> {
        let mut problems = Vec::new();
        if let Some(path) = &record.invite_path {
            let path = Path::new(path);
            if !invite_path_ok(&self.invite_dir, path) {
                problems.push(format!(
                    "not deleting {} (not an invitation in {})",
                    path.display(),
                    self.invite_dir.display()
                ));
            } else {
                match std::fs::remove_file(path) {
                    Ok(()) => {}
                    Err(error) if error.kind() == std::io::ErrorKind::NotFound => {}
                    Err(error) => {
                        problems.push(format!("could not delete the invitation: {error}"))
                    }
                }
            }
        }
        let mut updated = record.clone();
        updated.enrolled |= enrolled;
        updated.invite_path = None;
        *lock(&self.record) = updated.clone();
        if let Some(store) = &self.links {
            let saved = store.load().and_then(|mut links| {
                let mut link = links
                    .get(&updated.machine_id)
                    .cloned()
                    .unwrap_or_else(|| updated.clone());
                link.enrolled |= enrolled;
                link.invite_path = None;
                links.upsert(link);
                store.save(&links)
            });
            if let Err(error) = saved {
                problems.push(format!("could not save links.json: {error}"));
            }
        }
        (!problems.is_empty()).then(|| problems.join("; "))
    }
}

/// `path` is an `invite-*.uri` file directly inside `invite_dir` (compared
/// after resolving links; a missing dir or file never matches).
fn invite_path_ok(invite_dir: &Path, path: &Path) -> bool {
    let name_ok = path
        .file_name()
        .and_then(|n| n.to_str())
        .is_some_and(|n| n.starts_with("invite-") && n.ends_with(".uri") && n.len() > 11);
    let (Some(parent), Ok(dir)) = (path.parent(), invite_dir.canonicalize()) else {
        return false;
    };
    name_ok && parent.canonicalize().is_ok_and(|p| p == dir)
}

// ------------------------------------------------------------ fakes

/// In-memory `Connector` / `Host` / view for tests and `--smoke`.
pub mod fake {
    use std::collections::VecDeque;
    use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
    use std::sync::mpsc::{Receiver, Sender};
    use std::sync::{Arc, Mutex};

    use anyhow::{Result, anyhow, bail};
    use shellx_remote::{AttachEvent, ConnectConfig, RemoteTerminal};

    use super::{Connector, Host, lock};
    use crate::remote_link::ViewInput;

    #[derive(Default)]
    pub struct FakeView {
        pub writes: Mutex<Vec<Vec<u8>>>,
        pub resizes: Mutex<Vec<(u16, u16)>>,
    }

    impl FakeView {
        pub fn writes(&self) -> Vec<Vec<u8>> {
            lock(&self.writes).clone()
        }
    }

    impl ViewInput for FakeView {
        fn write(&self, bytes: &[u8]) -> Result<()> {
            lock(&self.writes).push(bytes.to_vec());
            Ok(())
        }
        fn resize(&self, cols: u16, rows: u16) -> Result<()> {
            lock(&self.resizes).push((cols, rows));
            Ok(())
        }
    }

    pub struct FakeAttach {
        pub terminal_id: String,
        pub view: Arc<FakeView>,
        pub events: Sender<AttachEvent>,
    }

    /// A Mac with terminals "1", "2", ...; every attach replays
    /// `Resized` + `Snapshot` like the real daemon.
    pub struct FakeHost {
        pub fingerprint: String,
        pub terminals: Mutex<Vec<RemoteTerminal>>,
        pub attaches: Mutex<Vec<FakeAttach>>,
        pub closed: AtomicBool,
        pub fail_list: AtomicBool,
        /// Every attach fails while the connection stays open.
        pub fail_attach: AtomicBool,
        /// The next n attaches fail (then they work again).
        pub fail_next_attaches: AtomicU64,
        pub creates: AtomicU64,
        pub attach_calls: AtomicU64,
        next_id: AtomicU64,
    }

    impl FakeHost {
        pub fn new(fingerprint: &str, terminals: usize) -> FakeHost {
            let host = FakeHost {
                fingerprint: fingerprint.into(),
                terminals: Mutex::new(Vec::new()),
                attaches: Mutex::new(Vec::new()),
                closed: AtomicBool::new(false),
                fail_list: AtomicBool::new(false),
                fail_attach: AtomicBool::new(false),
                fail_next_attaches: AtomicU64::new(0),
                creates: AtomicU64::new(0),
                attach_calls: AtomicU64::new(0),
                next_id: AtomicU64::new(1),
            };
            for _ in 0..terminals {
                host.add_terminal();
            }
            host
        }

        fn add_terminal(&self) -> RemoteTerminal {
            let id = self.next_id.fetch_add(1, Ordering::Relaxed).to_string();
            let terminal = RemoteTerminal {
                id: id.clone(),
                title: format!("t{id}"),
                cols: 80,
                rows: 24,
            };
            lock(&self.terminals).push(terminal.clone());
            terminal
        }

        pub fn attach_count(&self) -> usize {
            lock(&self.attaches).len()
        }

        pub fn view(&self, i: usize) -> Option<Arc<FakeView>> {
            lock(&self.attaches).get(i).map(|a| a.view.clone())
        }

        pub fn attached_ids(&self) -> Vec<String> {
            lock(&self.attaches)
                .iter()
                .map(|a| a.terminal_id.clone())
                .collect()
        }

        /// Send an event to the i-th attached view.
        pub fn emit(&self, i: usize, event: AttachEvent) {
            if let Some(a) = lock(&self.attaches).get(i) {
                let _ = a.events.send(event);
            }
        }

        /// The relay/daemon went away: every view gets `Disconnected`.
        pub fn disconnect(&self, reason: &str) {
            self.closed.store(true, Ordering::Release);
            for a in lock(&self.attaches).iter() {
                let _ = a.events.send(AttachEvent::Disconnected(reason.into()));
            }
        }

        /// The surface exited: drop it from the list, then detach its views.
        pub fn end_terminal(&self, id: &str) {
            lock(&self.terminals).retain(|t| t.id != id);
            for a in lock(&self.attaches).iter().filter(|a| a.terminal_id == id) {
                let _ = a.events.send(AttachEvent::Ended);
            }
        }
    }

    impl Host for FakeHost {
        fn daemon_fingerprint(&self) -> String {
            self.fingerprint.clone()
        }
        fn list_terminals(&self) -> Result<Vec<RemoteTerminal>> {
            if self.closed.load(Ordering::Acquire) || self.fail_list.load(Ordering::Acquire) {
                bail!("the connection to the Mac is closed");
            }
            Ok(lock(&self.terminals).clone())
        }
        fn create_terminal(&self) -> Result<RemoteTerminal> {
            if self.closed.load(Ordering::Acquire) {
                bail!("the connection to the Mac is closed");
            }
            self.creates.fetch_add(1, Ordering::AcqRel);
            Ok(self.add_terminal())
        }
        fn attach(
            &self,
            terminal_id: &str,
            cols: u16,
            rows: u16,
        ) -> Result<(Arc<dyn ViewInput>, Receiver<AttachEvent>)> {
            if self.closed.load(Ordering::Acquire) {
                bail!("the connection to the Mac is closed");
            }
            self.attach_calls.fetch_add(1, Ordering::AcqRel);
            let fail_once = self
                .fail_next_attaches
                .fetch_update(Ordering::AcqRel, Ordering::Acquire, |n| n.checked_sub(1))
                .is_ok();
            if fail_once || self.fail_attach.load(Ordering::Acquire) {
                bail!("the Mac refused the attach");
            }
            if !lock(&self.terminals).iter().any(|t| t.id == terminal_id) {
                bail!("no terminal {terminal_id}");
            }
            let (tx, rx) = std::sync::mpsc::channel();
            let _ = tx.send(AttachEvent::Resized { cols, rows });
            let _ = tx.send(AttachEvent::Snapshot(
                format!("snapshot {terminal_id}\r\n").into_bytes(),
            ));
            let view = Arc::new(FakeView::default());
            lock(&self.attaches).push(FakeAttach {
                terminal_id: terminal_id.into(),
                view: view.clone(),
                events: tx,
            });
            Ok((view, rx))
        }
        fn closed(&self) -> bool {
            self.closed.load(Ordering::Acquire)
        }
    }

    /// What one `connect` call was given.
    #[derive(Clone, Debug)]
    pub struct SeenConnect {
        pub invite_path: Option<std::path::PathBuf>,
        pub relay_route: String,
        pub relay_slot: String,
        pub device_name: String,
        /// Ticket paths returned by the callback (called `ticket_calls` times).
        pub tickets: Vec<std::path::PathBuf>,
    }

    /// Hands out scripted hosts (`push_host` / `push_error`); when the
    /// script is empty every connect gets a new host with `fingerprint`.
    pub struct FakeConnector {
        pub fingerprint: String,
        pub terminals: usize,
        pub enrolled: AtomicBool,
        /// How many times each connect calls the ticket callback (the real
        /// client calls it again on relay reconnects).
        pub ticket_calls: usize,
        script: Mutex<VecDeque<Result<Arc<FakeHost>, String>>>,
        pub seen: Mutex<Vec<SeenConnect>>,
        pub hosts: Mutex<Vec<Arc<FakeHost>>>,
        /// When set, an enrolling connect (with an invitation) waits here
        /// until the test sends `()` (the Mac owner approving).
        pub approval: Mutex<Option<Receiver<()>>>,
    }

    impl FakeConnector {
        pub fn new(fingerprint: &str, terminals: usize) -> FakeConnector {
            FakeConnector {
                fingerprint: fingerprint.into(),
                terminals,
                enrolled: AtomicBool::new(false),
                ticket_calls: 1,
                script: Mutex::new(VecDeque::new()),
                seen: Mutex::new(Vec::new()),
                hosts: Mutex::new(Vec::new()),
                approval: Mutex::new(None),
            }
        }

        pub fn push_host(&self, host: Arc<FakeHost>) {
            lock(&self.script).push_back(Ok(host));
        }

        pub fn push_error(&self, error: &str) {
            lock(&self.script).push_back(Err(error.into()));
        }

        pub fn host(&self, i: usize) -> Option<Arc<FakeHost>> {
            lock(&self.hosts).get(i).cloned()
        }

        pub fn host_count(&self) -> usize {
            lock(&self.hosts).len()
        }

        pub fn seen(&self) -> Vec<SeenConnect> {
            lock(&self.seen).clone()
        }
    }

    impl Connector for FakeConnector {
        fn is_enrolled(&self, _state_dir: &std::path::Path, _fingerprint: &str) -> bool {
            self.enrolled.load(Ordering::Acquire)
        }

        fn connect(&self, cfg: ConnectConfig) -> Result<Arc<dyn Host>> {
            let mut tickets = Vec::new();
            for _ in 0..self.ticket_calls {
                let path = (cfg.ticket)()?;
                // shellx-remote reads the ticket once, then deletes it.
                let _ = std::fs::remove_file(&path);
                tickets.push(path);
            }
            lock(&self.seen).push(SeenConnect {
                invite_path: cfg.invite_path.clone(),
                relay_route: cfg.relay_route.clone(),
                relay_slot: cfg.relay_slot.clone(),
                device_name: cfg.device_name.clone(),
                tickets,
            });
            if cfg.invite_path.is_some() {
                let approval = lock(&self.approval).take();
                if let Some(approval) = approval {
                    let _ = approval.recv();
                }
            }
            let next = lock(&self.script).pop_front();
            let host = match next {
                Some(Ok(host)) => host,
                Some(Err(error)) => return Err(anyhow!(error)),
                None => Arc::new(FakeHost::new(&self.fingerprint, self.terminals)),
            };
            if cfg.invite_path.is_some() {
                self.enrolled.store(true, Ordering::Release);
            }
            lock(&self.hosts).push(host.clone());
            Ok(host)
        }
    }
}

// ------------------------------------------------------------ smoke

/// `--smoke` (and Mac test): drive a `RemoteSession` against the fake Mac:
/// enroll (invite deleted, link saved enrolled), attach, mirror the
/// snapshot, one UTF-8 write for "tiếng Việt", refused input while
/// reconnecting, reconnect with a freshly minted ticket.
pub fn smoke() -> Result<String> {
    use crate::remote_link::{Applied, RemoteMirror};
    use fake::FakeConnector;
    use shellx_model::links::Links;

    static RUN: AtomicU64 = AtomicU64::new(0);
    let dir = std::env::temp_dir().join(format!(
        "shellx-smoke-remote-{}-{}",
        std::process::id(),
        RUN.fetch_add(1, Ordering::Relaxed)
    ));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir)?;
    let result = (|| -> Result<String> {
        let invite = dir.join("invite-m1.uri");
        std::fs::write(&invite, "cmux://enroll/secret")?;
        let tickets = dir.join("tickets");
        std::fs::create_dir_all(&tickets)?;
        let record = LinkRecord {
            machine_id: "m1".into(),
            machine_name: "Mac".into(),
            relay_route: "wss://relay.example/v2/relay".into(),
            relay_slot: "slot-1".into(),
            invite_path: Some(invite.to_string_lossy().into_owned()),
            daemon_fingerprint: "fp-1".into(),
            enrolled: false,
        };
        let store = LinksStore::new(dir.join("links.json"));
        let mut links = Links::default();
        links.upsert(record.clone());
        store.save(&links)?;
        let ticket_path = tickets.join(ticket_file_name("m1"));
        let core = Arc::new(MintingCore::new(ticket_path.clone()));
        let connector = Arc::new(FakeConnector::new("fp-1", 1));
        let session = RemoteSession::start(SessionConfig {
            record,
            core: core.clone(),
            connector: connector.clone(),
            state_dir: dir.clone(),
            invite_dir: dir.clone(),
            device_name: "PC test".into(),
            links: Some(LinksStore::new(dir.join("links.json"))),
            time_scale: 50,
        })?;
        let (tx, rx) = mpsc::channel::<PaneEvent>();
        let sink: PaneSink = Arc::new(move |event| tx.send(event).is_ok());
        let pane = session.open_pane(Want::First, 100, 30, sink)?;
        let mut mirror = RemoteMirror::new(pane.link.clone())?;
        let drain = |mirror: &mut RemoteMirror| -> Result<Vec<Applied>> {
            let mut out = Vec::new();
            while let Ok(event) = rx.try_recv() {
                out.push(mirror.apply(event)?);
            }
            Ok(out)
        };
        let wait = |what: &str, mut done: Box<dyn FnMut() -> bool + '_>| -> Result<()> {
            let deadline = Instant::now() + Duration::from_secs(10);
            while !done() {
                if Instant::now() > deadline {
                    bail!("remote smoke: timed out waiting for {what}");
                }
                std::thread::sleep(Duration::from_millis(5));
            }
            Ok(())
        };
        wait("the first attach", Box::new(|| pane.link.accepts_input()))?;
        let seen = connector.seen();
        if seen.len() != 1 || seen[0].invite_path.as_deref() != Some(invite.as_path()) {
            bail!("first connect did not enroll with the invitation: {seen:?}");
        }
        if invite.exists() {
            bail!("the invitation file was not deleted after enrollment");
        }
        let saved = LinksStore::new(dir.join("links.json")).load()?;
        if !saved
            .get("m1")
            .is_some_and(|l| l.enrolled && l.invite_path.is_none())
        {
            bail!("links.json not saved enrolled: {saved:?}");
        }
        let mut applied = Vec::new();
        let deadline = Instant::now() + Duration::from_secs(10);
        while !mirror
            .core()
            .text_lines()?
            .iter()
            .any(|l| l.starts_with("snapshot 1"))
        {
            if Instant::now() > deadline {
                bail!("the snapshot did not reach the mirror: {applied:?}");
            }
            std::thread::sleep(Duration::from_millis(5));
            applied.extend(drain(&mut mirror)?);
        }
        let reset = applied.iter().position(|a| *a == Applied::Reset);
        let fed = applied
            .iter()
            .position(|a| matches!(a, Applied::Fed { .. }));
        if reset.is_none() || reset > fed {
            bail!("the snapshot came without a reset first: {applied:?}");
        }
        let host = connector.host(0).ok_or_else(|| anyhow!("no host"))?;
        if !mirror.send_text("tiếng Việt") {
            bail!("input refused while connected");
        }
        let want = "tiếng Việt".as_bytes().to_vec();
        let view = host.view(0).ok_or_else(|| anyhow!("no view"))?;
        if view.writes() != vec![want.clone()] {
            bail!("IME commit was not one UTF-8 write: {:?}", view.writes());
        }
        host.disconnect("relay restarted");
        wait("Reconnecting", Box::new(|| !pane.link.accepts_input()))?;
        if mirror.send_text("lost") {
            bail!("input accepted while reconnecting");
        }
        let mints_before = core.mints();
        wait(
            "the reconnect",
            Box::new(|| connector.host_count() == 2 && pane.link.accepts_input()),
        )?;
        if core.mints() <= mints_before {
            bail!("the reconnect did not mint a fresh ticket");
        }
        let seen = connector.seen();
        if seen[1].invite_path.is_some() {
            bail!("an enrolled reconnect used the invitation");
        }
        if !mirror.send_text("ok") {
            bail!("input refused after the reconnect");
        }
        let new_view = connector
            .host(1)
            .and_then(|h| h.view(0))
            .ok_or_else(|| anyhow!("no view after reconnect"))?;
        if new_view.writes() != vec![b"ok".to_vec()] || view.writes() != vec![want] {
            bail!("input while reconnecting was queued or lost after the reconnect");
        }
        let status = session.status();
        if status.phase != ConnPhase::Connected || status.error.is_some() {
            bail!("unexpected status after the reconnect: {status:?}");
        }
        session.close();
        wait(
            "the session to finish",
            Box::new(|| session.status().finished),
        )?;
        Ok(format!(
            "enrolled (invite deleted), \"tiếng Việt\" = 1 write, input refused while reconnecting, reconnected with a fresh ticket ({} mints)",
            core.mints()
        ))
    })();
    let _ = std::fs::remove_dir_all(&dir);
    result
}

/// `tickets.mint` for the smoke/tests: writes a ticket file at `path` and
/// counts the mints (no network).
pub struct MintingCore {
    path: PathBuf,
    mints: AtomicU64,
    /// `write_to` names seen, in order.
    pub names: Mutex<Vec<String>>,
}

impl MintingCore {
    pub fn new(path: PathBuf) -> MintingCore {
        MintingCore {
            path,
            mints: AtomicU64::new(0),
            names: Mutex::new(Vec::new()),
        }
    }

    pub fn mints(&self) -> u64 {
        self.mints.load(Ordering::Acquire)
    }
}

impl CoreCall for MintingCore {
    fn call(&self, method: &str, params: serde_json::Value) -> Result<serde_json::Value, CoreErr> {
        if method != "tickets.mint" {
            return Err(CoreErr::new("unknown_method", method));
        }
        if params["permission"] != "connect" {
            return Err(CoreErr::new("invalid_params", "permission"));
        }
        lock(&self.names).push(params["write_to"].as_str().unwrap_or("").to_string());
        let n = self.mints.fetch_add(1, Ordering::AcqRel) + 1;
        std::fs::write(&self.path, format!("ticket-{n}"))
            .map_err(|e| CoreErr::new("io", &e.to_string()))?;
        Ok(serde_json::json!({
            "path": self.path.to_string_lossy(),
            "expires_at_unix": 4_000_000_000i64,
            "relay_url": "wss://relay.example/v2/relay",
        }))
    }
}

#[cfg(test)]
mod tests {
    use super::fake::{FakeConnector, FakeHost};
    use super::*;
    use crate::term_core::PtyLink;
    use shellx_model::links::Links;

    struct Rig {
        dir: PathBuf,
        session: RemoteSession,
        core: Arc<MintingCore>,
        connector: Arc<FakeConnector>,
        events: Receiver<PaneEvent>,
        sink: PaneSink,
        invite: PathBuf,
    }

    impl Drop for Rig {
        fn drop(&mut self) {
            let _ = std::fs::remove_dir_all(&self.dir);
        }
    }

    impl Rig {
        fn events(&self) -> Vec<PaneEvent> {
            self.events.try_iter().collect()
        }
    }

    fn record(dir: &Path, enrolled: bool) -> LinkRecord {
        LinkRecord {
            machine_id: "Mac/1".into(),
            machine_name: "Mac".into(),
            relay_route: "wss://relay.example/v2/relay".into(),
            relay_slot: "slot-1".into(),
            invite_path: (!enrolled)
                .then(|| dir.join("invite-mac-1.uri").to_string_lossy().into_owned()),
            daemon_fingerprint: "fp-1".into(),
            enrolled,
        }
    }

    fn rig_with(name: &str, connector: FakeConnector, enrolled: bool) -> Rig {
        rig_scaled(name, connector, enrolled, 100)
    }

    fn rig_scaled(name: &str, connector: FakeConnector, enrolled: bool, scale: u64) -> Rig {
        let dir = std::env::temp_dir().join(format!("shellx-rs-{name}-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        let invite = dir.join("invite-mac-1.uri");
        if !enrolled {
            std::fs::write(&invite, "cmux://enroll/x").unwrap();
        }
        let rec = record(&dir, enrolled);
        let store = LinksStore::new(dir.join("links.json"));
        let mut links = Links::default();
        links.upsert(rec.clone());
        store.save(&links).unwrap();
        let core = Arc::new(MintingCore::new(
            dir.join(ticket_file_name(&rec.machine_id)),
        ));
        let connector = Arc::new(connector);
        let session = RemoteSession::start(SessionConfig {
            record: rec,
            core: core.clone(),
            connector: connector.clone(),
            state_dir: dir.clone(),
            invite_dir: dir.clone(),
            device_name: "PC test".into(),
            links: Some(LinksStore::new(dir.join("links.json"))),
            time_scale: scale,
        })
        .unwrap();
        let (tx, events) = mpsc::channel();
        let sink: PaneSink = Arc::new(move |event| tx.send(event).is_ok());
        Rig {
            dir,
            session,
            core,
            connector,
            events,
            sink,
            invite,
        }
    }

    fn rig(name: &str) -> Rig {
        rig_with(name, FakeConnector::new("fp-1", 1), false)
    }

    fn wait(what: &str, mut done: impl FnMut() -> bool) {
        let deadline = Instant::now() + Duration::from_secs(10);
        while !done() {
            assert!(Instant::now() < deadline, "timed out waiting for {what}");
            std::thread::sleep(Duration::from_millis(2));
        }
    }

    #[test]
    fn smoke_drives_the_fake_mac() {
        let summary = smoke().unwrap();
        assert!(summary.contains("1 write"), "{summary}");
    }

    #[test]
    fn ticket_file_name_fits_core_rules() {
        assert_eq!(ticket_file_name("m1"), "connect-m1.ticket");
        assert_eq!(ticket_file_name("Mac/1"), "connect-mac-1.ticket");
        let long = ticket_file_name(&"Ab/C ".repeat(40));
        assert!(long.len() <= 64, "{long}");
        assert!(long.starts_with("connect-") && long.ends_with(".ticket"));
    }

    #[test]
    fn enrolls_once_then_connects_enrolled_with_fresh_tickets() {
        let mut connector = FakeConnector::new("fp-1", 1);
        connector.ticket_calls = 2; // a relay reconnect inside the client
        let r = rig_with("enroll", connector, false);
        let pane = r
            .session
            .open_pane(Want::First, 90, 20, r.sink.clone())
            .unwrap();
        wait("attach", || pane.link.accepts_input());
        let seen = r.connector.seen();
        assert_eq!(seen.len(), 1);
        assert_eq!(seen[0].invite_path.as_deref(), Some(r.invite.as_path()));
        assert_eq!(
            (seen[0].relay_route.as_str(), seen[0].relay_slot.as_str()),
            ("wss://relay.example/v2/relay", "slot-1")
        );
        assert_eq!(seen[0].device_name, "PC test");
        // the first callback call returns the minted ticket, the second mints again
        assert_eq!(r.core.mints(), 2);
        assert!(
            lock(&r.core.names)
                .iter()
                .all(|n| n == "connect-mac-1.ticket")
        );
        assert!(
            !r.invite.exists(),
            "invitation must be deleted after enrollment"
        );
        let saved = LinksStore::new(r.dir.join("links.json")).load().unwrap();
        let link = saved.get("Mac/1").unwrap();
        assert!(link.enrolled && link.invite_path.is_none());
        assert_eq!(
            r.connector.host(0).unwrap().attached_ids(),
            vec!["1".to_string()]
        );
        // attached at the pane's grid, the Mac's snapshot follows
        wait("snapshot", || {
            r.events()
                .contains(&PaneEvent::Snapshot(b"snapshot 1\r\n".to_vec()))
        });
        // reconnect: no invitation, a new mint
        let mints = r.core.mints();
        r.connector.host(0).unwrap().disconnect("relay restarted");
        wait("reconnect", || {
            r.connector.host_count() == 2 && pane.link.accepts_input()
        });
        assert!(r.connector.seen()[1].invite_path.is_none());
        assert!(r.core.mints() > mints);
    }

    #[test]
    fn falls_back_to_the_client_enrollment_record() {
        let connector = FakeConnector::new("fp-1", 1);
        connector.enrolled.store(true, Ordering::Release);
        let r = rig_with("fallback", connector, false);
        let pane = r
            .session
            .open_pane(Want::First, 80, 24, r.sink.clone())
            .unwrap();
        wait("attach", || pane.link.accepts_input());
        assert!(r.connector.seen()[0].invite_path.is_none());
        assert!(!r.invite.exists());
    }

    #[test]
    fn fingerprint_mismatch_never_attaches() {
        let r = rig_with("fp", FakeConnector::new("fp-OTHER", 1), false);
        let pane = r
            .session
            .open_pane(Want::First, 80, 24, r.sink.clone())
            .unwrap();
        wait("finish", || r.session.status().finished);
        let status = r.session.status();
        assert_eq!(
            status.error,
            Some(SessionError::FingerprintMismatch {
                expected: "fp-1".into(),
                got: "fp-OTHER".into()
            })
        );
        assert_eq!(r.connector.host(0).unwrap().attach_count(), 0);
        assert!(!pane.link.accepts_input());
        assert!(!pane.link.is_closed(), "the pane stays to show the error");
        let saved = LinksStore::new(r.dir.join("links.json")).load().unwrap();
        assert!(!saved.get("Mac/1").unwrap().enrolled);
        assert!(
            r.session
                .open_pane(Want::First, 80, 24, r.sink.clone())
                .is_err()
        );
    }

    #[test]
    fn needs_pairing_stops_retrying() {
        let connector = FakeConnector::new("fp-1", 1);
        connector.push_error("the invitation has expired; request access again");
        let r = rig_with("pairing", connector, false);
        let _pane = r
            .session
            .open_pane(Want::First, 80, 24, r.sink.clone())
            .unwrap();
        wait("finish", || r.session.status().finished);
        assert!(matches!(
            r.session.status().error,
            Some(SessionError::NeedsPairing(_))
        ));
        std::thread::sleep(Duration::from_millis(50));
        assert_eq!(r.connector.seen().len(), 1);
        // the expired invitation is deleted and dropped from the link
        assert!(!r.invite.exists());
        let saved = LinksStore::new(r.dir.join("links.json")).load().unwrap();
        let link = saved.get("Mac/1").unwrap();
        assert!(link.invite_path.is_none() && !link.enrolled);
    }

    #[test]
    fn attach_failure_backs_off_per_pane_without_reconnecting() {
        let connector = FakeConnector::new("fp-1", 0);
        let host = Arc::new(FakeHost::new("fp-1", 0)); // an empty Mac
        host.fail_attach.store(true, Ordering::Release);
        connector.push_host(host.clone());
        // backoff 1, 2, 4, 8 s -> 50, 100, 200, 400 ms
        let r = rig_scaled("attachfail", connector, true, 20);
        let pane = r
            .session
            .open_pane(Want::First, 80, 24, r.sink.clone())
            .unwrap();
        wait("first attach call", || {
            host.attach_calls.load(Ordering::Acquire) >= 1
        });
        std::thread::sleep(Duration::from_millis(600));
        let calls = host.attach_calls.load(Ordering::Acquire);
        // attempts at ~0, 50, 150, 350 ms (next at 750): growing delays,
        // not a 50 ms storm (that would be ~12)
        assert!((3..=5).contains(&calls), "{calls} attach calls");
        assert_eq!(
            r.connector.host_count(),
            1,
            "no reconnect for an attach error"
        );
        assert_eq!(r.core.mints(), 1);
        assert_eq!(
            host.creates.load(Ordering::Acquire),
            1,
            "one terminal created, reused"
        );
        let status = r.session.status();
        assert_eq!(status.phase, ConnPhase::Connected);
        assert!(status.attach_error.is_some());
        assert!(!pane.link.accepts_input());
        host.fail_attach.store(false, Ordering::Release);
        wait("attach", || pane.link.accepts_input());
        assert_eq!(host.attached_ids(), vec!["1".to_string()]);
        assert_eq!(host.creates.load(Ordering::Acquire), 1);
        wait("error cleared", || {
            r.session.status().attach_error.is_none()
        });
    }

    #[test]
    fn a_terminal_created_by_a_failed_attach_is_announced_once() {
        let connector = FakeConnector::new("fp-1", 1);
        let host = Arc::new(FakeHost::new("fp-1", 0)); // an empty Mac
        host.fail_next_attaches.store(1, Ordering::Release);
        connector.push_host(host.clone());
        let r = rig_scaled("announce", connector, true, 100);
        let pane = r
            .session
            .open_pane(Want::First, 80, 24, r.sink.clone())
            .unwrap();
        // create "1", its attach fails, the retry attaches "1"
        wait("attach", || pane.link.accepts_input());
        assert_eq!(host.attach_calls.load(Ordering::Acquire), 2);
        assert_eq!(host.creates.load(Ordering::Acquire), 1);
        assert_eq!(host.attached_ids(), vec!["1".to_string()]);
        // the reconnected Mac still lists "1": nothing new to announce
        host.disconnect("relay restarted");
        wait("reconnect", || {
            r.connector.host_count() == 2 && pane.link.accepts_input()
        });
        assert_eq!(r.connector.host(1).unwrap().attached_ids(), vec!["1"]);
        let retargeted: Vec<PaneEvent> = r
            .events()
            .into_iter()
            .filter(|e| matches!(e, PaneEvent::Retargeted { .. }))
            .collect();
        assert_eq!(
            retargeted,
            vec![PaneEvent::Retargeted {
                terminal_id: "1".into()
            }]
        );
    }

    #[test]
    fn closing_the_last_pane_and_opening_another_revives_the_session() {
        let r = rig_with("revive", FakeConnector::new("fp-1", 1), true);
        let mut pane = r
            .session
            .open_pane(Want::First, 80, 24, r.sink.clone())
            .unwrap();
        wait("attach", || pane.link.accepts_input());
        for round in 0..10 {
            r.session.close_pane(pane.id);
            match r.session.open_pane(Want::First, 80, 24, r.sink.clone()) {
                Ok(next) => {
                    pane = next;
                    wait("attach after reopen", || pane.link.accepts_input());
                    assert!(!r.session.status().finished, "round {round}");
                }
                Err(_) => {
                    // the worker finished first: the UI opens a new session
                    assert!(r.session.status().finished);
                    return;
                }
            }
        }
    }

    #[test]
    fn a_pane_opened_on_a_closed_session_is_answered() {
        let r = rig_with("late", FakeConnector::new("fp-1", 1), true);
        let pane = r
            .session
            .open_pane(Want::First, 80, 24, r.sink.clone())
            .unwrap();
        wait("attach", || pane.link.accepts_input());
        r.session.close();
        if let Ok(late) = r.session.open_pane(Want::First, 80, 24, r.sink.clone()) {
            wait("late pane ended", || late.link.is_closed());
        }
        wait("finish", || r.session.status().finished);
    }

    #[test]
    fn offline_during_approval_never_enrolls_twice() {
        let connector = FakeConnector::new("fp-1", 1);
        let (approve, approval) = mpsc::channel();
        *lock(&connector.approval) = Some(approval);
        let r = rig_with("enroll-once", connector, false);
        let pane = r
            .session
            .open_pane(Want::First, 80, 24, r.sink.clone())
            .unwrap();
        wait("enrolling connect", || r.connector.seen().len() == 1);
        r.session.set_machine_online(false);
        wait("Offline", || r.session.status().phase == ConnPhase::Offline);
        r.session.set_machine_online(true);
        wait("next attempt minted", || r.core.mints() == 2);
        std::thread::sleep(Duration::from_millis(50));
        assert_eq!(r.connector.seen().len(), 1, "a second enrollment started");
        approve.send(()).unwrap();
        wait("attach", || pane.link.accepts_input());
        assert_eq!(r.connector.seen().len(), 1);
        assert_eq!(r.connector.host_count(), 1);
        assert!(!r.invite.exists());
        assert_eq!(r.session.status().phase, ConnPhase::Connected);
    }

    /// Task 13b fix round 1: the last pane closes while the Mac owner has
    /// not approved yet; the session stays (not finished) and a pane opened
    /// later gets the enrolled host, with one invitation connect only.
    #[test]
    fn last_pane_closing_during_an_enrollment_keeps_the_session_for_the_next_pane() {
        let connector = FakeConnector::new("fp-1", 1);
        let (approve, approval) = mpsc::channel();
        *lock(&connector.approval) = Some(approval);
        let r = rig_with("park-enroll", connector, false);
        let first = r
            .session
            .open_pane(Want::First, 80, 24, r.sink.clone())
            .unwrap();
        wait("enrolling connect", || r.connector.seen().len() == 1);
        r.session.close_pane(first.id);
        std::thread::sleep(Duration::from_millis(100));
        assert!(
            !r.session.status().finished,
            "the session finished while its enrollment waits for approval"
        );
        let pane = r
            .session
            .open_pane(Want::First, 80, 24, r.sink.clone())
            .expect("a new pane is refused during the enrollment");
        std::thread::sleep(Duration::from_millis(50));
        assert_eq!(r.connector.seen().len(), 1, "a second enrollment started");
        approve.send(()).unwrap();
        wait("attach", || pane.link.accepts_input());
        let seen = r.connector.seen();
        assert_eq!(seen.len(), 1);
        assert!(seen[0].invite_path.is_some());
        assert_eq!(r.connector.host_count(), 1);
        assert!(!r.invite.exists());
        assert_eq!(r.session.status().phase, ConnPhase::Connected);
        assert!(!r.session.status().finished);
    }

    #[test]
    fn an_enrollment_ending_without_a_pane_finishes_idle_and_close_ends_it_early() {
        // approved with no pane waiting: the result lands, then the session
        // finishes (the next open starts a new one, already enrolled)
        let connector = FakeConnector::new("fp-1", 1);
        let (approve, approval) = mpsc::channel();
        *lock(&connector.approval) = Some(approval);
        let r = rig_with("park-ends", connector, false);
        let first = r
            .session
            .open_pane(Want::First, 80, 24, r.sink.clone())
            .unwrap();
        wait("enrolling connect", || r.connector.seen().len() == 1);
        r.session.close_pane(first.id);
        std::thread::sleep(Duration::from_millis(50));
        assert!(!r.session.status().finished);
        approve.send(()).unwrap();
        wait("finished after the enrollment", || {
            r.session.status().finished
        });
        assert!(!r.invite.exists());
        let saved = LinksStore::new(r.dir.join("links.json")).load().unwrap();
        assert!(saved.get("Mac/1").unwrap().enrolled);
        assert!(
            r.session
                .open_pane(Want::First, 80, 24, r.sink.clone())
                .is_err()
        );

        // sign-out (close) during the approval wait ends it at once
        let connector = FakeConnector::new("fp-1", 1);
        let (_approve, approval) = mpsc::channel::<()>();
        *lock(&connector.approval) = Some(approval);
        let r = rig_with("park-close", connector, false);
        let first = r
            .session
            .open_pane(Want::First, 80, 24, r.sink.clone())
            .unwrap();
        wait("enrolling connect", || r.connector.seen().len() == 1);
        r.session.close_pane(first.id);
        std::thread::sleep(Duration::from_millis(50));
        assert!(!r.session.status().finished);
        r.session.close();
        wait("finished after close", || r.session.status().finished);
    }

    #[test]
    fn closing_the_failing_pane_clears_the_attach_error() {
        let r = rig_with("attach-error-close", FakeConnector::new("fp-1", 1), true);
        let good = r
            .session
            .open_pane(Want::First, 80, 24, r.sink.clone())
            .unwrap();
        wait("first attach", || good.link.accepts_input());
        let host = r.connector.host(0).unwrap();
        host.fail_attach.store(true, Ordering::Release);
        let bad = r
            .session
            .open_pane(Want::New, 80, 24, r.sink.clone())
            .unwrap();
        wait("attach error", || r.session.status().attach_error.is_some());
        r.session.close_pane(bad.id);
        wait("attach error cleared", || {
            r.session.status().attach_error.is_none()
        });
        assert!(good.link.accepts_input());
        assert!(!r.session.status().finished);
    }

    /// Close `pane` and open a new one in one go. Both messages are queued
    /// before the worker can publish `finished` (it publishes under the
    /// status lock held here), so the worker always revives.
    fn close_and_reopen(r: &Rig, pane: u64, want: Want) -> RemotePane {
        let status = lock(&r.session.status);
        let id = r.session.next_pane.fetch_add(1, Ordering::Relaxed);
        let link = RemoteLink::new(80, 24);
        r.session.tx.send(Msg::ClosePane { pane }).unwrap();
        r.session
            .tx
            .send(Msg::OpenPane {
                pane: id,
                want,
                link: link.clone(),
                sink: r.sink.clone(),
            })
            .unwrap();
        drop(status);
        RemotePane { id, link }
    }

    #[test]
    fn reviving_during_an_enrollment_never_enrolls_twice() {
        let connector = FakeConnector::new("fp-1", 1);
        let (approve, approval) = mpsc::channel();
        *lock(&connector.approval) = Some(approval);
        let r = rig_with("revive-enroll", connector, false);
        let first = r
            .session
            .open_pane(Want::First, 80, 24, r.sink.clone())
            .unwrap();
        wait("enrolling connect", || r.connector.seen().len() == 1);
        // the last pane closes during the approval wait and a new one opens
        let pane = close_and_reopen(&r, first.id, Want::First);
        wait("the revived attempt minted", || r.core.mints() == 2);
        std::thread::sleep(Duration::from_millis(50));
        assert_eq!(r.connector.seen().len(), 1, "a second enrollment started");
        assert!(!r.session.status().finished);
        approve.send(()).unwrap();
        wait("attach", || pane.link.accepts_input());
        let seen = r.connector.seen();
        assert_eq!(seen.len(), 1);
        assert!(seen[0].invite_path.is_some());
        assert_eq!(r.connector.host_count(), 1);
        let host = r.connector.host(0).unwrap();
        assert_eq!(host.attach_count(), 1, "the pane attaches once");
        assert!(!r.invite.exists());
        let saved = LinksStore::new(r.dir.join("links.json")).load().unwrap();
        let link = saved.get("Mac/1").unwrap();
        assert!(link.enrolled && link.invite_path.is_none());
        let status = r.session.status();
        assert_eq!(
            (status.phase, status.save_error),
            (ConnPhase::Connected, None)
        );

        // Results of the old incarnation's attempt (1) are not the revived
        // attempt's. Pane ids never repeat, so the live pane's id is the
        // worst case: the attempt id alone must reject them.
        let view_gen = pane.link.current_gen().unwrap();
        let (_stale_tx, stale_rx) = mpsc::channel();
        let stale_view: Arc<dyn ViewInput> = Arc::new(super::fake::FakeView::default());
        let stale = [
            Msg::Minted {
                attempt: 1,
                result: Ok(TicketFile {
                    path: "stale.ticket".into(),
                    expires_at_unix: 1,
                    relay_url: "wss://relay.example/v2/relay".into(),
                }),
            },
            Msg::Linked {
                attempt: 1,
                result: Err(LinkFail::Other("stale".into())),
            },
            Msg::Attached {
                attempt: 1,
                pane: pane.id,
                result: Ok((stale_view, stale_rx, "1".into(), (80, 24))),
            },
            Msg::ViewEnd {
                attempt: 1,
                pane: pane.id,
                view_gen,
                end: PumpEnd::Disconnected("stale".into()),
            },
        ];
        for msg in stale {
            r.session.tx.send(msg).unwrap();
        }
        std::thread::sleep(Duration::from_millis(50));
        assert_eq!(pane.link.current_gen(), Some(view_gen), "view replaced");
        assert!(pane.link.accepts_input(), "stale disconnect taken");
        assert_eq!(r.session.status().phase, ConnPhase::Connected);
        assert_eq!((r.connector.seen().len(), r.core.mints()), (1, 2));
        PtyLink::write(&*pane.link, b"ok");
        assert_eq!(host.view(0).unwrap().writes(), vec![b"ok".to_vec()]);
    }

    #[test]
    fn an_enrollment_ending_while_the_session_stops_is_not_lost() {
        let connector = FakeConnector::new("fp-1", 1);
        let (approve, approval) = mpsc::channel();
        *lock(&connector.approval) = Some(approval);
        let r = rig_with("revive-drain", connector, false);
        let first = r
            .session
            .open_pane(Want::First, 80, 24, r.sink.clone())
            .unwrap();
        wait("enrolling connect", || r.connector.seen().len() == 1);
        // The worker stops (last pane closed) and the enrollment result is
        // queued before the new pane: it is read while the worker is
        // stopped, and must still end `enrolling`.
        let status = lock(&r.session.status); // the worker cannot publish
        r.session
            .tx
            .send(Msg::ClosePane { pane: first.id })
            .unwrap();
        approve.send(()).unwrap();
        wait("enrolled", || {
            r.connector.host_count() == 1 && !r.invite.exists()
        });
        std::thread::sleep(Duration::from_millis(30)); // Linked is queued
        let id = r.session.next_pane.fetch_add(1, Ordering::Relaxed);
        let link = RemoteLink::new(80, 24);
        r.session
            .tx
            .send(Msg::OpenPane {
                pane: id,
                want: Want::First,
                link: link.clone(),
                sink: r.sink.clone(),
            })
            .unwrap();
        drop(status);
        wait("attach", || link.accepts_input());
        let seen = r.connector.seen();
        assert_eq!(seen.len(), 2);
        assert!(seen[1].invite_path.is_none(), "enrolled once");
        assert_eq!(r.connector.host(1).unwrap().attach_count(), 1);
        assert_eq!(r.session.status().phase, ConnPhase::Connected);
    }

    #[test]
    fn invitation_is_deleted_only_from_the_tickets_dir() {
        let base = std::env::temp_dir().join(format!("shellx-rs-inv-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&base);
        let tickets = base.join("tickets");
        let other = base.join("other");
        std::fs::create_dir_all(&tickets).unwrap();
        std::fs::create_dir_all(&other).unwrap();
        for (dir, name) in [
            (&tickets, "invite-m1.uri"),
            (&tickets, "links.json"),
            (&other, "invite-m1.uri"),
        ] {
            std::fs::write(dir.join(name), "x").unwrap();
        }
        assert!(invite_path_ok(&tickets, &tickets.join("invite-m1.uri")));
        assert!(!invite_path_ok(&tickets, &tickets.join("links.json")));
        assert!(!invite_path_ok(&tickets, &other.join("invite-m1.uri")));
        assert!(!invite_path_ok(
            &tickets,
            &tickets.join("../other/invite-m1.uri")
        ));
        assert!(!invite_path_ok(&tickets, &tickets.join("invite-.uri")));
        // a link pointing outside: enrollment completes, the file stays
        let ctx = Ctx {
            machine_id: "m1".into(),
            ticket_name: ticket_file_name("m1"),
            core: Arc::new(MintingCore::new(tickets.join("t"))),
            connector: Arc::new(FakeConnector::new("fp-1", 1)),
            state_dir: base.clone(),
            invite_dir: tickets.clone(),
            device_name: "PC".into(),
            links: None,
            record: Arc::new(Mutex::new(record(&base, false))),
            last_ticket: Arc::new(Mutex::new(None)),
        };
        let mut rec = record(&base, false);
        rec.invite_path = Some(other.join("invite-m1.uri").to_string_lossy().into_owned());
        let problem = ctx.forget_invite(&rec, true).unwrap();
        assert!(problem.contains("not deleting"), "{problem}");
        assert!(other.join("invite-m1.uri").exists());
        assert!(lock(&ctx.record).enrolled && lock(&ctx.record).invite_path.is_none());
        rec.invite_path = Some(tickets.join("invite-m1.uri").to_string_lossy().into_owned());
        assert_eq!(ctx.forget_invite(&rec, true), None);
        assert!(!tickets.join("invite-m1.uri").exists());
        let _ = std::fs::remove_dir_all(&base);
    }

    #[test]
    fn connect_failures_back_off_and_mint_each_time() {
        let connector = FakeConnector::new("fp-1", 1);
        connector.push_error("relay connect failed");
        connector.push_error("relay connect failed");
        let r = rig_with("backoff", connector, true);
        let pane = r
            .session
            .open_pane(Want::First, 80, 24, r.sink.clone())
            .unwrap();
        wait("Reconnecting", || {
            matches!(r.session.status().phase, ConnPhase::Reconnecting { .. })
        });
        assert_eq!(r.session.status().shown, Some(Str::Reconnecting));
        assert!(!pane.link.accepts_input());
        wait("attach", || pane.link.accepts_input());
        assert_eq!(r.connector.seen().len(), 3);
        assert_eq!(r.core.mints(), 3, "one fresh ticket per attempt");
        let status = r.session.status();
        assert_eq!(status.phase, ConnPhase::Connected);
        assert_eq!(status.shown, None, "no Reconnecting pill once connected");
    }

    #[test]
    fn reconnecting_refuses_input_and_never_queues_it() {
        let r = rig_with("refuse", FakeConnector::new("fp-1", 1), true);
        let pane = r
            .session
            .open_pane(Want::First, 80, 24, r.sink.clone())
            .unwrap();
        wait("attach", || pane.link.accepts_input());
        let mut mirror = crate::remote_link::RemoteMirror::new(pane.link.clone()).unwrap();
        let host = r.connector.host(0).unwrap();
        host.disconnect("daemon killed");
        wait("Reconnecting", || !pane.link.accepts_input());
        assert!(!mirror.send_text("tiếng Việt"));
        mirror.core().send_text("x");
        PtyLink::write(&*pane.link, b"y");
        assert!(host.view(0).unwrap().writes().is_empty());
        wait("reconnect", || pane.link.accepts_input());
        assert!(mirror.send_text("tiếng Việt"));
        let new_view = r.connector.host(1).unwrap().view(0).unwrap();
        assert_eq!(new_view.writes(), vec!["tiếng Việt".as_bytes().to_vec()]);
    }

    #[test]
    fn ended_terminal_closes_only_that_pane_then_remote_ended() {
        let r = rig_with("ended", FakeConnector::new("fp-1", 1), true);
        let a = r
            .session
            .open_pane(Want::First, 80, 24, r.sink.clone())
            .unwrap();
        wait("attach a", || a.link.accepts_input());
        let (tx_b, rx_b) = mpsc::channel();
        let sink_b: PaneSink = Arc::new(move |event| tx_b.send(event).is_ok());
        let b = r.session.open_pane(Want::New, 80, 24, sink_b).unwrap();
        wait("attach b", || b.link.accepts_input());
        let host = r.connector.host(0).unwrap();
        assert_eq!(host.attached_ids(), vec!["1".to_string(), "2".to_string()]);
        assert!(rx_b.try_iter().any(|e| e
            == PaneEvent::Retargeted {
                terminal_id: "2".into()
            }));
        host.end_terminal("2");
        wait("pane b ended", || b.link.is_closed());
        assert!(rx_b.try_iter().any(|e| e == PaneEvent::Ended));
        assert!(a.link.accepts_input(), "the sibling pane stays");
        assert_eq!(r.session.status().phase, ConnPhase::Connected);
        host.end_terminal("1");
        wait("finish", || r.session.status().finished);
        assert!(a.link.is_closed());
        let status = r.session.status();
        assert_eq!(
            (status.phase, status.shown),
            (ConnPhase::Ended, Some(Str::RemoteEnded))
        );
    }

    #[test]
    fn ended_with_the_client_closed_is_a_disconnect() {
        let r = rig_with("graceful", FakeConnector::new("fp-1", 1), true);
        let pane = r
            .session
            .open_pane(Want::First, 80, 24, r.sink.clone())
            .unwrap();
        wait("attach", || pane.link.accepts_input());
        let host = r.connector.host(0).unwrap();
        // a gracefully stopping daemon: views detached, then the client closes
        host.closed.store(true, Ordering::Release);
        host.emit(0, AttachEvent::Ended);
        wait("reconnect", || {
            r.connector.host_count() == 2 && pane.link.accepts_input()
        });
        assert!(!pane.link.is_closed());
    }

    #[test]
    fn ended_while_the_list_fails_is_a_disconnect() {
        let r = rig_with("listfail", FakeConnector::new("fp-1", 1), true);
        let pane = r
            .session
            .open_pane(Want::First, 80, 24, r.sink.clone())
            .unwrap();
        wait("attach", || pane.link.accepts_input());
        let host = r.connector.host(0).unwrap();
        host.fail_list.store(true, Ordering::Release);
        host.emit(0, AttachEvent::Ended);
        wait("reconnect", || {
            r.connector.host_count() == 2 && pane.link.accepts_input()
        });
        assert!(!pane.link.is_closed());
    }

    #[test]
    fn detached_but_still_listed_reattaches() {
        let r = rig_with("detached", FakeConnector::new("fp-1", 1), true);
        let pane = r
            .session
            .open_pane(Want::First, 80, 24, r.sink.clone())
            .unwrap();
        wait("attach", || pane.link.accepts_input());
        let host = r.connector.host(0).unwrap();
        std::thread::sleep(Duration::from_millis(20)); // the snapshot was pumped
        host.emit(0, AttachEvent::Ended);
        wait("reattach", || {
            host.attach_count() == 2 && pane.link.accepts_input()
        });
        assert_eq!(host.attached_ids(), vec!["1".to_string(), "1".to_string()]);
        assert_eq!(r.connector.host_count(), 1);
    }

    #[test]
    fn after_a_daemon_restart_the_pane_moves_to_a_live_terminal() {
        let connector = FakeConnector::new("fp-1", 1);
        let first = Arc::new(FakeHost::new("fp-1", 1));
        connector.push_host(first.clone());
        // the restarted daemon numbers its surfaces anew: "1" is gone
        let restarted = Arc::new(FakeHost::new("fp-1", 0));
        for _ in 0..3 {
            restarted.create_terminal().unwrap();
        }
        restarted.end_terminal("1");
        connector.push_host(restarted.clone());
        let r = rig_with("restart", connector, true);
        let pane = r
            .session
            .open_pane(Want::First, 80, 24, r.sink.clone())
            .unwrap();
        wait("attach", || pane.link.accepts_input());
        r.events();
        first.disconnect("daemon killed");
        wait("reattach", || {
            restarted.attach_count() == 1 && pane.link.accepts_input()
        });
        assert_eq!(restarted.attached_ids(), vec!["2".to_string()]);
        assert!(r.events().contains(&PaneEvent::Retargeted {
            terminal_id: "2".into()
        }));
    }

    #[test]
    fn offline_machine_waits_then_connects_when_online() {
        let r = rig_with("offline", FakeConnector::new("fp-1", 1), true);
        r.session.set_machine_online(false);
        let pane = r
            .session
            .open_pane(Want::First, 80, 24, r.sink.clone())
            .unwrap();
        wait("Offline", || r.session.status().phase == ConnPhase::Offline);
        assert_eq!(r.session.status().shown, Some(Str::Offline));
        std::thread::sleep(Duration::from_millis(30));
        assert!(r.connector.seen().is_empty());
        r.session.set_machine_online(true);
        wait("attach", || pane.link.accepts_input());
    }

    #[test]
    fn closing_the_last_pane_finishes_the_session() {
        let r = rig_with("close", FakeConnector::new("fp-1", 1), true);
        let pane = r
            .session
            .open_pane(Want::First, 80, 24, r.sink.clone())
            .unwrap();
        wait("attach", || pane.link.accepts_input());
        r.session.close_pane(pane.id);
        wait("finish", || r.session.status().finished);
        assert!(!pane.link.accepts_input());
        assert!(
            !r.dir.join(ticket_file_name("Mac/1")).exists(),
            "ticket file cleaned up"
        );
    }

    #[test]
    fn resize_reaches_the_view_and_the_next_attach() {
        let r = rig_with("resize", FakeConnector::new("fp-1", 1), true);
        let pane = r
            .session
            .open_pane(Want::First, 80, 24, r.sink.clone())
            .unwrap();
        wait("attach", || pane.link.accepts_input());
        let host = r.connector.host(0).unwrap();
        pane.link.resize(120, 40, 8, 16).unwrap();
        assert_eq!(
            lock(&host.view(0).unwrap().resizes).clone(),
            vec![(120, 40)]
        );
        host.disconnect("x");
        wait("reconnect", || {
            r.connector.host_count() == 2 && pane.link.accepts_input()
        });
        // the new attach replays Resized at the pane's current grid
        let second = r.connector.host(1).unwrap();
        assert_eq!(second.attach_count(), 1);
        let events = r.events();
        assert!(
            events.contains(&PaneEvent::Reset {
                cols: 120,
                rows: 40
            }),
            "{events:?}"
        );
    }
}
