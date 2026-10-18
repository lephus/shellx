//! The terminal pane: one libghostty-vt grid, cursor, inline IME preedit
//! (moved from the spike's app.rs; colors now come from ui/theme.rs).
//! Each split pane is one `TermView` with its own shell. Keys go through
//! `shellx_model::keys::map_key`; app commands and the shell's exit are
//! emitted as `TermEvent`s for RootView, which owns the tabs model.
//!
//! Input rules (Windows Terminal style):
//! - IME: while a preedit exists keys belong to the IME; the preedit is
//!   drawn inline at the cursor and only a commit (`replace_text_in_range`)
//!   reaches the shell, as ONE `TermCore::send_text` of the composed text.
//!   `bounds_for_range` reports the cursor cell (plus the preedit before the
//!   range) of this pane's grid in window coordinates, so the candidate
//!   window opens under the cursor of the focused pane.
//! - Selection: left-drag selects a linear stream, double-click a word,
//!   triple-click a line, Shift+click extends. Selections live in viewport
//!   rows: they move with the content when output or the wheel scrolls the
//!   viewport and are dropped once a selected row leaves it, on resize, and
//!   on any typed input or paste. (When the scrollback is full, output
//!   scrolls without moving the offset; a newline arriving at the live
//!   bottom then clears the selection.) No mouse reporting to apps in
//!   the MVP, so a plain drag selects even when an app enabled mouse
//!   tracking (Shift+drag does too, as in Windows Terminal).
//! - Copy (Ctrl+Shift+C, or Ctrl+C while a selection exists) puts the
//!   cells' text (libghostty, wide-char aware) on the clipboard with CRLF
//!   row joins and clears the selection; Ctrl+C without a selection is the
//!   shell's SIGINT. Paste (Ctrl+Shift+V, Shift+Insert) goes through
//!   `TermCore::paste`: newlines normalized, embedded bracketed-paste
//!   markers stripped, bracketed only while the shell enabled mode 2004.
//! - DPI: cell metrics come from the window's current scale factor on every
//!   prepaint (and a scale change redraws), the grid origin is snapped to
//!   whole device pixels, and the PTY is resized when cols/rows change.

use std::ops::Range;
use std::time::Duration;

use ghostty_vt::{CellWidth, CursorShape, Rgb};
use gpui::{
    App, BorderStyle, Bounds, ClipboardItem, Context, DispatchPhase, Element, ElementId,
    ElementInputHandler, Entity, EntityInputHandler, EventEmitter, FocusHandle, Focusable, Font,
    FontFallbacks, GlobalElementId, Hitbox, HitboxBehavior, Hsla, InspectorElementId, IntoElement,
    KeyDownEvent, LayoutId, MouseButton, MouseDownEvent, MouseMoveEvent, MouseUpEvent, PaintQuad,
    Pixels, Point, Render, ScrollWheelEvent, ShapedLine, SharedString, StrikethroughStyle, Style,
    Subscription, TextRun, UTF16Selection, UnderlineStyle, Window, div, fill, font, outline, point,
    prelude::*, px, relative, size,
};

use std::sync::Arc;

use shellx_model::keys::{AppCommand, KeyAction, KeyCtx, KeyIn, map_key};
use shellx_model::layout::Rect;
use shellx_model::palette::{TERM_BG, TERM_CURSOR, TERM_FG, TERM_SELECTION};
use shellx_model::selection::{
    Cell, Follow, Selection, cell_at, drag_selection, follow_viewport, ime_cell,
    ime_index_for_point, ime_rect, line_span, selected_text, to_crlf, windows_ime_anchor, word_at,
};

use super::theme;
use crate::fonts;
use crate::local_pty::{LocalPty, spawn_reader};
use crate::term_core::{PtyLink, TermCore, rgb};
use crate::workspace::spawn_local_pane;

/// What a pane tells RootView.
pub(super) enum TermEvent {
    /// A window command typed in this pane (new tab, split, close, ...).
    Command(AppCommand),
    /// The shell ended (exit, crash, or a failed write): close the pane.
    Exited,
}

const FONT_SIZE: f32 = 14.0;
const LINE_HEIGHT: f32 = 1.3;
const PADDING: f32 = 6.0;
pub(super) const BASE_TITLE: &str = "ShellX";

fn hsla(c: Rgb) -> Hsla {
    gpui::rgb((u32::from(c.r) << 16) | (u32::from(c.g) << 8) | u32::from(c.b)).into()
}

fn utf16_len(s: &str) -> usize {
    s.chars().map(char::len_utf16).sum()
}

fn utf16_to_utf8(s: &str, utf16: usize) -> usize {
    let mut units = 0;
    for (i, ch) in s.char_indices() {
        if units >= utf16 {
            return i;
        }
        units += ch.len_utf16();
    }
    s.len()
}

