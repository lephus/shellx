//! Settings / About panel (spec §7.1): a 360 px right panel over the main
//! area, opened by the title bar gear or Ctrl+, and closed by Esc or its
//! close button. Sections: Tài khoản (where sign-in lives: "Đăng nhập…" asks
//! RootView for the sign-in dialog), Terminal (the shell new tabs start, or a
//! command line), Hiển thị (the display mode, and "Thử lại chế độ hiển thị
//! thường"), Cập nhật, Ngôn ngữ (read-only) and Giới thiệu (with the test label
//! and the CC BY 4.0 icon credit).

use gpui::{
    ClickEvent, Context, Div, Entity, EventEmitter, FocusHandle, Focusable, FontWeight,
    IntoElement, KeyDownEvent, Render, SharedString, Stateful, Subscription, Window, div,
    prelude::*, px, svg,
};
use shellx_model::account::AccountState;
use shellx_model::account::DELETE_ACCOUNT_URL;
use shellx_model::palette;
use shellx_model::shell::{CustomShellError, ShellChoice, ShellKind, custom_launch, kind_label};
use shellx_model::strings::{
    Lang, Str, added_from, custom_shell_error, shell_auto_label, sign_in_method_label, t,
    update_available, will_run,
};
use shellx_model::update::{UpdateStatus, download_url};

use crate::{build_info, startup};

use super::account::AccountService;
use super::app::Services;
use super::assets::Icon;
use super::button::{Kind, button};
use super::text_field::{TextField, TextFieldEvent};
use super::theme;
use super::update_banner::open_https;
use crate::local_pty::settings::{
    ShellOption, is_program_file, is_selected, shell_options, shells, shown_choice,
};

pub const WIDTH: f32 = 360.0;
pub const SOURCE_URL: &str = "https://github.com/lephus/shellx";

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum SettingsEvent {
    /// Esc / close button: RootView gives the keyboard back to the terminal.
    Closed,
    /// "Đăng nhập…" (signed out): RootView opens the sign-in dialog.
    SignInRequested,
    /// "Chuyển…" (signed in with a password): RootView opens the dialog that switches to Google.
    SwitchToGoogleRequested,
}

