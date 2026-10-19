//! Split tree of one tab: split, close, geometry, directional focus.

use crate::keys::Dir;

#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, PartialOrd, Ord)]
pub struct PaneId(pub u64);

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Axis {
    /// Children side by side, vertical divider ("split right").
    Row,
    /// Children stacked ("split down").
    Column,
}

#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Rect {
    pub x: f32,
    pub y: f32,
    pub w: f32,
    pub h: f32,
}

#[derive(Clone, Debug, PartialEq)]
pub enum Node {
    Leaf(PaneId),
    Split {
        axis: Axis,
        /// Share of the first child, 0.1..=0.9.
        ratio: f32,
        first: Box<Node>,
        second: Box<Node>,
    },
}

#[derive(Clone, Debug, PartialEq)]
pub struct Layout {
    root: Node,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Close {
    Closed { focus: PaneId },
    Last,
    NotFound,
}

const EPS: f32 = 0.5;

impl Node {
    fn first_leaf(&self) -> PaneId {
        match self {
            Node::Leaf(p) => *p,
            Node::Split { first, .. } => first.first_leaf(),
        }
    }

    fn last_leaf(&self) -> PaneId {
        match self {
            Node::Leaf(p) => *p,
            Node::Split { second, .. } => second.last_leaf(),
        }
    }

    fn collect(&self, out: &mut Vec<PaneId>) {
        match self {
            Node::Leaf(p) => out.push(*p),
            Node::Split { first, second, .. } => {
                first.collect(out);
                second.collect(out);
            }
        }
    }

    fn split(&mut self, target: PaneId, axis: Axis, new_pane: PaneId) -> bool {
        match self {
            Node::Leaf(p) if *p == target => {
                *self = Node::Split {
                    axis,
                    ratio: 0.5,
                    first: Box::new(Node::Leaf(target)),
                    second: Box::new(Node::Leaf(new_pane)),
                };
                true
            }
            Node::Leaf(_) => false,
            Node::Split { first, second, .. } => {
                first.split(target, axis, new_pane) || second.split(target, axis, new_pane)
            }
        }
    }

    /// Removes `pane`; returns the focus target when it was found in a split.
    fn close(&mut self, pane: PaneId) -> Option<PaneId> {
        let Node::Split { first, second, .. } = self else {
            return None;
        };
        let placeholder = || Node::Leaf(PaneId(0));
        if matches!(**first, Node::Leaf(p) if p == pane) {
            let sibling = std::mem::replace(&mut **second, placeholder());
            let focus = sibling.first_leaf();
            *self = sibling;
            return Some(focus);
        }
        if matches!(**second, Node::Leaf(p) if p == pane) {
            let sibling = std::mem::replace(&mut **first, placeholder());
            let focus = sibling.last_leaf();
            *self = sibling;
            return Some(focus);
        }
        first.close(pane).or_else(|| second.close(pane))
    }

    fn rects(&self, b: Rect, divider: f32, out: &mut Vec<(PaneId, Rect)>) {
        match self {
            Node::Leaf(p) => out.push((*p, b)),
            Node::Split {
                axis,
                ratio,
                first,
                second,
            } => match axis {
                Axis::Row => {
                    let fw = ratio * (b.w - divider);
                    first.rects(Rect { w: fw, ..b }, divider, out);
                    second.rects(
                        Rect {
                            x: b.x + fw + divider,
                            w: b.w - divider - fw,
                            ..b
                        },
                        divider,
                        out,
                    );
                }
                Axis::Column => {
                    let fh = ratio * (b.h - divider);
                    first.rects(Rect { h: fh, ..b }, divider, out);
                    second.rects(
                        Rect {
                            y: b.y + fh + divider,
                            h: b.h - divider - fh,
                            ..b
                        },
                        divider,
                        out,
                    );
                }
            },
        }
    }
}

impl Layout {
    pub fn new(pane: PaneId) -> Layout {
        Layout {
            root: Node::Leaf(pane),
        }
    }

    pub fn root(&self) -> &Node {
        &self.root
    }

