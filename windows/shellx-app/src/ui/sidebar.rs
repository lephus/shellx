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
//! password: sign-in lives in Settings -> Account (`login.rs`). After the
//! server ended the session, a "Sign in again" notice sits above the footer.
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
use shellx_model::account::AccountState;
use shellx_model::core_api::GooglePurpose;
use shellx_model::palette::{Pill, Status};
use shellx_model::settings_catalog::Section;
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

/// A machine in the machines-header "+" list (a Mac that may be asked, no link yet).
pub struct PickerEntry {
    pub machine_id: String,
    pub name: String,
    pub online: bool,
}

/// The machines-header "+" list: its machines (`sidebar::request_targets`) and the sentences under them
/// (`sidebar::request_panel_notes`: why none or none else can be asked).
pub struct Picker {
    pub entries: Vec<PickerEntry>,
    pub notes: &'static [Str],
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
    picker: Option<&Picker>,
    account: &Entity<AccountService>,
    help_open: bool,
    lang: Lang,
    cx: &mut Context<RootView>,
) -> Div {
    let signed_in = matches!(account.read(cx).state(), AccountState::LoggedIn { .. });
    // The groups and cards scroll; the brand, the machines header and the
    // footer stay put.
    let mut list = div()
        .id("sidebar-list")
        .flex()
        .flex_col()
        .flex_1()
        .min_h_0()
        .overflow_y_scroll();
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
        .bg(theme::sidebar_bg())
        .border_r_1()
        .border_color(theme::line())
        .child(brand(lang))
        .child(machines_block(picker, signed_in, lang, cx))
        .child(list)
        .children(session_notice(account, lang, cx))
        .child(footer(account, help_open, lang, cx))
}

/// After the server ended the session: "Your session expired." and "Sign in again" above the footer,
/// until the next sign-in (Ruling 29). It holds no focus handle, so the keyboard stays where it was.
fn session_notice(
    account: &Entity<AccountService>,
    lang: Lang,
    cx: &mut Context<RootView>,
) -> Option<Div> {
    let notice = account.read(cx).sign_in_notice()?;
    Some(
        div()
            .flex()
            .flex_col()
            .flex_none()
            .gap(px(6.0))
            .px(px(10.0))
            .py(px(6.0))
            .border_t_1()
            .border_color(theme::line())
            .child(
                div()
                    .text_size(theme::SMALL_SIZE)
                    .text_color(theme::sidebar_muted())
                    .child(t(lang, notice.line)),
            )
            .child(
                div().flex().child(
                    button(
                        "sidebar-sign-in-again",
                        t(lang, notice.button),
                        Kind::Secondary,
                        false,
                    )
                    .on_click(cx.listener(
                        |this, _: &ClickEvent, window, cx| {
                            this.open_sign_in(GooglePurpose::SignIn, window, cx);
                        },
                    )),
                ),
            ),
    )
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
                .text_color(theme::sidebar_text())
                .child(t(lang, Str::AppName)),
        )
}

/// The machines header with the "+" list under it while it is open. A press
/// outside this block closes the list: outside the list *and* the "+", so
/// pressing the "+" again toggles it instead of closing and reopening it.
/// The press still reaches what it hit (a terminal click focuses the pane).
fn machines_block(
    picker: Option<&Picker>,
    signed_in: bool,
    lang: Lang,
    cx: &mut Context<RootView>,
) -> Div {
    let block = div()
        .flex()
        .flex_col()
        .flex_none()
        .child(machines_header(signed_in, lang, cx));
    match picker {
        Some(picker) => block
            .child(machine_picker(picker, lang, cx))
            .on_mouse_down_out(cx.listener(|this, _: &MouseDownEvent, window, cx| {
                this.close_machine_picker(window, cx);
            })),
        None => block,
    }
}

/// `signed_in`: the "+" lists machines; signed out it opens the sign-in
/// dialog, and its tooltip says so.
fn machines_header(signed_in: bool, lang: Lang, cx: &mut Context<RootView>) -> Div {
    let tip = if signed_in {
        Str::AddMachine
    } else {
        Str::SignInEllipsis
    };
    let tip: SharedString = t(lang, tip).into();
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
        .text_color(theme::sidebar_muted())
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
                        .text_color(theme::sidebar_muted())
                        .group_hover("sidebar-add-machine", |style| {
                            style.text_color(theme::sidebar_icon_hover())
                        }),
                ),
        )
}

