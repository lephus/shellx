//! Account service, window side: owns the `AccountFlow`, runs its core calls
//! off the UI thread on one background worker (in order, so results arrive
//! in call order as the flow expects), delivers every `ScheduleTick` as a
//! `Tick` through a GPUI timer, and applies results with `entity.update`.
//! The sidebar (machines), Settings -> Account and the sign-in dialog
//! observe it.
//!
//! Sign-in is email first: the dialog sends the address (`email_send_code`) and the mailed code
//! (`email_submit_code`); both calls run on the serial worker. "Continue with Google" shows only when
//! the core says this build has a Google client (`check_google`, `google_available`): the dialog
//! calls `google_sign_in`, `OpenBrowser` opens the system browser and `CallGoogleFinish` (which blocks
//! until the browser answers) runs on its own background task, never on the serial worker, so a
//! cancel can still be sent. The account token stays inside shellx-core.

use std::sync::Arc;
use std::time::{Duration, Instant};

use gpui::{Context, prelude::*};
use shellx_model::account::{AccountAction, AccountEvent, AccountFlow, AccountState};
use shellx_model::account_view::{AccountView, account_view};
use shellx_model::core_api::{CoreCall, CoreErr, GooglePurpose, SignInMethod};
use shellx_model::email_sign_in::EmailStep;
use shellx_model::sidebar::MachineInfo;
use shellx_model::strings::Lang;
use shellx_model::update::{CHECK_INTERVAL_SECS, UpdateStatus};

use super::update_banner::open_https;
use crate::core_service::{MachineFacts, run_account_action, run_google_check, run_version_check};
use crate::os_info;

/// What the one worker runs. `version.check` shares the worker with the
/// account calls (one thread model, calls in order).
enum Job {
    Account(AccountAction),
    VersionCheck,
    /// `auth.google.available` (local).
    GoogleCheck,
}

enum Done {
    Account(AccountEvent),
    Version(UpdateStatus),
    /// `None`: the core could not answer.
    Google(Option<bool>),
}

pub struct AccountService {
    flow: AccountFlow,
    jobs: async_channel::Sender<Job>,
    /// For `CallGoogleFinish`, which runs on its own task.
    core: Arc<dyn CoreCall>,
    facts: MachineFacts,
    done_tx: async_channel::Sender<Done>,
    started: Instant,
    utc_offset_secs: i32,
    update: UpdateStatus,
    checking: bool,
    /// A check has finished since the app started.
    checked: bool,
    /// The core's answer to `auth.google.available`; `None` until it answered.
    google: Option<bool>,
    /// A `Job::GoogleCheck` is queued and has not answered.
    google_checking: bool,
    /// Mac development build only: the `google` preview's answer, which the core's never replaces.
    #[cfg(target_os = "macos")]
    dev_google: Option<bool>,
}

