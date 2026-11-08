//! Google's custom "Sign in with Google" button rules (Light theme).

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn google_button_matches_the_mac_and_the_branding_page() {
        assert_eq!((FILL, STROKE, TEXT), (0xFFFFFF, 0x747775, 0x1F1F1F));
        assert_eq!(
            [HEIGHT, CORNER_RADIUS, STROKE_WIDTH, LOGO_SIZE, PAD_LEFT, LOGO_GAP, PAD_RIGHT, FONT_SIZE, LINE_HEIGHT],
            [40.0, 4.0, 1.0, 20.0, 12.0, 10.0, 12.0, 14.0, 20.0]
        );
        assert_eq!((FONT_FAMILY, FONT_FAMILY_LEGACY, FONT_WEIGHT), ("Google Sans", "Google Sans Medium", 500.0));
    }
}
