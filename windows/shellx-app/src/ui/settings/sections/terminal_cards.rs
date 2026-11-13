//! Settings › Terminal: the Shell and Display cards moved from the 1.7.1 panel unchanged
//! (spec §5.4: "thẻ Shell hiện có", "thẻ Hiển thị hiện có"), then the Mac's two cards of
//! catalogue rows, each drawn once one of its rows is wired.
//!
//! Shell (spec §4.4): one row per shell found, Automatic first and the custom line last; the
//! chosen one is checked. It applies to terminals opened next. Display (spec §4.2): the mode
//! this run uses and, when it is the compatible one, why and a way to try the standard one at
//! the next start.

use gpui::{
    ClickEvent, Context, Div, Entity, Focusable, FontWeight, SharedString, Stateful, Subscription,
    Window, div, prelude::*, px, svg,
};
use serde_json::Value;
use shellx_model::settings::Key;
use shellx_model::settings_catalog::{Row, row};
use shellx_model::shell::{CustomShellError, ShellChoice, ShellKind, custom_launch, kind_label};
use shellx_model::strings::{Lang, Str, custom_shell_error, shell_auto_label, t, will_run};

use super::super::rows::{catalogue_row, rows_card};
use super::super::{SettingsView, card_body, muted, stack};
use crate::fonts;
use crate::local_pty::settings::{
    ShellOption, is_program_file, is_selected, shell_options, shells, shown_choice,
};
use crate::startup;
use crate::ui::app::Services;
use crate::ui::assets::Icon;
use crate::ui::button::{Kind, button};
use crate::ui::controls::{Picker, PickerEvent, card, row as card_row, section_header};
use crate::ui::settings_service::{SettingsService, current};
use crate::ui::text_field::TextField;
use crate::ui::theme;

/// The Mac's first card below Shell and Display (`TerminalSection.swift`, `mainCard`).
const BEHAVIOUR_ROWS: &[&str] = &[
    "terminalConfig.surface-tab-bar-font-size",
    "terminal.scrollSpeed",
    "terminal.copyOnSelect",
    "terminal.confirmUnsafePaste",
];

/// The Mac's second card (`TerminalGhosttyOptionsCard.swift`). The Font row is drawn here
/// (`font_row`: its options exist only at run time), the others by `catalogue_row`.
const OPTION_ROWS: &[&str] = &[
    "terminalConfig.font-family",
    "terminalConfig.font-size",
    "terminalConfig.cursor-style",
    "terminalConfig.window-padding-x",
    "terminalConfig.window-padding-y",
    "terminalConfig.scrollback-limit",
    "terminalConfig.middle-click-action",
];

/// The state of the Shell and Display cards.
pub struct TerminalCards {
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
    /// A shell lookup started by `opened` has not ended.
    refreshing: bool,
    /// The last choice could not be saved.
    shell_not_saved: bool,
    /// "Try standard display mode again" was stored for the next start.
    standard_requested: bool,
    /// The Font row's picker, made the first time the section is drawn (it lists the installed
    /// monospaced families, which are measured once).
    font_picker: Option<(Entity<Picker>, Subscription)>,
}

impl TerminalCards {
    /// The cards' state, and the subscriptions that keep the custom line checked and give its
    /// field's Esc and Tab to the view.
    pub fn new(cx: &mut Context<SettingsView>) -> (Self, Vec<Subscription>) {
        let lang = cx.global::<Services>().lang;
        let shell_field =
            cx.new(|cx| TextField::new(false, t(lang, Str::CustomShellPlaceholder), cx).tab_stop());
        let subscriptions = vec![
            cx.observe(&shell_field, |this, _, cx| {
                this.shell_line_changed(false, cx)
            }),
            cx.subscribe(&shell_field, |this, _, event, cx| {
                this.field_event(*event, cx)
            }),
        ];
        let cards = TerminalCards {
            shell_field,
            custom_open: false,
            shell_line: String::new(),
            shell_seq: 0,
            shell_check: None,
            shell_checker: None,
            refreshing: false,
            shell_not_saved: false,
            standard_requested: false,
            font_picker: None,
        };
        (cards, subscriptions)
    }
}

