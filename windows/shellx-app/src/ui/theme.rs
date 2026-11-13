//! Spec §7.4 and §5.5 for GPUI: the active theme's colours as `gpui::Hsla`, the UI / wordmark /
//! caption fonts and the text sizes. Every colour the window draws comes from here: the chrome
//! (`shellx_model::chrome`) and the terminal theme of the one process-wide [`Active`], which
//! `SettingsService` replaces when a theme setting or the window's appearance changes. Solid
//! colors only: no gradients, glows or colored shadows anywhere in the UI.

use std::sync::{LazyLock, PoisonError, RwLock};

use gpui::{Font, FontFallbacks, FontWeight, Hsla, Pixels, font, px};
use shellx_model::chrome::{Chrome, accent_color, chrome as derive_chrome};
use shellx_model::palette::Rgba;
use shellx_model::settings::Settings;
use shellx_model::theme_file::{self, TermTheme, ThemeSet, is_dark_mode};
use shellx_model::workspace_colors::{self, CardStyle};

use crate::fonts;

/// UI text (spec §7.4): Segoe UI Variable Text, then Segoe UI.
pub const UI_FAMILY: &str = "Segoe UI Variable Text";
pub const UI_FALLBACK: &str = "Segoe UI";
/// Windows caption glyphs: Segoe Fluent Icons (Windows 11), then Segoe MDL2
/// Assets (Windows 10).
pub const CAPTION_FAMILY: &str = "Segoe Fluent Icons";
pub const CAPTION_FALLBACK: &str = "Segoe MDL2 Assets";

pub const UI_SIZE: Pixels = px(13.0);
pub const SMALL_SIZE: Pixels = px(11.0);
pub const PILL_SIZE: Pixels = px(10.0);
pub const CAPTION_GLYPH_SIZE: Pixels = px(10.0);

/// The theme in use: the window's chrome and the terminals' colours.
#[derive(Clone, Debug, PartialEq)]
pub struct Active {
    pub chrome: Chrome,
    pub term: TermTheme,
}

impl Active {
    /// The theme `settings` choose: the light or dark side of the pair (`system_dark` is the
    /// window's appearance, for Appearance System), the accent (`system_accent` is the Windows
    /// accent, for Accent System) and the sidebar background.
    pub fn resolve(
        settings: &Settings,
        themes: &ThemeSet,
        system_dark: bool,
        system_accent: Option<Rgba>,
    ) -> Active {
        let dark = is_dark_mode(settings.appearance, system_dark);
        let term = theme_file::active(themes, settings, dark);
        let chrome = derive_chrome(
            &term,
            accent_color(&settings.accent, system_accent),
            settings.sidebar_background,
            settings.sidebar_color,
        );
        Active { chrome, term }
    }
}

/// The active theme and how many times it was replaced (a terminal compares the count with the
/// one it last took its colours at).
struct Current {
    active: Active,
    generation: u64,
}

/// Until the settings are read (and in `--smoke`): the default settings' theme, ShellX.
static CURRENT: LazyLock<RwLock<Current>> = LazyLock::new(|| {
    let active = Active::resolve(&Settings::default(), &ThemeSet::new(Vec::new()), true, None);
    RwLock::new(Current {
        active,
        generation: 0,
    })
});

fn read<T>(f: impl FnOnce(&Current) -> T) -> T {
    f(&CURRENT.read().unwrap_or_else(PoisonError::into_inner))
}

/// A copy of the process-wide current theme.
pub fn active() -> Active {
    read(|current| current.active.clone())
}

/// Replaces the current theme. The caller then refreshes every window; each terminal takes the
/// new colours on its next frame (`generation`).
pub fn set_active(active: Active) {
    let mut current = CURRENT.write().unwrap_or_else(PoisonError::into_inner);
    current.active = active;
    current.generation += 1;
}

/// Counts `set_active` calls.
pub fn generation() -> u64 {
    read(|current| current.generation)
}

fn chrome() -> Chrome {
    read(|current| current.active.chrome)
}

pub fn hsla(c: Rgba) -> Hsla {
    gpui::Rgba {
        r: f32::from(c.r) / 255.0,
        g: f32::from(c.g) / 255.0,
        b: f32::from(c.b) / 255.0,
        a: c.a,
    }
    .into()
}

