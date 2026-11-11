//! RootView: title bar on top, machine sidebar on the left, and the main
//! area: the active tab's split regions, each with its own tab bar
//! (spec §7.1; `tab_bar.rs`).
//!
//! RootView owns the one `Tabs` model and a `PaneHost` of `TermView`s. Every
//! structure change (new tab, split, close, respawn) goes through the model
//! first; `reconcile` then creates views for new panes and drops the views
//! of removed ones (which kills their shells), and the focused pane of the
//! active tab gets keyboard focus.
//!
//! The sidebar's machines come from the `AccountService` (signed in: the
//! account's machines; signed out: this PC only). Sign-in is never asked at
//! launch: Settings -> Account (or the machines "+" while signed out) opens
//! the `SignInDialog`, drawn over the whole window. Access to the other
//! machines (links, the code being waited on) comes from the `PairingPanel`,
//! which is drawn over the main area while it is open.
//!
//! Remote panes (Task 13b): "Mở" on a Mac (sidebar row, or the pairing
//! panel after approval) opens a new tab whose pane is
//! `PaneTarget::Remote`; `reconcile` opens it through `RemoteTabs` (one
//! session per Mac, shared by its panes) and a remote `TermView`. A split or
//! a new terminal tab (Ctrl+Shift+T) of a remote pane opens a new shell on
//! the same Mac; of a local pane, a local one. The tab bar's buttons do the
//! same for their own region. A new workspace
//! (Ctrl+Shift+N) is always local. A remote terminal ending closes only its
//! pane (the normal close path, so the last pane respawns a local tab);
//! every pane the model drops is closed on its session. The machine list
//! feeds the sessions' online flags; signing out closes every session and
//! every remote pane.
//!
//! One modal rule (`shellx_model::modal`): while a panel is open (forced
//! update overlay, sign-in dialog, settings, pairing) the topmost one holds
//! the keyboard, app commands and pane clicks are swallowed, Esc closes the
//! topmost closable one, and the terminal gets the keyboard back when the
//! last one closes. The overlay closes settings. Typed text is never
//! swallowed (a handled key-down yields no WM_CHAR on Windows). The
//! dropdowns (the title bar "+ ▾" menu, the help menu, the machines "+"
//! list) are not panels: they never hold the keyboard, and they close on a
//! click outside them, when a panel opens, a command runs or the sidebar
//! toggles, and on a plain Esc, which then reaches neither the shell nor a
//! panel (`close_menus`, R14).
//!
//! A shell that exits as it starts would respawn the last pane forever:
//! `RespawnGuard` holds the pane after 5 respawns in 10 s (a message and
//! "Thử lại" instead of a shell).
//!
//! Focus history (`shellx_model::history`): every move of the focused
//! terminal (another workspace, tab or region, a new one) is recorded, and
//! the title bar's Back / Forward walk it, skipping terminals closed since.

use std::collections::HashMap;
use std::convert::Infallible;
use std::sync::Arc;
use std::time::Instant;

use gpui::{
    App, Context, Entity, FocusHandle, Focusable, IntoElement, KeyDownEvent, Render, ScrollHandle,
    Subscription, Window, div, prelude::*, relative,
};
use shellx_model::account::AccountState;
use shellx_model::core_api::CoreCall;
use shellx_model::history::FocusHistory;
use shellx_model::keys::{AppCommand, KeyAction, KeyCtx, KeyIn, map_key};
use shellx_model::layout::{Axis, PaneId, SlotId};
use shellx_model::links::RemoteLink as LinkRecord;
use shellx_model::modal::{Panel, Panels, RootKey};
use shellx_model::palette::Status;
use shellx_model::sidebar::{MachineInfo, build_groups};
use shellx_model::strings::Lang;
use shellx_model::tabs::{CloseOutcome, PaneTarget, RespawnGuard, Tab, TabId, Tabs};
use shellx_model::update::{UpdateStatus, download_url};

