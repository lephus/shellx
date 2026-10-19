//! Request-access panel (spec §8.5): a RAISE/BORDER card centered over the
//! main area. "Xin quyền truy cập <máy>", the 6-digit code (Space Grotesk
//! Bold 32 px, spaced digits, `123 456`), the hint to compare it on the Mac,
//! this PC's device fingerprint in 4x4 groups (the Mac's approval screen
//! shows it too), and a status line with a running-yellow dot while waiting.
//! Approved: "Đã được chấp thuận" + Mở, which closes the panel and opens a
//! tab with the machine's terminal (Task 13b; disabled while the link is not
//! saved); a failed links.json write shows an ERROR line.
//! Denied / Expired / Failed: Thử lại. Huỷ, Esc or closing while waiting
//! cancels (polling stops).
//!
//! Threading: one background task owns the GPUI-free `PairingService` and
//! runs every command through `handle`, so `finish` (links.json I/O) never
//! runs on the UI thread; each core job runs on its own background task
//! (`execute_caught`, always delivers a result) and comes back as
//! `Cmd::Done`; each `tick_at` becomes a background timer that sends
//! `Cmd::Tick`. After every command the task publishes a `Snapshot`, which
//! this entity renders. A snapshot older than the UI's last Start / Cancel
//! (`ui_seq`) is ignored, so the panel never flashes a previous attempt.

use std::sync::Arc;
use std::time::{Duration, Instant};

use gpui::{
    App, ClickEvent, Context, Div, EventEmitter, FocusHandle, Focusable, FontWeight, Hsla,
    IntoElement, KeyDownEvent, Render, SharedString, Window, div, prelude::*, px,
};
use shellx_model::core_api::CoreCall;
use shellx_model::links::Links;
use shellx_model::palette;
use shellx_model::remote_state::PairState;
use shellx_model::sidebar::Access;
use shellx_model::strings::{
    Lang, Str, pairing_code_display, request_access_to, save_link_failed, t, your_device_code,
};

use super::app::Services;
use super::button::{Kind, button};
use super::theme;
use crate::fonts;
use crate::links_store::LinksStore;
use crate::pairing_service::{Cmd, PairingService, Snapshot, execute_caught};

pub const CARD_W: f32 = 400.0;
pub const CODE_SIZE: f32 = 32.0;

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum PairingEvent {
    /// Huỷ / Đóng / Esc: RootView gives the keyboard back to the terminal.
    Closed,
    /// Mở after the approval (the panel closed itself): RootView opens a tab
    /// with this machine's terminal.
    Open(String),
}

pub struct PairingPanel {
    cmds: async_channel::Sender<Cmd>,
    snap: Snapshot,
    /// Number of Start / Cancel commands sent.
    ui_seq: u64,
    open: bool,
    /// The machines-header "+" list in the sidebar.
    picker_open: bool,
    focus: FocusHandle,
}

impl EventEmitter<PairingEvent> for PairingPanel {}

impl Focusable for PairingPanel {
    fn focus_handle(&self, _: &App) -> FocusHandle {
        self.focus.clone()
    }
}