impl AccountService {
    pub fn new(core: Arc<dyn CoreCall>, facts: MachineFacts, cx: &mut Context<Self>) -> Self {
        let (jobs, job_rx) = async_channel::unbounded::<Job>();
        let (result_tx, results) = async_channel::unbounded::<Done>();
        let (finish_core, finish_facts, done_tx) = (core.clone(), facts.clone(), result_tx.clone());
        // Blocking core calls (ureq) run here, never on the UI thread.
        cx.background_spawn(async move {
            while let Ok(job) = job_rx.recv().await {
                let done = match job {
                    Job::Account(action) => {
                        run_account_action(core.as_ref(), &facts, action).map(Done::Account)
                    }
                    Job::VersionCheck => Some(Done::Version(run_version_check(core.as_ref()))),
                    Job::GoogleCheck => Some(Done::Google(run_google_check(core.as_ref()))),
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
                    Done::Google(answer) => svc.apply_google(answer, cx),
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
            core: finish_core,
            facts: finish_facts,
            done_tx,
            started: Instant::now(),
            utc_offset_secs: os_info::utc_offset_secs(),
            update: UpdateStatus::Unknown,
            checking: false,
            checked: false,
            google: None,
            google_checking: false,
            #[cfg(target_os = "macos")]
            dev_google: None,
        };
        svc.apply(AccountEvent::Started, cx);
        // Queued behind the first account call, so `config.set` has gone out.
        svc.check_google(cx);
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

    /// A submit now would start a login (not while one runs or this machine
    /// is being registered).
    pub fn accepts_login(&self) -> bool {
        self.flow.accepts_login()
    }

    /// A failed logout or Google switch (the session stays); the switch dialog words it, Settings shows
    /// it through `view`.
    pub fn notice(&self) -> Option<&CoreErr> {
        self.flow.notice()
    }

    /// Local UTC offset for "lần cuối HH:MM", refreshed with every list.
    pub fn utc_offset_secs(&self) -> i32 {
        self.utc_offset_secs
    }

    /// A Google flow the dialog started and has not seen end, if any.
    pub fn google_in_flight(&self) -> Option<GooglePurpose> {
        self.flow.google_in_flight()
    }

    /// "Continue with Google" (`SignIn`) or the switch from a password session (`Link`).
    pub fn google_sign_in(&mut self, purpose: GooglePurpose, cx: &mut Context<Self>) {
        self.apply(AccountEvent::GoogleRequested(purpose), cx);
    }

    /// Cancel / Esc while a Google flow waits for the browser.
    pub fn cancel_google(&mut self, cx: &mut Context<Self>) {
        self.apply(AccountEvent::GoogleCancelRequested, cx);
    }

    /// "Send code": the trimmed address and the mail's language (`Lang::locale`).
    pub fn email_send_code(&mut self, email: String, locale: &'static str, cx: &mut Context<Self>) {
        self.apply(
            AccountEvent::EmailCodeRequested {
                email,
                locale: locale.to_string(),
            },
            cx,
        );
    }

    /// The email field's text changed.
    pub fn email_edited(&mut self, cx: &mut Context<Self>) {
        self.apply(AccountEvent::EmailEdited, cx);
    }

    /// "Resend code".
    pub fn email_resend(&mut self, cx: &mut Context<Self>) {
        self.apply(AccountEvent::EmailResendRequested, cx);
    }

    /// Verify, Enter or six digits typed: the code field's text (the flow takes its digits).
    pub fn email_submit_code(&mut self, code: String, cx: &mut Context<Self>) {
        self.apply(AccountEvent::EmailCodeSubmitted(code), cx);
    }

    /// "Use a different email".
    pub fn email_change(&mut self, cx: &mut Context<Self>) {
        self.apply(AccountEvent::EmailChangeRequested, cx);
    }

    /// The dialog closed: a run that is not verifying ends; one that is still applies its answer.
    pub fn email_cancel(&mut self, cx: &mut Context<Self>) {
        self.apply(AccountEvent::EmailCancelled, cx);
    }

    pub fn email_step(&self) -> Option<EmailStep> {
        self.flow.email_step()
    }

    pub fn email_sent_to(&self) -> Option<&str> {
        self.flow.email_sent_to()
    }

    pub fn email_error(&self) -> Option<&CoreErr> {
        self.flow.email_error()
    }

    pub fn email_can_verify(&self) -> bool {
        self.flow.email_can_verify()
    }

    /// Seconds until "Resend code" can be pressed, at this service's clock.
    pub fn email_resend_wait_secs(&self) -> u64 {
        self.flow.email_resend_wait_secs(self.now_ms())
    }

    pub fn email_code_epoch(&self) -> u64 {
        self.flow.email_code_epoch()
    }

    /// A sign-in is under way (a code is checked, or this PC is being registered).
    pub fn signing_in(&self) -> bool {
        *self.flow.state() == AccountState::LoggingIn
    }

    /// Mac development build only (screenshots): "code" puts the flow on the code step with a made-up
    /// challenge for "you@example.com" (resend_in 60); "switch" goes on to `EmailCodeSubmitted("123456")`
    /// and a 409 (`switch_from_signed_in_device`); "expired" signs that code in, lists this PC, then
    /// has the server refuse the session (the "Sign in again" notice). It feeds the flow directly and
    /// drops the returned actions, so no core call is made; any other value does nothing.
    #[cfg(target_os = "macos")]
    pub fn dev_preview_email(&mut self, preview: &str, cx: &mut Context<Self>) {
        use shellx_model::core_api::EmailChallenge;
        let now = self.now_ms();
        let mut events = Vec::new();
        if matches!(preview, "code" | "switch" | "expired") {
            events.push(AccountEvent::EmailCodeRequested {
                email: "you@example.com".into(),
                locale: "en".into(),
            });
            events.push(AccountEvent::EmailBegun(Ok(EmailChallenge {
                challenge_id: "preview".into(),
                email: "you@example.com".into(),
                expires_in: 600,
                resend_in: 60,
            })));
        }
        if preview == "switch" {
            events.push(AccountEvent::EmailCodeSubmitted("123456".into()));
            events.push(AccountEvent::EmailFinished {
                challenge_id: "preview".into(),
                result: Err(CoreErr::new("switch_from_signed_in_device", "")),
            });
        }
        if preview == "expired" {
            events.push(AccountEvent::EmailCodeSubmitted("123456".into()));
            events.push(AccountEvent::EmailFinished {
                challenge_id: "preview".into(),
                result: Ok(shellx_model::core_api::GoogleSignIn {
                    user_id: "preview".into(),
                    device_id: "preview".into(),
                    device_public_key_b64: String::new(),
                    fingerprint: String::new(),
                    email: "you@example.com".into(),
                    auth_method: "email".into(),
                }),
            });
            events.push(AccountEvent::ListResult(Ok(vec![
                crate::shell_info::this_machine(None),
            ])));
            events.push(AccountEvent::ListResult(Err(CoreErr::new(
                "unauthorized",
                "",
            ))));
        }
        if events.is_empty() {
            return;
        }
        for event in events {
            let _ = self.flow.on(event, now);
        }
        cx.notify();
    }

    /// Mac development build only: the `google` preview shows the Google button although this build
    /// has no client.
    #[cfg(target_os = "macos")]
    pub fn dev_set_google_available(&mut self, on: bool, cx: &mut Context<Self>) {
        self.dev_google = Some(on);
        cx.notify();
    }

    pub fn refresh_sign_in_methods(&mut self, cx: &mut Context<Self>) {
        self.apply(AccountEvent::SignInMethodsRequested, cx);
    }

    pub fn remove_sign_in_method(&mut self, identity_id: String, cx: &mut Context<Self>) {
        self.apply(AccountEvent::RemoveSignInMethodRequested(identity_id), cx);
    }

    /// Sign out (the settings panel's button).
    pub fn logout(&mut self, cx: &mut Context<Self>) {
        self.apply(AccountEvent::LogoutRequested, cx);
    }

    /// The account email (Google sign-in or `auth.session`), while signed in.
    pub fn email(&self) -> Option<&str> {
        match self.flow.state() {
            AccountState::LoggedIn { .. } => self.flow.email(),
            _ => None,
        }
    }

    pub fn auth_method(&self) -> Option<&str> {
        self.flow.auth_method()
    }

    /// Signed in with a password: Settings offers the switch to Google.
    pub fn needs_google_switch(&self) -> bool {
        self.flow.needs_google_switch()
    }

    pub fn sign_in_methods(&self) -> Option<&[SignInMethod]> {
        self.flow.sign_in_methods()
    }

    pub fn removing_sign_in_method(&self) -> Option<&str> {
        self.flow.removing_sign_in_method()
    }

    /// The server ended the session: the sidebar and Settings show "Your session expired." with
    /// "Sign in again" until the next sign-in. No dialog opens by itself (Ruling 29).
    pub fn session_ended_by_server(&self) -> bool {
        self.flow.session_ended_by_server()
    }

    /// What Settings › Account draws, in `lang`.
    pub fn view(&self, lang: Lang) -> AccountView {
        account_view(&self.flow, self.google_available(), lang)
    }

    /// The core said this build has a Google client (Ruling 28). False until it answered yes: the dialog
    /// and Settings draw nothing Google-related meanwhile.
    pub fn google_available(&self) -> bool {
        #[cfg(target_os = "macos")]
        if let Some(on) = self.dev_google {
            return on;
        }
        self.google == Some(true)
    }

    /// Asks the core whether this build has a Google client, when the answer is unknown (no answer yet,
    /// or the last call failed) and no check is queued. `new` calls it once; the dialog calls it on open.
    pub fn check_google(&mut self, cx: &mut Context<Self>) {
        if self.google.is_some() || self.google_checking {
            return;
        }
        self.google_checking = true;
        let _ = self.jobs.try_send(Job::GoogleCheck);
        cx.notify();
    }

    fn apply_google(&mut self, answer: Option<bool>, cx: &mut Context<Self>) {
        if answer.is_some() {
            self.google = answer;
        }
        self.google_checking = false;
        cx.notify();
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
                AccountAction::OpenBrowser(url) => open_https(cx, &url),
                // Blocks for minutes: its own task, so a cancel can run on the worker meanwhile.
                finish @ AccountAction::CallGoogleFinish(_) => {
                    let (core, facts, tx) =
                        (self.core.clone(), self.facts.clone(), self.done_tx.clone());
                    cx.background_spawn(async move {
                        if let Some(event) = run_account_action(core.as_ref(), &facts, finish) {
                            let _ = tx.send(Done::Account(event)).await;
                        }
                    })
                    .detach();
                }
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
