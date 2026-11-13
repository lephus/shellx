//! Spec §7.4 for GPUI: the `shellx_model::palette` tokens as `gpui::Hsla`,
//! the UI / wordmark / caption fonts and the text sizes. Solid colors only:
//! no gradients, glows or colored shadows anywhere in the UI.

use gpui::{Font, FontFallbacks, FontWeight, Hsla, Pixels, font, px};
use shellx_model::palette::{self, Rgba};

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
/// Sidebar like the Mac's: brand name, machine and workspace titles, the
/// machines header.
pub const BRAND_SIZE: Pixels = px(14.0);
pub const CARD_TITLE_SIZE: Pixels = px(12.0);
pub const HEADER_SIZE: Pixels = px(10.5);
pub const CAPTION_GLYPH_SIZE: Pixels = px(10.0);

/// Sidebar session rows (mockup `.sess.cur` / `.sess:hover`).
pub const SESSION_SELECTED: Rgba = Rgba::rgb(0x1a1430);
pub const SESSION_HOVER: Rgba = Rgba::rgb(0x161026);

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
    hsla(palette::BG)
}
pub fn panel() -> Hsla {
    hsla(palette::PANEL)
}
pub fn raise() -> Hsla {
    hsla(palette::RAISE)
}
pub fn line() -> Hsla {
    hsla(palette::LINE)
}
pub fn border() -> Hsla {
    hsla(palette::BORDER)
}
pub fn text() -> Hsla {
    hsla(palette::TEXT)
}
pub fn text_hi() -> Hsla {
    hsla(palette::TEXT_HI)
}
pub fn muted() -> Hsla {
    hsla(palette::MUTED)
}
pub fn done() -> Hsla {
    hsla(palette::DONE)
}
pub fn primary() -> Hsla {
    hsla(palette::PRIMARY)
}
pub fn primary_soft() -> Hsla {
    hsla(palette::PRIMARY_SOFT)
}
pub fn primary_line() -> Hsla {
    hsla(palette::PRIMARY_LINE)
}
pub fn primary_text() -> Hsla {
    hsla(palette::PRIMARY_TEXT)
}
/// The primary colour as a colour well takes it (a Settings colour row with no colour of its
/// own, Selection Highlight's "Default", shows it).
pub fn primary_rgba() -> Rgba {
    palette::PRIMARY
}
pub fn error() -> Hsla {
    hsla(palette::ERROR)
}
/// Close caption button hover: ERROR at 0.9 (solid, no glow).
pub fn close_hover() -> Hsla {
    hsla(palette::ERROR.with_alpha(0.9))
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
            uses.extend(colour_uses(&text).into_iter().map(|u| format!("{name}:{u}")));
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
