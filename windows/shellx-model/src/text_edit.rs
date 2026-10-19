//! Single-line text buffer behind the app's text field (`ui/text_field.rs`):
//! content, selection, IME marked range (preedit), UTF-16 <-> UTF-8 offsets
//! for the platform input handler, and the masked (password) display.
//! The editing rules follow GPUI's `examples/input.rs` (Apache-2.0), moved
//! here so they are tested without GPUI.
//!
//! Offsets are UTF-8 byte offsets into the content unless a name says
//! `utf16` or `display`. Boundaries are chars, with zero-width chars
//! (combining marks, e.g. a decomposed Vietnamese tone mark) kept with the
//! char before them, so Backspace removes "ế" typed as e + ̂ + ́ whole.

use std::ops::Range;

use crate::selection::char_cells;

/// What the masked field draws per char.
pub const MASK_CHAR: char = '•';

/// Bytes a masked field reserves up front, so a typed password normally
/// never reallocates (a reallocation leaves the old copy in freed memory).
const MASKED_RESERVE: usize = 128;

/// `Debug` is written by hand: a masked field prints `***` and its length,
/// never its content or preedit.
#[derive(Clone, Default, PartialEq, Eq)]
pub struct TextEdit {
    content: String,
    selected: Range<usize>,
    reversed: bool,
    marked: Option<Range<usize>>,
    masked: bool,
}

/// Newlines, tabs and other control chars never enter a single-line field.
fn clean(text: &str) -> String {
    text.chars()
        .map(|c| {
            if c == '\n' || c == '\r' || c == '\t' {
                ' '
            } else {
                c
            }
        })
        .filter(|c| !c.is_control())
        .collect()
}

impl std::fmt::Debug for TextEdit {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        let mut d = f.debug_struct("TextEdit");
        if self.masked {
            d.field(
                "content",
                &format_args!("*** ({} bytes)", self.content.len()),
            );
        } else {
            d.field("content", &self.content);
        }
        d.field("selected", &self.selected)
            .field("reversed", &self.reversed)
            .field("marked", &self.marked)
            .field("masked", &self.masked)
            .finish()
    }
}

/// Overwrites the whole allocation with zeros (the live bytes and the spare
/// capacity, where Backspace / Delete / a mid-line edit left the bytes they
/// shifted away), then empties the string; the allocation is kept (and
/// reused), so the old text does not linger in freed memory.
fn wipe(s: &mut String) {
    let mut bytes = zeroed_allocation(s);
    bytes.clear();
    *s = String::from_utf8(bytes).unwrap_or_default();
}

/// Takes `s`'s allocation and zeroes all of it: returned with its length
/// set to its capacity (every byte initialized to 0), `s` left empty.
fn zeroed_allocation(s: &mut String) -> Vec<u8> {
    let mut bytes = std::mem::take(s).into_bytes();
    let cap = bytes.capacity();
    bytes.fill(0);
    // Zero the spare capacity too; within the capacity, so no reallocation.
    bytes.resize(cap, 0);
    // Keep the zeroing from being optimized away as a dead store.
    std::hint::black_box(&mut bytes);
    bytes
}

/// A masked field wipes its buffer when it goes away.
impl Drop for TextEdit {
    fn drop(&mut self) {
        if self.masked {
            wipe(&mut self.content);
        }
    }
}

fn is_attached(c: char) -> bool {
    !c.is_control() && char_cells(c) == 0
}

impl TextEdit {
    pub fn new(masked: bool) -> TextEdit {
        TextEdit {
            content: if masked {
                String::with_capacity(MASKED_RESERVE)
            } else {
                String::new()
            },
            selected: 0..0,
            reversed: false,
            marked: None,
            masked,
        }
    }

    /// Bytes allocated for the content.
    pub fn capacity(&self) -> usize {
        self.content.capacity()
    }

    pub fn text(&self) -> &str {
        &self.content
    }

    pub fn is_empty(&self) -> bool {
        self.content.is_empty()
    }

    pub fn masked(&self) -> bool {
        self.masked
    }

    pub fn selected_range(&self) -> Range<usize> {
        self.selected.clone()
    }

    pub fn reversed(&self) -> bool {
        self.reversed
    }

    pub fn marked_range(&self) -> Option<Range<usize>> {
        self.marked.clone()
    }

    pub fn cursor(&self) -> usize {
        if self.reversed {
            self.selected.start
        } else {
            self.selected.end
        }
    }

