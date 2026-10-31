//! Machine sidebar (spec §7.1 items 1-3 and 6): logo + wordmark, the
//! "MÁY CỦA BẠN" header, one group per machine from
//! `shellx_model::sidebar::build_groups`, and the footer (the "?" help menu,
//! the version and, when an update is available, its pill).
//! "THIẾT BỊ ĐANG KẾT NỐI" (item 5) is out of the MVP.
//! Under a machine: one workspace card per tab, like the Mac's (a purple
//! rail, the title, the git branch and the working directory; click selects
//! the tab). New workspaces are made from the title bar's "+".
//! Signed in, the groups are the account's machines (this PC first, the
//! others below, offline ones dimmed with "ngoại tuyến · lần cuối HH:MM");
//! signed out, this PC is the only group and the sidebar never asks for a
//! password: sign-in lives in Settings -> Account (`login.rs`).
//! Another online machine without access shows "Xin quyền truy cập", which
//! opens the pairing panel (`pairing.rs`); while waiting, the row shows the
//! code instead. The "+" in the machines header opens a small list of the
//! account's other machines without a link (same action); it never holds the
//! keyboard and closes on a click outside it and the "+". While signed out
//! that "+" opens the sign-in dialog instead. An online machine
//! with access shows "Mở", which opens a tab with its terminal (Task 13b);
//! that machine's tabs are listed under it.

use gpui::{
    ClickEvent, Context, Div, Entity, FontWeight, ImageSource, IntoElement, MouseDownEvent, Pixels,
    Resource, SharedString, Stateful, div, img, prelude::*, px, svg, transparent_black,
};
use shellx_model::palette::{
    PRIMARY_LINE, PRIMARY_SOFT, PRIMARY_TEXT, Pill, RAIL_PURPLE, SELECTION_TITLE, Status,
};
use shellx_model::sidebar::{MachineGroup, MachineIcon, RowAction};
use shellx_model::strings::{Lang, Str, pairing_code_display, t};
use shellx_model::tabs::TabId;
use shellx_model::update::{UpdateStatus, download_url, pill_text};

use super::account::AccountService;
use super::assets::Icon;
use super::button::{Kind, button};
use super::menu::{self, MenuItem};
use super::root::RootView;
use super::theme;
use super::tooltip::Tooltip;
use super::update_banner::open_https;

pub const WIDTH: Pixels = px(crate::workspace::SIDEBAR_W);

/// One workspace card: one per tab, under the machine its panes run on.
pub struct SessionRow {
    pub tab: TabId,
    /// The group it is listed under (this PC's id for a local tab).
    pub machine_id: String,
    /// The tab's focused pane title (`session_title`).
    pub title: String,
    pub selected: bool,
    /// `Status::pill` decides the pill; local shells are `Idle` (no pill).
    pub status: Status,
    /// The working directory (`~` for home), or a Mac pane's Mac name.
    pub path: Option<String>,
    /// The git branch of a local pane's directory.
    pub branch: Option<String>,
}

/// A machine in the machines-header "+" list (another machine, no link).
pub struct PickerEntry {
    pub machine_id: String,
    pub name: String,
    pub online: bool,
}