fn utf8_to_utf16(s: &str, utf8: usize) -> usize {
    utf16_len(&s[..utf8.min(s.len())])
}

/// The embedded JetBrains Mono, with system fallbacks for glyphs it lacks.
fn terminal_font() -> Font {
    let mut f = font(fonts::TERMINAL_FAMILY);
    f.fallbacks = Some(FontFallbacks::from_fonts(vec![
        "Cascadia Mono".into(),
        "Consolas".into(),
        "Segoe UI".into(),
        "Segoe UI Emoji".into(),
        "Segoe UI Symbol".into(),
    ]));
    f
}

/// The grid as last laid out (prepaint): mouse cells and IME geometry.
#[derive(Clone, Copy)]
struct Grid {
    /// Window position of cell (0, 0), snapped to whole device pixels.
    origin: Point<Pixels>,
    cell_w: Pixels,
    cell_h: Pixels,
    cols: u16,
    rows: u16,
    /// Where the IME preedit starts: the LIVE cursor cell (also while the
    /// cursor is hidden or the view is scrolled back; composing scrolls to
    /// the bottom), see `selection::ime_cell`.
    ime_cell: Option<Cell>,
}

impl Grid {
    fn origin_f32(&self) -> (f32, f32) {
        (f32::from(self.origin.x), f32::from(self.origin.y))
    }
}

#[derive(Clone, Copy, PartialEq)]
enum Granularity {
    Cell,
    Word,
    Line,
}

/// Left button held after a mouse down in the grid.
#[derive(Clone, Copy)]
struct Drag {
    /// What the click itself selected (one cell, the word or the line).
    origin: (Cell, Cell),
    granularity: Granularity,
}

pub(super) struct TermView {
    focus_handle: FocusHandle,
    font: Font,
    session: Option<TermCore>,
    link: Option<Arc<LocalPty>>,
    error: Option<String>,
    /// IME composition text (preedit), shown inline at the cursor and never
    /// sent to the PTY until committed.
    marked: Option<String>,
    marked_selection: Option<Range<usize>>,
    /// A visible selection (never an empty single-cell click).
    selection: Option<Selection>,
    drag: Option<Drag>,
    grid: Option<Grid>,
    /// One char per cell of the last frame (wide-char tails are `\0`), for
    /// double-click words and the copy fallback.
    cell_lines: Vec<String>,
    /// Scale factor the metrics were last computed at.
    scale: f32,
    _window_bounds: Subscription,
    cell_width: Pixels,
    line_height: Pixels,
    title: String,
}

impl TermView {
    pub(super) fn new(window: &mut Window, cx: &mut Context<Self>) -> Self {
        // Per-monitor DPI: moving the window to a display with another scale
        // (WM_DPICHANGED) changes the bounds; re-measure the grid then.
        let window_bounds = cx.observe_window_bounds(window, |view, window, cx| {
            if window.scale_factor() != view.scale {
                view.scale = window.scale_factor();
                cx.notify();
            }
        });
        let mut view = TermView {
            focus_handle: cx.focus_handle(),
            font: terminal_font(),
            session: None,
            link: None,
            error: None,
            marked: None,
            marked_selection: None,
            selection: None,
            drag: None,
            grid: None,
            cell_lines: Vec::new(),
            scale: window.scale_factor(),
            _window_bounds: window_bounds,
            cell_width: px(8.0),
            line_height: px(18.0),
            title: BASE_TITLE.to_string(),
        };
        match spawn_local_pane(80, 24, &[]) {
            Ok(started) => {
                let (link, core, reader) = (started.link, started.core, started.reader);
                view.session = Some(core);
                view.link = Some(link);
                let (tx, rx) = async_channel::unbounded::<Vec<u8>>();
                spawn_reader(reader, move |bytes| tx.send_blocking(bytes).is_ok());
                cx.spawn(async move |this, cx| {
                    while let Ok(mut batch) = rx.recv().await {
                        while let Ok(more) = rx.try_recv() {
                            batch.extend_from_slice(&more);
                        }
                        let fed = this.update(cx, |view, cx| {
                            let newline = batch.contains(&b'\n');
                            view.follow_viewport(newline, |session| session.feed(&batch));
                            cx.notify();
                        });
                        if fed.is_err() {
                            return;
                        }
                    }
                })
                .detach();
                // ConPTY keeps its output pipe open after the shell exits, so
                // poll the child (and the sticky write-failure flag) and tell
                // RootView, which closes this pane through the tabs model.
                cx.spawn(async move |this, cx| {
                    loop {
                        cx.background_executor()
                            .timer(Duration::from_millis(500))
                            .await;
                        let exited = this.update(cx, |view, cx| {
                            let exited = view.link.as_ref().is_some_and(|l| l.is_closed());
                            if exited {
                                cx.emit(TermEvent::Exited);
                            }
                            exited
                        });
                        // Err: the pane was dropped (closed by RootView).
                        if exited.unwrap_or(true) {
                            return;
                        }
                    }
                })
                .detach();
            }
            Err(error) => view.error = Some(format!("{error:#}")),
        }
        view
    }

