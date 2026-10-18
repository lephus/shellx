//! GPUI-free, in-process client for a Mac running ShellX: a `cmux-tui`
//! daemon registered on `cmux-relay` (D-W0-1 protocol (b)).
//!
//! Path: relay v2 (`cmux-remote`'s `RelayProvider`, tickets from the
//! caller) → Noise XX / XXpsk3 (`ClientConnection`, enrollment + on-site
//! approval) → service multiplexer → mux control streams speaking the
//! cmux-tui command protocol (`list-workspaces`, `new-workspace`, and one
//! `attach-surface` stream per attachment in v6 PTY byte mode). No local
//! socket and no sidecar process, so it works the same on Windows.
//!
//! Threading: `RemoteClient::connect` builds its own multi-thread tokio
//! runtime (2 workers). `connect`, `list_terminals`, `create_terminal` and
//! `attach` block the calling thread (call them off the UI thread, and not
//! from inside another tokio runtime). `Attachment::write`/`resize`/`detach`
//! never block. Events arrive on a `std::sync::mpsc` channel; a hung-up
//! channel means the client was dropped.
//!
//! Contract notes for the app (Task 13):
//! - Channels are unbounded (events to the app, commands to the Mac): there
//!   is no backpressure, so drain `events()` promptly; a stalled reader
//!   grows memory by the terminal's output rate.
//! - `Ended` means the view is gone: the surface exited, or the daemon was
//!   stopped gracefully (it detaches every view first). Treat `Ended`
//!   together with `closed()` as "reconnect", like `Disconnected`.
//! - After a successful enrollment (`connect` with `invite_path`), the caller
//!   must delete the invitation file (it holds the one-time PSK), and should
//!   check that `pair.poll`'s `daemon_fingerprint` equals
//!   `RemoteClient::daemon_fingerprint()` before trusting the pairing.
//! - Dropping a `RemoteClient` returns immediately; the graceful close runs
//!   on a detached thread.
//!
//! Reference implementations read for this port (MIT, cmux-tui workspace):
//! `crates/cmux-terminal-client/src/lib.rs` (`connect_route_client`),
//! `crates/cmux-tui/src/remote_runtime.rs` (`run_client`) and
//! `crates/cmux-tui/src/session/remote.rs` (attach/send requests).

mod events;
mod mux;
mod store;
mod ticket;

use std::collections::{BTreeMap, HashMap};
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::{Arc, Mutex};
use std::time::Duration;

use anyhow::{Context, anyhow, bail};
use async_trait::async_trait;
use base64::Engine;
use bytes::Bytes;
use cmux_remote::MuxLineClient;
use cmux_remote::connection::{
    ClientConnection, ClientConnectionConfig, ReconnectGroupSource, ReconnectPolicy,
};
use cmux_remote::crypto::{ClientAuthMode, public_key_fingerprint};
use cmux_remote::identity::EnrollmentInvitation;
use cmux_remote::provider::{
    ConnectRequest, LinkGroup, ProviderError, RelayClientConfig, RelayProvider, TransportProvider,
};
use cmux_remote::service::{EndpointRole, ServiceMultiplexer, ServiceStream};
use cmux_remote::session::SessionLimits;
use cmux_remote_protocol::{LanePolicy, Service, SessionId};
use serde_json::{Value, json};
use tokio::sync::{mpsc, oneshot, watch};
use url::Url;
use zeroize::Zeroizing;

pub use events::{AttachEvent, RemoteTerminal};

/// Largest relay carrier frame, as `cmux-tui remote connect` uses.
const MAX_CARRIER_FRAME_BYTES: usize = 65_535;
/// First connect with an invitation: Noise through the relay, then the Mac
/// owner approves on site.
const ENROLL_TIMEOUT: Duration = Duration::from_secs(300);
const CONNECT_TIMEOUT: Duration = Duration::from_secs(30);
const REQUEST_TIMEOUT: Duration = Duration::from_secs(15);
const ATTACH_TIMEOUT: Duration = Duration::from_secs(20);
const CLOSE_TIMEOUT: Duration = Duration::from_secs(2);
/// Name of the workspace `create_terminal` opens on an empty Mac.
const NEW_WORKSPACE_NAME: &str = "ShellX";
const CLIENT_KIND: &str = "shellx-windows";

