//! Update UI (spec §11): the forced-update overlay, and `open_https` for it
//! and for the sidebar footer's "update available" pill (`sidebar.rs`). Only
//! `https://` download links are opened (`shellx_model::update::is_https`).

use gpui::{App, Div, FocusHandle, FontWeight, KeyDownEvent, Stateful, div, prelude::*, px};
use shellx_model::keys::{KeyIn, is_window_system_key};
use shellx_model::strings::{Lang, Str, minimum_version, t};
use shellx_model::update::is_https;

use super::button::{Kind, button};
use super::theme;

/// Opens a download link; anything but https is ignored.
pub fn open_https(cx: &App, url: &str) {
    if is_https(url) {
        cx.open_url(url);
    }
}

/// Forced update: covers the window below the title bar, blocks mouse input
/// to the terminals (`occlude`) and swallows keys (the focus is on `focus`)
/// except the window's own Alt+F4 and Alt+Space. No way to skip it.
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
        .on_key_down(|event: &KeyDownEvent, _, cx| {
            let keystroke = &event.keystroke;
            let mods = keystroke.modifiers;
            let key = KeyIn {
                key: keystroke.key.as_str(),
                ctrl: mods.control,
                alt: mods.alt,
                shift: mods.shift,
                win: mods.platform,
            };
            // Alt+F4 and Alt+Space go on to Windows (R2 F7, Ruling 37).
            if !is_window_system_key(&key) {
                cx.stop_propagation();
            }
        })
        .child(card)
}
