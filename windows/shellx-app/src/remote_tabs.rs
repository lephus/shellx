//! GPUI-free glue between the window's tabs and the remote sessions (Task
//! 13b). The window (`ui/root.rs`) owns one `RemoteTabs`; `--smoke` and the
//! Mac tests drive the same code against the fake Mac of `remote_session`.
//!
//! - One `RemoteSession` per Mac, shared by all of that Mac's panes: started
//!   on the first pane, reused while it has not finished, replaced by a new
//!   one once it has (closed, ended, failed for good).
//! - Model `PaneId` -> (session, session pane id): closing a pane in the
//!   window detaches its view (`close_pane`). The session itself is kept
//!   until it has finished: after its last pane it finishes on its own,
//!   except while an invitation's enrollment still waits for the Mac
//!   owner's approval; the next Open then reuses it, so one invitation is
//!   never enrolled twice. Finished sessions no pane uses are let go.
//! - What a new pane shows (`Want`): sidebar Open on a Mac without panes
//!   shows its first terminal, another Open or a split of a remote pane
//!   creates a new terminal on the Mac (spec §8.6 C12), a stored terminal id
//!   reattaches. A split of a local pane stays local.
//! - The 15 s machine list feeds each session's online flag (on change).
//! - links.json is reloaded in the UI once a session enrolled (the
//!   invitation deleted, `enrolled = true` saved) or dropped an expired
//!   invitation; the pairing panel caches the links.
//! - Sign-out (or another account) closes every session.
//! - The pane's status pill (`overlay`) from a `SessionStatus` snapshot.
// The window (cfg(windows)) is the main user; the Mac build tests it.
#![cfg_attr(not(windows), allow(dead_code))]

use std::collections::BTreeMap;
use std::sync::Arc;

use anyhow::Result;
use shellx_model::account::AccountState;
use shellx_model::core_api::CoreCall;
use shellx_model::layout::PaneId;
use shellx_model::links::RemoteLink as LinkRecord;
use shellx_model::remote_state::ConnPhase;
use shellx_model::sidebar::MachineInfo;
use shellx_model::strings::{Lang, Str, save_link_failed};
use shellx_model::tabs::{PaneTarget, Tabs};

use crate::links_store::LinksStore;
use crate::remote_link::{PaneEvent, PaneSink};
use crate::remote_session::{
    RelayConnector, RemotePane, RemoteSession, SessionConfig, SessionError, SessionStatus, Want,
};

/// The grid a remote pane asks for before its first layout (the first
/// paint resizes the link, before the attach normally completes).
pub const INITIAL_GRID: (u16, u16) = (80, 24);

/// Longest detail line in the status pill.
const DETAIL_MAX: usize = 200;

// ------------------------------------------------------------ sessions

/// What the window needs from a session (`RemoteSession`, a fake in tests).
pub trait SessionApi: Send + Sync {
    fn open_pane(&self, want: Want, cols: u16, rows: u16, sink: PaneSink) -> Result<RemotePane>;
    fn close_pane(&self, pane: u64);
    fn set_machine_online(&self, online: bool);
    fn status(&self) -> SessionStatus;
    fn close(&self);
}

impl SessionApi for RemoteSession {
    fn open_pane(&self, want: Want, cols: u16, rows: u16, sink: PaneSink) -> Result<RemotePane> {
        RemoteSession::open_pane(self, want, cols, rows, sink)
    }
    fn close_pane(&self, pane: u64) {
        RemoteSession::close_pane(self, pane);
    }
    fn set_machine_online(&self, online: bool) {
        RemoteSession::set_machine_online(self, online);
    }
    fn status(&self) -> SessionStatus {
        RemoteSession::status(self)
    }
    fn close(&self) {
        RemoteSession::close(self);
    }
}

/// The app's session config (Task 13b brief item 5): shellx-core's tickets
/// dir for the invitation, the cached links store, the cmux-remote identity
/// dir, this PC's name and the relay connector. The relay URL comes from
/// the link and the minted tickets (R17), never from here.
pub fn app_session_config(
    record: LinkRecord,
    core: Arc<dyn CoreCall>,
) -> std::io::Result<SessionConfig> {
    Ok(SessionConfig {
        record,
        core,
        connector: Arc::new(RelayConnector),
        state_dir: crate::paths::remote_dir()?,
        invite_dir: crate::paths::core_dir()?.join("tickets"),
        device_name: crate::os_info::device_name(),
        links: Some(LinksStore::default_location()?),
        time_scale: 1,
    })
}

/// `RemoteSession::start` with `app_session_config` (non-blocking: it only
/// spawns the session's worker thread).
pub fn start_app_session(record: LinkRecord, core: Arc<dyn CoreCall>) -> Result<RemoteSession> {
    RemoteSession::start(app_session_config(record, core)?)
}

/// Why a remote pane could not open.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum OpenError {
    /// No saved access (links.json) for this machine.
    NoLink,
    /// The session could not start, or refused the pane.
    Failed(String),
}

struct Session<S> {
    session: Arc<S>,
    /// Last online flag sent to the session.
    online: Option<bool>,
    /// Started from a link that was not enrolled yet (or still named its
    /// invitation): links.json changes on the first connect.
    reload_links: bool,
}

struct Pane<S> {
    machine_id: String,
    session: Arc<S>,
    id: u64,
}

pub struct RemoteTabs<S> {
    sessions: BTreeMap<String, Session<S>>,
    panes: BTreeMap<PaneId, Pane<S>>,
    planned: BTreeMap<PaneId, Want>,
}

impl<S> Default for RemoteTabs<S> {
    fn default() -> Self {
        RemoteTabs {
            sessions: BTreeMap::new(),
            panes: BTreeMap::new(),
            planned: BTreeMap::new(),
        }
    }
}

impl<S: SessionApi> RemoteTabs<S> {
    pub fn new() -> Self {
        Self::default()
    }

    /// What `pane` (just added to the model) will show once the window opens
    /// it: `open_want` for a sidebar Open, `Want::New` for a split.
    pub fn plan(&mut self, pane: PaneId, want: Want) {
        self.planned.insert(pane, want);
    }

