//! ShellX file in an upstream crate; see
//! docs/superpowers/plans/2026-10-19-native-desktop-w2-mac-remote.md Task 7.
//!
//! A "virtual PTY" whose far end is a libghostty terminal owned by the ShellX
//! macOS app (ported from the W0 bridge spike, `shellx/w0-bridge` @
//! `4e1ed7bc41`). The Mux keeps its usual `PtyRuntime::Local` surface and
//! `ghostty-vt` mirror; only the PTY is replaced. Output comes from the app's
//! PTY tee, input goes back into the app's real PTY, and the real grid size is
//! pushed by the app (the Mac owns the PTY, so it is the sizing host).
//!
//! Frame: `[type u8][len u32 BE][payload]`, payload at most 16 MiB, one
//! Unix-socket connection per terminal. Types:
//! daemon -> app `H` hello JSON `{"protocol":1,"cols","rows","cwd"}`, `I`
//! input bytes, `R` resize wish (cols,rows u16 BE), `K` kill;
//! app -> daemon `A` ack JSON `{"surface_id","workspace_id","mode"}` (`mode` is
//! `attach` or `create`), `O` output bytes, `S` real grid (cols,rows u16 BE),
//! `E` exit. Every `S` after the handshake resizes the mirror, even when the
//! grid did not change (the app's forced echo after a remote resize). `E` or
//! end of stream ends the child.
//!
//! Enabled when the daemon runs with `CMUX_SHELLX_BRIDGE_SOCKET=<path>`: every
//! default-shell terminal it creates becomes a Mac terminal. The socket's
//! directory must be a real directory owned by this user with no group or
//! other permission bits; anything else is refused before connecting.

use std::io::{self, Read, Write};
use std::os::unix::fs::MetadataExt;
use std::os::unix::net::UnixStream;
use std::path::{Path, PathBuf};
use std::sync::{Arc, Condvar, Mutex};
use std::time::{Duration, Instant};

use cmux_pty::{Child, ChildKiller, ExitStatus, MasterPty, PtySize, SpawnedPty};

pub(crate) const BRIDGE_SOCKET_ENV: &str = "CMUX_SHELLX_BRIDGE_SOCKET";

/// Version carried in the hello frame.
const PROTOCOL: u32 = 1;
/// Largest payload either side may send in one frame.
const MAX_FRAME: usize = 16 * 1024 * 1024;

const HELLO: u8 = b'H';
const INPUT: u8 = b'I';
const RESIZE: u8 = b'R';
const KILL: u8 = b'K';
const ACK: u8 = b'A';
const OUTPUT: u8 = b'O';
const SIZE: u8 = b'S';
const EXIT: u8 = b'E';

pub(crate) struct VirtualPtySpec {
    socket: PathBuf,
}

/// Default-shell terminals become virtual when the bridge socket is set.
/// Terminals with an explicit command still run locally in the daemon.
pub(crate) fn spec_for(command: Option<&Vec<String>>) -> Option<VirtualPtySpec> {
    if command.is_some_and(|argv| !argv.is_empty()) {
        return None;
    }
    let socket = std::env::var_os(BRIDGE_SOCKET_ENV)?;
    if socket.is_empty() {
        return None;
    }
    Some(VirtualPtySpec { socket: socket.into() })
}

type HostSizeHandler = Box<dyn Fn(u16, u16) + Send + Sync>;

/// Where app `S` frames go after the handshake: the surface's handler once it
/// is installed. A report that arrives before that is kept and replayed on
/// install, so the mirror never stays at a grid the Mac already left.
#[derive(Default)]
struct HostSizeSink {
    handler: Option<HostSizeHandler>,
    missed: Option<(u16, u16)>,
}

struct Shared {
    writer: Mutex<UnixStream>,
    size: Mutex<PtySize>,
    /// Last real grid the app reported. A Mux resize to exactly this size is
    /// the echo of our own host-size apply and is not sent back.
    host_size: Mutex<Option<(u16, u16)>>,
    on_host_size: Mutex<HostSizeSink>,
    exited: Mutex<bool>,
    exited_cv: Condvar,
    /// The app's ack (`surface_id`, `workspace_id`, `mode`); read by tests.
    #[cfg_attr(not(test), allow(dead_code))]
    ack: serde_json::Value,
}