    /// True while the IME holds a composition (preedit) for this pane.
    pub(super) fn composing(&self) -> bool {
        self.marked.is_some()
    }

    /// The terminal's own title (OSC 0/2), if the shell set one.
    pub(super) fn terminal_title(&self) -> Option<String> {
        self.session.as_ref().and_then(TermCore::title)
    }

    /// A visible selection exists (Ctrl+C then copies instead of SIGINT).
    pub(super) fn has_selection(&self) -> bool {
        self.selection.is_some()
    }

    /// Copy / Paste, from this pane's keys or RootView's fallback.
    pub(super) fn clipboard_command(&mut self, command: AppCommand, cx: &mut Context<Self>) {
        match command {
            AppCommand::Copy => self.copy_selection(cx),
            AppCommand::Paste => self.paste_clipboard(cx),
            _ => {}
        }
    }

    /// The selected cells' text to the clipboard (CRLF row joins), then the
    /// selection is cleared. No selection: nothing happens.
    fn copy_selection(&mut self, cx: &mut Context<Self>) {
        let (Some(sel), Some(grid)) = (self.selection, self.grid) else {
            return;
        };
        let (start, end) = sel.ordered();
        let last_col = grid.cols.saturating_sub(1);
        let text = self
            .session
            .as_mut()
            .and_then(|s| {
                s.selection_text((start.col, start.row), (end.col.min(last_col), end.row))
            })
            .map(|t| to_crlf(&t))
            .unwrap_or_else(|| selected_text(&sel, &self.cell_lines, grid.cols).replace('\0', ""));
        if !text.is_empty() {
            cx.write_to_clipboard(ClipboardItem::new_string(text));
        }
        self.clear_selection(cx);
    }

    /// Clipboard text as data: `TermCore::paste` normalizes newlines, strips
    /// embedded `ESC[200~` / `ESC[201~` and brackets only under mode 2004.
    fn paste_clipboard(&mut self, cx: &mut Context<Self>) {
        let Some(text) = cx.read_from_clipboard().and_then(|item| item.text()) else {
            return;
        };
        self.clear_selection(cx);
        if let Some(session) = self.session.as_mut() {
            session.paste(&text);
        }
        cx.notify();
    }

    fn clear_selection(&mut self, cx: &mut Context<Self>) {
        self.drag = None;
        if self.selection.take().is_some() {
            cx.notify();
        }
    }

    /// Runs `f` (feed output, scroll), then moves the selection with the
    /// viewport content (`selection::follow_viewport`): shifted by the
    /// offset change, dropped once a selected row left the viewport, and
    /// cleared when output scrolled a full scrollback without moving the
    /// offset. `output_newline`: what `f` fed contained a newline.
    fn follow_viewport(&mut self, output_newline: bool, f: impl FnOnce(&mut TermCore)) {
        let Some(session) = self.session.as_mut() else {
            return;
        };
        let tracking = self.selection.is_some() || self.drag.is_some();
        let before = if tracking { session.viewport() } else { None };
        f(session);
        let (Some(before), Some(after), Some(grid)) = (before, session.viewport(), self.grid)
        else {
            return;
        };
        let delta = match follow_viewport(before, after, output_newline) {
            Follow::Keep => return,
            Follow::Clear => {
                self.selection = None;
                self.drag = None;
                return;
            }
            Follow::Shift(delta) => delta,
        };
        let shift = |c: Cell| {
            Selection::new(c)
                .shifted(delta, grid.rows)
                .map(|s| s.anchor())
        };
        self.selection = self.selection.and_then(|s| s.shifted(delta, grid.rows));
        self.drag = self.drag.and_then(|d| {
            Some(Drag {
                origin: (shift(d.origin.0)?, shift(d.origin.1)?),
                ..d
            })
        });
    }

    fn cell_for(&self, position: Point<Pixels>) -> Option<Cell> {
        let g = self.grid?;
        Some(cell_at(
            f32::from(position.x - g.origin.x),
            f32::from(position.y - g.origin.y),
            f32::from(g.cell_w),
            f32::from(g.cell_h),
            g.cols,
            g.rows,
        ))
    }