pub fn bg() -> Hsla {
    hsla(chrome().bg)
}
pub fn panel() -> Hsla {
    hsla(chrome().panel)
}
pub fn raise() -> Hsla {
    hsla(chrome().raise)
}
pub fn line() -> Hsla {
    hsla(chrome().line)
}
pub fn border() -> Hsla {
    hsla(chrome().border)
}
pub fn text() -> Hsla {
    hsla(chrome().text)
}
pub fn text_hi() -> Hsla {
    hsla(chrome().text_hi)
}
pub fn muted() -> Hsla {
    hsla(chrome().muted)
}
pub fn primary() -> Hsla {
    hsla(chrome().primary)
}
pub fn primary_soft() -> Hsla {
    hsla(chrome().primary_soft)
}
pub fn primary_line() -> Hsla {
    hsla(chrome().primary_line)
}
/// The accent as text on the window's surfaces.
pub fn primary_text() -> Hsla {
    hsla(chrome().primary_text)
}
/// The primary colour as a colour well takes it (a Settings colour row with no colour of its
/// own, Selection Highlight's "Default", shows it).
pub fn primary_rgba() -> Rgba {
    chrome().primary
}
/// Status dots and fills: the same hues on every theme.
pub fn running() -> Hsla {
    hsla(chrome().running)
}
pub fn done() -> Hsla {
    hsla(chrome().done)
}
pub fn error() -> Hsla {
    hsla(chrome().error)
}
/// Status hues as text on the window's surfaces (no text is drawn in the running hue).
pub fn done_text() -> Hsla {
    hsla(chrome().done_text)
}
pub fn error_text() -> Hsla {
    hsla(chrome().error_text)
}
/// Close caption button hover: the error hue at 0.9 (solid, no glow).
pub fn close_hover() -> Hsla {
    hsla(chrome().error.with_alpha(0.9))
}
/// The title of the selected tab in the focused region.
pub fn selection_title() -> Hsla {
    hsla(chrome().selection_title)
}
/// The bar under the selected tab of a region that is not focused.
pub fn indicator_unfocused() -> Hsla {
    hsla(chrome().indicator_unfocused)
}
/// Hover fill on the window's surfaces: tab bar, menus, the machine list.
pub fn panel_hover() -> Hsla {
    hsla(chrome().panel_hover)
}
/// Selected text in a text field.
pub fn field_selection() -> Hsla {
    hsla(chrome().field_selection)
}
/// The sidebar and what is drawn on it.
pub fn sidebar_bg() -> Hsla {
    hsla(chrome().sidebar_bg)
}
pub fn sidebar_text() -> Hsla {
    hsla(chrome().sidebar_text)
}
pub fn sidebar_muted() -> Hsla {
    hsla(chrome().sidebar_muted)
}
/// The sidebar's edge and footer line.
pub fn sidebar_line() -> Hsla {
    hsla(chrome().sidebar_line)
}
/// A workspace card under the pointer.
pub fn session_hover() -> Hsla {
    hsla(chrome().session_hover)
}
/// The accent as text on the sidebar: the pairing code, the update pill, a primary button.
pub fn sidebar_primary_text() -> Hsla {
    hsla(chrome().sidebar_primary_text)
}
/// An icon under the pointer on the sidebar.
pub fn sidebar_icon_hover() -> Hsla {
    hsla(chrome().sidebar_icon_hover)
}
/// What a workspace card of palette colour `color` draws (rail, fill, outline) on this theme's
/// sidebar, as the model decides it.
pub fn card_style(settings: &Settings, color: Rgba, selected: bool) -> CardStyle {
    workspace_colors::card_style(settings, &chrome(), color, selected)
}
/// The title and secondary text of a card with `fill`, made to read on it.
pub fn card_text(fill: Option<Rgba>, selected: bool) -> (Hsla, Hsla) {
    let (title, muted) = workspace_colors::card_text(&chrome(), fill, selected);
    (hsla(title), hsla(muted))
}
/// The terminal's default background and text.
pub fn term_bg() -> Hsla {
    hsla(read(|current| current.active.term.background))
}
pub fn term_fg() -> Hsla {
    hsla(read(|current| current.active.term.foreground))
}

fn with_fallback(family: &str, fallback: &str) -> Font {
    let mut f = font(family.to_string());
    f.fallbacks = Some(FontFallbacks::from_fonts(vec![fallback.to_string()]));
    f
}

pub fn ui_font() -> Font {
    with_fallback(UI_FAMILY, UI_FALLBACK)
}

pub fn caption_font() -> Font {
    with_fallback(CAPTION_FAMILY, CAPTION_FALLBACK)
}

/// "ShellX" wordmark: the embedded Space Grotesk Bold.
pub fn wordmark_font() -> Font {
    let mut f = font(fonts::DISPLAY_FAMILY);
    f.weight = FontWeight::BOLD;
    f
}

#[cfg(test)]
mod tests {
    use std::path::{Path, PathBuf};

    use shellx_model::chrome::chrome;
    use shellx_model::settings::{Accent, Appearance, Settings, SidebarBackground};
    use shellx_model::theme_file::{ThemeSet, shellx};

    use shellx_model::palette;

    use super::{Active, Rgba};

    #[test]
    fn the_default_settings_give_the_shellx_theme() {
        let themes = ThemeSet::new(Vec::new());
        let defaults = Active::resolve(&Settings::default(), &themes, false, None);
        assert_eq!(defaults.term, shellx());
        assert_eq!(
            defaults.chrome,
            chrome(
                &shellx(),
                palette::PRIMARY,
                SidebarBackground::FollowTheme,
                palette::PANEL
            )
        );
        assert_eq!(defaults.chrome.bg, palette::BG);
        // Nothing has replaced the process-wide theme in the tests.
        assert_eq!(super::active(), defaults);
    }

