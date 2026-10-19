//! Buttons (mockup `.btn` / `.btn.pri`): solid soft fills and a 1 px border,
//! no gradients or glows. Primary: PRIMARY_SOFT fill, PRIMARY_LINE border,
//! PRIMARY_TEXT label, semibold. Secondary: RAISE fill, BORDER, TEXT.

use gpui::{Div, ElementId, FontWeight, SharedString, Stateful, div, prelude::*, px};
use shellx_model::palette;

use super::theme;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Kind {
    Primary,
    Secondary,
}

/// A button shell; the caller adds `on_click` (skipped when `disabled`).
pub fn button(
    id: impl Into<ElementId>,
    label: impl Into<SharedString>,
    kind: Kind,
    disabled: bool,
) -> Stateful<Div> {
    let (bg, border, fg) = match kind {
        Kind::Primary => (
            theme::hsla(palette::PRIMARY_SOFT),
            theme::hsla(palette::PRIMARY_LINE),
            theme::hsla(palette::PRIMARY_TEXT),
        ),
        Kind::Secondary => (theme::raise(), theme::border(), theme::text()),
    };
    let label: SharedString = label.into();
    div()
        .id(id)
        .flex()
        .flex_none()
        .items_center()
        .justify_center()
        .px(px(10.0))
        .py(px(4.0))
        .rounded(px(7.0))
        .border_1()
        .border_color(border)
        .bg(bg)
        .text_color(fg)
        .when(kind == Kind::Primary, |el| {
            el.font_weight(FontWeight::SEMIBOLD)
        })
        .when(disabled, |el| el.opacity(0.5))
        .when(!disabled, |el| {
            el.cursor_pointer()
                .hover(|style| style.border_color(theme::hsla(palette::PRIMARY_LINE)))
        })
        .child(label)
}
