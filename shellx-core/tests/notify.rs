//! `notify.phones`: the Mac tells the phones granted to it that an agent needs the user, or that the
//! request was handled (`POST /v2/notifications`).
mod support;

use serde_json::json;
use shellx_core::Core;
use support::requests_to;

fn registered_with_phone() -> (Core, shellx_fake_api::FakeApi, support::Dir) {
    let (core, fake, dir) = support::logged_in();
    let m = core
        .call("machines.register", json!({"name": "Mac A", "platform": "macos", "os_version": "15", "app_version": "2.0.0"}))
        .unwrap();
    let machine = m["machine_id"].as_str().unwrap().to_string();
    let id = fake.add_phone_pairing(&machine, "Phu's iPhone", "ios", [7u8; 32]);
    core.call("phones.approve", json!({"pairing_id": id})).unwrap();
    (core, fake, dir)
}

#[test]
fn needs_you_posts_the_agent_and_workspace_and_answers_how_many_phones_got_it() {
    let (core, fake, _dir) = registered_with_phone();

    let out = core
        .call(
            "notify.phones",
            json!({"kind": "needs_you", "request_id": "req-1", "agent": "Claude Code", "workspace_title": "shellx"}),
        )
        .unwrap();

    assert_eq!(out, json!({"sent": 1}));
    let posts = requests_to(&fake, "/v2/notifications");
    assert_eq!(posts.len(), 1);
    assert_eq!(posts[0].method, "POST");
    assert_eq!(
        posts[0].body,
        json!({"kind": "needs_you", "request_id": "req-1", "agent": "Claude Code", "workspace_title": "shellx"})
    );
    assert!(posts[0].headers.get("authorization").is_some_and(|a| a.starts_with("Bearer ")));
}

#[test]
fn resolved_posts_only_the_request_id() {
    let (core, fake, _dir) = registered_with_phone();

    core.call("notify.phones", json!({"kind": "resolved", "request_id": "req-1", "agent": "Claude Code"})).unwrap();

    assert_eq!(requests_to(&fake, "/v2/notifications")[0].body, json!({"kind": "resolved", "request_id": "req-1"}));
}

#[test]
fn bad_params_are_refused_before_any_request() {
    let (core, fake, _dir) = registered_with_phone();
    for params in [
        json!({"kind": "done", "request_id": "r"}),
        json!({"kind": "resolved"}),
        json!({"kind": "resolved", "request_id": ""}),
        json!({"kind": "resolved", "request_id": "é".repeat(33)}),
        json!({"kind": "needs_you", "request_id": "r"}),
        json!({"kind": "needs_you", "request_id": "r", "agent": "  "}),
        json!({"kind": "needs_you", "request_id": "r", "agent": "Claude Code", "workspace_title": 7}),
        json!("not an object"),
    ] {
        let err = core.call("notify.phones", params.clone()).unwrap_err();
        assert_eq!(err.code, "invalid_params", "{params}");
    }
    assert!(requests_to(&fake, "/v2/notifications").is_empty());
}

#[test]
fn needs_a_registered_machine() {
    let (core, fake, _dir) = support::logged_in();
    let err = core.call("notify.phones", json!({"kind": "resolved", "request_id": "r"})).unwrap_err();
    assert_eq!(err.code, "not_registered");
    assert!(requests_to(&fake, "/v2/notifications").is_empty());
}
