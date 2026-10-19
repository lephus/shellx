//! Update UI (spec §11): the 32 px "update available" banner at the top of
//! the main area, and the forced-update overlay. Both only open `https://`
//! download links (`shellx_model::update::is_https`).

use gpui::{App, Div, Entity, FocusHandle, FontWeight, Stateful, div, prelude::*, px};
use shellx_model::palette;
use shellx_model::strings::{Lang, Str, minimum_version, t, update_available};
use shellx_model::update::is_https;

use super::account::AccountService;
use super::button::{Kind, button};
use super::theme;

pub const BANNER_H: f32 = 32.0;

/// Opens a download link; anything but https is ignored.
pub fn open_https(cx: &App, url: &str) {
    if is_https(url) {
        cx.open_url(url);
    }
}

/// 32 px banner: PRIMARY_SOFT fill, PRIMARY_LINE bottom border, PRIMARY_TEXT
/// label, a primary "Tải về" button and a close "×" (hidden until the next
/// check).
pub fn banner(
    lang: Lang,
    version: &str,
    url: Option<String>,
    account: Entity<AccountService>,
) -> Div {
    let download = url.is_some();
    div()
        .flex()
        .flex_row()
        .items_center()
        .gap(px(10.0))
        .flex_none()
        .w_full()
        .h(px(BANNER_H))
        .px(px(14.0))
        .bg(theme::hsla(palette::PRIMARY_SOFT))
        .border_b_1()
        .border_color(theme::hsla(palette::PRIMARY_LINE))
        .text_color(theme::hsla(palette::PRIMARY_TEXT))
        .child(
            div()
                .flex_1()
                .min_w_0()
                .truncate()
                .child(update_available(lang, version)),
        )
        .when(download, |row| {
            row.child(
                button(
                    "update-banner-download",
                    t(lang, Str::Download),
                    Kind::Primary,
                    false,
                )
                .py(px(1.0))
                .on_click(move |_, _, cx| {
                    if let Some(url) = &url {
                        open_https(cx, url);
                    }
                }),
            )
        })
        .child(
            div()
                .id("update-banner-close")
                .flex_none()
                .px(px(6.0))
                .cursor_pointer()
                .child("×")
                .on_click(move |_, _, cx| account.update(cx, |a, cx| a.hide_banner(cx))),
        )
}

/// Forced update: covers the window below the title bar, blocks mouse input
/// to the terminals (`occlude`) and swallows keys (the focus is on `focus`).
/// No way to skip it.
pub fn required_overlay(
    lang: Lang,
    min: &str,
    url: Option<String>,
    focus: &FocusHandle,
) -> Stateful<Div> {
    let download = url.is_some();
    let card = div()
        .flex()
        .flex_col()
        .gap(px(12.0))
        .w(px(380.0))
        .p(px(20.0))
        .rounded(px(10.0))
        .border_1()
        .border_color(theme::border())
        .bg(theme::raise())
        .child(
            div()
                .text_size(px(16.0))
                .font_weight(FontWeight::SEMIBOLD)
                .text_color(theme::text_hi())
                .child(t(lang, Str::UpdateRequired)),
        )
        .child(
            div()
                .text_color(theme::text())
                .child(minimum_version(lang, min)),
        )
        .when(download, |c| {
            c.child(
                div().flex().child(
                    button(
                        "update-required-download",
                        t(lang, Str::Download),
                        Kind::Primary,
                        false,
                    )
                    .on_click(move |_, _, cx| {
                        if let Some(url) = &url {
                            open_https(cx, url);
                        }
                    }),
                ),
            )
        });
    div()
        .id("update-required-overlay")
        .track_focus(focus)
        .occlude()
        .absolute()
        .top(px(crate::workspace::TITLEBAR_H))
        .left_0()
        .right_0()
        .bottom_0()
        .flex()
        .items_center()
        .justify_center()
        .bg(theme::bg().opacity(0.85))
        .on_key_down(|_, _, cx| cx.stop_propagation())
        .child(card)
}
