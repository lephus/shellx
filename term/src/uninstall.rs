//! `shellx-term uninstall`: removes the ShellX integration block from every
//! shell config file and deletes the `bin` directory (spec §5.1, §10.2, §10.6).
//!
//! Only the lines from the begin marker to the end marker are removed; the
//! rest of each file is kept byte for byte, in its own encoding (UTF-8, UTF-8
//! BOM, UTF-16 LE/BE) and line endings (LF/CRLF). Running it again, or
//! without anything installed, changes nothing.

use std::fmt;
use std::io::Write;
use std::path::{Path, PathBuf};

pub const BEGIN: &str = "# >>> ShellX >>>";
pub const END: &str = "# <<< ShellX <<<";

/// What `remove_block` found.
#[derive(Debug, PartialEq, Eq)]
pub enum Removal {
    /// No marker at all.
    NoBlock,
    /// The file without its block(s).
    Removed(Vec<u8>),
    /// A begin marker without an end marker; nothing to remove safely.
    Unterminated,
    /// UTF-16 with an odd number of bytes: not text we can scan.
    BadEncoding,
}

/// Removes begin..end lines in a sequence of code units (bytes or UTF-16
/// units). A marker is a whole line (after dropping one trailing `\r`),
/// exactly as the app's editor matches. Every other unit is kept as is.
fn strip<T: Copy + PartialEq>(
    units: &[T],
    nl: T,
    cr: T,
    begin: &[T],
    end: &[T],
) -> Option<Result<Vec<T>, ()>> {
    let is = |line: &[T], marker: &[T]| {
        let line = line.strip_suffix(&[nl]).unwrap_or(line);
        let line = line.strip_suffix(&[cr]).unwrap_or(line);
        line == marker
    };
    let mut out = Vec::with_capacity(units.len());
    let mut pending: Vec<T> = Vec::new();
    let mut inside = false;
    let mut removed = false;
    let mut saw_begin = false;
    for line in units.split_inclusive(|u| *u == nl) {
        if inside {
            pending.extend_from_slice(line);
            if is(line, end) {
                inside = false;
                pending.clear();
                removed = true;
            }
        } else if is(line, begin) {
            inside = true;
            saw_begin = true;
            pending.extend_from_slice(line);
        } else {
            out.extend_from_slice(line);
        }
    }
    out.extend_from_slice(&pending);
    if removed {
        Some(Ok(out))
    } else if saw_begin {
        Some(Err(()))
    } else {
        None
    }
}

