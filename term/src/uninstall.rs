//! `shellx-term uninstall`: removes the ShellX integration block from every
//! shell config file and deletes the `bin` directory (spec §5.1, §10.2, §10.6).
//!
//! Only the lines from the begin marker to the end marker are removed; the
//! rest of each file is kept byte for byte, in its own encoding (UTF-8, UTF-8
//! BOM, UTF-16 LE/BE) and line endings (LF/CRLF). Running it again, or
//! without anything installed, changes nothing.

use std::fmt;
use std::path::{Path, PathBuf};

pub const BEGIN: &str = "# >>> ShellX >>>";
pub const END: &str = "# <<< ShellX <<<";

#[derive(Clone, Copy)]
enum Encoding {
    Utf8,
    Utf8Bom,
    Utf16Le,
    Utf16Be,
}

fn decode(bytes: &[u8]) -> Option<(Encoding, String)> {
    let utf16 = |body: &[u8], from: fn([u8; 2]) -> u16| -> Option<String> {
        if !body.len().is_multiple_of(2) {
            return None;
        }
        let units: Vec<u16> = body.chunks_exact(2).map(|c| from([c[0], c[1]])).collect();
        String::from_utf16(&units).ok()
    };
    if let Some(body) = bytes.strip_prefix(&[0xEF, 0xBB, 0xBF]) {
        return Some((Encoding::Utf8Bom, String::from_utf8(body.to_vec()).ok()?));
    }
    if let Some(body) = bytes.strip_prefix(&[0xFF, 0xFE]) {
        return Some((Encoding::Utf16Le, utf16(body, u16::from_le_bytes)?));
    }
    if let Some(body) = bytes.strip_prefix(&[0xFE, 0xFF]) {
        return Some((Encoding::Utf16Be, utf16(body, u16::from_be_bytes)?));
    }
    Some((Encoding::Utf8, String::from_utf8(bytes.to_vec()).ok()?))
}

fn encode(encoding: Encoding, text: &str) -> Vec<u8> {
    match encoding {
        Encoding::Utf8 => text.as_bytes().to_vec(),
        Encoding::Utf8Bom => [&[0xEF, 0xBB, 0xBF][..], text.as_bytes()].concat(),
        Encoding::Utf16Le => [0xFF, 0xFE]
            .into_iter()
            .chain(text.encode_utf16().flat_map(u16::to_le_bytes))
            .collect(),
        Encoding::Utf16Be => [0xFE, 0xFF]
            .into_iter()
            .chain(text.encode_utf16().flat_map(u16::to_be_bytes))
            .collect(),
    }
}

/// Removes every complete ShellX block (begin line through end line, with its
/// line break) from `bytes`. `None` when there is nothing to remove: no block,
/// a begin marker without its end marker (left alone rather than guessing), or
/// content that is not text in a supported encoding.
pub fn remove_block(bytes: &[u8]) -> Option<Vec<u8>> {
    let (encoding, text) = decode(bytes)?;
    let marker = |line: &str, which: &str| line.trim_matches(['\r', '\n', ' ', '\t']) == which;
    let mut out = String::with_capacity(text.len());
    let mut pending = String::new();
    let mut inside = false;
    let mut removed = false;
    for line in text.split_inclusive('\n') {
        if inside {
            pending.push_str(line);
            if marker(line, END) {
                inside = false;
                pending.clear();
                removed = true;
            }
        } else if marker(line, BEGIN) {
            inside = true;
            pending.push_str(line);
        } else {
            out.push_str(line);
        }
    }
    // An unterminated block stays exactly as it was.
    out.push_str(&pending);
    removed.then(|| encode(encoding, &out))
}

