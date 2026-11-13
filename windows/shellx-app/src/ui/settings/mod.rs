//! The Settings view (spec §5.3, inventory §D): a column 210 wide with the search field on top
//! and the grouped sections below it, and a pane showing one section at a time as cards
//! (padding 20, 14 between cards). It does not know where it is drawn: `host.rs` puts it in a
//! window of its own, or over the main window as a panel.
//!
//! A section is listed only when one of its catalogue rows is wired, and a group only when one
//! of its sections is listed. A section with a file in `sections/` is drawn by that file's
//! `render(view, cx) -> Div`, dispatched in `section_content`; any other is its title and one
//! card of its catalogue rows (`rows::section_card`). The search field filters nothing yet
//! (search comes with F1). The section shown is kept in `ui-state.json`; the first one ever is
//! Account.
//!
//! Keys (`shellx_model::controls::view_key`): a plain Esc that no control used (an open picker
//! or colour well takes it first) asks the host to close; Tab and Shift+Tab move the focus, as
//! GPUI binds no Tab. Nothing else is stopped: on Windows a stopped key-down yields no WM_CHAR,
//! so a letter or digit always reaches the field that has the keyboard.

pub mod host;
mod rows;
mod sections {
    pub(super) mod about;
    pub(super) mod account;
    pub(super) mod shortcuts;
    pub(super) mod terminal_cards;
    pub(super) mod themes;
    pub(super) mod updates;
}

use std::collections::HashMap;

use gpui::{
    AnyWindowHandle, ClickEvent, Context, Div, Entity, EventEmitter, FocusHandle, Focusable,
    FontWeight, IntoElement, KeyDownEvent, Render, ScrollAnchor, ScrollHandle, SharedString,
    Stateful, Subscription, Window, div, point, prelude::*, px, relative, svg,
};
use shellx_model::controls::{ViewKey, view_key, view_takes_focus};
use shellx_model::core_api::GooglePurpose;
use shellx_model::settings_catalog::{
    Group, Row, Section, group_title, groups, row, rows, section_title,
};
use shellx_model::strings::{Lang, Str, t};

pub use host::SettingsHost;

use self::rows::RowEntry;
use self::sections::shortcuts::ShortcutList;
use self::sections::terminal_cards::TerminalCards;
use self::sections::themes::ThemeGallery;
use super::account::AccountService;
use super::app::Services;
use super::assets::Icon;
use super::controls::key_in;
use super::settings_service::{SettingsService, current};
use super::text_field::{TextField, TextFieldEvent};
use super::theme;
use crate::ui_state;

/// The left column (inventory §D: `navigationSplitViewColumnWidth(210)`).
const SIDEBAR_W: f32 = 210.0;
/// The detail pane's padding and the space between its cards.
const PANE_PADDING: f32 = 20.0;
const CARD_SPACING: f32 = 14.0;
/// A section row of the left column: its icon slot, and the gap to its title.
const ICON_SLOT: f32 = 16.0;
const ICON_GAP: f32 = 10.0;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum SettingsViewEvent {
    /// Esc, or the panel's close button: the host closes Settings.
    Close,
    /// "Đăng nhập…" or "Chuyển…" in Account: the main window comes to the front and opens the
    /// sign-in dialog there.
    OpenSignIn(GooglePurpose),
    /// "Check for updates" in Updates: the main window runs the check.
    CheckForUpdates,
}

pub struct SettingsView {
    account: Entity<AccountService>,
    focus: FocusHandle,
    section: Section,
    /// The section of the last draw: when another one is drawn, the view takes the keyboard.
    drawn_section: Option<Section>,
    search: Entity<TextField>,
    sidebar_scroll: ScrollHandle,
    detail_scroll: ScrollHandle,
    /// The window Settings was last opened in: a field's Tab moves the focus there.
    window: Option<AnyWindowHandle>,
    /// The kit controls of the catalogue rows, made the first time their row is drawn.
    controls: HashMap<&'static str, RowEntry>,
    /// The rows drawn in the last frame, by id, so `show_row` can scroll to one.
    anchors: HashMap<&'static str, ScrollAnchor>,
    /// The row `show_row` asked for, scrolled to once it has been drawn.
    pending_row: Option<&'static str>,
    /// The Shell and Display cards of Settings › Terminal.
    terminal: TerminalCards,
    /// The search bar and action rows of Settings › Keyboard Shortcuts.
    shortcuts: Entity<ShortcutList>,
    /// The state of Settings › Themes.
    themes: Entity<ThemeGallery>,
    _subscriptions: Vec<Subscription>,
}

