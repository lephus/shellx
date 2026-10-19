# Task 6 report: Pairing methods

**Status:** DONE_WITH_CONCERNS. Commit `f4c54e34c3` on `shellx/l5-remote` (base `2d9f44ac5f`). Not pushed.
**Ready:** `f4c54e34c3`. L6 can now link `shellx-core` as a path crate.

## What was built
- `shellx-core/src/pairing.rs`: the five methods.
  - `pair.request {to_machine_id}` sends `POST /v2/pairings {from_machine_id: <stored own id>, to_machine_id, requester_x25519_b64: <device pub, b64url-nopad>}` and returns `{pairing_id, code, fingerprint}`. `fingerprint` is computed locally from the device key. If the caller passes its own `from_machine_id`, it is ignored. A `to_machine_id` equal to this machine's own id gives `invalid_params`.
  - `pair.pending {}` sends `GET /v2/pairings?role=target`. It keeps only items with `status == "pending"`, `to_machine_id == own` and a path-safe id, and returns `{pairing_id, from_machine_id, code, fingerprint, server_fingerprint, suspicious}`.
    - `fingerprint` is computed locally from `requester_x25519_b64`. That field can come in standard or URL-safe base64, padded or not, because L4 returns standard base64.
    - `suspicious` is true when the local fingerprint is not equal to `server_fingerprint`. A missing or unusable key gives `fingerprint: ""` and `suspicious: true`.
  - `pair.approve {pairing_id, invite_uri, fingerprint?}`:
    1. Validates the params and parses the invite.
    2. Re-fetches the target list.
    3. Refuses, before any POST: `not_found`, then `pairing_not_pending`, then `contract_missing_requester_key`, then `fingerprint_mismatch` (server fingerprint, and also the optional fingerprint shown on screen).
    4. Seals with AAD = `pairing_id`.
    5. Sends `POST /v2/pairings/<id>/approve {sealed_invite_b64}` and returns `{}`.
  - `pair.deny {pairing_id}` sends `POST /v2/pairings/<id>/deny` and returns `{}`. Server codes are passed through.
  - `pair.poll {pairing_id, write_invite_to?}` sends `GET /v2/pairings?role=requester` and returns `{status}`.
    - When the status is `approved`, it opens the invite with the device key, parses it and returns `{status, relay_route, relay_slot, daemon_fingerprint}`.
    - With `write_invite_to` it adds `invite_path`: the file is `<state_dir>/tickets/<name>`, mode 0600, written through `StateStore::write_secret`. Without `write_invite_to` it adds `invite_uri` instead.
    - An approved item with no openable invite gives `invite_invalid`, with the fixed message used by seal.rs.
  - `pairing_id` must match `^[A-Za-z0-9_-]{1,128}$` because it goes into URL paths. `write_invite_to` is checked with `store::bare_file_name_ok`. Both checks run before any request.
- `src/lib.rs`: five dispatch arms.
- `fake-api/src/lib.rs`: `/v2/pairings` routes following the L4 Task 4 rules:
  - `from_machine_id` must be the caller's own machine (a new field, `Machine.device_id`).
  - The code is 6 digits, redrawn if it collides with a live pending request to the same target.
  - The fingerprint is copied from the requester's machine row.
  - Pending requests expire after 300 s (status computed lazily).
  - A new (from, to) request supersedes the old pending one.
  - `role=target` items carry `requester_x25519_b64` in standard base64 (D2).
  - The sealed invite is returned only to the requester, and only once approved.
  - Approve is target-only, takes 1 to 8192 bytes, refuses plaintext starting `cmux://` (`plaintext_invite`), returns 410/409, and **grants connect from requester to target**.
  - Deny can come from the target or the requester: 204 when pending or already denied, 409 otherwise.
  - Hooks in the brief: `tamper_requester_fingerprint`, `move_sealed_invite` (moves the blob and marks the destination approved), `expire`, `stored_sealed`.
  - Extra hooks: `drop_requester_key` (a server without D2), `set_list_all_pairings` (a server that ignores `role`), `has_grant`.
- `tests/ffi.rs`: the R1 test expected `pair.pending` to give `unknown_method` once a session exists. Every known method is implemented now, so it expects `not_registered`. The test was renamed to match.

