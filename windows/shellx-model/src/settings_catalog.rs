//! The Settings rows: every row of spec §5.4 in the Mac's order, plus `Custom` entries for the
//! cards a section file draws itself. The Settings view draws its rows from here and search
//! indexes them, so a row is drawn and found only once its feature sets `wired: true`.

use crate::settings::{IndicatorStyle, Key, Settings, SidebarBackground};
use crate::strings::Str;

/// The sidebar's groups (spec §5.3).
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum Group {
    General,
    Terminal,
    Workspace,
    SidebarAndDock,
    KeyboardAndAdvanced,
    ShellX,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum Section {
    Account,
    App,
    Themes,
    Terminal,
    WorkspaceColors,
    Sidebar,
    KeyboardShortcuts,
    Reset,
    Updates,
    About,
}

impl Section {
    /// The stable id used by `SHELLX_DEV_PREVIEW=settings:<id>` and the remembered section.
    pub fn id(self) -> &'static str {
        match self {
            Section::Account => "account",
            Section::App => "app",
            Section::Themes => "themes",
            Section::Terminal => "terminal",
            Section::WorkspaceColors => "workspaceColors",
            Section::Sidebar => "sidebar",
            Section::KeyboardShortcuts => "keyboardShortcuts",
            Section::Reset => "reset",
            Section::Updates => "updates",
            Section::About => "about",
        }
    }

    pub fn from_id(id: &str) -> Option<Section> {
        GROUPS
            .iter()
            .flat_map(|(_, sections)| sections.iter())
            .copied()
            .find(|s| s.id() == id)
    }
}

/// How a slider or number field shows its value.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Unit {
    /// "11 pt".
    Points,
    /// "1.00×".
    Times,
    /// "70%" for a value from 0 to 1.
    Percent,
    /// "50 MB".
    Megabytes,
}

#[derive(Clone, Copy, Debug, PartialEq)]
pub enum Control {
    Toggle,
    /// Label and the JSON value `settings.rs` reads.
    Segmented(&'static [(Str, &'static str)]),
    Picker(&'static [(Str, &'static str)]),
    Slider {
        min: f32,
        max: f32,
        step: f32,
        unit: Unit,
        /// A "Reset" button beside the slider, where the Mac's row has one.
        reset: bool,
    },
    Stepper {
        min: f32,
        max: f32,
        step: f32,
    },
    Number {
        min: f32,
        max: f32,
        unit: Unit,
    },
    Color {
        resettable: bool,
    },
    /// Drawn by its section file: a card, a list, or a control whose options are known only
    /// at run time.
    Custom,
}

#[derive(Clone, Copy, Debug)]
pub struct Row {
    /// The key's JSON path, or a fixed camelCase id for a row without a key.
    pub id: &'static str,
    pub key: Option<Key>,
    pub section: Section,
    pub title: Str,
    pub subtitle: Option<Str>,
    pub control: Control,
    /// Space separated, English and unaccented Vietnamese; search only.
    pub synonyms: &'static str,
    /// Drawn and searchable; set by the commit that makes the row work.
    pub wired: bool,
    pub enabled: fn(&Settings) -> bool,
    pub visible: fn(&Settings) -> bool,
}

static GROUPS: &[(Group, &[Section])] = &[
    (
        Group::General,
        &[Section::Account, Section::App, Section::Themes],
    ),
    (Group::Terminal, &[Section::Terminal]),
    (Group::Workspace, &[Section::WorkspaceColors]),
    (Group::SidebarAndDock, &[Section::Sidebar]),
    (
        Group::KeyboardAndAdvanced,
        &[Section::KeyboardShortcuts, Section::Reset],
    ),
    (Group::ShellX, &[Section::Updates, Section::About]),
];

/// The groups and their sections, in the order the sidebar lists them.
pub fn groups() -> &'static [(Group, &'static [Section])] {
    GROUPS
}

pub fn group_title(g: Group) -> Str {
    match g {
        Group::General => Str::SettingsGroupGeneral,
        Group::Terminal => Str::Terminal,
        Group::Workspace => Str::SettingsGroupWorkspace,
        Group::SidebarAndDock => Str::SettingsGroupSidebarAndDock,
        Group::KeyboardAndAdvanced => Str::SettingsGroupKeyboardAndAdvanced,
        Group::ShellX => Str::AppName,
    }
}

