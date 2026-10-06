//! `shellx` — the ShellX command line (A7 spec:
//! docs/superpowers/specs/2026-10-07-desktop-cli-a7-design.md). Talks to the
//! ShellX window (or the A5b daemon) over the local mux socket. Separate
//! from `proto`, which is the terminal-sharing link and must not change.

pub mod client;
pub mod endpoint;
pub mod value;
pub mod wire;
