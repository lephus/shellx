//! Device fingerprint (D1): first 16 lowercase hex chars of SHA-256 over the raw
//! 32-byte X25519 public key. Same value the server reports for machines.

use sha2::{Digest, Sha256};

pub fn fingerprint(public: &[u8; 32]) -> String {
    Sha256::digest(public)[..8].iter().map(|b| format!("{b:02x}")).collect()
}
