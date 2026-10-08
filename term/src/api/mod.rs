//! `shellx` — the ShellX command line (A7 spec:
//! docs/superpowers/specs/2026-10-07-desktop-cli-a7-design.md). Talks to the
//! ShellX window (or the A5b daemon) over the local mux socket. Separate
//! from `proto`, which is the terminal-sharing link and must not change.

pub mod args;
pub mod browser_js;
pub mod client;
pub mod config_path;
pub mod doctor;
pub mod endpoint;
pub mod output;
pub mod run;
pub mod skills;
pub mod value;
pub mod wire;

/// Entry point of the `shellx` command. Returns the exit code (D10).
pub fn main(args: Vec<std::ffi::OsString>) -> i32 {
    use std::io::Write;
    let args: Vec<String> = match args.into_iter().map(|a| a.into_string()).collect() {
        Ok(a) => a,
        Err(_) => {
            let _ = writeln!(
                std::io::stderr(),
                "shellx: arguments must be valid UTF-8 (usage)"
            );
            return 2;
        }
    };
    match args::parse(&args) {
        Err(msg) => {
            let _ = writeln!(std::io::stderr(), "shellx: {msg} (usage)");
            2
        }
        Ok(args::Invocation::Help(spec)) => {
            let _ = write!(std::io::stdout(), "{}", args::help_text(spec));
            0
        }
        Ok(args::Invocation::HelpGroup(g)) => {
            let _ = write!(
                std::io::stdout(),
                "{}",
                args::group_help(g).unwrap_or_default()
            );
            0
        }
        Ok(args::Invocation::Version) => {
            let _ = writeln!(
                std::io::stdout(),
                "shellx {} (api 1)",
                env!("CARGO_PKG_VERSION")
            );
            0
        }
        Ok(args::Invocation::Completions(sh)) => match args::completion_script(&sh) {
            Some(s) => {
                let _ = write!(std::io::stdout(), "{s}");
                0
            }
            None => {
                let _ = writeln!(
                    std::io::stderr(),
                    "shellx: completions for zsh, bash or pwsh"
                );
                2
            }
        },
        Ok(args::Invocation::Run(p)) => run_real(&p),
    }
}

fn env(k: &str) -> Option<String> {
    std::env::var(k).ok().filter(|v| !v.is_empty())
}

/// D30: the address is `--socket` › `$SHELLX_SOCKET` › the endpoint file's;
/// the secret always comes from the endpoint file, read with
/// [`endpoint::read`] (owner and mode checked). A file left behind by a
/// crash or power-off names a socket nobody listens on: the connect fails
/// at once → exit 3. `SHELLX_CLI_TOKEN` (A7 amendment) goes in `auth` only;
/// it is never printed.
pub fn connect_from_env(
    get: &dyn Fn(&str) -> Option<String>,
    socket: Option<&str>,
) -> Result<Box<dyn client::Session>, client::ApiError> {
    use client::ApiError;
    let not_running =
        || ApiError::NotRunning("ShellX is not running (open ShellX and try again)".into());
    let path = endpoint::default_path(get).ok_or_else(not_running)?;
    let ep = endpoint::read(&path).map_err(|e| match e {
        endpoint::ReadError::Missing => not_running(),
        // Never the secret: the error only names the file and why.
        other => ApiError::NotRunning(format!("ShellX is not running: {other}")),
    })?;
    let address = socket
        .map(String::from)
        .or_else(|| get("SHELLX_SOCKET"))
        .unwrap_or_else(|| ep.address.clone());
    let token = get("SHELLX_CLI_TOKEN");
    let conn = client::connect(
        &ep,
        &address,
        std::time::Duration::from_secs(2),
        token.as_deref(),
    )?;
    Ok(Box::new(conn))
}

fn run_real(parsed: &args::Parsed) -> i32 {
    use std::io::{IsTerminal, Write};
    let get = |k: &str| env(k);
    let connect = |socket: Option<&str>| connect_from_env(&get, socket);
    #[cfg(unix)]
    let mut tty_file = std::fs::OpenOptions::new()
        .write(true)
        .open("/dev/tty")
        .ok();
    #[cfg(windows)]
    let mut tty_file = std::fs::OpenOptions::new().write(true).open("CONOUT$").ok();
    let stdout = std::io::stdout();
    let stderr = std::io::stderr();
    let (mut out, mut err) = (stdout.lock(), stderr.lock());
    let stdin = std::io::stdin();
    let stdin_is_tty = stdin.is_terminal();
    let mut input = stdin.lock();
    let mut ctx = run::Ctx {
        env: &get,
        out: &mut out,
        err: &mut err,
        stdin: &mut input,
        stdin_is_tty,
        cwd: std::env::current_dir().unwrap_or_default(),
        home: get(if cfg!(windows) { "USERPROFILE" } else { "HOME" }).map(Into::into),
        tty: tty_file.as_mut().map(|f| f as &mut dyn Write),
        shared_terminal: shared_terminal(&get),
        connect: &connect,
        stdout_gone: STDOUT_GONE,
        exe: std::env::current_exe().ok(),
    };
    let code = run::run(parsed, &mut ctx);
    let _ = ctx.out.flush();
    code
}

/// Review I1: `events --follow | head -1` must end once `head` has gone,
/// even when no event ever comes to fail a write.
#[cfg(unix)]
const STDOUT_GONE: Option<fn(std::time::Duration) -> bool> = Some(stdout_gone);
/// Windows: not watched (recorded residual); a failed write still ends it.
#[cfg(windows)]
const STDOUT_GONE: Option<fn(std::time::Duration) -> bool> = None;

