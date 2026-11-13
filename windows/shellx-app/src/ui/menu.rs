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
//! (a Settings picker). `popover_at` opens at a point of the window (a right-click), scrolling
//! when the list is taller than the room it has; a row may carry a colour swatch and a check
//! mark, or be a heading that does nothing.

use std::rc::Rc;

use gpui::{
    App, ClickEvent, Corner, IntoElement, MouseDownEvent, Pixels, Point, ScrollHandle,
    SharedString, Window, anchored, deferred, div, point, prelude::*, px,
};
use shellx_model::palette::Rgba;

use super::theme;

/// Narrowest the menu gets, in px.
pub(super) const MIN_W: f32 = 220.0;
/// Tallest a scrolling menu gets (`popover_highlighted`), in px: about ten rows.
const MAX_SCROLLING_H: f32 = 280.0;

/// A row's action, and `on_close`.
type Action = dyn Fn(&mut Window, &mut App);

pub(super) struct MenuItem {
    pub label: SharedString,
    /// Shown on the right, e.g. "Ctrl+Shift+N": the action's current chord
    /// (`settings_service::shortcut_label`).
    pub shortcut: Option<SharedString>,
    pub on_click: Box<Action>,
    /// A colour dot before the label (a workspace colour).
    pub swatch: Option<Rgba>,
    /// A check mark before the swatch: the current choice.
    pub checked: bool,
    /// A heading: muted, no hover, no click, and the menu stays open on it.
    pub disabled: bool,
}

impl Default for MenuItem {
    fn default() -> Self {
        MenuItem {
            label: SharedString::default(),
            shortcut: None,
            on_click: Box::new(|_, _| {}),
            swatch: None,
            checked: false,
            disabled: false,
        }
    }
}

/// Opens down from the anchor point, 4 px below it.
pub(super) fn popover(
    items: Vec<MenuItem>,
    on_close: impl Fn(&mut Window, &mut App) + 'static,
) -> impl IntoElement {
    menu(
        items,
        None,
        on_close,
        Place::Anchor(Corner::TopLeft, px(4.0)),
    )
}

/// `popover` with row `highlighted` marked as the hovered row is. A list taller than
/// `MAX_SCROLLING_H` scrolls (mouse wheel, and `scroll.scroll_to_item` keeps the highlighted
/// row in view); a shorter one looks as `popover` does.
pub(super) fn popover_highlighted(
    items: Vec<MenuItem>,
    highlighted: usize,
    scroll: &ScrollHandle,
    on_close: impl Fn(&mut Window, &mut App) + 'static,
) -> impl IntoElement {
    menu(
        items,
        Some((highlighted, scroll)),
        on_close,
        Place::Anchor(Corner::TopLeft, px(4.0)),
    )
}

/// Opens up from the anchor point, 4 px above it.
pub(super) fn popover_above(
    items: Vec<MenuItem>,
    on_close: impl Fn(&mut Window, &mut App) + 'static,
) -> impl IntoElement {
    menu(
        items,
        None,
        on_close,
        Place::Anchor(Corner::BottomLeft, px(-4.0)),
    )
}

/// Opens with its top-left corner at `at` (window coordinates; the caller keeps it inside the
/// window, `workspace_colors::menu_origin`), no taller than `max_height`: a longer list scrolls.
pub(super) fn popover_at(
    items: Vec<MenuItem>,
    at: Point<Pixels>,
    max_height: Pixels,
    on_close: impl Fn(&mut Window, &mut App) + 'static,
) -> impl IntoElement {
    menu(items, None, on_close, Place::At(at, max_height))
}

/// Where the menu goes.
enum Place {
    /// `corner` of the menu goes `gap` (down is positive) from the anchor point.
    Anchor(Corner, Pixels),
    At(Point<Pixels>, Pixels),
}

fn menu(
    items: Vec<MenuItem>,
    highlighted: Option<(usize, &ScrollHandle)>,
    on_close: impl Fn(&mut Window, &mut App) + 'static,
    place: Place,
) -> impl IntoElement {
    let on_close: Rc<Action> = Rc::new(on_close);
    let (highlighted, scroll) = match highlighted {
        Some((ix, scroll)) => (Some(ix), Some(scroll)),
        None => (None, None),
    };
    let mut list = div()
        .id("menu-list")
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
        })
        .when_some(scroll, |list, scroll| {
            list.max_h(px(MAX_SCROLLING_H))
                .overflow_y_scroll()
                .track_scroll(scroll)
        })
        .when_some(
            match place {
                Place::At(_, max_height) => Some(max_height),
                Place::Anchor(..) => None,
            },
            |list, max_height| list.max_h(max_height).overflow_y_scroll(),
        );
    for (ix, item) in items.into_iter().enumerate() {
        let on_close = on_close.clone();
        let MenuItem {
            label,
            shortcut,
            on_click,
            swatch,
            checked,
            disabled,
        } = item;
        list = list.child(
            div()
                .id(("menu-item", ix))
                .flex_none()
                .flex()
                .flex_row()
                .items_center()
                .gap(px(24.0))
                .mx(px(4.0))
                .px(px(8.0))
                .py(px(5.0))
                .rounded(px(4.0))
                .when(!disabled, |row| {
                    row.cursor_pointer()
                        .when(highlighted == Some(ix), |row| row.bg(theme::panel_hover()))
                        .hover(|style| style.bg(theme::panel_hover()))
                        .on_click(move |_: &ClickEvent, window, cx| {
                            on_click(window, cx);
                            on_close(window, cx);
                        })
                })
                .child(
                    div()
                        .flex_1()
                        .min_w_0()
                        .flex()
                        .flex_row()
                        .items_center()
                        .gap(px(6.0))
                        .when_some(swatch, |label, colour| {
                            label
                                .child(
                                    div()
                                        .flex_none()
                                        .w(px(12.0))
                                        .text_size(theme::SMALL_SIZE)
                                        .text_color(theme::text_hi())
                                        .child(if checked { "\u{2713}" } else { "" }),
                                )
                                .child(
                                    div()
                                        .flex_none()
                                        .size(px(12.0))
                                        .rounded_full()
                                        .bg(theme::hsla(colour)),
                                )
                        })
                        .child(
                            div()
                                .min_w_0()
                                .truncate()
                                .text_color(if disabled {
                                    theme::muted()
                                } else {
                                    theme::text_hi()
                                })
                                .child(label),
                        ),
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
    let anchor = anchored().snap_to_window_with_margin(px(8.0));
    let anchor = match place {
        Place::Anchor(corner, gap) => anchor.anchor(corner).offset(point(px(0.0), gap)),
        Place::At(at, _) => anchor.anchor(Corner::TopLeft).position(at),
    };
    deferred(anchor.child(list)).with_priority(1)
}