/// Config files that may hold the block, in a fixed order.
pub fn config_files(home: &Path, windows: bool) -> Vec<PathBuf> {
    if windows {
        let mut files = Vec::new();
        for documents in [
            home.join("Documents"),
            home.join("OneDrive").join("Documents"),
        ] {
            for shell in ["PowerShell", "WindowsPowerShell"] {
                files.push(documents.join(shell).join("profile.ps1"));
            }
        }
        files
    } else {
        [".zshrc", ".bashrc", ".bash_profile"]
            .iter()
            .map(|name| home.join(name))
            .collect()
    }
}

/// The directory the blocks point at.
pub fn bin_dir(home: &Path, local_app_data: Option<&Path>, windows: bool) -> PathBuf {
    if windows {
        local_app_data
            .map(Path::to_path_buf)
            .unwrap_or_else(|| home.join("AppData").join("Local"))
            .join("ShellX")
            .join("bin")
    } else {
        home.join("Library/Application Support/ShellX/bin")
    }
}

#[derive(Debug, PartialEq, Eq)]
pub enum FileOutcome {
    Removed,
    NoBlock,
    Missing,
    Failed(String),
}

#[derive(Debug, PartialEq, Eq)]
pub enum BinOutcome {
    Removed,
    Missing,
    /// Windows: the running executable cannot be deleted; the rest is gone.
    LeftRunning(PathBuf),
    Failed(String),
}

#[derive(Debug)]
pub struct Report {
    pub files: Vec<(PathBuf, FileOutcome)>,
    pub bin: (PathBuf, BinOutcome),
}

impl Report {
    pub fn has_errors(&self) -> bool {
        self.files
            .iter()
            .any(|(_, o)| matches!(o, FileOutcome::Failed(_)))
            || matches!(self.bin.1, BinOutcome::Failed(_))
    }

    fn nothing_found(&self) -> bool {
        self.files
            .iter()
            .all(|(_, o)| matches!(o, FileOutcome::NoBlock | FileOutcome::Missing))
            && self.bin.1 == BinOutcome::Missing
    }
}

impl fmt::Display for Report {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        if self.nothing_found() {
            return write!(
                f,
                "ShellX terminal sharing is not installed; nothing to remove."
            );
        }
        for (path, outcome) in &self.files {
            match outcome {
                FileOutcome::Removed => {
                    writeln!(f, "Removed the ShellX block from {}", path.display())?
                }
                FileOutcome::Failed(why) => {
                    writeln!(f, "Could not update {}: {why}", path.display())?
                }
                FileOutcome::NoBlock | FileOutcome::Missing => {}
            }
        }
        let (dir, outcome) = &self.bin;
        match outcome {
            BinOutcome::Removed => write!(f, "Deleted {}", dir.display()),
            BinOutcome::Missing => write!(f, "No bin directory at {}", dir.display()),
            BinOutcome::LeftRunning(exe) => write!(
                f,
                "Deleted the contents of {} except {} (in use); delete it after closing ShellX terminals",
                dir.display(),
                exe.display()
            ),
            BinOutcome::Failed(why) => write!(f, "Could not delete {}: {why}", dir.display()),
        }
    }
}

fn clean_file(path: &Path) -> FileOutcome {
    let bytes = match std::fs::read(path) {
        Ok(bytes) => bytes,
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => return FileOutcome::Missing,
        Err(e) => return FileOutcome::Failed(e.to_string()),
    };
    match remove_block(&bytes) {
        None => FileOutcome::NoBlock,
        // In place (not rename): keeps permissions and symlinked dotfiles.
        Some(cleaned) => match std::fs::write(path, cleaned) {
            Ok(()) => FileOutcome::Removed,
            Err(e) => FileOutcome::Failed(e.to_string()),
        },
    }
}