/// Waits about `wait` for stdout to report an error or hang-up: a pipe
/// whose reader closed reports POLLHUP (macOS, checked) or POLLERR
/// (Linux), a closed terminal POLLHUP. macOS reports these only when
/// POLLOUT is asked for, so it is, and a stdout that is simply writable
/// (the usual case, and /dev/null's POLLNVAL) waits out the rest of
/// `wait` instead of spinning.
#[cfg(unix)]
fn stdout_gone(wait: std::time::Duration) -> bool {
    let started = std::time::Instant::now();
    let mut fd = libc::pollfd {
        fd: libc::STDOUT_FILENO,
        events: libc::POLLOUT,
        revents: 0,
    };
    let ms = wait.as_millis().min(i32::MAX as u128) as libc::c_int;
    // SAFETY: one valid pollfd, count 1.
    let n = unsafe { libc::poll(&mut fd, 1, ms) };
    // Not POLLNVAL: macOS answers it for /dev/null (checked), which is
    // not a reader that left; a truly closed fd 1 fails its next write.
    if n > 0 && fd.revents & (libc::POLLERR | libc::POLLHUP) != 0 {
        return true;
    }
    std::thread::sleep(wait.saturating_sub(started.elapsed()));
    false
}

/// D23 (2): `$SHELLX_TERM` names this terminal — the window is shared with
/// the phone by `shellx-term wrap` (Unix: its tty path; Windows:
/// `conpty:<pid>`). Unix (review M3): compared with the terminal the OSC
/// goes to — the controlling terminal, which `/dev/tty` opens — not with
/// whatever stdin is (`echo x | shellx notify` has a pipe there).
/// `ttyname` of the opened `/dev/tty` cannot be used: it answers
/// "/dev/tty" (macOS checked), so the device numbers are compared.
#[allow(clippy::let_and_return)] // one binding per platform
fn shared_terminal(get: &dyn Fn(&str) -> Option<String>) -> bool {
    let Some(term) = get("SHELLX_TERM") else {
        return false;
    };
    #[cfg(unix)]
    let shared = same_terminal(std::path::Path::new(&term), controlling_tty());
    #[cfg(windows)]
    let shared = term.starts_with("conpty:");
    shared
}

/// `path` is the character device `ctty` (a device number).
#[cfg(unix)]
fn same_terminal(path: &std::path::Path, ctty: Option<u64>) -> bool {
    use std::os::unix::fs::{FileTypeExt, MetadataExt};
    match (std::fs::metadata(path), ctty) {
        (Ok(m), Some(dev)) => m.file_type().is_char_device() && m.rdev() == dev,
        _ => false,
    }
}

/// The controlling terminal's device number, or `None` without one.
#[cfg(target_os = "macos")]
fn controlling_tty() -> Option<u64> {
    // SAFETY: proc_pidinfo writes at most `size` bytes into `info`, a
    // plain C struct for which all-zero bytes are valid.
    let mut info: libc::proc_bsdinfo = unsafe { std::mem::zeroed() };
    let size = std::mem::size_of::<libc::proc_bsdinfo>() as libc::c_int;
    let got = unsafe {
        libc::proc_pidinfo(
            libc::getpid(),
            libc::PROC_PIDTBSDINFO,
            0,
            (&mut info as *mut libc::proc_bsdinfo).cast(),
            size,
        )
    };
    // NODEV is all ones.
    (got == size && info.e_tdev != u32::MAX).then_some(u64::from(info.e_tdev))
}

/// The controlling terminal's device number (`tty_nr` of /proc/self/stat).
#[cfg(all(unix, not(target_os = "macos")))]
fn controlling_tty() -> Option<u64> {
    let stat = std::fs::read_to_string("/proc/self/stat").ok()?;
    // After "pid (comm) ": state ppid pgrp session tty_nr …
    let rest = &stat[stat.rfind(')')? + 1..];
    let nr: u64 = rest.split_whitespace().nth(4)?.parse().ok()?;
    if nr == 0 {
        return None;
    }
    let major = ((nr >> 8) & 0xfff) as libc::c_uint;
    let minor = ((nr & 0xff) | ((nr >> 12) & 0xfff00)) as libc::c_uint;
    #[allow(clippy::useless_conversion)] // dev_t is u64 or u32 by platform
    Some(u64::from(libc::makedev(major, minor)))
}

#[cfg(all(test, unix))]
mod tests {
    use super::*;
    use std::os::unix::fs::MetadataExt;

    #[test]
    fn shared_means_the_controlling_terminal_device() {
        let null = std::path::Path::new("/dev/null");
        let dev = std::fs::metadata(null).unwrap().rdev();
        assert!(same_terminal(null, Some(dev)));
        assert!(!same_terminal(null, Some(dev + 1)));
        assert!(!same_terminal(null, None));
        assert!(!same_terminal(
            std::path::Path::new("/nonexistent/tty"),
            Some(dev)
        ));
        // A regular file is never a terminal, whatever its numbers.
        let file = std::env::temp_dir();
        assert!(!same_terminal(
            &file,
            Some(std::fs::metadata(&file).unwrap().rdev())
        ));
    }

    #[test]
    fn the_controlling_terminal_is_the_one_stdin_names_when_it_is_one() {
        // Meaningful under a terminal (`script -q /dev/null cargo test …`);
        // without one there is nothing to compare.
        use std::io::IsTerminal;
        if std::io::stdin().is_terminal() {
            let dev = std::fs::metadata("/dev/stdin").unwrap().rdev();
            assert_eq!(controlling_tty(), Some(dev));
        }
    }
}