## Invite format (Ruling R4) — taken from `cmux-tui/crates/cmux-remote/src/`
- `identity.rs:38`: `ENROLLMENT_URI_PREFIX = "cmux://enroll/"`.
- `identity.rs:106-110` (`EnrollmentInvitation::to_uri`) and `:118-125` (`from_uri`): the JSON is encoded with **`URL_SAFE_NO_PAD`**, so unpadded base64url. I match that exactly; a padded string is refused (unit test).
- `identity.rs:66-79`: `struct EnrollmentInvitation { version: u32, id, secret, daemon_public_key, daemon_fingerprint, daemon_name, expires_at_unix: u64, route_hints: Vec<String>, relay_access: Vec<EnrollmentRelayAccess> (serde default, skip if empty), approval_required: bool }`. There are no serde renames; the field names are literal.
- `identity.rs:47-52`: `struct EnrollmentRelayAccess { route, slot, ticket }`.
- `identity.rs:22`: `STATE_VERSION = 1`. `:35`: `MAX_RELAY_SLOT_BYTES = 256`. `:2338`: route scheme must be `relay+ws|relay+wss|relay+https|relay+do`. `:2343-2346`: slot rules (non-empty, at most 256 bytes, no whitespace or control bytes).
- `crypto.rs:72-75`: `public_key_fingerprint` = `URL_SAFE_NO_PAD(SHA-256(key)[..16])`. `from_uri` checks that `daemon_fingerprint` matches `daemon_public_key` (`identity.rs:136-141`). I make the same check.
- `pairing.rs::InviteView` deserializes only `version`, `daemon_public_key`, `daemon_fingerprint` and `relay_access[].{route, slot}`. **`secret` and `ticket` are never deserialized.** The decoded JSON buffer is `Zeroizing`.
- The test helper `invite(route, slot)` in `tests/pairing.rs` builds the full struct in this exact shape. It includes `secret`, `ticket`, `route_hints` containing the route, and a valid daemon key/fingerprint pair.

## Tests
`tests/pairing.rs` has 13 tests:
- the 8 from the brief;
- `poll_returns_invite_uri_when_not_written`;
- `approve_refuses_fingerprint_other_than_the_one_shown`;
- `suspicious_item_without_requester_key_cannot_be_approved`;
- `invalid_params_never_reach_the_server` (17 cases, request count unchanged, no secret in any message);
- `unregistered_machine_cannot_pair`.

`pairing.rs` also has 3 unit tests: the invite parser accepts the cmux shape and refuses 10 bad variants; key decoding accepts both base64 alphabets; ids are path-safe.

**RED** — `(cd shellx-core && CARGO_INCREMENTAL=0 cargo test -p shellx-core --test pairing --locked)`. The fake routes were already in place, so the failures came from the core:
```
called `Result::unwrap()` on an `Err` value: CoreError { code: "unknown_method", message: "method not implemented: pair.request" }
test result: FAILED. 0 passed; 13 failed; ...
```
**GREEN** — same command: `test result: ok. 13 passed; 0 failed`.

**Mutation check:** I disabled the `fp != item.requester_fingerprint` check. `approve_refuses_fingerprint_mismatch` then FAILED, and the other 12 still passed. I restored the check afterwards.

**Full gate** — `(cd shellx-core && CARGO_INCREMENTAL=0 cargo test --workspace --locked && python3 scripts/test_check_deps.py && CARGO_INCREMENTAL=0 scripts/c-smoke.sh && python3 scripts/check_deps.py)`: exit 0, 0 warnings, 106 tests passed. The suites are lib 12, auth 16, ffi 10, machines 10, pairing 13, seal 11, store 17, tickets 7, version 4, fake-api 1+3+2. `check_deps` printed `ok` and c-smoke ran.

