//! The "Sign in to ShellX" dialog (the Mac's sign-in sheet). Every open is the person's: Settings ->
//! Account and the machines "+" while signed out.
//!
//! Email first (design §4.1, D3): the title, a line saying the first sign-in creates the account, the
//! email field with "Send code", then, only in a build with a Google client, "or" and Google's branded
//! "Continue with Google", and Cancel. After "Send code" the code step: where the code went, the code
//! field, Verify, "Resend code" (locked for the relay's `resend_in`), "Use a different email" and
//! Cancel. Six digits submit by themselves. Every failure is a sentence (`email_error`,
//! `google_error`), one line at a time. The rules (screens, Tab order, keys, the digits) are
//! `shellx_model::email_sign_in`'s; the steps are the account flow's.
//!
//! Keys (Ruling 30): the fields turn Enter, Esc and Tab into their own events; the dialog's own
//! listener acts only on what `dialog_key` returns, so a key it does not act on (typed text) is never
//! stopped and reaches the field through the platform's text path. Buttons hold focus handles and no
//! key listener: GPUI clicks a focused button on Enter or Space, and only enabled buttons have a click
//! handler. A click on the card gives the keyboard back to the control that had it.
//!
//! "Switch to Google sign-in" (`GooglePurpose::Link`, from Settings, only with Google) keeps today's
//! dialog: its own handle holds the keyboard and Enter starts Google.
//!
//! Other account errors (offline at start, a state-folder problem, a register failure) are not shown
//! here: Settings -> Account shows them.

use std::time::Duration;

use gpui::{
    AnyElement, App, ClickEvent, Context, Div, Entity, EventEmitter, FocusHandle, Focusable,
    FontWeight, IntoElement, KeyDownEvent, Render, SharedString, Stateful, Subscription, Window,
    div, prelude::*, px, transparent_black,
};
use shellx_model::account::AccountState;
use shellx_model::core_api::GooglePurpose;
use shellx_model::email_sign_in::{
    DialogFocus, DialogKey, SignInScreen, auto_submit, code_digits, dialog_key, email_looks_valid,
    email_text_refused, keep_keyboard, sign_in_screen, tab_order, tab_target, take_keyboard,
};
use shellx_model::strings::{
    Lang, Str, email_error, google_error, resend_code_in, sent_code_to, t,
};

use super::account::AccountService;
use super::app::Services;
use super::button::{Kind, button};
use super::google_button::google_button;
use super::text_field::{TextField, TextFieldEvent};
use super::theme;

/// Card width (the Mac's sheet).
const CARD_W: f32 = 340.0;
/// The corner of `ui/button.rs`'s buttons.
const BUTTON_RADIUS: f32 = 7.0;
/// The keyboard ring around a focused button, outside its own border.
const RING_WIDTH: f32 = 2.0;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum SignInEvent {
    /// Esc / Cancel / signed in: RootView gives the keyboard to the panel
    /// below, else back to the terminal.
    Closed,
    /// `open` ran, or the keyboard moved to another control of the dialog (a new screen): RootView
    /// gives it to `focus_target`.
    Opened,
}

/// What each control of the sign-in screen accepts, as drawn: Tab skips the others, and only an
/// enabled button has a click handler.
#[derive(Clone, Copy)]
struct Controls {
    screen: SignInScreen,
    google: bool,
    email_field: bool,
    send: bool,
    google_button: bool,
    code_field: bool,
    verify: bool,
    resend: bool,
    change: bool,
}

impl Controls {
    fn enabled(&self, control: DialogFocus) -> bool {
        match control {
            DialogFocus::EmailField => self.email_field,
            DialogFocus::SendCode => self.send,
            DialogFocus::Google => self.google_button,
            DialogFocus::CodeField => self.code_field,
            DialogFocus::Verify => self.verify,
            DialogFocus::Resend => self.resend,
            DialogFocus::ChangeEmail => self.change,
            DialogFocus::Cancel => true,
        }
    }
}

/// The buttons' focus handles.
struct Buttons {
    send: FocusHandle,
    google: FocusHandle,
    verify: FocusHandle,
    resend: FocusHandle,
    change: FocusHandle,
    cancel: FocusHandle,
}

