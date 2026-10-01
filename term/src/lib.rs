//! `shellx-term` as a library. The binary (`src/main.rs`) is a thin
//! wrapper; integration tests use the protocol modules to play the ShellX
//! agent's side of the local link.
//! Spec: docs/superpowers/specs/2026-10-01-desktop-terminal-sharing-design.md

pub mod cli;
#[cfg(unix)]
pub mod fallback;
#[cfg(unix)]
pub mod faults;
pub mod outbox;
pub mod proto;
pub mod ring;
#[cfg(unix)]
pub mod tty;
#[cfg(unix)]
pub mod wrap;
