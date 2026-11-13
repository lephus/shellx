//! Settings › Keyboard Shortcuts (spec §5.4, inventory §3 and §B): one card with Reset Default
//! Shortcuts, the search bar ("Search shortcuts", "Detect Shortcut", a clear button) and a row
//! per action with its recorder and X, then the footer note under the card.
//!
//! The search text filters the rows by their title in either language; "Detect Shortcut"
//! filters them by the next chord pressed (`keymap::listed`). A recorded chord is checked
//! before it is stored (`keymap::rebound`): one another action holds is not saved, and a red
//! banner under the row names that action, with "Undo" to close it; one `accept` refuses is not
//! saved either, and the banner says why. A row bound to Ctrl plus a letter says the key no
//! longer reaches the shell. Bindings are written as the whole `shortcuts.bindings` map
//! through `SettingsService`, whose keymap every window reads, so a change applies at once.
//!
//! The list's state is the `ShortcutList` entity; the view only places it in the card.

use std::collections::BTreeMap;

use gpui::{
    ClickEvent, Context, Div, Entity, KeyDownEvent, SharedString, Subscription, Window, div,
    prelude::*, px, transparent_black,
};
use serde_json::Value;
use shellx_model::controls::activates;
use shellx_model::keymap::{
    Action, Chord, ClearButton, Keymap, ListFilter, Refused, clear_button, conflict, listed,
    rebound, refusal, takes_from_the_shell,
};
use shellx_model::settings::Key;
use shellx_model::settings_catalog::{Row, Section, row, section_title};
use shellx_model::strings::{Lang, Str, t};

use super::super::{SettingsView, stack};
use crate::ui::app::Services;
use crate::ui::button::{Kind, button};
use crate::ui::controls::{Recorder, RecorderEvent, card, key_in, row as card_row, section_header};
use crate::ui::settings_service::{SettingsService, current_keymap};
use crate::ui::text_field::TextField;
use crate::ui::theme;

/// Why a row's chord was not saved, shown under it.
#[derive(Clone, Copy, Debug)]
enum Notice {
    Refused(Refused),
    /// Another action holds the chord.
    Taken(Action),
}

/// The search bar and the action rows.
pub struct ShortcutList {
    search: Entity<TextField>,
    detector: Entity<Recorder>,
    /// The search text at its last change (typing clears a detected chord).
    text: String,
    /// The chord "Detect Shortcut" heard: the list shows the actions bound to it.
    detected: Option<Chord>,
    /// One recorder per action, in list order.
    recorders: Vec<(Action, Entity<Recorder>)>,
    /// The banner under one row.
    notice: Option<(Action, Notice)>,
    _subscriptions: Vec<Subscription>,
}

/// The list, and the subscription that gives its search field's Esc and Tab to the view.
pub fn new(cx: &mut Context<SettingsView>) -> (Entity<ShortcutList>, Vec<Subscription>) {
    let list = cx.new(ShortcutList::new);
    let search = list.read(cx).search.clone();
    let subscription = cx.subscribe(&search, |view, _, event, cx| view.field_event(*event, cx));
    (list, vec![subscription])
}

pub fn render(view: &mut SettingsView, cx: &mut Context<SettingsView>) -> Div {
    let lang = cx.global::<Services>().lang;
    let wired = |id: &str| row(id).filter(|row| row.wired);
    let reset = wired("resetShortcuts").map(|row| {
        let line = reset_row(row, view.shortcuts.clone(), lang);
        view.anchored(row.id, line)
    });
    let list = wired("shortcutList").map(|row| {
        let list = div().child(view.shortcuts.clone());
        view.anchored(row.id, list)
    });
    let footer = list.is_some().then(|| {
        div()
            .pl(px(2.0))
            .text_size(px(10.0))
            .text_color(theme::muted())
            .child(t(lang, Str::SettingsShortcutsFooter))
    });
    stack()
        .child(section_header(
            t(lang, section_title(Section::KeyboardShortcuts)).into(),
        ))
        .child(card().children(reset).children(list))
        .children(footer)
}

/// Reset Default Shortcuts: `shortcuts.bindings` goes, every action has its default again.
fn reset_row(row: &Row, list: Entity<ShortcutList>, lang: Lang) -> Div {
    let reset = button(
        "shortcuts-reset-defaults",
        t(lang, Str::SettingsResetDefaults),
        Kind::Secondary,
        false,
    )
    .on_click(move |_, _, cx| {
        SettingsService::entity(cx).update(cx, |service, cx| service.reset(Key::Bindings, cx));
        list.update(cx, |list, cx| list.close_notice(cx));
    });
    card_row(
        t(lang, row.title).into(),
        row.subtitle.map(|s| t(lang, s).into()),
        reset,
        false,
    )
}