    /// Opens the remote pane `pane` of `machine_id` (the window calls this
    /// for every new `PaneTarget::Remote`). Reuses the Mac's session while it
    /// has not finished, else starts one from `record` with `start` and
    /// tells it whether the Mac is `online`. Non-blocking.
    #[allow(clippy::too_many_arguments)]
    pub fn open(
        &mut self,
        pane: PaneId,
        machine_id: &str,
        terminal_id: &str,
        record: Option<&LinkRecord>,
        online: Option<bool>,
        sink: PaneSink,
        start: &mut dyn FnMut(LinkRecord) -> Result<S>,
    ) -> Result<(Arc<S>, RemotePane), OpenError> {
        let want = self
            .planned
            .remove(&pane)
            .unwrap_or_else(|| want_for_target(terminal_id));
        let (cols, rows) = INITIAL_GRID;
        let reusable = self
            .sessions
            .get(machine_id)
            .filter(|s| !s.session.status().finished)
            .map(|s| s.session.clone());
        if let Some(session) = reusable {
            // It can still finish between the check and the send: then a
            // new session takes the pane below.
            if let Ok(remote) = session.open_pane(want.clone(), cols, rows, sink.clone()) {
                self.track(pane, machine_id, &session, &remote);
                return Ok((session, remote));
            }
        }
        let record = record.ok_or(OpenError::NoLink)?.clone();
        let reload_links = !record.enrolled || record.invite_path.is_some();
        let session = Arc::new(start(record).map_err(|e| OpenError::Failed(format!("{e:#}")))?);
        // Sent before the pane: an offline Mac shows "ngoại tuyến" at once.
        if let Some(online) = online {
            session.set_machine_online(online);
        }
        // A finished session that no pane uses any more drops here.
        self.sessions.insert(
            machine_id.to_string(),
            Session {
                session: session.clone(),
                online,
                reload_links,
            },
        );
        let remote = session
            .open_pane(want, cols, rows, sink)
            .map_err(|e| OpenError::Failed(format!("{e:#}")))?;
        self.track(pane, machine_id, &session, &remote);
        Ok((session, remote))
    }

    fn track(&mut self, pane: PaneId, machine_id: &str, session: &Arc<S>, remote: &RemotePane) {
        self.panes.insert(
            pane,
            Pane {
                machine_id: machine_id.to_string(),
                session: session.clone(),
                id: remote.id,
            },
        );
    }

    /// The window dropped `pane` (closed, its terminal ended, its tab
    /// closed): detach its view on the Mac. The session is NOT dropped here
    /// (dropping it would close it): its last pane gone, it finishes by
    /// itself, or, while an invitation's enrollment still waits for
    /// approval, stays for the next Open (one invitation, one enrollment).
    pub fn pane_closed(&mut self, pane: PaneId) {
        self.planned.remove(&pane);
        if let Some(closed) = self.panes.remove(&pane) {
            closed.session.close_pane(closed.id);
        }
        self.prune();
    }

    /// Lets go of sessions that have finished and that no pane uses.
    fn prune(&mut self) {
        let panes = &self.panes;
        self.sessions.retain(|_, s| {
            !s.session.status().finished
                || panes.values().any(|p| Arc::ptr_eq(&p.session, &s.session))
        });
    }

    /// The machine list (15 s poll): each open session learns whether its
    /// Mac is online, when that changed.
    pub fn machines_updated(&mut self, machines: &[MachineInfo]) {
        self.prune();
        for (machine_id, s) in &mut self.sessions {
            let Some(m) = machines.iter().find(|m| &m.machine_id == machine_id) else {
                continue;
            };
            if s.online != Some(m.online) {
                s.online = Some(m.online);
                s.session.set_machine_online(m.online);
            }
        }
    }

    /// `pane`'s session status changed. True (once per session) when
    /// links.json was rewritten by it: enrolled on the first connect, or
    /// the expired invitation dropped (`NeedsPairing`). The window then
    /// reloads its cached links (`Cmd::LoadLinks`).
    pub fn status_changed(&mut self, pane: PaneId) -> bool {
        let Some(p) = self.panes.get(&pane) else {
            return false;
        };
        let Some(s) = self.sessions.get_mut(&p.machine_id) else {
            return false;
        };
        if !s.reload_links || !Arc::ptr_eq(&s.session, &p.session) {
            return false;
        }
        let status = s.session.status();
        let rewritten = status.phase == ConnPhase::Connected
            || matches!(status.error, Some(SessionError::NeedsPairing(_)));
        if rewritten {
            s.reload_links = false;
        }
        rewritten
    }

    /// Sign-out or another account: close every session. The window then
    /// closes the remote panes through the tabs model.
    pub fn close_all(&mut self) {
        for s in self.sessions.values() {
            s.session.close();
        }
        for p in self.panes.values() {
            p.session.close();
        }
        self.sessions.clear();
        self.panes.clear();
        self.planned.clear();
    }

    /// The current session of a Mac (tests, smoke).
    pub fn session(&self, machine_id: &str) -> Option<&Arc<S>> {
        self.sessions.get(machine_id).map(|s| &s.session)
    }

    /// Remote panes the window has open.
    pub fn pane_count(&self) -> usize {
        self.panes.len()
    }
}

/// Want of a remote pane with no plan: its stored terminal, else the first.
pub fn want_for_target(terminal_id: &str) -> Want {
    if terminal_id.is_empty() {
        Want::First
    } else {
        Want::Terminal(terminal_id.to_string())
    }
}

/// Sidebar Open: a Mac without panes shows its first terminal (the one its
/// owner sees); another Open creates a new terminal there, like "+" does
/// for a local tab.
pub fn open_want(tabs: &Tabs, machine_id: &str) -> Want {
    if tabs.panes_on_machine(machine_id).is_empty() {
        Want::First
    } else {
        Want::New
    }
}

