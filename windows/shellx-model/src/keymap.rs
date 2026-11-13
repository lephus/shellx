//! The keymap: which chord runs which app command. The defaults are the
//! README's table; `shortcuts.bindings` in the settings file rebinds or
//! unbinds an action (Settings › Keyboard Shortcuts writes it).

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
}