impl ShortcutList {
    fn new(cx: &mut Context<Self>) -> Self {
        let lang = cx.global::<Services>().lang;
        let search = cx
            .new(|cx| TextField::new(false, t(lang, Str::SettingsSearchShortcuts), cx).tab_stop());
        let detector = cx.new(Recorder::detector);
        let recorders: Vec<(Action, Entity<Recorder>)> = Action::ALL
            .iter()
            .map(|&action| (action, cx.new(Recorder::row)))
            .collect();
        let mut subscriptions = vec![
            cx.observe(&search, |this, search, cx| this.search_changed(&search, cx)),
            cx.subscribe(&detector, |this, _, event, cx| {
                this.detector_event(event, cx)
            }),
            cx.observe(&SettingsService::entity(cx), |_, _, cx| cx.notify()),
        ];
        for (action, recorder) in &recorders {
            let action = *action;
            subscriptions.push(cx.subscribe(recorder, move |this, _, event, cx| {
                this.recorded(action, event, cx)
            }));
        }
        ShortcutList {
            search,
            detector,
            text: String::new(),
            detected: None,
            recorders,
            notice: None,
            _subscriptions: subscriptions,
        }
    }

    pub(in crate::ui::settings) fn close_notice(&mut self, cx: &mut Context<Self>) {
        if self.notice.take().is_some() {
            cx.notify();
        }
    }

    /// Typing filters by text again: a detected chord is dropped.
    fn search_changed(&mut self, search: &Entity<TextField>, cx: &mut Context<Self>) {
        let text = search.read(cx).text();
        if text == self.text {
            return;
        }
        if !text.trim().is_empty() {
            self.detected = None;
        }
        self.text = text.to_string();
        cx.notify();
    }

    fn clear_text(&mut self, cx: &mut Context<Self>) {
        self.text.clear();
        self.search.update(cx, |search, cx| search.clear(cx));
    }

    fn detector_event(&mut self, event: &RecorderEvent, cx: &mut Context<Self>) {
        match event {
            RecorderEvent::Recorded(chord) => {
                self.detected = Some(chord.clone());
                self.clear_text(cx);
            }
            RecorderEvent::Cleared => {
                self.detected = None;
                self.clear_text(cx);
            }
            RecorderEvent::Refused(_) | RecorderEvent::Restored => return,
        }
        cx.notify();
    }

    /// A row's recorder or button: the binding is stored, or the banner says why not.
    fn recorded(&mut self, action: Action, event: &RecorderEvent, cx: &mut Context<Self>) {
        let chord = match event {
            RecorderEvent::Refused(refused) => {
                self.notice = Some((action, Notice::Refused(*refused)));
                cx.notify();
                return;
            }
            RecorderEvent::Recorded(chord) => Some(chord.clone()),
            RecorderEvent::Cleared => None,
            RecorderEvent::Restored => action.default_chord(),
        };
        let service = SettingsService::entity(cx);
        let (outcome, unchanged) = {
            let service = service.read(cx);
            let bindings = &service.settings().bindings;
            let outcome = rebound(service.keymap(), bindings, action, chord.as_ref());
            let unchanged = outcome.as_ref().is_ok_and(|new| new == bindings);
            (outcome, unchanged)
        };
        match outcome {
            Err(holder) => self.notice = Some((action, Notice::Taken(holder))),
            Ok(bindings) => {
                self.notice = None;
                if !unchanged {
                    let value = bindings_value(bindings);
                    service.update(cx, |service, cx| service.set(Key::Bindings, value, cx));
                }
            }
        }
        cx.notify();
    }

    fn recorder(&self, action: Action) -> Entity<Recorder> {
        self.recorders
            .iter()
            .find(|(a, _)| *a == action)
            .map(|(_, recorder)| recorder.clone())
            .expect("every action has a recorder")
    }

    fn search_bar(&self) -> Div {
        div()
            .flex()
            .flex_row()
            .items_center()
            .gap(px(12.0))
            .px(px(14.0))
            .py(px(9.0))
            .border_t_1()
            .border_color(theme::line())
            .child(div().flex_1().min_w_0().child(self.search.clone()))
            .child(self.detector.clone())
    }

