//! Mouse rules: touchpad scroll accumulation and what the wheel does on each screen.

/// Most lines one wheel event may scroll.
const MAX_LINES_PER_EVENT: f64 = 1000.0;
/// Float noise allowed when a sum of small steps lands just under a whole line.
const TOLERANCE: f64 = 1e-6;

/// Turns the fractional line deltas GPUI-Windows reports (a notch is 3.0 lines, a touchpad
/// message 0.2 or 0.75) into whole lines. One per pane. `lines > 0` means toward history.
#[derive(Clone, Copy, Debug, Default)]
pub struct ScrollAccumulator {
    remainder: f64,
}

impl ScrollAccumulator {
    /// Adds a delta and returns the whole lines to scroll now (0 when still collecting).
    /// A change of direction drops the remainder; non-finite and zero input is ignored.
    pub fn add(&mut self, lines: f64) -> i32 {
        if !lines.is_finite() || lines == 0.0 {
            return 0;
        }
        if self.remainder != 0.0 && self.remainder.signum() != lines.signum() {
            self.remainder = 0.0;
        }
        self.remainder += lines;
        let whole = (self.remainder + self.remainder.signum() * TOLERANCE).trunc();
        self.remainder -= whole;
        if whole.abs() > MAX_LINES_PER_EVENT {
            self.remainder = 0.0;
            return (whole.clamp(-MAX_LINES_PER_EVENT, MAX_LINES_PER_EVENT)) as i32;
        }
        whole as i32
    }
}

/// The screen state of a pane that decides what the wheel does.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct ScreenModes {
    pub alternate: bool,
    pub mouse_reporting: bool,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum WheelAction {
    None,
    /// Scroll the history by this many lines (positive = toward older lines).
    Scrollback(i32),
    /// Send the cursor key `count` times; `key` is a libghostty chord name.
    Arrows {
        key: &'static str,
        count: u32,
    },
}

/// The primary screen always scrolls back. A full-screen program (alternate screen) gets
/// arrow keys, unless it asks for mouse reporting: ShellX does not encode mouse events, so
/// the wheel then does nothing.
pub fn wheel_action(lines: i32, modes: ScreenModes) -> WheelAction {
    if lines == 0 {
        return WheelAction::None;
    }
    if !modes.alternate {
        return WheelAction::Scrollback(lines);
    }
    if modes.mouse_reporting {
        return WheelAction::None;
    }
    WheelAction::Arrows {
        key: if lines > 0 { "up" } else { "down" },
        count: lines.unsigned_abs(),
    }
}

