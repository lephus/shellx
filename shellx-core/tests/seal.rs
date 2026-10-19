//! Sealed enrollment invite (D4): public seal/open behaviour.
//! The byte-exact known-answer vector for `seal_with` lives in `src/seal.rs`
//! (it needs the crate-private fixed-randomness entry point); this file checks
//! that the public `open_invite` opens that same pinned blob.

use base64::Engine;
use base64::engine::general_purpose::URL_SAFE_NO_PAD;
use shellx_core::seal::{open_invite, seal_invite};
use x25519_dalek::{PublicKey, StaticSecret};

const URI: &str = "cmux://enroll/eyJ2ZXJzaW9uIjoxfQ";
const INVALID: &str = "sealed invite could not be opened";
/// Pinned D4 vector (inputs in `seal::tests::known_answer_vector`).
const KAT_REQUESTER_SECRET: &str = "5dab087e624a8a4b79e17f8b83800ee66f3bb1292618b6fd1c2f8b27ff88e0eb";
const KAT_PAIRING_ID: &str = "pr_kat_0001";
const KAT_SEALED: &str = "AYUg8AmJMKdUdIt93LQ-91oNvzoNJjga9OukqY6qm05qAAECAwQFBgcICQoLlzn2MBAYsyDPxNRUAW64gPy2CZQXpRG0oJez1dJum-jh9OHTHrIsXlx9S4EzCur9";

fn keypair() -> (StaticSecret, [u8; 32]) {
    let mut raw = [0u8; 32];
    getrandom::fill(&mut raw).unwrap();
    let s = StaticSecret::from(raw);
    let p = PublicKey::from(&s).to_bytes();
    (s, p)
}

fn assert_invalid(s: &StaticSecret, pairing_id: &str, sealed: &str) {
    let e = open_invite(s, pairing_id, sealed).unwrap_err();
    assert_eq!(e.code, "invite_invalid");
    assert_eq!(e.message, INVALID);
}

fn raw(sealed: &str) -> Vec<u8> {
    URL_SAFE_NO_PAD.decode(sealed).unwrap()
}

fn enc(bytes: &[u8]) -> String {
    URL_SAFE_NO_PAD.encode(bytes)
}

#[test]
fn round_trip() {
    let (s, p) = keypair();
    let c = seal_invite(&p, "pr_1", URI).unwrap();
    assert_eq!(&*open_invite(&s, "pr_1", &c).unwrap(), URI);
    // Wire shape: version 1, eph_pub, nonce, ct ‖ tag.
    let b = raw(&c);
    assert_eq!(b.len(), 1 + 32 + 12 + URI.len() + 16);
    assert_eq!(b[0], 0x01);
    // Ciphertext never contains the plaintext.
    assert!(!b.windows(URI.len()).any(|w| w == URI.as_bytes()));
}

#[test]
fn wrong_key_fails() {
    let (_, p) = keypair();
    let (other, _) = keypair();
    let c = seal_invite(&p, "pr_1", URI).unwrap();
    assert_invalid(&other, "pr_1", &c);
}

#[test]
fn other_pairing_id_fails() {
    let (s, p) = keypair();
    let c = seal_invite(&p, "pr_1", URI).unwrap();
    assert_eq!(open_invite(&s, "pr_2", &c).unwrap_err().code, "invite_invalid");
    assert_invalid(&s, "pr_2", &c);
    assert_invalid(&s, "", &c);
    assert_invalid(&s, "pr_1 ", &c);
}

#[test]
fn any_flipped_byte_fails() {
    let (s, p) = keypair();
    let c = seal_invite(&p, "pr_1", URI).unwrap();
    let b = raw(&c);
    let tag_start = b.len() - 16;
    // version, eph_pub (first/last), nonce (first/last), ciphertext (first/last), tag (first/last)
    for i in [0, 1, 32, 33, 44, 45, tag_start - 1, tag_start, b.len() - 1] {
        let mut m = b.clone();
        m[i] ^= 0x01;
        assert_invalid(&s, "pr_1", &enc(&m));
    }
    // Every single byte, every bit position 7.
    for i in 0..b.len() {
        let mut m = b.clone();
        m[i] ^= 0x80;
        assert_invalid(&s, "pr_1", &enc(&m));
    }
}

#[test]
fn unknown_version_and_truncation_fail() {
    let (s, p) = keypair();
    let c = seal_invite(&p, "pr_1", URI).unwrap();
    let b = raw(&c);
    for v in [0x00u8, 0x02, 0xff] {
        let mut m = b.clone();
        m[0] = v;
        assert_invalid(&s, "pr_1", &enc(&m));
    }
    for n in [0, 1, 33, 45, 45 + 15, 45 + 16, b.len() - 1] {
        assert_invalid(&s, "pr_1", &enc(&b[..n]));
    }
    // Appended byte.
    let mut longer = b.clone();
    longer.push(0);
    assert_invalid(&s, "pr_1", &enc(&longer));
    // Not URL-safe no-pad base64: padding, whitespace, garbage. (Standard alphabet:
    // `standard_alphabet_is_refused`, on the pinned blob; a random blob's standard
    // encoding is byte-identical to `c` whenever `c` has no '-' or '_'.)
    assert_invalid(&s, "pr_1", &format!("{c}="));
    assert_invalid(&s, "pr_1", &format!(" {c}"));
    assert_invalid(&s, "pr_1", &format!("{c}\n"));
    assert_invalid(&s, "pr_1", "not base64 at all!");
    assert_invalid(&s, "pr_1", "");
    // Oversize input is refused before decoding (> 8192 raw bytes).
    assert_invalid(&s, "pr_1", &enc(&vec![1u8; 8193]));
    assert_invalid(&s, "pr_1", &"A".repeat(1 << 20));
}

