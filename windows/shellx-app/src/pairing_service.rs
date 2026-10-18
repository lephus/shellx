//! GPUI-free driver for `PairingFlow`: turns the flow's actions into blocking
//! shellx-core calls (`Job`s the app runs off the UI thread) and feeds the
//! results back. Each `pair.request` / `pair.poll` job is tagged with a
//! generation that changes on every accepted Start and every Cancel, so a
//! result that belongs to an abandoned attempt (cancel A, start B, A's reply
//! arrives) is dropped before it reaches the flow. On Approved the link is
//! saved to the `LinksStore` (enrolled = false; Task 13 enrolls on connect).
//!
//! The window drives it through `handle(Cmd)` on a background task that owns
//! the service, so both `execute` (core calls) and `finish` (links.json I/O)
//! stay off the UI thread; the UI renders the `Snapshot`s it publishes.
//! Core calls are bounded by shellx-core's HTTP timeouts (connect 10 s,
//! global 20 s per request; `pair.request` and `pair.poll` make one request
//! each), and `execute_caught` turns a panic into an error, so every job
//! delivers a `JobResult`.
#![cfg_attr(not(windows), allow(dead_code))] // the window (cfg(windows)) drives it

use std::collections::HashMap;

use shellx_model::core_api::{CoreCall, CoreErr, PairPoll, PairRequested, pair_poll, pair_request};
use shellx_model::links::{Links, RemoteLink};
use shellx_model::remote_state::{PairAction, PairEvent, PairState, PairingFlow};
use shellx_model::sidebar::Access;

use crate::links_store::LinksStore;

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Job {
    Request {
        generation: u64,
        machine_id: String,
    },
    Poll {
        generation: u64,
        pairing_id: String,
        write_invite_to: String,
    },
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum JobResult {
    Requested {
        generation: u64,
        result: Result<PairRequested, CoreErr>,
    },
    Polled {
        generation: u64,
        pairing_id: String,
        result: Result<PairPoll, CoreErr>,
    },
}

/// Run one job (blocking; call off the UI thread).
pub fn execute(core: &dyn CoreCall, job: &Job) -> JobResult {
    match job {
        Job::Request {
            generation,
            machine_id,
        } => JobResult::Requested {
            generation: *generation,
            result: pair_request(core, machine_id),
        },
        Job::Poll {
            generation,
            pairing_id,
            write_invite_to,
        } => JobResult::Polled {
            generation: *generation,
            pairing_id: pairing_id.clone(),
            result: pair_poll(core, pairing_id, write_invite_to),
        },
    }
}

/// `execute`, with a panic turned into an `internal` error, so the flow
/// always gets its result.
pub fn execute_caught(core: &dyn CoreCall, job: &Job) -> JobResult {
    std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| execute(core, job))).unwrap_or_else(
        |_| {
            let err = CoreErr::new("internal", "shellx-core call panicked");
            match job {
                Job::Request { generation, .. } => JobResult::Requested {
                    generation: *generation,
                    result: Err(err),
                },
                Job::Poll {
                    generation,
                    pairing_id,
                    ..
                } => JobResult::Polled {
                    generation: *generation,
                    pairing_id: pairing_id.clone(),
                    result: Err(err),
                },
            }
        },
    )
}

/// Longest id part of `invite-<id>.uri` that fits core's 64-byte limit.
const INVITE_ID_MAX: usize = 64 - "invite-".len() - ".uri".len();

/// FNV-1a 64 (no crypto needed: it only keeps sanitized names apart).
fn fnv1a64(s: &str) -> u64 {
    let mut h: u64 = 0xcbf2_9ce4_8422_2325;
    for b in s.bytes() {
        h ^= u64::from(b);
        h = h.wrapping_mul(0x0000_0100_0000_01b3);
    }
    h
}