use super::account::AccountService;
use super::app::Services;
use super::login::{SignInDialog, SignInEvent};
use super::pairing::{PairingEvent, PairingPanel};
use super::panes::{self, PaneArea, PaneView};
use super::settings::{SettingsEvent, SettingsPanel};
use super::sidebar::{self, PickerEntry, SessionRow};
use super::term_view::{TermEvent, TermView};
use super::theme;
use super::titlebar;
use super::update_banner;
use crate::core_service::MachineFacts;
use crate::cwd::{BranchCache, cwd_from_osc7, row_lines};
use crate::remote_link::{PaneEvent, PaneSink};
use crate::remote_session::RemoteSession;
use crate::remote_tabs::{AccountWatch, RemoteTabs, open_want, split_target, start_app_session};
use crate::shell_info::{remote_session_title, session_title, sidebar_machines, this_machine_id};
use crate::workspace::{DIVIDER, PaneHost};
use shellx_model::core_api::GooglePurpose;

pub struct RootView {
    tabs: Tabs,
    host: PaneHost<PaneView>,
    area: PaneArea,
    sidebar_visible: bool,
    /// `%COMPUTERNAME%`: this PC's name while it has no server entry.
    computer_name: Option<String>,
    /// The home folder (`USERPROFILE`, else `HOME`): a card shows it as `~`.
    home: Option<String>,
    /// Git branch per working directory, for the workspace cards.
    branches: BranchCache,
    account: Entity<AccountService>,
    sign_in: Entity<SignInDialog>,
    settings: Entity<SettingsPanel>,
    pairing: Entity<PairingPanel>,
    /// The remote panes' sessions (one per Mac) and pane ids.
    remotes: RemoteTabs<RemoteSession>,
    /// Sign-out (or another account) closes the remote sessions.
    account_watch: AccountWatch,
    /// Holds the keyboard while the forced-update overlay is up.
    overlay_focus: FocusHandle,
    /// Stops respawning a last pane whose shell exits as it starts.
    respawn: RespawnGuard,
    started: Instant,
    /// Back / Forward of the focused terminal.
    history: FocusHistory,
    /// The focused terminal as last recorded (`note_focus`).
    last_focus: PaneId,
    /// Set while Back / Forward moves the focus, so the step is not recorded.
    navigating: bool,
    /// The title bar "+" chevron's menu is showing.
    new_menu_open: bool,
    /// The sidebar footer "?" button's menu is showing.
    help_open: bool,
    /// Each region's tab strip scroll, and the terminal it last showed.
    tab_strips: HashMap<SlotId, (ScrollHandle, PaneId)>,
    _subscriptions: Vec<Subscription>,
}