impl PairingPanel {
    pub fn new(core: Arc<dyn CoreCall>, cx: &mut Context<Self>) -> Self {
        let (cmds, cmd_rx) = async_channel::unbounded::<Cmd>();
        let (snap_tx, snaps) = async_channel::unbounded::<Snapshot>();
        let executor = cx.background_executor().clone();
        let loop_tx = cmds.clone();
        cx.background_spawn(async move {
            let started = Instant::now();
            let now = move || u64::try_from(started.elapsed().as_millis()).unwrap_or(u64::MAX);
            let mut svc = PairingService::new(LinksStore::default_or_unavailable());
            let mut scheduled: Option<u64> = None;
            while let Ok(cmd) = cmd_rx.recv().await {
                for job in svc.handle(cmd, now()) {
                    let core = core.clone();
                    let tx = loop_tx.clone();
                    // Blocking core call (bounded by shellx-core's HTTP
                    // timeouts), off the UI thread and off this loop, so a
                    // Cancel is handled while a request is in flight.
                    executor
                        .spawn(async move {
                            let result = execute_caught(core.as_ref(), &job);
                            let _ = tx.send(Cmd::Done(result)).await;
                        })
                        .detach();
                }
                if let Some(at) = svc.tick_at()
                    && scheduled != Some(at)
                {
                    scheduled = Some(at);
                    let delay = Duration::from_millis(at.saturating_sub(now()));
                    let timers = executor.clone();
                    let tx = loop_tx.clone();
                    executor
                        .spawn(async move {
                            timers.timer(delay).await;
                            let _ = tx.send(Cmd::Tick { at_ms: at }).await;
                        })
                        .detach();
                }
                if snap_tx.send(svc.snapshot()).await.is_err() {
                    return;
                }
            }
        })
        .detach();
        cx.spawn(async move |this, cx| {
            while let Ok(snap) = snaps.recv().await {
                if this.update(cx, |panel, cx| panel.apply(snap, cx)).is_err() {
                    return;
                }
            }
        })
        .detach();
        // Unbounded: never full.
        let _ = cmds.try_send(Cmd::LoadLinks);
        PairingPanel {
            cmds,
            snap: Snapshot::default(),
            ui_seq: 0,
            open: false,
            picker_open: false,
            focus: cx.focus_handle(),
        }
    }

    pub fn is_open(&self) -> bool {
        self.open
    }

    pub fn picker_open(&self) -> bool {
        self.picker_open
    }

    pub fn toggle_picker(&mut self, cx: &mut Context<Self>) {
        self.picker_open = !self.picker_open;
        cx.notify();
    }

    /// Esc, or the sidebar hiding: the "+" list goes away.
    pub fn close_picker(&mut self, cx: &mut Context<Self>) {
        if self.picker_open {
            self.picker_open = false;
            cx.notify();
        }
    }

    /// Sidebar access: a saved link -> Granted, the code being waited on ->
    /// Pending, else None.
    pub fn access_for(&self, machine_id: &str) -> Access {
        self.snap.access_for(machine_id)
    }

    pub fn has_link(&self, machine_id: &str) -> bool {
        self.snap.links.get(machine_id).is_some()
    }

    /// The saved links (links.json) as last loaded or saved.
    pub fn links(&self) -> &Links {
        &self.snap.links
    }

    /// Re-reads links.json on the panel's task (a remote session saved
    /// `enrolled = true` or dropped its invitation through the same store).
    pub fn reload_links(&self) {
        // Unbounded: never full.
        let _ = self.cmds.try_send(Cmd::LoadLinks);
    }

    /// "Xin quyền truy cập" (row button or the "+" list): cancels any current
    /// attempt, requests access to this machine and opens the panel.
    pub fn request(
        &mut self,
        machine_id: String,
        machine_name: String,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) {
        self.ui_seq += 1;
        let _ = self.cmds.try_send(Cmd::Start {
            machine_id: machine_id.clone(),
            machine_name: machine_name.clone(),
            ui_seq: self.ui_seq,
        });
        // Shown until the task's first snapshot for this command arrives.
        self.snap = Snapshot {
            state: PairState::Requesting,
            target: Some((machine_id, machine_name)),
            ui_seq: self.ui_seq,
            links: std::mem::take(&mut self.snap.links),
            ..Snapshot::default()
        };
        self.open = true;
        self.picker_open = false;
        window.focus(&self.focus);
        cx.notify();
    }

    fn retry(&mut self, window: &mut Window, cx: &mut Context<Self>) {
        if let Some((id, name)) = self.snap.target.clone() {
            self.request(id, name, window, cx);
        }
    }

