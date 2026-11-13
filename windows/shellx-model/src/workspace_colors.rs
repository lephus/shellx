//! The workspace colour palette and how a workspace card is drawn. The Mac files are
//! `WorkspaceTabColorSettings.swift` (palette, brighten), `Sidebar/SidebarAppearanceSupport.swift`
//! (`sidebarWorkspaceRowBackgroundStyle`, `CmuxSelectionFill`, `sidebarUsesSubtleSelection`,
//! `drawsActiveBorder`, `sidebarWorkspaceRowExplicitRailNSColor`) and
//! `Packages/Shared/ShellXBrand/.../ShellXSelectionTint.swift`. Pure: C2 wires the cards.

use crate::chrome::{Chrome, is_dark_surface, mix};
use crate::palette::Rgba;
use crate::settings::{IndicatorStyle, Settings};

/// Mac: `WorkspaceTabColorSettings.originalPRPalette`, lines 21-37.
pub const BUILT_IN: [(&str, u32); 16] = [
    ("Red", 0xC0392B),
    ("Crimson", 0x922B21),
    ("Orange", 0xA04000),
    ("Amber", 0x7D6608),
    ("Olive", 0x4A5C18),
    ("Green", 0x196F3D),
    ("Teal", 0x006B6B),
    ("Aqua", 0x0E6B8C),
    ("Blue", 0x1565C0),
    ("Navy", 0x1A5276),
    ("Indigo", 0x283593),
    ("Purple", 0x6A1B9A),
    ("Magenta", 0xAD1457),
    ("Rose", 0x880E4F),
    ("Brown", 0x7B3F00),
    ("Charcoal", 0x3E4B5E),
];

/// The colour a new workspace starts with (Mac: `newWorkspaceColorHex`, lines 74-75).
pub const DEFAULT_NAME: &str = "Purple";

/// The rail's alpha (Mac: `SidebarWorkspaceRowCellView.swift:547`).
const RAIL_ALPHA: f32 = 0.95;
/// Unselected Solid Fill opacity when the setting is not a number (Mac: `SidebarAppearanceSupport.swift:580`, default `:500`).
const FALLBACK_UNSELECTED_OPACITY: f32 = 0.7;
/// Subtle selection fill alpha, emphasized: dark 0.14, light 0.11; edge 0.60
/// (Mac: `SidebarAppearanceSupport.swift:323-324`).
const SUBTLE_FILL_DARK: f32 = 0.14;
const SUBTLE_FILL_LIGHT: f32 = 0.11;
const SUBTLE_EDGE: f32 = 0.60;
/// The tint of a non-subtle selection on a dark sidebar: the accent at 22% over the sidebar
/// (Mac: `ShellXSelectionTint.sidebarFill`, ShellXSelectionTint.swift:43). The Mac mixes over
/// the fixed ShellX panel; Windows mixes over the sidebar's own background on purpose, so a
/// dark Custom sidebar gets a tint of its own colour. Both give #222d4e for the ShellX theme.
const TINT: f32 = 0.22;
/// The outline of the selected Solid Fill card: the label colour at 50%
/// (Mac: `SidebarWorkspaceRowCellView.swift:253-254`; 1.5 pt wide).
const ACTIVE_BORDER_ALPHA: f32 = 0.5;
/// Brighten (Mac: `WorkspaceTabColorSettings.brightenedForDarkAppearance`, lines 279-300).
const BRIGHT_FLOOR: f32 = 0.62;
const BRIGHT_BOOST: f32 = 0.28;
const GREY_SATURATION: f32 = 0.08;
const SATURATION_BOOST: f32 = 0.12;

#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Entry {
    pub name: &'static str,
    pub base: Rgba,
    pub color: Rgba,
}

/// The built-ins with the stored overrides applied (Mac: `palette(defaults:)`, built-in part).
pub fn palette(settings: &Settings) -> Vec<Entry> {
    BUILT_IN
        .iter()
        .map(|&(name, hex)| {
            let base = Rgba::rgb(hex);
            Entry {
                name,
                base,
                color: settings.palette.get(name).copied().unwrap_or(base),
            }
        })
        .collect()
}