/// Everything one connect needs. Values come from shellx-core
/// (`pair.poll`, `tickets.mint`); nothing here is hard-coded.
pub struct ConnectConfig {
    /// Client identity dir (created 0700 on Unix; on Windows the per-user
    /// `%LOCALAPPDATA%\ShellX\native\remote\`).
    pub state_dir: PathBuf,
    /// Shown on the Mac's approval screen.
    pub device_name: String,
    /// From `pair.poll`, e.g. `wss://relay.shellx.pro/v2/relay`
    /// (`ws`/`wss`/`relay+ws`/`relay+wss` accepted).
    pub relay_route: String,
    pub relay_slot: String,
    /// First connect after pairing; `None` once enrolled.
    pub invite_path: Option<PathBuf>,
    /// Mints a fresh connect ticket file per (re)connect. The file is read
    /// and then deleted by this crate.
    pub ticket: Arc<dyn Fn() -> anyhow::Result<PathBuf> + Send + Sync>,
}

/// A connected, enrolled client of one Mac.
pub struct RemoteClient {
    runtime: Option<tokio::runtime::Runtime>,
    inner: Arc<Inner>,
}

struct Inner {
    connection: Arc<ClientConnection>,
    multiplexer: Arc<ServiceMultiplexer>,
    control: MuxLineClient,
    next_request: AtomicU64,
    closed: AtomicBool,
    fatal: watch::Receiver<Option<String>>,
    daemon_fingerprint: String,
}

impl RemoteClient {
    /// Connect (and, with `invite_path`, enroll and wait up to 300 s for the
    /// Mac owner's approval). Blocking.
    pub fn connect(cfg: ConnectConfig) -> anyhow::Result<RemoteClient> {
        let runtime = tokio::runtime::Builder::new_multi_thread()
            .worker_threads(2)
            .thread_name("shellx-remote")
            .enable_all()
            .build()
            .context("could not start the remote client runtime")?;
        match runtime.block_on(connect_inner(cfg)) {
            Ok(inner) => Ok(RemoteClient {
                runtime: Some(runtime),
                inner: Arc::new(inner),
            }),
            Err(error) => {
                // Do not wait for blocking work still in flight (the app's
                // ticket callback): the connect budget is already spent.
                runtime.shutdown_background();
                Err(error)
            }
        }
    }

    /// Whether `state_dir` already holds an enrollment with this daemon
    /// (fingerprint from `pair.poll`), i.e. no invitation is needed.
    pub fn is_enrolled(state_dir: &Path, daemon_fingerprint: &str) -> bool {
        store::is_enrolled(state_dir, daemon_fingerprint)
    }

    /// Fingerprint of the Mac's daemon key this client verified.
    pub fn daemon_fingerprint(&self) -> &str {
        &self.inner.daemon_fingerprint
    }

    pub fn list_terminals(&self) -> anyhow::Result<Vec<RemoteTerminal>> {
        let tree = self.block_on(self.inner.request(json!({"cmd": "list-workspaces"})))?;
        Ok(events::terminals_from_tree(&tree))
    }

    /// Open a workspace with one terminal on the Mac (for a Mac with none).
    pub fn create_terminal(&self) -> anyhow::Result<RemoteTerminal> {
        let created = self.block_on(
            self.inner
                .request(json!({"cmd": "new-workspace", "name": NEW_WORKSPACE_NAME})),
        )?;
        let surface = created
            .get("surface")
            .and_then(Value::as_u64)
            .ok_or_else(|| anyhow!("the Mac did not return the new terminal"))?
            .to_string();
        let listed = self.list_terminals()?;
        Ok(listed
            .into_iter()
            .find(|terminal| terminal.id == surface)
            .unwrap_or(RemoteTerminal {
                id: surface,
                title: NEW_WORKSPACE_NAME.into(),
                cols: 0,
                rows: 0,
            }))
    }

