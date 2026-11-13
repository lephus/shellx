#[cfg(test)]
mod tests {
    use super::*;
    use crate::settings::{IndicatorStyle, SidebarBackground};
    use crate::strings::{t, Lang};
    use serde_json::json;
    use std::collections::HashSet;

    /// Keys whose rows are drawn by a section file (`Control::Custom` without a key).
    const CUSTOM_OWNED: &[Key] = &[Key::ThemeLight, Key::ThemeDark, Key::Palette, Key::Bindings];

    fn all_rows() -> impl Iterator<Item = &'static Row> {
        ROWS.iter()
    }

    fn ids(section: Section) -> Vec<&'static str> {
        rows(section).map(|r| r.id).collect()
    }

    #[test]
    fn every_key_has_exactly_one_row_or_is_custom_owned() {
        for key in Key::ALL {
            let count = all_rows().filter(|r| r.key == Some(*key)).count();
            if CUSTOM_OWNED.contains(key) {
                assert_eq!(count, 0, "{key:?} belongs to a custom row");
            } else {
                assert_eq!(count, 1, "{key:?} has one row");
            }
        }
    }

    #[test]
    fn row_ids_are_key_paths_or_fixed_camel_case_ids() {
        let mut seen = HashSet::new();
        for r in all_rows() {
            assert!(seen.insert(r.id), "{} is unique", r.id);
            match r.key {
                Some(key) => assert_eq!(r.id, key.path()),
                None => {
                    assert_eq!(r.control, Control::Custom, "{} has no key, so it is custom", r.id);
                    assert!(r.id.chars().all(|c| c.is_ascii_alphanumeric()), "{}", r.id);
                    assert!(r.id.starts_with(|c: char| c.is_ascii_lowercase()), "{}", r.id);
                }
            }
            assert_eq!(row(r.id).map(|found| found.id), Some(r.id));
        }
        assert!(row("no.such.row").is_none());
    }

    #[test]
    fn sections_follow_the_macs_order() {
        let order: Vec<(Group, Vec<Section>)> =
            groups().iter().map(|(g, s)| (*g, s.to_vec())).collect();
        assert_eq!(
            order,
            vec![
                (Group::General, vec![Section::Account, Section::App, Section::Themes]),
                (Group::Terminal, vec![Section::Terminal]),
                (Group::Workspace, vec![Section::WorkspaceColors]),
                (Group::SidebarAndDock, vec![Section::Sidebar]),
                (Group::KeyboardAndAdvanced, vec![Section::KeyboardShortcuts, Section::Reset]),
                (Group::ShellX, vec![Section::Updates, Section::About]),
            ]
        );
        let titles: Vec<&str> = groups().iter().map(|(g, _)| t(Lang::En, group_title(*g))).collect();
        assert_eq!(
            titles,
            ["General", "Terminal", "Workspace", "Sidebar & Dock", "Keyboard & Advanced", "ShellX"]
        );
        let sections: Vec<&str> = groups()
            .iter()
            .flat_map(|(_, s)| s.iter())
            .map(|s| t(Lang::En, section_title(*s)))
            .collect();
        assert_eq!(
            sections,
            [
                "Account",
                "App",
                "Themes",
                "Terminal",
                "Workspace Colors",
                "Sidebar",
                "Keyboard Shortcuts",
                "Reset",
                "Updates",
                "About"
            ]
        );
    }

    #[test]
    fn rows_follow_the_macs_order() {
        assert_eq!(ids(Section::Account), ["account"]);
        assert_eq!(
            ids(Section::App),
            [
                "app.language",
                "app.newWorkspacePlacement",
                "app.workspaceInheritWorkingDirectory",
                "app.keepWorkspaceOpenWhenClosingLastSurface",
                "app.focusHistoryIncludesPanesAndTabs",
                "app.equalizeSplitsOnCreate",
                "app.hideTabCloseButton",
            ]
        );
        assert_eq!(
            ids(Section::Themes),
            ["app.appearance", "app.accentColor", "terminalTheme", "themeGallery"]
        );
        assert_eq!(
            ids(Section::Terminal),
            [
                "shell",
                "display",
                "terminalConfig.surface-tab-bar-font-size",
                "terminal.scrollSpeed",
                "terminal.copyOnSelect",
                "terminal.confirmUnsafePaste",
                "terminalConfig.font-family",
                "terminalConfig.font-size",
                "terminalConfig.cursor-style",
                "terminalConfig.window-padding-x",
                "terminalConfig.window-padding-y",
                "terminalConfig.scrollback-limit",
                "terminalConfig.middle-click-action",
            ]
        );
        assert_eq!(
            ids(Section::WorkspaceColors),
            [
                "workspaceColors.indicatorStyle",
                "workspaceColors.subtleSelection",
                "workspaceColors.brightenInDarkMode",
                "workspaceColors.unselectedFillOpacity",
                "workspaceColors.selectionColor",
                "paletteRed",
                "paletteCrimson",
                "paletteOrange",
                "paletteAmber",
                "paletteOlive",
                "paletteGreen",
                "paletteTeal",
                "paletteAqua",
                "paletteBlue",
                "paletteNavy",
                "paletteIndigo",
                "palettePurple",
                "paletteMagenta",
                "paletteRose",
                "paletteBrown",
                "paletteCharcoal",
                "resetPalette",
            ]
        );
        assert_eq!(
            ids(Section::Sidebar),
            [
                "sidebarAppearance.background",
                "sidebarAppearance.tintColor",
                "terminalConfig.sidebar-font-size",
                "sidebar.hideAllDetails",
                "sidebar.wrapWorkspaceTitles",
                "sidebar.truncatePathFromStart",
                "sidebar.showBranchDirectory",
            ]
        );
        // The Mac puts Reset Default Shortcuts above the search bar and the action list.
        assert_eq!(ids(Section::KeyboardShortcuts), ["resetShortcuts", "shortcutList"]);
        assert_eq!(ids(Section::Reset), ["resetAll"]);
        assert_eq!(ids(Section::Updates), ["updates"]);
        assert_eq!(ids(Section::About), ["about"]);
        let listed: usize = groups().iter().flat_map(|(_, s)| s.iter()).map(|s| rows(*s).count()).sum();
        assert_eq!(listed, ROWS.len(), "every row sits in a listed section");
    }

    #[test]
    fn english_titles_are_the_macs() {
        assert_eq!(t(Lang::En, row("terminalConfig.font-size").unwrap().title), "Font Size");
        assert_eq!(
            t(Lang::En, row("workspaceColors.subtleSelection").unwrap().title),
            "Subtle Selection Highlight"
        );
        assert_eq!(
            t(Lang::En, row("sidebar.hideAllDetails").unwrap().title),
            "Hide All Sidebar Details"
        );
        let en = |id: &str| t(Lang::En, row(id).unwrap().title);
        assert_eq!(
            en("app.keepWorkspaceOpenWhenClosingLastSurface"),
            "Keep Workspace Open When Closing Last Surface"
        );
        assert_eq!(en("app.focusHistoryIncludesPanesAndTabs"), "Include Panes and Tabs in Focus History");
        assert_eq!(en("terminalConfig.middle-click-action"), "Middle-Click Paste");
        assert_eq!(en("terminal.confirmUnsafePaste"), "Confirm Unsafe Pastes");
        assert_eq!(en("sidebar.showBranchDirectory"), "Show Branch + Directory in Sidebar");
        assert_eq!(en("workspaceColors.indicatorStyle"), "Workspace Color Indicator");
        assert_eq!(en("terminalTheme"), "Terminal Theme");
        assert_eq!(en("resetShortcuts"), "Reset Default Shortcuts");
        assert_eq!(en("resetAll"), "Reset All Settings");
        assert_eq!(en("paletteCharcoal"), "Charcoal");
        // Vietnamese titles come from the Mac's Vietnamese table.
        let vi = |id: &str| t(Lang::Vi, row(id).unwrap().title);
        assert_eq!(vi("terminalConfig.font-size"), "Cỡ chữ");
        assert_eq!(vi("workspaceColors.subtleSelection"), "Làm nổi bật lựa chọn tinh tế");
        assert_eq!(vi("sidebar.hideAllDetails"), "Ẩn mọi chi tiết trên thanh bên");
        assert_eq!(t(Lang::Vi, section_title(Section::Themes)), "Giao diện màu");
        assert_eq!(t(Lang::Vi, section_title(Section::KeyboardShortcuts)), "Phím tắt");
    }

    #[test]
    fn controls_carry_the_spec_ranges_and_the_json_spellings() {
        let control = |id: &str| row(id).unwrap().control;
        assert_eq!(
            control("terminalConfig.surface-tab-bar-font-size"),
            Control::Slider { min: 8.0, max: 14.0, step: 0.5, unit: Unit::Points }
        );
        assert_eq!(
            control("terminal.scrollSpeed"),
            Control::Slider { min: 0.25, max: 3.0, step: 0.05, unit: Unit::Times }
        );
        assert_eq!(
            control("workspaceColors.unselectedFillOpacity"),
            Control::Slider { min: 0.0, max: 1.0, step: 0.05, unit: Unit::Percent }
        );
        assert_eq!(
            control("terminalConfig.sidebar-font-size"),
            Control::Slider { min: 10.0, max: 20.0, step: 0.5, unit: Unit::Points }
        );
        assert_eq!(
            control("terminalConfig.font-size"),
            Control::Stepper { min: 4.0, max: 96.0, step: 0.5 }
        );
        assert_eq!(
            control("terminalConfig.window-padding-x"),
            Control::Stepper { min: 0.0, max: 200.0, step: 1.0 }
        );
        assert_eq!(
            control("terminalConfig.window-padding-y"),
            Control::Stepper { min: 0.0, max: 200.0, step: 1.0 }
        );
        assert_eq!(
            control("terminalConfig.scrollback-limit"),
            Control::Number { min: 0.0, max: 100_000.0, unit: Unit::Megabytes }
        );
        assert_eq!(
            control("workspaceColors.selectionColor"),
            Control::Color { resettable: true }
        );
        assert_eq!(control("sidebarAppearance.tintColor"), Control::Color { resettable: false });
        assert_eq!(control("terminalConfig.font-family"), Control::Custom);
        assert_eq!(control("app.accentColor"), Control::Custom);
        assert_eq!(control("terminal.copyOnSelect"), Control::Toggle);

        let values = |id: &str| match control(id) {
            Control::Segmented(o) | Control::Picker(o) => o.iter().map(|(_, v)| *v).collect::<Vec<_>>(),
            other => panic!("{id} is {other:?}"),
        };
        assert_eq!(values("app.language"), ["system", "en", "vi"]);
        assert_eq!(values("app.appearance"), ["system", "light", "dark"]);
        assert_eq!(values("app.newWorkspacePlacement"), ["top", "afterCurrent", "end"]);
        assert_eq!(
            values("terminalConfig.cursor-style"),
            ["block", "bar", "underline", "block_hollow"]
        );
        assert_eq!(values("workspaceColors.indicatorStyle"), ["leftRail", "solidFill"]);
        assert_eq!(values("sidebarAppearance.background"), ["theme", "terminal", "custom"]);

        // Every option of every row is a value the settings model reads.
        for r in all_rows() {
            if let (Some(key), Control::Segmented(options) | Control::Picker(options)) = (r.key, r.control) {
                for (label, value) in options {
                    let mut s = Settings::default();
                    assert!(s.set_from_value(key, &json!(value)), "{}: {value}", r.id);
                    assert!(!t(Lang::En, *label).is_empty());
                }
            }
        }
    }

    #[test]
    fn every_string_has_both_languages() {
        let mut used: Vec<Str> = Vec::new();
        for (g, sections) in groups() {
            used.push(group_title(*g));
            used.extend(sections.iter().map(|s| section_title(*s)));
        }
        for r in all_rows() {
            used.push(r.title);
            used.extend(r.subtitle);
            if let Control::Segmented(o) | Control::Picker(o) = r.control {
                used.extend(o.iter().map(|(label, _)| *label));
            }
        }
        let new = Str::ALL.iter().copied().filter(|s| format!("{s:?}").starts_with("Settings"));
        for s in used.into_iter().chain(new) {
            for lang in [Lang::En, Lang::Vi] {
                assert!(!t(lang, s).trim().is_empty(), "{s:?} {lang:?}");
            }
            assert!(Str::ALL.contains(&s), "{s:?} is listed in Str::ALL");
        }
    }

    #[test]
    fn conditions_follow_the_spec() {
        let enabled = |id: &str, s: &Settings| (row(id).unwrap().enabled)(s);
        let visible = |id: &str, s: &Settings| (row(id).unwrap().visible)(s);
        let defaults = Settings::default();
        for r in all_rows() {
            assert!((r.visible)(&defaults) || r.id == "sidebarAppearance.tintColor", "{}", r.id);
            assert!((r.enabled)(&defaults) || r.id.starts_with("workspaceColors."), "{}", r.id);
        }

        let rail = Settings { indicator_style: IndicatorStyle::LeftRail, ..Settings::default() };
        let fill = Settings { indicator_style: IndicatorStyle::SolidFill, ..Settings::default() };
        assert!(enabled("workspaceColors.subtleSelection", &rail));
        assert!(!enabled("workspaceColors.subtleSelection", &fill));
        for id in ["workspaceColors.brightenInDarkMode", "workspaceColors.unselectedFillOpacity"] {
            assert!(!enabled(id, &rail), "{id}");
            assert!(enabled(id, &fill), "{id}");
        }

        for background in [SidebarBackground::FollowTheme, SidebarBackground::MatchTerminal] {
            let s = Settings { sidebar_background: background, ..Settings::default() };
            assert!(!visible("sidebarAppearance.tintColor", &s), "{background:?}");
        }
        let custom = Settings { sidebar_background: SidebarBackground::Custom, ..Settings::default() };
        assert!(visible("sidebarAppearance.tintColor", &custom));

        let hidden = Settings { hide_sidebar_details: true, ..Settings::default() };
        for id in ["sidebar.truncatePathFromStart", "sidebar.showBranchDirectory"] {
            assert!(enabled(id, &defaults), "{id}");
            assert!(!enabled(id, &hidden), "{id}");
        }
        // As on the Mac (SidebarSection.swift): titles still show, so wrapping them stays on.
        assert!(enabled("sidebar.wrapWorkspaceTitles", &hidden));
        assert!(enabled("sidebar.hideAllDetails", &hidden));
    }

    #[test]
    fn only_the_migrated_rows_start_wired() {
        let wired: Vec<&str> = all_rows().filter(|r| r.wired).map(|r| r.id).collect();
        assert_eq!(wired, ["account", "shell", "display", "updates", "about"]);
    }

    #[test]
    fn section_ids_round_trip() {
        let ids: Vec<&str> = groups().iter().flat_map(|(_, s)| s.iter()).map(|s| s.id()).collect();
        assert_eq!(
            ids,
            [
                "account",
                "app",
                "themes",
                "terminal",
                "workspaceColors",
                "sidebar",
                "keyboardShortcuts",
                "reset",
                "updates",
                "about"
            ]
        );
        for (_, sections) in groups() {
            for s in *sections {
                assert_eq!(Section::from_id(s.id()), Some(*s));
            }
        }
        assert_eq!(Section::from_id("Themes"), None);
        assert_eq!(Section::from_id(""), None);
    }

    #[test]
    fn synonyms_are_plain_lower_case_words() {
        for r in all_rows() {
            assert!(!r.synonyms.trim().is_empty(), "{}", r.id);
            assert!(r.synonyms.is_ascii(), "{} synonyms are unaccented", r.id);
            assert_eq!(r.synonyms, r.synonyms.to_lowercase(), "{}", r.id);
        }
    }
}
