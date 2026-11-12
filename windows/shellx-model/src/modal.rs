//! One modal rule for the window's panels (RootView): while any panel is
//! open, app commands (Ctrl+Shift+N/T/W/B, Ctrl+, , Alt+Shift+= and Alt+Shift+-
//! splits, Alt+arrows, tab and pane focus, terminal clicks) are swallowed; Esc
//! closes the topmost closable panel; the forced-update overlay closes the
//! settings panel and cannot itself be closed; the keyboard goes back to the
//! terminal only when the last panel has closed. The sign-in dialog (opened
//! from Settings -> Account) draws over Settings. The dropdowns (the title
//! bar "+ ▾" menu, the "?" help menu, the machines "+" list) are not panels:
//! they never hold the keyboard, but a plain Esc while one is open closes
//! them and goes nowhere else (`Panels::esc_closes_dropdowns`); so does a
//! right or middle press (`press_only_closes_dropdowns`).
//!
//! Typed text is never swallowed (`Panels::root_key`): on Windows a key-down
//! that was handled is not translated, so no WM_CHAR follows and the field
//! (or the terminal) would never see the letter.

use crate::keys::{AppCommand, KeyAction};

/// A panel, topmost first in drawing order.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Panel {
    /// Covers the whole window; never closed by the user.
    ForcedUpdate,
    /// The "Sign in to ShellX" dialog, centered over the window and drawn
    /// over Settings (it opens from Settings -> Account).
    SignIn,
    /// Drawn over everything but the dialog and the overlay.
    Settings,
    /// Centered over the main area.
    Pairing,
}

/// What the window root does with a key that reached it.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum RootKey {
    /// Leave it alone: it is typed text (or an IME key) and must reach the
    /// platform's text path.
    Pass,
    /// Stop it here.
    Swallow,
    /// Esc: close the topmost closable panel.
    CloseTop,
    /// Run this window command.
    Run(AppCommand),
}

/// Position in the drawing order, 0 = topmost.
fn rank(panel: Panel) -> u8 {
    match panel {
        Panel::ForcedUpdate => 0,
        Panel::SignIn => 1,
        Panel::Settings => 2,
        Panel::Pairing => 3,
    }
}

/// Which panels are open right now.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct Panels {
    pub forced_update: bool,
    pub sign_in: bool,
    pub settings: bool,
    pub pairing: bool,
}