    /// The span one click selects at `cell`.
    fn span_at(&self, cell: Cell, granularity: Granularity) -> (Cell, Cell) {
        let cols = self.grid.map_or(1, |g| g.cols);
        match granularity {
            Granularity::Cell => (cell, cell),
            Granularity::Word => {
                let line = self
                    .cell_lines
                    .get(usize::from(cell.row))
                    .map_or("", String::as_str);
                let (start, end) = word_at(line, cell.col);
                let last = end.saturating_sub(1).max(start).min(cols.saturating_sub(1));
                (
                    Cell {
                        row: cell.row,
                        col: start,
                    },
                    Cell {
                        row: cell.row,
                        col: last,
                    },
                )
            }
            Granularity::Line => line_span(cell.row, cols),
        }
    }

    /// A single click shows nothing until the drag reaches another cell.
    fn set_drag_selection(&mut self, sel: Selection, granularity: Granularity) {
        self.selection = (granularity != Granularity::Cell || !sel.is_empty()).then_some(sel);
    }

    fn select_mouse_down(&mut self, event: &MouseDownEvent, cx: &mut Context<Self>) {
        let Some(cell) = self.cell_for(event.position) else {
            return;
        };
        if event.modifiers.shift
            && let Some(sel) = self.selection
        {
            let anchor = (sel.anchor(), sel.anchor());
            self.drag = Some(Drag {
                origin: anchor,
                granularity: Granularity::Cell,
            });
            self.set_drag_selection(drag_selection(anchor, (cell, cell)), Granularity::Cell);
            cx.notify();
            return;
        }
        let granularity = match event.click_count {
            0 | 1 => Granularity::Cell,
            2 => Granularity::Word,
            _ => Granularity::Line,
        };
        let origin = self.span_at(cell, granularity);
        self.drag = Some(Drag {
            origin,
            granularity,
        });
        self.set_drag_selection(drag_selection(origin, origin), granularity);
        cx.notify();
    }

    fn select_mouse_move(&mut self, event: &MouseMoveEvent, cx: &mut Context<Self>) {
        let Some(drag) = self.drag else {
            return;
        };
        if event.pressed_button != Some(MouseButton::Left) {
            self.drag = None; // the button came up where we did not see it
            return;
        }
        let Some(cell) = self.cell_for(event.position) else {
            return;
        };
        let over = self.span_at(cell, drag.granularity);
        let before = self.selection;
        self.set_drag_selection(drag_selection(drag.origin, over), drag.granularity);
        if self.selection != before {
            cx.notify();
        }
    }

    fn select_mouse_up(&mut self) {
        self.drag = None;
    }

    fn on_key_down(&mut self, event: &KeyDownEvent, _: &mut Window, cx: &mut Context<Self>) {
        let keystroke = &event.keystroke;
        let mods = keystroke.modifiers;
        let key = KeyIn {
            key: keystroke.key.as_str(),
            ctrl: mods.control,
            alt: mods.alt,
            shift: mods.shift,
            win: mods.platform,
        };
        let ctx = KeyCtx {
            has_selection: self.has_selection(),
            // The IME owns keys while composing (map_key ignores them).
            composing: self.composing(),
        };
        match map_key(&key, &ctx) {
            KeyAction::App(command @ (AppCommand::Copy | AppCommand::Paste)) => {
                self.clipboard_command(command, cx);
                cx.stop_propagation();
            }
            KeyAction::App(command) => {
                cx.emit(TermEvent::Command(command));
                cx.stop_propagation();
            }
            KeyAction::Chord(chord) => {
                if let Some(session) = self.session.as_mut()
                    && session.send_chord(&chord)
                {
                    // Typed input ends the selection (Windows Terminal).
                    self.clear_selection(cx);
                    cx.stop_propagation();
                }
            }
            // Plain text: Windows turns the key into WM_CHAR / IME messages,
            // which arrive through the EntityInputHandler below.
            KeyAction::Text | KeyAction::Ignore => {}
        }
    }

    fn on_scroll(&mut self, event: &ScrollWheelEvent, _: &mut Window, cx: &mut Context<Self>) {
        let delta = event.delta.pixel_delta(self.line_height);
        let lines = (f32::from(delta.y) / f32::from(self.line_height)).round() as isize;
        if lines != 0 && self.session.is_some() {
            self.follow_viewport(false, |session| session.scroll_lines(-lines));
            cx.notify();
        }
    }
}

impl EventEmitter<TermEvent> for TermView {}

impl Focusable for TermView {
    fn focus_handle(&self, _: &App) -> FocusHandle {
        self.focus_handle.clone()
    }
}

