//! Settings › Themes (inventory §1 and §A): card 1 has Appearance (three thumbnails) and Accent
//! Color (a picker, and a colour well for Custom); card 2 has the Terminal Theme row (the pair,
//! and "Revert" while a pick made since the section opened can be undone) and the gallery:
//! a search field, then "Dark Themes" and "Light Themes" (the side in use first) as a grid of
//! cards that each preview a theme. A click on a card sets that side of the pair.
//!
//! The section's state is the `ThemeGallery` entity. It parses every theme once, when it is
//! made and when the user's themes are read again (`user_themes::read`, on a background
//! thread, each time the section opens), and keeps the two lists; a search only filters them.
//! The 464 cards are not all built: the grid has a fixed height computed from its rows, and
//! only the rows that meet the pane's viewport (plus one row either side) are drawn, placed
//! under a spacer. (`uniform_list` cannot hold the headings and the column count that follows
//! the width, so the same idea is done by hand over the pane's own scroll.)
//!
//! Keys: the search field is a `TextField` and takes its text. The grid is one tab stop: Left,
//! Right, Up and Down move a ring, Space or Enter picks the card under it. Nothing else is
//! stopped, and only while the grid has the keyboard.

use std::cell::Cell;
use std::rc::Rc;

use gpui::{
    ClickEvent, Context, Div, Entity, FocusHandle, FontWeight, KeyDownEvent, Render, ScrollHandle,
    SharedString, Stateful, Subscription, Window, canvas, div, point, prelude::*, px,
};
use shellx_model::controls::{activates, grid_key, moved_highlight};
use shellx_model::palette::Rgba;
use shellx_model::settings::{Accent, Key, accent_value, choice_value, theme_value};
use shellx_model::settings_catalog::{Row, Section, row, section_title};
use shellx_model::settings_search::fold;
use shellx_model::strings::{Lang, Str, t, theme_pair_summary};
use shellx_model::theme_file::{TermTheme, gallery_grid, is_dark, matching, shellx, sides_first};

use super::super::{SettingsView, stack};
use crate::fonts;
use crate::ui::app::Services;
use crate::ui::button::{Kind, button};
use crate::ui::controls::{
    ColorEvent, ColorWell, Picker, PickerEvent, card, key_in, row as card_row, section_header,
};
use crate::ui::settings_service::{SettingsService, current};
use crate::ui::text_field::TextField;
use crate::ui::theme;
use crate::user_themes;

/// A card's height; the space between cards and between rows of cards.
const CARD_H: f32 = 54.0;
const GAP: f32 = 10.0;
const ROW_H: f32 = CARD_H + GAP;
/// A heading ("Dark Themes") and the space under it.
const HEAD_H: f32 = 28.0;
/// The gallery's padding inside its card.
const GALLERY_PAD: f32 = 14.0;
/// Before the grid has been painted its width is not known.
const FIRST_WIDTH: f32 = 540.0;

/// One side of the pair: its themes, parsed once, and the ones a search leaves.
#[derive(Default)]
struct Side {
    themes: Vec<TermTheme>,
    folded: Vec<String>,
    /// Indices into `themes`.
    shown: Vec<usize>,
}

impl Side {
    fn new(themes: Vec<TermTheme>) -> Side {
        let folded = themes.iter().map(|theme| fold(&theme.name)).collect();
        let shown = (0..themes.len()).collect();
        Side {
            themes,
            folded,
            shown,
        }
    }
}

/// What the grid draws, top to bottom: a heading, or a row of cards.
#[derive(Clone, Copy)]
enum Item {
    Heading(bool),
    /// The cards `first..first + columns` of a side's shown list.
    Cards {
        dark: bool,
        first: usize,
    },
}

