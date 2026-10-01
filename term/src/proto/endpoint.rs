//! Where the agent listens: `endpoint` file (spec §6.1). Three lines:
//! `v=1`, `port=<1..65535>`, `secret=<64 lowercase hex>`.

use std::path::{Path, PathBuf};

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Endpoint {
    pub port: u16,
    pub secret: [u8; 32],
    /// The file's exact bytes (to notice when the agent rewrites it).
    pub raw: Vec<u8>,
}

#[derive(Debug, PartialEq, Eq)]
pub enum EndpointError {
    Missing,
    Malformed(&'static str),
    UnsupportedVersion,
}

pub fn endpoint_path_in(home: &Path) -> PathBuf {
    home.join("Library/Application Support/ShellX/term/endpoint")
}

/// `$HOME/Library/Application Support/ShellX/term/endpoint`, if HOME is set.
pub fn default_endpoint_path() -> Option<PathBuf> {
    std::env::var_os("HOME")
        .filter(|h| !h.is_empty())
        .map(|h| endpoint_path_in(Path::new(&h)))
}

pub fn read_endpoint(path: &Path) -> Result<Endpoint, EndpointError> {
    let raw = std::fs::read(path).map_err(|_| EndpointError::Missing)?;
    parse_endpoint(&raw)
}

pub fn parse_endpoint(raw: &[u8]) -> Result<Endpoint, EndpointError> {
    let text = std::str::from_utf8(raw).map_err(|_| EndpointError::Malformed("not UTF-8"))?;
    let mut lines = text.strip_suffix('\n').unwrap_or(text).split('\n');
    match lines.next() {
        Some("v=1") => {}
        Some(v) if v.starts_with("v=") => return Err(EndpointError::UnsupportedVersion),
        _ => return Err(EndpointError::Malformed("first line must be v=")),
    }
    let port = lines
        .next()
        .and_then(|l| l.strip_prefix("port="))
        .and_then(|p| p.parse::<u16>().ok())
        .filter(|p| *p > 0)
        .ok_or(EndpointError::Malformed("port"))?;
    let hex = lines
        .next()
        .and_then(|l| l.strip_prefix("secret="))
        .filter(|h| {
            h.len() == 64
                && h.bytes()
                    .all(|b| b.is_ascii_digit() || (b'a'..=b'f').contains(&b))
        })
        .ok_or(EndpointError::Malformed("secret"))?;
    if lines.next().is_some() {
        return Err(EndpointError::Malformed("extra lines"));
    }
    let mut secret = [0u8; 32];
    for (i, byte) in secret.iter_mut().enumerate() {
        *byte = u8::from_str_radix(&hex[2 * i..2 * i + 2], 16).expect("validated hex");
    }
    Ok(Endpoint {
        port,
        secret,
        raw: raw.to_vec(),
    })
}

/// The file the agent writes (used by tests and, in P3, mirrored in Dart).
pub fn format_endpoint(port: u16, secret: &[u8; 32]) -> String {
    let hex: String = secret.iter().map(|b| format!("{b:02x}")).collect();
    format!("v=1\nport={port}\nsecret={hex}\n")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn round_trips() {
        let secret: [u8; 32] = std::array::from_fn(|i| i as u8 * 7);
        let text = format_endpoint(49152, &secret);
        let ep = parse_endpoint(text.as_bytes()).unwrap();
        assert_eq!((ep.port, ep.secret), (49152, secret));
        assert_eq!(ep.raw, text.as_bytes());
        assert!(parse_endpoint(text.trim_end().as_bytes()).is_ok()); // no final newline
    }

    #[test]
    fn rejects_bad_files() {
        let ok_secret = "ab".repeat(32);
        for (bad, expected) in [
            (
                "v=2\nport=1\nsecret=00\n".to_string(),
                EndpointError::UnsupportedVersion,
            ),
            (
                "port=1\n".to_string(),
                EndpointError::Malformed("first line must be v="),
            ),
            (
                format!("v=1\nport=0\nsecret={ok_secret}\n"),
                EndpointError::Malformed("port"),
            ),
            (
                format!("v=1\nport=70000\nsecret={ok_secret}\n"),
                EndpointError::Malformed("port"),
            ),
            (
                "v=1\nport=5\nsecret=AB\n".to_string(),
                EndpointError::Malformed("secret"),
            ),
            (
                format!("v=1\nport=5\nsecret={}\n", "AB".repeat(32)),
                EndpointError::Malformed("secret"),
            ),
            (
                format!("v=1\nport=5\nsecret={ok_secret}\nx=1\n"),
                EndpointError::Malformed("extra lines"),
            ),
        ] {
            assert_eq!(
                parse_endpoint(bad.as_bytes()).unwrap_err(),
                expected,
                "{bad:?}"
            );
        }
        assert_eq!(
            read_endpoint(Path::new("/nonexistent/endpoint")).unwrap_err(),
            EndpointError::Missing
        );
    }

    #[test]
    fn the_path_is_under_application_support() {
        assert_eq!(
            endpoint_path_in(Path::new("/Users/u")),
            PathBuf::from("/Users/u/Library/Application Support/ShellX/term/endpoint")
        );
    }
}
