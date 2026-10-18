//! The GPUI window (Windows only): custom title bar, machine sidebar, and
//! tabs of split terminal panes, styled per spec §7.1 / §7.4.

mod app;
mod assets;
mod panes;
mod root;
mod sidebar;
mod term_view;
mod theme;
mod titlebar;

/// Opens the ShellX window and runs the app until it quits.
pub fn run() {
    app::run();
}
