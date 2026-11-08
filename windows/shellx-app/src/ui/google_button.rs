//! The branded "Continue with Google" button (`shellx_model::google_button`, Google's Light theme on the
//! dark UI): a white 40 px rectangle with a 1 px #747775 border and 4 px corners, Google's own "G"
//! 12 px from the left edge (only when the build found the official file), then the label in
//! Google Sans Medium 14/20 (only when that face is embedded; else the UI font at the same weight).
//! The "G" is Google's trademark, shown as downloaded: never recolored or resized.

use gpui::{
    Div, Font, FontFallbacks, FontWeight, ImageSource, Resource, SharedString, Stateful, div, font,
    img, prelude::*, px, rgb,
};
use shellx_model::google_button as spec;

use super::theme;
use crate::fonts;
use crate::icons;

/// Label font: Google Sans (then its legacy family, then the UI font), or the UI font at medium weight.
fn label_font() -> Font {
    let mut f = if fonts::has_google_sans() {
        let mut f = font(fonts::GOOGLE_SANS_FAMILY);
        f.fallbacks = Some(FontFallbacks::from_fonts(vec![
            spec::FONT_FAMILY_LEGACY.to_string(),
            theme::UI_FAMILY.to_string(),
        ]));
        f
    } else {
        theme::ui_font()
    };
    f.weight = FontWeight(spec::FONT_WEIGHT);
    f
}

/// The button shell; the caller adds `on_click`.
pub fn google_button(id: &'static str, label: &'static str) -> Stateful<Div> {
    let label: SharedString = label.into();
    div()
        .id(id)
        .flex()
        .flex_none()
        .flex_row()
        .items_center()
        .gap(px(spec::LOGO_GAP))
        .h(px(spec::HEIGHT))
        .pl(px(spec::PAD_LEFT))
        .pr(px(spec::PAD_RIGHT))
        .rounded(px(spec::CORNER_RADIUS))
        .border_1()
        .border_color(rgb(spec::STROKE))
        .bg(rgb(spec::FILL))
        .cursor_pointer()
        .when(icons::google_mark().is_some(), |b| {
            b.child(
                img(ImageSource::Resource(Resource::Embedded(
                    icons::GOOGLE_MARK_PATH.into(),
                )))
                .flex_none()
                .size(px(spec::LOGO_SIZE)),
            )
        })
        .child(
            div()
                .font(label_font())
                .text_size(px(spec::FONT_SIZE))
                .line_height(px(spec::LINE_HEIGHT))
                .text_color(rgb(spec::TEXT))
                .child(label),
        )
}
