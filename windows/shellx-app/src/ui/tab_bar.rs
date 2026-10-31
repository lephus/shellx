//! The tab bar of one split region, like the Mac's Bonsplit bar: one tab per
//! terminal of the region's stack (terminal icon, title, close box), and
//! New Terminal / Split Right / Split Down on the right.
//!
//! The selected tab of the focused region is blue-tinted with a PRIMARY bar
//! under it; the selected tab of another region has a RAISE fill and a dim
//! bar, so the keyboard's region is always clear. A click on a tab focuses
//! that terminal; the close box closes it. The buttons act on this region,
//! not on the focused one.

use gpui::{
    ClickEvent, Context, Div, ElementId, FontWeight, Hsla, SharedString, Stateful, div, prelude::*,
    px, svg,
};
use shellx_model::layout::{Axis, PaneId, SlotId};
use shellx_model::palette;
use shellx_model::strings::{Lang, Str, t};
use shellx_model::tabs::Stack;

use super::assets::Icon;
use super::root::RootView;
use super::theme;
use super::tooltip::Tooltip;
use crate::workspace::TAB_BAR_H;

/// Longest a tab's title grows before it is cut, in px.
const TITLE_MAX_W: f32 = 180.0;
/// Narrowest a tab gets, in px: its icon and close box always fit.
const TAB_MIN_W: f32 = 62.0;

/// The bar over `slot`'s terminal. `focused_slot`: the region the keyboard
/// goes to. Tab titles come from `RootView::tab_title`.
pub(super) fn render(
    root: &RootView,
    slot: SlotId,
    stack: &Stack,
    focused_slot: bool,
    lang: Lang,
    cx: &mut Context<RootView>,
) -> Div {
    let shown = stack.selected_pane();
    // The tabs keep their width and the strip scrolls sideways (the mouse
    // wheel scrolls it), so a tab never paints over its neighbour and a
    // close box never sits in another tab's hit area. The buttons stay
    // outside the strip, always visible.
    let mut tabs = div()
        .id(("tab-strip", slot.0))
        .flex()
        .flex_row()
        .items_center()
        .flex_1()
        .min_w_0()
        .h_full()
        .overflow_x_scroll();
    for &pane in &stack.panes {
        let title: SharedString = root.tab_title(pane, lang, cx).into();
        tabs = tabs.child(tab(pane, title, pane == shown, focused_slot, lang, cx));
    }
    div()
        .flex()
        .flex_row()
        .items_center()
        .flex_none()
        .w_full()
        .h(px(TAB_BAR_H))
        .bg(theme::panel())
        .border_b_1()
        .border_color(theme::line())
        .child(tabs)
        .child(buttons(slot, lang, cx))
}

fn tab(
    pane: PaneId,
    title: SharedString,
    selected: bool,
    focused_slot: bool,
    lang: Lang,
    cx: &mut Context<RootView>,
) -> Stateful<Div> {
    let current = selected && focused_slot;
    let (title_color, weight) = if current {
        (theme::hsla(palette::SELECTION_TITLE), FontWeight::SEMIBOLD)
    } else if selected {
        (theme::text(), FontWeight::NORMAL)
    } else {
        (theme::muted(), FontWeight::NORMAL)
    };
    let fill: Option<Hsla> = if current {
        Some(theme::hsla(palette::PRIMARY_SOFT))
    } else if selected {
        Some(theme::raise())
    } else {
        None
    };
    let bar = if current {
        theme::hsla(palette::PRIMARY)
    } else {
        theme::hsla(palette::INDICATOR_UNFOCUSED)
    };
    div()
        .id(("tab", pane.0))
        .relative()
        .flex()
        .flex_row()
        .items_center()
        .gap(px(6.0))
        .flex_shrink_0()
        .min_w(px(TAB_MIN_W))
        .h_full()
        .overflow_hidden()
        .px(px(10.0))
        .cursor_pointer()
        .when_some(fill, |el, fill| el.bg(fill))
        .when(!selected, |el| {
            el.hover(|style| style.bg(theme::hsla(theme::SESSION_HOVER)))
        })
        .on_click(cx.listener(move |this, _: &ClickEvent, window, cx| {
            this.focus_pane(pane, window, cx);
        }))
        .child(
            svg()
                .path(Icon::Terminal.path())
                .flex_none()
                .size(px(14.0))
                .text_color(title_color),
        )
        .child(
            div()
                .min_w_0()
                .max_w(px(TITLE_MAX_W))
                .truncate()
                .text_size(theme::SMALL_SIZE)
                .font_weight(weight)
                .text_color(title_color)
                .child(title),
        )
        .child(close_box(pane, lang, cx))
        .when(selected, |el| {
            el.child(
                div()
                    .absolute()
                    .left_0()
                    .right_0()
                    .bottom_0()
                    .h(px(2.0))
                    .bg(bar),
            )
        })
}