pub struct ThemeGallery {
    focus: FocusHandle,
    search: Entity<TextField>,
    accent_picker: Entity<Picker>,
    accent_well: Entity<ColorWell>,
    /// The search text at its last change.
    text: String,
    /// The pair (light, dark) when the section last opened: what "Revert" puts back.
    revert: (String, String),
    /// Dark, then light.
    sides: [Side; 2],
    /// The ring of the keyboard, counted over the cards shown in the order they are drawn.
    cursor: usize,
    /// The columns of the last frame (the arrows move a row by it).
    columns: usize,
    /// The grid's width, from the pane's width at its last paint (0 until then).
    width: Option<f32>,
    /// The grid's top edge (window coordinates) at its last paint. A change shows at the next
    /// draw: the rows built are a row wider than the viewport either side.
    top: Rc<Cell<f32>>,
    /// The pane's scroll, to keep the ring in view.
    scroll: ScrollHandle,
    /// The dark and light backgrounds the thumbnails of Appearance preview.
    preview: (Rgba, Rgba),
    _subscriptions: Vec<Subscription>,
}

pub fn new(
    scroll: ScrollHandle,
    cx: &mut Context<SettingsView>,
) -> (Entity<ThemeGallery>, Vec<Subscription>) {
    let gallery = cx.new(|cx| ThemeGallery::new(scroll, cx));
    let search = gallery.read(cx).search.clone();
    let subscription = cx.subscribe(&search, |view, _, event, cx| view.field_event(*event, cx));
    (gallery, vec![subscription])
}

/// The section was shown (Settings opened on it, or another section was left for it): the
/// pair to revert to is the one now, and the user's themes are read again.
pub fn opened(view: &mut SettingsView, cx: &mut Context<SettingsView>) {
    view.themes.update(cx, |gallery, cx| gallery.opened(cx));
}

pub fn render(view: &mut SettingsView, cx: &mut Context<SettingsView>) -> Div {
    let lang = cx.global::<Services>().lang;
    let wired = |id: &str| row(id).filter(|row| row.wired);
    let gallery = view.themes.clone();
    // The pane's width at its last paint, less its padding, the card's borders and the
    // gallery's padding.
    let pane = f32::from(view.detail_scroll.bounds().size.width);
    let width = (pane - 2.0 * super::super::PANE_PADDING - 2.0 - 2.0 * GALLERY_PAD)
        .max(0.0)
        .round();
    // Before the first paint the width is not known; a change draws the section again.
    // (The gallery is drawn after this, in the same frame, so it is not notified: a notify
    // during the parent's draw leaves its search field without its placeholder.)
    if gallery.update(cx, |gallery, _| {
        let changed = gallery.width != Some(width);
        gallery.width = Some(width);
        changed
    }) {
        view.redraw = true;
    }
    let appearance = wired("app.appearance").map(|row| {
        let line = appearance_row(row, &gallery, lang, cx);
        view.anchored(row.id, line)
    });
    let accent = wired("app.accentColor").map(|row| {
        let line = accent_row(row, &gallery, lang, cx);
        view.anchored(row.id, line)
    });
    let pair = wired("terminalTheme").map(|row| {
        let line = pair_row(row, &gallery, lang, cx);
        view.anchored(row.id, line)
    });
    let grid = wired("themeGallery").map(|row| {
        let body = div().child(gallery.clone());
        view.anchored(row.id, body)
    });
    let first = appearance.is_some() || accent.is_some();
    let second = pair.is_some() || grid.is_some();
    stack()
        .child(section_header(
            t(lang, section_title(Section::Themes)).into(),
        ))
        .when(first, |s| {
            s.child(card().children(appearance).children(accent))
        })
        .when(second, |s| s.child(card().children(pair).children(grid)))
}

