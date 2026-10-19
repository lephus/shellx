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
//! account's machines; signed out: this PC and the sign-in card). Access to
//! the other machines (links, the code being waited on) comes from the
//! `PairingPanel`, which is drawn over the main area while it is open.
//!
//! Remote panes (Task 13b): "Mở" on a Mac (sidebar row, or the pairing
//! panel after approval) opens a new tab whose pane is
//! `PaneTarget::Remote`; `reconcile` opens it through `RemoteTabs` (one
//! session per Mac, shared by its panes) and a remote `TermView`. A split of
//! a remote pane opens a new shell on the same Mac; a split of a local pane
//! and Ctrl+Shift+T stay local. A remote terminal ending closes only its
//! pane (the normal close path, so the last pane respawns a local tab);
//! every pane the model drops is closed on its session. The machine list
//! feeds the sessions' online flags; signing out closes every session and
//! every remote pane.
//!
//! One modal rule (`shellx_model::modal`): while a panel is open (forced
//! update overlay, settings, pairing, sign-in fields, machine picker) the
//! topmost one holds the keyboard, app commands and pane clicks are
//! swallowed, Esc closes the topmost closable one, and the terminal gets the
//! keyboard back when the last one closes. The overlay closes settings.
//!
//! A shell that exits as it starts would respawn the last pane forever:
//! `RespawnGuard` holds the pane after 5 respawns in 10 s (a message and
//! "Thử lại" instead of a shell).

use std::convert::Infallible;
use std::sync::Arc;
use std::time::Instant;

use gpui::{
    App, Context, Div, Entity, FocusHandle, Focusable, IntoElement, KeyDownEvent, Render,
    Subscription, Window, div, prelude::*, px, relative, svg,
};
use shellx_model::core_api::CoreCall;
use shellx_model::keys::{AppCommand, KeyAction, KeyCtx, KeyIn, map_key};
use shellx_model::layout::{Axis, PaneId};
use shellx_model::links::RemoteLink as LinkRecord;
use shellx_model::modal::{Panel, Panels};
use shellx_model::palette::Status;
use shellx_model::sidebar::{MachineInfo, build_groups};
use shellx_model::strings::Lang;
use shellx_model::tabs::{CloseOutcome, PaneTarget, RespawnGuard, TabId, Tabs};
use shellx_model::update::{UpdateStatus, download_url};

use super::account::AccountService;
use super::app::Services;
use super::assets::Icon;
use super::login::{LoginPanel, LoginPanelEvent};
use super::pairing::{PairingEvent, PairingPanel};
use super::panes::{self, PaneArea, PaneView};
use super::settings::{SettingsEvent, SettingsPanel};
use super::sidebar::{self, PickerEntry, SessionRow};
use super::term_view::{TermEvent, TermView};
use super::theme;
use super::titlebar;
use super::update_banner;
use crate::core_service::MachineFacts;
use crate::remote_link::{PaneEvent, PaneSink};
use crate::remote_session::RemoteSession;
use crate::remote_tabs::{AccountWatch, RemoteTabs, open_want, split_target, start_app_session};
use crate::shell_info::{remote_session_title, session_title, sidebar_machines, this_machine_id};
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
    pairing: Entity<PairingPanel>,
    /// The remote panes' sessions (one per Mac) and pane ids.
    remotes: RemoteTabs<RemoteSession>,
    /// Sign-out (or another account) closes the remote sessions.
    account_watch: AccountWatch,
    /// Holds the keyboard while the forced-update overlay is up.
    overlay_focus: FocusHandle,
    /// The machine picker's own focus (tracked by the picker list, never by
    /// an inert element): holds the keyboard while the picker is the topmost
    /// panel, so Esc bubbles to `on_key_down`.
    picker_focus: FocusHandle,
    /// Stops respawning a last pane whose shell exits as it starts.
    respawn: RespawnGuard,
    started: Instant,
    _subscriptions: Vec<Subscription>,
}

