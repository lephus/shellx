//! Custom title bar, laid out like the Mac's: sidebar toggle, the "+"
//! new-workspace split button (its chevron opens a menu), focus Back /
//! Forward, then a folder icon and the active workspace's name; on the right
//! the settings gear and the Windows caption buttons. The Mac's search box
//! and bell are not drawn until they do something (R2 F15, Ruling 22).
//!
//! The bar is the window's drag area (the name too); each control occludes
//! it, and the caption buttons report their `WindowControlArea` so Windows
//! hit-testing (snap layouts, double-click to maximize, drag to move) behaves
//! like a native caption. On macOS (development only) there are no caption
//! buttons; a spacer keeps the traffic lights clear.

use gpui::{
    ClickEvent, Context, Div, FontWeight, MouseDownEvent, Pixels, SharedString, Stateful, Window,
    WindowControlArea, div, prelude::*, px, svg,
};
use shellx_model::strings::{Lang, Str, t};

use super::assets::Icon;
use super::menu::{self, MenuItem};
use super::root::RootView;
use super::theme;
use super::tooltip::Tooltip;

pub const HEIGHT: Pixels = px(crate::workspace::TITLEBAR_H);
const CAPTION_WIDTH: Pixels = px(46.0);
/// Room for the macOS traffic-light buttons at the left of the bar.
const MAC_TRAFFIC_LIGHTS_W: f32 = 72.0;
/// The left group's buttons.
const BUTTON: Pixels = px(20.0);
const BUTTON_ICON: Pixels = px(14.0);
/// Back / Forward when there is nowhere to go.
const UNAVAILABLE_OPACITY: f32 = 0.4;

// Segoe Fluent Icons / Segoe MDL2 Assets caption glyphs.
const GLYPH_MINIMIZE: &str = "\u{E921}";
const GLYPH_MAXIMIZE: &str = "\u{E922}";
const GLYPH_RESTORE: &str = "\u{E923}";
const GLYPH_CLOSE: &str = "\u{E8BB}";

/// The bar. `root` gives the workspace name and whether Back / Forward can
/// go anywhere (reading the RootView entity during its own render would
/// panic, so `RootView::render` passes itself).
pub fn render(root: &RootView, lang: Lang, window: &Window, cx: &mut Context<RootView>) -> Div {
    let title: SharedString = root.tab_title(root.active_pane(), lang, cx).into();
    let left = div()
        .flex()
        .flex_row()
        .flex_none()
        .items_center()
        .gap(px(6.0))
        // On macOS the traffic-light spacer is the inset.
        .when(!cfg!(target_os = "macos"), |group| group.pl(px(8.0)))
        .child(
            icon_button(
                "titlebar-sidebar",
                Icon::WindowSidebar,
                BUTTON,
                t(lang, Str::ShowHideSidebar),
            )
            .on_click(cx.listener(|this, _: &ClickEvent, window, cx| {
                this.toggle_sidebar(window, cx);
            })),
        )
        .child(new_workspace_button(root.new_menu_open(), lang, cx))
        .child(
            icon_button(
                "titlebar-back",
                Icon::ArrowLeftMd,
                BUTTON,
                t(lang, Str::FocusBack),
            )
            .when(!root.can_focus_back(), |b| b.opacity(UNAVAILABLE_OPACITY))
            .on_click(cx.listener(|this, _: &ClickEvent, window, cx| {
                this.focus_back(window, cx);
            })),
        )
        .child(
            icon_button(
                "titlebar-forward",
                Icon::ArrowRightMd,
                BUTTON,
                t(lang, Str::FocusForward),
            )
            .when(!root.can_focus_forward(), |b| {
                b.opacity(UNAVAILABLE_OPACITY)
            })
            .on_click(cx.listener(|this, _: &ClickEvent, window, cx| {
                this.focus_forward(window, cx);
            })),
        );
    let right = div()
        .flex()
        .flex_row()
        .flex_none()
        .items_center()
        .gap(px(8.0))
        .pr(px(8.0))
        .child(
            icon_button(
                "titlebar-settings",
                Icon::Settings,
                px(24.0),
                t(lang, Str::Settings),
            )
            .on_click(cx.listener(|this, _: &ClickEvent, window, cx| {
                this.open_settings(window, cx);
            })),
        );

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
        .when(cfg!(target_os = "macos"), |bar| {
            bar.child(div().flex_none().w(px(MAC_TRAFFIC_LIGHTS_W)))
        })
        .child(left)
        .child(workspace_name(title))
        .child(right)
        .when(cfg!(windows), |bar| {
            bar.child(caption_buttons(window.is_maximized()))
        })
}

