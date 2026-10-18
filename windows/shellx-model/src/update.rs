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