impl Render for TermView {
    fn render(&mut self, _window: &mut Window, cx: &mut Context<Self>) -> impl IntoElement {
        let root = div()
            .size_full()
            .bg(theme::hsla(TERM_BG))
            .text_color(theme::hsla(TERM_FG))
            .p(px(PADDING))
            .cursor_text()
            .track_focus(&self.focus_handle)
            .key_context("Terminal")
            .on_key_down(cx.listener(Self::on_key_down))
            .on_scroll_wheel(cx.listener(Self::on_scroll))
            .on_mouse_down(
                MouseButton::Left,
                cx.listener(|this, _: &MouseDownEvent, window, _| {
                    window.focus(&this.focus_handle);
                }),
            );
        match &self.error {
            Some(error) => root.child(format!("Could not start the shell: {error}")),
            None => root.child(TermElement { view: cx.entity() }),
        }
    }
}

impl EntityInputHandler for TermView {
    fn text_for_range(
        &mut self,
        range_utf16: Range<usize>,
        adjusted_range: &mut Option<Range<usize>>,
        _: &mut Window,
        _: &mut Context<Self>,
    ) -> Option<String> {
        let marked = self.marked.as_deref().unwrap_or("");
        let start = utf16_to_utf8(marked, range_utf16.start);
        let end = utf16_to_utf8(marked, range_utf16.end).max(start);
        adjusted_range.replace(utf8_to_utf16(marked, start)..utf8_to_utf16(marked, end));
        Some(marked[start..end].to_string())
    }

    fn selected_text_range(
        &mut self,
        _ignore_disabled_input: bool,
        _: &mut Window,
        _: &mut Context<Self>,
    ) -> Option<UTF16Selection> {
        let len = self.marked.as_deref().map_or(0, utf16_len);
        Some(UTF16Selection {
            range: self.marked_selection.clone().unwrap_or(len..len),
            reversed: false,
        })
    }

    fn marked_text_range(&self, _: &mut Window, _: &mut Context<Self>) -> Option<Range<usize>> {
        self.marked.as_deref().map(|m| 0..utf16_len(m))
    }

    fn unmark_text(&mut self, _: &mut Window, cx: &mut Context<Self>) {
        self.marked = None;
        self.marked_selection = None;
        cx.notify();
    }

    fn replace_text_in_range(
        &mut self,
        _range: Option<Range<usize>>,
        text: &str,
        _: &mut Window,
        cx: &mut Context<Self>,
    ) {
        // Commit: typed characters, IME results, Unikey/EVKey injected text.
        // ONE send_text of the whole committed string, never per keystroke.
        self.marked = None;
        self.marked_selection = None;
        let text: String = text
            .chars()
            .filter(|c| *c == '\t' || !c.is_control())
            .collect();
        if !text.is_empty() {
            self.clear_selection(cx);
        }
        if let Some(session) = self.session.as_mut() {
            session.send_text(&text);
        }
        cx.notify();
    }

    fn replace_and_mark_text_in_range(
        &mut self,
        _range: Option<Range<usize>>,
        new_text: &str,
        new_selected_range: Option<Range<usize>>,
        _: &mut Window,
        cx: &mut Context<Self>,
    ) {
        if new_text.is_empty() {
            self.marked = None;
            self.marked_selection = None;
        } else {
            // Composing is typing: drop the selection and show the live
            // screen, where the preedit is drawn (nothing is sent yet).
            self.clear_selection(cx);
            if let Some(session) = self.session.as_mut() {
                session.scroll_to_bottom();
            }
            self.marked = Some(new_text.to_string());
            self.marked_selection = new_selected_range;
        }
        cx.notify();
    }

    /// Window-space rect of `range_utf16` of the preedit, which starts at
    /// this pane's cursor cell. GPUI 0.2.2 (Windows) asks this only at
    /// WM_IME_STARTCOMPOSITION, for the caret, and anchors the candidate
    /// window at the rect's vertical middle; `windows_ime_anchor` moves that
    /// point to the bottom of the cursor row so the list opens under it.
    fn bounds_for_range(
        &mut self,
        range_utf16: Range<usize>,
        _element_bounds: Bounds<Pixels>,
        _: &mut Window,
        _: &mut Context<Self>,
    ) -> Option<Bounds<Pixels>> {
        let grid = self.grid?;
        let cursor = grid.ime_cell?;
        let rect = ime_rect(
            cursor,
            grid.origin_f32(),
            f32::from(grid.cell_w),
            f32::from(grid.cell_h),
            self.marked.as_deref().unwrap_or(""),
            range_utf16,
        );
        Some(to_bounds(windows_ime_anchor(rect)))
    }

    /// The preedit char under `point` (the inverse of `ime_rect`).
    fn character_index_for_point(
        &mut self,
        point: Point<Pixels>,
        _: &mut Window,
        _: &mut Context<Self>,
    ) -> Option<usize> {
        let grid = self.grid?;
        ime_index_for_point(
            f32::from(point.x),
            f32::from(point.y),
            grid.ime_cell?,
            grid.origin_f32(),
            f32::from(grid.cell_w),
            f32::from(grid.cell_h),
            self.marked.as_deref()?,
        )
    }
}

