//! The colour well (the Mac's `ColorPicker`, 38 wide): a swatch button. A click, Space or Enter
//! opens a popover under it with a "#RRGGBB" field and a grid of swatches; the field has the
//! keyboard while it is open. Enter applies a valid code; an invalid one turns the field's
//! border to the error colour and emits nothing, until the text is a valid code again. A
//! click on a swatch applies it. Esc, Tab, Shift+Tab or a press outside close the popover;
//! the keyboard goes back to the well (Tab then moves on to the next control).

use gpui::{
    ClickEvent, Context, Corner, Entity, EventEmitter, FocusHandle, Focusable, KeyDownEvent,
    MouseDownEvent, Subscription, Window, anchored, deferred, div, point, prelude::*, px,
};
use shellx_model::controls;
use shellx_model::palette::Rgba;

use super::super::text_field::{TextField, TextFieldEvent};
use super::super::theme;
use super::{CONTROL_H, DISABLED_OPACITY, is_mouse, key_in, ring};

const WELL_W: f32 = 38.0;
const FIELD_W: f32 = 124.0;
const SWATCH: f32 = 18.0;
const SWATCH_GAP: f32 = 6.0;
const SWATCHES_PER_ROW: usize = 8;

#[derive(Clone, Copy, Debug, PartialEq)]
pub enum ColorEvent {
    Picked(Rgba),
}

pub struct ColorWell {
    focus_handle: FocusHandle,
    value: Rgba,
    swatches: Vec<Rgba>,
    disabled: bool,
    open: bool,
    /// Made the first time the popover opens (its events need the window).
    field: Option<Entity<TextField>>,
    _field_subscriptions: Vec<Subscription>,
}

impl EventEmitter<ColorEvent> for ColorWell {}

impl Focusable for ColorWell {
    fn focus_handle(&self, _: &gpui::App) -> FocusHandle {
        self.focus_handle.clone()
    }
}

impl ColorWell {
    /// `swatches` fill the popover's grid, in order.
    pub fn new(value: Rgba, swatches: Vec<Rgba>, cx: &mut Context<Self>) -> Self {
        ColorWell {
            focus_handle: cx.focus_handle().tab_stop(true),
            value,
            swatches,
            disabled: false,
            open: false,
            field: None,
            _field_subscriptions: Vec::new(),
        }
    }

    /// Shows `value`; emits nothing.
    pub fn set_value(&mut self, value: Rgba, cx: &mut Context<Self>) {
        if self.value != value {
            self.value = value;
            cx.notify();
        }
    }

    pub fn set_disabled(&mut self, disabled: bool, cx: &mut Context<Self>) {
        if self.disabled != disabled {
            self.disabled = disabled;
            self.open = false;
            cx.notify();
        }
    }

    fn open_popover(&mut self, window: &mut Window, cx: &mut Context<Self>) {
        if self.disabled {
            return;
        }
        let field = match &self.field {
            Some(field) => field.clone(),
            None => {
                let field = cx.new(|cx| TextField::new(false, "#RRGGBB", cx));
                self._field_subscriptions = vec![
                    cx.subscribe_in(&field, window, Self::on_field_event),
                    // The error border goes as soon as the text is a valid code.
                    cx.observe(&field, |_, field, cx| {
                        if controls::parse_hex(field.read(cx).text()).is_some() {
                            field.update(cx, |field, cx| field.set_invalid(false, cx));
                        }
                    }),
                ];
                self.field = Some(field.clone());
                field
            }
        };
        let hex = self.value.hex().to_uppercase();
        field.update(cx, |field, cx| {
            field.set_text(&hex, cx);
            field.set_invalid(false, cx);
        });
        window.focus(&field.focus_handle(cx));
        self.open = true;
        cx.notify();
    }

    /// Closes the popover; the keyboard comes back to the well if the field had it.
    fn close(&mut self, window: &mut Window, cx: &mut Context<Self>) {
        if !self.open {
            return;
        }
        self.open = false;
        if let Some(field) = &self.field
            && field.focus_handle(cx).is_focused(window)
        {
            window.focus(&self.focus_handle);
        }
        cx.notify();
    }

    fn pick(&mut self, color: Rgba, window: &mut Window, cx: &mut Context<Self>) {
        self.value = color;
        cx.emit(ColorEvent::Picked(color));
        self.close(window, cx);
    }

