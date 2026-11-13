//! The keymap: which chord runs which app command. The defaults are the
//! README's table; `shortcuts.bindings` in the settings file rebinds or
//! unbinds an action (Settings › Keyboard Shortcuts writes it).

use crate::keys::{AppCommand, Dir, KeyCtx, KeyIn, is_window_system_key};
use crate::strings::{Lang, Str, shortcut_conflict, t};
use std::collections::BTreeMap;

/// A key with its modifiers. Written "ctrl+shift+n": lower case, modifiers in
/// ctrl, alt, shift order. The Windows key is never part of one (`accept`).
#[derive(Clone, Debug, PartialEq, Eq, Hash)]
pub struct Chord {
    pub ctrl: bool,
    pub alt: bool,
    pub shift: bool,
    /// The GPUI key name in lower case: "n", "tab", "left", "f5", "=", ",".
    pub key: String,
}

impl Chord {
    /// Reads "ctrl+shift+n" in any case and modifier order (the key "+" is
    /// written "ctrl++"). `None` for an unknown or repeated modifier, a
    /// missing key or a space.
    pub fn parse(text: &str) -> Option<Chord> {
        let text = text.to_lowercase();
        let (mods, key) = if text == "+" {
            ("", "+")
        } else if let Some(mods) = text.strip_suffix("++") {
            (mods, "+")
        } else {
            text.rsplit_once('+').unwrap_or(("", &text))
        };
        if key.is_empty()
            || key.chars().any(char::is_whitespace)
            || ["ctrl", "alt", "shift"].contains(&key)
        {
            return None;
        }
        let mut chord = Chord {
            ctrl: false,
            alt: false,
            shift: false,
            key: key.to_string(),
        };
        if !mods.is_empty() {
            for m in mods.split('+') {
                let on = match m {
                    "ctrl" => &mut chord.ctrl,
                    "alt" => &mut chord.alt,
                    "shift" => &mut chord.shift,
                    _ => return None,
                };
                if std::mem::replace(on, true) {
                    return None;
                }
            }
        }
        Some(chord.normalised())
    }

    /// The written form, the one `parse` reads and `shortcuts.bindings` stores.
    pub fn text(&self) -> String {
        self.joined(["ctrl+", "alt+", "shift+"], &self.key)
    }

    /// The form shown to people: "Ctrl+Shift+N", "Alt+←", "Ctrl+,".
    pub fn label(&self) -> String {
        self.joined(["Ctrl+", "Alt+", "Shift+"], &key_label(&self.key))
    }

    /// The chord a key-down is.
    pub fn of(k: &KeyIn) -> Chord {
        Chord {
            ctrl: k.ctrl,
            alt: k.alt,
            shift: k.shift,
            key: k.key.to_lowercase(),
        }
        .normalised()
    }

    /// GPUI-Windows reports Alt+Shift+= as "+" and Alt+Shift+- as "_", with
    /// shift consumed: each shape is the one chord "alt+shift+=" / "alt+shift+-".
    fn normalised(mut self) -> Chord {
        if self.alt {
            let key = match self.key.as_str() {
                "+" => "=",
                "_" => "-",
                _ => return self,
            };
            self.key = key.to_string();
            self.shift = true;
        }
        self
    }

    fn joined(&self, names: [&str; 3], key: &str) -> String {
        let mut s = String::new();
        for (on, name) in [self.ctrl, self.alt, self.shift].into_iter().zip(names) {
            if on {
                s.push_str(name);
            }
        }
        s.push_str(key);
        s
    }
}

/// Arrows as arrows, Esc short, any other key name capitalised ("F5", "Tab").
fn key_label(key: &str) -> String {
    let named = match key {
        "left" => "←",
        "right" => "→",
        "up" => "↑",
        "down" => "↓",
        "pageup" => "PageUp",
        "pagedown" => "PageDown",
        "escape" => "Esc",
        _ => {
            let mut chars = key.chars();
            return chars
                .next()
                .map(|first| first.to_uppercase().chain(chars).collect())
                .unwrap_or_default();
        }
    };
    named.to_string()
}

/// A command with a row in Settings › Keyboard Shortcuts.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum Action {
    OpenSettings,
    ToggleSidebar,
    NewWorkspace,
    NewTerminal,
    CloseTab,
    NextWorkspace,
    PrevWorkspace,
    SplitRight,
    SplitDown,
    FocusLeft,
    FocusRight,
    FocusUp,
    FocusDown,
    FocusBack,
    FocusForward,
    Copy,
    Paste,
}

