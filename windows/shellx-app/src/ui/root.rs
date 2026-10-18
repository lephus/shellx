//! RootView: title bar on top, machine sidebar on the left, and the main
//! area: the session bar over the active tab's split panes (spec §7.1).
//!
//! RootView owns the one `Tabs` model and a `PaneHost` of `TermView`s. Every
//! structure change (new tab, split, close, respawn) goes through the model
//! first; `reconcile` then creates views for new panes and drops the views
//! of removed ones (which kills their shells), and the focused pane of the
//! active tab gets keyboard focus.

use std::convert::Infallible;

use gpui::{
    App, Context, Div, Focusable, IntoElement, KeyDownEvent, Render, Window, div, prelude::*, px,
    relative, svg,
};
use shellx_model::keys::{AppCommand, KeyAction, KeyCtx, KeyIn, map_key};
use shellx_model::layout::{Axis, PaneId};
use shellx_model::palette::Status;
use shellx_model::sidebar::{Access, MachineInfo, build_groups};
use shellx_model::strings::Lang;
use shellx_model::tabs::{CloseOutcome, PaneTarget, TabId, Tabs};

use super::app::Services;
use super::assets::Icon;
use super::panes::{self, PaneArea, PaneView};
use super::sidebar::{self, SessionRow};
use super::term_view::{TermEvent, TermView};
use super::theme;
use super::titlebar;
use crate::shell_info::{session_title, this_machine};
use crate::workspace::{DIVIDER, PaneHost, SESSION_BAR_H};

pub struct RootView {
    tabs: Tabs,
    host: PaneHost<PaneView>,
    area: PaneArea,
    sidebar_visible: bool,
    /// Machines shown in the sidebar: only this PC until pairing (Task 12).
    machines: Vec<MachineInfo>,
}

impl RootView {
    pub fn new(window: &mut Window, cx: &mut Context<Self>) -> Self {
        let (tabs, _) = Tabs::new();
        let computer_name = std::env::var("COMPUTERNAME").ok();
        let mut root = RootView {
            tabs,
            host: PaneHost::new(),
            area: PaneArea::default(),
            sidebar_visible: true,
            machines: vec![this_machine(computer_name.as_deref())],
        };
        root.reconcile(window, cx);
        root
    }

    /// Gives keyboard focus to the active tab's focused pane.
    pub fn focus_terminal(&self, window: &mut Window, cx: &App) {
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
            AppCommand::OpenSettings => self.open_settings(cx),
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
    /// No-op hook until Task 11 attaches the settings panel.
    pub fn open_settings(&mut self, _cx: &mut Context<Self>) {}

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
        let machine = self
            .machines
            .first()
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
            // utc offset 0: only this PC is listed, and it is never offline.
            let groups = build_groups(&self.machines, &|_| Access::None, 0, lang);
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
            Some(sidebar::render(&groups, &rows, lang, cx))
        } else {
            None
        };
        let session_bar = self.session_bar(lang, cx);
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
            .child(session_bar)
            .child(panes);

        div()
            .size_full()
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
    }
}
