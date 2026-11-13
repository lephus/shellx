//! Ghostty theme files (`key = value` lines): the bundled themes, the user's own, and the
//! light/dark pair rule. Pure: no GPUI, no file access.

use crate::palette::Rgba;
use crate::settings::{Appearance, Settings};

#[derive(Clone, Debug, PartialEq)]
pub struct TermTheme {
    pub name: String,
    pub background: Rgba,
    pub foreground: Rgba,
    pub cursor: Rgba,
    pub cursor_text: Rgba,
    pub selection_bg: Rgba,
    pub selection_fg: Rgba,
    pub ansi: [Rgba; 16],
}

pub fn parse(_name: &str, _text: &str) -> TermTheme {
    todo!()
}

pub fn shellx() -> TermTheme {
    todo!()
}

pub fn is_dark(_theme: &TermTheme) -> bool {
    todo!()
}

pub fn bundled() -> &'static [(&'static str, &'static str)] {
    &[]
}

pub struct ThemeSet {}

impl ThemeSet {
    pub fn new(_user: Vec<(String, String)>) -> ThemeSet {
        todo!()
    }
    pub fn get(&self, _name: &str) -> Option<TermTheme> {
        todo!()
    }
    pub fn dark(&self, _query: &str) -> Vec<&str> {
        todo!()
    }
    pub fn light(&self, _query: &str) -> Vec<&str> {
        todo!()
    }
}

pub fn active(_set: &ThemeSet, _settings: &Settings, _dark: bool) -> TermTheme {
    todo!()
}

pub fn is_dark_mode(_appearance: Appearance, _system_dark: bool) -> bool {
    todo!()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn rgb(hex: u32) -> Rgba {
        Rgba::rgb(hex)
    }

    #[test]
    fn the_shellx_theme_is_the_bundled_file() {
        let t = shellx();
        assert_eq!(t.name, "ShellX");
        assert_eq!(t.background, rgb(0x0b0716));
        assert_eq!(t.foreground, rgb(0xcdc7e0));
        assert_eq!(t.cursor, rgb(0x60a5fa));
        assert_eq!(t.selection_bg, rgb(0x233356));
        assert_eq!(t.selection_fg, rgb(0xe6e2f2));
        assert_eq!(t.ansi[0], rgb(0x211a37));
        assert_eq!(t.ansi[5], rgb(0xc49af0));
    }

    #[test]
    fn there_are_464_bundled_themes_386_dark_78_light() {
        assert_eq!(bundled().len(), 464);
        let set = ThemeSet::new(vec![]);
        assert_eq!(set.dark("").len(), 386);
        assert_eq!(set.light("").len(), 78);
    }

    #[test]
    fn odd_theme_files_parse() {
        let text = "# comment\r\nbackground = 0b0716\r\n\r\nforeground=#ffffff\r\n\
                    palette = 16=#ffffff\r\npalette = 1=#111111\r\npalette = 1=#222222\r\n";
        let t = parse("Odd", text);
        assert_eq!(t.name, "Odd");
        assert_eq!(t.background, rgb(0x0b0716));
        assert_eq!(t.foreground, rgb(0xffffff));
        assert_eq!(t.ansi[1], rgb(0x222222));
        // Slot 16 does not exist; the other slots keep the ShellX values.
        assert_eq!(t.ansi[0], shellx().ansi[0]);
        assert_eq!(t.ansi[15], shellx().ansi[15]);
    }

    #[test]
    fn a_theme_without_selection_swaps_foreground_and_background() {
        let t = parse("Plain", "background = #101010\nforeground = #e0e0e0\n");
        assert_eq!(t.selection_bg, rgb(0xe0e0e0));
        assert_eq!(t.selection_fg, rgb(0x101010));
        assert_eq!(t.cursor, rgb(0xe0e0e0));
        assert_eq!(t.cursor_text, rgb(0x101010));
    }

    #[test]
    fn user_theme_wins_a_case_insensitive_clash() {
        let set = ThemeSet::new(vec![(
            "shellx".to_string(),
            "background = #ffffff\nforeground = #000000\n".to_string(),
        )]);
        assert_eq!(set.get("SHELLX").unwrap().background, rgb(0xffffff));
        assert_eq!(set.get("ShellX").unwrap().background, rgb(0xffffff));
        let names: Vec<&str> = set.light("shellx");
        assert_eq!(names, vec!["shellx"]);
        assert!(set.dark("shellx").is_empty());
        assert_eq!(set.light("").len() + set.dark("").len(), 464);
    }

    #[test]
    fn the_pair_side_follows_dark_mode() {
        let set = ThemeSet::new(vec![]);
        let s = Settings::default();
        assert_eq!(active(&set, &s, true).name, "ShellX");
        assert_eq!(active(&set, &s, false).name, "Catppuccin Latte");
        assert!(is_dark_mode(Appearance::Dark, false));
        assert!(!is_dark_mode(Appearance::Light, true));
        assert!(is_dark_mode(Appearance::System, true));
        assert!(!is_dark_mode(Appearance::System, false));
    }

    #[test]
    fn a_missing_theme_name_falls_back_to_the_side_default() {
        let set = ThemeSet::new(vec![]);
        let mut s = Settings::default();
        s.theme_dark = "No Such Theme".into();
        s.theme_light = String::new();
        assert_eq!(active(&set, &s, true).name, "ShellX");
        assert_eq!(active(&set, &s, false).name, "Catppuccin Latte");
        s.theme_dark = "dracula".into();
        assert_eq!(active(&set, &s, true).name, "Dracula");
    }
}
