mod support;

use base64::Engine;
use base64::engine::general_purpose::URL_SAFE_NO_PAD;
use serde_json::{Value, json};
use std::collections::BTreeSet;
use support::requests_to;

const ACCESS: &str = "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"; // 43 chars

fn claims(ticket: &str) -> Value {
    let part = ticket.split('.').nth(1).unwrap();
    serde_json::from_slice(&URL_SAFE_NO_PAD.decode(part).unwrap()).unwrap()
}

fn create(core: &shellx_core::Core) -> Value {
    core.call("shares.create", json!({"permission":"view","lifetime":"1h","one_time":false,"access":ACCESS})).unwrap()
}

#[test]
fn create_then_host_ticket() {
    let (core, fake, _dir) = support::logged_in();
    let s = create(&core);
    let id = s["id"].as_str().unwrap();
    assert_eq!(id.len(), 8);
    assert!(s["slot"].as_str().unwrap().len() > 8);
    assert!(s["expires_at_unix"].as_u64().unwrap() > 0);
    assert!(s["claim_until_unix"].is_null());
    let t = core.call("shares.host_ticket", json!({"id": id})).unwrap();
    assert!(t["ticket"].as_str().unwrap().starts_with("v2."));
    assert!(t["expires_at_unix"].as_u64().unwrap() > 0);
    assert_eq!(t["relay_url"], "ws://127.0.0.1:9/v2/relay");
    let c = claims(t["ticket"].as_str().unwrap());
    assert_eq!(c["permission"], "register");
    assert_eq!(c["slot"], s["slot"]);
    // The display form with a dash is accepted and stripped before the call.
    let dashed = format!("{}-{}", &id[..4], &id[4..]);
    core.call("shares.host_ticket", json!({"id": dashed})).unwrap();
    let paths: Vec<String> = requests_to(&fake, &format!("/v2/shares/{id}/host-ticket")).into_iter().map(|r| r.path).collect();
    assert_eq!(paths.len(), 2);
    let l = core.call("shares.list", json!({})).unwrap();
    assert_eq!(l["shares"][0]["id"], id);
    assert_eq!(l["shares"][0]["permission"], "view");
    assert_eq!(l["shares"][0]["revoked"], false);
}

#[test]
fn one_time_create_forces_type_until_quit_and_claim_window() {
    let (core, _fake, _dir) = support::logged_in();
    let s = core.call("shares.create", json!({"permission":"view","lifetime":"15m","one_time":true,"access":ACCESS})).unwrap();
    let claim = s["claim_until_unix"].as_u64().unwrap();
    let exp = s["expires_at_unix"].as_u64().unwrap();
    assert_eq!(exp - claim, 86400 - 120);
    let l = core.call("shares.list", json!({})).unwrap();
    assert_eq!(l["shares"][0]["permission"], "type");
    assert_eq!(l["shares"][0]["lifetime"], "until_quit");
}

#[test]
fn ids_use_the_strict_alphabet_and_ignore_case() {
    let (core, fake, _dir) = support::logged_in();
    for id in ["ilou0000", "ILOU-0000"] {
        assert_eq!(core.call("shares.revoke", json!({"id": id})).unwrap_err().code, "invalid_params", "{id}");
    }
    assert!(requests_to(&fake, "/v2/shares/ilou0000").is_empty());
    core.call("shares.revoke", json!({"id": "K7F2-9QD1"})).unwrap_err(); // reaches the server (404), lowercased
    assert_eq!(requests_to(&fake, "/v2/shares/k7f29qd1").len(), 1);
}

#[test]
fn revoke_is_idempotent() {
    let (core, _fake, _dir) = support::logged_in();
    let id = create(&core)["id"].as_str().unwrap().to_string();
    core.call("shares.revoke", json!({"id": id})).unwrap();
    core.call("shares.revoke", json!({"id": id})).unwrap();
    let l = core.call("shares.list", json!({})).unwrap();
    assert_eq!(l["shares"][0]["revoked"], true);
}

#[test]
fn revoked_share_host_ticket_maps_code() {
    let (core, _fake, _dir) = support::logged_in();
    let id = create(&core)["id"].as_str().unwrap().to_string();
    core.call("shares.revoke", json!({"id": id})).unwrap();
    let e = core.call("shares.host_ticket", json!({"id": id})).unwrap_err();
    assert_eq!(e.code, "share_revoked");
    let e = core.call("shares.host_ticket", json!({"id": "zzzzzzzz"})).unwrap_err();
    assert_eq!(e.code, "share_not_found");
}

#[test]
fn create_never_sends_secret() {
    let (core, fake, _dir) = support::logged_in();
    core.call("shares.create", json!({"permission":"type","lifetime":"until_quit","one_time":true,"access":ACCESS, "secret":"x"})).unwrap();
    let req = &requests_to(&fake, "/v2/shares")[0];
    let keys: BTreeSet<&str> = req.body.as_object().unwrap().keys().map(String::as_str).collect();
    assert_eq!(keys, BTreeSet::from(["permission", "lifetime", "one_time", "access"]));
    assert_eq!(req.body["one_time"], true);
}

#[test]
fn invalid_params_do_not_reach_the_server() {
    let (core, fake, _dir) = support::logged_in();
    for p in [
        json!({"permission":"admin","lifetime":"1h","access":ACCESS}),
        json!({"permission":"view","lifetime":"2h","access":ACCESS}),
        json!({"permission":"view","lifetime":"1h","access":"short"}),
        json!({"permission":"view","lifetime":"1h"}),
        json!({"permission":"view","lifetime":"1h","access":ACCESS,"one_time":"yes"}),
    ] {
        assert_eq!(core.call("shares.create", p.clone()).unwrap_err().code, "invalid_params", "{p}");
    }
    for id in [json!(5), json!("../x"), json!("abc"), json!("")] {
        assert_eq!(core.call("shares.revoke", json!({"id": id})).unwrap_err().code, "invalid_params");
        assert_eq!(core.call("shares.host_ticket", json!({"id": id})).unwrap_err().code, "invalid_params");
    }
    assert!(fake.requests().iter().all(|r| !r.path.starts_with("/v2/shares")));
}

#[test]
fn shares_need_a_session() {
    let (core, _fake, _dir) = support::logged_out();
    assert_eq!(core.call("shares.list", json!({})).unwrap_err().code, "not_logged_in");
}