/// Removes every complete ShellX block from `bytes`, whatever the encoding
/// (UTF-8, UTF-8 BOM, UTF-16 LE/BE, or 8-bit code pages: the markers are
/// ASCII, so the other bytes never need decoding).
pub fn remove_block(bytes: &[u8]) -> Removal {
    fn finish(r: Option<Result<Vec<u8>, ()>>) -> Removal {
        match r {
            None => Removal::NoBlock,
            Some(Ok(out)) => Removal::Removed(out),
            Some(Err(())) => Removal::Unterminated,
        }
    }
    let utf16 = |body: &[u8], le: bool| -> Removal {
        if !body.len().is_multiple_of(2) {
            return Removal::BadEncoding;
        }
        let from = |c: &[u8]| {
            if le {
                u16::from_le_bytes([c[0], c[1]])
            } else {
                u16::from_be_bytes([c[0], c[1]])
            }
        };
        let units: Vec<u16> = body.chunks_exact(2).map(from).collect();
        let b: Vec<u16> = BEGIN.encode_utf16().collect();
        let e: Vec<u16> = END.encode_utf16().collect();
        match strip(&units, 0x0A, 0x0D, &b, &e) {
            None => Removal::NoBlock,
            Some(Err(())) => Removal::Unterminated,
            Some(Ok(out)) => {
                let bom: [u8; 2] = if le { [0xFF, 0xFE] } else { [0xFE, 0xFF] };
                let mut v = bom.to_vec();
                for u in out {
                    v.extend_from_slice(&if le { u.to_le_bytes() } else { u.to_be_bytes() });
                }
                Removal::Removed(v)
            }
        }
    };
    if let Some(body) = bytes.strip_prefix(&[0xFF, 0xFE]) {
        return utf16(body, true);
    }
    if let Some(body) = bytes.strip_prefix(&[0xFE, 0xFF]) {
        return utf16(body, false);
    }
    let (prefix, body) = match bytes.strip_prefix(&[0xEF, 0xBB, 0xBF]) {
        Some(body) => (&bytes[..3], body),
        None => (&bytes[..0], bytes),
    };
    match finish(strip(body, b'\n', b'\r', BEGIN.as_bytes(), END.as_bytes())) {
        Removal::Removed(out) => Removal::Removed([prefix, &out[..]].concat()),
        other => other,
    }
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

/// `<...>/ShellX`: the folder holding `bin` and `term`.
pub fn shellx_dir(home: &Path, local_app_data: Option<&Path>, windows: bool) -> PathBuf {
    if windows {
        local_app_data
            .map(Path::to_path_buf)
            .unwrap_or_else(|| home.join("AppData").join("Local"))
            .join("ShellX")
    } else {
        home.join("Library/Application Support/ShellX")
    }
}

/// The directory the blocks point at.
pub fn bin_dir(home: &Path, local_app_data: Option<&Path>, windows: bool) -> PathBuf {
    shellx_dir(home, local_app_data, windows).join("bin")
}

#[derive(Debug, PartialEq, Eq)]
pub enum FileOutcome {
    Removed,
    NoBlock,
    Missing,
    /// Found something we will not touch (reason).
    Skipped(String),
    Failed(String),
}

#[derive(Debug, PartialEq, Eq)]
pub enum DirOutcome {
    Removed,
    Missing,
    /// Not deleted on purpose (reason).
    Kept(String),
    /// Windows: the running executable cannot be deleted; the rest is gone.
    LeftRunning(PathBuf),
    Failed(String),
}

#[derive(Debug)]
pub struct Report {
    pub files: Vec<(PathBuf, FileOutcome)>,
    /// Windows without a user profile folder: PowerShell profiles unknown.
    pub profiles_unknown: bool,
    pub bin: (PathBuf, DirOutcome),
    pub term: (PathBuf, DirOutcome),
}

impl Report {
    /// Something failed or was skipped: the exit code is non-zero.
    pub fn has_errors(&self) -> bool {
        self.profiles_unknown
            || self.file_problem()
            || matches!(self.bin.1, DirOutcome::Failed(_))
            || matches!(self.term.1, DirOutcome::Failed(_))
    }

    fn file_problem(&self) -> bool {
        self.files
            .iter()
            .any(|(_, o)| matches!(o, FileOutcome::Failed(_) | FileOutcome::Skipped(_)))
    }

    fn nothing_found(&self) -> bool {
        !self.profiles_unknown
            && self
                .files
                .iter()
                .all(|(_, o)| matches!(o, FileOutcome::NoBlock | FileOutcome::Missing))
            && self.bin.1 == DirOutcome::Missing
            && self.term.1 == DirOutcome::Missing
    }
}

fn describe(f: &mut fmt::Formatter<'_>, dir: &Path, outcome: &DirOutcome) -> fmt::Result {
    match outcome {
        DirOutcome::Removed => writeln!(f, "Deleted {}", dir.display()),
        DirOutcome::Missing => Ok(()),
        DirOutcome::Kept(why) => writeln!(f, "Kept {}: {why}", dir.display()),
        DirOutcome::LeftRunning(exe) => writeln!(
            f,
            "Deleted the contents of {} except {} (in use); delete it after closing ShellX terminals",
            dir.display(),
            exe.display()
        ),
        DirOutcome::Failed(why) => writeln!(f, "Could not delete {}: {why}", dir.display()),
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
        if self.profiles_unknown {
            writeln!(
                f,
                "Skipped the PowerShell profiles: the user profile folder is not known"
            )?;
        }
        for (path, outcome) in &self.files {
            match outcome {
                FileOutcome::Removed => {
                    writeln!(f, "Removed the ShellX block from {}", path.display())?
                }
                FileOutcome::Skipped(why) => writeln!(f, "Skipped {}: {why}", path.display())?,
                FileOutcome::Failed(why) => {
                    writeln!(f, "Could not update {}: {why}", path.display())?
                }
                FileOutcome::NoBlock | FileOutcome::Missing => {}
            }
        }
        describe(f, &self.bin.0, &self.bin.1)?;
        describe(f, &self.term.0, &self.term.1)
    }
}

/// Replaces `path`'s content crash-safely: temp file beside the real target
/// (symlinks resolved), same mode, fsync, rename over it. Falls back to
/// writing in place where a rename would change the file (hard links, other
/// owner), where no temp file can be made, and, on Windows, when the rename
/// is refused (a sync client holding the file).
fn write_file(path: &Path, data: &[u8]) -> std::io::Result<()> {
    let target = std::fs::canonicalize(path)?;
    let meta = std::fs::metadata(&target)?;
    #[cfg(unix)]
    {
        use std::os::unix::fs::MetadataExt;
        if meta.nlink() > 1 || meta.uid() != unsafe { libc::geteuid() } {
            return std::fs::write(&target, data);
        }
    }
    let Some(dir) = target.parent() else {
        return std::fs::write(&target, data);
    };
    let name = target.file_name().unwrap_or_default().to_string_lossy();
    let tmp = dir.join(format!(".{name}.shellx-tmp-{}", std::process::id()));
    let mut options = std::fs::OpenOptions::new();
    options.write(true).create_new(true);
    #[cfg(unix)]
    {
        use std::os::unix::fs::OpenOptionsExt;
        use std::os::unix::fs::PermissionsExt;
        options.mode(meta.permissions().mode() & 0o7777);
    }
    let Ok(mut file) = options.open(&tmp) else {
        return std::fs::write(&target, data);
    };
    let written = file
        .write_all(data)
        .and_then(|()| file.set_permissions(meta.permissions()))
        .and_then(|()| file.sync_all());
    drop(file);
    if let Err(e) = written {
        let _ = std::fs::remove_file(&tmp);
        return Err(e);
    }
    match std::fs::rename(&tmp, &target) {
        Ok(()) => {
            #[cfg(unix)]
            if let Ok(d) = std::fs::File::open(dir) {
                let _ = d.sync_all();
            }
            Ok(())
        }
        Err(e) => {
            let _ = std::fs::remove_file(&tmp);
            if cfg!(windows) {
                std::fs::write(&target, data)
            } else {
                Err(e)
            }
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
        Removal::NoBlock => FileOutcome::NoBlock,
        Removal::Unterminated => FileOutcome::Skipped(format!(
            "has `{BEGIN}` without `{END}`; left unchanged, remove it by hand"
        )),
        Removal::BadEncoding => {
            FileOutcome::Skipped("unreadable UTF-16 (odd length); left unchanged".into())
        }
        Removal::Removed(cleaned) => match write_file(path, &cleaned) {
            Ok(()) => FileOutcome::Removed,
            Err(e) => FileOutcome::Failed(e.to_string()),
        },
    }
}

fn delete_dir(dir: &Path, windows: bool, running: Option<&Path>) -> DirOutcome {
    let meta = match std::fs::symlink_metadata(dir) {
        Ok(meta) => meta,
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => return DirOutcome::Missing,
        Err(e) => return DirOutcome::Failed(e.to_string()),
    };
    let result = if meta.file_type().is_symlink() || meta.is_file() {
        std::fs::remove_file(dir)
    } else {
        std::fs::remove_dir_all(dir)
    };
    match result {
        Ok(()) => DirOutcome::Removed,
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
                DirOutcome::LeftRunning(exe.to_path_buf())
            }
            None => DirOutcome::Failed(e.to_string()),
        },
        Err(e) => DirOutcome::Failed(e.to_string()),
    }
}

