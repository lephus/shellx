//! The shortcut recorder (the Mac's `ShortcutRecorderView`): a 160 wide button showing a chord
//! ("Ctrl+Shift+N") or "—", and the button beside it. A click, Space or Enter starts listening
//! ("Press shortcut…"); the next key that is not a modifier is the chord, Esc stops with
//! nothing recorded. Settings › Keyboard Shortcuts has one per action (the button is X, or the
//! restore arrow once the action is unbound) and one as "Detect Shortcut" ("Listening…"),
//! whose X clears the search.
//!
//! The key rules are `shellx_model::controls::{recorder_key, recorder_stops_key,
//! still_listening}`. An idle recorder stops no key. A listening one stops every key-down it
//! hears except Alt+F4, Alt+Space and the Windows key's, so no app command runs and Esc does
//! not close Settings. It listens only while it has the keyboard in the active window: a click
//! anywhere else, another section, Settings closing or going to the background end it, so it
//! can never be left swallowing the keys typed afterwards. It keeps the keyboard when it stops,
//! and then passes Esc and Tab on to the Settings view.

use gpui::{
    ClickEvent, Context, EventEmitter, FocusHandle, Focusable, KeyDownEvent, MouseDownEvent,
    SharedString, Window, div, prelude::*, px, svg, transparent_black,
};
use shellx_model::controls::{
    RecorderKey, activates, recorder_key, recorder_stops_key, still_listening,
};
use shellx_model::keymap::{Chord, ClearButton, Refused};
use shellx_model::strings::{Str, t};

use super::super::app::Services;
use super::super::assets::Icon;
use super::super::theme;
use super::super::tooltip::Tooltip;
use super::{CONTROL_H, CONTROL_TEXT, DISABLED_OPACITY, focus_ring, is_mouse, key_in, ring};

