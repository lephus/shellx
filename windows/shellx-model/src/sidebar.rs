//! Machines -> sidebar groups.

use serde::Deserialize;

use crate::strings::{Lang, Str, offline_last_seen, t};

/// `Debug` (hand-written) shows the name's length only: other machines' names never reach a log.
#[derive(Clone, PartialEq, Deserialize)]
pub struct MachineInfo {
    pub machine_id: String,
    pub name: String,
    /// "macos" | "windows"
    pub platform: String,
    pub online: bool,
    #[serde(default, deserialize_with = "null_as_zero")]
    pub last_seen_unix: i64,
    /// `""` when the core has none: it never shows the relay's own fingerprint and computes one only
    /// from a key, which the relay's list does not carry (R4 Blocker 1). Not used to decide anything.
    #[serde(default, deserialize_with = "string_or_empty")]
    pub fingerprint: String,
    #[serde(default)]
    pub is_this_machine: bool,
    /// The relay says this machine accepts connections from Windows PCs (Part 2). Only JSON `true` is
    /// true: the relay sends no such key today, and any other value reads false.
    #[serde(default, deserialize_with = "true_only")]
    pub can_host: bool,
}

impl std::fmt::Debug for MachineInfo {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("MachineInfo")
            .field("machine_id", &self.machine_id)
            .field("platform", &self.platform)
            .field("online", &self.online)
            .field("can_host", &self.can_host)
            .field("is_this_machine", &self.is_this_machine)
            .field(
                "name",
                &format_args!("<{} chars>", self.name.chars().count()),
            )
            .finish_non_exhaustive()
    }
}

fn true_only<'de, D: serde::Deserializer<'de>>(d: D) -> Result<bool, D::Error> {
    Ok(matches!(
        serde_json::Value::deserialize(d)?,
        serde_json::Value::Bool(true)
    ))
}

/// Which Macs the rows and the "+" picker offer "Request access" to.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum OfferRule {
    /// Only Macs the relay says can host (`can_host`): today none.
    RelayCanHost,
    /// Every Mac (`SHELLX_OFFER_ALL_MACS=1`), to try Part 2 with a test Mac build.
    AnyMac,
}

/// `SHELLX_OFFER_ALL_MACS`: only `1` (trimmed) offers every Mac.
pub fn offer_rule_from_env(value: Option<&str>) -> OfferRule {
    if value.map(str::trim) == Some("1") {
        OfferRule::AnyMac
    } else {
        OfferRule::RelayCanHost
    }
}

/// Whether this PC may ask `m` for access: another machine, a Mac, and one the relay says can host
/// (any Mac under `AnyMac`). A Windows PC never answers a request (R4 Major 5).
pub fn can_offer_access(m: &MachineInfo, rule: OfferRule) -> bool {
    !m.is_this_machine && m.platform == "macos" && (m.can_host || rule == OfferRule::AnyMac)
}

/// The "+" picker's machines: those `can_offer_access` allows that have no link (granted or pending) yet.
pub fn request_targets<'a>(
    machines: &'a [MachineInfo],
    has_link: &dyn Fn(&str) -> bool,
    rule: OfferRule,
) -> Vec<&'a MachineInfo> {
    machines
        .iter()
        .filter(|m| can_offer_access(m, rule) && !has_link(&m.machine_id))
        .collect()
}

/// The sentences the "+" picker shows: no Mac besides this machine → why none can be reached and what
/// to do; some Mac but none offered → why; every offered Mac already linked (`has_link`: granted or
/// pending) → that nothing is left to ask (review M7); otherwise none. So the picker is never empty
/// without a sentence.
pub fn request_panel_notes(
    machines: &[MachineInfo],
    has_link: &dyn Fn(&str) -> bool,
    rule: OfferRule,
) -> &'static [Str] {
    let mut macs = machines
        .iter()
        .filter(|m| !m.is_this_machine && m.platform == "macos")
        .peekable();
    if macs.peek().is_none() {
        &[Str::MacCannotHostYet, Str::SignInOnYourMac]
    } else if !macs.any(|m| can_offer_access(m, rule)) {
        &[Str::MacCannotHostYet]
    } else if request_targets(machines, has_link, rule).is_empty() {
        &[Str::NoOtherMachines]
    } else {
        &[]
    }
}

