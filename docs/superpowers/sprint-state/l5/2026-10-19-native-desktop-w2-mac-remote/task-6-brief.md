### Task 6: Pairing methods (security review)

**Files:**
- Create: `shellx-core/src/pairing.rs`, `shellx-core/tests/pairing.rs`
- Modify: `shellx-core/fake-api/src/lib.rs` (`/v2/pairings*`, 6-digit codes, 5-minute expiry, test hooks `tamper_requester_fingerprint(id, fp)`, `move_sealed_invite(from_id, to_id)`, `expire(id)`)

**Interfaces:**
- Consumes: `seal_invite`/`open_invite` (Task 5), `fingerprint` (Task 3), own `machine.json` (Task 4).
- Produces (D5):
  - `pair.request {to_machine_id}` → `POST /v2/pairings {from_machine_id:<own>, to_machine_id, requester_x25519_b64:<device pub>}` → `{pairing_id, code, fingerprint}` (`fingerprint` = local, of the device key).
  - `pair.pending {}` → `GET /v2/pairings?role=target` → `{pairings: [{pairing_id, from_machine_id, code, fingerprint, server_fingerprint, suspicious}]}` for `status == "pending"` and `to_machine_id == own`; `fingerprint` = `fingerprint(requester_x25519_b64)` computed locally; `suspicious` = `server_fingerprint != fingerprint`; items without `requester_x25519_b64` are returned with `suspicious: true` (D2 not deployed).
  - `pair.approve {pairing_id, invite_uri}` → re-fetches the target list; refuses `not_found`, `pairing_not_pending`, `contract_missing_requester_key`, `fingerprint_mismatch` **before** any POST; seals (AAD `pairing_id`) → `POST /v2/pairings/<id>/approve {sealed_invite_b64}` → `{}`.
  - `pair.deny {pairing_id}` → `POST /v2/pairings/<id>/deny` → `{}`.
  - `pair.poll {pairing_id, write_invite_to?}` → `GET /v2/pairings?role=requester` → `{status}`; when `approved` with `sealed_invite_b64`: opens it with the device key, parses the invite JSON (base64url after `cmux://enroll/`) and returns `{status, relay_route: relay_access[0].route, relay_slot: relay_access[0].slot, daemon_fingerprint}` plus `invite_path` (file written 0600 via `write_invite_to`) or `invite_uri` (when not written). An approved item without an openable invite → `invite_invalid`.

- [ ] **Step 1: Write the failing tests** (two `Core`s, A = requester, B = target, both logged in and registered against one `FakeApi`)

```rust
#[test] fn request_returns_code_and_local_fingerprint() {
    let r = a.call("pair.request", json!({"to_machine_id": b_id})).unwrap();
    assert!(r["code"].as_str().unwrap().len() == 6 && r["code"].as_str().unwrap().bytes().all(|c| c.is_ascii_digit()));
    assert_eq!(r["fingerprint"], a_login["fingerprint"]);
}
#[test] fn target_sees_pending_with_matching_fingerprint() { /* b pair.pending: same code, fingerprint == a's, suspicious == false */ }
#[test] fn approve_seals_and_requester_opens() {
    b.call("pair.approve", json!({"pairing_id": pid, "invite_uri": invite("relay+wss://relay.test/v2/relay", "slotB")})).unwrap();
    let p = a.call("pair.poll", json!({"pairing_id": pid, "write_invite_to": "invite-b.uri"})).unwrap();
    assert_eq!(p["status"], "approved"); assert_eq!(p["relay_slot"], "slotB");
    assert!(p.get("invite_uri").is_none()); assert_eq!(mode(p["invite_path"].as_str().unwrap()), 0o600);
    assert!(!fake.stored_sealed(&pid).contains("cmux://")); // server holds ciphertext only
}
#[test] fn approve_refuses_fingerprint_mismatch() {               // Review Focus 3
    fake.tamper_requester_fingerprint(&pid, "0000000000000000");
    assert_eq!(b.call("pair.approve", json!({"pairing_id": pid, "invite_uri": URI})).unwrap_err().code, "fingerprint_mismatch");
    assert!(!fake.requests().iter().any(|r| r.path.ends_with("/approve")));
}
#[test] fn approve_refuses_non_pending() { /* deny then approve → pairing_not_pending; expired → pairing_not_pending */ }
#[test] fn poll_rejects_invite_moved_to_another_pairing() {     // Review Focus 3
    fake.move_sealed_invite(&pid1, &pid2);
    assert_eq!(a.call("pair.poll", json!({"pairing_id": pid2})).unwrap_err().code, "invite_invalid");
}
#[test] fn denied_and_expired_pass_through() {}
#[test] fn pending_ignores_pairings_for_other_machines() {}
```

- [ ] **Step 2: Run** `(cd shellx-core && cargo test -p shellx-core --test pairing)` — Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** `(cd shellx-core && cargo test --workspace && scripts/c-smoke.sh)` — Expected: PASS. Report "ready <sha>" (L6 can now link `shellx-core` as a path crate).
- [ ] **Step 5: Security review** — checklist: no POST before all refusals; fingerprint computed from the exact bytes sealed to; AAD = pairing id on both ends; invite parsing never logs the secret; invite file 0600 and removed by the caller after use (Task 12); `suspicious` items can never be approved; `from_machine_id` always the stored own id. Fix findings.
- [ ] **Step 6: Commit** `git commit -m "feat(shellx-core): pairing request/pending/approve/deny/poll with local fingerprints and sealed invites"`

