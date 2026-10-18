//! Machine sidebar (spec §7.1 items 1-3 and 6): logo + wordmark, the
//! "MÁY CỦA BẠN" header, one group per machine from
//! `shellx_model::sidebar::build_groups`, and the end-to-end footer.
//! "THIẾT BỊ ĐANG KẾT NỐI" (item 5) is out of the MVP.
//! Under this PC: one session row per local tab (click selects the tab),
//! and a "+" on the group header that opens a new local tab.

use gpui::{
    AnyView, App, ClickEvent, Context, Div, FontWeight, ImageSource, IntoElement, Pixels, Render,
    Resource, SharedString, Stateful, Window, div, img, prelude::*, px, svg,
};
use shellx_model::palette::{Pill, Status};
use shellx_model::sidebar::{MachineGroup, MachineIcon};
use shellx_model::strings::{Lang, Str, t};
use shellx_model::tabs::TabId;

use super::assets::Icon;
use super::root::RootView;
use super::theme;
use crate::shell_info::LOCAL_MACHINE_ID;

pub const WIDTH: Pixels = px(crate::workspace::SIDEBAR_W);

/// One session row under this PC: one per local tab.
pub struct SessionRow {
    pub tab: TabId,
    /// The tab's focused pane title (`session_title`).
    pub title: String,
    pub selected: bool,
    /// `Status::pill` decides the pill; local shells are `Idle` (no pill).
    pub status: Status,
}

pub fn render(
    groups: &[MachineGroup],
    local_sessions: &[SessionRow],
    lang: Lang,
    cx: &mut Context<RootView>,
) -> Div {
    let mut list = div().flex().flex_col().flex_1().min_h_0().overflow_hidden();
    for group in groups {
        let local = group.machine_id == LOCAL_MACHINE_ID;
        list = list.child(group_header(group, local, lang, cx));
        if group.sessions_visible && local {
            for (ix, row) in local_sessions.iter().enumerate() {
                list = list.child(session_row(ix, row, lang, cx));
            }
        }
    }

    div()
        .flex()
        .flex_col()
        .flex_none()
        .w(WIDTH)
        .h_full()
        .bg(theme::panel())
        .border_r_1()
        .border_color(theme::line())
        .child(brand(lang))
        .child(machines_header(lang))
        .child(list)
        .child(footer(lang))
}

fn brand(lang: Lang) -> Div {
    // The logo keeps its own colors (the one allowed gradient), so it goes
    // through `img` (full-color raster) instead of the tinted `svg`.
    let logo = img(ImageSource::Resource(Resource::Embedded(
        Icon::Logo.path().into(),
    )))
    .flex_none()
    .size(px(20.0));
    div()
        .flex()
        .items_center()
        .gap(px(8.0))
        .px(px(14.0))
        .pt(px(12.0))
        .pb(px(2.0))
        .child(logo)
        .child(
            div()
                .font(theme::wordmark_font())
                .text_size(theme::WORDMARK_SIZE)
                .text_color(theme::text_hi())
                .child(t(lang, Str::AppName)),
        )
}

fn machines_header(lang: Lang) -> Div {
    // GPUI 0.2.2 has no letter-spacing, so the mockup's .08em tracking is
    // not reproduced; the string is upper-case already.
    div()
        .flex()
        .items_center()
        .justify_between()
        .px(px(14.0))
        .pt(px(12.0))
        .pb(px(6.0))
        .text_size(theme::SMALL_SIZE)
        .text_color(theme::muted())
        .child(t(lang, Str::MachinesHeader))
        .child(
            // Add a machine: no-op until Task 12 hooks pairing.
            div()
                .id("sidebar-add-machine")
                .group("sidebar-add-machine")
                .flex()
                .items_center()
                .justify_center()
                .size(px(20.0))
                .rounded(px(4.0))
                .cursor_pointer()
                .child(
                    svg()
                        .path(Icon::AddPlus.path())
                        .size(px(14.0))
                        .text_color(theme::muted())
                        .group_hover("sidebar-add-machine", |style| {
                            style.text_color(theme::text())
                        }),
                ),
        )
}

/// "+" on this PC's group header: a new local tab (tooltip "Tab mới").
fn new_tab_button(lang: Lang, cx: &mut Context<RootView>) -> Stateful<Div> {
    let tip: SharedString = t(lang, Str::NewTab).into();
    div()
        .id("sidebar-new-tab")
        .group("sidebar-new-tab")
        .flex()
        .flex_none()
        .items_center()
        .justify_center()
        .size(px(20.0))
        .rounded(px(4.0))
        .cursor_pointer()
        .tooltip(move |_, cx| Tooltip::view(tip.clone(), cx))
        .on_click(cx.listener(|this, _: &ClickEvent, window, cx| {
            this.new_tab(window, cx);
        }))
        .child(
            svg()
                .path(Icon::AddPlus.path())
                .size(px(14.0))
                .text_color(theme::muted())
                .group_hover("sidebar-new-tab", |style| style.text_color(theme::text())),
        )
}

