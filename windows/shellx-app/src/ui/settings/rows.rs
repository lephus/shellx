//! A catalogue row drawn with the control kit (`ui/controls/`): its title and subtitle in the
//! current language, its control showing the key's value, dimmed while its condition disables
//! it, absent while its condition hides it or until a task sets `wired: true`.
//!
//! A row reads its value with the typed getters of `shellx_model::settings` (`flag`, `number`,
//! `choice`, `colour`) and writes it through `SettingsService::set` with the matching
//! `*_value` function, never with JSON of its own: a key's stored form can differ from what
//! the row shows (Keep Workspace Open is inverted, the scrollback is in bytes).
//!
//! A control with state of its own (picker, slider, stepper, number field, colour well) is an
//! entity the view keeps per row, made the first time the row is drawn. Each draw sets its
//! value from the settings, so a change made elsewhere (Reset, another window) shows at once.

use gpui::{
    AnyElement, App, Context, Div, Entity, SharedString, Subscription, div, prelude::*, px,
};
use serde_json::Value;
use shellx_model::controls::{
    NumberEsc, digits, number_escape, number_pending, number_text, unit_suffix,
};
use shellx_model::palette::Rgba;
use shellx_model::settings::{Key, Settings, choice_value, colour_value, flag_value, number_value};
use shellx_model::settings_catalog::{Control, Row, Section, Unit, row, rows, section_title};
use shellx_model::strings::{Lang, Str, t};

use super::{SettingsView, stack};
use crate::ui::app::Services;
use crate::ui::button::{Kind, button};
use crate::ui::controls::{
    ColorEvent, ColorWell, Picker, PickerEvent, Slider, SliderEvent, Stepper, StepperEvent, card,
    row as card_row, section_header, segmented, toggle,
};
use crate::ui::settings_service::{SettingsService, current};
use crate::ui::text_field::{TextField, TextFieldEvent};
use crate::ui::theme;

/// The number field's width (Scrollback Limit's digits).
const NUMBER_W: f32 = 90.0;

/// A row's control that keeps state between draws.
pub(super) enum RowControl {
    Picker(Entity<Picker>),
    Slider(Entity<Slider>),
    Stepper(Entity<Stepper>),
    Number {
        field: Entity<TextField>,
        /// The field holds text the user typed that is not the stored value yet: a draw leaves
        /// it alone until it is committed (Enter, blur, close) or taken back (Esc).
        editing: bool,
    },
    Color(Entity<ColorWell>),
}

/// A row's control and the subscriptions that write its changes.
pub(super) struct RowEntry {
    control: RowControl,
    _subscriptions: Vec<Subscription>,
}

/// What a row shows of its key, read before any entity is touched.
struct Shown {
    visible: bool,
    enabled: bool,
    /// The key differs from its default (a Reset button shows).
    changed: bool,
    flag: Option<bool>,
    number: Option<f32>,
    choice: Option<&'static str>,
    colour: Option<Rgba>,
}

impl Shown {
    fn read(row: &Row, key: Key, s: &Settings) -> Shown {
        Shown {
            visible: (row.visible)(s),
            enabled: (row.enabled)(s),
            changed: s.to_value(key).is_some(),
            flag: s.flag(key),
            number: s.number(key),
            choice: s.choice(key),
            colour: s.colour(key),
        }
    }
}

