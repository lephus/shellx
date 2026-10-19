//! What a terminal pane does with IME input (GPUI-free, so the Mac tests
//! cover it): `TermView`'s `replace_text_in_range` (a commit: typed
//! characters, IME results, Unikey/EVKey injected text) and
//! `replace_and_mark_text_in_range` (a preedit update) call these with the
//! pane's backend as the `ImeTarget`.
//!
//! Rules: a preedit is only drawn, never sent; a commit is ONE write of the
//! whole committed string (never per keystroke), byte for byte (no Unicode
//! normalization), with control chars except Tab removed (Enter / Ctrl+C
//! reach the shell as chords, not as committed text); a remote pane that is
//! not attached refuses it (dropped, never queued; the caller flashes
//! `Str::InputPaused`).

// The window (cfg(windows)) is the user; the Mac build only tests it.
#![cfg_attr(not(windows), allow(dead_code))]

use std::ops::Range;

/// The pane's byte link, as the IME logic sees it.
pub trait ImeTarget {
    /// One write of committed text. False: refused (a remote pane that is
    /// not attached); the text is dropped.
    fn write_text(&mut self, text: &str) -> bool;
    /// Show the live screen (where the preedit is drawn).
    fn scroll_to_bottom(&mut self);
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Commit {
    /// Nothing was left to send (empty, or only control chars).
    Empty,
    /// Written (or there is no backend to write to).
    Sent,
    /// The target refused it: the caller flashes `Str::InputPaused`.
    Refused,
}

impl Commit {
    /// Committing text is typing: the caller drops the grid selection.
    pub fn clears_selection(self) -> bool {
        self != Commit::Empty
    }
}

/// Committed text as it is sent: control chars removed except Tab.
pub fn committed_text(text: &str) -> String {
    text.chars()
        .filter(|c| *c == '\t' || !c.is_control())
        .collect()
}

/// A commit: the preedit ends, then the cleaned text is written once.
pub fn commit(
    marked: &mut Option<String>,
    marked_selection: &mut Option<Range<usize>>,
    text: &str,
    target: &mut dyn ImeTarget,
) -> Commit {
    *marked = None;
    *marked_selection = None;
    let text = committed_text(text);
    if text.is_empty() {
        Commit::Empty
    } else if target.write_text(&text) {
        Commit::Sent
    } else {
        Commit::Refused
    }
}

/// A preedit update: stored for drawing, nothing is sent. An empty preedit
/// ends the composition. Returns true while composing (the caller drops the
/// grid selection: composing is typing).
pub fn update_preedit(
    marked: &mut Option<String>,
    marked_selection: &mut Option<Range<usize>>,
    new_text: &str,
    new_selected_range: Option<Range<usize>>,
    target: &mut dyn ImeTarget,
) -> bool {
    if new_text.is_empty() {
        *marked = None;
        *marked_selection = None;
        false
    } else {
        target.scroll_to_bottom();
        *marked = Some(new_text.to_string());
        *marked_selection = new_selected_range;
        true
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[derive(Default)]
    struct Rec {
        writes: Vec<Vec<u8>>,
        scrolls: usize,
        refuse: bool,
    }

    impl ImeTarget for Rec {
        fn write_text(&mut self, text: &str) -> bool {
            if self.refuse {
                return false;
            }
            self.writes.push(text.as_bytes().to_vec());
            true
        }
        fn scroll_to_bottom(&mut self) {
            self.scrolls += 1;
        }
    }

    const TIENG_VIET: [u8; 14] = [
        0x74, 0x69, 0xe1, 0xba, 0xbf, 0x6e, 0x67, 0x20, 0x56, 0x69, 0xe1, 0xbb, 0x87, 0x74,
    ];

    #[test]
    fn telex_preedit_then_one_commit_write() {
        let mut rec = Rec::default();
        let (mut marked, mut sel) = (None, None);
        // Telex: t i e e s n g -> the preedit grows, nothing is sent
        for (i, p) in ["t", "ti", "tie", "tiê", "tiế", "tiến", "tiếng"]
            .into_iter()
            .enumerate()
        {
            let len = p.encode_utf16().count();
            assert!(update_preedit(
                &mut marked,
                &mut sel,
                p,
                Some(len..len),
                &mut rec
            ));
            assert_eq!(marked.as_deref(), Some(p));
            assert_eq!(sel, Some(len..len));
            assert_eq!(rec.scrolls, i + 1);
        }
        assert!(rec.writes.is_empty(), "a preedit is never sent");
        let done = commit(&mut marked, &mut sel, "tiếng Việt", &mut rec);
        assert_eq!(done, Commit::Sent);
        assert!(done.clears_selection());
        assert_eq!(rec.writes, vec![TIENG_VIET.to_vec()]);
        assert_eq!((marked, sel), (None, None));
    }

    #[test]
    fn empty_preedit_ends_the_composition_without_sending() {
        let mut rec = Rec::default();
        let (mut marked, mut sel) = (Some("tiê".to_string()), Some(3..3));
        assert!(!update_preedit(&mut marked, &mut sel, "", None, &mut rec));
        assert_eq!((marked, sel), (None, None));
        assert_eq!((rec.writes.len(), rec.scrolls), (0, 0));
    }

    #[test]
    fn nfd_commit_is_sent_unnormalized() {
        let mut rec = Rec::default();
        let (mut marked, mut sel) = (None, None);
        let nfd = "tie\u{302}\u{301}ng";
        assert_eq!(commit(&mut marked, &mut sel, nfd, &mut rec), Commit::Sent);
        assert_eq!(rec.writes, vec![nfd.as_bytes().to_vec()]);
        assert_eq!(
            rec.writes[0],
            [0x74, 0x69, 0x65, 0xcc, 0x82, 0xcc, 0x81, 0x6e, 0x67]
        );
    }

    #[test]
    fn control_chars_are_dropped_but_tab_is_kept() {
        let mut rec = Rec::default();
        let (mut marked, mut sel) = (None, None);
        assert_eq!(
            commit(&mut marked, &mut sel, "a\rb\nc\x03d\te", &mut rec),
            Commit::Sent
        );
        assert_eq!(rec.writes, vec![b"abcd\te".to_vec()]);
        // only control chars: nothing is written, the selection stays
        for text in ["\r", "\n", "\x03", ""] {
            let done = commit(&mut marked, &mut sel, text, &mut rec);
            assert_eq!(done, Commit::Empty, "{text:?}");
            assert!(!done.clears_selection());
        }
        assert_eq!(rec.writes.len(), 1);
        assert_eq!(commit(&mut marked, &mut sel, "\t", &mut rec), Commit::Sent);
        assert_eq!(rec.writes[1], b"\t".to_vec());
    }

    #[test]
    fn refused_remote_writes_nothing_and_says_refused() {
        let mut rec = Rec {
            refuse: true,
            ..Rec::default()
        };
        let (mut marked, mut sel) = (Some("Việ".to_string()), Some(3..3));
        let done = commit(&mut marked, &mut sel, "tiếng Việt", &mut rec);
        assert_eq!(done, Commit::Refused);
        assert!(done.clears_selection());
        assert!(rec.writes.is_empty());
        // the preedit ends even when the commit is refused
        assert_eq!((marked, sel), (None, None));
        // an empty commit on a refused pane is not a refusal (no flash)
        assert_eq!(commit(&mut None, &mut None, "\r", &mut rec), Commit::Empty);
    }
}