fn appearance_row(
    row: &Row,
    gallery: &Entity<ThemeGallery>,
    lang: Lang,
    cx: &mut Context<SettingsView>,
) -> Div {
    let chosen = current(cx).choice(Key::Appearance).unwrap_or("dark");
    let (dark, light) = gallery.read(cx).preview;
    let options = [
        (Str::SettingsSystem, "system"),
        (Str::SettingsLight, "light"),
        (Str::SettingsDark, "dark"),
    ];
    let thumbnails = options.into_iter().fold(
        div().flex().flex_row().gap(px(8.0)),
        |thumbnails, (label, value)| {
            let backgrounds = match value {
                "light" => [light, light],
                "dark" => [dark, dark],
                _ => [dark, light],
            };
            thumbnails.child(thumbnail(
                value,
                t(lang, label),
                backgrounds,
                value == chosen,
            ))
        },
    );
    card_row(
        t(lang, row.title).into(),
        row.subtitle.map(|s| t(lang, s).into()),
        thumbnails,
        false,
    )
}

/// An Appearance button: 76 by 50, the label 10 high; chosen = the accent at 12 % and a 2 px
/// accent border, corner 8.
fn thumbnail(
    value: &'static str,
    label: &'static str,
    backgrounds: [Rgba; 2],
    chosen: bool,
) -> Stateful<Div> {
    let set = |window: &mut Window, cx: &mut gpui::App| {
        let _ = window;
        if let Some(value) = choice_value(Key::Appearance, value) {
            SettingsService::entity(cx)
                .update(cx, |service, cx| service.set(Key::Appearance, value, cx));
        }
    };
    let [left, right] = backgrounds;
    div()
        .id(SharedString::from(format!("appearance-{value}")))
        .flex()
        .flex_col()
        .flex_none()
        .items_center()
        .justify_center()
        .gap(px(5.0))
        .w(px(76.0))
        .h(px(50.0))
        .rounded(px(8.0))
        .border_2()
        .border_color(if chosen {
            theme::primary()
        } else {
            theme::line()
        })
        .when(chosen, |button| button.bg(theme::primary_soft()))
        .cursor_pointer()
        .tab_index(0)
        .focus(|style| style.border_color(theme::primary_text()))
        .child(
            div()
                .flex()
                .flex_row()
                .overflow_hidden()
                .w(px(30.0))
                .h(px(16.0))
                .rounded(px(4.0))
                .border_1()
                .border_color(theme::border())
                .child(div().flex_1().bg(theme::hsla(left)))
                .child(div().flex_1().bg(theme::hsla(right))),
        )
        .child(
            div()
                .text_size(px(10.0))
                .text_color(if chosen {
                    theme::primary_text()
                } else {
                    theme::text()
                })
                .child(label),
        )
        .on_click(move |event: &ClickEvent, window, cx| {
            if matches!(event, ClickEvent::Mouse(_)) {
                set(window, cx);
            }
        })
        .on_key_down(move |event: &KeyDownEvent, window, cx| {
            if activates(&key_in(event)) {
                cx.stop_propagation();
                if !event.is_held {
                    set(window, cx);
                }
            }
        })
}

fn accent_row(
    row: &Row,
    gallery: &Entity<ThemeGallery>,
    lang: Lang,
    cx: &mut Context<SettingsView>,
) -> Div {
    let accent = current(cx).accent;
    let (picker, well) = {
        let gallery = gallery.read(cx);
        (gallery.accent_picker.clone(), gallery.accent_well.clone())
    };
    let choice = match accent {
        Accent::ShellxBlue => "cmux",
        Accent::System => "system",
        Accent::Custom(_) => "custom",
    };
    picker.update(cx, |picker, cx| picker.set_value(choice, cx));
    if let Accent::Custom(colour) = accent {
        well.update(cx, |well, cx| well.set_value(colour, cx));
    }
    let control = div()
        .flex()
        .flex_row()
        .items_center()
        .gap(px(8.0))
        .child(picker)
        .when(matches!(accent, Accent::Custom(_)), |control| {
            control.child(well)
        });
    card_row(
        t(lang, row.title).into(),
        row.subtitle.map(|s| t(lang, s).into()),
        control,
        false,
    )
}

