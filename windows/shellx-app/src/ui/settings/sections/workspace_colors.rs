//! Settings › Workspace Colors: the card of the indicator rows (style, subtle selection, brighten,
//! unselected opacity, selection highlight) from the catalogue, the note about the right-click
//! menu, then the palette: one row per colour with its hex code, a colour well and "Base: #HEX"
//! (the built-in colour) under the name, and Reset Palette. Editing a colour recolours every
//! workspace that uses it at once, Purple included (it is every workspace without a colour of
//! its own).

use gpui::{Context, Div, SharedString, div, prelude::*, px};
use shellx_model::settings::Key;
use shellx_model::settings_catalog::{Section, row, rows, section_title};
use shellx_model::strings::{Str, palette_base, t};
use shellx_model::workspace_colors::{BUILT_IN, palette};

use super::super::rows::{palette_well, rows_card};
use super::super::{SettingsView, muted, stack};
use crate::ui::app::Services;
use crate::ui::button::{Kind, button};
use crate::ui::controls::{card, row as card_row, section_header};
use crate::ui::settings_service::{SettingsService, current};
use crate::ui::theme;

pub fn render(view: &mut SettingsView, cx: &mut Context<SettingsView>) -> Div {
    let lang = cx.global::<Services>().lang;
    // The catalogue rows that are settings of their own; the palette rows and Reset Palette are
    // drawn below.
    let ids: Vec<&'static str> = rows(Section::WorkspaceColors)
        .filter(|row| row.key.is_some_and(|key| key != Key::Palette))
        .map(|row| row.id)
        .collect();
    let mut palette_card = card();
    let settings = current(cx).clone();
    for (entry, (name, base)) in palette(&settings).into_iter().zip(BUILT_IN) {
        let Some(palette_row) = row(&format!("palette{name}")).filter(|row| row.wired) else {
            continue;
        };
        let well = palette_well(palette_row, name, entry.color, view, cx);
        well.update(cx, |well, cx| well.set_value(entry.color, cx));
        let control = div()
            .flex()
            .flex_row()
            .items_center()
            .gap(px(8.0))
            .child(
                div()
                    .text_size(px(12.0))
                    .text_color(theme::muted())
                    .child(SharedString::from(entry.color.hex().to_uppercase())),
            )
            .child(well);
        let base = format!("#{base:06X}");
        palette_card = palette_card.child(view.anchored(
            palette_row.id,
            card_row(
                t(lang, palette_row.title).into(),
                Some(palette_base(lang, &base).into()),
                control,
                false,
            ),
        ));
    }
    let edited = !settings.palette.is_empty();
    if let Some(reset) = row("resetPalette").filter(|row| row.wired) {
        let button = button(
            "reset-palette",
            t(lang, Str::SettingsReset),
            Kind::Secondary,
            !edited,
        )
        .when(edited, |b| {
            b.on_click(|_, _, cx| {
                SettingsService::entity(cx)
                    .update(cx, |service, cx| service.reset(Key::Palette, cx));
            })
        });
        palette_card = palette_card.child(view.anchored(
            reset.id,
            card_row(
                t(lang, reset.title).into(),
                reset.subtitle.map(|s| t(lang, s).into()),
                button,
                false,
            ),
        ));
    }
    stack()
        .child(section_header(
            t(lang, section_title(Section::WorkspaceColors)).into(),
        ))
        .children(rows_card(&ids, view, cx))
        .child(muted(t(lang, Str::SettingsPaletteNote)))
        .child(palette_card)
}
