//! End to end against a real `cmux-relay` and `cmux-tui` daemon (Unix only;
//! the client code under test is the same on Windows).
//!
//! Run: `cargo test -p shellx-remote --test relay_e2e -- --ignored --nocapture`
//! (binaries: see `tests/support/mod.rs`).
#![cfg(unix)]

mod support;

use std::path::Path;
use std::sync::mpsc::RecvTimeoutError;
use std::time::{Duration, Instant};

use shellx_remote::{AttachEvent, Attachment, ConnectConfig, RemoteClient};
use support::Harness;

const DEVICE: &str = "ShellX e2e PC";

fn config(harness: &Harness, route: String, invite: Option<&Path>) -> ConnectConfig {
    ConnectConfig {
        state_dir: harness.root.join("cstate/remote"),
        device_name: DEVICE.into(),
        relay_route: route,
        relay_slot: harness.slot.clone(),
        invite_path: invite.map(Path::to_path_buf),
        ticket: harness.ticket_fn(),
    }
}

/// Enroll through the relay: connect with the invitation on a thread, approve
/// on the "Mac" with the owner CLI, then the connect returns.
fn enroll(harness: &Harness) -> RemoteClient {
    let invite = harness.create_invitation();
    // The app gets `ws://`/`wss://` from pair.poll; the invite says relay+ws.
    let cfg = config(harness, harness.ws_route(), Some(&invite));
    let connecting = std::thread::spawn(move || RemoteClient::connect(cfg));
    harness.approve(DEVICE);
    let client = connecting
        .join()
        .expect("connect thread")
        .unwrap_or_else(|error| {
            panic!(
                "enrolled connect failed: {error:#}\n{}",
                harness.log("daemon.log")
            )
        });
    assert!(RemoteClient::is_enrolled(
        &harness.root.join("cstate/remote"),
        client.daemon_fingerprint()
    ));
    client
}

fn terminal_id(client: &RemoteClient) -> String {
    let terminals = client.list_terminals().expect("list terminals");
    match terminals.first() {
        Some(terminal) => terminal.id.clone(),
        None => {
            let created = client.create_terminal().expect("create terminal");
            let listed = client.list_terminals().expect("list after create");
            assert!(
                listed.iter().any(|t| t.id == created.id),
                "created terminal not listed"
            );
            created.id
        }
    }
}

/// Collect events until `done` says so; panics with what was seen on timeout.
fn wait_for(
    attachment: &Attachment,
    output: &mut Vec<u8>,
    timeout: Duration,
    mut done: impl FnMut(&AttachEvent, &[u8]) -> bool,
) -> AttachEvent {
    let deadline = Instant::now() + timeout;
    loop {
        let left = deadline.saturating_duration_since(Instant::now());
        match attachment.events().recv_timeout(left) {
            Ok(event) => {
                if let AttachEvent::Output(bytes) | AttachEvent::Snapshot(bytes) = &event {
                    output.extend_from_slice(bytes);
                }
                if done(&event, output) {
                    return event;
                }
            }
            Err(RecvTimeoutError::Timeout) => panic!(
                "timed out; output so far: {:?}",
                String::from_utf8_lossy(&output[output.len().saturating_sub(800)..])
            ),
            Err(RecvTimeoutError::Disconnected) => panic!("attach channel hung up"),
        }
    }
}

fn contains(haystack: &[u8], needle: &[u8]) -> bool {
    haystack
        .windows(needle.len())
        .any(|window| window == needle)
}

fn attach_ready(client: &RemoteClient, id: &str, cols: u16, rows: u16) -> (Attachment, Vec<u8>) {
    let attachment = client.attach(id, cols, rows).expect("attach");
    let mut output = Vec::new();
    let mut grid = None;
    wait_for(
        &attachment,
        &mut output,
        Duration::from_secs(20),
        |event, _| {
            match event {
                AttachEvent::Resized { cols, rows } => grid = Some((*cols, *rows)),
                AttachEvent::Snapshot(_) => return true,
                AttachEvent::Ended | AttachEvent::Disconnected(_) => {
                    panic!("attach ended: {event:?}")
                }
                AttachEvent::Output(_) => {}
            }
            false
        },
    );
    assert!(grid.is_some(), "snapshot without a preceding Resized");
    (attachment, output)
}

