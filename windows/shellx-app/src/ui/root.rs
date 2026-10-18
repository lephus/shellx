//! RootView: title bar on top, machine sidebar on the left, and the main
//! area: the session bar over the active tab's split panes (spec §7.1).
//!
//! RootView owns the one `Tabs` model and a `PaneHost` of `TermView`s. Every
//! structure change (new tab, split, close, respawn) goes through the model
//! first; `reconcile` then creates views for new panes and drops the views
//! of removed ones (which kills their shells), and the focused pane of the
//! active tab gets keyboard focus.
//!
//! The sidebar's machines come from the `AccountService` (signed in: the
//! account's machines; signed out: this PC and the sign-in card).

use std::convert::Infallible;

use gpui::{
    App, Context, Div, Entity, FocusHandle, Focusable, IntoElement, KeyDownEvent, Render,
    Subscription, Window, div, prelude::*, px, relative, svg,
};
use shellx_model::keys::{AppCommand, KeyAction, KeyCtx, KeyIn, map_key};
use shellx_model::layout::{Axis, PaneId};
use shellx_model::palette::Status;
use shellx_model::sidebar::{Access, MachineInfo, build_groups};
use shellx_model::strings::Lang;
use shellx_model::tabs::{CloseOutcome, PaneTarget, TabId, Tabs};
use shellx_model::update::{UpdateStatus, download_url};

use super::account::AccountService;
use super::app::Services;
use super::assets::Icon;
use super::login::{LoginPanel, LoginPanelEvent};
use super::panes::{self, PaneArea, PaneView};
use super::settings::{SettingsEvent, SettingsPanel};
use super::sidebar::{self, SessionRow};
use super::term_view::{TermEvent, TermView};
use super::theme;
use super::titlebar;
use super::update_banner;
use crate::core_service::MachineFacts;
use crate::shell_info::{session_title, sidebar_machines, this_machine_id};
use crate::workspace::{DIVIDER, PaneHost, SESSION_BAR_H};

pub struct RootView {
    tabs: Tabs,
    host: PaneHost<PaneView>,
    area: PaneArea,
    sidebar_visible: bool,
    /// `%COMPUTERNAME%`: this PC's name while it has no server entry.
    computer_name: Option<String>,
    account: Entity<AccountService>,
    login: Entity<LoginPanel>,
    settings: Entity<SettingsPanel>,
    /// Holds the keyboard while the forced-update overlay is up.
    overlay_focus: FocusHandle,
    _subscriptions: Vec<Subscription>,
}

impl RootView {
    pub fn new(window: &mut Window, cx: &mut Context<Self>) -> Self {
        let (tabs, _) = Tabs::new();
        let computer_name = std::env::var("COMPUTERNAME").ok();
        let core = cx.global::<Services>().core.clone();
        let account = cx.new(|cx| AccountService::new(core, MachineFacts::this_pc(), cx));
        let login = cx.new(|cx| LoginPanel::new(account.clone(), window, cx));
        let settings = cx.new(|cx| SettingsPanel::new(account.clone(), cx));
        let subscriptions = vec![
            // A forced update takes the keyboard from the terminals.
            cx.observe_in(&account, window, |this, _, window, cx| {
                if this.required(cx).is_some() {
                    this.focus_terminal(window, cx);
                }
                cx.notify();
            }),
            cx.subscribe_in(
                &settings,
                window,
                |this, _, _: &SettingsEvent, window, cx| this.after_focus_change(window, cx),
            ),
            cx.subscribe_in(
                &login,
                window,
                |this, _, event: &LoginPanelEvent, window, cx| match event {
                    LoginPanelEvent::Closed => this.after_focus_change(window, cx),
                },
            ),
        ];
        let mut root = RootView {
            tabs,
            host: PaneHost::new(),
            area: PaneArea::default(),
            sidebar_visible: true,
            computer_name,
            account,
            login,
            settings,
            overlay_focus: cx.focus_handle(),
            _subscriptions: subscriptions,
        };
        root.reconcile(window, cx);
        root
    }

