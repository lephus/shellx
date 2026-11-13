//! `TermCore`: a libghostty-vt `Terminal` + `RenderState` + `KeyEncoder` over
//! a byte link. Local panes (ConPTY) and remote panes differ only in their
//! `PtyLink`; everything else (palette, input encoding, paste, resize) is
//! shared. No UI here, so `--smoke` and the window drive the same code.

use std::sync::Arc;

use anyhow::{Context as _, Result};
use ghostty_vt::{Callbacks, KeyEncoder, RenderFrame, RenderState, Rgb, Terminal};
use shellx_model::palette::Rgba;
use shellx_model::paste::encode_paste;
use shellx_model::selection::Viewport;
use shellx_model::theme_file::TermTheme;

pub const SCROLLBACK_BYTES: usize = 10 * 1024 * 1024;

/// The byte link under a terminal pane. `&self` everywhere so libghostty's
/// `on_pty_write` callback (DSR/DA replies) can hold an `Arc<dyn PtyLink>`.
pub trait PtyLink: Send + Sync {
    fn write(&self, bytes: &[u8]);
    fn resize(&self, cols: u16, rows: u16, cell_w_px: u32, cell_h_px: u32) -> Result<()>;
    fn is_closed(&self) -> bool;
}

pub fn rgb(c: Rgba) -> Rgb {
    Rgb {
        r: c.r,
        g: c.g,
        b: c.b,
    }
}

/// The theme a new terminal starts with: the window's active one (`ui::theme`); ShellX in a
/// build without the window.
fn starting_theme() -> TermTheme {
    #[cfg(any(windows, target_os = "macos"))]
    return crate::ui::theme::active().term;
    #[cfg(not(any(windows, target_os = "macos")))]
    shellx_model::theme_file::shellx()
}

pub struct TermCore {
    terminal: Terminal,
    render: RenderState,
    encoder: KeyEncoder,
    link: Arc<dyn PtyLink>,
    cols: u16,
    rows: u16,
}

impl TermCore {
    pub fn new(link: Arc<dyn PtyLink>, cols: u16, rows: u16) -> Result<TermCore> {
        TermCore::build(link, cols, rows, true)
    }

    /// A mirror of a remote terminal (Task 13): the Mac's terminal host
    /// already answers queries (DSR, DA, ...), so this one never writes
    /// replies; only user input goes over the link.
    pub fn new_mirror(link: Arc<dyn PtyLink>, cols: u16, rows: u16) -> Result<TermCore> {
        TermCore::build(link, cols, rows, false)
    }

    fn build(
        link: Arc<dyn PtyLink>,
        cols: u16,
        rows: u16,
        answer_queries: bool,
    ) -> Result<TermCore> {
        // Query replies (DSR, DA, ...) go straight back over the link. ConPTY
        // asks for the cursor position at startup and waits for the answer.
        let reply = link.clone();
        let callbacks = Callbacks {
            on_pty_write: if answer_queries {
                Some(Box::new(move |bytes: &[u8]| reply.write(bytes)))
            } else {
                None
            },
            ..Default::default()
        };
        let terminal = Terminal::new(cols, rows, SCROLLBACK_BYTES, callbacks)
            .context("failed to create libghostty-vt terminal")?;
        let render = RenderState::new().context("failed to create render state")?;
        let encoder = KeyEncoder::new().context("failed to create key encoder")?;
        let mut core = TermCore {
            terminal,
            render,
            encoder,
            link,
            cols,
            rows,
        };
        core.set_theme(&starting_theme());
        Ok(core)
    }

    pub fn size(&self) -> (u16, u16) {
        (self.cols, self.rows)
    }

    /// Feed link output into the VT parser.
    pub fn feed(&mut self, bytes: &[u8]) {
        self.terminal.vt_write(bytes);
    }

    /// Committed text (typed characters, IME results): ONE write of its UTF-8.
    pub fn send_text(&mut self, text: &str) {
        if text.is_empty() {
            return;
        }
        self.terminal.scroll_to_bottom();
        self.link.write(text.as_bytes());
    }

    /// Encode a key chord ("enter", "ctrl+c", "shift+tab", "alt+x", "up")
    /// with libghostty-vt's key encoder, honoring the terminal's current
    /// keyboard modes, and write it. Returns false when the chord is not
    /// encodable (the caller then lets the platform deliver it as text).
    pub fn send_chord(&mut self, chord: &str) -> bool {
        let Some(bytes) = self.encode_chord(chord) else {
            return false;
        };
        self.terminal.scroll_to_bottom();
        self.link.write(&bytes);
        true
    }