impl EventEmitter<SettingsViewEvent> for SettingsView {}

impl Focusable for SettingsView {
    fn focus_handle(&self, _: &gpui::App) -> FocusHandle {
        self.focus.clone()
    }
}

impl SettingsView {
    pub fn new(account: Entity<AccountService>, cx: &mut Context<Self>) -> Self {
        let lang = cx.global::<Services>().lang;
        let search =
            cx.new(|cx| TextField::new(false, t(lang, Str::SettingsSearch), cx).tab_stop());
        let (terminal, mut subscriptions) = TerminalCards::new(cx);
        let (shortcuts, shortcut_subscriptions) = sections::shortcuts::new(cx);
        subscriptions.extend(shortcut_subscriptions);
        let detail_scroll = ScrollHandle::new();
        let (themes, theme_subscriptions) = sections::themes::new(detail_scroll.clone(), cx);
        subscriptions.extend(theme_subscriptions);
        subscriptions.extend([
            cx.observe(&account, |_, _, cx| cx.notify()),
            // A setting changed here or in the other window: the rows show it.
            cx.observe(&SettingsService::entity(cx), |_, _, cx| cx.notify()),
            cx.subscribe(&search, |this, _, event, cx| this.field_event(*event, cx)),
        ]);
        let listed = listed_sections();
        let first = listed
            .first()
            .and_then(|(_, sections)| sections.first().copied())
            .unwrap_or(Section::Account);
        let section = ui_state::load()
            .settings_section
            .as_deref()
            .and_then(Section::from_id)
            .filter(|section| is_listed(&listed, *section))
            .unwrap_or(first);
        SettingsView {
            account,
            focus: cx.focus_handle(),
            section,
            drawn_section: None,
            search,
            sidebar_scroll: ScrollHandle::new(),
            detail_scroll,
            window: None,
            controls: HashMap::new(),
            anchors: HashMap::new(),
            pending_row: None,
            terminal,
            shortcuts,
            themes,
            _subscriptions: subscriptions,
        }
    }

    /// Shows `section` from its top and keeps it for the next start. A section that is not
    /// listed (no wired row) is not shown.
    pub fn show_section(&mut self, section: Section, cx: &mut Context<Self>) {
        if !is_listed(&listed_sections(), section) {
            return;
        }
        if self.section != section {
            self.section = section;
            if section == Section::Themes {
                sections::themes::opened(self, cx);
            }
            let mut state = ui_state::load();
            state.settings_section = Some(section.id().to_string());
            ui_state::save(&state);
        }
        self.pending_row = None;
        self.detail_scroll.set_offset(point(px(0.0), px(0.0)));
        cx.notify();
    }

    /// Shows the row's section and scrolls the row into view (F1 adds the highlight). A row
    /// its settings hide shows its section from the top.
    #[allow(dead_code)] // first called by search (F1)
    pub fn show_row(&mut self, row_id: &'static str, cx: &mut Context<Self>) {
        let Some(row) = row(row_id).filter(|row| row.wired) else {
            return;
        };
        self.show_section(row.section, cx);
        if self.section == row.section && (row.visible)(current(cx)) {
            self.pending_row = Some(row.id);
        }
    }

    /// The host opened Settings in `window`: the sections that read something when Settings
    /// opens read it again.
    fn opened(&mut self, window: AnyWindowHandle, cx: &mut Context<Self>) {
        self.window = Some(window);
        sections::account::opened(self, cx);
        sections::terminal_cards::opened(self, cx);
        if self.section == Section::Themes {
            sections::themes::opened(self, cx);
        }
        cx.notify();
    }

    /// The panel's close button: the host closes Settings.
    fn request_close(&mut self, cx: &mut Context<Self>) {
        cx.emit(SettingsViewEvent::Close);
    }

    /// Esc, Tab or Shift+Tab in one of the view's text fields (the field stops them).
    fn field_event(&mut self, event: TextFieldEvent, cx: &mut Context<Self>) {
        match event {
            TextFieldEvent::Cancel => cx.emit(SettingsViewEvent::Close),
            TextFieldEvent::Next => self.move_focus(false, cx),
            TextFieldEvent::Prev => self.move_focus(true, cx),
            TextFieldEvent::Submit => {}
        }
    }