## Step 5 checklist self-review (Ruling R12; the formal review is still to be dispatched)
| Item | Where it is satisfied |
| --- | --- |
| No POST before all refusals | `pairing.rs:265` invite/params → `:270` machine → `:272` GET → refusals `:276` not_found, `:278` not_pending, `:280-281` missing key, `:284` server fp, `:287` shown fp → seal `:290` → the only POST `:295`. Tests assert 0 `/approve` requests for every refusal. |
| Fingerprint computed from the exact bytes sealed to | `:280` `let (key, fp) = requester_key(item)` (`:193-197`: decode, then `fingerprint(&key)`), then `:290` `seal_invite(&key, …)`. It is the same variable, with no re-decode in between. |
| AAD = pairing id on both ends | Seal: `:290` `seal_invite(&key, pairing_id, …)`, where `pairing_id` is the id matched at `:275`. Open: `:333` `open_invite(&secret, pairing_id, sealed)`. Test: `poll_rejects_invite_moved_to_another_pairing`. |
| Invite parsing never logs the secret | `parse_invite` (`:130-160`) returns `Option`, emits no message and never deserializes `secret` or `ticket`. Parse failures are a fixed `invite_invalid` (`:353-355`) or a fixed `invalid_params` (`:266-268`). The crate logs nothing. `PairingItem`'s Debug shows only the sealed blob's length. Tests check that responses and errors contain no `cmux://`, secret or ticket. |
| Invite file 0600, removed by the caller after use | `:344` `store.write_secret("tickets/<name>")` writes 0600 in a 0700 directory, refusing symlinks. Test asserts `mode == 0o600`. Removal belongs to Task 12 (`clientConnectsOnSnapshotLineAndDropsInviteFile`) and is noted in the module docs. |
| `suspicious` items can never be approved | Pending computes `suspicious = local_fp(None if no usable key) != server_fp` (`:236-237`). Approve refuses exactly the same two cases (`:280-284`), plus non-pending items and items not targeting this machine. Tests: `approve_refuses_fingerprint_mismatch`, `suspicious_item_without_requester_key_cannot_be_approved`. |
| `from_machine_id` always the stored own id | `:207` `require_machine`, then `:214` `from_machine_id: &own.machine_id`. Params are never read for it. The test passes `"from_machine_id": "evil"` and asserts the body still carries A's id. |

No findings that needed a fix.

## Files changed
- `/Users/lehuuphu/Documents/myProjects/shellx-wt-l5/shellx-core/src/pairing.rs` (new)
- `/Users/lehuuphu/Documents/myProjects/shellx-wt-l5/shellx-core/tests/pairing.rs` (new)
- `/Users/lehuuphu/Documents/myProjects/shellx-wt-l5/shellx-core/src/lib.rs`
- `/Users/lehuuphu/Documents/myProjects/shellx-wt-l5/shellx-core/fake-api/src/lib.rs`
- `/Users/lehuuphu/Documents/myProjects/shellx-wt-l5/shellx-core/tests/ffi.rs`

## Concerns / notes for the controller
1. **I added an optional `fingerprint` param to `pair.approve`.** It closes a gap the brief leaves open: between `pair.pending` and `pair.approve`, a server could swap the requester key and keep the server fingerprint consistent with it. The user would then approve fingerprint X while the invite is sealed to key Y. When the param is given, approve refuses with `fingerprint_mismatch` unless the key it seals to still has the fingerprint shown. The change is additive and keeps D5 compatible. **Recommendation:** Task 13 (`approve`) should pass the `PairingRequest`'s shown `fingerprint`, and L6 should do the same.
2. **The invite file goes to `<state_dir>/tickets/<name>`**, the same place `tickets.mint write_to` uses. Writing to the state-dir root would let a name like `device.key` or `session.json` overwrite core state. Task 8 (`pair.poll write_invite_to=invite.uri`) and Task 12/13 should use the returned `invite_path` and not build the path themselves.
3. **Requester-side invite checking is a subset of cmux's `from_uri`.** It checks version, the daemon key/fingerprint pair, the `relay+` scheme and the slot. It does not check expiry or `route_hints`; cmux re-validates the whole invite on `remote connect`. The target also parses the invite before approving, so a malformed `invite_uri` is `invalid_params` before any request.
4. **`pairing_id` is restricted to `[A-Za-z0-9_-]{1,128}`** because it goes into URL paths. L4 ids are UUIDv4, so this fits. L6 should apply the same rule.
5. **Fingerprint dependency on D1.** The server's `requester_fingerprint` is the fingerprint of the requester machine's noise key (L4 open question 3). Under D1 that is the device key, so the fingerprints agree. A machine registered with an explicit, different `noise_public_key_b64` would make every pairing it requests look `suspicious`. That is fail-closed and intended.
6. **Status mapping.** If the server's lazy expiry makes a pairing expired, the client already reports `pairing_not_pending` from the GET. A server `410 pairing_expired` in a race is passed through verbatim. A status outside the four known ones gives `server` in poll.
7. **Disk excursion.** Free space fell from 14.7 GiB at the start to 11.9 GiB before my first build, which was not caused by me. It reached 11 GiB after the RED build. I stopped building per R13 and wrote the code without compiling. When I next checked, another lane had freed space and it was back to 19 GiB, so I resumed.

