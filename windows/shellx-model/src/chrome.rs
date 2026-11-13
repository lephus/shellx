//! The app's chrome colours derived from the terminal theme and the accent (spec §5.5).
//!
//! The ShellX theme gives exactly the `palette` constants. Any other theme takes the same steps
//! ShellX's chrome takes between its background and its text, measured from those constants, and
//! every text colour is pushed until it reads on the surface it is drawn on.

use crate::palette::{self, Rgba};
use crate::settings::{Accent, SidebarBackground};
use crate::theme_file::{TermTheme, is_dark};

const WHITE: Rgba = Rgba::rgb(0xffffff);
const BLACK: Rgba = Rgba::rgb(0x000000);

/// WCAG AA for text, and for the muted text the spec allows at 3:1 (spec §5.5).
const TEXT_MIN: f32 = 4.5;
const MUTED_MIN: f32 = 3.0;

/// The sidebar following another theme: a dark one lifted 2% towards white, a light one pressed
/// 3% towards black (Mac: `WindowChromeSidebarTintDefaults.themeTint`, CmuxAppKitSupportUI).
const SIDEBAR_LIFT: f32 = 0.02;
const SIDEBAR_PRESS: f32 = 0.03;

/// Text on a sidebar whose readable side is not the window's (a custom colour): the strengths of
/// the system label colours the Mac draws on such a sidebar, `labelColor` and
/// `secondaryLabelColor` (Mac: `ShellXSidebarText`, ShellXBrand).
const LABEL: f32 = 0.85;
const SECONDARY_LABEL: f32 = 0.5;

/// Selected text in a text field: the accent at the strength ShellX 1.7.1 draws it.
const FIELD_SELECTION_ALPHA: f32 = 0.3;

/// The least contrast a border on a Custom sidebar keeps against it: visible, never glaring.
const EDGE_MIN: f32 = 1.5;

#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Chrome {
    /// The theme is dark (`theme_file::is_dark`).
    pub dark: bool,
    pub bg: Rgba,
    pub panel: Rgba,
    pub raise: Rgba,
    pub line: Rgba,
    pub border: Rgba,
    pub text: Rgba,
    pub text_hi: Rgba,
    pub muted: Rgba,
    pub primary: Rgba,
    pub primary_soft: Rgba,
    pub primary_line: Rgba,
    pub primary_text: Rgba,
    /// Fills and dots: the fixed status hues on every theme.
    pub running: Rgba,
    pub done: Rgba,
    pub error: Rgba,
    /// The same hues as text, adjusted for contrast on `bg`.
    pub running_text: Rgba,
    pub done_text: Rgba,
    pub error_text: Rgba,
    pub selection_title: Rgba,
    pub indicator_unfocused: Rgba,
    /// Session row fills, on `sidebar_bg`.
    pub session_selected: Rgba,
    pub session_hover: Rgba,
    pub sidebar_bg: Rgba,
    pub sidebar_text: Rgba,
    pub sidebar_muted: Rgba,
    /// Hover fill on the window's own surfaces (tab bar, menus, the machine list), stepped from
    /// `panel` whatever the sidebar is.
    pub panel_hover: Rgba,
    /// Selected text in a text field: the accent at 30%.
    pub field_selection: Rgba,
    /// The selected workspace card's title, on `session_selected`.
    pub sidebar_selection_title: Rgba,
    /// The accent as text on the sidebar: the pairing code, the update pill, a primary button.
    pub sidebar_primary_text: Rgba,
    /// An icon under the pointer on the sidebar (the machines header's "+").
    pub sidebar_icon_hover: Rgba,
    /// The sidebar's edge and the line above its footer, and the selected card's border.
    pub sidebar_line: Rgba,
    pub sidebar_border: Rgba,
}

/// WCAG 2 contrast ratio of two opaque colours, 1.0 to 21.0 (alpha is ignored).
pub fn contrast(a: Rgba, b: Rgba) -> f32 {
    let (la, lb) = (luminance(a), luminance(b));
    (la.max(lb) + 0.05) / (la.min(lb) + 0.05)
}