fn null_as_zero<'de, D: serde::Deserializer<'de>>(d: D) -> Result<i64, D::Error> {
    Ok(Option::<i64>::deserialize(d)?.unwrap_or(0))
}

/// A string is kept; null or any other JSON value reads as `""` (one odd item never fails the list).
fn string_or_empty<'de, D: serde::Deserializer<'de>>(d: D) -> Result<String, D::Error> {
    Ok(match serde_json::Value::deserialize(d)? {
        serde_json::Value::String(s) => s,
        _ => String::new(),
    })
}

/// Local knowledge of access to a machine.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Access {
    None,
    Pending { code: String },
    Granted,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum MachineIcon {
    Laptop,
    Desktop,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum RowAction {
    None,
    Open,
    RequestAccess,
    ShowCode(String),
}

/// `Debug` (hand-written) shows the title's length only: other machines' names never reach a log
/// (review M1).
#[derive(Clone, PartialEq, Eq)]
pub struct MachineGroup {
    pub machine_id: String,
    pub title: String,
    pub note: Option<String>,
    pub icon: MachineIcon,
    pub online: bool,
    pub dimmed: bool,
    pub subtitle: Option<String>,
    pub action: RowAction,
    pub sessions_visible: bool,
}

/// `build_groups_with` under the relay's rule (`OfferRule::RelayCanHost`).
pub fn build_groups(
    machines: &[MachineInfo],
    access: &dyn Fn(&str) -> Access,
    utc_offset_secs: i32,
    lang: Lang,
) -> Vec<MachineGroup> {
    build_groups_with(
        machines,
        access,
        utc_offset_secs,
        lang,
        OfferRule::RelayCanHost,
    )
}

/// Sidebar groups: this machine first, then online before offline, by name. An online machine with no
/// access gets `RequestAccess` only when `can_offer_access`; a granted one stays `Open`, a pending one
/// `ShowCode`.
pub fn build_groups_with(
    machines: &[MachineInfo],
    access: &dyn Fn(&str) -> Access,
    utc_offset_secs: i32,
    lang: Lang,
    rule: OfferRule,
) -> Vec<MachineGroup> {
    let icon = |m: &MachineInfo| match m.platform.as_str() {
        "macos" => MachineIcon::Laptop,
        _ => MachineIcon::Desktop,
    };
    let mut out = Vec::with_capacity(machines.len());

    for m in machines.iter().filter(|m| m.is_this_machine) {
        out.push(MachineGroup {
            machine_id: m.machine_id.clone(),
            title: m.name.clone(),
            note: Some(t(lang, Str::ThisMachine).to_string()),
            icon: icon(m),
            online: true,
            dimmed: false,
            subtitle: None,
            action: RowAction::None,
            sessions_visible: true,
        });
    }

    let mut others: Vec<&MachineInfo> = machines.iter().filter(|m| !m.is_this_machine).collect();
    // online first, then case-insensitive name, then id
    others.sort_by_key(|m| (!m.online, m.name.to_lowercase(), m.machine_id.clone()));

    for m in others {
        let (action, sessions_visible, subtitle) = if m.online {
            match access(&m.machine_id) {
                Access::Granted => (RowAction::Open, true, None),
                Access::Pending { code } => (RowAction::ShowCode(code), false, None),
                Access::None if can_offer_access(m, rule) => {
                    (RowAction::RequestAccess, false, None)
                }
                Access::None => (RowAction::None, false, None),
            }
        } else {
            (
                RowAction::None,
                false,
                Some(offline_text(m, utc_offset_secs, lang)),
            )
        };
        out.push(MachineGroup {
            machine_id: m.machine_id.clone(),
            title: m.name.clone(),
            note: None,
            icon: icon(m),
            online: m.online,
            dimmed: !m.online,
            subtitle,
            action,
            sessions_visible,
        });
    }
    out
}

impl std::fmt::Debug for MachineGroup {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("MachineGroup")
            .field("machine_id", &self.machine_id)
            .field(
                "title",
                &format_args!("<{} chars>", self.title.chars().count()),
            )
            .field("note", &self.note)
            .field("icon", &self.icon)
            .field("online", &self.online)
            .field("dimmed", &self.dimmed)
            .field("subtitle", &self.subtitle)
            .field("action", &self.action)
            .field("sessions_visible", &self.sessions_visible)
            .finish()
    }
}