pub struct SignInDialog {
    account: Entity<AccountService>,
    /// The dialog's own handle: `Link` keeps the keyboard here; for `SignIn` it gives it back.
    focus: FocusHandle,
    purpose: GooglePurpose,
    open: bool,
    /// A Google flow was started from this dialog, so its error is shown here.
    started: bool,
    email_field: Entity<TextField>,
    code_field: Entity<TextField>,
    buttons: Buttons,
    /// The digits this dialog last submitted, so one paste (or a click in the field) submits once.
    last_auto: Option<String>,
    /// The account's `email_code_epoch()` the code field matches.
    code_epoch_seen: u64,
    /// The email field's text when the dialog last looked: tells an edit from a click or a cursor move.
    email_text_seen: String,
    /// The screen drawn last.
    shown: SignInScreen,
    /// What holds the keyboard (`SignIn` only).
    focused: DialogFocus,
    /// The resend countdown repaints.
    counting: bool,
    _subscriptions: Vec<Subscription>,
}

impl SignInDialog {
    pub fn new(
        account: Entity<AccountService>,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) -> Self {
        let lang = cx.global::<Services>().lang;
        let email_field = cx.new(|cx| TextField::new(false, t(lang, Str::EmailAddress), cx));
        let code_field = cx.new(|cx| TextField::new(false, t(lang, Str::CodePlaceholder), cx));
        let buttons = Buttons {
            send: cx.focus_handle(),
            google: cx.focus_handle(),
            verify: cx.focus_handle(),
            resend: cx.focus_handle(),
            change: cx.focus_handle(),
            cancel: cx.focus_handle(),
        };
        let focus = cx.focus_handle();
        let mut subscriptions = vec![
            cx.observe(&account, |this, account, cx| {
                if this.open && this.finished_ok(account.read(cx)) {
                    // Signed in (or switched): the dialog goes away and the keyboard goes back to
                    // the panel below, else the terminal.
                    this.open = false;
                    this.reset(cx);
                    cx.emit(SignInEvent::Closed);
                }
                this.sync(cx);
                cx.notify();
            }),
            cx.observe(&email_field, |this, _, cx| this.email_changed(cx)),
            cx.observe(&code_field, |this, _, cx| this.code_changed(cx)),
            cx.subscribe_in(
                &email_field,
                window,
                |this, _, event: &TextFieldEvent, window, cx| {
                    this.field_event(DialogFocus::EmailField, *event, window, cx)
                },
            ),
            cx.subscribe_in(
                &code_field,
                window,
                |this, _, event: &TextFieldEvent, window, cx| {
                    this.field_event(DialogFocus::CodeField, *event, window, cx)
                },
            ),
            // A click on the card or the backdrop focuses the dialog's own handle: give the keyboard
            // back, so typed text still reaches the field (Ruling 30).
            cx.on_focus(&focus, window, |this, window, cx| {
                if this.open && this.purpose == GooglePurpose::SignIn {
                    let handle = this.handle_of(this.focused, cx);
                    window.focus(&handle);
                }
            }),
        ];
        // The keyboard's holder follows Tab, screen changes and clicks into a field or onto a button.
        let controls = [
            (
                DialogFocus::EmailField,
                email_field.read(cx).focus_handle(cx),
            ),
            (DialogFocus::CodeField, code_field.read(cx).focus_handle(cx)),
            (DialogFocus::SendCode, buttons.send.clone()),
            (DialogFocus::Google, buttons.google.clone()),
            (DialogFocus::Verify, buttons.verify.clone()),
            (DialogFocus::Resend, buttons.resend.clone()),
            (DialogFocus::ChangeEmail, buttons.change.clone()),
            (DialogFocus::Cancel, buttons.cancel.clone()),
        ];
        for (control, handle) in controls {
            subscriptions.push(cx.on_focus(&handle, window, move |this, window, cx| {
                // A click on a disabled control never takes the keyboard (review chunk 2 I-A).
                let c = this.controls(cx);
                let to = take_keyboard(c.screen, c.google, this.focused, control, |f| c.enabled(f));
                this.focused = to;
                if to != control {
                    let handle = this.handle_of(to, cx);
                    window.focus(&handle);
                }
                cx.notify();
            }));
        }
        SignInDialog {
            account,
            focus,
            purpose: GooglePurpose::SignIn,
            open: false,
            started: false,
            email_field,
            code_field,
            buttons,
            last_auto: None,
            code_epoch_seen: 0,
            email_text_seen: String::new(),
            shown: SignInScreen::Start {
                sending: false,
                google_waiting: false,
            },
            focused: DialogFocus::EmailField,
            counting: false,
            _subscriptions: subscriptions,
        }
    }