impl RootView {
    pub fn new(window: &mut Window, cx: &mut Context<Self>) -> Self {
        let (tabs, _) = Tabs::new();
        let last_focus = tabs.active().focused;
        let computer_name = std::env::var("COMPUTERNAME").ok();
        let home = std::env::var("USERPROFILE")
            .or_else(|_| std::env::var("HOME"))
            .ok();
        let core = cx.global::<Services>().core.clone();
        let pairing = cx.new(|cx| PairingPanel::new(core.clone(), cx));
        let account = cx.new(|cx| AccountService::new(core, MachineFacts::this_pc(), cx));
        let sign_in = cx.new(|cx| SignInDialog::new(account.clone(), window, cx));
        let settings = cx.new(|cx| SettingsPanel::new(account.clone(), cx));
        let subscriptions = vec![
            // A forced update takes the keyboard from the terminals and
            // closes the settings panel and the dropdowns.
            cx.observe_in(&account, window, |this, _, window, cx| {
                if this.panels(cx).must_close() == Some(Panel::Settings) {
                    this.settings.update(cx, |panel, cx| panel.close(cx));
                }
                if this.required(cx).is_some() {
                    this.close_menus(cx);
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
                |this, _, event: &SettingsEvent, window, cx| match event {
                    SettingsEvent::Closed => this.after_focus_change(window, cx),
                    SettingsEvent::SignInRequested => {
                        this.open_sign_in(GooglePurpose::SignIn, window, cx)
                    }
                    SettingsEvent::SwitchToGoogleRequested => {
                        this.open_sign_in(GooglePurpose::Link, window, cx);
                    }
                },
            ),
            // `open_sign_in` checked the modal rule before the dialog opened.
            cx.subscribe_in(&sign_in, window, |this, _, _: &SignInEvent, window, cx| {
                this.after_focus_change(window, cx)
            }),
        ];
        let mut root = RootView {
            tabs,
            host: PaneHost::new(),
            area: PaneArea::default(),
            sidebar_visible: true,
            computer_name,
            home,
            branches: BranchCache::new(),
            account,
            sign_in,
            settings,
            pairing,
            remotes: RemoteTabs::new(),
            account_watch: AccountWatch::default(),
            overlay_focus: cx.focus_handle(),
            respawn: RespawnGuard::new(),
            started: Instant::now(),
            history: FocusHistory::new(),
            last_focus,
            navigating: false,
            new_menu_open: false,
            help_open: false,
            tab_strips: HashMap::new(),
            _subscriptions: subscriptions,
        };
        root.reconcile(window, cx);
        #[cfg(target_os = "macos")]
        root.dev_sign_in_preview(window, cx);
        root
    }

    /// Mac development build only: `SHELLX_DEV_SIGN_IN=start|google|code|invalid|switch` opens the
    /// sign-in dialog on that screen for screenshots, with a made-up address and no core call
    /// (Ruling 38). Any other value does nothing.
    #[cfg(target_os = "macos")]
    fn dev_sign_in_preview(&mut self, window: &mut Window, cx: &mut Context<Self>) {
        let Ok(value) = std::env::var("SHELLX_DEV_SIGN_IN") else {
            return;
        };
        let value = value.trim();
        if !matches!(value, "start" | "google" | "code" | "invalid" | "switch") {
            return;
        }
        if value == "google" {
            self.account
                .update(cx, |account, cx| account.dev_set_google_available(true, cx));
        }
        self.open_sign_in(GooglePurpose::SignIn, window, cx);
        if matches!(value, "code" | "switch") {
            self.account
                .update(cx, |account, cx| account.dev_preview_email(value, cx));
        }
        let fill = match value {
            "invalid" => Some("phu@ẽample.com"),
            "switch" => Some("you@example.com"),
            _ => None,
        };
        if let Some(text) = fill {
            self.sign_in
                .update(cx, |dialog, cx| dialog.dev_fill_email(text, cx));
        }
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
            sign_in: self.sign_in.read(cx).is_open(),
            settings: self.settings.read(cx).is_open(),
            pairing: pairing.is_open(),
        }
    }

    /// Gives keyboard focus to the topmost open panel, else to the active
    /// tab's focused pane.
    pub fn focus_terminal(&self, window: &mut Window, cx: &App) {
        let handle = match self.panels(cx).top() {
            Some(Panel::ForcedUpdate) => self.overlay_focus.clone(),
            Some(Panel::SignIn) => self.sign_in.read(cx).focus_target(cx),
            Some(Panel::Settings) => self.settings.read(cx).focus_handle(cx),
            Some(Panel::Pairing) => self.pairing.read(cx).focus_handle(cx),
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
            Some(Panel::SignIn) => self.sign_in.update(cx, |p, cx| p.close(cx)),
            Some(Panel::Settings) => self.settings.update(cx, |p, cx| p.close(cx)),
            Some(Panel::Pairing) => self.pairing.update(cx, |p, cx| p.close(cx)),
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
        self.note_focus();
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
        // The server ended the session: ask for sign-in again. A password account is offered the
        // switch to Google once.
        if self
            .account
            .update(cx, |a, _| a.take_signed_out_by_server())
        {
            self.open_sign_in(GooglePurpose::SignIn, window, cx);
        } else if self.account.update(cx, |a, _| a.take_google_switch_offer()) {
            self.open_sign_in(GooglePurpose::Link, window, cx);
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

    /// A tab's close button. Like a pane click, it is swallowed while a panel
    /// is open.
    pub fn close_terminal(&mut self, pane: PaneId, window: &mut Window, cx: &mut Context<Self>) {
        if !self.panels(cx).allows_app_commands() {
            self.focus_terminal(window, cx);
            return;
        }
        self.close_pane(pane, window, cx);
    }

    fn run_command(&mut self, command: AppCommand, window: &mut Window, cx: &mut Context<Self>) {
        // A shortcut never leaves a dropdown drawn over what it changed.
        self.close_menus(cx);
        // A panel is open (or the forced update shows): terminals keep
        // running, but no command gets through.
        if !self.panels(cx).allows_app_commands() {
            return;
        }
        match command {
            AppCommand::NewWorkspace => self.new_tab(window, cx),
            AppCommand::NewTerminal => self.new_terminal_tab(window, cx),
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
                let slot = self.tabs.active().focused_slot();
                self.split(slot, Axis::Row, window, cx);
            }
            AppCommand::SplitDown => {
                let slot = self.tabs.active().focused_slot();
                self.split(slot, Axis::Column, window, cx);
            }
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

    /// After the model's focus may have moved (also the end of `select_tab`
    /// and `focus_pane`): keyboard focus follows, and the move is recorded.
    fn after_focus_change(&mut self, window: &mut Window, cx: &mut Context<Self>) {
        self.focus_terminal(window, cx);
        self.note_focus();
        cx.notify();
    }

    /// Records the move from the last recorded terminal to the focused one.
    /// Not while Back / Forward moves it, and not from a terminal that has
    /// closed since (closing is not a step to go back over).
    fn note_focus(&mut self) {
        let now = self.tabs.active().focused;
        if !self.navigating && self.tabs.contains(self.last_focus) {
            self.history.record(self.last_focus, now);
        }
        self.last_focus = now;
    }

    pub(super) fn can_focus_back(&self) -> bool {
        self.history.can_back(&step_targets(&self.tabs))
    }

    pub(super) fn can_focus_forward(&self) -> bool {
        self.history.can_forward(&step_targets(&self.tabs))
    }

    /// Title bar Back: the terminal focused before (skipping closed ones).
    pub fn focus_back(&mut self, window: &mut Window, cx: &mut Context<Self>) {
        self.step_focus(true, window, cx);
    }

    /// Title bar Forward: undoes a Back.
    pub fn focus_forward(&mut self, window: &mut Window, cx: &mut Context<Self>) {
        self.step_focus(false, window, cx);
    }

    /// Swallowed while a panel is open, like a pane click.
    fn step_focus(&mut self, back: bool, window: &mut Window, cx: &mut Context<Self>) {
        if !self.panels(cx).allows_app_commands() {
            self.focus_terminal(window, cx);
            return;
        }
        let current = self.tabs.active().focused;
        let target = {
            let alive = step_targets(&self.tabs);
            if back {
                self.history.back(current, &alive)
            } else {
                self.history.forward(current, &alive)
            }
        };
        let Some(pane) = target else {
            return;
        };
        self.navigating = true;
        self.tabs.focus(pane);
        self.after_focus_change(window, cx);
        self.navigating = false;
    }

    /// A new workspace: Ctrl+Shift+N and the title bar "+" (and its menu);
    /// always local. Swallowed while a panel is open.
    pub fn new_tab(&mut self, window: &mut Window, cx: &mut Context<Self>) {
        if !self.panels(cx).allows_app_commands() {
            self.focus_terminal(window, cx);
            return;
        }
        self.tabs.new_tab(PaneTarget::Local);
        self.reconcile(window, cx);
    }

    /// Ctrl+Shift+T and the "+" menu's "New Tab (Terminal)": a new terminal
    /// tab in the focused region.
    pub fn new_terminal_tab(&mut self, window: &mut Window, cx: &mut Context<Self>) {
        let slot = self.tabs.active().focused_slot();
        self.new_terminal(slot, window, cx);
    }

    /// The active workspace (`panes::render` lays out its regions).
    pub(super) fn active_tab(&self) -> &Tab {
        self.tabs.active()
    }

    /// The live terminal views, by pane.
    pub(super) fn pane_host(&self) -> &PaneHost<PaneView> {
        &self.host
    }

    /// Where the panes are laid out (measured once drawn).
    pub(super) fn pane_area(&self) -> &PaneArea {
        &self.area
    }

    pub(super) fn sidebar_visible(&self) -> bool {
        self.sidebar_visible
    }

    /// `slot`'s tab strip scroll (`tab_bar::render`), once seen.
    pub(super) fn tab_strip_scroll(&self, slot: SlotId) -> Option<&ScrollHandle> {
        self.tab_strips.get(&slot).map(|(scroll, _)| scroll)
    }

    /// Keeps a region's shown tab in view: when the region shows another
    /// terminal (a new tab, a click, a close), its strip scrolls to that tab
    /// once; between such changes the wheel scrolls freely. A strip seen
    /// for the first time is left as it is. Strips of closed regions go.
    fn follow_shown_tabs(&mut self) {
        let tabs = &self.tabs;
        self.tab_strips
            .retain(|slot, _| tabs.tabs().iter().any(|tab| tab.stacks.contains_key(slot)));
        for (slot, stack) in &tabs.active().stacks {
            let shown = stack.selected_pane();
            match self.tab_strips.get_mut(slot) {
                Some((scroll, last)) if *last != shown => {
                    *last = shown;
                    scroll.scroll_to_item(stack.selected);
                }
                Some(_) => {}
                None => {
                    self.tab_strips.insert(*slot, (ScrollHandle::new(), shown));
                }
            }
        }
    }

    /// The active workspace's focused terminal (its title names the
    /// workspace in the title bar).
    pub(super) fn active_pane(&self) -> PaneId {
        self.tabs.active().focused
    }

    pub(super) fn new_menu_open(&self) -> bool {
        self.new_menu_open
    }

    /// The title bar "+" chevron: shows or hides its menu.
    pub(super) fn toggle_new_menu(&mut self, cx: &mut Context<Self>) {
        self.new_menu_open = !self.new_menu_open;
        cx.notify();
    }

    /// A press outside the "+" menu, or a click on one of its rows.
    pub(super) fn close_new_menu(&mut self, cx: &mut Context<Self>) {
        if self.new_menu_open {
            self.new_menu_open = false;
            cx.notify();
        }
    }

    pub(super) fn help_open(&self) -> bool {
        self.help_open
    }

    /// The sidebar footer "?": shows or hides its menu.
    pub(super) fn toggle_help_menu(&mut self, cx: &mut Context<Self>) {
        self.help_open = !self.help_open;
        cx.notify();
    }

    /// A press outside the help menu, or a click on one of its rows.
    pub(super) fn close_help_menu(&mut self, cx: &mut Context<Self>) {
        if self.help_open {
            self.help_open = false;
            cx.notify();
        }
    }

    /// Whether a dropdown is showing: the title bar "+ ▾" menu, the help
    /// menu or the machines "+" list.
    fn dropdown_open(&self, cx: &App) -> bool {
        self.new_menu_open || self.help_open || self.pairing.read(cx).picker_open()
    }

    /// Closes every dropdown (the "+ ▾" menu, the help menu, the machines
    /// "+" list): a panel opens, a command or shortcut runs, the sidebar
    /// toggles, the forced update shows, or a plain Esc (R14).
    fn close_menus(&mut self, cx: &mut Context<Self>) {
        self.close_new_menu(cx);
        self.close_help_menu(cx);
        self.pairing.update(cx, |panel, cx| panel.close_picker(cx));
    }

    /// Makes `slot`'s selected terminal the focused one (a button of a
    /// region's tab bar acts on that region, not on the focused one).
    fn focus_slot(&mut self, slot: SlotId) {
        let pane = self
            .tabs
            .active()
            .stacks
            .get(&slot)
            .map(|stack| stack.selected_pane());
        if let Some(pane) = pane {
            self.tabs.focus(pane);
        }
    }

    /// Adds a terminal to `slot` (`add` makes it in the model). Like every
    /// new terminal it runs where the region's shown pane runs: a remote pane
    /// gets a new shell on the same Mac (spec §8.6 C12), a local pane a new
    /// local shell. Swallowed while a panel is open, like a pane click.
    fn add_terminal(
        &mut self,
        slot: SlotId,
        add: impl FnOnce(&mut Tabs, PaneTarget) -> PaneId,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) {
        if !self.panels(cx).allows_app_commands() {
            self.focus_terminal(window, cx);
            return;
        }
        self.focus_slot(slot);
        let (target, want) = split_target(&self.tabs, self.tabs.active().focused);
        let pane = add(&mut self.tabs, target);
        if let Some(want) = want {
            self.remotes.plan(pane, want);
        }
        self.reconcile(window, cx);
    }

    /// Splits `slot`: a new region next to it holding a new terminal.
    pub fn split(&mut self, slot: SlotId, axis: Axis, window: &mut Window, cx: &mut Context<Self>) {
        self.add_terminal(
            slot,
            |tabs, target| tabs.split_focused(axis, target),
            window,
            cx,
        );
    }

    /// Ctrl+Shift+T and a region's terminal button: a new terminal tab in
    /// `slot`, shown in place of the one it showed.
    pub fn new_terminal(&mut self, slot: SlotId, window: &mut Window, cx: &mut Context<Self>) {
        self.add_terminal(slot, |tabs, target| tabs.new_surface(target), window, cx);
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
    /// It is not a panel: the keyboard stays where it was. While signed out
    /// there is no list to show, so it opens the sign-in dialog instead.
    pub fn toggle_machine_picker(&mut self, window: &mut Window, cx: &mut Context<Self>) {
        if !matches!(self.account.read(cx).state(), AccountState::LoggedIn { .. }) {
            self.open_sign_in(GooglePurpose::SignIn, window, cx);
            return;
        }
        self.pairing.update(cx, |panel, cx| panel.toggle_picker(cx));
        self.after_focus_change(window, cx);
    }

    /// Settings -> Account "Đăng nhập…" and the machines "+" while signed
    /// out: the "Sign in to ShellX" dialog, over Settings if that is open.
    /// Refused while the forced-update overlay is up (`Panels::may_open`).
    pub fn open_sign_in(
        &mut self,
        purpose: GooglePurpose,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) {
        self.close_menus(cx);
        if !self.panels(cx).may_open(Panel::SignIn) {
            return;
        }
        self.sign_in
            .update(cx, |dialog, cx| dialog.open(purpose, window, cx));
    }

    /// A click outside the "+" list closes it (the click itself still runs).
    pub fn close_machine_picker(&mut self, window: &mut Window, cx: &mut Context<Self>) {
        self.pairing.update(cx, |panel, cx| panel.close_picker(cx));
        self.after_focus_change(window, cx);
    }

    /// Title bar button and `AppCommand::ToggleSidebar` (Ctrl+Shift+B, only
    /// while no panel is open). Closes the dropdowns, among them the machine
    /// picker and the help menu that live in the sidebar.
    pub fn toggle_sidebar(&mut self, window: &mut Window, cx: &mut Context<Self>) {
        self.sidebar_visible = !self.sidebar_visible;
        self.close_menus(cx);
        self.after_focus_change(window, cx);
    }

    /// Title bar Settings button and `AppCommand::OpenSettings` (Ctrl+,):
    /// toggles the settings panel.
    pub fn open_settings(&mut self, window: &mut Window, cx: &mut Context<Self>) {
        let open = !self.settings.read(cx).is_open();
        self.set_settings_open(open, window, cx);
    }

    /// The help menu's "Settings…" and "Check for Updates" (whose result
    /// shows in Settings -> Updates): opens the settings panel, never closes
    /// it.
    pub fn show_settings(&mut self, window: &mut Window, cx: &mut Context<Self>) {
        self.set_settings_open(true, window, cx);
    }

    /// Opens or closes the settings panel (blocked while a forced update or
    /// the sign-in dialog shows, both drawn above it). Closes the dropdowns.
    fn set_settings_open(&mut self, open: bool, window: &mut Window, cx: &mut Context<Self>) {
        self.close_menus(cx);
        if !self.panels(cx).may_open(Panel::Settings) {
            return;
        }
        if open {
            self.settings.update(cx, |panel, cx| panel.open(window, cx));
        } else {
            self.settings.update(cx, |panel, cx| panel.close(cx));
        }
    }

    /// Window shortcuts that no pane handled (e.g. focus outside the panes).
    /// A focused TermView maps keys itself and stops the ones it uses. While
    /// a panel is open, keys its field did not use end here: Esc closes the
    /// topmost panel, every app command is swallowed. Typed text and IME keys
    /// are never stopped: a handled key-down yields no WM_CHAR on Windows,
    /// so the field would never see the letter (`Panels::root_key`).
    fn on_key_down(&mut self, event: &KeyDownEvent, window: &mut Window, cx: &mut Context<Self>) {
        let (action, plain_escape) = self.key_action(event, cx);
        match self.panels(cx).root_key(&action, plain_escape) {
            RootKey::Pass => {}
            RootKey::Swallow => cx.stop_propagation(),
            RootKey::CloseTop => {
                self.close_top_panel(window, cx);
                cx.stop_propagation();
            }
            RootKey::Run(command) => {
                cx.stop_propagation();
                self.run_command(command, window, cx);
            }
        }
    }

    /// Capture phase, before the focused terminal (which sends Esc to the
    /// shell) or panel (which closes itself on Esc) sees the key: a plain
    /// Esc while a dropdown is open closes the dropdowns and goes no further
    /// (R14). Every other key, typed text included, passes untouched.
    fn on_key_down_capture(
        &mut self,
        event: &KeyDownEvent,
        _: &mut Window,
        cx: &mut Context<Self>,
    ) {
        if !self.dropdown_open(cx) {
            return;
        }
        let (action, plain_escape) = self.key_action(event, cx);
        if self
            .panels(cx)
            .esc_closes_dropdowns(&action, plain_escape, true)
        {
            self.close_menus(cx);
            cx.stop_propagation();
        }
    }

    /// The key as `map_key` sees it (with the focused terminal's selection
    /// and IME state), and whether it is Esc without modifiers.
    fn key_action(&self, event: &KeyDownEvent, cx: &App) -> (KeyAction, bool) {
        let keystroke = &event.keystroke;
        let mods = keystroke.modifiers;
        let key = KeyIn {
            key: keystroke.key.as_str(),
            ctrl: mods.control,
            alt: mods.alt,
            shift: mods.shift,
            win: mods.platform,
        };
        let plain_escape =
            !(mods.control || mods.alt || mods.shift || mods.platform) && key.key == "escape";
        let focused = self.focused_view(cx);
        let ctx = KeyCtx {
            has_selection: focused.is_some_and(TermView::has_selection),
            composing: focused.is_some_and(TermView::composing),
        };
        (map_key(&key, &ctx), plain_escape)
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

    /// Title of a terminal (a sidebar row, a tab bar tab): its terminal
    /// title, else "PowerShell" (a Mac tab: else the Mac's name).
    pub(super) fn tab_title(&self, focused: PaneId, lang: Lang, cx: &App) -> String {
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

    /// The path and git branch lines of a workspace card: a local pane's
    /// directory (from its shell's OSC 7) and the branch checked out there;
    /// a Mac pane shows the Mac's name and no branch (`cwd::row_lines`).
    fn card_lines(&mut self, pane: PaneId, cx: &App) -> (Option<String>, Option<String>) {
        let remote = self
            .pane_machine(pane)
            .map(|machine| self.machine_name(machine, cx));
        let cwd = self
            .host
            .get(pane)
            .and_then(|live| live.view.read(cx).cwd())
            .and_then(|url| cwd_from_osc7(&url));
        let (path, wants_branch) =
            row_lines(cwd.as_deref(), remote.as_deref(), self.home.as_deref());
        let branch = cwd
            .filter(|_| wants_branch)
            .and_then(|cwd| self.branches.get(&cwd, Instant::now()));
        (path, branch)
    }
}

/// Where Back / Forward may land: an open terminal other than the focused
/// one (a recorded step to the focused terminal itself is skipped).
fn step_targets(tabs: &Tabs) -> impl Fn(PaneId) -> bool + '_ {
    let current = tabs.active().focused;
    move |pane| pane != current && tabs.contains(pane)
}

impl Render for RootView {
    fn render(&mut self, window: &mut Window, cx: &mut Context<Self>) -> impl IntoElement {
        let lang = cx.global::<Services>().lang;
        let titlebar = titlebar::render(self, lang, window, cx);
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
            let tabs: Vec<(TabId, PaneId)> = self
                .tabs
                .tabs()
                .iter()
                .map(|tab| (tab.id, tab.focused))
                .collect();
            let mut rows = Vec::with_capacity(tabs.len());
            for (tab, focused) in tabs {
                let (path, branch) = self.card_lines(focused, cx);
                rows.push(SessionRow {
                    tab,
                    machine_id: self
                        .pane_machine(focused)
                        .filter(|m| groups.iter().any(|g| g.machine_id == *m))
                        .unwrap_or(local_id.as_str())
                        .to_string(),
                    title: self.tab_title(focused, lang, cx),
                    selected: tab == active,
                    status: Status::Idle,
                    path,
                    branch,
                });
            }
            Some(sidebar::render(
                &groups,
                &rows,
                &local_id,
                picker.as_deref(),
                &self.account,
                self.help_open,
                lang,
                cx,
            ))
        } else {
            None
        };
        let overlay = self.required(cx).map(|(min, url)| {
            update_banner::required_overlay(lang, &min, url, &self.overlay_focus)
        });
        let settings = self
            .settings
            .read(cx)
            .is_open()
            .then(|| self.settings.clone());
        let sign_in = self
            .sign_in
            .read(cx)
            .is_open()
            .then(|| self.sign_in.clone());
        let pairing = self
            .pairing
            .read(cx)
            .is_open()
            .then(|| self.pairing.clone());
        self.follow_shown_tabs();
        let panes = panes::render(self, lang, window, cx);
        let main = div()
            .flex()
            .flex_col()
            .flex_1()
            .min_w_0()
            .h_full()
            .relative()
            .overflow_hidden()
            .bg(theme::bg())
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
            .capture_key_down(cx.listener(Self::on_key_down_capture))
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
            .children(sign_in)
            .children(overlay)
    }
}