impl Shared {
    fn send(&self, kind: u8, payload: &[u8]) -> io::Result<()> {
        write_frame(&mut self.writer.lock().unwrap(), kind, payload)
    }

    fn mark_exited(&self) {
        *self.exited.lock().unwrap() = true;
        self.exited_cv.notify_all();
    }
}

/// Handle surface.rs keeps to route app-reported sizes into the Mux surface.
pub(crate) struct VirtualPtyHandle {
    shared: Arc<Shared>,
}

impl VirtualPtyHandle {
    pub(crate) fn initial_size(&self) -> Option<(u16, u16)> {
        *self.shared.host_size.lock().unwrap()
    }

    #[cfg(test)]
    pub(crate) fn ack(&self) -> &serde_json::Value {
        &self.shared.ack
    }

    /// Installs the host-size callback (the Mac's real PTY grid changed, or
    /// the Mac re-sent it after a remote resize). A report that arrived since
    /// `open` returned is delivered first, under the same lock the demux
    /// thread uses, so reports reach the handler in order.
    pub(crate) fn set_host_size_handler(&self, handler: HostSizeHandler) {
        let mut sink = self.shared.on_host_size.lock().unwrap();
        if let Some((cols, rows)) = sink.missed.take() {
            handler(cols, rows);
        }
        sink.handler = Some(handler);
    }
}

fn write_frame(stream: &mut UnixStream, kind: u8, payload: &[u8]) -> io::Result<()> {
    if payload.len() > MAX_FRAME {
        return Err(io::Error::new(io::ErrorKind::InvalidInput, "shellx bridge: frame too large"));
    }
    let mut frame = Vec::with_capacity(payload.len() + 5);
    frame.push(kind);
    frame.extend_from_slice(&(payload.len() as u32).to_be_bytes());
    frame.extend_from_slice(payload);
    stream.write_all(&frame)
}

fn read_frame(stream: &mut UnixStream) -> io::Result<(u8, Vec<u8>)> {
    let mut header = [0u8; 5];
    stream.read_exact(&mut header)?;
    let len = u32::from_be_bytes([header[1], header[2], header[3], header[4]]) as usize;
    if len > MAX_FRAME {
        return Err(io::Error::new(
            io::ErrorKind::InvalidData,
            format!("shellx bridge: frame too large ({len} bytes)"),
        ));
    }
    let mut payload = vec![0u8; len];
    stream.read_exact(&mut payload)?;
    Ok((header[0], payload))
}

fn parse_size(payload: &[u8]) -> Option<(u16, u16)> {
    match payload {
        [c0, c1, r0, r1] => Some((u16::from_be_bytes([*c0, *c1]), u16::from_be_bytes([*r0, *r1]))),
        _ => None,
    }
}

/// Refuses a socket whose directory another user could have planted or could
/// swap: it must be a real directory (not a symlink), owned by the effective
/// user, with no group or other permission bits.
fn check_socket_dir(socket: &Path) -> anyhow::Result<()> {
    let dir = match socket.parent() {
        Some(parent) if !parent.as_os_str().is_empty() => parent,
        _ => Path::new("."),
    };
    let metadata = std::fs::symlink_metadata(dir).map_err(|error| {
        anyhow::anyhow!("shellx bridge: socket directory {}: {error}", dir.display())
    })?;
    let problem = if metadata.file_type().is_symlink() {
        Some("is a symlink")
    } else if !metadata.is_dir() {
        Some("is not a directory")
    } else if metadata.uid() != unsafe { libc::geteuid() } {
        Some("is not owned by this user")
    } else if metadata.mode() & 0o077 != 0 {
        Some("is accessible to group or others")
    } else {
        None
    };
    match problem {
        Some(problem) => {
            anyhow::bail!("shellx bridge: insecure socket directory {} ({problem})", dir.display())
        }
        None => Ok(()),
    }
}