impl Action {
    /// The list order.
    pub const ALL: &'static [Action] = &[
        Action::OpenSettings,
        Action::ToggleSidebar,
        Action::NewWorkspace,
        Action::NewTerminal,
        Action::CloseTab,
        Action::NextWorkspace,
        Action::PrevWorkspace,
        Action::SplitRight,
        Action::SplitDown,
        Action::FocusLeft,
        Action::FocusRight,
        Action::FocusUp,
        Action::FocusDown,
        Action::FocusBack,
        Action::FocusForward,
        Action::Copy,
        Action::Paste,
    ];

    /// The key in `shortcuts.bindings`: the Mac's action id.
    pub fn id(self) -> &'static str {
        match self {
            Action::OpenSettings => "openSettings",
            Action::ToggleSidebar => "toggleSidebar",
            Action::NewWorkspace => "newTab",
            Action::NewTerminal => "newSurface",
            Action::CloseTab => "closeTab",
            Action::NextWorkspace => "nextSidebarTab",
            Action::PrevWorkspace => "prevSidebarTab",
            Action::SplitRight => "splitRight",
            Action::SplitDown => "splitDown",
            Action::FocusLeft => "focusLeft",
            Action::FocusRight => "focusRight",
            Action::FocusUp => "focusUp",
            Action::FocusDown => "focusDown",
            Action::FocusBack => "focusHistoryBack",
            Action::FocusForward => "focusHistoryForward",
            Action::Copy => "copy",
            Action::Paste => "paste",
        }
    }

    /// The row's title: the Mac's.
    pub fn title(self) -> Str {
        match self {
            Action::OpenSettings => Str::SettingsActionOpenSettings,
            Action::ToggleSidebar => Str::SettingsActionToggleSidebar,
            Action::NewWorkspace => Str::SettingsActionNewWorkspace,
            Action::NewTerminal => Str::SettingsActionNewSurface,
            Action::CloseTab => Str::SettingsActionCloseTab,
            Action::NextWorkspace => Str::SettingsActionNextWorkspace,
            Action::PrevWorkspace => Str::SettingsActionPreviousWorkspace,
            Action::SplitRight => Str::SettingsActionSplitRight,
            Action::SplitDown => Str::SettingsActionSplitDown,
            Action::FocusLeft => Str::SettingsActionFocusPaneLeft,
            Action::FocusRight => Str::SettingsActionFocusPaneRight,
            Action::FocusUp => Str::SettingsActionFocusPaneUp,
            Action::FocusDown => Str::SettingsActionFocusPaneDown,
            Action::FocusBack => Str::SettingsActionFocusBack,
            Action::FocusForward => Str::SettingsActionFocusForward,
            Action::Copy => Str::SettingsActionCopy,
            Action::Paste => Str::SettingsActionPaste,
        }
    }

    /// The chord in `windows/README.md`'s table; Back and Forward have none.
    pub fn default_chord(self) -> Option<Chord> {
        let text = match self {
            Action::OpenSettings => "ctrl+,",
            Action::ToggleSidebar => "ctrl+shift+b",
            Action::NewWorkspace => "ctrl+shift+n",
            Action::NewTerminal => "ctrl+shift+t",
            Action::CloseTab => "ctrl+shift+w",
            Action::NextWorkspace => "ctrl+tab",
            Action::PrevWorkspace => "ctrl+shift+tab",
            Action::SplitRight => "alt+shift+=",
            Action::SplitDown => "alt+shift+-",
            Action::FocusLeft => "alt+left",
            Action::FocusRight => "alt+right",
            Action::FocusUp => "alt+up",
            Action::FocusDown => "alt+down",
            Action::FocusBack | Action::FocusForward => return None,
            Action::Copy => "ctrl+shift+c",
            Action::Paste => "ctrl+shift+v",
        };
        Chord::parse(text)
    }

    pub fn command(self) -> AppCommand {
        match self {
            Action::OpenSettings => AppCommand::OpenSettings,
            Action::ToggleSidebar => AppCommand::ToggleSidebar,
            Action::NewWorkspace => AppCommand::NewWorkspace,
            Action::NewTerminal => AppCommand::NewTerminal,
            Action::CloseTab => AppCommand::ClosePane,
            Action::NextWorkspace => AppCommand::NextTab,
            Action::PrevWorkspace => AppCommand::PrevTab,
            Action::SplitRight => AppCommand::SplitRight,
            Action::SplitDown => AppCommand::SplitDown,
            Action::FocusLeft => AppCommand::FocusPane(Dir::Left),
            Action::FocusRight => AppCommand::FocusPane(Dir::Right),
            Action::FocusUp => AppCommand::FocusPane(Dir::Up),
            Action::FocusDown => AppCommand::FocusPane(Dir::Down),
            Action::FocusBack => AppCommand::FocusBack,
            Action::FocusForward => AppCommand::FocusForward,
            Action::Copy => AppCommand::Copy,
            Action::Paste => AppCommand::Paste,
        }
    }
}

/// Why a chord cannot be a shortcut.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Refused {
    /// A plain key: it is typing.
    NeedsModifier,
    /// Alt+F4 and Alt+Space: Windows' own.
    SystemKey,
    /// Held with the Windows key.
    WindowsKey,
    /// Ctrl with Alt: AltGr, how some keyboards type characters.
    AltGr,
}

/// Whether `chord` (pressed with the Windows key when `win`) may be a
/// shortcut: it needs Ctrl or Alt, or is one of F1 to F12.
pub fn accept(chord: &Chord, win: bool) -> Result<(), Refused> {
    let key = KeyIn {
        key: &chord.key,
        ctrl: chord.ctrl,
        alt: chord.alt,
        shift: chord.shift,
        win: false,
    };
    let function_key = chord
        .key
        .strip_prefix('f')
        .and_then(|n| n.parse::<u8>().ok())
        .is_some_and(|n| (1..=12).contains(&n));
    if win {
        Err(Refused::WindowsKey)
    } else if chord.ctrl && chord.alt {
        Err(Refused::AltGr)
    } else if is_window_system_key(&key) {
        Err(Refused::SystemKey)
    } else if chord.ctrl || chord.alt || function_key {
        Ok(())
    } else {
        Err(Refused::NeedsModifier)
    }
}

/// Ctrl plus a letter: the shell has a use for it (Ctrl+N, Ctrl+T), and once
/// it is a shortcut the shell no longer gets it.
pub fn takes_from_the_shell(chord: &Chord) -> bool {
    chord.ctrl
        && !chord.alt
        && !chord.shift
        && chord.key.len() == 1
        && chord.key.as_bytes()[0].is_ascii_lowercase()
}