/// Moves `fg` away from `bg` (towards white on dark, black on light) until the ratio is at least `min`.
///
/// `fg` comes back unchanged when it already reads. Otherwise it moves towards the end (white or
/// black) on its own side of `bg`, the smallest change; when that end cannot reach `min` it crosses
/// over `bg` towards the other end. When neither end reaches `min`, the result is the end that
/// contrasts more with `bg`. Each search halves a range of 255 steps, so it always ends.
pub fn ensure_contrast(fg: Rgba, bg: Rgba, min: f32) -> Rgba {
    if contrast(fg, bg) >= min {
        return fg;
    }
    let near = end_beyond(fg, bg);
    let far = if near == WHITE { BLACK } else { WHITE };
    for end in [near, far] {
        if contrast(end, bg) >= min {
            return first_readable(fg, end, bg, min);
        }
    }
    best_end(bg).with_alpha(fg.a)
}

/// The accent setting as a colour: ShellX Blue, the Windows accent (ShellX Blue when it cannot be
/// read), or the user's own.
pub fn accent_color(accent: &Accent, system: Option<Rgba>) -> Rgba {
    match accent {
        Accent::ShellxBlue => palette::PRIMARY,
        Accent::System => system.unwrap_or(palette::PRIMARY),
        Accent::Custom(color) => *color,
    }
}

/// The DWM `AccentColor` registry value, laid out 0xAABBGGRR; the alpha byte is ignored.
pub fn accent_from_dwm(abgr: u32) -> Rgba {
    Rgba {
        r: abgr as u8,
        g: (abgr >> 8) as u8,
        b: (abgr >> 16) as u8,
        a: 1.0,
    }
}

/// The chrome for `theme`, `accent` and the sidebar background setting (`sidebar_color` is the
/// Custom colour).
pub fn chrome(
    theme: &TermTheme,
    accent: Rgba,
    sidebar: SidebarBackground,
    sidebar_color: Rgba,
) -> Chrome {
    let s = if theme.background == palette::BG && theme.foreground == palette::TEXT {
        Surfaces::SHELLX
    } else {
        Surfaces::derive(theme.background, theme.foreground)
    };
    let sidebar_bg = sidebar_background(theme, sidebar, sidebar_color);
    let (sidebar_text, sidebar_muted) = sidebar_text(&s, sidebar_bg);
    let (session_selected, session_hover) = session_fills(sidebar_bg, sidebar_text);
    // The sidebar reads with the window's end: it keeps the window's colours, pushed until they
    // read on it; otherwise its own label colour stands in for them.
    let same_side = best_end(sidebar_bg) == best_end(s.bg);
    let on_sidebar = |window: Rgba| if same_side { window } else { sidebar_text };
    let (sidebar_line, sidebar_border) = if sidebar == SidebarBackground::Custom {
        // The window's borders belong to the window's colours; on a colour of the user's choice
        // they take the steps ShellX's take, from that colour towards its text, and stay visible.
        let at = |stop: Rgba| {
            let edge = mix(
                sidebar_bg,
                sidebar_text,
                step(palette::BG, stop, palette::TEXT),
            );
            ensure_contrast(edge, sidebar_bg, EDGE_MIN)
        };
        (at(palette::LINE), at(palette::BORDER))
    } else {
        (s.line, s.border)
    };
    Chrome {
        dark: is_dark(theme),
        bg: s.bg,
        panel: s.panel,
        raise: s.raise,
        line: s.line,
        border: s.border,
        text: s.text,
        text_hi: s.text_hi,
        muted: s.muted,
        primary: accent,
        primary_soft: accent.with_alpha(palette::PRIMARY_SOFT.a),
        primary_line: accent.with_alpha(palette::PRIMARY_LINE.a),
        primary_text: primary_text(accent, s.bg),
        running: palette::RUNNING,
        done: palette::DONE,
        error: palette::ERROR,
        running_text: ensure_contrast(palette::RUNNING, s.bg, TEXT_MIN),
        done_text: ensure_contrast(palette::DONE, s.bg, TEXT_MIN),
        error_text: ensure_contrast(palette::ERROR, s.bg, TEXT_MIN),
        selection_title: s.selection_title,
        indicator_unfocused: s.indicator_unfocused,
        session_selected,
        session_hover,
        sidebar_bg,
        sidebar_text,
        sidebar_muted,
        panel_hover: session_fills(s.panel, s.text_hi).1,
        field_selection: accent.with_alpha(FIELD_SELECTION_ALPHA),
        sidebar_selection_title: ensure_contrast(
            on_sidebar(s.selection_title),
            session_selected,
            TEXT_MIN,
        ),
        sidebar_primary_text: primary_text(accent, sidebar_bg),
        sidebar_icon_hover: ensure_contrast(on_sidebar(s.text), sidebar_bg, TEXT_MIN),
        sidebar_line,
        sidebar_border,
    }
}