/// Does the whole uninstall. `home` is `None` on Windows when the user
/// profile folder is unknown (the PowerShell profiles are then skipped).
pub fn run_with(
    home: Option<&Path>,
    local_app_data: Option<&Path>,
    windows: bool,
    running: Option<&Path>,
) -> Report {
    let files: Vec<(PathBuf, FileOutcome)> = home
        .map(|home| config_files(home, windows))
        .unwrap_or_default()
        .into_iter()
        .map(|path| {
            let outcome = clean_file(&path);
            (path, outcome)
        })
        .collect();
    let base = shellx_dir(home.unwrap_or(Path::new("")), local_app_data, windows);
    let (bin, term) = (base.join("bin"), base.join("term"));
    let problem = files
        .iter()
        .any(|(_, o)| matches!(o, FileOutcome::Failed(_) | FileOutcome::Skipped(_)));
    let (bin_outcome, term_outcome) = if problem {
        // Keep the binary: the user fixes the file and runs this again.
        let keep = |dir: &Path| match std::fs::symlink_metadata(dir) {
            Ok(_) => {
                DirOutcome::Kept("so you can run this again after fixing the problem above".into())
            }
            Err(_) => DirOutcome::Missing,
        };
        (keep(&bin), keep(&term))
    } else {
        (
            delete_dir(&bin, windows, running),
            delete_dir(&term, windows, running),
        )
    };
    Report {
        files,
        profiles_unknown: home.is_none(),
        bin: (bin, bin_outcome),
        term: (term, term_outcome),
    }
}