/// The Terminal Theme row: the pair in the subtitle, "Revert" while it differs from the pair
/// the section opened with.
fn pair_row(
    row: &Row,
    gallery: &Entity<ThemeGallery>,
    lang: Lang,
    cx: &mut Context<SettingsView>,
) -> Div {
    let settings = current(cx);
    let (light, dark) = (settings.theme_light.clone(), settings.theme_dark.clone());
    let revert = gallery.read(cx).revert.clone();
    let changed = (light.as_str(), dark.as_str()) != (revert.0.as_str(), revert.1.as_str());
    let control = div().when(changed, |control| {
        control.child(
            button(
                "themes-revert",
                t(lang, Str::SettingsRevert),
                Kind::Secondary,
                false,
            )
            .on_click(move |_, _, cx| {
                let revert = revert.clone();
                SettingsService::entity(cx).update(cx, |service, cx| {
                    for (key, name) in [(Key::ThemeLight, &revert.0), (Key::ThemeDark, &revert.1)] {
                        if let Some(value) = theme_value(key, name) {
                            service.set(key, value, cx);
                        }
                    }
                });
            }),
        )
    });
    card_row(
        t(lang, row.title).into(),
        Some(theme_pair_summary(lang, &light, &dark).into()),
        control,
        false,
    )
}

impl ThemeGallery {
    fn new(scroll: ScrollHandle, cx: &mut Context<Self>) -> Self {
        let lang = cx.global::<Services>().lang;
        let search = cx
            .new(|cx| TextField::new(false, t(lang, Str::SettingsSearchAllThemes), cx).tab_stop());
        let options = [
            (Str::SettingsAccentShellxBlue, "cmux"),
            (Str::SettingsSystem, "system"),
            (Str::SettingsAccentCustom, "custom"),
        ]
        .into_iter()
        .map(|(label, value)| {
            (
                SharedString::from(t(lang, label)),
                SharedString::from(value),
            )
        })
        .collect();
        let accent_picker = cx.new(|cx| Picker::new(options, "cmux", cx));
        let accent_well = cx.new(|cx| ColorWell::new(theme::primary_rgba(), Vec::new(), cx));
        let subscriptions = vec![
            cx.observe(&search, |this, search, cx| this.search_changed(&search, cx)),
            cx.subscribe(&accent_picker, |_, _, event: &PickerEvent, cx| {
                let PickerEvent::Picked(choice) = event;
                let accent = match choice.as_ref() {
                    "system" => Accent::System,
                    "custom" => Accent::Custom(match current(cx).accent {
                        Accent::Custom(colour) => colour,
                        _ => theme::primary_rgba(),
                    }),
                    _ => Accent::ShellxBlue,
                };
                set_accent(accent, cx);
            }),
            cx.subscribe(&accent_well, |_, _, event: &ColorEvent, cx| {
                let ColorEvent::Picked(colour) = *event;
                set_accent(Accent::Custom(colour), cx);
            }),
            cx.observe(&SettingsService::entity(cx), |_, _, cx| cx.notify()),
        ];
        let settings = current(cx);
        let mut gallery = ThemeGallery {
            focus: cx.focus_handle().tab_stop(true),
            search,
            accent_picker,
            accent_well,
            text: String::new(),
            revert: (settings.theme_light.clone(), settings.theme_dark.clone()),
            sides: [Side::default(), Side::default()],
            cursor: 0,
            columns: 1,
            width: None,
            top: Rc::new(Cell::new(0.0)),
            scroll,
            preview: (theme::primary_rgba(), theme::primary_rgba()),
            _subscriptions: subscriptions,
        };
        gallery.load(cx);
        gallery
    }

    /// The pair now is the one to revert to, and the user's themes are read again (off the UI
    /// thread); when they are in, the lists are built again.
    fn opened(&mut self, cx: &mut Context<Self>) {
        let settings = current(cx);
        self.revert = (settings.theme_light.clone(), settings.theme_dark.clone());
        cx.spawn(async move |this, cx| {
            let user = cx
                .background_executor()
                .spawn(async { user_themes::read() })
                .await;
            this.update(cx, |gallery, cx| {
                SettingsService::entity(cx)
                    .update(cx, |service, cx| service.set_user_themes(user, cx));
                gallery.load(cx);
            })
            .ok();
        })
        .detach();
        cx.notify();
    }