    /// Tab (or Shift+Tab, `back`) from a field: the field's own window moves the focus.
    fn move_focus(&self, back: bool, cx: &mut Context<Self>) {
        if let Some(window) = self.window {
            window
                .update(cx, |_, window, _| {
                    if back {
                        window.focus_prev()
                    } else {
                        window.focus_next()
                    }
                })
                .ok();
        }
    }

    fn on_key_down(&mut self, event: &KeyDownEvent, window: &mut Window, cx: &mut Context<Self>) {
        let Some(action) = view_key(&key_in(event)) else {
            return;
        };
        cx.stop_propagation();
        match action {
            ViewKey::Close => cx.emit(SettingsViewEvent::Close),
            ViewKey::Next => window.focus_next(),
            ViewKey::Prev => window.focus_prev(),
        }
    }

    /// `element` (a row, or a section file's card) as the place of the catalogue row `id`, so
    /// `show_row` can scroll to it.
    fn anchored(&mut self, id: &'static str, element: Div) -> Stateful<Div> {
        let anchor = self
            .anchors
            .entry(id)
            .or_insert_with(|| ScrollAnchor::for_handle(self.detail_scroll.clone()))
            .clone();
        element.id(id).anchor_scroll(Some(anchor))
    }

    /// The section shown, drawn by its file, else as one card of its rows.
    fn section_content(&mut self, cx: &mut Context<Self>) -> Div {
        match self.section {
            Section::Account => sections::account::render(self, cx),
            Section::Terminal => sections::terminal_cards::render(self, cx),
            Section::Themes => sections::themes::render(self, cx),
            Section::KeyboardShortcuts => sections::shortcuts::render(self, cx),
            Section::Updates => sections::updates::render(self, cx),
            Section::About => sections::about::render(self, cx),
            section => rows::section_card(section, self, cx),
        }
    }

    fn sidebar(&self, listed: &[(Group, Vec<Section>)], lang: Lang, cx: &mut Context<Self>) -> Div {
        let mut list = div()
            .id("settings-sections")
            .flex_1()
            .min_h_0()
            .overflow_y_scroll()
            .track_scroll(&self.sidebar_scroll)
            .px(px(8.0))
            .pb(px(10.0));
        for (group, sections) in listed {
            list = list.child(
                div()
                    .px(px(8.0))
                    .pt(px(10.0))
                    .pb(px(4.0))
                    .text_size(theme::SMALL_SIZE)
                    .font_weight(FontWeight::SEMIBOLD)
                    .text_color(theme::muted())
                    .child(t(lang, group_title(*group))),
            );
            for section in sections {
                list = list.child(self.section_row(*section, lang, cx));
            }
        }
        div()
            .flex()
            .flex_col()
            .flex_none()
            .w(px(SIDEBAR_W))
            .h_full()
            .bg(theme::panel())
            .border_r_1()
            .border_color(theme::line())
            .child(
                div()
                    .flex()
                    .flex_col()
                    .flex_none()
                    .p(px(10.0))
                    .child(self.search.clone()),
            )
            .child(list)
    }

    fn section_row(
        &self,
        section: Section,
        lang: Lang,
        cx: &mut Context<Self>,
    ) -> impl IntoElement {
        let selected = section == self.section;
        div()
            .id(SharedString::from(format!(
                "settings-section-{}",
                section.id()
            )))
            .flex()
            .flex_row()
            .items_center()
            .gap(px(ICON_GAP))
            .h(px(28.0))
            .px(px(8.0))
            .rounded(px(6.0))
            .cursor_pointer()
            .when(selected, |row| row.bg(theme::primary_soft()))
            .when(!selected, |row| row.hover(|row| row.bg(theme::raise())))
            .child(
                div()
                    .flex()
                    .flex_none()
                    .justify_center()
                    .w(px(ICON_SLOT))
                    .child(
                        svg()
                            .path(section_icon(section).path())
                            .size(px(14.0))
                            .text_color(if selected {
                                theme::primary_text()
                            } else {
                                theme::muted()
                            }),
                    ),
            )
            .child(
                div()
                    .min_w_0()
                    .truncate()
                    .text_color(if selected {
                        theme::text_hi()
                    } else {
                        theme::text()
                    })
                    .child(t(lang, section_title(section))),
            )
            .on_click(
                cx.listener(move |this, _: &ClickEvent, _, cx| this.show_section(section, cx)),
            )
    }
}

