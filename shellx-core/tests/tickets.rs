mod support;

use base64::Engine;
use base64::engine::general_purpose::URL_SAFE_NO_PAD;
use serde_json::{Value, json};
use shellx_core::Core;
use support::{requests_to, state_dir};

fn reg(core: &Core, name: &str) -> Value {
    core.call("machines.register", json!({"name":name,"platform":"macos","os_version":"15","app_version":"2.0.0"})).unwrap()
}

fn claims(ticket: &str) -> Value {
    let part = ticket.split('.').nth(1).unwrap();
    serde_json::from_slice(&URL_SAFE_NO_PAD.decode(part).unwrap()).unwrap()
}

#[test]
fn mint_writes_owner_only_file_and_omits_ticket() {
    let (core, fake, dir) = support::logged_in();
    let m = reg(&core, "Mac A");
    let r = core.call("tickets.mint", json!({"permission":"register","write_to":"register.ticket"})).unwrap();
    assert!(r.get("ticket").is_none());
    let p = std::path::PathBuf::from(r["path"].as_str().unwrap());
    assert!(p.ends_with("tickets/register.ticket"));
    assert_eq!(p, dir.join("tickets").join("register.ticket"));
    #[cfg(unix)]
    assert_eq!(support::mode(&p), 0o600);
    let t = std::fs::read_to_string(&p).unwrap();
    assert!(t.starts_with("v2."));
    assert!(r["expires_at_unix"].as_u64().unwrap() > 0);
    assert_eq!(r["relay_url"], "ws://127.0.0.1:9/v2/relay");
    assert_eq!(claims(&t)["slot"], m["slot"]);
    assert!(!r.to_string().contains(&t));
    let req = &requests_to(&fake, "/v2/relay/tickets")[0];
    assert_eq!(req.body["machine_id"], m["machine_id"]);
    assert_eq!(req.body["permission"], "register");
    assert!(req.body.get("target_machine_id").is_none());
}

#[test]
fn mint_returns_ticket_without_write_to() {
    let (core, _fake, dir) = support::logged_in();
    reg(&core, "Mac A");
    let r = core.call("tickets.mint", json!({"permission":"register"})).unwrap();
    let t = r["ticket"].as_str().unwrap();
    assert!(t.starts_with("v2."));
    assert!(r.get("path").is_none());
    assert!(std::fs::read_dir(dir.join("tickets")).unwrap().next().is_none());
    assert_eq!(claims(t)["permission"], "register");
}

#[test]
fn mint_rejects_bad_write_to_and_connect_without_target() {
    let (core, fake, dir) = support::logged_in();
    let m = reg(&core, "Mac A");
    for w in ["../x", "a/b", "tickets/x", ".hidden", "UP", "", "a b", &"a".repeat(65), "x\0y"] {
        let e = core.call("tickets.mint", json!({"permission":"register","write_to":w})).unwrap_err();
        assert_eq!(e.code, "invalid_params", "{w:?}");
    }
    let e = core.call("tickets.mint", json!({"permission":"register","write_to":5})).unwrap_err();
    assert_eq!(e.code, "invalid_params");
    for p in [json!({"permission":"connect"}), json!({"permission":"admin"}), json!({}), json!({"permission":"connect","target_machine_id":5})] {
        assert_eq!(core.call("tickets.mint", p.clone()).unwrap_err().code, "invalid_params", "{p}");
    }
    assert!(requests_to(&fake, "/v2/relay/tickets").is_empty(), "invalid params must not reach the server");
    assert!(std::fs::read_dir(dir.join("tickets")).unwrap().next().is_none());
    let _ = m;
}

#[test]
fn mint_without_machine_is_not_registered() {
    let (core, fake, _dir) = support::logged_in();
    let e = core.call("tickets.mint", json!({"permission":"register"})).unwrap_err();
    assert_eq!(e.code, "not_registered");
    assert!(requests_to(&fake, "/v2/relay/tickets").is_empty());
}