## Disk (`df -h /`)
- Before: 15 GiB available (15432388 KiB).
- During: 11 GiB at the lowest point.
- After the gate and commit: **18 GiB** available.
- `shellx-core/target` is about 1.5 GiB and was built only with `CARGO_INCREMENTAL=0`.

## Fix round 1 (Ruling R14) — commit `eb9af97546`
**Finding fixed (Important):** in the original version the on-screen fingerprint was optional, so a caller that forgot to send it failed open. The server can swap in an attacker key and a matching `requester_fingerprint` between `pair.pending` and `pair.approve`.

**Change:** `pair.approve` now fails closed.
- It compares the fingerprint computed locally from the re-fetched key against the `fingerprint` param when one is given.
- Otherwise it compares against the fingerprint this `Core` returned for that `pairing_id` in its most recent successful `pair.pending`.
- If neither exists, it refuses with `fingerprint_mismatch` and posts nothing.
- If both exist, the param wins.
- The check runs after the earlier refusals (`not_found`, `pairing_not_pending`, `contract_missing_requester_key`, server-fingerprint mismatch), so those codes are unchanged. It still runs before sealing and before any POST.

**Where the code is:**
- `src/lib.rs`: a new field `Core::shown_fingerprints: Mutex<HashMap<pairing_id, fingerprint>>`.
  - It is replaced on every successful `pair.pending` and left as is when `pair.pending` fails.
  - `config.set` clears it.
  - Only public-key fingerprints are kept, never secrets.
- `src/pairing.rs`:
  - New `shown_fingerprints(&pending_result)`, which leaves out items with an empty fingerprint.
  - `approve(..., remembered: Option<&str>)` with the `match param_fp.or(remembered)`.
  - The rule is documented in the module docs ("Shown-fingerprint rule").
- `fake-api/src/lib.rs`: new hook `swap_requester_key(id, public)`. It sets the key and a matching `requester_fingerprint`.

**Tests in `tests/pairing.rs`:** 15 now.
- The happy paths now call `pair.pending` first; that is the new contract, where the person sees the list before approving.
- New `approve_without_shown_fingerprint_fails_closed`: with no pending call and no param the result is `fingerprint_mismatch`; after `config.set` the remembered value is gone and it is `fingerprint_mismatch` again; 0 `/approve` posts.
- New `approve_refuses_key_swapped_after_pending`: the server swaps the key and its fingerprint consistently after pending. The result is `fingerprint_mismatch` without the param and also with the shown fingerprint as the param.
  - After a fresh pending shows the attacker fingerprint, a param holding the old shown value still wins and is refused.
  - 0 posts throughout.

**Mutation check:** with `None => {}` (fail open), `approve_without_shown_fingerprint_fails_closed` FAILED. I restored the code and the pairing tests passed again (15/15).

**Command:** `(cd shellx-core && CARGO_INCREMENTAL=0 cargo test --workspace --locked && python3 scripts/test_check_deps.py && CARGO_INCREMENTAL=0 scripts/c-smoke.sh && python3 scripts/check_deps.py)` → exit 0, 0 warnings, 108 tests passed (pairing 15/15). `check_deps` printed `ok`.

**Disk:**
- 10 GiB free when this round started, below the floor. I edited the code without building.
- I waited until free space was back at about 17.6 GiB before the first build.
- 18 GiB before the gate, 17 GiB after.

**Note for Task 13 / L6:** approving without first calling `pair.pending` on the same Core now always fails. Task 13's 5 s `pair.pending` timer meets this. Callers may also pass `fingerprint` explicitly.
