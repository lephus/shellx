//! Working directory and git branch of a local terminal, without GPUI.
//!
//! The shell a new tab starts reports its directory with OSC 7 at every
//! prompt (the PowerShell prompt hook); `cwd_from_osc7` turns that URL into a path,
//! `display_path` shortens it with `~` like the Mac sidebar, and `git_branch`
//! reads the branch from `.git/HEAD` (no `git` process, no libgit).

use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::time::{Duration, Instant};

/// `file://HOST/PATH` (OSC 7) to a path: percent-decoded, `/C:/x/y` becomes
/// `C:\x\y`, a unix path stays as it is. Anything else gives `None`.
pub fn cwd_from_osc7(url: &str) -> Option<String> {
    let rest = url.strip_prefix("file://")?;
    // The host ends at the first slash; an empty host is `file:///path`.
    let path = percent_decode(&rest[rest.find('/')?..]);
    let bytes = path.as_bytes();
    // PowerShell sends `/C:/x`: a drive letter after the slash that follows
    // the host (`C:` alone is the drive root).
    if bytes.len() >= 3
        && bytes[1].is_ascii_alphabetic()
        && bytes[2] == b':'
        && bytes.get(3).is_none_or(|&b| b == b'/')
    {
        let drive_path = path[1..].replace('/', "\\");
        return Some(if drive_path.len() == 2 {
            format!("{drive_path}\\")
        } else {
            drive_path
        });
    }
    // A share `\\srv\s` is sent as `///srv/s`.
    if let Some(unc) = path.strip_prefix('/').filter(|p| p.starts_with("//")) {
        return Some(unc.replace('/', "\\"));
    }
    Some(path)
}

/// `%XX` escapes to bytes, read as UTF-8. Text that is not an escape (the
/// shell sends a raw `Tài liệu`, and a lone `%`) is kept as it is.
fn percent_decode(text: &str) -> String {
    let bytes = text.as_bytes();
    let mut out = Vec::with_capacity(bytes.len());
    let mut i = 0;
    while i < bytes.len() {
        if bytes[i] == b'%'
            && i + 2 < bytes.len()
            && let (Some(hi), Some(lo)) = (hex_value(bytes[i + 1]), hex_value(bytes[i + 2]))
        {
            out.push(hi * 16 + lo);
            i += 3;
        } else {
            out.push(bytes[i]);
            i += 1;
        }
    }
    String::from_utf8_lossy(&out).into_owned()
}

fn hex_value(byte: u8) -> Option<u8> {
    char::from(byte).to_digit(16).map(|d| d as u8)
}

/// `~` for `home` itself and `~` + the rest below it (the path's own
/// separator is kept); any other path is returned unchanged. A drive-letter
/// path matches `home` case-insensitively.
pub fn display_path(cwd: &str, home: Option<&str>) -> String {
    let Some(home) = home.map(|h| h.trim_end_matches(['\\', '/'])) else {
        return cwd.to_string();
    };
    if home.is_empty() {
        return cwd.to_string();
    }
    let ignore_case = is_drive_path(cwd) && is_drive_path(home);
    let mut rest = cwd.char_indices();
    for want in home.chars() {
        match rest.next() {
            Some((_, got)) if same_char(got, want, ignore_case) => {}
            _ => return cwd.to_string(),
        }
    }
    let below = match rest.next() {
        None => "",
        Some((at, '\\' | '/')) => &cwd[at..],
        // `C:\Users\Administrator` is not below `C:\Users\Admin`.
        Some(_) => return cwd.to_string(),
    };
    format!("~{below}")
}

fn is_drive_path(path: &str) -> bool {
    let bytes = path.as_bytes();
    bytes.len() >= 2 && bytes[0].is_ascii_alphabetic() && bytes[1] == b':'
}

fn same_char(a: char, b: char, ignore_case: bool) -> bool {
    a == b || (ignore_case && a.to_lowercase().eq(b.to_lowercase()))
}

/// The path line of a sidebar card and whether to look up its branch. A pane
/// that shows a Mac gives the Mac's name (a local folder means nothing
/// there); a local pane gives its `cwd` with `~`, and asks for the branch.
/// A local pane that has not reported a directory gives neither.
pub fn row_lines(
    local_cwd: Option<&str>,
    remote_machine: Option<&str>,
    home: Option<&str>,
) -> (Option<String>, bool) {
    if let Some(machine) = remote_machine {
        return (Some(machine.to_string()), false);
    }
    match local_cwd {
        Some(cwd) => (Some(display_path(cwd, home)), true),
        None => (None, false),
    }
}