pub struct SettingsPanel {
    account: Entity<AccountService>,
    focus: FocusHandle,
    open: bool,
    /// Settings › Terminal's custom command line.
    shell_field: Entity<TextField>,
    /// The custom row was clicked and no line of it is stored yet.
    custom_open: bool,
    /// The line last sent to the check, its number, and the answer for it
    /// (the program it runs, or what is wrong); `None` while it runs.
    shell_line: String,
    shell_seq: u64,
    shell_check: Option<Result<String, CustomShellError>>,
    /// Lines to the checking thread (started at the first check).
    shell_checker: Option<async_channel::Sender<(u64, String)>>,
    /// A shell lookup started by `open` has not ended.
    refreshing: bool,
    /// The last choice could not be saved.
    shell_not_saved: bool,
    /// "Try standard display mode again" was stored for the next start.
    standard_requested: bool,
    _subscriptions: Vec<Subscription>,
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
        let lang = cx.global::<Services>().lang;
        let shell_field =
            cx.new(|cx| TextField::new(false, t(lang, Str::CustomShellPlaceholder), cx));
        let subscriptions = vec![
            cx.observe(&shell_field, |this, _, cx| {
                this.shell_line_changed(false, cx)
            }),
            cx.subscribe(&shell_field, |this, _, event: &TextFieldEvent, cx| {
                if *event == TextFieldEvent::Cancel {
                    this.close(cx);
                }
            }),
        ];
        let panel = SettingsPanel {
            account,
            focus: cx.focus_handle(),
            open: false,
            shell_field,
            custom_open: false,
            shell_line: String::new(),
            shell_seq: 0,
            shell_check: None,
            shell_checker: None,
            refreshing: false,
            shell_not_saved: false,
            standard_requested: false,
            _subscriptions: subscriptions,
        };
        // Development only (Ruling 24): Settings is open at start.
        #[cfg(target_os = "macos")]
        let panel = {
            let mut panel = panel;
            if std::env::var("SHELLX_DEV_PREVIEW").as_deref() == Ok("settings") {
                panel.open = true;
                panel.fill_stored_line(cx);
                panel.refresh_shells(cx);
            }
            panel
        };
        panel
    }

    pub fn is_open(&self) -> bool {
        self.open
    }

    pub fn open(&mut self, window: &mut Window, cx: &mut Context<Self>) {
        self.open = true;
        window.focus(&self.focus);
        if matches!(self.account.read(cx).state(), AccountState::LoggedIn { .. }) {
            self.account
                .update(cx, |a, cx| a.refresh_sign_in_methods(cx));
        }
        self.fill_stored_line(cx);
        self.refresh_shells(cx);
        cx.notify();
    }

    /// The custom row starts from what is stored.
    fn fill_stored_line(&mut self, cx: &mut Context<Self>) {
        self.custom_open = false;
        self.shell_not_saved = false;
        if let ShellChoice::Custom { command_line } = shells().choice() {
            self.shell_field
                .update(cx, |field, cx| field.set_text(&command_line, cx));
        }
    }

    /// Looks the shells up again on a thread of its own (a slow PATH can take
    /// minutes), then redraws from `shells().snapshot()`.
    fn refresh_shells(&mut self, cx: &mut Context<Self>) {
        if self.refreshing {
            return;
        }
        let (done, ended) = async_channel::bounded::<()>(1);
        let started = std::thread::Builder::new()
            .name("shell-refresh".into())
            .spawn(move || {
                shells().refresh_now();
                let _ = done.send_blocking(());
            });
        if started.is_err() {
            return;
        }
        self.refreshing = true;
        cx.spawn(async move |this, cx| {
            let _ = ended.recv().await;
            let _ = this.update(cx, |this, cx| {
                this.refreshing = false;
                cx.notify();
            });
        })
        .detach();
    }

    /// A row of Settings › Terminal was clicked. Every row but the custom one
    /// is stored at once; the custom one waits for a line that names a program.
    fn choose(&mut self, option: ShellOption, window: &mut Window, cx: &mut Context<Self>) {
        match option {
            ShellOption::Auto { .. } => {
                self.custom_open = false;
                self.store_choice(ShellChoice::Auto);
            }
            ShellOption::Known(shell) => {
                self.custom_open = false;
                self.store_choice(ShellChoice::Known { shell });
            }
            ShellOption::Custom => {
                self.custom_open = true;
                window.focus(&self.shell_field.focus_handle(cx));
                self.shell_line_changed(true, cx);
            }
        }
        cx.notify();
    }

    fn store_choice(&mut self, choice: ShellChoice) {
        self.shell_not_saved = shells().set_choice(choice).is_err();
    }

    /// The field's text changed (or `again`: check it anyway). Each line is
    /// checked off the UI thread; on the Mac nothing is checked (Ruling 19).
    fn shell_line_changed(&mut self, again: bool, cx: &mut Context<Self>) {
        let field = self.shell_field.read(cx);
        if field.composing() {
            return;
        }
        let text = field.text().to_string();
        if text == self.shell_line && !again {
            return;
        }
        self.shell_line = text.clone();
        self.shell_check = None;
        self.shell_seq += 1;
        cx.notify();
        if cfg!(windows) {
            self.check_shell_line(self.shell_seq, text, cx);
        }
    }

    /// Sends a line to the checking thread, which answers only the newest of
    /// the lines waiting for it: typing on a PC with a slow PATH never piles
    /// up checks.
    fn check_shell_line(&mut self, seq: u64, line: String, cx: &mut Context<Self>) {
        if self.shell_checker.is_none() {
            let (requests, waiting) = async_channel::unbounded::<(u64, String)>();
            let (answers, answered) = async_channel::unbounded();
            let probe = shells().probe();
            let started = std::thread::Builder::new()
                .name("shell-line-check".into())
                .spawn(move || {
                    while let Ok(mut request) = waiting.recv_blocking() {
                        while let Ok(newer) = waiting.try_recv() {
                            request = newer;
                        }
                        let (seq, line) = request;
                        let answer =
                            custom_launch(&line, &probe, &is_program_file).map(|l| l.program);
                        if answers.send_blocking((seq, line, answer)).is_err() {
                            return;
                        }
                    }
                });
            if started.is_err() {
                return;
            }
            cx.spawn(async move |this, cx| {
                while let Ok((seq, line, answer)) = answered.recv().await {
                    let updated = this.update(cx, |this, cx| {
                        this.shell_line_checked(seq, line, answer, cx);
                    });
                    if updated.is_err() {
                        return;
                    }
                }
            })
            .detach();
            self.shell_checker = Some(requests);
        }
        if let Some(requests) = &self.shell_checker {
            let _ = requests.try_send((seq, line));
        }
    }

    /// A line that names a program is stored as the choice; any other keeps
    /// the stored choice and says what is wrong.
    fn shell_line_checked(
        &mut self,
        seq: u64,
        line: String,
        answer: Result<String, CustomShellError>,
        cx: &mut Context<Self>,
    ) {
        if seq != self.shell_seq {
            return;
        }
        let stores = answer.is_ok() && (self.custom_open || self.stored_custom());
        self.shell_check = Some(answer);
        if stores {
            let choice = ShellChoice::Custom { command_line: line };
            if shells().choice() != choice {
                self.store_choice(choice);
            }
            self.custom_open = false;
        }
        cx.notify();
    }

    fn stored_custom(&self) -> bool {
        matches!(shells().choice(), ShellChoice::Custom { .. })
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
        // Everything below comes from the view (Ruling 33): no code and no text from the core is drawn.
        let view = account.view(lang);
        let signed_in = matches!(account.state(), AccountState::LoggedIn { .. });
        let who = if signed_in {
            account
                .email()
                .map_or_else(|| t(lang, Str::SignedIn).to_string(), str::to_string)
        } else {
            t(lang, Str::NotLoggedIn).to_string()
        };
        Self::section(t(lang, Str::Account))
            .child(div().text_color(theme::text_hi()).truncate().child(who))
            .when(!signed_in, |s| {
                s.child(Self::muted(t(lang, Str::SignInSubtitle)))
            })
            .when(view.google_switch, |s| {
                s.child(
                    div()
                        .flex()
                        .flex_col()
                        .gap(px(4.0))
                        .child(
                            div()
                                .text_color(theme::text_hi())
                                .child(t(lang, Str::SwitchToGoogle)),
                        )
                        .child(Self::muted(t(lang, Str::SwitchToGoogleIntro)))
                        .child(
                            div().flex().child(
                                button(
                                    "settings-switch-google",
                                    t(lang, Str::SwitchEllipsis),
                                    Kind::Primary,
                                    false,
                                )
                                .on_click(cx.listener(
                                    |_, _: &ClickEvent, _, cx| {
                                        cx.emit(SettingsEvent::SwitchToGoogleRequested);
                                    },
                                )),
                            ),
                        ),
                )
            })
            .when(signed_in, |s| s.child(self.methods_block(lang, cx)))
            // A failed sign-out or methods list, else why the account is not working (offline at
            // start, a state-folder problem): the sidebar does not show these.
            .children(view.error.map(|m| {
                div()
                    .text_size(theme::SMALL_SIZE)
                    .text_color(theme::hsla(palette::ERROR))
                    .child(m)
            }))
            .when(view.session_expired, |s| {
                s.child(Self::muted(t(lang, Str::SessionExpired)))
            })
            .when_some(view.sign_in, |s, label| {
                s.child(div().flex().child(
                    button("settings-sign-in", t(lang, label), Kind::Primary, false).on_click(
                        cx.listener(|_, _: &ClickEvent, _, cx| {
                            cx.emit(SettingsEvent::SignInRequested);
                        }),
                    ),
                ))
            })
            .when(view.sign_out, |s| {
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

    /// "Sign-in methods": one row per identity; an Apple ID can be removed; the link to delete the account.
    fn methods_block(&self, lang: Lang, cx: &mut Context<Self>) -> Div {
        let account = self.account.read(cx);
        let removing = account.removing_sign_in_method().map(str::to_string);
        let rows: Vec<Div> = account
            .sign_in_methods()
            .unwrap_or_default()
            .iter()
            .map(|m| {
                let hidden = m.email.is_empty() || m.is_private_email;
                let who = if m.is_apple() {
                    if hidden {
                        t(lang, Str::HiddenEmail).to_string()
                    } else {
                        m.email.clone()
                    }
                } else {
                    m.email.clone()
                };
                let kind = sign_in_method_label(&m.provider);
                let id = m.identity_id.clone();
                let busy = removing.as_deref() == Some(m.identity_id.as_str());
                div()
                    .flex()
                    .flex_row()
                    .items_center()
                    .justify_between()
                    .gap(px(8.0))
                    .child(
                        div()
                            .flex()
                            .flex_col()
                            .min_w_0()
                            .child(div().text_color(theme::text()).child(t(lang, kind)))
                            .child(Self::muted(who))
                            .children(
                                m.linked_via_device_name
                                    .as_deref()
                                    .filter(|_| m.is_apple())
                                    .map(|d| Self::muted(added_from(lang, d))),
                            ),
                    )
                    .when(m.is_apple(), |row| {
                        row.child(
                            button(
                                SharedString::from(format!("settings-remove-{id}")),
                                t(lang, Str::RemoveMethod),
                                Kind::Secondary,
                                busy,
                            )
                            .when(!busy, |b| {
                                let id = id.clone();
                                b.on_click(cx.listener(move |this, _: &ClickEvent, _, cx| {
                                    this.account.update(cx, |a, cx| {
                                        a.remove_sign_in_method(id.clone(), cx)
                                    });
                                }))
                            }),
                        )
                    })
            })
            .collect();
        div()
            .flex()
            .flex_col()
            .gap(px(6.0))
            .pt(px(6.0))
            .child(
                div()
                    .text_size(theme::PILL_SIZE)
                    .font_weight(FontWeight::SEMIBOLD)
                    .text_color(theme::muted())
                    .child(t(lang, Str::SignInMethods).to_uppercase()),
            )
            .children(rows)
            .child(
                div().flex().child(
                    button(
                        "settings-delete-account",
                        t(lang, Str::DeleteAccount),
                        Kind::Secondary,
                        false,
                    )
                    .on_click(|_, _, cx| open_https(cx, DELETE_ACCOUNT_URL)),
                ),
            )
    }

    /// Settings › Terminal (spec §4.4): one row per shell found, Automatic
    /// first and the custom line last; the chosen one is checked. It applies
    /// to terminals opened next.
    fn terminal_section(&self, lang: Lang, cx: &mut Context<Self>) -> Div {
        let snapshot = shells().snapshot();
        let shown = shown_choice(&snapshot.choice, &snapshot.found, snapshot.plan.is_some());
        let custom_selected = self.custom_open || self.stored_custom();
        let rows: Vec<Stateful<Div>> = shell_options(&snapshot.found)
            .into_iter()
            .map(|option| {
                let selected = match option {
                    ShellOption::Custom => custom_selected,
                    _ => !self.custom_open && is_selected(&option, &shown),
                };
                let (id, label) = match &option {
                    ShellOption::Auto { resolves_to } => (
                        "settings-shell-auto".to_string(),
                        shell_auto_label(lang, resolves_to.as_deref()),
                    ),
                    ShellOption::Known(kind) => (
                        format!("settings-shell-{}", kind_id(*kind)),
                        kind_label(*kind).to_string(),
                    ),
                    ShellOption::Custom => (
                        "settings-shell-custom".to_string(),
                        t(lang, Str::CustomCommandLine).to_string(),
                    ),
                };
                shell_row(id, label, selected).on_click(cx.listener(
                    move |this, _: &ClickEvent, window, cx| {
                        this.choose(option.clone(), window, cx);
                    },
                ))
            })
            .collect();
        let check = if let Some(note) = mac_preview_note() {
            Some(Self::muted(note))
        } else {
            match &self.shell_check {
                Some(Err(error)) => Some(
                    div()
                        .text_size(theme::SMALL_SIZE)
                        .text_color(theme::hsla(palette::ERROR))
                        .child(custom_shell_error(lang, error)),
                ),
                Some(Ok(program)) => Some(Self::muted(will_run(lang, program))),
                None => None,
            }
        };
        Self::section(t(lang, Str::Terminal))
            .children(rows)
            .when(custom_selected, |s| {
                s.child(div().pl(px(22.0)).child(self.shell_field.clone()))
                    .children(check.map(|line| line.pl(px(22.0))))
            })
            .child(Self::muted(t(lang, Str::AppliesToNewTerminals)))
            .when(snapshot.env_override.is_some(), |s| {
                s.child(
                    div()
                        .text_size(theme::SMALL_SIZE)
                        .text_color(theme::text())
                        .child(t(lang, Str::ShellEnvOverride)),
                )
            })
            .when(self.shell_not_saved, |s| {
                s.child(
                    div()
                        .text_size(theme::SMALL_SIZE)
                        .text_color(theme::hsla(palette::ERROR))
                        .child(t(lang, Str::ShellChoiceNotSaved)),
                )
            })
    }

    /// Settings › Display (spec §4.2): the mode this run uses and, when it is the compatible
    /// one, why and a way to try the standard one at the next start.
    fn display_section(&self, lang: Lang, cx: &mut Context<Self>) -> Div {
        let view = startup::display_view(&startup::render_status(), self.standard_requested);
        Self::section(t(lang, Str::Display))
            .child(div().text_color(theme::text()).child(t(lang, view.mode)))
            .children(view.explanation.map(|why| Self::muted(t(lang, why))))
            .when(view.offer_standard, |s| {
                s.child(
                    div().flex().child(
                        button(
                            "settings-try-standard",
                            t(lang, Str::TryStandardDisplay),
                            Kind::Secondary,
                            false,
                        )
                        .on_click(cx.listener(
                            |this, _: &ClickEvent, _, cx| {
                                match startup::request_standard_next_start() {
                                    Ok(()) => this.standard_requested = true,
                                    Err(error) => {
                                        log::warn!(
                                            "the standard display mode was not stored: {error}"
                                        )
                                    }
                                }
                                cx.notify();
                            },
                        )),
                    ),
                )
            })
            .when(view.takes_effect_note, |s| {
                s.child(Self::muted(t(lang, Str::TakesEffectNextStart)))
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
                    .child(build_info::about_version()),
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
                    .child(self.terminal_section(lang, cx))
                    .child(self.display_section(lang, cx))
                    .child(self.update_section(lang, cx))
                    .child(Self::language_section(lang))
                    .child(Self::about_section(lang)),
            )
    }
}

/// The Mac development build always starts bash (Ruling 19): its custom line
/// is not checked, and this says why. Development text: only the Mac build has it.
#[cfg(target_os = "macos")]
const MAC_PREVIEW_NOTE: &str =
    "Mac development build: new terminals always run bash; this line applies on Windows.";

/// `MAC_PREVIEW_NOTE` on the Mac, nothing elsewhere.
#[cfg(target_os = "macos")]
fn mac_preview_note() -> Option<&'static str> {
    Some(MAC_PREVIEW_NOTE)
}

#[cfg(not(target_os = "macos"))]
fn mac_preview_note() -> Option<&'static str> {
    None
}

/// The stable part of a shell row's id.
fn kind_id(kind: ShellKind) -> &'static str {
    match kind {
        ShellKind::Pwsh => "pwsh",
        ShellKind::WindowsPowerShell => "windows_powershell",
        ShellKind::Cmd => "cmd",
        ShellKind::GitBash => "git_bash",
        ShellKind::Wsl => "wsl",
    }
}