/// The window's surfaces and text, which depend on the theme alone.
struct Surfaces {
    bg: Rgba,
    panel: Rgba,
    raise: Rgba,
    line: Rgba,
    border: Rgba,
    text: Rgba,
    text_hi: Rgba,
    muted: Rgba,
    selection_title: Rgba,
    indicator_unfocused: Rgba,
}

impl Surfaces {
    const SHELLX: Surfaces = Surfaces {
        bg: palette::BG,
        panel: palette::PANEL,
        raise: palette::RAISE,
        line: palette::LINE,
        border: palette::BORDER,
        text: palette::TEXT,
        text_hi: palette::TEXT_HI,
        muted: palette::MUTED,
        selection_title: palette::SELECTION_TITLE,
        indicator_unfocused: palette::INDICATOR_UNFOCUSED,
    };

    /// Each surface sits where its ShellX constant sits on the way from `BG` to `TEXT`, here from
    /// `bg` to the readable text; the brighter texts sit where `TEXT_HI` and `SELECTION_TITLE` sit
    /// on the way on to white (to black on a light theme).
    fn derive(bg: Rgba, fg: Rgba) -> Surfaces {
        let text = ensure_contrast(fg, bg, TEXT_MIN);
        let at = |stop: Rgba| mix(bg, text, step(palette::BG, stop, palette::TEXT));
        let beyond = end_beyond(text, bg);
        let text_hi = mix(text, beyond, step(palette::TEXT, palette::TEXT_HI, WHITE));
        Surfaces {
            bg,
            panel: at(palette::PANEL),
            raise: at(palette::RAISE),
            line: at(palette::LINE),
            border: at(palette::BORDER),
            text,
            text_hi,
            muted: ensure_contrast(at(palette::MUTED), bg, MUTED_MIN),
            selection_title: mix(
                text_hi,
                beyond,
                step(palette::TEXT_HI, palette::SELECTION_TITLE, WHITE),
            ),
            indicator_unfocused: at(palette::INDICATOR_UNFOCUSED),
        }
    }
}

/// Follow Theme: ShellX keeps `PANEL`, recognised by its background as the Mac does; another
/// theme is lifted or pressed one small step. Match Terminal: the theme's background.
fn sidebar_background(theme: &TermTheme, sidebar: SidebarBackground, custom: Rgba) -> Rgba {
    match sidebar {
        SidebarBackground::FollowTheme if theme.background == palette::BG => palette::PANEL,
        SidebarBackground::FollowTheme if is_dark(theme) => {
            mix(theme.background, WHITE, SIDEBAR_LIFT)
        }
        SidebarBackground::FollowTheme => mix(theme.background, BLACK, SIDEBAR_PRESS),
        SidebarBackground::MatchTerminal => theme.background,
        SidebarBackground::Custom => custom,
    }
}

/// Names and labels on the sidebar. A sidebar that reads with the same end as the window keeps
/// the window's `text_hi` and `muted` (ShellX's sidebar draws names in `TEXT_HI`); one that does
/// not takes label colours made from its own readable end.
fn sidebar_text(s: &Surfaces, sidebar_bg: Rgba) -> (Rgba, Rgba) {
    let end = best_end(sidebar_bg);
    let (text, muted) = if end == best_end(s.bg) {
        (s.text_hi, s.muted)
    } else {
        (
            mix(sidebar_bg, end, LABEL),
            mix(sidebar_bg, end, SECONDARY_LABEL),
        )
    };
    (
        ensure_contrast(text, sidebar_bg, TEXT_MIN),
        ensure_contrast(muted, sidebar_bg, MUTED_MIN),
    )
}