    /// The forced update, if any: (minimum version, https download link).
    fn required(&self, cx: &App) -> Option<(String, Option<String>)> {
        match self.account.read(cx).update_status() {
            status @ UpdateStatus::Required { min, .. } => {
                Some((min.clone(), download_url(status).map(str::to_string)))
            }
            _ => None,
        }
    }

    /// Sidebar machines: the account's list, this PC first.
    fn machines(&self, cx: &App) -> Vec<MachineInfo> {
        sidebar_machines(
            self.account.read(cx).machines(),
            self.computer_name.as_deref(),
        )
    }

    /// Gives keyboard focus to the active tab's focused pane.
    pub fn focus_terminal(&self, window: &mut Window, cx: &App) {
        if self.required(cx).is_some() {
            window.focus(&self.overlay_focus);
            return;
        }
        if self.settings.read(cx).is_open() {
            window.focus(&self.settings.read(cx).focus_handle(cx));
            return;
        }
        if let Some(live) = self.host.get(self.tabs.active().focused) {
            window.focus(&live.view.read(cx).focus_handle(cx));
        }
    }

    /// Brings the views in line with the model, then refocuses.
    fn reconcile(&mut self, window: &mut Window, cx: &mut Context<Self>) {
        let changed = self.host.reconcile(&self.tabs, |pane, _target| {
            // Every pane is local until Task 13 adds remote links.
            let view = cx.new(|cx| TermView::new(window, cx));
            let events = cx.subscribe_in(
                &view,
                window,
                move |this, _, event: &TermEvent, window, cx| {
                    this.on_term_event(pane, event, window, cx);
                },
            );
            Ok::<_, Infallible>(PaneView {
                view,
                _events: events,
            })
        });
        // Dropping the removed views ends their shells (LocalPty::drop).
        let Ok(changed) = changed;
        drop(changed);
        self.focus_terminal(window, cx);
        cx.notify();
    }

    fn on_term_event(
        &mut self,
        pane: PaneId,
        event: &TermEvent,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) {
        match event {
            TermEvent::Command(command) => self.run_command(*command, window, cx),
            TermEvent::Exited => self.close_pane(pane, window, cx),
        }
    }

    /// Shell exit and Ctrl+Shift+W. PaneClosed: the sibling takes the space
    /// and focus moves to it; TabClosed: the neighbor tab becomes active;
    /// Respawned: the last pane of the last tab closed and a fresh local tab
    /// replaced it (the window never quits or goes empty because of that).
    fn close_pane(&mut self, pane: PaneId, window: &mut Window, cx: &mut Context<Self>) {
        match self.tabs.close_pane(pane) {
            CloseOutcome::NotFound => {}
            CloseOutcome::PaneClosed { .. }
            | CloseOutcome::TabClosed { .. }
            | CloseOutcome::Respawned { .. } => self.reconcile(window, cx),
        }
    }

    fn run_command(&mut self, command: AppCommand, window: &mut Window, cx: &mut Context<Self>) {
        // Forced update: terminals keep running, but no command gets through.
        if self.required(cx).is_some() {
            return;
        }
        match command {
            AppCommand::NewTab => self.new_tab(window, cx),
            AppCommand::ClosePane => {
                let pane = self.tabs.active().focused;
                self.close_pane(pane, window, cx);
            }
            AppCommand::NextTab => {
                self.tabs.next_tab();
                self.after_focus_change(window, cx);
            }
            AppCommand::PrevTab => {
                self.tabs.prev_tab();
                self.after_focus_change(window, cx);
            }
            AppCommand::SplitRight => {
                self.tabs.split_focused(Axis::Row, PaneTarget::Local);
                self.reconcile(window, cx);
            }
            AppCommand::SplitDown => {
                self.tabs.split_focused(Axis::Column, PaneTarget::Local);
                self.reconcile(window, cx);
            }
            AppCommand::FocusPane(dir) => {
                // The same rect the panes are rendered in.
                let bounds = self.area.bounds(window, self.sidebar_visible);
                if self.tabs.focus_dir(dir, bounds, DIVIDER) {
                    self.after_focus_change(window, cx);
                }
            }
            AppCommand::ToggleSidebar => self.toggle_sidebar(cx),
            AppCommand::OpenSettings => self.open_settings(window, cx),
            // A focused pane handles these itself; this is the fallback when
            // the key reached the root (focus outside the panes).
            AppCommand::Copy | AppCommand::Paste => {
                if let Some(live) = self.host.get(self.tabs.active().focused) {
                    live.view
                        .update(cx, |view, cx| view.clipboard_command(command, cx));
                }
            }
        }
    }