    /// Parses every theme of the service's set once, into the two sides.
    fn load(&mut self, cx: &mut Context<Self>) {
        let set = SettingsService::entity(cx);
        let set = set.read(cx).themes();
        let (dark, light): (Vec<TermTheme>, Vec<TermTheme>) =
            set.themes().into_iter().partition(is_dark);
        let fallback = shellx().background;
        self.preview = (
            set.get("ShellX")
                .map_or(Rgba::rgb(0), |theme| theme.background),
            set.get("Catppuccin Latte")
                .map_or(fallback, |theme| theme.background),
        );
        self.sides = [Side::new(dark), Side::new(light)];
        self.filter();
        cx.notify();
    }

    fn filter(&mut self) {
        for side in &mut self.sides {
            side.shown = matching(&side.folded, &self.text);
        }
        let total = self.sides.iter().map(|side| side.shown.len()).sum();
        self.cursor = moved_highlight(self.cursor, 0, total);
    }

    fn search_changed(&mut self, search: &Entity<TextField>, cx: &mut Context<Self>) {
        let text = search.read(cx).text();
        if text == self.text {
            return;
        }
        self.text = text.to_string();
        self.filter();
        cx.notify();
    }

    /// Sets the side of the pair the card belongs to.
    fn pick(&mut self, dark: bool, theme_ix: usize, cx: &mut Context<Self>) {
        let key = if dark {
            Key::ThemeDark
        } else {
            Key::ThemeLight
        };
        let name = &self.sides[side_ix(dark)].themes[theme_ix].name;
        if let Some(value) = theme_value(key, name) {
            SettingsService::entity(cx).update(cx, |service, cx| service.set(key, value, cx));
        }
    }

    /// The grid, top to bottom, for `columns` columns and the sides in `order`.
    fn items(&self, columns: usize, order: [bool; 2]) -> Vec<(Item, f32, f32)> {
        let mut items = Vec::new();
        let mut y = 0.0;
        for dark in order {
            let count = self.sides[side_ix(dark)].shown.len();
            if count == 0 {
                continue;
            }
            items.push((Item::Heading(dark), y, HEAD_H));
            y += HEAD_H;
            for first in (0..count).step_by(columns) {
                items.push((Item::Cards { dark, first }, y, ROW_H));
                y += ROW_H;
            }
        }
        items
    }

    /// The card under the ring, counted over the shown cards in `order`: its side and its
    /// place in that side's shown list.
    fn at_cursor(&self, order: [bool; 2]) -> Option<(bool, usize)> {
        let mut left = self.cursor;
        for dark in order {
            let count = self.sides[side_ix(dark)].shown.len();
            if left < count {
                return Some((dark, left));
            }
            left -= count;
        }
        None
    }

    /// Scrolls the pane so that the row of the ringed card is in view.
    fn reveal(&self, order: [bool; 2]) {
        let Some((dark, place)) = self.at_cursor(order) else {
            return;
        };
        let items = self.items(self.columns, order);
        let Some((_, y, h)) = items.iter().find(|(item, ..)| {
            matches!(item, Item::Cards { dark: d, first }
                if *d == dark && (*first..*first + self.columns).contains(&place))
        }) else {
            return;
        };
        let viewport = self.scroll.bounds();
        let (top, bottom) = (
            f32::from(viewport.origin.y),
            f32::from(viewport.origin.y + viewport.size.height),
        );
        let (item_top, item_bottom) = (self.top.get() + y, self.top.get() + y + h);
        let offset = self.scroll.offset();
        let delta = if item_top < top {
            top - item_top
        } else if item_bottom > bottom {
            bottom - item_bottom
        } else {
            return;
        };
        self.scroll
            .set_offset(point(offset.x, offset.y + px(delta)));
    }

