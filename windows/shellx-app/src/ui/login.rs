//! The "Sign in to ShellX" dialog (the Mac's sign-in sheet): Settings ->
//! Account opens it (and the machines "+" while signed out); the window never
//! asks for a password by itself.
//!
//! A centred card over a backdrop that swallows clicks: the title, Email and
//! Password (masked) fields, after a failed attempt an ERROR line
//! "Đăng nhập không thành công: <core message>", and a right-aligned
//! "Hủy" / "Đăng nhập" pair. "Đăng nhập" stays disabled until both fields
//! have text. Enter submits, Tab moves between the fields, Esc closes. While
//! the call runs the fields are disabled and the button reads
//! "Đang đăng nhập…". It closes itself when the account becomes signed in.
//!
//! Other account errors (offline at start, a state-folder problem, a
//! register failure) are not shown here: Settings -> Account shows them;
//! local terminals keep working and the account service retries by itself.
//!
//! The password field is cleared (its buffer zeroed) as soon as a login is
//! accepted, and when the dialog closes: the password then lives only in the
//! login call. A submit the account flow would ignore (this machine is being
//! registered) keeps the typed password and starts nothing.

use gpui::{
    App, ClickEvent, Context, Div, Entity, EventEmitter, FocusHandle, Focusable, FontWeight,
    IntoElement, Render, Subscription, Window, div, prelude::*, px,
};
use shellx_model::account::AccountState;
use shellx_model::palette;
use shellx_model::strings::{Lang, Str, login_failed, t};

use super::account::AccountService;
use super::app::Services;
use super::button::{Kind, button};
use super::text_field::{TextField, TextFieldEvent};
use super::theme;

/// Card width (the Mac's sheet).
const CARD_W: f32 = 340.0;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum SignInEvent {
    /// Esc / Cancel / signed in: RootView gives the keyboard to the panel
    /// below, else back to the terminal.
    Closed,
    /// `open` ran: RootView redraws (the dialog now holds the keyboard).
    Opened,
}

pub struct SignInDialog {
    account: Entity<AccountService>,
    email: Entity<TextField>,
    password: Entity<TextField>,
    open: bool,
    /// A login was submitted from this dialog, so its error is shown here.
    submitted: bool,
    _subscriptions: Vec<Subscription>,
}

impl SignInDialog {
    pub fn new(
        account: Entity<AccountService>,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) -> Self {
        let email = cx.new(|cx| TextField::new(false, "", cx));
        let password = cx.new(|cx| TextField::new(true, "", cx));
        let subscriptions = vec![
            // Typing enables or disables the "Đăng nhập" button.
            cx.observe(&email, |_, _, cx| cx.notify()),
            cx.observe(&password, |_, _, cx| cx.notify()),
            cx.subscribe_in(
                &email,
                window,
                |this, _, event: &TextFieldEvent, window, cx| {
                    this.on_field_event(*event, window, cx);
                },
            ),
            cx.subscribe_in(
                &password,
                window,
                |this, _, event: &TextFieldEvent, window, cx| {
                    this.on_field_event(*event, window, cx);
                },
            ),
            cx.observe(&account, |this, account, cx| {
                let (logged_in, busy) = {
                    let account = account.read(cx);
                    (
                        matches!(account.state(), AccountState::LoggedIn { .. }),
                        account.login_in_flight(),
                    )
                };
                if logged_in && this.open {
                    // Signed in: the dialog goes away and the keyboard goes
                    // back to the panel below, else the terminal.
                    this.password.update(cx, |f, cx| f.clear(cx));
                    this.open = false;
                    this.submitted = false;
                    cx.emit(SignInEvent::Closed);
                }
                this.email.update(cx, |f, cx| f.set_disabled(busy, cx));
                this.password.update(cx, |f, cx| f.set_disabled(busy, cx));
                cx.notify();
            }),
        ];
        SignInDialog {
            account,
            email,
            password,
            open: false,
            submitted: false,
            _subscriptions: subscriptions,
        }
    }

    fn on_field_event(
        &mut self,
        event: TextFieldEvent,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) {
        match event {
            TextFieldEvent::Submit => self.submit(window, cx),
            TextFieldEvent::Cancel => self.close(cx),
            TextFieldEvent::Next | TextFieldEvent::Prev => {
                let email_focused = self.email.read(cx).focus_handle(cx).is_focused(window);
                let next = if email_focused {
                    &self.password
                } else {
                    &self.email
                };
                window.focus(&next.read(cx).focus_handle(cx));
            }
        }
    }

    /// Shows the dialog (fresh: no password, no old error) and gives its
    /// field the keyboard. RootView only calls it when nothing above the
    /// dialog is open (`Panels::may_open`).
    pub fn open(&mut self, window: &mut Window, cx: &mut Context<Self>) {
        self.password.update(cx, |f, cx| f.clear(cx));
        self.open = true;
        self.submitted = false;
        window.focus(&self.focus_target(cx));
        cx.emit(SignInEvent::Opened);
        cx.notify();
    }