    /// The action's title (with the shell caption for Ctrl plus a letter), its recorder and
    /// button, and the banner when its last chord was not saved.
    fn row(&self, action: Action, keymap: &Keymap, lang: Lang, cx: &mut Context<Self>) -> Div {
        let chord = keymap.chord(action).cloned();
        let caption = chord
            .as_ref()
            .filter(|chord| takes_from_the_shell(chord))
            .map(|_| SharedString::from(t(lang, Str::SettingsShortcutLeavesShell)));
        let recorder = self.recorder(action);
        let button = clear_button(keymap, action);
        recorder.update(cx, |recorder, cx| recorder.show(chord, button, cx));
        let line = card_row(t(lang, action.title()).into(), caption, recorder, false);
        let banner = self
            .notice
            .filter(|(shown, _)| *shown == action)
            .map(|(_, notice)| {
                // Inside the row's padding, 4 below its line (the Mac's VStack spacing).
                div()
                    .px(px(14.0))
                    .pb(px(9.0))
                    .mt(px(-5.0))
                    .child(banner(notice, lang, cx))
            });
        div().child(line).children(banner)
    }
}

impl Render for ShortcutList {
    fn render(&mut self, _: &mut Window, cx: &mut Context<Self>) -> impl IntoElement {
        let lang = cx.global::<Services>().lang;
        let keymap = current_keymap(cx).clone();
        let filter = match &self.detected {
            Some(chord) => ListFilter::Chord(chord),
            None => ListFilter::Text(&self.text),
        };
        let shown = listed(&keymap, Some(filter), lang);
        let query = self.detected.is_some() || !self.text.trim().is_empty();
        let detected = self.detected.clone();
        self.detector.update(cx, |detector, cx| {
            let button = if query {
                ClearButton::Clear
            } else {
                ClearButton::Off
            };
            detector.show(detected, button, cx)
        });
        let rows: Vec<Div> = shown
            .iter()
            .map(|&action| self.row(action, &keymap, lang, cx))
            .collect();
        div()
            .flex()
            .flex_col()
            .child(self.search_bar())
            .children(rows)
            .when(shown.is_empty(), |list| {
                list.child(
                    div()
                        .px(px(14.0))
                        .py(px(9.0))
                        .border_t_1()
                        .border_color(theme::line())
                        .text_size(px(12.0))
                        .text_color(theme::muted())
                        .child(t(lang, Str::SettingsNoShortcutsMatch)),
                )
            })
    }
}

/// The Mac's rejection banner: red fill 12 %, stroke 35 %, corner 6, with "Undo", which only
/// closes it (nothing was saved).
fn banner(notice: Notice, lang: Lang, cx: &mut Context<ShortcutList>) -> Div {
    let text: SharedString = match notice {
        Notice::Refused(refused) => refusal(lang, refused).into(),
        Notice::Taken(holder) => conflict(lang, holder).into(),
    };
    let undo = div()
        .id("shortcut-undo")
        .flex_none()
        .px(px(4.0))
        .rounded(px(4.0))
        .border_1()
        .border_color(transparent_black())
        .text_color(theme::primary_text())
        .cursor_pointer()
        .tab_index(0)
        .focus(|style| style.border_color(theme::primary_text()))
        .child(t(lang, Str::SettingsUndo))
        .on_click(cx.listener(|this, event: &ClickEvent, _, cx| {
            if matches!(event, ClickEvent::Mouse(_)) {
                this.close_notice(cx);
            }
        }))
        .on_key_down(cx.listener(|this, event: &KeyDownEvent, _, cx| {
            if activates(&key_in(event)) {
                cx.stop_propagation();
                this.close_notice(cx);
            }
        }));
    div()
        .flex()
        .flex_row()
        .items_center()
        .gap(px(8.0))
        .px(px(8.0))
        .py(px(6.0))
        .rounded(px(6.0))
        .bg(theme::error().opacity(0.12))
        .border_1()
        .border_color(theme::error().opacity(0.35))
        .text_size(px(10.0))
        .child(
            div()
                .flex_1()
                .min_w_0()
                .text_color(theme::error())
                .child(text),
        )
        .child(undo)
}

/// `shortcuts.bindings` as `SettingsService::set` takes it: action id to chord, null unbound.
fn bindings_value(bindings: BTreeMap<String, Option<String>>) -> Value {
    Value::Object(
        bindings
            .into_iter()
            .map(|(id, chord)| (id, chord.map_or(Value::Null, Value::String)))
            .collect(),
    )
}
