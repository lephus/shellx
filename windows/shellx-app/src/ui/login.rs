//! Sign-in card in the sidebar's machines area (spec §7.1).
//!
//! Signed out: a card with "Chưa đăng nhập" and the primary "Đăng nhập"
//! button. The button opens the panel: Email, Mật khẩu (masked), the primary
//! "Đăng nhập" button and, after a failed attempt, an ERROR line
//! "Đăng nhập không thành công: <core message>". Enter submits, Tab moves
//! between the fields, Esc closes. While the call runs the fields are
//! disabled and the button reads "Đang đăng nhập…".
//!
//! Other account errors (offline at start, a state-folder problem, a
//! register failure) show as one muted line; local terminals keep working and
//! the account service retries by itself.
//!
//! The password field is cleared as soon as the login is submitted: the
//! password then lives only in the login call.

use gpui::{
    ClickEvent, Context, Div, Entity, EventEmitter, Focusable, IntoElement, Render, Subscription,
    Window, div, prelude::*, px,
};
use shellx_model::account::AccountState;
use shellx_model::palette;
use shellx_model::strings::{Lang, Str, login_failed, t};

use super::account::AccountService;
use super::app::Services;
use super::button::{Kind, button};
use super::text_field::{TextField, TextFieldEvent};
use super::theme;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum LoginPanelEvent {
    /// Esc / Cancel: RootView gives the keyboard back to the terminal.
    Closed,
}

pub struct LoginPanel {
    account: Entity<AccountService>,
    email: Entity<TextField>,
    password: Entity<TextField>,
    open: bool,
    /// A login was submitted from this panel, so its error is shown here.
    submitted: bool,
    _subscriptions: Vec<Subscription>,
}

impl LoginPanel {
    pub fn new(
        account: Entity<AccountService>,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) -> Self {
        let email = cx.new(|cx| TextField::new(false, "", cx));
        let password = cx.new(|cx| TextField::new(true, "", cx));
        let subscriptions = vec![
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
                if logged_in && (this.open || this.submitted) {
                    // Signed in: the panel goes away and the keyboard goes
                    // back to the terminal.
                    this.open = false;
                    this.submitted = false;
                    cx.emit(LoginPanelEvent::Closed);
                }
                this.email.update(cx, |f, cx| f.set_disabled(busy, cx));
                this.password.update(cx, |f, cx| f.set_disabled(busy, cx));
                cx.notify();
            }),
        ];
        LoginPanel {
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

    fn open(&mut self, window: &mut Window, cx: &mut Context<Self>) {
        self.open = true;
        let target = if self.email.read(cx).text().trim().is_empty() {
            &self.email
        } else {
            &self.password
        };
        window.focus(&target.read(cx).focus_handle(cx));
        cx.notify();
    }

    fn close(&mut self, cx: &mut Context<Self>) {
        self.open = false;
        cx.emit(LoginPanelEvent::Closed);
        cx.notify();
    }

    fn submit(&mut self, window: &mut Window, cx: &mut Context<Self>) {
        if self.account.read(cx).login_in_flight() {
            return;
        }
        let email = self.email.read(cx).text().trim().to_string();
        let password = self.password.read(cx).text().to_string();
        if email.is_empty() {
            window.focus(&self.email.read(cx).focus_handle(cx));
            return;
        }
        if password.is_empty() {
            window.focus(&self.password.read(cx).focus_handle(cx));
            return;
        }
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

    fn card() -> Div {
        div()
            .flex()
            .flex_col()
            .gap(px(8.0))
            .mx(px(8.0))
            .my(px(6.0))
            .p(px(12.0))
            .rounded(px(8.0))
            .bg(theme::raise())
            .border_1()
            .border_color(theme::border())
    }

    fn render_panel(
        &self,
        lang: Lang,
        busy: bool,
        error: Option<String>,
        cx: &mut Context<Self>,
    ) -> Div {
        let submit_label = if busy {
            t(lang, Str::SigningIn)
        } else {
            t(lang, Str::Login)
        };
        Self::card()
            .child(
                div()
                    .flex()
                    .flex_col()
                    .gap(px(4.0))
                    .child(Self::label(t(lang, Str::Email)))
                    .child(self.email.clone()),
            )
            .child(
                div()
                    .flex()
                    .flex_col()
                    .gap(px(4.0))
                    .child(Self::label(t(lang, Str::Password)))
                    .child(self.password.clone()),
            )
            .children(error.map(Self::error_line))
            .child(
                div()
                    .flex()
                    .items_center()
                    .gap(px(8.0))
                    .child(
                        button("login-submit", submit_label, Kind::Primary, busy).when(
                            !busy,
                            |b| {
                                b.on_click(cx.listener(|this, _: &ClickEvent, window, cx| {
                                    this.submit(window, cx);
                                }))
                            },
                        ),
                    )
                    .child(
                        button("login-cancel", t(lang, Str::Cancel), Kind::Secondary, false)
                            .on_click(cx.listener(|this, _: &ClickEvent, _, cx| this.close(cx))),
                    ),
            )
    }
}

impl EventEmitter<LoginPanelEvent> for LoginPanel {}

impl Render for LoginPanel {
    fn render(&mut self, _window: &mut Window, cx: &mut Context<Self>) -> impl IntoElement {
        let lang = cx.global::<Services>().lang;
        let account = self.account.read(cx);
        let state = account.state().clone();
        let busy = account.login_in_flight();
        let error = match &state {
            AccountState::Error(e) => Some(e.clone()),
            _ => None,
        };
        let login_error = error
            .as_ref()
            .filter(|_| self.submitted)
            .map(|e| login_failed(lang, &e.message));

        if self.open {
            return self.render_panel(lang, busy, login_error, cx);
        }
        let signed_out = matches!(state, AccountState::LoggedOut);
        if signed_out || login_error.is_some() || (busy && self.submitted) {
            return Self::card()
                .child(
                    div()
                        .text_color(theme::text())
                        .child(t(lang, Str::NotLoggedIn)),
                )
                .children(login_error.map(Self::error_line))
                .child(div().flex().child(
                    button("login-open", t(lang, Str::Login), Kind::Primary, false).on_click(
                        cx.listener(|this, _: &ClickEvent, window, cx| this.open(window, cx)),
                    ),
                ));
        }
        // Not from this panel: offline at start, state folder, register.
        match error {
            Some(e) => div()
                .px(px(14.0))
                .py(px(6.0))
                .text_size(theme::SMALL_SIZE)
                .text_color(theme::muted())
                .child(format!("{} · {}", t(lang, Str::Error), e.message)),
            None => div(),
        }
    }
}
