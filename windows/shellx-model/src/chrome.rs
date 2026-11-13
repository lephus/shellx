//! The app's chrome colours derived from the terminal theme and the accent (spec §5.5).

use crate::palette::Rgba;
use crate::settings::{Accent, SidebarBackground};
use crate::theme_file::TermTheme;

#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Chrome {
    pub dark: bool,
    pub bg: Rgba,
    pub panel: Rgba,
    pub raise: Rgba,
    pub line: Rgba,
    pub border: Rgba,
    pub text: Rgba,
    pub text_hi: Rgba,
    pub muted: Rgba,
    pub primary: Rgba,
    pub primary_soft: Rgba,
    pub primary_line: Rgba,
    pub primary_text: Rgba,
    pub running: Rgba,
    pub done: Rgba,
    pub error: Rgba,
    pub running_text: Rgba,
    pub done_text: Rgba,
    pub error_text: Rgba,
    pub selection_title: Rgba,
    pub indicator_unfocused: Rgba,
    pub session_selected: Rgba,
    pub session_hover: Rgba,
    pub sidebar_bg: Rgba,
    pub sidebar_text: Rgba,
    pub sidebar_muted: Rgba,
}

pub fn contrast(_a: Rgba, _b: Rgba) -> f32 {
    todo!()
}

pub fn ensure_contrast(_fg: Rgba, _bg: Rgba, _min: f32) -> Rgba {
    todo!()
}

pub fn accent_color(_accent: &Accent, _system: Option<Rgba>) -> Rgba {
    todo!()
}

pub fn accent_from_dwm(_abgr: u32) -> Rgba {
    todo!()
}

pub fn chrome(
    _theme: &TermTheme,
    _accent: Rgba,
    _sidebar: SidebarBackground,
    _sidebar_color: Rgba,
) -> Chrome {
    todo!()
}