/// What a split of `focused` opens: a split of a remote pane is a new shell
/// on the same Mac (spec §8.6 C12), a split of a local pane stays local.
pub fn split_target(tabs: &Tabs, focused: PaneId) -> (PaneTarget, Option<Want>) {
    match tabs.target(focused) {
        Some(PaneTarget::Remote { machine_id, .. }) => (
            PaneTarget::Remote {
                machine_id: machine_id.clone(),
                terminal_id: String::new(),
            },
            Some(Want::New),
        ),
        _ => (PaneTarget::Local, None),
    }
}

/// Merges runs of `Output` into one feed (the UI task drains its channel in
/// batches); everything else keeps its place and order.
pub fn coalesce(events: impl IntoIterator<Item = PaneEvent>) -> Vec<PaneEvent> {
    let mut out: Vec<PaneEvent> = Vec::new();
    for event in events {
        if let (PaneEvent::Output(more), Some(PaneEvent::Output(bytes))) = (&event, out.last_mut())
        {
            bytes.extend_from_slice(more);
            continue;
        }
        out.push(event);
    }
    out
}

/// Watches the account state for the remote sessions.
#[derive(Default)]
pub struct AccountWatch {
    signed_in: Option<String>,
}

impl AccountWatch {
    /// Feed every account state. True when the remote sessions must close:
    /// signed out after being signed in, or signed in as another machine.
    pub fn update(&mut self, state: &AccountState) -> bool {
        match state {
            AccountState::LoggedIn { machine_id } => {
                let other = self.signed_in.as_ref().is_some_and(|m| m != machine_id);
                self.signed_in = Some(machine_id.clone());
                other
            }
            AccountState::LoggedOut => self.signed_in.take().is_some(),
            _ => false,
        }
    }
}

// ------------------------------------------------------------ status pill

/// The pill's dot (spec §7.4): RUNNING while connecting, MUTED offline or
/// ended, ERROR for a session that stopped for good.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Tone {
    Running,
    Muted,
    Error,
}

/// The status pill centered on a remote pane.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Overlay {
    pub title: Str,
    pub tone: Tone,
    /// Small MUTED lines under the title (reasons, save errors).
    pub details: Vec<String>,
}

fn clip(text: &str) -> String {
    let text = text.trim();
    match text.char_indices().nth(DETAIL_MAX) {
        Some((cut, _)) => format!("{}…", &text[..cut]),
        None => text.to_string(),
    }
}

fn tone_of(title: Str) -> Tone {
    match title {
        Str::Connecting | Str::Reconnecting | Str::RemoteAttachFailed => Tone::Running,
        Str::FingerprintMismatch | Str::NeedsPairing | Str::Error => Tone::Error,
        _ => Tone::Muted,
    }
}

/// The pill of a remote pane, or none while it is connected and attached.
/// Shown while the phase is not Connected, or a session error is set, or
/// the session's attach error is set and THIS pane is not `attached` (the
/// error is session-wide; a sibling that works shows nothing); the save
/// error (links.json) is a detail line while shown.
pub fn overlay(status: &SessionStatus, attached: bool, lang: Lang) -> Option<Overlay> {
    let mut details = Vec::new();
    let title = match (&status.error, &status.phase) {
        (Some(SessionError::FingerprintMismatch { .. }), _) => Str::FingerprintMismatch,
        (Some(SessionError::NeedsPairing(reason)), _) => {
            details.push(reason.clone());
            Str::NeedsPairing
        }
        (None, ConnPhase::Connected) => {
            if attached {
                return None;
            }
            details.push(status.attach_error.clone()?);
            Str::RemoteAttachFailed
        }
        (None, phase) => {
            let title = status.shown.unwrap_or(match phase {
                ConnPhase::Reconnecting { .. } => Str::Reconnecting,
                ConnPhase::Offline => Str::Offline,
                ConnPhase::Ended => Str::RemoteEnded,
                _ => Str::Connecting,
            });
            if title == Str::Reconnecting
                && let Some(reason) = &status.reason
            {
                details.push(reason.clone());
            }
            if let Some(error) = &status.attach_error {
                details.push(error.clone());
            }
            title
        }
    };
    if let Some(error) = &status.save_error {
        details.push(save_link_failed(lang, error));
    }
    details.retain(|d| !d.trim().is_empty());
    Some(Overlay {
        title,
        tone: tone_of(title),
        details: details.iter().map(|d| clip(d)).collect(),
    })
}

/// The pill of a remote pane that could not open.
pub fn failed_overlay(error: &OpenError) -> Overlay {
    match error {
        OpenError::NoLink => Overlay {
            title: Str::NeedsPairing,
            tone: Tone::Error,
            details: Vec::new(),
        },
        OpenError::Failed(reason) => Overlay {
            title: Str::Error,
            tone: Tone::Error,
            details: vec![clip(reason)],
        },
    }
}

// ------------------------------------------------------------ smoke

