//! The Settings control kit (spec §5.3, inventory §D): the card, its rows and the section
//! header above it, the switch, the segmented control, the picker, the slider, the stepper,
//! the colour well and the shortcut recorder.
//!
//! A stateless control is a function of the value it shows and calls back when the user
//! changes it. A control with its own state (an open list, a drag, a typed hex code) is an
//! entity that emits an event; it holds no setting: its owner sets the value from outside
//! (`set_value`), so a value changed elsewhere (Reset, another window) shows at once.
//!
//! Every enabled control is a GPUI tab stop (its owner moves focus with
//! `Window::focus_next` / `focus_prev` on Tab), shows a ring while it has the keyboard, and
//! is operated with the keys `shellx_model::controls` names. A key handler stops only those
//! keys, and only while its own control has the keyboard: a stopped key-down yields no
//! WM_CHAR on Windows. Keyboard clicks are taken on key-down, so `on_click` handlers ignore
//! the key-up click GPUI also reports for a focused element. A disabled control is drawn at
//! half opacity, takes no input and is not a tab stop.

mod card;
mod color_well;
mod picker;
mod recorder;
mod segmented;
mod slider;
mod stepper;
mod toggle;

pub use card::{card, row, section_header};
pub use color_well::{ColorEvent, ColorWell};
pub use picker::{Picker, PickerEvent};
pub use recorder::{Recorder, RecorderEvent};
pub use segmented::segmented;
pub use slider::{Slider, SliderEvent};
pub use stepper::{Stepper, StepperEvent};
pub use toggle::toggle;

use gpui::{ClickEvent, KeyDownEvent, Pixels, StyleRefinement, prelude::*, px};
use shellx_model::keys::KeyIn;

use super::theme;

/// Height of a segmented control, a picker, a stepper's buttons and a colour well.
const CONTROL_H: Pixels = px(22.0);
/// Labels inside a control and the value beside one: the Mac's callout size.
const CONTROL_TEXT: Pixels = px(12.0);
const DISABLED_OPACITY: f32 = 0.5;

/// The key as `shellx_model::controls` reads it (the Settings view reads its own keys so too).
pub(super) fn key_in(event: &KeyDownEvent) -> KeyIn<'_> {
    let mods = event.keystroke.modifiers;
    KeyIn {
        key: event.keystroke.key.as_str(),
        ctrl: mods.control,
        alt: mods.alt,
        shift: mods.shift,
        win: mods.platform,
    }
}

/// A click with the mouse; Space and Enter are handled on key-down instead.
fn is_mouse(event: &ClickEvent) -> bool {
    matches!(event, ClickEvent::Mouse(_))
}

/// The 1 px border colour of a control while it has the keyboard.
fn ring() -> gpui::Hsla {
    theme::primary_text()
}

/// The ring of a stateless control, which cannot ask whether it is focused.
fn focus_ring(style: StyleRefinement) -> StyleRefinement {
    style.border_color(ring())
}
