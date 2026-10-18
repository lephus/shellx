//! `version.check` result -> update status and banner.

use crate::core_api::{CoreErr, VersionInfo};
use crate::strings::{Lang, Str, t, update_available};

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum UpdateStatus {
    UpToDate,
    Available {
        version: String,
        url: Option<String>,
    },
    Required {
        min: String,
        url: Option<String>,
    },
    Unknown,
}

pub fn from_version_info(info: &VersionInfo) -> UpdateStatus {
    match info.status.as_str() {
        "ok" => UpdateStatus::UpToDate,
        "update_available" => match &info.latest_version {
            Some(v) => UpdateStatus::Available {
                version: v.clone(),
                url: info.download_url.clone(),
            },
            None => UpdateStatus::Unknown,
        },
        "update_required" => match &info.min_version {
            Some(v) => UpdateStatus::Required {
                min: v.clone(),
                url: info.download_url.clone(),
            },
            None => UpdateStatus::Unknown,
        },
        _ => UpdateStatus::Unknown,
    }
}

/// Errors never block the app (offline use).
pub fn from_result(r: Result<VersionInfo, CoreErr>) -> UpdateStatus {
    r.map_or(UpdateStatus::Unknown, |i| from_version_info(&i))
}

/// `version.check` runs at startup and then every 6 hours.
pub const CHECK_INTERVAL_SECS: u64 = 6 * 60 * 60;

/// Only `https://` download links are ever opened.
pub fn is_https(url: &str) -> bool {
    url.len() > "https://".len()
        && url
            .get(.."https://".len())
            .is_some_and(|p| p.eq_ignore_ascii_case("https://"))
        && !url.chars().any(|c| c.is_control() || c.is_whitespace())
}

/// The URL the Download button opens: the status' link when it is https.
pub fn download_url(status: &UpdateStatus) -> Option<&str> {
    match status {
        UpdateStatus::Available { url, .. } | UpdateStatus::Required { url, .. } => {
            url.as_deref().filter(|u| is_https(u))
        }
        UpdateStatus::UpToDate | UpdateStatus::Unknown => None,
    }
}

pub fn banner(status: &UpdateStatus, lang: Lang) -> Option<String> {
    match status {
        UpdateStatus::Available { version, .. } => Some(update_available(lang, version)),
        UpdateStatus::Required { .. } => Some(t(lang, Str::UpdateRequired).to_string()),
        UpdateStatus::UpToDate | UpdateStatus::Unknown => None,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn info(
        status: &str,
        min: Option<&str>,
        latest: Option<&str>,
        url: Option<&str>,
    ) -> VersionInfo {
        VersionInfo {
            status: status.into(),
            min_version: min.map(Into::into),
            latest_version: latest.map(Into::into),
            download_url: url.map(Into::into),
        }
    }

    #[test]
    fn each_status() {
        assert_eq!(
            from_version_info(&info("ok", None, None, None)),
            UpdateStatus::UpToDate
        );
        assert_eq!(
            from_version_info(&info(
                "update_available",
                None,
                Some("2.0.1"),
                Some("https://d")
            )),
            UpdateStatus::Available {
                version: "2.0.1".into(),
                url: Some("https://d".into())
            }
        );
        assert_eq!(
            from_version_info(&info("update_required", Some("2.0.0"), Some("2.0.1"), None)),
            UpdateStatus::Required {
                min: "2.0.0".into(),
                url: None
            }
        );
    }

    #[test]
    fn unknown_status_or_missing_version() {
        assert_eq!(
            from_version_info(&info("weird", None, None, None)),
            UpdateStatus::Unknown
        );
        assert_eq!(
            from_version_info(&info("update_available", None, None, None)),
            UpdateStatus::Unknown
        );
        assert_eq!(
            from_version_info(&info("update_required", None, Some("1"), None)),
            UpdateStatus::Unknown
        );
    }

    #[test]
    fn error_is_unknown() {
        assert_eq!(
            from_result(Err(CoreErr::new("network", "x"))),
            UpdateStatus::Unknown
        );
        assert_eq!(
            from_result(Ok(info("ok", None, None, None))),
            UpdateStatus::UpToDate
        );
    }

    #[test]
    fn https_only() {
        assert!(is_https("https://shellx.pro/download"));
        assert!(is_https("HTTPS://shellx.pro"));
        assert!(!is_https("http://shellx.pro"));
        assert!(!is_https("https://"));
        assert!(!is_https("file:///C:/x.exe"));
        assert!(!is_https("javascript:alert(1)"));
        assert!(!is_https(" https://x"));
        assert!(!is_https("https://x y"));
        assert!(!is_https("https://x\n"));
        assert!(!is_https(""));
        assert!(!is_https("ttps://é"));
    }

    #[test]
    fn download_url_needs_https() {
        let ok = UpdateStatus::Available {
            version: "2.0.1".into(),
            url: Some("https://d".into()),
        };
        assert_eq!(download_url(&ok), Some("https://d"));
        let bad = UpdateStatus::Required {
            min: "2.0.1".into(),
            url: Some("http://d".into()),
        };
        assert_eq!(download_url(&bad), None);
        assert_eq!(download_url(&UpdateStatus::UpToDate), None);
        assert_eq!(CHECK_INTERVAL_SECS, 21_600);
    }

    #[test]
    fn banner_text() {
        let a = UpdateStatus::Available {
            version: "2.0.1".into(),
            url: None,
        };
        assert_eq!(
            banner(&a, Lang::Vi).as_deref(),
            Some("Có bản cập nhật 2.0.1")
        );
        assert_eq!(
            banner(&a, Lang::En).as_deref(),
            Some("Update available: 2.0.1")
        );
        let r = UpdateStatus::Required {
            min: "2.0.0".into(),
            url: None,
        };
        assert_eq!(banner(&r, Lang::Vi).as_deref(), Some("Cần cập nhật"));
        assert_eq!(banner(&UpdateStatus::UpToDate, Lang::Vi), None);
        assert_eq!(banner(&UpdateStatus::Unknown, Lang::En), None);
    }
}
