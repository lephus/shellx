//! Prints Noise_XX_25519_ChaChaPoly_SHA256 test vectors generated with `snow`.
//!
//! Run from the repo root:
//!   cargo run --manifest-path shellx-link/vectors/gen/Cargo.toml > shellx-link/vectors/noise_xx.json

const PROTOCOL: &str = "Noise_XX_25519_ChaChaPoly_SHA256";
const PROLOGUE: &[u8] = b"shellx-link/1";
const HANDSHAKE_PAYLOADS: [&[u8]; 3] = [b"", b"hello-r", b"hello-i"];
const TRANSPORT_PAYLOADS: [&[u8]; 2] = [b"ping", b"pong"];

fn key(seed: u8) -> [u8; 32] {
    let mut k = [0u8; 32];
    for (i, b) in k.iter_mut().enumerate() {
        *b = seed.wrapping_add((i as u8).wrapping_mul(7));
    }
    k
}

fn hex(bytes: &[u8]) -> String {
    bytes.iter().map(|b| format!("{b:02x}")).collect()
}

fn main() {
    let i_static = key(0x11);
    let i_ephemeral = key(0x22);
    let r_static = key(0x33);
    let r_ephemeral = key(0x44);

    let params: snow::params::NoiseParams = PROTOCOL.parse().expect("params");
    let mut initiator = snow::Builder::new(params.clone())
        .local_private_key(&i_static)
        .expect("i s")
        .fixed_ephemeral_key_for_testing_only(&i_ephemeral)
        .prologue(PROLOGUE)
        .expect("i prologue")
        .build_initiator()
        .expect("initiator");
    let mut responder = snow::Builder::new(params)
        .local_private_key(&r_static)
        .expect("r s")
        .fixed_ephemeral_key_for_testing_only(&r_ephemeral)
        .prologue(PROLOGUE)
        .expect("r prologue")
        .build_responder()
        .expect("responder");

    let mut buf = vec![0u8; 65535];
    let mut out = vec![0u8; 65535];
    let mut handshake = Vec::new();
    for (index, payload) in HANDSHAKE_PAYLOADS.iter().enumerate() {
        let (sender, writer, reader) = if index % 2 == 0 {
            ("initiator", &mut initiator, &mut responder)
        } else {
            ("responder", &mut responder, &mut initiator)
        };
        let n = writer.write_message(payload, &mut buf).expect("write handshake");
        let m = reader.read_message(&buf[..n], &mut out).expect("read handshake");
        assert_eq!(&out[..m], *payload);
        handshake.push((sender, hex(payload), hex(&buf[..n])));
    }
    assert!(initiator.is_handshake_finished() && responder.is_handshake_finished());

    // Ephemeral publics are the first 32 bytes of messages 1 and 2 (the `e` token in clear).
    let i_ephemeral_public = handshake[0].2[..64].to_string();
    let r_ephemeral_public = handshake[1].2[..64].to_string();
    let i_static_public = hex(responder.get_remote_static().expect("rs at responder"));
    let r_static_public = hex(initiator.get_remote_static().expect("rs at initiator"));
    let handshake_hash = hex(initiator.get_handshake_hash());
    assert_eq!(handshake_hash, hex(responder.get_handshake_hash()));

    let mut i_transport = initiator.into_transport_mode().expect("i transport");
    let mut r_transport = responder.into_transport_mode().expect("r transport");
    let mut i_to_r = Vec::new();
    let mut r_to_i = Vec::new();
    for payload in TRANSPORT_PAYLOADS {
        let n = i_transport.write_message(payload, &mut buf).expect("i write");
        let m = r_transport.read_message(&buf[..n], &mut out).expect("r read");
        assert_eq!(&out[..m], payload);
        i_to_r.push((hex(payload), hex(&buf[..n])));
    }
    for payload in TRANSPORT_PAYLOADS {
        let n = r_transport.write_message(payload, &mut buf).expect("r write");
        let m = i_transport.read_message(&buf[..n], &mut out).expect("i read");
        assert_eq!(&out[..m], payload);
        r_to_i.push((hex(payload), hex(&buf[..n])));
    }

    let messages = |list: &[(String, String)]| -> String {
        list.iter()
            .map(|(p, c)| format!("      {{ \"payload\": \"{p}\", \"ciphertext\": \"{c}\" }}"))
            .collect::<Vec<_>>()
            .join(",\n")
    };
    let handshake_json = handshake
        .iter()
        .map(|(s, p, c)| format!("    {{ \"sender\": \"{s}\", \"payload\": \"{p}\", \"ciphertext\": \"{c}\" }}"))
        .collect::<Vec<_>>()
        .join(",\n");

    println!("{{");
    println!("  \"generator\": \"shellx-link/vectors/gen (snow 0.10.0)\",");
    println!("  \"protocol\": \"{PROTOCOL}\",");
    println!("  \"encoding\": \"all byte strings are lowercase hex\",");
    println!("  \"prologue\": \"{}\",", hex(PROLOGUE));
    println!("  \"initiator\": {{");
    println!("    \"static_private\": \"{}\",", hex(&i_static));
    println!("    \"static_public\": \"{i_static_public}\",");
    println!("    \"ephemeral_private\": \"{}\",", hex(&i_ephemeral));
    println!("    \"ephemeral_public\": \"{i_ephemeral_public}\"");
    println!("  }},");
    println!("  \"responder\": {{");
    println!("    \"static_private\": \"{}\",", hex(&r_static));
    println!("    \"static_public\": \"{r_static_public}\",");
    println!("    \"ephemeral_private\": \"{}\",", hex(&r_ephemeral));
    println!("    \"ephemeral_public\": \"{r_ephemeral_public}\"");
    println!("  }},");
    println!("  \"handshake\": [\n{handshake_json}\n  ],");
    println!("  \"handshake_hash\": \"{handshake_hash}\",");
    println!("  \"transport\": {{");
    println!("    \"initiator_to_responder\": [\n{}\n    ],", messages(&i_to_r));
    println!("    \"responder_to_initiator\": [\n{}\n    ]", messages(&r_to_i));
    println!("  }}");
    println!("}}");
}
