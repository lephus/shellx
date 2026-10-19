//! GPUI-free pane orchestration shared by the window and `--smoke`.
//!
//! `PaneHost<P>` maps every pane of a `shellx_model::tabs::Tabs` (all tabs,
//! not just the active one) to a live value `P`: a `TermView` entity in the
//! window, a bare `TermCore` + `LocalPty` in the smoke. Structure changes go
//! through the model only; `reconcile` then spawns values for new panes and
//! hands back the values of removed panes, whose drop kills their shell.
//!
//! Also here: the pane-area geometry the window lays out and `Tabs::focus_dir`
//! uses, and the one way a local pane (PowerShell on ConPTY) is started.

// The window (cfg(windows)) is the main user; the Mac build only tests it.
#![cfg_attr(not(windows), allow(dead_code))]

use std::collections::{BTreeMap, BTreeSet};
use std::io::Read;
use std::sync::Arc;

use anyhow::Result;
use shellx_model::layout::{PaneId, Rect};
use shellx_model::tabs::{PaneTarget, Tabs};

use crate::local_pty::{LocalPty, default_shell};
use crate::term_core::TermCore;

/// Width of the line between split panes (`Layout::rects` divider), in px.
pub const DIVIDER: f32 = 1.0;
/// Fixed chrome around the pane area, in px (ui/titlebar.rs, ui/root.rs
/// session bar, ui/sidebar.rs). Borders are inside these sizes.
pub const TITLEBAR_H: f32 = 40.0;
pub const SESSION_BAR_H: f32 = 36.0;
pub const SIDEBAR_W: f32 = 290.0;

/// Size of the pane area for a window viewport, before the first layout
/// measures it (the window prefers the measured size once it has one).
pub fn estimate_pane_area(viewport_w: f32, viewport_h: f32, sidebar_visible: bool) -> Rect {
    let side = if sidebar_visible { SIDEBAR_W } else { 0.0 };
    Rect {
        x: 0.0,
        y: 0.0,
        w: (viewport_w - side).max(0.0),
        h: (viewport_h - TITLEBAR_H - SESSION_BAR_H).max(0.0),
    }
}

/// Every pane of every tab, in id order.
pub fn model_panes(tabs: &Tabs) -> Vec<PaneId> {
    let set: BTreeSet<PaneId> = tabs
        .tabs()
        .iter()
        .flat_map(|tab| tab.layout.panes())
        .collect();
    set.into_iter().collect()
}

pub struct Reconciled<P> {
    /// Panes that got a fresh value, in id order.
    pub added: Vec<PaneId>,
    /// Panes the model no longer has, with their values. Dropping a value
    /// ends its shell.
    pub removed: Vec<(PaneId, P)>,
}

pub struct PaneHost<P> {
    panes: BTreeMap<PaneId, P>,
}

impl<P> Default for PaneHost<P> {
    fn default() -> Self {
        PaneHost {
            panes: BTreeMap::new(),
        }
    }
}

impl<P> PaneHost<P> {
    pub fn new() -> Self {
        Self::default()
    }

    /// Makes the live set equal to the model's panes: removes values whose
    /// pane is gone, then spawns one for each new pane. On a spawn error the
    /// panes handled so far stay reconciled and the error is returned.
    pub fn reconcile<E>(
        &mut self,
        tabs: &Tabs,
        mut spawn: impl FnMut(PaneId, &PaneTarget) -> Result<P, E>,
    ) -> Result<Reconciled<P>, E> {
        let live: BTreeSet<PaneId> = model_panes(tabs).into_iter().collect();
        let gone: Vec<PaneId> = self
            .panes
            .keys()
            .filter(|pane| !live.contains(pane))
            .copied()
            .collect();
        let mut out = Reconciled {
            added: Vec::new(),
            removed: Vec::with_capacity(gone.len()),
        };
        for pane in gone {
            if let Some(value) = self.panes.remove(&pane) {
                out.removed.push((pane, value));
            }
        }
        for pane in live {
            if self.panes.contains_key(&pane) {
                continue;
            }
            let target = tabs.target(pane).unwrap_or(&PaneTarget::Local);
            let value = spawn(pane, target)?;
            self.panes.insert(pane, value);
            out.added.push(pane);
        }
        Ok(out)
    }

