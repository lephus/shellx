//! The slider (the Mac's `Slider` with its value beside it): a 130 wide track and the value
//! in its unit. A press on the track moves the knob there and drags it; Left and Right move
//! it one step. It emits every new value, while dragging too (the settings service writes the
//! file once the value stops changing).

use gpui::{
    Bounds, Context, DispatchPhase, EventEmitter, FocusHandle, Focusable, FontWeight, KeyDownEvent,
    MouseButton, MouseDownEvent, MouseMoveEvent, MouseUpEvent, Pixels, Window, canvas, div,
    prelude::*, px,
};
use shellx_model::controls::{self, DragMove};
use shellx_model::settings_catalog::Unit;

use super::super::theme;
use super::{CONTROL_TEXT, DISABLED_OPACITY, key_in, ring};

const TRACK_W: f32 = 130.0;
/// The height that takes presses: the knob's, plus a little.
const HIT_H: f32 = 18.0;
const RAIL_H: f32 = 4.0;
const KNOB: f32 = 14.0;
const VALUE_W: f32 = 44.0;

#[derive(Clone, Copy, Debug, PartialEq)]
pub enum SliderEvent {
    Changed(f32),
}

pub struct Slider {
    focus_handle: FocusHandle,
    value: f32,
    min: f32,
    max: f32,
    step: f32,
    unit: Unit,
    disabled: bool,
    dragging: bool,
    /// Where the track was laid out last: the pointer's place along it.
    track: Option<Bounds<Pixels>>,
}

impl EventEmitter<SliderEvent> for Slider {}

impl Focusable for Slider {
    fn focus_handle(&self, _: &gpui::App) -> FocusHandle {
        self.focus_handle.clone()
    }
}

impl Slider {
    pub fn new(
        value: f32,
        min: f32,
        max: f32,
        step: f32,
        unit: Unit,
        cx: &mut Context<Self>,
    ) -> Self {
        Slider {
            focus_handle: cx.focus_handle().tab_stop(true),
            value,
            min,
            max,
            step,
            unit,
            disabled: false,
            dragging: false,
            track: None,
        }
    }

    /// Shows `value`; emits nothing.
    pub fn set_value(&mut self, value: f32, cx: &mut Context<Self>) {
        if self.value != value {
            self.value = value;
            cx.notify();
        }
    }

    pub fn set_disabled(&mut self, disabled: bool, cx: &mut Context<Self>) {
        if self.disabled != disabled {
            self.disabled = disabled;
            self.dragging = false;
            cx.notify();
        }
    }

    fn change(&mut self, value: f32, cx: &mut Context<Self>) {
        if self.value != value {
            self.value = value;
            cx.emit(SliderEvent::Changed(value));
            cx.notify();
        }
    }

    /// The knob's centre follows the pointer.
    fn drag_to(&mut self, x: Pixels, cx: &mut Context<Self>) {
        let Some(track) = self.track else {
            return;
        };
        let travel = f32::from(track.size.width) - KNOB;
        let fraction = if travel > 0.0 {
            (f32::from(x - track.origin.x) - KNOB / 2.0) / travel
        } else {
            0.0
        };
        let value = controls::slider_value(fraction, self.min, self.max, self.step);
        self.change(value, cx);
    }

    /// A pointer move anywhere in the window while a drag is on. A move without the left
    /// button ends the drag: GPUI-Windows sends no mouse-up when the capture is lost.
    fn on_drag_move(&mut self, event: &MouseMoveEvent, cx: &mut Context<Self>) {
        let left_down = event.pressed_button == Some(MouseButton::Left);
        match controls::slider_drag_move(self.dragging, left_down) {
            DragMove::Ignore => {}
            DragMove::Follow => self.drag_to(event.position.x, cx),
            DragMove::End => self.dragging = false,
        }
    }

