//! `RemoteLink`: the `PtyLink` of a remote pane (a Mac terminal over relay
//! v2). GPUI-free; the window (Task 13b) and `--smoke` use the same code.
//!
//! - `write` sends ONE `send` message per call through the current view
//!   (`shellx_remote::AttachmentInput`), so a composed IME commit leaves as
//!   one UTF-8 write. Without a view (connecting, reconnecting, offline,
//!   ended) input is dropped, never queued.
//! - `resize` records the pane's grid (used for the next attach) and reports
//!   it to the Mac when it changed; the Mac answers with `Resized` +
//!   `Snapshot`.
//! - `is_closed` is true once the remote terminal really ended (the pane
//!   then closes through the tabs model).
//!
//! The link outlives reconnects: `RemoteSession` installs a fresh view after
//! every (re)attach and clears it when the connection drops. A pump thread
//! per view turns `AttachEvent`s into `PaneEvent`s for the pane's sink; the
//! UI thread applies them to a `RemoteMirror` (a mirror `TermCore` that never
//! answers terminal queries: the Mac's terminal host already does).
// Wired into the window by Task 13b; `--smoke` and tests use it today.
#![allow(dead_code)]

use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::mpsc::Receiver;
use std::sync::{Arc, Mutex};

use anyhow::Result;
use shellx_model::paste::remote_paste_fits;
use shellx_remote::{AttachEvent, AttachmentInput};

use crate::term_core::{PtyLink, TermCore};

/// The input half of one attached view.
pub trait ViewInput: Send + Sync {
    fn write(&self, bytes: &[u8]) -> Result<()>;
    fn resize(&self, cols: u16, rows: u16) -> Result<()>;
}

impl ViewInput for AttachmentInput {
    fn write(&self, bytes: &[u8]) -> Result<()> {
        AttachmentInput::write(self, bytes)
    }
    fn resize(&self, cols: u16, rows: u16) -> Result<()> {
        AttachmentInput::resize(self, cols, rows)
    }
}

/// What a remote pane's UI applies (in order) to its `RemoteMirror`.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum PaneEvent {
    /// The Mac's grid is now `cols` x `rows`: start a fresh mirror; a
    /// `Snapshot` follows.
    Reset { cols: u16, rows: u16 },
    /// VT replay of the current screen; feed into the fresh mirror.
    Snapshot(Vec<u8>),
    /// Live output.
    Output(Vec<u8>),
    /// The session status changed: re-read `RemoteSession::status()`.
    Status,
    /// The pane now shows this terminal (first attach, or another one after
    /// the Mac restarted); update `PaneTarget::Remote::terminal_id`.
    Retargeted { terminal_id: String },
    /// The remote terminal ended: close this pane.
    Ended,
}

/// Delivers a pane's events to its UI; `false` means the UI is gone.
pub type PaneSink = Arc<dyn Fn(PaneEvent) -> bool + Send + Sync>;

struct Inner {
    /// (generation, view) of the attached view, if any.
    view: Option<(u64, Arc<dyn ViewInput>)>,
    /// The pane's grid as last requested by the UI.
    size: (u16, u16),
    next_gen: u64,
}

pub struct RemoteLink {
    inner: Mutex<Inner>,
    ended: AtomicBool,
}

impl RemoteLink {
    pub fn new(cols: u16, rows: u16) -> Arc<RemoteLink> {
        Arc::new(RemoteLink {
            inner: Mutex::new(Inner {
                view: None,
                size: (cols.max(2), rows.max(1)),
                next_gen: 1,
            }),
            ended: AtomicBool::new(false),
        })
    }

