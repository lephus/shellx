//! The user's own terminal themes: the files of `native_dir()/themes`, one theme per file,
//! named by the file. Reading is best effort: a missing folder, an unreadable file or one that
//! is not UTF-8 is skipped; which files are read (size and count caps, order) is
//! `shellx_model::theme_file::user_theme_files`. Nothing here logs a file name or its content.

use std::fs;

use shellx_model::theme_file::user_theme_files;

use crate::paths;

/// The user's theme files as (name, text), in name order. Empty when there are none.
pub fn read() -> Vec<(String, String)> {
    let Ok(dir) = paths::native_dir().map(|dir| dir.join("themes")) else {
        return Vec::new();
    };
    let Ok(entries) = fs::read_dir(&dir) else {
        return Vec::new();
    };
    // Only the first few thousand entries are looked at, so a folder of millions of files
    // costs a bounded time.
    let found: Vec<(String, u64)> = entries
        .flatten()
        .take(5_000)
        .filter_map(|entry| {
            let meta = entry.metadata().ok().filter(|meta| meta.is_file())?;
            Some((entry.file_name().into_string().ok()?, meta.len()))
        })
        .collect();
    user_theme_files(&found)
        .into_iter()
        .filter_map(|i| {
            let name = &found[i].0;
            let text = fs::read_to_string(dir.join(name)).ok()?;
            Some((name.clone(), text))
        })
        .collect()
}