    /// Clears everything (after a submit, and when the sign-in panel
    /// closes, the password field is emptied). The content is zeroed in
    /// place first.
    pub fn clear(&mut self) {
        wipe(&mut self.content);
        self.selected = 0..0;
        self.reversed = false;
        self.marked = None;
    }

    pub fn set_text(&mut self, text: &str) {
        let mut text = clean(text);
        wipe(&mut self.content);
        self.content.push_str(&text);
        wipe(&mut text);
        let end = self.content.len();
        self.selected = end..end;
        self.reversed = false;
        self.marked = None;
    }

    // ---- movement --------------------------------------------------------

    pub fn move_to(&mut self, offset: usize) {
        let offset = self.clamp(offset);
        self.selected = offset..offset;
        self.reversed = false;
    }

    pub fn select_to(&mut self, offset: usize) {
        let offset = self.clamp(offset);
        if self.reversed {
            self.selected.start = offset;
        } else {
            self.selected.end = offset;
        }
        if self.selected.end < self.selected.start {
            self.reversed = !self.reversed;
            self.selected = self.selected.end..self.selected.start;
        }
    }

    pub fn select_all(&mut self) {
        self.move_to(0);
        self.select_to(self.content.len());
    }

    pub fn left(&mut self) {
        if self.selected.is_empty() {
            self.move_to(self.previous_boundary(self.cursor()));
        } else {
            self.move_to(self.selected.start);
        }
    }

    pub fn right(&mut self) {
        if self.selected.is_empty() {
            self.move_to(self.next_boundary(self.selected.end));
        } else {
            self.move_to(self.selected.end);
        }
    }

    pub fn select_left(&mut self) {
        self.select_to(self.previous_boundary(self.cursor()));
    }

    pub fn select_right(&mut self) {
        self.select_to(self.next_boundary(self.cursor()));
    }

    pub fn home(&mut self) {
        self.move_to(0);
    }

    pub fn end(&mut self) {
        self.move_to(self.content.len());
    }

    pub fn backspace(&mut self) {
        if self.selected.is_empty() {
            self.select_to(self.previous_boundary(self.cursor()));
        }
        self.replace_selection("");
    }

    pub fn delete(&mut self) {
        if self.selected.is_empty() {
            self.select_to(self.next_boundary(self.cursor()));
        }
        self.replace_selection("");
    }

    /// Text for Copy/Cut: the selection, never anything from a masked field.
    pub fn copy_text(&self) -> Option<String> {
        if self.masked || self.selected.is_empty() {
            return None;
        }
        Some(self.content[self.selected.clone()].to_string())
    }

    /// Cut: the copied text, and the selection removed.
    pub fn cut(&mut self) -> Option<String> {
        let text = self.copy_text()?;
        self.replace_selection("");
        Some(text)
    }

    /// Paste or typed text at the selection (no IME range involved).
    pub fn insert(&mut self, text: &str) {
        self.replace_selection(text);
    }

    fn replace_selection(&mut self, text: &str) {
        let range = self.selected.clone();
        self.splice(range, text);
        self.marked = None;
    }

    fn splice(&mut self, range: Range<usize>, text: &str) -> usize {
        let mut text = clean(text);
        self.content.replace_range(range.clone(), &text);
        let end = range.start + text.len();
        // The cleaned copy of typed or pasted text is not left behind.
        wipe(&mut text);
        self.selected = end..end;
        self.reversed = false;
        end
    }

    // ---- input handler (IME) ---------------------------------------------

    fn target(&self, range_utf16: Option<Range<usize>>) -> Range<usize> {
        range_utf16
            .map(|r| self.range_from_utf16(&r))
            .or(self.marked.clone())
            .unwrap_or(self.selected.clone())
    }

    /// `replace_text_in_range`: commits text (WM_CHAR, IME result). An empty
    /// replacement with no range and no preedit is a no-op: the Japanese IME
    /// sends one when a composition is cancelled, and it must not delete a
    /// selection.
    pub fn replace_text_in_range(&mut self, range_utf16: Option<Range<usize>>, text: &str) {
        if text.is_empty() && range_utf16.is_none() && self.marked.is_none() {
            return;
        }
        let range = self.target(range_utf16);
        self.splice(range, text);
        self.marked = None;
    }