impl RootView {
    pub fn new(window: &mut Window, cx: &mut Context<Self>) -> Self {
        let (tabs, _) = Tabs::new();
        let computer_name = std::env::var("COMPUTERNAME").ok();
        let core = cx.global::<Services>().core.clone();
        let pairing = cx.new(|cx| PairingPanel::new(core.clone(), cx));
        let account = cx.new(|cx| AccountService::new(core, MachineFacts::this_pc(), cx));
        let login = cx.new(|cx| LoginPanel::new(account.clone(), window, cx));
        let settings = cx.new(|cx| SettingsPanel::new(account.clone(), cx));
        let subscriptions = vec![
            // A forced update takes the keyboard from the terminals and
            // closes the settings panel.
            cx.observe_in(&account, window, |this, _, window, cx| {
                if this.panels(cx).must_close() == Some(Panel::Settings) {
                    this.settings.update(cx, |panel, cx| panel.close(cx));
                }
                if this.required(cx).is_some() {
                    this.focus_terminal(window, cx);
                }
                this.account_changed(window, cx);
                cx.notify();
            }),
            cx.observe(&pairing, |_, _, cx| cx.notify()),
            cx.subscribe_in(
                &pairing,
                window,
                |this, _, event: &PairingEvent, window, cx| match event {
                    PairingEvent::Closed => this.after_focus_change(window, cx),
                    // "Mở" after the approval: the panel closed itself.
                    PairingEvent::Open(machine_id) => {
                        this.open_remote(machine_id.clone(), window, cx);
                    }
                },
            ),
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
                    // Only when nothing above the sign-in fields is open;
                    // else they close again and the keyboard stays put.
                    LoginPanelEvent::Opened => {
                        if this.panels(cx).may_open(Panel::Login) {
                            this.after_focus_change(window, cx);
                        } else {
                            this.login.update(cx, |p, cx| p.close(cx));
                        }
                    }
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
            pairing,
            remotes: RemoteTabs::new(),
            account_watch: AccountWatch::default(),
            overlay_focus: cx.focus_handle(),
            picker_focus: cx.focus_handle(),
            respawn: RespawnGuard::new(),
            started: Instant::now(),
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

    /// Which panels are open (the modal rule's input).
    fn panels(&self, cx: &App) -> Panels {
        let pairing = self.pairing.read(cx);
        Panels {
            forced_update: self.required(cx).is_some(),
            settings: self.settings.read(cx).is_open(),
            pairing: pairing.is_open(),
            login: self.sidebar_visible && self.login.read(cx).is_open(),
            picker: self.sidebar_visible && pairing.picker_open(),
        }
    }

    /// Gives keyboard focus to the topmost open panel, else to the active
    /// tab's focused pane.
    pub fn focus_terminal(&self, window: &mut Window, cx: &App) {
        let handle = match self.panels(cx).top() {
            Some(Panel::ForcedUpdate) => self.overlay_focus.clone(),
            Some(Panel::Settings) => self.settings.read(cx).focus_handle(cx),
            Some(Panel::Pairing) => self.pairing.read(cx).focus_handle(cx),
            Some(Panel::Login) => self.login.read(cx).focus_target(cx),
            Some(Panel::Picker) => self.picker_focus.clone(),
            None => match self.host.get(self.tabs.active().focused) {
                Some(live) => live.view.read(cx).focus_handle(cx),
                None => return,
            },
        };
        window.focus(&handle);
    }

    /// Esc while a panel is open: closes the topmost closable one (never the
    /// forced-update overlay). `false` when there is none.
    fn close_top_panel(&mut self, window: &mut Window, cx: &mut Context<Self>) -> bool {
        match self.panels(cx).esc_target() {
            Some(Panel::Settings) => self.settings.update(cx, |p, cx| p.close(cx)),
            Some(Panel::Pairing) => self.pairing.update(cx, |p, cx| p.close(cx)),
            Some(Panel::Login) => self.login.update(cx, |p, cx| p.close(cx)),
            Some(Panel::Picker) => self.pairing.update(cx, |p, cx| p.close_picker(cx)),
            Some(Panel::ForcedUpdate) | None => return false,
        }
        self.after_focus_change(window, cx);
        true
    }

    fn now_ms(&self) -> u64 {
        u64::try_from(self.started.elapsed().as_millis()).unwrap_or(u64::MAX)
    }

    /// Brings the views in line with the model, then refocuses.
    fn reconcile(&mut self, window: &mut Window, cx: &mut Context<Self>) {
        // What a new remote pane needs: the shared core (minting tickets),
        // the cached links (the Mac's relay route and key) and whether the
        // Mac is online (the last machine list).
        let core: Arc<dyn CoreCall> = cx.global::<Services>().core.clone();
        let links = self.pairing.read(cx).links().clone();
        let machines = self.machines(cx);
        let remotes = &mut self.remotes;
        let respawn = &self.respawn;
        let changed = self.host.reconcile(&self.tabs, |pane, target| {
            let view = match target {
                // The shell kept exiting as it started: no new shell until
                // the user retries.
                PaneTarget::Local if respawn.is_held(pane) => {
                    cx.new(|cx| TermView::new_held(window, cx))
                }
                PaneTarget::Local => cx.new(|cx| TermView::new(window, cx)),
                PaneTarget::Remote {
                    machine_id,
                    terminal_id,
                } => {
                    // Sent from the session's threads; one UI task per pane
                    // drains it. `false` (UI gone) stops the sending.
                    let (tx, rx) = async_channel::unbounded::<PaneEvent>();
                    let sink: PaneSink = Arc::new(move |event| tx.send_blocking(event).is_ok());
                    let online = machines
                        .iter()
                        .find(|m| &m.machine_id == machine_id)
                        .map(|m| m.online);
                    let opened = remotes.open(
                        pane,
                        machine_id,
                        terminal_id,
                        links.get(machine_id),
                        online,
                        sink,
                        &mut |record: LinkRecord| start_app_session(record, core.clone()),
                    );
                    cx.new(|cx| TermView::new_remote(opened, rx, window, cx))
                }
            };
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
        // Dropping the removed views ends their shells (LocalPty::drop);
        // a removed remote pane is closed on its session (its view on the
        // Mac detaches, the shell there keeps running).
        let Ok(changed) = changed;
        for (pane, _) in &changed.removed {
            self.remotes.pane_closed(*pane);
        }
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
            // "Thử lại" or a key in the held pane: a fresh pane and shell.
            TermEvent::Retry => {
                let now = self.now_ms();
                if self.respawn.retry(&mut self.tabs, now) != CloseOutcome::NotFound {
                    self.reconcile(window, cx);
                }
            }
            TermEvent::Retargeted(terminal_id) => {
                self.tabs.retarget(pane, terminal_id);
            }
            TermEvent::RemoteStatus => {
                // The session rewrote links.json (enrolled, or dropped an
                // expired invitation): reload the cached links.
                if self.remotes.status_changed(pane) {
                    self.pairing.read(cx).reload_links();
                }
            }
        }
    }

    /// The account changed (every list, sign-in, sign-out): feed the remote
    /// sessions whether their Mac is online; sign-out (or another account)
    /// closes them all.
    fn account_changed(&mut self, window: &mut Window, cx: &mut Context<Self>) {
        let account = self.account.read(cx);
        let close = self.account_watch.update(account.state());
        self.remotes.machines_updated(account.machines());
        if close {
            self.close_all_remote(window, cx);
        }
    }

    /// Closes every remote session, then every remote pane through the
    /// tabs model (the last pane of the last tab respawns a local tab).
    fn close_all_remote(&mut self, window: &mut Window, cx: &mut Context<Self>) {
        self.remotes.close_all();
        let panes = self.tabs.remote_panes();
        if panes.is_empty() {
            return;
        }
        for pane in panes {
            self.tabs.close_pane(pane);
        }
        self.reconcile(window, cx);
    }

    /// Shell exit and Ctrl+Shift+W. PaneClosed: the sibling takes the space
    /// and focus moves to it; TabClosed: the neighbor tab becomes active;
    /// Respawned: the last pane of the last tab closed and a fresh local tab
    /// replaced it (the window never quits or goes empty because of that).
    fn close_pane(&mut self, pane: PaneId, window: &mut Window, cx: &mut Context<Self>) {
        let outcome = self.tabs.close_pane(pane);
        let now = self.now_ms();
        self.respawn.on_close(&outcome, now);
        match outcome {
            CloseOutcome::NotFound => {}
            CloseOutcome::PaneClosed { .. }
            | CloseOutcome::TabClosed { .. }
            | CloseOutcome::Respawned { .. } => self.reconcile(window, cx),
        }
    }

    fn run_command(&mut self, command: AppCommand, window: &mut Window, cx: &mut Context<Self>) {
        // A panel is open (or the forced update shows): terminals keep
        // running, but no command gets through.
        if !self.panels(cx).allows_app_commands() {
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
            AppCommand::SplitRight => self.split(Axis::Row, window, cx),
            AppCommand::SplitDown => self.split(Axis::Column, window, cx),
            AppCommand::FocusPane(dir) => {
                // The same rect the panes are rendered in.
                let bounds = self.area.bounds(window, self.sidebar_visible);
                if self.tabs.focus_dir(dir, bounds, DIVIDER) {
                    self.after_focus_change(window, cx);
                }
            }
            AppCommand::ToggleSidebar => self.toggle_sidebar(window, cx),
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

    /// Ctrl+Shift+T and the "+" on this PC's sidebar group (always local).
    pub fn new_tab(&mut self, window: &mut Window, cx: &mut Context<Self>) {
        self.tabs.new_tab(PaneTarget::Local);
        self.reconcile(window, cx);
    }

    /// Splits the focused pane: a remote pane gets a new shell on the same
    /// Mac (spec §8.6 C12), a local pane a new local shell.
    fn split(&mut self, axis: Axis, window: &mut Window, cx: &mut Context<Self>) {
        let (target, want) = split_target(&self.tabs, self.tabs.active().focused);
        let pane = self.tabs.split_focused(axis, target);
        if let Some(want) = want {
            self.remotes.plan(pane, want);
        }
        self.reconcile(window, cx);
    }

    /// "Mở" on a Mac (sidebar row, or the pairing panel after approval): a
    /// new tab with that Mac's terminal (its first one; another Open makes a
    /// new terminal there). Blocked while a forced update shows.
    pub fn open_remote(&mut self, machine_id: String, window: &mut Window, cx: &mut Context<Self>) {
        if self.required(cx).is_some() {
            return;
        }
        let want = open_want(&self.tabs, &machine_id);
        let (_, pane) = self.tabs.new_tab(PaneTarget::Remote {
            machine_id,
            terminal_id: String::new(),
        });
        self.remotes.plan(pane, want);
        self.reconcile(window, cx);
    }

    /// Sidebar session row click (swallowed while a panel is open).
    pub fn select_tab(&mut self, tab: TabId, window: &mut Window, cx: &mut Context<Self>) {
        if !self.panels(cx).allows_app_commands() {
            self.focus_terminal(window, cx);
            return;
        }
        if self.tabs.select(tab) {
            self.after_focus_change(window, cx);
        }
    }

    /// Mouse down inside a pane. While a panel is open the click is
    /// swallowed: the keyboard goes back to the panel (TermView focused
    /// itself first) and the model's focused pane stays.
    pub fn focus_pane(&mut self, pane: PaneId, window: &mut Window, cx: &mut Context<Self>) {
        if !self.panels(cx).allows_app_commands() {
            self.focus_terminal(window, cx);
            return;
        }
        if self.tabs.active().focused != pane {
            self.tabs.focus(pane);
            self.after_focus_change(window, cx);
        }
    }

    /// Sidebar "Xin quyền truy cập" (row button or the "+" list): opens the
    /// pairing panel for that machine (blocked while a forced update shows).
    pub fn request_access(
        &mut self,
        machine_id: String,
        machine_name: String,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) {
        if self.required(cx).is_some() {
            return;
        }
        self.pairing.update(cx, |panel, cx| {
            panel.request(machine_id, machine_name, window, cx);
        });
    }

    /// The machines-header "+": the list of machines to request access to.
    /// While it is open it is a panel (Esc closes it).
    pub fn toggle_machine_picker(&mut self, window: &mut Window, cx: &mut Context<Self>) {
        self.pairing.update(cx, |panel, cx| panel.toggle_picker(cx));
        self.after_focus_change(window, cx);
    }

    /// Title bar button and `AppCommand::ToggleSidebar` (Ctrl+Shift+B, only
    /// while no panel is open). Hiding the sidebar closes the sign-in fields
    /// (wiping a typed password) and the machine picker that live in it, so
    /// the keyboard never stays on a field that is no longer drawn.
    pub fn toggle_sidebar(&mut self, window: &mut Window, cx: &mut Context<Self>) {
        self.sidebar_visible = !self.sidebar_visible;
        if !self.sidebar_visible {
            self.login.update(cx, |p, cx| p.close(cx));
            self.pairing.update(cx, |p, cx| p.close_picker(cx));
        }
        self.after_focus_change(window, cx);
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
    /// A focused TermView maps keys itself and stops the ones it uses. While
    /// a panel is open, keys its field did not use end here: Esc closes the
    /// topmost panel, every app command is swallowed.
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
        let panels = self.panels(cx);
        if panels.top() == Some(Panel::ForcedUpdate) {
            cx.stop_propagation();
            return;
        }
        if panels.any_open() {
            let plain = !(mods.control || mods.alt || mods.shift || mods.platform);
            if plain && key.key == "escape" {
                self.close_top_panel(window, cx);
            }
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

    /// The Mac a remote pane shows; `None` for a local pane.
    fn pane_machine(&self, pane: PaneId) -> Option<&str> {
        match self.tabs.target(pane) {
            Some(PaneTarget::Remote { machine_id, .. }) => Some(machine_id.as_str()),
            _ => None,
        }
    }

    /// A machine's name: the account's list, else the saved link, else its id.
    fn machine_name(&self, machine_id: &str, cx: &App) -> String {
        self.account
            .read(cx)
            .machines()
            .iter()
            .find(|m| m.machine_id == machine_id)
            .map(|m| m.name.clone())
            .or_else(|| {
                self.pairing
                    .read(cx)
                    .links()
                    .get(machine_id)
                    .map(|l| l.machine_name.clone())
            })
            .unwrap_or_else(|| machine_id.to_string())
    }

    /// Sidebar / session bar title of a tab: its focused pane's terminal
    /// title, else "PowerShell" (a Mac tab: else the Mac's name).
    fn tab_title(&self, focused: PaneId, lang: Lang, cx: &App) -> String {
        let title = self
            .host
            .get(focused)
            .and_then(|live| live.view.read(cx).terminal_title());
        match self.pane_machine(focused) {
            Some(machine) => {
                remote_session_title(title.as_deref(), &self.machine_name(machine, cx))
            }
            None => session_title(title.as_deref(), lang),
        }
    }

    /// 36 px bar over the panes: terminal icon, "<tab title> › <machine>".
    fn session_bar(&self, lang: Lang, cx: &App) -> Div {
        let focused = self.tabs.active().focused;
        let title = self.tab_title(focused, lang, cx);
        let machine = match self.pane_machine(focused) {
            Some(remote) => self.machine_name(remote, cx),
            None => {
                let machines = self.machines(cx);
                let local_id = this_machine_id(&machines);
                machines
                    .iter()
                    .find(|m| m.machine_id == local_id)
                    .map(|m| m.name.clone())
                    .unwrap_or_default()
            }
        };
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
            let pairing = self.pairing.read(cx);
            let groups = build_groups(
                &machines,
                &|id: &str| pairing.access_for(id),
                utc_offset,
                lang,
            );
            let picker: Option<Vec<PickerEntry>> = pairing.picker_open().then(|| {
                machines
                    .iter()
                    .filter(|m| !m.is_this_machine && !pairing.has_link(&m.machine_id))
                    .map(|m| PickerEntry {
                        machine_id: m.machine_id.clone(),
                        name: m.name.clone(),
                        online: m.online,
                    })
                    .collect()
            });
            let active = self.tabs.active().id;
            // A tab is listed under the machine its panes run on (a Mac tab
            // under that Mac's group; under this PC if the Mac is not listed).
            let rows: Vec<SessionRow> = self
                .tabs
                .tabs()
                .iter()
                .map(|tab| SessionRow {
                    tab: tab.id,
                    machine_id: self
                        .pane_machine(tab.focused)
                        .filter(|m| groups.iter().any(|g| g.machine_id == *m))
                        .unwrap_or(local_id.as_str())
                        .to_string(),
                    title: self.tab_title(tab.focused, lang, cx),
                    selected: tab.id == active,
                    status: Status::Idle,
                })
                .collect();
            let login = self.login.clone();
            Some(sidebar::render(
                &groups,
                &rows,
                &local_id,
                &login,
                picker
                    .as_deref()
                    .map(|entries| (entries, &self.picker_focus)),
                lang,
                cx,
            ))
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
        let pairing = self
            .pairing
            .read(cx)
            .is_open()
            .then(|| self.pairing.clone());
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
            .relative()
            .overflow_hidden()
            .bg(theme::bg())
            .children(banner)
            .child(session_bar)
            .child(panes)
            // The pairing card, centered over the main area.
            .children(pairing);

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
