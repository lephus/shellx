//! The workspace colour palette and how a workspace card is drawn. The Mac files are
//! `WorkspaceTabColorSettings.swift` (palette, brighten), `Sidebar/SidebarAppearanceSupport.swift`
//! (`sidebarWorkspaceRowBackgroundStyle`, `CmuxSelectionFill`, `sidebarUsesSubtleSelection`,
//! `drawsActiveBorder`, `sidebarWorkspaceRowExplicitRailNSColor`) and
//! `Packages/Shared/ShellXBrand/.../ShellXSelectionTint.swift`. Pure: C2 wires the cards.

use crate::chrome::{Chrome, MUTED_MIN, TEXT_MIN, ensure_contrast, is_dark_surface, mix};
use crate::palette::Rgba;
use crate::settings::{IndicatorStyle, Key, Settings};

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

/// Widths of the card's coloured parts, in px (points mapped 1:1). The rail is a 3 wide bar, 3 in
/// from the card's left edge and 5 in from its top and bottom, ends rounded to half its width
/// (Mac: `SidebarWorkspaceRowCellView.swift:1609-1610`).
pub const RAIL_WIDTH: f32 = 3.0;
pub const RAIL_LEFT: f32 = 3.0;
pub const RAIL_INSET_Y: f32 = 5.0;
pub const RAIL_RADIUS: f32 = 1.5;
/// The card's outline: 1 for the selection edge (`SidebarWorkspaceRowCellView.swift:244`), 1.5
/// for the Solid Fill active border (`:249-254`).
const EDGE_WIDTH: f32 = 1.0;
const ACTIVE_BORDER_WIDTH: f32 = 1.5;

/// The width of every card's outline under `settings` (clear when it has no colour, so a
/// selection never moves the text).
pub fn border_width(settings: &Settings) -> f32 {
    match settings.indicator_style {
        IndicatorStyle::LeftRail => EDGE_WIDTH,
        IndicatorStyle::SolidFill => ACTIVE_BORDER_WIDTH,
    }
}

/// One line of the card menu: a palette entry.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct MenuEntry {
    pub name: &'static str,
    pub color: Rgba,
    /// The workspace's own colour.
    pub checked: bool,
}

/// The right-click menu of a card, under the heading "Workspace Color".
#[derive(Clone, Debug, PartialEq)]
pub struct ColorMenu {
    /// "Clear Color" is listed: only a colour of the workspace's own can be cleared.
    pub clear: bool,
    pub entries: Vec<MenuEntry>,
}

/// The menu of a workspace whose own colour is `current` (`None`: it shows the default Purple
/// without having chosen it, so there is nothing to clear and no check).
pub fn color_menu(settings: &Settings, current: Option<&str>) -> ColorMenu {
    ColorMenu {
        clear: current.is_some(),
        entries: palette(settings)
            .into_iter()
            .map(|entry| MenuEntry {
                name: entry.name,
                color: entry.color,
                checked: current == Some(entry.name),
            })
            .collect(),
    }
}

/// The top-left corner of a menu of `size` asked at `at`, kept `margin` inside a window of
/// `window` (all `(width, height)` or `(x, y)` in px). A menu too big for the window starts at
/// the margin.
pub fn menu_origin(
    at: (f32, f32),
    size: (f32, f32),
    window: (f32, f32),
    margin: f32,
) -> (f32, f32) {
    let place = |at: f32, size: f32, window: f32| at.min(window - margin - size).max(margin);
    (place(at.0, size.0, window.0), place(at.1, size.1, window.1))
}

/// The title and the secondary text of a card with `fill` (its colour, over the sidebar), made
/// to read on it: the chrome's own text colours when nothing is filled, else pushed until they
/// reach the contrast the sidebar's labels have.
pub fn card_text(chrome: &Chrome, fill: Option<Rgba>, selected: bool) -> (Rgba, Rgba) {
    let title = if selected {
        chrome.sidebar_selection_title
    } else {
        chrome.sidebar_text
    };
    let muted = chrome.sidebar_muted;
    let Some(fill) = fill else {
        return (title, muted);
    };
    let surface = mix(chrome.sidebar_bg, fill, fill.a).with_alpha(1.0);
    (
        ensure_contrast(title, surface, TEXT_MIN),
        ensure_contrast(muted, surface, MUTED_MIN),
    )
}