    /// Attach to a terminal in PTY byte mode with this viewer's grid.
    pub fn attach(&self, terminal_id: &str, cols: u16, rows: u16) -> anyhow::Result<Attachment> {
        let surface: u64 = terminal_id
            .parse()
            .with_context(|| format!("invalid terminal id {terminal_id:?}"))?;
        if cols == 0 || rows == 0 {
            bail!("attach needs a non-empty grid");
        }
        let inner = self.inner.clone();
        self.block_on(async move {
            tokio::time::timeout(ATTACH_TIMEOUT, open_attachment(&inner, surface, cols, rows))
                .await
                .map_err(|_| anyhow!("attaching to the remote terminal timed out"))?
        })
    }

    /// The connection to the Mac failed for good (or was closed).
    pub fn closed(&self) -> bool {
        self.inner.is_closed()
    }

    fn block_on<T>(
        &self,
        future: impl std::future::Future<Output = anyhow::Result<T>>,
    ) -> anyhow::Result<T> {
        if self.closed() {
            bail!("the connection to the Mac is closed");
        }
        self.runtime
            .as_ref()
            .expect("runtime lives until drop")
            .block_on(future)
    }
}

impl Drop for RemoteClient {
    /// Returns at once: the graceful close (bounded by `CLOSE_TIMEOUT` per
    /// step) and the runtime shutdown run on a detached thread, so dropping
    /// a client whose Mac is gone never stalls the caller, and dropping it
    /// from inside another tokio runtime does not panic.
    fn drop(&mut self) {
        let Some(runtime) = self.runtime.take() else {
            return;
        };
        let inner = self.inner.clone();
        inner.closed.store(true, Ordering::Release);
        let closer = move || {
            runtime.block_on(async move {
                let _ = tokio::time::timeout(CLOSE_TIMEOUT, inner.control.close()).await;
                let _ = tokio::time::timeout(CLOSE_TIMEOUT, inner.connection.close()).await;
                let _ = tokio::time::timeout(CLOSE_TIMEOUT, inner.multiplexer.shutdown()).await;
            });
            runtime.shutdown_timeout(Duration::from_millis(500));
        };
        if let Err(error) = std::thread::Builder::new()
            .name("shellx-remote-close".into())
            .spawn(closer)
        {
            // No thread: skip the graceful close rather than block.
            drop(error);
        }
    }
}

impl Inner {
    fn is_closed(&self) -> bool {
        self.closed.load(Ordering::Acquire) || self.fatal.borrow().is_some()
    }

    /// One request on the shared control stream; returns the response data.
    async fn request(&self, mut request: Value) -> anyhow::Result<Value> {
        let id = self.next_request.fetch_add(1, Ordering::Relaxed);
        request["id"] = json!(id);
        let reply = tokio::time::timeout(REQUEST_TIMEOUT, self.control.request(&request))
            .await
            .map_err(|_| anyhow!("the Mac did not answer in {}s", REQUEST_TIMEOUT.as_secs()))?
            .map_err(|error| anyhow!("mux control request failed: {error}"))?;
        events::response_result(&reply).map_err(|error| anyhow!("the Mac refused: {error}"))
    }
}

/// `wss://…` → `relay+wss://…` (the relay provider's scheme family).
fn relay_endpoint(route: &str) -> anyhow::Result<Url> {
    let url = Url::parse(route.trim()).with_context(|| format!("invalid relay route {route:?}"))?;
    let scheme = match url.scheme() {
        "ws" | "relay+ws" => "relay+ws",
        "wss" | "https" | "relay+wss" | "relay+https" => "relay+wss",
        other => bail!("relay route scheme {other:?} is not a relay"),
    };
    let (_, rest) = url
        .as_str()
        .split_once("://")
        .expect("parsed URL has an authority");
    Url::parse(&format!("{scheme}://{rest}")).context("invalid relay route")
}

fn read_invitation(path: &Path) -> anyhow::Result<EnrollmentInvitation> {
    // Unix: owner-only check as `cmux-tui remote connect --invite-file`.
    // Windows: plain read under the per-user state dir (NEEDS SECURITY REVIEW).
    #[cfg(unix)]
    let text = cmux_remote::secret_file::read_owner_only_string(path, 64 * 1024)
        .with_context(|| format!("could not read the invitation {}", path.display()))?;
    #[cfg(not(unix))]
    let text = Zeroizing::new(
        std::fs::read_to_string(path)
            .with_context(|| format!("could not read the invitation {}", path.display()))?,
    );
    EnrollmentInvitation::from_uri(text.trim())
        .map_err(|error| anyhow!("invalid invitation: {error}"))
}

