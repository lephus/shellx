//! A small popover menu (the title bar's "+" options; the help menu): a
//! RAISE box of rows, each a label with an optional shortcut on the right.
//!
//! The caller decides where it shows: it puts `popover` inside an absolutely
//! positioned box at the anchor point, and the menu's top-left goes there
//! (moved back into the window if it would spill out). `popover_above` is the
//! same for a button at the window's bottom: the menu's bottom-left goes at
//! the anchor point, so it opens upward. It is drawn after everything else,
//! so it covers what is under it. It is not a panel: it holds no focus, so
//! the keyboard stays where it was. A press outside it, or a click on a row
//! (after the row's action), calls `on_close`. `popover_highlighted` also
//! marks one row, for the owner that moves through the rows with the keys
//! (a Settings picker).

use std::rc::Rc;

use gpui::{
    App, ClickEvent, Corner, IntoElement, MouseDownEvent, Pixels, SharedString, Window, anchored,
    deferred, div, point, prelude::*, px,
};

use super::theme;

/// Narrowest the menu gets, in px.
const MIN_W: f32 = 220.0;

/// A row's action, and `on_close`.
type Action = dyn Fn(&mut Window, &mut App);

pub(super) struct MenuItem {
    pub label: SharedString,
    /// Shown on the right, e.g. "Ctrl+Shift+N": the action's current chord
    /// (`settings_service::shortcut_label`).
    pub shortcut: Option<SharedString>,
    pub on_click: Box<Action>,
}

/// Opens down from the anchor point, 4 px below it.
pub(super) fn popover(
    items: Vec<MenuItem>,
    on_close: impl Fn(&mut Window, &mut App) + 'static,
) -> impl IntoElement {
    menu(items, None, on_close, Corner::TopLeft, px(4.0))
}

/// `popover` with row `highlighted` marked as the hovered row is.
pub(super) fn popover_highlighted(
    items: Vec<MenuItem>,
    highlighted: usize,
    on_close: impl Fn(&mut Window, &mut App) + 'static,
) -> impl IntoElement {
    menu(items, Some(highlighted), on_close, Corner::TopLeft, px(4.0))
}

/// Opens up from the anchor point, 4 px above it.
pub(super) fn popover_above(
    items: Vec<MenuItem>,
    on_close: impl Fn(&mut Window, &mut App) + 'static,
) -> impl IntoElement {
    menu(items, None, on_close, Corner::BottomLeft, px(-4.0))
}

/// `corner` of the menu goes `gap` (down is positive) from the anchor point.
fn menu(
    items: Vec<MenuItem>,
    highlighted: Option<usize>,
    on_close: impl Fn(&mut Window, &mut App) + 'static,
    corner: Corner,
    gap: Pixels,
) -> impl IntoElement {
    let on_close: Rc<Action> = Rc::new(on_close);
    let mut list = div()
        .occlude()
        .flex()
        .flex_col()
        .min_w(px(MIN_W))
        .py(px(4.0))
        .bg(theme::raise())
        .border_1()
        .border_color(theme::border())
        .rounded(px(8.0))
        .font(theme::ui_font())
        .text_size(theme::UI_SIZE)
        .on_mouse_down_out({
            let on_close = on_close.clone();
            move |_: &MouseDownEvent, window, cx| on_close(window, cx)
        });
    for (ix, item) in items.into_iter().enumerate() {
        let on_close = on_close.clone();
        let MenuItem {
            label,
            shortcut,
            on_click,
        } = item;
        list = list.child(
            div()
                .id(("menu-item", ix))
                .flex()
                .flex_row()
                .items_center()
                .gap(px(24.0))
                .mx(px(4.0))
                .px(px(8.0))
                .py(px(5.0))
                .rounded(px(4.0))
                .cursor_pointer()
                .when(highlighted == Some(ix), |row| {
                    row.bg(theme::hsla(theme::SESSION_HOVER))
                })
                .hover(|style| style.bg(theme::hsla(theme::SESSION_HOVER)))
                .on_click(move |_: &ClickEvent, window, cx| {
                    on_click(window, cx);
                    on_close(window, cx);
                })
                .child(
                    div()
                        .flex_1()
                        .min_w_0()
                        .truncate()
                        .text_color(theme::text_hi())
                        .child(label),
                )
                .children(shortcut.map(|keys| {
                    div()
                        .flex_none()
                        .text_size(theme::SMALL_SIZE)
                        .text_color(theme::muted())
                        .child(keys)
                })),
        );
    }
    deferred(
        anchored()
            .anchor(corner)
            .offset(point(px(0.0), gap))
            .snap_to_window_with_margin(px(8.0))
            .child(list),
    )
    .with_priority(1)
}