pub fn run(home: Option<&Path>, local_app_data: Option<&Path>) -> Report {
    let running = std::env::current_exe().ok();
    run_with(home, local_app_data, cfg!(windows), running.as_deref())
}

/// Entry point of the subcommand: prints the summary, returns the exit code.
pub fn main() -> i32 {
    let windows = cfg!(windows);
    let var = if windows { "USERPROFILE" } else { "HOME" };
    let home = std::env::var_os(var)
        .filter(|h| !h.is_empty())
        .map(PathBuf::from);
    let local = std::env::var_os("LOCALAPPDATA")
        .filter(|h| !h.is_empty())
        .map(PathBuf::from);
    // Windows needs only LOCALAPPDATA for `bin` and `term`; Unix needs HOME.
    if home.is_none() && (!windows || local.is_none()) {
        let _ = writeln!(std::io::stderr(), "shellx-term: {var} is not set");
        return 1;
    }
    let report = run(home.as_deref(), local.as_deref());
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

    fn removed(bytes: &[u8]) -> Vec<u8> {
        match remove_block(bytes) {
            Removal::Removed(out) => out,
            other => panic!("expected Removed, got {other:?}"),
        }
    }

    fn utf16(text: &str, le: bool) -> Vec<u8> {
        let mut v = if le {
            vec![0xFF, 0xFE]
        } else {
            vec![0xFE, 0xFF]
        };
        for u in text.encode_utf16() {
            v.extend_from_slice(&if le { u.to_le_bytes() } else { u.to_be_bytes() });
        }
        v
    }

    #[test]
    fn removes_the_block_and_keeps_the_rest_for_lf_and_crlf() {
        for eol in ["\n", "\r\n"] {
            let input = format!("export A=1{eol}{}export B=2 # é{eol}", block(eol));
            assert_eq!(
                removed(input.as_bytes()),
                format!("export A=1{eol}export B=2 # é{eol}").as_bytes()
            );
        }
    }

    #[test]
    fn block_at_the_top_or_end_and_without_a_final_newline() {
        let top = format!("{}rest\n", block("\n"));
        assert_eq!(removed(top.as_bytes()), b"rest\n");
        let end = format!("rest\n{BEGIN}\nx\n{END}");
        assert_eq!(removed(end.as_bytes()), b"rest\n");
        assert_eq!(removed(block("\n").as_bytes()), b"");
    }

    #[test]
    fn keeps_each_encoding() {
        let text = format!("a\r\n{}b é\r\n", block("\r\n"));
        let want = "a\r\nb é\r\n";
        let utf8_bom = [&[0xEF, 0xBB, 0xBF][..], text.as_bytes()].concat();
        assert_eq!(
            removed(&utf8_bom),
            [&[0xEF, 0xBB, 0xBF][..], want.as_bytes()].concat()
        );
        for le in [true, false] {
            assert_eq!(removed(&utf16(&text, le)), utf16(want, le));
        }
    }

    #[test]
    fn non_utf8_bytes_are_kept_exactly() {
        // Latin-1 / cp1258 profile: 0xE9, 0xFF and a lone 0xC3 survive.
        let mut input = b"# caf\xe9 \xff\n".to_vec();
        input.extend_from_slice(block("\n").as_bytes());
        input.extend_from_slice(b"tail \xc3\n");
        assert_eq!(removed(&input), b"# caf\xe9 \xff\ntail \xc3\n");
        // Same with a UTF-8 BOM that is followed by invalid UTF-8.
        let bom = [&[0xEF, 0xBB, 0xBF][..], &input].concat();
        assert_eq!(
            removed(&bom),
            [&[0xEF, 0xBB, 0xBF][..], b"# caf\xe9 \xff\ntail \xc3\n"].concat()
        );
    }

    #[test]
    fn utf16_with_a_lone_surrogate_is_handled() {
        for le in [true, false] {
            let mut input = utf16(&format!("a\n{}b\n", block("\n")), le);
            // Splice a lone surrogate (0xD800) before the final "b\n".
            let at = input.len() - 4;
            let lone = if le { [0x00, 0xD8] } else { [0xD8, 0x00] };
            input.splice(at..at, lone);
            let mut want = utf16("a\n", le);
            want.extend_from_slice(&lone);
            for u in "b\n".encode_utf16() {
                want.extend_from_slice(&if le { u.to_le_bytes() } else { u.to_be_bytes() });
            }
            assert_eq!(removed(&input), want);
        }
    }

    #[test]
    fn nothing_to_remove() {
        assert_eq!(remove_block(b""), Removal::NoBlock);
        assert_eq!(remove_block(b"export A=1\n"), Removal::NoBlock);
        let once = removed(format!("x\n{}", block("\n")).as_bytes());
        assert_eq!(remove_block(&once), Removal::NoBlock);
    }

    #[test]
    fn unterminated_and_odd_length_are_reported_not_hidden() {
        assert_eq!(
            remove_block(format!("a\n{BEGIN}\nb\n").as_bytes()),
            Removal::Unterminated
        );
        assert_eq!(remove_block(&[0xFF, 0xFE, 0x41]), Removal::BadEncoding);
    }

    #[test]
    fn markers_must_be_the_whole_line() {
        // Indented (inside a function) or with other text: left alone.
        let indented = format!("f() {{\n  {BEGIN}\n  echo hi\n  {END}\n}}\n");
        assert_eq!(remove_block(indented.as_bytes()), Removal::NoBlock);
        let trailing = format!("{BEGIN} \nx\n{END}\n");
        assert_eq!(remove_block(trailing.as_bytes()), Removal::NoBlock);
    }

    #[test]
    fn removes_several_blocks_but_not_a_marker_inside_a_line() {
        let input = format!("{}mid\necho '{BEGIN}'\n{}", block("\n"), block("\n"));
        assert_eq!(
            removed(input.as_bytes()),
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

    #[test]
    fn windows_without_a_profile_folder_still_cleans_bin_and_term() {
        let root = temp("winhome");
        let shellx = root.join("ShellX");
        std::fs::create_dir_all(shellx.join("bin")).unwrap();
        std::fs::create_dir_all(shellx.join("term")).unwrap();
        let report = run_with(None, Some(&root), true, None);
        assert!(report.profiles_unknown && report.has_errors());
        assert_eq!(report.bin.1, DirOutcome::Removed);
        assert_eq!(report.term.1, DirOutcome::Removed);
        assert!(report
            .to_string()
            .contains("Skipped the PowerShell profiles"));
        let _ = std::fs::remove_dir_all(&root);
    }

    fn temp(name: &str) -> PathBuf {
        let dir =
            std::env::temp_dir().join(format!("shellx-uninstall-{}-{name}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        dir
    }

    #[cfg(unix)]
    mod fs {
        use super::*;
        use std::os::unix::fs::{MetadataExt, PermissionsExt};

        fn run_home(home: &Path) -> Report {
            run_with(Some(home), None, false, None)
        }

        #[test]
        fn cleans_files_deletes_bin_and_term_and_is_idempotent() {
            let home = temp("run");
            std::fs::write(home.join(".zshrc"), format!("a\n{}", block("\n"))).unwrap();
            std::fs::write(home.join(".bashrc"), "plain\n").unwrap();
            let shellx = shellx_dir(&home, None, false);
            for d in ["bin", "term"] {
                std::fs::create_dir_all(shellx.join(d)).unwrap();
                std::fs::write(shellx.join(d).join("f"), "x").unwrap();
            }

            let first = run_home(&home);
            assert!(!first.has_errors());
            assert_eq!(first.files[0].1, FileOutcome::Removed);
            assert_eq!(first.files[1].1, FileOutcome::NoBlock);
            assert_eq!(first.files[2].1, FileOutcome::Missing);
            assert_eq!(first.bin.1, DirOutcome::Removed);
            assert_eq!(first.term.1, DirOutcome::Removed);
            assert_eq!(std::fs::read(home.join(".zshrc")).unwrap(), b"a\n");
            assert!(!home.join(".bash_profile").exists(), "never created");
            assert!(first.to_string().contains("Removed the ShellX block"));

            let second = run_home(&home);
            assert!(!second.has_errors());
            assert!(second.to_string().contains("nothing to remove"));
            let _ = std::fs::remove_dir_all(&home);
        }

        #[test]
        fn a_symlinked_file_stays_a_link_and_the_target_keeps_mode_and_content() {
            let home = temp("symlink");
            let real = home.join("dotfiles-zshrc");
            std::fs::write(&real, format!("keep\n{}", block("\n"))).unwrap();
            std::fs::set_permissions(&real, std::fs::Permissions::from_mode(0o600)).unwrap();
            std::os::unix::fs::symlink(&real, home.join(".zshrc")).unwrap();
            let report = run_home(&home);
            assert_eq!(report.files[0].1, FileOutcome::Removed);
            assert!(std::fs::symlink_metadata(home.join(".zshrc"))
                .unwrap()
                .file_type()
                .is_symlink());
            assert_eq!(std::fs::read(&real).unwrap(), b"keep\n");
            assert_eq!(std::fs::metadata(&real).unwrap().mode() & 0o7777, 0o600);
            // No temp file left behind.
            let leftovers: Vec<_> = std::fs::read_dir(&home)
                .unwrap()
                .flatten()
                .filter(|e| e.file_name().to_string_lossy().contains("shellx-tmp"))
                .collect();
            assert!(leftovers.is_empty());
            let _ = std::fs::remove_dir_all(&home);
        }

        #[test]
        fn permissions_are_kept_and_hard_links_are_written_in_place() {
            let home = temp("perm");
            let file = home.join(".bashrc");
            std::fs::write(&file, format!("x\n{}", block("\n"))).unwrap();
            std::fs::set_permissions(&file, std::fs::Permissions::from_mode(0o640)).unwrap();
            assert_eq!(run_home(&home).files[1].1, FileOutcome::Removed);
            assert_eq!(std::fs::metadata(&file).unwrap().mode() & 0o7777, 0o640);

            let other = home.join(".zshrc");
            std::fs::write(&other, format!("y\n{}", block("\n"))).unwrap();
            let linked = home.join("linked");
            std::fs::hard_link(&other, &linked).unwrap();
            assert_eq!(run_home(&home).files[0].1, FileOutcome::Removed);
            // Both names still see the same (edited) file.
            assert_eq!(std::fs::read(&linked).unwrap(), b"y\n");
            assert_eq!(std::fs::read(&other).unwrap(), b"y\n");
            assert_eq!(std::fs::metadata(&other).unwrap().nlink(), 2);
            let _ = std::fs::remove_dir_all(&home);
        }

        #[test]
        fn skipped_files_are_printed_fail_the_run_and_keep_bin() {
            let home = temp("skipped");
            let content = format!("a\n{BEGIN}\nunfinished\n");
            std::fs::write(home.join(".bashrc"), &content).unwrap();
            let bin = bin_dir(&home, None, false);
            std::fs::create_dir_all(&bin).unwrap();
            let report = run_home(&home);
            assert!(matches!(report.files[1].1, FileOutcome::Skipped(_)));
            assert!(report.has_errors());
            let text = report.to_string();
            assert!(
                text.contains("Skipped") && text.contains(".bashrc"),
                "{text}"
            );
            assert!(!text.contains("nothing to remove"));
            assert!(matches!(report.bin.1, DirOutcome::Kept(_)));
            assert!(bin.exists());
            assert_eq!(
                std::fs::read(home.join(".bashrc")).unwrap(),
                content.as_bytes()
            );
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
            assert_eq!(run_home(&home).bin.1, DirOutcome::Removed);
            assert!(target.join("keep").exists());
            let _ = std::fs::remove_dir_all(&home);
        }
    }
}
