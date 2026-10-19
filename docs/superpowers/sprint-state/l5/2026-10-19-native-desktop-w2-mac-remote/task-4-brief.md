### Task 4: `machines.*` and `tickets.mint`

**Files:**
- Create: `shellx-core/src/{machines.rs,tickets.rs}`, `shellx-core/tests/{machines.rs,tickets.rs}`, `shellx-core/fake-api/tests/ticket_format.rs`
- Modify: `shellx-core/fake-api/src/lib.rs` (routes `/v2/machines*`, `/v2/relay/tickets`)

**Interfaces:**
- `machines.register {name, platform, os_version, app_version, noise_public_key_b64?}` → `POST /v2/machines` (key defaults to the device key, D1) → stores `machine.json` → `{machine_id, slot}`.
- `machines.list {}` → `{machines: [{machine_id, name, platform, online, last_seen_unix, fingerprint, is_this_machine}]}`.
- `machines.heartbeat {}` → `POST /v2/machines/<own id>/heartbeat` → `{}`; `not_registered` without `machine.json`.
- `tickets.mint {permission: "register"|"connect", target_machine_id?, write_to?}` → `POST /v2/relay/tickets {machine_id:<own>, permission, target_machine_id?}` → `{ticket, expires_at_unix, relay_url}`, or with `write_to` (bare file name): writes `tickets/<write_to>` via `StateStore` and returns `{path, expires_at_unix, relay_url}`. `connect` without `target_machine_id` → `invalid_params`.
- Fake API: tickets are minted exactly per ledger "Ticket format" (`v2.` + b64url(claims) + `.` + b64url(HMAC-SHA256(secret, signing payload))), lifetime `ticket_ttl_secs`; `register` only for the caller's machine; `connect` only for a granted pairing target **or the caller's own machine** (D3); `online` = heartbeat within 90 s; test hook `set_last_heartbeat(machine_id, unix)`.

- [ ] **Step 1: Write the failing tests**

```rust
#[test] fn register_then_heartbeat_uses_stored_id() {
    let r = core.call("machines.register", json!({"name":"Mac A","platform":"macos","os_version":"15.5","app_version":"2.0.0"})).unwrap();
    core.call("machines.heartbeat", json!({})).unwrap();
    assert_eq!(fake.requests().last().unwrap().path, format!("/v2/machines/{}/heartbeat", r["machine_id"].as_str().unwrap()));
}
#[test] fn register_defaults_key_to_device_key() { /* body.noise_public_key_b64 == login's device_public_key_b64 */ }
#[test] fn list_marks_this_machine_and_offline_after_90s() {}
#[test] fn mint_writes_owner_only_file_and_omits_ticket() {
    let r = core.call("tickets.mint", json!({"permission":"register","write_to":"register.ticket"})).unwrap();
    assert!(r.get("ticket").is_none());
    let p = PathBuf::from(r["path"].as_str().unwrap());
    assert!(p.ends_with("tickets/register.ticket")); assert_eq!(mode(&p), 0o600);
    assert!(std::fs::read_to_string(&p).unwrap().starts_with("v2."));
}
#[test] fn mint_rejects_bad_write_to_and_connect_without_target() {}
#[test] fn connect_without_grant_is_not_granted_but_own_machine_is_allowed() { /* 403 code "not_granted" (L4 plan Task 5); own machine allowed per D3 */ }
```

`fake-api/tests/ticket_format.rs`: decode a minted ticket → claims `version 2`, `issuer "shellx-relay"`, `permission "register"`, `role "daemon"`, `circuit/lane/generation null`, `expires_at_unix - issued_at_unix == ttl`; recompute HMAC over `"cmux-relay-ticket-v2\n2\nshellx-relay\nregister\ndaemon\n<slot>\n\n\n\n<iat>\n<exp>"` and compare.

- [ ] **Step 2: Run** `(cd shellx-core && cargo test --workspace)` — Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** `(cd shellx-core && cargo test --workspace)` — Expected: PASS.
- [ ] **Step 5: Commit** `git commit -m "feat(shellx-core): machines register/list/heartbeat and relay tickets written owner-only"`

