//! `account.identities.list` / `account.identities.remove`.
mod support;

use serde_json::json;

#[test]
fn identities_list_returns_the_relay_items() {
    let (core, fake, _dir) = support::google_logged_out();
    let r = support::google_sign_in(&core, "sign_in").unwrap();
    fake.add_identity(r["user_id"].as_str().unwrap(), "apple", "a-sub", "x@privaterelay.appleid.com", true, Some("Phu's iPhone"));
    let out = core.call("account.identities.list", json!({})).unwrap();
    let items = out["identities"].as_array().unwrap();
    assert_eq!(items.len(), 2);
    let google = items.iter().find(|i| i["provider"] == "google").unwrap();
    assert_eq!(google["email"], "google-user@shellx.test");
    let apple = items.iter().find(|i| i["provider"] == "apple").unwrap();
    assert_eq!(apple["is_private_email"], true);
    assert_eq!(apple["linked_via_device_name"], "Phu's iPhone");
    assert!(apple["created_at_unix"].as_u64().unwrap() > 0);
}

#[test]
fn identities_remove_sends_the_id_and_passes_relay_codes() {
    let (core, fake, _dir) = support::google_logged_out();
    let r = support::google_sign_in(&core, "sign_in").unwrap();
    let apple = fake.add_identity(r["user_id"].as_str().unwrap(), "apple", "a-sub", "x@y.z", false, None);
    assert_eq!(core.call("account.identities.remove", json!({"identity_id": apple})).unwrap(), json!({}));
    let out = core.call("account.identities.list", json!({})).unwrap();
    let items = out["identities"].as_array().unwrap();
    assert_eq!(items.len(), 1);
    let gid = items[0]["identity_id"].clone();
    assert_eq!(core.call("account.identities.remove", json!({"identity_id": gid})).unwrap_err().code, "last_google_identity");
    assert_eq!(core.call("account.identities.remove", json!({"identity_id": "id-0"})).unwrap_err().code, "identity_not_found");
    let before = fake.requests().len();
    assert_eq!(core.call("account.identities.remove", json!({"identity_id": "../x"})).unwrap_err().code, "invalid_params");
    assert_eq!(fake.requests().len(), before);
}

#[test]
fn identities_need_a_session_and_a_401_forgets_it() {
    let (core, fake, dir) = support::google_logged_out();
    assert_eq!(core.call("account.identities.list", json!({})).unwrap_err().code, "not_logged_in");
    support::google_sign_in(&core, "sign_in").unwrap();
    fake.revoke_token(&fake.issued_token());
    assert_eq!(core.call("account.identities.list", json!({})).unwrap_err().code, "unauthorized");
    assert!(!dir.join("session.json").exists());
    assert!(dir.join("device.key").exists());
}
