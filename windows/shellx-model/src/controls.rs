//! The rules of the Settings controls (`shellx-app/src/ui/controls/`): where a slider's track
//! maps to a value, how a stepper moves, how the colour field reads a hex code, how a value is
//! written beside its control, and which keys each control uses.
//!
//! A control stops only the keys these functions name, and only while it has the keyboard:
//! on Windows a stopped key-down produces no WM_CHAR, so a control never takes a letter, a
//! digit, Tab or a chord. The one exception is a shortcut recorder while it listens: then every
//! key-down is the chord it records (`recorder_stops_key`), and it listens only while it has
//! the keyboard (`still_listening`).

use crate::keymap::{Chord, Refused, accept};
use crate::keys::{KeyIn, is_modifier_alone, is_window_system_key};
use crate::palette::Rgba;
use crate::settings_catalog::{Section, Unit};

/// The value at `fraction` of a slider's track: clamped to the track, snapped to `step`.
pub fn slider_value(fraction: f32, min: f32, max: f32, step: f32) -> f32 {
    let fraction = f64::from(unit_interval(fraction));
    let (min64, max64) = (f64::from(min), f64::from(max));
    snap(min64 + fraction * (max64 - min64), min, max, step)
}

/// Where `value` sits on a slider's track, from 0 to 1.
pub fn slider_fraction(value: f32, min: f32, max: f32) -> f32 {
    if max <= min {
        return 0.0;
    }
    unit_interval((value - min) / (max - min))
}

/// Clamped to 0–1, NaN to 0.
fn unit_interval(fraction: f32) -> f32 {
    if fraction.is_nan() {
        0.0
    } else {
        fraction.clamp(0.0, 1.0)
    }
}

/// `value` moved by `steps` whole steps, snapped and clamped.
pub fn stepped(value: f32, steps: i32, min: f32, max: f32, step: f32) -> f32 {
    snap(
        f64::from(value) + f64::from(steps) * f64::from(step),
        min,
        max,
        step,
    )
}

/// Snaps to a multiple of `step` as `settings.rs` reads the value back, drops the float noise
/// the way `settings.json` writes it (four decimals), then clamps.
fn snap(x: f64, min: f32, max: f32, step: f32) -> f32 {
    let step = f64::from(step);
    let x = if step > 0.0 {
        (x / step).round() * step
    } else {
        x
    };
    let x = (x * 1e4).round() / 1e4;
    // `max().min()` never panics on an empty range, unlike `clamp`.
    (x as f32).max(min).min(max)
}

/// "#RRGGBB" or "RRGGBB", any case, spaces around it ignored.
pub fn parse_hex(text: &str) -> Option<Rgba> {
    let text = text.trim();
    let digits = text.strip_prefix('#').unwrap_or(text);
    if digits.len() != 6 || !digits.bytes().all(|b| b.is_ascii_hexdigit()) {
        return None;
    }
    u32::from_str_radix(digits, 16).ok().map(Rgba::rgb)
}

/// The label beside a slider or stepper, as the Mac writes it: "13 pt", "12.5 pt", "1.00×",
/// "70%", "50 MB".
pub fn format_value(value: f32, unit: Unit) -> String {
    match unit {
        Unit::Points => format!("{} pt", points(value)),
        Unit::Times => format!("{value:.2}×"),
        Unit::Percent => format!("{}%", (f64::from(value) * 100.0).round()),
        Unit::Megabytes => format!("{} MB", f64::from(value).round()),
    }
}

/// What a number field (Scrollback Limit) keeps of the text typed into it: the ASCII digits.
pub fn digits(text: &str) -> String {
    text.chars().filter(char::is_ascii_digit).collect()
}

/// The value a number field commits (Enter, or leaving it): its digits as a whole number,
/// clamped to the row's range. `None` while it holds no digit; the field then shows the
/// stored value again.
pub fn number_entry(text: &str, min: f32, max: f32) -> Option<f32> {
    let digits = digits(text);
    if digits.is_empty() {
        return None;
    }
    // f64 reads any number of digits (a huge one is then clamped, not refused).
    let value: f64 = digits.parse().ok()?;
    Some((value as f32).max(min).min(max))
}

