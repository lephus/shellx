//! Facts about this machine sent to `config.set` / `machines.register`, and
//! the local UTC offset for "lần cuối HH:MM".
// The window (cfg(windows)) is the main user; the Mac build only tests it.
#![cfg_attr(not(windows), allow(dead_code))]

/// Windows version like `10.0.26100`, `"unknown"` when unreadable or off Windows.
pub fn os_version() -> String {
    #[cfg(windows)]
    {
        windows_version().unwrap_or_else(|| "unknown".to_string())
    }
    #[cfg(not(windows))]
    {
        "unknown".to_string()
    }
}

#[cfg(windows)]
fn windows_version() -> Option<String> {
    use winreg::RegKey;
    use winreg::enums::HKEY_LOCAL_MACHINE;
    let key = RegKey::predef(HKEY_LOCAL_MACHINE)
        .open_subkey(r"SOFTWARE\Microsoft\Windows NT\CurrentVersion")
        .ok()?;
    let major: u32 = key.get_value("CurrentMajorVersionNumber").ok()?;
    let minor: u32 = key.get_value("CurrentMinorVersionNumber").ok()?;
    let build: String = key.get_value("CurrentBuildNumber").ok()?;
    Some(format!("{major}.{minor}.{build}"))
}

/// The computer name, `"PC Windows"` when `COMPUTERNAME` is unset or empty.
pub fn device_name() -> String {
    device_name_from(std::env::var("COMPUTERNAME").ok())
}

fn device_name_from(value: Option<String>) -> String {
    match value.map(|v| v.trim().to_string()) {
        Some(v) if !v.is_empty() => v,
        _ => "PC Windows".to_string(),
    }
}

/// Seconds to add to UTC for local time now (Windows time zone, daylight
/// saving included); 0 when unknown or off Windows.
pub fn utc_offset_secs() -> i32 {
    #[cfg(windows)]
    {
        use windows_sys::Win32::System::Time::{GetTimeZoneInformation, TIME_ZONE_INFORMATION};
        let mut tz = TIME_ZONE_INFORMATION::default();
        // SAFETY: `tz` is a valid, writable TIME_ZONE_INFORMATION.
        let id = unsafe { GetTimeZoneInformation(&mut tz) };
        offset_from_tz(id, tz.Bias, tz.StandardBias, tz.DaylightBias)
    }
    #[cfg(not(windows))]
    {
        0
    }
}

/// The Windows display language as a LANGID (`GetUserDefaultUILanguage`,
/// 0x042A for vi-VN); `None` off Windows. `Lang::from_system` reads it.
pub fn ui_language_id() -> Option<u16> {
    #[cfg(windows)]
    {
        // SAFETY: takes no arguments and returns the id by value.
        Some(unsafe { windows_sys::Win32::Globalization::GetUserDefaultUILanguage() })
    }
    #[cfg(not(windows))]
    {
        None
    }
}

/// Whether a screen reader (Narrator, NVDA, JAWS) says it is running
/// (`SPI_GETSCREENREADER`; Narrator sets it while it runs). False off Windows
/// or when the query fails.
pub fn screen_reader_running() -> bool {
    #[cfg(windows)]
    {
        use windows_sys::Win32::UI::WindowsAndMessaging::{
            SPI_GETSCREENREADER, SystemParametersInfoW,
        };
        let mut on: windows_sys::core::BOOL = 0;
        // SAFETY: SPI_GETSCREENREADER writes one BOOL to `pvparam`, which
        // points at a live, writable BOOL.
        let ok = unsafe { SystemParametersInfoW(SPI_GETSCREENREADER, 0, (&raw mut on).cast(), 0) };
        ok != 0 && on != 0
    }
    #[cfg(not(windows))]
    {
        false
    }
}