    /// The flow this dialog serves ended with a session.
    fn finished_ok(&self, account: &AccountService) -> bool {
        match self.purpose {
            GooglePurpose::SignIn => matches!(account.state(), AccountState::LoggedIn { .. }),
            GooglePurpose::Link => {
                self.started
                    && account.google_in_flight().is_none()
                    && account.auth_method() == Some("google")
            }
        }
    }

    /// Shows the dialog fresh (empty fields, no old error) and gives it the keyboard: the email field
    /// for `SignIn`, the dialog's own handle for `Link`. RootView only calls it when nothing above the
    /// dialog is open (`Panels::may_open`).
    pub fn open(&mut self, purpose: GooglePurpose, window: &mut Window, cx: &mut Context<Self>) {
        self.purpose = purpose;
        self.open = true;
        self.reset(cx);
        match purpose {
            GooglePurpose::SignIn => {
                // Asked again while the answer is unknown (an earlier call failed).
                self.account
                    .update(cx, |account, cx| account.check_google(cx));
                self.shown = self.screen(cx);
                self.focused = Self::first_control(self.shown);
                let handle = self.handle_of(self.focused, cx);
                window.focus(&handle);
                self.sync(cx);
            }
            GooglePurpose::Link => window.focus(&self.focus),
        }
        cx.emit(SignInEvent::Opened);
        cx.notify();
    }

    /// The dialog is shown and holds the keyboard.
    pub fn is_open(&self) -> bool {
        self.open
    }

    /// The handle the keyboard belongs to while the dialog is open.
    pub fn focus_target(&self, cx: &App) -> FocusHandle {
        match self.purpose {
            GooglePurpose::SignIn => self.handle_of(self.focused, cx),
            GooglePurpose::Link => self.focus.clone(),
        }
    }

    /// Esc / Cancel: a running Google flow is cancelled, an email run ends (a code already being
    /// checked still applies its answer), then the dialog closes.
    pub fn close(&mut self, cx: &mut Context<Self>) {
        if self.account.read(cx).google_in_flight().is_some() {
            self.account
                .update(cx, |account, cx| account.cancel_google(cx));
        }
        if self.purpose == GooglePurpose::SignIn {
            self.account
                .update(cx, |account, cx| account.email_cancel(cx));
        }
        if self.open {
            self.open = false;
            self.reset(cx);
            cx.emit(SignInEvent::Closed);
        }
        cx.notify();
    }

    /// Mac development build only: fills the email field for the `invalid` and `switch` previews, and
    /// marks the text as seen, so the fill is no edit (the `switch` preview keeps its sentence).
    #[cfg(target_os = "macos")]
    pub fn dev_fill_email(&mut self, text: &str, cx: &mut Context<Self>) {
        self.email_text_seen = text.to_string();
        self.email_field
            .update(cx, |field, cx| field.dev_set_text(text, cx));
    }

    /// Both fields empty and enabled, no submitted digits, no Google error of an earlier attempt.
    fn reset(&mut self, cx: &mut Context<Self>) {
        self.started = false;
        self.last_auto = None;
        self.email_text_seen.clear();
        self.code_epoch_seen = self.account.read(cx).email_code_epoch();
        for field in [&self.email_field, &self.code_field] {
            field.update(cx, |field, cx| {
                field.clear(cx);
                field.set_disabled(false, cx);
            });
        }
    }

    fn screen(&self, cx: &App) -> SignInScreen {
        let account = self.account.read(cx);
        sign_in_screen(
            account.email_step(),
            account.email_sent_to().is_some(),
            account.google_in_flight().is_some(),
            account.signing_in(),
        )
    }

    fn first_control(screen: SignInScreen) -> DialogFocus {
        match screen {
            SignInScreen::Start { .. } => DialogFocus::EmailField,
            SignInScreen::Code { .. } => DialogFocus::CodeField,
            SignInScreen::SigningIn => DialogFocus::Cancel,
        }
    }

