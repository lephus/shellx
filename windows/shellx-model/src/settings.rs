//! The typed settings of the Windows app and their sparse `settings.json` form.
//!
//! Every field has a dotted JSON path (a [`Key`]); a field equal to its default is
//! absent from the file. Defaults and value spellings follow the Mac.

use std::collections::BTreeMap;

use serde_json::{Map, Number, Value};

use crate::palette::Rgba;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum LanguageChoice {
    System,
    En,
    Vi,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Appearance {
    System,
    Light,
    Dark,
}

#[derive(Clone, Copy, Debug, PartialEq)]
pub enum Accent {
    ShellxBlue,
    System,
    Custom(Rgba),
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Placement {
    Top,
    AfterCurrent,
    End,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum CursorStyle {
    Block,
    Bar,
    Underline,
    Hollow,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum IndicatorStyle {
    LeftRail,
    SolidFill,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum SidebarBackground {
    FollowTheme,
    MatchTerminal,
    Custom,
}

#[derive(Clone, Debug, PartialEq)]
pub struct Settings {
    pub language: LanguageChoice,
    pub appearance: Appearance,
    pub accent: Accent,
    pub new_workspace_placement: Placement,
    pub inherit_working_directory: bool,
    pub keep_workspace_open: bool,
    pub focus_history_includes_panes: bool,
    pub equalize_splits: bool,
    pub hide_tab_close_button: bool,
    pub theme_light: String,
    pub theme_dark: String,
    pub tab_bar_font_size: f32,
    pub scroll_speed: f32,
    pub copy_on_select: bool,
    pub confirm_unsafe_paste: bool,
    pub font_family: Option<String>,
    pub font_size: f32,
    pub cursor_style: CursorStyle,
    pub padding_x: u32,
    pub padding_y: u32,
    pub scrollback_mb: u32,
    pub middle_click_paste: bool,
    pub indicator_style: IndicatorStyle,
    pub subtle_selection: bool,
    pub brighten_in_dark: bool,
    pub unselected_fill_opacity: f32,
    pub selection_color: Option<Rgba>,
    /// Overrides of the built-in 16 workspace colours only (name to colour).
    pub palette: BTreeMap<String, Rgba>,
    pub sidebar_background: SidebarBackground,
    pub sidebar_color: Rgba,
    pub sidebar_font_size: f32,
    pub hide_sidebar_details: bool,
    pub wrap_workspace_titles: bool,
    pub truncate_path_from_start: bool,
    pub show_branch_directory: bool,
    /// Action id to chord text; `None` is an unbound action.
    pub bindings: BTreeMap<String, Option<String>>,
}

impl Default for Settings {
    fn default() -> Settings {
        Settings {
            language: LanguageChoice::System,
            appearance: Appearance::Dark,
            accent: Accent::ShellxBlue,
            new_workspace_placement: Placement::AfterCurrent,
            inherit_working_directory: true,
            keep_workspace_open: false,
            focus_history_includes_panes: false,
            equalize_splits: false,
            hide_tab_close_button: false,
            theme_light: "Catppuccin Latte".into(),
            theme_dark: "ShellX".into(),
            tab_bar_font_size: 11.0,
            scroll_speed: 1.0,
            copy_on_select: false,
            // The one default that differs from the Mac: pastes stay confirmed.
            confirm_unsafe_paste: true,
            font_family: None,
            font_size: 13.0,
            cursor_style: CursorStyle::Block,
            padding_x: 2,
            padding_y: 2,
            scrollback_mb: 50,
            middle_click_paste: true,
            indicator_style: IndicatorStyle::LeftRail,
            subtle_selection: true,
            brighten_in_dark: true,
            unselected_fill_opacity: 0.70,
            selection_color: None,
            palette: BTreeMap::new(),
            sidebar_background: SidebarBackground::FollowTheme,
            sidebar_color: Rgba::rgb(0x100B1D),
            sidebar_font_size: 12.5,
            hide_sidebar_details: false,
            wrap_workspace_titles: false,
            truncate_path_from_start: false,
            show_branch_directory: true,
            bindings: BTreeMap::new(),
        }
    }
}

/// One variant per field of [`Settings`].
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum Key {
    Language,
    Appearance,
    Accent,
    NewWorkspacePlacement,
    InheritWorkingDirectory,
    KeepWorkspaceOpen,
    FocusHistoryIncludesPanes,
    EqualizeSplits,
    HideTabCloseButton,
    ThemeLight,
    ThemeDark,
    TabBarFontSize,
    ScrollSpeed,
    CopyOnSelect,
    ConfirmUnsafePaste,
    FontFamily,
    FontSize,
    CursorStyle,
    PaddingX,
    PaddingY,
    ScrollbackMb,
    MiddleClickPaste,
    IndicatorStyle,
    SubtleSelection,
    BrightenInDark,
    UnselectedFillOpacity,
    SelectionColor,
    Palette,
    SidebarBackground,
    SidebarColor,
    SidebarFontSize,
    HideSidebarDetails,
    WrapWorkspaceTitles,
    TruncatePathFromStart,
    ShowBranchDirectory,
    Bindings,
}

impl Key {
    pub const ALL: &'static [Key] = &[
        Key::Language,
        Key::Appearance,
        Key::Accent,
        Key::NewWorkspacePlacement,
        Key::InheritWorkingDirectory,
        Key::KeepWorkspaceOpen,
        Key::FocusHistoryIncludesPanes,
        Key::EqualizeSplits,
        Key::HideTabCloseButton,
        Key::ThemeLight,
        Key::ThemeDark,
        Key::TabBarFontSize,
        Key::ScrollSpeed,
        Key::CopyOnSelect,
        Key::ConfirmUnsafePaste,
        Key::FontFamily,
        Key::FontSize,
        Key::CursorStyle,
        Key::PaddingX,
        Key::PaddingY,
        Key::ScrollbackMb,
        Key::MiddleClickPaste,
        Key::IndicatorStyle,
        Key::SubtleSelection,
        Key::BrightenInDark,
        Key::UnselectedFillOpacity,
        Key::SelectionColor,
        Key::Palette,
        Key::SidebarBackground,
        Key::SidebarColor,
        Key::SidebarFontSize,
        Key::HideSidebarDetails,
        Key::WrapWorkspaceTitles,
        Key::TruncatePathFromStart,
        Key::ShowBranchDirectory,
        Key::Bindings,
    ];

    /// The dotted path of the key in `settings.json` (also the id of its Settings row).
    pub const fn path(self) -> &'static str {
        match self {
            Key::Language => "app.language",
            Key::Appearance => "app.appearance",
            Key::Accent => "app.accentColor",
            Key::NewWorkspacePlacement => "app.newWorkspacePlacement",
            Key::InheritWorkingDirectory => "app.workspaceInheritWorkingDirectory",
            Key::KeepWorkspaceOpen => "app.keepWorkspaceOpenWhenClosingLastSurface",
            Key::FocusHistoryIncludesPanes => "app.focusHistoryIncludesPanesAndTabs",
            Key::EqualizeSplits => "app.equalizeSplitsOnCreate",
            Key::HideTabCloseButton => "app.hideTabCloseButton",
            Key::ThemeLight => "terminalConfig.theme.light",
            Key::ThemeDark => "terminalConfig.theme.dark",
            Key::TabBarFontSize => "terminalConfig.surface-tab-bar-font-size",
            Key::ScrollSpeed => "terminal.scrollSpeed",
            Key::CopyOnSelect => "terminal.copyOnSelect",
            Key::ConfirmUnsafePaste => "terminal.confirmUnsafePaste",
            Key::FontFamily => "terminalConfig.font-family",
            Key::FontSize => "terminalConfig.font-size",
            Key::CursorStyle => "terminalConfig.cursor-style",
            Key::PaddingX => "terminalConfig.window-padding-x",
            Key::PaddingY => "terminalConfig.window-padding-y",
            Key::ScrollbackMb => "terminalConfig.scrollback-limit",
            Key::MiddleClickPaste => "terminalConfig.middle-click-action",
            Key::IndicatorStyle => "workspaceColors.indicatorStyle",
            Key::SubtleSelection => "workspaceColors.subtleSelection",
            Key::BrightenInDark => "workspaceColors.brightenInDarkMode",
            Key::UnselectedFillOpacity => "workspaceColors.unselectedFillOpacity",
            Key::SelectionColor => "workspaceColors.selectionColor",
            Key::Palette => "workspaceColors.colors",
            Key::SidebarBackground => "sidebarAppearance.background",
            Key::SidebarColor => "sidebarAppearance.tintColor",
            Key::SidebarFontSize => "terminalConfig.sidebar-font-size",
            Key::HideSidebarDetails => "sidebar.hideAllDetails",
            Key::WrapWorkspaceTitles => "sidebar.wrapWorkspaceTitles",
            Key::TruncatePathFromStart => "sidebar.truncatePathFromStart",
            Key::ShowBranchDirectory => "sidebar.showBranchDirectory",
            Key::Bindings => "shortcuts.bindings",
        }
    }
}

// Scrollback is stored in bytes, as the Mac writes it (TerminalGhosttyOptionsCard.swift:
// `bytesPerMegabyte = 1_000_000`); the row shows megabytes.
const BYTES_PER_MB: u64 = 1_000_000;

// Enum spellings. Mac files: WorkspacePlacement.swift (`top`, `end`, `afterCurrent`),
// GhosttyCursorStyle.swift (`block`, `bar`, `underline`, `block_hollow`),
// WorkspaceIndicatorStyle.swift (`leftRail`, `solidFill`). The sidebar background
// strings are a Windows key; the middle-click values come from
// GhosttyTerminalOptionChange.swift (`primary-paste`, `ignore`).
const PLACEMENTS: &[(&str, Placement)] = &[
    ("top", Placement::Top),
    ("afterCurrent", Placement::AfterCurrent),
    ("end", Placement::End),
];
const CURSORS: &[(&str, CursorStyle)] = &[
    ("block", CursorStyle::Block),
    ("bar", CursorStyle::Bar),
    ("underline", CursorStyle::Underline),
    ("block_hollow", CursorStyle::Hollow),
];
const INDICATORS: &[(&str, IndicatorStyle)] = &[
    ("leftRail", IndicatorStyle::LeftRail),
    ("solidFill", IndicatorStyle::SolidFill),
];
const SIDEBAR_BACKGROUNDS: &[(&str, SidebarBackground)] = &[
    ("theme", SidebarBackground::FollowTheme),
    ("terminal", SidebarBackground::MatchTerminal),
    ("custom", SidebarBackground::Custom),
];
const LANGUAGES: &[(&str, LanguageChoice)] = &[
    ("system", LanguageChoice::System),
    ("en", LanguageChoice::En),
    ("vi", LanguageChoice::Vi),
];
const APPEARANCES: &[(&str, Appearance)] = &[
    ("system", Appearance::System),
    ("light", Appearance::Light),
    ("dark", Appearance::Dark),
];

fn name<T: Copy + PartialEq>(table: &[(&'static str, T)], v: T) -> Option<&'static str> {
    table.iter().find(|(_, t)| *t == v).map(|(n, _)| *n)
}

fn name_of<T: Copy + PartialEq>(table: &[(&'static str, T)], v: T) -> Value {
    Value::String(name(table, v).unwrap_or_default().to_string())
}

fn from_name<T: Copy>(table: &[(&str, T)], v: &Value) -> Option<T> {
    let s = v.as_str()?;
    table.iter().find(|(n, _)| *n == s).map(|(_, t)| *t)
}

fn parse_hex(s: &str) -> Option<Rgba> {
    let digits = s.strip_prefix('#')?;
    if digits.len() != 6 || !digits.bytes().all(|b| b.is_ascii_hexdigit()) {
        return None;
    }
    u32::from_str_radix(digits, 16).ok().map(Rgba::rgb)
}

fn hex_value(c: Rgba) -> Value {
    Value::String(c.hex())
}

fn num(x: f32) -> Value {
    // Four decimals keep 0.7 from being written as 0.699999988.
    let x = (f64::from(x) * 1e4).round() / 1e4;
    Number::from_f64(x).map_or(Value::Null, Value::Number)
}

/// A JSON number, or a string holding one (Ghostty config values are text).
fn as_f64(v: &Value) -> Option<f64> {
    match v {
        Value::Number(n) => n.as_f64(),
        Value::String(s) => s.trim().parse().ok(),
        _ => None,
    }
    .filter(|x| x.is_finite())
}

fn snapped(v: &Value, min: f64, max: f64, step: f64) -> Option<f32> {
    let x = as_f64(v)?.clamp(min, max);
    Some(((x / step).round() * step).clamp(min, max) as f32)
}

fn whole(v: &Value, max: u32) -> Option<u32> {
    Some(as_f64(v)?.round().clamp(0.0, f64::from(max)) as u32)
}

impl Settings {
    /// Reads each key on its own: one bad value never affects another.
    pub fn from_json(root: &Map<String, Value>) -> Settings {
        let mut s = Settings::default();
        for key in Key::ALL {
            if let Some(v) = get(root, key.path()) {
                s.set_from_value(*key, v);
            }
        }
        s
    }

    /// `None` when the field equals its default: the key is then absent from the file.
    pub fn to_value(&self, key: Key) -> Option<Value> {
        let value = self.raw(key);
        (value != Settings::default().raw(key)).then_some(value)
    }

    /// The JSON form of a field, default or not.
    fn raw(&self, key: Key) -> Value {
        match key {
            Key::Language => name_of(LANGUAGES, self.language),
            Key::Appearance => name_of(APPEARANCES, self.appearance),
            Key::Accent => Value::String(match self.accent {
                Accent::ShellxBlue => "cmux".into(),
                Accent::System => "system".into(),
                Accent::Custom(c) => c.hex(),
            }),
            Key::NewWorkspacePlacement => name_of(PLACEMENTS, self.new_workspace_placement),
            Key::InheritWorkingDirectory => self.inherit_working_directory.into(),
            Key::KeepWorkspaceOpen => (!self.keep_workspace_open).into(),
            Key::FocusHistoryIncludesPanes => self.focus_history_includes_panes.into(),
            Key::EqualizeSplits => self.equalize_splits.into(),
            Key::HideTabCloseButton => self.hide_tab_close_button.into(),
            Key::ThemeLight => self.theme_light.clone().into(),
            Key::ThemeDark => self.theme_dark.clone().into(),
            Key::TabBarFontSize => num(self.tab_bar_font_size),
            Key::ScrollSpeed => num(self.scroll_speed),
            Key::CopyOnSelect => self.copy_on_select.into(),
            Key::ConfirmUnsafePaste => self.confirm_unsafe_paste.into(),
            Key::FontFamily => self.font_family.clone().map_or(Value::Null, Value::String),
            Key::FontSize => num(self.font_size),
            Key::CursorStyle => name_of(CURSORS, self.cursor_style),
            Key::PaddingX => self.padding_x.into(),
            Key::PaddingY => self.padding_y.into(),
            Key::ScrollbackMb => (u64::from(self.scrollback_mb) * BYTES_PER_MB).into(),
            Key::MiddleClickPaste => if self.middle_click_paste {
                "primary-paste"
            } else {
                "ignore"
            }
            .into(),
            Key::IndicatorStyle => name_of(INDICATORS, self.indicator_style),
            Key::SubtleSelection => self.subtle_selection.into(),
            Key::BrightenInDark => self.brighten_in_dark.into(),
            Key::UnselectedFillOpacity => num(self.unselected_fill_opacity),
            Key::SelectionColor => self.selection_color.map_or(Value::Null, hex_value),
            Key::Palette => Value::Object(
                self.palette
                    .iter()
                    .map(|(k, c)| (k.clone(), hex_value(*c)))
                    .collect(),
            ),
            Key::SidebarBackground => name_of(SIDEBAR_BACKGROUNDS, self.sidebar_background),
            Key::SidebarColor => hex_value(self.sidebar_color),
            Key::SidebarFontSize => num(self.sidebar_font_size),
            Key::HideSidebarDetails => self.hide_sidebar_details.into(),
            Key::WrapWorkspaceTitles => self.wrap_workspace_titles.into(),
            Key::TruncatePathFromStart => self.truncate_path_from_start.into(),
            Key::ShowBranchDirectory => self.show_branch_directory.into(),
            Key::Bindings => Value::Object(
                self.bindings
                    .iter()
                    .map(|(k, v)| (k.clone(), v.clone().map_or(Value::Null, Value::String)))
                    .collect(),
            ),
        }
    }

    /// Clamps to the range; `false` (and no change) for a value of the wrong type.
    pub fn set_from_value(&mut self, key: Key, value: &Value) -> bool {
        self.try_set(key, value).is_some()
    }

    fn try_set(&mut self, key: Key, v: &Value) -> Option<()> {
        match key {
            Key::Language => self.language = from_name(LANGUAGES, v)?,
            Key::Appearance => self.appearance = from_name(APPEARANCES, v)?,
            Key::Accent => {
                self.accent = match v.as_str()? {
                    "cmux" => Accent::ShellxBlue,
                    "system" => Accent::System,
                    hex => Accent::Custom(parse_hex(hex)?),
                }
            }
            Key::NewWorkspacePlacement => self.new_workspace_placement = from_name(PLACEMENTS, v)?,
            Key::InheritWorkingDirectory => self.inherit_working_directory = v.as_bool()?,
            Key::KeepWorkspaceOpen => self.keep_workspace_open = !v.as_bool()?,
            Key::FocusHistoryIncludesPanes => self.focus_history_includes_panes = v.as_bool()?,
            Key::EqualizeSplits => self.equalize_splits = v.as_bool()?,
            Key::HideTabCloseButton => self.hide_tab_close_button = v.as_bool()?,
            Key::ThemeLight => self.theme_light = v.as_str()?.to_string(),
            Key::ThemeDark => self.theme_dark = v.as_str()?.to_string(),
            Key::TabBarFontSize => self.tab_bar_font_size = snapped(v, 8.0, 14.0, 0.5)?,
            Key::ScrollSpeed => self.scroll_speed = snapped(v, 0.25, 3.0, 0.05)?,
            Key::CopyOnSelect => self.copy_on_select = v.as_bool()?,
            Key::ConfirmUnsafePaste => self.confirm_unsafe_paste = v.as_bool()?,
            Key::FontFamily => {
                self.font_family = match v {
                    Value::Null => None,
                    other => Some(other.as_str()?.to_string()).filter(|s| !s.is_empty()),
                }
            }
            Key::FontSize => self.font_size = snapped(v, 4.0, 96.0, 0.5)?,
            Key::CursorStyle => self.cursor_style = from_name(CURSORS, v)?,
            Key::PaddingX => self.padding_x = whole(v, 200)?,
            Key::PaddingY => self.padding_y = whole(v, 200)?,
            Key::ScrollbackMb => {
                let bytes = as_f64(v)?.max(0.0);
                let mb = (bytes / BYTES_PER_MB as f64).round();
                self.scrollback_mb = mb.min(100_000.0) as u32;
            }
            Key::MiddleClickPaste => {
                self.middle_click_paste = match v.as_str()? {
                    "primary-paste" => true,
                    "ignore" => false,
                    _ => return None,
                }
            }
            Key::IndicatorStyle => self.indicator_style = from_name(INDICATORS, v)?,
            Key::SubtleSelection => self.subtle_selection = v.as_bool()?,
            Key::BrightenInDark => self.brighten_in_dark = v.as_bool()?,
            Key::UnselectedFillOpacity => {
                self.unselected_fill_opacity = snapped(v, 0.0, 1.0, 0.05)?
            }
            Key::SelectionColor => {
                self.selection_color = match v {
                    Value::Null => None,
                    other => Some(parse_hex(other.as_str()?)?),
                }
            }
            Key::Palette => {
                self.palette = v
                    .as_object()?
                    .iter()
                    .filter_map(|(k, c)| Some((k.clone(), parse_hex(c.as_str()?)?)))
                    .collect()
            }
            Key::SidebarBackground => {
                self.sidebar_background = from_name(SIDEBAR_BACKGROUNDS, v)?
            }
            Key::SidebarColor => self.sidebar_color = parse_hex(v.as_str()?)?,
            Key::SidebarFontSize => self.sidebar_font_size = snapped(v, 10.0, 20.0, 0.5)?,
            Key::HideSidebarDetails => self.hide_sidebar_details = v.as_bool()?,
            Key::WrapWorkspaceTitles => self.wrap_workspace_titles = v.as_bool()?,
            Key::TruncatePathFromStart => self.truncate_path_from_start = v.as_bool()?,
            Key::ShowBranchDirectory => self.show_branch_directory = v.as_bool()?,
            Key::Bindings => {
                self.bindings = v
                    .as_object()?
                    .iter()
                    .filter_map(|(k, c)| match c {
                        Value::Null => Some((k.clone(), None)),
                        Value::String(s) => Some((k.clone(), Some(s.clone()))),
                        _ => None,
                    })
                    .collect()
            }
        }
        Some(())
    }

    pub fn reset(&mut self, key: Key) {
        let default = Settings::default().raw(key);
        self.set_from_value(key, &default);
    }

    // Typed access for the Settings rows (`shellx-app/src/ui/settings/rows.rs`): a row reads
    // the value it shows with one of these and writes it back with the matching `*_value`
    // function, so no control spells a key's JSON itself (Keep Workspace Open is stored
    // inverted, Middle-Click Paste as a word, the scrollback in bytes).

    /// Whether a switch row shows on. `None` for a key that is not a switch.
    pub fn flag(&self, key: Key) -> Option<bool> {
        // Read through the stored form, so the key-to-field table is `flag_field` alone.
        let on = flag_value(key, true)?;
        Some(self.raw(key) == on)
    }

    /// The number a slider, stepper or number row shows: megabytes for the scrollback. `None`
    /// for a key that is not a number.
    pub fn number(&self, key: Key) -> Option<f32> {
        Some(match key {
            Key::TabBarFontSize => self.tab_bar_font_size,
            Key::ScrollSpeed => self.scroll_speed,
            Key::FontSize => self.font_size,
            Key::PaddingX => self.padding_x as f32,
            Key::PaddingY => self.padding_y as f32,
            Key::ScrollbackMb => self.scrollback_mb as f32,
            Key::UnselectedFillOpacity => self.unselected_fill_opacity,
            Key::SidebarFontSize => self.sidebar_font_size,
            _ => return None,
        })
    }

    /// The option a segmented or picker row shows, spelled as its JSON value (the catalogue's
    /// option values). `None` for a key without options.
    pub fn choice(&self, key: Key) -> Option<&'static str> {
        match key {
            Key::Language => name(LANGUAGES, self.language),
            Key::Appearance => name(APPEARANCES, self.appearance),
            Key::NewWorkspacePlacement => name(PLACEMENTS, self.new_workspace_placement),
            Key::CursorStyle => name(CURSORS, self.cursor_style),
            Key::IndicatorStyle => name(INDICATORS, self.indicator_style),
            Key::SidebarBackground => name(SIDEBAR_BACKGROUNDS, self.sidebar_background),
            _ => None,
        }
    }

    /// The colour a colour row shows; `None` when none is set (Selection Highlight's
    /// "Default") or the key is not a colour.
    pub fn colour(&self, key: Key) -> Option<Rgba> {
        match key {
            Key::SelectionColor => self.selection_color,
            Key::SidebarColor => Some(self.sidebar_color),
            _ => None,
        }
    }

    /// The field behind a switch row's key.
    fn flag_field(&mut self, key: Key) -> Option<&mut bool> {
        Some(match key {
            Key::InheritWorkingDirectory => &mut self.inherit_working_directory,
            Key::KeepWorkspaceOpen => &mut self.keep_workspace_open,
            Key::FocusHistoryIncludesPanes => &mut self.focus_history_includes_panes,
            Key::EqualizeSplits => &mut self.equalize_splits,
            Key::HideTabCloseButton => &mut self.hide_tab_close_button,
            Key::CopyOnSelect => &mut self.copy_on_select,
            Key::ConfirmUnsafePaste => &mut self.confirm_unsafe_paste,
            Key::MiddleClickPaste => &mut self.middle_click_paste,
            Key::SubtleSelection => &mut self.subtle_selection,
            Key::BrightenInDark => &mut self.brighten_in_dark,
            Key::HideSidebarDetails => &mut self.hide_sidebar_details,
            Key::WrapWorkspaceTitles => &mut self.wrap_workspace_titles,
            Key::TruncatePathFromStart => &mut self.truncate_path_from_start,
            Key::ShowBranchDirectory => &mut self.show_branch_directory,
            _ => return None,
        })
    }
}

/// The JSON `SettingsService::set` takes for a switch row turned on or off.
pub fn flag_value(key: Key, on: bool) -> Option<Value> {
    let mut s = Settings::default();
    *s.flag_field(key)? = on;
    Some(s.raw(key))
}

/// The JSON for a number row set to `shown` (megabytes for the scrollback, written in bytes).
/// `None` for a key that is not a number, or a value that is not finite.
pub fn number_value(key: Key, shown: f32) -> Option<Value> {
    Settings::default().number(key)?;
    if !shown.is_finite() {
        return None;
    }
    Some(match key {
        Key::ScrollbackMb => {
            let mb = f64::from(shown).max(0.0).round() as u64;
            Value::from(mb.saturating_mul(BYTES_PER_MB))
        }
        _ => num(shown),
    })
}

/// The JSON for picking `choice` in a segmented or picker row; `None` when the key has no such
/// option.
pub fn choice_value(key: Key, choice: &str) -> Option<Value> {
    Settings::default().choice(key)?;
    let value = Value::String(choice.to_string());
    Settings::default()
        .set_from_value(key, &value)
        .then_some(value)
}

/// The JSON for a colour row set to `colour`.
pub fn colour_value(key: Key, colour: Rgba) -> Option<Value> {
    matches!(key, Key::SelectionColor | Key::SidebarColor).then(|| hex_value(colour))
}

pub fn get<'a>(root: &'a Map<String, Value>, path: &str) -> Option<&'a Value> {
    let mut parts = path.split('.');
    let mut cur = root.get(parts.next()?)?;
    for part in parts {
        cur = cur.as_object()?.get(part)?;
    }
    Some(cur)
}

/// Inserts along a dotted path; `None` removes the key and prunes parents it leaves empty.
pub fn put(root: &mut Map<String, Value>, path: &str, value: Option<Value>) {
    let parts: Vec<&str> = path.split('.').collect();
    put_parts(root, &parts, value);
}

fn put_parts(map: &mut Map<String, Value>, parts: &[&str], value: Option<Value>) {
    let [head, rest @ ..] = parts else { return };
    if rest.is_empty() {
        match value {
            Some(v) => {
                map.insert((*head).to_string(), v);
            }
            None => {
                map.remove(*head);
            }
        }
        return;
    }
    if value.is_none() && !map.get(*head).is_some_and(Value::is_object) {
        return;
    }
    let child = map
        .entry((*head).to_string())
        .or_insert_with(|| Value::Object(Map::new()));
    if !child.is_object() {
        *child = Value::Object(Map::new());
    }
    let inner = child.as_object_mut().expect("just made an object");
    put_parts(inner, rest, value);
    if inner.is_empty() {
        map.remove(*head);
    }
}

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

    use crate::settings_catalog::{Control, Section, groups, rows};

    /// Every row of the catalogue with its key and control.
    fn keyed_rows() -> impl Iterator<Item = (Key, Control)> {
        groups()
            .iter()
            .flat_map(|(_, sections)| sections.iter().copied())
            .flat_map(|section: Section| rows(section))
            .filter_map(|row| row.key.map(|key| (key, row.control)))
    }

    /// The value a row writes, read back as the file would give it.
    fn applied(key: Key, value: Option<Value>) -> Settings {
        let value = value.unwrap_or_else(|| panic!("{key:?} has no value"));
        let mut s = Settings::default();
        assert!(s.set_from_value(key, &value), "{key:?} accepts {value}");
        s
    }

    #[test]
    fn a_switch_shows_its_meaning_and_writes_the_stored_spelling() {
        // Keep Workspace Open is stored inverted.
        assert_eq!(flag_value(Key::KeepWorkspaceOpen, true), Some(json!(false)));
        assert_eq!(flag_value(Key::KeepWorkspaceOpen, false), Some(json!(true)));
        assert_eq!(
            Settings::default().flag(Key::KeepWorkspaceOpen),
            Some(false)
        );
        let kept = applied(
            Key::KeepWorkspaceOpen,
            flag_value(Key::KeepWorkspaceOpen, true),
        );
        assert!(kept.keep_workspace_open);
        assert_eq!(kept.flag(Key::KeepWorkspaceOpen), Some(true));
        // Middle-Click Paste is stored as "primary-paste" / "ignore".
        assert_eq!(
            flag_value(Key::MiddleClickPaste, true),
            Some(json!("primary-paste"))
        );
        assert_eq!(
            flag_value(Key::MiddleClickPaste, false),
            Some(json!("ignore"))
        );
        assert_eq!(Settings::default().flag(Key::MiddleClickPaste), Some(true));
        let ignored = applied(
            Key::MiddleClickPaste,
            flag_value(Key::MiddleClickPaste, false),
        );
        assert_eq!(ignored.flag(Key::MiddleClickPaste), Some(false));
        // A plain switch.
        assert_eq!(flag_value(Key::CopyOnSelect, true), Some(json!(true)));
        // Not a switch.
        assert_eq!(Settings::default().flag(Key::FontSize), None);
        assert_eq!(flag_value(Key::FontSize, true), None);
        // Every switch row of the catalogue, both ways.
        for (key, control) in keyed_rows() {
            if control != Control::Toggle {
                continue;
            }
            for on in [true, false] {
                let s = applied(key, flag_value(key, on));
                assert_eq!(s.flag(key), Some(on), "{key:?} {on}");
            }
        }
    }

    #[test]
    fn a_number_row_shows_megabytes_and_writes_bytes_for_the_scrollback() {
        assert_eq!(Settings::default().number(Key::ScrollbackMb), Some(50.0));
        assert_eq!(
            number_value(Key::ScrollbackMb, 75.0),
            Some(json!(75_000_000u64))
        );
        let s = applied(Key::ScrollbackMb, number_value(Key::ScrollbackMb, 75.0));
        assert_eq!(s.scrollback_mb, 75);
        assert_eq!(s.number(Key::ScrollbackMb), Some(75.0));
        assert_eq!(number_value(Key::FontSize, 15.5), Some(json!(15.5)));
        assert_eq!(Settings::default().number(Key::PaddingX), Some(2.0));
        assert_eq!(number_value(Key::FontSize, f32::NAN), None);
        assert_eq!(Settings::default().number(Key::CopyOnSelect), None);
        assert_eq!(number_value(Key::CopyOnSelect, 1.0), None);
        // Every slider, stepper and number row reads back what it wrote.
        for (key, control) in keyed_rows() {
            let (min, max) = match control {
                Control::Slider { min, max, .. }
                | Control::Stepper { min, max, .. }
                | Control::Number { min, max, .. } => (min, max),
                _ => continue,
            };
            for shown in [min, max] {
                let s = applied(key, number_value(key, shown));
                assert_eq!(s.number(key), Some(shown), "{key:?} {shown}");
            }
        }
    }

    #[test]
    fn a_choice_row_writes_the_catalogue_spelling() {
        assert_eq!(Settings::default().choice(Key::CursorStyle), Some("block"));
        assert_eq!(
            choice_value(Key::CursorStyle, "block_hollow"),
            Some(json!("block_hollow"))
        );
        assert_eq!(choice_value(Key::CursorStyle, "hollow"), None);
        assert_eq!(choice_value(Key::CopyOnSelect, "block"), None);
        assert_eq!(Settings::default().choice(Key::FontSize), None);
        // Every option of every segmented and picker row.
        for (key, control) in keyed_rows() {
            let options = match control {
                Control::Segmented(options) | Control::Picker(options) => options,
                _ => continue,
            };
            for (_, spelling) in options {
                let s = applied(key, choice_value(key, spelling));
                assert_eq!(s.choice(key), Some(*spelling), "{key:?}");
            }
        }
    }

    #[test]
    fn a_colour_row_writes_its_hex_code() {
        assert_eq!(Settings::default().colour(Key::SelectionColor), None);
        assert_eq!(
            Settings::default().colour(Key::SidebarColor),
            Some(Rgba::rgb(0x100B1D))
        );
        let colour = Rgba::rgb(0x112233);
        assert_eq!(
            colour_value(Key::SelectionColor, colour),
            Some(json!("#112233"))
        );
        assert_eq!(colour_value(Key::FontSize, colour), None);
        assert_eq!(Settings::default().colour(Key::FontSize), None);
        for (key, control) in keyed_rows() {
            if !matches!(control, Control::Color { .. }) {
                continue;
            }
            let s = applied(key, colour_value(key, colour));
            assert_eq!(s.colour(key), Some(colour), "{key:?}");
        }
    }
}