/// A number field's text for a stored value.
pub fn number_text(value: f32) -> String {
    format!("{}", f64::from(value).round())
}

/// What Esc does in a number field: with an edit in it, the stored value comes back and the
/// window stays; with none, the key is the window's (it closes).
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum NumberEsc {
    Restore,
    Close,
}

pub fn number_escape(text: &str, stored: f32) -> NumberEsc {
    let _ = (text, stored);
    unimplemented!()
}

/// The value to write when the window closes with `text` in the field: its clamped number,
/// only when it differs from the stored one.
pub fn number_pending(text: &str, stored: f32, min: f32, max: f32) -> Option<f32> {
    let _ = (text, stored, min, max);
    unimplemented!()
}

/// The unit written after a number field.
pub fn unit_suffix(unit: Unit) -> &'static str {
    match unit {
        Unit::Points => "pt",
        Unit::Times => "×",
        Unit::Percent => "%",
        Unit::Megabytes => "MB",
    }
}

/// At most two decimals and no trailing zero, like the Mac's `formattedFontSize`.
fn points(value: f32) -> String {
    let text = format!("{value:.2}");
    text.trim_end_matches('0').trim_end_matches('.').to_string()
}

fn no_modifier(k: &KeyIn) -> bool {
    !(k.ctrl || k.alt || k.shift || k.win)
}

/// A focused slider: Left and Right move it one step.
pub fn slider_key(k: &KeyIn) -> Option<i32> {
    if !no_modifier(k) {
        return None;
    }
    match k.key {
        "left" => Some(-1),
        "right" => Some(1),
        _ => None,
    }
}

/// A focused stepper: Up and Down move it one step.
pub fn stepper_key(k: &KeyIn) -> Option<i32> {
    if !no_modifier(k) {
        return None;
    }
    match k.key {
        "down" => Some(-1),
        "up" => Some(1),
        _ => None,
    }
}

/// Space or Enter: flips a focused toggle, picks a focused segment, opens a closed picker or
/// colour well.
pub fn activates(k: &KeyIn) -> bool {
    no_modifier(k) && matches!(k.key, "space" | "enter")
}

/// A key the Settings view handles itself, once no control or field has used it.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ViewKey {
    /// A plain Esc: the host closes Settings (an open popover has taken its Esc already).
    Close,
    /// Tab: the focus moves to the next control.
    Next,
    /// Shift+Tab: the focus moves to the previous control.
    Prev,
}

pub fn view_key(k: &KeyIn) -> Option<ViewKey> {
    if k.ctrl || k.alt || k.win {
        return None;
    }
    match (k.key, k.shift) {
        ("escape", false) => Some(ViewKey::Close),
        ("tab", false) => Some(ViewKey::Next),
        ("tab", true) => Some(ViewKey::Prev),
        _ => None,
    }
}