    fn controls(&self, cx: &App) -> Controls {
        let account = self.account.read(cx);
        let screen = self.screen(cx);
        let google = account.google_available();
        let email = self.email_field.read(cx);
        let code = self.code_field.read(cx);
        let mut c = Controls {
            screen,
            google,
            email_field: false,
            send: false,
            google_button: false,
            code_field: false,
            verify: false,
            resend: false,
            change: false,
        };
        match screen {
            SignInScreen::Start {
                sending,
                google_waiting,
            } => {
                c.email_field = !sending;
                c.send = !sending
                    && !google_waiting
                    && account.accepts_login()
                    && !email.composing()
                    && email_looks_valid(email.text());
                c.google_button = google && !sending && !google_waiting && account.accepts_login();
            }
            SignInScreen::Code { busy } => {
                let idle = !busy && !code.composing();
                c.code_field = !busy && account.email_can_verify();
                c.verify = idle && account.email_can_verify() && code_digits(code.text()).is_some();
                c.resend = idle && account.email_resend_wait_secs() == 0;
                c.change = idle;
            }
            SignInScreen::SigningIn => {}
        }
        c
    }

    fn handle_of(&self, control: DialogFocus, cx: &App) -> FocusHandle {
        match control {
            DialogFocus::EmailField => self.email_field.read(cx).focus_handle(cx),
            DialogFocus::CodeField => self.code_field.read(cx).focus_handle(cx),
            DialogFocus::SendCode => self.buttons.send.clone(),
            DialogFocus::Google => self.buttons.google.clone(),
            DialogFocus::Verify => self.buttons.verify.clone(),
            DialogFocus::Resend => self.buttons.resend.clone(),
            DialogFocus::ChangeEmail => self.buttons.change.clone(),
            DialogFocus::Cancel => self.buttons.cancel.clone(),
        }
    }

    /// Brings the dialog in line with the account: empties the code field when the epoch moved (never
    /// during a composition: then at its end), enables the fields as drawn, moves the keyboard when the
    /// screen changes, and keeps the resend countdown repainting.
    fn sync(&mut self, cx: &mut Context<Self>) {
        if !self.open || self.purpose != GooglePurpose::SignIn {
            return;
        }
        let epoch = self.account.read(cx).email_code_epoch();
        if epoch != self.code_epoch_seen && !self.code_field.read(cx).composing() {
            self.code_epoch_seen = epoch;
            self.last_auto = None;
            self.code_field.update(cx, |field, cx| field.clear(cx));
        }
        let c = self.controls(cx);
        self.email_field
            .update(cx, |field, cx| field.set_disabled(!c.email_field, cx));
        self.code_field
            .update(cx, |field, cx| field.set_disabled(!c.code_field, cx));
        let mut moved = false;
        if std::mem::discriminant(&c.screen) != std::mem::discriminant(&self.shown) {
            // A new screen: its first control takes the keyboard; the email field keeps its text.
            self.focused = Self::first_control(c.screen);
            moved = true;
        }
        // A holder that turned disabled (Resend, Verify, Send code pressed) or left the screen gives
        // the keyboard to the screen's field, so the next code typed or pasted reaches it (review
        // chunk 2 I-A); Google's holder leaves when the build has no Google client.
        let kept = keep_keyboard(c.screen, c.google, self.focused, |f| c.enabled(f));
        if kept != self.focused {
            self.focused = kept;
            moved = true;
        }
        self.shown = c.screen;
        if moved {
            cx.emit(SignInEvent::Opened);
        }
        if matches!(c.screen, SignInScreen::Code { busy: false }) {
            self.start_countdown(cx);
        }
    }

    /// Repaints "Resend code in N s" every second while the code step shows and the lock runs.
    fn start_countdown(&mut self, cx: &mut Context<Self>) {
        if self.counting || self.account.read(cx).email_resend_wait_secs() == 0 {
            return;
        }
        self.counting = true;
        cx.spawn(async move |this, cx| {
            loop {
                cx.background_executor().timer(Duration::from_secs(1)).await;
                let again = this.update(cx, |this, cx| {
                    cx.notify();
                    let again = this.open
                        && matches!(this.shown, SignInScreen::Code { busy: false })
                        && this.account.read(cx).email_resend_wait_secs() > 0;
                    this.counting = again;
                    again
                });
                if !matches!(again, Ok(true)) {
                    return;
                }
            }
        })
        .detach();
    }

