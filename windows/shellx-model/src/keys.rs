//! Key mapping following Windows Terminal conventions.

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Dir {
    Left,
    Right,
    Up,
    Down,
}

/// `key` is the GPUI key name: "a", "c", "enter", "tab", "left", "f5", "=", "," ...
#[derive(Clone, Copy, Debug)]
pub struct KeyIn<'a> {
    pub key: &'a str,
    pub ctrl: bool,
    pub alt: bool,
    pub shift: bool,
    pub win: bool,
}

#[derive(Clone, Copy, Debug)]
pub struct KeyCtx {
    pub has_selection: bool,
    pub composing: bool,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum AppCommand {
    Copy,
    Paste,
    NewTab,
    ClosePane,
    NextTab,
    PrevTab,
    SplitRight,
    SplitDown,
    FocusPane(Dir),
    ToggleSidebar,
    OpenSettings,
}

#[derive(Debug, PartialEq, Eq)]
pub enum KeyAction {
    App(AppCommand),
    /// libghostty chord grammar: "ctrl+alt+shift+<key>".
    Chord(String),
    /// Let the IME / WM_CHAR path deliver it.
    Text,
    Ignore,
}

fn is_named(key: &str) -> bool {
    matches!(
        key,
        "enter"
            | "backspace"
            | "tab"
            | "escape"
            | "up"
            | "down"
            | "left"
            | "right"
            | "home"
            | "end"
            | "pageup"
            | "pagedown"
            | "insert"
            | "delete"
    ) || key
        .strip_prefix('f')
        .and_then(|n| n.parse::<u8>().ok())
        .is_some_and(|n| (1..=24).contains(&n))
}

fn app_binding(key: &str, ctrl: bool, alt: bool, shift: bool, ctx: &KeyCtx) -> Option<AppCommand> {
    use AppCommand::*;
    match (ctrl, alt, shift, key) {
        (true, false, true, "c") => Some(Copy),
        (true, false, false, "c") if ctx.has_selection => Some(Copy),
        (true, false, true, "v") => Some(Paste),
        (false, false, true, "insert") => Some(Paste),
        (true, false, true, "t") => Some(NewTab),
        (true, false, true, "w") => Some(ClosePane),
        (true, false, false, "tab") => Some(NextTab),
        (true, false, true, "tab") => Some(PrevTab),
        (true, false, false, "pagedown") => Some(NextTab),
        (true, false, false, "pageup") => Some(PrevTab),
        (false, true, true, "=" | "+") => Some(SplitRight),
        (false, true, true, "-" | "_") => Some(SplitDown),
        (false, true, false, "left") => Some(FocusPane(Dir::Left)),
        (false, true, false, "right") => Some(FocusPane(Dir::Right)),
        (false, true, false, "up") => Some(FocusPane(Dir::Up)),
        (false, true, false, "down") => Some(FocusPane(Dir::Down)),
        (true, false, true, "b") => Some(ToggleSidebar),
        (true, false, false, ",") => Some(OpenSettings),
        _ => None,
    }
}

pub fn map_key(k: &KeyIn, ctx: &KeyCtx) -> KeyAction {
    if ctx.composing || k.win {
        return KeyAction::Ignore;
    }
    let key = k.key.to_lowercase();
    if let Some(cmd) = app_binding(&key, k.ctrl, k.alt, k.shift, ctx) {
        return KeyAction::App(cmd);
    }
    if k.ctrl && k.alt {
        return KeyAction::Text; // AltGr
    }
    let space_mod = key == "space" && (k.ctrl || k.alt);
    if is_named(&key) || space_mod || k.ctrl || k.alt {
        let mut s = String::new();
        for (on, name) in [(k.ctrl, "ctrl+"), (k.alt, "alt+"), (k.shift, "shift+")] {
            if on {
                s.push_str(name);
            }
        }
        s.push_str(&key);
        return KeyAction::Chord(s);
    }
    KeyAction::Text
}

#[cfg(test)]
mod tests {
    use super::*;