/// shellx-core accepts only bare names of `[a-z0-9._-]`, at most 64 bytes,
/// starting with a lowercase letter or digit. Machine ids are mapped into
/// that set (lowercased, anything else becomes `-`). When that changed or
/// truncated the id, 8 hex of an FNV-1a hash of the original id are
/// appended, so two machines never share an invite file (it holds the PSK).
pub fn invite_file_name(machine_id: &str) -> String {
    let mut id: String = machine_id
        .chars()
        .map(|c| {
            let c = c.to_ascii_lowercase();
            if c.is_ascii_lowercase() || c.is_ascii_digit() || matches!(c, '.' | '_' | '-') {
                c
            } else {
                '-'
            }
        })
        .collect();
    if id == machine_id && id.len() <= INVITE_ID_MAX {
        return format!("invite-{id}.uri");
    }
    let hash = fnv1a64(machine_id) >> 32;
    id.truncate(INVITE_ID_MAX - 9); // ASCII only: byte truncation is safe
    format!("invite-{id}-{hash:08x}.uri")
}

/// What the window sends the background task that owns the service.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Cmd {
    /// Read links.json (startup).
    LoadLinks,
    /// Cancel any current attempt, then request access to this machine.
    /// `ui_seq` is echoed in the snapshot (see `Snapshot::ui_seq`).
    Start {
        machine_id: String,
        machine_name: String,
        ui_seq: u64,
    },
    /// Stop waiting (the panel closed).
    Cancel { ui_seq: u64 },
    /// A timer for `tick_at() == at_ms` fired.
    Tick { at_ms: u64 },
    /// A job finished.
    Done(JobResult),
}

/// What the window renders.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Snapshot {
    pub state: PairState,
    /// (machine id, machine name) of the current attempt.
    pub target: Option<(String, String)>,
    /// This PC's device fingerprint from `pair.request` (shown so the user can
    /// compare it with the approval screen on the Mac).
    pub fingerprint: Option<String>,
    pub save_error: Option<String>,
    pub links: Links,
    pub pending: HashMap<String, String>,
    /// The `ui_seq` of the last Start / Cancel handled: the window ignores
    /// snapshots older than its last command.
    pub ui_seq: u64,
}

impl Default for Snapshot {
    fn default() -> Self {
        Snapshot {
            state: PairState::Idle,
            target: None,
            fingerprint: None,
            save_error: None,
            links: Links::default(),
            pending: HashMap::new(),
            ui_seq: 0,
        }
    }
}

impl Snapshot {
    /// Sidebar access for a machine: link -> Granted, waiting -> Pending.
    pub fn access_for(&self, machine_id: &str) -> Access {
        self.links.access_for(machine_id, &self.pending)
    }
}

pub struct PairingService {
    store: LinksStore,
    flow: PairingFlow,
    generation: u64,
    /// (machine id, machine name) of the current attempt.
    target: Option<(String, String)>,
    tick_at: Option<u64>,
    saved_generation: Option<u64>,
    save_error: Option<String>,
    fingerprint: Option<String>,
    links: Links,
    ui_seq: u64,
}

impl PairingService {
    pub fn new(store: LinksStore) -> PairingService {
        PairingService {
            store,
            flow: PairingFlow::new(),
            generation: 0,
            target: None,
            tick_at: None,
            saved_generation: None,
            save_error: None,
            fingerprint: None,
            links: Links::default(),
            ui_seq: 0,
        }
    }

    /// Links as last loaded or saved.
    #[allow(dead_code)] // tests; the window reads `snapshot()`
    pub fn links(&self) -> &Links {
        &self.links
    }

    /// Reads links.json (a corrupt file is moved aside by the store).
    pub fn load_links(&mut self) {
        match self.store.load() {
            Ok(links) => self.links = links,
            Err(e) => eprintln!("shellx: could not read the remote links: {e}"),
        }
    }

    #[allow(dead_code)] // tests; the window reads `snapshot()`
    pub fn fingerprint(&self) -> Option<&str> {
        self.fingerprint.as_deref()
    }

