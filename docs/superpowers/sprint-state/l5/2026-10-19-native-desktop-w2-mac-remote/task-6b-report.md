# Task 6b report

Commits (shellx/l5-remote, pushed): 55ebf4fff6 test(shellx-core) fake API enforces registered key (R17/R13); f64ba9eadd e2e fails fast + secret scan + workflow paths.

## Changes
- fake-api/src/lib.rs: POST /v2/pairings -> 400 `bad_request` ("Malformed request body") unless requester_x25519_b64 equals the requester machine's registered noise_public_key_b64. Copied from real server feat/relay-v2:relay/src/v2/pairings.ts:103 (`Errors.badRequest()` = relay/src/http/errors.ts:15, 400 "bad_request"). GET items of both roles now carry requester_x25519_b64 (standard base64; real server pairings.ts:165). Module doc updated.
- shellx-core/tests/pairing.rs: `request_with_key_other_than_registered_is_refused` (machine registered with explicit different key; pair.request -> code bad_request; target's pair.pending empty), `requester_list_items_carry_the_requester_key` (GET role=requester via ureq with the session token).
- RED: both new tests failed before the fake change (request succeeded; key Null). GREEN after: pairing 17/17, workspace all ok.
- workflow paths widened as ruled (R22a). harness.wait_until re-raises HarnessError (R22b). Harness.secret_leaks() scans every regular file under the harness dir (excl. *.input.log) for `cmux://enroll/`, HMAC secret, password; called in tearDown of every test before close (R22c). py_compile ok.
- relay_url: no production example exists in the fake/docs (default is the local placeholder ws://127.0.0.1:9/v2/relay, used by fake-api tests); left unchanged, nothing to change.

## Gate
cargo test --workspace --locked, test_check_deps.py, c-smoke.sh, check_deps.py all pass (scripts live in shellx-core/scripts). df stayed ~13 GB.

## CI
Run 39175354906 on f64ba9ea: first attempt failed only in `test_reconnect_after_relay_restart_with_2s_tickets` (viewer did not reconnect in 45 s, "relay rejected the authenticated operation"); no leak assertion fired. Rerun of failed job: success (all 4 jobs green). Previous run 39173969849 had passed.

## Concerns
- Reconnect-after-relay-restart e2e is flaky (1 of 2 attempts on this commit); not caused by this change (no leak/fast-fail involvement) but worth a look.
- shellx-core tests/seal.rs `unknown_version_and_truncation_fail` failed once in ~20 runs locally (passed on rerun, and on stash): a pre-existing flaky test (likely random byte).
