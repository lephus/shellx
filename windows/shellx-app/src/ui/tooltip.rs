//! The plain tooltip every icon button uses.

use gpui::{AnyView, App, Context, IntoElement, Render, SharedString, Window, div, prelude::*, px};

use super::theme;

/// Plain tooltip: RAISE box, 1 px BORDER, small TEXT label.
pub(super) struct Tooltip {
    text: SharedString,
}

impl Tooltip {
    pub(super) fn view(text: SharedString, cx: &mut App) -> AnyView {
        cx.new(|_| Tooltip { text }).into()
    }
}

impl Render for Tooltip {
    fn render(&mut self, _: &mut Window, _: &mut Context<Self>) -> impl IntoElement {
        div()
            .px(px(8.0))
            .py(px(4.0))
            .bg(theme::raise())
            .border_1()
            .border_color(theme::border())
            .rounded(px(6.0))
            .font(theme::ui_font())
            .text_size(theme::SMALL_SIZE)
            .text_color(theme::text())
            .child(self.text.clone())
    }
}