/// The selected and hovered rows on a surface (the sidebar, or the window's panels): ShellX's own
/// fills on ShellX's panel, otherwise the same steps from the surface towards its text.
fn session_fills(surface: Rgba, text: Rgba) -> (Rgba, Rgba) {
    if surface == palette::PANEL && text == palette::TEXT_HI {
        return (palette::SESSION_SELECTED, palette::SESSION_HOVER);
    }
    let at = |stop: Rgba| mix(surface, text, step(palette::PANEL, stop, palette::TEXT_HI));
    (at(palette::SESSION_SELECTED), at(palette::SESSION_HOVER))
}

/// The accent as text: lifted the step `PRIMARY_TEXT` takes from `PRIMARY` (ShellX Blue lifts to
/// `PRIMARY_TEXT` itself), away from `bg`, then pushed until it reads.
fn primary_text(accent: Rgba, bg: Rgba) -> Rgba {
    let beyond = end_beyond(accent, bg);
    let lifted = if accent == palette::PRIMARY && beyond == WHITE {
        palette::PRIMARY_TEXT
    } else {
        mix(
            accent,
            beyond,
            step(palette::PRIMARY, palette::PRIMARY_TEXT, WHITE),
        )
    };
    ensure_contrast(lifted, bg, TEXT_MIN)
}

/// Relative luminance, sRGB linearised as the Mac does (`WindowChromeColorResolver`,
/// CmuxAppKitSupportUI).
fn luminance(c: Rgba) -> f32 {
    let linear = |v: u8| {
        let s = f32::from(v) / 255.0;
        if s <= 0.03928 {
            s / 12.92
        } else {
            ((s + 0.055) / 1.055).powf(2.4)
        }
    };
    0.2126 * linear(c.r) + 0.7152 * linear(c.g) + 0.0722 * linear(c.b)
}

/// Whether `bg` reads as a dark surface: white is its readable end (Mac: `readableColorScheme`).
pub(crate) fn is_dark_surface(bg: Rgba) -> bool {
    best_end(bg) == WHITE
}

/// White or black, whichever contrasts more with `bg` (Mac: `readableColorScheme`).
fn best_end(bg: Rgba) -> Rgba {
    if contrast(WHITE, bg) >= contrast(BLACK, bg) {
        WHITE
    } else {
        BLACK
    }
}

/// The end that lies beyond `c` as seen from `bg`: white when `c` is lighter, black when darker,
/// and the end that contrasts more when the two are equally light.
fn end_beyond(c: Rgba, bg: Rgba) -> Rgba {
    let (lc, lb) = (luminance(c), luminance(bg));
    if lc > lb {
        WHITE
    } else if lc < lb {
        BLACK
    } else {
        best_end(bg)
    }
}

/// The colour nearest `fg` on the way to `end` that reaches `min` on `bg`. `fg` does not reach
/// it and `end` does. Every channel moves one way, so luminance only grows (or only shrinks)
/// along the way: once past `bg` the ratio only grows, and before that it stays below `fg`'s.
fn first_readable(fg: Rgba, end: Rgba, bg: Rgba, min: f32) -> Rgba {
    let at = |k: u32| mix(fg, end, k as f32 / 255.0);
    let (mut fails, mut reads) = (0u32, 255u32);
    while reads - fails > 1 {
        let k = (fails + reads) / 2;
        if contrast(at(k), bg) >= min {
            reads = k;
        } else {
            fails = k;
        }
    }
    at(reads)
}

/// `from` moved the fraction `t` of the way to `to`, each channel rounded; `from`'s alpha.
pub(crate) fn mix(from: Rgba, to: Rgba, t: f32) -> Rgba {
    let channel = |a: u8, b: u8| {
        (f32::from(a) + (f32::from(b) - f32::from(a)) * t)
            .round()
            .clamp(0.0, 255.0) as u8
    };
    Rgba {
        r: channel(from.r, to.r),
        g: channel(from.g, to.g),
        b: channel(from.b, to.b),
        a: from.a,
    }
}

