//! Pure Rust model for the ShellX Windows app: no GPUI, no libghostty.

pub mod account;
pub mod core_api;
pub mod first_window;
pub mod google_button;
pub mod history;
pub mod keys;
pub mod layout;
pub mod links;
pub mod modal;
pub mod mouse;
pub mod palette;
pub mod paste;
pub mod redact;
pub mod remote_state;
pub mod selection;
pub mod shell;
pub mod sidebar;
pub mod strings;
pub mod tabs;
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
        assert_eq!(VERSION, "1.7.0");
    }
}
