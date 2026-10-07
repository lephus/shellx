//! `shellx` — the ShellX command line (A7 spec:
//! docs/superpowers/specs/2026-10-07-desktop-cli-a7-design.md). Talks to the
//! ShellX window (or the A5b daemon) over the local mux socket. Separate
//! from `proto`, which is the terminal-sharing link and must not change.

pub mod args;
pub mod browser_js;
pub mod client;
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
    };
    let code = run::run(parsed, &mut ctx);
    let _ = ctx.out.flush();
    code
}

/// D23 (2): `$SHELLX_TERM` names this terminal — the window is shared with
/// the phone by `shellx-term wrap` (Unix: its tty path; Windows:
/// `conpty:<pid>`).
#[allow(clippy::let_and_return)] // one binding per platform
fn shared_terminal(get: &dyn Fn(&str) -> Option<String>) -> bool {
    let Some(term) = get("SHELLX_TERM") else {
        return false;
    };
    #[cfg(unix)]
    let shared = {
        // SAFETY: ttyname returns null or a pointer to a static buffer that
        // stays valid until the next ttyname call (none in between).
        let name = unsafe { libc::ttyname(0) };
        !name.is_null() && unsafe { std::ffi::CStr::from_ptr(name) }.to_string_lossy() == term
    };
    #[cfg(windows)]
    let shared = term.starts_with("conpty:");
    shared
}
