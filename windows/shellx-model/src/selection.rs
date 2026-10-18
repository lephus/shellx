//! Grid selection in viewport coordinates, plus the GPUI-free geometry the
//! terminal pane needs for mouse selection and IME placement (tested here,
//! on the Mac, because the window itself only builds on Windows CI).

use std::ops::Range;

use crate::layout::Rect;

#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord)]
pub struct Cell {
    pub row: u16,
    pub col: u16,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Selection {
    anchor: Cell,
    head: Cell,
}

impl Selection {
    pub fn new(at: Cell) -> Selection {
        Selection {
            anchor: at,
            head: at,
        }
    }

    pub fn extend(&mut self, to: Cell) {
        self.head = to;
    }

    pub fn is_empty(&self) -> bool {
        self.anchor == self.head
    }

    /// Where the selection started (stays put while dragging / Shift+click).
    pub fn anchor(&self) -> Cell {
        self.anchor
    }

    pub fn head(&self) -> Cell {
        self.head
    }

    /// The same cells after the viewport content moved down by `delta` rows
    /// (negative: up, e.g. new output scrolled the screen). `None` once any
    /// selected row left the `rows`-high viewport: the selection is dropped
    /// rather than pointing at other text.
    pub fn shifted(&self, delta: i64, rows: u16) -> Option<Selection> {
        let shift = |c: Cell| -> Option<Cell> {
            let row = i64::from(c.row) + delta;
            (0..i64::from(rows)).contains(&row).then(|| Cell {
                row: row as u16,
                col: c.col,
            })
        };
        Some(Selection {
            anchor: shift(self.anchor)?,
            head: shift(self.head)?,
        })
    }

    pub fn ordered(&self) -> (Cell, Cell) {
        if self.anchor <= self.head {
            (self.anchor, self.head)
        } else {
            (self.head, self.anchor)
        }
    }

