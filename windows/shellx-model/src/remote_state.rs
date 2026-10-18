//! Pairing and connection state machines. Pure and event driven: the app
//! executes the returned actions off the UI thread and feeds results back as
//! events. Time is passed in (`now_ms`); there is no clock or thread here.

use crate::core_api::{CoreErr, PairPoll, PairRequested, PairStatus, TicketFile};
use crate::strings::Str;

pub const POLL_INTERVAL_MS: u64 = 2_000;
pub const PAIRING_TIMEOUT_MS: u64 = 300_000;
pub const BACKOFF_CAP_MS: u64 = 30_000;

// ---------------------------------------------------------------- pairing

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum PairState {
    Idle,
    Requesting,
    Waiting {
        pairing_id: String,
        code: String,
        started_ms: u64,
    },
    Approved {
        invite_path: String,
        relay_route: String,
        relay_slot: String,
        daemon_fingerprint: String,
    },
    Denied,
    Expired,
    Failed(CoreErr),
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum PairEvent {
    Start { to_machine_id: String },
    Requested(Result<PairRequested, CoreErr>),
    Tick,
    Polled(Result<PairPoll, CoreErr>),
    Cancel,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum PairAction {
    CallPairRequest { to: String },
    CallPairPoll { pairing_id: String },
    ScheduleTick { at_ms: u64 },
    Done,
}

#[derive(Debug)]
pub struct PairingFlow {
    state: PairState,
}

impl Default for PairingFlow {
    fn default() -> Self {
        PairingFlow::new()
    }
}

impl PairingFlow {
    pub fn new() -> PairingFlow {
        PairingFlow {
            state: PairState::Idle,
        }
    }

    pub fn state(&self) -> &PairState {
        &self.state
    }

    pub fn on(&mut self, ev: PairEvent, now_ms: u64) -> Vec<PairAction> {
        match ev {
            PairEvent::Start { to_machine_id } => match self.state {
                PairState::Idle
                | PairState::Approved { .. }
                | PairState::Denied
                | PairState::Expired
                | PairState::Failed(_) => {
                    self.state = PairState::Requesting;
                    vec![PairAction::CallPairRequest { to: to_machine_id }]
                }
                PairState::Requesting | PairState::Waiting { .. } => Vec::new(),
            },
            PairEvent::Requested(r) => {
                if self.state != PairState::Requesting {
                    return Vec::new();
                }
                match r {
                    Ok(req) => {
                        self.state = PairState::Waiting {
                            pairing_id: req.pairing_id,
                            code: req.code,
                            started_ms: now_ms,
                        };
                        vec![PairAction::ScheduleTick {
                            at_ms: now_ms + POLL_INTERVAL_MS,
                        }]
                    }
                    Err(e) => {
                        self.state = PairState::Failed(e);
                        vec![PairAction::Done]
                    }
                }
            }
            PairEvent::Tick => {
                let PairState::Waiting {
                    pairing_id,
                    started_ms,
                    ..
                } = &self.state
                else {
                    return Vec::new();
                };
                if now_ms >= started_ms + PAIRING_TIMEOUT_MS {
                    self.state = PairState::Expired;
                    return vec![PairAction::Done];
                }
                vec![PairAction::CallPairPoll {
                    pairing_id: pairing_id.clone(),
                }]
            }
            PairEvent::Polled(r) => {
                let PairState::Waiting { started_ms, .. } = &self.state else {
                    return Vec::new();
                };
                let deadline = started_ms + PAIRING_TIMEOUT_MS;
                match r {
                    Ok(p) => match p.status {
                        PairStatus::Approved => {
                            self.state = match (
                                p.invite_path,
                                p.relay_route,
                                p.relay_slot,
                                p.daemon_fingerprint,
                            ) {
                                (Some(a), Some(b), Some(c), Some(d)) => PairState::Approved {
                                    invite_path: a,
                                    relay_route: b,
                                    relay_slot: c,
                                    daemon_fingerprint: d,
                                },
                                _ => PairState::Failed(CoreErr::new(
                                    "bad_response",
                                    "approved without invite details",
                                )),
                            };
                            vec![PairAction::Done]
                        }
                        PairStatus::Denied => {
                            self.state = PairState::Denied;
                            vec![PairAction::Done]
                        }
                        PairStatus::Expired => {
                            self.state = PairState::Expired;
                            vec![PairAction::Done]
                        }
                        PairStatus::Pending => self.keep_waiting(now_ms, deadline),
                    },
                    // transient failure: keep waiting until the deadline
                    Err(_) => self.keep_waiting(now_ms, deadline),
                }
            }
            PairEvent::Cancel => match self.state {
                PairState::Requesting | PairState::Waiting { .. } => {
                    self.state = PairState::Idle;
                    vec![PairAction::Done]
                }
                _ => Vec::new(),
            },
        }
    }

    fn keep_waiting(&mut self, now_ms: u64, deadline: u64) -> Vec<PairAction> {
        if now_ms >= deadline {
            self.state = PairState::Expired;
            return vec![PairAction::Done];
        }
        vec![PairAction::ScheduleTick {
            at_ms: (now_ms + POLL_INTERVAL_MS).min(deadline),
        }]
    }
}

// ------------------------------------------------------------- connection

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum ConnPhase {
    Disconnected,
    Connecting { attempt: u32 },
    Connected,
    Reconnecting { attempt: u32, retry_at_ms: u64 },
    Offline,
    Ended,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum ConnEvent {
    Open,
    Connected,
    Disconnected { reason: String },
    TicketMinted(Result<TicketFile, CoreErr>),
    Tick,
    MachineOffline,
    MachineOnline,
    RemoteEnded,
    Close,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum ConnAction {
    MintTicket,
    Connect { ticket_path: String },
    ScheduleTick { at_ms: u64 },
    ShowStatus(Str),
    Drop,
}

/// Delay after the n-th consecutive failure (n >= 1): 1, 2, 4, 8, 16, 30, 30 ... s.
pub fn backoff_ms(failures: u32) -> u64 {
    let n = failures.max(1);
    (1_000u64 << (n - 1).min(5)).min(BACKOFF_CAP_MS)
}

#[derive(Debug)]
pub struct ConnState {
    phase: ConnPhase,
    failures: u32,
    machine_online: bool,
    last_reason: Option<String>,
}

impl Default for ConnState {
    fn default() -> Self {
        ConnState::new()
    }
}

impl ConnState {
    pub fn new() -> ConnState {
        ConnState {
            phase: ConnPhase::Disconnected,
            failures: 0,
            machine_online: true,
            last_reason: None,
        }
    }

    pub fn phase(&self) -> &ConnPhase {
        &self.phase
    }

    pub fn last_reason(&self) -> Option<&str> {
        self.last_reason.as_deref()
    }

    pub fn accepts_input(&self) -> bool {
        self.phase == ConnPhase::Connected
    }

    pub fn on(&mut self, ev: ConnEvent, now_ms: u64) -> Vec<ConnAction> {
        match ev {
            ConnEvent::Open => {
                if self.phase != ConnPhase::Disconnected {
                    return Vec::new();
                }
                if !self.machine_online {
                    self.phase = ConnPhase::Offline;
                    return vec![ConnAction::ShowStatus(Str::Offline)];
                }
                self.start_attempt(1, true)
            }
            ConnEvent::TicketMinted(r) => {
                if !matches!(self.phase, ConnPhase::Connecting { .. }) {
                    return Vec::new();
                }
                match r {
                    Ok(t) => vec![ConnAction::Connect {
                        ticket_path: t.path,
                    }],
                    Err(e) => self.fail(now_ms, format!("{e}")),
                }
            }
            ConnEvent::Connected => {
                if matches!(self.phase, ConnPhase::Connecting { .. }) {
                    self.phase = ConnPhase::Connected;
                    self.failures = 0;
                    Vec::new()
                } else {
                    // a link that finished opening after we gave up on it
                    vec![ConnAction::Drop]
                }
            }
            ConnEvent::Disconnected { reason } => match self.phase {
                ConnPhase::Connecting { .. } | ConnPhase::Connected => self.fail(now_ms, reason),
                _ => Vec::new(),
            },
            ConnEvent::Tick => match self.phase {
                ConnPhase::Reconnecting {
                    attempt,
                    retry_at_ms,
                } if now_ms >= retry_at_ms => self.start_attempt(attempt + 1, false),
                _ => Vec::new(),
            },
            ConnEvent::MachineOffline => {
                self.machine_online = false;
                match self.phase {
                    ConnPhase::Connecting { .. } | ConnPhase::Reconnecting { .. } => {
                        self.phase = ConnPhase::Offline;
                        vec![ConnAction::ShowStatus(Str::Offline)]
                    }
                    _ => Vec::new(),
                }
            }
            ConnEvent::MachineOnline => {
                self.machine_online = true;
                if self.phase == ConnPhase::Offline {
                    self.failures = 0;
                    self.start_attempt(1, true)
                } else {
                    Vec::new()
                }
            }
            ConnEvent::RemoteEnded => {
                if self.phase == ConnPhase::Ended {
                    return Vec::new();
                }
                self.phase = ConnPhase::Ended;
                vec![ConnAction::ShowStatus(Str::RemoteEnded), ConnAction::Drop]
            }
            ConnEvent::Close => {
                if self.phase == ConnPhase::Ended {
                    return Vec::new();
                }
                self.phase = ConnPhase::Ended;
                vec![ConnAction::Drop]
            }
        }
    }

    /// Every (re)connect attempt mints a fresh ticket first.
    /// A retry keeps showing "reconnecting"; only a first attempt says "connecting".
    fn start_attempt(&mut self, attempt: u32, announce: bool) -> Vec<ConnAction> {
        self.phase = ConnPhase::Connecting { attempt };
        if announce {
            vec![
                ConnAction::ShowStatus(Str::Connecting),
                ConnAction::MintTicket,
            ]
        } else {
            vec![ConnAction::MintTicket]
        }
    }

    fn fail(&mut self, now_ms: u64, reason: String) -> Vec<ConnAction> {
        self.last_reason = Some(reason);
        if !self.machine_online {
            self.phase = ConnPhase::Offline;
            return vec![ConnAction::ShowStatus(Str::Offline)];
        }
        self.failures = self.failures.saturating_add(1);
        let retry_at_ms = now_ms + backoff_ms(self.failures);
        self.phase = ConnPhase::Reconnecting {
            attempt: self.failures,
            retry_at_ms,
        };
        vec![
            ConnAction::ShowStatus(Str::Reconnecting),
            ConnAction::ScheduleTick { at_ms: retry_at_ms },
        ]
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn ticket(n: u32) -> TicketFile {
        TicketFile {
            path: format!("C:\\t{n}.json"),
            expires_at_unix: 1,
            relay_url: "wss://r".into(),
        }
    }

    fn dis() -> ConnEvent {
        ConnEvent::Disconnected {
            reason: "eof".into(),
        }
    }

    fn sched(a: &[ConnAction]) -> Option<u64> {
        a.iter().find_map(|x| match x {
            ConnAction::ScheduleTick { at_ms } => Some(*at_ms),
            _ => None,
        })
    }

    /// Open + mint ok + connected.
    fn connected(c: &mut ConnState, now: u64) {
        assert_eq!(
            c.on(ConnEvent::Open, now),
            vec![
                ConnAction::ShowStatus(Str::Connecting),
                ConnAction::MintTicket
            ]
        );
        assert_eq!(
            c.on(ConnEvent::TicketMinted(Ok(ticket(0))), now),
            vec![ConnAction::Connect {
                ticket_path: "C:\\t0.json".into()
            }]
        );
        assert!(c.on(ConnEvent::Connected, now).is_empty());
        assert!(c.accepts_input());
    }

    #[test]
    fn backoff_table() {
        let got: Vec<u64> = (1..=8).map(backoff_ms).collect();
        assert_eq!(got, [1000, 2000, 4000, 8000, 16000, 30000, 30000, 30000]);
        assert_eq!(backoff_ms(u32::MAX), 30000);
    }

    #[test]
    fn disconnect_backs_off_and_mints_new_ticket() {
        let mut c = ConnState::new();
        let mut now = 10_000u64;
        c.on(ConnEvent::Open, now);
        let mut paths = Vec::new();
        let mut delays = Vec::new();
        for n in 1..=7u32 {
            // current attempt: ticket minted then connect, then it fails
            let a = c.on(ConnEvent::TicketMinted(Ok(ticket(n))), now);
            let ConnAction::Connect { ticket_path } = &a[0] else {
                panic!("expected Connect, got {a:?}")
            };
            paths.push(ticket_path.clone());
            let a = c.on(dis(), now);
            assert_eq!(a[0], ConnAction::ShowStatus(Str::Reconnecting));
            assert!(!c.accepts_input());
            let at = sched(&a).expect("tick scheduled");
            delays.push(at - now);
            // an early tick does nothing
            assert!(c.on(ConnEvent::Tick, at - 1).is_empty());
            now = at;
            // the tick starts the retry with a freshly minted ticket
            assert_eq!(c.on(ConnEvent::Tick, now), vec![ConnAction::MintTicket]);
            assert_eq!(c.phase(), &ConnPhase::Connecting { attempt: n + 1 });
        }
        assert_eq!(delays, [1000, 2000, 4000, 8000, 16000, 30000, 30000]);
        let mut uniq = paths.clone();
        uniq.dedup();
        assert_eq!(uniq.len(), 7, "every attempt uses its own minted ticket");
    }

    #[test]
    fn backoff_resets_after_connect() {
        let mut c = ConnState::new();
        c.on(ConnEvent::Open, 0);
        // fail three times
        let mut now = 0;
        for n in 1..=3 {
            c.on(ConnEvent::TicketMinted(Ok(ticket(n))), now);
            let a = c.on(dis(), now);
            now = sched(&a).unwrap();
            c.on(ConnEvent::Tick, now);
        }
        c.on(ConnEvent::TicketMinted(Ok(ticket(9))), now);
        c.on(ConnEvent::Connected, now);
        assert!(c.accepts_input());
        let a = c.on(dis(), now + 5);
        assert_eq!(sched(&a), Some(now + 5 + 1000));
    }

    #[test]
    fn ticket_mint_failure_counts_as_failed_attempt() {
        let mut c = ConnState::new();
        c.on(ConnEvent::Open, 0);
        let a = c.on(
            ConnEvent::TicketMinted(Err(CoreErr::new("network", "x"))),
            0,
        );
        assert_eq!(
            a,
            vec![
                ConnAction::ShowStatus(Str::Reconnecting),
                ConnAction::ScheduleTick { at_ms: 1000 }
            ]
        );
        assert_eq!(c.on(ConnEvent::Tick, 1000), vec![ConnAction::MintTicket]);
        let a = c.on(
            ConnEvent::TicketMinted(Err(CoreErr::new("network", "x"))),
            1000,
        );
        assert_eq!(sched(&a), Some(3000));
    }

    #[test]
    fn offline_machine_stops_retries_until_online() {
        let mut c = ConnState::new();
        c.on(ConnEvent::Open, 0);
        c.on(ConnEvent::TicketMinted(Ok(ticket(1))), 0);
        let a = c.on(dis(), 0);
        assert_eq!(sched(&a), Some(1000));
        let a = c.on(ConnEvent::MachineOffline, 500);
        assert_eq!(a, vec![ConnAction::ShowStatus(Str::Offline)]);
        assert_eq!(c.phase(), &ConnPhase::Offline);
        // the stale tick no longer retries
        assert!(c.on(ConnEvent::Tick, 1000).is_empty());
        assert!(
            c.on(ConnEvent::TicketMinted(Ok(ticket(2))), 1000)
                .is_empty()
        );
        // coming back reconnects immediately with a fresh ticket and reset backoff
        let a = c.on(ConnEvent::MachineOnline, 9000);
        assert_eq!(
            a,
            vec![
                ConnAction::ShowStatus(Str::Connecting),
                ConnAction::MintTicket
            ]
        );
        assert_eq!(c.phase(), &ConnPhase::Connecting { attempt: 1 });
        c.on(ConnEvent::TicketMinted(Ok(ticket(3))), 9000);
        let a = c.on(dis(), 9000);
        assert_eq!(sched(&a), Some(10_000));
    }

    #[test]
    fn offline_while_connected_goes_offline_on_drop() {
        let mut c = ConnState::new();
        connected(&mut c, 0);
        assert!(c.on(ConnEvent::MachineOffline, 1).is_empty());
        assert!(c.accepts_input());
        let a = c.on(dis(), 2);
        assert_eq!(a, vec![ConnAction::ShowStatus(Str::Offline)]);
        assert_eq!(c.phase(), &ConnPhase::Offline);
    }

    #[test]
    fn input_refused_unless_connected() {
        let mut c = ConnState::new();
        assert!(!c.accepts_input());
        c.on(ConnEvent::Open, 0);
        assert!(!c.accepts_input());
        c.on(ConnEvent::TicketMinted(Ok(ticket(1))), 0);
        assert!(!c.accepts_input());
        c.on(ConnEvent::Connected, 0);
        assert!(c.accepts_input());
        c.on(dis(), 0);
        assert!(!c.accepts_input());
        c.on(ConnEvent::MachineOffline, 0);
        assert!(!c.accepts_input());
        c.on(ConnEvent::MachineOnline, 0);
        assert!(!c.accepts_input());
        c.on(ConnEvent::Close, 0);
        assert!(!c.accepts_input());
    }

    #[test]
    fn remote_ended_and_close_are_terminal() {
        let mut c = ConnState::new();
        connected(&mut c, 0);
        let a = c.on(ConnEvent::RemoteEnded, 1);
        assert_eq!(
            a,
            vec![ConnAction::ShowStatus(Str::RemoteEnded), ConnAction::Drop]
        );
        assert_eq!(c.phase(), &ConnPhase::Ended);
        assert!(c.on(dis(), 2).is_empty());
        assert!(c.on(ConnEvent::Tick, 3).is_empty());
        assert!(c.on(ConnEvent::MachineOnline, 3).is_empty());
        assert!(c.on(ConnEvent::Open, 3).is_empty());

        let mut c = ConnState::new();
        connected(&mut c, 0);
        assert_eq!(c.on(ConnEvent::Close, 1), vec![ConnAction::Drop]);
        assert_eq!(c.phase(), &ConnPhase::Ended);
        assert!(c.on(ConnEvent::Close, 2).is_empty());
    }

    #[test]
    fn stray_connected_after_giving_up_is_dropped() {
        let mut c = ConnState::new();
        c.on(ConnEvent::Open, 0);
        c.on(ConnEvent::TicketMinted(Ok(ticket(1))), 0);
        c.on(ConnEvent::MachineOffline, 1);
        assert_eq!(c.on(ConnEvent::Connected, 2), vec![ConnAction::Drop]);
        assert!(!c.accepts_input());
    }

    #[test]
    fn disconnect_reason_is_kept() {
        let mut c = ConnState::new();
        connected(&mut c, 0);
        c.on(
            ConnEvent::Disconnected {
                reason: "relay restart".into(),
            },
            0,
        );
        assert_eq!(c.last_reason(), Some("relay restart"));
    }

    // -------- pairing

    fn requested() -> PairRequested {
        PairRequested {
            pairing_id: "p1".into(),
            code: "482913".into(),
            fingerprint: "fp".into(),
        }
    }

    fn poll(status: PairStatus) -> PairPoll {
        PairPoll {
            status,
            invite_path: None,
            relay_route: None,
            relay_slot: None,
            daemon_fingerprint: None,
        }
    }

    fn waiting(f: &mut PairingFlow, now: u64) {
        assert_eq!(
            f.on(
                PairEvent::Start {
                    to_machine_id: "m1".into()
                },
                now
            ),
            vec![PairAction::CallPairRequest { to: "m1".into() }]
        );
        assert_eq!(f.state(), &PairState::Requesting);
        let a = f.on(PairEvent::Requested(Ok(requested())), now);
        assert_eq!(a, vec![PairAction::ScheduleTick { at_ms: now + 2000 }]);
        assert_eq!(
            f.state(),
            &PairState::Waiting {
                pairing_id: "p1".into(),
                code: "482913".into(),
                started_ms: now
            }
        );
    }

    #[test]
    fn pairing_polls_every_2s_until_approved() {
        let mut f = PairingFlow::new();
        waiting(&mut f, 1000);
        let mut now = 1000;
        for _ in 0..3 {
            now += 2000;
            assert_eq!(
                f.on(PairEvent::Tick, now),
                vec![PairAction::CallPairPoll {
                    pairing_id: "p1".into()
                }]
            );
            let a = f.on(PairEvent::Polled(Ok(poll(PairStatus::Pending))), now + 50);
            assert_eq!(
                a,
                vec![PairAction::ScheduleTick {
                    at_ms: now + 50 + 2000
                }]
            );
            now += 50;
        }
        // a transient poll failure keeps waiting
        now += 2000;
        f.on(PairEvent::Tick, now);
        let a = f.on(PairEvent::Polled(Err(CoreErr::new("network", "x"))), now);
        assert_eq!(a, vec![PairAction::ScheduleTick { at_ms: now + 2000 }]);
        assert!(matches!(f.state(), PairState::Waiting { .. }));
        now += 2000;
        f.on(PairEvent::Tick, now);
        let approved = PairPoll {
            status: PairStatus::Approved,
            invite_path: Some("C:\\i".into()),
            relay_route: Some("r".into()),
            relay_slot: Some("s".into()),
            daemon_fingerprint: Some("df".into()),
        };
        let a = f.on(PairEvent::Polled(Ok(approved)), now);
        assert_eq!(a, vec![PairAction::Done]);
        assert_eq!(
            f.state(),
            &PairState::Approved {
                invite_path: "C:\\i".into(),
                relay_route: "r".into(),
                relay_slot: "s".into(),
                daemon_fingerprint: "df".into()
            }
        );
        // terminal: further events do nothing
        assert!(f.on(PairEvent::Tick, now + 2000).is_empty());
    }

    #[test]
    fn pairing_approved_without_invite_fields_fails() {
        let mut f = PairingFlow::new();
        waiting(&mut f, 0);
        f.on(PairEvent::Tick, 2000);
        let a = f.on(PairEvent::Polled(Ok(poll(PairStatus::Approved))), 2000);
        assert_eq!(a, vec![PairAction::Done]);
        assert!(matches!(f.state(), PairState::Failed(e) if e.code == "bad_response"));
    }

    #[test]
    fn pairing_expires_after_5_minutes() {
        let mut f = PairingFlow::new();
        waiting(&mut f, 1000);
        let mut now = 1000;
        loop {
            now += 2000;
            let a = f.on(PairEvent::Tick, now);
            if f.state() == &PairState::Expired {
                assert_eq!(a, vec![PairAction::Done]);
                break;
            }
            assert_eq!(
                a,
                vec![PairAction::CallPairPoll {
                    pairing_id: "p1".into()
                }]
            );
            let a = f.on(PairEvent::Polled(Err(CoreErr::new("network", "x"))), now);
            assert_eq!(a.len(), 1);
            assert!(now < 1000 + 300_000 + 2000, "ran past the deadline");
        }
        assert_eq!(now, 1000 + 300_000);
    }

    #[test]
    fn pairing_deadline_caps_scheduled_tick() {
        let mut f = PairingFlow::new();
        waiting(&mut f, 0);
        f.on(PairEvent::Tick, 299_000);
        let a = f.on(PairEvent::Polled(Ok(poll(PairStatus::Pending))), 299_500);
        assert_eq!(a, vec![PairAction::ScheduleTick { at_ms: 300_000 }]);
        // the tick at the deadline expires without another poll
        assert_eq!(f.on(PairEvent::Tick, 300_000), vec![PairAction::Done]);
        assert_eq!(f.state(), &PairState::Expired);

        // a pending result that lands after the deadline also expires
        let mut f = PairingFlow::new();
        waiting(&mut f, 0);
        f.on(PairEvent::Tick, 299_000);
        let a = f.on(PairEvent::Polled(Ok(poll(PairStatus::Pending))), 300_100);
        assert_eq!(a, vec![PairAction::Done]);
        assert_eq!(f.state(), &PairState::Expired);
    }

    #[test]
    fn pairing_denied_is_terminal() {
        let mut f = PairingFlow::new();
        waiting(&mut f, 0);
        f.on(PairEvent::Tick, 2000);
        assert_eq!(
            f.on(PairEvent::Polled(Ok(poll(PairStatus::Denied))), 2000),
            vec![PairAction::Done]
        );
        assert_eq!(f.state(), &PairState::Denied);
        assert!(f.on(PairEvent::Tick, 4000).is_empty());
        assert!(f.on(PairEvent::Cancel, 4000).is_empty());
        assert_eq!(f.state(), &PairState::Denied);

        let mut f = PairingFlow::new();
        waiting(&mut f, 0);
        f.on(PairEvent::Tick, 2000);
        assert_eq!(
            f.on(PairEvent::Polled(Ok(poll(PairStatus::Expired))), 2000),
            vec![PairAction::Done]
        );
        assert_eq!(f.state(), &PairState::Expired);
    }

    #[test]
    fn pairing_request_failure_is_failed() {
        let mut f = PairingFlow::new();
        f.on(
            PairEvent::Start {
                to_machine_id: "m".into(),
            },
            0,
        );
        let a = f.on(
            PairEvent::Requested(Err(CoreErr::new("forbidden", "no"))),
            0,
        );
        assert_eq!(a, vec![PairAction::Done]);
        assert_eq!(
            f.state(),
            &PairState::Failed(CoreErr::new("forbidden", "no"))
        );
        // a terminal flow can be restarted
        assert_eq!(
            f.on(
                PairEvent::Start {
                    to_machine_id: "m".into()
                },
                5
            ),
            vec![PairAction::CallPairRequest { to: "m".into() }]
        );
    }

    #[test]
    fn pairing_cancel_returns_idle() {
        let mut f = PairingFlow::new();
        assert!(f.on(PairEvent::Cancel, 0).is_empty());
        waiting(&mut f, 0);
        assert_eq!(f.on(PairEvent::Cancel, 10), vec![PairAction::Done]);
        assert_eq!(f.state(), &PairState::Idle);
        // late results after cancel are ignored
        assert!(f.on(PairEvent::Tick, 2000).is_empty());
        assert!(
            f.on(PairEvent::Polled(Ok(poll(PairStatus::Approved))), 2000)
                .is_empty()
        );
        assert_eq!(f.state(), &PairState::Idle);

        let mut f = PairingFlow::new();
        f.on(
            PairEvent::Start {
                to_machine_id: "m".into(),
            },
            0,
        );
        assert_eq!(f.on(PairEvent::Cancel, 1), vec![PairAction::Done]);
        assert_eq!(f.state(), &PairState::Idle);
        assert!(f.on(PairEvent::Requested(Ok(requested())), 2).is_empty());
    }

    #[test]
    fn pairing_start_while_active_is_ignored() {
        let mut f = PairingFlow::new();
        waiting(&mut f, 0);
        assert!(
            f.on(
                PairEvent::Start {
                    to_machine_id: "x".into()
                },
                1
            )
            .is_empty()
        );
    }
}
