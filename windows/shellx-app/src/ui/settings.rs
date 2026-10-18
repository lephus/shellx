//! Settings / About panel (spec §7.1): a 360 px right panel over the main
//! area, opened by the title bar gear or Ctrl+, and closed by Esc or its
//! close button. Sections: Tài khoản, Cập nhật, Ngôn ngữ (read-only) and
//! Giới thiệu (with the CC BY 4.0 icon credit).

use gpui::{
    ClickEvent, Context, Div, Entity, EventEmitter, FocusHandle, Focusable, FontWeight,
    IntoElement, KeyDownEvent, Render, SharedString, Window, div, prelude::*, px,
};
use shellx_model::account::AccountState;
use shellx_model::palette;
use shellx_model::strings::{Lang, Str, t, update_available};
use shellx_model::update::{UpdateStatus, download_url};

use super::account::AccountService;
use super::app::Services;
use super::button::{Kind, button};
use super::theme;
use super::update_banner::open_https;

pub const WIDTH: f32 = 360.0;
pub const SOURCE_URL: &str = "https://github.com/lephus/shellx";

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum SettingsEvent {
    /// Esc / close button: RootView gives the keyboard back to the terminal.
    Closed,
}

pub struct SettingsPanel {
    account: Entity<AccountService>,
    focus: FocusHandle,
    open: bool,
}

impl EventEmitter<SettingsEvent> for SettingsPanel {}

impl Focusable for SettingsPanel {
    fn focus_handle(&self, _: &gpui::App) -> FocusHandle {
        self.focus.clone()
    }
}

impl SettingsPanel {
    pub fn new(account: Entity<AccountService>, cx: &mut Context<Self>) -> Self {
        cx.observe(&account, |_, _, cx| cx.notify()).detach();
        SettingsPanel {
            account,
            focus: cx.focus_handle(),
            open: false,
        }
    }

    pub fn is_open(&self) -> bool {
        self.open
    }

    pub fn open(&mut self, window: &mut Window, cx: &mut Context<Self>) {
        self.open = true;
        window.focus(&self.focus);
        cx.notify();
    }

    pub fn close(&mut self, cx: &mut Context<Self>) {
        if self.open {
            self.open = false;
            cx.emit(SettingsEvent::Closed);
            cx.notify();
        }
    }

    fn on_key_down(&mut self, event: &KeyDownEvent, _: &mut Window, cx: &mut Context<Self>) {
        if event.keystroke.key == "escape" {
            cx.stop_propagation();
            self.close(cx);
        }
    }

    fn section(title: &str) -> Div {
        div()
            .flex()
            .flex_col()
            .gap(px(8.0))
            .px(px(16.0))
            .py(px(14.0))
            .border_b_1()
            .border_color(theme::border())
            .child(
                div()
                    .text_size(theme::PILL_SIZE)
                    .font_weight(FontWeight::SEMIBOLD)
                    .text_color(theme::muted())
                    .child(title.to_uppercase()),
            )
    }

    fn muted(text: impl Into<SharedString>) -> Div {
        div()
            .text_size(theme::SMALL_SIZE)
            .text_color(theme::muted())
            .child(text.into())
    }

    fn account_section(&self, lang: Lang, cx: &mut Context<Self>) -> Div {
        let account = self.account.read(cx);
        let signed_in = matches!(account.state(), AccountState::LoggedIn { .. });
        let who = if signed_in {
            account
                .email()
                .map_or_else(|| t(lang, Str::SignedIn).to_string(), str::to_string)
        } else {
            t(lang, Str::NotLoggedIn).to_string()
        };
        let notice = account.notice().map(|e| e.message.clone());
        Self::section(t(lang, Str::Account))
            .child(div().text_color(theme::text_hi()).truncate().child(who))
            .children(notice.filter(|m| !m.is_empty()).map(|m| {
                div()
                    .text_size(theme::SMALL_SIZE)
                    .text_color(theme::hsla(palette::ERROR))
                    .child(m)
            }))
            .when(signed_in, |s| {
                s.child(
                    div().flex().child(
                        button(
                            "settings-logout",
                            t(lang, Str::Logout),
                            Kind::Secondary,
                            false,
                        )
                        .on_click(cx.listener(
                            |this, _: &ClickEvent, _, cx| {
                                this.account.update(cx, |a, cx| a.logout(cx));
                            },
                        )),
                    ),
                )
            })
    }