/// How far `at` sits on the way from `from` to `to`: the channel differences summed over the
/// channel ranges summed. Used to read ShellX's own steps off the palette constants.
fn step(from: Rgba, at: Rgba, to: Rgba) -> f32 {
    let span = |a: Rgba, b: Rgba| {
        (f32::from(b.r) - f32::from(a.r))
            + (f32::from(b.g) - f32::from(a.g))
            + (f32::from(b.b) - f32::from(a.b))
    };
    span(from, at) / span(from, to)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::palette;
    use crate::theme_file::{ThemeSet, bundled, parse, shellx};

    fn rgb(hex: u32) -> Rgba {
        Rgba::rgb(hex)
    }

    fn named(name: &str) -> TermTheme {
        ThemeSet::new(vec![]).get(name).unwrap()
    }

    /// A theme with only these two colours changed from ShellX's.
    fn theme(background: u32, foreground: u32) -> TermTheme {
        TermTheme {
            name: "Test".into(),
            background: rgb(background),
            foreground: rgb(foreground),
            ..shellx()
        }
    }

    /// The pairs spec §5.5 requires: text colours at 4.5:1, muted text at 3:1, each on the surface
    /// it is drawn on.
    fn readable_pairs(c: &Chrome) -> [(&'static str, Rgba, Rgba, f32); 11] {
        [
            (
                "sidebar_selection_title on session_selected",
                c.sidebar_selection_title,
                c.session_selected,
                4.5,
            ),
            (
                "sidebar_primary_text on sidebar_bg",
                c.sidebar_primary_text,
                c.sidebar_bg,
                4.5,
            ),
            (
                "sidebar_icon_hover on sidebar_bg",
                c.sidebar_icon_hover,
                c.sidebar_bg,
                4.5,
            ),
            ("text on bg", c.text, c.bg, 4.5),
            (
                "sidebar_text on sidebar_bg",
                c.sidebar_text,
                c.sidebar_bg,
                4.5,
            ),
            ("primary_text on bg", c.primary_text, c.bg, 4.5),
            ("running_text on bg", c.running_text, c.bg, 4.5),
            ("done_text on bg", c.done_text, c.bg, 4.5),
            ("error_text on bg", c.error_text, c.bg, 4.5),
            ("muted on bg", c.muted, c.bg, 3.0),
            (
                "sidebar_muted on sidebar_bg",
                c.sidebar_muted,
                c.sidebar_bg,
                3.0,
            ),
        ]
    }

    #[test]
    fn the_shellx_theme_gives_todays_chrome_exactly() {
        let c = chrome(
            &shellx(),
            rgb(0x60a5fa),
            SidebarBackground::FollowTheme,
            rgb(0x100b1d),
        );
        assert_eq!(c.bg, palette::BG);
        assert_eq!(c.panel, palette::PANEL);
        assert_eq!(c.raise, palette::RAISE);
        assert_eq!(c.line, palette::LINE);
        assert_eq!(c.border, palette::BORDER);
        assert_eq!(c.text, palette::TEXT);
        assert_eq!(c.text_hi, palette::TEXT_HI);
        assert_eq!(c.muted, palette::MUTED);
        assert_eq!(c.primary_text, palette::PRIMARY_TEXT);
        assert_eq!(c.sidebar_bg, palette::PANEL);
        assert_eq!(c.running_text, palette::RUNNING);
        assert_eq!(c.session_selected, rgb(0x1a1430));
        // Every field. The sidebar draws names in TEXT_HI and labels in MUTED today.
        assert_eq!(
            c,
            Chrome {
                dark: true,
                bg: palette::BG,
                panel: palette::PANEL,
                raise: palette::RAISE,
                line: palette::LINE,
                border: palette::BORDER,
                text: palette::TEXT,
                text_hi: palette::TEXT_HI,
                muted: palette::MUTED,
                primary: palette::PRIMARY,
                primary_soft: palette::PRIMARY_SOFT,
                primary_line: palette::PRIMARY_LINE,
                primary_text: palette::PRIMARY_TEXT,
                running: palette::RUNNING,
                done: palette::DONE,
                error: palette::ERROR,
                running_text: palette::RUNNING,
                done_text: palette::DONE,
                error_text: palette::ERROR,
                selection_title: palette::SELECTION_TITLE,
                indicator_unfocused: palette::INDICATOR_UNFOCUSED,
                session_selected: palette::SESSION_SELECTED,
                session_hover: palette::SESSION_HOVER,
                sidebar_bg: palette::PANEL,
                sidebar_text: palette::TEXT_HI,
                sidebar_muted: palette::MUTED,
                // The tab bar and menus hover with the session row's fill today.
                panel_hover: palette::SESSION_HOVER,
                field_selection: palette::PRIMARY.with_alpha(0.3),
                sidebar_selection_title: palette::SELECTION_TITLE,
                sidebar_primary_text: palette::PRIMARY_TEXT,
                // The machines header's "+" turns TEXT under the pointer.
                sidebar_icon_hover: palette::TEXT,
                sidebar_line: palette::LINE,
                sidebar_border: palette::BORDER,
            }
        );
    }

    #[test]
    fn every_bundled_theme_is_readable() {
        let accents = [palette::PRIMARY, rgb(0x0078d7), rgb(0xfff3a0)];
        let sidebars = [
            (SidebarBackground::FollowTheme, palette::PANEL),
            (SidebarBackground::MatchTerminal, palette::PANEL),
            (SidebarBackground::Custom, rgb(0xffffff)),
            (SidebarBackground::Custom, rgb(0x000000)),
        ];
        assert_eq!(bundled().len(), 464);
        let mut failures = Vec::new();
        for (name, text) in bundled() {
            let theme = parse(name, text);
            for accent in accents {
                for (sidebar, color) in sidebars {
                    let c = chrome(&theme, accent, sidebar, color);
                    for (pair, fg, bg, min) in readable_pairs(&c) {
                        let ratio = contrast(fg, bg);
                        if ratio < min {
                            failures.push(format!(
                                "{name}: {pair}: {} on {} is {ratio:.2}:1, needs {min}:1 \
                                 (accent {}, sidebar {sidebar:?} {})",
                                fg.hex(),
                                bg.hex(),
                                accent.hex(),
                                color.hex()
                            ));
                        }
                    }
                }
            }
        }
        assert!(
            failures.is_empty(),
            "{} unreadable pairs:\n{}",
            failures.len(),
            failures[..failures.len().min(40)].join("\n")
        );
    }

    #[test]
    fn contrast_is_the_wcag_ratio() {
        let (white, black) = (rgb(0xffffff), rgb(0x000000));
        assert!((contrast(white, black) - 21.0).abs() < 1e-4);
        assert!((contrast(black, white) - 21.0).abs() < 1e-4);
        assert_eq!(contrast(palette::BG, palette::BG), 1.0);
        // #777777 on white is the classic just-below-AA grey: 4.48:1.
        assert!((contrast(rgb(0x777777), white) - 4.48).abs() < 0.01);
    }

    #[test]
    fn contrast_search_terminates_on_equal_colours() {
        // Dark: the colour moves towards white until it reads.
        let dark = rgb(0x0b0716);
        let up = ensure_contrast(dark, dark, 4.5);
        assert!(contrast(up, dark) >= 4.5);
        assert!(luminance(up) > luminance(dark));
        // Light: towards black.
        let light = rgb(0xffffff);
        let down = ensure_contrast(light, light, 4.5);
        assert!(contrast(down, light) >= 4.5);
        assert!(luminance(down) < luminance(light));
        // A ratio no colour reaches gives the end that contrasts more.
        assert_eq!(ensure_contrast(light, light, 22.0), rgb(0x000000));
        assert_eq!(ensure_contrast(dark, dark, 22.0), rgb(0xffffff));
        let grey = rgb(0x777777);
        assert_eq!(ensure_contrast(grey, grey, 7.0), rgb(0x000000));
        assert_eq!(ensure_contrast(grey, grey, f32::NAN), rgb(0x000000));
        // A colour that already reads is kept.
        assert_eq!(ensure_contrast(palette::TEXT, dark, 4.5), palette::TEXT);
        // A theme whose foreground equals its background still reads, dark and light.
        for hex in [0x1e1e1e, 0xfafafa] {
            let c = chrome(
                &theme(hex, hex),
                palette::PRIMARY,
                SidebarBackground::FollowTheme,
                palette::PANEL,
            );
            for (pair, fg, bg, min) in readable_pairs(&c) {
                assert!(contrast(fg, bg) >= min, "{hex:06x}: {pair}");
            }
            assert_ne!(c.border, c.bg, "{hex:06x}: the surfaces still step");
        }
    }

    #[test]
    fn sidebar_follows_the_macs_rule() {
        let follow = |t: &TermTheme| {
            chrome(
                t,
                palette::PRIMARY,
                SidebarBackground::FollowTheme,
                rgb(0x123456),
            )
            .sidebar_bg
        };
        assert_eq!(follow(&shellx()), palette::PANEL);
        // Dracula #282a36 + 2% white: 40 * 0.98 + 5.1 = 44.3, 46.26, 58.02.
        let dracula = named("Dracula");
        assert_eq!(dracula.background, rgb(0x282a36));
        assert_eq!(follow(&dracula), rgb(0x2c2e3a));
        // Catppuccin Latte #eff1f5 + 3% black: 239 * 0.97 = 231.83, 233.77, 237.65.
        let latte = named("Catppuccin Latte");
        assert_eq!(latte.background, rgb(0xeff1f5));
        assert_eq!(follow(&latte), rgb(0xe8eaee));
        let with = |sidebar, color| chrome(&dracula, palette::PRIMARY, sidebar, color);
        assert_eq!(
            with(SidebarBackground::MatchTerminal, rgb(0x123456)).sidebar_bg,
            rgb(0x282a36)
        );
        let custom = with(SidebarBackground::Custom, rgb(0x123456));
        assert_eq!(custom.sidebar_bg, rgb(0x123456));
        // The sidebar's text follows its own background: a white sidebar on a dark theme
        // takes the Mac's label strengths in black, 85% and 50%.
        let white = with(SidebarBackground::Custom, rgb(0xffffff));
        assert_eq!(white.sidebar_text, rgb(0x262626));
        assert_eq!(white.sidebar_muted, rgb(0x808080));
        // A sidebar on the theme's side keeps the theme's text.
        let followed = with(SidebarBackground::FollowTheme, rgb(0x123456));
        assert_eq!(followed.sidebar_text, followed.text_hi);
        assert_eq!(followed.sidebar_muted, followed.muted);
    }

    #[test]
    fn text_on_the_sidebar_reads_on_the_sidebar() {
        let dracula = named("Dracula");
        // A white sidebar on a dark theme: the window's own colours do not read on it (the
        // selected title was 1.11:1), the sidebar's do.
        let white = chrome(
            &dracula,
            palette::PRIMARY,
            SidebarBackground::Custom,
            rgb(0xffffff),
        );
        assert!(contrast(white.selection_title, white.session_selected) < 4.5);
        assert!(contrast(white.primary_text, white.sidebar_bg) < 4.5);
        assert!(contrast(white.sidebar_selection_title, white.session_selected) >= 4.5);
        assert!(contrast(white.sidebar_primary_text, white.sidebar_bg) >= 4.5);
        assert!(contrast(white.sidebar_icon_hover, white.sidebar_bg) >= 4.5);
        // A sidebar on the theme's own side keeps the window's colours.
        let follow = chrome(
            &dracula,
            palette::PRIMARY,
            SidebarBackground::FollowTheme,
            palette::PANEL,
        );
        assert_eq!(follow.sidebar_selection_title, follow.selection_title);
        assert_eq!(follow.sidebar_primary_text, follow.primary_text);
        assert_eq!(follow.sidebar_icon_hover, follow.text);
    }

    #[test]
    fn the_panels_hover_does_not_follow_the_sidebar() {
        let dracula = named("Dracula");
        let with = |sidebar, color| chrome(&dracula, palette::PRIMARY, sidebar, color);
        let follow = with(SidebarBackground::FollowTheme, palette::PANEL);
        let white = with(SidebarBackground::Custom, rgb(0xffffff));
        assert_eq!(follow.panel_hover, white.panel_hover);
        assert_ne!(white.panel_hover, white.session_hover);
        // A small step from the panel towards the text: lighter than the panel on a dark theme,
        // still far from the text.
        assert!(luminance(follow.panel_hover) > luminance(follow.panel));
        assert!(contrast(follow.panel_hover, follow.panel) < 1.3);
        let latte = chrome(
            &named("Catppuccin Latte"),
            palette::PRIMARY,
            SidebarBackground::FollowTheme,
            palette::PANEL,
        );
        assert!(luminance(latte.panel_hover) < luminance(latte.panel));
    }

    #[test]
    fn a_custom_accent_colours_primary_only() {
        let orange = rgb(0xff8800);
        for theme in [shellx(), named("Dracula"), named("Catppuccin Latte")] {
            let blue = chrome(
                &theme,
                palette::PRIMARY,
                SidebarBackground::FollowTheme,
                palette::PANEL,
            );
            let custom = chrome(
                &theme,
                orange,
                SidebarBackground::FollowTheme,
                palette::PANEL,
            );
            assert_eq!(custom.primary, orange);
            assert_eq!(custom.primary_soft, orange.with_alpha(0.12));
            assert_eq!(custom.primary_line, orange.with_alpha(0.45));
            assert_ne!(custom.primary_text, blue.primary_text, "{}", theme.name);
            assert!(contrast(custom.primary_text, custom.bg) >= 4.5);
            assert_eq!(
                (custom.running, custom.done, custom.error),
                (palette::RUNNING, palette::DONE, palette::ERROR)
            );
            assert_eq!(custom.field_selection, orange.with_alpha(0.3));
            assert_ne!(
                custom.sidebar_primary_text, blue.sidebar_primary_text,
                "{}",
                theme.name
            );
            assert!(contrast(custom.sidebar_primary_text, custom.sidebar_bg) >= 4.5);
            assert_eq!(
                Chrome {
                    primary: blue.primary,
                    primary_soft: blue.primary_soft,
                    primary_line: blue.primary_line,
                    primary_text: blue.primary_text,
                    field_selection: blue.field_selection,
                    sidebar_primary_text: blue.sidebar_primary_text,
                    ..custom
                },
                blue,
                "{}: only the primary fields change",
                theme.name
            );
        }
    }

    #[test]
    fn the_accent_setting_gives_a_colour() {
        let system = rgb(0x0078d7);
        assert_eq!(
            accent_color(&Accent::ShellxBlue, Some(system)),
            palette::PRIMARY
        );
        assert_eq!(accent_color(&Accent::System, Some(system)), system);
        assert_eq!(accent_color(&Accent::System, None), palette::PRIMARY);
        assert_eq!(
            accent_color(&Accent::Custom(rgb(0xff8800)), Some(system)),
            rgb(0xff8800)
        );
    }

    #[test]
    fn the_dwm_value_is_abgr() {
        assert_eq!(accent_from_dwm(0xff_d7_78_00), Rgba::rgb(0x0078d7));
        // The alpha byte is ignored.
        assert_eq!(accent_from_dwm(0x00_33_22_11), Rgba::rgb(0x112233));
    }

    #[test]
    fn a_custom_sidebar_keeps_its_borders_visible() {
        let mut failures = Vec::new();
        let colours = [rgb(0xffffff), rgb(0x000000), rgb(0x203040), rgb(0x100b1d)];
        for (name, text) in bundled() {
            let theme = parse(name, text);
            for custom in colours {
                let c = chrome(&theme, palette::PRIMARY, SidebarBackground::Custom, custom);
                for (what, border) in [("line", c.sidebar_line), ("border", c.sidebar_border)] {
                    let ratio = contrast(border, c.sidebar_bg);
                    if ratio < 1.5 {
                        failures.push(format!("{name} {custom:?} {what} {ratio:.2}"));
                    }
                }
            }
        }
        assert!(failures.is_empty(), "{failures:#?}");
    }

    #[test]
    fn a_sidebar_that_follows_the_theme_keeps_the_windows_borders() {
        for sidebar in [
            SidebarBackground::FollowTheme,
            SidebarBackground::MatchTerminal,
        ] {
            let c = chrome(&named("Dracula"), palette::PRIMARY, sidebar, rgb(0xffffff));
            assert_eq!((c.sidebar_line, c.sidebar_border), (c.line, c.border));
        }
    }
}
