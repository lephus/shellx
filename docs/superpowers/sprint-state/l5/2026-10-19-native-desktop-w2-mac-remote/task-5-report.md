# Task 5 report: Sealed invite (L5, shellx-core)

**Status:** DONE. Commit `2d9f44ac5f` on `shellx/l5-remote` (parent ae32772244). Not pushed.
Commit message (Step 6, verbatim): `feat(shellx-core): sealed enrollment invite (X25519, HKDF-SHA256 shellx-invite-v1, ChaCha20-Poly1305, pairing-bound AAD)`

## What was implemented

- `shellx-core/src/seal.rs` (new): the D4 wire format.
  - `pub fn seal_invite(requester_pub: &[u8; 32], pairing_id: &str, invite_uri: &str) -> Result<String, CoreError>`: fresh 32-byte ephemeral secret and 12-byte nonce from `getrandom::fill` (no rand stack added), then `seal_with`.
  - `pub(crate) fn seal_with(eph: StaticSecret, nonce: [u8; 12], requester_pub, pairing_id, invite_uri)`: checks inputs (`invalid_params`), then `seal_bytes`, then base64url without padding.
  - `fn seal_bytes(...) -> Option<Vec<u8>>`: builds `0x01 ‖ eph_pub ‖ nonce ‖ pt`. The buffer is sized up front and encrypted in place (`encrypt_in_place_detached`, AAD = pairing id), then the tag is appended. It never reallocates, so no plaintext copy is left behind.
  - `fn derive_key(...) -> Option<Zeroizing<[u8; 32]>>`: X25519, refuses a non-contributory result, then HKDF-SHA256 with salt `eph_pub ‖ requester_pub` and info `"shellx-invite-v1"` into a 32-byte key.
  - `pub fn open_invite(device_secret: &StaticSecret, pairing_id: &str, sealed_b64: &str) -> Result<Zeroizing<String>, CoreError>`: every failure is `invite_invalid` with "sealed invite could not be opened".
  - Public constants: `VERSION`, `HKDF_INFO`, `URI_PREFIX`, `SEALED_MAX_BYTES = 8192`, `URI_MAX_BYTES = 8131`.
- `shellx-core/src/lib.rs`: `pub mod seal;`. Not wired into dispatch (Task 6 does that).
- `shellx-core/Cargo.toml`: `hkdf = "0.12"` and `chacha20poly1305 = { version = "0.10", default-features = false }`. Default features are off so aead's getrandom/rand_core path is not pulled in. `sha2`, `x25519-dalek`, `zeroize`, `getrandom` and `base64` are reused at their existing versions.
- `shellx-core/tests/seal.rs` (new): integration tests for the public API.

Additions beyond the brief:
- `seal_invite` refuses an empty `pairing_id` (`invalid_params`), and `open_invite` refuses one (`invite_invalid`). This does not change the wire bytes. L6 should mirror it.
- `open_invite` refuses input longer than 10923 base64 characters before decoding. That is the longest encoding of an 8192-byte blob.

### Where the known-answer test lives, and why
The test is `seal::tests::known_answer_vector` in `#[cfg(test)] mod tests` inside `src/seal.rs`. That lets `seal_with` stay `pub(crate)`, so no API with caller-chosen ephemeral key or nonce is reachable from outside the crate, not even behind `#[doc(hidden)]`. The integration file also has `known_answer_vector_opens`. It opens the same pinned blob through the public `open_invite` and checks that the wrong pairing id fails. A second unit test, `open_refuses_non_enroll_or_non_utf8_plaintext`, uses the private `seal_bytes` for the same reason: it has to forge AEAD-valid blobs that `seal_invite` itself refuses to make.

## Known-answer vector (for L6 / any reimplementation)

The X25519 secrets are the RFC 7748 §6.1 Alice/Bob keys. That makes the X25519 step checkable against the RFC on its own (shared = RFC value).

| field | value |
|---|---|
| eph_secret | `77076d0a7318a57d3c16c17251b26645df4c2f87ebc0992ab177fba51db92c2a` |
| requester_secret | `5dab087e624a8a4b79e17f8b83800ee66f3bb1292618b6fd1c2f8b27ff88e0eb` |
| nonce | `000102030405060708090a0b` |
| pairing_id (AAD, UTF-8) | `pr_kat_0001` |
| invite_uri (plaintext) | `cmux://enroll/eyJ2ZXJzaW9uIjoxfQ` |
| eph_pub | `8520f0098930a754748b7ddcb43ef75a0dbf3a0d26381af4eba4a98eaa9b4e6a` |
| requester_pub | `de9edb7d7b7dc1b4d35b61c2ece435373f8343c85b78674dadfc7e146f882b4f` |
| shared (X25519) | `4a5d9d5ba4ce2de1728e3bf480350f25e07e21c947d19e3376f09b3c1e161742` |
| HKDF key | `e67d50bc040745aab88a8dfde9eda4e31f20c0e785f83a862cd7dc07c1cd0878` |
| sealed (93 raw bytes) | `AYUg8AmJMKdUdIt93LQ-91oNvzoNJjga9OukqY6qm05qAAECAwQFBgcICQoLlzn2MBAYsyDPxNRUAW64gPy2CZQXpRG0oJez1dJum-jh9OHTHrIsXlx9S4EzCur9` |

