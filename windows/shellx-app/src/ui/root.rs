//! RootView: title bar on top, machine sidebar on the left, the terminal
//! pane filling the rest (Task 8 replaces the single pane with tabs/splits).

use gpui::{
    App, Context, Entity, Focusable, IntoElement, KeyDownEvent, Render, Window, div, prelude::*,
    relative,
};
use shellx_model::keys::{AppCommand, KeyAction, KeyCtx, KeyIn, map_key};
use shellx_model::palette::Status;
use shellx_model::sidebar::{Access, MachineInfo, build_groups};

use super::app::Services;
use super::sidebar::{self, SessionRow};
use super::term_view::TermView;
use super::theme;
use super::titlebar;
use crate::shell_info::{session_title, this_machine};

pub struct RootView {
    term: Entity<TermView>,
    sidebar_visible: bool,
    /// Machines shown in the sidebar: only this PC until pairing (Task 12).
    machines: Vec<MachineInfo>,
}

impl RootView {
    pub fn new(window: &mut Window, cx: &mut Context<Self>) -> Self {
        let term = cx.new(|cx| TermView::new(window, cx));
        let computer_name = std::env::var("COMPUTERNAME").ok();
        RootView {
            term,
            sidebar_visible: true,
            machines: vec![this_machine(computer_name.as_deref())],
        }
    }

    pub fn focus_terminal(&self, window: &mut Window, cx: &App) {
        window.focus(&self.term.read(cx).focus_handle(cx));
    }

    /// Title bar button and `AppCommand::ToggleSidebar` (Ctrl+Shift+B).
    pub fn toggle_sidebar(&mut self, cx: &mut Context<Self>) {
        self.sidebar_visible = !self.sidebar_visible;
        cx.notify();
    }

    /// Title bar Settings button and `AppCommand::OpenSettings` (Ctrl+,).
    /// No-op hook until Task 11 attaches the settings panel.
    pub fn open_settings(&mut self, _cx: &mut Context<Self>) {}

    /// Window-wide shortcuts, before the focused pane sees the key. Only the
    /// shell commands are taken here; everything else reaches the terminal
    /// unchanged (Task 8 routes the pane commands through `map_key`).
    fn on_key_capture(&mut self, event: &KeyDownEvent, _: &mut Window, cx: &mut Context<Self>) {
        let keystroke = &event.keystroke;
        let mods = keystroke.modifiers;
        let key = KeyIn {
            key: keystroke.key.as_str(),
            ctrl: mods.control,
            alt: mods.alt,
            shift: mods.shift,
            win: mods.platform,
        };
        let ctx = KeyCtx {
            has_selection: false,
            composing: self.term.read(cx).composing(),
        };
        match map_key(&key, &ctx) {
            KeyAction::App(AppCommand::ToggleSidebar) => {
                self.toggle_sidebar(cx);
                cx.stop_propagation();
            }
            KeyAction::App(AppCommand::OpenSettings) => {
                self.open_settings(cx);
                cx.stop_propagation();
            }
            _ => {}
        }
    }
}

impl Render for RootView {
    fn render(&mut self, window: &mut Window, cx: &mut Context<Self>) -> impl IntoElement {
        let lang = cx.global::<Services>().lang;
        let titlebar = titlebar::render(lang, window, cx);
        let sidebar = if self.sidebar_visible {
            // utc offset 0: only this PC is listed, and it is never offline.
            let groups = build_groups(&self.machines, &|_| Access::None, 0, lang);
            let rows = [SessionRow {
                title: session_title(self.term.read(cx).terminal_title().as_deref(), lang),
                selected: true,
                status: Status::Idle,
            }];
            Some(sidebar::render(&groups, &rows, lang, cx))
        } else {
            None
        };
        let main = div()
            .flex_1()
            .min_w_0()
            .h_full()
            .overflow_hidden()
            .bg(theme::bg())
            .child(self.term.clone());

        div()
            .size_full()
            .flex()
            .flex_col()
            .bg(theme::bg())
            .text_color(theme::text())
            .font(theme::ui_font())
            .text_size(theme::UI_SIZE)
            .line_height(relative(1.4))
            .capture_key_down(cx.listener(Self::on_key_capture))
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
