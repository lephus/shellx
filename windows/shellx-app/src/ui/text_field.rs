//! Single-line text field.
//!
//! Adapted from GPUI 0.2.2 `examples/input.rs` (Copyright Zed Industries,
//! Apache License 2.0): the `EntityInputHandler` implementation, the
//! shaped-line element that registers the input handler at paint time, and
//! mouse selection. ShellX changes: the editing rules live in
//! `shellx_model::text_edit` (tested on the Mac); keys come from
//! `on_key_down` instead of app-wide key bindings; a masked (password) mode;
//! horizontal scrolling; the §7.4 palette; Enter / Esc / Tab events; the IME
//! candidate anchor below the line (GPUI on Windows anchors IMM32 at
//! `y + h/2` of `bounds_for_range`, see `selection::windows_ime_anchor`).
//!
//! Text and IME composition arrive through the same input handler as in the
//! terminal panes: WM_CHAR and IMM32 composition call
//! `replace_text_in_range` / `replace_and_mark_text_in_range`, and Windows
//! sends no key-down to the view while a composition is open.

use std::ops::Range;

use gpui::{
    App, Bounds, ClipboardItem, ContentMask, Context, CursorStyle, ElementId, ElementInputHandler,
    Entity, EntityInputHandler, EventEmitter, FocusHandle, Focusable, GlobalElementId,
    InspectorElementId, KeyDownEvent, LayoutId, MouseButton, MouseDownEvent, MouseMoveEvent,
    MouseUpEvent, PaintQuad, Pixels, Point, ShapedLine, SharedString, Style, TextRun,
    UTF16Selection, UnderlineStyle, Window, div, fill, point, prelude::*, px, relative, size,
};
use shellx_model::palette;
use shellx_model::text_edit::TextEdit;

use super::theme;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum TextFieldEvent {
    /// Enter.
    Submit,
    /// Esc.
    Cancel,
    /// Tab.
    Next,
    /// Shift+Tab.
    Prev,
}

pub struct TextField {
    focus_handle: FocusHandle,
    edit: TextEdit,
    placeholder: SharedString,
    disabled: bool,
    last_layout: Option<ShapedLine>,
    last_bounds: Option<Bounds<Pixels>>,
    /// Horizontal scroll of the shaped line (keeps the cursor visible).
    scroll_x: Pixels,
    is_selecting: bool,
}

impl TextField {
    pub fn new(masked: bool, placeholder: impl Into<SharedString>, cx: &mut Context<Self>) -> Self {
        TextField {
            focus_handle: cx.focus_handle(),
            edit: TextEdit::new(masked),
            placeholder: placeholder.into(),
            disabled: false,
            last_layout: None,
            last_bounds: None,
            scroll_x: px(0.0),
            is_selecting: false,
        }
    }

    pub fn text(&self) -> &str {
        self.edit.text()
    }

    pub fn clear(&mut self, cx: &mut Context<Self>) {
        self.edit.clear();
        self.scroll_x = px(0.0);
        cx.notify();
    }

    /// A disabled field keeps its text and ignores edits (while signing in).
    pub fn set_disabled(&mut self, disabled: bool, cx: &mut Context<Self>) {
        if self.disabled != disabled {
            self.disabled = disabled;
            cx.notify();
        }
    }