pub fn section_title(s: Section) -> Str {
    match s {
        Section::Account => Str::Account,
        Section::App => Str::SettingsSectionApp,
        Section::Themes => Str::SettingsSectionThemes,
        Section::Terminal => Str::Terminal,
        Section::WorkspaceColors => Str::SettingsSectionWorkspaceColors,
        Section::Sidebar => Str::SettingsSectionSidebar,
        Section::KeyboardShortcuts => Str::SettingsSectionKeyboardShortcuts,
        Section::Reset => Str::SettingsReset,
        Section::Updates => Str::Updates,
        Section::About => Str::About,
    }
}

/// The rows of a section, top to bottom.
pub fn rows(section: Section) -> impl Iterator<Item = &'static Row> {
    ROWS.iter().filter(move |r| r.section == section)
}

pub fn row(id: &str) -> Option<&'static Row> {
    ROWS.iter().find(|r| r.id == id)
}

fn always(_: &Settings) -> bool {
    true
}

fn not_solid_fill(s: &Settings) -> bool {
    s.indicator_style != IndicatorStyle::SolidFill
}

fn not_left_rail(s: &Settings) -> bool {
    s.indicator_style != IndicatorStyle::LeftRail
}

fn custom_sidebar_color(s: &Settings) -> bool {
    s.sidebar_background == SidebarBackground::Custom
}

fn sidebar_details_shown(s: &Settings) -> bool {
    !s.hide_sidebar_details
}

/// A row for one settings key; its id is the key's path.
const fn setting(
    key: Key,
    section: Section,
    title: Str,
    subtitle: Option<Str>,
    control: Control,
    synonyms: &'static str,
) -> Row {
    Row {
        id: key.path(),
        key: Some(key),
        section,
        title,
        subtitle,
        control,
        synonyms,
        wired: false,
        enabled: always,
        visible: always,
    }
}

/// A card or row its section file draws on its own.
const fn custom(id: &'static str, section: Section, title: Str, synonyms: &'static str) -> Row {
    Row {
        id,
        key: None,
        section,
        title,
        subtitle: None,
        control: Control::Custom,
        synonyms,
        wired: false,
        enabled: always,
        visible: always,
    }
}

const fn toggle(
    key: Key,
    section: Section,
    title: Str,
    subtitle: Str,
    synonyms: &'static str,
) -> Row {
    setting(
        key,
        section,
        title,
        Some(subtitle),
        Control::Toggle,
        synonyms,
    )
}

const fn palette(id: &'static str, name: Str, synonyms: &'static str) -> Row {
    custom(id, Section::WorkspaceColors, name, synonyms)
}