    /// Linear (stream) selection like Windows Terminal: `(row, start col, end col exclusive)`.
    /// First row runs from the start to end of line, middle rows are full,
    /// the last row runs to the end cell inclusive.
    pub fn spans(&self, cols: u16) -> Vec<(u16, u16, u16)> {
        let (s, e) = self.ordered();
        if s.row == e.row {
            return vec![(s.row, s.col, (e.col + 1).min(cols))];
        }
        let mut v = vec![(s.row, s.col, cols)];
        v.extend((s.row + 1..e.row).map(|r| (r, 0, cols)));
        v.push((e.row, 0, (e.col + 1).min(cols)));
        v
    }
}

/// Floor, clamped to the grid; negative (and NaN) goes to 0.
pub fn cell_at(x: f32, y: f32, cell_w: f32, cell_h: f32, cols: u16, rows: u16) -> Cell {
    let idx = |v: f32, size: f32, n: u16| -> u16 {
        let i = (v / size).floor();
        if i.is_nan() || i < 0.0 {
            0
        } else {
            (i.min(f32::from(n.saturating_sub(1)))) as u16
        }
    };
    Cell {
        row: idx(y, cell_h, rows),
        col: idx(x, cell_w, cols),
    }
}

/// `lines[row]` is indexed by char, one char per cell. Known limitation:
/// wide (CJK/emoji) characters occupy two cells but one char, so columns
/// after them are off by one.
pub fn selected_text(sel: &Selection, lines: &[String], cols: u16) -> String {
    sel.spans(cols)
        .into_iter()
        .map(|(row, start, end)| {
            let line = lines
                .get(usize::from(row))
                .map(String::as_str)
                .unwrap_or("");
            let s: String = line
                .chars()
                .skip(usize::from(start))
                .take(usize::from(end.saturating_sub(start)))
                .collect();
            s.trim_end_matches(' ').to_string()
        })
        .collect::<Vec<_>>()
        .join("\r\n")
}

/// A drag that started on the span `origin` (one cell for a click, the word
/// for a double-click, the line for a triple-click) and is now over the span
/// `over` (same granularity). The origin span always stays selected; the
/// selection grows from its far end toward the pointer.
pub fn drag_selection(origin: (Cell, Cell), over: (Cell, Cell)) -> Selection {
    let mut sel = if over.0 < origin.0 {
        Selection::new(origin.1)
    } else {
        Selection::new(origin.0)
    };
    sel.extend(if over.0 < origin.0 {
        over.0
    } else {
        over.1.max(origin.1)
    });
    sel
}

/// The whole row `row` as an inclusive span, for triple-click.
pub fn line_span(row: u16, cols: u16) -> (Cell, Cell) {
    (
        Cell { row, col: 0 },
        Cell {
            row,
            col: cols.saturating_sub(1),
        },
    )
}

/// Clipboard text uses CRLF between rows (Windows), whatever the source used.
pub fn to_crlf(text: &str) -> String {
    text.replace("\r\n", "\n").replace('\n', "\r\n")
}

/// Grid cells a character takes: 0 for combining marks and zero-width
/// characters, 2 for East Asian wide / fullwidth characters and emoji, else
/// 1. A small wcwidth approximation, good enough to place the IME preedit
/// (precomposed Vietnamese letters are 1 cell; decomposed marks are 0).
pub fn char_cells(c: char) -> u16 {
    let u = u32::from(c);
    let zero = matches!(u,
        0x0300..=0x036F | 0x1AB0..=0x1AFF | 0x1DC0..=0x1DFF | 0x200B..=0x200F
        | 0x20D0..=0x20FF | 0xFE00..=0xFE0F | 0xFE20..=0xFE2F);
    if zero || c.is_control() {
        return 0;
    }
    let wide = matches!(u,
        0x1100..=0x115F | 0x2E80..=0x303E | 0x3041..=0x33FF | 0x3400..=0x4DBF
        | 0x4E00..=0x9FFF | 0xA000..=0xA4CF | 0xAC00..=0xD7A3 | 0xF900..=0xFAFF
        | 0xFE30..=0xFE4F | 0xFF00..=0xFF60 | 0xFFE0..=0xFFE6 | 0x1F300..=0x1F64F
        | 0x1F900..=0x1F9FF | 0x20000..=0x3FFFD);
    if wide { 2 } else { 1 }
}

/// Cells taken by the chars of `text` that start before UTF-16 offset
/// `utf16`, and by those in `range_utf16`.
fn cells_before_and_in(text: &str, range_utf16: &Range<usize>) -> (u16, u16) {
    let (mut before, mut inside, mut at) = (0u16, 0u16, 0usize);
    for c in text.chars() {
        let w = char_cells(c);
        if at < range_utf16.start {
            before += w;
        } else if at < range_utf16.end {
            inside += w;
        }
        at += c.len_utf16();
    }
    (before, inside)
}

/// Where an IME range is drawn, in window coordinates: the preedit starts at
/// the `cursor` cell of a grid whose top-left cell is at `origin`, so
/// `range_utf16` of the preedit covers the cells after the preedit chars
/// before it. At least one cell wide (an empty range is the caret cell).
pub fn ime_rect(
    cursor: Cell,
    origin: (f32, f32),
    cell_w: f32,
    cell_h: f32,
    preedit: &str,
    range_utf16: Range<usize>,
) -> Rect {
    let (before, inside) = cells_before_and_in(preedit, &range_utf16);
    Rect {
        x: origin.0 + cell_w * f32::from(cursor.col.saturating_add(before)),
        y: origin.1 + cell_h * f32::from(cursor.row),
        w: cell_w * f32::from(inside.max(1)),
        h: cell_h,
    }
}

/// GPUI 0.2.2 on Windows puts the IMM32 composition and candidate windows at
/// `(x, y + h / 2)` of the rect `bounds_for_range` returns (events.rs
/// `retrieve_caret_position`). Moving the rect down half a row makes that
/// point the bottom edge of the cursor row, so the candidate list opens
/// under the line (as in Windows Terminal) instead of covering the preedit.
pub fn windows_ime_anchor(rect: Rect) -> Rect {
    Rect {
        y: rect.y + rect.h / 2.0,
        ..rect
    }
}

/// The inverse of [`ime_rect`]: the UTF-16 offset in `preedit` of the char
/// under window point `(x, y)`, or `None` when the point is not on the
/// preedit drawn at `cursor`.
pub fn ime_index_for_point(
    x: f32,
    y: f32,
    cursor: Cell,
    origin: (f32, f32),
    cell_w: f32,
    cell_h: f32,
    preedit: &str,
) -> Option<usize> {
    let top = origin.1 + cell_h * f32::from(cursor.row);
    if !(top..top + cell_h).contains(&y) || cell_w <= 0.0 {
        return None;
    }
    let col = ((x - origin.0) / cell_w).floor() - f32::from(cursor.col);
    if col.is_nan() || col < 0.0 {
        return None;
    }
    let (mut cells, mut at) = (0f32, 0usize);
    for c in preedit.chars() {
        let w = f32::from(char_cells(c));
        if col < cells + w {
            return Some(at);
        }
        cells += w;
        at += c.len_utf16();
    }
    None
}

const SEPARATORS: &str = "()[]{}<>'\"`,;|│";

fn is_sep(c: char) -> bool {
    c.is_whitespace() || SEPARATORS.contains(c)
}

/// `start..end` (exclusive) of the run of non-separator chars around `col`;
/// on a separator (or past the line) `(col, col + 1)`.
pub fn word_at(line: &str, col: u16) -> (u16, u16) {
    let chars: Vec<char> = line.chars().collect();
    let c = usize::from(col);
    if c >= chars.len() || is_sep(chars[c]) {
        return (col, col + 1);
    }
    let mut s = c;
    while s > 0 && !is_sep(chars[s - 1]) {
        s -= 1;
    }
    let mut e = c + 1;
    while e < chars.len() && !is_sep(chars[e]) {
        e += 1;
    }
    (s as u16, e as u16)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn c(row: u16, col: u16) -> Cell {
        Cell { row, col }
    }

    fn lines(v: &[&str]) -> Vec<String> {
        v.iter().map(|s| s.to_string()).collect()
    }

    #[test]
    fn single_row() {
        let mut s = Selection::new(c(0, 2));
        assert!(s.is_empty());
        s.extend(c(0, 4));
        assert!(!s.is_empty());
        assert_eq!(s.spans(10), vec![(0, 2, 5)]);
        assert_eq!(selected_text(&s, &lines(&["hello world"]), 11), "llo");
    }

    #[test]
    fn multi_row_and_reverse_drag() {
        let l = lines(&["abcdef", "ghijkl", "mnopqr"]);
        let mut fwd = Selection::new(c(0, 3));
        fwd.extend(c(2, 1));
        let mut rev = Selection::new(c(2, 1));
        rev.extend(c(0, 3));
        assert_eq!(fwd.ordered(), (c(0, 3), c(2, 1)));
        assert_eq!(fwd.spans(6), vec![(0, 3, 6), (1, 0, 6), (2, 0, 2)]);
        let t = "def\r\nghijkl\r\nmn";
        assert_eq!(selected_text(&fwd, &l, 6), t);
        assert_eq!(selected_text(&rev, &l, 6), t);
    }

    #[test]
    fn trailing_spaces_trimmed_and_crlf_join() {
        let l = lines(&["ab   ", "cd   "]);
        let mut s = Selection::new(c(0, 0));
        s.extend(c(1, 4));
        assert_eq!(selected_text(&s, &l, 5), "ab\r\ncd");
    }

    #[test]
    fn rows_beyond_lines_are_empty() {
        let mut s = Selection::new(c(0, 0));
        s.extend(c(2, 3));
        assert_eq!(selected_text(&s, &lines(&["x"]), 5), "x\r\n\r\n");
    }

    #[test]
    fn cell_at_clamps() {
        assert_eq!(cell_at(25.0, 41.0, 10.0, 20.0, 80, 24), c(2, 2));
        assert_eq!(cell_at(-5.0, -1.0, 10.0, 20.0, 80, 24), c(0, 0));
        assert_eq!(cell_at(9999.0, 9999.0, 10.0, 20.0, 80, 24), c(23, 79));
    }

    #[test]
    fn word_at_path_and_separators() {
        let line = r"cd C:\Users\phu\x.txt (ok)";
        assert_eq!(word_at(line, 6), (3, 21));
        assert_eq!(word_at(line, 3), (3, 21));
        assert_eq!(word_at(line, 2), (2, 3));
        assert_eq!(word_at(line, 21), (21, 22));
        assert_eq!(word_at(line, 22), (22, 23));
        assert_eq!(word_at(line, 24), (23, 25));
        assert_eq!(word_at(line, 200), (200, 201));
    }

    #[test]
    fn shifted_moves_rows_and_drops_when_out_of_view() {
        let mut s = Selection::new(c(5, 2));
        s.extend(c(7, 4));
        let up = s.shifted(-3, 24).unwrap();
        assert_eq!((up.anchor(), up.head()), (c(2, 2), c(4, 4)));
        assert_eq!(s.shifted(0, 24), Some(s));
        assert_eq!(s.shifted(-6, 24), None);
        assert_eq!(s.shifted(17, 24), None);
        assert_eq!(s.shifted(16, 24).unwrap().head(), c(23, 4));
    }

    #[test]
    fn drag_grows_from_the_origin_span() {
        // Plain drag: origin is one cell.
        let a = c(1, 5);
        let fwd = drag_selection((a, a), (c(2, 3), c(2, 3)));
        assert_eq!((fwd.anchor(), fwd.head()), (a, c(2, 3)));
        let back = drag_selection((a, a), (c(0, 1), c(0, 1)));
        assert_eq!(back.ordered(), (c(0, 1), a));
        // Double-click word drag: the clicked word stays selected.
        let word = (c(1, 3), c(1, 7));
        let right = drag_selection(word, (c(1, 9), c(1, 12)));
        assert_eq!(right.ordered(), (c(1, 3), c(1, 12)));
        let inside = drag_selection(word, (c(1, 3), c(1, 7)));
        assert_eq!(inside.ordered(), word);
        let left = drag_selection(word, (c(1, 0), c(1, 1)));
        assert_eq!(left.ordered(), (c(1, 0), c(1, 7)));
        // Triple-click line drag over two rows.
        let line = drag_selection(line_span(2, 80), line_span(4, 80));
        assert_eq!(line.ordered(), (c(2, 0), c(4, 79)));
        assert_eq!(line.spans(80), vec![(2, 0, 80), (3, 0, 80), (4, 0, 80)]);
    }

    #[test]
    fn crlf_row_joins() {
        assert_eq!(to_crlf("a\nb\r\nc"), "a\r\nb\r\nc");
        assert_eq!(to_crlf("tiếng Việt"), "tiếng Việt");
    }

    #[test]
    fn char_cells_vietnamese_cjk_marks() {
        assert!("tiếng Việt".chars().all(|ch| char_cells(ch) == 1));
        assert_eq!(char_cells('\u{301}'), 0); // decomposed acute accent
        assert_eq!(char_cells('漢'), 2);
        assert_eq!(char_cells('か'), 2);
        assert_eq!(char_cells('한'), 2);
        assert_eq!(char_cells('😀'), 2);
        assert_eq!(char_cells('a'), 1);
    }

    #[test]
    fn ime_rect_at_cursor_in_a_split_pane() {
        // A right-hand split pane whose grid starts at (606.5, 82.0).
        let o = (606.5, 82.0);
        let cur = c(3, 10);
        let caret = ime_rect(cur, o, 8.0, 18.0, "", 0..0);
        assert_eq!(
            caret,
            Rect {
                x: 686.5,
                y: 136.0,
                w: 8.0,
                h: 18.0
            }
        );
        // Telex preedit "tiế": the caret after it is 3 cells right.
        let after = ime_rect(cur, o, 8.0, 18.0, "tiế", 3..3);
        assert_eq!(after.x, 686.5 + 24.0);
        let whole = ime_rect(cur, o, 8.0, 18.0, "tiế", 0..3);
        assert_eq!((whole.x, whole.w), (686.5, 24.0));
        // Japanese preedit: wide chars count two cells each.
        let ja = ime_rect(cur, o, 8.0, 18.0, "かんじ", 2..3);
        assert_eq!((ja.x, ja.w), (686.5 + 32.0, 16.0));
        // Astral char: 2 UTF-16 units, 2 cells.
        let emoji = ime_rect(cur, o, 8.0, 18.0, "😀a", 2..3);
        assert_eq!((emoji.x, emoji.w), (686.5 + 16.0, 8.0));
    }

    #[test]
    fn windows_anchor_is_the_row_bottom() {
        let r = ime_rect(c(3, 10), (0.0, 0.0), 8.0, 18.0, "", 0..0);
        let a = windows_ime_anchor(r);
        // GPUI uses y + h / 2: that is the bottom edge of row 3.
        assert_eq!(a.y + a.h / 2.0, r.y + r.h);
        assert_eq!((a.x, a.w, a.h), (r.x, r.w, r.h));
    }

    #[test]
    fn ime_index_for_point_inverts_ime_rect() {
        let (o, cur) = ((6.0, 6.0), c(2, 4));
        let p = "tiếng";
        for i in 0..5 {
            let r = ime_rect(cur, o, 8.0, 18.0, p, i..i + 1);
            let hit = ime_index_for_point(r.x + 1.0, r.y + 1.0, cur, o, 8.0, 18.0, p);
            assert_eq!(hit, Some(i));
        }
        let off_row = ime_index_for_point(6.0 + 40.0, 6.0, cur, o, 8.0, 18.0, p);
        assert_eq!(off_row, None);
        let past = ime_rect(cur, o, 8.0, 18.0, p, 5..5);
        assert_eq!(
            ime_index_for_point(past.x + 1.0, past.y + 1.0, cur, o, 8.0, 18.0, p),
            None
        );
        let ja = "かんじ";
        let r = ime_rect(cur, o, 8.0, 18.0, ja, 1..2);
        assert_eq!(
            ime_index_for_point(r.x + 12.0, r.y, cur, o, 8.0, 18.0, ja),
            Some(1)
        );
    }

    #[test]
    fn word_at_vietnamese_uses_chars() {
        let line = "tiếng Việt";
        assert_eq!(word_at(line, 1), (0, 5));
        assert_eq!(word_at(line, 7), (6, 10));
        let mut s = Selection::new(c(0, 6));
        s.extend(c(0, 9));
        assert_eq!(selected_text(&s, &lines(&[line]), 10), "Việt");
    }
}