/// Connects to the app, binds (or creates) one Mac terminal and returns a
/// master/child pair the surface code uses exactly like a real PTY.
pub(crate) fn open(
    spec: &VirtualPtySpec,
    size: PtySize,
    cwd: Option<&str>,
) -> anyhow::Result<(SpawnedPty, VirtualPtyHandle)> {
    check_socket_dir(&spec.socket)?;
    let mut stream = UnixStream::connect(&spec.socket).map_err(|error| {
        anyhow::anyhow!("shellx bridge: connect {}: {error}", spec.socket.display())
    })?;
    let hello = serde_json::json!({
        "protocol": PROTOCOL,
        "cols": size.cols,
        "rows": size.rows,
        "cwd": cwd,
    });
    write_frame(&mut stream, HELLO, &serde_json::to_vec(&hello)?)?;
    // The app answers with A (bound surface), then S (its real grid), then
    // the screen snapshot as O frames.
    stream.set_read_timeout(Some(Duration::from_secs(10)))?;
    let (kind, payload) = read_frame(&mut stream)?;
    if kind != ACK {
        anyhow::bail!("shellx bridge: app refused the terminal (frame {:?})", kind as char);
    }
    let ack: serde_json::Value = serde_json::from_slice(&payload)
        .map_err(|error| anyhow::anyhow!("shellx bridge: malformed ack: {error}"))?;
    let mut host_size = None;
    let mut early_output = Vec::new();
    let deadline = Instant::now() + Duration::from_secs(2);
    stream.set_read_timeout(Some(Duration::from_millis(200)))?;
    while host_size.is_none() && Instant::now() < deadline {
        match read_frame(&mut stream) {
            Ok((SIZE, payload)) => host_size = parse_size(&payload),
            Ok((OUTPUT, payload)) => early_output.extend_from_slice(&payload),
            Ok((EXIT, _)) => anyhow::bail!("shellx bridge: app ended the terminal during setup"),
            Ok(_) => {}
            Err(error)
                if matches!(error.kind(), io::ErrorKind::WouldBlock | io::ErrorKind::TimedOut) => {}
            Err(error) => return Err(error.into()),
        }
    }
    stream.set_read_timeout(None)?;

    let (reader, mut pipe_writer) = UnixStream::pair()?;
    let initial = host_size.map(|(cols, rows)| PtySize { cols, rows, ..size }).unwrap_or(size);
    let shared = Arc::new(Shared {
        writer: Mutex::new(stream.try_clone()?),
        size: Mutex::new(initial),
        host_size: Mutex::new(host_size),
        on_host_size: Mutex::new(HostSizeSink::default()),
        exited: Mutex::new(false),
        exited_cv: Condvar::new(),
        ack,
    });
    std::thread::Builder::new().name("shellx-bridge-demux".into()).spawn({
        let shared = shared.clone();
        let mut stream = stream;
        move || {
            // Output from the handshake goes first, and from this thread: the
            // mirror's reader starts only after `open` returns, and the pipe
            // holds a few KB, so writing it in `open` could block forever.
            let mut alive = pipe_writer.write_all(&early_output).is_ok();
            drop(early_output);
            while alive {
                match read_frame(&mut stream) {
                    Ok((OUTPUT, payload)) => alive = pipe_writer.write_all(&payload).is_ok(),
                    Ok((SIZE, payload)) => {
                        let Some((cols, rows)) = parse_size(&payload) else { continue };
                        *shared.host_size.lock().unwrap() = Some((cols, rows));
                        let mut sink = shared.on_host_size.lock().unwrap();
                        match sink.handler.as_ref() {
                            Some(handler) => handler(cols, rows),
                            None => sink.missed = Some((cols, rows)),
                        }
                    }
                    Ok((EXIT, _)) | Err(_) => alive = false,
                    Ok(_) => {}
                }
            }
            drop(pipe_writer);
            shared.mark_exited();
        }
    })?;

    let master = VirtualMaster { shared: shared.clone(), reader };
    let child = VirtualChild { shared: shared.clone() };
    Ok((
        SpawnedPty { master: Box::new(master), child: Box::new(child) },
        VirtualPtyHandle { shared },
    ))
}

struct VirtualMaster {
    shared: Arc<Shared>,
    reader: UnixStream,
}