/// The Mac's `.frame(width: 160)`.
const WIDTH: f32 = 160.0;
/// Between the recorder and its button, as in the Mac's row.
const GAP: f32 = 12.0;

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum RecorderEvent {
    /// The chord pressed while listening: one `accept` takes (a row), or any (Detect Shortcut).
    Recorded(Chord),
    /// A row's chord that cannot be a shortcut, and why.
    Refused(Refused),
    /// The X: a row unbinds its action, Detect Shortcut clears the search.
    Cleared,
    /// The restore arrow: the row's default comes back.
    Restored,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum Use {
    /// An action's row.
    Row,
    /// "Detect Shortcut" in the search bar.
    Detect,
}

pub struct Recorder {
    focus: FocusHandle,
    kind: Use,
    listening: bool,
    /// Shown while idle: the row's chord, or the chord Detect Shortcut heard.
    chord: Option<Chord>,
    button: ClearButton,
}

impl EventEmitter<RecorderEvent> for Recorder {}

impl Focusable for Recorder {
    fn focus_handle(&self, _: &gpui::App) -> FocusHandle {
        self.focus.clone()
    }
}

impl Recorder {
    /// An action's recorder.
    pub fn row(cx: &mut Context<Self>) -> Self {
        Self::new(Use::Row, cx)
    }

    /// "Detect Shortcut".
    pub fn detector(cx: &mut Context<Self>) -> Self {
        Self::new(Use::Detect, cx)
    }

    fn new(kind: Use, cx: &mut Context<Self>) -> Self {
        Recorder {
            focus: cx.focus_handle().tab_stop(true),
            kind,
            listening: false,
            chord: None,
            button: ClearButton::Off,
        }
    }

    /// Shows `chord` (`None`: "—", or "Detect Shortcut") and `button` beside it; emits nothing.
    pub fn show(&mut self, chord: Option<Chord>, button: ClearButton, cx: &mut Context<Self>) {
        if self.chord != chord || self.button != button {
            self.chord = chord;
            self.button = button;
            cx.notify();
        }
    }

    fn listen(&mut self, window: &mut Window, cx: &mut Context<Self>) {
        window.focus(&self.focus);
        self.listening = true;
        cx.notify();
    }

    fn stop(&mut self, cx: &mut Context<Self>) {
        if self.listening {
            self.listening = false;
            cx.notify();
        }
    }

    /// Listening ends once the recorder has lost the keyboard or its window the foreground.
    fn follow_focus(&mut self, window: &Window) {
        self.listening = still_listening(
            self.listening,
            self.focus.is_focused(window),
            window.is_window_active(),
        );
    }

    fn on_key_down(&mut self, event: &KeyDownEvent, window: &mut Window, cx: &mut Context<Self>) {
        self.follow_focus(window);
        let key = key_in(event);
        if recorder_stops_key(self.listening, &key) {
            cx.stop_propagation();
        }
        match recorder_key(self.listening, &key, event.is_held) {
            RecorderKey::Pass | RecorderKey::Wait => {}
            RecorderKey::Listen => self.listen(window, cx),
            RecorderKey::Cancel => self.stop(cx),
            RecorderKey::Pressed(chord, accepted) => {
                self.stop(cx);
                cx.emit(match (self.kind, accepted) {
                    (Use::Row, Err(refused)) => RecorderEvent::Refused(refused),
                    _ => RecorderEvent::Recorded(chord),
                });
            }
        }
    }

    fn label(&self, cx: &Context<Self>) -> (SharedString, bool) {
        let lang = cx.global::<Services>().lang;
        let text = match (self.listening, self.kind, &self.chord) {
            (true, Use::Row, _) => t(lang, Str::SettingsPressShortcut).into(),
            (true, Use::Detect, _) => t(lang, Str::SettingsListening).into(),
            (false, _, Some(chord)) => chord.label().into(),
            (false, Use::Row, None) => "—".into(),
            (false, Use::Detect, None) => t(lang, Str::SettingsDetectShortcut).into(),
        };
        (text, self.chord.is_none() && !self.listening)
    }

    /// X (unbind, or clear the search), the restore arrow, or a disabled X.
    fn button(&self, cx: &mut Context<Self>) -> impl IntoElement {
        let lang = cx.global::<Services>().lang;
        let (icon, tip, event) = match (self.button, self.kind) {
            (ClearButton::Off, _) => (Icon::CloseSm, None, None),
            (ClearButton::Restore, _) => (
                Icon::ArrowLeftMd,
                Some(Str::SettingsRestoreShortcut),
                Some(RecorderEvent::Restored),
            ),
            (ClearButton::Clear, Use::Row) => (
                Icon::CloseSm,
                Some(Str::SettingsUnbindShortcut),
                Some(RecorderEvent::Cleared),
            ),
            (ClearButton::Clear, Use::Detect) => {
                (Icon::CloseSm, None, Some(RecorderEvent::Cleared))
            }
        };
        let button = div()
            .id("recorder-button")
            .flex()
            .flex_none()
            .items_center()
            .justify_center()
            .size(CONTROL_H)
            .rounded(px(6.0))
            .border_1()
            .border_color(transparent_black())
            .child(
                svg()
                    .path(icon.path())
                    .size(px(12.0))
                    .text_color(theme::muted()),
            );
        let Some(event) = event else {
            return button.opacity(DISABLED_OPACITY);
        };
        let pressed = event.clone();
        button
            .tab_index(0)
            .cursor_pointer()
            .focus(focus_ring)
            .hover(|style| style.bg(theme::raise()))
            .when_some(tip, |button, tip| {
                let tip = SharedString::from(t(lang, tip));
                button.tooltip(move |_, cx| Tooltip::view(tip.clone(), cx))
            })
            .on_click(cx.listener(move |_, click: &ClickEvent, _, cx| {
                if is_mouse(click) {
                    cx.emit(pressed.clone());
                }
            }))
            .on_key_down(cx.listener(move |_, key: &KeyDownEvent, _, cx| {
                if activates(&key_in(key)) {
                    cx.stop_propagation();
                    if !key.is_held {
                        cx.emit(event.clone());
                    }
                }
            }))
    }
}

impl Render for Recorder {
    fn render(&mut self, window: &mut Window, cx: &mut Context<Self>) -> impl IntoElement {
        self.follow_focus(window);
        let focused = self.focus.is_focused(window);
        let (label, placeholder) = self.label(cx);
        let field = div()
            .id("recorder")
            .track_focus(&self.focus)
            .flex()
            .flex_none()
            .items_center()
            .justify_center()
            .w(px(WIDTH))
            .h(CONTROL_H)
            .px(px(8.0))
            .rounded(px(6.0))
            .border_1()
            .border_color(if focused { ring() } else { theme::border() })
            .bg(if self.listening {
                theme::primary_soft()
            } else {
                theme::raise()
            })
            .text_size(CONTROL_TEXT)
            .text_color(if self.listening {
                theme::primary_text()
            } else if placeholder {
                theme::muted()
            } else {
                theme::text()
            })
            .cursor_pointer()
            .when(!focused, |field| {
                field.hover(|style| style.border_color(theme::primary_line()))
            })
            .child(div().min_w_0().truncate().child(label))
            .on_click(cx.listener(|this, event: &ClickEvent, window, cx| {
                if !is_mouse(event) {
                    return;
                }
                if this.listening {
                    this.stop(cx);
                } else {
                    this.listen(window, cx);
                }
            }))
            .on_mouse_down_out(cx.listener(|this, _: &MouseDownEvent, _, cx| this.stop(cx)))
            .on_key_down(cx.listener(Self::on_key_down));
        div()
            .flex()
            .flex_row()
            .flex_none()
            .items_center()
            .gap(px(GAP))
            .child(field)
            .child(self.button(cx))
    }
}