/// A clickable row of Settings › Terminal; the chosen one carries the check.
fn shell_row(id: String, label: String, selected: bool) -> Stateful<Div> {
    let mark = div().flex_none().size(px(14.0)).when(selected, |mark| {
        mark.child(
            svg()
                .path(Icon::CircleCheck.path())
                .size(px(14.0))
                .text_color(theme::hsla(palette::PRIMARY)),
        )
    });
    div()
        .id(SharedString::from(id))
        .flex()
        .flex_row()
        .items_center()
        .gap(px(8.0))
        .px(px(6.0))
        .py(px(4.0))
        .rounded(px(6.0))
        .cursor_pointer()
        .hover(|row| row.bg(theme::bg()))
        .child(mark)
        .child(
            div()
                .min_w_0()
                .truncate()
                .text_color(if selected {
                    theme::text_hi()
                } else {
                    theme::text()
                })
                .child(label),
        )
}

mod host;

#[cfg(test)]
mod tests {
    use super::{listed_sections, listed_with, preview};
    use shellx_model::settings_catalog::{Group, Row, Section, groups, rows};

    /// Only the rows with these ids are wired.
    fn wired(ids: &'static [&'static str]) -> impl Fn(&Row) -> bool {
        move |row| ids.contains(&row.id)
    }

    #[test]
    fn sections_without_a_wired_row_are_not_listed() {
        assert_eq!(
            listed_with(wired(&["account", "shell", "display", "updates", "about"])),
            vec![
                (Group::General, vec![Section::Account]),
                (Group::Terminal, vec![Section::Terminal]),
                (Group::ShellX, vec![Section::Updates, Section::About]),
            ]
        );
        assert_eq!(listed_with(wired(&[])), vec![]);
        // A section is listed for one wired row, in its group's order.
        assert_eq!(
            listed_with(wired(&["app.appearance", "account"])),
            vec![(Group::General, vec![Section::Account, Section::Themes])]
        );
        let everything: Vec<(Group, Vec<Section>)> = groups()
            .iter()
            .map(|(group, sections)| (*group, sections.to_vec()))
            .collect();
        assert_eq!(listed_with(|_| true), everything);
        // The sidebar lists exactly the sections the catalogue has a wired row in.
        let listed: Vec<Section> = listed_sections()
            .into_iter()
            .flat_map(|(_, sections)| sections)
            .collect();
        for (_, sections) in groups() {
            for section in *sections {
                assert_eq!(
                    listed.contains(section),
                    rows(*section).any(|row| row.wired),
                    "{section:?}"
                );
            }
        }
    }

    #[test]
    fn the_preview_variable_names_a_section() {
        assert_eq!(preview(None), None);
        assert_eq!(preview(Some("")), None);
        assert_eq!(preview(Some("paste")), None);
        assert_eq!(preview(Some("settingsx")), None);
        // `settings` opens Settings on the section it shows anyway.
        assert_eq!(preview(Some("settings")), Some(None));
        assert_eq!(preview(Some(" settings ")), Some(None));
        assert_eq!(preview(Some("settings:")), Some(None));
        assert_eq!(preview(Some("settings:nope")), Some(None));
        for (_, sections) in groups() {
            for section in *sections {
                let value = format!("settings:{}", section.id());
                assert_eq!(preview(Some(&value)), Some(Some(*section)), "{value}");
            }
        }
        assert_eq!(
            preview(Some("settings:keyboardShortcuts")),
            Some(Some(Section::KeyboardShortcuts))
        );
    }
}