fn reconnect_policy() -> ReconnectPolicy {
    ReconnectPolicy {
        initial_delay: Duration::from_millis(250),
        maximum_delay: Duration::from_secs(4),
        // A short in-place recovery keeps attach streams across a network
        // blip; past it the multiplexer reports a fatal error and the app's
        // own backoff (1..30 s, fresh ticket) builds a new client.
        maximum_duration: Some(Duration::from_secs(30)),
        ..ReconnectPolicy::default()
    }
}

/// Fresh relay link groups for `ClientConnection`'s in-place reconnects;
/// each one fetches a ticket through the caller's callback.
struct RelayReconnect {
    provider: Arc<RelayProvider>,
    request: ConnectRequest,
    tickets: ticket::TicketSource,
}

#[async_trait]
impl ReconnectGroupSource for RelayReconnect {
    async fn next_group(&self) -> Result<Arc<dyn LinkGroup>, ProviderError> {
        // A reconnect is a new burst: never reuse the previous connect's
        // ticket, which may be the one the relay just rejected.
        self.tickets.new_burst();
        let group = self.provider.connect(self.request.clone()).await;
        if group.is_err() {
            self.tickets.new_burst();
        }
        group
    }
}

/// Make ring the process TLS provider for `wss://` relays (idempotent; an
/// already-installed provider is kept).
fn ensure_tls_provider() {
    let _ = rustls::crypto::ring::default_provider().install_default();
}

