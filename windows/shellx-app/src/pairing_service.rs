//! GPUI-free driver for `PairingFlow`: turns the flow's actions into blocking
//! shellx-core calls (`Job`s the app runs off the UI thread) and feeds the
//! results back. Each `pair.request` / `pair.poll` job is tagged with a
//! generation that changes on every accepted Start and every Cancel, so a
//! result that belongs to an abandoned attempt (cancel A, start B, A's reply
//! arrives) is dropped before it reaches the flow. On Approved the link is
//! saved to the `LinksStore` (enrolled = false; Task 13 enrolls on connect).
#![allow(dead_code)] // wired by the pairing UI (Task 12b)

use std::collections::HashMap;

use shellx_model::core_api::{CoreCall, CoreErr, PairPoll, PairRequested, pair_poll, pair_request};
use shellx_model::links::RemoteLink;
use shellx_model::remote_state::{PairAction, PairEvent, PairState, PairingFlow};

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

/// shellx-core accepts only bare names of `[a-z0-9._-]`, at most 64 bytes,
/// starting with a lowercase letter or digit. Machine ids are mapped into
/// that set (lowercased, anything else becomes `-`).
pub fn invite_file_name(machine_id: &str) -> String {
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
    id.truncate(64 - "invite-".len() - ".uri".len());
    format!("invite-{id}.uri")
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
        }
    }

    pub fn state(&self) -> &PairState {
        self.flow.state()
    }

    /// When the app should call `tick` next (ms, same clock as `now_ms`).
    pub fn tick_at(&self) -> Option<u64> {
        self.tick_at
    }

    /// Set when the link could not be written after an approval.
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
        self.tick_at = None;
        self.jobs(actions)
    }

    /// Stops polling; results of jobs already in flight are dropped.
    pub fn cancel(&mut self, now_ms: u64) -> Vec<Job> {
        let actions = self.flow.on(PairEvent::Cancel, now_ms);
        if !actions.is_empty() {
            self.generation += 1;
            self.target = None;
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
                self.flow.on(PairEvent::Polled { pairing_id, result }, now_ms)
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
            self.store.save(&links)
        });
        if let Err(e) = saved {
            self.save_error = Some(e.to_string());
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
            vec![Ok(json!({"status": "pending"})), Ok(json!({"status": "pending"})), approved()],
        );
        let (st, svc) = run(&core, store);
        assert!(matches!(st, PairState::Approved { .. }), "{st:?}");
        assert!(svc.save_error().is_none());
        let links = LinksStore::new(dir.join("links.json")).load().unwrap();
        let l = links.get("m1").unwrap();
        assert_eq!(l.machine_name, "Mac của Phú");
        assert_eq!(l.invite_path.as_deref(), Some("/core/tickets/invite-m1.uri"));
        assert_eq!(l.relay_route, "relay+wss://r/v2/relay");
        assert_eq!(l.relay_slot, "s1");
        assert_eq!(l.daemon_fingerprint, "dd");
        assert!(!l.enrolled);
        let calls = core.calls();
        assert_eq!(calls.len(), 4);
        assert_eq!(calls[0], ("pair.request".into(), json!({"to_machine_id": "m1"})));
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
            assert!(matches!(st, PairState::Denied | PairState::Expired), "{st:?}");
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
        let Job::Request { machine_id, .. } = &b[0] else { panic!() };
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

    #[test]
    fn invite_file_name_fits_core_rules() {
        assert_eq!(invite_file_name("m1"), "invite-m1.uri");
        let n = invite_file_name(&"Ab/C ".repeat(40));
        assert!(n.len() <= 64, "{n}");
        assert!(n.bytes().all(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || b"._-".contains(&c)));
    }
}
