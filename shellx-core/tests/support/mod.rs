//! Shared helpers for the integration tests: a `Core` configured against an
//! in-process `FakeApi` with its own owner-only state dir.
#![allow(dead_code)]

use serde_json::{Value, json};
use shellx_core::Core;
use shellx_fake_api::{FakeApi, FakeOptions, Recorded};
use std::ops::Deref;
use std::path::{Path, PathBuf};
use tempfile::TempDir;

/// The core's `state_dir`; keeps the temp dir alive. Derefs to the state dir path.
pub struct Dir {
    _tmp: TempDir,
    path: PathBuf,
}

impl Deref for Dir {
    type Target = Path;
    fn deref(&self) -> &Path {
        &self.path
    }
}

pub fn state_dir() -> Dir {
    let tmp = tempfile::tempdir().unwrap();
    let path = tmp.path().join("core");
    Dir { _tmp: tmp, path }
}

pub fn fake() -> FakeApi {
    FakeApi::start(FakeOptions::default())
}

/// `config.set` with `api_base` + `state_dir`, merged with `extra`.
pub fn configure(core: &Core, api_base: &str, dir: &Path, extra: Value) {
    let mut p = json!({"api_base": api_base, "state_dir": dir.to_str().unwrap()});
    for (k, v) in extra.as_object().cloned().unwrap_or_default() {
        p[k] = v;
    }
    core.call("config.set", p).unwrap();
}

pub fn logged_out() -> (Core, FakeApi, Dir) {
    logged_out_with(json!({}))
}

pub fn logged_out_with(extra: Value) -> (Core, FakeApi, Dir) {
    let fake = fake();
    let dir = state_dir();
    let core = Core::new();
    configure(&core, &fake.base_url, &dir, extra);
    (core, fake, dir)
}

pub fn logged_in() -> (Core, FakeApi, Dir) {
    let (core, fake, dir) = logged_out();
    core.call("auth.login", json!({"email": "a@b.c", "password": "pw"})).unwrap();
    (core, fake, dir)
}

/// Recorded header by name (the fake lowercases header names).
pub fn header<'a>(req: &'a Recorded, name: &str) -> Option<&'a str> {
    req.headers.get(&name.to_ascii_lowercase()).map(String::as_str)
}

pub fn requests_to(fake: &FakeApi, path: &str) -> Vec<Recorded> {
    fake.requests().into_iter().filter(|r| r.path == path).collect()
}

#[cfg(unix)]
pub fn mode(p: impl AsRef<Path>) -> u32 {
    use std::os::unix::fs::MetadataExt;
    std::fs::metadata(p).unwrap().mode() & 0o7777
}

/// config.set extras pointing Google at the fake (`/fake-google/*`) with the fake's client.
pub fn google(fake: &FakeApi) -> Value {
    json!({
        "google_auth_url": format!("{}/fake-google/auth", fake.base_url),
        "google_token_url": format!("{}/fake-google/token", fake.base_url),
        "google_client_id": "fake-desktop-client",
        "google_client_secret": "fake-desktop-secret",
    })
}

/// Like `logged_out`, configured with `google(&fake)`.
pub fn google_logged_out() -> (Core, FakeApi, Dir) {
    let fake = fake();
    let dir = state_dir();
    let core = Core::new();
    configure(&core, &fake.base_url, &dir, google(&fake));
    (core, fake, dir)
}

/// Query of `url` as a map (through `shellx_core::auth_google::parse_query`).
pub fn query(url: &str) -> std::collections::HashMap<String, String> {
    let q = url.split_once('?').map(|(_, q)| q).unwrap_or("");
    shellx_core::auth_google::parse_query(q).into_iter().collect()
}

/// begin -> fake Google in a browser thread -> finish; finish's result.
pub fn google_sign_in(core: &Core, purpose: &str) -> Result<Value, shellx_core::CoreError> {
    let begun = core.call("auth.google.begin", json!({"purpose": purpose}))?;
    let url = begun["auth_url"].as_str().unwrap().to_string();
    let browser = std::thread::spawn(move || shellx_fake_api::browse(&url));
    let done = core.call("auth.google.finish", json!({"flow_id": begun["flow_id"]}));
    let _ = browser.join();
    done
}

/// begin, read the fake's mailbox, finish; finish's result.
pub fn email_sign_in(core: &Core, fake: &FakeApi, email: &str) -> Result<Value, shellx_core::CoreError> {
    let begun = core.call("auth.email.begin", json!({"email": email, "locale": "en"}))?;
    let code = fake.email_code(begun["email"].as_str().unwrap()).expect("the fake mailed a code");
    core.call("auth.email.finish", json!({"challenge_id": begun["challenge_id"], "code": code}))
}