    /// The email field notified: an edit (not a click or a cursor move) hides Google's failure and
    /// clears the run's (D4: the InvalidEmail sentence replaces a stale one).
    fn email_changed(&mut self, cx: &mut Context<Self>) {
        if !self.open {
            return;
        }
        let text = self.email_field.read(cx).text();
        if text != self.email_text_seen {
            self.email_text_seen = text.to_string();
            self.started = false;
            self.account
                .update(cx, |account, cx| account.email_edited(cx));
        }
        self.sync(cx);
        cx.notify();
    }

    /// The code field notified: six new digits submit by themselves.
    fn code_changed(&mut self, cx: &mut Context<Self>) {
        if !self.open {
            return;
        }
        self.sync(cx);
        let can = {
            let field = self.code_field.read(cx);
            self.account.read(cx).email_can_verify()
                && matches!(self.shown, SignInScreen::Code { busy: false })
                && !field.composing()
        };
        let text = self.code_field.read(cx).text().to_string();
        if let Some(digits) = auto_submit(self.last_auto.as_deref(), &text, can) {
            self.submit_code(digits, cx);
        }
        cx.notify();
    }

    fn field_event(
        &mut self,
        field: DialogFocus,
        event: TextFieldEvent,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) {
        // A field that lost the keyboard says so after the focus has moved: it must not take
        // the tracking back.
        if !self.open || event == TextFieldEvent::Blur {
            return;
        }
        self.focused = field;
        match event {
            TextFieldEvent::Submit => match field {
                DialogFocus::EmailField => self.send_code(cx),
                _ => self.verify(cx),
            },
            TextFieldEvent::Cancel => self.close(cx),
            TextFieldEvent::Next => self.move_focus(false, window, cx),
            TextFieldEvent::Prev => self.move_focus(true, window, cx),
            TextFieldEvent::Blur => {}
        }
    }

    /// Tab / Shift+Tab: the next (previous) enabled control in D3's order.
    fn move_focus(&mut self, back: bool, window: &mut Window, cx: &mut Context<Self>) {
        if self.purpose != GooglePurpose::SignIn {
            return;
        }
        let c = self.controls(cx);
        let order = tab_order(c.screen, c.google);
        self.focused = tab_target(order, self.focused, back, |control| c.enabled(control));
        let handle = self.handle_of(self.focused, cx);
        window.focus(&handle);
        cx.notify();
    }

    /// "Send code" (the button, or Enter in the email field), when it is enabled.
    fn send_code(&mut self, cx: &mut Context<Self>) {
        if !self.controls(cx).send {
            return;
        }
        let lang = cx.global::<Services>().lang;
        let email = self.email_field.read(cx).text().trim().to_string();
        self.started = false;
        self.account.update(cx, |account, cx| {
            account.email_send_code(email, lang.locale(), cx)
        });
    }

    /// Verify (the button, or Enter in the code field), when it is enabled.
    fn verify(&mut self, cx: &mut Context<Self>) {
        if !self.controls(cx).verify {
            return;
        }
        let text = self.code_field.read(cx).text().to_string();
        if let Some(digits) = code_digits(&text) {
            self.submit_code(digits, cx);
        }
    }

    fn submit_code(&mut self, digits: String, cx: &mut Context<Self>) {
        self.last_auto = Some(digits.clone());
        self.account
            .update(cx, |account, cx| account.email_submit_code(digits, cx));
    }

    fn resend(&mut self, cx: &mut Context<Self>) {
        if self.controls(cx).resend {
            self.account
                .update(cx, |account, cx| account.email_resend(cx));
        }
    }

    fn change_email(&mut self, cx: &mut Context<Self>) {
        if self.controls(cx).change {
            self.account
                .update(cx, |account, cx| account.email_change(cx));
        }
    }

