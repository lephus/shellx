//! Real `cmux-relay` + `cmux-tui` daemon for the shellx-remote e2e.
//!
//! Binaries come from `SHELLX_E2E_BIN_DIR` (default
//! `cmux-tui/target/release`; build them with
//! `cargo build -p cmux-relay -p cmux-tui --release` in `cmux-tui/`). They
//! are copied into a short per-run dir under `/tmp` and every process runs
//! there with an isolated environment (HOME, TMPDIR, no inherited cmux
//! variables): no state of the user's own cmux/ShellX is touched, nothing
//! reads `~/Documents` (macOS TCC), and Unix socket paths stay short. The
//! HMAC secret, tickets and invitation are deleted on drop.

#![allow(dead_code)]

use std::fs;
use std::io::Write;
use std::os::unix::fs::{OpenOptionsExt, PermissionsExt};
use std::path::{Path, PathBuf};
use std::process::{Child, Command, Output, Stdio};
use std::sync::Arc;
use std::sync::atomic::{AtomicUsize, Ordering};
use std::time::{Duration, Instant};

use serde_json::Value;

/// A UTF-8 locale that exists on a stock runner (Ubuntu ships C.UTF-8).
#[cfg(target_os = "macos")]
const UTF8_LOCALE: &str = "en_US.UTF-8";
#[cfg(not(target_os = "macos"))]
const UTF8_LOCALE: &str = "C.UTF-8";

pub struct Harness {
    pub root: PathBuf,
    relay_bin: PathBuf,
    tui_bin: PathBuf,
    secret: String,
    pub slot: String,
    pub session: String,
    port: u16,
    relay: Option<Child>,
    daemon: Option<Child>,
    tickets: Arc<AtomicUsize>,
}

fn random_hex(bytes: usize) -> String {
    let mut buffer = vec![0_u8; bytes];
    getrandom::fill(&mut buffer).expect("random bytes");
    buffer.iter().map(|byte| format!("{byte:02x}")).collect()
}

fn write_private(path: &Path, text: &str) {
    let mut file = fs::OpenOptions::new()
        .write(true)
        .create(true)
        .truncate(true)
        .mode(0o600)
        .open(path)
        .unwrap_or_else(|error| panic!("write {}: {error}", path.display()));
    file.write_all(text.as_bytes()).unwrap();
}

fn bin_dir() -> PathBuf {
    if let Some(dir) = std::env::var_os("SHELLX_E2E_BIN_DIR") {
        return PathBuf::from(dir);
    }
    Path::new(env!("CARGO_MANIFEST_DIR")).join("../../cmux-tui/target/release")
}

fn free_port() -> u16 {
    std::net::TcpListener::bind("127.0.0.1:0")
        .unwrap()
        .local_addr()
        .unwrap()
        .port()
}

fn wait_until<T>(timeout: Duration, mut probe: impl FnMut() -> Option<T>) -> Option<T> {
    let deadline = Instant::now() + timeout;
    loop {
        if let Some(value) = probe() {
            return Some(value);
        }
        if Instant::now() > deadline {
            return None;
        }
        std::thread::sleep(Duration::from_millis(200));
    }
}

impl Harness {
    /// Start a relay and a headless `--ephemeral` daemon registered on it.
    pub fn start(name: &str) -> Harness {
        let source = bin_dir();
        let root = PathBuf::from(format!("/tmp/shx{name}{}", &random_hex(3)));
        fs::create_dir_all(&root).unwrap();
        fs::set_permissions(&root, fs::Permissions::from_mode(0o700)).unwrap();
        for dir in ["home", "tmp", "dstate", "cstate", "tickets", "bin"] {
            fs::create_dir_all(root.join(dir)).unwrap();
            fs::set_permissions(root.join(dir), fs::Permissions::from_mode(0o700)).unwrap();
        }
        let copy = |bin: &str| {
            let from = source.join(bin);
            let to = root.join("bin").join(bin);
            fs::copy(&from, &to).unwrap_or_else(|error| {
                panic!(
                    "{} missing ({error}); build with `cargo build -p cmux-relay -p cmux-tui \
                     --release` in cmux-tui/ or set SHELLX_E2E_BIN_DIR",
                    from.display()
                )
            });
            to
        };
        let relay_bin = copy("cmux-relay");
        let tui_bin = copy("cmux-tui");
        write_private(&root.join("config.json"), "{}");
        let mut harness = Harness {
            relay_bin,
            tui_bin,
            secret: random_hex(32),
            slot: random_hex(16),
            session: format!("shx{name}"),
            port: free_port(),
            relay: None,
            daemon: None,
            tickets: Arc::new(AtomicUsize::new(0)),
            root,
        };
        harness.start_relay();
        harness.start_daemon();
        harness
    }

    pub fn route(&self) -> String {
        format!("relay+ws://127.0.0.1:{}", self.port)
    }

