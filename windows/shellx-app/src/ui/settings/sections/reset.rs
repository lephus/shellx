//! Settings › Reset: one centred "Reset All Settings" button, no confirmation (spec §5.4).
//! It puts every setting back to its default and the shell choice back to Automatic, and
//! closes what Settings had open. Sign-in, `links.json`, `render.json` and `ui-state.json`
//! stay as they are. Theme, terminals, sidebar, keymap and language follow at once, through
//! the settings service.

use gpui::{Context, Div, div, prelude::*, px};
use shellx_model::settings_catalog::{Section, row, section_title};
use shellx_model::strings::{Str, t};

use super::super::{SettingsView, stack};
use crate::ui::app::Services;
use crate::ui::button::{Kind, button};
use crate::ui::controls::{card, section_header};
use crate::ui::settings_service::SettingsService;

pub fn render(view: &mut SettingsView, cx: &mut Context<SettingsView>) -> Div {
    let lang = cx.global::<Services>().lang;
    let line = row("resetAll").filter(|row| row.wired).map(|row| {
        let reset = button(
            "settings-reset-all",
            t(lang, Str::SettingsResetAllSettings),
            Kind::Secondary,
            false,
        )
        .on_click(cx.listener(|view, _, _, cx| reset_all(view, cx)));
        let line = div()
            .flex()
            .flex_row()
            .justify_center()
            .px(px(14.0))
            .py(px(12.0))
            .child(reset);
        view.anchored(row.id, line)
    });
    stack()
        .child(section_header(
            t(lang, section_title(Section::Reset)).into(),
        ))
        .child(card().children(line))
}

/// Every setting back to its default, now. An open banner or edit line goes with it.
fn reset_all(view: &mut SettingsView, cx: &mut Context<SettingsView>) {
    SettingsService::entity(cx).update(cx, |service, cx| service.reset_all(cx));
    super::terminal_cards::reset_shell(view, cx);
    view.shortcuts.update(cx, |list, cx| list.close_notice(cx));
    cx.notify();
}