/// The row's card line with its control, reading and writing the row's key through the service.
pub fn catalogue_row(
    row: &'static Row,
    view: &mut SettingsView,
    cx: &mut Context<SettingsView>,
) -> Option<Div> {
    if !row.wired {
        return None;
    }
    let key = row.key?;
    let shown = Shown::read(row, key, current(cx));
    if !shown.visible {
        return None;
    }
    let lang = cx.global::<Services>().lang;
    // `SHELLX_LANG` decides the language while it is set: the Language row can change nothing.
    let env_decides = key == Key::Language
        && Lang::env_decides(std::env::var("SHELLX_LANG").ok().as_deref());
    let disabled = !shown.enabled || env_decides;
    let control: AnyElement = match row.control {
        // Drawn by its section file.
        Control::Custom => return None,
        Control::Toggle => toggle(row.id, shown.flag?, disabled, move |on, _, cx| {
            write(key, flag_value(key, on), cx)
        })
        .into_any_element(),
        Control::Segmented(options) => {
            let labels: Vec<(SharedString, &'static str)> = options
                .iter()
                .map(|(label, value)| (t(lang, *label).into(), *value))
                .collect();
            segmented(
                row.id,
                &labels,
                shown.choice?,
                disabled,
                move |value, _, cx| write(key, choice_value(key, value), cx),
            )
            .into_any_element()
        }
        Control::Picker(options) => {
            let choice = shown.choice?;
            let picker = picker(row, key, options, choice, lang, view, cx);
            let labelled = picker_labels(options, lang);
            picker.update(cx, |picker, cx| {
                picker.set_labels(labelled, cx);
                picker.set_value(choice, cx);
                picker.set_disabled(disabled, cx);
            });
            picker.into_any_element()
        }
        Control::Slider {
            min,
            max,
            step,
            unit,
            reset,
        } => {
            let value = shown.number?;
            let slider = slider(row, key, (value, min, max, step, unit), view, cx);
            slider.update(cx, |slider, cx| {
                slider.set_value(value, cx);
                slider.set_disabled(disabled, cx);
            });
            div()
                .flex()
                .flex_row()
                .items_center()
                .gap(px(8.0))
                .child(slider)
                .when(reset && shown.changed, |control| {
                    control.child(reset_button(row, key, disabled, lang))
                })
                .into_any_element()
        }
        Control::Stepper { min, max, step } => {
            let value = shown.number?;
            let stepper = stepper(row, key, (value, min, max, step), view, cx);
            stepper.update(cx, |stepper, cx| {
                stepper.set_value(value, cx);
                stepper.set_disabled(disabled, cx);
            });
            stepper.into_any_element()
        }
        Control::Number { unit, .. } => {
            let value = shown.number?;
            let (field, editing) = number_field(row, view, cx);
            field.update(cx, |field, cx| {
                // The text being typed stays until it is committed.
                let text = number_text(value);
                if !editing && field.text() != text {
                    field.set_text(&text, cx);
                }
                field.set_disabled(disabled, cx);
            });
            number_control(field, unit).into_any_element()
        }
        Control::Color { resettable } => {
            let well = colour_well(row, key, shown.colour, view, cx);
            well.update(cx, |well, cx| {
                well.set_value(shown.colour.unwrap_or_else(theme::primary_rgba), cx);
                well.set_disabled(disabled, cx);
            });
            let label: SharedString = match shown.colour {
                Some(colour) => colour.hex().to_uppercase().into(),
                None => t(lang, Str::SettingsDefault).into(),
            };
            div()
                .flex()
                .flex_row()
                .items_center()
                .gap(px(8.0))
                .child(
                    div()
                        .text_size(px(12.0))
                        .text_color(theme::muted())
                        .child(label),
                )
                .child(well)
                .when(resettable && shown.changed, |control| {
                    control.child(reset_button(row, key, disabled, lang))
                })
                .into_any_element()
        }
    };
    let title = t(lang, row.title).into();
    let subtitle = row
        .subtitle
        .or(env_decides.then_some(Str::SettingsLanguageEnvOverride))
        .map(|s| SharedString::from(t(lang, s)));
    let line = view.anchored(row.id, card_row(title, subtitle, control, disabled));
    Some(div().child(line))
}

/// A card of the rows named by `ids` that are drawn; `None` when none is (not wired yet, or
/// hidden), so a section shows no empty card. A `Custom` row among them is left to its section
/// file.
pub(super) fn rows_card(
    ids: &[&'static str],
    view: &mut SettingsView,
    cx: &mut Context<SettingsView>,
) -> Option<Div> {
    let drawn: Vec<Div> = ids
        .iter()
        .filter_map(|id| row(id))
        .filter_map(|row| catalogue_row(row, view, cx))
        .collect();
    (!drawn.is_empty()).then(|| card().children(drawn))
}

/// A section without a file of its own: its title, and one card of its drawn rows.
pub(super) fn section_card(
    section: Section,
    view: &mut SettingsView,
    cx: &mut Context<SettingsView>,
) -> Div {
    let lang = cx.global::<Services>().lang;
    let ids: Vec<&'static str> = rows(section).map(|row| row.id).collect();
    stack()
        .child(section_header(t(lang, section_title(section)).into()))
        .children(rows_card(&ids, view, cx))
}

/// Writes a row's value; `None` (a value the key cannot take) changes nothing.
fn write(key: Key, value: Option<Value>, cx: &mut App) {
    if let Some(value) = value {
        SettingsService::entity(cx).update(cx, |service, cx| service.set(key, value, cx));
    }
}

fn reset_button(row: &Row, key: Key, disabled: bool, lang: Lang) -> impl IntoElement {
    button(
        SharedString::from(format!("{}-reset", row.id)),
        t(lang, Str::SettingsReset),
        Kind::Secondary,
        disabled,
    )
    .when(!disabled, |b| {
        b.on_click(move |_, _, cx| {
            SettingsService::entity(cx).update(cx, |service, cx| service.reset(key, cx));
        })
    })
}

fn picker(
    row: &'static Row,
    key: Key,
    options: &'static [(Str, &'static str)],
    choice: &'static str,
    lang: Lang,
    view: &mut SettingsView,
    cx: &mut Context<SettingsView>,
) -> Entity<Picker> {
    if let Some(RowEntry {
        control: RowControl::Picker(picker),
        ..
    }) = view.controls.get(row.id)
    {
        return picker.clone();
    }
    let picker = cx.new(|cx| Picker::new(picker_labels(options, lang), choice, cx));
    let subscription = cx.subscribe(&picker, move |_, _, event: &PickerEvent, cx| {
        let PickerEvent::Picked(value) = event;
        write(key, choice_value(key, value), cx);
    });
    keep(view, row, RowControl::Picker(picker.clone()), subscription);
    picker
}

