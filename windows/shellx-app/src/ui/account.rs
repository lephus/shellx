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
use shellx_model::update::{CHECK_INTERVAL_SECS, UpdateStatus};

use crate::core_service::{MachineFacts, run_account_action, run_version_check};
use crate::os_info;

/// What the one worker runs. `version.check` shares the worker with the
/// account calls (one thread model, calls in order).
enum Job {
    Account(AccountAction),
    VersionCheck,
}

enum Done {
    Account(AccountEvent),
    Version(UpdateStatus),
}

pub struct AccountService {
    flow: AccountFlow,
    jobs: async_channel::Sender<Job>,
    started: Instant,
    utc_offset_secs: i32,
    /// Email typed at sign-in (kept for the settings panel, never the
    /// password). Unknown after a restart.
    email: Option<String>,
    update: UpdateStatus,
    checking: bool,
    /// A check has finished since the app started.
    checked: bool,
    /// The user closed the "update available" banner; the next check result
    /// shows it again.
    banner_hidden: bool,
}

impl AccountService {
    pub fn new(core: Arc<dyn CoreCall>, facts: MachineFacts, cx: &mut Context<Self>) -> Self {
        let (jobs, job_rx) = async_channel::unbounded::<Job>();
        let (result_tx, results) = async_channel::unbounded::<Done>();
        // Blocking core calls (ureq) run here, never on the UI thread.
        cx.background_spawn(async move {
            while let Ok(job) = job_rx.recv().await {
                let done = match job {
                    Job::Account(action) => {
                        run_account_action(core.as_ref(), &facts, action).map(Done::Account)
                    }
                    Job::VersionCheck => Some(Done::Version(run_version_check(core.as_ref()))),
                };
                if let Some(done) = done
                    && result_tx.send(done).await.is_err()
                {
                    return;
                }
            }
        })
        .detach();
        cx.spawn(async move |this, cx| {
            while let Ok(done) = results.recv().await {
                let applied = this.update(cx, |svc, cx| match done {
                    Done::Account(event) => svc.apply(event, cx),
                    Done::Version(status) => svc.apply_update(status, cx),
                });
                if applied.is_err() {
                    return;
                }
            }
        })
        .detach();
        // Every 6 hours after the startup check.
        cx.spawn(async move |this, cx| {
            loop {
                cx.background_executor()
                    .timer(Duration::from_secs(CHECK_INTERVAL_SECS))
                    .await;
                if this.update(cx, |svc, cx| svc.check_update(cx)).is_err() {
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
            email: None,
            update: UpdateStatus::Unknown,
            checking: false,
            checked: false,
            banner_hidden: false,
        };
        svc.apply(AccountEvent::Started, cx);
        // Startup check: queued behind the first account call, so
        // `config.set` has already gone out.
        svc.check_update(cx);
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
        self.email = Some(email.clone());
        self.apply(AccountEvent::LoginSubmitted { email, password }, cx);
    }

    /// Sign out (the settings panel's button).
    pub fn logout(&mut self, cx: &mut Context<Self>) {
        self.apply(AccountEvent::LogoutRequested, cx);
    }

    /// The email typed at sign-in, while signed in.
    pub fn email(&self) -> Option<&str> {
        match self.flow.state() {
            AccountState::LoggedIn { .. } => self.email.as_deref(),
            _ => None,
        }
    }

    pub fn update_status(&self) -> &UpdateStatus {
        &self.update
    }

    pub fn checking(&self) -> bool {
        self.checking
    }

    pub fn checked(&self) -> bool {
        self.checked
    }

    /// The banner is shown for `Available` until the user closes it.
    pub fn banner_visible(&self) -> bool {
        matches!(self.update, UpdateStatus::Available { .. }) && !self.banner_hidden
    }

    pub fn hide_banner(&mut self, cx: &mut Context<Self>) {
        self.banner_hidden = true;
        cx.notify();
    }

    /// Runs `version.check` on the worker now (startup, every 6 h, and the
    /// settings button). One at a time.
    pub fn check_update(&mut self, cx: &mut Context<Self>) {
        if self.checking {
            return;
        }
        self.checking = true;
        let _ = self.jobs.try_send(Job::VersionCheck);
        cx.notify();
    }

    fn apply_update(&mut self, status: UpdateStatus, cx: &mut Context<Self>) {
        // A failed check (offline) never lifts a forced update.
        let keep =
            matches!(self.update, UpdateStatus::Required { .. }) && status == UpdateStatus::Unknown;
        if !keep {
            self.update = status;
        }
        self.checking = false;
        self.checked = true;
        self.banner_hidden = false;
        cx.notify();
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
                    let _ = self.jobs.try_send(Job::Account(call));
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
