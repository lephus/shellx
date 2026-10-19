# Task 4 report: machines.* and tickets.mint

Commit ae32772244 on shellx/l5-remote: "feat(shellx-core): machines register/list/heartbeat and relay tickets written owner-only" (R11 fixes folded into the same commit, noted in its body).

## Implemented
- src/machines.rs: register (key defaults to device key, stores machine.json {machine_id, slot}, returns {machine_id, slot}), list (is_this_machine = id equals machine.json id; fingerprint = locally computed from the server-provided key, falling back to the server field; last_seen_unix 0 when never seen), heartbeat (not_registered without machine.json, returns {}).
- src/tickets.rs: mint. Validation before any request: permission, connect needs target_machine_id, write_to must match the store's bare-name rule (new store::bare_file_name_ok). With write_to the ticket goes to tickets/<write_to> via StateStore (0600), response {path, expires_at_unix, relay_url} with no ticket; otherwise {ticket, expires_at_unix, relay_url}. MintResponse Debug hides the ticket and Drop zeroizes it.
- lib.rs: four arms added after the R1 gates. ffi test that used machines.list as "known but unimplemented" now uses pair.pending.
- Fake API: POST/GET /v2/machines, POST /v2/machines/<id>/heartbeat, POST /v2/relay/tickets. Tickets byte-exact per ledger (v2.b64url(claims).b64url(HMAC-SHA256)), issuer from options (default shellx-relay), TTL ticket_ttl_secs, register only for own machine (400 if another target), connect for own machine (D3) or a granted pair else 403 not_granted, unknown target 404 machine_not_found, online = heartbeat within 90 s. Hooks: set_last_heartbeat, grant_connect (empty by default, for Task 6), revoke_token. New fake deps: hmac 0.12, sha2 0.10 (MIT/Apache-2.0).
- R11: http.rs `.proxy(None)` with comment; FakeOptions hand-written Debug redacting password and hmac_secret (unit test); auth.login removes machine.json when user_id differs from the previous session (test login_as_another_user_drops_machine_json).

## Tests
tests/machines.rs (10), tests/tickets.rs (7), fake-api/tests/ticket_format.rs (2: byte-exact HMAC recompute for register/daemon and connect/client, rules 401/400/404), fake-api unit test for Debug redaction.
RED: `cargo test --workspace --locked` before implementation: `test result: FAILED. 0 passed; 10 failed` (tests/machines.rs; fake hooks stubbed as state only, routes 404).
GREEN: full gate `(cargo test --workspace --locked && python3 scripts/test_check_deps.py && scripts/c-smoke.sh && python3 scripts/check_deps.py)` rc=0, zero warnings, all suites ok.

## Self-review
Response shapes and codes match the brief; 90 s rule tested at 100 s offline and 80 s online; no ticket in responses with write_to, in errors or Debug; invalid params never reach the server. Cargo.lock has only the pre-existing openssl-probe (not openssl); check_deps passes. Disk 16 GB free.

## Concerns
- The ledger text says issuer "cmux-relay" but the brief and fake default use "shellx-relay"; the server config issuer must match the relay's CMUX_RELAY_ISSUER (L4/deploy).
- Re-registering the same (user, key) returns the same machine in the fake (idempotent); the real L4 behaviour is unverified.
- Heartbeat does not count at register; a machine is offline until its first heartbeat.
- R11 not split into a separate commit (fake lib.rs changes interleave).