/// Composed Vietnamese text goes out as one UTF-8 write and comes back from
/// the remote shell; resize reaches the remote PTY.
#[test]
#[ignore = "needs cmux-relay + cmux-tui binaries (SHELLX_E2E_BIN_DIR)"]
fn vietnamese_round_trip() {
    let harness = Harness::start("vn");
    let client = enroll(&harness);
    let id = terminal_id(&client);
    let (attachment, mut output) = attach_ready(&client, &id, 100, 30);

    // `tiếng Việt` = 74 69 e1 ba bf 6e 67 20 56 69 e1 bb 87 74 (Review Focus 1).
    let text = "tiếng Việt";
    assert_eq!(
        text.as_bytes(),
        [
            0x74, 0x69, 0xe1, 0xba, 0xbf, 0x6e, 0x67, 0x20, 0x56, 0x69, 0xe1, 0xbb, 0x87, 0x74
        ]
    );
    // The shell computes the suffix, so the marker only appears in its
    // output, never in the echo of the typed line.
    attachment
        .write(format!("printf '%s-%s\\n' '{text}' $((6*7))\r").as_bytes())
        .unwrap();
    let marker = format!("{text}-42");
    wait_for(
        &attachment,
        &mut output,
        Duration::from_secs(20),
        |event, seen| {
            assert!(
                !matches!(event, AttachEvent::Ended | AttachEvent::Disconnected(_)),
                "{event:?}"
            );
            contains(seen, marker.as_bytes())
        },
    );

    // Resize: the Mac re-grids and sends a fresh replay; the PTY sees it.
    attachment.resize(120, 40).unwrap();
    wait_for(
        &attachment,
        &mut output,
        Duration::from_secs(20),
        |event, _| {
            matches!(
                event,
                AttachEvent::Resized {
                    cols: 120,
                    rows: 40
                }
            )
        },
    );
    output.clear();
    attachment.write(b"stty size\r").unwrap();
    wait_for(
        &attachment,
        &mut output,
        Duration::from_secs(20),
        |_, seen| contains(seen, b"40 120"),
    );

    attachment.detach();
    // The control stream still works after a detach.
    assert!(client.list_terminals().unwrap().iter().any(|t| t.id == id));
    assert!(!client.closed());
    assert!(
        harness.tickets_minted() >= 1,
        "connect must take tickets from the callback"
    );
}

/// `--ephemeral` loses workspace state with the daemon process, so this
/// checks what the app relies on: after a SIGKILL of the daemon (no graceful
/// detach) an open view reports `Disconnected` within the client's bounded
/// in-place recovery, the client reports `closed()` and
/// refuses input, and a NEW `RemoteClient::connect` with a fresh ticket and
/// no invitation (enrolled auth; the daemon's remote state dir survives)
/// works against the restarted daemon, down to a new attach round trip.
#[test]
#[ignore = "needs cmux-relay + cmux-tui binaries (SHELLX_E2E_BIN_DIR)"]
fn reconnects_after_daemon_restart() {
    let mut harness = Harness::start("rc");
    let client = enroll(&harness);
    let id = terminal_id(&client);
    let (attachment, mut output) = attach_ready(&client, &id, 80, 24);
    let minted_before = harness.tickets_minted();

    harness.kill_daemon();
    let killed = Instant::now();
    let ended = wait_for(
        &attachment,
        &mut output,
        Duration::from_secs(90),
        |event, _| matches!(event, AttachEvent::Ended | AttachEvent::Disconnected(_)),
    );
    eprintln!("view {:?} after daemon kill: {ended:?}", killed.elapsed());
    assert!(matches!(ended, AttachEvent::Disconnected(_)), "{ended:?}");
    assert!(
        attachment.write(b"x").is_err(),
        "input must be refused once the view ended"
    );
    harness.start_daemon();
    let closed = Instant::now();
    while !client.closed() {
        assert!(
            closed.elapsed() < Duration::from_secs(90),
            "client never reported closed"
        );
        std::thread::sleep(Duration::from_millis(200));
    }
    drop(attachment);
    drop(client);

    let mut reconnected = None;
    let started = Instant::now();
    while reconnected.is_none() {
        match RemoteClient::connect(config(&harness, harness.route(), None)) {
            Ok(client) => reconnected = Some(client),
            // The daemon may still be registering its slot on the relay.
            Err(error) if started.elapsed() < Duration::from_secs(60) => {
                eprintln!("reconnect attempt failed (retrying): {error:#}");
                std::thread::sleep(Duration::from_secs(1));
            }
            Err(error) => panic!("reconnect failed: {error:#}\n{}", harness.log("daemon.log")),
        }
    }
    let client = reconnected.unwrap();
    assert!(
        harness.tickets_minted() > minted_before,
        "reconnect must mint a fresh ticket"
    );
    let id = terminal_id(&client);
    let (attachment, mut output) = attach_ready(&client, &id, 80, 24);
    attachment.write(b"echo again-$((40+2))\r").unwrap();
    wait_for(
        &attachment,
        &mut output,
        Duration::from_secs(20),
        |_, seen| contains(seen, b"again-42"),
    );
}