/// Plain tooltip: RAISE box, 1 px BORDER, small TEXT label.
struct Tooltip {
    text: SharedString,
}

impl Tooltip {
    fn view(text: SharedString, cx: &mut App) -> AnyView {
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

fn group_header(group: &MachineGroup, local: bool, lang: Lang, cx: &mut Context<RootView>) -> Div {
    let icon = match group.icon {
        MachineIcon::Laptop => Icon::Laptop,
        MachineIcon::Desktop => Icon::Desktop,
    };
    let dot = if group.online {
        theme::done()
    } else {
        theme::muted()
    };
    let title_row = div()
        .flex()
        .items_center()
        .gap(px(8.0))
        .child(
            svg()
                .path(icon.path())
                .flex_none()
                .size(px(16.0))
                .text_color(theme::muted()),
        )
        .child(
            div()
                .min_w_0()
                .truncate()
                .text_color(theme::text_hi())
                .font_weight(FontWeight::SEMIBOLD)
                .child(group.title.clone()),
        )
        .when_some(group.note.clone(), |row, note| {
            row.child(
                div()
                    .flex_none()
                    .text_size(theme::SMALL_SIZE)
                    .text_color(theme::muted())
                    .child(format!("· {note}")),
            )
        })
        .child(div().flex_1())
        .child(div().flex_none().size(px(6.0)).rounded_full().bg(dot))
        .when(local, |row| row.child(new_tab_button(lang, cx)));

    div()
        .flex()
        .flex_col()
        .px(px(14.0))
        .pt(px(8.0))
        .pb(px(4.0))
        .when(group.dimmed, |header| header.opacity(0.5))
        .child(title_row)
        .when_some(group.subtitle.clone(), |header, subtitle| {
            header.child(
                div()
                    .pl(px(24.0))
                    .text_size(theme::SMALL_SIZE)
                    .text_color(theme::muted())
                    .child(subtitle),
            )
        })
}

fn session_row(
    ix: usize,
    row: &SessionRow,
    lang: Lang,
    cx: &mut Context<RootView>,
) -> Stateful<Div> {
    let selected = row.selected;
    let tab = row.tab;
    div()
        .id(("sidebar-session", ix))
        .flex()
        .items_center()
        .gap(px(8.0))
        .mx(px(8.0))
        .my(px(2.0))
        .px(px(10.0))
        .py(px(7.0))
        .rounded(px(8.0))
        .cursor_pointer()
        .when(selected, |el| el.bg(theme::hsla(theme::SESSION_SELECTED)))
        .when(!selected, |el| {
            el.hover(|style| style.bg(theme::hsla(theme::SESSION_HOVER)))
        })
        .on_click(cx.listener(move |this, _: &ClickEvent, window, cx| {
            this.select_tab(tab, window, cx);
        }))
        .child(
            svg()
                .path(Icon::Terminal.path())
                .flex_none()
                .size(px(13.0))
                .text_color(theme::muted()),
        )
        .child(
            div()
                .flex_1()
                .min_w_0()
                .truncate()
                .text_color(theme::text_hi())
                .child(row.title.clone()),
        )
        .when_some(row.status.pill(), |el, pill| {
            el.child(pill_label(pill, lang))
        })
}

fn pill_label(pill: Pill, lang: Lang) -> Div {
    div()
        .flex_none()
        .px(px(6.0))
        .rounded(px(8.0))
        .text_size(theme::PILL_SIZE)
        .bg(theme::hsla(pill.bg))
        .text_color(theme::hsla(pill.fg))
        .child(t(lang, pill.label))
}

fn footer(lang: Lang) -> Div {
    div()
        .flex()
        .items_center()
        .gap(px(8.0))
        .px(px(14.0))
        .py(px(10.0))
        .border_t_1()
        .border_color(theme::line())
        .text_size(theme::SMALL_SIZE)
        .text_color(theme::muted())
        .child(
            svg()
                .path(Icon::ShieldCheck.path())
                .flex_none()
                .size(px(13.0))
                .text_color(theme::done()),
        )
        .child(div().min_w_0().truncate().child(t(lang, Str::E2eFooter)))
}