async fn connect_inner(cfg: ConnectConfig) -> anyhow::Result<Inner> {
    ensure_tls_provider();
    let endpoint = relay_endpoint(&cfg.relay_route)?;
    if cfg.relay_slot.trim().is_empty() {
        bail!("relay slot is empty");
    }
    let state_dir = cfg.state_dir.clone();
    let store = tokio::task::spawn_blocking(move || store::Store::open(&state_dir))
        .await
        .context("client identity task failed")??;
    let invitation = cfg
        .invite_path
        .as_deref()
        .map(read_invitation)
        .transpose()?;
    let (auth, expected_daemon, budget) = match &invitation {
        Some(invitation) => {
            let now = std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap_or_default()
                .as_secs();
            if invitation.expires_at_unix <= now {
                bail!("the invitation has expired; request access again");
            }
            let secret = invitation
                .secret_bytes()
                .map_err(|e| anyhow!("invitation: {e}"))?;
            (
                ClientAuthMode::Invitation {
                    id: invitation.id.clone(),
                    secret: Zeroizing::new(secret),
                },
                store::decode_key(&invitation.daemon_public_key)?,
                ENROLL_TIMEOUT,
            )
        }
        None => {
            let key = store
                .daemon_for_slot(&cfg.relay_slot)
                .await?
                .ok_or_else(|| {
                    anyhow!("this PC is not enrolled with that Mac; request access again")
                })?;
            (ClientAuthMode::Enrolled, key, CONNECT_TIMEOUT)
        }
    };

    let tickets = ticket::TicketSource::new(cfg.ticket.clone());
    let provider = Arc::new(
        RelayProvider::with_credentials(
            RelayClientConfig {
                slot: cfg.relay_slot.clone(),
                ticket: String::new(),
                maximum_frame_bytes: MAX_CARRIER_FRAME_BYTES,
                control_timeout: Duration::from_secs(15),
            },
            tickets.credential_source(),
        )
        .map_err(|error| anyhow!("relay configuration: {error}"))?,
    );
    let mut session = [0_u8; 16];
    getrandom::fill(&mut session).map_err(|error| anyhow!("random session id: {error}"))?;
    let request = ConnectRequest {
        endpoint: endpoint.clone(),
        session: SessionId(session),
        lane_policy: LanePolicy::Auto,
        routing: BTreeMap::new(),
    };
    let config = ClientConnectionConfig {
        identity: store.identity(),
        expected_daemon: Some(expected_daemon),
        auth,
        device_name: cfg.device_name.clone(),
        session: SessionId(session),
        lane_policy: LanePolicy::Auto,
        limits: SessionLimits::default(),
        reconnect: reconnect_policy(),
    };
    let with_ticket_reason = |error: String| match tickets.last_error() {
        Some(reason) => anyhow!("{error} (connect ticket: {reason})"),
        None => anyhow!("{error}"),
    };
    let connecting = async {
        let group = provider
            .connect(request.clone())
            .await
            .map_err(|error| with_ticket_reason(format!("relay connect failed: {error}")))?;
        let reconnect: Arc<dyn ReconnectGroupSource> = Arc::new(RelayReconnect {
            provider: provider.clone(),
            request: request.clone(),
            tickets: tickets.clone(),
        });
        let connected =
            ClientConnection::connect_with_reconnect_groups(group.clone(), config, Some(reconnect))
                .await;
        match connected {
            Ok(connection) => Ok(connection),
            Err(error) => {
                let _ = tokio::time::timeout(CLOSE_TIMEOUT, group.close()).await;
                Err(with_ticket_reason(format!(
                    "secure connect to the Mac failed: {error}"
                )))
            }
        }
    };
    let connection = tokio::time::timeout(budget, connecting)
        .await
        .map_err(|_| {
            if invitation.is_some() {
                anyhow!(
                    "the Mac did not approve this PC within {}s",
                    budget.as_secs()
                )
            } else {
                anyhow!(
                    "connecting to the Mac timed out after {}s",
                    budget.as_secs()
                )
            }
        })??;
    let daemon_key = connection.daemon_public_key();
    if daemon_key != expected_daemon {
        let _ = connection.close().await;
        bail!("the Mac's key does not match the paired key");
    }
    if let Some(invitation) = &invitation {
        store
            .pin(
                &invitation.daemon_name,
                daemon_key,
                endpoint.as_str(),
                &cfg.relay_slot,
            )
            .await?;
    }

    let multiplexer = ServiceMultiplexer::new(connection.clone(), EndpointRole::Client);
    let fatal = multiplexer.subscribe_fatal();
    let control = match MuxLineClient::open(&multiplexer).await {
        Ok(control) => control,
        Err(error) => {
            let _ = connection.close().await;
            bail!("could not open the Mac's terminal service: {error}");
        }
    };
    let inner = Inner {
        connection,
        multiplexer,
        control,
        next_request: AtomicU64::new(1),
        closed: AtomicBool::new(false),
        fatal,
        daemon_fingerprint: public_key_fingerprint(&daemon_key),
    };
    inner.request(json!({"cmd": "identify"})).await?;
    inner
        .request(json!({"cmd": "set-client-info", "name": cfg.device_name, "kind": CLIENT_KIND}))
        .await?;
    Ok(inner)
}

// ---------------------------------------------------------------------------
// Attachments

type Reply = oneshot::Sender<Result<Value, String>>;

enum Command {
    Request {
        request: Value,
        reply: Option<Reply>,
    },
    Close,
}

/// One attached remote terminal: its own mux control stream.
pub struct Attachment {
    events: std::sync::mpsc::Receiver<AttachEvent>,
    input: AttachmentInput,
}

/// The input half of an [`Attachment`] (`write`/`resize`), `Send + Sync`
/// so a pane's link can hold it while a pump thread owns the event
/// receiver (`Attachment::into_parts`). Dropping it closes the view.
pub struct AttachmentInput {
    commands: mpsc::UnboundedSender<Command>,
    surface: u64,
    alive: Arc<AtomicBool>,
}

impl Attachment {
    pub fn events(&self) -> &std::sync::mpsc::Receiver<AttachEvent> {
        &self.events
    }

    /// Input bytes as ONE `send` message (a composed IME commit stays one
    /// UTF-8 write). Fails once the view ended or the link is down.
    pub fn write(&self, bytes: &[u8]) -> anyhow::Result<()> {
        self.input.write(bytes)
    }