/// The picker's (label, value) options in `lang`.
fn picker_labels(
    options: &'static [(Str, &'static str)],
    lang: Lang,
) -> Vec<(SharedString, SharedString)> {
    options
        .iter()
        .map(|(label, value)| (t(lang, *label).into(), SharedString::from(*value)))
        .collect()
}

fn slider(
    row: &'static Row,
    key: Key,
    (value, min, max, step, unit): (f32, f32, f32, f32, Unit),
    view: &mut SettingsView,
    cx: &mut Context<SettingsView>,
) -> Entity<Slider> {
    if let Some(RowEntry {
        control: RowControl::Slider(slider),
        ..
    }) = view.controls.get(row.id)
    {
        return slider.clone();
    }
    let slider = cx.new(|cx| Slider::new(value, min, max, step, unit, cx));
    let subscription = cx.subscribe(&slider, move |_, _, event: &SliderEvent, cx| {
        let SliderEvent::Changed(value) = *event;
        write(key, number_value(key, value), cx);
    });
    keep(view, row, RowControl::Slider(slider.clone()), subscription);
    slider
}

fn stepper(
    row: &'static Row,
    key: Key,
    (value, min, max, step): (f32, f32, f32, f32),
    view: &mut SettingsView,
    cx: &mut Context<SettingsView>,
) -> Entity<Stepper> {
    if let Some(RowEntry {
        control: RowControl::Stepper(stepper),
        ..
    }) = view.controls.get(row.id)
    {
        return stepper.clone();
    }
    // Every Mac stepper shows points ("13 pt").
    let stepper = cx.new(|cx| Stepper::new(value, min, max, step, Unit::Points, cx));
    let subscription = cx.subscribe(&stepper, move |_, _, event: &StepperEvent, cx| {
        let StepperEvent::Changed(value) = *event;
        write(key, number_value(key, value), cx);
    });
    keep(
        view,
        row,
        RowControl::Stepper(stepper.clone()),
        subscription,
    );
    stepper
}

/// The row's number field and whether it is being edited.
fn number_field(
    row: &'static Row,
    view: &mut SettingsView,
    cx: &mut Context<SettingsView>,
) -> (Entity<TextField>, bool) {
    if let Some(RowEntry {
        control: RowControl::Number { field, editing },
        ..
    }) = view.controls.get(row.id)
    {
        return (field.clone(), *editing);
    }
    let field = cx.new(|cx| TextField::new(false, "", cx).tab_stop());
    let id = row.id;
    let subscriptions = vec![
        // Only digits stay in the field.
        cx.observe(&field, move |view, field, cx| {
            let typed = field.read(cx);
            if typed.composing() {
                return;
            }
            let kept = digits(typed.text());
            if kept != typed.text() {
                field.update(cx, |field, cx| field.set_text(&kept, cx));
            }
            // Text that is not the stored value is an edit a draw must not overwrite.
            let stored = number_row(id, view, cx).map(|(_, stored, ..)| number_text(stored));
            let differs = stored.is_some_and(|stored| stored != kept);
            if let Some(RowEntry {
                control: RowControl::Number { editing, .. },
                ..
            }) = view.controls.get_mut(id)
            {
                *editing = differs;
            }
        }),
        cx.subscribe(
            &field,
            move |view, _, event: &TextFieldEvent, cx| match event {
                // Enter, or the keyboard leaving the field, commits it (clamped).
                TextFieldEvent::Submit | TextFieldEvent::Blur => commit_number(id, view, cx),
                // Esc takes an edit back; with none it is the window's.
                TextFieldEvent::Cancel if restore_number(id, view, cx) => {}
                _ => view.field_event(*event, cx),
            },
        ),
    ];
    view.controls.insert(
        row.id,
        RowEntry {
            control: RowControl::Number {
                field: field.clone(),
                editing: false,
            },
            _subscriptions: subscriptions,
        },
    );
    (field, false)
}

