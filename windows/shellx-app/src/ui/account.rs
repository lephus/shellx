//! Account service, window side: owns the `AccountFlow`, runs its core calls
//! off the UI thread on one background worker (in order, so results arrive
//! in call order as the flow expects), delivers every `ScheduleTick` as a
//! `Tick` through a GPUI timer, and applies results with `entity.update`.
//! The sidebar (machines + sign-in card) observes it.
//!
//! The password goes from the sign-in panel straight into
//! `AccountEvent::LoginSubmitted` -> `CallLogin` -> the worker, and is
//! dropped after the call. The account token stays inside shellx-core.

use std::sync::Arc;
use std::time::{Duration, Instant};

use gpui::{Context, prelude::*};
use shellx_model::account::{AccountAction, AccountEvent, AccountFlow, AccountState};
use shellx_model::core_api::{CoreCall, CoreErr};
use shellx_model::sidebar::MachineInfo;

use crate::core_service::{MachineFacts, run_account_action};
use crate::os_info;

pub struct AccountService {
    flow: AccountFlow,
    jobs: async_channel::Sender<AccountAction>,
    started: Instant,
    utc_offset_secs: i32,
}

impl AccountService {
    pub fn new(core: Arc<dyn CoreCall>, facts: MachineFacts, cx: &mut Context<Self>) -> Self {
        let (jobs, job_rx) = async_channel::unbounded::<AccountAction>();
        let (result_tx, results) = async_channel::unbounded::<AccountEvent>();
        // Blocking core calls (ureq) run here, never on the UI thread.
        cx.background_spawn(async move {
            while let Ok(action) = job_rx.recv().await {
                if let Some(event) = run_account_action(core.as_ref(), &facts, action)
                    && result_tx.send(event).await.is_err()
                {
                    return;
                }
            }
        })
        .detach();
        cx.spawn(async move |this, cx| {
            while let Ok(event) = results.recv().await {
                if this.update(cx, |svc, cx| svc.apply(event, cx)).is_err() {
                    return;
                }
            }
        })
        .detach();

        let mut svc = AccountService {
            flow: AccountFlow::new(),
            jobs,
            started: Instant::now(),
            utc_offset_secs: os_info::utc_offset_secs(),
        };
        svc.apply(AccountEvent::Started, cx);
        svc
    }

    pub fn state(&self) -> &AccountState {
        self.flow.state()
    }

    /// The last machine list from the server (kept while offline).
    pub fn machines(&self) -> &[MachineInfo] {
        self.flow.machines()
    }

    pub fn login_in_flight(&self) -> bool {
        self.flow.login_in_flight()
    }

    /// A failed logout (the session stays); the settings panel shows it.
    pub fn notice(&self) -> Option<&CoreErr> {
        self.flow.notice()
    }

    /// Local UTC offset for "lần cuối HH:MM", refreshed with every list.
    pub fn utc_offset_secs(&self) -> i32 {
        self.utc_offset_secs
    }

    /// Sign-in panel submit. The password is moved into the event.
    pub fn login(&mut self, email: String, password: String, cx: &mut Context<Self>) {
        self.apply(AccountEvent::LoginSubmitted { email, password }, cx);
    }

    /// Sign out (Task 11's settings panel calls this).
    #[allow(dead_code)]
    pub fn logout(&mut self, cx: &mut Context<Self>) {
        self.apply(AccountEvent::LogoutRequested, cx);
    }

    fn now_ms(&self) -> u64 {
        u64::try_from(self.started.elapsed().as_millis()).unwrap_or(u64::MAX)
    }

    fn apply(&mut self, event: AccountEvent, cx: &mut Context<Self>) {
        if matches!(event, AccountEvent::ListResult(_)) {
            self.utc_offset_secs = os_info::utc_offset_secs();
        }
        let now = self.now_ms();
        for action in self.flow.on(event, now) {
            match action {
                AccountAction::ScheduleTick { at_ms } => self.schedule_tick(at_ms, cx),
                // Unbounded: never full; closed only if the worker is gone.
                call => {
                    let _ = self.jobs.try_send(call);
                }
            }
        }
        cx.notify();
    }

    /// One detached timer per `ScheduleTick`. The flow asks for a new tick
    /// only once the previous one is due, so at most one or two are pending;
    /// a tick that finds nothing due does nothing.
    fn schedule_tick(&mut self, at_ms: u64, cx: &mut Context<Self>) {
        let delay = Duration::from_millis(at_ms.saturating_sub(self.now_ms()));
        cx.spawn(async move |this, cx| {
            cx.background_executor().timer(delay).await;
            this.update(cx, |svc, cx| {
                // Never earlier than asked, so the flow sees the tick as due.
                let now = svc.now_ms().max(at_ms);
                svc.apply(AccountEvent::Tick(now), cx);
            })
            .ok();
        })
        .detach();
    }
}
