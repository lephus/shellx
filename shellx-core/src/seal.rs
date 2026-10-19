//! Sealed enrollment invite (D4). The target seals a `cmux://enroll/` URI to the
//! requester's X25519 device key; the server only relays ciphertext.
//!
//! Wire format (Windows/L6 reimplements these bytes; see `tests::known_answer_vector`):
//!
//! ```text
//! sealed = base64url_nopad( 0x01 ‖ eph_pub[32] ‖ nonce[12] ‖ ChaCha20-Poly1305(pt) ‖ tag[16] )
//! shared = X25519(eph_secret, requester_pub)          -- must be contributory
//! key    = HKDF-SHA256(ikm = shared, salt = eph_pub ‖ requester_pub,
//!                      info = "shellx-invite-v1", L = 32)
//! aad    = UTF-8 pairing_id
//! pt     = UTF-8 invite URI, starts with "cmux://enroll/", ≤ 8131 bytes
//! ```
//!
//! Every open failure is the same `invite_invalid` error with a fixed message, so
//! a caller learns nothing about which check failed. Nothing here logs.

use crate::envelope::CoreError;
use base64::Engine;
use base64::engine::general_purpose::URL_SAFE_NO_PAD;
use chacha20poly1305::aead::{AeadInPlace, KeyInit};
use chacha20poly1305::{ChaCha20Poly1305, Key, Nonce, Tag};
use hkdf::Hkdf;
use sha2::Sha256;
use x25519_dalek::{PublicKey, StaticSecret};
use zeroize::{Zeroize, Zeroizing};

pub const VERSION: u8 = 0x01;
pub const HKDF_INFO: &[u8] = b"shellx-invite-v1";
pub const URI_PREFIX: &str = "cmux://enroll/";
/// L4's `SEALED_INVITE_MAX_BYTES` (raw, before base64).
pub const SEALED_MAX_BYTES: usize = 8192;
const PUB_LEN: usize = 32;
const NONCE_LEN: usize = 12;
const TAG_LEN: usize = 16;
const HEADER_LEN: usize = 1 + PUB_LEN + NONCE_LEN;
/// 8192 − 1 − 32 − 12 − 16 = 8131.
pub const URI_MAX_BYTES: usize = SEALED_MAX_BYTES - HEADER_LEN - TAG_LEN;
/// Longest base64url-no-pad string a `SEALED_MAX_BYTES` blob encodes to (10923).
const SEALED_MAX_B64: usize = (SEALED_MAX_BYTES * 4).div_ceil(3);

const INVALID_CODE: &str = "invite_invalid";
const INVALID_MESSAGE: &str = "sealed invite could not be opened";

fn invalid() -> CoreError {
    CoreError::new(INVALID_CODE, INVALID_MESSAGE)
}

/// Seal `invite_uri` to `requester_pub`, bound to `pairing_id`. Fresh ephemeral
/// key and random nonce per call. Input errors are `invalid_params`.
pub fn seal_invite(requester_pub: &[u8; 32], pairing_id: &str, invite_uri: &str) -> Result<String, CoreError> {
    let mut eph_raw = Zeroizing::new([0u8; 32]);
    let mut nonce = [0u8; NONCE_LEN];
    getrandom::fill(&mut eph_raw[..]).map_err(|_| CoreError::new("crypto", "random source unavailable"))?;
    getrandom::fill(&mut nonce).map_err(|_| CoreError::new("crypto", "random source unavailable"))?;
    seal_with(StaticSecret::from(*eph_raw), nonce, requester_pub, pairing_id, invite_uri)
}

/// `seal_invite` with caller-supplied ephemeral secret and nonce. Crate-private:
/// only `seal_invite` (fresh randomness) and the known-answer test call it.
pub(crate) fn seal_with(
    eph: StaticSecret,
    nonce: [u8; NONCE_LEN],
    requester_pub: &[u8; 32],
    pairing_id: &str,
    invite_uri: &str,
) -> Result<String, CoreError> {
    if pairing_id.is_empty() {
        return Err(CoreError::invalid_params("pairing_id is required"));
    }
    if !invite_uri.starts_with(URI_PREFIX) {
        return Err(CoreError::invalid_params(format!("invite_uri must start with {URI_PREFIX}")));
    }
    if invite_uri.len() > URI_MAX_BYTES {
        return Err(CoreError::invalid_params(format!("invite_uri is longer than {URI_MAX_BYTES} bytes")));
    }
    let sealed = seal_bytes(&eph, nonce, requester_pub, pairing_id, invite_uri.as_bytes())
        .ok_or_else(|| CoreError::invalid_params("requester key is not a usable X25519 public key"))?;
    Ok(URL_SAFE_NO_PAD.encode(sealed))
}