**Independent cross-check:** I worked out the vector with pyca/cryptography 45.0.5 (X25519, HKDF, ChaCha20Poly1305) **before** writing the Rust code, from the D4 text alone. I pinned it into the test, and the Rust implementation matched it on its first run. The test prints all of the above under `cargo test -p shellx-core --lib seal::tests::known -- --nocapture`.

## Tests

- Integration, `tests/seal.rs` (11 tests):
  - `round_trip`: also checks the wire shape and length, and that the plaintext does not appear in the blob.
  - `wrong_key_fails`
  - `other_pairing_id_fails`: also tries `""` and `"pr_1 "`.
  - `any_flipped_byte_fails`: flips the first and last byte of each region (version, eph_pub, nonce, ct, tag), then the high bit of every byte.
  - `unknown_version_and_truncation_fail`:
    - versions 0x00, 0x02 and 0xff
    - truncations at 0, 1, 33, 45, 60, 61 and len−1, plus one appended byte
    - padding, standard alphabet, leading or trailing whitespace, garbage and an empty string
    - an 8193-byte blob, and a 1 MiB string
  - `low_order_eph_pub_is_refused_on_open`: the all-zero point and the order-8 point.
  - `low_order_requester_key_is_refused`: `[0;32]` and u=1 give `invalid_params`.
  - `empty_pairing_id_is_refused`
  - `only_cmux_enroll_uris_seal`:
    - wrong scheme or case, a missing slash and a leading space are refused, with a fixed message that does not echo the input
    - an 8132-byte URI is refused
    - an 8131-byte URI gives exactly 8192 raw bytes and round-trips
    - the bare prefix seals
  - `same_input_seals_differently`: checks for a distinct eph_pub and a distinct nonce.
  - `known_answer_vector_opens`
- Unit, `src/seal.rs` (3 tests):
  - `known_answer_vector`: pins eph_pub, requester_pub, shared, key and the blob, and opens the blob with the requester secret.
  - `open_refuses_non_enroll_or_non_utf8_plaintext`: the plaintexts `""`, `https://x`, `cmux://enroll`, a leading 0xff 0xfe, and a trailing 0xff, each with a valid AEAD.
  - `size_constants_match_d4`: 8131, 10923.

**Mutation checks** (run, then reverted; the file was confirmed identical with `cmp`):
- Swapping the salt order makes `known_answer_vector` fail.
- Disabling `was_contributory` makes `low_order_requester_key_is_refused` fail.

### RED
```
$ (cd shellx-core && cargo test -p shellx-core --test seal)
error[E0432]: unresolved import ... could not find `seal` in `shellx_core`
error: could not compile `shellx-core` (test "seal") due to 1 previous error
```
(The KAT literal was already pinned from the Python reference at this point, so it was a genuinely failing expectation.)

### GREEN (full gate)
```
$ (cd shellx-core && cargo test --workspace --locked && python3 scripts/test_check_deps.py && scripts/c-smoke.sh && python3 scripts/check_deps.py)
unittests src/lib.rs ........ test result: ok. 9 passed
tests/auth.rs ............... ok. 16 passed
tests/ffi.rs ................ ok. 10 passed
tests/machines.rs ........... ok. 10 passed
tests/seal.rs ............... ok. 11 passed
tests/store.rs .............. ok. 17 passed
tests/tickets.rs ............ ok. 7 passed
tests/version.rs ............ ok. 4 passed
fake-api lib/bin/ticket_format ok. 1 / 3 / 2 passed
test_check_deps.py: Ran 3 tests ... OK
c-smoke: {"error":{"code":"unknown_method","message":"unknown method: nope"}}
check_deps.py: ok
exit=0
```
90 tests in total, 0 failures, no compiler warnings. `cargo clippy --all-targets` reports a single warning, which was already there (`src/store.rs:259` collapsible if) and is not in this diff.

## Dependencies + licenses (all new Cargo.lock entries)

| crate | version | license |
|---|---|---|
| hkdf | 0.12.4 | MIT OR Apache-2.0 |
| chacha20poly1305 | 0.10.1 | Apache-2.0 OR MIT |
| chacha20 | 0.9.1 | Apache-2.0 OR MIT |
| poly1305 | 0.8.0 | Apache-2.0 OR MIT |
| aead | 0.5.2 | MIT OR Apache-2.0 |
| cipher | 0.4.4 | MIT OR Apache-2.0 |
| universal-hash | 0.5.1 | MIT OR Apache-2.0 |
| inout | 0.1.4 | MIT OR Apache-2.0 |
| opaque-debug | 0.3.1 | MIT OR Apache-2.0 |