    /// Google (the button, or Enter on the `Link` dialog): starts the flow unless one runs or the flow
    /// would ignore it.
    fn start(&mut self, cx: &mut Context<Self>) {
        let account = self.account.read(cx);
        let can = account.google_in_flight().is_none()
            && match self.purpose {
                GooglePurpose::SignIn => account.accepts_login() && account.google_available(),
                GooglePurpose::Link => account.needs_google_switch(),
            };
        if !can {
            return;
        }
        self.started = true;
        let purpose = self.purpose;
        self.account
            .update(cx, |account, cx| account.google_sign_in(purpose, cx));
        cx.notify();
    }

    /// The dialog's own listener (Ruling 30): it stops only the keys it acts on.
    fn on_key_down(&mut self, event: &KeyDownEvent, window: &mut Window, cx: &mut Context<Self>) {
        let stroke = &event.keystroke;
        let mods = stroke.modifiers;
        let holder = if self.focus.is_focused(window) {
            None
        } else {
            Some(self.focused)
        };
        let key = dialog_key(
            holder,
            self.purpose == GooglePurpose::Link,
            stroke.key.as_str(),
            mods.shift,
            mods.control || mods.alt || mods.platform,
        );
        match key {
            DialogKey::Pass => {}
            DialogKey::Close => {
                cx.stop_propagation();
                self.close(cx);
            }
            DialogKey::Move { back } => {
                cx.stop_propagation();
                self.move_focus(back, window, cx);
            }
            DialogKey::StartGoogle => {
                cx.stop_propagation();
                self.start(cx);
            }
        }
    }

    /// A button that can hold the keyboard: its focus handle and its click handler, only while it is
    /// enabled (GPUI clicks a focused element on Enter or Space; a disabled button takes no focus, so a
    /// click on it never takes the keyboard: the card's handle gets it and gives it back). The ring that
    /// shows the keyboard sits outside the button and never changes its box (review chunk 2 M-C): a
    /// 2 px border that is always there, transparent until the button holds the keyboard. Google's
    /// branded stroke stays as it is. `radius`: the button's corner; `wide`: the button fills the row.
    #[allow(clippy::too_many_arguments)]
    fn focusable(
        &self,
        element: Stateful<Div>,
        control: DialogFocus,
        enabled: bool,
        radius: f32,
        wide: bool,
        window: &Window,
        cx: &Context<Self>,
        on_click: impl Fn(&mut Self, &mut Context<Self>) + 'static,
    ) -> Div {
        let handle = self.handle_of(control, cx);
        let ring = if handle.is_focused(window) {
            theme::primary_line()
        } else {
            transparent_black()
        };
        let element = if enabled {
            element.track_focus(&handle).on_click(cx.listener(
                move |this, _: &ClickEvent, _, cx| {
                    // The press already gave this button the keyboard, but `on_focus` runs only
                    // at the end of the next draw, and a touchpad tap delivers press and release
                    // with no draw between them. Record the holder now, so the sync this click
                    // triggers hands the keyboard back to the field when the button turns off
                    // (re-review of I-A).
                    this.focused = control;
                    on_click(this, cx)
                },
            ))
        } else {
            element
        };
        div()
            .flex()
            .when(wide, |ring| ring.w_full())
            .rounded(px(radius + RING_WIDTH))
            .border(px(RING_WIDTH))
            .border_color(ring)
            .child(element)
    }

    fn title(text: &'static str) -> Div {
        div()
            .text_size(px(15.0))
            .font_weight(FontWeight::SEMIBOLD)
            .text_color(theme::text_hi())
            .child(text)
    }

    fn error_line(text: String) -> Div {
        div()
            .text_size(theme::SMALL_SIZE)
            .text_color(theme::error_text())
            .child(text)
    }

    fn muted_line(text: impl Into<SharedString>) -> Div {
        div()
            .text_size(theme::SMALL_SIZE)
            .text_color(theme::muted())
            .child(text.into())
    }

    fn waiting_for_google(lang: Lang) -> Div {
        div()
            .flex()
            .flex_col()
            .gap(px(4.0))
            .child(
                div()
                    .text_color(theme::text_hi())
                    .child(t(lang, Str::WaitingForGoogle)),
            )
            .child(Self::muted_line(t(lang, Str::BrowserHint)))
    }

    /// One button on its own line.
    fn row(element: Div) -> AnyElement {
        div().flex().child(element).into_any_element()
    }

