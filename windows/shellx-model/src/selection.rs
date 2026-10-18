//! Grid selection in viewport coordinates.

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
    fn word_at_vietnamese_uses_chars() {
        let line = "tiếng Việt";
        assert_eq!(word_at(line, 1), (0, 5));
        assert_eq!(word_at(line, 7), (6, 10));
        let mut s = Selection::new(c(0, 6));
        s.extend(c(0, 9));
        assert_eq!(selected_text(&s, &lines(&[line]), 10), "Việt");
    }
}