/// `--smoke` (and a Mac test): the window's remote-tab path against the fake
/// Mac, with the real `RemoteSession`. Sidebar Open -> one session, the
/// pane retargets to the Mac's first terminal and links.json is reloaded
/// once (enrolled); a split -> `Want::New` on the same session, a new
/// terminal; a commit in the split is one UTF-8 write; that terminal ending
/// closes only its pane; sign-out closes the session and every remote pane
/// (a local tab stays).
pub fn smoke() -> Result<String> {
    use std::sync::atomic::{AtomicU64, Ordering};
    use std::sync::mpsc;
    use std::time::{Duration, Instant};

    use anyhow::{anyhow, bail, ensure};
    use shellx_model::layout::Axis;
    use shellx_model::links::Links;
    use shellx_model::tabs::CloseOutcome;

    use crate::remote_link::{Applied, RemoteMirror};
    use crate::remote_session::fake::FakeConnector;
    use crate::remote_session::{MintingCore, ticket_file_name};

    static RUN: AtomicU64 = AtomicU64::new(0);
    let dir = std::env::temp_dir().join(format!(
        "shellx-smoke-tabs-{}-{}",
        std::process::id(),
        RUN.fetch_add(1, Ordering::Relaxed)
    ));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir)?;

    struct Live {
        events: mpsc::Receiver<PaneEvent>,
        mirror: RemoteMirror,
    }
    let sink = || {
        let (tx, rx) = mpsc::channel::<PaneEvent>();
        let sink: PaneSink = Arc::new(move |event| tx.send(event).is_ok());
        (sink, rx)
    };
    // Apply what arrived; returns the Applied values.
    let pump = |live: &mut Live| -> Result<Vec<Applied>> {
        let mut out = Vec::new();
        while let Ok(event) = live.events.try_recv() {
            out.push(live.mirror.apply(event)?);
        }
        Ok(out)
    };
    let until = |live: &mut Live, what: &str, want: &dyn Fn(&Applied) -> bool| -> Result<()> {
        let deadline = Instant::now() + Duration::from_secs(10);
        loop {
            if pump(live)?.iter().any(want) {
                return Ok(());
            }
            if Instant::now() > deadline {
                bail!("remote tabs smoke: timed out waiting for {what}");
            }
            std::thread::sleep(Duration::from_millis(5));
        }
    };

    let result = (|| -> Result<String> {
        let invite = dir.join("invite-m1.uri");
        std::fs::write(&invite, "cmux://enroll/secret")?;
        let record = LinkRecord {
            machine_id: "m1".into(),
            machine_name: "Mac".into(),
            relay_route: "wss://relay.example/v2/relay".into(),
            relay_slot: "slot-1".into(),
            invite_path: Some(invite.to_string_lossy().into_owned()),
            daemon_fingerprint: "fp-1".into(),
            enrolled: false,
        };
        let mut links = Links::default();
        links.upsert(record.clone());
        LinksStore::new(dir.join("links.json")).save(&links)?;
        let core = Arc::new(MintingCore::new(dir.join(ticket_file_name("m1"))));
        let connector = Arc::new(FakeConnector::new("fp-1", 1));
        let mut starts = 0u32;
        let mut start = |record: LinkRecord| -> Result<RemoteSession> {
            starts += 1;
            RemoteSession::start(SessionConfig {
                record,
                core: core.clone(),
                connector: connector.clone(),
                state_dir: dir.clone(),
                invite_dir: dir.clone(),
                device_name: "PC test".into(),
                links: Some(LinksStore::new(dir.join("links.json"))),
                time_scale: 50,
            })
        };
        let mut remotes: RemoteTabs<RemoteSession> = RemoteTabs::new();
        let (mut tabs, local) = Tabs::new();

        // Sidebar Open: a new tab, the Mac's first terminal.
        let want = open_want(&tabs, "m1");
        ensure!(want == Want::First, "first Open wants {want:?}");
        let (_, p1) = tabs.new_tab(PaneTarget::Remote {
            machine_id: "m1".into(),
            terminal_id: String::new(),
        });
        remotes.plan(p1, want);
        let (s1, rx1) = sink();
        let (session, pane1) = remotes
            .open(p1, "m1", "", links.get("m1"), Some(true), s1, &mut start)
            .map_err(|e| anyhow!("open: {e:?}"))?;
        let mut live1 = Live {
            events: rx1,
            mirror: RemoteMirror::new(pane1.link.clone())?,
        };
        until(&mut live1, "the first pane's terminal", &|a| {
            *a == Applied::Retargeted("1".into())
        })?;
        ensure!(tabs.retarget(p1, "1"), "retarget p1");
        ensure!(
            remotes.status_changed(p1) && !remotes.status_changed(p1),
            "links.json reload must be asked once after the enrollment"
        );
        ensure!(!invite.exists(), "the invitation was not deleted");

        // Split: a new terminal on the same Mac, through the same session.
        let (target, planned) = split_target(&tabs, p1);
        let p2 = tabs.split_focused(Axis::Row, target);
        remotes.plan(
            p2,
            planned.ok_or_else(|| anyhow!("no plan for a remote split"))?,
        );
        let (s2, rx2) = sink();
        let (same, pane2) = remotes
            .open(p2, "m1", "", links.get("m1"), Some(true), s2, &mut start)
            .map_err(|e| anyhow!("split: {e:?}"))?;
        ensure!(
            Arc::ptr_eq(&same, &session),
            "the split started a second session"
        );
        let mut live2 = Live {
            events: rx2,
            mirror: RemoteMirror::new(pane2.link.clone())?,
        };
        until(&mut live2, "the split's new terminal", &|a| {
            *a == Applied::Retargeted("2".into())
        })?;
        ensure!(tabs.retarget(p2, "2"), "retarget p2");
        let host = connector.host(0).ok_or_else(|| anyhow!("no host"))?;
        ensure!(
            host.creates.load(Ordering::Acquire) == 1,
            "the split must create exactly one terminal on the Mac"
        );

        // Typing into the split: one write of the composed UTF-8.
        ensure!(live2.mirror.send_text("tiếng Việt"), "input refused");
        let view = host
            .attaches
            .lock()
            .map_err(|_| anyhow!("poisoned"))?
            .iter()
            .find(|a| a.terminal_id == "2")
            .map(|a| a.view.clone())
            .ok_or_else(|| anyhow!("no view of terminal 2"))?;
        ensure!(
            view.writes() == vec!["tiếng Việt".as_bytes().to_vec()],
            "the commit was not one UTF-8 write: {:?}",
            view.writes()
        );

        // The split's terminal ends on the Mac: only that pane closes.
        host.end_terminal("2");
        until(&mut live2, "the split's end", &|a| *a == Applied::Ended)?;
        ensure!(
            matches!(tabs.close_pane(p2), CloseOutcome::PaneClosed { .. }),
            "the end did not close only that pane"
        );
        remotes.pane_closed(p2);
        ensure!(remotes.pane_count() == 1, "pane map out of step");
        ensure!(
            !session.status().finished && live1.mirror.link().accepts_input(),
            "the sibling pane lost its session"
        );

        // Sign-out: every session closes, remote tabs close, a local tab stays.
        remotes.close_all();
        for pane in tabs.remote_panes() {
            tabs.close_pane(pane);
        }
        ensure!(tabs.remote_panes().is_empty(), "remote panes left");
        ensure!(
            tabs.active().layout.panes() == vec![local],
            "the local tab did not stay"
        );
        let deadline = Instant::now() + Duration::from_secs(10);
        while !session.status().finished {
            if Instant::now() > deadline {
                bail!("the session did not finish after sign-out");
            }
            std::thread::sleep(Duration::from_millis(5));
        }
        ensure!(starts == 1, "{starts} sessions started for one Mac");
        Ok(
            "open -> terminal 1, links reloaded once; split -> terminal 2 on the same session, \
             1 write; its end closed only that pane; sign-out closed the session"
                .to_string(),
        )
    })();
    let _ = std::fs::remove_dir_all(&dir);
    result
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::Mutex;
    use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};

    use crate::remote_link::RemoteLink;

    /// Records what the window asked of it.
    struct FakeSession {
        status: Mutex<SessionStatus>,
        refuse: AtomicBool,
        wants: Mutex<Vec<Want>>,
        closed_panes: Mutex<Vec<u64>>,
        online: Mutex<Vec<bool>>,
        closes: AtomicU64,
        next: AtomicU64,
    }

    impl FakeSession {
        fn new() -> FakeSession {
            FakeSession {
                status: Mutex::new(status(ConnPhase::Disconnected)),
                refuse: AtomicBool::new(false),
                wants: Mutex::new(Vec::new()),
                closed_panes: Mutex::new(Vec::new()),
                online: Mutex::new(Vec::new()),
                closes: AtomicU64::new(0),
                next: AtomicU64::new(1),
            }
        }

        fn finish(&self) {
            self.status.lock().unwrap().finished = true;
        }
    }

    impl SessionApi for FakeSession {
        fn open_pane(&self, want: Want, cols: u16, rows: u16, _: PaneSink) -> Result<RemotePane> {
            if self.refuse.load(Ordering::Acquire) || self.status.lock().unwrap().finished {
                anyhow::bail!("this remote session has finished");
            }
            self.wants.lock().unwrap().push(want);
            Ok(RemotePane {
                id: self.next.fetch_add(1, Ordering::AcqRel),
                link: RemoteLink::new(cols, rows),
            })
        }
        fn close_pane(&self, pane: u64) {
            self.closed_panes.lock().unwrap().push(pane);
        }
        fn set_machine_online(&self, online: bool) {
            self.online.lock().unwrap().push(online);
        }
        fn status(&self) -> SessionStatus {
            self.status.lock().unwrap().clone()
        }
        fn close(&self) {
            self.closes.fetch_add(1, Ordering::AcqRel);
        }
    }

    fn status(phase: ConnPhase) -> SessionStatus {
        SessionStatus {
            phase,
            shown: None,
            reason: None,
            error: None,
            save_error: None,
            attach_error: None,
            finished: false,
        }
    }

    fn record(id: &str, enrolled: bool) -> LinkRecord {
        LinkRecord {
            machine_id: id.into(),
            machine_name: format!("Mac {id}"),
            relay_route: "route".into(),
            relay_slot: "slot".into(),
            invite_path: (!enrolled).then(|| format!("/t/invite-{id}.uri")),
            daemon_fingerprint: "fp".into(),
            enrolled,
        }
    }

    fn sink() -> PaneSink {
        Arc::new(|_| true)
    }

    /// Starts FakeSessions and keeps them for the test.
    #[derive(Default)]
    struct Starter {
        started: Vec<Arc<FakeSession>>,
        records: Vec<LinkRecord>,
        fail: bool,
    }

    /// `RemoteTabs` stores its own `Arc<S>`; a starter hands out sessions
    /// that the test can also inspect, so `S` is a shared handle here.
    struct Shared(Arc<FakeSession>);

    impl SessionApi for Shared {
        fn open_pane(&self, w: Want, c: u16, r: u16, s: PaneSink) -> Result<RemotePane> {
            self.0.open_pane(w, c, r, s)
        }
        fn close_pane(&self, pane: u64) {
            self.0.close_pane(pane)
        }
        fn set_machine_online(&self, online: bool) {
            self.0.set_machine_online(online)
        }
        fn status(&self) -> SessionStatus {
            self.0.status()
        }
        fn close(&self) {
            self.0.close()
        }
    }

    impl Starter {
        fn start(&mut self) -> impl FnMut(LinkRecord) -> Result<Shared> + '_ {
            move |record| {
                if self.fail {
                    anyhow::bail!("LOCALAPPDATA is not set");
                }
                self.records.push(record);
                let session = Arc::new(FakeSession::new());
                self.started.push(session.clone());
                Ok(Shared(session))
            }
        }
    }

    fn open(
        remotes: &mut RemoteTabs<Shared>,
        starter: &mut Starter,
        pane: u64,
        machine: &str,
        terminal: &str,
        rec: Option<&LinkRecord>,
        online: Option<bool>,
    ) -> Result<(Arc<Shared>, RemotePane), OpenError> {
        let mut start = starter.start();
        remotes.open(
            PaneId(pane),
            machine,
            terminal,
            rec,
            online,
            sink(),
            &mut start,
        )
    }

    #[test]
    fn one_session_per_mac_shared_by_its_panes() {
        let mut remotes = RemoteTabs::new();
        let mut starter = Starter::default();
        let (m1, m2) = (record("m1", true), record("m2", true));
        remotes.plan(PaneId(1), Want::First);
        let (a, pa) = open(&mut remotes, &mut starter, 1, "m1", "", Some(&m1), None).unwrap();
        remotes.plan(PaneId(2), Want::New);
        let (b, pb) = open(&mut remotes, &mut starter, 2, "m1", "", Some(&m1), None).unwrap();
        let (c, _) = open(&mut remotes, &mut starter, 3, "m2", "", Some(&m2), None).unwrap();
        assert!(Arc::ptr_eq(&a, &b));
        assert!(!Arc::ptr_eq(&a, &c));
        assert_ne!(pa.id, pb.id);
        assert_eq!(starter.started.len(), 2);
        assert_eq!(
            *starter.started[0].wants.lock().unwrap(),
            vec![Want::First, Want::New]
        );
        // no plan: the stored terminal id reattaches, an empty one is First
        open(&mut remotes, &mut starter, 4, "m2", "7", Some(&m2), None).unwrap();
        assert_eq!(
            *starter.started[1].wants.lock().unwrap(),
            vec![Want::First, Want::Terminal("7".into())]
        );
        assert_eq!(remotes.pane_count(), 4);
    }

    #[test]
    fn a_finished_session_is_replaced_and_its_panes_keep_theirs() {
        let mut remotes = RemoteTabs::new();
        let mut starter = Starter::default();
        let m1 = record("m1", true);
        let (old, _) = open(&mut remotes, &mut starter, 1, "m1", "", Some(&m1), None).unwrap();
        starter.started[0].finish(); // e.g. a fingerprint mismatch
        let (new, _) = open(&mut remotes, &mut starter, 2, "m1", "", Some(&m1), None).unwrap();
        assert!(!Arc::ptr_eq(&old, &new));
        assert_eq!(starter.started.len(), 2);
        assert!(Arc::ptr_eq(remotes.session("m1").unwrap(), &new));
        // closing the old pane talks to the old session, the new one stays
        remotes.pane_closed(PaneId(1));
        assert_eq!(*starter.started[0].closed_panes.lock().unwrap(), vec![1]);
        assert!(remotes.session("m1").is_some());
        // finishing between the check and the send: a new session takes it
        starter.started[1].refuse.store(true, Ordering::Release);
        let (third, _) = open(&mut remotes, &mut starter, 3, "m1", "", Some(&m1), None).unwrap();
        assert_eq!(starter.started.len(), 3);
        assert!(Arc::ptr_eq(remotes.session("m1").unwrap(), &third));
    }

    #[test]
    fn closing_panes_detaches_and_keeps_the_session_until_it_finishes() {
        let mut remotes = RemoteTabs::new();
        let mut starter = Starter::default();
        let m1 = record("m1", true);
        let (_, a) = open(&mut remotes, &mut starter, 1, "m1", "", Some(&m1), None).unwrap();
        let (_, b) = open(&mut remotes, &mut starter, 2, "m1", "", Some(&m1), None).unwrap();
        remotes.pane_closed(PaneId(1));
        assert_eq!(*starter.started[0].closed_panes.lock().unwrap(), vec![a.id]);
        assert!(remotes.session("m1").is_some());
        remotes.pane_closed(PaneId(2));
        remotes.pane_closed(PaneId(2)); // twice, or a local pane: nothing
        remotes.pane_closed(PaneId(9));
        assert_eq!(
            *starter.started[0].closed_panes.lock().unwrap(),
            vec![a.id, b.id]
        );
        assert_eq!(remotes.pane_count(), 0);
        // Kept while it has not finished (an enrollment may still be waiting
        // for approval): the next Open reuses it, never a second session.
        assert!(remotes.session("m1").is_some());
        assert_eq!(starter.started[0].closes.load(Ordering::Acquire), 0);
        open(&mut remotes, &mut starter, 3, "m1", "", Some(&m1), None).unwrap();
        assert_eq!(starter.started.len(), 1);
        remotes.pane_closed(PaneId(3));
        // Once it finished (idle), it is let go and the next Open starts afresh.
        starter.started[0].finish();
        remotes.machines_updated(&[]);
        assert!(remotes.session("m1").is_none());
        open(&mut remotes, &mut starter, 4, "m1", "", Some(&m1), None).unwrap();
        assert_eq!(starter.started.len(), 2);
    }

    /// Fix round 1 (review Important 1): the tab is closed while the Mac
    /// owner has not approved yet, then "Mở" again from the cached (not yet
    /// enrolled) record: one session, ONE invitation connect, one approval.
    #[test]
    fn closing_the_tab_during_an_approval_never_enrolls_twice() {
        use std::sync::mpsc;
        use std::time::{Duration, Instant};

        use shellx_model::links::Links;

        use crate::remote_session::fake::FakeConnector;
        use crate::remote_session::{MintingCore, ticket_file_name};

        let dir = std::env::temp_dir().join(format!("shellx-rt-reopen-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        let invite = dir.join("invite-m1.uri");
        std::fs::write(&invite, "cmux://enroll/secret").unwrap();
        let rec = LinkRecord {
            machine_id: "m1".into(),
            machine_name: "Mac".into(),
            relay_route: "route".into(),
            relay_slot: "slot".into(),
            invite_path: Some(invite.to_string_lossy().into_owned()),
            daemon_fingerprint: "fp-1".into(),
            enrolled: false,
        };
        let mut links = Links::default();
        links.upsert(rec.clone());
        LinksStore::new(dir.join("links.json"))
            .save(&links)
            .unwrap();
        let core = Arc::new(MintingCore::new(dir.join(ticket_file_name("m1"))));
        let connector = Arc::new(FakeConnector::new("fp-1", 1));
        let (approve, approval) = mpsc::channel();
        *connector.approval.lock().unwrap() = Some(approval);
        let mut starts = 0u32;
        let mut start = |record: LinkRecord| -> Result<RemoteSession> {
            starts += 1;
            RemoteSession::start(SessionConfig {
                record,
                core: core.clone(),
                connector: connector.clone(),
                state_dir: dir.clone(),
                invite_dir: dir.clone(),
                device_name: "PC test".into(),
                links: Some(LinksStore::new(dir.join("links.json"))),
                time_scale: 50,
            })
        };
        let wait = |what: &str, done: &dyn Fn() -> bool| {
            let deadline = Instant::now() + Duration::from_secs(10);
            while !done() {
                assert!(Instant::now() < deadline, "timed out waiting for {what}");
                std::thread::sleep(Duration::from_millis(5));
            }
        };
        let mut remotes: RemoteTabs<RemoteSession> = RemoteTabs::new();

        remotes.plan(PaneId(1), Want::First);
        let (session, first) = remotes
            .open(
                PaneId(1),
                "m1",
                "",
                Some(&rec),
                Some(true),
                sink(),
                &mut start,
            )
            .map_err(|e| format!("{e:?}"))
            .unwrap();
        wait("the enrolling connect", &|| connector.seen().len() == 1);
        // The user closes the tab: the window drops the pane and its view
        // (with the view's handle on the session).
        remotes.pane_closed(PaneId(1));
        drop((session, first));
        std::thread::sleep(Duration::from_millis(100));

        // "Mở" again, from the cached record (not enrolled, invite named).
        remotes.plan(PaneId(2), Want::First);
        let (_session, second) = remotes
            .open(
                PaneId(2),
                "m1",
                "",
                Some(&rec),
                Some(true),
                sink(),
                &mut start,
            )
            .map_err(|e| format!("{e:?}"))
            .unwrap();
        std::thread::sleep(Duration::from_millis(50));
        assert_eq!(connector.seen().len(), 1, "a second enrollment started");
        approve.send(()).unwrap();
        wait("the new pane's attach", &|| second.link.accepts_input());
        let seen = connector.seen();
        assert_eq!(starts, 1, "a second session was started");
        assert_eq!(seen.len(), 1, "{} invitation connects", seen.len());
        assert!(seen[0].invite_path.is_some());
        assert_eq!(connector.host_count(), 1);
        assert!(!invite.exists());
        let saved = LinksStore::new(dir.join("links.json")).load().unwrap();
        assert!(
            saved
                .get("m1")
                .is_some_and(|l| l.enrolled && l.invite_path.is_none())
        );
        remotes.close_all();
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn no_link_or_a_failed_start_is_an_error_the_pane_shows() {
        let mut remotes = RemoteTabs::new();
        let mut starter = Starter::default();
        let e = open(&mut remotes, &mut starter, 1, "m1", "", None, None)
            .err()
            .expect("no link");
        assert_eq!(e, OpenError::NoLink);
        starter.fail = true;
        let e = open(
            &mut remotes,
            &mut starter,
            2,
            "m1",
            "",
            Some(&record("m1", true)),
            None,
        )
        .err()
        .expect("failed start");
        assert!(matches!(&e, OpenError::Failed(m) if m.contains("LOCALAPPDATA")));
        assert_eq!(remotes.pane_count(), 0);
        assert_eq!(failed_overlay(&OpenError::NoLink).title, Str::NeedsPairing);
        let o = failed_overlay(&e);
        assert_eq!((o.title, o.tone), (Str::Error, Tone::Error));
        assert!(o.details[0].contains("LOCALAPPDATA"));
    }

    #[test]
    fn online_flag_is_sent_at_start_and_on_change_only() {
        let mut remotes = RemoteTabs::new();
        let mut starter = Starter::default();
        let m1 = record("m1", true);
        open(
            &mut remotes,
            &mut starter,
            1,
            "m1",
            "",
            Some(&m1),
            Some(true),
        )
        .unwrap();
        let mac = |online| MachineInfo {
            machine_id: "m1".into(),
            name: "Mac".into(),
            platform: "macos".into(),
            online,
            last_seen_unix: 0,
            fingerprint: "f".into(),
            is_this_machine: false,
        };
        remotes.machines_updated(&[mac(true)]);
        remotes.machines_updated(&[mac(false)]);
        remotes.machines_updated(&[mac(false)]);
        remotes.machines_updated(&[]); // a list without the Mac changes nothing
        remotes.machines_updated(&[mac(true)]);
        assert_eq!(
            *starter.started[0].online.lock().unwrap(),
            vec![true, false, true]
        );
    }

    #[test]
    fn links_reload_once_after_enrollment_or_a_dropped_invitation() {
        let mut remotes = RemoteTabs::new();
        let mut starter = Starter::default();
        let (new, old) = (record("m1", false), record("m2", true));
        open(&mut remotes, &mut starter, 1, "m1", "", Some(&new), None).unwrap();
        open(&mut remotes, &mut starter, 2, "m1", "", Some(&new), None).unwrap();
        open(&mut remotes, &mut starter, 3, "m2", "", Some(&old), None).unwrap();
        let s1 = starter.started[0].clone();
        *s1.status.lock().unwrap() = status(ConnPhase::Connecting { attempt: 1 });
        assert!(!remotes.status_changed(PaneId(1)));
        *s1.status.lock().unwrap() = status(ConnPhase::Connected);
        assert!(remotes.status_changed(PaneId(2)));
        assert!(!remotes.status_changed(PaneId(1))); // once per session
        // already enrolled: nothing to reload
        *starter.started[1].status.lock().unwrap() = status(ConnPhase::Connected);
        assert!(!remotes.status_changed(PaneId(3)));
        assert!(!remotes.status_changed(PaneId(9)));
        // an expired invitation is dropped from links.json too
        let mut remotes = RemoteTabs::new();
        let mut starter = Starter::default();
        open(&mut remotes, &mut starter, 1, "m1", "", Some(&new), None).unwrap();
        let mut ended = status(ConnPhase::Ended);
        ended.error = Some(SessionError::NeedsPairing("request access again".into()));
        *starter.started[0].status.lock().unwrap() = ended;
        assert!(remotes.status_changed(PaneId(1)));
    }

    #[test]
    fn close_all_closes_every_session() {
        let mut remotes = RemoteTabs::new();
        let mut starter = Starter::default();
        let (m1, m2) = (record("m1", true), record("m2", true));
        open(&mut remotes, &mut starter, 1, "m1", "", Some(&m1), None).unwrap();
        starter.started[0].finish();
        open(&mut remotes, &mut starter, 2, "m1", "", Some(&m1), None).unwrap();
        open(&mut remotes, &mut starter, 3, "m2", "", Some(&m2), None).unwrap();
        remotes.plan(PaneId(4), Want::New);
        remotes.close_all();
        for s in &starter.started {
            assert!(s.closes.load(Ordering::Acquire) >= 1);
        }
        assert_eq!(remotes.pane_count(), 0);
        assert!(remotes.session("m1").is_none() && remotes.session("m2").is_none());
        // the plan was dropped too: pane 4 opens its stored terminal
        open(&mut remotes, &mut starter, 4, "m1", "", Some(&m1), None).unwrap();
        assert_eq!(*starter.started[3].wants.lock().unwrap(), vec![Want::First]);
    }

    #[test]
    fn open_and_split_wants() {
        let (mut tabs, local) = Tabs::new();
        assert_eq!(open_want(&tabs, "m1"), Want::First);
        assert_eq!(split_target(&tabs, local), (PaneTarget::Local, None));
        let (_, r) = tabs.new_tab(PaneTarget::Remote {
            machine_id: "m1".into(),
            terminal_id: "3".into(),
        });
        assert_eq!(open_want(&tabs, "m1"), Want::New);
        assert_eq!(open_want(&tabs, "m2"), Want::First);
        assert_eq!(
            split_target(&tabs, r),
            (
                PaneTarget::Remote {
                    machine_id: "m1".into(),
                    terminal_id: String::new()
                },
                Some(Want::New)
            )
        );
        assert_eq!(want_for_target(""), Want::First);
        assert_eq!(want_for_target("3"), Want::Terminal("3".into()));
    }

    #[test]
    fn coalesce_merges_output_runs_only() {
        let out = |s: &str| PaneEvent::Output(s.as_bytes().to_vec());
        let merged = coalesce(vec![
            PaneEvent::Reset { cols: 80, rows: 24 },
            PaneEvent::Snapshot(b"s".to_vec()),
            out("a"),
            out("b"),
            PaneEvent::Status,
            out("c"),
            PaneEvent::Ended,
        ]);
        assert_eq!(
            merged,
            vec![
                PaneEvent::Reset { cols: 80, rows: 24 },
                PaneEvent::Snapshot(b"s".to_vec()),
                out("ab"),
                PaneEvent::Status,
                out("c"),
                PaneEvent::Ended,
            ]
        );
        assert!(coalesce(Vec::new()).is_empty());
    }

    #[test]
    fn account_watch_closes_on_sign_out_or_another_account() {
        let mut w = AccountWatch::default();
        assert!(!w.update(&AccountState::Unknown));
        assert!(!w.update(&AccountState::LoggedOut)); // never signed in
        assert!(!w.update(&AccountState::LoggingIn));
        let me = |id: &str| AccountState::LoggedIn {
            machine_id: id.into(),
        };
        assert!(!w.update(&me("pc-1")));
        assert!(!w.update(&me("pc-1"))); // every notify: no change
        assert!(
            !w.update(&AccountState::Error(shellx_model::core_api::CoreErr::new(
                "network", "down"
            )))
        );
        assert!(w.update(&AccountState::LoggedOut));
        assert!(!w.update(&AccountState::LoggedOut));
        assert!(!w.update(&me("pc-1")));
        assert!(w.update(&me("pc-2")));
    }

    #[test]
    fn pill_per_status() {
        let vi = Lang::Vi;
        assert_eq!(overlay(&status(ConnPhase::Connected), true, vi), None);
        let o = overlay(&status(ConnPhase::Disconnected), false, vi).unwrap();
        assert_eq!((o.title, o.tone), (Str::Connecting, Tone::Running));
        let mut s = status(ConnPhase::Connecting { attempt: 1 });
        s.shown = Some(Str::Connecting);
        assert_eq!(overlay(&s, false, vi).unwrap().title, Str::Connecting);
        let mut s = status(ConnPhase::Reconnecting {
            attempt: 2,
            retry_at_ms: 9,
        });
        s.shown = Some(Str::Reconnecting);
        s.reason = Some("relay closed".into());
        let o = overlay(&s, false, vi).unwrap();
        assert_eq!((o.title, o.tone), (Str::Reconnecting, Tone::Running));
        assert_eq!(o.details, vec!["relay closed".to_string()]);
        // a retry in flight still says reconnecting
        let mut s = status(ConnPhase::Connecting { attempt: 3 });
        s.shown = Some(Str::Reconnecting);
        assert_eq!(overlay(&s, false, vi).unwrap().title, Str::Reconnecting);
        let mut s = status(ConnPhase::Offline);
        s.shown = Some(Str::Offline);
        s.reason = Some("x".into());
        let o = overlay(&s, false, vi).unwrap();
        assert_eq!(
            (o.title, o.tone, o.details.len()),
            (Str::Offline, Tone::Muted, 0)
        );
        let o = overlay(&status(ConnPhase::Ended), false, vi).unwrap();
        assert_eq!((o.title, o.tone), (Str::RemoteEnded, Tone::Muted));
        // errors win over the phase
        let mut s = status(ConnPhase::Ended);
        s.error = Some(SessionError::FingerprintMismatch {
            expected: "a".into(),
            got: "b".into(),
        });
        let o = overlay(&s, false, vi).unwrap();
        assert_eq!((o.title, o.tone), (Str::FingerprintMismatch, Tone::Error));
        s.error = Some(SessionError::NeedsPairing("invitation expired".into()));
        let o = overlay(&s, false, vi).unwrap();
        assert_eq!((o.title, o.tone), (Str::NeedsPairing, Tone::Error));
        assert_eq!(o.details, vec!["invitation expired".to_string()]);
        // connected but a pane cannot attach: shown on THAT pane (not
        // attached), with the reason; an attached sibling shows nothing
        let mut s = status(ConnPhase::Connected);
        s.attach_error = Some("no terminal 4".into());
        let o = overlay(&s, false, vi).unwrap();
        assert_eq!(o.title, Str::RemoteAttachFailed);
        assert_eq!(o.details, vec!["no terminal 4".to_string()]);
        assert_eq!(overlay(&s, true, vi), None);
        // the save error is a detail while the pill shows (never alone)
        s.attach_error = None;
        s.save_error = Some("disk full".into());
        assert_eq!(overlay(&s, false, vi), None);
        s.phase = ConnPhase::Offline;
        let o = overlay(&s, false, vi).unwrap();
        assert_eq!(
            o.details,
            vec!["Không lưu được quyền truy cập: disk full".to_string()]
        );
        // long details are clipped
        s.save_error = None;
        s.attach_error = Some("x".repeat(500));
        let o = overlay(&s, false, vi).unwrap();
        assert_eq!(o.details[0].chars().count(), DETAIL_MAX + 1);
        assert!(o.details[0].ends_with('…'));
    }

    #[test]
    fn smoke_remote_tabs() {
        let summary = smoke().unwrap();
        assert!(summary.contains("split"), "{summary}");
    }
}