static ROWS: &[Row] = &[
    // Account (the existing panel).
    Row {
        wired: true,
        ..custom(
            "account",
            Section::Account,
            Str::Account,
            "account auth authentication login logout sign in sign out signin signout email google user profile tai khoan dang nhap dang xuat",
        )
    },
    // App.
    Row {
        wired: true,
        ..setting(
            Key::Language,
            Section::App,
            Str::Language,
            None,
            Control::Picker(&[
                (Str::SettingsSystem, "system"),
                (Str::SettingsLanguageEnglish, "en"),
                (Str::SettingsLanguageVietnamese, "vi"),
            ]),
            "language locale localization translation english vietnamese restart ngon ngu tieng viet tieng anh",
        )
    },
    Row {
        wired: true,
        ..setting(
            Key::NewWorkspacePlacement,
            Section::App,
            Str::SettingsNewWorkspacePlacement,
            Some(Str::SettingsNewWorkspacePlacementSubtitle),
            Control::Picker(&[
                (Str::SettingsPlacementTop, "top"),
                (Str::SettingsPlacementAfterCurrent, "afterCurrent"),
                (Str::SettingsPlacementEnd, "end"),
            ]),
            "new workspace placement insert position order top after current end bottom vi tri phien moi tren cuoi",
        )
    },
    Row {
        wired: true,
        ..toggle(
            Key::InheritWorkingDirectory,
            Section::App,
            Str::SettingsInheritWorkingDirectory,
            Str::SettingsInheritWorkingDirectorySubtitle,
            "inherit workspace working directory cwd folder current new workspace ke thua thu muc lam viec phien moi",
        )
    },
    Row {
        wired: true,
        ..toggle(
            Key::KeepWorkspaceOpen,
            Section::App,
            Str::SettingsKeepWorkspaceOpen,
            Str::SettingsKeepWorkspaceOpenSubtitle,
            "keep workspace open close last surface pane tab terminal giu phien mo dong tab cuoi",
        )
    },
    Row {
        wired: true,
        ..toggle(
            Key::FocusHistoryIncludesPanes,
            Section::App,
            Str::SettingsFocusHistoryIncludesPanes,
            Str::SettingsFocusHistoryIncludesPanesSubtitle,
            "focus history back forward panes tabs workspaces navigation lich su tieu diem quay lai tien toi khung",
        )
    },
    Row {
        wired: true,
        ..toggle(
            Key::EqualizeSplits,
            Section::App,
            Str::SettingsEqualizeSplits,
            Str::SettingsEqualizeSplitsSubtitle,
            "equalize balance distribute even equal split pane size new split can bang chia khung",
        )
    },
    Row {
        wired: true,
        ..toggle(
            Key::HideTabCloseButton,
            Section::App,
            Str::SettingsHideTabCloseButton,
            Str::SettingsHideTabCloseButtonSubtitle,
            "hide tab close button x tabs an nut dong tab",
        )
    },
    // Themes.
    Row {
        wired: true,
        ..setting(
            Key::Appearance,
            Section::Themes,
            Str::SettingsAppearance,
            Some(Str::SettingsAppearanceSubtitle),
            Control::Segmented(&[
                (Str::SettingsSystem, "system"),
                (Str::SettingsLight, "light"),
                (Str::SettingsDark, "dark"),
            ]),
            "appearance theme color scheme light mode dark mode system mode giao dien sang toi he thong",
        )
    },
    // A picker plus a colour well for Custom, whose JSON value is the colour itself.
    Row {
        wired: true,
        ..setting(
            Key::Accent,
            Section::Themes,
            Str::SettingsAccentColor,
            Some(Str::SettingsAccentColorSubtitle),
            Control::Custom,
            "accent color highlight tint blue system accent windows accent shellx blue mau nhan xanh",
        )
    },
    Row {
        wired: true,
        ..custom(
            "terminalTheme",
            Section::Themes,
            Str::SettingsTerminalTheme,
            "terminal theme ghostty themes color scheme palette colors light dark pair revert catppuccin gruvbox nord dracula solarized tokyonight rose pine github giao dien mau theme sang toi",
        )
    },
    Row {
        wired: true,
        ..custom(
            "themeGallery",
            Section::Themes,
            Str::SettingsSearchAllThemes,
            "theme gallery preview cards dark themes light themes thu vien theme tim",
        )
    },
    // Terminal: the two existing cards, then the Mac's rows.
    Row {
        wired: true,
        ..custom(
            "shell",
            Section::Terminal,
            Str::SettingsShell,
            "shell powershell pwsh command prompt cmd wsl git bash custom command line automatic chon shell dong lenh tu dong",
        )
    },
    Row {
        wired: true,
        ..custom(
            "display",
            Section::Terminal,
            Str::Display,
            "display rendering mode standard compatible gpu direct composition hien thi che do thuong tuong thich",
        )
    },
    Row {
        wired: true,
        ..setting(
            Key::TabBarFontSize,
            Section::Terminal,
            Str::SettingsTabBarFontSize,
            Some(Str::SettingsTabBarFontSizeSubtitle),
            Control::Slider {
                min: 8.0,
                max: 14.0,
                step: 0.5,
                unit: Unit::Points,
                reset: true,
            },
            "tab bar font size title text points pt bigger smaller co chu thanh tab",
        )
    },
    Row {
        wired: true,
        ..setting(
            Key::ScrollSpeed,
            Section::Terminal,
            Str::SettingsScrollSpeed,
            Some(Str::SettingsScrollSpeedSubtitle),
            Control::Slider {
                min: 0.25,
                max: 3.0,
                step: 0.05,
                unit: Unit::Times,
                reset: true,
            },
            "scroll speed multiplier wheel mouse touchpad trackpad sensitivity faster slower toc do cuon con lan",
        )
    },
    Row {
        wired: true,
        ..toggle(
            Key::CopyOnSelect,
            Section::Terminal,
            Str::SettingsCopyOnSelect,
            Str::SettingsCopyOnSelectSubtitle,
            "copy on selection select clipboard mouse sao chep khi chon bo nho tam",
        )
    },
    Row {
        wired: true,
        ..toggle(
            Key::ConfirmUnsafePaste,
            Section::Terminal,
            Str::SettingsConfirmUnsafePaste,
            Str::SettingsConfirmUnsafePasteSubtitleOn,
            "confirm unsafe paste protection warning multi-line multiple lines newline clipboard xac nhan dan nhieu dong",
        )
    },
    // "Default" plus the installed monospaced families, known only at run time.
    Row {
        wired: true,
        ..setting(
            Key::FontFamily,
            Section::Terminal,
            Str::SettingsFont,
            None,
            Control::Custom,
            "font family typeface monospaced monospace terminal font jetbrains mono phong chu",
        )
    },
    Row {
        wired: true,
        ..setting(
            Key::FontSize,
            Section::Terminal,
            Str::SettingsFontSize,
            None,
            Control::Stepper {
                min: 4.0,
                max: 96.0,
                step: 0.5,
            },
            "font size text size points pt bigger smaller zoom co chu",
        )
    },
    Row {
        wired: true,
        ..setting(
            Key::CursorStyle,
            Section::Terminal,
            Str::SettingsCursorStyle,
            None,
            Control::Segmented(&[
                (Str::SettingsCursorBlock, "block"),
                (Str::SettingsCursorBar, "bar"),
                (Str::SettingsCursorUnderline, "underline"),
                (Str::SettingsCursorHollow, "block_hollow"),
            ]),
            "cursor style shape block bar beam underline hollow caret kieu con tro",
        )
    },
    Row {
        wired: true,
        ..setting(
            Key::PaddingX,
            Section::Terminal,
            Str::SettingsPaddingX,
            None,
            Control::Stepper {
                min: 0.0,
                max: 200.0,
                step: 1.0,
            },
            "horizontal padding left right margin inset spacing dem ngang le",
        )
    },
    Row {
        wired: true,
        ..setting(
            Key::PaddingY,
            Section::Terminal,
            Str::SettingsPaddingY,
            None,
            Control::Stepper {
                min: 0.0,
                max: 200.0,
                step: 1.0,
            },
            "vertical padding top bottom margin inset spacing dem doc le",
        )
    },
    Row {
        wired: true,
        ..setting(
            Key::ScrollbackMb,
            Section::Terminal,
            Str::SettingsScrollbackLimit,
            Some(Str::SettingsScrollbackLimitSubtitle),
            Control::Number {
                min: 0.0,
                max: 100_000.0,
                unit: Unit::Megabytes,
            },
            "scrollback limit history buffer lines memory megabytes mb gioi han lich su bo nho",
        )
    },
    Row {
        wired: true,
        ..toggle(
            Key::MiddleClickPaste,
            Section::Terminal,
            Str::SettingsMiddleClickPaste,
            Str::SettingsMiddleClickPasteSubtitle,
            "middle click paste mouse button wheel primary selection dan nut giua chuot",
        )
    },
    // Workspace Colors.
    setting(
        Key::IndicatorStyle,
        Section::WorkspaceColors,
        Str::SettingsWorkspaceColorIndicator,
        None,
        Control::Picker(&[
            (Str::SettingsLeftRail, "leftRail"),
            (Str::SettingsSolidFill, "solidFill"),
        ]),
        "workspace color indicator left rail solid fill style stripe chi bao mau phien vach ben trai to dac",
    ),
    Row {
        enabled: not_solid_fill,
        ..toggle(
            Key::SubtleSelection,
            Section::WorkspaceColors,
            Str::SettingsSubtleSelection,
            Str::SettingsSubtleSelectionSubtitle,
            "subtle selection highlight tint hairline edge selected workspace accent lam noi bat lua chon tinh te",
        )
    },
    Row {
        enabled: not_left_rail,
        ..toggle(
            Key::BrightenInDark,
            Section::WorkspaceColors,
            Str::SettingsBrightenInDark,
            Str::SettingsBrightenInDarkSubtitle,
            "brighten colors dark mode lighten workspace colors fill dim muted lam sang mau che do toi",
        )
    },
    Row {
        enabled: not_left_rail,
        ..setting(
            Key::UnselectedFillOpacity,
            Section::WorkspaceColors,
            Str::SettingsUnselectedFillOpacity,
            Some(Str::SettingsUnselectedFillOpacitySubtitle),
            Control::Slider {
                min: 0.0,
                max: 1.0,
                step: 0.05,
                unit: Unit::Percent,
                reset: false,
            },
            "unselected fill opacity transparency alpha solid fill inactive workspace row do mo duc to mau chua chon",
        )
    },
    setting(
        Key::SelectionColor,
        Section::WorkspaceColors,
        Str::SettingsSelectionHighlight,
        Some(Str::SettingsSelectionHighlightSubtitle),
        Control::Color { resettable: true },
        "selection highlight selected workspace color background active mau lam noi bat muc chon",
    ),
    palette(
        "paletteRed",
        Str::SettingsColorRed,
        "palette workspace color red bang mau do",
    ),
    palette(
        "paletteCrimson",
        Str::SettingsColorCrimson,
        "palette workspace color crimson bang mau do tham",
    ),
    palette(
        "paletteOrange",
        Str::SettingsColorOrange,
        "palette workspace color orange bang mau cam",
    ),
    palette(
        "paletteAmber",
        Str::SettingsColorAmber,
        "palette workspace color amber bang mau ho phach",
    ),
    palette(
        "paletteOlive",
        Str::SettingsColorOlive,
        "palette workspace color olive bang mau o liu",
    ),
    palette(
        "paletteGreen",
        Str::SettingsColorGreen,
        "palette workspace color green bang mau xanh la",
    ),
    palette(
        "paletteTeal",
        Str::SettingsColorTeal,
        "palette workspace color teal bang mau xanh mong ket",
    ),
    palette(
        "paletteAqua",
        Str::SettingsColorAqua,
        "palette workspace color aqua bang mau xanh ngoc",
    ),
    palette(
        "paletteBlue",
        Str::SettingsColorBlue,
        "palette workspace color blue bang mau xanh duong",
    ),
    palette(
        "paletteNavy",
        Str::SettingsColorNavy,
        "palette workspace color navy bang mau xanh hai quan",
    ),
    palette(
        "paletteIndigo",
        Str::SettingsColorIndigo,
        "palette workspace color indigo bang mau cham",
    ),
    palette(
        "palettePurple",
        Str::SettingsColorPurple,
        "palette workspace color purple bang mau tim",
    ),
    palette(
        "paletteMagenta",
        Str::SettingsColorMagenta,
        "palette workspace color magenta bang mau hong canh sen",
    ),
    palette(
        "paletteRose",
        Str::SettingsColorRose,
        "palette workspace color rose bang mau hong sam",
    ),
    palette(
        "paletteBrown",
        Str::SettingsColorBrown,
        "palette workspace color brown bang mau nau",
    ),
    palette(
        "paletteCharcoal",
        Str::SettingsColorCharcoal,
        "palette workspace color charcoal bang mau xam than",
    ),
    Row {
        subtitle: Some(Str::SettingsResetPaletteSubtitle),
        ..custom(
            "resetPalette",
            Section::WorkspaceColors,
            Str::SettingsResetPalette,
            "reset palette named colors restore built-in default dat lai bang mau mac dinh",
        )
    },
    // Sidebar.
    Row {
        wired: true,
        ..setting(
            Key::SidebarBackground,
            Section::Sidebar,
            Str::SettingsSidebarBackground,
            Some(Str::SettingsSidebarBackgroundSubtitle),
            Control::Picker(&[
                (Str::SettingsFollowTheme, "theme"),
                (Str::SettingsMatchTerminal, "terminal"),
                (Str::SettingsCustomColor, "custom"),
            ]),
            "sidebar background match terminal follow theme custom color tint nen thanh ben theo giao dien mau khop rieng",
        )
    },
    Row {
        wired: true,
        visible: custom_sidebar_color,
        ..setting(
            Key::SidebarColor,
            Section::Sidebar,
            Str::SettingsSidebarColor,
            Some(Str::SettingsSidebarColorSubtitle),
            Control::Color { resettable: false },
            "sidebar color tint custom background mau thanh ben rieng",
        )
    },
    Row {
        wired: true,
        ..setting(
            Key::SidebarFontSize,
            Section::Sidebar,
            Str::SettingsSidebarFontSize,
            Some(Str::SettingsSidebarFontSizeSubtitle),
            Control::Slider {
                min: 10.0,
                max: 20.0,
                step: 0.5,
                unit: Unit::Points,
                reset: true,
            },
            "sidebar font size workspace titles text points pt bigger smaller co chu thanh ben",
        )
    },
    Row {
        wired: true,
        ..toggle(
            Key::HideSidebarDetails,
            Section::Sidebar,
            Str::SettingsHideAllSidebarDetails,
            Str::SettingsHideAllSidebarDetailsSubtitle,
            "hide all sidebar details compact only titles minimal an moi chi tiet thanh ben",
        )
    },
    // Stays enabled while details are hidden, since the titles still show (as the Mac's
    // SidebarSection.swift does).
    Row {
        wired: true,
        ..toggle(
            Key::WrapWorkspaceTitles,
            Section::Sidebar,
            Str::SettingsWrapWorkspaceTitles,
            Str::SettingsWrapWorkspaceTitlesSubtitle,
            "wrap workspace titles multiline long titles xuong dong tieu de phien",
        )
    },
    Row {
        wired: true,
        enabled: sidebar_details_shown,
        ..toggle(
            Key::TruncatePathFromStart,
            Section::Sidebar,
            Str::SettingsTruncatePathFromStart,
            Str::SettingsTruncatePathFromStartSubtitle,
            "truncate path from start cwd directory basename short folder cat duong dan tu dau",
        )
    },
    Row {
        wired: true,
        enabled: sidebar_details_shown,
        ..toggle(
            Key::ShowBranchDirectory,
            Section::Sidebar,
            Str::SettingsShowBranchDirectory,
            Str::SettingsShowBranchDirectorySubtitle,
            "show branch directory git cwd path folder repo hien branch thu muc",
        )
    },
    // Keyboard Shortcuts: the Mac puts Reset above the search bar and the action list.
    Row {
        subtitle: Some(Str::SettingsResetDefaultShortcutsSubtitle),
        wired: true,
        ..custom(
            "resetShortcuts",
            Section::KeyboardShortcuts,
            Str::SettingsResetDefaultShortcuts,
            "reset default shortcuts restore defaults built in hotkeys keybindings dat lai phim tat mac dinh",
        )
    },
    Row {
        wired: true,
        ..custom(
            "shortcutList",
            Section::KeyboardShortcuts,
            Str::SettingsSectionKeyboardShortcuts,
            "keyboard shortcuts hotkeys keybindings key bindings commands record unbind settings toggle left sidebar new workspace new surface close tab next workspace previous workspace split right split down focus pane left right up down focus back forward copy paste phim tat ghi phim",
        )
    },
    // Reset.
    custom(
        "resetAll",
        Section::Reset,
        Str::SettingsResetAllSettings,
        "reset all settings factory reset restore defaults clear preferences dat lai tat ca cai dat mac dinh",
    ),
    // Updates and About (the existing panels).
    Row {
        wired: true,
        ..custom(
            "updates",
            Section::Updates,
            Str::Updates,
            "updates check for updates version download new release cap nhat kiem tra phien ban tai ve",
        )
    },
    Row {
        wired: true,
        ..custom(
            "about",
            Section::About,
            Str::About,
            "about version credits license fonts icons cmux gpl gioi thieu phien ban",
        )
    },
];

