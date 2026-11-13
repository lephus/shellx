//! Pure Rust model for the ShellX Windows app: no GPUI, no libghostty.

pub mod account;
pub mod account_view;
pub mod controls;
pub mod core_api;
pub mod crash_report;
pub mod diagnose;
pub mod email_sign_in;
pub mod first_window;
pub mod google_button;
pub mod history;
pub mod keys;
pub mod layout;
pub mod links;
pub mod log_file;
pub mod modal;
pub mod mouse;
pub mod palette;
pub mod paste;
pub mod redact;
pub mod remote_state;
pub mod selection;
pub mod settings;
pub mod settings_catalog;
pub mod settings_search;
pub mod shell;
pub mod sidebar;
pub mod start_guard;
pub mod strings;
pub mod tabs;
pub mod theme_file;
pub mod text_edit;
pub mod update;

pub use keys::Dir;

/// Version of the ShellX Windows app (the workspace version).
pub const VERSION: &str = env!("CARGO_PKG_VERSION");

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn version_matches_workspace() {
        assert_eq!(VERSION, "1.7.1");
    }
}
