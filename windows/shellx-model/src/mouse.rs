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
}
