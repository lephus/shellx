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

use crate::settings_search::fold;

const SHELLX_FILE: &str = include_str!("../../../Resources/ghostty/themes/ShellX");

/// Bundled theme files: name and text, sorted case-insensitively by name.
const BUNDLED: &[(&str, &str)] = include!(concat!(env!("OUT_DIR"), "/bundled_themes.rs"));

pub fn bundled() -> &'static [(&'static str, &'static str)] {
    BUNDLED
}

fn parse_hex(value: &str) -> Option<Rgba> {
    let hex = value.trim().trim_start_matches('#');
    if hex.len() != 6 || !hex.bytes().all(|b| b.is_ascii_hexdigit()) {
        return None;
    }
    u32::from_str_radix(hex, 16).ok().map(Rgba::rgb)
}

/// Reads the `key = value` lines of a theme file. A key that is missing, or a colour that does not
/// parse, takes the value spec section 5.5 names; a later line replaces an earlier one.
pub fn parse(name: &str, text: &str) -> TermTheme {
    parse_with(name, text, Some(&shellx()))
}

fn parse_with(name: &str, text: &str, fallback: Option<&TermTheme>) -> TermTheme {
    let mut base = [None; 16];
    let (mut background, mut foreground) = (None, None);
    let (mut cursor, mut cursor_text) = (None, None);
    let (mut selection_bg, mut selection_fg) = (None, None);
    // Windows editors write a UTF-8 BOM, which must not hide the first key.
    for line in text.trim_start_matches('\u{feff}').lines() {
        let line = line.trim();
        if line.is_empty() || line.starts_with('#') {
            continue;
        }
        let Some((key, value)) = line.split_once('=') else {
            continue;
        };
        let (key, value) = (key.trim(), value.trim());
        match key {
            "palette" => {
                if let Some((slot, color)) = value.split_once('=') {
                    if let (Ok(slot), Some(color)) =
                        (slot.trim().parse::<usize>(), parse_hex(color))
                    {
                        if slot < 16 {
                            base[slot] = Some(color);
                        }
                    }
                }
            }
            "background" => background = parse_hex(value).or(background),
            "foreground" => foreground = parse_hex(value).or(foreground),
            "cursor-color" => cursor = parse_hex(value).or(cursor),
            "cursor-text" => cursor_text = parse_hex(value).or(cursor_text),
            "selection-background" => selection_bg = parse_hex(value).or(selection_bg),
            "selection-foreground" => selection_fg = parse_hex(value).or(selection_fg),
            _ => {}
        }
    }
    let default_bg = fallback.map_or(Rgba::rgb(0), |t| t.background);
    let default_fg = fallback.map_or(Rgba::rgb(0), |t| t.foreground);
    let background = background.unwrap_or(default_bg);
    let foreground = foreground.unwrap_or(default_fg);
    let mut ansi = [Rgba::rgb(0); 16];
    for (slot, color) in ansi.iter_mut().enumerate() {
        *color = base[slot]
            .or_else(|| fallback.map(|t| t.ansi[slot]))
            .unwrap_or(Rgba::rgb(0));
    }
    TermTheme {
        name: name.to_string(),
        background,
        foreground,
        cursor: cursor.unwrap_or(foreground),
        cursor_text: cursor_text.unwrap_or(background),
        selection_bg: selection_bg.unwrap_or(foreground),
        selection_fg: selection_fg.unwrap_or(background),
        ansi,
    }
}

/// The bundled "ShellX" theme, also the source of every value a theme file leaves out.
pub fn shellx() -> TermTheme {
    // The file defines every key, so it needs no fallback.
    parse_with("ShellX", SHELLX_FILE, None)
}

/// Luma of the background below one half (0.299 R + 0.587 G + 0.114 B).
pub fn is_dark(theme: &TermTheme) -> bool {
    let b = theme.background;
    let luma = 0.299 * f32::from(b.r) + 0.587 * f32::from(b.g) + 0.114 * f32::from(b.b);
    luma / 255.0 < 0.5
}