    #[test]
    fn the_settings_choose_the_theme_the_accent_and_the_sidebar() {
        let themes = ThemeSet::new(Vec::new());
        let mut s = Settings {
            theme_dark: "Dracula".into(),
            ..Settings::default()
        };
        assert_eq!(
            Active::resolve(&s, &themes, false, None).term.name,
            "Dracula"
        );
        s.appearance = Appearance::Light;
        assert_eq!(
            Active::resolve(&s, &themes, true, None).term.name,
            "Catppuccin Latte"
        );
        // System follows the window's appearance.
        s.appearance = Appearance::System;
        assert_eq!(
            Active::resolve(&s, &themes, true, None).term.name,
            "Dracula"
        );
        let light = Active::resolve(&s, &themes, false, None);
        assert_eq!(light.term.name, "Catppuccin Latte");
        assert_eq!(light.chrome.bg, light.term.background);
        // Accent System takes the Windows accent; Custom sidebar its colour.
        let windows_blue = Rgba::rgb(0x0078d7);
        s.accent = Accent::System;
        s.sidebar_background = SidebarBackground::Custom;
        s.sidebar_color = Rgba::rgb(0x123456);
        let chosen = Active::resolve(&s, &themes, false, Some(windows_blue));
        assert_eq!(chosen.chrome.primary, windows_blue);
        assert_eq!(chosen.chrome.sidebar_bg, Rgba::rgb(0x123456));
    }

    /// Every `.rs` file under `dir`, sorted.
    fn rust_files(dir: &Path, out: &mut Vec<PathBuf>) {
        let mut entries: Vec<PathBuf> = std::fs::read_dir(dir)
            .unwrap()
            .map(|entry| entry.unwrap().path())
            .collect();
        entries.sort();
        for path in entries {
            if path.is_dir() {
                rust_files(&path, out);
            } else if path.extension().is_some_and(|ext| ext == "rs") {
                out.push(path);
            }
        }
    }

    /// A constant's name: upper-case letters, digits and `_` (`PRIMARY`, `TERM_BG`), not a type
    /// such as `Rgba` or `Status`.
    fn is_constant(name: &str) -> bool {
        name.starts_with(|c: char| c.is_ascii_uppercase())
            && name
                .chars()
                .all(|c| c.is_ascii_uppercase() || c.is_ascii_digit() || c == '_')
    }

    /// The colour names and literals in `text`, as "line: what".
    fn colour_uses(text: &str) -> Vec<String> {
        let line_of = |at: usize| text[..at].matches('\n').count() + 1;
        let mut found = Vec::new();
        for (at, _) in text.match_indices("palette::") {
            let rest = &text[at + "palette::".len()..];
            // `palette::{A, B}` names each item; `palette::A` one.
            let names: Vec<&str> = match rest.strip_prefix('{') {
                Some(group) => group[..group.find('}').unwrap_or(group.len())]
                    .split(',')
                    .collect(),
                None => vec![rest],
            };
            for name in names {
                let name = name.trim_start();
                let end = name
                    .find(|c: char| !(c.is_ascii_alphanumeric() || c == '_'))
                    .unwrap_or(name.len());
                if is_constant(&name[..end]) {
                    found.push(format!("{}: palette::{}", line_of(at), &name[..end]));
                }
            }
        }
        for literal in ["rgb(0x", "rgba(0x"] {
            for (at, _) in text.match_indices(literal) {
                let line = text.lines().nth(line_of(at) - 1).unwrap_or("").trim();
                found.push(format!("{}: {line}", line_of(at)));
            }
        }
        found
    }

    #[test]
    fn no_ui_file_names_a_palette_colour_or_a_literal() {
        let src = Path::new(env!("CARGO_MANIFEST_DIR")).join("src");
        let mut files = vec![src.join("term_core.rs")];
        rust_files(&src.join("ui"), &mut files);
        // The theme maps the palette; the Google button keeps Google's colours.
        let exempt = [src.join("ui/theme.rs"), src.join("ui/google_button.rs")];
        let mut uses = Vec::new();
        for file in files.iter().filter(|f| !exempt.contains(f)) {
            let text = std::fs::read_to_string(file).unwrap();
            let name = file.strip_prefix(&src).unwrap().display().to_string();
            uses.extend(
                colour_uses(&text)
                    .into_iter()
                    .map(|u| format!("{name}:{u}")),
            );
        }
        assert!(
            uses.is_empty(),
            "{} colours bypass ui/theme.rs:\n{}",
            uses.len(),
            uses.join("\n")
        );
    }

    #[test]
    fn the_guard_sees_names_imports_and_literals_but_not_types() {
        let text = "use shellx_model::palette::{self, Rgba, Status};\n\
                    use shellx_model::palette::{\n    PRIMARY_LINE, Pill,\n};\n\
                    let a = palette::PRIMARY.with_alpha(0.3);\n\
                    let b = Rgba::rgb(0x112233);\n\
                    let c = gpui::rgba(0x11223344);\n";
        assert_eq!(
            colour_uses(text),
            [
                "2: palette::PRIMARY_LINE",
                "5: palette::PRIMARY",
                "6: let b = Rgba::rgb(0x112233);",
                "7: let c = gpui::rgba(0x11223344);",
            ]
        );
    }
}
