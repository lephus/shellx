//! The rules of the Settings controls (`shellx-app/src/ui/controls/`): where a slider's track
//! maps to a value, how a stepper moves, how the colour field reads a hex code, how a value is
//! written beside its control, and which keys each control uses.
//!
//! A control stops only the keys these functions name, and only while it has the keyboard:
//! on Windows a stopped key-down produces no WM_CHAR, so a control never takes a letter, a
//! digit, Tab or a chord.

use crate::keys::KeyIn;
use crate::palette::Rgba;
use crate::settings_catalog::Unit;

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
}