    pub fn split(&mut self, target: PaneId, axis: Axis, new_pane: PaneId) -> bool {
        self.root.split(target, axis, new_pane)
    }

    pub fn close(&mut self, pane: PaneId) -> Close {
        if !self.contains(pane) {
            return Close::NotFound;
        }
        match self.root.close(pane) {
            Some(focus) => Close::Closed { focus },
            None => Close::Last,
        }
    }

    pub fn panes(&self) -> Vec<PaneId> {
        let mut v = Vec::new();
        self.root.collect(&mut v);
        v
    }

    pub fn contains(&self, pane: PaneId) -> bool {
        self.panes().contains(&pane)
    }

    pub fn len(&self) -> usize {
        self.panes().len()
    }

    pub fn is_empty(&self) -> bool {
        false
    }

    pub fn rects(&self, bounds: Rect, divider: f32) -> Vec<(PaneId, Rect)> {
        let mut v = Vec::new();
        self.root.rects(bounds, divider, &mut v);
        v
    }

    pub fn neighbor(&self, pane: PaneId, dir: Dir, bounds: Rect, divider: f32) -> Option<PaneId> {
        let rects = self.rects(bounds, divider);
        let me = rects.iter().find(|(p, _)| *p == pane)?.1;
        let overlap = |a0: f32, a1: f32, b0: f32, b1: f32| a1.min(b1) - a0.max(b0);
        let mut best: Option<(PaneId, f32, f32)> = None;
        for (p, r) in rects.iter().filter(|(p, _)| *p != pane) {
            let (dist, ov) = match dir {
                Dir::Right => (
                    r.x - (me.x + me.w),
                    overlap(me.y, me.y + me.h, r.y, r.y + r.h),
                ),
                Dir::Left => (
                    me.x - (r.x + r.w),
                    overlap(me.y, me.y + me.h, r.y, r.y + r.h),
                ),
                Dir::Down => (
                    r.y - (me.y + me.h),
                    overlap(me.x, me.x + me.w, r.x, r.x + r.w),
                ),
                Dir::Up => (
                    me.y - (r.y + r.h),
                    overlap(me.x, me.x + me.w, r.x, r.x + r.w),
                ),
            };
            if dist < -EPS || ov <= EPS {
                continue;
            }
            let better = match best {
                None => true,
                Some((_, bd, bo)) => dist < bd - EPS || ((dist - bd).abs() <= EPS && ov > bo + EPS),
            };
            if better {
                best = Some((*p, dist, ov));
            }
        }
        best.map(|(p, _, _)| p)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const B: Rect = Rect {
        x: 0.0,
        y: 0.0,
        w: 1001.0,
        h: 601.0,
    };

    fn p(n: u64) -> PaneId {
        PaneId(n)
    }

    #[test]
    fn split_and_close_round_trip() {
        let mut l = Layout::new(p(1));
        assert!(l.split(p(1), Axis::Row, p(2)));
        assert!(!l.split(p(9), Axis::Row, p(3)));
        assert_eq!(l.panes(), vec![p(1), p(2)]);
        assert_eq!(
            (l.len(), l.contains(p(2)), l.contains(p(3))),
            (2, true, false)
        );
        assert_eq!(l.close(p(2)), Close::Closed { focus: p(1) });
        assert_eq!(l, Layout::new(p(1)));
    }

    #[test]
    fn close_gives_space_to_sibling() {
        let mut l = Layout::new(p(1));
        l.split(p(1), Axis::Row, p(2));
        l.split(p(2), Axis::Row, p(3));
        assert_eq!(l.close(p(2)), Close::Closed { focus: p(3) });
        let r = l.rects(B, 1.0);
        assert_eq!(r.len(), 2);
        assert_eq!(r[0].1.x, 0.0);
        assert!((r[0].1.w + 1.0 + r[1].1.w - B.w).abs() < 1e-3);
        // closing the first child of the root hands everything to the rest
        assert_eq!(l.close(p(1)), Close::Closed { focus: p(3) });
        assert_eq!(l.rects(B, 1.0), vec![(p(3), B)]);
    }

    #[test]
    fn close_focus_moves_to_neighbor() {
        let mut l = Layout::new(p(1));
        l.split(p(1), Axis::Row, p(2));
        l.split(p(2), Axis::Column, p(3));
        // closing a first child focuses the sibling's first leaf
        assert_eq!(l.close(p(1)), Close::Closed { focus: p(2) });
        // closing a second child focuses the sibling's last leaf
        let mut l = Layout::new(p(1));
        l.split(p(1), Axis::Column, p(2));
        l.split(p(1), Axis::Row, p(3));
        assert_eq!(l.panes(), vec![p(1), p(3), p(2)]);
        assert_eq!(l.close(p(2)), Close::Closed { focus: p(3) });
    }

    #[test]
    fn close_last_reports_last() {
        let mut l = Layout::new(p(1));
        assert_eq!(l.close(p(1)), Close::Last);
        assert_eq!(l, Layout::new(p(1)));
        assert_eq!(l.close(p(7)), Close::NotFound);
    }

    #[test]
    fn rects_respect_divider_and_ratio() {
        let mut l = Layout::new(p(1));
        l.split(p(1), Axis::Row, p(2));
        let b = Rect {
            x: 10.0,
            y: 20.0,
            w: 101.0,
            h: 50.0,
        };
        let r = l.rects(b, 1.0);
        assert_eq!(
            r[0].1,
            Rect {
                x: 10.0,
                y: 20.0,
                w: 50.0,
                h: 50.0
            }
        );
        assert_eq!(
            r[1].1,
            Rect {
                x: 61.0,
                y: 20.0,
                w: 50.0,
                h: 50.0
            }
        );
        let mut l = Layout::new(p(1));
        l.split(p(1), Axis::Column, p(2));
        let r = l.rects(
            Rect {
                x: 0.0,
                y: 0.0,
                w: 40.0,
                h: 101.0,
            },
            1.0,
        );
        assert_eq!(
            r[0].1,
            Rect {
                x: 0.0,
                y: 0.0,
                w: 40.0,
                h: 50.0
            }
        );
        assert_eq!(
            r[1].1,
            Rect {
                x: 0.0,
                y: 51.0,
                w: 40.0,
                h: 50.0
            }
        );
    }

    #[test]
    fn neighbor_in_each_direction() {
        // 1 | 2 on top, split each column down: 1/3 left, 2/4 right
        let mut l = Layout::new(p(1));
        l.split(p(1), Axis::Row, p(2));
        l.split(p(1), Axis::Column, p(3));
        l.split(p(2), Axis::Column, p(4));
        let n = |a, d| l.neighbor(p(a), d, B, 1.0);
        assert_eq!(n(1, Dir::Right), Some(p(2)));
        assert_eq!(n(1, Dir::Down), Some(p(3)));
        assert_eq!(n(4, Dir::Left), Some(p(3)));
        assert_eq!(n(4, Dir::Up), Some(p(2)));
        assert_eq!(n(3, Dir::Right), Some(p(4)));
        assert_eq!(n(2, Dir::Left), Some(p(1)));
        assert_eq!(n(1, Dir::Left), None);
        assert_eq!(n(1, Dir::Up), None);
        assert_eq!(n(4, Dir::Right), None);
        assert_eq!(n(4, Dir::Down), None);
        assert_eq!(l.neighbor(p(99), Dir::Up, B, 1.0), None);
    }

    #[test]
    fn neighbor_prefers_largest_overlap() {
        // left pane 1 beside a right column of 2 (top, small) and 3 (bottom, big)
        let mut l = Layout::new(p(1));
        l.split(p(1), Axis::Row, p(2));
        l.split(p(2), Axis::Column, p(3));
        if let Node::Split { second, .. } = &mut l.root
            && let Node::Split { ratio, .. } = &mut **second
        {
            *ratio = 0.2;
        }
        assert_eq!(l.neighbor(p(1), Dir::Right, B, 1.0), Some(p(3)));
    }
}