fn to_bounds(r: Rect) -> Bounds<Pixels> {
    Bounds::new(point(px(r.x), px(r.y)), size(px(r.w), px(r.h)))
}

struct TermElement {
    view: Entity<TermView>,
}

impl IntoElement for TermElement {
    type Element = Self;

    fn into_element(self) -> Self::Element {
        self
    }
}

struct TextPaint {
    origin: Point<Pixels>,
    line: ShapedLine,
}

#[derive(Default)]
struct Prepaint {
    backgrounds: Vec<PaintQuad>,
    selection: Vec<PaintQuad>,
    texts: Vec<TextPaint>,
    cursor: Option<PaintQuad>,
    preedit_bg: Option<PaintQuad>,
    preedit: Option<TextPaint>,
    line_height: Pixels,
    hitbox: Option<Hitbox>,
}

#[derive(Clone, PartialEq)]
struct RunStyle {
    fg: Hsla,
    bg: Option<Hsla>,
    bold: bool,
    italic: bool,
    underline: bool,
    strikethrough: bool,
}

struct RunAcc {
    col: usize,
    cols: usize,
    text: String,
    style: RunStyle,
    wide: bool,
}

fn cell_style(cell: &ghostty_vt::Cell, default_fg: Rgb, default_bg: Rgb) -> RunStyle {
    let mut fg = cell.resolved_fg.unwrap_or(default_fg);
    let mut bg = cell.resolved_bg;
    if cell.inverse {
        let new_bg = Some(fg);
        fg = bg.unwrap_or(default_bg);
        bg = new_bg;
    }
    let mut fg = hsla(fg);
    if cell.faint {
        fg.a = 0.6;
    }
    RunStyle {
        fg,
        bg: bg.filter(|b| *b != default_bg).map(hsla),
        bold: cell.bold,
        italic: cell.italic,
        underline: cell.underline || cell.underline_style.is_some(),
        strikethrough: cell.strikethrough,
    }
}

impl Element for TermElement {
    type RequestLayoutState = ();
    type PrepaintState = Prepaint;

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
        style.size.height = relative(1.).into();
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
        let hitbox = window.insert_hitbox(bounds, HitboxBehavior::Normal);
        let base_font = self.view.read(cx).font.clone();
        let font_size = px(FONT_SIZE);
        let text_system = cx.text_system().clone();
        let font_id = text_system.resolve_font(&base_font);
        let cell_w = text_system
            .advance(font_id, font_size, 'M')
            .map(|s| s.width)
            .unwrap_or(px(FONT_SIZE * 0.6));
        // Metrics come from the scale factor of THIS frame (per-monitor
        // DPI): whole device pixels per row, and the grid origin snapped to
        // a device pixel, so rows never blur at 125/150/200 %.
        let scale = window.scale_factor();
        let snap = |v: Pixels| px((f32::from(v) * scale).round() / scale);
        let line_h = px((FONT_SIZE * LINE_HEIGHT * scale).round() / scale);
        let grid_origin = point(snap(bounds.origin.x), snap(bounds.origin.y));
        let cols = (f32::from(bounds.size.width) / f32::from(cell_w))
            .floor()
            .max(2.0) as u16;
        let rows = (f32::from(bounds.size.height) / f32::from(line_h))
            .floor()
            .max(1.0) as u16;
        let cell_w_px = (f32::from(cell_w) * scale).round() as u32;
        let cell_h_px = (f32::from(line_h) * scale).round() as u32;

        let (frame, ime_cell, selection, marked, focused, title) =
            self.view.update(cx, |view, _| {
                view.cell_width = cell_w;
                view.line_height = line_h;
                view.scale = scale;
                let focused = view.focus_handle.is_focused(window);
                let Some(session) = view.session.as_mut() else {
                    return (None, None, None, None, focused, None);
                };
                let size_before = session.vt_cols_rows();
                let _ = session.resize(cols, rows, cell_w_px, cell_h_px);
                if session.vt_cols_rows() != size_before {
                    // Reflow moves the text: the old cells mean nothing now.
                    view.selection = None;
                    view.drag = None;
                }
                let title = session.title();
                let frame = session.frame().ok();
                // The live cursor, not the viewport one: see `ime_cell`.
                let ime_cell = frame
                    .as_ref()
                    .and_then(|f| ime_cell(session.cursor_position(), f.size.1));
                (
                    frame,
                    ime_cell,
                    view.selection,
                    view.marked.clone(),
                    focused,
                    title,
                )
            });
        let mut out = Prepaint {
            line_height: line_h,
            hitbox: Some(hitbox),
            ..Default::default()
        };
        let Some(frame) = frame else {
            return out;
        };
        let (frame_cols, frame_rows) = frame.size;