    fn after_focus_change(&mut self, window: &mut Window, cx: &mut Context<Self>) {
        self.focus_terminal(window, cx);
        cx.notify();
    }

    /// Ctrl+Shift+T and the "+" on this PC's sidebar group.
    pub fn new_tab(&mut self, window: &mut Window, cx: &mut Context<Self>) {
        self.tabs.new_tab(PaneTarget::Local);
        self.reconcile(window, cx);
    }

    /// Sidebar session row click.
    pub fn select_tab(&mut self, tab: TabId, window: &mut Window, cx: &mut Context<Self>) {
        if self.tabs.select(tab) {
            self.after_focus_change(window, cx);
        }
    }

    /// Mouse down inside a pane.
    pub fn focus_pane(&mut self, pane: PaneId, window: &mut Window, cx: &mut Context<Self>) {
        if self.tabs.active().focused != pane {
            self.tabs.focus(pane);
            self.after_focus_change(window, cx);
        }
    }

    /// Title bar button and `AppCommand::ToggleSidebar` (Ctrl+Shift+B).
    pub fn toggle_sidebar(&mut self, cx: &mut Context<Self>) {
        self.sidebar_visible = !self.sidebar_visible;
        cx.notify();
    }

    /// Title bar Settings button and `AppCommand::OpenSettings` (Ctrl+,).
    /// Toggles the settings panel (blocked while a forced update shows).
    pub fn open_settings(&mut self, window: &mut Window, cx: &mut Context<Self>) {
        if self.required(cx).is_some() {
            return;
        }
        if self.settings.read(cx).is_open() {
            self.settings.update(cx, |panel, cx| panel.close(cx));
        } else {
            self.settings.update(cx, |panel, cx| panel.open(window, cx));
        }
    }

    /// Window shortcuts that no pane handled (e.g. focus outside the panes).
    /// A focused TermView maps keys itself and stops the ones it uses.
    fn on_key_down(&mut self, event: &KeyDownEvent, window: &mut Window, cx: &mut Context<Self>) {
        let keystroke = &event.keystroke;
        let mods = keystroke.modifiers;
        let key = KeyIn {
            key: keystroke.key.as_str(),
            ctrl: mods.control,
            alt: mods.alt,
            shift: mods.shift,
            win: mods.platform,
        };
        if self.required(cx).is_some() {
            cx.stop_propagation();
            return;
        }
        let focused = self.focused_view(cx);
        let ctx = KeyCtx {
            has_selection: focused.is_some_and(TermView::has_selection),
            composing: focused.is_some_and(TermView::composing),
        };
        if let KeyAction::App(command) = map_key(&key, &ctx) {
            cx.stop_propagation();
            self.run_command(command, window, cx);
        }
    }

