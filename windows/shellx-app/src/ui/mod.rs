//! The GPUI window (Windows only): custom title bar, machine sidebar, and
//! tabs of split terminal panes, styled per spec §7.1 / §7.4.

mod account;
mod app;
mod assets;
mod button;
mod login;
mod pairing;
mod panes;
mod root;
mod settings;
mod sidebar;
mod term_view;
mod text_field;
mod theme;
mod titlebar;
mod update_banner;

/// Opens the ShellX window and runs the app until it quits.
pub fn run() {
    app::run();
}
