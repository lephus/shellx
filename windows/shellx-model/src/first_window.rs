//! First-window size rule: 1200x760 where it fits, shrunk to the work area where it does not.
//! All values are logical pixels: the monitor's work area divided by its scale.

/// The size the window prefers (logical pixels).
pub const PREFERRED: (f32, f32) = (1200.0, 760.0);
/// Below this size the window opens maximized instead.
pub const MINIMUM: (f32, f32) = (720.0, 420.0);

/// The work area (`MONITORINFO.rcWork`) of the monitor the window opens on.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct WorkArea {
    pub x: f32,
    pub y: f32,
    pub width: f32,
    pub height: f32,
}

/// Where and how large the first window opens.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct FirstWindow {
    pub x: f32,
    pub y: f32,
    pub width: f32,
    pub height: f32,
    pub maximized: bool,
}

fn valid_extent(v: f32) -> bool {
    v.is_finite() && v > 0.0
}

/// Shrinks 1200x760 to the work area, centres it with floored offsets, and asks for a
/// maximized window when the shrunk size is below 720x420 or the work area is unusable.
pub fn first_window(wa: WorkArea) -> FirstWindow {
    if !valid_extent(wa.width) || !valid_extent(wa.height) {
        return FirstWindow {
            x: if wa.x.is_finite() { wa.x } else { 0.0 },
            y: if wa.y.is_finite() { wa.y } else { 0.0 },
            width: PREFERRED.0,
            height: PREFERRED.1,
            maximized: true,
        };
    }
    let width = PREFERRED.0.min(wa.width);
    let height = PREFERRED.1.min(wa.height);
    FirstWindow {
        x: wa.x + ((wa.width - width) / 2.0).floor(),
        y: wa.y + ((wa.height - height) / 2.0).floor(),
        width,
        height,
        maximized: width < MINIMUM.0 || height < MINIMUM.1,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn fw(x: f32, y: f32, width: f32, height: f32, maximized: bool) -> FirstWindow {
        FirstWindow {
            x,
            y,
            width,
            height,
            maximized,
        }
    }
    fn wa(x: f32, y: f32, width: f32, height: f32) -> WorkArea {
        WorkArea {
            x,
            y,
            width,
            height,
        }
    }

    #[test]
    fn first_window_fits_the_four_screens_of_r1() {
        // 1920x1080 @150%
        assert_eq!(
            first_window(wa(0.0, 0.0, 1280.0, 672.0)),
            fw(40.0, 0.0, 1200.0, 672.0, false)
        );
        // 1366x768 @100%
        assert_eq!(
            first_window(wa(0.0, 0.0, 1366.0, 720.0)),
            fw(83.0, 0.0, 1200.0, 720.0, false)
        );
        // 2160x1440 @200%
        assert_eq!(
            first_window(wa(0.0, 0.0, 1080.0, 672.0)),
            fw(0.0, 0.0, 1080.0, 672.0, false)
        );
        // 2256x1504 @200%
        assert_eq!(
            first_window(wa(0.0, 0.0, 1128.0, 704.0)),
            fw(0.0, 0.0, 1128.0, 704.0, false)
        );
        // 3840x2160 @300%
        assert_eq!(
            first_window(wa(0.0, 0.0, 1280.0, 672.0)),
            fw(40.0, 0.0, 1200.0, 672.0, false)
        );
    }

    #[test]
    fn large_screens_keep_1200_by_760_centred() {
        // 1920x1080 @100%
        assert_eq!(
            first_window(wa(0.0, 0.0, 1920.0, 1032.0)),
            fw(360.0, 136.0, 1200.0, 760.0, false)
        );
        // @125%
        assert_eq!(
            first_window(wa(0.0, 0.0, 1536.0, 816.0)),
            fw(168.0, 28.0, 1200.0, 760.0, false)
        );
    }

    #[test]
    fn first_window_stays_inside_a_work_area_that_does_not_start_at_zero() {
        // taskbar on the left
        assert_eq!(
            first_window(wa(48.0, 0.0, 1232.0, 720.0)),
            fw(64.0, 0.0, 1200.0, 720.0, false)
        );
        // a monitor left of the primary
        assert_eq!(
            first_window(wa(-1920.0, 0.0, 1920.0, 1032.0)),
            fw(-1560.0, 136.0, 1200.0, 760.0, false)
        );
        // taskbar on top
        assert_eq!(
            first_window(wa(0.0, 48.0, 1280.0, 672.0)),
            fw(40.0, 48.0, 1200.0, 672.0, false)
        );
    }

    #[test]
    fn small_screens_shrink_or_open_maximized() {
        assert_eq!(
            first_window(wa(0.0, 0.0, 800.0, 560.0)),
            fw(0.0, 0.0, 800.0, 560.0, false)
        );
        assert_eq!(
            first_window(wa(0.0, 0.0, 640.0, 440.0)),
            fw(0.0, 0.0, 640.0, 440.0, true)
        );
        // fractional 1366x768 @125%
        assert_eq!(
            first_window(wa(0.0, 0.0, 1092.8, 566.4)),
            fw(0.0, 0.0, 1092.8, 566.4, false)
        );
        // too short rather than too narrow
        assert!(first_window(wa(0.0, 0.0, 1280.0, 400.0)).maximized);
    }

    #[test]
    fn a_broken_work_area_opens_maximized() {
        for (w, h) in [
            (0.0, 700.0),
            (1280.0, 0.0),
            (-5.0, 700.0),
            (1280.0, -1.0),
            (f32::NAN, 700.0),
            (1280.0, f32::NAN),
            (f32::INFINITY, 700.0),
            (1280.0, f32::NEG_INFINITY),
        ] {
            let r = first_window(wa(10.0, 20.0, w, h));
            assert!(r.maximized, "{w} x {h}");
            assert_eq!((r.width, r.height), (1200.0, 760.0), "{w} x {h}");
            assert_eq!((r.x, r.y), (10.0, 20.0), "{w} x {h}");
        }
        let r = first_window(wa(f32::NAN, f32::INFINITY, 0.0, 0.0));
        assert_eq!((r.x, r.y, r.maximized), (0.0, 0.0, true));
    }
}
