//! The active tab's split tree (spec §7.1 "Khu vực chính"): each region is
//! absolutely positioned at its `Layout::rects` rect inside the pane area
//! and holds its tab bar (`tab_bar.rs`) over its stack's selected pane's
//! `TermView`.
//! The 1 px gaps between rects show the area's LINE background, which draws
//! the dividers. No divider dragging in the MVP.
//! Inactive tabs and unselected stacked panes are not rendered; their views
//! (and shells) stay alive in RootView's pane host.

use std::cell::Cell;
use std::rc::Rc;

use gpui::{
    Bounds, Context, Div, Entity, MouseButton, MouseDownEvent, Pixels, Size, Subscription, Window,
    canvas, div, prelude::*, px,
};
use shellx_model::layout::{PaneId, Rect, SlotId};
use shellx_model::strings::Lang;
use shellx_model::tabs::Stack;

use super::root::RootView;
use super::tab_bar;
use super::term_view::TermView;
use super::theme;
use crate::workspace::{DIVIDER, estimate_pane_area};

/// A live pane in the window: its view, and RootView's subscription to it.
/// Dropping it drops the view, whose `LocalPty` kills the shell.
pub(super) struct PaneView {
    pub(super) view: Entity<TermView>,
    pub(super) _events: Subscription,
}

/// The pane area's size as last laid out, keyed by what it depends on, so a
/// stale size is never used after the window or the sidebar changed.
#[derive(Clone, Copy, PartialEq)]
struct Measured {
    viewport: Size<Pixels>,
    sidebar_visible: bool,
    w: f32,
    h: f32,
}

#[derive(Clone, Default)]
pub struct PaneArea {
    measured: Rc<Cell<Option<Measured>>>,
}

impl PaneArea {
    /// The rect the panes are laid out in (origin 0,0), shared by rendering
    /// and `Tabs::focus_dir`. Uses the measured size when it matches the
    /// current viewport and sidebar, else the estimate from the chrome sizes.
    pub fn bounds(&self, window: &Window, sidebar_visible: bool) -> Rect {
        let viewport = window.viewport_size();
        match self.measured.get() {
            Some(m) if m.viewport == viewport && m.sidebar_visible == sidebar_visible => Rect {
                x: 0.0,
                y: 0.0,
                w: m.w,
                h: m.h,
            },
            _ => estimate_pane_area(
                f32::from(viewport.width),
                f32::from(viewport.height),
                sidebar_visible,
            ),
        }
    }

    /// Records the laid-out size; redraws once when it differs from what
    /// this frame used.
    fn record(&self, bounds: Bounds<Pixels>, window: &mut Window, sidebar_visible: bool) {
        let used = self.bounds(window, sidebar_visible);
        let m = Measured {
            viewport: window.viewport_size(),
            sidebar_visible,
            w: f32::from(bounds.size.width),
            h: f32::from(bounds.size.height),
        };
        if self.measured.get() == Some(m) {
            return;
        }
        self.measured.set(Some(m));
        if (used.w - m.w).abs() > 0.5 || (used.h - m.h).abs() > 0.5 {
            // `refresh` is a no-op while drawing; ask for the next frame.
            window.on_next_frame(|window, _| window.refresh());
        }
    }
}

/// The active workspace's regions, laid out in RootView's pane area.
pub(super) fn render(
    root: &RootView,
    lang: Lang,
    window: &Window,
    cx: &mut Context<RootView>,
) -> Div {
    let tab = root.active_tab();
    let host = root.pane_host();
    let area = root.pane_area();
    let sidebar_visible = root.sidebar_visible();
    let bounds = area.bounds(window, sidebar_visible);
    let recorder = area.clone();
    let mut container = div()
        .relative()
        .flex_1()
        .min_h_0()
        .w_full()
        .overflow_hidden()
        .bg(theme::line())
        .child(
            canvas(
                move |bounds, window, _| recorder.record(bounds, window, sidebar_visible),
                |_, _, _, _| {},
            )
            .absolute()
            .top_0()
            .left_0()
            .size_full(),
        );
    // Each region shows the selected terminal of its stack; the others
    // stay alive in the host, like the panes of inactive tabs.
    let focused_slot = tab.focused_slot();
    for (slot, r) in tab.layout.rects(bounds, DIVIDER) {
        let Some(stack) = tab.stacks.get(&slot) else {
            continue;
        };
        let Some(live) = host.get(stack.selected_pane()) else {
            continue;
        };
        let region = Region {
            slot,
            stack,
            focused: slot == focused_slot,
            rect: r,
        };
        container = container.child(region_view(root, lang, region, live.view.clone(), cx));
    }
    container
}

/// One split region: where it is, and what its tab bar shows.
struct Region<'a> {
    slot: SlotId,
    stack: &'a Stack,
    /// The region the keyboard goes to.
    focused: bool,
    rect: Rect,
}

/// A region: its tab bar over the selected terminal.
fn region_view(
    root: &RootView,
    lang: Lang,
    region: Region<'_>,
    view: Entity<TermView>,
    cx: &mut Context<RootView>,
) -> Div {
    let Region {
        slot,
        stack,
        focused,
        rect: r,
    } = region;
    let pane: PaneId = stack.selected_pane();
    div()
        .absolute()
        .left(px(r.x))
        .top(px(r.y))
        .w(px(r.w))
        .h(px(r.h))
        .overflow_hidden()
        .flex()
        .flex_col()
        .bg(theme::bg())
        .child(tab_bar::render(root, slot, stack, focused, lang, cx))
        .child(
            div()
                .relative()
                .flex_1()
                .min_h_0()
                .w_full()
                .overflow_hidden()
                // TermView focuses itself on a click of any button; this
                // keeps the model in step (R2 F4). (Clicks on the tab bar act
                // on their own.)
                .on_mouse_down(
                    MouseButton::Left,
                    cx.listener(move |this, _: &MouseDownEvent, window, cx| {
                        this.focus_pane(pane, window, cx);
                    }),
                )
                .on_mouse_down(
                    MouseButton::Right,
                    cx.listener(move |this, _: &MouseDownEvent, window, cx| {
                        this.focus_pane(pane, window, cx);
                    }),
                )
                .on_mouse_down(
                    MouseButton::Middle,
                    cx.listener(move |this, _: &MouseDownEvent, window, cx| {
                        this.focus_pane(pane, window, cx);
                    }),
                )
                .child(view),
        )
}