    fn lock(&self) -> std::sync::MutexGuard<'_, Inner> {
        self.inner
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner())
    }

    /// Input reaches the Mac only while a view is attached and the terminal
    /// has not ended. The UI shows `Str::InputPaused` when this is false.
    pub fn accepts_input(&self) -> bool {
        !self.ended.load(Ordering::Acquire) && self.lock().view.is_some()
    }

    /// The pane's grid (cols, rows) as last requested by the UI.
    pub fn size(&self) -> (u16, u16) {
        self.lock().size
    }

    /// Install a freshly attached view (attached at `attached_size`); returns
    /// its generation. A resize the UI made meanwhile is sent now.
    pub(crate) fn install(&self, view: Arc<dyn ViewInput>, attached_size: (u16, u16)) -> u64 {
        let (view_gen, size) = {
            let mut inner = self.lock();
            let view_gen = inner.next_gen;
            inner.next_gen += 1;
            inner.view = Some((view_gen, view.clone()));
            (view_gen, inner.size)
        };
        if size != attached_size {
            let _ = view.resize(size.0, size.1);
        }
        view_gen
    }

    /// Drop the current view (connection lost, pane closing). Dropping the
    /// last handle of an `AttachmentInput` closes the view on the Mac.
    pub(crate) fn clear_view(&self) {
        let view = self.lock().view.take();
        drop(view);
    }

    pub(crate) fn current_gen(&self) -> Option<u64> {
        self.lock().view.as_ref().map(|(view_gen, _)| *view_gen)
    }

    pub(crate) fn mark_ended(&self) {
        self.ended.store(true, Ordering::Release);
        self.clear_view();
    }

    fn view(&self) -> Option<Arc<dyn ViewInput>> {
        if self.ended.load(Ordering::Acquire) {
            return None;
        }
        self.lock().view.as_ref().map(|(_, view)| view.clone())
    }
}

impl PtyLink for RemoteLink {
    fn write(&self, bytes: &[u8]) {
        if bytes.is_empty() {
            return;
        }
        // Not attached: refused (dropped), never queued for later.
        if let Some(view) = self.view() {
            let _ = view.write(bytes);
        }
    }

    fn resize(&self, cols: u16, rows: u16, _cell_w_px: u32, _cell_h_px: u32) -> Result<()> {
        let size = (cols.max(2), rows.max(1));
        let view = {
            let mut inner = self.lock();
            if inner.size == size {
                // Also breaks a loop when the Mac keeps another grid: the
                // mirror is reset to its size, the UI asks again, nothing
                // new is sent.
                return Ok(());
            }
            inner.size = size;
            inner.view.as_ref().map(|(_, view)| view.clone())
        };
        if let Some(view) = view {
            // Not connected: the next attach uses the recorded size.
            let _ = view.resize(size.0, size.1);
        }
        Ok(())
    }

    fn is_closed(&self) -> bool {
        self.ended.load(Ordering::Acquire)
    }
}

/// Why a view's pump stopped.
#[derive(Clone, Debug, PartialEq, Eq)]
pub(crate) enum PumpEnd {
    /// The daemon detached the view (the surface exited, or the daemon is
    /// stopping). `saw_snapshot`: this view delivered a snapshot first.
    Ended { saw_snapshot: bool },
    /// The connection failed or the stream overflowed.
    Disconnected(String),
    /// The event channel hung up (client dropped) or the UI is gone.
    HungUp,
    /// The link has another view now; this one is obsolete.
    Stale,
}

/// Forward one view's events to the pane until it stops. Blocking: run it on
/// its own thread and drain promptly (the channel is unbounded).
pub(crate) fn pump(
    events: &Receiver<AttachEvent>,
    link: &RemoteLink,
    view_gen: u64,
    sink: &PaneSink,
) -> PumpEnd {
    let mut saw_snapshot = false;
    loop {
        let Ok(event) = events.recv() else {
            return PumpEnd::HungUp;
        };
        if link.current_gen() != Some(view_gen) {
            return PumpEnd::Stale;
        }
        let forwarded = match event {
            AttachEvent::Resized { cols, rows } => sink(PaneEvent::Reset { cols, rows }),
            AttachEvent::Snapshot(bytes) => {
                saw_snapshot = true;
                sink(PaneEvent::Snapshot(bytes))
            }
            AttachEvent::Output(bytes) => sink(PaneEvent::Output(bytes)),
            AttachEvent::Ended => return PumpEnd::Ended { saw_snapshot },
            AttachEvent::Disconnected(reason) => return PumpEnd::Disconnected(reason),
        };
        if !forwarded {
            return PumpEnd::HungUp;
        }
    }
}