    /// `replace_and_mark_text_in_range`: the IME preedit. `selected_utf16` is
    /// the caret inside the new preedit.
    pub fn replace_and_mark_text_in_range(
        &mut self,
        range_utf16: Option<Range<usize>>,
        text: &str,
        selected_utf16: Option<Range<usize>>,
    ) {
        let range = self.target(range_utf16);
        let text = clean(text);
        self.content.replace_range(range.clone(), &text);
        self.marked = (!text.is_empty()).then(|| range.start..range.start + text.len());
        let in_preedit = |utf16: usize| -> usize {
            let mut count = 0;
            let mut bytes = 0;
            for c in text.chars() {
                if count >= utf16 {
                    break;
                }
                count += c.len_utf16();
                bytes += c.len_utf8();
            }
            range.start + bytes
        };
        self.selected = match selected_utf16 {
            Some(sel) => in_preedit(sel.start)..in_preedit(sel.end),
            None => {
                let end = range.start + text.len();
                end..end
            }
        };
        self.reversed = false;
    }

    pub fn unmark(&mut self) {
        self.marked = None;
    }

    // ---- offsets ---------------------------------------------------------

    fn clamp(&self, offset: usize) -> usize {
        let mut offset = offset.min(self.content.len());
        while !self.content.is_char_boundary(offset) {
            offset -= 1;
        }
        offset
    }

    pub fn previous_boundary(&self, offset: usize) -> usize {
        let mut chars = self.content[..self.clamp(offset)].char_indices().rev();
        for (ix, c) in chars.by_ref() {
            if !is_attached(c) {
                return ix;
            }
        }
        0
    }

    pub fn next_boundary(&self, offset: usize) -> usize {
        let start = self.clamp(offset);
        let mut iter = self.content[start..].char_indices();
        if iter.next().is_none() {
            return self.content.len();
        }
        for (ix, c) in iter {
            if !is_attached(c) {
                return start + ix;
            }
        }
        self.content.len()
    }

    pub fn offset_to_utf16(&self, offset: usize) -> usize {
        self.content[..self.clamp(offset)]
            .chars()
            .map(char::len_utf16)
            .sum()
    }

    pub fn offset_from_utf16(&self, utf16: usize) -> usize {
        let mut count = 0;
        for (ix, c) in self.content.char_indices() {
            if count >= utf16 {
                return ix;
            }
            count += c.len_utf16();
        }
        self.content.len()
    }

    pub fn range_to_utf16(&self, range: &Range<usize>) -> Range<usize> {
        self.offset_to_utf16(range.start)..self.offset_to_utf16(range.end)
    }

    pub fn range_from_utf16(&self, range: &Range<usize>) -> Range<usize> {
        self.offset_from_utf16(range.start)..self.offset_from_utf16(range.end)
    }

    /// `text_for_range` for the input handler: `None` for a masked field (the
    /// password is never handed to the IME).
    pub fn text_for_utf16_range(
        &self,
        range_utf16: &Range<usize>,
    ) -> Option<(String, Range<usize>)> {
        if self.masked {
            return None;
        }
        let range = self.range_from_utf16(range_utf16);
        let start = range.start.min(range.end);
        let text = self.content[start..range.end.max(start)].to_string();
        Some((text, self.range_to_utf16(&(start..range.end.max(start)))))
    }

    // ---- display ---------------------------------------------------------

    /// What the field draws: the content, or one `MASK_CHAR` per char.
    pub fn display_text(&self) -> String {
        if self.masked {
            self.content.chars().map(|_| MASK_CHAR).collect()
        } else {
            self.content.clone()
        }
    }

    /// Content offset -> offset in `display_text`.
    pub fn display_offset(&self, offset: usize) -> usize {
        if !self.masked {
            return self.clamp(offset);
        }
        self.content[..self.clamp(offset)].chars().count() * MASK_CHAR.len_utf8()
    }

    /// Offset in `display_text` (e.g. from a mouse x) -> content offset.
    pub fn content_offset(&self, display: usize) -> usize {
        if !self.masked {
            return self.clamp(display);
        }
        let n = display / MASK_CHAR.len_utf8();
        self.content
            .char_indices()
            .nth(n)
            .map_or(self.content.len(), |(ix, _)| ix)
    }