impl Render for SettingsView {
    fn render(&mut self, window: &mut Window, cx: &mut Context<Self>) -> impl IntoElement {
        let lang = cx.global::<Services>().lang;
        // Every way to another section (its row, `show_section`, `show_row`, the host opening
        // Settings on a section) ends here: the control that had the keyboard is not drawn any
        // more, so the view takes it, and Esc and Tab keep working.
        if view_takes_focus(self.drawn_section, self.section) {
            window.focus(&self.focus);
        }
        self.drawn_section = Some(self.section);
        rows::commit_left_numbers(self, window, cx);
        self.anchors.clear();
        let listed = listed_sections();
        let sidebar = self.sidebar(&listed, lang, cx);
        let content = self.section_content(cx);
        if let Some(anchor) = self.pending_row.take().and_then(|id| self.anchors.get(id)) {
            // It is placed once this frame is laid out; the scroll lands on the next one.
            anchor.scroll_to(window, cx);
            window.on_next_frame(|window, _| window.refresh());
        }
        div()
            .id("settings-view")
            .key_context("SettingsView")
            .track_focus(&self.focus)
            .on_key_down(cx.listener(Self::on_key_down))
            .size_full()
            .flex()
            .flex_row()
            .bg(theme::bg())
            .text_color(theme::text())
            .font(theme::ui_font())
            .text_size(theme::UI_SIZE)
            .line_height(relative(1.4))
            .child(sidebar)
            .child(
                div()
                    .id("settings-detail")
                    .flex_1()
                    .min_w_0()
                    .h_full()
                    .overflow_y_scroll()
                    .track_scroll(&self.detail_scroll)
                    .child(div().p(px(PANE_PADDING)).child(content)),
            )
    }
}

/// The pane's column: a section's header and cards, 14 apart.
fn stack() -> Div {
    div().flex().flex_col().gap(px(CARD_SPACING))
}

/// The content of a card moved from the 1.7.1 panel: its lines 8 apart, inside a row's
/// padding.
fn card_body() -> Div {
    div()
        .flex()
        .flex_col()
        .gap(px(8.0))
        .px(px(14.0))
        .py(px(12.0))
}

/// A secondary line of a card (the 1.7.1 panel's).
fn muted(text: impl Into<SharedString>) -> Div {
    div()
        .text_size(theme::SMALL_SIZE)
        .text_color(theme::muted())
        .child(text.into())
}

/// The groups and sections the column lists: a section with a wired row, a group with a
/// listed section, in the catalogue's order.
fn listed_sections() -> Vec<(Group, Vec<Section>)> {
    listed_with(|row| row.wired)
}

fn listed_with(wired: impl Fn(&Row) -> bool) -> Vec<(Group, Vec<Section>)> {
    groups()
        .iter()
        .filter_map(|(group, sections)| {
            let shown: Vec<Section> = sections
                .iter()
                .copied()
                .filter(|section| rows(*section).any(&wired))
                .collect();
            (!shown.is_empty()).then_some((*group, shown))
        })
        .collect()
}

fn is_listed(listed: &[(Group, Vec<Section>)], section: Section) -> bool {
    listed
        .iter()
        .any(|(_, sections)| sections.contains(&section))
}

/// The icon of a section's row (the Mac's SF Symbol, from the icons ShellX has).
fn section_icon(section: Section) -> Icon {
    match section {
        Section::Account => Icon::Users,
        Section::App => Icon::Settings,
        Section::Themes => Icon::Desktop,
        Section::Terminal => Icon::Terminal,
        Section::WorkspaceColors => Icon::Columns,
        Section::Sidebar => Icon::WindowSidebar,
        Section::KeyboardShortcuts => Icon::Command,
        Section::Reset => Icon::ArrowLeftMd,
        Section::Updates => Icon::Cloud,
        Section::About => Icon::CircleHelp,
    }
}

/// `SHELLX_DEV_PREVIEW` (Mac development build): `settings` opens Settings at start,
/// `settings:<section id>` opens it on that section. `None`: no Settings preview; `Some(None)`:
/// open on the section it shows anyway (also for an id it does not know).
#[cfg(any(test, target_os = "macos"))]
pub fn preview(value: Option<&str>) -> Option<Option<Section>> {
    let rest = value?.trim().strip_prefix("settings")?;
    if rest.is_empty() {
        return Some(None);
    }
    let id = rest.strip_prefix(':')?;
    Some(Section::from_id(id.trim()))
}

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
