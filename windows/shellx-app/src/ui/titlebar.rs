//! Custom title bar (spec §7.1): sidebar toggle, search box, bell, settings,
//! then the Windows caption buttons. The bar is the window's drag area; each
//! interactive child occludes it, and the caption buttons report their
//! `WindowControlArea` so Windows hit-testing (snap layouts, double-click to
//! maximize, drag to move) behaves like a native caption.

use gpui::{
    ClickEvent, Context, Div, Pixels, Stateful, Window, WindowControlArea, div, prelude::*, px, svg,
};
use shellx_model::strings::{Lang, Str, t};

use super::assets::Icon;
use super::root::RootView;
use super::theme;

pub const HEIGHT: Pixels = px(crate::workspace::TITLEBAR_H);
const CAPTION_WIDTH: Pixels = px(46.0);
const ICON_SIZE: Pixels = px(16.0);
const SEARCH_MAX_WIDTH: Pixels = px(360.0);

// Segoe Fluent Icons / Segoe MDL2 Assets caption glyphs.
const GLYPH_MINIMIZE: &str = "\u{E921}";
const GLYPH_MAXIMIZE: &str = "\u{E922}";
const GLYPH_RESTORE: &str = "\u{E923}";
const GLYPH_CLOSE: &str = "\u{E8BB}";

pub fn render(lang: Lang, window: &Window, cx: &mut Context<RootView>) -> Div {
    let toggle = icon_button("titlebar-sidebar", Icon::WindowSidebar)
        .on_click(cx.listener(|this, _: &ClickEvent, _, cx| this.toggle_sidebar(cx)));
    // Notifications are display-only in the MVP (no badge, no panel).
    let bell = icon_button("titlebar-bell", Icon::BellRing);
    let settings = icon_button("titlebar-settings", Icon::Settings)
        .on_click(cx.listener(|this, _: &ClickEvent, _, cx| this.open_settings(cx)));

    div()
        .flex()
        .flex_row()
        .items_center()
        .flex_none()
        .w_full()
        .h(HEIGHT)
        .bg(theme::panel())
        .border_b_1()
        .border_color(theme::line())
        .window_control_area(WindowControlArea::Drag)
        .child(div().flex_none().pl(px(8.0)).child(toggle))
        .child(
            div()
                .flex_1()
                .min_w_0()
                .flex()
                .justify_center()
                .px(px(16.0))
                .child(search_box(lang)),
        )
        .child(
            div()
                .flex_none()
                .flex()
                .items_center()
                .gap(px(2.0))
                .pr(px(8.0))
                .child(bell)
                .child(settings),
        )
        .child(caption_buttons(window.is_maximized()))
}

/// 28 px square icon button: MUTED glyph, TEXT on hover. Occludes the drag
/// area so clicks land here instead of moving the window.
fn icon_button(id: &'static str, icon: Icon) -> Stateful<Div> {
    div()
        .id(id)
        .group(id)
        .occlude()
        .flex()
        .flex_none()
        .items_center()
        .justify_center()
        .size(px(28.0))
        .rounded(px(6.0))
        .cursor_pointer()
        .child(
            svg()
                .path(icon.path())
                .size(ICON_SIZE)
                .text_color(theme::muted())
                .group_hover(id, |style| style.text_color(theme::text())),
        )
}

/// Display only in the MVP: the command palette is a known cut, so a click
/// does nothing (it still occludes the drag area).
fn search_box(lang: Lang) -> Div {
    div()
        .occlude()
        .flex()
        .items_center()
        .gap(px(8.0))
        .w_full()
        .max_w(SEARCH_MAX_WIDTH)
        .h(px(26.0))
        .px(px(10.0))
        .bg(theme::raise())
        .border_1()
        .border_color(theme::border())
        .rounded(px(6.0))
        .text_color(theme::muted())
        .child(
            svg()
                .path(Icon::Search.path())
                .flex_none()
                .size(px(14.0))
                .text_color(theme::muted()),
        )
        .child(
            div()
                .min_w_0()
                .truncate()
                .child(t(lang, Str::SearchPlaceholder)),
        )
}

fn caption_buttons(maximized: bool) -> Div {
    let max_glyph = if maximized {
        GLYPH_RESTORE
    } else {
        GLYPH_MAXIMIZE
    };
    div()
        .flex()
        .flex_row()
        .flex_none()
        .h_full()
        .child(caption(GLYPH_MINIMIZE, WindowControlArea::Min, false))
        .child(caption(max_glyph, WindowControlArea::Max, false))
        .child(caption(GLYPH_CLOSE, WindowControlArea::Close, true))
}

/// One 46 px caption button. No click handler on purpose: Windows performs
/// the action from the `WindowControlArea` hit-test (HTMINBUTTON etc.), and a
/// GPUI handler that stopped the event would swallow it.
fn caption(glyph: &'static str, area: WindowControlArea, close: bool) -> Div {
    div()
        .occlude()
        .window_control_area(area)
        .flex()
        .flex_none()
        .items_center()
        .justify_center()
        .w(CAPTION_WIDTH)
        .h_full()
        .font(theme::caption_font())
        .text_size(theme::CAPTION_GLYPH_SIZE)
        .text_color(theme::text())
        .map(|button| {
            if close {
                button.hover(|style| style.bg(theme::close_hover()).text_color(theme::text_hi()))
            } else {
                button.hover(|style| style.bg(theme::raise()))
            }
        })
        .child(glyph)
}