    fn on_key_down(&mut self, event: &KeyDownEvent, _: &mut Window, cx: &mut Context<Self>) {
        let keystroke = &event.keystroke;
        let mods = keystroke.modifiers;
        // Alt / Win chords are app shortcuts; Ctrl+Alt is AltGr text (WM_CHAR).
        if mods.alt || mods.platform {
            return;
        }
        let (ctrl, shift) = (mods.control, mods.shift);
        let key = keystroke.key.as_str();
        let event = match (key, ctrl, shift) {
            ("enter", false, _) => Some(TextFieldEvent::Submit),
            ("escape", _, _) => Some(TextFieldEvent::Cancel),
            ("tab", false, false) => Some(TextFieldEvent::Next),
            ("tab", false, true) => Some(TextFieldEvent::Prev),
            _ => None,
        };
        if let Some(event) = event {
            cx.emit(event);
            cx.stop_propagation();
            return;
        }
        if self.disabled {
            return;
        }
        let edit = &mut self.edit;
        let handled = match (key, ctrl, shift) {
            ("backspace", false, _) => {
                edit.backspace();
                true
            }
            ("delete", false, false) => {
                edit.delete();
                true
            }
            ("left", false, false) => {
                edit.left();
                true
            }
            ("left", false, true) => {
                edit.select_left();
                true
            }
            ("right", false, false) => {
                edit.right();
                true
            }
            ("right", false, true) => {
                edit.select_right();
                true
            }
            ("home", false, false) => {
                edit.home();
                true
            }
            ("home", false, true) => {
                edit.select_to(0);
                true
            }
            ("end", false, false) => {
                edit.end();
                true
            }
            ("end", false, true) => {
                edit.select_to(edit.text().len());
                true
            }
            ("a", true, false) => {
                edit.select_all();
                true
            }
            // Ctrl+Shift+C/V too, so the terminal shortcuts never reach a pane
            // while a field has the keyboard.
            ("c", true, _) | ("insert", true, false) => {
                // Nothing leaves a masked field.
                if let Some(text) = edit.copy_text() {
                    cx.write_to_clipboard(ClipboardItem::new_string(text));
                }
                true
            }
            ("x", true, false) | ("delete", false, true) => {
                if let Some(text) = edit.cut() {
                    cx.write_to_clipboard(ClipboardItem::new_string(text));
                }
                true
            }
            ("v", true, _) | ("insert", false, true) => {
                if let Some(text) = cx.read_from_clipboard().and_then(|item| item.text()) {
                    edit.insert(&text);
                }
                true
            }
            _ => false,
        };
        if handled {
            cx.stop_propagation();
            cx.notify();
        }
    }

    fn on_mouse_down(
        &mut self,
        event: &MouseDownEvent,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) {
        window.focus(&self.focus_handle);
        self.is_selecting = true;
        let offset = self.index_for_mouse_position(event.position);
        if event.modifiers.shift {
            self.edit.select_to(offset);
        } else {
            self.edit.move_to(offset);
        }
        cx.notify();
    }

    fn on_mouse_up(&mut self, _: &MouseUpEvent, _: &mut Window, _: &mut Context<Self>) {
        self.is_selecting = false;
    }

    fn on_mouse_move(&mut self, event: &MouseMoveEvent, _: &mut Window, cx: &mut Context<Self>) {
        if self.is_selecting {
            let offset = self.index_for_mouse_position(event.position);
            self.edit.select_to(offset);
            cx.notify();
        }
    }

    /// Content offset under a window point.
    fn index_for_mouse_position(&self, position: Point<Pixels>) -> usize {
        if self.edit.is_empty() {
            return 0;
        }
        let (Some(bounds), Some(line)) = (self.last_bounds.as_ref(), self.last_layout.as_ref())
        else {
            return 0;
        };
        if position.y < bounds.top() {
            return 0;
        }
        if position.y > bounds.bottom() {
            return self.edit.text().len();
        }
        let display = line.closest_index_for_x(position.x - bounds.left() + self.scroll_x);
        self.edit.content_offset(display)
    }

    /// Window x of a content offset in the last painted line.
    fn x_for_offset(&self, offset: usize) -> Option<Pixels> {
        let line = self.last_layout.as_ref()?;
        let bounds = self.last_bounds?;
        let display = if self.edit.is_empty() {
            0
        } else {
            self.edit.display_offset(offset)
        };
        Some(bounds.left() + line.x_for_index(display) - self.scroll_x)
    }
}

impl EventEmitter<TextFieldEvent> for TextField {}

impl Focusable for TextField {
    fn focus_handle(&self, _: &App) -> FocusHandle {
        self.focus_handle.clone()
    }
}

impl EntityInputHandler for TextField {
    fn text_for_range(
        &mut self,
        range_utf16: Range<usize>,
        actual_range: &mut Option<Range<usize>>,
        _window: &mut Window,
        _cx: &mut Context<Self>,
    ) -> Option<String> {
        let (text, actual) = self.edit.text_for_utf16_range(&range_utf16)?;
        actual_range.replace(actual);
        Some(text)
    }

    fn selected_text_range(
        &mut self,
        _ignore_disabled_input: bool,
        _window: &mut Window,
        _cx: &mut Context<Self>,
    ) -> Option<UTF16Selection> {
        Some(UTF16Selection {
            range: self.edit.range_to_utf16(&self.edit.selected_range()),
            reversed: self.edit.reversed(),
        })
    }

    fn marked_text_range(
        &self,
        _window: &mut Window,
        _cx: &mut Context<Self>,
    ) -> Option<Range<usize>> {
        self.edit
            .marked_range()
            .map(|range| self.edit.range_to_utf16(&range))
    }

