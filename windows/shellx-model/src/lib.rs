//! Pure Rust model for the ShellX Windows app: no GPUI, no libghostty.

pub mod keys;
pub mod palette;
pub mod paste;
pub mod strings;

pub use keys::Dir;

/// Version of the ShellX Windows app (the workspace version).
pub const VERSION: &str = env!("CARGO_PKG_VERSION");

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn version_matches_workspace() {
        assert_eq!(VERSION, "2.0.0");
    }
}