    /// Report this viewer's grid; a `Resized` + `Snapshot` follows when the
    /// Mac applies it.
    pub fn resize(&self, cols: u16, rows: u16) -> anyhow::Result<()> {
        self.input.resize(cols, rows)
    }

    /// Split into the input half and the event receiver (the receiver is
    /// not `Sync`, so a pump thread owns it). Dropping the input half
    /// closes the view, as dropping the `Attachment` does.
    pub fn into_parts(self) -> (AttachmentInput, std::sync::mpsc::Receiver<AttachEvent>) {
        (self.input, self.events)
    }

    pub fn detach(self) {
        // Drop closes the stream.
    }
}

impl AttachmentInput {
    /// See [`Attachment::write`].
    pub fn write(&self, bytes: &[u8]) -> anyhow::Result<()> {
        if bytes.is_empty() {
            return Ok(());
        }
        let encoded = base64::engine::general_purpose::STANDARD.encode(bytes);
        self.send(json!({"cmd": "send", "surface": self.surface, "bytes": encoded}))
    }

    /// See [`Attachment::resize`].
    pub fn resize(&self, cols: u16, rows: u16) -> anyhow::Result<()> {
        if cols == 0 || rows == 0 {
            bail!("resize needs a non-empty grid");
        }
        self.send(
            json!({"cmd": "resize-surface", "surface": self.surface, "cols": cols, "rows": rows}),
        )
    }

    fn send(&self, request: Value) -> anyhow::Result<()> {
        if !self.alive.load(Ordering::Acquire) {
            bail!("the remote terminal is not connected");
        }
        self.commands
            .send(Command::Request {
                request,
                reply: None,
            })
            .map_err(|_| anyhow!("the remote terminal is not connected"))
    }
}

impl Drop for AttachmentInput {
    fn drop(&mut self) {
        self.alive.store(false, Ordering::Release);
        let _ = self.commands.send(Command::Close);
    }
}

async fn open_attachment(
    inner: &Arc<Inner>,
    surface: u64,
    cols: u16,
    rows: u16,
) -> anyhow::Result<Attachment> {
    let stream = inner
        .multiplexer
        .open(Service::MuxControl, BTreeMap::new())
        .await
        .map_err(|error| anyhow!("could not open an attach stream: {error}"))?;
    let buffered = match mux::await_opened(&stream).await {
        Ok(buffered) => buffered,
        Err(error) => {
            let _ = stream.close().await;
            return Err(error);
        }
    };
    let stream = Arc::new(stream);
    let (event_tx, events) = std::sync::mpsc::channel();
    let (commands, command_rx) = mpsc::unbounded_channel();
    let pending: Arc<Mutex<HashMap<u64, Reply>>> = Arc::default();
    let alive = Arc::new(AtomicBool::new(true));
    tokio::spawn(write_loop(stream.clone(), command_rx, pending.clone()));
    tokio::spawn(read_loop(
        stream,
        buffered,
        event_tx,
        pending,
        inner.fatal.clone(),
        alive.clone(),
    ));
    let attachment = Attachment {
        events,
        input: AttachmentInput {
            commands,
            surface,
            alive,
        },
    };

    let identity = attachment_request(&attachment, json!({"cmd": "identify"})).await?;
    let initial_size = identity
        .get("capabilities")
        .and_then(Value::as_array)
        .is_some_and(|caps| {
            caps.iter()
                .any(|cap| cap.as_str() == Some("attach-initial-size"))
        });
    let mut attach = json!({"cmd": "attach-surface", "surface": surface});
    if initial_size {
        attach["cols"] = json!(cols);
        attach["rows"] = json!(rows);
    }
    attachment_request(&attachment, attach).await?;
    if !initial_size {
        attachment.resize(cols, rows)?;
    }
    Ok(attachment)
}

async fn attachment_request(attachment: &Attachment, request: Value) -> anyhow::Result<Value> {
    let (reply, response) = oneshot::channel();
    attachment
        .input
        .commands
        .send(Command::Request {
            request,
            reply: Some(reply),
        })
        .map_err(|_| anyhow!("attach stream closed"))?;
    response
        .await
        .map_err(|_| anyhow!("attach stream closed before the Mac answered"))?
        .map_err(|error| anyhow!("the Mac refused the attach: {error}"))
}

