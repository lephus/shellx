//! How much does the ShellX block slow down opening a terminal window?
//! (spec §1 criterion 5, §13 R3). Uses your real zsh startup files through
//! a temporary ZDOTDIR; nothing in $HOME is modified.
//!
//!     cargo build --release && cargo run --release --example startup_bench
//!
//! SHELLX_BENCH_RUNS (default 20) sets the samples per variant.

use portable_pty::{native_pty_system, CommandBuilder, PtySize};
use std::io::Read;
use std::path::{Path, PathBuf};
use std::sync::mpsc;
use std::time::{Duration, Instant};

const READY: &str = "__SHELLX_READY__";
const BLOCK: &str = include_str!("../shell/block.zsh");
const INSTALLED: &str = "$HOME/Library/Application Support/ShellX/bin/shellx-term";

fn main() {
    let runs: usize = std::env::var("SHELLX_BENCH_RUNS")
        .ok()
        .and_then(|value| value.parse().ok())
        .unwrap_or(20);
    let bin = Path::new(env!("CARGO_MANIFEST_DIR")).join("target/release/shellx-term");
    assert!(bin.exists(), "build first: cargo build --release");
    let home = PathBuf::from(std::env::var_os("HOME").expect("HOME"));
    let root = std::env::temp_dir().join(format!("shellx-bench-{}", std::process::id()));
    assert!(
        BLOCK.contains(INSTALLED),
        "block.zsh no longer contains the installed path"
    );
    let wrapped = BLOCK.replace(INSTALLED, bin.to_str().unwrap());
    assert!(
        wrapped.contains("wrap --login --"),
        "block.zsh has no login branch to measure"
    );
    let nologin = wrapped.replace("wrap --login --", "wrap --");
    assert_ne!(
        nologin, wrapped,
        "the non-login variant must differ from the login one"
    );
    let variants = [
        ("baseline", setup(&root.join("baseline"), &home, "")),
        (
            "wrapped, login inner",
            setup(&root.join("login"), &home, &wrapped),
        ),
        (
            "wrapped, non-login inner",
            setup(
                &root.join("nologin"),
                &home,
                &wrapped.replace("wrap --login --", "wrap --"),
            ),
        ),
    ];

    let mut samples: Vec<Vec<f64>> = vec![Vec::new(); variants.len()];
    for round in 0..runs + 2 {
        for (i, (_, zdotdir)) in variants.iter().enumerate() {
            let ms = time_to_ready(zdotdir);
            if round >= 2 {
                samples[i].push(ms); // the first two rounds only warm caches
            }
        }
    }
    let baseline = median(&samples[0]);
    for (i, (name, _)) in variants.iter().enumerate() {
        let m = median(&samples[i]);
        println!(
            "{name:<26} median {m:7.1} ms   p90 {:7.1} ms   overhead {:+7.1} ms",
            percentile(&samples[i], 0.9),
            m - baseline
        );
    }
    let _ = std::fs::remove_dir_all(&root);
}

/// A ZDOTDIR whose files source the real ones, `block` first in .zshrc, and
/// a marker printed when startup is done.
fn setup(dir: &Path, home: &Path, block: &str) -> PathBuf {
    std::fs::create_dir_all(dir).unwrap();
    for name in [".zshenv", ".zprofile", ".zlogin"] {
        let real = home.join(name);
        std::fs::write(
            dir.join(name),
            format!("[[ -f '{0}' ]] && source '{0}'\n", real.display()),
        )
        .unwrap();
    }
    let real_rc = home.join(".zshrc");
    let rc = format!(
        "{block}[[ -f '{0}' ]] && source '{0}'\nprint -r -- {READY}\n",
        real_rc.display()
    );
    std::fs::write(dir.join(".zshrc"), rc).unwrap();
    dir.to_path_buf()
}

/// Milliseconds from starting a login zsh in a new PTY to the marker.
fn time_to_ready(zdotdir: &Path) -> f64 {
    let pair = native_pty_system()
        .openpty(PtySize {
            rows: 40,
            cols: 120,
            pixel_width: 0,
            pixel_height: 0,
        })
        .unwrap();
    let mut cmd = CommandBuilder::new("/bin/zsh");
    cmd.arg("-l");
    cmd.env("ZDOTDIR", zdotdir);
    for name in ["SHELLX_TERM", "SHELLX", "TMUX", "STY"] {
        cmd.env_remove(name);
    }
    let start = Instant::now();
    let mut child = pair.slave.spawn_command(cmd).unwrap();
    drop(pair.slave);
    let mut reader = pair.master.try_clone_reader().unwrap();
    let (tx, rx) = mpsc::channel();
    std::thread::spawn(move || {
        let mut buf = [0u8; 4096];
        let mut seen = Vec::new();
        while let Ok(n) = reader.read(&mut buf) {
            if n == 0 {
                break;
            }
            seen.extend_from_slice(&buf[..n]);
            if String::from_utf8_lossy(&seen).contains(READY) {
                let _ = tx.send(());
                break;
            }
        }
    });
    let ready = rx.recv_timeout(Duration::from_secs(10)).is_ok();
    let ms = start.elapsed().as_secs_f64() * 1000.0;
    // Closing our end first lets the shell's tty drain and exit; waiting with
    // the master still open stalls for minutes.
    drop(pair.master);
    let _ = child.kill();
    let _ = child.wait();
    assert!(
        ready,
        "no ready marker within 10 s for {}",
        zdotdir.display()
    );
    ms
}

fn median(values: &[f64]) -> f64 {
    percentile(values, 0.5)
}

fn percentile(values: &[f64], p: f64) -> f64 {
    let mut sorted = values.to_vec();
    sorted.sort_by(|a, b| a.partial_cmp(b).unwrap());
    sorted[((sorted.len() - 1) as f64 * p).round() as usize]
}
