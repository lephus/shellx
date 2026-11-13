//! Where the Settings view is drawn (spec §5.3). By default in a window of its own, so the
//! terminal beside it shows each change at once: content 980×680, at least 820×540, resizable,
//! a close button only, the main window's `app_id`. Opening it again brings that window to the
//! front. When the window cannot open, or with `SHELLX_SETTINGS_HOST=panel`, the same view is
//! drawn over the main window as a panel (the 1.7.1 panel's place in the modal rules,
//! `Panel::Settings`), so a PC where a second window misbehaves still has Settings.
//!
//! The Settings window keeps its frame (`ui-state.json`) when it closes: from its close
//! button, Esc, or the main window closing, which closes it too before the app quits.

use gpui::{
    AnyWindowHandle, App, Bounds, ClickEvent, Context, Entity, Focusable, FontWeight, IntoElement,
    Pixels, Render, TitlebarOptions, Window, WindowBounds, WindowHandle, WindowOptions, div, point,
    prelude::*, px, relative, size,
};
use shellx_model::settings_catalog::Section;
use shellx_model::strings::{Lang, Str, t};

use super::SettingsView;
use crate::ui::account::AccountService;
use crate::ui::app::{APP_ID, Services, dev_background};
use crate::ui::root::RootView;
use crate::ui::{theme, titlebar};
use crate::ui_state;

/// The window's size the first time (the Mac's content size), and the least it shrinks to.
const WIDTH: f32 = 980.0;
const HEIGHT: f32 = 680.0;
const MIN_WIDTH: f32 = 820.0;
const MIN_HEIGHT: f32 = 540.0;
/// The panel's header, with its title and close button (the window has a caption instead).
const PANEL_HEADER_H: f32 = 40.0;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum HostKind {
    /// A window of its own (the default).
    Window,
    /// Over the main window.
    Panel,
}

/// `SHELLX_SETTINGS_HOST`: "panel" (any case, spaces around it ignored) draws Settings over
/// the main window; anything else, or nothing, gives it a window.
pub fn host_kind(env: Option<&str>) -> HostKind {
    match env {
        Some(value) if value.trim().eq_ignore_ascii_case("panel") => HostKind::Panel,
        _ => HostKind::Window,
    }
}

pub struct SettingsHost {
    view: Entity<SettingsView>,
    kind: HostKind,
    /// The panel host: Settings is drawn over the main window.
    panel_open: bool,
    /// The window host: the Settings window, until it closes.
    window: Option<WindowHandle<SettingsWindow>>,
}

impl SettingsHost {
    pub fn new(account: Entity<AccountService>, cx: &mut Context<RootView>) -> Self {
        SettingsHost {
            view: cx.new(|cx| SettingsView::new(account, cx)),
            kind: host_kind(std::env::var("SHELLX_SETTINGS_HOST").ok().as_deref()),
            panel_open: false,
            window: None,
        }
    }

    /// The view, whichever host draws it (`RootView` takes its events).
    pub fn view(&self) -> &Entity<SettingsView> {
        &self.view
    }

    /// Shows Settings, on `section` when one is given. A second call brings the window to the
    /// front. When the window cannot open, Settings opens as the panel, and stays one.
    pub fn open(
        &mut self,
        section: Option<Section>,
        window: &mut Window,
        cx: &mut Context<RootView>,
    ) {
        if let Some(section) = section {
            self.view
                .update(cx, |view, cx| view.show_section(section, cx));
        }
        if let Some(open) = self.live_window(cx) {
            open.update(cx, |_, window, _| window.activate_window())
                .ok();
            return;
        }
        if self.kind == HostKind::Window {
            match open_window(self.view.clone(), window, cx) {
                Ok(handle) => {
                    self.window = Some(handle);
                    return;
                }
                Err(error) => {
                    log::warn!(
                        "shellx: the Settings window did not open ({error:#}); Settings opens as a panel"
                    );
                    self.kind = HostKind::Panel;
                }
            }
        }
        if !self.panel_open {
            self.panel_open = true;
            let main = window.window_handle();
            self.view.update(cx, |view, cx| view.opened(main, cx));
        }
        window.focus(&self.view.focus_handle(cx));
        cx.notify();
    }