    fn unmark_text(&mut self, _window: &mut Window, _cx: &mut Context<Self>) {
        self.edit.unmark();
    }

    fn replace_text_in_range(
        &mut self,
        range_utf16: Option<Range<usize>>,
        new_text: &str,
        _window: &mut Window,
        cx: &mut Context<Self>,
    ) {
        if self.disabled {
            return;
        }
        self.edit.replace_text_in_range(range_utf16, new_text);
        cx.notify();
    }

    fn replace_and_mark_text_in_range(
        &mut self,
        range_utf16: Option<Range<usize>>,
        new_text: &str,
        new_selected_range_utf16: Option<Range<usize>>,
        _window: &mut Window,
        cx: &mut Context<Self>,
    ) {
        if self.disabled {
            return;
        }
        self.edit
            .replace_and_mark_text_in_range(range_utf16, new_text, new_selected_range_utf16);
        cx.notify();
    }

    fn bounds_for_range(
        &mut self,
        range_utf16: Range<usize>,
        bounds: Bounds<Pixels>,
        _window: &mut Window,
        _cx: &mut Context<Self>,
    ) -> Option<Bounds<Pixels>> {
        let range = self.edit.range_from_utf16(&range_utf16);
        let start = self.x_for_offset(range.start)?;
        let end = self.x_for_offset(range.end)?.max(start + px(1.0));
        let height = bounds.size.height;
        // GPUI on Windows anchors the IME windows at (x, y + h/2): shift the
        // rect down half a line so the anchor is the bottom of the text line.
        Some(Bounds::new(
            point(start, bounds.top() + height * 0.5),
            size(end - start, height),
        ))
    }

    fn character_index_for_point(
        &mut self,
        point: Point<Pixels>,
        _window: &mut Window,
        _cx: &mut Context<Self>,
    ) -> Option<usize> {
        let bounds = self.last_bounds?;
        let line = self.last_layout.as_ref()?;
        if !bounds.contains(&point) || self.edit.is_empty() {
            return None;
        }
        let display = line.index_for_x(point.x - bounds.left() + self.scroll_x)?;
        let offset = self.edit.content_offset(display);
        Some(self.edit.offset_to_utf16(offset))
    }
}

struct TextElement {
    field: Entity<TextField>,
}

struct PrepaintState {
    line: Option<ShapedLine>,
    cursor: Option<PaintQuad>,
    selection: Option<PaintQuad>,
    scroll_x: Pixels,
}

impl IntoElement for TextElement {
    type Element = Self;

    fn into_element(self) -> Self::Element {
        self
    }
}

impl Element for TextElement {
    type RequestLayoutState = ();
    type PrepaintState = PrepaintState;

    fn id(&self) -> Option<ElementId> {
        None
    }

    fn source_location(&self) -> Option<&'static core::panic::Location<'static>> {
        None
    }

    fn request_layout(
        &mut self,
        _id: Option<&GlobalElementId>,
        _inspector_id: Option<&InspectorElementId>,
        window: &mut Window,
        cx: &mut App,
    ) -> (LayoutId, Self::RequestLayoutState) {
        let mut style = Style::default();
        style.size.width = relative(1.).into();
        style.size.height = window.line_height().into();
        (window.request_layout(style, [], cx), ())
    }