    fn focused_view<'a>(&self, cx: &'a App) -> Option<&'a TermView> {
        self.host
            .get(self.tabs.active().focused)
            .map(|live| live.view.read(cx))
    }

    /// Sidebar / session bar title of a tab: its focused pane's terminal
    /// title, else "PowerShell".
    fn tab_title(&self, focused: PaneId, lang: Lang, cx: &App) -> String {
        let title = self
            .host
            .get(focused)
            .and_then(|live| live.view.read(cx).terminal_title());
        session_title(title.as_deref(), lang)
    }

    /// 36 px bar over the panes: terminal icon, "<tab title> › <machine>".
    fn session_bar(&self, lang: Lang, cx: &App) -> Div {
        let title = self.tab_title(self.tabs.active().focused, lang, cx);
        let machines = self.machines(cx);
        let local_id = this_machine_id(&machines);
        let machine = machines
            .iter()
            .find(|m| m.machine_id == local_id)
            .map(|m| m.name.clone())
            .unwrap_or_default();
        div()
            .flex()
            .flex_row()
            .items_center()
            .gap(px(8.0))
            .flex_none()
            .w_full()
            .h(px(SESSION_BAR_H))
            .px(px(14.0))
            .bg(theme::panel())
            .border_b_1()
            .border_color(theme::line())
            .child(
                svg()
                    .path(Icon::Terminal.path())
                    .flex_none()
                    .size(px(14.0))
                    .text_color(theme::muted()),
            )
            .child(
                div()
                    .flex()
                    .flex_row()
                    .items_center()
                    .min_w_0()
                    .gap(px(6.0))
                    .child(
                        div()
                            .min_w_0()
                            .truncate()
                            .text_color(theme::text_hi())
                            .child(title),
                    )
                    .child(div().flex_none().text_color(theme::muted()).child("›"))
                    .child(div().flex_none().text_color(theme::muted()).child(machine)),
            )
    }
}

impl Render for RootView {
    fn render(&mut self, window: &mut Window, cx: &mut Context<Self>) -> impl IntoElement {
        let lang = cx.global::<Services>().lang;
        let titlebar = titlebar::render(lang, window, cx);
        let sidebar = if self.sidebar_visible {
            let machines = self.machines(cx);
            let local_id = this_machine_id(&machines).to_string();
            let utc_offset = self.account.read(cx).utc_offset_secs();
            // Access to other machines comes with pairing (Task 12).
            let groups = build_groups(&machines, &|_| Access::None, utc_offset, lang);
            let active = self.tabs.active().id;
            let rows: Vec<SessionRow> = self
                .tabs
                .tabs()
                .iter()
                .map(|tab| SessionRow {
                    tab: tab.id,
                    title: self.tab_title(tab.focused, lang, cx),
                    selected: tab.id == active,
                    status: Status::Idle,
                })
                .collect();
            let login = self.login.clone();
            Some(sidebar::render(&groups, &rows, &local_id, &login, lang, cx))
        } else {
            None
        };
        let session_bar = self.session_bar(lang, cx);
        let account = self.account.read(cx);
        let banner = match account.update_status() {
            status @ UpdateStatus::Available { version, .. } if account.banner_visible() => {
                Some(update_banner::banner(
                    lang,
                    version,
                    download_url(status).map(str::to_string),
                    self.account.clone(),
                ))
            }
            _ => None,
        };
        let overlay = self.required(cx).map(|(min, url)| {
            update_banner::required_overlay(lang, &min, url, &self.overlay_focus)
        });
        let settings = self
            .settings
            .read(cx)
            .is_open()
            .then(|| self.settings.clone());
        let panes = panes::render(
            self.tabs.active(),
            &self.host,
            &self.area,
            self.sidebar_visible,
            window,
            cx,
        );
        let main = div()
            .flex()
            .flex_col()
            .flex_1()
            .min_w_0()
            .h_full()
            .overflow_hidden()
            .bg(theme::bg())
            .children(banner)
            .child(session_bar)
            .child(panes);

        div()
            .size_full()
            .relative()
            .flex()
            .flex_col()
            .bg(theme::bg())
            .text_color(theme::text())
            .font(theme::ui_font())
            .text_size(theme::UI_SIZE)
            .line_height(relative(1.4))
            .on_key_down(cx.listener(Self::on_key_down))
            .child(titlebar)
            .child(
                div()
                    .flex()
                    .flex_row()
                    .flex_1()
                    .min_h_0()
                    .w_full()
                    .children(sidebar)
                    .child(main),
            )
            .children(settings)
            .children(overlay)
    }
}
