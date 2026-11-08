//! Google's custom "Sign in with Google" button rules, Light theme in every appearance
//! (https://developers.google.com/identity/branding-guidelines). The same numbers as the Mac's
//! `GoogleSignInButtonSpec`; the "G" itself is Google's own file and lives in the app's assets.

pub const FILL: u32 = 0xFFFFFF;
pub const STROKE: u32 = 0x747775;
pub const TEXT: u32 = 0x1F1F1F;
pub const HEIGHT: f32 = 40.0;
pub const CORNER_RADIUS: f32 = 4.0;
pub const STROKE_WIDTH: f32 = 1.0;
pub const LOGO_SIZE: f32 = 20.0;
pub const PAD_LEFT: f32 = 12.0;
pub const LOGO_GAP: f32 = 10.0;
pub const PAD_RIGHT: f32 = 12.0;
pub const FONT_SIZE: f32 = 14.0;
pub const LINE_HEIGHT: f32 = 20.0;
/// Typographic family of the static Medium face.
pub const FONT_FAMILY: &str = "Google Sans";
/// Its legacy (name ID 1) family, tried second.
pub const FONT_FAMILY_LEGACY: &str = "Google Sans Medium";
pub const FONT_WEIGHT: f32 = 500.0;

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
