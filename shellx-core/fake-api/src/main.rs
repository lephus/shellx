//! `shellx-fake-api --bind 127.0.0.1:<port> --relay-url <url> --ticket-ttl <s> --issuer <s>`
//!
//! Secrets come from the environment only, never argv: `CMUX_RELAY_HMAC_SECRET`
//! (required, at least 32 bytes) and `SHELLX_FAKE_PASSWORD` (the password every
//! fake account accepts; default `pw`). Prints `listening <base_url>` once bound
//! (`--bind 127.0.0.1:0` picks a free port). Secret values are never printed.

use shellx_fake_api::{FakeApi, FakeOptions};
use std::io::Write;

const USAGE: &str =
    "usage: shellx-fake-api --bind 127.0.0.1:<port> --relay-url <url> --ticket-ttl <secs> --issuer <name>";

fn die(msg: &str) -> ! {
    eprintln!("shellx-fake-api: {msg}\n{USAGE}");
    std::process::exit(2);
}

fn main() {
    let mut opts = FakeOptions::default();
    let mut bind = "127.0.0.1:0".to_string();
    let mut args = std::env::args().skip(1);
    while let Some(flag) = args.next() {
        let mut value = || args.next().unwrap_or_else(|| die(&format!("{flag} needs a value")));
        match flag.as_str() {
            "--bind" => bind = value(),
            "--relay-url" => opts.relay_url = value(),
            "--ticket-ttl" => {
                opts.ticket_ttl_secs =
                    value().parse().ok().filter(|t| *t > 0).unwrap_or_else(|| die("--ticket-ttl must be a positive integer"));
            }
            "--issuer" => opts.issuer = value(),
            "-h" | "--help" => {
                println!("{USAGE}");
                return;
            }
            other => die(&format!("unknown argument {other}")),
        }
    }
    match std::env::var("CMUX_RELAY_HMAC_SECRET") {
        Ok(s) if s.len() >= 32 => opts.hmac_secret = s.into_bytes(),
        Ok(s) => die(&format!("CMUX_RELAY_HMAC_SECRET must be at least 32 bytes (got {})", s.len())),
        Err(_) => die("CMUX_RELAY_HMAC_SECRET is not set"),
    }
    if let Ok(pw) = std::env::var("SHELLX_FAKE_PASSWORD") {
        if pw.is_empty() {
            die("SHELLX_FAKE_PASSWORD must not be empty");
        }
        opts.password = pw;
    }
    if !bind.starts_with("127.0.0.1:") {
        die("--bind must be 127.0.0.1:<port> (the fake API is loopback only)");
    }
    let api = FakeApi::bind(&bind, opts).unwrap_or_else(|e| die(&e));
    println!("listening {}", api.base_url);
    let _ = std::io::stdout().flush();
    api.wait();
}