/// The README's second chords: they have no row and yield to any binding of
/// the same chord.
fn alias(chord: &Chord, ctx: &KeyCtx) -> Option<AppCommand> {
    match (chord.ctrl, chord.alt, chord.shift, chord.key.as_str()) {
        (true, false, false, "c") if ctx.has_selection => Some(AppCommand::Copy),
        (false, false, true, "insert") => Some(AppCommand::Paste),
        (true, false, false, "pagedown") => Some(AppCommand::NextTab),
        (true, false, false, "pageup") => Some(AppCommand::PrevTab),
        _ => None,
    }
}

/// An action and the chord it has now.
#[derive(Clone, Debug, PartialEq, Eq)]
struct Bound {
    action: Action,
    chord: Option<Chord>,
    /// `chord` is the action's default chord.
    default: bool,
}

/// The chord of every action: the defaults, with the user's bindings over them.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Keymap {
    /// One per action, in list order.
    bound: Vec<Bound>,
}

impl Keymap {
    /// `bindings` is `Settings::bindings` (`shortcuts.bindings`): action id
    /// to chord text, `None` for unbound. Unknown ids and unparsable chords
    /// are ignored, and so is a chord `accept` refuses: a hand-edited file
    /// cannot turn a typing key into a shortcut.
    pub fn from_bindings(bindings: &BTreeMap<String, Option<String>>) -> Keymap {
        let bound = Action::ALL
            .iter()
            .map(|&action| {
                let default = action.default_chord();
                let chord = match bindings.get(action.id()) {
                    None => default.clone(),
                    Some(None) => None,
                    Some(Some(text)) => Chord::parse(text)
                        .filter(|c| accept(c, false).is_ok())
                        .or_else(|| default.clone()),
                };
                Bound {
                    action,
                    default: chord == default,
                    chord,
                }
            })
            .collect();
        Keymap { bound }
    }

    fn bound(&self, action: Action) -> &Bound {
        self.bound
            .iter()
            .find(|b| b.action == action)
            .expect("every action has an entry")
    }

    pub fn chord(&self, action: Action) -> Option<&Chord> {
        self.bound(action).chord.as_ref()
    }

    pub fn is_default(&self, action: Action) -> bool {
        self.bound(action).default
    }

    /// The action that has `chord` now; an alias has none. When a
    /// hand-edited file gives one chord to two actions, the one the user
    /// rebound wins over the one that has it by default.
    pub fn holder(&self, chord: &Chord) -> Option<Action> {
        let holds = |b: &&Bound| b.chord.as_ref() == Some(chord);
        self.bound
            .iter()
            .filter(|b| !b.default)
            .find(holds)
            .or_else(|| self.bound.iter().find(holds))
            .map(|b| b.action)
    }

    /// The app command `k` runs: its action's, else a fixed alias (Ctrl+C
    /// copies while a selection exists, Shift+Insert pastes, Ctrl+PageDown /
    /// Ctrl+PageUp are next and previous workspace). The IME, the Windows
    /// key and AltGr are `keys::map_key`'s to rule out first.
    pub fn command(&self, k: &KeyIn, ctx: &KeyCtx) -> Option<AppCommand> {
        let chord = Chord::of(k);
        match self.holder(&chord) {
            Some(action) => Some(action.command()),
            None => alias(&chord, ctx),
        }
    }

    /// The `shortcuts.bindings` entry to store: `None` removes the entry (back to default).
    pub fn entry(action: Action, chord: Option<&Chord>) -> Option<Option<String>> {
        (chord != action.default_chord().as_ref()).then(|| chord.map(Chord::text))
    }
}

/// The sentence shown under a row whose recorded chord was refused.
pub fn refusal(lang: Lang, refused: Refused) -> &'static str {
    let sentence = match refused {
        Refused::NeedsModifier => Str::SettingsShortcutNeedsModifier,
        Refused::SystemKey => Str::SettingsShortcutReservedByWindows,
        Refused::WindowsKey => Str::SettingsShortcutWindowsKey,
        Refused::AltGr => Str::SettingsShortcutCtrlAlt,
    };
    t(lang, sentence)
}

