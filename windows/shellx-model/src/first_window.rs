//! First-window size rule: 1200x760 where it fits, shrunk to the work area where it does not.
//! All values are logical pixels: the monitor's work area divided by its scale.

/// The size the window prefers (logical pixels).
pub const PREFERRED: (f32, f32) = (1200.0, 760.0);
/// Below this size the window opens maximized instead.
pub const MINIMUM: (f32, f32) = (720.0, 420.0);

/// The area the window may use, in logical pixels, in the frame the caller's window API
/// expects.
///
/// GPUI 0.2.2 opens a window with `SetWindowPlacement`, whose rectangle is in *workspace*
/// coordinates: (0, 0) is the top-left corner of the primary monitor's work area, not of the
/// screen. So the values passed here for the primary monitor start at (0, 0) whatever side
/// the taskbar is on (`primary_workspace`); passing `rcWork` in screen coordinates would push
/// the window down by the height of a top taskbar or right by the width of a left one.
/// `first_window` itself only works inside the frame it is given.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct WorkArea {
    pub x: f32,
    pub y: f32,
    pub width: f32,
    pub height: f32,
}

impl WorkArea {
    /// The primary monitor's work area in workspace coordinates: the origin is (0, 0) and the
    /// size is the work area's physical pixels (`rcWork.right - left`, `bottom - top`)
    /// divided by the monitor's scale (1.5 for 150 %). A scale that is not finite or not above
    /// zero counts as 1.0.
    pub fn primary_workspace(width_px: f32, height_px: f32, scale: f32) -> WorkArea {
        let _ = scale;
        WorkArea {
            x: 0.0,
            y: 0.0,
            width: width_px,
            height: height_px,
        }
    }
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
/// maximized window when the shrunk size is below 720x420 or the work area is unusable. The
/// result is in the same frame as `wa` (for GPUI on Windows: workspace coordinates, see
/// `WorkArea`) and in logical pixels.
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

    // `MONITORINFO.rcWork` (screen coordinates: left, top, right, bottom) of the primary monitor.
    fn workspace(left: f32, top: f32, right: f32, bottom: f32, scale: f32) -> WorkArea {
        WorkArea::primary_workspace(right - left, bottom - top, scale)
    }

    #[test]
    fn the_taskbar_side_does_not_move_the_window_in_workspace_coordinates() {
        // 1920x1080 @150 %, a 48 px taskbar at the bottom, on top, and on the left (the work
        // area is then 1872 wide). The origin of rcWork differs, the workspace frame does not.
        let bottom = first_window(workspace(0.0, 0.0, 1920.0, 1032.0, 1.5));
        let top = first_window(workspace(0.0, 48.0, 1920.0, 1080.0, 1.5));
        let left = first_window(workspace(48.0, 0.0, 1920.0, 1080.0, 1.5));
        assert_eq!(bottom, fw(40.0, 0.0, 1200.0, 688.0, false));
        assert_eq!(top, bottom);
        assert_eq!(left, fw(24.0, 0.0, 1200.0, 720.0, false));
        // R1's screen: 1920x1080 @150 %, work area 1920x1008 -> 1280x672
        assert_eq!(
            workspace(0.0, 0.0, 1920.0, 1008.0, 1.5),
            wa(0.0, 0.0, 1280.0, 672.0)
        );
        assert_eq!(
            first_window(workspace(0.0, 0.0, 1920.0, 1008.0, 1.5)),
            fw(40.0, 0.0, 1200.0, 672.0, false)
        );
        // the same screen with the taskbar on top
        assert_eq!(
            first_window(workspace(0.0, 72.0, 1920.0, 1080.0, 1.5)),
            fw(40.0, 0.0, 1200.0, 672.0, false)
        );
    }

    #[test]
    fn a_workspace_window_never_has_a_negative_origin() {
        for scale in [
            1.0,
            1.25,
            1.5,
            1.75,
            2.0,
            2.5,
            3.0,
            0.0,
            -1.0,
            f32::NAN,
            f32::INFINITY,
        ] {
            for (w, h) in [
                (1920.0, 1032.0),
                (1366.0, 720.0),
                (1280.0, 400.0),
                (800.0, 560.0),
                (640.0, 440.0),
                (0.0, 0.0),
                (-10.0, 500.0),
                (f32::NAN, 700.0),
            ] {
                let r = first_window(WorkArea::primary_workspace(w, h, scale));
                assert!(r.x >= 0.0 && r.y >= 0.0, "{w}x{h} @{scale}: {r:?}");
                assert!(
                    r.x.is_finite() && r.y.is_finite(),
                    "{w}x{h} @{scale}: {r:?}"
                );
            }
        }
    }

    #[test]
    fn a_bad_scale_counts_as_one() {
        for scale in [0.0, -2.0, f32::NAN, f32::INFINITY, f32::NEG_INFINITY] {
            assert_eq!(
                WorkArea::primary_workspace(1280.0, 720.0, scale),
                wa(0.0, 0.0, 1280.0, 720.0),
                "{scale}"
            );
        }
        assert_eq!(
            WorkArea::primary_workspace(2160.0, 1344.0, 2.0),
            wa(0.0, 0.0, 1080.0, 672.0)
        );
    }
}