    pub fn encode_chord(&mut self, chord: &str) -> Option<Vec<u8>> {
        let input = ghostty_vt::key_input_from_chord(chord)?;
        self.encoder.sync_from_terminal(&self.terminal);
        let mut out = Vec::new();
        self.encoder.encode(&input, &mut out).ok()?;
        (!out.is_empty()).then_some(out)
    }

    /// Paste clipboard text as data: bracketed only while the app enabled
    /// mode 2004; embedded markers are stripped by `encode_paste`.
    pub fn paste(&mut self, text: &str) {
        let bytes = self.encode_paste(text);
        self.write_paste(&bytes);
    }

    /// `text` as `paste` would send it (for a caller that checks its size).
    pub fn encode_paste(&self, text: &str) -> Vec<u8> {
        encode_paste(text, self.bracketed_paste())
    }

    /// Writes an `encode_paste` result (nothing when empty).
    pub fn write_paste(&mut self, bytes: &[u8]) {
        if bytes.is_empty() {
            return;
        }
        self.terminal.scroll_to_bottom();
        self.link.write(bytes);
    }

    pub fn bracketed_paste(&self) -> bool {
        self.terminal.mode(2004, false)
    }

    /// Resize the VT grid, then the link. No-op when unchanged.
    pub fn resize(&mut self, cols: u16, rows: u16, cell_w_px: u32, cell_h_px: u32) -> Result<()> {
        let (cols, rows) = (cols.max(2), rows.max(1));
        if (cols, rows) == (self.cols, self.rows) {
            return Ok(());
        }
        self.terminal
            .resize(cols, rows, cell_w_px, cell_h_px)
            .context("VT resize failed")?;
        self.link.resize(cols, rows, cell_w_px, cell_h_px)?;
        self.cols = cols;
        self.rows = rows;
        Ok(())
    }

    pub fn scroll_lines(&mut self, delta: isize) {
        self.terminal.scroll_delta(delta);
    }

    /// A full-screen program (less, vim, htop) switched to the alternate
    /// screen: the wheel sends it arrow keys (`mouse::wheel_action`).
    pub fn alternate_screen(&self) -> bool {
        self.terminal.active_screen() == ghostty_vt::Screen::Alternate
    }

    /// The program enabled a mouse tracking mode (1000, 1002, 1003, ...).
    pub fn mouse_tracking(&self) -> bool {
        self.terminal.mouse_tracking()
    }

    pub fn vt_cols_rows(&self) -> (u16, u16) {
        (self.terminal.cols(), self.terminal.rows())
    }

    pub fn title(&self) -> Option<String> {
        self.terminal.title()
    }

    /// The last OSC 7 URL the shell wrote (`file://HOST/PATH`), if any
    /// (`crate::cwd::cwd_from_osc7` turns it into a path).
    pub fn pwd(&self) -> Option<String> {
        self.terminal.pwd()
    }

    pub fn frame(&mut self) -> Result<RenderFrame> {
        self.render
            .update(&mut self.terminal)
            .context("render update failed")?;
        Ok(self.render.build_frame()?)
    }

    pub fn text_lines(&mut self) -> Result<Vec<String>> {
        self.render
            .update(&mut self.terminal)
            .context("render update failed")?;
        Ok(self.render.text_lines()?)
    }

    /// Viewport selection text, `start`/`end` as (col, row), inclusive.
    /// libghostty walks the real cells, so wide (CJK) characters, combining
    /// marks and soft-wrapped rows come out right; rows join with `\n`.
    pub fn selection_text(&mut self, start: (u16, u16), end: (u16, u16)) -> Option<String> {
        self.terminal.selection_text(start, end)
    }

    /// Scrollbar geometry: the viewport within scrollback + screen.
    /// Selections live in viewport rows, so a change of the offset moves
    /// them (new output scrolling the screen, or the mouse wheel).
    pub fn viewport(&self) -> Option<Viewport> {
        self.terminal.scrollbar().map(|s| Viewport {
            total: s.total,
            offset: s.offset,
            len: s.len,
        })
    }

    pub fn scroll_to_bottom(&mut self) {
        self.terminal.scroll_to_bottom();
    }

    /// Cursor (col, row) in the active screen, also while the cursor is
    /// hidden; equals the viewport cell when not scrolled back.
    pub fn cursor_position(&self) -> Option<(u16, u16)> {
        self.terminal.cursor_position()
    }