async fn write_loop(
    stream: Arc<ServiceStream>,
    mut commands: mpsc::UnboundedReceiver<Command>,
    pending: Arc<Mutex<HashMap<u64, Reply>>>,
) {
    let mut next_id = 1_u64;
    let mut next_message = 1_u64;
    while let Some(command) = commands.recv().await {
        let Command::Request { mut request, reply } = command else {
            break;
        };
        let id = next_id;
        next_id += 1;
        request["id"] = json!(id);
        let lane = mux::lane_for_command(
            request
                .get("cmd")
                .and_then(Value::as_str)
                .unwrap_or_default(),
        );
        let mut line = match serde_json::to_vec(&request) {
            Ok(line) => line,
            Err(_) => continue,
        };
        line.push(b'\n');
        if let Some(reply) = reply {
            pending
                .lock()
                .unwrap_or_else(|e| e.into_inner())
                .insert(id, reply);
        }
        let message = next_message;
        next_message += 1;
        for packet in mux::encode_line(message, &line) {
            if stream.send_on(lane, packet).await.is_err() {
                pending
                    .lock()
                    .unwrap_or_else(|e| e.into_inner())
                    .remove(&id);
                let _ = stream.close().await;
                return;
            }
        }
    }
    let _ = tokio::time::timeout(CLOSE_TIMEOUT, stream.close()).await;
}

async fn read_loop(
    stream: Arc<ServiceStream>,
    mut buffered: std::collections::VecDeque<cmux_remote::service::StreamChunk>,
    events: std::sync::mpsc::Sender<AttachEvent>,
    pending: Arc<Mutex<HashMap<u64, Reply>>>,
    mut fatal: watch::Receiver<Option<String>>,
    alive: Arc<AtomicBool>,
) {
    let mut assembler = mux::LineAssembler::default();
    let end = loop {
        let chunk = match buffered.pop_front() {
            Some(chunk) => Ok(Some(chunk)),
            None => tokio::select! {
                chunk = stream.receive() => chunk.map_err(|error| error.to_string()),
                message = wait_fatal(&mut fatal) => Err(message),
            },
        };
        let chunk = match chunk {
            Ok(Some(chunk)) => chunk,
            Ok(None) => break AttachEvent::Ended,
            Err(error) => break AttachEvent::Disconnected(error),
        };
        if !chunk.payload.is_empty() {
            match assembler.push(chunk.lane, Bytes::clone(&chunk.payload)) {
                Ok(Some(line)) => match events::decode_line(&line) {
                    Ok(events::Line::Events(list)) => {
                        let mut terminal = None;
                        for event in list {
                            if matches!(event, AttachEvent::Ended | AttachEvent::Disconnected(_)) {
                                terminal = Some(event);
                                break;
                            }
                            if events.send(event).is_err() {
                                terminal = Some(AttachEvent::Ended);
                                break;
                            }
                        }
                        if let Some(event) = terminal {
                            break event;
                        }
                    }
                    Ok(events::Line::Response { id, result }) => {
                        let reply = pending
                            .lock()
                            .unwrap_or_else(|e| e.into_inner())
                            .remove(&id);
                        if let Some(reply) = reply {
                            let _ = reply.send(result);
                        }
                    }
                    Ok(events::Line::Ignored) => {}
                    Err(error) => break AttachEvent::Disconnected(format!("{error:#}")),
                },
                Ok(None) => {}
                Err(error) => break AttachEvent::Disconnected(format!("{error:#}")),
            }
        }
        if chunk.finished || chunk.reset {
            break match fatal.borrow().clone() {
                Some(message) => AttachEvent::Disconnected(message),
                None if chunk.reset => AttachEvent::Disconnected("attach stream was reset".into()),
                None => AttachEvent::Ended,
            };
        }
    };
    alive.store(false, Ordering::Release);
    pending.lock().unwrap_or_else(|e| e.into_inner()).clear();
    let _ = events.send(end);
    let _ = tokio::time::timeout(CLOSE_TIMEOUT, stream.close()).await;
}

