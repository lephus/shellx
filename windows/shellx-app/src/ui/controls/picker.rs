//! The picker (the Mac's menu-style `Picker`): a 22 high button showing the chosen option's
//! label; a click, Space or Enter opens the list (`menu::popover_highlighted`) under it.
//! The list holds no focus: the keyboard stays on the picker, where Up and Down move the
//! highlight, Space or Enter picks and Esc closes. A press outside closes it, and so does Tab
//! (which goes on to move the focus).

use gpui::{
    ClickEvent, Context, EventEmitter, FocusHandle, Focusable, KeyDownEvent, MouseDownEvent,
    ScrollHandle, SharedString, Window, div, point, prelude::*, px, svg,
};
use shellx_model::controls::{self, PopoverKey};

use super::super::assets::Icon;
use super::super::menu::{self, MenuItem};
use super::super::theme;
use super::{CONTROL_H, CONTROL_TEXT, DISABLED_OPACITY, is_mouse, key_in, ring};

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum PickerEvent {
    /// The value of the picked option (also when it is the current one).
    Picked(SharedString),
}

pub struct Picker {
    focus_handle: FocusHandle,
    /// (label, value)
    options: Vec<(SharedString, SharedString)>,
    value: SharedString,
    disabled: bool,
    /// The highlighted row while the list is open.
    open: Option<usize>,
    /// The list's scroll position: a long list (the Font picker) scrolls to the highlight.
    scroll: ScrollHandle,
}

impl EventEmitter<PickerEvent> for Picker {}

impl Focusable for Picker {
    fn focus_handle(&self, _: &gpui::App) -> FocusHandle {
        self.focus_handle.clone()
    }
}

impl Picker {
    /// `options` are (label, value).
    pub fn new(
        options: Vec<(SharedString, SharedString)>,
        value: impl Into<SharedString>,
        cx: &mut Context<Self>,
    ) -> Self {
        Picker {
            focus_handle: cx.focus_handle().tab_stop(true),
            options,
            value: value.into(),
            disabled: false,
            open: None,
            scroll: ScrollHandle::new(),
        }
    }

    /// Shows `value` as chosen; emits nothing.
    pub fn set_value(&mut self, value: impl Into<SharedString>, cx: &mut Context<Self>) {
        let value = value.into();
        if self.value != value {
            self.value = value;
            cx.notify();
        }
    }

    /// Shows the options with these labels (a new language); the values stay.
    pub fn set_labels(&mut self, options: Vec<(SharedString, SharedString)>, cx: &mut Context<Self>) {
        if self.options != options {
            self.options = options;
            cx.notify();
        }
    }

    pub fn set_disabled(&mut self, disabled: bool, cx: &mut Context<Self>) {
        if self.disabled != disabled {
            self.disabled = disabled;
            self.open = None;
            cx.notify();
        }
    }

    pub fn is_open(&self) -> bool {
        self.open.is_some()
    }

    fn selected_index(&self) -> Option<usize> {
        self.options
            .iter()
            .position(|(_, value)| *value == self.value)
    }

    fn open_list(&mut self, cx: &mut Context<Self>) {
        if !self.disabled && !self.options.is_empty() {
            let at = self.selected_index().unwrap_or(0);
            self.open = Some(at);
            self.scroll.set_offset(point(px(0.0), px(0.0)));
            self.scroll.scroll_to_item(at);
            cx.notify();
        }
    }

    fn close(&mut self, cx: &mut Context<Self>) {
        if self.open.take().is_some() {
            cx.notify();
        }
    }

    fn pick(&mut self, ix: usize, cx: &mut Context<Self>) {
        self.open = None;
        if let Some((_, value)) = self.options.get(ix) {
            self.value = value.clone();
            cx.emit(PickerEvent::Picked(value.clone()));
        }
        cx.notify();
    }

    fn on_key_down(&mut self, event: &KeyDownEvent, window: &mut Window, cx: &mut Context<Self>) {
        if self.disabled || !self.focus_handle.is_focused(window) {
            return;
        }
        let key = key_in(event);
        match self.open {
            None => {
                if controls::activates(&key) {
                    cx.stop_propagation();
                    if !event.is_held {
                        self.open_list(cx);
                    }
                }
            }
            Some(highlighted) => match controls::popover_key(&key) {
                Some(PopoverKey::Move(delta)) => {
                    cx.stop_propagation();
                    let moved = controls::moved_highlight(highlighted, delta, self.options.len());
                    self.open = Some(moved);
                    self.scroll.scroll_to_item(moved);
                    cx.notify();
                }
                Some(PopoverKey::Pick) => {
                    cx.stop_propagation();
                    if !event.is_held {
                        self.pick(highlighted, cx);
                    }
                }
                Some(PopoverKey::Close) => {
                    cx.stop_propagation();
                    self.close(cx);
                }
                // Tab closes the list and goes on to move the focus.
                None if key.key == "tab" => self.close(cx),
                None => {}
            },
        }
    }

    fn list(&self, highlighted: usize, cx: &mut Context<Self>) -> impl IntoElement {
        let picker = cx.entity().downgrade();
        let items = (0..self.options.len())
            .map(|ix| {
                let picker = picker.clone();
                MenuItem {
                    label: self.options[ix].0.clone(),
                    shortcut: None,
                    on_click: Box::new(move |_, cx| {
                        picker.update(cx, |this, cx| this.pick(ix, cx)).ok();
                    }),
                    ..Default::default()
                }
            })
            .collect();
        menu::popover_highlighted(items, highlighted, &self.scroll, move |_, cx| {
            picker.update(cx, |this, cx| this.close(cx)).ok();
        })
    }
}

impl Render for Picker {
    fn render(&mut self, window: &mut Window, cx: &mut Context<Self>) -> impl IntoElement {
        let focused = !self.disabled && self.focus_handle.is_focused(window);
        let label = self
            .selected_index()
            .map_or_else(|| self.value.clone(), |ix| self.options[ix].0.clone());
        let button = div()
            .id("picker")
            .flex()
            .flex_row()
            .items_center()
            .gap(px(6.0))
            .h(CONTROL_H)
            .px(px(8.0))
            .rounded(px(6.0))
            .border_1()
            .border_color(if focused { ring() } else { theme::border() })
            .bg(theme::raise())
            .text_size(CONTROL_TEXT)
            .text_color(theme::text())
            .child(div().min_w_0().truncate().child(label))
            .child(
                svg()
                    .path(Icon::ChevronDown.path())
                    .flex_none()
                    .size(px(10.0))
                    .text_color(theme::muted()),
            );
        let button = if self.disabled {
            button.opacity(DISABLED_OPACITY)
        } else {
            button
                .track_focus(&self.focus_handle)
                .cursor_pointer()
                .when(!focused, |button| {
                    button.hover(|style| style.border_color(theme::primary_line()))
                })
                // While the list is open, a press here only closes it: otherwise the list's
                // "press outside" would close it and this click would open it again.
                .capture_any_mouse_down(cx.listener(|this, _: &MouseDownEvent, _, cx| {
                    if this.is_open() {
                        this.close(cx);
                        cx.stop_propagation();
                    }
                }))
                .on_click(cx.listener(|this, event: &ClickEvent, _, cx| {
                    if is_mouse(event) {
                        this.open_list(cx);
                    }
                }))
                .on_key_down(cx.listener(Self::on_key_down))
        };
        let list = self.open.map(|highlighted| {
            div()
                .absolute()
                .top_full()
                .left_0()
                .child(self.list(highlighted, cx))
        });
        div().relative().flex_none().child(button).children(list)
    }
}