#[test]
fn low_order_eph_pub_is_refused_on_open() {
    let (s, p) = keypair();
    let c = seal_invite(&p, "pr_1", URI).unwrap();
    let b = raw(&c);
    // All-zero and the order-8 point 0xe0eb7a7c...: X25519 yields the zero secret.
    let low_order: [[u8; 32]; 2] = [
        [0u8; 32],
        [
            0xe0, 0xeb, 0x7a, 0x7c, 0x3b, 0x41, 0xb8, 0xae, 0x16, 0x56, 0xe3, 0xfa, 0xf1, 0x9f, 0xc4, 0x6a, 0xda, 0x09,
            0x8d, 0xeb, 0x9c, 0x32, 0xb1, 0xfd, 0x86, 0x62, 0x05, 0x16, 0x5f, 0x49, 0xb8, 0x00,
        ],
    ];
    for point in low_order {
        let mut m = b.clone();
        m[1..33].copy_from_slice(&point);
        assert_invalid(&s, "pr_1", &enc(&m));
    }
}

#[test]
fn low_order_requester_key_is_refused() {
    let e = seal_invite(&[0u8; 32], "pr_1", URI).unwrap_err();
    assert_eq!(e.code, "invalid_params");
    let mut one = [0u8; 32];
    one[0] = 1;
    assert_eq!(seal_invite(&one, "pr_1", URI).unwrap_err().code, "invalid_params");
}

#[test]
fn empty_pairing_id_is_refused() {
    let (_, p) = keypair();
    assert_eq!(seal_invite(&p, "", URI).unwrap_err().code, "invalid_params");
}

#[test]
fn only_cmux_enroll_uris_seal() {
    let (s, p) = keypair();
    for bad in ["https://x", "", "cmux://enroll", "CMUX://enroll/x", " cmux://enroll/x", "cmux://other/x"] {
        let e = seal_invite(&p, "pr_1", bad).unwrap_err();
        assert_eq!(e.code, "invalid_params", "{bad:?}");
        // Fixed message: the input is never echoed back.
        assert_eq!(e.message, "invite_uri must start with cmux://enroll/", "{bad:?}");
    }
    let prefix = "cmux://enroll/";
    let too_long = format!("{prefix}{}", "a".repeat(8132 - prefix.len()));
    assert_eq!(too_long.len(), 8132);
    assert_eq!(seal_invite(&p, "pr_1", &too_long).unwrap_err().code, "invalid_params");
    let max = format!("{prefix}{}", "a".repeat(8131 - prefix.len()));
    assert_eq!(max.len(), 8131);
    let c = seal_invite(&p, "pr_1", &max).unwrap();
    assert_eq!(raw(&c).len(), 8192);
    assert_eq!(open_invite(&s, "pr_1", &c).unwrap().as_str(), max);
    // The bare prefix is still a cmux enroll URI.
    let c = seal_invite(&p, "pr_1", prefix).unwrap();
    assert_eq!(&*open_invite(&s, "pr_1", &c).unwrap(), prefix);
}

#[test]
fn same_input_seals_differently() {
    let (s, p) = keypair();
    let a = seal_invite(&p, "pr_1", URI).unwrap();
    let b = seal_invite(&p, "pr_1", URI).unwrap();
    assert_ne!(a, b);
    let (ra, rb) = (raw(&a), raw(&b));
    assert_ne!(ra[1..33], rb[1..33], "fresh ephemeral key per seal");
    assert_ne!(ra[33..45], rb[33..45], "fresh nonce per seal");
    assert_eq!(&*open_invite(&s, "pr_1", &a).unwrap(), URI);
    assert_eq!(&*open_invite(&s, "pr_1", &b).unwrap(), URI);
}

/// The pinned D4 vector (see `seal::tests::known_answer_vector` for every input)
/// opens through the public API with the fixed requester secret (RFC 7748 "Bob").
#[test]
fn known_answer_vector_opens() {
    let requester = StaticSecret::from(hex32(KAT_REQUESTER_SECRET));
    assert_eq!(&*open_invite(&requester, KAT_PAIRING_ID, KAT_SEALED).unwrap(), URI);
    assert_invalid(&requester, "pr_kat_0002", KAT_SEALED);
}

/// The same bytes in the standard base64 alphabet ('+' / '/') are refused. Uses
/// the pinned blob because it contains URL-safe-only characters, so its standard
/// encoding really differs; a fresh random blob has none ~2% of the time.
#[test]
fn standard_alphabet_is_refused() {
    let requester = StaticSecret::from(hex32(KAT_REQUESTER_SECRET));
    let b = raw(KAT_SEALED);
    let standard = base64::engine::general_purpose::STANDARD.encode(&b);
    assert!(standard.contains('+') && !standard.contains('='), "{standard}");
    assert_ne!(standard, KAT_SEALED);
    assert_invalid(&requester, KAT_PAIRING_ID, &standard);
    // '/' (standard 63) where URL-safe has '-' (62): off-alphabet, refused.
    assert_invalid(&requester, KAT_PAIRING_ID, &KAT_SEALED.replace('-', "/"));
    // Control: the URL-safe original still opens.
    assert_eq!(&*open_invite(&requester, KAT_PAIRING_ID, KAT_SEALED).unwrap(), URI);
}

fn hex32(h: &str) -> [u8; 32] {
    let mut out = [0u8; 32];
    for (i, b) in out.iter_mut().enumerate() {
        *b = u8::from_str_radix(&h[2 * i..2 * i + 2], 16).unwrap();
    }
    out
}