impl MasterPty for VirtualMaster {
    fn resize(&self, size: PtySize) -> Result<(), anyhow::Error> {
        *self.shared.size.lock().unwrap() = size;
        if *self.shared.host_size.lock().unwrap() == Some((size.cols, size.rows)) {
            return Ok(());
        }
        let mut payload = Vec::with_capacity(4);
        payload.extend_from_slice(&size.cols.to_be_bytes());
        payload.extend_from_slice(&size.rows.to_be_bytes());
        self.shared.send(RESIZE, &payload)?;
        Ok(())
    }

    fn get_size(&self) -> Result<PtySize, anyhow::Error> {
        Ok(*self.shared.size.lock().unwrap())
    }

    fn try_clone_reader(&self) -> Result<Box<dyn Read + Send>, anyhow::Error> {
        Ok(Box::new(self.reader.try_clone()?))
    }

    fn take_writer(&self) -> Result<Box<dyn Write + Send>, anyhow::Error> {
        Ok(Box::new(VirtualWriter { shared: self.shared.clone() }))
    }

    fn process_group_leader(&self) -> Option<libc::pid_t> {
        None
    }

    fn as_raw_fd(&self) -> Option<std::os::fd::RawFd> {
        None
    }

    fn tty_name(&self) -> Option<PathBuf> {
        None
    }
}

struct VirtualWriter {
    shared: Arc<Shared>,
}

impl Write for VirtualWriter {
    /// Sends at most one capped frame; `write_all` loops over larger input.
    fn write(&mut self, buf: &[u8]) -> io::Result<usize> {
        if buf.is_empty() {
            return Ok(0);
        }
        let chunk = &buf[..buf.len().min(MAX_FRAME)];
        self.shared.send(INPUT, chunk)?;
        Ok(chunk.len())
    }

    fn flush(&mut self) -> io::Result<()> {
        Ok(())
    }
}

#[derive(Clone)]
struct VirtualChild {
    shared: Arc<Shared>,
}

impl std::fmt::Debug for VirtualChild {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("VirtualChild").finish()
    }
}

impl ChildKiller for VirtualChild {
    /// Tells the app to unbind the terminal, then hangs up; the demux thread
    /// sees the end of stream and marks the child exited.
    fn kill(&mut self) -> io::Result<()> {
        let _ = self.shared.send(KILL, &[]);
        let _ = self.shared.writer.lock().unwrap().shutdown(std::net::Shutdown::Both);
        Ok(())
    }

    fn clone_killer(&self) -> Box<dyn ChildKiller + Send + Sync> {
        Box::new(self.clone())
    }
}

impl Child for VirtualChild {
    fn try_wait(&mut self) -> io::Result<Option<ExitStatus>> {
        Ok((*self.shared.exited.lock().unwrap()).then_some(ExitStatus::with_exit_code(0)))
    }

    fn wait(&mut self) -> io::Result<ExitStatus> {
        let mut exited = self.shared.exited.lock().unwrap();
        while !*exited {
            exited = self.shared.exited_cv.wait(exited).unwrap();
        }
        Ok(ExitStatus::with_exit_code(0))
    }