pub fn render(view: &mut SettingsView, cx: &mut Context<SettingsView>) -> Div {
    let lang = cx.global::<Services>().lang;
    let shell = card().child(view.shell_body(lang, cx));
    let shell = view.anchored("shell", shell);
    let display = card().child(view.display_body(lang, cx));
    let display = view.anchored("display", display);
    let behaviour = rows_card(BEHAVIOUR_ROWS, view, cx);
    let options = options_card(view, cx);
    stack()
        .child(section_header(t(lang, Str::Terminal).into()))
        .child(shell)
        .child(display)
        .children(behaviour)
        .children(options)
}

/// The second card: the catalogue rows that are wired, the Font row among them.
fn options_card(view: &mut SettingsView, cx: &mut Context<SettingsView>) -> Option<Div> {
    let drawn: Vec<Div> = OPTION_ROWS
        .iter()
        .filter_map(|id| row(id))
        .filter_map(|row| {
            if row.key == Some(Key::FontFamily) {
                font_row(row, view, cx)
            } else {
                catalogue_row(row, view, cx)
            }
        })
        .collect();
    (!drawn.is_empty()).then(|| card().children(drawn))
}

/// The Font row: "Default" and the installed monospaced families. A stored family that is not
/// installed is listed, selected, with "(not installed)" after it, and draws with the default.
fn font_row(
    row: &'static Row,
    view: &mut SettingsView,
    cx: &mut Context<SettingsView>,
) -> Option<Div> {
    if !row.wired {
        return None;
    }
    let lang = cx.global::<Services>().lang;
    let stored = current(cx).font_family.clone().unwrap_or_default();
    let picker = match &view.terminal.font_picker {
        Some((picker, _)) => picker.clone(),
        None => {
            let families = fonts::monospace_families(cx);
            let mut options: Vec<(SharedString, SharedString)> = vec![(
                t(lang, Str::SettingsDefault).into(),
                SharedString::default(),
            )];
            if !stored.is_empty()
                && !families
                    .iter()
                    .any(|family| family.as_ref() == stored.as_str())
            {
                let label = format!("{stored} {}", t(lang, Str::SettingsFontNotInstalled));
                options.push((label.into(), stored.clone().into()));
            }
            options.extend(families.into_iter().map(|family| (family.clone(), family)));
            let picker = cx.new(|cx| Picker::new(options, stored.clone(), cx));
            let subscription = cx.subscribe(&picker, |_, _, event: &PickerEvent, cx| {
                let PickerEvent::Picked(family) = event;
                let family = Value::String(family.to_string());
                SettingsService::entity(cx)
                    .update(cx, |service, cx| service.set(Key::FontFamily, family, cx));
            });
            view.terminal.font_picker = Some((picker.clone(), subscription));
            picker
        }
    };
    picker.update(cx, |picker, cx| picker.set_value(stored, cx));
    let title = t(lang, row.title).into();
    let line = view.anchored(row.id, card_row(title, None, picker, false));
    Some(div().child(line))
}

/// Settings was opened: the custom row starts from what is stored and the shells are looked
/// up again.
pub fn opened(view: &mut SettingsView, cx: &mut Context<SettingsView>) {
    view.fill_stored_line(cx);
    view.refresh_shells(cx);
}

/// A card's title: the catalogue row's title, as a row's title is drawn.
fn card_title(text: &'static str) -> Div {
    div()
        .text_size(px(13.0))
        .font_weight(FontWeight::MEDIUM)
        .text_color(theme::text_hi())
        .child(text)
}

impl SettingsView {
    /// The custom row starts from what is stored.
    fn fill_stored_line(&mut self, cx: &mut Context<Self>) {
        self.terminal.custom_open = false;
        self.terminal.shell_not_saved = false;
        if let ShellChoice::Custom { command_line } = shells().choice() {
            self.terminal
                .shell_field
                .update(cx, |field, cx| field.set_text(&command_line, cx));
        }
    }

