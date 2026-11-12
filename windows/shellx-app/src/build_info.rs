//! What this build is: version, commit, test label and kind (spec §4.6, Ruling 25). The
//! label and commit are read at compile time (`SHELLX_BUILD_LABEL`, `SHELLX_BUILD_COMMIT`,
//! else `CMUX_TUI_BUILD_COMMIT`, which the cross build sets); a value of the wrong shape is
//! ignored. The version inside the app stays `x.y.z`.

use std::sync::OnceLock;

/// The test label: a lower-case letter, then up to 9 lower-case letters or digits.
pub(crate) fn label_from(value: Option<&str>) -> Option<&str> {
    let v = value?;
    let mut chars = v.chars();
    let first_ok = chars.next().is_some_and(|c| c.is_ascii_lowercase());
    let rest_ok = chars.all(|c| c.is_ascii_lowercase() || c.is_ascii_digit());
    (first_ok && rest_ok && v.len() <= 10).then_some(v)
}

/// The first of the two values that is a full commit (40 hex digits).
pub(crate) fn commit_from<'a>(
    shellx: Option<&'a str>,
    cmux_tui: Option<&'a str>,
) -> Option<&'a str> {
    let full = |v: &&str| v.len() == 40 && v.bytes().all(|b| b.is_ascii_hexdigit());
    shellx.filter(full).or(cmux_tui.filter(full))
}

/// `ShellX 1.7.0 (test 5dd1e2dc6a)` with a label; `ShellX 1.7.0 (test)` with a label and no
/// commit; `ShellX 1.7.0` without a label, commit or not (the commit is in the report's
/// `[app]` section; plan review M-24).
pub(crate) fn about_version_from(
    version: &str,
    label: Option<&str>,
    commit: Option<&str>,
) -> String {
    match (label, commit) {
        (Some(label), Some(commit)) => {
            let short = commit.get(..10).unwrap_or(commit);
            format!("ShellX {version} ({label} {short})")
        }
        (Some(label), None) => format!("ShellX {version} ({label})"),
        (None, _) => format!("ShellX {version}"),
    }
}

/// `release` or `debug`, plus ` <label>` for a test build.
pub(crate) fn build_kind_from(release: bool, label: Option<&str>) -> String {
    let kind = if release { "release" } else { "debug" };
    match label {
        Some(label) => format!("{kind} {label}"),
        None => kind.to_string(),
    }
}

/// The commit this exe was built from, when the build said it.
pub fn commit() -> Option<&'static str> {
    commit_from(
        option_env!("SHELLX_BUILD_COMMIT"),
        option_env!("CMUX_TUI_BUILD_COMMIT"),
    )
}

/// The test label, when this is a test build.
pub fn label() -> Option<&'static str> {
    label_from(option_env!("SHELLX_BUILD_LABEL"))
}

/// `release`, `debug`, or either plus ` <label>`.
pub fn build_kind() -> &'static str {
    static KIND: OnceLock<String> = OnceLock::new();
    KIND.get_or_init(|| build_kind_from(!cfg!(debug_assertions), label()))
}

/// The name and version Settings › About, the start log line and reports show.
pub fn about_version() -> String {
    about_version_from(shellx_model::VERSION, label(), commit())
}

#[cfg(test)]
mod tests {
    use super::*;

    const C40: &str = "5dd1e2dc6a0123456789abcdef0123456789abcd";

    #[test]
    fn build_info_validates_label_and_commit() {
        assert_eq!(label_from(Some("test")), Some("test"));
        assert_eq!(label_from(Some("abcdefghij")), Some("abcdefghij"));
        assert_eq!(label_from(Some("t1")), Some("t1"));
        for bad in [
            "Test",
            "test-1",
            "abcdefghijk",
            "",
            "1test",
            " test",
            "tếst",
        ] {
            assert_eq!(label_from(Some(bad)), None, "{bad:?}");
        }
        assert_eq!(label_from(None), None);

        assert_eq!(commit_from(Some(C40), None), Some(C40));
        assert_eq!(commit_from(Some(&C40[..39]), None), None);
        assert_eq!(commit_from(Some("g".repeat(40).as_str()), None), None);
        assert_eq!(commit_from(None, Some(C40)), Some(C40));
        assert_eq!(commit_from(Some(&C40[..39]), Some(C40)), Some(C40));
        assert_eq!(commit_from(None, None), None);

        assert_eq!(
            about_version_from("1.7.0", Some("test"), Some(C40)),
            "ShellX 1.7.0 (test 5dd1e2dc6a)"
        );
        assert_eq!(about_version_from("1.7.0", None, Some(C40)), "ShellX 1.7.0");
        assert_eq!(about_version_from("1.7.0", None, None), "ShellX 1.7.0");
        assert_eq!(
            about_version_from("1.7.0", Some("test"), None),
            "ShellX 1.7.0 (test)"
        );

        assert_eq!(build_kind_from(true, Some("test")), "release test");
        assert_eq!(build_kind_from(true, None), "release");
        assert_eq!(build_kind_from(false, None), "debug");

        // This build: no label or commit is set for `cargo test`, or valid ones are.
        assert!(about_version().starts_with("ShellX 1.7.0"));
        assert!(build_kind().starts_with("release") || build_kind().starts_with("debug"));
    }
}
