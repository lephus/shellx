//! The `shellx-fake-api` binary takes secrets from the environment only.
use std::io::{BufRead, BufReader};
use std::process::{Command, Stdio};

const BIN: &str = env!("CARGO_BIN_EXE_shellx-fake-api");
const SECRET: &str = "0123456789abcdef0123456789abcdef-test";

fn base() -> Command {
    let mut c = Command::new(BIN);
    c.env_remove("CMUX_RELAY_HMAC_SECRET").env_remove("SHELLX_FAKE_PASSWORD");
    c.args(["--bind", "127.0.0.1:0", "--relay-url", "ws://127.0.0.1:9/v2/relay", "--ticket-ttl", "2", "--issuer", "shellx-relay"]);
    c
}

#[test]
fn refuses_to_start_without_secret_and_never_prints_it() {
    let out = base().output().unwrap();
    assert_eq!(out.status.code(), Some(2));
    let short = base().env("CMUX_RELAY_HMAC_SECRET", "too-short-secret").output().unwrap();
    assert_eq!(short.status.code(), Some(2));
    let all = format!("{}{}", String::from_utf8_lossy(&short.stdout), String::from_utf8_lossy(&short.stderr));
    assert!(!all.contains("too-short-secret"));
}

#[test]
fn refuses_non_loopback_bind() {
    let out = Command::new(BIN)
        .env("CMUX_RELAY_HMAC_SECRET", SECRET)
        .args(["--bind", "0.0.0.0:0"])
        .output()
        .unwrap();
    assert_eq!(out.status.code(), Some(2));
}

#[test]
fn serves_version_with_secret_from_env() {
    let mut child = base().env("CMUX_RELAY_HMAC_SECRET", SECRET).stdout(Stdio::piped()).stderr(Stdio::piped()).spawn().unwrap();
    let mut line = String::new();
    BufReader::new(child.stdout.take().unwrap()).read_line(&mut line).unwrap();
    let url = line.trim().strip_prefix("listening ").unwrap().to_string();
    let addr = url.strip_prefix("http://").unwrap();
    use std::io::{Read, Write};
    let mut s = std::net::TcpStream::connect(addr).unwrap();
    s.write_all(b"GET /v1/version HTTP/1.1\r\nHost: x\r\nConnection: close\r\n\r\n").unwrap();
    let mut resp = String::new();
    s.read_to_string(&mut resp).unwrap();
    child.kill().unwrap();
    let out = child.wait_with_output().unwrap();
    assert!(resp.starts_with("HTTP/1.1 200"), "{resp}");
    assert!(resp.contains("latest_agent"));
    assert!(!resp.contains(SECRET));
    assert!(!String::from_utf8_lossy(&out.stderr).contains(SECRET));
    assert!(!line.contains(SECRET));
}
