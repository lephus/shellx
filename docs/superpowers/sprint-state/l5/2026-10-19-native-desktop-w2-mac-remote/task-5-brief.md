### Task 5: Sealed invite (security review)

**Files:**
- Create: `shellx-core/src/seal.rs`, `shellx-core/tests/seal.rs`

**Interfaces:**
- Produces: `pub fn seal_invite(requester_pub: &[u8; 32], pairing_id: &str, invite_uri: &str) -> Result<String, CoreError>`; `pub fn open_invite(device_secret: &x25519_dalek::StaticSecret, pairing_id: &str, sealed_b64: &str) -> Result<Zeroizing<String>, CoreError>`; test-only `pub(crate) fn seal_with(eph: StaticSecret, nonce: [u8; 12], …)` for the known-answer vector. Format: D4. Every open failure returns code `invite_invalid` with the fixed message "sealed invite could not be opened"; seal input errors return `invalid_params`.

- [ ] **Step 1: Write the failing tests**

```rust
const URI: &str = "cmux://enroll/eyJ2ZXJzaW9uIjoxfQ";
#[test] fn round_trip() { let (s, p) = keypair(); let c = seal_invite(&p, "pr_1", URI).unwrap(); assert_eq!(&*open_invite(&s, "pr_1", &c).unwrap(), URI); }
#[test] fn wrong_key_fails() {}
#[test] fn other_pairing_id_fails() { assert_eq!(open_invite(&s, "pr_2", &c).unwrap_err().code, "invite_invalid"); }
#[test] fn any_flipped_byte_fails() { /* flip one byte in each region: version, eph_pub, nonce, ciphertext, tag */ }
#[test] fn unknown_version_and_truncation_fail() {}
#[test] fn low_order_requester_key_is_refused() { assert_eq!(seal_invite(&[0u8; 32], "pr_1", URI).unwrap_err().code, "invalid_params"); }
#[test] fn only_cmux_enroll_uris_seal() { /* "https://x" → invalid_params; 8132-byte cmux URI → invalid_params; 8131 bytes → sealed blob decodes to exactly 8192 bytes */ }
#[test] fn same_input_seals_differently() {}
#[test] fn known_answer_vector() { /* fixed eph secret, requester secret, nonce → pinned b64; Windows/L6 and any reimplementation check this */ }
```

- [ ] **Step 2: Run** `(cd shellx-core && cargo test -p shellx-core --test seal)` — Expected: FAIL.
- [ ] **Step 3: Implement** with `x25519-dalek` (`was_contributory()`), `hkdf::Hkdf::<Sha256>::new(Some(&salt), shared)`, `chacha20poly1305::ChaCha20Poly1305` with `Payload { msg, aad }`, `OsRng` for the ephemeral secret and nonce, `Zeroizing` for shared secret, key and plaintext. Run once, paste the produced vector into `known_answer_vector`, rerun.
- [ ] **Step 4: Run** — Expected: PASS.
- [ ] **Step 5: Security review** — checklist: D4 bytes exactly (salt order, info string, AAD = pairing id), contributory check on both seal and open, fresh ephemeral + random nonce per seal, no plaintext/shared secret in errors or logs, constant error message, length checks before decrypt, base64 variant (URL_SAFE_NO_PAD) consistent. Fix findings.
- [ ] **Step 6: Commit** `git commit -m "feat(shellx-core): sealed enrollment invite (X25519, HKDF-SHA256 shellx-invite-v1, ChaCha20-Poly1305, pairing-bound AAD)"`