/// What applying a `PaneEvent` did, for the UI.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Applied {
    Reset,
    Fed { newline: bool },
    Status,
    Retargeted(String),
    Ended,
}

/// What `RemoteMirror::paste` did.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Paste {
    Sent,
    /// Not attached: show `Str::InputPaused`.
    Refused,
    /// Over `REMOTE_PASTE_MAX_BYTES`: show `Str::PasteTooLarge`.
    TooLarge,
}

/// UI-thread state of a remote pane: a mirror `TermCore` over the pane's
/// `RemoteLink`, replaced on every `Reset`.
pub struct RemoteMirror {
    link: Arc<RemoteLink>,
    core: TermCore,
}

impl RemoteMirror {
    /// A blank mirror at the link's grid until the first snapshot arrives.
    pub fn new(link: Arc<RemoteLink>) -> Result<RemoteMirror> {
        let (cols, rows) = link.size();
        let core = TermCore::new_mirror(link.clone(), cols, rows)?;
        Ok(RemoteMirror { link, core })
    }

    pub fn core(&mut self) -> &mut TermCore {
        &mut self.core
    }

    pub fn link(&self) -> &Arc<RemoteLink> {
        &self.link
    }

    pub fn apply(&mut self, event: PaneEvent) -> Result<Applied> {
        Ok(match event {
            PaneEvent::Reset { cols, rows } => {
                self.core = TermCore::new_mirror(self.link.clone(), cols, rows)?;
                Applied::Reset
            }
            PaneEvent::Snapshot(bytes) | PaneEvent::Output(bytes) => {
                self.core.feed(&bytes);
                Applied::Fed {
                    newline: bytes.contains(&b'\n'),
                }
            }
            PaneEvent::Status => Applied::Status,
            PaneEvent::Retargeted { terminal_id } => Applied::Retargeted(terminal_id),
            PaneEvent::Ended => Applied::Ended,
        })
    }

    /// Clipboard text as data (`TermCore::paste`), refused whole while not
    /// attached (`Str::InputPaused`) or when its encoded size is over
    /// `REMOTE_PASTE_MAX_BYTES` (`Str::PasteTooLarge`; one relay send above
    /// ~12 MB fails). Never cut, never queued.
    pub fn paste(&mut self, text: &str) -> Paste {
        if !self.link.accepts_input() {
            return Paste::Refused;
        }
        let bytes = self.core.encode_paste(text);
        if !remote_paste_fits(bytes.len()) {
            return Paste::TooLarge;
        }
        self.core.write_paste(&bytes);
        Paste::Sent
    }

