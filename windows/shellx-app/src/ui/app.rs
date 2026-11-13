//! Application setup: embedded fonts and icons, app-wide services, and the
//! main window with the system title bar hidden (ShellX draws its own).

use std::borrow::Cow;
use std::sync::Arc;

#[cfg(windows)]
use gpui::point;
use gpui::{
    App, Application, Bounds, Global, TitlebarOptions, WindowBounds, WindowOptions, prelude::*, px,
    size,
};
use shellx_model::core_api::CoreCall;
use shellx_model::settings::LanguageChoice;
use shellx_model::start_guard::StartReason;
use shellx_model::strings::Lang;

use super::assets::Assets;
use super::root::RootView;
use super::settings::host::{close_settings_windows, is_settings_window};
use super::settings_service::SettingsService;
use crate::core_service::{ConfiguredCore, MachineFacts};
use crate::crash::{self, CrashTest};
use crate::fonts;
use crate::os_info;
use crate::shell_info::BASE_TITLE;
use crate::startup;

/// App-wide services the views read with `cx.global::<Services>()`.
/// Later tasks add the remote client here.
pub struct Services {
    pub lang: Lang,
    /// shellx-core, configured for this PC before its first call. Its calls
    /// block: run them off the UI thread (`cx.background_spawn`).
    pub core: Arc<dyn CoreCall>,
}

impl Global for Services {}

/// The language the settings choose now: `SHELLX_LANG`, else the Language setting, else
/// the Windows display language.
pub fn resolve_lang(choice: LanguageChoice) -> Lang {
    Lang::from_choice(
        choice,
        std::env::var("SHELLX_LANG").ok().as_deref(),
        os_info::ui_language_id(),
    )
}

/// The windows' `app_id` (the main window and Settings share it).
pub const APP_ID: &str = "pro.shellx.desktop";

/// Development on a Mac only: `SHELLX_DEV_BACKGROUND=1` opens the window without
/// taking the keyboard or coming to the front. An automated run of the built window
/// uses it, so the terminal in that window can never catch what a person is typing
/// in another app. Windows builds ignore the variable.
pub fn dev_background() -> bool {
    cfg!(target_os = "macos")
        && background_requested(std::env::var("SHELLX_DEV_BACKGROUND").ok().as_deref())
}

fn background_requested(value: Option<&str>) -> bool {
    value == Some("1")
}

/// The first window: on Windows 1200x760 shrunk to the primary monitor's work area (R1 F2),
/// maximized when it would be smaller than 720x420 or the work area is unknown; on a Mac
/// (development) 1200x760 centred.
#[cfg(windows)]
fn first_window_bounds(_cx: &App) -> WindowBounds {
    let fw = os_info::first_window_placement(os_info::primary_work_area());
    let bounds = Bounds {
        origin: point(px(fw.x), px(fw.y)),
        size: size(px(fw.width), px(fw.height)),
    };
    if fw.maximized {
        WindowBounds::Maximized(bounds)
    } else {
        WindowBounds::Windowed(bounds)
    }
}

#[cfg(not(windows))]
fn first_window_bounds(cx: &App) -> WindowBounds {
    WindowBounds::Windowed(Bounds::centered(None, size(px(1200.0), px(760.0)), cx))
}

pub fn run() {
    Application::new().with_assets(Assets).run(|cx: &mut App| {
        // GPUI has read GPUI_DISABLE_DIRECT_COMPOSITION (in `Application::new`): the shells in
        // this window must not inherit a value this start set (plan review M-11).
        startup::forget_render_variable();
        if let Err(error) = cx
            .text_system()
            .add_fonts(fonts::embedded().into_iter().map(Cow::Borrowed).collect())
        {
            log::warn!("failed to register the embedded fonts: {error:#}");
        }
        cx.set_global(Services {
            lang: Lang::from_system(
                std::env::var("SHELLX_LANG").ok().as_deref(),
                os_info::ui_language_id(),
            ),
            core: Arc::new(ConfiguredCore::this_pc(MachineFacts::this_pc())),
        });
        SettingsService::init(cx);

        let background = dev_background();
        let window_bounds = first_window_bounds(cx);
        let retry = startup::render_status().reason == StartReason::RetryAfterOpenFailed;
        let opened = if crash::crash_test() == Some(CrashTest::Window) && !retry {
            // `--crash-test window`: the open fails without being tried, except in the
            // compatible relaunch it causes (Ruling 31).
            Err(anyhow::anyhow!("crash test: the window was not opened"))
        } else {
            cx.open_window(
                WindowOptions {
                    window_bounds: Some(window_bounds),
                    // The primary monitor (GPUI places in its workspace coordinates).
                    display_id: None,
                    // `appears_transparent` hides the Windows caption; the
                    // title bar in ui/titlebar.rs marks its drag area and
                    // caption buttons for hit-testing (snap layouts work).
                    titlebar: Some(TitlebarOptions {
                        title: Some(BASE_TITLE.into()),
                        appears_transparent: true,
                        ..Default::default()
                    }),
                    window_min_size: Some(size(px(720.0), px(420.0))),
                    app_id: Some(APP_ID.into()),
                    focus: !background,
                    ..Default::default()
                },
                |window, cx| cx.new(|cx| RootView::new(window, cx)),
            )
        };
        let window = match opened {
            Ok(window) => window,
            Err(error) => startup::window_failed(&error),
        };
        window
            .update(cx, |root, window, cx| {
                SettingsService::follow_window_appearance(window, cx);
                root.focus_terminal(window, cx);
                if !background {
                    cx.activate(true);
                }
                // The first frame (Ruling 6): GPUI runs next-frame callbacks at the start of a
                // frame request, so the second one runs once the first frame was presented.
                window.on_next_frame(|window, _| {
                    window.on_next_frame(|_, _| startup::first_frame_drawn())
                });
                #[cfg(target_os = "macos")]
                root.dev_settings_preview(window, cx);
            })
            .ok();
        // `--crash-test panic|native` (Ruling 31): a foreground task runs inside GPUI's window
        // procedure (on a Mac its dispatcher trampoline), the path a real UI-thread crash takes.
        match crash::crash_test() {
            Some(CrashTest::Panic) => {
                // The procedure cannot unwind: the hook writes the file, then the process
                // aborts.
                cx.spawn(async move |_| -> () {
                    // A crash test never changes the next start's display mode (I-4).
                    startup::orderly_quit();
                    panic!("crash test: a panic on the UI thread (--crash-test panic)")
                })
                .detach();
            }
            Some(CrashTest::Native) => {
                cx.spawn(async move |_| {
                    startup::orderly_quit();
                    // SAFETY: none; this is the deliberate access violation of `--crash-test
                    // native`: a write into the first page, which is never mapped. Address 8,
                    // not null, so debug builds' null-pointer check cannot turn it into a panic.
                    unsafe { std::ptr::without_provenance_mut::<u8>(8).write_volatile(1) }
                })
                .detach();
            }
            _ => {}
        }
        // The last window but Settings closed: Settings closes with it (keeping its frame) and
        // the app quits.
        cx.on_window_closed(|cx| {
            if cx.windows().iter().all(is_settings_window) {
                close_settings_windows(cx);
                startup::orderly_quit();
                cx.quit();
            }
        })
        .detach();
    });
}

#[cfg(test)]
mod tests {
    use super::background_requested;

    #[test]
    fn only_the_exact_switch_opens_the_window_in_the_background() {
        assert!(background_requested(Some("1")));
        for other in [None, Some(""), Some("0"), Some("true"), Some(" 1")] {
            assert!(!background_requested(other), "{other:?}");
        }
    }
}
