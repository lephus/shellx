//! The workspace colour palette and how a workspace card is drawn (Mac: `WorkspaceTabColorSettings`,
//! `sidebarWorkspaceRowBackgroundStyle`, `ShellXSelectionTint`). Pure: C2 wires the cards.

use crate::chrome::Chrome;
use crate::palette::Rgba;
use crate::settings::Settings;

pub const BUILT_IN: [(&str, u32); 16] = [("", 0); 16];
pub const DEFAULT_NAME: &str = "Purple";

#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Entry {
    pub name: &'static str,
    pub base: Rgba,
    pub color: Rgba,
}

pub fn palette(_settings: &Settings) -> Vec<Entry> {
    todo!()
}

pub fn workspace_color(_settings: &Settings, _name: Option<&str>) -> Rgba {
    todo!()
}

#[derive(Clone, Copy, Debug, PartialEq)]
pub struct CardStyle {
    pub rail: Option<Rgba>,
    pub fill: Option<Rgba>,
    pub border: Option<Rgba>,
}

pub fn card_style(_settings: &Settings, _chrome: &Chrome, _color: Rgba, _selected: bool) -> CardStyle {
    todo!()
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
        chrome(&shellx(), rgb(ACCENT), SidebarBackground::FollowTheme, rgb(0x100b1d))
    }

    /// The same theme with a white Custom sidebar: a light surface on a dark theme.
    fn light_sidebar() -> Chrome {
        chrome(&shellx(), rgb(ACCENT), SidebarBackground::Custom, rgb(0xffffff))
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
            .map(|e| (e.name, (u32::from(e.color.r) << 16) | (u32::from(e.color.g) << 8) | u32::from(e.color.b)))
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
        assert_eq!(card_style(&off, &dark(), purple(&off), false).rail, card.rail);
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
        assert_eq!(card_style(&s, &dark(), purple(&s), false).fill.unwrap().a, 1.0);
        s.unselected_fill_opacity = f32::NAN;
        assert_eq!(card_style(&s, &dark(), purple(&s), false).fill.unwrap().a, 0.7);
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
        assert_eq!(card_style(&s, &dark(), purple(&s), true).fill, Some(rgb(0xaabbcc)));
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