/// The colour of a palette name. `None` or an unknown name is the current Purple
/// (Mac: `newWorkspaceColorHex`, lines 74-75).
pub fn workspace_color(settings: &Settings, name: Option<&str>) -> Rgba {
    let by_name = |n: &str| {
        settings.palette.get(n).copied().or_else(|| {
            BUILT_IN
                .iter()
                .find(|(b, _)| *b == n)
                .map(|&(_, hex)| Rgba::rgb(hex))
        })
    };
    name.and_then(by_name)
        .or_else(|| by_name(DEFAULT_NAME))
        .expect("Purple is built in")
}

/// What a workspace card draws: the rail on its left edge, its background and its outline.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct CardStyle {
    pub rail: Option<Rgba>,
    pub fill: Option<Rgba>,
    pub border: Option<Rgba>,
}

/// The card of a workspace with colour `color`, on the sidebar of `chrome`. The accent is
/// `chrome.primary`; "dark" is the sidebar's own surface, not the window's. Windows has no
/// multi-select and no inactive-window dimming, so the selection is always the emphasized one.
/// Where the Mac uses the system accent for the subtle tint, this uses the app accent.
pub fn card_style(settings: &Settings, chrome: &Chrome, color: Rgba, selected: bool) -> CardStyle {
    let dark = is_dark_surface(chrome.sidebar_bg);
    let accent = chrome.primary;
    let rail_style = settings.indicator_style == IndicatorStyle::LeftRail;
    // `sidebarUsesSubtleSelection` (SidebarAppearanceSupport.swift:434-442): a chosen selection
    // colour is an explicit request for a solid fill.
    let subtle = settings.subtle_selection && rail_style && settings.selection_color.is_none();
    let none = CardStyle {
        rail: None,
        fill: None,
        border: None,
    };

    if rail_style {
        // `sidebarWorkspaceRowExplicitRailNSColor`: forceBright, whatever Brighten says.
        let rail = Some(brightened(color).with_alpha(RAIL_ALPHA));
        if !selected {
            return CardStyle { rail, ..none };
        }
        if subtle {
            let alpha = if dark {
                SUBTLE_FILL_DARK
            } else {
                SUBTLE_FILL_LIGHT
            };
            return CardStyle {
                rail,
                fill: Some(accent.with_alpha(alpha)),
                border: Some(accent.with_alpha(SUBTLE_EDGE)),
            };
        }
        // `sidebarSelectedWorkspaceBackgroundNSColor` (SidebarAppearanceSupport.swift:347-385):
        // a chosen colour first, then ShellX's tint on a dark sidebar, otherwise the accent.
        let fill = match settings.selection_color {
            Some(c) => c,
            None if dark => mix(chrome.sidebar_bg, accent, TINT).with_alpha(1.0),
            None => accent,
        };
        return CardStyle {
            rail,
            fill: Some(fill),
            border: None,
        };
    }

    // Solid Fill.
    if selected {
        return CardStyle {
            fill: Some(settings.selection_color.unwrap_or(accent)),
            // `drawsActiveBorder`: solid-fill rows always outline the selected one.
            border: Some(chrome.sidebar_text.with_alpha(ACTIVE_BORDER_ALPHA)),
            ..none
        };
    }
    let opacity = settings.unselected_fill_opacity;
    let opacity = if opacity.is_finite() {
        opacity.clamp(0.0, 1.0)
    } else {
        FALLBACK_UNSELECTED_OPACITY
    };
    // `displayNSColor`: brightened on a dark sidebar when Brighten Colors in Dark Mode is on.
    let shown = if dark && settings.brighten_in_dark {
        brightened(color)
    } else {
        color
    };
    CardStyle {
        fill: Some(shown.with_alpha(opacity)),
        ..none
    }
}

