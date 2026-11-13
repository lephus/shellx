//! Settings › Updates (moved from the 1.7.1 panel unchanged): this version, what the last
//! check found, Download when there is a newer one, and "Check for updates" (the main window
//! runs the check, as the help menu's "Check for Updates" does).

use gpui::{ClickEvent, Context, Div, div, prelude::*, px};
use shellx_model::strings::{Str, t, update_available};
use shellx_model::update::{UpdateStatus, download_url};

use super::super::{SettingsView, SettingsViewEvent, card_body, muted, stack};
use crate::ui::app::Services;
use crate::ui::button::{Kind, button};
use crate::ui::controls::{card, section_header};
use crate::ui::theme;
use crate::ui::update_banner::open_https;

pub fn render(view: &mut SettingsView, cx: &mut Context<SettingsView>) -> Div {
    let lang = cx.global::<Services>().lang;
    let account = view.account.read(cx);
    let status = account.update_status().clone();
    let checking = account.checking();
    let text = if checking {
        t(lang, Str::Checking).to_string()
    } else {
        match &status {
            UpdateStatus::UpToDate => t(lang, Str::UpToDate).to_string(),
            UpdateStatus::Available { version, .. } => update_available(lang, version),
            UpdateStatus::Required { .. } => t(lang, Str::UpdateRequired).to_string(),
            UpdateStatus::Unknown if account.checked() => t(lang, Str::CheckFailed).to_string(),
            UpdateStatus::Unknown => String::new(),
        }
    };
    let url = download_url(&status).map(str::to_string);
    let body = card_body()
        .child(div().text_color(theme::text()).child(format!(
            "{} {}",
            t(lang, Str::Version),
            shellx_model::VERSION
        )))
        .when(!text.is_empty(), |s| s.child(muted(text)))
        .child(
            div()
                .flex()
                .flex_row()
                .gap(px(8.0))
                .when_some(url, |row, url| {
                    row.child(
                        button(
                            "settings-download",
                            t(lang, Str::Download),
                            Kind::Primary,
                            false,
                        )
                        .on_click(move |_, _, cx| open_https(cx, &url)),
                    )
                })
                .child(
                    button(
                        "settings-check-update",
                        t(lang, Str::CheckUpdate),
                        Kind::Secondary,
                        checking,
                    )
                    .when(!checking, |b| {
                        b.on_click(cx.listener(|_, _: &ClickEvent, _, cx| {
                            cx.emit(SettingsViewEvent::CheckForUpdates);
                        }))
                    }),
                ),
        );
    stack()
        .child(section_header(t(lang, Str::Updates).into()))
        .child(view.anchored("updates", card().child(body)))
}