/// D4 bytes for any plaintext; `None` when the shared secret is non-contributory.
/// The plaintext is encrypted in place inside the output buffer (sized up front,
/// so it never reallocates and leaves no plaintext copy behind).
fn seal_bytes(
    eph: &StaticSecret,
    nonce: [u8; NONCE_LEN],
    requester_pub: &[u8; 32],
    pairing_id: &str,
    plaintext: &[u8],
) -> Option<Vec<u8>> {
    let eph_pub = PublicKey::from(eph).to_bytes();
    let key = derive_key(eph, requester_pub, &eph_pub, requester_pub)?;
    let mut out = Vec::with_capacity(HEADER_LEN + plaintext.len() + TAG_LEN);
    out.push(VERSION);
    out.extend_from_slice(&eph_pub);
    out.extend_from_slice(&nonce);
    out.extend_from_slice(plaintext);
    let tag = ChaCha20Poly1305::new(Key::from_slice(&key[..]))
        .encrypt_in_place_detached(Nonce::from_slice(&nonce), pairing_id.as_bytes(), &mut out[HEADER_LEN..])
        .ok()?;
    out.extend_from_slice(&tag);
    Some(out)
}

/// HKDF-SHA256(X25519(our_secret, their_pub), salt = eph_pub ‖ requester_pub,
/// info = "shellx-invite-v1") → 32-byte key; `None` for a non-contributory DH.
fn derive_key(
    our_secret: &StaticSecret,
    their_pub: &[u8; 32],
    eph_pub: &[u8; 32],
    requester_pub: &[u8; 32],
) -> Option<Zeroizing<[u8; 32]>> {
    // `SharedSecret` zeroizes itself on drop.
    let shared = our_secret.diffie_hellman(&PublicKey::from(*their_pub));
    if !shared.was_contributory() {
        return None;
    }
    let mut salt = [0u8; 2 * PUB_LEN];
    salt[..PUB_LEN].copy_from_slice(eph_pub);
    salt[PUB_LEN..].copy_from_slice(requester_pub);
    let mut key = Zeroizing::new([0u8; 32]);
    Hkdf::<Sha256>::new(Some(&salt), shared.as_bytes()).expand(HKDF_INFO, &mut key[..]).ok()?;
    Some(key)
}

/// Open a sealed invite with this device's X25519 secret. Every failure (bad
/// base64, wrong length, unknown version, non-contributory key, AEAD failure,
/// non-UTF-8 or non-`cmux://enroll/` plaintext) is `invite_invalid` with the
/// fixed message "sealed invite could not be opened".
pub fn open_invite(
    device_secret: &StaticSecret,
    pairing_id: &str,
    sealed_b64: &str,
) -> Result<Zeroizing<String>, CoreError> {
    if pairing_id.is_empty() || sealed_b64.len() > SEALED_MAX_B64 {
        return Err(invalid());
    }
    let raw = URL_SAFE_NO_PAD.decode(sealed_b64).map_err(|_| invalid())?;
    if raw.len() < HEADER_LEN + TAG_LEN || raw.len() > SEALED_MAX_BYTES || raw[0] != VERSION {
        return Err(invalid());
    }
    let eph_pub: [u8; 32] = raw[1..1 + PUB_LEN].try_into().map_err(|_| invalid())?;
    let nonce = Nonce::from_slice(&raw[1 + PUB_LEN..HEADER_LEN]);
    let (ct, tag) = raw[HEADER_LEN..].split_at(raw.len() - HEADER_LEN - TAG_LEN);
    let requester_pub = PublicKey::from(device_secret).to_bytes();
    let key = derive_key(device_secret, &eph_pub, &eph_pub, &requester_pub).ok_or_else(invalid)?;
    let mut buf = Zeroizing::new(ct.to_vec());
    ChaCha20Poly1305::new(Key::from_slice(&key[..]))
        .decrypt_in_place_detached(nonce, pairing_id.as_bytes(), &mut buf[..], Tag::from_slice(tag))
        .map_err(|_| invalid())?;
    let uri = match String::from_utf8(std::mem::take(&mut *buf)) {
        Ok(s) => Zeroizing::new(s),
        Err(e) => {
            e.into_bytes().zeroize();
            return Err(invalid());
        }
    };
    if !uri.starts_with(URI_PREFIX) {
        return Err(invalid());
    }
    Ok(uri)
}

#[cfg(test)]
mod tests {
    //! Lives here (not in `tests/seal.rs`) because `seal_with` is crate-private:
    //! fixed randomness must never be reachable from outside the crate.
    use super::*;

    fn hex(bytes: &[u8]) -> String {
        bytes.iter().map(|b| format!("{b:02x}")).collect()
    }

    fn unhex<const N: usize>(h: &str) -> [u8; N] {
        let mut out = [0u8; N];
        for (i, b) in out.iter_mut().enumerate() {
            *b = u8::from_str_radix(&h[2 * i..2 * i + 2], 16).unwrap();
        }
        out
    }