    fn on_field_event(
        &mut self,
        field: &Entity<TextField>,
        event: &TextFieldEvent,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) {
        match event {
            TextFieldEvent::Submit => match controls::parse_hex(field.read(cx).text()) {
                Some(color) => self.pick(color, window, cx),
                None => field.update(cx, |field, cx| field.set_invalid(true, cx)),
            },
            TextFieldEvent::Cancel | TextFieldEvent::Prev => self.close(window, cx),
            TextFieldEvent::Next => {
                self.close(window, cx);
                window.focus_next();
            }
            TextFieldEvent::Blur => {}
        }
    }

    fn on_key_down(&mut self, event: &KeyDownEvent, window: &mut Window, cx: &mut Context<Self>) {
        // The popover's field sits under the well in the key path: only the well's own keys.
        if self.disabled || self.open || !self.focus_handle.is_focused(window) {
            return;
        }
        if controls::activates(&key_in(event)) {
            cx.stop_propagation();
            if !event.is_held {
                self.open_popover(window, cx);
            }
        }
    }

    fn popover(&self, field: Entity<TextField>, cx: &mut Context<Self>) -> impl IntoElement {
        let mut grid = div().flex().flex_col().gap(px(SWATCH_GAP));
        for (row_ix, colors) in self.swatches.chunks(SWATCHES_PER_ROW).enumerate() {
            let mut row = div().flex().flex_row().gap(px(SWATCH_GAP));
            for (col_ix, &color) in colors.iter().enumerate() {
                let current = color == self.value;
                row = row.child(
                    div()
                        .id(("swatch", row_ix * SWATCHES_PER_ROW + col_ix))
                        .size(px(SWATCH))
                        .rounded(px(4.0))
                        .border_1()
                        .border_color(if current { ring() } else { theme::line() })
                        .bg(theme::hsla(color))
                        .cursor_pointer()
                        .hover(|style| style.border_color(theme::text_hi()))
                        .on_click(cx.listener(move |this, _: &ClickEvent, window, cx| {
                            this.pick(color, window, cx);
                        })),
                );
            }
            grid = grid.child(row);
        }
        deferred(
            anchored()
                .anchor(Corner::TopLeft)
                .offset(point(px(0.0), px(4.0)))
                .snap_to_window_with_margin(px(8.0))
                .child(
                    div()
                        .occlude()
                        .flex()
                        .flex_col()
                        .gap(px(10.0))
                        .p(px(10.0))
                        .bg(theme::raise())
                        .border_1()
                        .border_color(theme::border())
                        .rounded(px(8.0))
                        .on_mouse_down_out(cx.listener(|this, _: &MouseDownEvent, window, cx| {
                            this.close(window, cx);
                        }))
                        .child(div().w(px(FIELD_W)).child(field))
                        .when(!self.swatches.is_empty(), |popover| popover.child(grid)),
                ),
        )
        .with_priority(1)
    }
}

impl Render for ColorWell {
    fn render(&mut self, window: &mut Window, cx: &mut Context<Self>) -> impl IntoElement {
        let focused = !self.disabled && self.focus_handle.is_focused(window);
        let well = div()
            .id("color-well")
            .flex_none()
            .w(px(WELL_W))
            .h(CONTROL_H)
            .p(px(3.0))
            .rounded(px(6.0))
            .border_1()
            .border_color(if focused { ring() } else { theme::border() })
            .bg(theme::raise())
            .child(
                div()
                    .size_full()
                    .rounded(px(3.0))
                    .bg(theme::hsla(self.value)),
            );
        let well = if self.disabled {
            well.opacity(DISABLED_OPACITY)
        } else {
            well.track_focus(&self.focus_handle)
                .cursor_pointer()
                .when(!focused, |well| {
                    well.hover(|style| style.border_color(theme::primary_line()))
                })
                // While the popover is open, a press here only closes it: otherwise its
                // "press outside" would close it and this click would open it again.
                .capture_any_mouse_down(cx.listener(|this, _: &MouseDownEvent, window, cx| {
                    if this.open {
                        this.close(window, cx);
                        cx.stop_propagation();
                    }
                }))
                .on_click(cx.listener(|this, event: &ClickEvent, window, cx| {
                    if is_mouse(event) {
                        this.open_popover(window, cx);
                    }
                }))
                .on_key_down(cx.listener(Self::on_key_down))
        };
        let popover = match (&self.field, self.open) {
            (Some(field), true) => Some(
                div()
                    .absolute()
                    .top_full()
                    .left_0()
                    .child(self.popover(field.clone(), cx)),
            ),
            _ => None,
        };
        div().relative().flex_none().child(well).children(popover)
    }
}