/// Stores the field's number (clamped to the row's range) and shows the stored value again;
/// a field without digits just shows the stored value again.
fn commit_number(id: &'static str, view: &mut SettingsView, cx: &mut Context<SettingsView>) {
    let Some(row) = row(id) else { return };
    let (Some(key), Control::Number { min, max, .. }) = (row.key, row.control) else {
        return;
    };
    let Some(RowEntry {
        control: RowControl::Number { field, .. },
        ..
    }) = view.controls.get(id)
    else {
        return;
    };
    let field = field.clone();
    // Only a value that differs from the stored one is written: a blur after Esc or after a
    // close-commit rewrites nothing.
    if let Some(stored) = current(cx).number(key)
        && let Some(value) = number_pending(field.read(cx).text(), stored, min, max)
    {
        write(key, number_value(key, value), cx);
    }
    let shown = current(cx).number(key).map(number_text).unwrap_or_default();
    field.update(cx, |field, cx| field.set_text(&shown, cx));
}

/// The stored value of a number row, as its field shows it, and its range.
fn number_row(
    id: &'static str,
    view: &SettingsView,
    cx: &App,
) -> Option<(Entity<TextField>, f32, f32, f32)> {
    let row = row(id)?;
    let (Some(key), Control::Number { min, max, .. }) = (row.key, row.control) else {
        return None;
    };
    let RowEntry {
        control: RowControl::Number { field, .. },
        ..
    } = view.controls.get(id)?
    else {
        return None;
    };
    Some((field.clone(), current(cx).number(key)?, min, max))
}

/// Esc in a number field with an edit in it: the stored value comes back. `false` when there
/// is no edit (Esc then closes Settings).
fn restore_number(
    id: &'static str,
    view: &mut SettingsView,
    cx: &mut Context<SettingsView>,
) -> bool {
    let Some((field, stored, ..)) = number_row(id, view, cx) else {
        return false;
    };
    if number_escape(field.read(cx).text(), stored) == NumberEsc::Close {
        return false;
    }
    field.update(cx, |field, cx| field.set_text(&number_text(stored), cx));
    true
}

/// Settings is closing: a number field holding an edit commits it (clamped).
pub(super) fn commit_pending_numbers(view: &mut SettingsView, cx: &mut Context<SettingsView>) {
    let ids: Vec<&'static str> = view
        .controls
        .iter()
        .filter(|(_, entry)| matches!(entry.control, RowControl::Number { .. }))
        .map(|(id, _)| *id)
        .collect();
    for id in ids {
        let Some((field, stored, min, max)) = number_row(id, view, cx) else {
            continue;
        };
        let key = row(id).and_then(|row| row.key);
        if let (Some(key), Some(value)) =
            (key, number_pending(field.read(cx).text(), stored, min, max))
        {
            write(key, number_value(key, value), cx);
        }
    }
}

fn number_control(field: Entity<TextField>, unit: Unit) -> Div {
    div()
        .flex()
        .flex_row()
        .items_center()
        .gap(px(6.0))
        .child(div().w(px(NUMBER_W)).child(field))
        .child(
            div()
                .text_size(px(12.0))
                .text_color(theme::muted())
                .child(unit_suffix(unit)),
        )
}

fn colour_well(
    row: &'static Row,
    key: Key,
    colour: Option<Rgba>,
    view: &mut SettingsView,
    cx: &mut Context<SettingsView>,
) -> Entity<ColorWell> {
    if let Some(RowEntry {
        control: RowControl::Color(well),
        ..
    }) = view.controls.get(row.id)
    {
        return well.clone();
    }
    // The kit holds no palette: the task that wires a colour row gives it swatches.
    let well =
        cx.new(|cx| ColorWell::new(colour.unwrap_or_else(theme::primary_rgba), Vec::new(), cx));
    let subscription = cx.subscribe(&well, move |_, _, event: &ColorEvent, cx| {
        let ColorEvent::Picked(colour) = *event;
        write(key, colour_value(key, colour), cx);
    });
    keep(view, row, RowControl::Color(well.clone()), subscription);
    well
}

fn keep(view: &mut SettingsView, row: &Row, control: RowControl, subscription: Subscription) {
    view.controls.insert(
        row.id,
        RowEntry {
            control,
            _subscriptions: vec![subscription],
        },
    );
}