    fn process_id(&self) -> Option<u32> {
        None
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::os::unix::fs::PermissionsExt;
    use std::os::unix::net::UnixListener;
    use std::sync::mpsc;
    use std::thread::JoinHandle;

    const SIZE_80X24: PtySize = PtySize { cols: 80, rows: 24, pixel_width: 0, pixel_height: 0 };
    const WAIT: Duration = Duration::from_secs(10);

    fn frame(kind: u8, payload: &[u8]) -> Vec<u8> {
        let mut out = vec![kind];
        out.extend_from_slice(&(payload.len() as u32).to_be_bytes());
        out.extend_from_slice(payload);
        out
    }

    fn size_frame(cols: u16, rows: u16) -> Vec<u8> {
        let mut payload = cols.to_be_bytes().to_vec();
        payload.extend_from_slice(&rows.to_be_bytes());
        frame(SIZE, &payload)
    }

    /// A per-test socket directory, owner-only unless a test says otherwise.
    struct SocketDir(PathBuf);

    impl SocketDir {
        fn new(name: &str) -> Self {
            Self::with_mode(name, 0o700)
        }

        fn with_mode(name: &str, mode: u32) -> Self {
            let dir = std::env::temp_dir().join(format!("vpty-{}-{name}", std::process::id()));
            let _ = std::fs::remove_dir_all(&dir);
            std::fs::create_dir_all(&dir).unwrap();
            std::fs::set_permissions(&dir, std::fs::Permissions::from_mode(mode)).unwrap();
            Self(dir)
        }

        fn socket(&self) -> PathBuf {
            self.0.join("b.sock")
        }

        fn spec(&self) -> VirtualPtySpec {
            VirtualPtySpec { socket: self.socket() }
        }
    }

    impl Drop for SocketDir {
        fn drop(&mut self) {
            let _ = std::fs::remove_dir_all(&self.0);
        }
    }

    /// A fake app on `dir`: accepts one terminal, acks it, reports `grid` as
    /// its real size, then hands the connection and the hello to `script`.
    fn fake_app<T: Send + 'static>(
        dir: &SocketDir,
        grid: (u16, u16),
        script: impl FnOnce(&mut UnixStream, serde_json::Value) -> T + Send + 'static,
    ) -> JoinHandle<T> {
        let listener = UnixListener::bind(dir.socket()).unwrap();
        std::thread::spawn(move || {
            let (mut conn, _) = listener.accept().unwrap();
            let (kind, hello) = read_frame(&mut conn).unwrap();
            assert_eq!(kind, HELLO);
            let hello: serde_json::Value = serde_json::from_slice(&hello).unwrap();
            conn.write_all(&frame(
                ACK,
                br#"{"surface_id":"x","workspace_id":"w","mode":"attach"}"#,
            ))
            .unwrap();
            conn.write_all(&size_frame(grid.0, grid.1)).unwrap();
            script(&mut conn, hello)
        })
    }

    /// Reads one input frame and expects it to be `go` (the test's cue).
    fn wait_for_cue(conn: &mut UnixStream) {
        loop {
            match read_frame(conn) {
                Ok((INPUT, bytes)) => {
                    assert_eq!(bytes, b"go");
                    return;
                }
                Ok(_) => {}
                Err(error) => panic!("app lost the daemon before the cue: {error}"),
            }
        }
    }