impl Panels {
    /// The topmost open panel: it holds the keyboard.
    pub fn top(&self) -> Option<Panel> {
        [
            (self.forced_update, Panel::ForcedUpdate),
            (self.sign_in, Panel::SignIn),
            (self.settings, Panel::Settings),
            (self.pairing, Panel::Pairing),
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

    /// Whether `panel` may open (and take the keyboard) now: nothing above
    /// it in the drawing order is open. Opening Settings under the sign-in
    /// dialog, or the dialog under the overlay, is refused; the dialog opens
    /// over Settings and over pairing.
    pub fn may_open(&self, panel: Panel) -> bool {
        self.top().is_none_or(|top| rank(top) >= rank(panel))
    }

    /// A panel that must close now: the settings panel never stays open
    /// under the forced-update overlay.
    pub fn must_close(&self) -> Option<Panel> {
        (self.forced_update && self.settings).then_some(Panel::Settings)
    }

    /// Whether this key closes the open dropdowns (the title bar "+ ▾"
    /// menu, the sidebar "?" help menu, the machines "+" list) instead of
    /// going anywhere else. The root asks in the CAPTURE phase, before the
    /// focused terminal (which would send Esc to the shell) or panel (which
    /// would close itself) sees the key. Only a plain Esc, and only while a
    /// dropdown is open; never while an IME composes (`action` is
    /// `Ignore`: the Esc cancels the composition) and never under the
    /// forced-update overlay (nothing reacts to keys there).
    pub fn esc_closes_dropdowns(
        &self,
        action: &KeyAction,
        plain_escape: bool,
        dropdown_open: bool,
    ) -> bool {
        plain_escape
            && dropdown_open
            && !matches!(action, KeyAction::Ignore)
            && self.top() != Some(Panel::ForcedUpdate)
    }

    /// What the root does with `action` (from `map_key`); `plain_escape` is
    /// Esc without modifiers. Typed text and IME keys (`Text`, `Ignore`)
    /// always pass: the open panel's field (or the terminal) takes them from
    /// the platform's text path.
    pub fn root_key(&self, action: &KeyAction, plain_escape: bool) -> RootKey {
        let text = matches!(action, KeyAction::Text | KeyAction::Ignore);
        match self.top() {
            // Nothing closes the overlay, Esc included.
            Some(Panel::ForcedUpdate) if text => RootKey::Pass,
            Some(Panel::ForcedUpdate) => RootKey::Swallow,
            Some(_) if plain_escape => RootKey::CloseTop,
            Some(_) if text => RootKey::Pass,
            Some(_) => RootKey::Swallow,
            None => match action {
                KeyAction::App(command) => RootKey::Run(*command),
                _ => RootKey::Pass,
            },
        }
    }
}

/// Whether a mouse press only closes the open dropdowns and goes nowhere
/// else: a button other than the left one while a dropdown shows. A
/// dropdown leaves the keyboard on the terminal, so a right click that
/// dismisses it would otherwise also paste there. The root asks in the
/// CAPTURE phase, before the terminal sees the press. A left press keeps
/// its way: the dropdown closes itself and the click lands.
pub fn press_only_closes_dropdowns(left_button: bool, dropdown_open: bool) -> bool {
    dropdown_open && !left_button
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn composing_and_text_keys_pass_while_a_panel_is_open() {
        // Typed text and IME keys must reach the sign-in, settings and
        // pairing fields: a handled key-down never becomes a WM_CHAR on
        // Windows, so stopping them here leaves the fields dead.
        for p in [
            Panels {
                settings: true,
                ..Panels::default()
            },
            Panels {
                sign_in: true,
                ..Panels::default()
            },
            Panels {
                pairing: true,
                ..Panels::default()
            },
        ] {
            assert_eq!(p.root_key(&KeyAction::Text, false), RootKey::Pass, "{p:?}");
            assert_eq!(
                p.root_key(&KeyAction::Ignore, false),
                RootKey::Pass,
                "{p:?}"
            );
            assert_eq!(
                p.root_key(&KeyAction::App(AppCommand::NewWorkspace), false),
                RootKey::Swallow,
                "{p:?}"
            );
            assert_eq!(
                p.root_key(&KeyAction::Chord("ctrl+x".into()), false),
                RootKey::Swallow,
                "{p:?}"
            );
            assert_eq!(
                p.root_key(&KeyAction::Chord("escape".into()), true),
                RootKey::CloseTop,
                "{p:?}"
            );
        }
    }

    #[test]
    fn esc_closes_an_open_dropdown_before_the_shell_or_a_panel_sees_it() {
        let esc = KeyAction::Chord("escape".into());
        let pairing = Panels {
            pairing: true,
            ..Panels::default()
        };
        // A dropdown is open: a plain Esc closes it, with or without a panel
        // (the sidebar and title bar stay clickable beside the pairing card).
        for p in [Panels::default(), pairing] {
            assert!(p.esc_closes_dropdowns(&esc, true, true), "{p:?}");
            // Only a plain Esc, and only while a dropdown is open.
            assert!(!p.esc_closes_dropdowns(&esc, false, true), "{p:?}");
            assert!(!p.esc_closes_dropdowns(&esc, true, false), "{p:?}");
            for other in [
                KeyAction::Text,
                KeyAction::Chord("enter".into()),
                KeyAction::App(AppCommand::NewWorkspace),
            ] {
                assert!(!p.esc_closes_dropdowns(&other, false, true), "{other:?}");
            }
        }
        // No dropdown: Esc goes on as before (to the shell, or CloseTop).
        assert_eq!(Panels::default().root_key(&esc, true), RootKey::Pass);
        assert_eq!(pairing.root_key(&esc, true), RootKey::CloseTop);
        // An IME composition gets its Esc (it cancels the composition).
        assert!(!Panels::default().esc_closes_dropdowns(&KeyAction::Ignore, true, true));
        // Nothing reacts under the forced-update overlay.
        let overlay = Panels {
            forced_update: true,
            ..Panels::default()
        };
        assert!(!overlay.esc_closes_dropdowns(&esc, true, true));
    }

    #[test]
    fn alt_f4_reaches_windows_under_every_panel() {
        use crate::keys::{KeyCtx, KeyIn, map_key};
        let alt_f4 = KeyIn {
            key: "f4",
            ctrl: false,
            alt: true,
            shift: false,
            win: false,
        };
        let ctx = KeyCtx {
            has_selection: false,
            composing: false,
        };
        let action = map_key(&alt_f4, &ctx);
        for p in [
            Panels::default(),
            Panels {
                settings: true,
                ..Panels::default()
            },
            Panels {
                forced_update: true,
                ..Panels::default()
            },
            Panels {
                forced_update: true,
                settings: true,
                ..Panels::default()
            },
        ] {
            assert_eq!(p.root_key(&action, false), RootKey::Pass, "{p:?}");
        }
    }

    #[test]
    fn forced_update_passes_text_and_swallows_everything_else() {
        let p = Panels {
            forced_update: true,
            settings: true,
            ..Panels::default()
        };
        assert_eq!(p.root_key(&KeyAction::Text, false), RootKey::Pass);
        assert_eq!(p.root_key(&KeyAction::Ignore, false), RootKey::Pass);
        assert_eq!(
            p.root_key(&KeyAction::App(AppCommand::OpenSettings), false),
            RootKey::Swallow
        );
        assert_eq!(
            p.root_key(&KeyAction::Chord("ctrl+x".into()), false),
            RootKey::Swallow
        );
        // nothing closes the overlay
        assert_eq!(
            p.root_key(&KeyAction::Chord("escape".into()), true),
            RootKey::Swallow
        );
    }

    #[test]
    fn nothing_open_runs_app_commands_and_passes_the_rest() {
        let p = Panels::default();
        assert_eq!(
            p.root_key(&KeyAction::App(AppCommand::NewWorkspace), false),
            RootKey::Run(AppCommand::NewWorkspace)
        );
        for action in [
            KeyAction::Text,
            KeyAction::Ignore,
            KeyAction::Chord("ctrl+x".into()),
            KeyAction::Chord("escape".into()),
        ] {
            assert_eq!(p.root_key(&action, true), RootKey::Pass, "{action:?}");
        }
    }

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
                    sign_in: true,
                    ..Panels::default()
                },
                Panel::SignIn,
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
            sign_in: true,
            ..Panels::default()
        };
        let mut closed = Vec::new();
        while let Some(top) = p.esc_target() {
            closed.push(top);
            match top {
                Panel::Settings => p.settings = false,
                Panel::Pairing => p.pairing = false,
                Panel::SignIn => p.sign_in = false,
                Panel::ForcedUpdate => unreachable!(),
            }
            // commands stay swallowed until the last one closed
            assert_eq!(p.allows_app_commands(), p.top().is_none());
        }
        assert_eq!(closed, [Panel::SignIn, Panel::Settings, Panel::Pairing]);
        assert!(p.allows_app_commands());
    }

    #[test]
    fn a_right_or_middle_press_only_closes_an_open_dropdown() {
        // Right or middle while a dropdown shows: the press closes it and
        // goes no further, so the terminal under it never pastes (review I2).
        assert!(press_only_closes_dropdowns(false, true));
        // The left button keeps its way: the dropdown closes itself on a
        // press outside and the click still lands where it was aimed.
        assert!(!press_only_closes_dropdowns(true, true));
        // No dropdown: every press goes on as usual.
        assert!(!press_only_closes_dropdowns(false, false));
        assert!(!press_only_closes_dropdowns(true, false));
    }

    #[test]
    fn a_panel_opens_only_when_nothing_above_it_is_open() {
        // Drawing order, topmost first.
        let order = [
            Panel::ForcedUpdate,
            Panel::SignIn,
            Panel::Settings,
            Panel::Pairing,
        ];
        let only = |panel: Panel| Panels {
            forced_update: panel == Panel::ForcedUpdate,
            sign_in: panel == Panel::SignIn,
            settings: panel == Panel::Settings,
            pairing: panel == Panel::Pairing,
        };
        let none = Panels::default();
        for (open_at, open) in order.into_iter().enumerate() {
            assert!(none.may_open(open), "{open:?} with nothing open");
            let panels = only(open);
            for (candidate_at, candidate) in order.into_iter().enumerate() {
                // A panel may open when the one up now is the same or lower.
                assert_eq!(
                    panels.may_open(candidate),
                    open_at >= candidate_at,
                    "{candidate:?} while {open:?} is open"
                );
            }
        }
    }

    #[test]
    fn sign_in_draws_above_settings_and_opens_while_settings_is_open() {
        // The sign-in dialog is opened from Settings -> Account, so it must
        // draw over Settings, open while Settings is up and close first.
        let both = Panels {
            settings: true,
            sign_in: true,
            ..Panels::default()
        };
        assert_eq!(both.top(), Some(Panel::SignIn));
        assert!(
            Panels {
                settings: true,
                ..Panels::default()
            }
            .may_open(Panel::SignIn)
        );
        // ... but Settings does not open over the dialog, nor the dialog
        // over the forced-update overlay.
        assert!(!both.may_open(Panel::Settings));
        assert!(
            !Panels {
                forced_update: true,
                ..Panels::default()
            }
            .may_open(Panel::SignIn)
        );
        // Esc closes the dialog first, then Settings.
        let mut p = both;
        assert_eq!(p.esc_target(), Some(Panel::SignIn));
        p.sign_in = false;
        assert_eq!(p.esc_target(), Some(Panel::Settings));
        assert!(!p.allows_app_commands());
        p.settings = false;
        assert_eq!(p.esc_target(), None);
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