    /// Closes Settings, its window or its panel. The caller gives the keyboard back.
    pub fn close(&mut self, cx: &mut Context<RootView>) {
        if self.panel_open {
            self.panel_open = false;
            cx.notify();
        }
        if let Some(open) = self.live_window(cx) {
            open.update(cx, |settings, window, cx| settings.close(window, cx))
                .ok();
        }
        self.window = None;
    }

    /// Settings shows, in either host.
    pub fn is_open(&self, cx: &App) -> bool {
        self.panel_open || self.live_window(cx).is_some()
    }

    /// What `Panels { settings }` reads: only the panel is one of the main window's panels.
    pub fn is_open_as_panel(&self) -> bool {
        self.panel_open
    }

    /// What `RootView::render` draws over the main window.
    pub fn panel_view(&self) -> Option<Entity<SettingsView>> {
        self.panel_open.then(|| self.view.clone())
    }

    /// The Settings window, unless it has closed (its close button closes it without telling
    /// the host).
    fn live_window(&self, cx: &App) -> Option<WindowHandle<SettingsWindow>> {
        self.window.filter(|settings| {
            cx.windows()
                .iter()
                .any(|open| open.window_id() == settings.window_id())
        })
    }
}

/// Opens the Settings window where it was last, else centred on the main window's display.
fn open_window(
    view: Entity<SettingsView>,
    main: &Window,
    cx: &mut App,
) -> anyhow::Result<WindowHandle<SettingsWindow>> {
    let lang = cx.global::<Services>().lang;
    let (bounds, display_id) = placement(ui_state::load().settings_frame, main, cx);
    let options = WindowOptions {
        window_bounds: Some(WindowBounds::Windowed(bounds)),
        // `appears_transparent` hides the system caption: `titlebar::settings_caption` draws
        // the title and the close button.
        titlebar: Some(TitlebarOptions {
            title: Some(t(lang, Str::Settings).into()),
            appears_transparent: true,
            ..Default::default()
        }),
        focus: !dev_background(),
        is_resizable: true,
        is_minimizable: false,
        display_id,
        window_min_size: Some(size(px(MIN_WIDTH), px(MIN_HEIGHT))),
        app_id: Some(APP_ID.into()),
        ..Default::default()
    };
    cx.open_window(options, |window, cx| {
        let handle = window.window_handle();
        view.update(cx, |view, cx| view.opened(handle, cx));
        window.focus(&view.focus_handle(cx));
        cx.new(|cx| SettingsWindow::new(view, window, cx))
    })
}

/// The frame to open at, and its display: the saved one (grown to the minimum size), else the
/// first size centred on the main window's display. GPUI-Windows moves a frame that is not on
/// the given display to that display's default place.
fn placement(
    saved: Option<(f32, f32, f32, f32)>,
    main: &Window,
    cx: &App,
) -> (Bounds<Pixels>, Option<gpui::DisplayId>) {
    if let Some((x, y, width, height)) = saved {
        let bounds = Bounds {
            origin: point(px(x), px(y)),
            size: size(px(width.max(MIN_WIDTH)), px(height.max(MIN_HEIGHT))),
        };
        let display = cx
            .displays()
            .into_iter()
            .find(|display| display.bounds().contains(&bounds.center()))
            .map(|display| display.id());
        return (bounds, display);
    }
    let display = main.display(cx).map(|display| display.id());
    let bounds = Bounds::centered(display, size(px(WIDTH), px(HEIGHT)), cx);
    (bounds, display)
}

/// The Settings window's root: its caption above the view.
pub struct SettingsWindow {
    view: Entity<SettingsView>,
}