    /// Default foreground, background and cursor, and the 16 palette slots, from `theme`; at any
    /// time, so a live terminal recolours on its next frame. Slots 16-255 keep Ghostty's, and a
    /// slot the program set itself (OSC 4) stays in effect.
    pub fn set_theme(&mut self, theme: &TermTheme) {
        self.terminal.set_default_colors(
            Some(rgb(theme.foreground)),
            Some(rgb(theme.background)),
            Some(rgb(theme.cursor)),
        );
        let mut overrides: [Option<Rgb>; 256] = [None; 256];
        for (slot, color) in overrides.iter_mut().zip(theme.ansi.iter()) {
            *slot = Some(rgb(*color));
        }
        self.terminal.set_default_palette(&overrides);
    }

    #[allow(dead_code)] // used by later tasks (selection copy, pane close)
    pub fn link_closed(&self) -> bool {
        self.link.is_closed()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use shellx_model::theme_file;
    use std::sync::Mutex;

    #[derive(Default)]
    struct FakeLink {
        writes: Mutex<Vec<Vec<u8>>>,
        resizes: Mutex<Vec<(u16, u16)>>,
    }

    impl PtyLink for FakeLink {
        fn write(&self, bytes: &[u8]) {
            self.writes.lock().unwrap().push(bytes.to_vec());
        }
        fn resize(&self, cols: u16, rows: u16, _: u32, _: u32) -> Result<()> {
            self.resizes.lock().unwrap().push((cols, rows));
            Ok(())
        }
        fn is_closed(&self) -> bool {
            false
        }
    }

    fn core() -> (TermCore, Arc<FakeLink>) {
        let link = Arc::new(FakeLink::default());
        (TermCore::new(link.clone(), 80, 24).unwrap(), link)
    }

    fn writes(link: &FakeLink) -> Vec<Vec<u8>> {
        link.writes.lock().unwrap().clone()
    }

    #[test]
    fn a_new_terminal_starts_with_the_active_theme() {
        // No test changes the process-wide theme, so it is the default: ShellX.
        let shellx = theme_file::shellx();
        let (mut t, _) = core();
        let frame = t.frame().unwrap();
        assert_eq!(
            frame.default_colors,
            (rgb(shellx.background), rgb(shellx.foreground))
        );
        assert_eq!(frame.cursor_color, Some(rgb(shellx.cursor)));
        for slot in 0..16u8 {
            assert_eq!(
                t.render.palette_color(slot),
                rgb(shellx.ansi[usize::from(slot)]),
                "slot {slot}"
            );
        }
    }

    #[test]
    fn set_theme_recolours_a_live_terminal() {
        let dracula = theme_file::ThemeSet::new(vec![]).get("Dracula").unwrap();
        let (mut t, _) = core();
        t.feed(b"\x1b[31mred\x1b[0m plain");
        let before = t.frame().unwrap();
        assert_eq!(
            before.styled_rows()[0][0].resolved_fg,
            Some(rgb(theme_file::shellx().ansi[1]))
        );
        t.set_theme(&dracula);
        let frame = t.frame().unwrap();
        assert_eq!(
            frame.default_colors,
            (rgb(dracula.background), rgb(dracula.foreground))
        );
        assert_eq!(frame.cursor_color, Some(rgb(dracula.cursor)));
        assert_eq!(
            frame.styled_rows()[0][0].resolved_fg,
            Some(rgb(dracula.ansi[1]))
        );
        for slot in 0..16u8 {
            assert_eq!(
                t.render.palette_color(slot),
                rgb(dracula.ansi[usize::from(slot)]),
                "slot {slot}"
            );
        }
        // The text stays; only its colours change.
        assert_eq!(t.text_lines().unwrap()[0].trim_end(), "red plain");
    }

    #[test]
    fn paste_is_bracketed_only_when_mode_2004_set() {
        let (mut t, link) = core();
        t.feed(b"\x1b[?2004h");
        assert!(t.bracketed_paste());
        t.paste("a\nb");
        assert_eq!(writes(&link), vec![b"\x1b[200~a\rb\x1b[201~".to_vec()]);
        t.feed(b"\x1b[?2004l");
        t.paste("a\nb");
        assert_eq!(writes(&link)[1], b"a\rb".to_vec());
        assert_eq!(writes(&link).len(), 2);
    }

    #[test]
    fn send_text_is_one_utf8_write() {
        let (mut t, link) = core();
        t.send_text("tiếng Việt");
        assert_eq!(
            writes(&link),
            vec![vec![
                0x74, 0x69, 0xe1, 0xba, 0xbf, 0x6e, 0x67, 0x20, 0x56, 0x69, 0xe1, 0xbb, 0x87, 0x74
            ]]
        );
    }

    #[test]
    fn pwd_is_the_last_osc7_url() {
        let (mut t, _) = core();
        assert_eq!(t.pwd(), None);
        t.feed(b"\x1b]7;file://PC/C:/Users/Admin\x1b\\");
        assert_eq!(t.pwd().as_deref(), Some("file://PC/C:/Users/Admin"));
        // Raw UTF-8 and spaces, as the PowerShell hook writes them.
        t.feed("\x1b]7;file://PC/C:/Tài liệu\x1b\\".as_bytes());
        assert_eq!(t.pwd().as_deref(), Some("file://PC/C:/Tài liệu"));
    }

    #[test]
    fn alternate_screen_and_mouse_tracking_follow_the_modes() {
        let (mut t, _) = core();
        assert!(!t.alternate_screen());
        assert!(!t.mouse_tracking());
        t.feed(b"\x1b[?1049h");
        assert!(t.alternate_screen());
        assert!(!t.mouse_tracking());
        t.feed(b"\x1b[?1000h");
        assert!(t.mouse_tracking());
        t.feed(b"\x1b[?1049l\x1b[?1000l");
        assert!(!t.alternate_screen());
        assert!(!t.mouse_tracking());
    }

    #[test]
    fn resize_reaches_link_once() {
        let (mut t, link) = core();
        t.resize(100, 30, 8, 16).unwrap();
        t.resize(100, 30, 8, 16).unwrap();
        assert_eq!(*link.resizes.lock().unwrap(), vec![(100, 30)]);
        assert_eq!(t.size(), (100, 30));
        assert_eq!(t.vt_cols_rows(), (100, 30));
        t.resize(0, 0, 8, 16).unwrap();
        assert_eq!(t.size(), (2, 1));
    }

    #[test]
    fn selection_text_wide_chars_and_rows() {
        let (mut t, _) = core();
        t.feed("ab漢字c\r\ntiếng Việt".as_bytes());
        // 漢 and 字 take two cells each: "ab漢字c" spans columns 0..=6.
        assert_eq!(t.selection_text((0, 0), (6, 0)).as_deref(), Some("ab漢字c"));
        let two = t.selection_text((2, 0), (4, 1)).unwrap();
        assert_eq!(shellx_model::selection::to_crlf(&two), "漢字c\r\ntiếng");
        assert_eq!(t.cursor_position(), Some((10, 1)));
        assert_eq!(t.viewport().map(|v| v.offset), Some(0));
    }

    #[test]
    fn viewport_offset_follows_output_and_wheel() {
        let offset = |t: &TermCore| t.viewport().unwrap().offset;
        let (mut t, _) = core();
        t.feed(b"top\r\n");
        let before = offset(&t);
        t.feed("x\r\n".repeat(30).as_bytes());
        let after = offset(&t);
        // 30 new lines on a 24-row screen: the content moved up by `after - before`.
        assert!(after > before, "{before} -> {after}");
        t.scroll_lines(-3);
        assert_eq!(offset(&t), after - 3);
        t.scroll_to_bottom();
        assert_eq!(offset(&t), after);
        assert_eq!(t.viewport().unwrap().len, 24);
    }

    #[test]
    fn ime_cell_is_the_live_cursor_while_scrolled_back() {
        use shellx_model::selection::{Cell, ime_cell};
        let (mut t, _) = core();
        t.feed("x\r\n".repeat(40).as_bytes());
        // Cursor mid-screen (row 10, col 4), so it stays visible scrolled back.
        t.feed(b"\x1b[11;5H");
        let live = t.cursor_position();
        assert_eq!(live, Some((4, 10)));
        let at_bottom = t.frame().unwrap().cursor.map(|c| (c.x, c.y));
        assert_eq!(at_bottom, live);
        t.scroll_lines(-5);
        // The viewport cursor moved 5 rows down; the IME cell must not.
        let viewport = t.frame().unwrap().cursor.map(|c| (c.x, c.y));
        assert_eq!(viewport, live.map(|(x, y)| (x, y + 5)));
        assert_eq!(t.cursor_position(), live);
        let (x, y) = live.unwrap();
        assert_eq!(
            ime_cell(t.cursor_position(), 24),
            Some(Cell { row: y, col: x })
        );
    }

    #[test]
    fn smoke_input_paths() {
        crate::smoke::input_paths().unwrap();
    }

    #[test]
    fn query_reply_goes_to_link() {
        let (mut t, link) = core();
        t.feed(b"\x1b[6n");
        let all: Vec<u8> = writes(&link).concat();
        assert!(all.starts_with(b"\x1b[") && all.ends_with(b"R"), "{all:?}");
    }
}
