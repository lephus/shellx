//! Mutual proof of the endpoint secret (spec §6.3). The agent proves first,
//! so a process squatting on the port without the secret never receives a
//! terminal byte.

use hmac::{Hmac, KeyInit, Mac};
use sha2::Sha256;

type HmacSha256 = Hmac<Sha256>;

pub const AGENT_LABEL: &[u8] = b"shellx-term/agent";
pub const TERM_LABEL: &[u8] = b"shellx-term/term";

fn mac(secret: &[u8; 32], label: &[u8], first: &[u8; 32], second: &[u8; 32]) -> HmacSha256 {
    let mut m = <HmacSha256 as KeyInit>::new_from_slice(secret).expect("HMAC takes any key length");
    m.update(label);
    m.update(first);
    m.update(second);
    m
}

fn bytes(m: HmacSha256) -> [u8; 32] {
    let mut out = [0u8; 32];
    out.copy_from_slice(&m.finalize().into_bytes());
    out
}

/// HMAC(secret, "shellx-term/agent" ‖ nonce_term ‖ nonce_agent).
pub fn agent_proof(secret: &[u8; 32], nonce_term: &[u8; 32], nonce_agent: &[u8; 32]) -> [u8; 32] {
    bytes(mac(secret, AGENT_LABEL, nonce_term, nonce_agent))
}

/// HMAC(secret, "shellx-term/term" ‖ nonce_agent ‖ nonce_term).
pub fn term_proof(secret: &[u8; 32], nonce_agent: &[u8; 32], nonce_term: &[u8; 32]) -> [u8; 32] {
    bytes(mac(secret, TERM_LABEL, nonce_agent, nonce_term))
}

/// Constant-time check of the agent's proof.
pub fn verify_agent(
    secret: &[u8; 32],
    nonce_term: &[u8; 32],
    nonce_agent: &[u8; 32],
    proof: &[u8],
) -> bool {
    mac(secret, AGENT_LABEL, nonce_term, nonce_agent)
        .verify_slice(proof)
        .is_ok()
}

/// Constant-time check of the terminal's proof (used by the agent; tests).
pub fn verify_term(
    secret: &[u8; 32],
    nonce_agent: &[u8; 32],
    nonce_term: &[u8; 32],
    proof: &[u8],
) -> bool {
    mac(secret, TERM_LABEL, nonce_agent, nonce_term)
        .verify_slice(proof)
        .is_ok()
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::proto::messages::tests::{hex, vector};

    fn inputs() -> ([u8; 32], [u8; 32], [u8; 32]) {
        let secret = [0x42; 32];
        let nonce_term: [u8; 32] = std::array::from_fn(|i| i as u8 + 1);
        let nonce_agent: [u8; 32] = std::array::from_fn(|i| 0x80 + i as u8);
        (secret, nonce_term, nonce_agent)
    }

    #[test]
    fn proofs_verify_and_differ_by_direction() {
        let (s, t, a) = inputs();
        let agent = agent_proof(&s, &t, &a);
        let term = term_proof(&s, &a, &t);
        assert_ne!(agent, term);
        assert!(verify_agent(&s, &t, &a, &agent));
        assert!(verify_term(&s, &a, &t, &term));
        assert!(!verify_agent(&s, &t, &a, &term));
        assert!(!verify_agent(&[0x43; 32], &t, &a, &agent));
        assert!(!verify_agent(&s, &t, &a, &agent[..31]));
    }

    /// Run once: `cargo test --features test-hooks write_proof_vectors -- --ignored`
    #[test]
    #[ignore]
    fn write_proof_vectors() {
        let (s, t, a) = inputs();
        let path = concat!(env!("CARGO_MANIFEST_DIR"), "/protocol/vectors.txt");
        let text = std::fs::read_to_string(path).unwrap();
        let lines: Vec<&str> = text.lines().filter(|l| !l.starts_with("auth.")).collect();
        let mut out = lines.join("\n");
        out.push('\n');
        out.push_str(&format!("auth.secret={}\n", hex(&s)));
        out.push_str(&format!("auth.nonce_term={}\n", hex(&t)));
        out.push_str(&format!("auth.nonce_agent={}\n", hex(&a)));
        out.push_str(&format!(
            "auth.agent_proof={}\n",
            hex(&agent_proof(&s, &t, &a))
        ));
        out.push_str(&format!(
            "auth.term_proof={}\n",
            hex(&term_proof(&s, &a, &t))
        ));
        std::fs::write(path, out).unwrap();
    }

    #[test]
    fn proof_vectors_match() {
        let (s, t, a) = inputs();
        assert_eq!(
            vector("auth.agent_proof").unwrap(),
            hex(&agent_proof(&s, &t, &a))
        );
        assert_eq!(
            vector("auth.term_proof").unwrap(),
            hex(&term_proof(&s, &a, &t))
        );
    }
}