/// Where a new local workspace starts when it inherits the working directory: the folder the
/// focused pane's shell last reported (`osc7`). A pane that shows a Mac (`remote`) has a path
/// on another machine, and a folder that is gone (`is_dir` says so) is no start: both give
/// `None`, and the workspace starts where it always did.
pub fn inherited_start_dir(
    osc7: Option<&str>,
    remote: bool,
    is_dir: &dyn Fn(&Path) -> bool,
) -> Option<PathBuf> {
    if remote {
        return None;
    }
    let dir = PathBuf::from(cwd_from_osc7(osc7?)?);
    is_dir(&dir).then_some(dir)
}

/// The branch checked out in the repository that contains `cwd`: the name
/// for `ref: refs/heads/NAME`, the first 7 characters of a detached HEAD,
/// `None` outside a repository.
pub fn git_branch(cwd: &Path) -> Option<String> {
    let head = cwd.ancestors().find_map(head_file)?;
    let head = std::fs::read_to_string(head).ok()?;
    let head = head.trim();
    if let Some(reference) = head.strip_prefix("ref:") {
        return reference
            .trim()
            .strip_prefix("refs/heads/")
            .map(str::to_string);
    }
    let sha = head.len() == 40 || head.len() == 64;
    (sha && head.bytes().all(|b| b.is_ascii_hexdigit())).then(|| head[..7].to_string())
}

/// The `HEAD` file of the repository whose working tree root is `dir`: in
/// `dir/.git`, or in the directory a `.git` file (a linked worktree or a
/// submodule) points to.
fn head_file(dir: &Path) -> Option<PathBuf> {
    let dot_git = dir.join(".git");
    if dot_git.is_dir() {
        return Some(dot_git.join("HEAD"));
    }
    let text = std::fs::read_to_string(&dot_git).ok()?;
    let target = text.lines().find_map(|line| line.strip_prefix("gitdir:"))?;
    Some(dir.join(target.trim()).join("HEAD"))
}

/// What a card shows for a folder's branch, and whether the caller must start a background
/// read of it (`git_branch`, then `BranchCache::store`).
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct BranchLookup {
    pub branch: Option<String>,
    pub read: bool,
}

/// The last branch read per working directory (Ruling 23). `.git/HEAD` is never read on the
/// UI thread: `lookup` says when a read is due, the caller reads in the background and
/// `store`s the answer. One read per folder at a time; an answer is kept for `TTL`; a card
/// shows the last known branch while a new read runs; a read that hangs blocks only re-reads
/// of its own folder.
pub struct BranchCache {
    entries: HashMap<String, BranchEntry>,
}

struct BranchEntry {
    branch: Option<String>,
    /// When the last answer arrived; `None` before the first.
    read_at: Option<Instant>,
    /// A read is running.
    reading: bool,
}

/// How long a branch read is reused.
const TTL: Duration = Duration::from_secs(2);

impl BranchCache {
    pub fn new() -> BranchCache {
        BranchCache {
            entries: HashMap::new(),
        }
    }

    /// The branch to show for `cwd` now, and whether to start a read.
    pub fn lookup(&mut self, cwd: &str, now: Instant) -> BranchLookup {
        let entry = self.entries.entry(cwd.to_string()).or_insert(BranchEntry {
            branch: None,
            read_at: None,
            reading: false,
        });
        let fresh = entry
            .read_at
            .is_some_and(|at| now.saturating_duration_since(at) < TTL);
        let read = !entry.reading && !fresh;
        if read {
            entry.reading = true;
        }
        BranchLookup {
            branch: entry.branch.clone(),
            read,
        }
    }