    fn prepaint(
        &mut self,
        _id: Option<&GlobalElementId>,
        _inspector_id: Option<&InspectorElementId>,
        bounds: Bounds<Pixels>,
        _request_layout: &mut Self::RequestLayoutState,
        window: &mut Window,
        cx: &mut App,
    ) -> Self::PrepaintState {
        let field = self.field.read(cx);
        let edit = &field.edit;
        let style = window.text_style();
        let empty = edit.is_empty();

        let (display_text, text_color): (SharedString, _) = if empty {
            (field.placeholder.clone(), theme::muted())
        } else {
            (edit.display_text().into(), theme::text_hi())
        };
        let run = TextRun {
            len: display_text.len(),
            font: style.font(),
            color: text_color,
            background_color: None,
            underline: None,
            strikethrough: None,
        };
        // The IME preedit is underlined (as in the terminal panes).
        let runs = match edit.marked_range().filter(|_| !empty) {
            Some(marked) => {
                let marked = edit.display_range(&marked);
                vec![
                    TextRun {
                        len: marked.start,
                        ..run.clone()
                    },
                    TextRun {
                        len: marked.end - marked.start,
                        underline: Some(UnderlineStyle {
                            color: Some(run.color),
                            thickness: px(1.0),
                            wavy: false,
                        }),
                        ..run.clone()
                    },
                    TextRun {
                        len: display_text.len() - marked.end,
                        ..run
                    },
                ]
                .into_iter()
                .filter(|run| run.len > 0)
                .collect()
            }
            None => vec![run],
        };

        let font_size = style.font_size.to_pixels(window.rem_size());
        let line = window
            .text_system()
            .shape_line(display_text, font_size, &runs, None);

        let selected = edit.selected_range();
        let cursor_x = if empty {
            px(0.0)
        } else {
            line.x_for_index(edit.display_offset(edit.cursor()))
        };
        // Keep the cursor inside the field.
        let width = bounds.size.width;
        let mut scroll_x = field.scroll_x;
        if empty || line.width <= width {
            scroll_x = px(0.0);
        } else {
            if cursor_x - scroll_x > width - px(2.0) {
                scroll_x = cursor_x - width + px(2.0);
            }
            if cursor_x < scroll_x {
                scroll_x = cursor_x;
            }
        }

        let origin_x = bounds.left() - scroll_x;
        let (selection, cursor) = if selected.is_empty() || empty {
            (
                None,
                Some(fill(
                    Bounds::new(
                        point(origin_x + cursor_x, bounds.top()),
                        size(px(1.5), bounds.bottom() - bounds.top()),
                    ),
                    theme::hsla(palette::PRIMARY),
                )),
            )
        } else {
            let range = edit.display_range(&selected);
            (
                Some(fill(
                    Bounds::from_corners(
                        point(origin_x + line.x_for_index(range.start), bounds.top()),
                        point(origin_x + line.x_for_index(range.end), bounds.bottom()),
                    ),
                    theme::hsla(palette::PRIMARY.with_alpha(0.3)),
                )),
                None,
            )
        };
        PrepaintState {
            line: Some(line),
            cursor,
            selection,
            scroll_x,
        }
    }

    fn paint(
        &mut self,
        _id: Option<&GlobalElementId>,
        _inspector_id: Option<&InspectorElementId>,
        bounds: Bounds<Pixels>,
        _request_layout: &mut Self::RequestLayoutState,
        prepaint: &mut Self::PrepaintState,
        window: &mut Window,
        cx: &mut App,
    ) {
        let focus_handle = self.field.read(cx).focus_handle.clone();
        window.handle_input(
            &focus_handle,
            ElementInputHandler::new(bounds, self.field.clone()),
            cx,
        );
        let line = prepaint.line.take().unwrap_or_default();
        let scroll_x = prepaint.scroll_x;
        let focused = focus_handle.is_focused(window);
        let line_height = window.line_height();
        window.with_content_mask(Some(ContentMask { bounds }), |window| {
            if let Some(selection) = prepaint.selection.take() {
                window.paint_quad(selection);
            }
            line.paint(
                point(bounds.left() - scroll_x, bounds.top()),
                line_height,
                window,
                cx,
            )
            .ok();
            if focused && let Some(cursor) = prepaint.cursor.take() {
                window.paint_quad(cursor);
            }
        });
        self.field.update(cx, |field, _cx| {
            field.last_layout = Some(line);
            field.last_bounds = Some(bounds);
            field.scroll_x = scroll_x;
        });
    }
}

impl Render for TextField {
    fn render(&mut self, window: &mut Window, cx: &mut Context<Self>) -> impl IntoElement {
        let focused = self.focus_handle.is_focused(window);
        let border = if focused {
            theme::hsla(palette::PRIMARY_LINE)
        } else {
            theme::border()
        };
        div()
            .flex()
            .w_full()
            .key_context("TextField")
            .track_focus(&self.focus_handle)
            .cursor(CursorStyle::IBeam)
            .on_key_down(cx.listener(Self::on_key_down))
            .on_mouse_down(MouseButton::Left, cx.listener(Self::on_mouse_down))
            .on_mouse_up(MouseButton::Left, cx.listener(Self::on_mouse_up))
            .on_mouse_up_out(MouseButton::Left, cx.listener(Self::on_mouse_up))
            .on_mouse_move(cx.listener(Self::on_mouse_move))
            .px(px(8.0))
            .py(px(5.0))
            .bg(theme::bg())
            .border_1()
            .border_color(border)
            .rounded(px(6.0))
            .text_size(theme::UI_SIZE)
            .line_height(px(18.0))
            .when(self.disabled, |el| el.opacity(0.6))
            .child(TextElement { field: cx.entity() })
    }
}