    /// Runs a blocking call off the test thread so a broken bridge fails the
    /// test instead of hanging it.
    fn within<T: Send + 'static>(what: &str, f: impl FnOnce() -> T + Send + 'static) -> T {
        let (tx, rx) = mpsc::channel();
        std::thread::spawn(move || {
            let _ = tx.send(f());
        });
        rx.recv_timeout(WAIT).unwrap_or_else(|_| panic!("timed out: {what}"))
    }

    fn read_exactly(mut reader: Box<dyn Read + Send>, len: usize) -> Vec<u8> {
        within("reader", move || {
            let mut got = vec![0u8; len];
            reader.read_exact(&mut got).unwrap();
            got
        })
    }

    /// A fake app acks, reports a 100x30 grid, sends recorded output, then
    /// echoes every input frame back as output.
    #[test]
    fn virtual_pty_round_trips_output_input_and_sizes() {
        let dir = SocketDir::new("roundtrip");
        let app = fake_app(&dir, (100, 30), |conn, _| {
            conn.write_all(&frame(OUTPUT, b"\x1b[31mred\x1b[0m\r\n")).unwrap();
            let mut seen_resize = None;
            loop {
                match read_frame(conn) {
                    Ok((INPUT, bytes)) => conn.write_all(&frame(OUTPUT, &bytes)).unwrap(),
                    Ok((RESIZE, size)) => seen_resize = parse_size(&size),
                    Ok((KILL, _)) | Err(_) => break,
                    Ok(_) => {}
                }
            }
            seen_resize
        });
        let (spawned, handle) = open(&dir.spec(), SIZE_80X24, None).unwrap();
        assert_eq!(handle.initial_size(), Some((100, 30)));
        assert_eq!(handle.ack()["mode"], "attach");
        let mut reader = spawned.master.try_clone_reader().unwrap();
        let mut writer = spawned.master.take_writer().unwrap();
        let mut got = vec![0u8; 64];
        let n = reader.read(&mut got).unwrap();
        assert_eq!(&got[..n], b"\x1b[31mred\x1b[0m\r\n");
        writer.write_all(b"ls\r").unwrap();
        let n = reader.read(&mut got).unwrap();
        assert_eq!(&got[..n], b"ls\r");
        // An echo of the host size is not sent back; a real wish is.
        spawned.master.resize(PtySize { cols: 100, rows: 30, ..SIZE_80X24 }).unwrap();
        spawned.master.resize(PtySize { cols: 60, rows: 20, ..SIZE_80X24 }).unwrap();
        assert_eq!(spawned.master.get_size().unwrap().cols, 60);
        let mut child = spawned.child;
        child.kill().unwrap();
        assert_eq!(app.join().unwrap(), Some((60, 20)));
        assert!(child.wait().unwrap().success());
    }

    /// Review Focus 4: composed Vietnamese reaches the Mac PTY byte for byte.
    #[test]
    fn virtual_pty_forwards_vietnamese_utf8_unchanged() {
        let dir = SocketDir::new("vi-input");
        let app = fake_app(&dir, (80, 24), |conn, _| {
            let mut input = Vec::new();
            while input.len() < 15 {
                match read_frame(conn) {
                    Ok((INPUT, bytes)) => input.extend_from_slice(&bytes),
                    Ok(_) => {}
                    Err(_) => break,
                }
            }
            input
        });
        let (spawned, _handle) = open(&dir.spec(), SIZE_80X24, None).unwrap();
        let mut writer = spawned.master.take_writer().unwrap();
        writer.write_all("tiếng Việt\r".as_bytes()).unwrap();
        let app_received_input = app.join().unwrap();
        assert_eq!(
            app_received_input,
            vec![
                0x74, 0x69, 0xe1, 0xba, 0xbf, 0x6e, 0x67, 0x20, 0x56, 0x69, 0xe1, 0xbb, 0x87, 0x74,
                0x0d
            ]
        );
    }

    /// A tee chunk boundary inside a UTF-8 character must not reorder or drop
    /// bytes. The first half arrives before the size report (buffered during
    /// the handshake), the second after it (the demux thread).
    #[test]
    fn split_utf8_output_reaches_reader_in_order() {
        let dir = SocketDir::new("vi-output");
        let listener = UnixListener::bind(dir.socket()).unwrap();
        let app = std::thread::spawn(move || {
            let (mut conn, _) = listener.accept().unwrap();
            let (kind, _) = read_frame(&mut conn).unwrap();
            assert_eq!(kind, HELLO);
            conn.write_all(&frame(ACK, br#"{"surface_id":"x","mode":"attach"}"#)).unwrap();
            conn.write_all(&frame(OUTPUT, b"Vi\xe1\xbb")).unwrap();
            conn.write_all(&size_frame(80, 24)).unwrap();
            conn.write_all(&frame(OUTPUT, b"\x87t")).unwrap();
            // Keep the connection open until the daemon hangs up.
            while read_frame(&mut conn).is_ok() {}
        });
        let (spawned, _handle) = open(&dir.spec(), SIZE_80X24, None).unwrap();
        let reader = spawned.master.try_clone_reader().unwrap();
        assert_eq!(read_exactly(reader, 6), "Việt".as_bytes());
        let mut child = spawned.child;
        child.kill().unwrap();
        app.join().unwrap();
    }

    /// A screen snapshot far larger than the in-process pipe's buffer can
    /// arrive before the size report; `open` must still return, and every
    /// byte must reach the reader in order, before any later output.
    #[test]
    fn large_output_before_size_does_not_block_open() {
        const EARLY: usize = 96 * 1024;
        let dir = SocketDir::new("early-big");
        let listener = UnixListener::bind(dir.socket()).unwrap();
        let app = std::thread::spawn(move || {
            let (mut conn, _) = listener.accept().unwrap();
            let (kind, _) = read_frame(&mut conn).unwrap();
            assert_eq!(kind, HELLO);
            conn.write_all(&frame(ACK, br#"{"surface_id":"x","mode":"attach"}"#)).unwrap();
            let early: Vec<u8> = (0..EARLY).map(|i| b'a' + (i % 26) as u8).collect();
            for chunk in early.chunks(4096) {
                conn.write_all(&frame(OUTPUT, chunk)).unwrap();
            }
            conn.write_all(&size_frame(80, 24)).unwrap();
            conn.write_all(&frame(OUTPUT, b"<after>")).unwrap();
            while read_frame(&mut conn).is_ok() {}
        });
        let socket = dir.socket();
        let (reader, mut child) = within("open with large early output", move || {
            let (spawned, handle) = open(&VirtualPtySpec { socket }, SIZE_80X24, None).unwrap();
            assert_eq!(handle.initial_size(), Some((80, 24)));
            (spawned.master.try_clone_reader().unwrap(), spawned.child)
        });
        let got = read_exactly(reader, EARLY + 7);
        let expected: Vec<u8> = (0..EARLY).map(|i| b'a' + (i % 26) as u8).collect();
        assert!(got[..EARLY] == expected[..], "early output reordered or corrupted");
        assert_eq!(&got[EARLY..], b"<after>");
        child.kill().unwrap();
        app.join().unwrap();
    }

    /// The Mac re-sends its grid after every remote resize even when it did
    /// not change (the forced echo); each report must reach the mirror.
    #[test]
    fn forced_host_size_reaches_handler_even_if_unchanged() {
        let dir = SocketDir::new("forced");
        let app = fake_app(&dir, (44, 37), |conn, _| {
            wait_for_cue(conn);
            conn.write_all(&size_frame(44, 37)).unwrap();
            conn.write_all(&size_frame(44, 37)).unwrap();
            while read_frame(conn).is_ok() {}
        });
        let (spawned, handle) = open(&dir.spec(), SIZE_80X24, None).unwrap();
        assert_eq!(handle.initial_size(), Some((44, 37)));
        let (tx, rx) = mpsc::channel();
        handle.set_host_size_handler(Box::new(move |cols, rows| {
            let _ = tx.send((cols, rows));
        }));
        let mut writer = spawned.master.take_writer().unwrap();
        writer.write_all(b"go").unwrap();
        assert_eq!(rx.recv_timeout(WAIT).unwrap(), (44, 37));
        assert_eq!(rx.recv_timeout(WAIT).unwrap(), (44, 37));
        assert!(rx.recv_timeout(Duration::from_millis(200)).is_err());
        let mut child = spawned.child;
        child.kill().unwrap();
        app.join().unwrap();
    }

    /// A grid change the Mac reports before the surface installs its handler
    /// is replayed on install instead of being lost.
    #[test]
    fn host_size_reported_before_handler_is_replayed() {
        let dir = SocketDir::new("missed");
        let app = fake_app(&dir, (80, 24), |conn, _| {
            conn.write_all(&size_frame(90, 33)).unwrap();
            while read_frame(conn).is_ok() {}
        });
        let (spawned, handle) = open(&dir.spec(), SIZE_80X24, None).unwrap();
        let deadline = Instant::now() + WAIT;
        while handle.initial_size() != Some((90, 33)) {
            assert!(Instant::now() < deadline, "demux never saw the second grid");
            std::thread::sleep(Duration::from_millis(5));
        }
        let (tx, rx) = mpsc::channel();
        handle.set_host_size_handler(Box::new(move |cols, rows| {
            let _ = tx.send((cols, rows));
        }));
        assert_eq!(rx.recv_timeout(WAIT).unwrap(), (90, 33));
        assert!(rx.recv_timeout(Duration::from_millis(200)).is_err());
        let mut child = spawned.child;
        child.kill().unwrap();
        app.join().unwrap();
    }

    /// `E` alone ends the child, while the connection is still open.
    #[test]
    fn app_exit_frame_ends_child() {
        let dir = SocketDir::new("exit");
        let (done_tx, done_rx) = mpsc::channel::<()>();
        let app = fake_app(&dir, (80, 24), move |conn, _| {
            wait_for_cue(conn);
            conn.write_all(&frame(EXIT, &[])).unwrap();
            let _ = done_rx.recv_timeout(WAIT);
        });
        let (spawned, _handle) = open(&dir.spec(), SIZE_80X24, None).unwrap();
        let mut writer = spawned.master.take_writer().unwrap();
        let mut child = spawned.child;
        assert!(child.try_wait().unwrap().is_none());
        writer.write_all(b"go").unwrap();
        let mut child = within("child.wait after E", move || {
            assert!(child.wait().unwrap().success());
            child
        });
        assert!(child.try_wait().unwrap().is_some());
        // The mirror's reader sees end of stream too.
        let mut reader = spawned.master.try_clone_reader().unwrap();
        let n = within("reader EOF after E", move || reader.read(&mut [0u8; 8]).unwrap());
        assert_eq!(n, 0);
        done_tx.send(()).unwrap();
        app.join().unwrap();
    }

    /// The socket's directory must be owner-only and not a symlink; the
    /// daemon refuses before it connects, so nothing reaches the listener.
    #[test]
    fn refuses_socket_in_world_accessible_dir() {
        for mode in [0o777, 0o755, 0o750, 0o701] {
            let dir = SocketDir::with_mode(&format!("insecure-{mode:o}"), mode);
            let listener = UnixListener::bind(dir.socket()).unwrap();
            listener.set_nonblocking(true).unwrap();
            let error = open(&dir.spec(), SIZE_80X24, None).err().expect("insecure dir accepted");
            assert!(
                error.to_string().contains("shellx bridge: insecure socket directory"),
                "mode {mode:o}: {error}"
            );
            assert_eq!(
                listener.accept().unwrap_err().kind(),
                io::ErrorKind::WouldBlock,
                "mode {mode:o}: daemon connected anyway"
            );
        }

        let real = SocketDir::new("symlink-target");
        let _listener = UnixListener::bind(real.socket()).unwrap();
        let link = std::env::temp_dir().join(format!("vpty-{}-symlink", std::process::id()));
        let _ = std::fs::remove_file(&link);
        std::os::unix::fs::symlink(&real.0, &link).unwrap();
        let spec = VirtualPtySpec { socket: link.join("b.sock") };
        let error = open(&spec, SIZE_80X24, None).err().expect("symlinked dir accepted");
        let _ = std::fs::remove_file(&link);
        assert!(error.to_string().contains("shellx bridge: insecure socket directory"), "{error}");
    }

    #[test]
    fn hello_carries_protocol_1() {
        let dir = SocketDir::new("hello");
        let app = fake_app(&dir, (80, 24), |conn, hello| {
            while read_frame(conn).is_ok() {}
            hello
        });
        let (spawned, _handle) = open(&dir.spec(), SIZE_80X24, Some("/tmp/project")).unwrap();
        let mut child = spawned.child;
        child.kill().unwrap();
        let hello = app.join().unwrap();
        assert_eq!(hello["protocol"], 1);
        assert_eq!(hello["cols"], 80);
        assert_eq!(hello["rows"], 24);
        assert_eq!(hello["cwd"], "/tmp/project");
    }

    /// A frame header announcing more than the 16 MiB cap is refused before
    /// its payload is read or allocated.
    #[test]
    fn oversize_frame_is_rejected() {
        let dir = SocketDir::new("oversize");
        let listener = UnixListener::bind(dir.socket()).unwrap();
        let app = std::thread::spawn(move || {
            let (mut conn, _) = listener.accept().unwrap();
            let (kind, _) = read_frame(&mut conn).unwrap();
            assert_eq!(kind, HELLO);
            conn.write_all(&frame(ACK, br#"{"surface_id":"x","mode":"attach"}"#)).unwrap();
            let mut header = vec![OUTPUT];
            header.extend_from_slice(&(16u32 * 1024 * 1024 + 1).to_be_bytes());
            conn.write_all(&header).unwrap();
            while read_frame(&mut conn).is_ok() {}
        });
        let error = open(&dir.spec(), SIZE_80X24, None).err().expect("oversize frame accepted");
        assert!(error.to_string().contains("frame too large"), "{error}");
        app.join().unwrap();

        // The cap itself is a valid frame.
        let (mut a, mut b) = UnixStream::pair().unwrap();
        let payload = vec![b'x'; 16 * 1024 * 1024];
        let writer = std::thread::spawn(move || a.write_all(&frame(OUTPUT, &payload)).unwrap());
        let (kind, got) = read_frame(&mut b).unwrap();
        writer.join().unwrap();
        assert_eq!((kind, got.len()), (OUTPUT, 16 * 1024 * 1024));
    }
}