        let (default_bg, default_fg) = frame.default_colors;
        let cell_origin = |col: usize, row: usize| {
            point(
                grid_origin.x + cell_w * col as f32,
                grid_origin.y + line_h * row as f32,
            )
        };

        let flush = |acc: Option<RunAcc>, row: usize, out: &mut Prepaint, window: &mut Window| {
            let Some(acc) = acc else { return };
            let origin = cell_origin(acc.col, row);
            if let Some(bg) = acc.style.bg {
                out.backgrounds.push(fill(
                    Bounds::new(origin, size(cell_w * acc.cols as f32, line_h)),
                    bg,
                ));
            }
            let decorated = acc.style.underline || acc.style.strikethrough;
            if acc.text.trim().is_empty() && !decorated {
                return;
            }
            let mut run_font = base_font.clone();
            if acc.style.bold {
                run_font = run_font.bold();
            }
            if acc.style.italic {
                run_font = run_font.italic();
            }
            let fg = acc.style.fg;
            let run = TextRun {
                len: acc.text.len(),
                font: run_font,
                color: fg,
                background_color: None,
                underline: acc.style.underline.then_some(UnderlineStyle {
                    thickness: px(1.0),
                    color: Some(fg),
                    wavy: false,
                }),
                strikethrough: acc.style.strikethrough.then_some(StrikethroughStyle {
                    thickness: px(1.0),
                    color: Some(fg),
                }),
            };
            let line = window.text_system().shape_line(
                SharedString::from(acc.text),
                font_size,
                &[run],
                None,
            );
            out.texts.push(TextPaint { origin, line });
        };

        let mut cursor_line_text = String::new();
        let mut cell_lines = Vec::with_capacity(frame.styled_rows().len());
        for (row, cells) in frame.styled_rows().iter().enumerate() {
            let mut acc: Option<RunAcc> = None;
            let mut cell_line = String::with_capacity(cells.len());
            let is_cursor_row = frame.cursor.is_some_and(|c| usize::from(c.y) == row);
            for (col, cell) in cells.iter().enumerate() {
                if cell.width == CellWidth::SpacerTail {
                    cell_line.push('\0');
                    continue; // covered by the wide lead cell before it
                }
                let wide = cell.width == CellWidth::Wide;
                let text = if cell.text.is_empty()
                    || cell.invisible
                    || cell.width == CellWidth::SpacerHead
                {
                    " "
                } else {
                    cell.text.as_str()
                };
                cell_line.push(text.chars().next().unwrap_or(' '));
                if is_cursor_row {
                    cursor_line_text.push_str(text);
                }
                let style = cell_style(cell, default_fg, default_bg);
                let breaks = acc
                    .as_ref()
                    .is_none_or(|a| a.style != style || a.wide || wide);
                if breaks {
                    flush(acc.take(), row, &mut out, window);
                    acc = Some(RunAcc {
                        col,
                        cols: 0,
                        text: String::new(),
                        style,
                        wide,
                    });
                }
                let a = acc.as_mut().expect("run started above");
                a.text.push_str(text);
                a.cols += if wide { 2 } else { 1 };
            }
            flush(acc.take(), row, &mut out, window);
            cell_lines.push(cell_line);
        }

        // Selection: TERM_SELECTION over the selected cells, under the text.
        if let Some(sel) = selection {
            let color = theme::hsla(TERM_SELECTION);
            for (row, start, end) in sel.spans(frame_cols) {
                if row >= frame_rows || end <= start {
                    continue;
                }
                out.selection.push(fill(
                    Bounds::new(
                        cell_origin(usize::from(start), usize::from(row)),
                        size(cell_w * f32::from(end - start), line_h),
                    ),
                    color,
                ));
            }
        }