    /// Plain-WebSocket form, as `pair.poll` would hand it to the app.
    pub fn ws_route(&self) -> String {
        format!("ws://127.0.0.1:{}", self.port)
    }

    fn isolated(&self, program: &Path) -> Command {
        let mut command = Command::new(program);
        command
            .env_clear()
            .env("HOME", self.root.join("home"))
            .env("TMPDIR", format!("{}/", self.root.join("tmp").display()))
            .env("PATH", "/usr/bin:/bin:/usr/sbin:/sbin")
            .env(
                "USER",
                std::env::var("USER").unwrap_or_else(|_| "shellx".into()),
            )
            .env("SHELL", "/bin/sh")
            .env("LANG", UTF8_LOCALE)
            .env("LC_ALL", UTF8_LOCALE)
            .env("TERM", "xterm-256color")
            .env("CMUX_TUI_CONFIG", self.root.join("config.json"))
            .current_dir(self.root.join("tmp"))
            .stdin(Stdio::null());
        command
    }

    fn tui(&self, args: &[&str]) -> Output {
        self.isolated(&self.tui_bin)
            .args(args)
            .output()
            .expect("run cmux-tui")
    }

    fn start_relay(&mut self) {
        let log = fs::File::create(self.root.join("relay.log")).unwrap();
        let child = self
            .isolated(&self.relay_bin)
            .env("CMUX_RELAY_HMAC_SECRET", &self.secret)
            .args(["serve", "--bind", &format!("127.0.0.1:{}", self.port)])
            .stdout(log.try_clone().unwrap())
            .stderr(log)
            .spawn()
            .expect("start cmux-relay");
        self.relay = Some(child);
        let port = self.port;
        wait_until(Duration::from_secs(20), || {
            std::net::TcpStream::connect(("127.0.0.1", port)).ok()
        })
        .unwrap_or_else(|| panic!("relay did not listen: {}", self.log("relay.log")));
    }

    /// Mint a relay ticket with the CLI into an owner-only file.
    pub fn mint(&self, permission: &str, path: &Path) {
        let output = self
            .isolated(&self.relay_bin)
            .env("CMUX_RELAY_HMAC_SECRET", &self.secret)
            .args(["ticket", "--permission", permission, "--slot", &self.slot])
            .output()
            .expect("mint ticket");
        assert!(
            output.status.success(),
            "mint failed: {}",
            String::from_utf8_lossy(&output.stderr)
        );
        write_private(path, String::from_utf8(output.stdout).unwrap().trim());
    }

    /// The app's `ticket` callback: a fresh connect ticket file per call.
    pub fn ticket_fn(&self) -> Arc<dyn Fn() -> anyhow::Result<PathBuf> + Send + Sync> {
        let relay_bin = self.relay_bin.clone();
        let secret = self.secret.clone();
        let slot = self.slot.clone();
        let dir = self.root.join("tickets");
        let count = self.tickets.clone();
        let env_root = self.root.clone();
        Arc::new(move || {
            let n = count.fetch_add(1, Ordering::SeqCst);
            let output = Command::new(&relay_bin)
                .env_clear()
                .env("HOME", env_root.join("home"))
                .env("PATH", "/usr/bin:/bin")
                .env("CMUX_RELAY_HMAC_SECRET", &secret)
                .args(["ticket", "--permission", "connect", "--slot", &slot])
                .current_dir(env_root.join("tmp"))
                .output()?;
            anyhow::ensure!(output.status.success(), "ticket mint failed");
            let path = dir.join(format!("connect-{n}.ticket"));
            write_private(&path, String::from_utf8(output.stdout)?.trim());
            Ok(path)
        })
    }

    pub fn tickets_minted(&self) -> usize {
        self.tickets.load(Ordering::SeqCst)
    }

    pub fn start_daemon(&mut self) {
        let ticket = self.root.join("register.ticket");
        self.mint("register", &ticket);
        let log = fs::OpenOptions::new()
            .create(true)
            .append(true)
            .open(self.root.join("daemon.log"))
            .unwrap();
        let route = self.route();
        let dstate = self.root.join("dstate");
        let child = self
            .isolated(&self.tui_bin)
            .args([
                "server",
                "start",
                "--session",
                &self.session,
                "--headless",
                "--ephemeral",
                "--remote-state-dir",
                dstate.to_str().unwrap(),
                "--relay",
                &route,
                "--relay-slot",
                &self.slot,
                "--relay-ticket-file",
                ticket.to_str().unwrap(),
            ])
            .stdout(log.try_clone().unwrap())
            .stderr(log)
            .spawn()
            .expect("start cmux-tui daemon");
        self.daemon = Some(child);
        // The admin socket answers once the remote runtime is up.
        wait_until(Duration::from_secs(30), || {
            self.admin("devices", &["--json"])
                .status
                .success()
                .then_some(())
        })
        .unwrap_or_else(|| panic!("daemon did not start: {}", self.log("daemon.log")));
    }