`hmac 0.12`, `digest`, `sha2`, `rand_core 0.6` and `subtle` were already in the lockfile. No new getrandom version was added. `check_deps.py` prints `ok`. The lockfile has no aws-lc*, openssl/openssl-sys, native-tls or iroh*. Only the existing `openssl-probe` is present, which the guard allows.

## Step 5 checklist: self-review with line refs (`shellx-core/src/seal.rs` at 2d9f44ac5f)

| Checklist item | Satisfied by |
|---|---|
| D4 bytes exactly: layout | L95–102: `out.push(VERSION)` (L28 `0x01`), `eph_pub`, `nonce`, then the plaintext encrypted in place, then the 16-byte `tag`. On open, L140–145 split at `1`, `1+32`, `45` and `len−16`. |
| D4: salt order | L119–121: `salt = eph_pub ‖ requester_pub`. Seal passes `(eph_pub, requester_pub)` (L93). Open passes `(eph_pub, PublicKey::from(device_secret))` (L146–147). The salt-swap mutation fails the KAT. |
| D4: info string | L29 `HKDF_INFO = b"shellx-invite-v1"`, used at L123. Output is 32 bytes (`[0u8; 32]`, L122). |
| D4: AAD = pairing id | L100 (seal) and L150 (open): `pairing_id.as_bytes()`. Tested by `other_pairing_id_fails` and `known_answer_vector_opens`. |
| D4: plaintext rule | Seal: L71 (`starts_with(URI_PREFIX)`) and L74 (`len() > URI_MAX_BYTES`, where 8131 = 8192−1−32−12−16, L38). Open: L159. |
| Contributory check on seal and on open | Both paths go through `derive_key`, L116 `if !shared.was_contributory() { return None; }`. Seal maps the result to `invalid_params` (L77–78), open to `invite_invalid` (L147). |
| Fresh ephemeral + random nonce per seal | L52–56: `getrandom::fill` for a new 32-byte secret and a 12-byte nonce on every `seal_invite` call. `seal_with` is `pub(crate)` (L61). Tested by `same_input_seals_differently`. |
| No plaintext or shared secret in errors or logs | The module has no `log`, `print` or `eprintln` outside `#[cfg(test)]`. Seal error messages are fixed strings or constants (L69, L72, L75, L78), with no input echoed (asserted in `only_cmux_enroll_uris_seal`). Open errors all use `invalid()` (L45–46). |
| Zeroization | Ephemeral raw bytes: `Zeroizing` (L52). Key: `Zeroizing` (L122). `SharedSecret` and `StaticSecret` zeroize on drop (x25519-dalek `zeroize` default feature). The cipher zeroizes its key on drop (chacha20poly1305 `Drop`). Open buffer: `Zeroizing` (L148). Returned URI: `Zeroizing<String>` (L153). Bytes rejected by the UTF-8 check are zeroized (L155). |
| Constant error message | L42–46: one `invalid()` constructor. Every `Err` in `open_invite` (L136–160) uses it, including base64 (L139), length or version (L140), non-contributory (L147), AEAD (L151), UTF-8 (L156) and prefix (L159). Tests assert code and message. |
| Length checks before decrypt | L136 (`sealed_b64.len() > 10923`, before decoding) and L140 (`raw.len()` within `[61, 8192]`, and `raw[0] == VERSION`). Both come before `derive_key` and the decrypt at L147–151. |
| Base64 variant consistent | `URL_SAFE_NO_PAD` on both ends (L79 encode, L139 decode). The base64 0.22 engine refuses padding and non-canonical trailing bits. Tested: `{c}=`, the standard alphabet and whitespace all fail. |

Findings from the self-review that I fixed before committing:
- An earlier draft of the test asserted that error messages "do not contain the input". That gives a false positive for `"cmux://enroll"`, because the fixed message mentions the prefix. I replaced it with an exact fixed-message assertion.
- I moved the raw-plaintext forging test into the unit module so the crate does not need a public test hook.

## Concerns

1. **Disk:** free space is now about 13 GB, below the 15 GB rule. It was 15 GB at the start. This task's build grew `shellx-core/target` by about 0.5 GB, and I deleted `target/debug/incremental` (415 MB) after the gate. The rest of the drop came from outside this worktree, presumably other lanes. The controller should free space before the next build.
2. **Remaining copies of secret material (low):**
   - hkdf 0.12 does not zeroize its internal PRK/HMAC state.
   - `StaticSecret::from(*eph_raw)` (L56) makes a temporary stack copy of the ephemeral bytes. `auth.rs` uses the same pattern for the device key.
   - Neither copy goes into errors or logs. Both are inside the process only.
3. **Empty pairing id:** refused on both seal and open. This rule is not in D4. L6 should do the same (it does not change the wire bytes).
4. Not wired into `Core::call`. Task 6 consumes `seal_invite` and `open_invite`.