    /// A background read of `cwd` answered.
    pub fn store(&mut self, cwd: &str, branch: Option<String>, now: Instant) {
        self.entries.insert(
            cwd.to_string(),
            BranchEntry {
                branch,
                read_at: Some(now),
                reading: false,
            },
        );
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;
    use std::time::Duration;

    const SHA: &str = "0123456789abcdef0123456789abcdef01234567";

    fn repo_with_head(head: &str) -> tempfile::TempDir {
        let tmp = tempfile::tempdir().unwrap();
        fs::create_dir(tmp.path().join(".git")).unwrap();
        fs::write(tmp.path().join(".git/HEAD"), head).unwrap();
        tmp
    }

    #[test]
    fn osc7_windows_path() {
        assert_eq!(
            cwd_from_osc7("file://PC/C:/Users/Admin").as_deref(),
            Some(r"C:\Users\Admin")
        );
    }

    #[test]
    fn osc7_unix_path() {
        assert_eq!(
            cwd_from_osc7("file://mac.local/Users/a/p").as_deref(),
            Some("/Users/a/p")
        );
        // An empty host is valid too.
        assert_eq!(cwd_from_osc7("file:///tmp").as_deref(), Some("/tmp"));
    }

    #[test]
    fn osc7_with_unicode_and_percent_escapes() {
        let want = Some(r"C:\Tài liệu");
        assert_eq!(
            cwd_from_osc7("file://PC/C:/T%C3%A0i%20li%E1%BB%87u").as_deref(),
            want
        );
        assert_eq!(cwd_from_osc7("file://PC/C:/Tài liệu").as_deref(), want);
    }

    #[test]
    fn osc7_unc_share_and_drive_root() {
        assert_eq!(
            cwd_from_osc7("file://PC///srv/share/dir").as_deref(),
            Some(r"\\srv\share\dir")
        );
        assert_eq!(cwd_from_osc7("file://PC/C:").as_deref(), Some(r"C:\"));
        assert_eq!(cwd_from_osc7("file://PC/C:/").as_deref(), Some(r"C:\"));
    }

    #[test]
    fn osc7_keeps_a_percent_that_is_not_an_escape() {
        assert_eq!(
            cwd_from_osc7("file://PC/C:/100%/a%2").as_deref(),
            Some(r"C:\100%\a%2")
        );
    }

    #[test]
    fn osc7_rejects_other_schemes() {
        assert_eq!(cwd_from_osc7("http://PC/C:/x"), None);
        assert_eq!(cwd_from_osc7("/C:/x"), None);
        assert_eq!(cwd_from_osc7(""), None);
        assert_eq!(cwd_from_osc7("file://PC"), None);
    }

    #[test]
    fn display_path_home_and_below_and_outside() {
        let home = Some(r"C:\Users\Admin");
        assert_eq!(display_path(r"C:\Users\Admin", home), "~");
        assert_eq!(display_path(r"c:\users\admin\code", home), r"~\code");
        assert_eq!(display_path(r"D:\x", home), r"D:\x");
        assert_eq!(
            display_path(r"C:\Users\Administrator", home),
            r"C:\Users\Administrator"
        );
        assert_eq!(display_path("/Users/a/p", Some("/Users/a")), "~/p");
        assert_eq!(display_path("/Users/a/p", None), "/Users/a/p");
    }

    #[test]
    fn row_lines_for_local_and_remote_panes() {
        let home = Some(r"C:\Users\Admin");
        // A pane that shows a Mac: the Mac's name, never a branch lookup.
        assert_eq!(
            row_lines(None, Some("MacBook"), home),
            (Some("MacBook".to_string()), false)
        );
        // Even a stale local cwd does not leak into a remote pane's row.
        assert_eq!(
            row_lines(Some(r"C:\x"), Some("MacBook"), home),
            (Some("MacBook".to_string()), false)
        );
        // A local pane: the path with `~`, and look the branch up.
        assert_eq!(
            row_lines(Some(r"C:\Users\Admin\code"), None, home),
            (Some(r"~\code".to_string()), true)
        );
        // No directory reported yet: no path line, no branch.
        assert_eq!(row_lines(None, None, home), (None, false));
    }

    #[test]
    fn git_branch_plain_repo() {
        let tmp = repo_with_head("ref: refs/heads/feat/windows\n");
        assert_eq!(git_branch(tmp.path()).as_deref(), Some("feat/windows"));
    }

    #[test]
    fn git_branch_from_a_subdirectory() {
        let tmp = repo_with_head("ref: refs/heads/main\n");
        let deep = tmp.path().join("a/b");
        fs::create_dir_all(&deep).unwrap();
        assert_eq!(git_branch(&deep).as_deref(), Some("main"));
    }

    #[test]
    fn git_branch_worktree_gitdir_file() {
        let tmp = tempfile::tempdir().unwrap();
        let admin = tmp.path().join("main/.git/worktrees/wt");
        fs::create_dir_all(&admin).unwrap();
        fs::write(admin.join("HEAD"), "ref: refs/heads/topic\n").unwrap();
        let wt = tmp.path().join("wt");
        fs::create_dir(&wt).unwrap();
        // Relative to the file's directory.
        fs::write(wt.join(".git"), "gitdir: ../main/.git/worktrees/wt\n").unwrap();
        assert_eq!(git_branch(&wt).as_deref(), Some("topic"));
        // And absolute.
        fs::write(wt.join(".git"), format!("gitdir: {}\n", admin.display())).unwrap();
        assert_eq!(git_branch(&wt).as_deref(), Some("topic"));
    }

    #[test]
    fn git_branch_detached_head_is_short_sha() {
        let tmp = repo_with_head(&format!("{SHA}\n"));
        assert_eq!(git_branch(tmp.path()).as_deref(), Some("0123456"));
    }

    #[test]
    fn git_branch_none_outside_a_repo() {
        let tmp = tempfile::tempdir().unwrap();
        assert_eq!(git_branch(tmp.path()), None);
    }

    fn found(branch: Option<&str>, read: bool) -> BranchLookup {
        BranchLookup {
            branch: branch.map(String::from),
            read,
        }
    }

    #[test]
    fn a_new_folder_is_read_once_in_the_background() {
        let mut cache = BranchCache::new();
        let t0 = Instant::now();
        assert_eq!(cache.lookup(r"C:\work", t0), found(None, true));
        // the read is running: nobody starts another
        assert_eq!(cache.lookup(r"C:\work", t0), found(None, false));
        cache.store(r"C:\work", Some("main".into()), t0);
        assert_eq!(cache.lookup(r"C:\work", t0), found(Some("main"), false));
        // another folder has its own read
        assert_eq!(cache.lookup(r"C:\other", t0), found(None, true));
    }

    #[test]
    fn a_stale_branch_shows_while_it_is_read_again() {
        let mut cache = BranchCache::new();
        let t0 = Instant::now();
        cache.lookup(r"C:\work", t0);
        cache.store(r"C:\work", Some("main".into()), t0);
        let fresh = t0 + Duration::from_millis(1999);
        assert_eq!(cache.lookup(r"C:\work", fresh), found(Some("main"), false));
        // after 2 s: read again, and show the last known branch meanwhile
        let stale = t0 + Duration::from_secs(2);
        assert_eq!(cache.lookup(r"C:\work", stale), found(Some("main"), true));
        assert_eq!(cache.lookup(r"C:\work", stale), found(Some("main"), false));
        cache.store(r"C:\work", Some("dev".into()), stale);
        assert_eq!(cache.lookup(r"C:\work", stale), found(Some("dev"), false));
    }

    #[test]
    fn a_hung_read_is_never_started_twice() {
        let mut cache = BranchCache::new();
        let t0 = Instant::now();
        let reads = (0..=100)
            .map(|step| cache.lookup(r"\\server\share", t0 + Duration::from_millis(step * 100)))
            .filter(|lookup| lookup.read)
            .count();
        assert_eq!(reads, 1);
    }

    #[test]
    fn percent_encoded_osc7_round_trips() {
        for path in [
            r"C:\Users\Phú\Tài liệu",
            r"C:\",
            r"\\srv\share\Dự án",
            r"C:\a%b",
            r"D:\100% done",
        ] {
            assert_eq!(
                cwd_from_osc7(&shellx_model::shell::osc7_url("PC", path)),
                Some(path.to_string()),
                "{path}"
            );
        }
    }

    #[test]
    fn a_new_workspace_inherits_the_focused_local_directory_that_exists() {
        let exists = |path: &Path| path == Path::new("C:\\Users\\me\\code");
        let url = Some("file://PC/C:/Users/me/code");
        assert_eq!(
            inherited_start_dir(url, false, &exists),
            Some(PathBuf::from("C:\\Users\\me\\code"))
        );
        // A Mac pane's path is on another machine.
        assert_eq!(inherited_start_dir(url, true, &exists), None);
        // The folder is gone, or the shell has reported nothing, or not a path.
        assert_eq!(
            inherited_start_dir(Some("file://PC/C:/gone"), false, &exists),
            None
        );
        assert_eq!(inherited_start_dir(None, false, &exists), None);
        assert_eq!(inherited_start_dir(Some("nonsense"), false, &exists), None);
    }
}
