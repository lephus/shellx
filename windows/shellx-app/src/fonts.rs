//! Embedded fonts (all SIL OFL 1.1; license texts sit next to the files in
//! `assets/fonts/`). The window registers them at startup, so the terminal
//! and the wordmark look the same on every machine.

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
