//! What this build is: version, commit, test label and kind (spec §4.6, Ruling 25).

#[cfg(test)]
mod tests {
    use super::*;

    const C40: &str = "5dd1e2dc6a0123456789abcdef0123456789abcd";

    #[test]
    fn build_info_validates_label_and_commit() {
        assert_eq!(label_from(Some("test")), Some("test"));
        assert_eq!(label_from(Some("abcdefghij")), Some("abcdefghij"));
        assert_eq!(label_from(Some("t1")), Some("t1"));
        for bad in ["Test", "test-1", "abcdefghijk", "", "1test", " test", "tếst"] {
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