    /// Committed text (typing, IME commit): one write while connected.
    /// Returns false when the input was refused (show `Str::InputPaused`);
    /// refused text is dropped, not queued.
    pub fn send_text(&mut self, text: &str) -> bool {
        if !self.link.accepts_input() {
            return false;
        }
        self.core.send_text(text);
        true
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[derive(Default)]
    pub(crate) struct RecView {
        writes: Mutex<Vec<Vec<u8>>>,
        resizes: Mutex<Vec<(u16, u16)>>,
    }

    impl ViewInput for RecView {
        fn write(&self, bytes: &[u8]) -> Result<()> {
            self.writes.lock().unwrap().push(bytes.to_vec());
            Ok(())
        }
        fn resize(&self, cols: u16, rows: u16) -> Result<()> {
            self.resizes.lock().unwrap().push((cols, rows));
            Ok(())
        }
    }

    const TIENG_VIET: [u8; 14] = [
        0x74, 0x69, 0xe1, 0xba, 0xbf, 0x6e, 0x67, 0x20, 0x56, 0x69, 0xe1, 0xbb, 0x87, 0x74,
    ];

    #[test]
    fn remote_commit_sends_composed_utf8() {
        let link = RemoteLink::new(80, 24);
        let view = Arc::new(RecView::default());
        link.install(view.clone(), (80, 24));
        let mut mirror = RemoteMirror::new(link.clone()).unwrap();
        assert!(mirror.send_text("tiếng Việt"));
        let writes = view.writes.lock().unwrap().clone();
        assert_eq!(writes, vec![TIENG_VIET.to_vec()]);
    }

    #[test]
    fn input_while_reconnecting_is_refused_not_queued() {
        let link = RemoteLink::new(80, 24);
        let old = Arc::new(RecView::default());
        link.install(old.clone(), (80, 24));
        link.clear_view(); // the connection dropped: Reconnecting
        let mut mirror = RemoteMirror::new(link.clone()).unwrap();
        assert!(!link.accepts_input());
        assert!(!mirror.send_text("tiếng Việt"));
        mirror.core().send_text("x"); // the TermCore path is gated too
        assert!(mirror.core().send_chord("enter"));
        assert!(old.writes.lock().unwrap().is_empty());
        // reattached: nothing queued arrives, new input does
        let new = Arc::new(RecView::default());
        link.install(new.clone(), (80, 24));
        assert!(mirror.send_text("a"));
        assert_eq!(new.writes.lock().unwrap().clone(), vec![b"a".to_vec()]);
    }

    #[test]
    fn remote_paste_over_8_mib_is_refused_whole() {
        use shellx_model::paste::REMOTE_PASTE_MAX_BYTES;
        let link = RemoteLink::new(80, 24);
        let view = Arc::new(RecView::default());
        link.install(view.clone(), (80, 24));
        let mut mirror = RemoteMirror::new(link.clone()).unwrap();
        // at the cap (not bracketed: no markers): one write
        let fits = "a".repeat(REMOTE_PASTE_MAX_BYTES);
        assert_eq!(mirror.paste(&fits), Paste::Sent);
        assert_eq!(view.writes.lock().unwrap().len(), 1);
        assert_eq!(view.writes.lock().unwrap()[0].len(), REMOTE_PASTE_MAX_BYTES);
        // one byte over: nothing at all is sent (never a cut paste)
        let over = "a".repeat(REMOTE_PASTE_MAX_BYTES + 1);
        assert_eq!(mirror.paste(&over), Paste::TooLarge);
        // bracketed: the markers count, so the cap-sized text is too large
        mirror
            .apply(PaneEvent::Output(b"\x1b[?2004h".to_vec()))
            .unwrap();
        assert!(mirror.core().bracketed_paste());
        assert_eq!(mirror.paste(&fits), Paste::TooLarge);
        assert_eq!(view.writes.lock().unwrap().len(), 1);
        // a small paste still goes, bracketed, in one write
        assert_eq!(mirror.paste("ls\n"), Paste::Sent);
        assert_eq!(
            view.writes.lock().unwrap()[1],
            b"\x1b[200~ls\r\x1b[201~".to_vec()
        );
        // not attached: refused before any size check, nothing sent
        link.clear_view();
        assert_eq!(mirror.paste("ls"), Paste::Refused);
        assert_eq!(mirror.paste(&over), Paste::Refused);
        assert_eq!(view.writes.lock().unwrap().len(), 2);
    }

    #[test]
    fn mirror_never_answers_queries() {
        let link = RemoteLink::new(80, 24);
        let view = Arc::new(RecView::default());
        link.install(view.clone(), (80, 24));
        let mut mirror = RemoteMirror::new(link).unwrap();
        mirror
            .apply(PaneEvent::Output(b"\x1b[6n\x1b[c".to_vec()))
            .unwrap();
        assert!(view.writes.lock().unwrap().is_empty());
    }

    #[test]
    fn reset_snapshot_output_build_the_screen() {
        let link = RemoteLink::new(80, 24);
        let mut mirror = RemoteMirror::new(link).unwrap();
        assert_eq!(
            mirror
                .apply(PaneEvent::Reset {
                    cols: 100,
                    rows: 30
                })
                .unwrap(),
            Applied::Reset
        );
        assert_eq!(mirror.core().size(), (100, 30));
        mirror
            .apply(PaneEvent::Snapshot(b"hello\r\n".to_vec()))
            .unwrap();
        mirror
            .apply(PaneEvent::Output("tiếng Việt".as_bytes().to_vec()))
            .unwrap();
        let lines = mirror.core().text_lines().unwrap();
        assert!(lines[0].starts_with("hello"), "{lines:?}");
        assert!(lines[1].starts_with("tiếng Việt"), "{lines:?}");
    }

    #[test]
    fn resize_is_recorded_deduplicated_and_sent_on_install() {
        let link = RemoteLink::new(80, 24);
        link.resize(120, 40, 8, 16).unwrap(); // not attached: only recorded
        assert_eq!(link.size(), (120, 40));
        let view = Arc::new(RecView::default());
        link.install(view.clone(), (80, 24)); // attached at the old size
        assert_eq!(view.resizes.lock().unwrap().clone(), vec![(120, 40)]);
        link.resize(120, 40, 8, 16).unwrap();
        link.resize(100, 30, 8, 16).unwrap();
        assert_eq!(
            view.resizes.lock().unwrap().clone(),
            vec![(120, 40), (100, 30)]
        );
    }

    #[test]
    fn pump_forwards_in_order_and_reports_the_end() {
        let link = RemoteLink::new(80, 24);
        let view_gen = link.install(Arc::new(RecView::default()), (80, 24));
        let (tx, rx) = std::sync::mpsc::channel();
        let seen = Arc::new(Mutex::new(Vec::new()));
        let sink: PaneSink = {
            let seen = seen.clone();
            Arc::new(move |event| {
                seen.lock().unwrap().push(event);
                true
            })
        };
        tx.send(AttachEvent::Resized { cols: 90, rows: 20 })
            .unwrap();
        tx.send(AttachEvent::Snapshot(b"s".to_vec())).unwrap();
        tx.send(AttachEvent::Output(b"o".to_vec())).unwrap();
        tx.send(AttachEvent::Ended).unwrap();
        assert_eq!(
            pump(&rx, &link, view_gen, &sink),
            PumpEnd::Ended { saw_snapshot: true }
        );
        assert_eq!(
            seen.lock().unwrap().clone(),
            vec![
                PaneEvent::Reset { cols: 90, rows: 20 },
                PaneEvent::Snapshot(b"s".to_vec()),
                PaneEvent::Output(b"o".to_vec()),
            ]
        );
        tx.send(AttachEvent::Disconnected("x".into())).unwrap();
        assert_eq!(
            pump(&rx, &link, view_gen, &sink),
            PumpEnd::Disconnected("x".into())
        );
        // a replaced view's late output never reaches the pane
        link.install(Arc::new(RecView::default()), (80, 24));
        tx.send(AttachEvent::Output(b"late".to_vec())).unwrap();
        assert_eq!(pump(&rx, &link, view_gen, &sink), PumpEnd::Stale);
        drop(tx);
        let view_gen = link.current_gen().unwrap();
        assert_eq!(pump(&rx, &link, view_gen, &sink), PumpEnd::HungUp);
    }

    #[test]
    fn ended_link_is_closed_and_refuses_input() {
        let link = RemoteLink::new(80, 24);
        let view = Arc::new(RecView::default());
        link.install(view.clone(), (80, 24));
        link.mark_ended();
        assert!(link.is_closed());
        assert!(!link.accepts_input());
        PtyLink::write(&*link, b"x");
        assert!(view.writes.lock().unwrap().is_empty());
    }
}
