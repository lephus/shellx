//! The switch (the Mac's `Toggle` in switch style): 32×18, the primary colour when on.

use std::rc::Rc;

use gpui::{
    App, ClickEvent, Div, ElementId, KeyDownEvent, Stateful, Window, div, prelude::*, px,
    transparent_black,
};
use shellx_model::controls;

use super::super::theme;
use super::{DISABLED_OPACITY, focus_ring, is_mouse, key_in};

const WIDTH: f32 = 32.0;
const HEIGHT: f32 = 18.0;
const KNOB: f32 = 14.0;

/// A click, Space or Enter calls `on_change` with the opposite of `on`.
pub fn toggle(
    id: impl Into<ElementId>,
    on: bool,
    disabled: bool,
    on_change: impl Fn(bool, &mut Window, &mut App) + 'static,
) -> Stateful<Div> {
    let switch = div()
        .id(id)
        .flex()
        .flex_none()
        .items_center()
        .when(on, |switch| switch.justify_end())
        .w(px(WIDTH))
        .h(px(HEIGHT))
        // With the 1 px ring, the knob sits 2 px inside the track.
        .px(px(1.0))
        .rounded_full()
        .border_1()
        .border_color(transparent_black())
        .bg(if on {
            theme::primary()
        } else {
            theme::border()
        })
        .child(div().size(px(KNOB)).rounded_full().bg(theme::text_hi()));
    if disabled {
        return switch.opacity(DISABLED_OPACITY);
    }
    let on_change = Rc::new(on_change);
    switch
        .tab_index(0)
        .cursor_pointer()
        .focus(focus_ring)
        .on_click({
            let on_change = on_change.clone();
            move |event: &ClickEvent, window, cx| {
                if is_mouse(event) {
                    on_change(!on, window, cx);
                }
            }
        })
        .on_key_down(move |event: &KeyDownEvent, window, cx| {
            if controls::activates(&key_in(event)) {
                cx.stop_propagation();
                if !event.is_held {
                    on_change(!on, window, cx);
                }
            }
        })
}
