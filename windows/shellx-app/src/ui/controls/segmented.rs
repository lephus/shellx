//! The segmented control (the Mac's segmented `Picker`): 22 high, one segment per option, the
//! chosen one in the primary colour. Each segment is a tab stop of its own.

use std::rc::Rc;

use gpui::{
    App, ClickEvent, Div, ElementId, KeyDownEvent, SharedString, Stateful, Window, div, prelude::*,
    px, transparent_black,
};
use shellx_model::controls;

use super::super::theme;
use super::{CONTROL_H, CONTROL_TEXT, DISABLED_OPACITY, focus_ring, is_mouse, key_in};

/// `options` are (label, value); a click, Space or Enter on a segment calls `on_pick` with its
/// value, also when it is the chosen one.
pub fn segmented(
    id: impl Into<ElementId>,
    options: &[(SharedString, &'static str)],
    selected: &str,
    disabled: bool,
    on_pick: impl Fn(&'static str, &mut Window, &mut App) + 'static,
) -> Stateful<Div> {
    let on_pick = Rc::new(on_pick);
    let mut control = div()
        .id(id)
        .flex()
        .flex_row()
        .flex_none()
        .items_center()
        .gap(px(1.0))
        .h(CONTROL_H)
        .p(px(1.0))
        .rounded(px(6.0))
        .border_1()
        .border_color(theme::border())
        .bg(theme::bg())
        .text_size(CONTROL_TEXT)
        .when(disabled, |control| control.opacity(DISABLED_OPACITY));
    for (ix, (label, value)) in options.iter().enumerate() {
        let value = *value;
        let chosen = value == selected;
        let segment = div()
            .id(("segment", ix))
            .flex()
            .items_center()
            .justify_center()
            .h_full()
            .px(px(10.0))
            .rounded(px(4.0))
            .border_1()
            .border_color(transparent_black())
            .map(|segment| {
                if chosen {
                    segment
                        .bg(theme::primary_soft())
                        .text_color(theme::primary_text())
                } else {
                    segment.text_color(theme::text())
                }
            })
            .child(label.clone());
        control = control.child(if disabled {
            segment
        } else {
            let on_pick = on_pick.clone();
            segment
                .tab_index(0)
                .cursor_pointer()
                .focus(focus_ring)
                .when(!chosen, |segment| {
                    segment.hover(|style| style.bg(theme::raise()))
                })
                .on_click({
                    let on_pick = on_pick.clone();
                    move |event: &ClickEvent, window, cx| {
                        if is_mouse(event) {
                            on_pick(value, window, cx);
                        }
                    }
                })
                .on_key_down(move |event: &KeyDownEvent, window, cx| {
                    if controls::activates(&key_in(event)) {
                        cx.stop_propagation();
                        if !event.is_held {
                            on_pick(value, window, cx);
                        }
                    }
                })
        });
    }
    control
}