    fn on_key_down(&mut self, event: &KeyDownEvent, window: &mut Window, cx: &mut Context<Self>) {
        if !self.focus.is_focused(window) {
            return;
        }
        let key = key_in(event);
        let order = self.order(cx);
        if let Some(step) = grid_key(&key, self.columns) {
            cx.stop_propagation();
            let total = self.sides.iter().map(|side| side.shown.len()).sum();
            self.cursor = moved_highlight(self.cursor, step, total);
            self.reveal(order);
            cx.notify();
        } else if activates(&key) {
            cx.stop_propagation();
            if let (false, Some((dark, place))) = (event.is_held, self.at_cursor(order)) {
                let theme_ix = self.sides[side_ix(dark)].shown[place];
                self.pick(dark, theme_ix, cx);
            }
        }
    }

    /// The sides in the order they are drawn: the one in use first.
    fn order(&self, cx: &Context<Self>) -> [bool; 2] {
        sides_first(SettingsService::entity(cx).read(cx).is_dark_mode())
    }

    fn search_bar(&self) -> Div {
        div().flex_none().w(px(200.0)).child(self.search.clone())
    }

    fn heading(dark: bool, lang: Lang) -> Div {
        div()
            .h(px(HEAD_H))
            .flex()
            .items_center()
            .text_size(px(12.0))
            .font_weight(FontWeight::SEMIBOLD)
            .text_color(theme::muted())
            .child(t(
                lang,
                if dark {
                    Str::SettingsDarkThemes
                } else {
                    Str::SettingsLightThemes
                },
            ))
    }

    /// One card: the theme's own colours (background, name in the foreground, cursor block,
    /// two rows of eight ANSI swatches). `chosen` is the side's current theme; `ringed` is
    /// where the keyboard is.
    fn card(
        &self,
        theme: &TermTheme,
        id: usize,
        pick: (bool, usize),
        (chosen, ringed): (bool, bool),
        width: f32,
        cx: &mut Context<Self>,
    ) -> Stateful<Div> {
        let swatches = |range: std::ops::Range<usize>| {
            range.fold(div().flex().flex_row().flex_1().min_h_0(), |row, slot| {
                row.child(div().flex_1().bg(theme::hsla(theme.ansi[slot])))
            })
        };
        div()
            .id(("theme-card", id))
            .relative()
            .flex()
            .flex_col()
            .flex_none()
            .justify_between()
            .overflow_hidden()
            .w(px(width))
            .h(px(CARD_H))
            .p(px(6.0))
            .rounded(px(8.0))
            .border_2()
            .border_color(if ringed {
                theme::primary_text()
            } else if chosen {
                theme::primary()
            } else {
                theme::line()
            })
            .bg(theme::hsla(theme.background))
            .cursor_pointer()
            .child(
                div()
                    .flex()
                    .flex_row()
                    .items_center()
                    .gap(px(4.0))
                    .child(
                        div()
                            .min_w_0()
                            .truncate()
                            .font_family(fonts::TERMINAL_FAMILY)
                            .text_size(px(10.0))
                            .font_weight(FontWeight::MEDIUM)
                            .text_color(theme::hsla(theme.foreground))
                            .child(SharedString::from(theme.name.clone())),
                    )
                    .child(
                        div()
                            .flex_none()
                            .w(px(5.0))
                            .h(px(11.0))
                            .bg(theme::hsla(theme.cursor)),
                    ),
            )
            .child(
                div()
                    .flex()
                    .flex_col()
                    .flex_none()
                    .h(px(16.0))
                    .child(swatches(0..8))
                    .child(swatches(8..16)),
            )
            .when(chosen, |card| {
                card.child(
                    div()
                        .absolute()
                        .top_0()
                        .left_0()
                        .size_full()
                        .bg(theme::primary_soft()),
                )
            })
            .on_click(cx.listener(move |this, event: &ClickEvent, window, cx| {
                if matches!(event, ClickEvent::Mouse(_)) {
                    window.focus(&this.focus);
                    this.pick(pick.0, pick.1, cx);
                }
            }))
    }
}