/// `local_id`: this PC's group (its server id when signed in).
/// `sessions`: every tab, each listed under its `machine_id` group.
/// `picker`: the "+" list, when open.
/// `account`: the update status for the footer pill, and "Check for Updates".
/// `help_open`: the footer "?" menu is showing.
pub fn render(
    groups: &[MachineGroup],
    sessions: &[SessionRow],
    local_id: &str,
    picker: Option<&[PickerEntry]>,
    account: &Entity<AccountService>,
    help_open: bool,
    lang: Lang,
    cx: &mut Context<RootView>,
) -> Div {
    let mut list = div().flex().flex_col().flex_1().min_h_0().overflow_hidden();
    for (ix, group) in groups.iter().enumerate() {
        let local = group.machine_id == local_id;
        list = list.child(group_header(ix, group, lang, cx));
        if local && !group.sessions_visible {
            continue;
        }
        // A Mac's open tabs stay listed (and selectable) while it is
        // offline: their panes show "ngoại tuyến".
        for (ix, row) in sessions.iter().enumerate() {
            if row.machine_id == group.machine_id {
                list = list.child(workspace_card(ix, row, lang, cx));
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
        .child(machines_block(picker, lang, cx))
        .child(list)
        .child(footer(account, help_open, lang, cx))
}

fn brand(lang: Lang) -> Div {
    // The logo keeps its own colors (the one allowed gradient), so it goes
    // through `img` (full-color raster) instead of the tinted `svg`.
    let logo = img(ImageSource::Resource(Resource::Embedded(
        Icon::Logo.path().into(),
    )))
    .flex_none()
    .size(px(18.0));
    // The Mac's brand row is in the system font, so this is the UI font
    // (inherited), not the Space Grotesk wordmark.
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
                .text_size(theme::BRAND_SIZE)
                .font_weight(FontWeight::SEMIBOLD)
                .text_color(theme::text_hi())
                .child(t(lang, Str::AppName)),
        )
}

/// The machines header with the "+" list under it while it is open. A press
/// outside this block closes the list: outside the list *and* the "+", so
/// pressing the "+" again toggles it instead of closing and reopening it.
/// The press still reaches what it hit (a terminal click focuses the pane).
fn machines_block(picker: Option<&[PickerEntry]>, lang: Lang, cx: &mut Context<RootView>) -> Div {
    let block = div()
        .flex()
        .flex_col()
        .flex_none()
        .child(machines_header(lang, cx));
    match picker {
        Some(entries) => block
            .child(machine_picker(entries, lang, cx))
            .on_mouse_down_out(cx.listener(|this, _: &MouseDownEvent, window, cx| {
                this.close_machine_picker(window, cx);
            })),
        None => block,
    }
}

fn machines_header(lang: Lang, cx: &mut Context<RootView>) -> Div {
    let tip: SharedString = t(lang, Str::AddMachine).into();
    // GPUI 0.2.2 has no letter-spacing, so the mockup's .08em tracking is
    // not reproduced; the string is upper-case already.
    div()
        .flex()
        .items_center()
        .justify_between()
        .px(px(14.0))
        .pt(px(10.0))
        .pb(px(4.0))
        .text_size(theme::HEADER_SIZE)
        .font_weight(FontWeight::MEDIUM)
        .text_color(theme::muted())
        .child(t(lang, Str::MachinesHeader))
        .child(
            // Request access to another machine: toggles the "+" list (signed
            // out: opens the sign-in dialog).
            div()
                .id("sidebar-add-machine")
                .group("sidebar-add-machine")
                .flex()
                .items_center()
                .justify_center()
                .size(px(24.0))
                .rounded(px(4.0))
                .cursor_pointer()
                .tooltip(move |_, cx| Tooltip::view(tip.clone(), cx))
                .on_click(cx.listener(|this, _: &ClickEvent, window, cx| {
                    this.toggle_machine_picker(window, cx);
                }))
                .child(
                    svg()
                        .path(Icon::AddPlus.path())
                        .size(px(18.0))
                        .text_color(theme::muted())
                        .group_hover("sidebar-add-machine", |style| {
                            style.text_color(theme::text())
                        }),
                ),
        )
}

/// The "+" list: the account's other machines without a link. Online ones
/// request access on click; offline ones are dimmed (approval needs the
/// other machine).
fn machine_picker(entries: &[PickerEntry], lang: Lang, cx: &mut Context<RootView>) -> Div {
    // Not a panel: no focus handle, so the keyboard stays where it was.
    let mut list = div()
        .flex()
        .flex_col()
        .mx(px(10.0))
        .mb(px(6.0))
        .py(px(4.0))
        .rounded(px(8.0))
        .border_1()
        .border_color(theme::border())
        .bg(theme::raise())
        .text_size(theme::SMALL_SIZE);
    if entries.is_empty() {
        list = list.child(
            div()
                .px(px(10.0))
                .py(px(6.0))
                .text_color(theme::muted())
                .child(t(lang, Str::NoOtherMachines)),
        );
    }
    for (ix, entry) in entries.iter().enumerate() {
        let dot = if entry.online {
            theme::done()
        } else {
            theme::muted()
        };
        let row = div()
            .id(("sidebar-picker", ix))
            .flex()
            .items_center()
            .gap(px(8.0))
            .px(px(10.0))
            .py(px(6.0))
            .child(
                div()
                    .flex_1()
                    .min_w_0()
                    .truncate()
                    .text_color(theme::text_hi())
                    .child(entry.name.clone()),
            )
            .child(div().flex_none().size(px(6.0)).rounded_full().bg(dot));
        let row = if entry.online {
            let (id, name) = (entry.machine_id.clone(), entry.name.clone());
            row.cursor_pointer()
                .hover(|style| style.bg(theme::hsla(theme::SESSION_HOVER)))
                .on_click(cx.listener(move |this, _: &ClickEvent, window, cx| {
                    this.request_access(id.clone(), name.clone(), window, cx);
                }))
        } else {
            row.opacity(0.5)
        };
        list = list.child(row);
    }
    list
}

fn group_header(ix: usize, group: &MachineGroup, lang: Lang, cx: &mut Context<RootView>) -> Div {
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
        // "Name · this PC": the note sits right after the name.
        .child(
            div()
                .flex()
                .items_center()
                .gap(px(4.0))
                .flex_1()
                .min_w_0()
                .child(
                    div()
                        .min_w_0()
                        .truncate()
                        .text_size(theme::CARD_TITLE_SIZE)
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
                }),
        )
        .child(div().flex_none().size(px(6.0)).rounded_full().bg(dot));

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
        .when_some(row_action(ix, group, lang, cx), |header, action| {
            header.child(div().flex().pl(px(24.0)).pt(px(4.0)).child(action))
        })
}

/// The action under another machine's name. RequestAccess opens the pairing
/// panel; ShowCode shows the code being waited on; Open opens a tab with the
/// machine's terminal.
fn row_action(
    ix: usize,
    group: &MachineGroup,
    lang: Lang,
    cx: &mut Context<RootView>,
) -> Option<Div> {
    match &group.action {
        RowAction::RequestAccess => {
            let (id, name) = (group.machine_id.clone(), group.title.clone());
            Some(
                div().child(
                    button(
                        ("sidebar-request-access", ix),
                        t(lang, Str::RequestAccess),
                        Kind::Secondary,
                        false,
                    )
                    .text_size(theme::SMALL_SIZE)
                    .on_click(cx.listener(
                        move |this, _: &ClickEvent, window, cx| {
                            this.request_access(id.clone(), name.clone(), window, cx);
                        },
                    )),
                ),
            )
        }
        RowAction::ShowCode(code) => Some(
            div()
                .text_size(theme::SMALL_SIZE)
                .text_color(theme::hsla(shellx_model::palette::PRIMARY_TEXT))
                .child(pairing_code_display(code)),
        ),
        RowAction::Open => {
            let id = group.machine_id.clone();
            Some(
                div().child(
                    button(
                        ("sidebar-open", ix),
                        t(lang, Str::Open),
                        Kind::Primary,
                        false,
                    )
                    .text_size(theme::SMALL_SIZE)
                    .on_click(cx.listener(
                        move |this, _: &ClickEvent, window, cx| {
                            this.open_remote(id.clone(), window, cx);
                        },
                    )),
                ),
            )
        }
        RowAction::None => None,
    }
}

/// One workspace, like the Mac's card: a purple rail on the left edge, the
/// title, then (when there are any) the git branch and the directory. The
/// selected card has a fill and a 1 px edge; the edge is there (clear) on
/// the others so selecting never moves the text.
fn workspace_card(
    ix: usize,
    row: &SessionRow,
    lang: Lang,
    cx: &mut Context<RootView>,
) -> Stateful<Div> {
    let selected = row.selected;
    let tab = row.tab;
    let title_color = if selected {
        theme::hsla(SELECTION_TITLE)
    } else {
        theme::text_hi()
    };
    let title_line = div()
        .flex()
        .items_center()
        .gap(px(8.0))
        .child(
            div()
                .flex_1()
                .min_w_0()
                .truncate()
                .text_size(theme::CARD_TITLE_SIZE)
                .font_weight(FontWeight::SEMIBOLD)
                .text_color(title_color)
                .child(row.title.clone()),
        )
        .when_some(row.status.pill(), |el, pill| {
            el.child(pill_label(pill, lang))
        });
    let content = div()
        .flex()
        .flex_col()
        .gap(px(2.0))
        .pl(px(12.0))
        .pr(px(8.0))
        .py(px(6.0))
        .child(title_line)
        .when_some(row.branch.as_ref(), |el, branch| {
            el.child(card_line(format!("\u{2387} {branch}")))
        })
        .when_some(row.path.as_ref(), |el, path| {
            el.child(card_line(path.clone()))
        });
    div()
        .id(("sidebar-session", ix))
        .relative()
        .flex()
        .flex_col()
        .mx(px(8.0))
        .my(px(2.0))
        .rounded(px(6.0))
        .border_1()
        .border_color(transparent_black())
        .cursor_pointer()
        .when(selected, |el| {
            el.bg(theme::hsla(theme::SESSION_SELECTED))
                .border_color(theme::border())
        })
        .when(!selected, |el| {
            el.hover(|style| style.bg(theme::hsla(theme::SESSION_HOVER)))
        })
        .on_click(cx.listener(move |this, _: &ClickEvent, window, cx| {
            this.select_tab(tab, window, cx);
        }))
        .child(
            div()
                .absolute()
                .left_0()
                .top_0()
                .bottom_0()
                .w(px(3.0))
                .rounded_tl(px(6.0))
                .rounded_bl(px(6.0))
                .bg(theme::hsla(RAIL_PURPLE.with_alpha(0.95))),
        )
        .child(content)
}

/// A secondary line of a card: 11 px, muted, cut off at the card's edge.
/// The text sits in a row as a `flex_1` child, like the title: as a plain
/// child of the column GPUI measures it at width 0 first and keeps that
/// (the line would show only "…").
fn card_line(text: String) -> Div {
    div().flex().child(
        div()
            .flex_1()
            .min_w_0()
            .truncate()
            .text_size(theme::SMALL_SIZE)
            .text_color(theme::muted())
            .child(text),
    )
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

/// Pages the help menu's Docs and GitHub rows open.
const DOCS_URL: &str = "https://shellx.pro";
const GITHUB_URL: &str = "https://github.com/lephus/shellx";

/// Footer height of every control in it, in px.
const FOOTER_BUTTON: f32 = 22.0;

/// The Mac's footer: the "?" help button, the version, a spacer and, only
/// while an update is available, its pill.
fn footer(
    account: &Entity<AccountService>,
    help_open: bool,
    lang: Lang,
    cx: &mut Context<RootView>,
) -> Div {
    let status = account.read(cx).update_status().clone();
    div()
        .flex()
        .flex_row()
        .flex_none()
        .items_center()
        .gap(px(4.0))
        .pl(px(6.0))
        .pr(px(10.0))
        .py(px(6.0))
        .border_t_1()
        .border_color(theme::line())
        .child(help_button(account, help_open, lang, cx))
        .child(version_label())
        .child(div().flex_1())
        .children(update_pill(&status, lang))
}

/// The "?" (14 px, muted) with its menu opening upward from it.
fn help_button(
    account: &Entity<AccountService>,
    help_open: bool,
    lang: Lang,
    cx: &mut Context<RootView>,
) -> Div {
    let tip: SharedString = t(lang, Str::Help).into();
    let button = div()
        .id("sidebar-help")
        .group("sidebar-help")
        .flex()
        .flex_none()
        .items_center()
        .justify_center()
        .size(px(FOOTER_BUTTON))
        .rounded(px(6.0))
        .cursor_pointer()
        .tooltip(move |_, cx| Tooltip::view(tip.clone(), cx))
        // While the menu is open, a press here closes it and goes no
        // further: otherwise the menu's "press outside" would close it and
        // this click would open it again (as the title bar's chevron does).
        .capture_any_mouse_down(cx.listener(|this, _: &MouseDownEvent, _, cx| {
            if this.help_open() {
                this.close_help_menu(cx);
                cx.stop_propagation();
            }
        }))
        .on_click(cx.listener(|this, _: &ClickEvent, _, cx| this.toggle_help_menu(cx)))
        .child(
            svg()
                .path(Icon::CircleHelp.path())
                .size(px(14.0))
                .text_color(theme::muted())
                .group_hover("sidebar-help", |style| style.text_color(theme::text_hi())),
        );
    div()
        .relative()
        .flex_none()
        .child(button)
        .when(help_open, |el| {
            // Anchor point: the button's top-left; the menu sits above it.
            el.child(
                div()
                    .absolute()
                    .top_0()
                    .left_0()
                    .child(help_menu(account, lang, cx)),
            )
        })
}

/// Settings…, Check for Updates, Docs and GitHub.
fn help_menu(
    account: &Entity<AccountService>,
    lang: Lang,
    cx: &mut Context<RootView>,
) -> impl IntoElement {
    let root = cx.entity().downgrade();
    let link = |label: Str, url: &'static str| MenuItem {
        label: t(lang, label).into(),
        shortcut: None,
        on_click: Box::new(move |_, cx| open_https(cx, url)),
    };
    let items = vec![
        MenuItem {
            label: t(lang, Str::SettingsEllipsis).into(),
            shortcut: Some("Ctrl+,"),
            on_click: Box::new({
                let root = root.clone();
                move |window, cx| {
                    root.update(cx, |this, cx| this.open_settings(window, cx))
                        .ok();
                }
            }),
        },
        MenuItem {
            label: t(lang, Str::CheckForUpdates).into(),
            shortcut: None,
            on_click: Box::new({
                let account = account.clone();
                move |_, cx| account.update(cx, |account, cx| account.check_update(cx))
            }),
        },
        link(Str::Docs, DOCS_URL),
        link(Str::GitHub, GITHUB_URL),
    ];
    menu::popover_above(items, move |_, cx| {
        root.update(cx, |this, cx| this.close_help_menu(cx)).ok();
    })
}

/// "v1.5.3", 11 px muted.
fn version_label() -> Div {
    div()
        .flex()
        .flex_none()
        .items_center()
        .h(px(FOOTER_BUTTON))
        .px(px(5.0))
        .text_size(theme::SMALL_SIZE)
        .text_color(theme::muted())
        .child(format!("v{}", shellx_model::VERSION))
}

/// "Update Available: 1.5.4": a PRIMARY_SOFT capsule that opens the download
/// link (when the status has an https one) on a click.
fn update_pill(status: &UpdateStatus, lang: Lang) -> Option<Stateful<Div>> {
    let text = pill_text(status, lang)?;
    let url = download_url(status).map(str::to_string);
    let pill = div()
        .id("sidebar-update-pill")
        .flex()
        .flex_none()
        .items_center()
        .h(px(FOOTER_BUTTON))
        .px(px(8.0))
        .rounded_full()
        .border_1()
        .border_color(theme::hsla(PRIMARY_LINE))
        .bg(theme::hsla(PRIMARY_SOFT))
        .text_size(theme::SMALL_SIZE)
        .font_weight(FontWeight::MEDIUM)
        .text_color(theme::hsla(PRIMARY_TEXT))
        .whitespace_nowrap()
        .child(text);
    Some(match url {
        Some(url) => pill
            .cursor_pointer()
            .on_click(move |_: &ClickEvent, _, cx| open_https(cx, &url)),
        None => pill,
    })
}