    /// One window command; returns the jobs to run off this thread.
    pub fn handle(&mut self, cmd: Cmd, now_ms: u64) -> Vec<Job> {
        match cmd {
            Cmd::LoadLinks => {
                self.load_links();
                Vec::new()
            }
            Cmd::Start {
                machine_id,
                machine_name,
                ui_seq,
            } => {
                self.ui_seq = ui_seq;
                let mut jobs = self.cancel(now_ms);
                jobs.extend(self.start(&machine_id, &machine_name, now_ms));
                jobs
            }
            Cmd::Cancel { ui_seq } => {
                self.ui_seq = ui_seq;
                self.cancel(now_ms)
            }
            // Never earlier than asked, so the flow sees the tick as due.
            Cmd::Tick { at_ms } => self.tick(now_ms.max(at_ms)),
            Cmd::Done(result) => self.finish(result, now_ms),
        }
    }

    pub fn snapshot(&self) -> Snapshot {
        Snapshot {
            state: self.flow.state().clone(),
            target: self.target.clone(),
            fingerprint: self.fingerprint.clone(),
            save_error: self.save_error.clone(),
            links: self.links.clone(),
            pending: self.pending(),
            ui_seq: self.ui_seq,
        }
    }

    #[allow(dead_code)] // tests; the window reads `snapshot()`
    pub fn state(&self) -> &PairState {
        self.flow.state()
    }

    /// When the app should call `tick` next (ms, same clock as `now_ms`).
    pub fn tick_at(&self) -> Option<u64> {
        self.tick_at
    }

    /// Set when the link could not be written after an approval.
    #[allow(dead_code)] // tests; the window reads `snapshot()`
    pub fn save_error(&self) -> Option<&str> {
        self.save_error.as_deref()
    }

    pub fn target_machine_id(&self) -> Option<&str> {
        self.target.as_ref().map(|(id, _)| id.as_str())
    }

    /// For `Links::access_for`: the machine being waited on and its code.
    pub fn pending(&self) -> HashMap<String, String> {
        let mut m = HashMap::new();
        if let (PairState::Waiting { code, .. }, Some((id, _))) = (self.flow.state(), &self.target)
        {
            m.insert(id.clone(), code.clone());
        }
        m
    }

    /// Ignored while a request is already running.
    pub fn start(&mut self, machine_id: &str, machine_name: &str, now_ms: u64) -> Vec<Job> {
        let actions = self.flow.on(
            PairEvent::Start {
                to_machine_id: machine_id.to_string(),
            },
            now_ms,
        );
        if actions.is_empty() {
            return Vec::new();
        }
        self.generation += 1;
        self.target = Some((machine_id.to_string(), machine_name.to_string()));
        self.save_error = None;
        self.fingerprint = None;
        self.tick_at = None;
        self.jobs(actions)
    }

    /// Stops polling; results of jobs already in flight are dropped.
    pub fn cancel(&mut self, now_ms: u64) -> Vec<Job> {
        let actions = self.flow.on(PairEvent::Cancel, now_ms);
        if !actions.is_empty() {
            self.generation += 1;
            self.target = None;
            self.fingerprint = None;
            self.tick_at = None;
        }
        self.jobs(actions)
    }

    pub fn tick(&mut self, now_ms: u64) -> Vec<Job> {
        match self.tick_at {
            Some(at) if now_ms >= at => {}
            _ => return Vec::new(),
        }
        self.tick_at = None;
        let actions = self.flow.on(PairEvent::Tick, now_ms);
        self.jobs(actions)
    }

    pub fn finish(&mut self, result: JobResult, now_ms: u64) -> Vec<Job> {
        let actions = match result {
            JobResult::Requested { generation, result } => {
                if generation != self.generation {
                    return Vec::new();
                }
                if let Ok(req) = &result
                    && *self.flow.state() == PairState::Requesting
                {
                    self.fingerprint = Some(req.fingerprint.clone());
                }
                self.flow.on(PairEvent::Requested(result), now_ms)
            }
            JobResult::Polled {
                generation,
                pairing_id,
                result,
            } => {
                if generation != self.generation {
                    return Vec::new();
                }
                self.flow
                    .on(PairEvent::Polled { pairing_id, result }, now_ms)
            }
        };
        let jobs = self.jobs(actions);
        self.save_if_approved();
        jobs
    }

