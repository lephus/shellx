#[cfg(test)]
mod tests {
    use super::{HostKind, host_kind};

    #[test]
    fn only_panel_selects_the_panel_host() {
        for value in [None, Some(""), Some("window"), Some("1"), Some("panels")] {
            assert_eq!(host_kind(value), HostKind::Window, "{value:?}");
        }
        for value in [Some("panel"), Some(" Panel "), Some("PANEL")] {
            assert_eq!(host_kind(value), HostKind::Panel, "{value:?}");
        }
    }
}
