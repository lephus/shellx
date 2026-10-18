//! Embedded icons: the 20 coolicons v4.1 SVGs (CC BY 4.0, Kryston Schwarze)
//! plus the ShellX logo. GPUI-free, so the `--smoke-ui-assets` check and the
//! window's `AssetSource` (ui/assets.rs) share one table.
//!
//! Every coolicon draws with `stroke="currentColor"`; `gpui::svg()` renders
//! an SVG to an alpha mask and tints it with the element's text color, so no
//! file needed normalizing. The logo keeps its own gradient and is drawn with
//! `gpui::img()` (full color), never tinted.

#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum Icon {
    AddPlus,
    BellRing,
    ChevronDown,
    CircleCheck,
    Cloud,
    Command,
    Data,
    Desktop,
    Laptop,
    Link,
    Mobile,
    MoreHorizontal,
    QrCode,
    Search,
    Settings,
    Share,
    ShieldCheck,
    Terminal,
    Users,
    WindowSidebar,
    Logo,
}

macro_rules! icon_table {
    ($($variant:ident => $file:literal),* $(,)?) => {
        impl Icon {
            pub const ALL: &'static [Icon] = &[$(Icon::$variant),*];

            /// Asset path, as passed to `svg().path(..)` / the asset source.
            pub fn path(self) -> &'static str {
                match self {
                    $(Icon::$variant => concat!("icons/", $file),)*
                }
            }

            /// The embedded SVG bytes.
            pub fn bytes(self) -> &'static [u8] {
                match self {
                    $(Icon::$variant => include_bytes!(concat!("../assets/icons/", $file)),)*
                }
            }
        }
    };
}

icon_table! {
    AddPlus => "add_plus.svg",
    BellRing => "bell_ring.svg",
    ChevronDown => "chevron_down.svg",
    CircleCheck => "circle_check.svg",
    Cloud => "cloud.svg",
    Command => "command.svg",
    Data => "data.svg",
    Desktop => "desktop.svg",
    Laptop => "laptop.svg",
    Link => "link.svg",
    Mobile => "mobile.svg",
    MoreHorizontal => "more_horizontal.svg",
    QrCode => "qr_code.svg",
    Search => "search.svg",
    Settings => "settings.svg",
    Share => "share.svg",
    ShieldCheck => "shield_check.svg",
    Terminal => "terminal.svg",
    Users => "users.svg",
    WindowSidebar => "window_sidebar.svg",
    Logo => "logo.svg",
}

/// Bytes for an asset path (what GPUI's asset source is asked for).
pub fn by_path(path: &str) -> Option<&'static [u8]> {
    Icon::ALL
        .iter()
        .find(|icon| icon.path() == path)
        .map(|icon| icon.bytes())
}

/// Asset paths under `prefix` (GPUI's `AssetSource::list`).
#[cfg_attr(not(windows), allow(dead_code))]
pub fn list(prefix: &str) -> Vec<&'static str> {
    Icon::ALL
        .iter()
        .map(|icon| icon.path())
        .filter(|path| path.starts_with(prefix))
        .collect()
}

/// True when `data` is an SVG document: after optional whitespace, an XML
/// declaration and comments, it opens with `<svg`, and it has a `viewBox`.
pub fn looks_like_svg(data: &[u8]) -> bool {
    let Ok(text) = std::str::from_utf8(data) else {
        return false;
    };
    let mut rest = text.trim_start_matches('\u{feff}');
    loop {
        rest = rest.trim_start();
        if let Some(after) = rest.strip_prefix("<?xml") {
            let Some(end) = after.find("?>") else {
                return false;
            };
            rest = &after[end + 2..];
        } else if let Some(after) = rest.strip_prefix("<!--") {
            let Some(end) = after.find("-->") else {
                return false;
            };
            rest = &after[end + 3..];
        } else {
            break;
        }
    }
    rest.starts_with("<svg") && rest.contains("viewBox")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn every_icon_is_an_embedded_svg() {
        assert_eq!(Icon::ALL.len(), 21);
        for icon in Icon::ALL {
            assert!(looks_like_svg(icon.bytes()), "{icon:?} is not an SVG");
            assert_eq!(by_path(icon.path()), Some(icon.bytes()), "{icon:?}");
        }
    }

    #[test]
    fn paths_are_unique_and_listed() {
        let mut paths: Vec<&str> = Icon::ALL.iter().map(|i| i.path()).collect();
        paths.sort_unstable();
        paths.dedup();
        assert_eq!(paths.len(), Icon::ALL.len());
        assert_eq!(list("icons/").len(), Icon::ALL.len());
        assert!(list("fonts/").is_empty());
        assert_eq!(by_path("icons/missing.svg"), None);
    }

    #[test]
    fn coolicons_tint_with_current_color() {
        for icon in Icon::ALL.iter().filter(|i| **i != Icon::Logo) {
            let text = std::str::from_utf8(icon.bytes()).unwrap();
            assert!(text.contains("currentColor"), "{icon:?}");
            assert!(!text.contains('#'), "{icon:?} hard-codes a color");
        }
    }

    #[test]
    fn svg_sniffing() {
        assert!(looks_like_svg(b"<svg viewBox=\"0 0 1 1\"/>"));
        assert!(looks_like_svg(
            b"<?xml version=\"1.0\"?>\n<!-- c -->\n <svg viewBox=\"0 0 1 1\"/>"
        ));
        assert!(!looks_like_svg(b"<svg width=\"1\"/>"));
        assert!(!looks_like_svg(b"<html><svg viewBox=\"0 0 1 1\"/></html>"));
        assert!(!looks_like_svg(b"<!-- unterminated <svg viewBox"));
        assert!(!looks_like_svg(&[0xff, 0xfe]));
    }
}