    fn k(key: &str) -> KeyIn<'_> {
        KeyIn {
            key,
            ctrl: false,
            alt: false,
            shift: false,
            win: false,
        }
    }
    fn ctrl(key: &str) -> KeyIn<'_> {
        KeyIn {
            ctrl: true,
            ..k(key)
        }
    }
    fn cs(key: &str) -> KeyIn<'_> {
        KeyIn {
            ctrl: true,
            shift: true,
            ..k(key)
        }
    }
    fn alt(key: &str) -> KeyIn<'_> {
        KeyIn {
            alt: true,
            ..k(key)
        }
    }
    fn alt_shift(key: &str) -> KeyIn<'_> {
        KeyIn {
            alt: true,
            shift: true,
            ..k(key)
        }
    }
    const NO_SEL: KeyCtx = KeyCtx {
        has_selection: false,
        composing: false,
    };
    const SEL: KeyCtx = KeyCtx {
        has_selection: true,
        composing: false,
    };

    fn app(c: AppCommand) -> KeyAction {
        KeyAction::App(c)
    }
    fn chord(s: &str) -> KeyAction {
        KeyAction::Chord(s.to_string())
    }

    #[test]
    fn ctrl_c_copies_only_with_selection() {
        assert_eq!(map_key(&ctrl("c"), &SEL), app(AppCommand::Copy));
        assert_eq!(map_key(&ctrl("c"), &NO_SEL), chord("ctrl+c"));
        assert_eq!(map_key(&cs("c"), &NO_SEL), app(AppCommand::Copy));
        assert_eq!(map_key(&cs("C"), &NO_SEL), app(AppCommand::Copy));
        // Ctrl+Shift+C with selection is still Copy; Ctrl+Alt+C with selection is not.
        let ca = KeyIn {
            ctrl: true,
            alt: true,
            ..k("c")
        };
        assert_ne!(map_key(&ca, &SEL), app(AppCommand::Copy));
    }

    #[test]
    fn ctrl_v_goes_to_shell() {
        assert_eq!(map_key(&ctrl("v"), &NO_SEL), chord("ctrl+v"));
        assert_eq!(map_key(&ctrl("v"), &SEL), chord("ctrl+v"));
    }

    #[test]
    fn ctrl_shift_v_and_shift_insert_paste() {
        assert_eq!(map_key(&cs("v"), &NO_SEL), app(AppCommand::Paste));
        assert_eq!(map_key(&cs("V"), &NO_SEL), app(AppCommand::Paste));
        let si = KeyIn {
            shift: true,
            ..k("insert")
        };
        assert_eq!(map_key(&si, &NO_SEL), app(AppCommand::Paste));
        assert_eq!(map_key(&k("insert"), &NO_SEL), chord("insert"));
    }

    #[test]
    fn altgr_is_text() {
        let ag = KeyIn {
            ctrl: true,
            alt: true,
            ..k("e")
        };
        assert_eq!(map_key(&ag, &NO_SEL), KeyAction::Text);
        let ag = KeyIn {
            ctrl: true,
            alt: true,
            shift: true,
            ..k("7")
        };
        assert_eq!(map_key(&ag, &NO_SEL), KeyAction::Text);
    }

    #[test]
    fn composing_ignores_everything() {
        let c = KeyCtx {
            has_selection: true,
            composing: true,
        };
        assert_eq!(map_key(&k("a"), &c), KeyAction::Ignore);
        assert_eq!(map_key(&k("enter"), &c), KeyAction::Ignore);
        assert_eq!(map_key(&ctrl("c"), &c), KeyAction::Ignore);
        assert_eq!(map_key(&cs("v"), &c), KeyAction::Ignore);
        let w = KeyIn {
            win: true,
            ..k("a")
        };
        assert_eq!(map_key(&w, &NO_SEL), KeyAction::Ignore);
    }

    #[test]
    fn split_and_focus_bindings() {
        assert_eq!(
            map_key(&alt_shift("="), &NO_SEL),
            app(AppCommand::SplitRight)
        );
        assert_eq!(
            map_key(&alt_shift("+"), &NO_SEL),
            app(AppCommand::SplitRight)
        );
        assert_eq!(
            map_key(&alt_shift("-"), &NO_SEL),
            app(AppCommand::SplitDown)
        );
        assert_eq!(
            map_key(&alt_shift("_"), &NO_SEL),
            app(AppCommand::SplitDown)
        );
        assert_eq!(
            map_key(&alt("left"), &NO_SEL),
            app(AppCommand::FocusPane(Dir::Left))
        );
        assert_eq!(
            map_key(&alt("right"), &NO_SEL),
            app(AppCommand::FocusPane(Dir::Right))
        );
        assert_eq!(
            map_key(&alt("up"), &NO_SEL),
            app(AppCommand::FocusPane(Dir::Up))
        );
        assert_eq!(
            map_key(&alt("down"), &NO_SEL),
            app(AppCommand::FocusPane(Dir::Down))
        );
        assert_eq!(map_key(&cs("t"), &NO_SEL), app(AppCommand::NewTab));
        assert_eq!(map_key(&cs("w"), &NO_SEL), app(AppCommand::ClosePane));
        assert_eq!(map_key(&ctrl("tab"), &NO_SEL), app(AppCommand::NextTab));
        assert_eq!(map_key(&cs("tab"), &NO_SEL), app(AppCommand::PrevTab));
        assert_eq!(
            map_key(&ctrl("pagedown"), &NO_SEL),
            app(AppCommand::NextTab)
        );
        assert_eq!(map_key(&ctrl("pageup"), &NO_SEL), app(AppCommand::PrevTab));
        assert_eq!(map_key(&cs("b"), &NO_SEL), app(AppCommand::ToggleSidebar));
        assert_eq!(map_key(&ctrl(","), &NO_SEL), app(AppCommand::OpenSettings));
        // Alt+Shift+arrow is not a focus binding: falls through to a chord.
        assert_eq!(
            map_key(&alt_shift("left"), &NO_SEL),
            chord("alt+shift+left")
        );
    }

    #[test]
    fn named_keys_become_chords() {
        assert_eq!(map_key(&k("enter"), &NO_SEL), chord("enter"));
        assert_eq!(map_key(&k("backspace"), &NO_SEL), chord("backspace"));
        assert_eq!(map_key(&k("escape"), &NO_SEL), chord("escape"));
        assert_eq!(map_key(&k("f5"), &NO_SEL), chord("f5"));
        assert_eq!(map_key(&k("f24"), &NO_SEL), chord("f24"));
        assert_eq!(map_key(&k("left"), &NO_SEL), chord("left"));
        assert_eq!(map_key(&k("pageup"), &NO_SEL), chord("pageup"));
        let st = KeyIn {
            shift: true,
            ..k("tab")
        };
        assert_eq!(map_key(&st, &NO_SEL), chord("shift+tab"));
        assert_eq!(map_key(&alt("b"), &NO_SEL), chord("alt+b"));
        assert_eq!(map_key(&ctrl("A"), &NO_SEL), chord("ctrl+a"));
        let all = KeyIn {
            ctrl: true,
            shift: true,
            ..k("left")
        };
        assert_eq!(map_key(&all, &NO_SEL), chord("ctrl+shift+left"));
        assert_eq!(map_key(&ctrl("space"), &NO_SEL), chord("ctrl+space"));
        assert_eq!(map_key(&k("space"), &NO_SEL), KeyAction::Text);
    }

    #[test]
    fn plain_letters_are_text() {
        assert_eq!(map_key(&k("a"), &NO_SEL), KeyAction::Text);
        let s = KeyIn {
            shift: true,
            ..k("A")
        };
        assert_eq!(map_key(&s, &NO_SEL), KeyAction::Text);
        assert_eq!(map_key(&k("1"), &NO_SEL), KeyAction::Text);
        assert_eq!(map_key(&k("ế"), &NO_SEL), KeyAction::Text);
    }
}