    // Inputs: X25519 secrets are RFC 7748 §6.1 Alice (ephemeral) and Bob (requester),
    // so the shared secret is the RFC's 4a5d9d5b…161742.
    const EPH_SECRET: &str = "77076d0a7318a57d3c16c17251b26645df4c2f87ebc0992ab177fba51db92c2a";
    const REQUESTER_SECRET: &str = "5dab087e624a8a4b79e17f8b83800ee66f3bb1292618b6fd1c2f8b27ff88e0eb";
    const NONCE_HEX: &str = "000102030405060708090a0b";
    const PAIRING_ID: &str = "pr_kat_0001";
    const URI: &str = "cmux://enroll/eyJ2ZXJzaW9uIjoxfQ";
    // Expected intermediates and output (cross-checked with pyca/cryptography).
    const EPH_PUB: &str = "8520f0098930a754748b7ddcb43ef75a0dbf3a0d26381af4eba4a98eaa9b4e6a";
    const REQUESTER_PUB: &str = "de9edb7d7b7dc1b4d35b61c2ece435373f8343c85b78674dadfc7e146f882b4f";
    const SHARED: &str = "4a5d9d5ba4ce2de1728e3bf480350f25e07e21c947d19e3376f09b3c1e161742";
    const KEY: &str = "e67d50bc040745aab88a8dfde9eda4e31f20c0e785f83a862cd7dc07c1cd0878";
    const SEALED: &str = "AYUg8AmJMKdUdIt93LQ-91oNvzoNJjga9OukqY6qm05qAAECAwQFBgcICQoLlzn2MBAYsyDPxNRUAW64gPy2CZQXpRG0oJez1dJum-jh9OHTHrIsXlx9S4EzCur9";

    #[test]
    fn known_answer_vector() {
        let eph = StaticSecret::from(unhex::<32>(EPH_SECRET));
        let requester = StaticSecret::from(unhex::<32>(REQUESTER_SECRET));
        let nonce = unhex::<12>(NONCE_HEX);
        let eph_pub = PublicKey::from(&eph).to_bytes();
        let requester_pub = PublicKey::from(&requester).to_bytes();
        println!("shellx-invite-v1 known-answer vector (D4)");
        println!("  eph_secret       = {EPH_SECRET}");
        println!("  requester_secret = {REQUESTER_SECRET}");
        println!("  nonce            = {NONCE_HEX}");
        println!("  pairing_id (aad) = {PAIRING_ID:?}");
        println!("  invite_uri (pt)  = {URI:?}");
        println!("  eph_pub          = {}", hex(&eph_pub));
        println!("  requester_pub    = {}", hex(&requester_pub));
        println!("  shared           = {}", hex(eph.diffie_hellman(&PublicKey::from(requester_pub)).as_bytes()));
        let key = derive_key(&eph, &requester_pub, &eph_pub, &requester_pub).unwrap();
        println!("  hkdf key         = {}", hex(&key[..]));
        let sealed = seal_with(eph.clone(), nonce, &requester_pub, PAIRING_ID, URI).unwrap();
        println!("  sealed           = {sealed}");

        assert_eq!(hex(&eph_pub), EPH_PUB);
        assert_eq!(hex(&requester_pub), REQUESTER_PUB);
        assert_eq!(hex(eph.diffie_hellman(&PublicKey::from(requester_pub)).as_bytes()), SHARED);
        assert_eq!(hex(&key[..]), KEY);
        assert_eq!(sealed, SEALED);
        // The requester side opens the pinned blob.
        assert_eq!(&*open_invite(&requester, PAIRING_ID, SEALED).unwrap(), URI);
    }

    /// AEAD-valid blobs whose plaintext is not a UTF-8 `cmux://enroll/` URI are refused.
    #[test]
    fn open_refuses_non_enroll_or_non_utf8_plaintext() {
        let requester = StaticSecret::from(unhex::<32>(REQUESTER_SECRET));
        let requester_pub = PublicKey::from(&requester).to_bytes();
        let eph = StaticSecret::from(unhex::<32>(EPH_SECRET));
        let pts: [&[u8]; 5] = [b"", b"https://x", b"cmux://enroll", b"\xff\xfecmux://enroll/x", b"cmux://enroll/\xff"];
        for pt in pts {
            let blob = seal_bytes(&eph, unhex::<12>(NONCE_HEX), &requester_pub, PAIRING_ID, pt).unwrap();
            let e = open_invite(&requester, PAIRING_ID, &URL_SAFE_NO_PAD.encode(blob)).unwrap_err();
            assert_eq!((e.code.as_str(), e.message.as_str()), (INVALID_CODE, INVALID_MESSAGE));
        }
    }

    #[test]
    fn size_constants_match_d4() {
        assert_eq!(URI_MAX_BYTES, 8131);
        assert_eq!(SEALED_MAX_B64, 10923);
        assert_eq!(URL_SAFE_NO_PAD.encode([0u8; SEALED_MAX_BYTES]).len(), SEALED_MAX_B64);
    }
}