/// Bundled themes plus the user's own files.
pub struct ThemeSet {
    /// Name and file text, sorted case-insensitively; one entry per case-folded name.
    entries: Vec<(String, String)>,
}

impl ThemeSet {
    /// A user name wins a case-insensitive clash with a bundled one.
    pub fn new(user: Vec<(String, String)>) -> ThemeSet {
        let mut entries: Vec<(String, String)> = bundled()
            .iter()
            .map(|(n, t)| (n.to_string(), t.to_string()))
            .collect();
        for (name, text) in user {
            let lower = name.to_lowercase();
            entries.retain(|(n, _)| n.to_lowercase() != lower);
            entries.push((name, text));
        }
        entries.sort_by(|a, b| {
            a.0.to_lowercase()
                .cmp(&b.0.to_lowercase())
                .then_with(|| a.0.cmp(&b.0))
        });
        ThemeSet { entries }
    }

    pub fn get(&self, name: &str) -> Option<TermTheme> {
        let lower = name.to_lowercase();
        self.entries
            .iter()
            .find(|(n, _)| n.to_lowercase() == lower)
            .map(|(n, t)| parse(n, t))
    }

    /// Every theme once, parsed, in the set's order. Parses the whole set: keep the result
    /// instead of calling it per frame.
    pub fn themes(&self) -> Vec<TermTheme> {
        self.entries.iter().map(|(n, t)| parse(n, t)).collect()
    }

    fn side(&self, query: &str, dark: bool) -> Vec<&str> {
        let query = fold(query.trim());
        self.entries
            .iter()
            .filter(|(n, _)| fold(n).contains(&query))
            .filter(|(n, t)| is_dark(&parse(n, t)) == dark)
            .map(|(n, _)| n.as_str())
            .collect()
    }

    /// Dark themes whose folded name contains the folded query; an empty query lists all.
    pub fn dark(&self, query: &str) -> Vec<&str> {
        self.side(query, true)
    }

    pub fn light(&self, query: &str) -> Vec<&str> {
        self.side(query, false)
    }
}

/// A user theme file over this many bytes is not read.
pub const USER_THEME_MAX_BYTES: u64 = 64 * 1024;
/// At most this many user theme files are read.
pub const USER_THEME_MAX_FILES: usize = 500;

/// Which of the user's theme files (name, size in bytes) are read, as indices into `files`:
/// a name that starts with a dot and a file over `USER_THEME_MAX_BYTES` are skipped, the rest
/// are taken in case-insensitive name order, the first `USER_THEME_MAX_FILES` of them.
pub fn user_theme_files(files: &[(String, u64)]) -> Vec<usize> {
    let mut picked: Vec<usize> = (0..files.len())
        .filter(|&i| {
            let (name, size) = &files[i];
            !name.is_empty() && !name.starts_with('.') && *size <= USER_THEME_MAX_BYTES
        })
        .collect();
    picked.sort_by(|&a, &b| {
        let (a, b) = (&files[a].0, &files[b].0);
        a.to_lowercase()
            .cmp(&b.to_lowercase())
            .then_with(|| a.cmp(b))
    });
    picked.truncate(USER_THEME_MAX_FILES);
    picked
}

/// The gallery's columns: as many as fit 128 wide with 10 between them, each as wide as the
/// width allows up to 220 (the Mac's adaptive grid). Returns the column count and a card's width.
pub fn gallery_grid(width: f32) -> (usize, f32) {
    const MIN: f32 = 128.0;
    const MAX: f32 = 220.0;
    const GAP: f32 = 10.0;
    let width = if width.is_finite() {
        width.max(0.0)
    } else {
        0.0
    };
    let columns = (((width + GAP) / (MIN + GAP)).floor() as usize).max(1);
    let each = (width - GAP * (columns - 1) as f32) / columns as f32;
    (columns, each.clamp(MIN, MAX))
}

