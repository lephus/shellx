//! The "Sign in to ShellX" dialog (the Mac's sign-in sheet): Settings -> Account opens it (and the
//! machines "+" while signed out, and after the server ended the session). The window never asks for a
//! password: sign-in is Google only.
//!
//! A centred card over a backdrop that swallows clicks: the title ("Switch to Google sign-in" and its
//! intro when it switches a password session), Google's branded "Continue with Google" button and,
//! while the browser works, "Waiting for Google..." with a hint. After a failed attempt of this dialog
//! an ERROR line explains it (`shellx_model::strings::google_error`). Enter starts, Esc / Cancel
//! cancels a running flow and closes. It closes itself when the flow it started succeeds.
//!
//! Other account errors (offline at start, a state-folder problem, a register failure) are not shown
//! here: Settings -> Account shows them.

use gpui::{
    App, ClickEvent, Context, Div, Entity, EventEmitter, FocusHandle, FontWeight, IntoElement,
    KeyDownEvent, Render, Window, div, prelude::*, px,
};
use shellx_model::account::AccountState;
use shellx_model::core_api::GooglePurpose;
use shellx_model::palette;
use shellx_model::strings::{Lang, Str, google_error, t};

use super::account::AccountService;
use super::app::Services;
use super::button::{Kind, button};
use super::google_button::google_button;
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
    focus: FocusHandle,
    purpose: GooglePurpose,
    open: bool,
    /// A Google flow was started from this dialog, so its error is shown here.
    started: bool,
    _subscription: gpui::Subscription,
}

impl SignInDialog {
    pub fn new(
        account: Entity<AccountService>,
        _window: &mut Window,
        cx: &mut Context<Self>,
    ) -> Self {
        let subscription = cx.observe(&account, |this, account, cx| {
            if this.open && this.finished_ok(account.read(cx)) {
                // Signed in (or switched): the dialog goes away and the keyboard goes back to the
                // panel below, else the terminal.
                this.open = false;
                this.started = false;
                cx.emit(SignInEvent::Closed);
            }
            cx.notify();
        });
        SignInDialog {
            account,
            focus: cx.focus_handle(),
            purpose: GooglePurpose::SignIn,
            open: false,
            started: false,
            _subscription: subscription,
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

    /// Shows the dialog (fresh: no old error) and gives it the keyboard. RootView only calls it when
    /// nothing above the dialog is open (`Panels::may_open`).
    pub fn open(&mut self, purpose: GooglePurpose, window: &mut Window, cx: &mut Context<Self>) {
        self.purpose = purpose;
        self.open = true;
        self.started = false;
        window.focus(&self.focus);
        cx.emit(SignInEvent::Opened);
        cx.notify();
    }

    /// The dialog is shown and holds the keyboard.
    pub fn is_open(&self) -> bool {
        self.open
    }

    /// The handle the keyboard belongs to while the dialog is open.
    pub fn focus_target(&self, _cx: &App) -> FocusHandle {
        self.focus.clone()
    }

    /// Esc / Cancel: a running Google flow is cancelled, then the dialog closes.
    pub fn close(&mut self, cx: &mut Context<Self>) {
        if self.account.read(cx).google_in_flight().is_some() {
            self.account
                .update(cx, |account, cx| account.cancel_google(cx));
        }
        if self.open {
            self.open = false;
            self.started = false;
            cx.emit(SignInEvent::Closed);
        }
        cx.notify();
    }

    /// Enter / the button: starts the flow unless one runs or the flow would ignore it.
    fn start(&mut self, cx: &mut Context<Self>) {
        let account = self.account.read(cx);
        let can = account.google_in_flight().is_none()
            && match self.purpose {
                GooglePurpose::SignIn => account.accepts_login(),
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

    fn on_key_down(&mut self, event: &KeyDownEvent, _: &mut Window, cx: &mut Context<Self>) {
        match event.keystroke.key.as_str() {
            "enter" => {
                cx.stop_propagation();
                self.start(cx);
            }
            "escape" => {
                cx.stop_propagation();
                self.close(cx);
            }
            _ => {}
        }
    }

    fn error_line(text: String) -> Div {
        div()
            .text_size(theme::SMALL_SIZE)
            .text_color(theme::hsla(palette::ERROR))
            .child(text)
    }

    fn muted_line(text: &'static str) -> Div {
        div()
            .text_size(theme::SMALL_SIZE)
            .text_color(theme::muted())
            .child(text)
    }
}

impl EventEmitter<SignInEvent> for SignInDialog {}

impl Render for SignInDialog {
    fn render(&mut self, _window: &mut Window, cx: &mut Context<Self>) -> impl IntoElement {
        let lang: Lang = cx.global::<Services>().lang;
        let account = self.account.read(cx);
        let waiting = account.google_in_flight().is_some();
        // Only a failure of this dialog's own attempt; other account errors are Settings -> Account's.
        let error = if self.started && !waiting {
            match (self.purpose, account.state()) {
                (GooglePurpose::SignIn, AccountState::Error(e)) => google_error(lang, &e.code),
                (GooglePurpose::Link, _) => {
                    account.notice().and_then(|e| google_error(lang, &e.code))
                }
                _ => None,
            }
        } else {
            None
        };
        let title = match self.purpose {
            GooglePurpose::SignIn => t(lang, Str::SignInTitle),
            GooglePurpose::Link => t(lang, Str::SwitchToGoogle),
        };
        let action = if waiting {
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
        } else {
            div().flex().justify_center().child(
                google_button("sign-in-google", t(lang, Str::ContinueWithGoogle))
                    .on_click(cx.listener(|this, _: &ClickEvent, _, cx| this.start(cx))),
            )
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
            .child(
                div()
                    .text_size(px(15.0))
                    .font_weight(FontWeight::SEMIBOLD)
                    .text_color(theme::text_hi())
                    .child(title),
            )
            .when(self.purpose == GooglePurpose::Link, |c| {
                c.child(Self::muted_line(t(lang, Str::SwitchToGoogleIntro)))
            })
            .child(action)
            .children(error.map(Self::error_line))
            .child(
                div().flex().flex_row().justify_end().child(
                    button(
                        "sign-in-cancel",
                        t(lang, Str::Cancel),
                        Kind::Secondary,
                        false,
                    )
                    .on_click(cx.listener(|this, _: &ClickEvent, _, cx| this.close(cx))),
                ),
            );

        // Covers the window below the title bar: the backdrop blocks the mouse for everything under
        // it, and the keyboard is on the dialog's own handle.
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