    fn update_section(&self, lang: Lang, cx: &mut Context<Self>) -> Div {
        let account = self.account.read(cx);
        let status = account.update_status().clone();
        let checking = account.checking();
        let text = if checking {
            t(lang, Str::Checking).to_string()
        } else {
            match &status {
                UpdateStatus::UpToDate => t(lang, Str::UpToDate).to_string(),
                UpdateStatus::Available { version, .. } => update_available(lang, version),
                UpdateStatus::Required { .. } => t(lang, Str::UpdateRequired).to_string(),
                UpdateStatus::Unknown if account.checked() => t(lang, Str::CheckFailed).to_string(),
                UpdateStatus::Unknown => String::new(),
            }
        };
        let url = download_url(&status).map(str::to_string);
        Self::section(t(lang, Str::Updates))
            .child(div().text_color(theme::text()).child(format!(
                "{} {}",
                t(lang, Str::Version),
                shellx_model::VERSION
            )))
            .when(!text.is_empty(), |s| s.child(Self::muted(text)))
            .child(
                div()
                    .flex()
                    .flex_row()
                    .gap(px(8.0))
                    .when_some(url, |row, url| {
                        row.child(
                            button(
                                "settings-download",
                                t(lang, Str::Download),
                                Kind::Primary,
                                false,
                            )
                            .on_click(move |_, _, cx| open_https(cx, &url)),
                        )
                    })
                    .child(
                        button(
                            "settings-check-update",
                            t(lang, Str::CheckUpdate),
                            Kind::Secondary,
                            checking,
                        )
                        .when(!checking, |b| {
                            b.on_click(cx.listener(|this, _: &ClickEvent, _, cx| {
                                this.account.update(cx, |a, cx| a.check_update(cx));
                            }))
                        }),
                    ),
            )
    }

    fn language_section(lang: Lang) -> Div {
        Self::section(t(lang, Str::Language))
            .child(
                div()
                    .text_color(theme::text())
                    .child(t(lang, Str::LanguageName)),
            )
            .child(Self::muted(t(lang, Str::LanguageHint)))
    }

    fn about_section(lang: Lang) -> Div {
        Self::section(t(lang, Str::About))
            .child(
                div()
                    .text_color(theme::text_hi())
                    .font_weight(FontWeight::SEMIBOLD)
                    .child(format!(
                        "{} {}",
                        t(lang, Str::AppName),
                        shellx_model::VERSION
                    )),
            )
            .child(Self::muted(t(lang, Str::CmuxCredits)))
            .child(Self::muted(t(lang, Str::IconCredits)))
            .child(Self::muted(t(lang, Str::FontCredits)))
            .child(
                div()
                    .id("settings-source")
                    .text_size(theme::SMALL_SIZE)
                    .text_color(theme::hsla(palette::PRIMARY_TEXT))
                    .cursor_pointer()
                    .child(SOURCE_URL)
                    .on_click(|_, _, cx| open_https(cx, SOURCE_URL)),
            )
    }
}

impl Render for SettingsPanel {
    fn render(&mut self, _window: &mut Window, cx: &mut Context<Self>) -> impl IntoElement {
        let lang = cx.global::<Services>().lang;
        let header = div()
            .flex()
            .flex_row()
            .items_center()
            .justify_between()
            .flex_none()
            .h(px(40.0))
            .px(px(16.0))
            .border_b_1()
            .border_color(theme::border())
            .child(
                div()
                    .font_weight(FontWeight::SEMIBOLD)
                    .text_color(theme::text_hi())
                    .child(t(lang, Str::Settings)),
            )
            .child(
                div()
                    .id("settings-close")
                    .px(px(8.0))
                    .cursor_pointer()
                    .text_color(theme::muted())
                    .hover(|s| s.text_color(theme::text()))
                    .child("×")
                    .on_click(cx.listener(|this, _: &ClickEvent, _, cx| this.close(cx))),
            );
        div()
            .id("settings-panel")
            .track_focus(&self.focus)
            .occlude()
            .absolute()
            .top(px(crate::workspace::TITLEBAR_H))
            .right_0()
            .bottom_0()
            .w(px(WIDTH))
            .flex()
            .flex_col()
            .bg(theme::raise())
            .border_l_1()
            .border_color(theme::border())
            .on_key_down(cx.listener(Self::on_key_down))
            .child(header)
            .child(
                div()
                    .id("settings-body")
                    .flex_1()
                    .min_h_0()
                    .overflow_y_scroll()
                    .child(self.account_section(lang, cx))
                    .child(self.update_section(lang, cx))
                    .child(Self::language_section(lang))
                    .child(Self::about_section(lang)),
            )
    }
}