/// At most one screen (`rows`, at least 1) per wheel event. Windows' "scroll one screen at a
/// time" setting reaches GPUI as billions of lines a notch: that becomes one screen of history
/// or `rows` arrow keys, never a thousand writes to the program.
pub fn cap_to_screen(action: WheelAction, rows: u16) -> WheelAction {
    let rows = rows.max(1);
    match action {
        WheelAction::None => WheelAction::None,
        WheelAction::Scrollback(lines) => {
            WheelAction::Scrollback(lines.clamp(-i32::from(rows), i32::from(rows)))
        }
        WheelAction::Arrows { key, count } => WheelAction::Arrows {
            key,
            count: count.min(u32::from(rows)),
        },
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum SecondaryButton {
    Right,
    Middle,
}

/// What a click on a pane does.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum PaneClick {
    /// Only move the focus to the pane.
    FocusOnly,
    Paste,
    CopySelection,
    Nothing,
}

/// Right and middle clicks as in the Windows console. A click on an unfocused pane only
/// focuses it. On the focused pane the right button copies the selection, or pastes when
/// there is none; the middle button pastes while `middle_pastes` (Settings › Terminal ›
/// Middle-Click Paste) is on, and does nothing otherwise.
pub fn secondary_click(
    button: SecondaryButton,
    pane_focused: bool,
    has_selection: bool,
    middle_pastes: bool,
) -> PaneClick {
    if !pane_focused {
        return PaneClick::FocusOnly;
    }
    match button {
        SecondaryButton::Right if has_selection => PaneClick::CopySelection,
        SecondaryButton::Right => PaneClick::Paste,
        SecondaryButton::Middle if middle_pastes => PaneClick::Paste,
        SecondaryButton::Middle => PaneClick::Nothing,
    }
}

/// A wheel or touchpad distance in lines, times the Scroll Speed setting. Applied before the
/// fractional accumulator, so 0.25x of 4 lines collects to exactly one line.
pub fn scaled_scroll(lines: f64, speed: f32) -> f64 {
    lines * f64::from(speed)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_wheel_notch_scrolls_three_lines() {
        let mut a = ScrollAccumulator::default();
        assert_eq!(a.add(3.0), 3);
        assert_eq!(a.add(3.0), 3);
        assert_eq!(a.add(-3.0), -3);
    }

    #[test]
    fn touchpad_steps_add_up() {
        let mut a = ScrollAccumulator::default();
        let got: Vec<i32> = (0..5).map(|_| a.add(0.2)).collect();
        assert_eq!(got, [0, 0, 0, 0, 1]);

        let mut a = ScrollAccumulator::default();
        let got: Vec<i32> = (0..4).map(|_| a.add(0.75)).collect();
        assert_eq!(got, [0, 1, 1, 1]);

        let mut a = ScrollAccumulator::default();
        let sum: i32 = (0..40).map(|_| a.add(0.2)).sum();
        assert_eq!(sum, 8);
    }

    #[test]
    fn a_change_of_direction_drops_the_remainder() {
        let mut a = ScrollAccumulator::default();
        assert_eq!(a.add(0.6), 0);
        assert_eq!(a.add(-0.2), 0);
        assert_eq!(a.add(-0.9), -1);
    }

    #[test]
    fn odd_deltas_never_panic() {
        let mut a = ScrollAccumulator::default();
        assert_eq!(a.add(0.6), 0);
        assert_eq!(a.add(f64::NAN), 0);
        assert_eq!(a.add(f64::INFINITY), 0);
        assert_eq!(a.add(f64::NEG_INFINITY), 0);
        assert_eq!(a.add(0.6), 1); // the first 0.6 survived

        let mut a = ScrollAccumulator::default();
        assert_eq!(a.add(1e12), 1000);
        assert_eq!(a.add(0.5), 0); // the remainder was dropped
        assert_eq!(a.add(-1e12), -1000);
    }

    #[test]
    fn the_wheel_scrolls_back_on_the_primary_screen() {
        for mouse_reporting in [false, true] {
            let modes = ScreenModes {
                alternate: false,
                mouse_reporting,
            };
            assert_eq!(wheel_action(3, modes), WheelAction::Scrollback(3));
            assert_eq!(wheel_action(-2, modes), WheelAction::Scrollback(-2));
        }
    }

    #[test]
    fn the_wheel_sends_arrows_in_full_screen_programs() {
        let plain = ScreenModes {
            alternate: true,
            mouse_reporting: false,
        };
        assert_eq!(
            wheel_action(3, plain),
            WheelAction::Arrows {
                key: "up",
                count: 3
            }
        );
        assert_eq!(
            wheel_action(-2, plain),
            WheelAction::Arrows {
                key: "down",
                count: 2
            }
        );
        let reporting = ScreenModes {
            alternate: true,
            mouse_reporting: true,
        };
        assert_eq!(wheel_action(3, reporting), WheelAction::None);
        for alternate in [false, true] {
            for mouse_reporting in [false, true] {
                let modes = ScreenModes {
                    alternate,
                    mouse_reporting,
                };
                assert_eq!(wheel_action(0, modes), WheelAction::None);
            }
        }
        // the most negative count must not overflow
        assert_eq!(
            wheel_action(i32::MIN, plain),
            WheelAction::Arrows {
                key: "down",
                count: i32::MIN.unsigned_abs()
            }
        );
    }

    #[test]
    fn one_wheel_event_moves_at_most_one_screen() {
        // Windows' "scroll one screen at a time" makes a notch billions of lines
        // (review M8): never more than the pane's rows of history or arrow keys.
        assert_eq!(
            cap_to_screen(WheelAction::Scrollback(1000), 24),
            WheelAction::Scrollback(24)
        );
        assert_eq!(
            cap_to_screen(WheelAction::Scrollback(-1000), 24),
            WheelAction::Scrollback(-24)
        );
        assert_eq!(
            cap_to_screen(
                WheelAction::Arrows {
                    key: "up",
                    count: 1000
                },
                24
            ),
            WheelAction::Arrows {
                key: "up",
                count: 24
            }
        );
        // ordinary steps are untouched
        assert_eq!(
            cap_to_screen(WheelAction::Scrollback(3), 24),
            WheelAction::Scrollback(3)
        );
        let three = WheelAction::Arrows {
            key: "down",
            count: 3,
        };
        assert_eq!(cap_to_screen(three, 24), three);
        assert_eq!(cap_to_screen(WheelAction::None, 24), WheelAction::None);
        // a pane not measured yet still moves one line
        assert_eq!(
            cap_to_screen(WheelAction::Scrollback(-5), 0),
            WheelAction::Scrollback(-1)
        );
    }

    #[test]
    fn secondary_clicks_follow_the_windows_console() {
        for button in [SecondaryButton::Right, SecondaryButton::Middle] {
            for has_selection in [false, true] {
                for middle in [false, true] {
                    assert_eq!(
                        secondary_click(button, false, has_selection, middle),
                        PaneClick::FocusOnly,
                        "{button:?} {has_selection} {middle}"
                    );
                }
            }
        }
        assert_eq!(
            secondary_click(SecondaryButton::Right, true, true, false),
            PaneClick::CopySelection
        );
        assert_eq!(
            secondary_click(SecondaryButton::Right, true, false, false),
            PaneClick::Paste
        );
        // the right button ignores the middle-click setting
        assert_eq!(
            secondary_click(SecondaryButton::Right, true, false, true),
            PaneClick::Paste
        );
    }

    #[test]
    fn middle_click_pastes_only_when_on_and_the_pane_has_focus() {
        for has_selection in [false, true] {
            assert_eq!(
                secondary_click(SecondaryButton::Middle, true, has_selection, true),
                PaneClick::Paste
            );
            assert_eq!(
                secondary_click(SecondaryButton::Middle, true, has_selection, false),
                PaneClick::Nothing
            );
            // the first click on an unfocused pane only focuses it
            assert_eq!(
                secondary_click(SecondaryButton::Middle, false, has_selection, true),
                PaneClick::FocusOnly
            );
        }
    }

    #[test]
    fn scroll_speed_scales_before_accumulating() {
        let mut a = ScrollAccumulator::default();
        assert_eq!(a.add(scaled_scroll(4.0, 0.25)), 1);
        let mut a = ScrollAccumulator::default();
        assert_eq!(a.add(scaled_scroll(3.0, 2.0)), 6);
        // 0.25x of a 3-line notch collects over several notches instead of rounding to 0
        let mut a = ScrollAccumulator::default();
        let got: Vec<i32> = (0..4).map(|_| a.add(scaled_scroll(3.0, 0.25))).collect();
        assert_eq!(got, [0, 1, 1, 1]);
        // direction and the neutral speed are kept; odd input stays odd for the accumulator
        assert_eq!(scaled_scroll(-3.0, 1.0), -3.0);
        assert!(scaled_scroll(f64::NAN, 2.0).is_nan());
    }
}