    /// "Switch to Google sign-in": the title, the intro, Google (or "Waiting for Google…"), its error.
    fn link_children(&self, lang: Lang, cx: &Context<Self>) -> Vec<AnyElement> {
        let account = self.account.read(cx);
        let waiting = account.google_in_flight().is_some();
        let error = if self.started && !waiting {
            account.notice().and_then(|e| google_error(lang, &e.code))
        } else {
            None
        };
        let action = if waiting {
            Self::waiting_for_google(lang)
        } else {
            div().flex().justify_center().child(
                google_button("sign-in-google", t(lang, Str::ContinueWithGoogle))
                    .on_click(cx.listener(|this, _: &ClickEvent, _, cx| this.start(cx))),
            )
        };
        let mut items = vec![
            Self::title(t(lang, Str::SwitchToGoogle)).into_any_element(),
            Self::muted_line(t(lang, Str::SwitchToGoogleIntro)).into_any_element(),
            action.into_any_element(),
        ];
        items.extend(error.map(|e| Self::error_line(e).into_any_element()));
        items.push(
            div()
                .flex()
                .flex_row()
                .justify_end()
                .child(
                    button(
                        "sign-in-cancel",
                        t(lang, Str::Cancel),
                        Kind::Secondary,
                        false,
                    )
                    .on_click(cx.listener(|this, _: &ClickEvent, _, cx| this.close(cx))),
                )
                .into_any_element(),
        );
        items
    }

    /// The email-first screens (`sign_in_screen`).
    fn sign_in_children(&self, lang: Lang, window: &Window, cx: &Context<Self>) -> Vec<AnyElement> {
        let c = self.controls(cx);
        let account = self.account.read(cx);
        let mut items = vec![Self::title(t(lang, Str::SignInTitle)).into_any_element()];
        match c.screen {
            SignInScreen::Start {
                sending,
                google_waiting,
            } => {
                // One failure line at a time (D3): Google's, else the run's, else the address hint.
                // Google's line is its own attempt's failure, never the account state (which may be
                // an error the attempt came back to: review I1).
                let google_line = if c.google && self.started && !google_waiting {
                    account
                        .google_failure()
                        .and_then(|e| google_error(lang, &e.code))
                } else {
                    None
                };
                let email = self.email_field.read(cx);
                let email_line = if google_line.is_some() {
                    None
                } else if let Some(e) = account.email_error() {
                    Some(email_error(lang, &e.code))
                } else if !email.composing() && email_text_refused(email.text()) {
                    Some(t(lang, Str::InvalidEmail).to_string())
                } else {
                    None
                };
                items.push(
                    Self::muted_line(t(lang, Str::FirstSignInCreatesAccount)).into_any_element(),
                );
                items.push(self.email_field.clone().into_any_element());
                items.extend(email_line.map(|line| Self::error_line(line).into_any_element()));
                let send = button(
                    "sign-in-send-code",
                    t(lang, Str::SendCode),
                    Kind::Primary,
                    !c.send,
                )
                .w_full();
                items.push(
                    self.focusable(
                        send,
                        DialogFocus::SendCode,
                        c.send,
                        BUTTON_RADIUS,
                        true,
                        window,
                        cx,
                        |this, cx| this.send_code(cx),
                    )
                    .into_any_element(),
                );
                if c.google {
                    items.push(
                        div()
                            .flex()
                            .justify_center()
                            .text_size(theme::SMALL_SIZE)
                            .text_color(theme::muted())
                            .child(t(lang, Str::OrDivider))
                            .into_any_element(),
                    );
                    if google_waiting {
                        items.push(Self::waiting_for_google(lang).into_any_element());
                    } else {
                        let google =
                            google_button("sign-in-google", t(lang, Str::ContinueWithGoogle))
                                .when(sending, |b| b.opacity(0.5));
                        let google = self.focusable(
                            google,
                            DialogFocus::Google,
                            c.google_button,
                            shellx_model::google_button::CORNER_RADIUS,
                            false,
                            window,
                            cx,
                            |this, cx| this.start(cx),
                        );
                        items.push(
                            div()
                                .flex()
                                .justify_center()
                                .child(google)
                                .into_any_element(),
                        );
                    }
                    items.extend(google_line.map(|line| Self::error_line(line).into_any_element()));
                }
            }
            SignInScreen::Code { .. } => {
                // Only while that code can still be verified (review chunk 1 M5).
                if let Some(address) = account.email_code_sent_to() {
                    items.push(
                        div()
                            .text_color(theme::text_hi())
                            .child(sent_code_to(lang, address))
                            .into_any_element(),
                    );
                }
                items.push(self.code_field.clone().into_any_element());
                items.extend(
                    account
                        .email_error()
                        .map(|e| Self::error_line(email_error(lang, &e.code)).into_any_element()),
                );
                let verify = button(
                    "sign-in-verify",
                    t(lang, Str::VerifyCode),
                    Kind::Primary,
                    !c.verify,
                )
                .w_full();
                items.push(
                    self.focusable(
                        verify,
                        DialogFocus::Verify,
                        c.verify,
                        BUTTON_RADIUS,
                        true,
                        window,
                        cx,
                        |this, cx| this.verify(cx),
                    )
                    .into_any_element(),
                );
                let wait = account.email_resend_wait_secs();
                let label = if wait > 0 {
                    resend_code_in(lang, wait)
                } else {
                    t(lang, Str::ResendCode).to_string()
                };
                let resend = button("sign-in-resend", label, Kind::Secondary, !c.resend);
                items.push(Self::row(self.focusable(
                    resend,
                    DialogFocus::Resend,
                    c.resend,
                    BUTTON_RADIUS,
                    false,
                    window,
                    cx,
                    |this, cx| this.resend(cx),
                )));
                let change = button(
                    "sign-in-change-email",
                    t(lang, Str::UseDifferentEmail),
                    Kind::Secondary,
                    !c.change,
                );
                items.push(Self::row(self.focusable(
                    change,
                    DialogFocus::ChangeEmail,
                    c.change,
                    BUTTON_RADIUS,
                    false,
                    window,
                    cx,
                    |this, cx| this.change_email(cx),
                )));
            }
            SignInScreen::SigningIn => {
                items.push(
                    div()
                        .text_color(theme::text_hi())
                        .child(t(lang, Str::SigningIn))
                        .into_any_element(),
                );
            }
        }
        let cancel = button(
            "sign-in-cancel",
            t(lang, Str::Cancel),
            Kind::Secondary,
            false,
        );
        items.push(
            div()
                .flex()
                .flex_row()
                .justify_end()
                .child(self.focusable(
                    cancel,
                    DialogFocus::Cancel,
                    true,
                    BUTTON_RADIUS,
                    false,
                    window,
                    cx,
                    |this, cx| this.close(cx),
                ))
                .into_any_element(),
        );
        items
    }
}