#[cfg(test)]
mod tests {
    use super::*;
    use crate::strings::{Lang, t};
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
                    assert_eq!(
                        r.control,
                        Control::Custom,
                        "{} has no key, so it is custom",
                        r.id
                    );
                    assert!(r.id.chars().all(|c| c.is_ascii_alphanumeric()), "{}", r.id);
                    assert!(
                        r.id.starts_with(|c: char| c.is_ascii_lowercase()),
                        "{}",
                        r.id
                    );
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
                (
                    Group::General,
                    vec![Section::Account, Section::App, Section::Themes]
                ),
                (Group::Terminal, vec![Section::Terminal]),
                (Group::Workspace, vec![Section::WorkspaceColors]),
                (Group::SidebarAndDock, vec![Section::Sidebar]),
                (
                    Group::KeyboardAndAdvanced,
                    vec![Section::KeyboardShortcuts, Section::Reset]
                ),
                (Group::ShellX, vec![Section::Updates, Section::About]),
            ]
        );
        let titles: Vec<&str> = groups()
            .iter()
            .map(|(g, _)| t(Lang::En, group_title(*g)))
            .collect();
        assert_eq!(
            titles,
            [
                "General",
                "Terminal",
                "Workspace",
                "Sidebar & Dock",
                "Keyboard & Advanced",
                "ShellX"
            ]
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
            [
                "app.appearance",
                "app.accentColor",
                "terminalTheme",
                "themeGallery"
            ]
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
        assert_eq!(
            ids(Section::KeyboardShortcuts),
            ["resetShortcuts", "shortcutList"]
        );
        assert_eq!(ids(Section::Reset), ["resetAll"]);
        assert_eq!(ids(Section::Updates), ["updates"]);
        assert_eq!(ids(Section::About), ["about"]);
        let listed: usize = groups()
            .iter()
            .flat_map(|(_, s)| s.iter())
            .map(|s| rows(*s).count())
            .sum();
        assert_eq!(listed, ROWS.len(), "every row sits in a listed section");
    }

    #[test]
    fn english_titles_are_the_macs() {
        assert_eq!(
            t(Lang::En, row("terminalConfig.font-size").unwrap().title),
            "Font Size"
        );
        assert_eq!(
            t(
                Lang::En,
                row("workspaceColors.subtleSelection").unwrap().title
            ),
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
        assert_eq!(
            en("app.focusHistoryIncludesPanesAndTabs"),
            "Include Panes and Tabs in Focus History"
        );
        assert_eq!(
            en("terminalConfig.middle-click-action"),
            "Middle-Click Paste"
        );
        assert_eq!(en("terminal.confirmUnsafePaste"), "Confirm Unsafe Pastes");
        assert_eq!(
            en("sidebar.showBranchDirectory"),
            "Show Branch + Directory in Sidebar"
        );
        assert_eq!(
            en("workspaceColors.indicatorStyle"),
            "Workspace Color Indicator"
        );
        assert_eq!(en("terminalTheme"), "Terminal Theme");
        assert_eq!(en("resetShortcuts"), "Reset Default Shortcuts");
        assert_eq!(en("resetAll"), "Reset All Settings");
        assert_eq!(en("paletteCharcoal"), "Charcoal");
        // Vietnamese titles come from the Mac's Vietnamese table.
        let vi = |id: &str| t(Lang::Vi, row(id).unwrap().title);
        assert_eq!(vi("terminalConfig.font-size"), "Cỡ chữ");
        assert_eq!(
            vi("workspaceColors.subtleSelection"),
            "Làm nổi bật lựa chọn tinh tế"
        );
        assert_eq!(
            vi("sidebar.hideAllDetails"),
            "Ẩn mọi chi tiết trên thanh bên"
        );
        assert_eq!(t(Lang::Vi, section_title(Section::Themes)), "Giao diện màu");
        assert_eq!(
            t(Lang::Vi, section_title(Section::KeyboardShortcuts)),
            "Phím tắt"
        );
    }

    /// A slider has a Reset button exactly where the Mac's row has one: TerminalSection.swift
    /// (Tab Bar Font Size, Scroll Speed) and SidebarSection.swift (Sidebar Font Size) have a
    /// "Reset" button; WorkspaceColorsSection.swift's Unselected Fill Opacity has none.
    #[test]
    fn slider_reset_buttons_follow_the_mac() {
        let sliders: Vec<(&str, bool)> = all_rows()
            .filter_map(|r| match r.control {
                Control::Slider { reset, .. } => Some((r.id, reset)),
                _ => None,
            })
            .collect();
        assert_eq!(
            sliders,
            [
                ("terminalConfig.surface-tab-bar-font-size", true),
                ("terminal.scrollSpeed", true),
                ("workspaceColors.unselectedFillOpacity", false),
                ("terminalConfig.sidebar-font-size", true),
            ]
        );
    }

    #[test]
    fn controls_carry_the_spec_ranges_and_the_json_spellings() {
        let control = |id: &str| row(id).unwrap().control;
        assert_eq!(
            control("terminalConfig.surface-tab-bar-font-size"),
            Control::Slider {
                min: 8.0,
                max: 14.0,
                step: 0.5,
                unit: Unit::Points,
                reset: true
            }
        );
        assert_eq!(
            control("terminal.scrollSpeed"),
            Control::Slider {
                min: 0.25,
                max: 3.0,
                step: 0.05,
                unit: Unit::Times,
                reset: true
            }
        );
        assert_eq!(
            control("workspaceColors.unselectedFillOpacity"),
            Control::Slider {
                min: 0.0,
                max: 1.0,
                step: 0.05,
                unit: Unit::Percent,
                reset: false
            }
        );
        assert_eq!(
            control("terminalConfig.sidebar-font-size"),
            Control::Slider {
                min: 10.0,
                max: 20.0,
                step: 0.5,
                unit: Unit::Points,
                reset: true
            }
        );
        assert_eq!(
            control("terminalConfig.font-size"),
            Control::Stepper {
                min: 4.0,
                max: 96.0,
                step: 0.5
            }
        );
        assert_eq!(
            control("terminalConfig.window-padding-x"),
            Control::Stepper {
                min: 0.0,
                max: 200.0,
                step: 1.0
            }
        );
        assert_eq!(
            control("terminalConfig.window-padding-y"),
            Control::Stepper {
                min: 0.0,
                max: 200.0,
                step: 1.0
            }
        );
        assert_eq!(
            control("terminalConfig.scrollback-limit"),
            Control::Number {
                min: 0.0,
                max: 100_000.0,
                unit: Unit::Megabytes
            }
        );
        assert_eq!(
            control("workspaceColors.selectionColor"),
            Control::Color { resettable: true }
        );
        assert_eq!(
            control("sidebarAppearance.tintColor"),
            Control::Color { resettable: false }
        );
        assert_eq!(control("terminalConfig.font-family"), Control::Custom);
        assert_eq!(control("app.accentColor"), Control::Custom);
        assert_eq!(control("terminal.copyOnSelect"), Control::Toggle);

        let values = |id: &str| match control(id) {
            Control::Segmented(o) | Control::Picker(o) => {
                o.iter().map(|(_, v)| *v).collect::<Vec<_>>()
            }
            other => panic!("{id} is {other:?}"),
        };
        assert_eq!(values("app.language"), ["system", "en", "vi"]);
        assert_eq!(values("app.appearance"), ["system", "light", "dark"]);
        assert_eq!(
            values("app.newWorkspacePlacement"),
            ["top", "afterCurrent", "end"]
        );
        assert_eq!(
            values("terminalConfig.cursor-style"),
            ["block", "bar", "underline", "block_hollow"]
        );
        assert_eq!(
            values("workspaceColors.indicatorStyle"),
            ["leftRail", "solidFill"]
        );
        assert_eq!(
            values("sidebarAppearance.background"),
            ["theme", "terminal", "custom"]
        );

        // Every option of every row is a value the settings model reads.
        for r in all_rows() {
            if let (Some(key), Control::Segmented(options) | Control::Picker(options)) =
                (r.key, r.control)
            {
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
        let new = Str::ALL
            .iter()
            .copied()
            .filter(|s| format!("{s:?}").starts_with("Settings"));
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
            assert!(
                (r.visible)(&defaults) || r.id == "sidebarAppearance.tintColor",
                "{}",
                r.id
            );
            assert!(
                (r.enabled)(&defaults) || r.id.starts_with("workspaceColors."),
                "{}",
                r.id
            );
        }

        let rail = Settings {
            indicator_style: IndicatorStyle::LeftRail,
            ..Settings::default()
        };
        let fill = Settings {
            indicator_style: IndicatorStyle::SolidFill,
            ..Settings::default()
        };
        assert!(enabled("workspaceColors.subtleSelection", &rail));
        assert!(!enabled("workspaceColors.subtleSelection", &fill));
        for id in [
            "workspaceColors.brightenInDarkMode",
            "workspaceColors.unselectedFillOpacity",
        ] {
            assert!(!enabled(id, &rail), "{id}");
            assert!(enabled(id, &fill), "{id}");
        }

        for background in [
            SidebarBackground::FollowTheme,
            SidebarBackground::MatchTerminal,
        ] {
            let s = Settings {
                sidebar_background: background,
                ..Settings::default()
            };
            assert!(
                !visible("sidebarAppearance.tintColor", &s),
                "{background:?}"
            );
        }
        let custom = Settings {
            sidebar_background: SidebarBackground::Custom,
            ..Settings::default()
        };
        assert!(visible("sidebarAppearance.tintColor", &custom));

        let hidden = Settings {
            hide_sidebar_details: true,
            ..Settings::default()
        };
        for id in [
            "sidebar.truncatePathFromStart",
            "sidebar.showBranchDirectory",
        ] {
            assert!(enabled(id, &defaults), "{id}");
            assert!(!enabled(id, &hidden), "{id}");
        }
        // While Hide All Sidebar Details is on, Truncate Path From Start and Show Branch +
        // Directory are disabled (above) but Wrap Workspace Titles stays enabled: the titles
        // still show. The Mac does the same (Packages/macOS/CmuxSettingsUI/Sources/
        // CmuxSettingsUI/Sections/SidebarSection.swift: no `.disabled(hideAll.current)` on it).
        assert!(enabled("sidebar.wrapWorkspaceTitles", &hidden));
        assert!(enabled("sidebar.hideAllDetails", &hidden));
    }

    #[test]
    fn only_the_migrated_rows_start_wired() {
        let wired: Vec<&str> = all_rows().filter(|r| r.wired).map(|r| r.id).collect();
        assert_eq!(
            wired,
            [
                "account",
                "app.language",
                "app.newWorkspacePlacement",
                "app.workspaceInheritWorkingDirectory",
                "app.keepWorkspaceOpenWhenClosingLastSurface",
                "app.focusHistoryIncludesPanesAndTabs",
                "app.equalizeSplitsOnCreate",
                "app.hideTabCloseButton",
                "app.appearance",
                "app.accentColor",
                "terminalTheme",
                "themeGallery",
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
                "sidebarAppearance.background",
                "sidebarAppearance.tintColor",
                "terminalConfig.sidebar-font-size",
                "sidebar.hideAllDetails",
                "sidebar.wrapWorkspaceTitles",
                "sidebar.truncatePathFromStart",
                "sidebar.showBranchDirectory",
                "resetShortcuts",
                "shortcutList",
                "updates",
                "about"
            ]
        );
    }

    #[test]
    fn section_ids_round_trip() {
        let ids: Vec<&str> = groups()
            .iter()
            .flat_map(|(_, s)| s.iter())
            .map(|s| s.id())
            .collect();
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