    fn on_mouse_down(&mut self, event: &MouseDownEvent, _: &mut Window, cx: &mut Context<Self>) {
        if !self.disabled {
            self.dragging = true;
            self.drag_to(event.position.x, cx);
        }
    }

    fn on_key_down(&mut self, event: &KeyDownEvent, window: &mut Window, cx: &mut Context<Self>) {
        if self.disabled || !self.focus_handle.is_focused(window) {
            return;
        }
        if let Some(steps) = controls::slider_key(&key_in(event)) {
            cx.stop_propagation();
            let value = controls::stepped(self.value, steps, self.min, self.max, self.step);
            self.change(value, cx);
        }
    }
}

impl Render for Slider {
    fn render(&mut self, window: &mut Window, cx: &mut Context<Self>) -> impl IntoElement {
        let focused = !self.disabled && self.focus_handle.is_focused(window);
        let fraction = controls::slider_fraction(self.value, self.min, self.max);
        let knob_x = fraction * (TRACK_W - KNOB);
        let rail_top = (HIT_H - RAIL_H) / 2.0;
        let slider = cx.entity();
        let track = div()
            .relative()
            .flex_none()
            .w(px(TRACK_W))
            .h(px(HIT_H))
            .child(
                div()
                    .absolute()
                    .left(px(KNOB / 2.0))
                    .right(px(KNOB / 2.0))
                    .top(px(rail_top))
                    .h(px(RAIL_H))
                    .rounded_full()
                    .bg(theme::border()),
            )
            .child(
                div()
                    .absolute()
                    .left(px(KNOB / 2.0))
                    .top(px(rail_top))
                    .w(px(knob_x))
                    .h(px(RAIL_H))
                    .rounded_full()
                    .bg(theme::primary()),
            )
            .child(
                div()
                    .absolute()
                    .left(px(knob_x))
                    .top(px((HIT_H - KNOB) / 2.0))
                    .size(px(KNOB))
                    .rounded_full()
                    .border_1()
                    .border_color(if focused { ring() } else { theme::border() })
                    .bg(theme::text_hi()),
            )
            // Records the track's bounds; while a drag is on, takes the pointer's moves and
            // the release anywhere in the window (GPUI captures the mouse on the press).
            .child(
                canvas(
                    {
                        let slider = slider.clone();
                        move |bounds, _, cx| {
                            slider.update(cx, |this, _| this.track = Some(bounds));
                        }
                    },
                    move |_, (), window, _| {
                        let moves = slider.clone();
                        window.on_mouse_event(move |event: &MouseMoveEvent, phase, _, cx| {
                            if phase == DispatchPhase::Bubble && moves.read(cx).dragging {
                                moves.update(cx, |this, cx| this.on_drag_move(event, cx));
                            }
                        });
                        window.on_mouse_event(move |event: &MouseUpEvent, phase, _, cx| {
                            if phase == DispatchPhase::Bubble
                                && event.button == MouseButton::Left
                                && slider.read(cx).dragging
                            {
                                slider.update(cx, |this, _| this.dragging = false);
                            }
                        });
                    },
                )
                .absolute()
                .size_full(),
            )
            .when(!self.disabled, |track| {
                track
                    .cursor_pointer()
                    .on_mouse_down(MouseButton::Left, cx.listener(Self::on_mouse_down))
            });
        let value = div()
            .flex()
            .flex_none()
            .justify_end()
            .w(px(VALUE_W))
            .text_size(CONTROL_TEXT)
            .font_weight(FontWeight::MEDIUM)
            .text_color(theme::text())
            .child(controls::format_value(self.value, self.unit));
        div()
            .id("slider")
            .flex()
            .flex_row()
            .flex_none()
            .items_center()
            .gap(px(8.0))
            .map(|slider| {
                if self.disabled {
                    slider.opacity(DISABLED_OPACITY)
                } else {
                    slider
                        .track_focus(&self.focus_handle)
                        .on_key_down(cx.listener(Self::on_key_down))
                }
            })
            .child(track)
            .child(value)
    }
}