/// The 16 px close box of a tab: muted, TEXT_HI under the mouse.
fn close_box(pane: PaneId, lang: Lang, cx: &mut Context<RootView>) -> Stateful<Div> {
    let tip: SharedString = t(lang, Str::CloseTab).into();
    let group = SharedString::from(format!("tab-close-{}", pane.0));
    div()
        .id(("tab-close", pane.0))
        .group(group.clone())
        .flex()
        .flex_none()
        .items_center()
        .justify_center()
        .size(px(16.0))
        .rounded(px(4.0))
        .cursor_pointer()
        .tooltip(move |_, cx| Tooltip::view(tip.clone(), cx))
        .on_click(cx.listener(move |this, _: &ClickEvent, window, cx| {
            // The click is the close box's, not the tab's.
            cx.stop_propagation();
            this.close_terminal(pane, window, cx);
        }))
        .child(
            svg()
                .path(Icon::CloseSm.path())
                .size(px(9.0))
                .text_color(theme::muted())
                .group_hover(group, |style| style.text_color(theme::text_hi())),
        )
}

/// New Terminal, Split Right and Split Down, for this region.
fn buttons(slot: SlotId, lang: Lang, cx: &mut Context<RootView>) -> Div {
    div()
        .flex()
        .flex_row()
        .flex_none()
        .items_center()
        .gap(px(2.0))
        .pr(px(6.0))
        .child(button(
            slot,
            "terminal",
            Icon::Terminal,
            Str::NewTerminal,
            lang,
            cx.listener(move |this, _: &ClickEvent, window, cx| {
                this.new_terminal(slot, window, cx);
            }),
        ))
        .child(button(
            slot,
            "right",
            Icon::Columns,
            Str::SplitRight,
            lang,
            cx.listener(move |this, _: &ClickEvent, window, cx| {
                this.split(slot, Axis::Row, window, cx);
            }),
        ))
        .child(button(
            slot,
            "down",
            Icon::Rows,
            Str::SplitDown,
            lang,
            cx.listener(move |this, _: &ClickEvent, window, cx| {
                this.split(slot, Axis::Column, window, cx);
            }),
        ))
}

/// A 20 px icon button with a tooltip; `name` keeps its id apart from the
/// other regions' buttons.
fn button(
    slot: SlotId,
    name: &'static str,
    icon: Icon,
    tip: Str,
    lang: Lang,
    on_click: impl Fn(&ClickEvent, &mut gpui::Window, &mut gpui::App) + 'static,
) -> Stateful<Div> {
    let tip: SharedString = t(lang, tip).into();
    let id = SharedString::from(format!("tab-bar-{}-{name}", slot.0));
    div()
        .id(ElementId::from(id.clone()))
        .group(id.clone())
        .flex()
        .flex_none()
        .items_center()
        .justify_center()
        .size(px(20.0))
        .rounded(px(4.0))
        .cursor_pointer()
        .tooltip(move |_, cx| Tooltip::view(tip.clone(), cx))
        .on_click(on_click)
        .child(
            svg()
                .path(icon.path())
                .size(px(14.0))
                .text_color(theme::muted())
                .group_hover(id, |style| style.text_color(theme::text_hi())),
        )
}