#[test]
fn connect_without_grant_is_not_granted_but_own_machine_is_allowed() {
    let (core, fake, _dir) = support::logged_in();
    let mine = reg(&core, "Mac A");
    let other = Core::new();
    let d = state_dir();
    support::configure(&other, &fake.base_url, &d, json!({}));
    other.call("auth.login", json!({"email":"c@d.e","password":"pw"})).unwrap();
    let o = reg(&other, "Other");
    let oid = o["machine_id"].as_str().unwrap();
    let e = core.call("tickets.mint", json!({"permission":"connect","target_machine_id":oid})).unwrap_err();
    assert_eq!(e.code, "not_granted");
    // D3: the caller's own machine needs no grant.
    let own = core
        .call("tickets.mint", json!({"permission":"connect","target_machine_id":mine["machine_id"]}))
        .unwrap();
    let c = claims(own["ticket"].as_str().unwrap());
    assert_eq!(c["permission"], "connect");
    assert_eq!(c["role"], "client");
    assert_eq!(c["slot"], mine["slot"]);
    // Once a pairing grant exists, the other machine is allowed and the ticket carries its slot.
    fake.grant_connect(mine["machine_id"].as_str().unwrap(), oid);
    let granted = core.call("tickets.mint", json!({"permission":"connect","target_machine_id":oid})).unwrap();
    assert_eq!(claims(granted["ticket"].as_str().unwrap())["slot"], o["slot"]);
}

#[test]
fn unknown_target_machine_passes_server_code() {
    let (core, _fake, _dir) = support::logged_in();
    reg(&core, "Mac A");
    let e = core.call("tickets.mint", json!({"permission":"connect","target_machine_id":"nope"})).unwrap_err();
    assert_eq!(e.code, "machine_not_found");
}

#[test]
fn error_messages_never_contain_tickets() {
    let (core, _fake, dir) = support::logged_in();
    reg(&core, "Mac A");
    let r = core.call("tickets.mint", json!({"permission":"register","write_to":"t"})).unwrap();
    let t = std::fs::read_to_string(r["path"].as_str().unwrap()).unwrap();
    let e = core.call("tickets.mint", json!({"permission":"register","write_to":"../t"})).unwrap_err();
    assert!(!format!("{e:?}").contains(&t));
    let _ = dir;
}

#[test]
fn mint_passes_lane() {
    let (core, fake, _dir) = support::logged_in();
    let m = reg(&core, "Mac A");
    let r = core.call("tickets.mint", json!({"permission":"register","lane":"link"})).unwrap();
    assert_eq!(claims(r["ticket"].as_str().unwrap())["slot"], m["link_slot"]);
    let reqs = requests_to(&fake, "/v2/relay/tickets");
    assert_eq!(reqs[0].body["lane"], "link");
    // Without a lane the body has none and the cmux slot is used.
    let plain = core.call("tickets.mint", json!({"permission":"register"})).unwrap();
    assert_eq!(claims(plain["ticket"].as_str().unwrap())["slot"], m["slot"]);
    assert!(requests_to(&fake, "/v2/relay/tickets")[1].body.get("lane").is_none());
    // Connecting to itself on the link lane.
    let me = core
        .call("tickets.mint", json!({"permission":"connect","target_machine_id":m["machine_id"],"lane":"link"}))
        .unwrap();
    assert_eq!(claims(me["ticket"].as_str().unwrap())["slot"], m["link_slot"]);
}

#[test]
fn mint_rejects_other_lanes_before_any_request() {
    let (core, fake, _dir) = support::logged_in();
    reg(&core, "Mac A");
    let before = requests_to(&fake, "/v2/relay/tickets").len();
    for lane in [json!("terminal"), json!(""), json!(3)] {
        let e = core.call("tickets.mint", json!({"permission":"register","lane":lane})).unwrap_err();
        assert_eq!(e.code, "invalid_params");
    }
    assert_eq!(requests_to(&fake, "/v2/relay/tickets").len(), before);
}

#[test]
fn mint_link_lane_needs_a_link_slot_from_register() {
    let (core, fake, dir) = support::logged_in();
    let m = reg(&core, "Mac A");
    std::fs::write(dir.join("machine.json"), json!({"machine_id": m["machine_id"], "slot": m["slot"]}).to_string()).unwrap();
    let before = requests_to(&fake, "/v2/relay/tickets").len();
    let e = core.call("tickets.mint", json!({"permission":"register","lane":"link"})).unwrap_err();
    assert_eq!(e.code, "not_registered");
    assert_eq!(requests_to(&fake, "/v2/relay/tickets").len(), before);
}
