//! Embedded fonts (all SIL OFL 1.1; license texts sit next to the files in
//! `assets/fonts/`). The window registers them at startup, so the terminal
//! and the wordmark look the same on every machine.

use gpui::{App, Font, FontFallbacks, SharedString, font, px};
use shellx_model::settings::is_monospace;

pub const TERMINAL_FAMILY: &str = "JetBrains Mono";
pub const DISPLAY_FAMILY: &str = "Space Grotesk";
/// Typographic family of the Google Sans Medium face (the "Continue with Google" label).
pub const GOOGLE_SANS_FAMILY: &str = "Google Sans";

/// The Google Sans Medium face is embedded (cfg `shellx_google_sans`: the TTF and its OFL text are in
/// `assets/fonts/`).
pub fn has_google_sans() -> bool {
    cfg!(shellx_google_sans)
}

pub fn embedded() -> Vec<&'static [u8]> {
    #[cfg_attr(not(shellx_google_sans), allow(unused_mut))]
    let mut fonts = vec![
        include_bytes!("../assets/fonts/JetBrainsMono-Regular.ttf").as_slice(),
        include_bytes!("../assets/fonts/JetBrainsMono-Bold.ttf").as_slice(),
        include_bytes!("../assets/fonts/JetBrainsMono-Italic.ttf").as_slice(),
        include_bytes!("../assets/fonts/JetBrainsMono-BoldItalic.ttf").as_slice(),
        include_bytes!("../assets/fonts/SpaceGrotesk-Bold.ttf").as_slice(),
    ];
    #[cfg(shellx_google_sans)]
    fonts.push(include_bytes!("../assets/fonts/GoogleSans-Medium.ttf").as_slice());
    fonts
}

/// Whether `family` is installed (or embedded): the one test both the terminal's font and the
/// Font picker's "(not installed)" use.
pub fn is_installed(family: &str, cx: &App) -> bool {
    cx.text_system().all_font_names().iter().any(|n| n == family)
}

/// The font a terminal draws with: `family` when it is installed (or embedded), otherwise the
/// default (JetBrains Mono), with system fallbacks for glyphs the family lacks.
pub fn terminal_font(family: Option<&str>, cx: &App) -> Font {
    let installed = family.filter(|name| is_installed(name, cx));
    let mut f = font(installed.unwrap_or(TERMINAL_FAMILY).to_string());
    f.fallbacks = Some(FontFallbacks::from_fonts(vec![
        "Cascadia Mono".into(),
        "Consolas".into(),
        "Segoe UI".into(),
        "Segoe UI Emoji".into(),
        "Segoe UI Symbol".into(),
    ]));
    f
}

/// The installed families whose `i` and `M` have the same advance, sorted: the Font picker's
/// list after "Default". It measures every family, so it is called once when the section
/// opens, never per frame.
pub fn monospace_families(cx: &App) -> Vec<SharedString> {
    let system = cx.text_system();
    let size = px(16.0);
    let mut names: Vec<String> = system
        .all_font_names()
        .into_iter()
        .filter(|name| !name.starts_with(['.', '@']))
        .filter(|name| {
            let id = system.resolve_font(&font(name.clone()));
            match (system.advance(id, size, 'i'), system.advance(id, size, 'M')) {
                (Ok(i), Ok(m)) => is_monospace(f32::from(i.width), f32::from(m.width)),
                _ => false,
            }
        })
        .collect();
    names.sort_by_key(|name| name.to_lowercase());
    names.dedup();
    names.into_iter().map(SharedString::from).collect()
}

/// True when `data` starts with a TrueType / OpenType magic number.
pub fn has_font_magic(data: &[u8]) -> bool {
    matches!(data.get(..4), Some([0, 1, 0, 0] | b"true" | b"OTTO"))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn embedded_fonts_are_truetype_and_google_sans_follows_the_build() {
        let fonts = embedded();
        assert_eq!(fonts.len(), 5 + usize::from(has_google_sans()));
        assert_eq!(has_google_sans(), cfg!(shellx_google_sans));
        assert!(fonts.iter().all(|f| has_font_magic(f)));
    }
}
