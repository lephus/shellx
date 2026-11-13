#[cfg(test)]
mod tests {
    use super::*;
    use crate::keys::KeyIn;

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
        (0..=n)
            .map(|k| stepped(min, k, min, max, step))
            .collect()
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
        let named = ["tab", "backspace", "delete", "home", "end", "pageup", "pagedown", "f2"]
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