/// Mac: `brightenedForDarkAppearance`. HSB brightness `max(v, 0.62) + (1-v)*0.28`; saturation
/// `s + (1-s)*0.12` unless the colour is nearly grey; the hue stays.
fn brightened(c: Rgba) -> Rgba {
    let (r, g, b) = (
        f32::from(c.r) / 255.0,
        f32::from(c.g) / 255.0,
        f32::from(c.b) / 255.0,
    );
    let max = r.max(g).max(b);
    let delta = max - r.min(g).min(b);
    let hue = if delta == 0.0 {
        0.0
    } else if max == r {
        (((g - b) / delta) % 6.0 + 6.0) % 6.0
    } else if max == g {
        (b - r) / delta + 2.0
    } else {
        (r - g) / delta + 4.0
    };
    let sat = if max == 0.0 { 0.0 } else { delta / max };
    let v = (max.max(BRIGHT_FLOOR) + (1.0 - max) * BRIGHT_BOOST).min(1.0);
    let s = if sat <= GREY_SATURATION {
        sat
    } else {
        (sat + (1.0 - sat) * SATURATION_BOOST).min(1.0)
    };
    let (p, q, t) = (
        v * (1.0 - s),
        v * (1.0 - s * hue.fract()),
        v * (1.0 - s * (1.0 - hue.fract())),
    );
    let (r, g, b) = match hue.floor() as u32 {
        0 => (v, t, p),
        1 => (q, v, p),
        2 => (p, v, t),
        3 => (p, q, v),
        4 => (t, p, v),
        _ => (v, p, q),
    };
    let byte = |x: f32| (x * 255.0).round().clamp(0.0, 255.0) as u8;
    Rgba {
        r: byte(r),
        g: byte(g),
        b: byte(b),
        a: c.a,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::chrome::chrome;
    use crate::settings::{IndicatorStyle, SidebarBackground};
    use crate::theme_file::shellx;

    fn rgb(hex: u32) -> Rgba {
        Rgba::rgb(hex)
    }

    const ACCENT: u32 = 0x60a5fa;

    /// ShellX theme, accent #60a5fa, the dark sidebar (#100b1d).
    fn dark() -> Chrome {
        chrome(
            &shellx(),
            rgb(ACCENT),
            SidebarBackground::FollowTheme,
            rgb(0x100b1d),
        )
    }

    /// The same theme with a white Custom sidebar: a light surface on a dark theme.
    fn light_sidebar() -> Chrome {
        chrome(
            &shellx(),
            rgb(ACCENT),
            SidebarBackground::Custom,
            rgb(0xffffff),
        )
    }

    fn settings(style: IndicatorStyle, subtle: bool) -> Settings {
        Settings {
            indicator_style: style,
            subtle_selection: subtle,
            ..Settings::default()
        }
    }

    fn purple(s: &Settings) -> Rgba {
        workspace_color(s, Some("Purple"))
    }

    #[test]
    fn the_built_in_palette_is_the_macs_sixteen() {
        let p = palette(&Settings::default());
        let got: Vec<(&str, u32)> = p
            .iter()
            .map(|e| {
                (
                    e.name,
                    (u32::from(e.color.r) << 16)
                        | (u32::from(e.color.g) << 8)
                        | u32::from(e.color.b),
                )
            })
            .collect();
        assert_eq!(
            got,
            vec![
                ("Red", 0xC0392B),
                ("Crimson", 0x922B21),
                ("Orange", 0xA04000),
                ("Amber", 0x7D6608),
                ("Olive", 0x4A5C18),
                ("Green", 0x196F3D),
                ("Teal", 0x006B6B),
                ("Aqua", 0x0E6B8C),
                ("Blue", 0x1565C0),
                ("Navy", 0x1A5276),
                ("Indigo", 0x283593),
                ("Purple", 0x6A1B9A),
                ("Magenta", 0xAD1457),
                ("Rose", 0x880E4F),
                ("Brown", 0x7B3F00),
                ("Charcoal", 0x3E4B5E),
            ]
        );
        assert_eq!(DEFAULT_NAME, "Purple");
    }

    #[test]
    fn an_override_changes_one_entry_and_keeps_its_base() {
        let mut s = Settings::default();
        s.palette.insert("Teal".into(), rgb(0x112233));
        let p = palette(&s);
        let teal = p.iter().find(|e| e.name == "Teal").unwrap();
        assert_eq!(teal.color, rgb(0x112233));
        assert_eq!(teal.base, rgb(0x006B6B));
        let changed = p.iter().filter(|e| e.color != e.base).count();
        assert_eq!(changed, 1);
    }

    #[test]
    fn a_new_workspace_is_purple_and_follows_an_edited_purple() {
        let mut s = Settings::default();
        assert_eq!(workspace_color(&s, None), rgb(0x6A1B9A));
        assert_eq!(workspace_color(&s, Some("No such colour")), rgb(0x6A1B9A));
        assert_eq!(workspace_color(&s, Some("Teal")), rgb(0x006B6B));
        s.palette.insert("Purple".into(), rgb(0x445566));
        assert_eq!(workspace_color(&s, None), rgb(0x445566));
        assert_eq!(workspace_color(&s, Some("No such colour")), rgb(0x445566));
        assert_eq!(workspace_color(&s, Some("Purple")), rgb(0x445566));
    }

    #[test]
    fn left_rail_draws_a_rail_and_no_fill_when_unselected() {
        // The rail is the colour brightened (forceBright), at 0.95. Purple #6a1b9a = (106,27,154):
        // v = 154/255 = 0.6039, s = (154-27)/154 = 0.8247, h = 277.3 deg.
        // v' = max(v, 0.62) + (1-v)*0.28 = 0.7309; s' = s + (1-s)*0.12 = 0.8457.
        // max = 0.7309*255 = 186.4 -> 186; min = 186.4*(1-0.8457) = 28.8 -> 29;
        // mid (r) = 186.4*(1 - 0.8457*(1-0.6221)) = 126.8 -> 127. So #7f1dba.
        let s = settings(IndicatorStyle::LeftRail, true);
        let card = card_style(&s, &dark(), purple(&s), false);
        assert_eq!(card.rail, Some(rgb(0x7f1dba).with_alpha(0.95)));
        assert_eq!(card.fill, None);
        assert_eq!(card.border, None);
        // Brighten Colors in Dark Mode off does not touch the rail: the Mac forces it bright.
        let mut off = s.clone();
        off.brighten_in_dark = false;
        assert_eq!(
            card_style(&off, &dark(), purple(&off), false).rail,
            card.rail
        );
        // The selected card keeps its rail.
        assert_eq!(card_style(&s, &dark(), purple(&s), true).rail, card.rail);
    }

    #[test]
    fn subtle_selection_is_an_accent_tint_with_a_border() {
        // Dark: the accent at 0.14 as the fill, 0.60 as the 1px edge (CmuxSelectionFill.resolve).
        let s = settings(IndicatorStyle::LeftRail, true);
        let card = card_style(&s, &dark(), purple(&s), true);
        assert_eq!(card.fill, Some(rgb(ACCENT).with_alpha(0.14)));
        assert_eq!(card.border, Some(rgb(ACCENT).with_alpha(0.60)));
        // A light sidebar: 0.11.
        let card = card_style(&s, &light_sidebar(), purple(&s), true);
        assert_eq!(card.fill, Some(rgb(ACCENT).with_alpha(0.11)));
        assert_eq!(card.border, Some(rgb(ACCENT).with_alpha(0.60)));
    }

    #[test]
    fn subtle_off_is_a_solid_accent_fill() {
        let s = settings(IndicatorStyle::LeftRail, false);
        // Dark sidebar: ShellX's tint, the accent at 22% over the sidebar #100b1d:
        // r = 16 + 0.22*(96-16) = 33.6 -> 34 (0x22); g = 11 + 0.22*(165-11) = 44.9 -> 45 (0x2d);
        // b = 29 + 0.22*(250-29) = 77.6 -> 78 (0x4e). It is opaque and has no border.
        let card = card_style(&s, &dark(), purple(&s), true);
        assert_eq!(card.fill, Some(rgb(0x222d4e)));
        assert_eq!(card.border, None);
        // A light sidebar keeps the plain accent.
        let card = card_style(&s, &light_sidebar(), purple(&s), true);
        assert_eq!(card.fill, Some(rgb(ACCENT)));
        assert_eq!(card.border, None);
        // Unselected: nothing.
        assert_eq!(card_style(&s, &dark(), purple(&s), false).fill, None);
    }

    #[test]
    fn solid_fill_uses_the_unselected_opacity() {
        let mut s = settings(IndicatorStyle::SolidFill, true);
        // Unselected: the colour (brightened on a dark sidebar) at the unselected opacity, 0.70.
        let card = card_style(&s, &dark(), purple(&s), false);
        assert_eq!(card.fill, Some(rgb(0x7f1dba).with_alpha(0.70)));
        assert_eq!(card.rail, None);
        assert_eq!(card.border, None);
        s.unselected_fill_opacity = 0.35;
        assert_eq!(
            card_style(&s, &dark(), purple(&s), false).fill,
            Some(rgb(0x7f1dba).with_alpha(0.35))
        );
        // Selected: the accent, solid, with a 50% label-colour outline (sidebar text #e6e2f2).
        let card = card_style(&s, &dark(), purple(&s), true);
        assert_eq!(card.fill, Some(rgb(ACCENT)));
        assert_eq!(card.border, Some(rgb(0xe6e2f2).with_alpha(0.5)));
        // A value outside 0..1 is clamped, NaN falls back to 0.7.
        s.unselected_fill_opacity = 1.7;
        assert_eq!(
            card_style(&s, &dark(), purple(&s), false).fill.unwrap().a,
            1.0
        );
        s.unselected_fill_opacity = f32::NAN;
        assert_eq!(
            card_style(&s, &dark(), purple(&s), false).fill.unwrap().a,
            0.7
        );
    }

    #[test]
    fn a_custom_selection_colour_is_always_solid() {
        let mut s = settings(IndicatorStyle::LeftRail, true);
        s.selection_color = Some(rgb(0xaabbcc));
        // The subtle tint gives way to the colour the user chose, in both indicator styles.
        let card = card_style(&s, &dark(), purple(&s), true);
        assert_eq!(card.fill, Some(rgb(0xaabbcc)));
        assert_eq!(card.border, None);
        s.indicator_style = IndicatorStyle::SolidFill;
        let card = card_style(&s, &dark(), purple(&s), true);
        assert_eq!(card.fill, Some(rgb(0xaabbcc)));
        // With subtle off as well.
        s.subtle_selection = false;
        s.indicator_style = IndicatorStyle::LeftRail;
        assert_eq!(
            card_style(&s, &dark(), purple(&s), true).fill,
            Some(rgb(0xaabbcc))
        );
    }

    #[test]
    fn brighten_applies_only_on_dark_chrome_with_solid_fill() {
        let mut s = settings(IndicatorStyle::SolidFill, true);
        let fill = |s: &Settings, c: &Chrome| card_style(s, c, purple(s), false).fill.unwrap();
        // On: dark sidebar brightens, light sidebar does not.
        assert_eq!(fill(&s, &dark()), rgb(0x7f1dba).with_alpha(0.70));
        assert_eq!(fill(&s, &light_sidebar()), rgb(0x6a1b9a).with_alpha(0.70));
        // Off: never.
        s.brighten_in_dark = false;
        assert_eq!(fill(&s, &dark()), rgb(0x6a1b9a).with_alpha(0.70));
        // A grey (saturation <= 0.08) keeps its saturation: #808080 -> v' = 0.62+0.498*0.28 = 0.759.
        s.brighten_in_dark = true;
        let grey = card_style(&s, &dark(), rgb(0x808080), false).fill.unwrap();
        assert_eq!((grey.r, grey.g, grey.b), (194, 194, 194));
    }
}