    pub fn get(&self, pane: PaneId) -> Option<&P> {
        self.panes.get(&pane)
    }

    pub fn get_mut(&mut self, pane: PaneId) -> Option<&mut P> {
        self.panes.get_mut(&pane)
    }

    /// Live panes, in id order.
    pub fn ids(&self) -> Vec<PaneId> {
        self.panes.keys().copied().collect()
    }

    pub fn iter_mut(&mut self) -> impl Iterator<Item = (PaneId, &mut P)> {
        self.panes.iter_mut().map(|(pane, value)| (*pane, value))
    }

    pub fn len(&self) -> usize {
        self.panes.len()
    }

    pub fn is_empty(&self) -> bool {
        self.panes.is_empty()
    }
}

/// A started local pane: the shell's ConPTY link, its terminal core and the
/// output reader the caller pumps into `core.feed`.
pub struct LocalPane {
    pub core: TermCore,
    pub link: Arc<LocalPty>,
    pub reader: Box<dyn Read + Send>,
}

/// Starts the default shell (PowerShell, or `SHELLX_SHELL`) with
/// `extra_args` appended, on a `cols` x `rows` pseudoconsole.
pub fn spawn_local_pane(cols: u16, rows: u16, extra_args: &[&str]) -> Result<LocalPane> {
    let (program, args) = default_shell();
    let mut args: Vec<&str> = args;
    args.extend_from_slice(extra_args);
    let (link, reader) = LocalPty::spawn(&program, &args, cols, rows)?;
    let core = TermCore::new(link.clone(), cols, rows)?;
    Ok(LocalPane { core, link, reader })
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::cell::RefCell;
    use std::convert::Infallible;
    use std::rc::Rc;

    use shellx_model::layout::Axis;
    use shellx_model::tabs::CloseOutcome;

    /// Records its pane id in `dropped` when dropped (stands in for a shell).
    struct Fake {
        pane: PaneId,
        dropped: Rc<RefCell<Vec<PaneId>>>,
    }

    impl Drop for Fake {
        fn drop(&mut self) {
            self.dropped.borrow_mut().push(self.pane);
        }
    }

    fn sync(
        host: &mut PaneHost<Fake>,
        tabs: &Tabs,
        dropped: &Rc<RefCell<Vec<PaneId>>>,
    ) -> (Vec<PaneId>, Vec<PaneId>) {
        let r = host
            .reconcile(tabs, |pane, _| {
                Ok::<_, Infallible>(Fake {
                    pane,
                    dropped: dropped.clone(),
                })
            })
            .unwrap();
        let removed = r.removed.iter().map(|(p, _)| *p).collect();
        (r.added, removed)
    }

    #[test]
    fn reconcile_spawns_for_every_tab_and_drops_removed() {
        let dropped = Rc::new(RefCell::new(Vec::new()));
        let mut host = PaneHost::new();
        let (mut tabs, p1) = Tabs::new();
        assert_eq!(sync(&mut host, &tabs, &dropped), (vec![p1], vec![]));
        let p2 = tabs.split_focused(Axis::Row, PaneTarget::Local);
        let (_, p3) = tabs.new_tab(PaneTarget::Local);
        // the inactive first tab keeps its panes alive
        assert_eq!(sync(&mut host, &tabs, &dropped), (vec![p2, p3], vec![]));
        assert_eq!(host.ids(), vec![p1, p2, p3]);
        assert_eq!(host.ids(), model_panes(&tabs));
        // idempotent
        assert_eq!(sync(&mut host, &tabs, &dropped), (vec![], vec![]));
        assert!(dropped.borrow().is_empty());

        assert!(matches!(
            tabs.close_pane(p2),
            CloseOutcome::PaneClosed { .. }
        ));
        assert_eq!(sync(&mut host, &tabs, &dropped), (vec![], vec![p2]));
        // the removed value was returned and then dropped by the caller
        assert_eq!(*dropped.borrow(), vec![p2]);
        assert_eq!(host.ids(), vec![p1, p3]);
    }

    #[test]
    fn reconcile_handles_tab_close_and_respawn() {
        let dropped = Rc::new(RefCell::new(Vec::new()));
        let mut host = PaneHost::new();
        let (mut tabs, p1) = Tabs::new();
        let (t2, p2) = tabs.new_tab(PaneTarget::Local);
        sync(&mut host, &tabs, &dropped);
        assert!(matches!(
            tabs.close_pane(p1),
            CloseOutcome::TabClosed { active, .. } if active == t2
        ));
        assert_eq!(sync(&mut host, &tabs, &dropped), (vec![], vec![p1]));
        let CloseOutcome::Respawned { pane: p3, .. } = tabs.close_pane(p2) else {
            panic!("expected Respawned");
        };
        assert_eq!(sync(&mut host, &tabs, &dropped), (vec![p3], vec![p2]));
        assert_eq!(host.ids(), vec![p3]);
        assert_eq!(*dropped.borrow(), vec![p1, p2]);
        assert_eq!(host.len(), 1);
        assert!(!host.is_empty());
    }

    #[test]
    fn spawn_error_keeps_earlier_panes() {
        let mut host: PaneHost<PaneId> = PaneHost::new();
        let (mut tabs, p1) = Tabs::new();
        let p2 = tabs.split_focused(Axis::Column, PaneTarget::Local);
        let err = host.reconcile(
            &tabs,
            |pane, _| {
                if pane == p2 { Err("boom") } else { Ok(pane) }
            },
        );
        assert_eq!(err.err(), Some("boom"));
        assert_eq!(host.ids(), vec![p1]);
        let ok = host
            .reconcile(&tabs, |pane, _| Ok::<_, Infallible>(pane))
            .unwrap();
        assert_eq!(ok.added, vec![p2]);
        assert_eq!(host.get(p2), Some(&p2));
    }

    #[test]
    fn pane_area_subtracts_chrome() {
        let a = estimate_pane_area(1200.0, 760.0, true);
        assert_eq!(
            a,
            Rect {
                x: 0.0,
                y: 0.0,
                w: 910.0,
                h: 684.0
            }
        );
        assert_eq!(estimate_pane_area(1200.0, 760.0, false).w, 1200.0);
        let tiny = estimate_pane_area(100.0, 50.0, true);
        assert_eq!((tiny.w, tiny.h), (0.0, 0.0));
    }

    #[test]
    fn focus_dir_with_pane_area_matches_rendered_rects() {
        let (mut tabs, p1) = Tabs::new();
        let p2 = tabs.split_focused(Axis::Row, PaneTarget::Local);
        let p3 = tabs.split_focused(Axis::Column, PaneTarget::Local);
        let area = estimate_pane_area(1200.0, 760.0, true);
        let rects = tabs.active().layout.rects(area, DIVIDER);
        let r = |p| rects.iter().find(|(q, _)| *q == p).unwrap().1;
        // p1 left half, p2 over p3 on the right, 1 px lines between them
        assert_eq!(r(p1).x, 0.0);
        assert_eq!(r(p2).x, r(p1).w + DIVIDER);
        assert_eq!(r(p3).y, r(p2).h + DIVIDER);
        use shellx_model::keys::Dir;
        assert!(tabs.focus_dir(Dir::Up, area, DIVIDER));
        assert_eq!(tabs.active().focused, p2);
        assert!(tabs.focus_dir(Dir::Left, area, DIVIDER));
        assert_eq!(tabs.active().focused, p1);
        assert!(!tabs.focus_dir(Dir::Left, area, DIVIDER));
    }
}