    /// Closes the panel; while requesting or waiting this is Cancel.
    pub fn close(&mut self, cx: &mut Context<Self>) {
        if !self.open {
            return;
        }
        if matches!(
            self.snap.state,
            PairState::Requesting | PairState::Waiting { .. }
        ) {
            self.ui_seq += 1;
            let _ = self.cmds.try_send(Cmd::Cancel {
                ui_seq: self.ui_seq,
            });
            self.snap.state = PairState::Idle;
            self.snap.pending.clear();
            self.snap.ui_seq = self.ui_seq;
        }
        self.open = false;
        cx.emit(PairingEvent::Closed);
        cx.notify();
    }

    fn apply(&mut self, snap: Snapshot, cx: &mut Context<Self>) {
        if snap.ui_seq >= self.ui_seq {
            self.snap = snap;
            cx.notify();
        }
    }

    fn on_key_down(&mut self, event: &KeyDownEvent, _: &mut Window, cx: &mut Context<Self>) {
        if event.keystroke.key == "escape" {
            cx.stop_propagation();
            self.close(cx);
        }
    }

    fn status_line(dot: Hsla, text: impl Into<SharedString>, color: Hsla) -> Div {
        div()
            .flex()
            .flex_row()
            .items_center()
            .gap(px(8.0))
            .child(div().flex_none().size(px(8.0)).rounded_full().bg(dot))
            .child(div().min_w_0().text_color(color).child(text.into()))
    }

    /// The code in Space Grotesk Bold 32 px TEXT_HI. GPUI 0.2.2 has no
    /// letter spacing, so each digit is its own box with a gap.
    fn code_view(code: &str) -> Div {
        let mut row = div()
            .flex()
            .flex_row()
            .items_center()
            .gap(px(4.0))
            .font(theme::wordmark_font())
            .text_size(px(CODE_SIZE))
            .text_color(theme::text_hi());
        for ch in pairing_code_display(code).chars() {
            row = if ch == ' ' {
                row.child(div().w(px(10.0)))
            } else {
                row.child(div().child(ch.to_string()))
            };
        }
        row
    }

    fn cancel_button(lang: Lang, cx: &mut Context<Self>) -> impl IntoElement {
        button(
            "pairing-cancel",
            t(lang, Str::Cancel),
            Kind::Secondary,
            false,
        )
        .on_click(cx.listener(|this, _: &ClickEvent, _, cx| this.close(cx)))
    }

    fn close_button(lang: Lang, cx: &mut Context<Self>) -> impl IntoElement {
        button("pairing-close", t(lang, Str::Close), Kind::Secondary, false)
            .on_click(cx.listener(|this, _: &ClickEvent, _, cx| this.close(cx)))
    }

    fn retry_button(lang: Lang, cx: &mut Context<Self>) -> impl IntoElement {
        button("pairing-retry", t(lang, Str::Retry), Kind::Primary, false)
            .on_click(cx.listener(|this, _: &ClickEvent, window, cx| this.retry(window, cx)))
    }

    /// Mở: closes the panel and opens the machine's terminal in a new tab.
    /// Disabled while no link is saved for it (the save error line says why).
    fn open_button(&self, lang: Lang, cx: &mut Context<Self>) -> impl IntoElement {
        let target = self
            .snap
            .target
            .as_ref()
            .map(|(id, _)| id.clone())
            .filter(|id| self.snap.links.get(id).is_some());
        button(
            "pairing-open",
            t(lang, Str::Open),
            Kind::Primary,
            target.is_none(),
        )
        .when_some(target, |el, machine_id| {
            el.on_click(cx.listener(move |this, _: &ClickEvent, _, cx| {
                this.open_remote(machine_id.clone(), cx);
            }))
        })
    }

    fn open_remote(&mut self, machine_id: String, cx: &mut Context<Self>) {
        self.open = false;
        cx.emit(PairingEvent::Open(machine_id));
        cx.notify();
    }
}