/// Whether the Settings view takes the keyboard before it draws `shown`, `drawn` being the
/// section of its last draw (`None` before the first): the control that had the keyboard
/// belongs to the section that was on screen, and once it is not drawn GPUI sends the keys
/// nowhere, so Esc and Tab would stop working. Not on the first draw (the host has just given
/// the view the keyboard), and not while the same section stays.
pub fn view_takes_focus(drawn: Option<Section>, shown: Section) -> bool {
    drawn.is_some_and(|drawn| drawn != shown)
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum PopoverKey {
    /// Moves the highlight by this many rows.
    Move(i32),
    /// Picks the highlighted row.
    Pick,
    Close,
}

/// The keys of an open picker list (the keyboard stays on the picker while it is open).
pub fn popover_key(k: &KeyIn) -> Option<PopoverKey> {
    if !no_modifier(k) {
        return None;
    }
    match k.key {
        "up" => Some(PopoverKey::Move(-1)),
        "down" => Some(PopoverKey::Move(1)),
        "space" | "enter" => Some(PopoverKey::Pick),
        "escape" => Some(PopoverKey::Close),
        _ => None,
    }
}

/// The highlighted row of a list of `len` rows after moving `delta` rows: it stops at the ends.
pub fn moved_highlight(current: usize, delta: i32, len: usize) -> usize {
    let last = len.saturating_sub(1);
    let current = current.min(last) as i64;
    (current + i64::from(delta)).clamp(0, last as i64) as usize
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum DragMove {
    /// No drag is on.
    Ignore,
    /// The knob follows the pointer.
    Follow,
    /// The button came up where the slider did not see it (GPUI-Windows sends no mouse-up
    /// when the capture is lost): the drag ends, the knob stays.
    End,
}

/// What a pointer move does to a slider, given whether it is dragging and whether the left
/// button is down during the move.
pub fn slider_drag_move(dragging: bool, left_down: bool) -> DragMove {
    match (dragging, left_down) {
        (false, _) => DragMove::Ignore,
        (true, true) => DragMove::Follow,
        (true, false) => DragMove::End,
    }
}

/// What a shortcut recorder (a row's in Settings › Keyboard Shortcuts, or its "Detect
/// Shortcut") does with a key-down that reaches it.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum RecorderKey {
    /// Not its key.
    Pass,
    /// Space or Enter on an idle recorder: it starts listening.
    Listen,
    /// Listening, and this is a modifier alone or an auto-repeat: it waits for the chord.
    Wait,
    /// A plain Esc while listening: it stops, with nothing recorded.
    Cancel,
    /// The chord pressed while listening, and whether `keymap::accept` takes it (Detect
    /// Shortcut looks it up either way). Listening ends.
    Pressed(Chord, Result<(), Refused>),
}

/// `listening` is whether the recorder listens now; `repeat` is GPUI's `is_held`.
pub fn recorder_key(listening: bool, k: &KeyIn, repeat: bool) -> RecorderKey {
    if !listening {
        return if !repeat && activates(k) {
            RecorderKey::Listen
        } else {
            RecorderKey::Pass
        };
    }
    if repeat || is_modifier_alone(k.key) {
        return RecorderKey::Wait;
    }
    if no_modifier(k) && k.key == "escape" {
        return RecorderKey::Cancel;
    }
    let chord = Chord::of(k);
    let accepted = accept(&chord, k.win);
    RecorderKey::Pressed(chord, accepted)
}

/// Whether a recorder stops a key-down. An idle one stops none, not even the Space or Enter
/// that starts it (nothing else wants them while it has the keyboard): a stopped key-down
/// yields no WM_CHAR on Windows. A listening one stops every key-down it hears, so no app
/// command runs and Esc does not close Settings, except the keys Windows keeps (Alt+F4,
/// Alt+Space, anything with the Windows key), which go on to Windows.
pub fn recorder_stops_key(listening: bool, k: &KeyIn) -> bool {
    listening && !k.win && !is_window_system_key(k)
}

/// Whether a recorder still listens: only while it has the keyboard (`focused`) in the active
/// window. A click elsewhere that takes the keyboard, another section, Settings closing or
/// going to the background each end it, so it cannot keep swallowing keys.
pub fn still_listening(listening: bool, focused: bool, window_active: bool) -> bool {
    listening && focused && window_active
}

#[cfg(test)]
mod tests {
    use super::*;

    fn plain(key: &str) -> KeyIn<'_> {
        KeyIn {
            key,
            ctrl: false,
            alt: false,
            shift: false,
            win: false,
        }
    }

    /// `key` with each single modifier, then with all of them.
    fn chords(key: &str) -> [KeyIn<'_>; 5] {
        let k = plain(key);
        [
            KeyIn { ctrl: true, ..k },
            KeyIn { alt: true, ..k },
            KeyIn { shift: true, ..k },
            KeyIn { win: true, ..k },
            KeyIn {
                ctrl: true,
                alt: true,
                shift: true,
                win: true,
                ..k
            },
        ]
    }

    /// Every value a catalogue slider can hold, from `min` by `step` to `max`.
    fn grid(min: f32, max: f32, step: f32) -> Vec<f32> {
        let n = ((max - min) / step).round() as i32;
        (0..=n).map(|k| stepped(min, k, min, max, step)).collect()
    }

    #[test]
    fn slider_snaps_and_clamps() {
        // Tab bar font size: 8–14 pt, step 0.5.
        assert_eq!(slider_value(0.5, 8.0, 14.0, 0.5), 11.0);
        assert_eq!(slider_value(2.0, 8.0, 14.0, 0.5), 14.0);
        assert_eq!(slider_value(-1.0, 8.0, 14.0, 0.5), 8.0);
        assert_eq!(slider_value(f32::NAN, 8.0, 14.0, 0.5), 8.0);
        // 8 + 0.52 × 6 = 11.12 snaps to the nearest half point.
        assert_eq!(slider_value(0.52, 8.0, 14.0, 0.5), 11.0);
        // Scroll speed: 0.25–3.0, step 0.05; no float noise left over.
        assert_eq!(slider_value(0.6, 0.25, 3.0, 0.05), 1.9);
        assert_eq!(slider_value(1.0, 0.25, 3.0, 0.05), 3.0);
        // Unselected fill opacity: 0–1, step 0.05.
        assert_eq!(slider_value(0.7, 0.0, 1.0, 0.05), 0.7);

        assert_eq!(slider_fraction(11.0, 8.0, 14.0), 0.5);
        assert_eq!(slider_fraction(8.0, 8.0, 14.0), 0.0);
        assert_eq!(slider_fraction(20.0, 8.0, 14.0), 1.0);
        assert_eq!(slider_fraction(2.0, 8.0, 14.0), 0.0);
        assert_eq!(slider_fraction(f32::NAN, 8.0, 14.0), 0.0);
        // An empty range puts the knob at the start instead of dividing by zero.
        assert_eq!(slider_fraction(5.0, 5.0, 5.0), 0.0);

        // The knob of every value a slider can hold maps back to that value.
        for (min, max, step) in [
            (8.0, 14.0, 0.5),
            (0.25, 3.0, 0.05),
            (0.0, 1.0, 0.05),
            (10.0, 20.0, 0.5),
        ] {
            for v in grid(min, max, step) {
                assert_eq!(
                    slider_value(slider_fraction(v, min, max), min, max, step),
                    v,
                    "{v} in {min}–{max} step {step}"
                );
            }
        }
    }

    #[test]
    fn stepped_moves_by_whole_steps() {
        // Font size stepper: 4–96 pt, step 0.5.
        assert_eq!(stepped(13.0, 1, 4.0, 96.0, 0.5), 13.5);
        assert_eq!(stepped(13.0, -2, 4.0, 96.0, 0.5), 12.0);
        assert_eq!(stepped(96.0, 1, 4.0, 96.0, 0.5), 96.0);
        assert_eq!(stepped(4.0, -1, 4.0, 96.0, 0.5), 4.0);
        assert_eq!(stepped(13.0, 0, 4.0, 96.0, 0.5), 13.0);
        // A value off the grid lands on it.
        assert_eq!(stepped(13.3, 1, 4.0, 96.0, 0.5), 14.0);
        // Padding: 0–200, step 1.
        assert_eq!(stepped(0.0, 3, 0.0, 200.0, 1.0), 3.0);
        assert_eq!(stepped(0.0, -1, 0.0, 200.0, 1.0), 0.0);
        // Scroll speed: one step from 1.00× is exactly 1.05×.
        assert_eq!(stepped(1.0, 1, 0.25, 3.0, 0.05), 1.05);
        assert_eq!(stepped(1.0, -15, 0.25, 3.0, 0.05), 0.25);
        // Twenty steps of 0.05 from 0 are exactly 1.
        assert_eq!(stepped(0.0, 20, 0.0, 1.0, 0.05), 1.0);
    }

    #[test]
    fn hex_parses_with_and_without_hash() {
        let blue = Some(Rgba::rgb(0x60a5fa));
        assert_eq!(parse_hex("#60A5FA"), blue);
        assert_eq!(parse_hex("60a5fa "), blue);
        assert_eq!(parse_hex("  #60a5Fa\t"), blue);
        assert_eq!(parse_hex("#000000"), Some(Rgba::rgb(0)));
        assert_eq!(parse_hex("#12"), None);
        assert_eq!(parse_hex("#gggggg"), None);
        assert_eq!(parse_hex(""), None);
        assert_eq!(parse_hex("#"), None);
        assert_eq!(parse_hex("#60a5fa0"), None);
        assert_eq!(parse_hex("##60a5f"), None);
        assert_eq!(parse_hex("+60a5f"), None);
        assert_eq!(parse_hex("#60 a5f"), None);
    }

    #[test]
    fn values_format_with_their_unit() {
        assert_eq!(format_value(13.0, Unit::Points), "13 pt");
        assert_eq!(format_value(12.5, Unit::Points), "12.5 pt");
        assert_eq!(format_value(100.0, Unit::Points), "100 pt");
        assert_eq!(format_value(1.0, Unit::Times), "1.00×");
        assert_eq!(format_value(0.25, Unit::Times), "0.25×");
        assert_eq!(format_value(1.05, Unit::Times), "1.05×");
        assert_eq!(format_value(0.7, Unit::Percent), "70%");
        assert_eq!(format_value(0.05, Unit::Percent), "5%");
        assert_eq!(format_value(1.0, Unit::Percent), "100%");
        assert_eq!(format_value(50.0, Unit::Megabytes), "50 MB");
        assert_eq!(format_value(0.0, Unit::Megabytes), "0 MB");
    }

    #[test]
    fn each_control_uses_only_its_own_keys() {
        assert_eq!(slider_key(&plain("left")), Some(-1));
        assert_eq!(slider_key(&plain("right")), Some(1));
        assert_eq!(slider_key(&plain("up")), None);
        assert_eq!(slider_key(&plain("down")), None);

        assert_eq!(stepper_key(&plain("up")), Some(1));
        assert_eq!(stepper_key(&plain("down")), Some(-1));
        assert_eq!(stepper_key(&plain("left")), None);
        assert_eq!(stepper_key(&plain("right")), None);

        assert!(activates(&plain("space")));
        assert!(activates(&plain("enter")));
        assert!(!activates(&plain("escape")));
        assert!(!activates(&plain("down")));

        assert_eq!(popover_key(&plain("up")), Some(PopoverKey::Move(-1)));
        assert_eq!(popover_key(&plain("down")), Some(PopoverKey::Move(1)));
        assert_eq!(popover_key(&plain("enter")), Some(PopoverKey::Pick));
        assert_eq!(popover_key(&plain("space")), Some(PopoverKey::Pick));
        assert_eq!(popover_key(&plain("escape")), Some(PopoverKey::Close));
        assert_eq!(popover_key(&plain("left")), None);
    }

    /// A stopped key-down yields no WM_CHAR on Windows: no control may take typed text,
    /// Tab (focus moves on) or a shortcut.
    #[test]
    fn no_control_uses_a_letter_a_digit_tab_or_a_chord() {
        let letters = ('a'..='z').chain('0'..='9').map(String::from);
        let named = [
            "tab",
            "backspace",
            "delete",
            "home",
            "end",
            "pageup",
            "pagedown",
            "f2",
        ]
        .map(String::from);
        for key in letters.chain(named) {
            let k = plain(&key);
            assert_eq!(slider_key(&k), None, "{key}");
            assert_eq!(stepper_key(&k), None, "{key}");
            assert!(!activates(&k), "{key}");
            assert_eq!(popover_key(&k), None, "{key}");
        }
        for key in ["left", "right", "up", "down", "space", "enter", "escape"] {
            for k in chords(key) {
                assert_eq!(slider_key(&k), None, "{k:?}");
                assert_eq!(stepper_key(&k), None, "{k:?}");
                assert!(!activates(&k), "{k:?}");
                assert_eq!(popover_key(&k), None, "{k:?}");
            }
        }
    }

    #[test]
    fn the_highlight_stops_at_the_ends_of_the_list() {
        assert_eq!(moved_highlight(0, 1, 3), 1);
        assert_eq!(moved_highlight(2, 1, 3), 2);
        assert_eq!(moved_highlight(0, -1, 3), 0);
        assert_eq!(moved_highlight(2, -1, 3), 1);
        // A stale index (the list got shorter) comes back inside it.
        assert_eq!(moved_highlight(9, 0, 3), 2);
        assert_eq!(moved_highlight(0, 1, 0), 0);
    }

    /// GPUI-Windows sends no mouse-up when the capture is lost mid-drag (Alt+Tab, the Win
    /// key, a dialog): a move without the left button ends the drag instead of moving the knob.
    #[test]
    fn a_slider_drag_ends_when_the_left_button_is_no_longer_down() {
        assert_eq!(slider_drag_move(true, true), DragMove::Follow);
        assert_eq!(slider_drag_move(true, false), DragMove::End);
        assert_eq!(slider_drag_move(false, true), DragMove::Ignore);
        assert_eq!(slider_drag_move(false, false), DragMove::Ignore);
    }

    /// A number field (Scrollback Limit): it keeps only the digits typed, commits a whole
    /// number clamped to the row's range, and writes its unit beside it.
    #[test]
    fn a_number_field_keeps_digits_and_commits_a_clamped_whole_number() {
        assert_eq!(digits("1a2 3"), "123");
        assert_eq!(digits("-5.5"), "55");
        assert_eq!(digits("１２"), "");
        assert_eq!(digits(""), "");
        assert_eq!(number_entry("50", 0.0, 100_000.0), Some(50.0));
        assert_eq!(number_entry("007", 0.0, 100_000.0), Some(7.0));
        assert_eq!(number_entry(" 12 ", 0.0, 100_000.0), Some(12.0));
        assert_eq!(number_entry("200000", 0.0, 100_000.0), Some(100_000.0));
        assert_eq!(
            number_entry("99999999999999999999999", 0.0, 100_000.0),
            Some(100_000.0)
        );
        assert_eq!(number_entry("3", 4.0, 96.0), Some(4.0));
        assert_eq!(number_entry("", 0.0, 100_000.0), None);
        assert_eq!(number_entry("MB", 0.0, 100_000.0), None);
        assert_eq!(number_text(50.0), "50");
        assert_eq!(number_text(100_000.0), "100000");
        assert_eq!(unit_suffix(Unit::Megabytes), "MB");
        assert_eq!(unit_suffix(Unit::Points), "pt");
        assert_eq!(unit_suffix(Unit::Times), "×");
        assert_eq!(unit_suffix(Unit::Percent), "%");
    }

    /// The Settings view's own keys: a plain Esc asks its host to close it, Tab and Shift+Tab
    /// move the focus (GPUI binds no Tab). Nothing else, so a letter or a digit always
    /// reaches the field that has the keyboard, and a chord stays the window's or Windows'.
    #[test]
    fn the_settings_view_uses_only_esc_tab_and_shift_tab() {
        assert_eq!(view_key(&plain("escape")), Some(ViewKey::Close));
        assert_eq!(view_key(&plain("tab")), Some(ViewKey::Next));
        assert_eq!(
            view_key(&KeyIn {
                shift: true,
                ..plain("tab")
            }),
            Some(ViewKey::Prev)
        );
        let letters = ('a'..='z').map(|c| c.to_string());
        let digits = ('0'..='9').map(|c| c.to_string());
        let others = [
            "space",
            "enter",
            "backspace",
            "delete",
            "left",
            "right",
            "up",
            "down",
            "home",
            "end",
            "f2",
        ]
        .map(str::to_string);
        for key in letters.chain(digits).chain(others) {
            assert_eq!(view_key(&plain(&key)), None, "{key}");
            for chord in chords(&key) {
                assert_eq!(view_key(&chord), None, "{key} chord");
            }
        }
        for key in ["escape", "tab"] {
            let k = plain(key);
            for chord in [
                KeyIn { ctrl: true, ..k },
                KeyIn { alt: true, ..k },
                KeyIn { win: true, ..k },
            ] {
                assert_eq!(view_key(&chord), None, "{key} chord");
            }
        }
        assert_eq!(
            view_key(&KeyIn {
                shift: true,
                ..plain("escape")
            }),
            None
        );
    }

    /// The control that has the keyboard belongs to the section on screen. When another
    /// section is drawn, that control is gone and GPUI would send the keys nowhere (no Esc, no
    /// Tab): the view takes the keyboard first. Not on its first draw, where the host has just
    /// given it the keyboard, and not while the same section stays.
    #[test]
    fn the_view_takes_the_keyboard_when_its_section_changes() {
        assert!(view_takes_focus(Some(Section::Terminal), Section::About));
        assert!(view_takes_focus(Some(Section::About), Section::Updates));
        assert!(!view_takes_focus(
            Some(Section::Terminal),
            Section::Terminal
        ));
        assert!(!view_takes_focus(None, Section::Account));
    }

    /// Every key a person may type while Settings is open, plain and as chords.
    fn every_key() -> Vec<String> {
        let named = [
            "space",
            "enter",
            "tab",
            "escape",
            "backspace",
            "delete",
            "left",
            "right",
            "up",
            "down",
            "home",
            "end",
            "pageup",
            "pagedown",
            "insert",
            "f1",
            "f4",
            "f5",
            "f12",
            "f13",
            ",",
            ".",
            "=",
            "+",
            "-",
            "_",
            "/",
            "[",
            "]",
            "shift",
            "control",
            "alt",
        ];
        ('a'..='z')
            .chain('0'..='9')
            .map(String::from)
            .chain(named.map(String::from))
            .collect()
    }

    fn with(k: KeyIn<'_>, ctrl: bool, alt: bool, shift: bool) -> KeyIn<'_> {
        KeyIn {
            ctrl,
            alt,
            shift,
            ..k
        }
    }

    /// The key rule of this app: on Windows a stopped key-down yields no WM_CHAR. A recorder
    /// (a row's, or "Detect Shortcut") that is not listening stops nothing: a letter typed
    /// into the search field next to it always arrives. Only a fresh Space or Enter on the
    /// recorder itself starts it listening, and even that key goes on.
    #[test]
    fn an_idle_recorder_stops_no_key() {
        for key in every_key() {
            let plain_key = plain(&key);
            for k in std::iter::once(plain_key).chain(chords(&key)) {
                assert!(!recorder_stops_key(false, &k), "{k:?}");
                let expected = if activates(&k) {
                    RecorderKey::Listen
                } else {
                    RecorderKey::Pass
                };
                assert_eq!(recorder_key(false, &k, false), expected, "{k:?}");
                // A held key never starts it.
                assert_eq!(recorder_key(false, &k, true), RecorderKey::Pass, "{k:?}");
            }
        }
        assert_eq!(
            recorder_key(false, &plain("enter"), false),
            RecorderKey::Listen
        );
        assert_eq!(
            recorder_key(false, &plain("space"), false),
            RecorderKey::Listen
        );
    }

    /// A listening recorder uses every key-down, so it stops them all (no app command runs,
    /// Esc does not close Settings), except the ones Windows keeps: Alt+F4, Alt+Space and
    /// anything with the Windows key still reach Windows. It waits past a modifier alone and an
    /// auto-repeat, Esc ends it with nothing recorded, and the first other key is the chord,
    /// read through `Chord::of` as the keymap reads it, with `accept`'s verdict.
    #[test]
    fn a_listening_recorder_takes_one_chord_and_waits_past_modifiers() {
        let chord = |text: &str| Chord::parse(text).unwrap();
        let pressed = |k: KeyIn<'_>| recorder_key(true, &k, false);
        for key in every_key() {
            for (ctrl, alt, shift) in [
                (false, false, false),
                (true, false, false),
                (false, true, false),
                (false, false, true),
                (true, false, true),
                (false, true, true),
                (true, true, false),
            ] {
                let k = with(plain(&key), ctrl, alt, shift);
                let windows_keeps =
                    alt && !ctrl && !shift && matches!(key.as_str(), "f4" | "space");
                assert_eq!(recorder_stops_key(true, &k), !windows_keeps, "{k:?}");
            }
            let win = KeyIn {
                win: true,
                ..plain(&key)
            };
            assert!(!recorder_stops_key(true, &win), "{key}");
        }

        // A modifier alone (GPUI-Windows sends none, other platforms may) and an auto-repeat.
        for name in ["shift", "control", "alt", "platform", "capslock"] {
            let k = with(
                plain(name),
                name == "control",
                name == "alt",
                name == "shift",
            );
            assert_eq!(pressed(k), RecorderKey::Wait, "{name}");
        }
        assert_eq!(
            recorder_key(true, &with(plain("k"), true, false, false), true),
            RecorderKey::Wait
        );

        // Esc ends listening; with a modifier it is a chord like any other.
        assert_eq!(pressed(plain("escape")), RecorderKey::Cancel);
        assert_eq!(
            pressed(with(plain("escape"), true, false, false)),
            RecorderKey::Pressed(chord("ctrl+escape"), Ok(()))
        );
        assert_eq!(
            pressed(with(plain("escape"), false, false, true)),
            RecorderKey::Pressed(chord("shift+escape"), Err(Refused::NeedsModifier))
        );

        // The chord and why it may not be a shortcut.
        assert_eq!(
            pressed(with(plain("k"), true, false, true)),
            RecorderKey::Pressed(chord("ctrl+shift+k"), Ok(()))
        );
        assert_eq!(
            pressed(plain("f5")),
            RecorderKey::Pressed(chord("f5"), Ok(()))
        );
        assert_eq!(
            pressed(plain("a")),
            RecorderKey::Pressed(chord("a"), Err(Refused::NeedsModifier))
        );
        assert_eq!(
            pressed(plain("tab")),
            RecorderKey::Pressed(chord("tab"), Err(Refused::NeedsModifier))
        );
        assert_eq!(
            pressed(with(plain("a"), true, true, false)),
            RecorderKey::Pressed(chord("ctrl+alt+a"), Err(Refused::AltGr))
        );
        assert_eq!(
            pressed(with(plain("f4"), false, true, false)),
            RecorderKey::Pressed(chord("alt+f4"), Err(Refused::SystemKey))
        );
        assert_eq!(
            pressed(KeyIn {
                win: true,
                ..with(plain("k"), true, false, false)
            }),
            RecorderKey::Pressed(chord("ctrl+k"), Err(Refused::WindowsKey))
        );

        // GPUI-Windows' shapes: Alt+Shift+= arrives as Alt and "+", Ctrl+Shift+= as Ctrl and
        // "+". Recording reads them as matching does, and the label is what `label` gives.
        assert_eq!(
            pressed(with(plain("+"), false, true, false)),
            RecorderKey::Pressed(chord("alt+shift+="), Ok(()))
        );
        let ctrl_plus = Chord::of(&with(plain("+"), true, false, false));
        assert_eq!(
            pressed(with(plain("+"), true, false, false)),
            RecorderKey::Pressed(ctrl_plus.clone(), Ok(()))
        );
        assert_eq!(ctrl_plus.label(), "Ctrl++");
    }

    /// A recorder left listening would swallow the next keys, so it listens only while it has
    /// the keyboard in the active window: a click elsewhere that takes the focus, another
    /// section (the view takes the keyboard), Settings closing or going to the background
    /// each end it. An idle recorder never starts listening on its own.
    #[test]
    fn listening_ends_once_the_recorder_loses_the_keyboard() {
        assert!(still_listening(true, true, true));
        for (focused, active) in [(false, true), (true, false), (false, false)] {
            assert!(
                !still_listening(true, focused, active),
                "{focused} {active}"
            );
        }
        for (focused, active) in [(true, true), (false, true), (true, false), (false, false)] {
            assert!(
                !still_listening(false, focused, active),
                "{focused} {active}"
            );
        }
    }

    #[test]
    fn esc_in_a_number_field_restores_an_edit_and_otherwise_closes() {
        assert_eq!(number_escape("75", 50.0), NumberEsc::Restore);
        assert_eq!(number_escape("", 50.0), NumberEsc::Restore);
        assert_eq!(number_escape("50", 50.0), NumberEsc::Close);
    }

    #[test]
    fn closing_with_an_edit_in_a_number_field_commits_it_clamped() {
        assert_eq!(number_pending("75", 50.0, 0.0, 100_000.0), Some(75.0));
        assert_eq!(number_pending("999999", 50.0, 0.0, 100_000.0), Some(100_000.0));
        assert_eq!(number_pending("50", 50.0, 0.0, 100_000.0), None);
        assert_eq!(number_pending("", 50.0, 0.0, 100_000.0), None);
        // An edit that clamps to the stored value changes nothing.
        assert_eq!(number_pending("200000", 100_000.0, 0.0, 100_000.0), None);
    }
}
