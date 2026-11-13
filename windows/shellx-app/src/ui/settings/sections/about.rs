//! Settings › About (moved from the 1.7.1 panel unchanged): the version with the test label,
//! the credits (cmux, the icons under CC BY 4.0, the fonts) and the source link.

use gpui::{Context, Div, FontWeight, div, prelude::*};
use shellx_model::strings::{Str, t};

use super::super::{SettingsView, card_body, muted, stack};
use crate::build_info;
use crate::ui::app::Services;
use crate::ui::controls::{card, section_header};
use crate::ui::theme;
use crate::ui::update_banner::open_https;

const SOURCE_URL: &str = "https://github.com/lephus/shellx";

pub fn render(view: &mut SettingsView, cx: &mut Context<SettingsView>) -> Div {
    let lang = cx.global::<Services>().lang;
    let body = card_body()
        .child(
            div()
                .text_color(theme::text_hi())
                .font_weight(FontWeight::SEMIBOLD)
                .child(build_info::about_version()),
        )
        .child(muted(t(lang, Str::CmuxCredits)))
        .child(muted(t(lang, Str::IconCredits)))
        .child(muted(t(lang, Str::FontCredits)))
        .child(
            div()
                .id("settings-source")
                .text_size(theme::SMALL_SIZE)
                .text_color(theme::primary_text())
                .cursor_pointer()
                .child(SOURCE_URL)
                .on_click(|_, _, cx| open_https(cx, SOURCE_URL)),
        );
    stack()
        .child(section_header(t(lang, Str::About).into()))
        .child(view.anchored("about", card().child(body)))
}
