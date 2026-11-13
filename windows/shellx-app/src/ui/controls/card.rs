//! The Settings card, its rows and the section header above it (inventory §D): a card has
//! radius 13 and a 1 px border and no title; a row has padding 14 × 9, its title (13,
//! medium) and subtitle (10, muted, at most 2 lines) on the left, its control on the right,
//! and a 1 px divider above it. A header is a separate line placed above a card, as the Mac's
//! `SettingsSectionHeader` is.
//!
//! The caller adds rows with `card().child(row(..))`. Each row draws its own divider; the
//! card lifts its first row 1 px so that row's divider lies on the card's border, where the
//! card clips it (GPUI clips to a rectangle inside the border, so the line cannot show past
//! the rounded corners).

use gpui::{Div, FontWeight, IntoElement, SharedString, div, prelude::*, px};

use super::super::theme;
use super::DISABLED_OPACITY;

const RADIUS: f32 = 13.0;
const PAD_X: f32 = 14.0;
const PAD_Y: f32 = 9.0;

pub fn card() -> Div {
    div()
        .flex()
        .flex_col()
        .w_full()
        .rounded(px(RADIUS))
        .border_1()
        .border_color(theme::line())
        .bg(theme::panel())
        .overflow_hidden()
        .child(div().h_0().mb(px(-1.0)))
}

/// The Mac's `SettingsSectionHeader`: 13 semibold in the muted colour, 2 px in from the left,
/// 2 px closer to the card below it than the pane's 14 spacing.
pub fn section_header(title: SharedString) -> Div {
    div()
        .pl(px(2.0))
        .mb(px(-2.0))
        .text_size(px(13.0))
        .font_weight(FontWeight::SEMIBOLD)
        .text_color(theme::muted())
        .child(title)
}

/// `disabled` dims the title and subtitle; the control draws its own disabled state.
pub fn row(
    title: SharedString,
    subtitle: Option<SharedString>,
    control: impl IntoElement,
    disabled: bool,
) -> Div {
    let has_subtitle = subtitle.is_some();
    div()
        .flex()
        .flex_row()
        .items_center()
        .gap(px(12.0))
        .px(px(PAD_X))
        .py(px(PAD_Y))
        .border_t_1()
        .border_color(theme::line())
        .child(
            div()
                .flex()
                .flex_col()
                .flex_1()
                .min_w_0()
                .when(has_subtitle, |labels| labels.gap(px(3.0)))
                .when(disabled, |labels| labels.opacity(DISABLED_OPACITY))
                .child(
                    div()
                        .text_size(px(13.0))
                        .font_weight(FontWeight::MEDIUM)
                        .text_color(theme::text_hi())
                        .child(title),
                )
                .children(subtitle.map(|subtitle| {
                    div()
                        .text_size(px(10.0))
                        .text_color(theme::muted())
                        .line_clamp(2)
                        .child(subtitle)
                })),
        )
        .child(div().flex().flex_none().justify_end().child(control))
}
