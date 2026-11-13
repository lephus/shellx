#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::{json, Map, Value};
    use std::collections::HashSet;

    fn obj(v: Value) -> Map<String, Value> {
        v.as_object().expect("an object").clone()
    }

    #[test]
    fn defaults_are_the_macs() {
        let s = Settings::default();
        assert_eq!(s.font_size, 13.0);
        assert_eq!((s.padding_x, s.padding_y), (2, 2));
        assert_eq!(s.scrollback_mb, 50);
        assert!(s.confirm_unsafe_paste);
        assert!(s.middle_click_paste);
        assert_eq!(s.appearance, Appearance::Dark);
        assert_eq!(s.theme_dark, "ShellX");
        assert_eq!(s.theme_light, "Catppuccin Latte");
        assert_eq!(s.sidebar_font_size, 12.5);
        assert!(!s.focus_history_includes_panes);
    }

    #[test]
    fn a_default_settings_writes_no_key() {
        let s = Settings::default();
        for key in Key::ALL {
            assert_eq!(s.to_value(*key), None, "{key:?}");
        }
    }

    /// A non-default value per key, in the spelling the file holds.
    fn sample(key: Key) -> Value {
        match key {
            Key::Language => json!("vi"),
            Key::Appearance => json!("light"),
            Key::Accent => json!("#ff8800"),
            Key::NewWorkspacePlacement => json!("end"),
            Key::InheritWorkingDirectory => json!(false),
            Key::KeepWorkspaceOpen => json!(false),
            Key::FocusHistoryIncludesPanes => json!(true),
            Key::EqualizeSplits => json!(true),
            Key::HideTabCloseButton => json!(true),
            Key::ThemeLight => json!("Nord"),
            Key::ThemeDark => json!("Dracula"),
            Key::TabBarFontSize => json!(12.5),
            Key::ScrollSpeed => json!(2.0),
            Key::CopyOnSelect => json!(true),
            Key::ConfirmUnsafePaste => json!(false),
            Key::FontFamily => json!("Cascadia Mono"),
            Key::FontSize => json!(15.5),
            Key::CursorStyle => json!("block_hollow"),
            Key::PaddingX => json!(8),
            Key::PaddingY => json!(6),
            Key::ScrollbackMb => json!(100_000_000),
            Key::MiddleClickPaste => json!("ignore"),
            Key::IndicatorStyle => json!("solidFill"),
            Key::SubtleSelection => json!(false),
            Key::BrightenInDark => json!(false),
            Key::UnselectedFillOpacity => json!(0.5),
            Key::SelectionColor => json!("#112233"),
            Key::Palette => json!({"Red": "#aa0000"}),
            Key::SidebarBackground => json!("custom"),
            Key::SidebarColor => json!("#222222"),
            Key::SidebarFontSize => json!(14.0),
            Key::HideSidebarDetails => json!(true),
            Key::WrapWorkspaceTitles => json!(true),
            Key::TruncatePathFromStart => json!(true),
            Key::ShowBranchDirectory => json!(false),
            Key::Bindings => json!({"newTab": "ctrl+t", "closeTab": null}),
        }
    }

    #[test]
    fn every_key_round_trips() {
        for key in Key::ALL {
            let mut s = Settings::default();
            let value = sample(*key);
            assert!(s.set_from_value(*key, &value), "{key:?} accepts its sample");
            assert_eq!(s.to_value(*key), Some(value.clone()), "{key:?} writes back");
            assert_ne!(s, Settings::default(), "{key:?} changed the settings");
            for other in Key::ALL.iter().filter(|k| *k != key) {
                assert_eq!(s.to_value(*other), None, "{key:?} leaked into {other:?}");
            }
            let mut root = Map::new();
            put(&mut root, key.path(), s.to_value(*key));
            assert_eq!(get(&root, key.path()), Some(&value), "{key:?} put/get");
            assert_eq!(Settings::from_json(&root), s, "{key:?} from_json");
            s.reset(*key);
            assert_eq!(s, Settings::default(), "{key:?} reset");
        }
    }

    #[test]
    fn numbers_are_clamped_and_snapped() {
        let mut s = Settings::default();
        assert!(s.set_from_value(Key::FontSize, &json!(500)));
        assert_eq!(s.font_size, 96.0);
        assert!(s.set_from_value(Key::FontSize, &json!(13.26)));
        assert_eq!(s.font_size, 13.5);
        assert!(s.set_from_value(Key::ScrollSpeed, &json!(0)));
        assert_eq!(s.scroll_speed, 0.25);
        assert!(s.set_from_value(Key::PaddingX, &json!(9999)));
        assert_eq!(s.padding_x, 200);
        assert!(s.set_from_value(Key::PaddingY, &json!(-4)));
        assert_eq!(s.padding_y, 0);
        assert!(s.set_from_value(Key::UnselectedFillOpacity, &json!(0.7)));
        assert_eq!(s.unselected_fill_opacity, 0.70);
        assert_eq!(s.to_value(Key::UnselectedFillOpacity), None);
    }

    #[test]
    fn odd_values_are_skipped_per_key() {
        let root = obj(json!({
            "terminalConfig": {"font-size": "big", "cursor-style": "bar"},
            "app": {"appearance": 7}
        }));
        let s = Settings::from_json(&root);
        assert_eq!(s.font_size, 13.0);
        assert_eq!(s.cursor_style, CursorStyle::Bar);
        assert_eq!(s.appearance, Appearance::Dark);
        let mut t = Settings::default();
        assert!(!t.set_from_value(Key::FontSize, &json!("big")));
        assert_eq!(t, Settings::default());
    }

    #[test]
    fn keep_workspace_open_is_stored_inverted() {
        let s = Settings::from_json(&obj(
            json!({"app": {"keepWorkspaceOpenWhenClosingLastSurface": true}}),
        ));
        assert!(!s.keep_workspace_open);
        let mut s = Settings::default();
        s.keep_workspace_open = true;
        assert_eq!(s.to_value(Key::KeepWorkspaceOpen), Some(json!(false)));
    }

    #[test]
    fn accent_reads_cmux_system_and_hex() {
        let read = |v: &str| Settings::from_json(&obj(json!({"app": {"accentColor": v}}))).accent;
        assert_eq!(read("cmux"), Accent::ShellxBlue);
        assert_eq!(read("system"), Accent::System);
        assert_eq!(read("#ff8800"), Accent::Custom(Rgba::rgb(0xff8800)));
        assert_eq!(read("#zz"), Accent::ShellxBlue);
    }

    #[test]
    fn put_prunes_empty_parents_and_keeps_siblings() {
        let mut root = obj(json!({
            "shell": {"x": 1},
            "app": {"language": "vi", "appearance": "light"},
            "terminalConfig": {"theme": {"light": "Nord"}}
        }));
        put(&mut root, "app.language", None);
        assert_eq!(root["shell"], json!({"x": 1}));
        assert_eq!(root["app"], json!({"appearance": "light"}));
        put(&mut root, "terminalConfig.theme.light", None);
        assert!(!root.contains_key("terminalConfig"));
        put(&mut root, "a.b.c", Some(json!(1)));
        assert_eq!(root["a"], json!({"b": {"c": 1}}));
    }

    #[test]
    fn key_paths_are_unique() {
        let paths: HashSet<&str> = Key::ALL.iter().map(|k| k.path()).collect();
        assert_eq!(paths.len(), Key::ALL.len());
    }
}
