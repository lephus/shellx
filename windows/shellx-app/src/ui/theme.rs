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
pub const WORDMARK_SIZE: Pixels = px(16.0);
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