/// The title and secondary text of an unselected card while the pointer is on it: the hover
/// fill replaces the card's own fill, so the text must read on that.
pub fn hover_card_text(chrome: &Chrome) -> (Rgba, Rgba) {
    todo!("{chrome:?}")
}

/// The JSON of `Key::Palette` once `name` is `colour`; a colour equal to the built-in one is
/// dropped, and the last drop gives the empty object (the default).
pub fn palette_edit(settings: &Settings, name: &str, colour: Rgba) -> serde_json::Value {
    let mut edited = settings.clone();
    let is_base = BUILT_IN
        .iter()
        .any(|&(n, hex)| n == name && Rgba::rgb(hex) == colour);
    if is_base {
        edited.palette.remove(name);
    } else {
        edited.palette.insert(name.to_string(), colour);
    }
    edited
        .to_value(Key::Palette)
        .unwrap_or_else(|| serde_json::json!({}))
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
    #[test]
    fn the_outline_is_wider_on_a_solid_fill_card() {
        let rail = settings(IndicatorStyle::LeftRail, true);
        let solid = settings(IndicatorStyle::SolidFill, true);
        assert_eq!(border_width(&rail), 1.0);
        assert_eq!(border_width(&solid), 1.5);
    }

    #[test]
    fn the_menu_lists_the_palette_and_checks_the_workspaces_own_colour() {
        let s = Settings::default();
        let m = color_menu(&s, Some("Green"));
        assert!(m.clear);
        assert_eq!(m.entries.len(), 16);
        assert_eq!(m.entries[0].name, "Red");
        assert_eq!(m.entries[0].color, rgb(0xC0392B));
        let checked: Vec<_> = m
            .entries
            .iter()
            .filter(|e| e.checked)
            .map(|e| e.name)
            .collect();
        assert_eq!(checked, ["Green"]);
        // No colour of its own: nothing to clear and nothing checked, though it draws Purple.
        let none = color_menu(&s, None);
        assert!(!none.clear);
        assert!(none.entries.iter().all(|e| !e.checked));
        // An edited palette colour shows in the menu.
        let mut edited = Settings::default();
        edited.palette.insert("Red".into(), rgb(0x112233));
        assert_eq!(color_menu(&edited, None).entries[0].color, rgb(0x112233));
        // A name the palette does not know is a colour of its own, but checks nothing.
        let odd = color_menu(&s, Some("Mauve"));
        assert!(odd.clear && odd.entries.iter().all(|e| !e.checked));
    }

    #[test]
    fn a_menu_asked_near_an_edge_stays_inside_the_window() {
        let window = (800.0, 600.0);
        let size = (220.0, 300.0);
        assert_eq!(
            menu_origin((100.0, 100.0), size, window, 8.0),
            (100.0, 100.0)
        );
        // Right edge, bottom edge, both.
        assert_eq!(
            menu_origin((700.0, 100.0), size, window, 8.0),
            (572.0, 100.0)
        );
        assert_eq!(
            menu_origin((100.0, 500.0), size, window, 8.0),
            (100.0, 292.0)
        );
        assert_eq!(
            menu_origin((790.0, 590.0), size, window, 8.0),
            (572.0, 292.0)
        );
        // Outside the top-left, and too big for the window: the margin.
        assert_eq!(menu_origin((-5.0, 2.0), size, window, 8.0), (8.0, 8.0));
        assert_eq!(
            menu_origin((100.0, 100.0), (220.0, 900.0), window, 8.0),
            (100.0, 8.0)
        );
    }

    #[test]
    fn card_text_reads_on_every_colour_and_is_left_alone_without_one() {
        for sidebar in [dark(), light_sidebar()] {
            let (title, muted) = card_text(&sidebar, None, false);
            assert_eq!(
                (title, muted),
                (sidebar.sidebar_text, sidebar.sidebar_muted)
            );
            let (title, _) = card_text(&sidebar, None, true);
            assert_eq!(title, sidebar.sidebar_selection_title);
            let s = Settings::default();
            for (name, _) in BUILT_IN {
                for opacity in [0.0, 0.3, 0.7, 1.0] {
                    for fill in [
                        workspace_color(&s, Some(name)).with_alpha(opacity),
                        brightened(workspace_color(&s, Some(name))).with_alpha(opacity),
                    ] {
                        let surface = mix(sidebar.sidebar_bg, fill, fill.a).with_alpha(1.0);
                        for selected in [false, true] {
                            let (title, muted) = card_text(&sidebar, Some(fill), selected);
                            assert!(
                                crate::chrome::contrast(title, surface) >= 4.5,
                                "{name} {opacity} title"
                            );
                            assert!(
                                crate::chrome::contrast(muted, surface) >= 3.0,
                                "{name} {opacity} muted"
                            );
                        }
                    }
                }
            }
        }
    }

    #[test]
    fn card_text_that_already_reads_is_not_changed() {
        let c = dark();
        // The default selected card (subtle accent tint) keeps the chrome's own title.
        let fill = settings_fill(&c);
        assert_eq!(card_text(&c, Some(fill), true).0, c.sidebar_selection_title);
    }

    fn settings_fill(c: &Chrome) -> Rgba {
        card_style(&Settings::default(), c, rgb(0x6A1B9A), true)
            .fill
            .unwrap()
    }

    #[test]
    fn editing_a_palette_colour_keeps_the_others_and_drops_a_colour_back_at_its_base() {
        let s = Settings::default();
        assert_eq!(
            palette_edit(&s, "Red", rgb(0x112233)),
            serde_json::json!({"Red": "#112233"})
        );
        let mut two = Settings::default();
        two.palette.insert("Red".into(), rgb(0x112233));
        assert_eq!(
            palette_edit(&two, "Blue", rgb(0x010203)),
            serde_json::json!({"Red": "#112233", "Blue": "#010203"})
        );
        // Back to the built-in colour: the entry goes, and the last one leaves the default.
        assert_eq!(
            palette_edit(&two, "Red", rgb(0xC0392B)),
            serde_json::json!({})
        );
    }

    #[test]
    fn card_text_reads_on_the_hover_fill_and_on_selected_solid_fills() {
        let s = Settings::default();
        for sidebar in [dark(), light_sidebar()] {
            let surface = mix(sidebar.sidebar_bg, sidebar.session_hover, sidebar.session_hover.a)
                .with_alpha(1.0);
            let (title, muted) = hover_card_text(&sidebar);
            assert!(crate::chrome::contrast(title, surface) >= 4.5, "hover title");
            assert!(crate::chrome::contrast(muted, surface) >= 3.0, "hover muted");
            // The selected card's fill: the accent, or any chosen selection colour.
            for fill in std::iter::once(sidebar.primary)
                .chain(BUILT_IN.iter().map(|&(_, hex)| rgb(hex)))
                .chain([rgb(0xffffff), rgb(0x000000), rgb(0x808080)])
            {
                let solid = Settings {
                    indicator_style: IndicatorStyle::SolidFill,
                    selection_color: Some(fill),
                    ..s.clone()
                };
                let style = card_style(&solid, &sidebar, rgb(0x6A1B9A), true);
                let shown = style.fill.unwrap();
                assert_eq!(shown, fill);
                let (title, muted) = card_text(&sidebar, style.fill, true);
                assert!(crate::chrome::contrast(title, shown) >= 4.5, "{fill:?} title");
                assert!(crate::chrome::contrast(muted, shown) >= 3.0, "{fill:?} muted");
            }
            let accent = card_style(&settings(IndicatorStyle::SolidFill, true), &sidebar, rgb(0x6A1B9A), true);
            let (title, _) = card_text(&sidebar, accent.fill, true);
            assert!(crate::chrome::contrast(title, sidebar.primary) >= 4.5, "accent title");
        }
    }
}
