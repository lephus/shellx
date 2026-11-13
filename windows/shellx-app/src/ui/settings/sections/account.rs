//! Settings › Account (moved from the 1.7.1 panel unchanged): who is signed in, "Đăng nhập…"
//! (the main window opens the sign-in dialog), the switch to Google, the sign-in methods, the
//! link to delete the account, and sign-out.

use gpui::{ClickEvent, Context, Div, FontWeight, SharedString, div, prelude::*, px};
use shellx_model::account::{AccountState, DELETE_ACCOUNT_URL};
use shellx_model::core_api::GooglePurpose;
use shellx_model::strings::{Lang, Str, added_from, sign_in_method_label, t};

use super::super::{SettingsView, SettingsViewEvent, card_body, muted, stack};
use crate::ui::app::Services;
use crate::ui::button::{Kind, button};
use crate::ui::controls::{card, section_header};
use crate::ui::theme;
use crate::ui::update_banner::open_https;

pub fn render(view: &mut SettingsView, cx: &mut Context<SettingsView>) -> Div {
    let lang = cx.global::<Services>().lang;
    stack()
        .child(section_header(t(lang, Str::Account).into()))
        .child({
            let card = card().child(body(view, lang, cx));
            view.anchored("account", card)
        })
}

/// Settings was opened: the sign-in methods are asked for again.
pub fn opened(view: &mut SettingsView, cx: &mut Context<SettingsView>) {
    if matches!(view.account.read(cx).state(), AccountState::LoggedIn { .. }) {
        view.account
            .update(cx, |a, cx| a.refresh_sign_in_methods(cx));
    }
}

fn body(view: &SettingsView, lang: Lang, cx: &mut Context<SettingsView>) -> Div {
    let account = view.account.read(cx);
    // Everything below comes from the view (Ruling 33): no code and no text from the core is drawn.
    let account_view = account.view(lang);
    let signed_in = matches!(account.state(), AccountState::LoggedIn { .. });
    let who = if signed_in {
        account
            .email()
            .map_or_else(|| t(lang, Str::SignedIn).to_string(), str::to_string)
    } else {
        t(lang, Str::NotLoggedIn).to_string()
    };
    card_body()
        .child(div().text_color(theme::text_hi()).truncate().child(who))
        .when(!signed_in, |s| s.child(muted(t(lang, Str::SignInSubtitle))))
        .when(account_view.google_switch, |s| {
            s.child(
                div()
                    .flex()
                    .flex_col()
                    .gap(px(4.0))
                    .child(
                        div()
                            .text_color(theme::text_hi())
                            .child(t(lang, Str::SwitchToGoogle)),
                    )
                    .child(muted(t(lang, Str::SwitchToGoogleIntro)))
                    .child(
                        div().flex().child(
                            button(
                                "settings-switch-google",
                                t(lang, Str::SwitchEllipsis),
                                Kind::Primary,
                                false,
                            )
                            .on_click(cx.listener(
                                |_, _: &ClickEvent, _, cx| {
                                    cx.emit(SettingsViewEvent::OpenSignIn(GooglePurpose::Link));
                                },
                            )),
                        ),
                    ),
            )
        })
        .when(signed_in, |s| s.child(methods_block(view, lang, cx)))
        // A failed sign-out or methods list, else why the account is not working (offline at
        // start, a state-folder problem): the sidebar does not show these.
        .children(account_view.error.map(|m| {
            div()
                .text_size(theme::SMALL_SIZE)
                .text_color(theme::error_text())
                .child(m)
        }))
        .when(account_view.session_expired, |s| {
            s.child(muted(t(lang, Str::SessionExpired)))
        })
        .when_some(account_view.sign_in, |s, label| {
            s.child(div().flex().child(
                button("settings-sign-in", t(lang, label), Kind::Primary, false).on_click(
                    cx.listener(|_, _: &ClickEvent, _, cx| {
                        cx.emit(SettingsViewEvent::OpenSignIn(GooglePurpose::SignIn));
                    }),
                ),
            ))
        })
        .when(account_view.sign_out, |s| {
            s.child(
                div().flex().child(
                    button(
                        "settings-logout",
                        t(lang, Str::Logout),
                        Kind::Secondary,
                        false,
                    )
                    .on_click(cx.listener(
                        |this: &mut SettingsView, _: &ClickEvent, _, cx| {
                            this.account.update(cx, |a, cx| a.logout(cx));
                        },
                    )),
                ),
            )
        })
}

/// "Sign-in methods": one row per identity; an Apple ID can be removed; the link to delete the account.
fn methods_block(view: &SettingsView, lang: Lang, cx: &mut Context<SettingsView>) -> Div {
    let account = view.account.read(cx);
    let removing = account.removing_sign_in_method().map(str::to_string);
    let rows: Vec<Div> = account
        .sign_in_methods()
        .unwrap_or_default()
        .iter()
        .map(|m| {
            let hidden = m.email.is_empty() || m.is_private_email;
            let who = if m.is_apple() {
                if hidden {
                    t(lang, Str::HiddenEmail).to_string()
                } else {
                    m.email.clone()
                }
            } else {
                m.email.clone()
            };
            let kind = sign_in_method_label(&m.provider);
            let id = m.identity_id.clone();
            let busy = removing.as_deref() == Some(m.identity_id.as_str());
            div()
                .flex()
                .flex_row()
                .items_center()
                .justify_between()
                .gap(px(8.0))
                .child(
                    div()
                        .flex()
                        .flex_col()
                        .min_w_0()
                        .child(div().text_color(theme::text()).child(t(lang, kind)))
                        .child(muted(who))
                        .children(
                            m.linked_via_device_name
                                .as_deref()
                                .filter(|_| m.is_apple())
                                .map(|d| muted(added_from(lang, d))),
                        ),
                )
                .when(m.is_apple(), |row| {
                    row.child(
                        button(
                            SharedString::from(format!("settings-remove-{id}")),
                            t(lang, Str::RemoveMethod),
                            Kind::Secondary,
                            busy,
                        )
                        .when(!busy, |b| {
                            let id = id.clone();
                            b.on_click(cx.listener(
                                move |this: &mut SettingsView, _: &ClickEvent, _, cx| {
                                    this.account.update(cx, |a, cx| {
                                        a.remove_sign_in_method(id.clone(), cx)
                                    });
                                },
                            ))
                        }),
                    )
                })
        })
        .collect();
    div()
        .flex()
        .flex_col()
        .gap(px(6.0))
        .pt(px(6.0))
        .child(
            div()
                .text_size(theme::PILL_SIZE)
                .font_weight(FontWeight::SEMIBOLD)
                .text_color(theme::muted())
                .child(t(lang, Str::SignInMethods).to_uppercase()),
        )
        .children(rows)
        .child(
            div().flex().child(
                button(
                    "settings-delete-account",
                    t(lang, Str::DeleteAccount),
                    Kind::Secondary,
                    false,
                )
                .on_click(|_, _, cx| open_https(cx, DELETE_ACCOUNT_URL)),
            ),
        )
}
