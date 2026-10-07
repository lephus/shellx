#![cfg(unix)]
use shellx_term::api::client::daemon_proof;
use shellx_term::api::value::Value;
use shellx_term::api::wire::{recv, send, Message};
use std::os::unix::net::{UnixListener, UnixStream};
use std::path::{Path, PathBuf};
use std::process::Command;
use std::time::{Duration, Instant};

fn bin() -> std::path::PathBuf {
    std::path::PathBuf::from(env!("CARGO_BIN_EXE_shellx-term"))
}

/// One `shellx` symlink per test process (tests run in parallel).
fn shellx_link() -> std::path::PathBuf {
    static LINK: std::sync::OnceLock<PathBuf> = std::sync::OnceLock::new();
    LINK.get_or_init(|| {
        let dir = std::env::temp_dir().join(format!("shellx-dispatch-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let link = dir.join("shellx");
        let _ = std::fs::remove_file(&link);
        std::os::unix::fs::symlink(bin(), &link).unwrap();
        link
    })
    .clone()
}

#[test]
fn shellx_name_is_the_cli_and_never_starts_a_shell() {
    let out = Command::new(shellx_link()).arg("bogus").output().unwrap();
    assert_eq!(out.status.code(), Some(2));
    assert!(String::from_utf8_lossy(&out.stderr).contains("unknown command"));
    let v = Command::new(shellx_link())
        .arg("--version")
        .output()
        .unwrap();
    assert!(String::from_utf8_lossy(&v.stdout).starts_with("shellx "));
}

#[test]
fn shellx_term_cli_subcommand_and_old_paths_unchanged() {
    let out = Command::new(bin()).args(["cli", "help"]).output().unwrap();
    assert_eq!(out.status.code(), Some(0));
    assert!(String::from_utf8_lossy(&out.stdout).contains("Usage: shellx"));
    let v = Command::new(bin()).arg("--version").output().unwrap();
    assert!(String::from_utf8_lossy(&v.stdout).starts_with("shellx-term "));
}

#[test]
fn not_running_is_exit_3() {
    let out = Command::new(shellx_link())
        .arg("ls")
        .env("SHELLX_ENDPOINT", "/nonexistent/endpoint")
        .output()
        .unwrap();
    assert_eq!(out.status.code(), Some(3));
    assert!(String::from_utf8_lossy(&out.stderr).contains("ShellX is not running"));
}

const SECRET_HEX: &str = "0707070707070707070707070707070707070707070707070707070707070707";
const TOKEN: &str = "c0ffee00c0ffee00c0ffee00c0ffee00c0ffee00c0ffee00c0ffee00c0ffee00";

fn temp_dir(name: &str) -> PathBuf {
    // Short: a Unix socket path is limited to ~104 bytes.
    let d = PathBuf::from(format!("/tmp/sxd-{}-{name}", std::process::id()));
    let _ = std::fs::remove_dir_all(&d);
    std::fs::create_dir_all(&d).unwrap();
    d
}

/// A 0600 endpoint file naming `address`.
fn endpoint_file(dir: &Path, address: &Path) -> PathBuf {
    use std::io::Write;
    use std::os::unix::fs::OpenOptionsExt;
    let path = dir.join("endpoint");
    let mut f = std::fs::OpenOptions::new()
        .write(true)
        .create_new(true)
        .mode(0o600)
        .open(&path)
        .unwrap();
    write!(
        f,
        "v=1\naddress={}\nsecret={SECRET_HEX}\npid=1\ninstance=x\nprotocol=1\napp=1.0.0\n",
        address.display()
    )
    .unwrap();
    path
}

/// The CLI must connect within 5 s (a CLI that never comes fails the test
/// instead of hanging it).
fn accept_within(l: &UnixListener) -> UnixStream {
    l.set_nonblocking(true).unwrap();
    let until = Instant::now() + Duration::from_secs(5);
    loop {
        match l.accept() {
            Ok((s, _)) => {
                s.set_nonblocking(false).unwrap();
                return s;
            }
            Err(_) if Instant::now() < until => std::thread::sleep(Duration::from_millis(10)),
            Err(e) => panic!("the CLI never connected: {e}"),
        }
    }
}

/// The Dart host's side of the handshake; returns the `auth` token.
fn accept(s: &mut UnixStream) -> Option<String> {
    let hello = recv(s).unwrap();
    let nc: [u8; 32] = hello
        .get("nonce")
        .and_then(Value::as_bytes)
        .unwrap()
        .try_into()
        .unwrap();
    let nd = [9u8; 32];
    send(
        s,
        &Message::new(
            "hello",
            vec![
                ("protocol", Value::Int(1)),
                ("app", Value::text("1.0.0")),
                ("nonce", Value::Bytes(nd.to_vec())),
                (
                    "proof",
                    Value::Bytes(daemon_proof(&[7; 32], &nc, &nd).to_vec()),
                ),
            ],
        ),
    )
    .unwrap();
    let auth = recv(s).unwrap();
    assert_eq!(auth.t, "auth");
    send(s, &Message::new("ready", vec![])).unwrap();
    auth.get("token").and_then(Value::as_str).map(String::from)
}

fn answer(s: &mut UnixStream, fields: Vec<(&str, Value)>) -> Message {
    let r = recv(s).unwrap();
    let mut m = Message::new("result", fields);
    m.q = r.q;
    send(s, &m).unwrap();
    r
}

fn version(s: &mut UnixStream) {
    let caps = Value::Array(vec![Value::text("ui.ls"), Value::text("cli.notify")]);
    let r = answer(s, vec![("api", Value::Int(1)), ("caps", caps)]);
    assert_eq!(r.t, "api.version");
}

fn shellx(endpoint: &Path, token: Option<&str>, args: &[&str]) -> std::process::Output {
    let mut c = Command::new(shellx_link());
    c.args(args)
        .env("SHELLX_ENDPOINT", endpoint)
        .env_remove("SHELLX_SOCKET")
        .env_remove("SHELLX_CLI_TOKEN")
        .env_remove("SHELLX_PANE_ID")
        .env_remove("SHELLX_TERM");
    if let Some(t) = token {
        c.env("SHELLX_CLI_TOKEN", t);
    }
    c.output().unwrap()
}

#[test]
fn a_shellx_shell_sends_its_token_and_reads_the_endpoint_file() {
    let dir = temp_dir("token");
    let sock = dir.join("s");
    let listener = UnixListener::bind(&sock).unwrap();
    let ep = endpoint_file(&dir, &sock);
    let host = std::thread::spawn(move || {
        let mut s = accept_within(&listener);
        let token = accept(&mut s);
        version(&mut s);
        let pane = Value::map(vec![
            ("id", Value::Int(5)),
            ("kind", Value::text("terminal")),
            ("title", Value::text("zsh")),
            ("cwd", Value::Null),
            ("branch", Value::Null),
            ("ports", Value::Array(vec![])),
            ("exitCode", Value::Null),
        ]);
        let tab = Value::map(vec![
            ("id", Value::Int(5)),
            ("panes", Value::Array(vec![pane])),
        ]);
        let ws = Value::map(vec![
            ("id", Value::text("default")),
            ("tabs", Value::Array(vec![tab])),
        ]);
        let r = answer(
            &mut s,
            vec![
                ("workspaces", Value::Array(vec![ws])),
                ("selectedTab", Value::Int(5)),
                ("focusedPane", Value::Null),
            ],
        );
        assert_eq!(r.t, "ui.ls");
        token
    });
    let out = shellx(&ep, Some(TOKEN), &["ls", "--json"]);
    assert_eq!(host.join().unwrap().as_deref(), Some(TOKEN));
    let stdout = String::from_utf8_lossy(&out.stdout);
    assert_eq!(
        out.status.code(),
        Some(0),
        "{stdout} {}",
        String::from_utf8_lossy(&out.stderr)
    );
    assert!(
        stdout.contains("\"id\":\"p5\",\"kind\":\"terminal\""),
        "{stdout}"
    );
    assert!(stdout.contains("\"focusedPane\":null"), "{stdout}");
    // The token is never printed.
    assert!(!stdout.contains(TOKEN) && !String::from_utf8_lossy(&out.stderr).contains(TOKEN));
}

#[test]
fn outside_shellx_forbidden_prints_the_hosts_hint_exit_6() {
    let dir = temp_dir("forbid");
    let sock = dir.join("s");
    let listener = UnixListener::bind(&sock).unwrap();
    let ep = endpoint_file(&dir, &sock);
    let hint = "This terminal is not a ShellX shell. Allow it in the ShellX tray: Command line → Allow other terminals";
    let host = std::thread::spawn(move || {
        let mut s = accept_within(&listener);
        let token = accept(&mut s);
        version(&mut s);
        let r = recv(&mut s).unwrap();
        let mut e = Message::new(
            "error",
            vec![
                ("code", Value::text("forbidden")),
                ("message", Value::text(hint)),
            ],
        );
        e.q = r.q;
        send(&mut s, &e).unwrap();
        token
    });
    let out = shellx(&ep, None, &["ls"]);
    assert_eq!(host.join().unwrap(), None);
    assert_eq!(out.status.code(), Some(6));
    assert_eq!(
        String::from_utf8_lossy(&out.stderr),
        format!("shellx: {hint} (forbidden)\n")
    );
}

#[test]
fn a_stale_endpoint_is_not_running_fast() {
    // Power-off or a crash leaves the endpoint behind: its socket is gone,
    // or is a file nobody listens on.
    let dir = temp_dir("stale");
    let gone = endpoint_file(&dir, &dir.join("missing.sock"));
    let dir2 = temp_dir("stale2");
    let sock = dir2.join("s");
    drop(UnixListener::bind(&sock).unwrap());
    assert!(sock.exists());
    let refused = endpoint_file(&dir2, &sock);
    for ep in [gone, refused] {
        let started = Instant::now();
        let out = shellx(&ep, Some(TOKEN), &["ls"]);
        assert!(
            started.elapsed() < Duration::from_secs(1),
            "{:?}",
            started.elapsed()
        );
        assert_eq!(out.status.code(), Some(3));
        assert!(String::from_utf8_lossy(&out.stderr).contains("ShellX is not running"));
    }
}

#[test]
fn an_endpoint_file_others_can_read_is_refused() {
    use std::os::unix::fs::PermissionsExt;
    let dir = temp_dir("mode");
    let ep = endpoint_file(&dir, &dir.join("s"));
    std::fs::set_permissions(&ep, std::fs::Permissions::from_mode(0o644)).unwrap();
    let out = shellx(&ep, None, &["ls"]);
    assert_eq!(out.status.code(), Some(3));
    let err = String::from_utf8_lossy(&out.stderr);
    assert!(err.contains("refusing the ShellX endpoint file"), "{err}");
    assert!(!err.contains(SECRET_HEX));
}

#[test]
fn events_follow_ends_when_its_reader_goes_away() {
    // `shellx events --follow | head -1`: once the reader closed the pipe,
    // the next event ends the CLI and closes the connection.
    use std::io::{BufRead, Read};
    let dir = temp_dir("pipe");
    let sock = dir.join("s");
    let listener = UnixListener::bind(&sock).unwrap();
    let ep = endpoint_file(&dir, &sock);
    let (go_on, wait_reader) = std::sync::mpsc::channel::<()>();
    let host = std::thread::spawn(move || {
        let mut s = accept_within(&listener);
        accept(&mut s);
        let caps = Value::Array(vec![Value::text("cli.events.subscribe")]);
        answer(&mut s, vec![("api", Value::Int(1)), ("caps", caps)]);
        let r = answer(&mut s, vec![]);
        assert_eq!(r.t, "cli.events.subscribe");
        let event = Message::new("event", vec![("kind", Value::text("pane.exited"))]);
        send(&mut s, &event).unwrap();
        wait_reader.recv().unwrap();
        // The reader is gone: one more event, then the CLI must hang up.
        let _ = send(&mut s, &event);
        s.set_read_timeout(Some(Duration::from_secs(3))).unwrap();
        let mut rest = Vec::new();
        s.read_to_end(&mut rest).is_ok()
    });
    let mut child = Command::new(shellx_link())
        .args(["events", "--follow"])
        .env("SHELLX_ENDPOINT", &ep)
        .env("SHELLX_CLI_TOKEN", TOKEN)
        .env_remove("SHELLX_SOCKET")
        .stdout(std::process::Stdio::piped())
        .stderr(std::process::Stdio::null())
        .spawn()
        .unwrap();
    let mut out = std::io::BufReader::new(child.stdout.take().unwrap());
    let mut first = String::new();
    out.read_line(&mut first).unwrap();
    assert_eq!(first, "{\"kind\":\"pane.exited\"}\n");
    drop(out);
    go_on.send(()).unwrap();
    let started = Instant::now();
    let status = loop {
        if let Some(s) = child.try_wait().unwrap() {
            break s;
        }
        if started.elapsed() > Duration::from_secs(3) {
            let _ = child.kill();
            panic!("shellx events kept running after its reader left");
        }
        std::thread::sleep(Duration::from_millis(20));
    };
    assert_eq!(status.code(), Some(0));
    assert!(host.join().unwrap(), "the connection was not closed");
}

#[test]
fn events_follow_ends_soon_after_its_reader_goes_away_even_without_events() {
    // `shellx events --follow --kinds pane.exited | head -1` where no other
    // event ever comes: the CLI notices the closed pipe by itself.
    use std::io::{BufRead, Read};
    let dir = temp_dir("quiet");
    let sock = dir.join("s");
    let listener = UnixListener::bind(&sock).unwrap();
    let ep = endpoint_file(&dir, &sock);
    let host = std::thread::spawn(move || {
        let mut s = accept_within(&listener);
        accept(&mut s);
        let caps = Value::Array(vec![Value::text("cli.events.subscribe")]);
        answer(&mut s, vec![("api", Value::Int(1)), ("caps", caps)]);
        answer(&mut s, vec![]);
        let event = Message::new("event", vec![("kind", Value::text("pane.exited"))]);
        send(&mut s, &event).unwrap();
        // Nothing more is sent; the CLI must hang up on its own.
        s.set_read_timeout(Some(Duration::from_secs(5))).unwrap();
        let mut rest = Vec::new();
        s.read_to_end(&mut rest).is_ok()
    });
    let mut child = Command::new(shellx_link())
        .args(["events", "--follow", "--kinds", "pane.exited"])
        .env("SHELLX_ENDPOINT", &ep)
        .env("SHELLX_CLI_TOKEN", TOKEN)
        .env_remove("SHELLX_SOCKET")
        .stdout(std::process::Stdio::piped())
        .stderr(std::process::Stdio::null())
        .spawn()
        .unwrap();
    let mut out = std::io::BufReader::new(child.stdout.take().unwrap());
    let mut first = String::new();
    out.read_line(&mut first).unwrap();
    assert_eq!(first, "{\"kind\":\"pane.exited\"}\n");
    drop(out);
    let started = Instant::now();
    let status = loop {
        if let Some(s) = child.try_wait().unwrap() {
            break s;
        }
        if started.elapsed() > Duration::from_millis(2500) {
            let _ = child.kill();
            panic!("shellx events kept running after its reader left");
        }
        std::thread::sleep(Duration::from_millis(20));
    };
    assert_eq!(status.code(), Some(0));
    assert!(host.join().unwrap(), "the connection was not closed");
}

#[test]
fn events_into_a_file_keep_going() {
    // A stdout that is a regular file never looks "gone".
    let dir = temp_dir("file");
    let sock = dir.join("s");
    let listener = UnixListener::bind(&sock).unwrap();
    let ep = endpoint_file(&dir, &sock);
    let host = std::thread::spawn(move || {
        let mut s = accept_within(&listener);
        accept(&mut s);
        let caps = Value::Array(vec![Value::text("cli.events.subscribe")]);
        answer(&mut s, vec![("api", Value::Int(1)), ("caps", caps)]);
        answer(&mut s, vec![]);
        let event = Message::new("event", vec![("kind", Value::text("tab.opened"))]);
        send(&mut s, &event).unwrap();
        std::thread::sleep(Duration::from_millis(2500));
        send(&mut s, &event).unwrap();
        // Then ShellX closes the stream.
    });
    let out_path = dir.join("events.jsonl");
    let out = std::fs::File::create(&out_path).unwrap();
    let status = Command::new(shellx_link())
        .args(["events", "--follow"])
        .env("SHELLX_ENDPOINT", &ep)
        .env("SHELLX_CLI_TOKEN", TOKEN)
        .env_remove("SHELLX_SOCKET")
        .stdout(out)
        .stderr(std::process::Stdio::null())
        .status()
        .unwrap();
    host.join().unwrap();
    assert_eq!(status.code(), Some(3));
    assert_eq!(
        std::fs::read_to_string(&out_path).unwrap().lines().count(),
        2
    );
}

#[test]
fn events_into_dev_null_keep_going() {
    // macOS answers poll(POLLOUT) on /dev/null with POLLNVAL: that is not
    // a reader that left.
    let dir = temp_dir("null");
    let sock = dir.join("s");
    let listener = UnixListener::bind(&sock).unwrap();
    let ep = endpoint_file(&dir, &sock);
    let host = std::thread::spawn(move || {
        let mut s = accept_within(&listener);
        accept(&mut s);
        let caps = Value::Array(vec![Value::text("cli.events.subscribe")]);
        answer(&mut s, vec![("api", Value::Int(1)), ("caps", caps)]);
        answer(&mut s, vec![]);
        let event = Message::new("event", vec![("kind", Value::text("tab.opened"))]);
        send(&mut s, &event).unwrap();
        std::thread::sleep(Duration::from_millis(2500));
        let _ = send(&mut s, &event);
    });
    let started = Instant::now();
    let status = Command::new(shellx_link())
        .args(["events", "--follow"])
        .env("SHELLX_ENDPOINT", &ep)
        .env("SHELLX_CLI_TOKEN", TOKEN)
        .env_remove("SHELLX_SOCKET")
        .stdout(std::fs::File::create("/dev/null").unwrap())
        .stderr(std::process::Stdio::null())
        .status()
        .unwrap();
    host.join().unwrap();
    assert!(
        started.elapsed() >= Duration::from_millis(2500),
        "{:?}",
        started.elapsed()
    );
    assert_eq!(status.code(), Some(3));
}