    /// Stop the daemon through its own socket, then make sure it is gone.
    pub fn stop_daemon(&mut self) {
        let _ = self.tui(&["server", "stop", "--session", &self.session]);
        if let Some(mut child) = self.daemon.take() {
            let exited = wait_until(Duration::from_secs(10), || child.try_wait().ok().flatten());
            if exited.is_none() {
                let _ = child.kill();
                let _ = child.wait();
            }
        }
        self.kill_terminal_hosts();
    }

    /// SIGKILL the daemon (a crashed or vanished Mac), no graceful detach.
    pub fn kill_daemon(&mut self) {
        if let Some(mut child) = self.daemon.take() {
            let _ = child.kill();
            let _ = child.wait();
        }
        self.kill_terminal_hosts();
    }

    fn admin(&self, action: &str, extra: &[&str]) -> Output {
        let dstate = self.root.join("dstate");
        let mut args = vec!["remote", "enroll", action];
        args.extend_from_slice(extra);
        args.extend_from_slice(&["--session", &self.session, "--state-dir"]);
        args.push(dstate.to_str().unwrap());
        self.tui(&args)
    }

    /// `remote enroll create` with the relay as the only route.
    pub fn create_invitation(&self) -> PathBuf {
        let ticket = self.root.join("invite-connect.ticket");
        self.mint("connect", &ticket);
        let route = self.route();
        let ticket_arg = ticket.to_str().unwrap().to_owned();
        let output = self.admin(
            "create",
            &[
                "--advertise",
                &route,
                "--relay-route",
                &route,
                "--relay-slot",
                &self.slot,
                "--relay-ticket-file",
                &ticket_arg,
            ],
        );
        assert!(
            output.status.success(),
            "enroll create failed: {}",
            String::from_utf8_lossy(&output.stderr)
        );
        let uri = String::from_utf8(output.stdout).unwrap();
        assert!(
            uri.trim().starts_with("cmux://enroll/"),
            "unexpected invitation output"
        );
        let path = self.root.join("invitation.txt");
        write_private(&path, uri.trim());
        path
    }

    /// Wait for a pending enrollment from `device_name` and approve it.
    pub fn approve(&self, device_name: &str) -> String {
        let id = wait_until(Duration::from_secs(60), || {
            let output = self.admin("pending", &["--json"]);
            let value: Value = serde_json::from_slice(&output.stdout).ok()?;
            pending_invitation(&value, device_name)
        })
        .unwrap_or_else(|| panic!("no pending enrollment: {}", self.log("daemon.log")));
        let output = self.admin("approve", &[&id]);
        assert!(
            output.status.success(),
            "approve failed: {}",
            String::from_utf8_lossy(&output.stderr)
        );
        id
    }

    pub fn log(&self, name: &str) -> String {
        fs::read_to_string(self.root.join(name)).unwrap_or_default()
    }

    /// Terminal hosts may outlive the daemon; find ours by the isolated HOME.
    fn kill_terminal_hosts(&self) {
        let Ok(output) = Command::new("pgrep")
            .args(["-f", "__terminal-host"])
            .output()
        else {
            return;
        };
        let marker = format!("HOME={}", self.root.join("home").display());
        for pid in String::from_utf8_lossy(&output.stdout).split_whitespace() {
            let env = Command::new("ps")
                .args(["eww", "-o", "command=", "-p", pid])
                .output();
            if env.is_ok_and(|env| String::from_utf8_lossy(&env.stdout).contains(&marker)) {
                let _ = Command::new("pkill").args(["-P", pid]).status();
                let _ = Command::new("kill").arg(pid).status();
            }
        }
    }
}

fn pending_invitation(value: &Value, device_name: &str) -> Option<String> {
    match value {
        Value::Array(items) => items
            .iter()
            .find_map(|item| pending_invitation(item, device_name)),
        Value::Object(object) => {
            if let (Some(Value::String(id)), Some(Value::String(name))) =
                (object.get("invitation_id"), object.get("device_name"))
                && name == device_name
            {
                return Some(id.clone());
            }
            object
                .values()
                .find_map(|item| pending_invitation(item, device_name))
        }
        _ => None,
    }
}

impl Drop for Harness {
    fn drop(&mut self) {
        // Secrets first, so a failed teardown never leaves them behind.
        for name in ["register.ticket", "invite-connect.ticket", "invitation.txt"] {
            let _ = fs::remove_file(self.root.join(name));
        }
        let _ = fs::remove_dir_all(self.root.join("tickets"));
        self.stop_daemon();
        if let Some(mut relay) = self.relay.take() {
            let _ = relay.kill();
            let _ = relay.wait();
        }
        if std::env::var_os("SHELLX_E2E_KEEP").is_none() {
            let _ = fs::remove_dir_all(&self.root);
        }
    }
}