impl Render for PairingPanel {
    fn render(&mut self, _window: &mut Window, cx: &mut Context<Self>) -> impl IntoElement {
        let lang = cx.global::<Services>().lang;
        let name = self
            .snap
            .target
            .as_ref()
            .map(|(_, name)| name.clone())
            .unwrap_or_default();
        let running = theme::hsla(palette::RUNNING);
        let error = theme::hsla(palette::ERROR);
        let buttons = div()
            .flex()
            .flex_row()
            .justify_end()
            .gap(px(8.0))
            .pt(px(4.0));

        let mut card = div()
            .flex()
            .flex_col()
            .gap(px(12.0))
            .w(px(CARD_W))
            .p(px(20.0))
            .rounded(px(10.0))
            .border_1()
            .border_color(theme::border())
            .bg(theme::raise())
            .child(
                div()
                    .text_size(px(16.0))
                    .font_weight(FontWeight::SEMIBOLD)
                    .text_color(theme::text_hi())
                    .child(request_access_to(lang, &name)),
            );
        card = match &self.snap.state {
            PairState::Idle | PairState::Requesting => card
                .child(Self::status_line(
                    running,
                    t(lang, Str::SendingRequest),
                    theme::text(),
                ))
                .child(buttons.child(Self::cancel_button(lang, cx))),
            PairState::Waiting { code, .. } => card
                .child(Self::code_view(code))
                .child(
                    div()
                        .text_color(theme::muted())
                        .child(t(lang, Str::PairingCodeHint)),
                )
                .children(self.snap.fingerprint.as_deref().map(|fp| {
                    div()
                        .font_family(fonts::TERMINAL_FAMILY)
                        .text_size(theme::SMALL_SIZE)
                        .text_color(theme::muted())
                        .child(your_device_code(lang, fp))
                }))
                .child(Self::status_line(
                    running,
                    t(lang, Str::WaitingApproval),
                    theme::text(),
                ))
                .child(buttons.child(Self::cancel_button(lang, cx))),
            PairState::Approved { .. } => card
                .child(Self::status_line(
                    theme::done(),
                    t(lang, Str::Approved),
                    theme::done(),
                ))
                .children(self.snap.save_error.as_deref().map(|e| {
                    div()
                        .text_size(theme::SMALL_SIZE)
                        .text_color(error)
                        .child(save_link_failed(lang, e))
                }))
                .child(
                    buttons
                        .child(Self::close_button(lang, cx))
                        .child(self.open_button(lang, cx)),
                ),
            PairState::Denied => card
                .child(Self::status_line(error, t(lang, Str::Denied), error))
                .child(
                    buttons
                        .child(Self::close_button(lang, cx))
                        .child(Self::retry_button(lang, cx)),
                ),
            PairState::Expired => card
                .child(Self::status_line(
                    theme::muted(),
                    t(lang, Str::Expired),
                    theme::text(),
                ))
                .child(
                    buttons
                        .child(Self::close_button(lang, cx))
                        .child(Self::retry_button(lang, cx)),
                ),
            PairState::Failed(e) => {
                let message = if e.message.trim().is_empty() {
                    e.code.clone()
                } else {
                    e.message.clone()
                };
                card.child(Self::status_line(
                    error,
                    format!("{} · {message}", t(lang, Str::Error)),
                    error,
                ))
                .child(
                    buttons
                        .child(Self::close_button(lang, cx))
                        .child(Self::retry_button(lang, cx)),
                )
            }
        };

        // Covers the main area (RootView makes it `relative`): the terminals
        // get no mouse input while the panel is up, and the keyboard is here.
        div()
            .id("pairing-overlay")
            .track_focus(&self.focus)
            .occlude()
            .absolute()
            .top_0()
            .left_0()
            .right_0()
            .bottom_0()
            .flex()
            .items_center()
            .justify_center()
            .bg(theme::bg().opacity(0.6))
            .on_key_down(cx.listener(Self::on_key_down))
            .child(card)
    }
}
