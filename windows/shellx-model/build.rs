//! Writes `bundled_themes.rs` into OUT_DIR: one `include_str!` entry per Ghostty theme file in
//! `Resources/ghostty/themes`, sorted case-insensitively by name.

use std::{env, fs, path::PathBuf};

fn main() {
    let manifest = PathBuf::from(env::var("CARGO_MANIFEST_DIR").expect("CARGO_MANIFEST_DIR"));
    let dir = manifest.join("../../Resources/ghostty/themes");
    let dir = fs::canonicalize(&dir).unwrap_or_else(|e| panic!("{}: {e}", dir.display()));
    println!("cargo:rerun-if-changed={}", dir.display());

    let mut names: Vec<String> = fs::read_dir(&dir)
        .unwrap_or_else(|e| panic!("{}: {e}", dir.display()))
        .filter_map(|entry| {
            let entry = entry.ok()?;
            if !entry.file_type().ok()?.is_file() {
                return None;
            }
            entry.file_name().into_string().ok()
        })
        .filter(|name| !name.starts_with('.'))
        .collect();
    names.sort_by(|a, b| {
        a.to_lowercase()
            .cmp(&b.to_lowercase())
            .then_with(|| a.cmp(b))
    });

    let mut out = String::from("&[\n");
    for name in &names {
        // Absolute path with forward slashes (valid on Windows and macOS); `{:?}` escapes it.
        let path = dir.join(name).to_string_lossy().replace('\\', "/");
        let path = path.strip_prefix("//?/").unwrap_or(&path).to_string();
        out.push_str(&format!("    ({name:?}, include_str!({path:?})),\n"));
    }
    out.push_str("]\n");
    let dest = PathBuf::from(env::var("OUT_DIR").expect("OUT_DIR")).join("bundled_themes.rs");
    fs::write(dest, out).expect("write bundled_themes.rs");
}