/// The conflict banner: "<holder's title> already uses this shortcut."
pub fn conflict(lang: Lang, holder: Action) -> String {
    shortcut_conflict(lang, t(lang, holder.title()))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::keys::{AppCommand, Dir, KeyAction, KeyCtx, KeyIn, map_key};
    use crate::strings::{Lang, Str, t};
    use std::collections::BTreeMap;

    const NO_SEL: KeyCtx = KeyCtx {
        has_selection: false,
        composing: false,
    };
    const SEL: KeyCtx = KeyCtx {
        has_selection: true,
        composing: false,
    };

    fn key(key: &str, ctrl: bool, alt: bool, shift: bool) -> KeyIn<'_> {
        KeyIn {
            key,
            ctrl,
            alt,
            shift,
            win: false,
        }
    }
    fn pressed(c: &Chord) -> KeyIn<'_> {
        key(&c.key, c.ctrl, c.alt, c.shift)
    }
    fn chord(text: &str) -> Chord {
        Chord::parse(text).unwrap_or_else(|| panic!("{text} does not parse"))
    }
    fn defaults() -> Keymap {
        Keymap::from_bindings(&BTreeMap::new())
    }
    fn with(bindings: &[(&str, Option<&str>)]) -> Keymap {
        Keymap::from_bindings(
            &bindings
                .iter()
                .map(|(id, c)| (id.to_string(), c.map(str::to_string)))
                .collect(),
        )
    }
    fn app(c: AppCommand) -> KeyAction {
        KeyAction::App(c)
    }
    fn to_shell(s: &str) -> KeyAction {
        KeyAction::Chord(s.to_string())
    }

    #[test]
    fn the_default_keymap_is_the_readme_table() {
        use Action::*;
        let table = [
            (OpenSettings, Some("ctrl+,"), AppCommand::OpenSettings),
            (
                ToggleSidebar,
                Some("ctrl+shift+b"),
                AppCommand::ToggleSidebar,
            ),
            (NewWorkspace, Some("ctrl+shift+n"), AppCommand::NewWorkspace),
            (NewTerminal, Some("ctrl+shift+t"), AppCommand::NewTerminal),
            (CloseTab, Some("ctrl+shift+w"), AppCommand::ClosePane),
            (NextWorkspace, Some("ctrl+tab"), AppCommand::NextTab),
            (PrevWorkspace, Some("ctrl+shift+tab"), AppCommand::PrevTab),
            (SplitRight, Some("alt+shift+="), AppCommand::SplitRight),
            (SplitDown, Some("alt+shift+-"), AppCommand::SplitDown),
            (
                FocusLeft,
                Some("alt+left"),
                AppCommand::FocusPane(Dir::Left),
            ),
            (
                FocusRight,
                Some("alt+right"),
                AppCommand::FocusPane(Dir::Right),
            ),
            (FocusUp, Some("alt+up"), AppCommand::FocusPane(Dir::Up)),
            (
                FocusDown,
                Some("alt+down"),
                AppCommand::FocusPane(Dir::Down),
            ),
            (FocusBack, None, AppCommand::FocusBack),
            (FocusForward, None, AppCommand::FocusForward),
            (Copy, Some("ctrl+shift+c"), AppCommand::Copy),
            (Paste, Some("ctrl+shift+v"), AppCommand::Paste),
        ];
        let km = defaults();
        // the list order is the table's
        assert_eq!(
            Action::ALL,
            table.map(|(action, _, _)| action).as_slice(),
            "list order"
        );
        for (action, text, command) in table {
            assert_eq!(action.default_chord().map(|c| c.text()).as_deref(), text);
            assert_eq!(km.chord(action).map(Chord::text).as_deref(), text);
            assert!(km.is_default(action), "{action:?}");
            assert_eq!(action.command(), command, "{action:?}");
            if let Some(c) = km.chord(action) {
                assert_eq!(
                    km.command(&pressed(c), &NO_SEL),
                    Some(command),
                    "{action:?}"
                );
                assert_eq!(km.holder(c), Some(action), "{action:?}");
            }
        }
        // the README's second chords: fixed aliases without a row
        assert_eq!(
            km.command(&key("insert", false, false, true), &NO_SEL),
            Some(AppCommand::Paste)
        );
        assert_eq!(
            km.command(&key("pagedown", true, false, false), &NO_SEL),
            Some(AppCommand::NextTab)
        );
        assert_eq!(
            km.command(&key("pageup", true, false, false), &NO_SEL),
            Some(AppCommand::PrevTab)
        );
        assert_eq!(
            km.command(&key("c", true, false, false), &SEL),
            Some(AppCommand::Copy)
        );
        assert_eq!(km.command(&key("c", true, false, false), &NO_SEL), None);
        // the Mac's action ids (the `shortcuts.bindings` keys) and titles
        assert_eq!(
            Action::ALL.iter().map(|a| a.id()).collect::<Vec<_>>(),
            [
                "openSettings",
                "toggleSidebar",
                "newTab",
                "newSurface",
                "closeTab",
                "nextSidebarTab",
                "prevSidebarTab",
                "splitRight",
                "splitDown",
                "focusLeft",
                "focusRight",
                "focusUp",
                "focusDown",
                "focusHistoryBack",
                "focusHistoryForward",
                "copy",
                "paste",
            ]
        );
        assert_eq!(
            Action::ALL
                .iter()
                .map(|a| t(Lang::En, a.title()))
                .collect::<Vec<_>>(),
            [
                "Settings…",
                "Toggle Left Sidebar",
                "New Workspace",
                "New Surface",
                "Close Tab",
                "Next Workspace",
                "Previous Workspace",
                "Split Right",
                "Split Down",
                "Focus Pane Left",
                "Focus Pane Right",
                "Focus Pane Up",
                "Focus Pane Down",
                "Focus Back",
                "Focus Forward",
                "Copy",
                "Paste",
            ]
        );
        // unknown ids and unparsable chords are ignored
        assert_eq!(
            with(&[
                ("noSuchAction", Some("ctrl+shift+k")),
                ("newTab", Some("cmd+n")),
                ("closeTab", Some("")),
                ("splitRight", Some("ctrl+shift")),
            ]),
            km
        );
    }

    #[test]
    fn chords_parse_and_print_round_trip() {
        for text in [
            "ctrl+,",
            "ctrl+shift+n",
            "ctrl+shift+tab",
            "alt+shift+=",
            "alt+shift+-",
            "alt+left",
            "ctrl+pagedown",
            "shift+insert",
            "f5",
            "shift+f12",
            "ctrl+alt+shift+7",
            "ctrl++",
        ] {
            assert_eq!(Chord::parse(text).map(|c| c.text()).as_deref(), Some(text));
        }
        assert_eq!(
            chord("ctrl+shift+n"),
            Chord {
                ctrl: true,
                alt: false,
                shift: true,
                key: "n".into()
            }
        );
        // any case and modifier order reads as the one written form
        assert_eq!(chord("Shift+Ctrl+N").text(), "ctrl+shift+n");
        assert_eq!(chord("ALT+Left").text(), "alt+left");
        for bad in [
            "",
            "ctrl+",
            "ctrl+shift",
            "cmd+n",
            "win+e",
            "ctrl+ctrl+n",
            "ctrl + n",
        ] {
            assert_eq!(Chord::parse(bad), None, "{bad:?}");
        }
        for (text, label) in [
            ("ctrl+shift+n", "Ctrl+Shift+N"),
            ("alt+left", "Alt+←"),
            ("alt+right", "Alt+→"),
            ("alt+up", "Alt+↑"),
            ("alt+down", "Alt+↓"),
            ("ctrl+,", "Ctrl+,"),
            ("alt+shift+=", "Alt+Shift+="),
            ("ctrl+shift+tab", "Ctrl+Shift+Tab"),
            ("ctrl+pagedown", "Ctrl+PageDown"),
            ("shift+insert", "Shift+Insert"),
            ("f5", "F5"),
            ("ctrl+escape", "Ctrl+Esc"),
        ] {
            assert_eq!(chord(text).label(), label, "{text}");
        }
    }

    #[test]
    fn gpui_windows_shapes_match_their_chords() {
        // GPUI-Windows reports Alt+Shift+= as "+" and Alt+Shift+- as "_", shift consumed
        assert_eq!(
            Chord::of(&key("+", false, true, false)),
            chord("alt+shift+=")
        );
        assert_eq!(
            Chord::of(&key("_", false, true, false)),
            chord("alt+shift+-")
        );
        assert_eq!(
            Chord::of(&key("+", false, true, true)),
            chord("alt+shift+=")
        );
        assert_eq!(
            Chord::of(&key("_", false, true, true)),
            chord("alt+shift+-")
        );
        assert_eq!(chord("alt++"), chord("alt+shift+="));
        // the Mac shapes are the same chords; unshifted Alt+= is another one
        assert_eq!(
            Chord::of(&key("=", false, true, true)),
            chord("alt+shift+=")
        );
        assert_eq!(
            Chord::of(&key("-", false, true, true)),
            chord("alt+shift+-")
        );
        assert_eq!(Chord::of(&key("=", false, true, false)), chord("alt+="));
        // letters lower case
        assert_eq!(
            Chord::of(&key("N", true, false, true)),
            chord("ctrl+shift+n")
        );
        // an action rebound to Alt+Shift+= takes both shapes
        let km = with(&[
            ("splitRight", Some("ctrl+shift+r")),
            ("toggleSidebar", Some("alt+shift+=")),
        ]);
        for k in [key("+", false, true, false), key("=", false, true, true)] {
            assert_eq!(
                map_key(&k, &km, &NO_SEL),
                app(AppCommand::ToggleSidebar),
                "{k:?}"
            );
        }
    }

    #[test]
    fn a_rebound_action_leaves_its_old_chord_to_the_shell() {
        let km = with(&[("newTab", Some("ctrl+shift+k"))]);
        assert_eq!(
            map_key(&key("n", true, false, true), &km, &NO_SEL),
            to_shell("ctrl+shift+n")
        );
        assert_eq!(
            map_key(&key("k", true, false, true), &km, &NO_SEL),
            app(AppCommand::NewWorkspace)
        );
        assert_eq!(km.chord(Action::NewWorkspace), Some(&chord("ctrl+shift+k")));
        assert!(!km.is_default(Action::NewWorkspace));
        // the others keep theirs
        assert!(km.is_default(Action::NewTerminal));
        assert_eq!(
            map_key(&key("t", true, false, true), &km, &NO_SEL),
            app(AppCommand::NewTerminal)
        );
    }

    #[test]
    fn an_unbound_action_has_no_chord() {
        let km = with(&[("openSettings", None)]);
        assert_eq!(km.chord(Action::OpenSettings), None);
        assert!(!km.is_default(Action::OpenSettings));
        assert_eq!(km.holder(&chord("ctrl+,")), None);
        assert_eq!(km.command(&key(",", true, false, false), &NO_SEL), None);
        assert_eq!(
            map_key(&key(",", true, false, false), &km, &NO_SEL),
            to_shell("ctrl+,")
        );
        // Back and Forward start unbound, and a binding makes them run
        let km = defaults();
        assert_eq!(km.chord(Action::FocusBack), None);
        assert_eq!(km.chord(Action::FocusForward), None);
        let km = with(&[("focusHistoryBack", Some("alt+shift+left"))]);
        assert_eq!(
            map_key(&key("left", false, true, true), &km, &NO_SEL),
            app(AppCommand::FocusBack)
        );
    }

    #[test]
    fn a_user_binding_takes_an_alias() {
        assert_eq!(
            accept(&chord("shift+insert"), false),
            Err(Refused::NeedsModifier)
        );
        // a file that binds it anyway is ignored: Split Right keeps its chord
        let km = with(&[("splitRight", Some("shift+insert"))]);
        assert!(km.is_default(Action::SplitRight));
        assert_eq!(
            map_key(&key("insert", false, false, true), &km, &NO_SEL),
            app(AppCommand::Paste)
        );
        // Ctrl+PageDown is accepted, and Next Workspace's alias yields
        assert_eq!(accept(&chord("ctrl+pagedown"), false), Ok(()));
        let km = with(&[("splitRight", Some("ctrl+pagedown"))]);
        assert_eq!(
            map_key(&key("pagedown", true, false, false), &km, &NO_SEL),
            app(AppCommand::SplitRight)
        );
        // Next Workspace keeps Ctrl+Tab; the other aliases stay
        assert_eq!(
            map_key(&key("tab", true, false, false), &km, &NO_SEL),
            app(AppCommand::NextTab)
        );
        assert_eq!(
            map_key(&key("pageup", true, false, false), &km, &NO_SEL),
            app(AppCommand::PrevTab)
        );
        // Ctrl+C with a selection yields too
        let km = with(&[("newSurface", Some("ctrl+c"))]);
        assert_eq!(
            map_key(&key("c", true, false, false), &km, &SEL),
            app(AppCommand::NewTerminal)
        );
    }

    #[test]
    fn altgr_and_system_keys_are_refused() {
        assert_eq!(accept(&chord("ctrl+alt+e"), false), Err(Refused::AltGr));
        assert_eq!(
            accept(&chord("ctrl+alt+shift+7"), false),
            Err(Refused::AltGr)
        );
        assert_eq!(accept(&chord("alt+f4"), false), Err(Refused::SystemKey));
        assert_eq!(accept(&chord("alt+space"), false), Err(Refused::SystemKey));
        assert_eq!(
            accept(&chord("ctrl+shift+n"), true),
            Err(Refused::WindowsKey)
        );
        assert_eq!(accept(&chord("f5"), true), Err(Refused::WindowsKey));
        // near misses are not Windows' keys
        assert_eq!(accept(&chord("alt+shift+f4"), false), Ok(()));
        assert_eq!(accept(&chord("ctrl+f4"), false), Ok(()));
        assert_eq!(accept(&chord("ctrl+space"), false), Ok(()));
        // a file that binds them anyway is ignored: Ctrl+Alt stays text, Alt+F4 Windows'
        let km = with(&[
            ("newTab", Some("ctrl+alt+e")),
            ("newSurface", Some("alt+f4")),
        ]);
        assert_eq!(km, defaults());
        assert_eq!(
            map_key(&key("e", true, true, false), &km, &NO_SEL),
            KeyAction::Text
        );
        assert_eq!(
            map_key(&key("f4", false, true, false), &km, &NO_SEL),
            KeyAction::Ignore
        );
        // one sentence for each refusal, in both languages
        for lang in [Lang::En, Lang::Vi] {
            for (refused, sentence) in [
                (Refused::NeedsModifier, Str::SettingsShortcutNeedsModifier),
                (Refused::SystemKey, Str::SettingsShortcutReservedByWindows),
                (Refused::WindowsKey, Str::SettingsShortcutWindowsKey),
                (Refused::AltGr, Str::SettingsShortcutCtrlAlt),
            ] {
                assert_eq!(refusal(lang, refused), t(lang, sentence));
            }
        }
    }

    #[test]
    fn function_keys_need_no_modifier() {
        for n in 1..=12 {
            let f = format!("f{n}");
            assert_eq!(accept(&chord(&f), false), Ok(()), "{f}");
            assert_eq!(accept(&chord(&format!("shift+{f}")), false), Ok(()), "{f}");
        }
        assert_eq!(accept(&chord("f13"), false), Err(Refused::NeedsModifier));
        assert_eq!(accept(&chord("ctrl+f13"), false), Ok(()));
        for plain in [
            "a",
            "shift+a",
            "1",
            "enter",
            "escape",
            "tab",
            "shift+tab",
            "space",
            "left",
            "insert",
        ] {
            assert_eq!(
                accept(&chord(plain), false),
                Err(Refused::NeedsModifier),
                "{plain}"
            );
        }
        // bound, F5 runs its command; an unbound F6 still reaches the shell
        let km = with(&[("newSurface", Some("f5"))]);
        assert_eq!(
            map_key(&key("f5", false, false, false), &km, &NO_SEL),
            app(AppCommand::NewTerminal)
        );
        assert_eq!(
            map_key(&key("f6", false, false, false), &km, &NO_SEL),
            to_shell("f6")
        );
    }

    #[test]
    fn the_holder_of_a_chord_is_found() {
        let km = defaults();
        assert_eq!(km.holder(&chord("ctrl+shift+t")), Some(Action::NewTerminal));
        assert_eq!(km.holder(&chord("alt+shift+=")), Some(Action::SplitRight));
        assert_eq!(km.holder(&chord("ctrl+shift+k")), None);
        // an alias has no row: nobody holds it
        for alias in ["ctrl+pagedown", "ctrl+pageup", "shift+insert", "ctrl+c"] {
            assert_eq!(km.holder(&chord(alias)), None, "{alias}");
        }
        // after a rebind the new chord is the action's, the old one nobody's
        let km = with(&[("newTab", Some("ctrl+shift+k"))]);
        assert_eq!(
            km.holder(&chord("ctrl+shift+k")),
            Some(Action::NewWorkspace)
        );
        assert_eq!(km.holder(&chord("ctrl+shift+n")), None);
        // a hand-edited file that gives one chord to two actions: the user's binding wins
        let km = with(&[("newTab", Some("ctrl+shift+t"))]);
        assert_eq!(
            km.holder(&chord("ctrl+shift+t")),
            Some(Action::NewWorkspace)
        );
        assert_eq!(
            map_key(&key("t", true, false, true), &km, &NO_SEL),
            app(AppCommand::NewWorkspace)
        );
        // the banner names the holder
        assert_eq!(
            conflict(Lang::En, Action::NewTerminal),
            "New Surface already uses this shortcut."
        );
        assert_eq!(
            conflict(Lang::Vi, Action::SplitRight),
            "Chia sang phải đang dùng phím tắt này."
        );
    }

    #[test]
    fn an_entry_equal_to_the_default_is_removed() {
        let k = chord("ctrl+shift+k");
        assert_eq!(
            Keymap::entry(Action::NewWorkspace, Some(&chord("ctrl+shift+n"))),
            None
        );
        assert_eq!(
            Keymap::entry(Action::NewWorkspace, Some(&k)),
            Some(Some("ctrl+shift+k".to_string()))
        );
        assert_eq!(Keymap::entry(Action::NewWorkspace, None), Some(None));
        // Back has no default chord: unbound is its default
        assert_eq!(Keymap::entry(Action::FocusBack, None), None);
        assert_eq!(
            Keymap::entry(Action::FocusBack, Some(&chord("f6"))),
            Some(Some("f6".to_string()))
        );
        // what is stored reads back as the same keymap
        let wanted = [
            (Action::NewWorkspace, Some(k.clone())),
            (Action::OpenSettings, None),
            (Action::FocusBack, Some(chord("f6"))),
            (Action::Copy, Some(chord("ctrl+shift+c"))),
        ];
        let bindings: BTreeMap<String, Option<String>> = wanted
            .iter()
            .filter_map(|(a, c)| Keymap::entry(*a, c.as_ref()).map(|e| (a.id().to_string(), e)))
            .collect();
        assert_eq!(bindings.len(), 3, "{bindings:?}");
        let km = Keymap::from_bindings(&bindings);
        for (action, c) in &wanted {
            assert_eq!(km.chord(*action), c.as_ref(), "{action:?}");
        }
        assert!(km.is_default(Action::Copy));
    }

    #[test]
    fn ctrl_letter_is_flagged_as_taken_from_the_shell() {
        assert!(takes_from_the_shell(&chord("ctrl+n")));
        assert!(takes_from_the_shell(&chord("ctrl+z")));
        for other in [
            "ctrl+shift+n",
            "ctrl+alt+n",
            "alt+n",
            "ctrl+,",
            "ctrl+1",
            "ctrl+tab",
            "ctrl+f5",
            "f5",
        ] {
            assert!(!takes_from_the_shell(&chord(other)), "{other}");
        }
        // it is accepted (with the caption), and then Ctrl+N no longer reaches the shell
        assert_eq!(accept(&chord("ctrl+n"), false), Ok(()));
        let km = with(&[("newTab", Some("ctrl+n"))]);
        assert_eq!(
            map_key(&key("n", true, false, false), &km, &NO_SEL),
            app(AppCommand::NewWorkspace)
        );
    }

    fn stored(entries: &[(&str, Option<&str>)]) -> BTreeMap<String, Option<String>> {
        entries
            .iter()
            .map(|(id, c)| (id.to_string(), c.map(str::to_string)))
            .collect()
    }

    /// The search bar of Settings › Keyboard Shortcuts: every word typed must be in the
    /// action's title, in the language shown or the other one, without case or Vietnamese
    /// marks. Blank text lists every action, in list order.
    #[test]
    fn the_list_filters_by_text_in_either_language() {
        let km = defaults();
        let text = |q: &str, lang: Lang| listed(&km, Some(ListFilter::Text(q)), lang);
        assert_eq!(listed(&km, None, Lang::En), Action::ALL);
        assert_eq!(listed(&km, None, Lang::Vi), Action::ALL);
        assert_eq!(text("", Lang::En), Action::ALL);
        assert_eq!(text("   ", Lang::Vi), Action::ALL);
        // The language shown, any case, in list order.
        assert_eq!(
            text("split", Lang::En),
            [Action::SplitRight, Action::SplitDown]
        );
        assert_eq!(text("SPLIT right", Lang::En), [Action::SplitRight]);
        assert_eq!(text("settings", Lang::En), [Action::OpenSettings]);
        // Vietnamese typed with or without its marks ("Chia sang phải").
        assert_eq!(text("Chia sang phải", Lang::Vi), [Action::SplitRight]);
        assert_eq!(text("chia phai", Lang::Vi), [Action::SplitRight]);
        assert_eq!(text("CHIA", Lang::Vi), [Action::SplitRight, Action::SplitDown]);
        assert_eq!(
            text("phai", Lang::Vi),
            [Action::SplitRight, Action::FocusRight]
        );
        assert_eq!(text("dan", Lang::Vi), [Action::Paste]);
        // Decomposed marks fold the same way.
        assert_eq!(text("pha\u{0309}i", Lang::Vi), text("phai", Lang::Vi));
        // The other language's title finds it too.
        assert_eq!(text("split right", Lang::Vi), [Action::SplitRight]);
        assert_eq!(text("chia sang phai", Lang::En), [Action::SplitRight]);
        assert_eq!(text("cài đặt", Lang::En), [Action::OpenSettings]);
        // Every word must match.
        assert!(text("split zzz", Lang::En).is_empty());
        assert!(text("zzz", Lang::Vi).is_empty());
    }

    /// "Detect Shortcut": the list shows the actions the chord pressed runs now (the user's
    /// binding, not the default), however GPUI-Windows reports it. An alias has no row.
    #[test]
    fn the_list_filters_by_chord() {
        let by = |km: &Keymap, c: &Chord, lang: Lang| listed(km, Some(ListFilter::Chord(c)), lang);
        let km = defaults();
        assert_eq!(
            by(&km, &chord("ctrl+shift+n"), Lang::En),
            [Action::NewWorkspace]
        );
        assert!(by(&km, &chord("f5"), Lang::En).is_empty());
        // Alt+Shift+= as GPUI-Windows sends it: Alt and "+".
        assert_eq!(
            by(&km, &Chord::of(&key("+", false, true, false)), Lang::Vi),
            [Action::SplitRight]
        );
        for nobody in ["ctrl+shift+k", "ctrl+pagedown", "shift+insert", "ctrl+c", "a"] {
            assert!(by(&km, &chord(nobody), Lang::En).is_empty(), "{nobody}");
        }
        // The current binding: the rebound chord, not the old one; an unbound action never.
        let km = with(&[("splitRight", Some("ctrl+shift+k")), ("newTab", None)]);
        assert_eq!(
            by(&km, &chord("ctrl+shift+k"), Lang::En),
            [Action::SplitRight]
        );
        assert!(by(&km, &chord("alt+shift+="), Lang::En).is_empty());
        assert!(by(&km, &chord("ctrl+shift+n"), Lang::En).is_empty());
        // A hand-edited file giving one chord to two actions: both are shown.
        let km = with(&[("newTab", Some("ctrl+shift+t"))]);
        assert_eq!(
            by(&km, &chord("ctrl+shift+t"), Lang::En),
            [Action::NewWorkspace, Action::NewTerminal]
        );
    }

    /// A recorded chord another action holds is not saved: the holder is named and the
    /// bindings stay as they were. Any other chord replaces the action's entry and keeps
    /// every other entry, ids this version does not know included.
    #[test]
    fn a_chord_another_action_holds_is_not_saved() {
        let none = BTreeMap::new();
        let km = defaults();
        assert_eq!(
            rebound(&km, &none, Action::SplitRight, Some(&chord("ctrl+shift+k"))),
            Ok(stored(&[("splitRight", Some("ctrl+shift+k"))]))
        );
        assert_eq!(
            rebound(&km, &none, Action::SplitRight, Some(&chord("ctrl+shift+n"))),
            Err(Action::NewWorkspace)
        );
        assert_eq!(
            rebound(&km, &none, Action::Copy, Some(&chord("ctrl+tab"))),
            Err(Action::NextWorkspace)
        );
        // Its own chord again changes nothing.
        assert_eq!(
            rebound(&km, &none, Action::NewWorkspace, Some(&chord("ctrl+shift+n"))),
            Ok(none.clone())
        );
        // An alias yields to a binding: Shift+Insert can be bound.
        assert_eq!(
            rebound(&km, &none, Action::SplitDown, Some(&chord("shift+insert"))),
            Ok(stored(&[("splitDown", Some("shift+insert"))]))
        );
        // A chord a rebind freed can be taken; the other entries stay.
        let b = stored(&[("newTab", Some("ctrl+shift+k")), ("futureAction", Some("ctrl+q"))]);
        let km = Keymap::from_bindings(&b);
        assert_eq!(
            rebound(&km, &b, Action::SplitRight, Some(&chord("ctrl+shift+n"))),
            Ok(stored(&[
                ("newTab", Some("ctrl+shift+k")),
                ("futureAction", Some("ctrl+q")),
                ("splitRight", Some("ctrl+shift+n")),
            ]))
        );
        assert_eq!(
            rebound(&km, &b, Action::SplitRight, Some(&chord("ctrl+shift+k"))),
            Err(Action::NewWorkspace)
        );
    }

    /// The X beside a recorder unbinds; once the action is unbound it is a restore arrow that
    /// puts the default back (and is refused like any chord when another action took the
    /// default meanwhile). Back and Forward have no default: unbound, their X does nothing.
    #[test]
    fn x_unbinds_and_then_restores_the_default() {
        let km = defaults();
        let none = BTreeMap::new();
        let default = Action::SplitRight.default_chord();
        assert_eq!(clear_button(&km, Action::SplitRight), ClearButton::Clear);
        let cleared = rebound(&km, &none, Action::SplitRight, None).unwrap();
        assert_eq!(cleared, stored(&[("splitRight", None)]));
        let km = Keymap::from_bindings(&cleared);
        assert_eq!(km.chord(Action::SplitRight), None);
        assert_eq!(clear_button(&km, Action::SplitRight), ClearButton::Restore);
        assert_eq!(
            rebound(&km, &cleared, Action::SplitRight, default.as_ref()),
            Ok(none.clone())
        );
        // A rebound action: X unbinds it, and restore gives the default, not the old chord.
        let b = stored(&[("splitRight", Some("ctrl+shift+k"))]);
        let km = Keymap::from_bindings(&b);
        assert_eq!(clear_button(&km, Action::SplitRight), ClearButton::Clear);
        let cleared = rebound(&km, &b, Action::SplitRight, None).unwrap();
        assert_eq!(cleared, stored(&[("splitRight", None)]));
        // Another action took the default meanwhile: restoring it is a conflict.
        let b = stored(&[("splitRight", None), ("splitDown", Some("alt+shift+="))]);
        let km = Keymap::from_bindings(&b);
        assert_eq!(clear_button(&km, Action::SplitRight), ClearButton::Restore);
        assert_eq!(
            rebound(&km, &b, Action::SplitRight, default.as_ref()),
            Err(Action::SplitDown)
        );
        // Back: nothing to unbind or restore until it is bound; unbinding it removes its entry.
        assert_eq!(clear_button(&defaults(), Action::FocusBack), ClearButton::Off);
        let b = stored(&[("focusHistoryBack", Some("f6"))]);
        let km = Keymap::from_bindings(&b);
        assert_eq!(clear_button(&km, Action::FocusBack), ClearButton::Clear);
        assert_eq!(rebound(&km, &b, Action::FocusBack, None), Ok(none));
    }
}