fn luminance(_c: Rgba) -> f32 {
    todo!()
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::palette;
    use crate::theme_file::{ThemeSet, bundled, parse, shellx};

    fn rgb(hex: u32) -> Rgba {
        Rgba::rgb(hex)
    }

    fn named(name: &str) -> TermTheme {
        ThemeSet::new(vec![]).get(name).unwrap()
    }

    /// A theme with only these two colours changed from ShellX's.
    fn theme(background: u32, foreground: u32) -> TermTheme {
        TermTheme {
            name: "Test".into(),
            background: rgb(background),
            foreground: rgb(foreground),
            ..shellx()
        }
    }

    /// The pairs spec §5.5 requires: text colours at 4.5:1, muted text at 3:1.
    fn readable_pairs(c: &Chrome) -> [(&'static str, Rgba, Rgba, f32); 8] {
        [
            ("text on bg", c.text, c.bg, 4.5),
            ("sidebar_text on sidebar_bg", c.sidebar_text, c.sidebar_bg, 4.5),
            ("primary_text on bg", c.primary_text, c.bg, 4.5),
            ("running_text on bg", c.running_text, c.bg, 4.5),
            ("done_text on bg", c.done_text, c.bg, 4.5),
            ("error_text on bg", c.error_text, c.bg, 4.5),
            ("muted on bg", c.muted, c.bg, 3.0),
            ("sidebar_muted on sidebar_bg", c.sidebar_muted, c.sidebar_bg, 3.0),
        ]
    }

    #[test]
    fn the_shellx_theme_gives_todays_chrome_exactly() {
        let c = chrome(
            &shellx(),
            rgb(0x60a5fa),
            SidebarBackground::FollowTheme,
            rgb(0x100b1d),
        );
        assert_eq!(c.bg, palette::BG);
        assert_eq!(c.panel, palette::PANEL);
        assert_eq!(c.raise, palette::RAISE);
        assert_eq!(c.line, palette::LINE);
        assert_eq!(c.border, palette::BORDER);
        assert_eq!(c.text, palette::TEXT);
        assert_eq!(c.text_hi, palette::TEXT_HI);
        assert_eq!(c.muted, palette::MUTED);
        assert_eq!(c.primary_text, palette::PRIMARY_TEXT);
        assert_eq!(c.sidebar_bg, palette::PANEL);
        assert_eq!(c.running_text, palette::RUNNING);
        assert_eq!(c.session_selected, rgb(0x1a1430));
        // Every field. The sidebar draws names in TEXT_HI and labels in MUTED today.
        assert_eq!(
            c,
            Chrome {
                dark: true,
                bg: palette::BG,
                panel: palette::PANEL,
                raise: palette::RAISE,
                line: palette::LINE,
                border: palette::BORDER,
                text: palette::TEXT,
                text_hi: palette::TEXT_HI,
                muted: palette::MUTED,
                primary: palette::PRIMARY,
                primary_soft: palette::PRIMARY_SOFT,
                primary_line: palette::PRIMARY_LINE,
                primary_text: palette::PRIMARY_TEXT,
                running: palette::RUNNING,
                done: palette::DONE,
                error: palette::ERROR,
                running_text: palette::RUNNING,
                done_text: palette::DONE,
                error_text: palette::ERROR,
                selection_title: palette::SELECTION_TITLE,
                indicator_unfocused: palette::INDICATOR_UNFOCUSED,
                session_selected: palette::SESSION_SELECTED,
                session_hover: palette::SESSION_HOVER,
                sidebar_bg: palette::PANEL,
                sidebar_text: palette::TEXT_HI,
                sidebar_muted: palette::MUTED,
            }
        );
    }

    #[test]
    fn every_bundled_theme_is_readable() {
        let accents = [palette::PRIMARY, rgb(0x0078d7), rgb(0xfff3a0)];
        let sidebars = [
            (SidebarBackground::FollowTheme, palette::PANEL),
            (SidebarBackground::MatchTerminal, palette::PANEL),
            (SidebarBackground::Custom, rgb(0xffffff)),
            (SidebarBackground::Custom, rgb(0x000000)),
        ];
        assert_eq!(bundled().len(), 464);
        let mut failures = Vec::new();
        for (name, text) in bundled() {
            let theme = parse(name, text);
            for accent in accents {
                for (sidebar, color) in sidebars {
                    let c = chrome(&theme, accent, sidebar, color);
                    for (pair, fg, bg, min) in readable_pairs(&c) {
                        let ratio = contrast(fg, bg);
                        if ratio < min {
                            failures.push(format!(
                                "{name}: {pair}: {} on {} is {ratio:.2}:1, needs {min}:1 \
                                 (accent {}, sidebar {sidebar:?} {})",
                                fg.hex(),
                                bg.hex(),
                                accent.hex(),
                                color.hex()
                            ));
                        }
                    }
                }
            }
        }
        assert!(
            failures.is_empty(),
            "{} unreadable pairs:\n{}",
            failures.len(),
            failures[..failures.len().min(40)].join("\n")
        );
    }

    #[test]
    fn contrast_is_the_wcag_ratio() {
        let (white, black) = (rgb(0xffffff), rgb(0x000000));
        assert!((contrast(white, black) - 21.0).abs() < 1e-4);
        assert!((contrast(black, white) - 21.0).abs() < 1e-4);
        assert_eq!(contrast(palette::BG, palette::BG), 1.0);
        // #777777 on white is the classic just-below-AA grey: 4.48:1.
        assert!((contrast(rgb(0x777777), white) - 4.48).abs() < 0.01);
    }

    #[test]
    fn contrast_search_terminates_on_equal_colours() {
        // Dark: the colour moves towards white until it reads.
        let dark = rgb(0x0b0716);
        let up = ensure_contrast(dark, dark, 4.5);
        assert!(contrast(up, dark) >= 4.5);
        assert!(luminance(up) > luminance(dark));
        // Light: towards black.
        let light = rgb(0xffffff);
        let down = ensure_contrast(light, light, 4.5);
        assert!(contrast(down, light) >= 4.5);
        assert!(luminance(down) < luminance(light));
        // A ratio no colour reaches gives the end that contrasts more.
        assert_eq!(ensure_contrast(light, light, 22.0), rgb(0x000000));
        assert_eq!(ensure_contrast(dark, dark, 22.0), rgb(0xffffff));
        let grey = rgb(0x777777);
        assert_eq!(ensure_contrast(grey, grey, 7.0), rgb(0x000000));
        assert_eq!(ensure_contrast(grey, grey, f32::NAN), rgb(0x000000));
        // A colour that already reads is kept.
        assert_eq!(ensure_contrast(palette::TEXT, dark, 4.5), palette::TEXT);
        // A theme whose foreground equals its background still reads, dark and light.
        for hex in [0x1e1e1e, 0xfafafa] {
            let c = chrome(
                &theme(hex, hex),
                palette::PRIMARY,
                SidebarBackground::FollowTheme,
                palette::PANEL,
            );
            for (pair, fg, bg, min) in readable_pairs(&c) {
                assert!(contrast(fg, bg) >= min, "{hex:06x}: {pair}");
            }
            assert_ne!(c.border, c.bg, "{hex:06x}: the surfaces still step");
        }
    }

    #[test]
    fn sidebar_follows_the_macs_rule() {
        let follow = |t: &TermTheme| {
            chrome(
                t,
                palette::PRIMARY,
                SidebarBackground::FollowTheme,
                rgb(0x123456),
            )
            .sidebar_bg
        };
        assert_eq!(follow(&shellx()), palette::PANEL);
        // Dracula #282a36 + 2% white: 40 * 0.98 + 5.1 = 44.3, 46.26, 58.02.
        let dracula = named("Dracula");
        assert_eq!(dracula.background, rgb(0x282a36));
        assert_eq!(follow(&dracula), rgb(0x2c2e3a));
        // Catppuccin Latte #eff1f5 + 3% black: 239 * 0.97 = 231.83, 233.77, 237.65.
        let latte = named("Catppuccin Latte");
        assert_eq!(latte.background, rgb(0xeff1f5));
        assert_eq!(follow(&latte), rgb(0xe8eaee));
        let with = |sidebar, color| chrome(&dracula, palette::PRIMARY, sidebar, color);
        assert_eq!(
            with(SidebarBackground::MatchTerminal, rgb(0x123456)).sidebar_bg,
            rgb(0x282a36)
        );
        let custom = with(SidebarBackground::Custom, rgb(0x123456));
        assert_eq!(custom.sidebar_bg, rgb(0x123456));
        // The sidebar's text follows its own background: a white sidebar on a dark theme
        // takes the Mac's label strengths in black, 85% and 50%.
        let white = with(SidebarBackground::Custom, rgb(0xffffff));
        assert_eq!(white.sidebar_text, rgb(0x262626));
        assert_eq!(white.sidebar_muted, rgb(0x808080));
        // A sidebar on the theme's side keeps the theme's text.
        let followed = with(SidebarBackground::FollowTheme, rgb(0x123456));
        assert_eq!(followed.sidebar_text, followed.text_hi);
        assert_eq!(followed.sidebar_muted, followed.muted);
    }

    #[test]
    fn a_custom_accent_colours_primary_only() {
        let orange = rgb(0xff8800);
        for theme in [shellx(), named("Dracula"), named("Catppuccin Latte")] {
            let blue = chrome(
                &theme,
                palette::PRIMARY,
                SidebarBackground::FollowTheme,
                palette::PANEL,
            );
            let custom = chrome(
                &theme,
                orange,
                SidebarBackground::FollowTheme,
                palette::PANEL,
            );
            assert_eq!(custom.primary, orange);
            assert_eq!(custom.primary_soft, orange.with_alpha(0.12));
            assert_eq!(custom.primary_line, orange.with_alpha(0.45));
            assert_ne!(custom.primary_text, blue.primary_text, "{}", theme.name);
            assert!(contrast(custom.primary_text, custom.bg) >= 4.5);
            assert_eq!(
                (custom.running, custom.done, custom.error),
                (palette::RUNNING, palette::DONE, palette::ERROR)
            );
            assert_eq!(
                Chrome {
                    primary: blue.primary,
                    primary_soft: blue.primary_soft,
                    primary_line: blue.primary_line,
                    primary_text: blue.primary_text,
                    ..custom
                },
                blue,
                "{}: only the primary fields change",
                theme.name
            );
        }
    }

    #[test]
    fn the_accent_setting_gives_a_colour() {
        let system = rgb(0x0078d7);
        assert_eq!(
            accent_color(&Accent::ShellxBlue, Some(system)),
            palette::PRIMARY
        );
        assert_eq!(accent_color(&Accent::System, Some(system)), system);
        assert_eq!(accent_color(&Accent::System, None), palette::PRIMARY);
        assert_eq!(
            accent_color(&Accent::Custom(rgb(0xff8800)), Some(system)),
            rgb(0xff8800)
        );
    }

    #[test]
    fn the_dwm_value_is_abgr() {
        assert_eq!(accent_from_dwm(0xff_d7_78_00), Rgba::rgb(0x0078d7));
        // The alpha byte is ignored.
        assert_eq!(accent_from_dwm(0x00_33_22_11), Rgba::rgb(0x112233));
    }
}
