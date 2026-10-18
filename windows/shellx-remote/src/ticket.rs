//! Relay connect tickets from the caller's minting callback.
//!
//! `cmux-remote` queries a `RelayCredentialSource` before every relay
//! WebSocket (the control socket and each of the ~3 circuits of one
//! connect, and again on every reconnect). One mint covers the whole burst:
//! a ticket is reused for at most `REUSE_WINDOW`, far inside the server's
//! 120 s ticket lifetime, so each (re)connect asks the callback once.

use std::path::Path;
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

use anyhow::{Context, anyhow};
use cmux_remote::provider::RelayCredentialSource;
use zeroize::Zeroizing;

pub(crate) type TicketFn = Arc<dyn Fn() -> anyhow::Result<std::path::PathBuf> + Send + Sync>;

const REUSE_WINDOW: Duration = Duration::from_secs(30);
const MAX_TICKET_BYTES: usize = 4096;

#[derive(Default)]
struct Cache {
    ticket: Option<(Zeroizing<String>, Instant)>,
    /// Last mint/read failure; upstream drops callback errors on purpose
    /// (no secrets in transport errors), this keeps a credential-free reason.
    last_error: Option<String>,
}

#[derive(Clone)]
pub(crate) struct TicketSource {
    mint: TicketFn,
    cache: Arc<Mutex<Cache>>,
}

impl TicketSource {
    pub(crate) fn new(mint: TicketFn) -> Self {
        Self {
            mint,
            cache: Arc::default(),
        }
    }

    pub(crate) fn credential_source(&self) -> RelayCredentialSource {
        let source = self.clone();
        RelayCredentialSource::callback(move || {
            let source = source.clone();
            async move {
                tokio::task::spawn_blocking(move || source.fetch())
                    .await
                    .map_err(|_| ())?
                    .map(|ticket| ticket.to_string())
                    .map_err(|_| ())
            }
        })
    }

    pub(crate) fn last_error(&self) -> Option<String> {
        self.cache
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .last_error
            .clone()
    }

    fn fetch(&self) -> anyhow::Result<Zeroizing<String>> {
        let mut cache = self.cache.lock().unwrap_or_else(|e| e.into_inner());
        if let Some((ticket, minted)) = &cache.ticket
            && minted.elapsed() < REUSE_WINDOW
        {
            return Ok(ticket.clone());
        }
        let result = (self.mint)().and_then(|path| {
            let ticket = read_ticket_file(&path);
            // The file is a one-use hand-off from the minter; do not leave a
            // live credential on disk.
            let _ = std::fs::remove_file(&path);
            ticket
        });
        match result {
            Ok(ticket) => {
                cache.ticket = Some((ticket.clone(), Instant::now()));
                cache.last_error = None;
                Ok(ticket)
            }
            Err(error) => {
                cache.ticket = None;
                cache.last_error = Some(format!("{error:#}"));
                Err(error)
            }
        }
    }
}

/// Read one ticket file. Unix keeps `cmux-remote`'s owner-only check
/// (owner, mode 0600, no symlink). Windows: plain read of a file the
/// caller wrote under its per-user state dir (NEEDS SECURITY REVIEW).
fn read_ticket_file(path: &Path) -> anyhow::Result<Zeroizing<String>> {
    #[cfg(unix)]
    let text = cmux_remote::secret_file::read_owner_only_string(path, MAX_TICKET_BYTES)
        .with_context(|| format!("could not read the connect ticket {}", path.display()))?;
    #[cfg(not(unix))]
    let text = {
        let bytes =
            Zeroizing::new(std::fs::read(path).with_context(|| {
                format!("could not read the connect ticket {}", path.display())
            })?);
        if bytes.len() > MAX_TICKET_BYTES {
            return Err(anyhow!(
                "connect ticket is larger than {MAX_TICKET_BYTES} bytes"
            ));
        }
        Zeroizing::new(
            std::str::from_utf8(&bytes)
                .context("connect ticket is not UTF-8")?
                .to_owned(),
        )
    };
    let trimmed = text.trim();
    if trimmed.is_empty() {
        return Err(anyhow!("connect ticket file is empty"));
    }
    Ok(Zeroizing::new(trimmed.to_owned()))
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::atomic::{AtomicUsize, Ordering};

    fn write_ticket(path: &Path, text: &str) {
        let mut options = std::fs::OpenOptions::new();
        options.write(true).create(true).truncate(true);
        #[cfg(unix)]
        {
            use std::os::unix::fs::OpenOptionsExt;
            options.mode(0o600);
        }
        use std::io::Write;
        options
            .open(path)
            .unwrap()
            .write_all(text.as_bytes())
            .unwrap();
    }

    #[test]
    fn one_mint_serves_a_burst_and_the_file_is_removed() {
        let dir = std::env::temp_dir().join(format!("shellx-ticket-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let mints = Arc::new(AtomicUsize::new(0));
        let mint: TicketFn = {
            let dir = dir.clone();
            let mints = mints.clone();
            Arc::new(move || {
                let n = mints.fetch_add(1, Ordering::SeqCst);
                let path = dir.join(format!("t{n}"));
                write_ticket(&path, &format!("v2.ticket-{n}\n"));
                Ok(path)
            })
        };
        let source = TicketSource::new(mint);
        assert_eq!(&*source.fetch().unwrap(), "v2.ticket-0");
        assert_eq!(&*source.fetch().unwrap(), "v2.ticket-0");
        assert_eq!(mints.load(Ordering::SeqCst), 1);
        assert!(!dir.join("t0").exists());
        std::fs::remove_dir_all(&dir).unwrap();
    }

    #[test]
    fn mint_failures_are_remembered_without_the_ticket() {
        let source = TicketSource::new(Arc::new(|| Err(anyhow!("account token expired"))));
        assert!(source.fetch().is_err());
        assert_eq!(
            source.last_error().as_deref(),
            Some("account token expired")
        );
    }

    #[cfg(unix)]
    #[test]
    fn unix_rejects_a_world_readable_ticket() {
        use std::os::unix::fs::PermissionsExt;
        let path = std::env::temp_dir().join(format!("shellx-ticket-mode-{}", std::process::id()));
        write_ticket(&path, "v2.x");
        std::fs::set_permissions(&path, std::fs::Permissions::from_mode(0o644)).unwrap();
        assert!(read_ticket_file(&path).is_err());
        std::fs::remove_file(&path).unwrap();
    }
}