/// A square icon button with a tooltip: 14 px MUTED glyph, TEXT_HI on
/// hover. Occludes the drag area so clicks land here instead of moving the
/// window.
fn icon_button(
    id: &'static str,
    icon: Icon,
    size: Pixels,
    tip: impl Into<SharedString>,
) -> Stateful<Div> {
    let tip = tip.into();
    div()
        .id(id)
        .group(id)
        .occlude()
        .flex()
        .flex_none()
        .items_center()
        .justify_center()
        .size(size)
        .rounded(px(6.0))
        .cursor_pointer()
        .tooltip(move |_, cx| Tooltip::view(tip.clone(), cx))
        .child(
            svg()
                .path(icon.path())
                .size(BUTTON_ICON)
                .text_color(theme::muted())
                .group_hover(id, |style| style.text_color(theme::text_hi())),
        )
}

/// "+" (a new workspace) and its chevron (a menu: New Workspace, New Tab
/// (Terminal)), side by side like the Mac's split button.
fn new_workspace_button(menu_open: bool, lang: Lang, cx: &mut Context<RootView>) -> Div {
    let plus_tip = format!("{} (Ctrl+Shift+N)", t(lang, Str::NewWorkspace));
    let plus = icon_button("titlebar-new", Icon::AddPlus, BUTTON, plus_tip)
        .on_click(cx.listener(|this, _: &ClickEvent, window, cx| this.new_tab(window, cx)));
    let chevron = div()
        .id("titlebar-new-options")
        .group("titlebar-new-options")
        .occlude()
        .flex()
        .flex_none()
        .items_center()
        .justify_center()
        .w(px(12.0))
        .h(BUTTON)
        .rounded(px(4.0))
        .cursor_pointer()
        .tooltip({
            let tip = SharedString::from(t(lang, Str::NewWorkspaceOptions));
            move |_, cx| Tooltip::view(tip.clone(), cx)
        })
        // While the menu is open, a press here closes it and goes no
        // further: otherwise the menu's "press outside" would close it and
        // this click would open it again. Capture runs here before the menu
        // (drawn later) sees the press.
        .capture_any_mouse_down(cx.listener(|this, _: &MouseDownEvent, _, cx| {
            if this.new_menu_open() {
                this.close_new_menu(cx);
                cx.stop_propagation();
            }
        }))
        .on_click(cx.listener(|this, _: &ClickEvent, _, cx| this.toggle_new_menu(cx)))
        .child(
            svg()
                .path(Icon::ChevronDown.path())
                .size(px(10.0))
                .text_color(theme::muted())
                .group_hover("titlebar-new-options", |style| {
                    style.text_color(theme::text_hi())
                }),
        );
    div()
        .relative()
        .flex()
        .flex_row()
        .flex_none()
        .items_center()
        .child(plus)
        .child(chevron)
        .when(menu_open, |button| {
            button.child(
                div()
                    .absolute()
                    .top_full()
                    .left_0()
                    .child(new_workspace_menu(lang, cx)),
            )
        })
}

/// The chevron's menu: New Workspace and New Tab (Terminal).
fn new_workspace_menu(lang: Lang, cx: &mut Context<RootView>) -> impl IntoElement {
    let root = cx.entity().downgrade();
    let items = vec![
        MenuItem {
            label: t(lang, Str::NewWorkspace).into(),
            shortcut: Some("Ctrl+Shift+N"),
            on_click: Box::new({
                let root = root.clone();
                move |window, cx| {
                    root.update(cx, |this, cx| this.new_tab(window, cx)).ok();
                }
            }),
        },
        MenuItem {
            label: t(lang, Str::NewTerminalTab).into(),
            shortcut: Some("Ctrl+Shift+T"),
            on_click: Box::new({
                let root = root.clone();
                move |window, cx| {
                    root.update(cx, |this, cx| this.new_terminal_tab(window, cx))
                        .ok();
                }
            }),
        },
    ];
    menu::popover(items, move |_, cx| {
        root.update(cx, |this, cx| this.close_new_menu(cx)).ok();
    })
}

/// Folder icon and the active workspace's name; takes the room left between
/// the two groups (still the drag area).
fn workspace_name(title: SharedString) -> Div {
    div()
        .flex()
        .flex_row()
        .flex_1()
        .min_w_0()
        .items_center()
        .gap(px(6.0))
        .ml(px(10.0))
        .child(
            svg()
                .path(Icon::Folder.path())
                .flex_none()
                .size(px(16.0))
                .text_color(theme::muted()),
        )
        .child(
            div()
                .min_w_0()
                .truncate()
                .text_size(px(13.0))
                .font_weight(FontWeight::SEMIBOLD)
                .text_color(theme::text_hi())
                .child(title),
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