/// The gallery's two sides in the order they are listed: the side in use first (`true` is
/// the dark side).
pub fn sides_first(dark_mode: bool) -> [bool; 2] {
    [dark_mode, !dark_mode]
}

/// The indices of the folded names (`settings_search::fold`) that contain the folded query;
/// an empty query matches all.
pub fn matching(folded_names: &[String], query: &str) -> Vec<usize> {
    let query = fold(query.trim());
    (0..folded_names.len())
        .filter(|&i| folded_names[i].contains(&query))
        .collect()
}

/// Whether a gallery card named `card` is the theme the pair's side stores as `stored`: the
/// same case rule as the lookup (`ThemeSet::get`).
pub fn is_current_theme(card: &str, stored: &str) -> bool {
    card.to_lowercase() == stored.to_lowercase()
}

/// The grid's top edge (window coordinates) moved by more than half a row since the frame
/// was built: the rows built are for the old place, so another frame is needed.
pub fn top_moved(old: f32, new: f32, row: f32) -> bool {
    (new - old).abs() > row / 2.0
}

/// Which of the grid's items (top and height, in grid coordinates) to build: those that meet
/// the viewport (`view` = top and bottom in window coordinates) or lie within `margin` of it,
/// for a grid whose top edge is at `grid_top`. A span of indices; empty when none does.
pub fn visible_span(
    items: &[(f32, f32)],
    view: (f32, f32),
    grid_top: f32,
    margin: f32,
) -> std::ops::Range<usize> {
    let (low, high) = (view.0 - grid_top - margin, view.1 - grid_top + margin);
    let meets = |&(y, h): &(f32, f32)| y + h >= low && y <= high;
    match (items.iter().position(meets), items.iter().rposition(meets)) {
        (Some(first), Some(last)) => first..last + 1,
        _ => 0..0,
    }
}

/// The theme in use: the pair's side for `dark`; an empty or unknown name takes that side's
/// default ("ShellX" dark, "Catppuccin Latte" light), then ShellX.
pub fn active(set: &ThemeSet, settings: &Settings, dark: bool) -> TermTheme {
    let (chosen, default) = if dark {
        (&settings.theme_dark, "ShellX")
    } else {
        (&settings.theme_light, "Catppuccin Latte")
    };
    set.get(chosen)
        .or_else(|| set.get(default))
        .unwrap_or_else(shellx)
}

