//! Focus history behind the title bar's Back / Forward arrows, like the
//! Mac's: every move of the focused terminal is recorded, Back returns to the
//! one before, Forward undoes a Back. A terminal closed since it was recorded
//! is skipped (`alive` says which still exist), so a step never lands on
//! nothing.

use crate::layout::PaneId;

/// Most entries Back keeps; the oldest is dropped past it.
const CAP: usize = 50;

#[derive(Clone, Debug, Default)]
pub struct FocusHistory {
    /// Older focus first; Back pops from the end.
    back: Vec<PaneId>,
    /// Undone steps, the next one last.
    forward: Vec<PaneId>,
}

impl FocusHistory {
    pub fn new() -> Self {
        Self::default()
    }

    /// Focus moved `from` -> `to`: `from` goes on Back and Forward is
    /// cleared. A move to the same terminal is not one.
    pub fn record(&mut self, from: PaneId, to: PaneId) {
        if from == to {
            return;
        }
        push_capped(&mut self.back, from);
        self.forward.clear();
    }

    /// The pane Back goes to from `current`: the newest alive entry (dead
    /// ones above it are dropped); `current` goes on Forward. `None`, and
    /// nothing changes, when no alive entry is left.
    pub fn back(&mut self, current: PaneId, alive: &dyn Fn(PaneId) -> bool) -> Option<PaneId> {
        let pane = pop_alive(&mut self.back, alive)?;
        self.forward.push(current);
        Some(pane)
    }

    /// The mirror of `back`: undoes the last Back step.
    pub fn forward(&mut self, current: PaneId, alive: &dyn Fn(PaneId) -> bool) -> Option<PaneId> {
        let pane = pop_alive(&mut self.forward, alive)?;
        push_capped(&mut self.back, current);
        Some(pane)
    }

    pub fn can_back(&self, alive: &dyn Fn(PaneId) -> bool) -> bool {
        self.back.iter().any(|&pane| alive(pane))
    }

    pub fn can_forward(&self, alive: &dyn Fn(PaneId) -> bool) -> bool {
        self.forward.iter().any(|&pane| alive(pane))
    }
}

/// Whether a move of focus is recorded: any move when `includes_panes`, else
/// only one into another workspace (a move between the panes of one workspace
/// is not a step).
pub fn records(includes_panes: bool, same_workspace: bool) -> bool {
    includes_panes || !same_workspace
}

fn push_capped(stack: &mut Vec<PaneId>, pane: PaneId) {
    stack.push(pane);
    if stack.len() > CAP {
        stack.remove(0);
    }
}

/// Pops the newest alive entry and the dead ones above it; leaves `stack`
/// alone when none is alive.
fn pop_alive(stack: &mut Vec<PaneId>, alive: &dyn Fn(PaneId) -> bool) -> Option<PaneId> {
    let i = stack.iter().rposition(|&pane| alive(pane))?;
    let pane = stack[i];
    stack.truncate(i);
    Some(pane)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn p(n: u64) -> PaneId {
        PaneId(n)
    }

    fn all(_: PaneId) -> bool {
        true
    }

    #[test]
    fn back_and_forward_round_trip() {
        let mut h = FocusHistory::new();
        h.record(p(1), p(2));
        h.record(p(2), p(3));
        assert!(h.can_back(&all));
        assert!(!h.can_forward(&all));
        assert_eq!(h.back(p(3), &all), Some(p(2)));
        assert_eq!(h.back(p(2), &all), Some(p(1)));
        assert_eq!(h.back(p(1), &all), None);
        assert!(!h.can_back(&all));
        assert!(h.can_forward(&all));
        assert_eq!(h.forward(p(1), &all), Some(p(2)));
        assert_eq!(h.forward(p(2), &all), Some(p(3)));
        assert_eq!(h.forward(p(3), &all), None);
        assert_eq!(h.back(p(3), &all), Some(p(2)));
    }

    #[test]
    fn back_skips_closed_panes() {
        let mut h = FocusHistory::new();
        h.record(p(1), p(2));
        h.record(p(2), p(3));
        h.record(p(3), p(4));
        // 3 and 2 were closed: Back from 4 lands on 1, never on nothing.
        let open = |pane: PaneId| pane != p(2) && pane != p(3);
        assert!(h.can_back(&open));
        assert_eq!(h.back(p(4), &open), Some(p(1)));
        assert!(!h.can_back(&open));
        assert_eq!(h.back(p(1), &open), None);
        // Forward goes back to 4.
        assert_eq!(h.forward(p(1), &open), Some(p(4)));

        // Forward skips a closed pane too.
        let mut h = FocusHistory::new();
        h.record(p(1), p(2));
        h.record(p(2), p(3));
        assert_eq!(h.back(p(3), &all), Some(p(2)));
        assert_eq!(h.back(p(2), &all), Some(p(1)));
        let open = |pane: PaneId| pane != p(2);
        assert_eq!(h.forward(p(1), &open), Some(p(3)));
        assert!(!h.can_forward(&open));
    }

    #[test]
    fn record_clears_forward() {
        let mut h = FocusHistory::new();
        h.record(p(1), p(2));
        assert_eq!(h.back(p(2), &all), Some(p(1)));
        assert!(h.can_forward(&all));
        h.record(p(1), p(3));
        assert!(!h.can_forward(&all));
        assert_eq!(h.forward(p(3), &all), None);
        assert_eq!(h.back(p(3), &all), Some(p(1)));
    }

    #[test]
    fn same_pane_is_not_recorded() {
        let mut h = FocusHistory::new();
        h.record(p(1), p(1));
        assert!(!h.can_back(&all));
        assert_eq!(h.back(p(1), &all), None);
        // Nor does it clear forward.
        h.record(p(1), p(2));
        assert_eq!(h.back(p(2), &all), Some(p(1)));
        h.record(p(1), p(1));
        assert!(h.can_forward(&all));
    }

    #[test]
    fn back_is_capped_at_fifty() {
        let mut h = FocusHistory::new();
        for n in 0..60 {
            h.record(p(n), p(n + 1));
        }
        let mut current = p(60);
        let mut steps = 0;
        while let Some(pane) = h.back(current, &all) {
            current = pane;
            steps += 1;
        }
        assert_eq!(steps, 50);
        // The 10 oldest were dropped.
        assert_eq!(current, p(10));
    }

    #[test]
    fn nothing_alive_changes_nothing() {
        let mut h = FocusHistory::new();
        h.record(p(1), p(2));
        h.record(p(2), p(3));
        let none = |_: PaneId| false;
        assert!(!h.can_back(&none));
        assert_eq!(h.back(p(3), &none), None);
        assert!(!h.can_forward(&all));
        // Both entries are still there, in order.
        assert_eq!(h.back(p(3), &all), Some(p(2)));
        assert_eq!(h.forward(p(2), &none), None);
        assert!(!h.can_forward(&none));
        assert_eq!(h.back(p(2), &all), Some(p(1)));
        assert_eq!(h.forward(p(1), &all), Some(p(2)));
        assert_eq!(h.forward(p(2), &all), Some(p(3)));
    }

    #[test]
    fn focus_history_skips_moves_inside_a_workspace_by_default() {
        // Off: only a move to another workspace is recorded.
        assert!(!records(false, true));
        assert!(records(false, false));
        // On: every move is.
        assert!(records(true, true));
        assert!(records(true, false));
    }
}