    /// Looks the shells up again on a thread of its own (a slow PATH can take
    /// minutes), then redraws from `shells().snapshot()`.
    fn refresh_shells(&mut self, cx: &mut Context<Self>) {
        if self.terminal.refreshing {
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
        self.terminal.refreshing = true;
        cx.spawn(async move |this, cx| {
            let _ = ended.recv().await;
            let _ = this.update(cx, |this, cx| {
                this.terminal.refreshing = false;
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
                self.terminal.custom_open = false;
                self.store_choice(ShellChoice::Auto);
            }
            ShellOption::Known(shell) => {
                self.terminal.custom_open = false;
                self.store_choice(ShellChoice::Known { shell });
            }
            ShellOption::Custom => {
                self.terminal.custom_open = true;
                window.focus(&self.terminal.shell_field.focus_handle(cx));
                self.shell_line_changed(true, cx);
            }
        }
        cx.notify();
    }

    fn store_choice(&mut self, choice: ShellChoice) {
        self.terminal.shell_not_saved = shells().set_choice(choice).is_err();
    }

    /// The field's text changed (or `again`: check it anyway). Each line is
    /// checked off the UI thread; on the Mac nothing is checked (Ruling 19).
    fn shell_line_changed(&mut self, again: bool, cx: &mut Context<Self>) {
        let field = self.terminal.shell_field.read(cx);
        if field.composing() {
            return;
        }
        let text = field.text().to_string();
        if text == self.terminal.shell_line && !again {
            return;
        }
        self.terminal.shell_line = text.clone();
        self.terminal.shell_check = None;
        self.terminal.shell_seq += 1;
        cx.notify();
        if cfg!(windows) {
            self.check_shell_line(self.terminal.shell_seq, text, cx);
        }
    }

    /// Sends a line to the checking thread, which answers only the newest of
    /// the lines waiting for it: typing on a PC with a slow PATH never piles
    /// up checks.
    fn check_shell_line(&mut self, seq: u64, line: String, cx: &mut Context<Self>) {
        if self.terminal.shell_checker.is_none() {
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
            self.terminal.shell_checker = Some(requests);
        }
        if let Some(requests) = &self.terminal.shell_checker {
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
        if seq != self.terminal.shell_seq {
            return;
        }
        let stores = answer.is_ok() && (self.terminal.custom_open || self.stored_custom());
        self.terminal.shell_check = Some(answer);
        if stores {
            let choice = ShellChoice::Custom { command_line: line };
            if shells().choice() != choice {
                self.store_choice(choice);
            }
            self.terminal.custom_open = false;
        }
        cx.notify();
    }

    fn stored_custom(&self) -> bool {
        matches!(shells().choice(), ShellChoice::Custom { .. })
    }

    /// The Shell card's content.
    fn shell_body(&self, lang: Lang, cx: &mut Context<Self>) -> Div {
        let snapshot = shells().snapshot();
        let shown = shown_choice(&snapshot.choice, &snapshot.found, snapshot.plan.is_some());
        let custom_selected = self.terminal.custom_open || self.stored_custom();
        let rows: Vec<Stateful<Div>> = shell_options(&snapshot.found)
            .into_iter()
            .map(|option| {
                let selected = match option {
                    ShellOption::Custom => custom_selected,
                    _ => !self.terminal.custom_open && is_selected(&option, &shown),
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
            Some(muted(note))
        } else {
            match &self.terminal.shell_check {
                Some(Err(error)) => Some(
                    div()
                        .text_size(theme::SMALL_SIZE)
                        .text_color(theme::error_text())
                        .child(custom_shell_error(lang, error)),
                ),
                Some(Ok(program)) => Some(muted(will_run(lang, program))),
                None => None,
            }
        };
        card_body()
            .child(card_title(t(lang, Str::SettingsShell)))
            .children(rows)
            .when(custom_selected, |s| {
                s.child(div().pl(px(22.0)).child(self.terminal.shell_field.clone()))
                    .children(check.map(|line| line.pl(px(22.0))))
            })
            .child(muted(t(lang, Str::AppliesToNewTerminals)))
            .when(snapshot.env_override.is_some(), |s| {
                s.child(
                    div()
                        .text_size(theme::SMALL_SIZE)
                        .text_color(theme::text())
                        .child(t(lang, Str::ShellEnvOverride)),
                )
            })
            .when(self.terminal.shell_not_saved, |s| {
                s.child(
                    div()
                        .text_size(theme::SMALL_SIZE)
                        .text_color(theme::error_text())
                        .child(t(lang, Str::ShellChoiceNotSaved)),
                )
            })
    }

    /// The Display card's content.
    fn display_body(&self, lang: Lang, cx: &mut Context<Self>) -> Div {
        let view =
            startup::display_view(&startup::render_status(), self.terminal.standard_requested);
        card_body()
            .child(card_title(t(lang, Str::Display)))
            .child(div().text_color(theme::text()).child(t(lang, view.mode)))
            .children(view.explanation.map(|why| muted(t(lang, why))))
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
                                    Ok(()) => this.terminal.standard_requested = true,
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
                s.child(muted(t(lang, Str::TakesEffectNextStart)))
            })
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
                .text_color(theme::primary()),
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
