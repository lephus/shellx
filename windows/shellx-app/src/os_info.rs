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
