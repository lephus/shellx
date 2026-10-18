//! Application setup: embedded fonts and icons, app-wide services, and the
//! main window with the system title bar hidden (ShellX draws its own).

use std::borrow::Cow;
use std::sync::Arc;

use gpui::{
    App, Application, Bounds, Global, TitlebarOptions, WindowBounds, WindowOptions, prelude::*, px,
    size,
};
use shellx_model::core_api::CoreCall;
use shellx_model::strings::Lang;

use super::assets::Assets;
use super::root::RootView;
use super::term_view::BASE_TITLE;
use crate::core_service::{ConfiguredCore, MachineFacts};
use crate::fonts;

/// App-wide services the views read with `cx.global::<Services>()`.
/// Later tasks add the remote client here.
pub struct Services {
    pub lang: Lang,
    /// shellx-core, configured for this PC before its first call. Its calls
    /// block: run them off the UI thread (`cx.background_spawn`).
    pub core: Arc<dyn CoreCall>,
}

impl Global for Services {}

pub fn run() {
    Application::new().with_assets(Assets).run(|cx: &mut App| {
        if let Err(error) = cx
            .text_system()
            .add_fonts(fonts::embedded().into_iter().map(Cow::Borrowed).collect())
        {
            eprintln!("failed to register the embedded fonts: {error:#}");
        }
        cx.set_global(Services {
            lang: Lang::from_env(),
            core: Arc::new(ConfiguredCore::this_pc(MachineFacts::this_pc())),
        });

        let bounds = Bounds::centered(None, size(px(1200.0), px(760.0)), cx);
        let window = cx
            .open_window(
                WindowOptions {
                    window_bounds: Some(WindowBounds::Windowed(bounds)),
                    // `appears_transparent` hides the Windows caption; the
                    // title bar in ui/titlebar.rs marks its drag area and
                    // caption buttons for hit-testing (snap layouts work).
                    titlebar: Some(TitlebarOptions {
                        title: Some(BASE_TITLE.into()),
                        appears_transparent: true,
                        ..Default::default()
                    }),
                    window_min_size: Some(size(px(720.0), px(420.0))),
                    app_id: Some("pro.shellx.desktop".into()),
                    ..Default::default()
                },
                |window, cx| cx.new(|cx| RootView::new(window, cx)),
            )
            .expect("failed to open the ShellX window");
        window
            .update(cx, |root, window, cx| {
                root.focus_terminal(window, cx);
                cx.activate(true);
            })
            .ok();
        cx.on_window_closed(|cx| {
            if cx.windows().is_empty() {
                cx.quit();
            }
        })
        .detach();
    });
}
