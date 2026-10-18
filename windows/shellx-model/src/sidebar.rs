//! Machines -> sidebar groups.

use serde::Deserialize;

use crate::strings::{Lang, Str, offline_last_seen, t};

#[derive(Clone, Debug, PartialEq, Deserialize)]
pub struct MachineInfo {
    pub machine_id: String,
    pub name: String,
    /// "macos" | "windows"
    pub platform: String,
    pub online: bool,
    #[serde(default, deserialize_with = "null_as_zero")]
    pub last_seen_unix: i64,
    pub fingerprint: String,
    #[serde(default)]
    pub is_this_machine: bool,
}

fn null_as_zero<'de, D: serde::Deserializer<'de>>(d: D) -> Result<i64, D::Error> {
    Ok(Option::<i64>::deserialize(d)?.unwrap_or(0))
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

#[derive(Clone, Debug, PartialEq, Eq)]
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

pub fn build_groups(
    machines: &[MachineInfo],
    access: &dyn Fn(&str) -> Access,
    utc_offset_secs: i32,
    lang: Lang,
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
                Access::None => (RowAction::RequestAccess, false, None),
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

    #[test]
    fn action_per_access_state() {
        let ms = vec![
            m("g", "a", "macos", true, 0, false),
            m("p", "b", "macos", true, 0, false),
            m("n", "c", "macos", true, 0, false),
            m("o", "d", "macos", false, 5, false),
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
}