impl EventEmitter<SignInEvent> for SignInDialog {}

impl Render for SignInDialog {
    fn render(&mut self, window: &mut Window, cx: &mut Context<Self>) -> impl IntoElement {
        let lang: Lang = cx.global::<Services>().lang;
        self.email_field.update(cx, |field, cx| {
            field.set_placeholder(t(lang, Str::EmailAddress), cx)
        });
        self.code_field.update(cx, |field, cx| {
            field.set_placeholder(t(lang, Str::CodePlaceholder), cx)
        });
        let items = match self.purpose {
            GooglePurpose::SignIn => self.sign_in_children(lang, window, cx),
            GooglePurpose::Link => self.link_children(lang, cx),
        };
        let card = div()
            .flex()
            .flex_col()
            .gap(px(12.0))
            .w(px(CARD_W))
            .p(px(20.0))
            .rounded(px(10.0))
            .border_1()
            .border_color(theme::border())
            .bg(theme::raise())
            .children(items);

        // Covers the window below the title bar: the backdrop blocks the mouse for everything under
        // it. Its listener sees every key the focused control did not stop (Ruling 30).
        div()
            .id("sign-in-dialog")
            .track_focus(&self.focus)
            .on_key_down(cx.listener(Self::on_key_down))
            .occlude()
            .absolute()
            .top(px(crate::workspace::TITLEBAR_H))
            .left_0()
            .right_0()
            .bottom_0()
            .flex()
            .items_center()
            .justify_center()
            .bg(theme::bg().opacity(0.6))
            .child(card)
    }
}