    fn jobs(&mut self, actions: Vec<PairAction>) -> Vec<Job> {
        let mut jobs = Vec::new();
        for a in actions {
            match a {
                PairAction::CallPairRequest { to } => jobs.push(Job::Request {
                    generation: self.generation,
                    machine_id: to,
                }),
                PairAction::CallPairPoll { pairing_id } => {
                    let machine_id = self.target_machine_id().unwrap_or_default();
                    jobs.push(Job::Poll {
                        generation: self.generation,
                        write_invite_to: invite_file_name(machine_id),
                        pairing_id,
                    });
                }
                PairAction::ScheduleTick { at_ms } => self.tick_at = Some(at_ms),
                PairAction::Done => self.tick_at = None,
            }
        }
        jobs
    }

    fn save_if_approved(&mut self) {
        let PairState::Approved {
            invite_path,
            relay_route,
            relay_slot,
            daemon_fingerprint,
        } = self.flow.state()
        else {
            return;
        };
        if self.saved_generation == Some(self.generation) {
            return;
        }
        let Some((machine_id, machine_name)) = self.target.clone() else {
            return;
        };
        let link = RemoteLink {
            machine_id,
            machine_name,
            relay_route: relay_route.clone(),
            relay_slot: relay_slot.clone(),
            invite_path: Some(invite_path.clone()),
            daemon_fingerprint: daemon_fingerprint.clone(),
            enrolled: false,
        };
        self.saved_generation = Some(self.generation);
        let saved = self.store.load().and_then(|mut links| {
            links.upsert(link);
            self.store.save(&links).map(|()| links)
        });
        match saved {
            Ok(links) => self.links = links,
            Err(e) => self.save_error = Some(e.to_string()),
        }
    }