async fn wait_fatal(fatal: &mut watch::Receiver<Option<String>>) -> String {
    loop {
        if let Some(message) = fatal.borrow().clone() {
            return message;
        }
        if fatal.changed().await.is_err() {
            return "the connection to the Mac stopped".into();
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn attachment_parts_split_send_sync_input_from_the_receiver() {
        fn send_sync<T: Send + Sync>() {}
        send_sync::<AttachmentInput>();
        send_sync::<RemoteClient>();
        let (_event_tx, events) = std::sync::mpsc::channel();
        let (commands, mut command_rx) = mpsc::unbounded_channel();
        let alive = Arc::new(AtomicBool::new(true));
        let attachment = Attachment {
            events,
            input: AttachmentInput {
                commands,
                surface: 7,
                alive: alive.clone(),
            },
        };
        let (input, _events) = attachment.into_parts();
        input.write("tiếng Việt".as_bytes()).unwrap();
        let Some(Command::Request { request, .. }) = command_rx.try_recv().ok() else {
            panic!("no send request");
        };
        assert_eq!(request["cmd"], "send");
        assert_eq!(request["surface"], 7);
        drop(input);
        assert!(!alive.load(Ordering::Acquire));
        assert!(matches!(command_rx.try_recv(), Ok(Command::Close)));
    }

    #[test]
    fn relay_routes_map_to_the_relay_scheme_family() {
        assert_eq!(
            relay_endpoint("wss://relay.shellx.pro/v2/relay")
                .unwrap()
                .as_str(),
            "relay+wss://relay.shellx.pro/v2/relay"
        );
        assert_eq!(
            relay_endpoint("ws://127.0.0.1:8787").unwrap().as_str(),
            "relay+ws://127.0.0.1:8787/"
        );
        assert_eq!(
            relay_endpoint("relay+ws://127.0.0.1:8787/")
                .unwrap()
                .as_str(),
            "relay+ws://127.0.0.1:8787/"
        );
        assert!(relay_endpoint("http://relay.example").is_err());
        assert!(relay_endpoint("not a url").is_err());
    }

    #[test]
    fn invitation_file_round_trips() {
        let invitation = EnrollmentInvitation {
            version: 1,
            id: "inv-1".into(),
            secret: base64::engine::general_purpose::URL_SAFE_NO_PAD.encode([7_u8; 32]),
            daemon_public_key: base64::engine::general_purpose::URL_SAFE_NO_PAD.encode([9_u8; 32]),
            daemon_fingerprint: public_key_fingerprint(&[9_u8; 32]),
            daemon_name: "Mac".into(),
            expires_at_unix: u64::MAX / 2,
            route_hints: vec!["relay+ws://127.0.0.1:8787".into()],
            relay_access: Vec::new(),
            approval_required: true,
        };
        let path = std::env::temp_dir().join(format!("shellx-invite-{}", std::process::id()));
        let mut options = std::fs::OpenOptions::new();
        options.write(true).create(true).truncate(true);
        #[cfg(unix)]
        {
            use std::os::unix::fs::OpenOptionsExt;
            options.mode(0o600);
        }
        use std::io::Write;
        let mut file = options.open(&path).unwrap();
        writeln!(file, "{}", invitation.to_uri().unwrap()).unwrap();
        drop(file);
        let parsed = read_invitation(&path).unwrap();
        std::fs::remove_file(&path).unwrap();
        assert_eq!(parsed.id, "inv-1");
        assert_eq!(
            store::decode_key(&parsed.daemon_public_key).unwrap(),
            [9_u8; 32]
        );
        assert_eq!(parsed.secret_bytes().unwrap(), [7_u8; 32]);
    }

    #[test]
    fn wss_has_a_tls_provider() {
        ensure_tls_provider();
        // tokio-tungstenite builds its client config this way; it panics
        // when rustls has no crypto provider.
        let _ = rustls::ClientConfig::builder()
            .with_root_certificates(rustls::RootCertStore::empty())
            .with_no_client_auth();
    }

    #[test]
    fn reconnect_policy_is_valid_and_bounded() {
        let policy = reconnect_policy();
        policy.validate().unwrap();
        assert!(policy.maximum_duration.is_some());
    }
}