        // Cursor, then the IME preedit drawn inline over the cursor cell
        // (also while the app hides the cursor).
        let caret_cell = if marked.is_some() {
            ime_cell
        } else {
            frame.cursor.map(|c| Cell { row: c.y, col: c.x })
        };
        if let Some(caret) = caret_cell {
            let origin = cell_origin(usize::from(caret.col), usize::from(caret.row));
            let color = hsla(frame.cursor_color.unwrap_or(rgb(TERM_CURSOR)));
            let mut cursor_origin = origin;
            if let Some(text) = marked.as_ref() {
                let run = TextRun {
                    len: text.len(),
                    font: base_font.clone(),
                    color: hsla(default_fg),
                    background_color: None,
                    underline: Some(UnderlineStyle {
                        thickness: px(1.5),
                        color: Some(color),
                        wavy: false,
                    }),
                    strikethrough: None,
                };
                let line = window.text_system().shape_line(
                    SharedString::from(text.clone()),
                    font_size,
                    &[run],
                    None,
                );
                let width = line.width.max(cell_w);
                out.preedit_bg = Some(fill(
                    Bounds::new(origin, size(width, line_h)),
                    hsla(default_bg),
                ));
                cursor_origin.x += line.width;
                out.preedit = Some(TextPaint { origin, line });
            }
            let cell = Bounds::new(cursor_origin, size(cell_w, line_h));
            let shape = match (&marked, frame.cursor) {
                (None, Some(cursor)) => cursor.shape,
                _ => CursorShape::Bar,
            };
            out.cursor = Some(match (focused, shape) {
                (false, _) | (true, CursorShape::BlockHollow) => {
                    outline(cell, color, BorderStyle::Solid)
                }
                (true, CursorShape::Bar) => {
                    fill(Bounds::new(cursor_origin, size(px(2.0), line_h)), color)
                }
                (true, CursorShape::Underline) => fill(
                    Bounds::new(
                        point(cursor_origin.x, cursor_origin.y + line_h - px(2.0)),
                        size(cell_w, px(2.0)),
                    ),
                    color,
                ),
                (true, CursorShape::Block) => {
                    let mut block = color;
                    block.a = 0.55;
                    fill(cell, block)
                }
            });
        }

        // Accessibility stopgap: GPUI 0.2.2 has no UIA tree, so expose the
        // cursor line through the window title (Narrator: Insert+T). Only
        // the focused pane writes it, so split panes do not fight over it.
        let line = cursor_line_text.trim_end();
        let wanted = match (title, line.is_empty()) {
            (Some(t), true) => format!("{t} - {BASE_TITLE}"),
            (_, false) => format!("{line} - {BASE_TITLE}"),
            (None, true) => BASE_TITLE.to_string(),
        };
        let grid = Grid {
            origin: grid_origin,
            cell_w,
            cell_h: line_h,
            cols: frame_cols,
            rows: frame_rows,
            ime_cell,
        };
        let title_changed = self.view.update(cx, |view, _| {
            view.grid = Some(grid);
            view.cell_lines = cell_lines;
            if focused && view.title != wanted {
                view.title = wanted.clone();
                true
            } else {
                false
            }
        });
        if title_changed {
            window.set_window_title(&wanted);
        }
        out
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
        let focus_handle = self.view.read(cx).focus_handle.clone();
        window.handle_input(
            &focus_handle,
            ElementInputHandler::new(bounds, self.view.clone()),
            cx,
        );

        // Mouse selection. Bubble-phase listeners that never stop
        // propagation: TermView's own mouse-down (keyboard focus) and the
        // pane slot's (model focus, `RootView::focus_pane`) still run.
        // Moves and the button release are taken anywhere in the window
        // while a drag is active (GPUI captures the mouse on button down).
        if let Some(hitbox) = prepaint.hitbox.take() {
            let view = self.view.clone();
            window.on_mouse_event(move |event: &MouseDownEvent, phase, window, cx| {
                if phase == DispatchPhase::Bubble
                    && event.button == MouseButton::Left
                    && hitbox.is_hovered(window)
                {
                    view.update(cx, |view, cx| view.select_mouse_down(event, cx));
                }
            });
            let view = self.view.clone();
            window.on_mouse_event(move |event: &MouseMoveEvent, phase, _, cx| {
                if phase == DispatchPhase::Bubble && view.read(cx).drag.is_some() {
                    view.update(cx, |view, cx| view.select_mouse_move(event, cx));
                }
            });
            let view = self.view.clone();
            window.on_mouse_event(move |event: &MouseUpEvent, phase, _, cx| {
                if phase == DispatchPhase::Bubble
                    && event.button == MouseButton::Left
                    && view.read(cx).drag.is_some()
                {
                    view.update(cx, |view, _| view.select_mouse_up());
                }
            });
        }

        for quad in prepaint.backgrounds.drain(..) {
            window.paint_quad(quad);
        }
        for quad in prepaint.selection.drain(..) {
            window.paint_quad(quad);
        }
        if let Some(cursor) = prepaint.cursor.take() {
            window.paint_quad(cursor);
        }
        let line_height = prepaint.line_height;
        for text in prepaint.texts.drain(..) {
            let _ = text.line.paint(text.origin, line_height, window, cx);
        }
        if let Some(bg) = prepaint.preedit_bg.take() {
            window.paint_quad(bg);
        }
        if let Some(text) = prepaint.preedit.take() {
            let _ = text.line.paint(text.origin, line_height, window, cx);
        }
    }
}