fn delete_bin(dir: &Path, windows: bool, running: Option<&Path>) -> BinOutcome {
    let meta = match std::fs::symlink_metadata(dir) {
        Ok(meta) => meta,
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => return BinOutcome::Missing,
        Err(e) => return BinOutcome::Failed(e.to_string()),
    };
    let result = if meta.file_type().is_symlink() || meta.is_file() {
        std::fs::remove_file(dir)
    } else {
        std::fs::remove_dir_all(dir)
    };
    match result {
        Ok(()) => BinOutcome::Removed,
        Err(e) if windows => match running.filter(|exe| exe.starts_with(dir)) {
            Some(exe) => {
                // The running .exe is locked; take everything else.
                if let Ok(entries) = std::fs::read_dir(dir) {
                    for entry in entries.flatten() {
                        if entry.path() != exe {
                            let _ = std::fs::remove_file(entry.path());
                        }
                    }
                }
                BinOutcome::LeftRunning(exe.to_path_buf())
            }
            None => BinOutcome::Failed(e.to_string()),
        },
        Err(e) => BinOutcome::Failed(e.to_string()),
    }
}

/// Does the whole uninstall for `home` (`local_app_data` on Windows).
pub fn run(home: &Path, local_app_data: Option<&Path>) -> Report {
    let windows = cfg!(windows);
    let files = config_files(home, windows)
        .into_iter()
        .map(|path| {
            let outcome = clean_file(&path);
            (path, outcome)
        })
        .collect();
    let dir = bin_dir(home, local_app_data, windows);
    let running = std::env::current_exe().ok();
    let outcome = delete_bin(&dir, windows, running.as_deref());
    Report {
        files,
        bin: (dir, outcome),
    }
}

