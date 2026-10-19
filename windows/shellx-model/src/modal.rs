//! One modal rule for the window's panels (RootView): while any panel is
//! open, app commands (Ctrl+Shift+T/W/D/E, Ctrl+, , the sidebar toggle,
//! tab and pane focus, terminal clicks) are swallowed; Esc closes the
//! topmost closable panel; the forced-update overlay closes the settings
//! panel and cannot itself be closed; the keyboard goes back to the terminal
//! only when the last panel has closed.

/// A panel, topmost first in drawing order.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Panel {
    /// Covers the whole window; never closed by the user.
    ForcedUpdate,
    /// Drawn over everything but the overlay.
    Settings,
    /// Centered over the main area.
    Pairing,
    /// The sign-in fields in the sidebar.
    Login,
    /// The machines-header "+" list in the sidebar.
    Picker,
}

/// Which panels are open right now.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct Panels {
    pub forced_update: bool,
    pub settings: bool,
    pub pairing: bool,
    pub login: bool,
    pub picker: bool,
}

impl Panels {
    /// The topmost open panel: it holds the keyboard.
    pub fn top(&self) -> Option<Panel> {
        [
            (self.forced_update, Panel::ForcedUpdate),
            (self.settings, Panel::Settings),
            (self.pairing, Panel::Pairing),
            (self.login, Panel::Login),
            (self.picker, Panel::Picker),
        ]
        .into_iter()
        .find_map(|(open, panel)| open.then_some(panel))
    }

    pub fn any_open(&self) -> bool {
        self.top().is_some()
    }

    /// Window commands from keys or panes (and pane clicks) run only while
    /// no panel is open; the terminal has the keyboard then.
    pub fn allows_app_commands(&self) -> bool {
        !self.any_open()
    }

    /// What Esc closes: the topmost panel, unless that is the forced-update
    /// overlay (nothing closes it).
    pub fn esc_target(&self) -> Option<Panel> {
        self.top().filter(|p| *p != Panel::ForcedUpdate)
    }

    /// A panel that must close now: the settings panel never stays open
    /// under the forced-update overlay.
    pub fn must_close(&self) -> Option<Panel> {
        (self.forced_update && self.settings).then_some(Panel::Settings)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn nothing_open_allows_commands_and_esc_goes_to_the_terminal() {
        let p = Panels::default();
        assert_eq!(p.top(), None);
        assert!(p.allows_app_commands());
        assert_eq!(p.esc_target(), None);
        assert_eq!(p.must_close(), None);
    }

    #[test]
    fn any_panel_swallows_commands_and_esc_closes_it() {
        let each = [
            (
                Panels {
                    settings: true,
                    ..Panels::default()
                },
                Panel::Settings,
            ),
            (
                Panels {
                    pairing: true,
                    ..Panels::default()
                },
                Panel::Pairing,
            ),
            (
                Panels {
                    login: true,
                    ..Panels::default()
                },
                Panel::Login,
            ),
            (
                Panels {
                    picker: true,
                    ..Panels::default()
                },
                Panel::Picker,
            ),
        ];
        for (p, panel) in each {
            assert!(!p.allows_app_commands(), "{panel:?}");
            assert_eq!(p.top(), Some(panel));
            assert_eq!(p.esc_target(), Some(panel));
        }
    }

    #[test]
    fn esc_closes_the_topmost_one_at_a_time() {
        let mut p = Panels {
            settings: true,
            pairing: true,
            login: true,
            picker: true,
            ..Panels::default()
        };
        let mut closed = Vec::new();
        while let Some(top) = p.esc_target() {
            closed.push(top);
            match top {
                Panel::Settings => p.settings = false,
                Panel::Pairing => p.pairing = false,
                Panel::Login => p.login = false,
                Panel::Picker => p.picker = false,
                Panel::ForcedUpdate => unreachable!(),
            }
            // commands stay swallowed until the last one closed
            assert_eq!(p.allows_app_commands(), p.top().is_none());
        }
        assert_eq!(
            closed,
            [Panel::Settings, Panel::Pairing, Panel::Login, Panel::Picker]
        );
        assert!(p.allows_app_commands());
    }

    #[test]
    fn forced_update_overlay_cannot_be_closed_and_closes_settings() {
        let p = Panels {
            forced_update: true,
            settings: true,
            pairing: true,
            ..Panels::default()
        };
        assert_eq!(p.top(), Some(Panel::ForcedUpdate));
        assert!(!p.allows_app_commands());
        assert_eq!(p.esc_target(), None);
        assert_eq!(p.must_close(), Some(Panel::Settings));
        let p = Panels {
            forced_update: true,
            ..Panels::default()
        };
        assert_eq!(p.must_close(), None);
        assert_eq!(p.esc_target(), None);
        assert!(!p.allows_app_commands());
    }
}
