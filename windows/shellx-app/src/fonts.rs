//! Embedded fonts (both SIL OFL 1.1; license texts sit next to the files in
//! `assets/fonts/`). The window registers them at startup, so the terminal
//! and the wordmark look the same on every machine.

pub const TERMINAL_FAMILY: &str = "JetBrains Mono";
pub const DISPLAY_FAMILY: &str = "Space Grotesk";

pub fn embedded() -> Vec<&'static [u8]> {
    vec![
        include_bytes!("../assets/fonts/JetBrainsMono-Regular.ttf").as_slice(),
        include_bytes!("../assets/fonts/JetBrainsMono-Bold.ttf").as_slice(),
        include_bytes!("../assets/fonts/JetBrainsMono-Italic.ttf").as_slice(),
        include_bytes!("../assets/fonts/JetBrainsMono-BoldItalic.ttf").as_slice(),
        include_bytes!("../assets/fonts/SpaceGrotesk-Bold.ttf").as_slice(),
    ]
}

/// True when `data` starts with a TrueType / OpenType magic number.
pub fn has_font_magic(data: &[u8]) -> bool {
    matches!(data.get(..4), Some([0, 1, 0, 0] | b"true" | b"OTTO"))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn five_embedded_fonts_are_truetype() {
        let fonts = embedded();
        assert_eq!(fonts.len(), 5);
        assert!(fonts.iter().all(|f| has_font_magic(f)));
    }
}