    pub fn display_range(&self, range: &Range<usize>) -> Range<usize> {
        self.display_offset(range.start)..self.display_offset(range.end)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn typed(s: &str) -> TextEdit {
        let mut t = TextEdit::new(false);
        for c in s.chars() {
            t.replace_text_in_range(None, &c.to_string());
        }
        t
    }

    #[test]
    fn typing_moving_and_deleting() {
        let mut t = typed("abc");
        assert_eq!((t.text(), t.cursor()), ("abc", 3));
        t.left();
        t.backspace();
        assert_eq!((t.text(), t.cursor()), ("ac", 1));
        t.delete();
        assert_eq!(t.text(), "a");
        t.home();
        t.insert("x");
        t.end();
        t.insert("y");
        assert_eq!(t.text(), "xay");
        t.select_all();
        assert_eq!(t.copy_text().as_deref(), Some("xay"));
        t.backspace();
        assert!(t.is_empty());
        // movement at the ends stays put
        t.left();
        t.backspace();
        t.delete();
        t.right();
        assert_eq!((t.text(), t.cursor()), ("", 0));
    }

    #[test]
    fn selection_extends_both_ways() {
        let mut t = typed("hello");
        t.select_left();
        t.select_left();
        assert_eq!(t.selected_range(), 3..5);
        assert!(t.reversed());
        t.right(); // collapses to the end
        assert_eq!(t.selected_range(), 5..5);
        t.move_to(2);
        t.select_right();
        t.select_right();
        assert_eq!(t.selected_range(), 2..4);
        assert_eq!(t.cut().as_deref(), Some("ll"));
        assert_eq!(t.text(), "heo");
    }

    #[test]
    fn vietnamese_precomposed_and_decomposed() {
        let mut t = typed("Việt");
        assert_eq!(t.text(), "Việt");
        t.backspace();
        t.backspace();
        assert_eq!(t.text(), "Vi");
        // e + combining circumflex + combining acute: one boundary step
        let mut d = TextEdit::new(false);
        d.insert("tie\u{0302}\u{0301}ng");
        d.move_to(d.text().len());
        d.left();
        d.left();
        assert_eq!(&d.text()[d.cursor()..], "ng");
        d.backspace();
        assert_eq!(d.text(), "ting");
        d.home();
        d.right();
        d.right();
        assert_eq!(d.cursor(), 2);
    }

    #[test]
    fn ime_preedit_then_commit_telex() {
        // Telex: "vieejt" -> preedit grows, then commits "việt" once
        let mut t = typed("tên ");
        for pre in ["v", "vi", "vie", "viê", "viêj", "việt"] {
            t.replace_and_mark_text_in_range(None, pre, None);
            let marked = t.marked_range().unwrap();
            assert_eq!(&t.text()[marked.clone()], pre);
            assert_eq!(t.cursor(), marked.end);
        }
        t.replace_text_in_range(None, "việt");
        assert_eq!(t.text(), "tên việt");
        assert_eq!(t.marked_range(), None);
        assert_eq!(t.cursor(), t.text().len());
    }

    #[test]
    fn ime_caret_inside_preedit_and_cancel() {
        let mut t = typed("ab");
        t.move_to(1);
        t.replace_and_mark_text_in_range(None, "かんじ", Some(1..1));
        assert_eq!(t.text(), "aかんじb");
        assert_eq!(t.marked_range(), Some(1..10));
        assert_eq!(t.cursor(), 1 + "か".len());
        // cancel: empty commit replaces the preedit
        t.replace_text_in_range(None, "");
        assert_eq!(t.text(), "ab");
        // an empty commit without a preedit leaves a selection alone
        t.select_all();
        t.replace_text_in_range(None, "");
        assert_eq!(t.text(), "ab");
        // an empty preedit clears the mark
        t.move_to(2);
        t.replace_and_mark_text_in_range(None, "x", None);
        t.replace_and_mark_text_in_range(None, "", None);
        assert_eq!((t.text(), t.marked_range()), ("ab", None));
    }

    #[test]
    fn utf16_offsets_round_trip() {
        let t = typed("aệ😀b");
        assert_eq!(t.offset_to_utf16(t.text().len()), 1 + 1 + 2 + 1);
        for (b, u) in [(0, 0), (1, 1), (4, 2), (8, 4), (9, 5)] {
            assert_eq!(t.offset_to_utf16(b), u);
            assert_eq!(t.offset_from_utf16(u), b);
        }
        assert_eq!(t.range_from_utf16(&(2..4)), 4..8);
        let (s, r) = t.text_for_utf16_range(&(1..4)).unwrap();
        assert_eq!((s.as_str(), r), ("ệ😀", 1..4));
        // replace a utf16 range
        let mut t = t;
        t.replace_text_in_range(Some(2..4), "x");
        assert_eq!(t.text(), "aệxb");
    }

    #[test]
    fn newlines_and_controls_are_cleaned() {
        let mut t = TextEdit::new(false);
        t.insert("a\r\nb\tc\u{7}d");
        assert_eq!(t.text(), "a  b cd");
        t.set_text("x\ny");
        assert_eq!((t.text(), t.cursor()), ("x y", 3));
    }

    #[test]
    fn masked_display_and_no_leaks() {
        let mut t = TextEdit::new(true);
        t.insert("pá😀");
        assert_eq!(t.display_text(), "•••");
        assert_eq!(t.display_offset(t.text().len()), 9);
        assert_eq!(t.display_offset(1), 3);
        assert_eq!(t.content_offset(3), 1);
        assert_eq!(t.content_offset(6), 3);
        assert_eq!(t.content_offset(9), t.text().len());
        assert_eq!(t.content_offset(100), t.text().len());
        t.select_all();
        assert_eq!(t.display_range(&t.selected_range()), 0..9);
        assert_eq!(t.copy_text(), None);
        assert_eq!(t.cut(), None);
        assert_eq!(t.text(), "pá😀");
        assert_eq!(t.text_for_utf16_range(&(0..2)), None);
        // the plain field maps 1:1
        let p = typed("ab");
        assert_eq!((p.display_offset(1), p.content_offset(1)), (1, 1));
        assert_eq!(p.display_text(), "ab");
        t.clear();
        assert!(t.is_empty() && t.masked());
    }

    #[test]
    fn masked_debug_shows_no_typed_char() {
        let mut t = TextEdit::new(true);
        // chars that never occur in the struct's own Debug skeleton
        t.insert("QJ#~");
        t.replace_and_mark_text_in_range(None, "ế", None);
        let dbg = format!("{t:?}");
        for c in "QJ#~ế".chars() {
            assert!(!dbg.contains(c), "{c:?} in {dbg}");
        }
        assert!(dbg.contains("***"), "{dbg}");
        // the plain field still shows its text
        assert!(format!("{:?}", typed("ab")).contains("\"ab\""));
    }

    // No test reads a String's spare capacity (that would read memory that
    // may be uninitialized): the zeroing is checked on the full-length Vec
    // `zeroed_allocation` returns, and `clear` / `set_text` / drop are
    // checked to go through it (same allocation, emptied).

    #[test]
    fn zeroed_allocation_zeroes_bytes_edited_away() {
        // Backspace-like truncation leaves "r2" in the spare capacity.
        let mut s = String::with_capacity(32);
        s.push_str("hunter2");
        s.truncate(5);
        let (ptr, cap) = (s.as_ptr(), s.capacity());
        let bytes = zeroed_allocation(&mut s);
        // the same allocation, all of it (live and spare bytes), now zero
        assert_eq!(bytes.as_ptr(), ptr);
        assert_eq!(bytes.len(), cap);
        assert_eq!(bytes.capacity(), cap);
        assert!(bytes.iter().all(|&b| b == 0), "{bytes:?}");
        assert!(s.is_empty() && s.capacity() == 0);
    }

    #[test]
    fn clear_zeroes_bytes_edited_away() {
        let mut t = TextEdit::new(true);
        t.insert("hunter2");
        let (ptr, cap) = (t.content.as_ptr(), t.capacity());
        t.backspace();
        t.backspace();
        assert_eq!(t.text(), "hunte");
        // Backspace only shortened the live text (the tail is in the spare
        // capacity until a wipe)
        assert_eq!((t.content.as_ptr(), t.capacity()), (ptr, cap));
        t.clear();
        // wiped in place through `zeroed_allocation`: same allocation, empty
        assert!(t.is_empty());
        assert_eq!((t.content.as_ptr(), t.capacity()), (ptr, cap));
        // mid-edit: a deletion in the middle shifts the tail left
        let mut t = TextEdit::new(true);
        t.insert("abcXYZ");
        t.move_to(1);
        t.delete();
        t.delete();
        assert_eq!(t.text(), "aXYZ");
        let ptr = t.content.as_ptr();
        t.clear();
        assert!(t.is_empty() && t.content.as_ptr() == ptr);
        // set_text replaces the content in the same (wiped) allocation
        let mut t = TextEdit::new(true);
        t.insert("oldsecret");
        let (ptr, cap) = (t.content.as_ptr(), t.capacity());
        t.set_text("new");
        assert_eq!(t.text(), "new");
        assert_eq!((t.content.as_ptr(), t.capacity()), (ptr, cap));
    }

    #[test]
    fn clear_wipes_and_keeps_the_buffer() {
        let mut t = TextEdit::new(true);
        t.insert("secret-password");
        let cap = t.capacity();
        t.clear();
        assert!(t.is_empty() && t.masked());
        assert_eq!(t.selected_range(), 0..0);
        // the same allocation is reused (it was zeroed, not freed with the
        // password in it)
        assert_eq!(t.capacity(), cap);
        t.insert("x");
        assert_eq!(t.text(), "x");
    }
}
