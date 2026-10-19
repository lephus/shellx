//! Tabs of layouts, pane ownership, local/remote targets.

use std::collections::{BTreeMap, VecDeque};

use crate::keys::Dir;
use crate::layout::{Axis, Close, Layout, PaneId, Rect};

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum PaneTarget {
    Local,
    Remote {
        machine_id: String,
        terminal_id: String,
    },
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub struct TabId(pub u64);

#[derive(Clone, Debug)]
pub struct Tab {
    pub id: TabId,
    pub layout: Layout,
    pub focused: PaneId,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum CloseOutcome {
    PaneClosed { tab: TabId, focus: PaneId },
    TabClosed { closed: TabId, active: TabId },
    Respawned { tab: TabId, pane: PaneId },
    NotFound,
}

#[derive(Debug)]
pub struct Tabs {
    tabs: Vec<Tab>,
    active: usize,
    targets: BTreeMap<PaneId, PaneTarget>,
    next_pane: u64,
    next_tab: u64,
}

impl Tabs {
    /// Starts with one Local tab.
    pub fn new() -> (Tabs, PaneId) {
        let mut t = Tabs {
            tabs: Vec::new(),
            active: 0,
            targets: BTreeMap::new(),
            next_pane: 1,
            next_tab: 1,
        };
        let (_, pane) = t.new_tab(PaneTarget::Local);
        (t, pane)
    }

    fn alloc_pane(&mut self) -> PaneId {
        let p = PaneId(self.next_pane);
        self.next_pane += 1;
        p
    }

    /// Appended after the active tab and made active.
    pub fn new_tab(&mut self, target: PaneTarget) -> (TabId, PaneId) {
        let pane = self.alloc_pane();
        let id = TabId(self.next_tab);
        self.next_tab += 1;
        self.targets.insert(pane, target);
        let at = if self.tabs.is_empty() {
            0
        } else {
            self.active + 1
        };
        self.tabs.insert(
            at,
            Tab {
                id,
                layout: Layout::new(pane),
                focused: pane,
            },
        );
        self.active = at;
        (id, pane)
    }

    /// Splits the active tab's focused pane; the new pane gets focus.
    pub fn split_focused(&mut self, axis: Axis, target: PaneTarget) -> PaneId {
        let pane = self.alloc_pane();
        let tab = &mut self.tabs[self.active];
        let ok = tab.layout.split(tab.focused, axis, pane);
        debug_assert!(ok, "focused pane is always in its layout");
        tab.focused = pane;
        self.targets.insert(pane, target);
        pane
    }

    pub fn close_pane(&mut self, pane: PaneId) -> CloseOutcome {
        let Some(i) = self.tabs.iter().position(|t| t.layout.contains(pane)) else {
            return CloseOutcome::NotFound;
        };
        let tab = &mut self.tabs[i];
        match tab.layout.close(pane) {
            Close::Closed { focus } => {
                if tab.focused == pane {
                    tab.focused = focus;
                }
                let out = CloseOutcome::PaneClosed {
                    tab: tab.id,
                    focus: tab.focused,
                };
                self.targets.remove(&pane);
                out
            }
            Close::Last => {
                self.targets.remove(&pane);
                if self.tabs.len() == 1 {
                    self.tabs.clear();
                    self.active = 0;
                    let (tab, pane) = self.new_tab(PaneTarget::Local);
                    return CloseOutcome::Respawned { tab, pane };
                }
                let closed = self.tabs.remove(i).id;
                if i == self.active {
                    self.active = i.saturating_sub(1);
                } else if i < self.active {
                    self.active -= 1;
                }
                CloseOutcome::TabClosed {
                    closed,
                    active: self.tabs[self.active].id,
                }
            }
            Close::NotFound => CloseOutcome::NotFound,
        }
    }

    /// Focuses `pane` (and activates its tab).
    pub fn focus(&mut self, pane: PaneId) {
        if let Some(i) = self.tabs.iter().position(|t| t.layout.contains(pane)) {
            self.active = i;
            self.tabs[i].focused = pane;
        }
    }

    pub fn focus_dir(&mut self, dir: Dir, bounds: Rect, divider: f32) -> bool {
        let tab = &mut self.tabs[self.active];
        match tab.layout.neighbor(tab.focused, dir, bounds, divider) {
            Some(p) => {
                tab.focused = p;
                true
            }
            None => false,
        }
    }

    pub fn select(&mut self, tab: TabId) -> bool {
        match self.tabs.iter().position(|t| t.id == tab) {
            Some(i) => {
                self.active = i;
                true
            }
            None => false,
        }
    }

    pub fn next_tab(&mut self) {
        self.active = (self.active + 1) % self.tabs.len();
    }

    pub fn prev_tab(&mut self) {
        self.active = (self.active + self.tabs.len() - 1) % self.tabs.len();
    }

    pub fn active(&self) -> &Tab {
        &self.tabs[self.active]
    }

    pub fn tabs(&self) -> &[Tab] {
        &self.tabs
    }

    pub fn target(&self, pane: PaneId) -> Option<&PaneTarget> {
        self.targets.get(&pane)
    }

    /// Remote panes of a machine (to mark them offline).
    pub fn panes_on_machine(&self, machine_id: &str) -> Vec<PaneId> {
        self.targets
            .iter()
            .filter(
                |(_, t)| matches!(t, PaneTarget::Remote { machine_id: m, .. } if m == machine_id),
            )
            .map(|(p, _)| *p)
            .collect()
    }

    /// Every remote pane, in id order (sign-out closes them all).
    pub fn remote_panes(&self) -> Vec<PaneId> {
        self.targets
            .iter()
            .filter(|(_, t)| matches!(t, PaneTarget::Remote { .. }))
            .map(|(p, _)| *p)
            .collect()
    }

    /// A remote pane now shows `terminal_id` (its first attach, or another
    /// terminal after the Mac restarted). False for a local or unknown pane.
    pub fn retarget(&mut self, pane: PaneId, terminal_id: &str) -> bool {
        match self.targets.get_mut(&pane) {
            Some(PaneTarget::Remote {
                terminal_id: shown, ..
            }) => {
                *shown = terminal_id.to_string();
                true
            }
            _ => false,
        }
    }
}

/// Respawns of the last pane allowed within `RESPAWN_WINDOW_MS`.
pub const RESPAWN_LIMIT: usize = 5;
pub const RESPAWN_WINDOW_MS: u64 = 10_000;

/// Stops a respawn storm: a shell that exits right after it starts (a bad
/// `SHELLX_SHELL`) would otherwise close the last pane, respawn, exit again,
/// forever. After `RESPAWN_LIMIT` respawns within `RESPAWN_WINDOW_MS` the
/// next respawned pane is *held*: the window shows a message there and
/// starts no shell until the user retries ("Thử lại" or any key).
#[derive(Debug, Default)]
pub struct RespawnGuard {
    /// When the recent allowed respawns happened (ms, oldest first).
    recent: VecDeque<u64>,
    held: Option<PaneId>,
}

impl RespawnGuard {
    pub fn new() -> RespawnGuard {
        RespawnGuard::default()
    }

    /// Feeds a `Tabs::close_pane` outcome. A `Respawned` pane is held when
    /// the limit was already reached in the window ending at `now_ms`.
    pub fn on_close(&mut self, outcome: &CloseOutcome, now_ms: u64) {
        let CloseOutcome::Respawned { pane, .. } = outcome else {
            return;
        };
        self.recent
            .retain(|&at| now_ms.saturating_sub(at) < RESPAWN_WINDOW_MS);
        if self.recent.len() >= RESPAWN_LIMIT {
            self.held = Some(*pane);
        } else {
            self.recent.push_back(now_ms);
            self.held = None;
        }
    }

    /// The pane shows the "shell exits at start" message instead of a shell.
    pub fn is_held(&self, pane: PaneId) -> bool {
        self.held == Some(pane)
    }

    pub fn held(&self) -> Option<PaneId> {
        self.held
    }

    /// Retry from the held pane: forgets the history and replaces the held
    /// pane with a fresh one (which starts a shell). `NotFound` when no pane
    /// is held.
    pub fn retry(&mut self, tabs: &mut Tabs, now_ms: u64) -> CloseOutcome {
        let Some(pane) = self.held.take() else {
            return CloseOutcome::NotFound;
        };
        self.recent.clear();
        let out = tabs.close_pane(pane);
        self.on_close(&out, now_ms);
        out
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn respawn_storm_stops_after_five_in_ten_seconds() {
        let (mut t, _) = Tabs::new();
        let mut g = RespawnGuard::new();
        let mut now = 0;
        // the shell exits instantly: the last pane closes every 500 ms
        for i in 0..RESPAWN_LIMIT {
            now += 500;
            let out = t.close_pane(t.active().focused);
            g.on_close(&out, now);
            assert!(matches!(out, CloseOutcome::Respawned { .. }), "{i}");
            assert_eq!(g.held(), None, "respawn {i} starts a shell");
        }
        now += 500;
        let out = t.close_pane(t.active().focused);
        g.on_close(&out, now);
        let CloseOutcome::Respawned { pane, .. } = out else {
            panic!("{out:?}")
        };
        // the window keeps one tab, its pane held (no shell)
        assert!(g.is_held(pane));
        assert_eq!(t.tabs().len(), 1);
        assert_eq!(t.active().focused, pane);
        // closing the held pane again soon stays held
        now += 500;
        let out = t.close_pane(pane);
        g.on_close(&out, now);
        let held = g.held().expect("still held");
        assert_eq!(t.active().focused, held);
        // other outcomes do not count
        let (_, other) = t.new_tab(PaneTarget::Local);
        g.on_close(&t.close_pane(other), now);
        assert_eq!(g.held(), Some(held));
        // retry: a fresh pane that starts a shell, history forgotten
        let out = g.retry(&mut t, now + 1);
        let CloseOutcome::Respawned { pane: fresh, .. } = out else {
            panic!("{out:?}")
        };
        assert_ne!(fresh, held);
        assert!(!g.is_held(fresh) && g.held().is_none());
        assert_eq!(t.target(held), None);
        assert_eq!(g.retry(&mut t, now + 2), CloseOutcome::NotFound);
    }

    #[test]
    fn slow_exits_keep_respawning() {
        let (mut t, _) = Tabs::new();
        let mut g = RespawnGuard::new();
        // one exit every 2.5 s: at most 4 in any 10 s window
        for i in 0..20u64 {
            let out = t.close_pane(t.active().focused);
            g.on_close(&out, i * 2_500);
            assert_eq!(g.held(), None, "{i}");
        }
        // a burst after a quiet 10 s starts counting from zero
        let mut g = RespawnGuard::new();
        for i in 0..RESPAWN_LIMIT as u64 {
            g.on_close(&t.close_pane(t.active().focused), i);
        }
        g.on_close(&t.close_pane(t.active().focused), 10_000);
        assert_eq!(g.held(), None);
    }

    const B: Rect = Rect {
        x: 0.0,
        y: 0.0,
        w: 801.0,
        h: 601.0,
    };

    fn remote(m: &str, t: &str) -> PaneTarget {
        PaneTarget::Remote {
            machine_id: m.into(),
            terminal_id: t.into(),
        }
    }

    #[test]
    fn closing_last_pane_of_last_tab_respawns() {
        let (mut t, first) = Tabs::new();
        let old_tab = t.active().id;
        match t.close_pane(first) {
            CloseOutcome::Respawned { tab, pane } => {
                assert_ne!(pane, first);
                assert_ne!(tab, old_tab);
                assert_eq!(t.active().id, tab);
                assert_eq!(t.active().focused, pane);
            }
            other => panic!("expected Respawned, got {other:?}"),
        }
        assert_eq!(t.tabs().len(), 1);
        let panes = t.active().layout.panes();
        assert_eq!(panes.len(), 1);
        assert_eq!(t.target(panes[0]), Some(&PaneTarget::Local));
        assert_eq!(t.target(first), None);
    }

    #[test]
    fn closing_a_split_pane_keeps_tab() {
        let (mut t, a) = Tabs::new();
        let b = t.split_focused(Axis::Row, PaneTarget::Local);
        assert_eq!(t.active().focused, b);
        let tab = t.active().id;
        assert_eq!(t.close_pane(b), CloseOutcome::PaneClosed { tab, focus: a });
        assert_eq!(t.tabs().len(), 1);
        assert_eq!(t.active().layout.panes(), vec![a]);
        // closing an unfocused pane leaves focus alone
        let c = t.split_focused(Axis::Column, PaneTarget::Local);
        assert_eq!(t.close_pane(a), CloseOutcome::PaneClosed { tab, focus: c });
        assert_eq!(t.close_pane(PaneId(999)), CloseOutcome::NotFound);
    }

    #[test]
    fn closing_last_pane_of_a_tab_selects_left_neighbor() {
        let (mut t, p1) = Tabs::new();
        let t1 = t.active().id;
        let (t2, p2) = t.new_tab(PaneTarget::Local);
        let (t3, p3) = t.new_tab(PaneTarget::Local);
        assert_eq!(
            t.tabs().iter().map(|x| x.id).collect::<Vec<_>>(),
            vec![t1, t2, t3]
        );
        assert_eq!(
            t.close_pane(p3),
            CloseOutcome::TabClosed {
                closed: t3,
                active: t2
            }
        );
        assert_eq!(t.active().id, t2);
        t.select(t1);
        assert_eq!(
            t.close_pane(p1),
            CloseOutcome::TabClosed {
                closed: t1,
                active: t2
            }
        );
        assert_eq!(t.active().id, t2);
        assert_eq!(
            t.close_pane(p2),
            CloseOutcome::Respawned {
                tab: t.active().id,
                pane: t.active().focused
            }
        );
    }

    #[test]
    fn closing_a_background_tab_keeps_active_tab() {
        let (mut t, p1) = Tabs::new();
        let (t2, _) = t.new_tab(PaneTarget::Local);
        let c = t.close_pane(p1);
        assert!(matches!(c, CloseOutcome::TabClosed { active, .. } if active == t2));
        assert_eq!(t.active().id, t2);
    }

    #[test]
    fn new_tab_inserts_after_active() {
        let (mut t, _) = Tabs::new();
        let (t2, _) = t.new_tab(PaneTarget::Local);
        let first = t.tabs()[0].id;
        t.select(first);
        let (t3, _) = t.new_tab(PaneTarget::Local);
        assert_eq!(
            t.tabs().iter().map(|x| x.id).collect::<Vec<_>>(),
            vec![first, t3, t2]
        );
        assert_eq!(t.active().id, t3);
    }

    #[test]
    fn pane_ids_never_reused() {
        let (mut t, p1) = Tabs::new();
        let mut seen = vec![p1];
        for _ in 0..3 {
            let last = *seen.last().unwrap();
            let p = t.split_focused(Axis::Row, PaneTarget::Local);
            t.close_pane(last);
            let (_, q) = t.new_tab(PaneTarget::Local);
            for id in [p, q] {
                assert!(!seen.contains(&id));
                seen.push(id);
            }
        }
        loop {
            let live = t.active().focused;
            if let CloseOutcome::Respawned { pane, .. } = t.close_pane(live) {
                assert!(!seen.contains(&pane));
                break;
            }
        }
    }

    #[test]
    fn next_prev_wrap() {
        let (mut t, _) = Tabs::new();
        let (a, _) = (t.tabs()[0].id, ());
        let (b, _) = t.new_tab(PaneTarget::Local);
        let (c, _) = t.new_tab(PaneTarget::Local);
        t.next_tab();
        assert_eq!(t.active().id, a);
        t.prev_tab();
        assert_eq!(t.active().id, c);
        t.prev_tab();
        assert_eq!(t.active().id, b);
        assert!(t.select(a) && !t.select(TabId(999)));
    }

    #[test]
    fn remote_targets_are_tracked_and_dropped_on_close() {
        let (mut t, local) = Tabs::new();
        let (_, r1) = t.new_tab(remote("m1", "t1"));
        let r2 = t.split_focused(Axis::Row, remote("m1", "t2"));
        let (_, r3) = t.new_tab(remote("m2", "t9"));
        assert_eq!(t.target(r1), Some(&remote("m1", "t1")));
        assert_eq!(t.target(local), Some(&PaneTarget::Local));
        assert_eq!(t.panes_on_machine("m1"), vec![r1, r2]);
        assert_eq!(t.panes_on_machine("m2"), vec![r3]);
        assert!(t.panes_on_machine("zz").is_empty());
        t.close_pane(r2);
        assert_eq!(t.target(r2), None);
        assert_eq!(t.panes_on_machine("m1"), vec![r1]);
    }

    #[test]
    fn retarget_updates_only_remote_panes() {
        let (mut t, local) = Tabs::new();
        let (_, r) = t.new_tab(remote("m1", ""));
        assert!(t.retarget(r, "7"));
        assert_eq!(t.target(r), Some(&remote("m1", "7")));
        assert!(!t.retarget(local, "7"));
        assert_eq!(t.target(local), Some(&PaneTarget::Local));
        assert!(!t.retarget(PaneId(999), "7"));
        assert_eq!(t.remote_panes(), vec![r]);
    }

    #[test]
    fn closing_every_remote_pane_leaves_a_local_tab() {
        // sign-out: remote tabs close through the normal path
        let (mut t, local) = Tabs::new();
        let (_, r1) = t.new_tab(remote("m1", "1"));
        let r2 = t.split_focused(Axis::Row, remote("m1", "2"));
        let (_, r3) = t.new_tab(remote("m2", "1"));
        assert_eq!(t.remote_panes(), vec![r1, r2, r3]);
        for p in t.remote_panes() {
            assert_ne!(t.close_pane(p), CloseOutcome::NotFound);
        }
        assert!(t.remote_panes().is_empty());
        assert_eq!(t.tabs().len(), 1);
        assert_eq!(t.active().layout.panes(), vec![local]);
        // the last tab remote: closing it respawns a local tab
        let (mut t, first) = Tabs::new();
        let (_, r) = t.new_tab(remote("m1", "1"));
        t.close_pane(first);
        assert!(matches!(t.close_pane(r), CloseOutcome::Respawned { .. }));
        let pane = t.active().focused;
        assert_eq!(t.target(pane), Some(&PaneTarget::Local));
    }

    #[test]
    fn focus_and_focus_dir() {
        let (mut t, a) = Tabs::new();
        let b = t.split_focused(Axis::Row, PaneTarget::Local);
        assert!(t.focus_dir(Dir::Left, B, 1.0));
        assert_eq!(t.active().focused, a);
        assert!(!t.focus_dir(Dir::Left, B, 1.0));
        let (_, c) = t.new_tab(PaneTarget::Local);
        t.focus(b);
        assert_eq!(t.active().focused, b);
        assert_ne!(t.active().focused, c);
    }
}