/// `GetTimeZoneInformation` result -> seconds east of UTC. The biases are
/// minutes with UTC = local + bias; the id says which extra bias is in effect
/// (1 = TIME_ZONE_ID_STANDARD, 2 = TIME_ZONE_ID_DAYLIGHT, 0 = no DST rules,
/// u32::MAX = TIME_ZONE_ID_INVALID -> 0).
fn offset_from_tz(id: u32, bias: i32, standard_bias: i32, daylight_bias: i32) -> i32 {
    let extra = match id {
        0 => 0,
        1 => standard_bias,
        2 => daylight_bias,
        _ => return 0,
    };
    -(bias + extra) * 60
}

#[cfg(test)]
mod tests {
    #[test]
    fn utc_offset_from_biases() {
        // Viet Nam: UTC+7, no DST
        assert_eq!(offset_from_tz(0, -420, 0, 0), 7 * 3600);
        // US Pacific in summer: bias 480, daylight -60 -> UTC-7
        assert_eq!(offset_from_tz(2, 480, 0, -60), -7 * 3600);
        assert_eq!(offset_from_tz(1, 480, 0, -60), -8 * 3600);
        // India UTC+5:30
        assert_eq!(offset_from_tz(0, -330, 0, 0), 5 * 3600 + 1800);
        assert_eq!(offset_from_tz(u32::MAX, -420, 0, 0), 0);
        if cfg!(not(windows)) {
            assert_eq!(utc_offset_secs(), 0);
        }
    }

    use super::*;

    #[test]
    fn device_name_falls_back() {
        assert_eq!(device_name_from(None), "PC Windows");
        assert_eq!(device_name_from(Some("  ".into())), "PC Windows");
        assert_eq!(device_name_from(Some("DESKTOP-1".into())), "DESKTOP-1");
    }

    #[test]
    fn ui_language_id_is_known_only_on_windows() {
        if cfg!(not(windows)) {
            assert_eq!(ui_language_id(), None);
        } else {
            assert!(ui_language_id().is_some_and(|id| id != 0));
        }
    }

    #[test]
    fn the_first_window_is_placed_for_the_screens_of_r1() {
        use shellx_model::first_window::FirstWindow;
        let fw = |x, y, width, height, maximized| FirstWindow {
            x,
            y,
            width,
            height,
            maximized,
        };
        // 1920x1080 @150 %, taskbar at the bottom: rcWork 1920x1008 physical pixels
        assert_eq!(
            first_window_placement(Some((1920.0, 1008.0, 1.5))),
            fw(40.0, 0.0, 1200.0, 672.0, false)
        );
        // 1366x768 @100 %
        assert_eq!(
            first_window_placement(Some((1366.0, 720.0, 1.0))),
            fw(83.0, 0.0, 1200.0, 720.0, false)
        );
        // 2160x1440 @200 %
        assert_eq!(
            first_window_placement(Some((2160.0, 1344.0, 2.0))),
            fw(0.0, 0.0, 1080.0, 672.0, false)
        );
        // 2256x1504 @200 %
        assert_eq!(
            first_window_placement(Some((2256.0, 1408.0, 2.0))),
            fw(0.0, 0.0, 1128.0, 704.0, false)
        );
        // Taskbar on top: rcWork (0, 72)-(1920, 1080) at 144 dpi gives the first case; the
        // origin stays (0, 0) because GPUI places in workspace coordinates.
        let top = work_area_from_rect(0, 72, 1920, 1080, 144);
        assert_eq!(top, Some((1920.0, 1008.0, 1.5)));
        assert_eq!(
            first_window_placement(top),
            fw(40.0, 0.0, 1200.0, 672.0, false)
        );
        // An empty or inverted rectangle is no work area.
        assert_eq!(work_area_from_rect(0, 0, 0, 1080, 96), None);
        assert_eq!(work_area_from_rect(0, 1080, 1920, 0, 96), None);
        // Unknown: maximized.
        assert!(first_window_placement(None).maximized);
        if cfg!(not(windows)) {
            assert_eq!(primary_work_area(), None);
        }
    }

    #[test]
    fn os_version_is_never_empty() {
        let v = os_version();
        assert!(!v.is_empty());
        if cfg!(not(windows)) {
            assert_eq!(v, "unknown");
        } else {
            assert!(v.starts_with("10."), "{v}");
        }
    }
}
