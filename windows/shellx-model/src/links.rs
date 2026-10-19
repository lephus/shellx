//! Remote links: the Macs this account has been granted access to. Pure and
//! serde only. Holds no secrets: `invite_path` names the owner-only invite
//! file shellx-core wrote, never its content.

use std::collections::HashMap;

use serde::{Deserialize, Serialize};

use crate::sidebar::Access;

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct RemoteLink {
    pub machine_id: String,
    pub machine_name: String,
    pub relay_route: String,
    pub relay_slot: String,
    #[serde(default)]
    pub invite_path: Option<String>,
    pub daemon_fingerprint: String,
    #[serde(default)]
    pub enrolled: bool,
}

#[derive(Clone, Debug, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct Links {
    #[serde(default)]
    pub links: Vec<RemoteLink>,
}

impl Links {
    pub fn load_from_str(s: &str) -> Result<Links, serde_json::Error> {
        serde_json::from_str(s)
    }

    pub fn to_string_pretty(&self) -> String {
        serde_json::to_string_pretty(self).expect("links serialize")
    }

    /// Insert, or replace the link for the same machine.
    pub fn upsert(&mut self, link: RemoteLink) {
        match self.links.iter_mut().find(|l| l.machine_id == link.machine_id) {
            Some(slot) => *slot = link,
            None => self.links.push(link),
        }
    }

    pub fn get(&self, machine_id: &str) -> Option<&RemoteLink> {
        self.links.iter().find(|l| l.machine_id == machine_id)
    }

    pub fn remove(&mut self, machine_id: &str) -> Option<RemoteLink> {
        let i = self.links.iter().position(|l| l.machine_id == machine_id)?;
        Some(self.links.remove(i))
    }

    /// `pending` maps machine id to the pairing code being waited on.
    pub fn access_for(&self, machine_id: &str, pending: &HashMap<String, String>) -> Access {
        if self.get(machine_id).is_some() {
            Access::Granted
        } else if let Some(code) = pending.get(machine_id) {
            Access::Pending { code: code.clone() }
        } else {
            Access::None
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn link(id: &str, slot: &str) -> RemoteLink {
        RemoteLink {
            machine_id: id.into(),
            machine_name: format!("Mac {id}"),
            relay_route: "relay+wss://r/v2/relay".into(),
            relay_slot: slot.into(),
            invite_path: Some(format!("/x/invite-{id}.uri")),
            daemon_fingerprint: "ab12".into(),
            enrolled: false,
        }
    }

    #[test]
    fn round_trip() {
        let mut l = Links::default();
        l.upsert(link("m1", "s1"));
        l.upsert(link("m2", "s2"));
        let back = Links::load_from_str(&l.to_string_pretty()).unwrap();
        assert_eq!(back, l);
        assert_eq!(Links::load_from_str("{}").unwrap(), Links::default());
    }

    #[test]
    fn upsert_replaces_get_remove() {
        let mut l = Links::default();
        l.upsert(link("m1", "s1"));
        l.upsert(link("m1", "s9"));
        assert_eq!(l.links.len(), 1);
        assert_eq!(l.get("m1").unwrap().relay_slot, "s9");
        assert!(l.get("nope").is_none());
        assert!(l.remove("m1").is_some());
        assert!(l.remove("m1").is_none());
        assert!(l.links.is_empty());
    }

    #[test]
    fn access_mapping() {
        let mut l = Links::default();
        l.upsert(link("m1", "s1"));
        let mut pending = HashMap::new();
        pending.insert("m2".to_string(), "123456".to_string());
        pending.insert("m1".to_string(), "000000".to_string());
        assert_eq!(l.access_for("m1", &pending), Access::Granted);
        assert_eq!(
            l.access_for("m2", &pending),
            Access::Pending { code: "123456".into() }
        );
        assert_eq!(l.access_for("m3", &pending), Access::None);
    }
}