impl SettingsWindow {
    fn new(view: Entity<SettingsView>, window: &mut Window, cx: &mut Context<Self>) -> Self {
        // The close button and Alt+F4 close it without `close`: the frame is kept here.
        window.on_window_should_close(cx, |window, _| {
            remember_frame(window);
            true
        });
        SettingsWindow { view }
    }

    /// Esc, Settings closed from the main window, or the app quitting.
    fn close(&mut self, window: &mut Window, _: &mut Context<Self>) {
        remember_frame(window);
        window.remove_window();
    }
}

impl Render for SettingsWindow {
    fn render(&mut self, _: &mut Window, cx: &mut Context<Self>) -> impl IntoElement {
        let lang = cx.global::<Services>().lang;
        div()
            .size_full()
            .flex()
            .flex_col()
            .bg(theme::bg())
            .text_color(theme::text())
            .font(theme::ui_font())
            .text_size(theme::UI_SIZE)
            .line_height(relative(1.4))
            .child(titlebar::settings_caption(t(lang, Str::Settings).into()))
            .child(div().flex_1().min_h_0().child(self.view.clone()))
    }
}

/// Keeps the window's frame (its restore frame while maximized) for the next open.
fn remember_frame(window: &Window) {
    let bounds = window.window_bounds().get_bounds();
    let mut state = ui_state::load();
    state.settings_frame = Some((
        f32::from(bounds.origin.x),
        f32::from(bounds.origin.y),
        f32::from(bounds.size.width),
        f32::from(bounds.size.height),
    ));
    ui_state::save(&state);
}

/// Whether `window` is the Settings window.
pub fn is_settings_window(window: &AnyWindowHandle) -> bool {
    window.downcast::<SettingsWindow>().is_some()
}

/// Closes the Settings window, keeping its frame: the last other window has closed and the
/// app quits.
pub fn close_settings_windows(cx: &mut App) {
    for window in cx.windows() {
        if let Some(settings) = window.downcast::<SettingsWindow>() {
            settings
                .update(cx, |settings, window, cx| settings.close(window, cx))
                .ok();
        }
    }
}

/// The panel host: the view over the main window below its title bar, under a header with the
/// title and a close button.
pub fn panel(view: Entity<SettingsView>, lang: Lang) -> impl IntoElement {
    let closing = view.clone();
    let header = div()
        .flex()
        .flex_row()
        .items_center()
        .justify_between()
        .flex_none()
        .h(px(PANEL_HEADER_H))
        .px(px(16.0))
        .bg(theme::panel())
        .border_b_1()
        .border_color(theme::border())
        .child(
            div()
                .font_weight(FontWeight::SEMIBOLD)
                .text_color(theme::text_hi())
                .child(t(lang, Str::Settings)),
        )
        .child(
            div()
                .id("settings-close")
                .px(px(8.0))
                .cursor_pointer()
                .text_color(theme::muted())
                .hover(|s| s.text_color(theme::text()))
                .child("×")
                .on_click(move |_: &ClickEvent, _, cx| {
                    closing.update(cx, |view, cx| view.request_close(cx));
                }),
        );
    div()
        .id("settings-panel")
        .occlude()
        .absolute()
        .top(px(crate::workspace::TITLEBAR_H))
        .left_0()
        .right_0()
        .bottom_0()
        .flex()
        .flex_col()
        .bg(theme::bg())
        .child(header)
        .child(div().flex_1().min_h_0().child(view))
}

#[cfg(test)]
mod tests {
    use super::{HostKind, host_kind};

    #[test]
    fn only_panel_selects_the_panel_host() {
        for value in [None, Some(""), Some("window"), Some("1"), Some("panels")] {
            assert_eq!(host_kind(value), HostKind::Window, "{value:?}");
        }
        for value in [Some("panel"), Some(" Panel "), Some("PANEL")] {
            assert_eq!(host_kind(value), HostKind::Panel, "{value:?}");
        }
    }
}