    /// Run the flow to a final state on the calling thread (smoke and tests).
    /// `now` is the clock in ms, `sleep` waits that many ms.
    pub fn run_blocking(
        &mut self,
        core: &dyn CoreCall,
        machine_id: &str,
        machine_name: &str,
        mut now: impl FnMut() -> u64,
        mut sleep: impl FnMut(u64),
    ) -> PairState {
        let mut queue = self.start(machine_id, machine_name, now());
        for _ in 0..10_000 {
            while let Some(job) = queue.pop() {
                let r = execute(core, &job);
                queue.extend(self.finish(r, now()));
            }
            if !matches!(
                self.flow.state(),
                PairState::Requesting | PairState::Waiting { .. }
            ) {
                break;
            }
            let Some(at) = self.tick_at else { break };
            let t = now();
            if at > t {
                sleep(at - t);
            }
            queue.extend(self.tick(now()));
        }
        self.flow.state().clone()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;
    use shellx_model::core_api::FakeCore;
    use std::cell::Cell;
    use std::path::PathBuf;

    fn tmp(name: &str) -> PathBuf {
        let d = std::env::temp_dir().join(format!("shellx-pair-{name}-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&d);
        d
    }

    fn requested(id: &str, code: &str) -> Result<serde_json::Value, CoreErr> {
        Ok(json!({"pairing_id": id, "code": code, "fingerprint": "ab"}))
    }

    fn approved() -> Result<serde_json::Value, CoreErr> {
        Ok(json!({
            "status": "approved", "invite_path": "/core/tickets/invite-m1.uri",
            "relay_route": "relay+wss://r/v2/relay", "relay_slot": "s1",
            "daemon_fingerprint": "dd"
        }))
    }

    fn run(core: &FakeCore, store: LinksStore) -> (PairState, PairingService) {
        let clock = Cell::new(1_000u64);
        let mut svc = PairingService::new(store);
        let st = svc.run_blocking(
            core,
            "m1",
            "Mac của Phú",
            || clock.get(),
            |ms| clock.set(clock.get() + ms),
        );
        (st, svc)
    }

    #[test]
    fn approved_after_pending_saves_link() {
        let dir = tmp("ok");
        let store = LinksStore::new(dir.join("links.json"));
        let core = FakeCore::new();
        core.on("pair.request", requested("p1", "482913"));
        core.on_seq(
            "pair.poll",
            vec![
                Ok(json!({"status": "pending"})),
                Ok(json!({"status": "pending"})),
                approved(),
            ],
        );
        let (st, svc) = run(&core, store);
        assert!(matches!(st, PairState::Approved { .. }), "{st:?}");
        assert!(svc.save_error().is_none());
        let links = LinksStore::new(dir.join("links.json")).load().unwrap();
        let l = links.get("m1").unwrap();
        assert_eq!(l.machine_name, "Mac của Phú");
        assert_eq!(
            l.invite_path.as_deref(),
            Some("/core/tickets/invite-m1.uri")
        );
        assert_eq!(l.relay_route, "relay+wss://r/v2/relay");
        assert_eq!(l.relay_slot, "s1");
        assert_eq!(l.daemon_fingerprint, "dd");
        assert!(!l.enrolled);
        let calls = core.calls();
        assert_eq!(calls.len(), 4);
        assert_eq!(
            calls[0],
            ("pair.request".into(), json!({"to_machine_id": "m1"}))
        );
        assert_eq!(
            calls[1].1,
            json!({"pairing_id": "p1", "write_invite_to": "invite-m1.uri"})
        );
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn denied_and_expired_save_nothing() {
        for status in ["denied", "expired"] {
            let dir = tmp(status);
            let core = FakeCore::new();
            core.on("pair.request", requested("p1", "111111"));
            core.on("pair.poll", Ok(json!({"status": status})));
            let (st, _) = run(&core, LinksStore::new(dir.join("links.json")));
            assert!(
                matches!(st, PairState::Denied | PairState::Expired),
                "{st:?}"
            );
            assert!(!dir.join("links.json").exists());
            let _ = std::fs::remove_dir_all(&dir);
        }
    }

    #[test]
    fn request_failure_is_failed_without_link() {
        let dir = tmp("fail");
        let core = FakeCore::new();
        core.on("pair.request", Err(CoreErr::new("not_logged_in", "x")));
        let (st, _) = run(&core, LinksStore::new(dir.join("links.json")));
        assert!(matches!(st, PairState::Failed(_)));
        assert!(!dir.join("links.json").exists());
    }

    #[test]
    fn stale_request_after_cancel_and_restart_is_ignored() {
        let dir = tmp("stale");
        let mut svc = PairingService::new(LinksStore::new(dir.join("links.json")));
        let a = svc.start("mA", "A", 0);
        let Job::Request { .. } = &a[0] else { panic!() };
        assert!(svc.cancel(10).is_empty());
        let b = svc.start("mB", "B", 20);
        let Job::Request { machine_id, .. } = &b[0] else {
            panic!()
        };
        assert_eq!(machine_id, "mB");
        // A's reply arrives first: ignored
        let late_a = execute_fake(&a[0], "pA", "111111");
        assert!(svc.finish(late_a, 30).is_empty());
        assert_eq!(svc.state(), &PairState::Requesting);
        assert!(svc.pending().is_empty());
        // B's reply is adopted
        let rb = execute_fake(&b[0], "pB", "222222");
        svc.finish(rb, 40);
        assert_eq!(svc.pending().get("mB").map(String::as_str), Some("222222"));
        assert!(svc.tick_at().is_some());
    }

    fn execute_fake(job: &Job, id: &str, code: &str) -> JobResult {
        let core = FakeCore::new();
        core.on("pair.request", requested(id, code));
        execute(&core, job)
    }

    #[test]
    fn stale_poll_after_cancel_is_ignored_and_start_while_waiting_is_ignored() {
        let dir = tmp("stalepoll");
        let mut svc = PairingService::new(LinksStore::new(dir.join("links.json")));
        let a = svc.start("m1", "A", 0);
        svc.finish(execute_fake(&a[0], "p1", "123456"), 0);
        assert!(svc.start("m2", "B", 1).is_empty());
        assert_eq!(svc.target_machine_id(), Some("m1"));
        let polls = svc.tick(2_000);
        let core = FakeCore::new();
        core.on("pair.poll", approved());
        let late = execute(&core, &polls[0]);
        svc.cancel(2_100);
        assert!(svc.finish(late, 2_200).is_empty());
        assert_eq!(svc.state(), &PairState::Idle);
        assert!(!dir.join("links.json").exists());
    }

    #[test]
    fn smoke_pairing_flow() {
        crate::smoke::pairing_flow().unwrap();
    }

    fn core_ok(n: &str) -> bool {
        n.len() <= 64
            && n.bytes()
                .all(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || b"._-".contains(&c))
            && n.as_bytes()[0].is_ascii_lowercase()
    }

    #[test]
    fn invite_file_name_fits_core_rules() {
        assert_eq!(invite_file_name("m1"), "invite-m1.uri");
        let uuid = "0b9c6f1e-5d2a-4c3b-9a8e-7f6d5c4b3a21";
        assert_eq!(invite_file_name(uuid), format!("invite-{uuid}.uri"));
        let n = invite_file_name(&"Ab/C ".repeat(40));
        assert!(core_ok(&n), "{n}");
    }

    #[test]
    fn invite_file_name_never_shared_after_sanitizing() {
        let names = [
            invite_file_name("m1"),
            invite_file_name("M1"),
            invite_file_name("m/1"),
            invite_file_name("m:1"),
            invite_file_name("máy1"),
            invite_file_name(&format!("{}a", "x".repeat(60))),
            invite_file_name(&format!("{}b", "x".repeat(60))),
        ];
        for n in &names {
            assert!(core_ok(n), "{n}");
        }
        let set: std::collections::HashSet<_> = names.iter().collect();
        assert_eq!(set.len(), names.len(), "{names:?}");
        // stable for the same id
        assert_eq!(invite_file_name("M1"), names[1]);
        assert!(names[1].starts_with("invite-m1-") && names[1].ends_with(".uri"));
    }

    struct PanicCore;
    impl CoreCall for PanicCore {
        fn call(&self, _: &str, _: serde_json::Value) -> Result<serde_json::Value, CoreErr> {
            panic!("boom")
        }
    }

    #[test]
    fn execute_caught_always_delivers_a_result() {
        let job = Job::Poll {
            generation: 3,
            pairing_id: "p1".into(),
            write_invite_to: "invite-m1.uri".into(),
        };
        match execute_caught(&PanicCore, &job) {
            JobResult::Polled {
                generation,
                pairing_id,
                result: Err(e),
            } => {
                assert_eq!((generation, pairing_id.as_str()), (3, "p1"));
                assert_eq!(e.code, "internal");
            }
            other => panic!("{other:?}"),
        }
    }

    /// The window's loop, synchronously: handle a command, run its jobs and
    /// feed their results back until nothing is left.
    fn drive(svc: &mut PairingService, core: &FakeCore, cmd: Cmd, now: u64) {
        let mut queue = svc.handle(cmd, now);
        while let Some(job) = queue.pop() {
            let r = execute_caught(core, &job);
            queue.extend(svc.handle(Cmd::Done(r), now));
        }
    }

    #[test]
    fn commands_drive_the_flow_and_snapshots_carry_what_the_panel_shows() {
        let dir = tmp("cmd");
        let mut svc = PairingService::new(LinksStore::new(dir.join("links.json")));
        let core = FakeCore::new();
        core.on(
            "pair.request",
            Ok(json!({"pairing_id": "p1", "code": "482913", "fingerprint": "0123456789abcdef"})),
        );
        drive(&mut svc, &core, Cmd::LoadLinks, 0);
        drive(
            &mut svc,
            &core,
            Cmd::Start {
                machine_id: "m1".into(),
                machine_name: "Mac".into(),
                ui_seq: 1,
            },
            0,
        );
        let snap = svc.snapshot();
        assert!(matches!(snap.state, PairState::Waiting { .. }), "{snap:?}");
        assert_eq!(snap.ui_seq, 1);
        assert_eq!(snap.fingerprint.as_deref(), Some("0123456789abcdef"));
        assert_eq!(snap.target, Some(("m1".into(), "Mac".into())));
        assert_eq!(
            snap.access_for("m1"),
            Access::Pending {
                code: "482913".into()
            }
        );
        let at = svc.tick_at().unwrap();
        // a timer that fires a little early still counts as the tick
        core.on("pair.poll", approved());
        drive(&mut svc, &core, Cmd::Tick { at_ms: at }, at - 1);
        let snap = svc.snapshot();
        assert!(matches!(snap.state, PairState::Approved { .. }), "{snap:?}");
        assert_eq!(snap.access_for("m1"), Access::Granted);
        assert!(snap.save_error.is_none());
        // a fresh service reads the saved link
        let mut again = PairingService::new(LinksStore::new(dir.join("links.json")));
        again.handle(Cmd::LoadLinks, 0);
        assert!(again.links().get("m1").is_some());
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn start_for_another_machine_cancels_the_current_one() {
        let dir = tmp("switch");
        let mut svc = PairingService::new(LinksStore::new(dir.join("links.json")));
        let start = |id: &str, seq| Cmd::Start {
            machine_id: id.into(),
            machine_name: id.into(),
            ui_seq: seq,
        };
        let a = svc.handle(start("mA", 1), 0);
        let b = svc.handle(start("mB", 2), 10);
        assert_eq!(b.len(), 1);
        // A's reply arrives after B started: ignored
        assert!(
            svc.handle(Cmd::Done(execute_fake(&a[0], "pA", "111111")), 20)
                .is_empty()
        );
        assert_eq!(svc.state(), &PairState::Requesting);
        svc.handle(Cmd::Done(execute_fake(&b[0], "pB", "222222")), 30);
        let snap = svc.snapshot();
        assert_eq!(snap.target.as_ref().map(|t| t.0.as_str()), Some("mB"));
        assert_eq!(snap.pending.get("mB").map(String::as_str), Some("222222"));
        assert!(!snap.pending.contains_key("mA"));
        assert!(svc.handle(Cmd::Cancel { ui_seq: 3 }, 40).is_empty());
        assert_eq!(svc.snapshot().state, PairState::Idle);
        assert_eq!(svc.snapshot().ui_seq, 3);
        assert!(svc.snapshot().fingerprint.is_none());
    }

    #[test]
    fn save_failure_after_approval_is_reported() {
        let mut svc = PairingService::new(LinksStore::unavailable("LOCALAPPDATA is not set"));
        let core = FakeCore::new();
        core.on("pair.request", requested("p1", "123456"));
        core.on("pair.poll", approved());
        drive(
            &mut svc,
            &core,
            Cmd::Start {
                machine_id: "m1".into(),
                machine_name: "Mac".into(),
                ui_seq: 1,
            },
            0,
        );
        let at = svc.tick_at().unwrap();
        drive(&mut svc, &core, Cmd::Tick { at_ms: at }, at);
        let snap = svc.snapshot();
        assert!(matches!(snap.state, PairState::Approved { .. }));
        assert_eq!(snap.save_error.as_deref(), Some("LOCALAPPDATA is not set"));
        assert_eq!(snap.access_for("m1"), Access::None);
    }

    #[test]
    fn corrupt_links_file_is_moved_aside_on_load() {
        let dir = tmp("corrupt");
        std::fs::create_dir_all(&dir).unwrap();
        std::fs::write(dir.join("links.json"), "{not json").unwrap();
        let mut svc = PairingService::new(LinksStore::new(dir.join("links.json")));
        svc.handle(Cmd::LoadLinks, 0);
        assert!(svc.links().links.is_empty());
        assert!(!dir.join("links.json").exists());
        let _ = std::fs::remove_dir_all(&dir);
    }
}