fn offline_text(m: &MachineInfo, utc_offset_secs: i32, lang: Lang) -> String {
    if m.last_seen_unix <= 0 {
        return t(lang, Str::Offline).to_string();
    }
    let local = m.last_seen_unix + i64::from(utc_offset_secs);
    let sod = local.rem_euclid(86_400);
    offline_last_seen(lang, (sod / 3600) as u8, (sod % 3600 / 60) as u8)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn m(id: &str, name: &str, platform: &str, online: bool, seen: i64, me: bool) -> MachineInfo {
        MachineInfo {
            machine_id: id.into(),
            name: name.into(),
            platform: platform.into(),
            online,
            last_seen_unix: seen,
            fingerprint: "fp".into(),
            is_this_machine: me,
            can_host: false,
        }
    }

    fn none(_: &str) -> Access {
        Access::None
    }

    #[test]
    fn ordering_self_first_online_before_offline_name_sorted() {
        let ms = vec![
            m("5", "zed", "macos", false, 1760841900, false),
            m("4", "beta", "macos", true, 0, false),
            m("3", "Alpha", "windows", false, 1760841900, false),
            m("2", "alpha", "macos", true, 0, false),
            m("1", "Zzz-me", "windows", true, 0, true),
            m("0", "Alpha", "macos", true, 0, false),
        ];
        let g = build_groups(&ms, &none, 0, Lang::Vi);
        let ids: Vec<_> = g.iter().map(|x| x.machine_id.as_str()).collect();
        assert_eq!(ids, ["1", "0", "2", "4", "3", "5"]);
    }

    #[test]
    fn this_machine_is_always_online_undimmed_local() {
        let ms = vec![m("1", "PC", "windows", false, 0, true)];
        let g = &build_groups(&ms, &none, 0, Lang::Vi)[0];
        assert!(g.online && !g.dimmed && g.sessions_visible);
        assert_eq!(g.note.as_deref(), Some("máy này"));
        assert_eq!(g.action, RowAction::None);
        assert_eq!(g.subtitle, None);
        assert_eq!(g.title, "PC");
    }

    #[test]
    fn offline_subtitle_uses_utc_offset() {
        let ms = vec![m("1", "Mac", "macos", false, 1760841900, false)];
        let g = &build_groups(&ms, &none, 7 * 3600, Lang::Vi)[0];
        assert_eq!(g.subtitle.as_deref(), Some("ngoại tuyến · lần cuối 09:45"));
        assert!(g.dimmed && !g.online && !g.sessions_visible);
        assert_eq!(g.action, RowAction::None);
        let g = &build_groups(&ms, &none, 0, Lang::En)[0];
        assert_eq!(g.subtitle.as_deref(), Some("offline · last seen 02:45"));
        // negative offset wraps to the previous day
        let g = &build_groups(&ms, &none, -3 * 3600, Lang::En)[0];
        assert_eq!(g.subtitle.as_deref(), Some("offline · last seen 23:45"));
    }

    #[test]
    fn offline_never_seen_is_plain() {
        let ms = vec![m("1", "Mac", "macos", false, 0, false)];
        let g = &build_groups(&ms, &none, 0, Lang::Vi)[0];
        assert_eq!(g.subtitle.as_deref(), Some("ngoại tuyến"));
    }

    #[test]
    fn icons_per_platform() {
        let ms = vec![
            m("1", "a", "macos", true, 0, false),
            m("2", "b", "windows", true, 0, false),
            m("3", "c", "freebsd", true, 0, false),
        ];
        let g = build_groups(&ms, &none, 0, Lang::Vi);
        assert_eq!(g[0].icon, MachineIcon::Laptop);
        assert_eq!(g[1].icon, MachineIcon::Desktop);
        assert_eq!(g[2].icon, MachineIcon::Desktop);
    }

    fn host(mut m: MachineInfo) -> MachineInfo {
        m.can_host = true;
        m
    }

    #[test]
    fn action_per_access_state() {
        // Macs the relay says can host: the access state alone decides.
        let ms = vec![
            host(m("g", "a", "macos", true, 0, false)),
            host(m("p", "b", "macos", true, 0, false)),
            host(m("n", "c", "macos", true, 0, false)),
            host(m("o", "d", "macos", false, 5, false)),
        ];
        let acc = |id: &str| match id {
            "g" | "o" => Access::Granted,
            "p" => Access::Pending {
                code: "123456".into(),
            },
            _ => Access::None,
        };
        let g = build_groups(&ms, &acc, 0, Lang::Vi);
        assert_eq!(g[0].action, RowAction::Open);
        assert!(g[0].sessions_visible);
        assert_eq!(g[1].action, RowAction::ShowCode("123456".into()));
        assert!(!g[1].sessions_visible);
        assert_eq!(g[2].action, RowAction::RequestAccess);
        // offline stays inert even when access was granted
        assert_eq!(g[3].action, RowAction::None);
        assert!(!g[3].sessions_visible);
    }

    #[test]
    fn missing_is_this_machine_deserializes_false() {
        let v: MachineInfo = serde_json::from_str(
            r#"{"machine_id":"m","name":"n","platform":"macos","online":true,"last_seen_unix":1,"fingerprint":"f","x":1}"#,
        )
        .unwrap();
        assert!(!v.is_this_machine);
    }

    #[test]
    fn null_or_absent_last_seen_is_zero_and_does_not_fail_the_list() {
        let v: Vec<MachineInfo> = serde_json::from_str(
            r#"[{"machine_id":"a","name":"n","platform":"macos","online":false,"last_seen_unix":null,"fingerprint":"f"},
                {"machine_id":"b","name":"n","platform":"macos","online":false,"fingerprint":"f"}]"#,
        )
        .unwrap();
        assert_eq!(v[0].last_seen_unix, 0);
        assert_eq!(v[1].last_seen_unix, 0);
        let g = build_groups(&v, &|_| Access::None, 0, Lang::Vi);
        assert_eq!(g[0].subtitle.as_deref(), Some("ngoại tuyến"));
    }

    /// R4 Blocker 1: the core sends `"fingerprint": null` for every machine of the real relay's list.
    #[test]
    fn null_absent_or_odd_fingerprint_reads_as_empty() {
        let v: Vec<MachineInfo> = serde_json::from_str(
            r#"[{"machine_id":"a","name":"n","platform":"macos","online":true,"last_seen_unix":1,"fingerprint":null},
                {"machine_id":"b","name":"n","platform":"macos","online":true,"last_seen_unix":1},
                {"machine_id":"c","name":"n","platform":"macos","online":true,"last_seen_unix":1,"fingerprint":42}]"#,
        )
        .unwrap();
        assert_eq!(v.len(), 3);
        for m in &v {
            assert_eq!(m.fingerprint, "", "{}", m.machine_id);
        }
        let kept: MachineInfo = serde_json::from_str(
            r#"{"machine_id":"d","name":"n","platform":"macos","online":true,"fingerprint":"ab12"}"#,
        )
        .unwrap();
        assert_eq!(kept.fingerprint, "ab12");
    }

    fn action_of(groups: &[MachineGroup], id: &str) -> RowAction {
        groups
            .iter()
            .find(|g| g.machine_id == id)
            .unwrap()
            .action
            .clone()
    }

    #[test]
    fn only_macs_the_relay_says_can_host_get_request_access() {
        let ms = vec![
            m("me", "PC", "windows", true, 0, true),
            host(m("mac-host", "a", "macos", true, 0, false)),
            m("mac-plain", "b", "macos", true, 0, false),
            host(m("pc-host", "c", "windows", true, 0, false)),
            host(m("mac-offline", "d", "macos", false, 0, false)),
            m("mac-granted", "e", "macos", true, 0, false),
            m("mac-pending", "f", "macos", true, 0, false),
        ];
        let acc = |id: &str| match id {
            "mac-granted" => Access::Granted,
            "mac-pending" => Access::Pending {
                code: "123456".into(),
            },
            _ => Access::None,
        };
        let g = build_groups(&ms, &acc, 0, Lang::Vi);
        assert_eq!(action_of(&g, "mac-host"), RowAction::RequestAccess);
        assert_eq!(action_of(&g, "mac-plain"), RowAction::None);
        assert_eq!(action_of(&g, "pc-host"), RowAction::None);
        assert_eq!(action_of(&g, "mac-offline"), RowAction::None);
        assert_eq!(action_of(&g, "mac-granted"), RowAction::Open);
        assert_eq!(
            action_of(&g, "mac-pending"),
            RowAction::ShowCode("123456".into())
        );
        assert_eq!(action_of(&g, "me"), RowAction::None);
        // build_groups is build_groups_with the relay's rule
        assert_eq!(
            build_groups_with(&ms, &acc, 0, Lang::Vi, OfferRule::RelayCanHost),
            g
        );
    }

    #[test]
    fn any_mac_rule_offers_every_online_mac_but_never_a_pc() {
        let ms = vec![
            m("me", "PC", "windows", true, 0, true),
            m("mac-plain", "b", "macos", true, 0, false),
            host(m("pc-host", "c", "windows", true, 0, false)),
            m("pc", "d", "windows", true, 0, false),
            m("mac-offline", "e", "macos", false, 0, false),
        ];
        let g = build_groups_with(&ms, &none, 0, Lang::Vi, OfferRule::AnyMac);
        assert_eq!(action_of(&g, "mac-plain"), RowAction::RequestAccess);
        assert_eq!(action_of(&g, "pc-host"), RowAction::None);
        assert_eq!(action_of(&g, "pc"), RowAction::None);
        assert_eq!(action_of(&g, "mac-offline"), RowAction::None);
        assert_eq!(action_of(&g, "me"), RowAction::None);
    }

    #[test]
    fn offer_rule_reads_the_environment_value() {
        for v in [
            None,
            Some(""),
            Some("0"),
            Some("true"),
            Some("yes"),
            Some("11"),
        ] {
            assert_eq!(offer_rule_from_env(v), OfferRule::RelayCanHost, "{v:?}");
        }
        for v in [Some("1"), Some(" 1 "), Some("1\n")] {
            assert_eq!(offer_rule_from_env(v), OfferRule::AnyMac, "{v:?}");
        }
    }

    #[test]
    fn request_targets_skip_this_machine_linked_and_unofferable() {
        let ms = vec![
            host(m("me", "PC", "macos", true, 0, true)),
            host(m("m1", "a", "macos", true, 0, false)),
            host(m("m2", "b", "macos", true, 0, false)),
            m("m3", "c", "macos", true, 0, false),
            host(m("p1", "d", "windows", true, 0, false)),
            host(m("m4", "e", "macos", false, 0, false)),
        ];
        let linked = |id: &str| id == "m2";
        let ids = |v: Vec<&MachineInfo>| v.iter().map(|m| m.machine_id.clone()).collect::<Vec<_>>();
        assert_eq!(
            ids(request_targets(&ms, &linked, OfferRule::RelayCanHost)),
            ["m1", "m4"]
        );
        assert_eq!(
            ids(request_targets(&ms, &linked, OfferRule::AnyMac)),
            ["m1", "m3", "m4"]
        );
        assert!(can_offer_access(&ms[1], OfferRule::RelayCanHost));
        assert!(!can_offer_access(&ms[0], OfferRule::AnyMac), "this machine");
        assert!(!can_offer_access(&ms[4], OfferRule::AnyMac), "a PC");
    }

    #[test]
    fn request_panel_notes_tell_the_truth() {
        use OfferRule::{AnyMac, RelayCanHost};
        let me = m("me", "PC", "windows", true, 0, true);
        let pc = host(m("pc", "Bếp-PC", "windows", true, 0, false));
        let mac = m("mac", "MacBook", "macos", true, 0, false);
        let both = [Str::MacCannotHostYet, Str::SignInOnYourMac];
        let none = |_: &str| false;
        assert_eq!(
            request_panel_notes(std::slice::from_ref(&me), &none, RelayCanHost),
            both
        );
        assert_eq!(request_panel_notes(&[], &none, RelayCanHost), both);
        assert_eq!(
            request_panel_notes(&[me.clone(), pc.clone()], &none, RelayCanHost),
            both
        );
        assert_eq!(
            request_panel_notes(&[me.clone(), pc.clone(), mac.clone()], &none, RelayCanHost),
            [Str::MacCannotHostYet]
        );
        assert!(
            request_panel_notes(&[me.clone(), host(mac.clone())], &none, RelayCanHost).is_empty()
        );
        assert!(request_panel_notes(&[me.clone(), mac.clone()], &none, AnyMac).is_empty());
        assert_eq!(request_panel_notes(&[me], &none, AnyMac), both);
    }

    /// Review M7: the "+" panel is never empty without a sentence, also when every Mac that can be
    /// asked already has access or a request waiting.
    #[test]
    fn the_request_panel_always_says_why_it_is_empty() {
        use OfferRule::{AnyMac, RelayCanHost};
        let me = m("me", "PC", "windows", true, 0, true);
        let a = host(m("a", "MacBook", "macos", true, 0, false));
        let b = host(m("b", "Mac mini", "macos", false, 0, false));
        let c = m("c", "iMac", "macos", true, 0, false);
        let pc = host(m("pc", "Bếp-PC", "windows", true, 0, false));
        let ms = [me.clone(), a.clone(), b.clone(), c.clone(), pc.clone()];
        assert!(request_panel_notes(&ms, &|_| false, RelayCanHost).is_empty());
        assert!(request_panel_notes(&ms, &|id| id == "a", RelayCanHost).is_empty());
        assert_eq!(
            request_panel_notes(&ms, &|id| id == "a" || id == "b", RelayCanHost),
            [Str::NoOtherMachines]
        );
        assert!(request_panel_notes(&ms, &|id| id == "a" || id == "b", AnyMac).is_empty());
        assert_eq!(
            request_panel_notes(&ms, &|id| id != "pc", AnyMac),
            [Str::NoOtherMachines]
        );
        // Whatever the list, the links and the rule: something to click, or a sentence.
        let lists: [&[MachineInfo]; 5] = [
            &[],
            std::slice::from_ref(&me),
            &[me.clone(), pc.clone()],
            &[me.clone(), c.clone()],
            &ms,
        ];
        let links: [&dyn Fn(&str) -> bool; 3] = [&|_| false, &|id| id == "a", &|_| true];
        for list in lists {
            for has_link in links {
                for rule in [RelayCanHost, AnyMac] {
                    assert!(
                        !request_targets(list, has_link, rule).is_empty()
                            || !request_panel_notes(list, has_link, rule).is_empty(),
                        "{list:?} {rule:?}"
                    );
                }
            }
        }
    }

    #[test]
    fn can_host_reads_true_only_for_json_true() {
        let item = |extra: &str| -> MachineInfo {
            serde_json::from_str(&format!(
                r#"{{"machine_id":"m","name":"n","platform":"macos","online":true,"fingerprint":null{extra}}}"#
            ))
            .unwrap_or_else(|e| panic!("{extra}: {e}"))
        };
        for extra in [
            "",
            r#","can_host":false"#,
            r#","can_host":null"#,
            r#","can_host":"true""#,
            r#","can_host":1"#,
            r#","can_host":{}"#,
        ] {
            assert!(!item(extra).can_host, "{extra}");
        }
        assert!(item(r#","can_host":true"#).can_host);
    }
}
