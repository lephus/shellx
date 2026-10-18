//! `version.check`: `GET /v1/version`, compare `app_version` with the server's
//! `min_agent` (→ `update_required`) and `latest_agent.version`
//! (→ `update_available`).
//!
//! Versions are strict SemVer 2.0 (`MAJOR.MINOR.PATCH[-pre][+build]`, no leading
//! zeros, numbers fit `u64`); build metadata is ignored and a pre-release sorts
//! before its release. A version the parser rejects (ours or the server's) is
//! "nothing to compare against": it never forces an update, like the server's
//! own `isSettableVersion` contract.

use crate::api::VersionResponse;
use crate::config::Config;
use crate::envelope::CoreError;
use crate::http::{self, Method};
use serde_json::{Value, json};
use std::cmp::Ordering;

#[derive(Debug, Clone, PartialEq, Eq)]
enum Pre {
    Num(u64),
    Alpha(String),
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SemVer {
    core: [u64; 3],
    pre: Vec<Pre>,
}

fn num(s: &str) -> Option<u64> {
    if s.is_empty() || !s.bytes().all(|c| c.is_ascii_digit()) || (s.len() > 1 && s.starts_with('0')) {
        return None;
    }
    s.parse().ok()
}

impl SemVer {
    pub fn parse(s: &str) -> Option<SemVer> {
        let (rest, build) = match s.split_once('+') {
            Some((r, b)) => (r, Some(b)),
            None => (s, None),
        };
        let ident_ok = |id: &str| !id.is_empty() && id.bytes().all(|c| c.is_ascii_alphanumeric() || c == b'-');
        if let Some(b) = build
            && !b.split('.').all(ident_ok)
        {
            return None;
        }
        let (core, pre) = match rest.split_once('-') {
            Some((c, p)) => (c, Some(p)),
            None => (rest, None),
        };
        let parts: Vec<&str> = core.split('.').collect();
        if parts.len() != 3 {
            return None;
        }
        let core = [num(parts[0])?, num(parts[1])?, num(parts[2])?];
        let mut ids = Vec::new();
        if let Some(p) = pre {
            for id in p.split('.') {
                if !ident_ok(id) {
                    return None;
                }
                if id.bytes().all(|c| c.is_ascii_digit()) {
                    ids.push(Pre::Num(num(id)?));
                } else {
                    ids.push(Pre::Alpha(id.to_string()));
                }
            }
        }
        Some(SemVer { core, pre: ids })
    }
}

impl Ord for Pre {
    fn cmp(&self, other: &Pre) -> Ordering {
        match (self, other) {
            (Pre::Num(a), Pre::Num(b)) => a.cmp(b),
            (Pre::Num(_), Pre::Alpha(_)) => Ordering::Less,
            (Pre::Alpha(_), Pre::Num(_)) => Ordering::Greater,
            (Pre::Alpha(a), Pre::Alpha(b)) => a.cmp(b),
        }
    }
}

impl PartialOrd for Pre {
    fn partial_cmp(&self, other: &Pre) -> Option<Ordering> {
        Some(self.cmp(other))
    }
}

impl Ord for SemVer {
    fn cmp(&self, other: &SemVer) -> Ordering {
        self.core.cmp(&other.core).then_with(|| match (self.pre.is_empty(), other.pre.is_empty()) {
            (true, true) => Ordering::Equal,
            (true, false) => Ordering::Greater,
            (false, true) => Ordering::Less,
            // Lexicographic over identifiers; a shorter prefix sorts first.
            (false, false) => self.pre.cmp(&other.pre),
        })
    }
}

impl PartialOrd for SemVer {
    fn partial_cmp(&self, other: &SemVer) -> Option<Ordering> {
        Some(self.cmp(other))
    }
}

/// `a < b`, false if either does not parse.
fn older(a: &str, b: Option<&str>) -> bool {
    match (SemVer::parse(a), b.and_then(SemVer::parse)) {
        (Some(a), Some(b)) => a < b,
        _ => false,
    }
}

/// `{status, min_version, latest_version, download_url}` from a parsed body.
pub fn evaluate(cfg: &Config, v: &VersionResponse) -> Value {
    let latest = v.latest_agent.as_ref();
    let latest_version = latest.and_then(|l| l.version.as_deref());
    let download_url = latest.and_then(|l| if cfg.platform == "windows" { l.win_url.as_deref() } else { l.mac_url.as_deref() });
    let status = if older(&cfg.app_version, v.min_agent.as_deref()) {
        "update_required"
    } else if older(&cfg.app_version, latest_version) {
        "update_available"
    } else {
        "ok"
    };
    json!({
        "status": status,
        "min_version": v.min_agent,
        "latest_version": latest_version,
        "download_url": download_url,
    })
}

pub fn check(agent: &ureq::Agent, cfg: &Config, bearer: Option<&str>) -> Result<Value, CoreError> {
    const PATH: &str = "/v1/version";
    let reply = http::send(agent, cfg, bearer, Method::Get, PATH, None, None)?;
    let body: VersionResponse = http::parse_json(PATH, &reply)?;
    Ok(evaluate(cfg, &body))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn v(s: &str) -> SemVer {
        SemVer::parse(s).unwrap_or_else(|| panic!("parse {s}"))
    }

    #[test]
    fn parses_strictly() {
        for ok in ["0.0.0", "1.2.3", "10.20.30", "1.0.0-alpha", "1.0.0-alpha.1", "1.0.0-0.3.7", "1.0.0-x.7.z.92", "1.0.0+20130313144700", "1.0.0-beta+exp.sha.5114f85", "18446744073709551615.0.0"] {
            assert!(SemVer::parse(ok).is_some(), "{ok}");
        }
        for bad in ["", "1", "1.2", "1.2.3.4", "01.2.3", "1.02.3", "1.2.03", "v1.2.3", "1.2.3-", "1.2.3+", "1.2.3-01", "1.2.3-a..b", "1.2.3-a_b", " 1.2.3", "1.2.3 ", "-1.2.3", "1.2.x", "18446744073709551616.0.0"] {
            assert!(SemVer::parse(bad).is_none(), "{bad}");
        }
    }

    #[test]
    fn orders_per_semver_spec() {
        let chain = ["1.0.0-alpha", "1.0.0-alpha.1", "1.0.0-alpha.beta", "1.0.0-beta", "1.0.0-beta.2", "1.0.0-beta.11", "1.0.0-rc.1", "1.0.0", "1.0.1", "1.1.0", "1.10.0", "2.0.0"];
        for w in chain.windows(2) {
            assert!(v(w[0]) < v(w[1]), "{} < {}", w[0], w[1]);
        }
        assert_eq!(v("1.0.0+a").cmp(&v("1.0.0+b")), Ordering::Equal);
        assert!(!older("2.0.0", Some("2.0.0")));
        assert!(!older("2.0.0", None));
        assert!(!older("garbage", Some("9.9.9")));
        assert!(!older("1.0.0", Some("garbage")));
    }
}
