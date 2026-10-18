//! Facts about this machine sent to `config.set` / `machines.register`.
#![allow(dead_code)] // used by the sign-in wiring (Task 10b)

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

#[cfg(test)]
mod tests {
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