/// Entry point of the subcommand: prints the summary, returns the exit code.
pub fn main() -> i32 {
    use std::io::Write;
    let var = if cfg!(windows) { "USERPROFILE" } else { "HOME" };
    let Some(home) = std::env::var_os(var).filter(|h| !h.is_empty()) else {
        let _ = writeln!(std::io::stderr(), "shellx-term: {var} is not set");
        return 1;
    };
    let local = std::env::var_os("LOCALAPPDATA").map(PathBuf::from);
    let report = run(Path::new(&home), local.as_deref());
    if report.has_errors() {
        let _ = writeln!(
            std::io::stderr(),
            "shellx-term: uninstall incomplete\n{report}"
        );
        1
    } else {
        let _ = writeln!(std::io::stdout(), "{report}");
        0
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn block(eol: &str) -> String {
        format!("{BEGIN}{eol}if true; then{eol}  :{eol}fi{eol}{END}{eol}")
    }

    fn utf16(text: &str, le: bool) -> Vec<u8> {
        encode(
            if le {
                Encoding::Utf16Le
            } else {
                Encoding::Utf16Be
            },
            text,
        )
    }

    #[test]
    fn removes_the_block_and_keeps_the_rest_for_lf_and_crlf() {
        for eol in ["\n", "\r\n"] {
            let input = format!("export A=1{eol}{}export B=2 # é{eol}", block(eol));
            let out = remove_block(input.as_bytes()).unwrap();
            assert_eq!(
                out,
                format!("export A=1{eol}export B=2 # é{eol}").as_bytes()
            );
        }
    }

    #[test]
    fn block_at_the_top_or_end_and_without_a_final_newline() {
        let top = format!("{}rest\n", block("\n"));
        assert_eq!(remove_block(top.as_bytes()).unwrap(), b"rest\n");
        let end = format!("rest\n{BEGIN}\nx\n{END}");
        assert_eq!(remove_block(end.as_bytes()).unwrap(), b"rest\n");
        // A file holding only the block becomes empty.
        assert_eq!(remove_block(block("\n").as_bytes()).unwrap(), b"");
    }

    #[test]
    fn keeps_each_encoding() {
        let text = format!("a\r\n{}b é\r\n", block("\r\n"));
        let want = "a\r\nb é\r\n";
        let utf8_bom = [&[0xEF, 0xBB, 0xBF][..], text.as_bytes()].concat();
        assert_eq!(
            remove_block(&utf8_bom).unwrap(),
            [&[0xEF, 0xBB, 0xBF][..], want.as_bytes()].concat()
        );
        for le in [true, false] {
            assert_eq!(remove_block(&utf16(&text, le)).unwrap(), utf16(want, le));
        }
    }

    #[test]
    fn nothing_to_remove_returns_none() {
        assert_eq!(remove_block(b""), None);
        assert_eq!(remove_block(b"export A=1\n"), None);
        // Idempotent: a second pass finds nothing.
        let once = remove_block(format!("x\n{}", block("\n")).as_bytes()).unwrap();
        assert_eq!(remove_block(&once), None);
    }

    #[test]
    fn an_unterminated_block_and_foreign_bytes_are_left_alone() {
        assert_eq!(remove_block(format!("a\n{BEGIN}\nb\n").as_bytes()), None);
        assert_eq!(remove_block(&[0xFF, 0x00, 0xC3, 0x28]), None);
        // Odd length UTF-16.
        assert_eq!(remove_block(&[0xFF, 0xFE, 0x41]), None);
    }

    #[test]
    fn removes_several_blocks_but_not_a_marker_inside_a_line() {
        let input = format!("{}mid\necho '{BEGIN}'\n{}", block("\n"), block("\n"));
        assert_eq!(
            remove_block(input.as_bytes()).unwrap(),
            format!("mid\necho '{BEGIN}'\n").as_bytes()
        );
    }

    #[test]
    fn file_lists() {
        let home = Path::new("/h");
        assert_eq!(
            config_files(home, false),
            ["/h/.zshrc", "/h/.bashrc", "/h/.bash_profile"].map(PathBuf::from)
        );
        assert_eq!(config_files(home, true).len(), 4);
        assert_eq!(
            bin_dir(home, None, false),
            Path::new("/h/Library/Application Support/ShellX/bin")
        );
    }

    #[cfg(unix)]
    mod fs {
        use super::*;

        fn temp(name: &str) -> PathBuf {
            let dir = std::env::temp_dir()
                .join(format!("shellx-uninstall-{}-{name}", std::process::id()));
            let _ = std::fs::remove_dir_all(&dir);
            std::fs::create_dir_all(&dir).unwrap();
            dir
        }

        #[test]
        fn cleans_files_deletes_bin_and_is_idempotent() {
            let home = temp("run");
            std::fs::write(home.join(".zshrc"), format!("a\n{}", block("\n"))).unwrap();
            std::fs::write(home.join(".bashrc"), "plain\n").unwrap();
            let bin = bin_dir(&home, None, false);
            std::fs::create_dir_all(&bin).unwrap();
            std::fs::write(bin.join("shellx-term"), "x").unwrap();

            let first = run(&home, None);
            assert!(!first.has_errors());
            assert_eq!(first.files[0].1, FileOutcome::Removed);
            assert_eq!(first.files[1].1, FileOutcome::NoBlock);
            assert_eq!(first.files[2].1, FileOutcome::Missing);
            assert_eq!(first.bin.1, BinOutcome::Removed);
            assert_eq!(std::fs::read(home.join(".zshrc")).unwrap(), b"a\n");
            assert!(!home.join(".bash_profile").exists(), "never created");
            assert!(first.to_string().contains("Removed the ShellX block"));

            let second = run(&home, None);
            assert!(second.nothing_found());
            assert!(second.to_string().contains("nothing to remove"));
            let _ = std::fs::remove_dir_all(&home);
        }

        #[test]
        fn a_symlinked_bin_is_unlinked_not_followed() {
            let home = temp("link");
            let target = home.join("elsewhere");
            std::fs::create_dir_all(&target).unwrap();
            std::fs::write(target.join("keep"), "x").unwrap();
            let bin = bin_dir(&home, None, false);
            std::fs::create_dir_all(bin.parent().unwrap()).unwrap();
            std::os::unix::fs::symlink(&target, &bin).unwrap();
            assert_eq!(run(&home, None).bin.1, BinOutcome::Removed);
            assert!(target.join("keep").exists());
            let _ = std::fs::remove_dir_all(&home);
        }
    }
}