    /// The dialog is shown; a field holds the keyboard.
    pub fn is_open(&self) -> bool {
        self.open
    }

    /// The field the keyboard belongs to while the dialog is open: Email
    /// while it is empty, else Mật khẩu.
    pub fn focus_target(&self, cx: &App) -> FocusHandle {
        let target = if self.email.read(cx).text().trim().is_empty() {
            &self.email
        } else {
            &self.password
        };
        target.read(cx).focus_handle(cx)
    }

    /// Esc / Cancel: the typed password is wiped.
    pub fn close(&mut self, cx: &mut Context<Self>) {
        self.password.update(cx, |f, cx| f.clear(cx));
        if self.open {
            self.open = false;
            self.submitted = false;
            cx.emit(SignInEvent::Closed);
        }
        cx.notify();
    }

    fn submit(&mut self, window: &mut Window, cx: &mut Context<Self>) {
        // Ignored by the flow (a login runs, or this machine is being
        // registered): keep the password, start nothing.
        if !self.account.read(cx).accepts_login() {
            return;
        }
        let email = self.email.read(cx).text().trim().to_string();
        if email.is_empty() {
            window.focus(&self.email.read(cx).focus_handle(cx));
            return;
        }
        if self.password.read(cx).text().is_empty() {
            window.focus(&self.password.read(cx).focus_handle(cx));
            return;
        }
        // The only copy outside the field; it moves into the login call.
        let password = self.password.read(cx).text().to_string();
        self.password.update(cx, |f, cx| f.clear(cx));
        window.focus(&self.password.read(cx).focus_handle(cx));
        self.submitted = true;
        self.account
            .update(cx, |account, cx| account.login(email, password, cx));
        cx.notify();
    }

    fn label(text: &'static str) -> Div {
        div()
            .text_size(theme::SMALL_SIZE)
            .text_color(theme::muted())
            .child(text)
    }

    fn error_line(text: String) -> Div {
        div()
            .text_size(theme::SMALL_SIZE)
            .text_color(theme::hsla(palette::ERROR))
            .child(text)
    }

    /// A label over its field.
    fn field(label: &'static str, field: &Entity<TextField>) -> Div {
        div()
            .flex()
            .flex_col()
            .gap(px(4.0))
            .child(Self::label(label))
            .child(field.clone())
    }
}

impl EventEmitter<SignInEvent> for SignInDialog {}

impl Render for SignInDialog {
    fn render(&mut self, _window: &mut Window, cx: &mut Context<Self>) -> impl IntoElement {
        let lang: Lang = cx.global::<Services>().lang;
        let account = self.account.read(cx);
        let busy = account.login_in_flight();
        // Only a failure of this dialog's own attempt; other account errors
        // are Settings -> Account's.
        let error = match account.state() {
            AccountState::Error(e) if self.submitted => Some(login_failed(lang, &e.message)),
            _ => None,
        };
        let filled = !self.email.read(cx).text().trim().is_empty()
            && !self.password.read(cx).text().is_empty();
        let can_submit = filled && !busy;
        let submit_label = if busy {
            t(lang, Str::SigningIn)
        } else {
            t(lang, Str::Login)
        };

        let card =
            div()
                .flex()
                .flex_col()
                .gap(px(12.0))
                .w(px(CARD_W))
                .p(px(20.0))
                .rounded(px(10.0))
                .border_1()
                .border_color(theme::border())
                .bg(theme::raise())
                .child(
                    div()
                        .text_size(px(15.0))
                        .font_weight(FontWeight::SEMIBOLD)
                        .text_color(theme::text_hi())
                        .child(t(lang, Str::SignInTitle)),
                )
                .child(Self::field(t(lang, Str::EmailAddress), &self.email))
                .child(Self::field(t(lang, Str::Password), &self.password))
                .children(error.map(Self::error_line))
                .child(
                    div()
                        .flex()
                        .flex_row()
                        .justify_end()
                        .gap(px(8.0))
                        .child(
                            button(
                                "sign-in-cancel",
                                t(lang, Str::Cancel),
                                Kind::Secondary,
                                false,
                            )
                            .on_click(cx.listener(|this, _: &ClickEvent, _, cx| this.close(cx))),
                        )
                        .child(
                            button("sign-in-submit", submit_label, Kind::Primary, !can_submit)
                                .when(can_submit, |b| {
                                    b.on_click(cx.listener(|this, _: &ClickEvent, window, cx| {
                                        this.submit(window, cx);
                                    }))
                                }),
                        ),
                );

        // Covers the window below the title bar: the backdrop blocks the
        // mouse for everything under it, and the keyboard is in a field.
        div()
            .id("sign-in-dialog")
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
