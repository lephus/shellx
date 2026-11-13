//! The stepper (the Mac's `Stepper` with its value as the label): the value in its unit, then
//! − and + buttons joined in one 22 high box. A click on a button or Up / Down moves the value
//! one step; a button is dimmed at its end of the range.

use gpui::{
    ClickEvent, Context, EventEmitter, FocusHandle, Focusable, KeyDownEvent, Window, div,
    prelude::*, px,
};
use shellx_model::controls;
use shellx_model::settings_catalog::Unit;

use super::super::theme;
use super::{CONTROL_H, CONTROL_TEXT, DISABLED_OPACITY, key_in, ring};

const BUTTON_W: f32 = 20.0;

#[derive(Clone, Copy, Debug, PartialEq)]
pub enum StepperEvent {
    Changed(f32),
}

pub struct Stepper {
    focus_handle: FocusHandle,
    value: f32,
    min: f32,
    max: f32,
    step: f32,
    unit: Unit,
    disabled: bool,
}

impl EventEmitter<StepperEvent> for Stepper {}

impl Focusable for Stepper {
    fn focus_handle(&self, _: &gpui::App) -> FocusHandle {
        self.focus_handle.clone()
    }
}

impl Stepper {
    pub fn new(
        value: f32,
        min: f32,
        max: f32,
        step: f32,
        unit: Unit,
        cx: &mut Context<Self>,
    ) -> Self {
        Stepper {
            focus_handle: cx.focus_handle().tab_stop(true),
            value,
            min,
            max,
            step,
            unit,
            disabled: false,
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
            cx.notify();
        }
    }

    fn step_by(&mut self, steps: i32, cx: &mut Context<Self>) {
        let value = controls::stepped(self.value, steps, self.min, self.max, self.step);
        if value != self.value {
            self.value = value;
            cx.emit(StepperEvent::Changed(value));
            cx.notify();
        }
    }

    fn on_key_down(&mut self, event: &KeyDownEvent, window: &mut Window, cx: &mut Context<Self>) {
        if self.disabled || !self.focus_handle.is_focused(window) {
            return;
        }
        if let Some(steps) = controls::stepper_key(&key_in(event)) {
            cx.stop_propagation();
            self.step_by(steps, cx);
        }
    }

    /// − (`steps` −1) or + (`steps` 1); `can` is false at that end of the range.
    fn button(
        &self,
        id: &'static str,
        glyph: &'static str,
        steps: i32,
        can: bool,
        cx: &mut Context<Self>,
    ) -> impl IntoElement {
        div()
            .id(id)
            .flex()
            .items_center()
            .justify_center()
            .w(px(BUTTON_W))
            .h_full()
            .text_color(theme::text())
            .map(|button| {
                if self.disabled {
                    // The whole stepper is dimmed already.
                    button
                } else if !can {
                    button.opacity(DISABLED_OPACITY)
                } else {
                    button
                        .cursor_pointer()
                        .hover(|style| style.bg(theme::line()))
                        .on_click(cx.listener(move |this, _: &ClickEvent, _, cx| {
                            this.step_by(steps, cx);
                        }))
                }
            })
            .child(glyph)
    }
}

impl Render for Stepper {
    fn render(&mut self, window: &mut Window, cx: &mut Context<Self>) -> impl IntoElement {
        let focused = !self.disabled && self.focus_handle.is_focused(window);
        let value = div()
            .text_size(CONTROL_TEXT)
            .text_color(theme::muted())
            .child(controls::format_value(self.value, self.unit));
        let buttons = div()
            .flex()
            .flex_row()
            .flex_none()
            .h(CONTROL_H)
            .rounded(px(6.0))
            .border_1()
            .border_color(if focused { ring() } else { theme::border() })
            .bg(theme::raise())
            .overflow_hidden()
            .child(self.button("stepper-down", "\u{2212}", -1, self.value > self.min, cx))
            .child(div().w(px(1.0)).h_full().bg(theme::border()))
            .child(self.button("stepper-up", "+", 1, self.value < self.max, cx));
        div()
            .id("stepper")
            .flex()
            .flex_row()
            .flex_none()
            .items_center()
            .gap(px(8.0))
            .when(self.disabled, |stepper| stepper.opacity(DISABLED_OPACITY))
            .when(!self.disabled, |stepper| {
                stepper
                    .track_focus(&self.focus_handle)
                    .on_key_down(cx.listener(Self::on_key_down))
            })
            .child(value)
            .child(buttons)
    }
}