pub fn is_dark_mode(appearance: Appearance, system_dark: bool) -> bool {
    match appearance {
        Appearance::Dark => true,
        Appearance::Light => false,
        Appearance::System => system_dark,
    }
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
    #[test]
    fn a_bom_does_not_hide_the_first_key() {
        let t = parse(
            "Bom",
            "\u{feff}background = #123456\nforeground = #abcdef\n",
        );
        assert_eq!(t.background, rgb(0x123456));
        assert_eq!(t.foreground, rgb(0xabcdef));
    }

    #[test]
    fn user_theme_files_are_sorted_and_capped() {
        let files: Vec<(String, u64)> = vec![
            ("Zeta".into(), 10),
            ("alpha".into(), 10),
            ("Huge".into(), USER_THEME_MAX_BYTES + 1),
            ("Edge".into(), USER_THEME_MAX_BYTES),
            (".hidden".into(), 10),
            ("Beta".into(), 0),
        ];
        let picked: Vec<&str> = user_theme_files(&files)
            .into_iter()
            .map(|i| files[i].0.as_str())
            .collect();
        assert_eq!(picked, ["alpha", "Beta", "Edge", "Zeta"]);
        let many: Vec<(String, u64)> = (0..USER_THEME_MAX_FILES + 40)
            .map(|n| (format!("t{n:04}"), 1))
            .collect();
        let picked = user_theme_files(&many);
        assert_eq!(picked.len(), USER_THEME_MAX_FILES);
        assert_eq!(many[picked[0]].0, "t0000");
        assert!(user_theme_files(&[]).is_empty());
    }

    #[test]
    fn every_theme_is_listed_once_with_its_side() {
        let set = ThemeSet::new(vec![]);
        let all = set.themes();
        assert_eq!(all.len(), 464);
        assert_eq!(all.iter().filter(|t| is_dark(t)).count(), 386);
        assert_eq!(all[0].name, bundled()[0].0);
    }

    #[test]
    fn the_gallery_grid_is_adaptive_between_128_and_220() {
        assert_eq!(gallery_grid(100.0), (1, 128.0));
        assert_eq!(gallery_grid(300.0), (2, 145.0));
        assert_eq!(gallery_grid(138.0), (1, 138.0));
        assert_eq!(gallery_grid(137.0).0, 1);
        assert_eq!(gallery_grid(500.0), (3, 160.0));
        let (columns, width) = gallery_grid(1000.0);
        assert_eq!(columns, 7);
        assert!((width - 940.0 / 7.0).abs() < 0.01);
        // One column never gets wider than 220.
        assert_eq!(gallery_grid(260.0), (1, 220.0));
        assert_eq!(gallery_grid(0.0), (1, 128.0));
    }

    #[test]
    fn the_side_in_use_is_listed_first() {
        assert_eq!(sides_first(true), [true, false]);
        assert_eq!(sides_first(false), [false, true]);
    }

    #[test]
    fn the_gallery_search_folds_case_and_accents() {
        let names: Vec<String> = ["Catppuccin Latte", "Dracula", "Rosé Pine"]
            .iter()
            .map(|n| crate::settings_search::fold(n))
            .collect();
        assert_eq!(matching(&names, ""), [0, 1, 2]);
        assert_eq!(matching(&names, "  DRAC "), [1]);
        assert_eq!(matching(&names, "rose"), [2]);
        assert!(matching(&names, "zzz").is_empty());
    }
    #[test]
    fn a_card_is_current_when_its_name_is_the_stored_one_in_the_lookup_case_rule() {
        assert!(is_current_theme("Catppuccin Latte", "catppuccin latte"));
        assert!(is_current_theme("Dracula", "Dracula"));
        assert!(!is_current_theme("Dracula", "Nord"));
        assert!(!is_current_theme("Dracula", ""));
        // The two sides are told apart by the caller: a dark card against the light name is no match.
        let (dark, light) = ("ShellX", "Catppuccin Latte");
        assert!(is_current_theme("ShellX", dark));
        assert!(!is_current_theme("ShellX", light));
    }

    #[test]
    fn a_moved_grid_top_asks_for_another_frame_only_past_half_a_row() {
        assert!(!top_moved(500.0, 500.0, 64.0));
        assert!(!top_moved(500.0, 520.0, 64.0));
        assert!(top_moved(500.0, 540.0, 64.0));
        assert!(top_moved(500.0, 100.0, 64.0));
    }

    #[test]
    fn only_the_rows_that_meet_the_viewport_and_a_margin_are_built() {
        // (top, height) of 10 rows of 64.
        let rows: Vec<(f32, f32)> = (0..10).map(|n| (n as f32 * 64.0, 64.0)).collect();
        // Grid starts at 500 in the window; the viewport is 80..400: above the grid.
        assert_eq!(visible_span(&rows, (80.0, 400.0), 500.0, 64.0), 0..0);
        // Grid top at 100, viewport 80..400: rows 0..=4 (y 0..320), plus a margin row.
        assert_eq!(visible_span(&rows, (80.0, 400.0), 100.0, 64.0), 0..6);
        // Scrolled far down: grid top at -300, viewport 80..400 -> y 380..700.
        assert_eq!(visible_span(&rows, (80.0, 400.0), -300.0, 64.0), 4..10);
        assert_eq!(visible_span(&[], (0.0, 10.0), 0.0, 64.0), 0..0);
    }
}