fn side_ix(dark: bool) -> usize {
    if dark { 0 } else { 1 }
}

fn set_accent(accent: Accent, cx: &mut gpui::App) {
    SettingsService::entity(cx).update(cx, |service, cx| {
        service.set(Key::Accent, accent_value(accent), cx)
    });
}

impl Render for ThemeGallery {
    fn render(&mut self, window: &mut Window, cx: &mut Context<Self>) -> impl IntoElement {
        let lang = cx.global::<Services>().lang;
        let order = self.order(cx);
        let width = self.width.filter(|w| *w > 0.0).unwrap_or(FIRST_WIDTH);
        let (columns, card_width) = gallery_grid(width);
        self.columns = columns;
        let items = self.items(columns, order);
        let total = items.last().map_or(0.0, |(_, y, h)| y + h);

        // The rows that meet the pane's viewport, and one row more either side.
        let viewport = self.scroll.bounds();
        let (view_top, view_bottom) = if f32::from(viewport.size.height) > 0.0 {
            (
                f32::from(viewport.origin.y),
                f32::from(viewport.origin.y + viewport.size.height),
            )
        } else {
            (0.0, f32::from(window.viewport_size().height))
        };
        let top = self.top.get();
        let (low, high) = (view_top - top - ROW_H, view_bottom - top + ROW_H);
        let visible: Vec<&(Item, f32, f32)> = items
            .iter()
            .filter(|(_, y, h)| y + h >= low && *y <= high)
            .collect();
        let spacer = visible.first().map_or(0.0, |(_, y, _)| *y);

        let settings = current(cx);
        let pair = [
            settings.theme_dark.to_lowercase(),
            settings.theme_light.to_lowercase(),
        ];
        let ring = self.focus.is_focused(window);
        let ringed = self.at_cursor(order);
        let mut body = div().flex().flex_col().w_full().pt(px(spacer));
        for (item, ..) in visible {
            match *item {
                Item::Heading(dark) => body = body.child(Self::heading(dark, lang)),
                Item::Cards { dark, first } => {
                    let side = &self.sides[side_ix(dark)];
                    let before: usize = order
                        .iter()
                        .take_while(|d| **d != dark)
                        .map(|d| self.sides[side_ix(*d)].shown.len())
                        .sum();
                    let mut cards = div().flex().flex_row().gap(px(GAP)).h(px(ROW_H));
                    for place in first..(first + columns).min(side.shown.len()) {
                        let theme_ix = side.shown[place];
                        let theme = &side.themes[theme_ix];
                        let chosen = theme.name.to_lowercase() == pair[side_ix(!dark)];
                        let at = ring && ringed == Some((dark, place));
                        let id = before + place;
                        cards = cards.child(self.card(
                            theme,
                            id,
                            (dark, theme_ix),
                            (chosen, at),
                            card_width,
                            cx,
                        ));
                    }
                    body = body.child(cards);
                }
            }
        }

        let top_cell = self.top.clone();
        let measure = canvas(
            move |bounds, _, _| top_cell.set(f32::from(bounds.origin.y)),
            |_, _, _, _| {},
        )
        .absolute()
        .top_0()
        .left_0()
        .size_full();
        let grid = div()
            .id("theme-grid")
            .relative()
            .w_full()
            .h(px(total))
            .track_focus(&self.focus)
            .on_key_down(cx.listener(Self::on_key_down))
            .child(measure)
            .child(body);
        div()
            .flex()
            .flex_col()
            .w_full()
            .gap(px(8.0))
            .border_t_1()
            .border_color(theme::line())
            .p(px(GALLERY_PAD))
            .child(self.search_bar())
            .child(if items.is_empty() {
                div()
                    .text_size(px(12.0))
                    .text_color(theme::muted())
                    .child(t(lang, Str::SettingsNoThemesMatch))
            } else {
                div().child(grid)
            })
    }
}