/// The "+" list: the Macs that may be asked and have no link yet. Online ones
/// request access on click; offline ones are dimmed (approval needs the
/// other machine). Under them, the sentences saying why none (or none else)
/// can be asked, so the list is never empty and silent.
fn machine_picker(picker: &Picker, lang: Lang, cx: &mut Context<RootView>) -> Div {
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
    for (ix, entry) in picker.entries.iter().enumerate() {
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
                .hover(|style| style.bg(theme::panel_hover()))
                .on_click(cx.listener(move |this, _: &ClickEvent, window, cx| {
                    this.request_access(id.clone(), name.clone(), window, cx);
                }))
        } else {
            row.opacity(0.5)
        };
        list = list.child(row);
    }
    for note in picker.notes {
        list = list.child(
            div()
                .px(px(10.0))
                .py(px(6.0))
                .text_color(theme::muted())
                .child(t(lang, *note)),
        );
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
        theme::sidebar_muted()
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
                .text_color(theme::sidebar_muted()),
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
                        .text_color(theme::sidebar_text())
                        .font_weight(FontWeight::SEMIBOLD)
                        .child(group.title.clone()),
                )
                .when_some(group.note.clone(), |row, note| {
                    row.child(
                        div()
                            .flex_none()
                            .text_size(theme::SMALL_SIZE)
                            .text_color(theme::sidebar_muted())
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
                    .text_color(theme::sidebar_muted())
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
                .text_color(theme::sidebar_primary_text())
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
                    .text_color(theme::sidebar_primary_text())
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
        theme::sidebar_selection_title()
    } else {
        theme::sidebar_text()
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
            el.bg(theme::session_selected())
                .border_color(theme::border())
        })
        .when(!selected, |el| {
            el.hover(|style| style.bg(theme::session_hover()))
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
                .bg(theme::rail_purple()),
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
            .text_color(theme::sidebar_muted())
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
                .text_color(theme::sidebar_muted())
                .group_hover("sidebar-help", |style| {
                    style.text_color(theme::sidebar_text())
                }),
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

/// Settings…, Check for Updates, Create Diagnostics Report (a separate `--diagnose`
/// process, Ruling 35), Docs and GitHub.
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
                // Opens Settings, never closes it (Ctrl+, toggles).
                move |window, cx| {
                    root.update(cx, |this, cx| this.show_settings(None, window, cx))
                        .ok();
                }
            }),
        },
        MenuItem {
            label: t(lang, Str::CheckForUpdates).into(),
            shortcut: None,
            on_click: Box::new({
                let account = account.clone();
                let root = root.clone();
                // The result ("Checking…", "Up to date", a new version)
                // shows in Settings -> Updates, so that opens too.
                move |window, cx| {
                    account.update(cx, |account, cx| account.check_update(cx));
                    root.update(cx, |this, cx| {
                        this.show_settings(Some(Section::Updates), window, cx)
                    })
                    .ok();
                }
            }),
        },
        MenuItem {
            label: t(lang, Str::CreateDiagnosticsReport).into(),
            shortcut: None,
            // The report runs in its own process (`--diagnose`), so the window stays responsive.
            on_click: Box::new(|_, _| {
                if let Err(error) = crate::diagnose_run::spawn_report_process() {
                    log::warn!("the diagnostics report did not start: {error}");
                }
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
        .text_color(theme::sidebar_muted())
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
        .border_color(theme::primary_line())
        .bg(theme::primary_soft())
        .text_size(theme::SMALL_SIZE)
        .font_weight(FontWeight::MEDIUM)
        .text_color(theme::sidebar_primary_text())
        .whitespace_nowrap()
        .child(text);
    Some(match url {
        Some(url) => pill
            .cursor_pointer()
            .on_click(move |_: &ClickEvent, _, cx| open_https(cx, &url)),
        None => pill,
    })
}
