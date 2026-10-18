//! `--smoke`: headless check of the same Session the window uses. Starts an
//! interactive PowerShell on ConPTY, types a command through the same input
//! path as the window (committed text + libghostty-vt-encoded Enter), waits
//! for the computed result in the libghostty-vt grid, resizes, and exits.
//! Exit code 0 = pass. No window is opened.
//!
//! Then the pane checks: a `Tabs` model with two splits and a second tab,
//! one real shell per pane through `workspace::PaneHost` (the window's code
//! path), closed in an order that walks PaneClosed (shell `exit`, then the
//! Ctrl+Shift+W path) -> TabClosed -> Respawned. After every step the live
//! shells must equal the model's panes, and every dropped pane's shell must
//! have exited within 5 s.
//!
//! `--smoke-ui-assets` (also run first by `--smoke`): every icon the window
//! loads is embedded and is an SVG, and every shell string exists in vi + en.

use std::sync::mpsc;
use std::time::{Duration, Instant};

use anyhow::{Context as _, Result, bail, ensure};
use shellx_model::layout::{Axis, PaneId};
use shellx_model::tabs::{CloseOutcome, PaneTarget, Tabs};

use crate::fonts;
use crate::icons::{self, Icon};
use crate::local_pty::{ExitProbe, LocalPty, default_shell, spawn_reader};
use crate::shell_info::SHELL_STRINGS;
use crate::term_core::{PtyLink, TermCore, rgb};
use crate::workspace::{PaneHost, model_panes, spawn_local_pane};
use shellx_model::palette::TERM_BG;
use shellx_model::strings::{Lang, t};

const TIMEOUT: Duration = Duration::from_secs(45);
/// A dropped pane's shell must be gone within this.
const EXIT_TIMEOUT: Duration = Duration::from_secs(5);

struct Pump {
    rx: mpsc::Receiver<Vec<u8>>,
    closed: bool,
}

impl Pump {
    /// Feed output until `done(lines)` holds or the deadline passes.
    fn until(
        &mut self,
        session: &mut TermCore,
        what: &str,
        mut done: impl FnMut(&[String]) -> bool,
    ) -> Result<Vec<String>> {
        let deadline = Instant::now() + TIMEOUT;
        loop {
            let lines = session.text_lines()?;
            if done(&lines) {
                return Ok(lines);
            }
            if Instant::now() > deadline {
                dump(&lines);
                bail!("timed out waiting for {what}");
            }
            if self.closed {
                std::thread::sleep(Duration::from_millis(100));
                continue;
            }
            match self.rx.recv_timeout(Duration::from_millis(100)) {
                Ok(bytes) => {
                    session.feed(&bytes);
                    while let Ok(more) = self.rx.try_recv() {
                        session.feed(&more);
                    }
                }
                Err(mpsc::RecvTimeoutError::Timeout) => {}
                Err(mpsc::RecvTimeoutError::Disconnected) => self.closed = true,
            }
        }
    }
}

fn dump(lines: &[String]) {
    eprintln!("---- grid ----");
    for line in lines.iter().filter(|l| !l.is_empty()) {
        eprintln!("{line}");
    }
    eprintln!("--------------");
}

fn contains(lines: &[String], needle: &str) -> bool {
    lines.iter().any(|line| line.contains(needle))
}

fn has_prompt(lines: &[String]) -> bool {
    lines
        .iter()
        .any(|l| l.trim_end().ends_with('>') || l.contains("PS "))
}

/// `-NoProfile` keeps the runner's profile out of the results.
fn smoke_shell_args(program: &str) -> Vec<&'static str> {
    if program.to_ascii_lowercase().contains("powershell") || program.contains("pwsh") {
        vec!["-NoProfile"]
    } else {
        Vec::new()
    }
}

/// Cross-platform, no GPUI: the icon table and the shell strings.
pub fn ui_assets() -> Result<()> {
    for icon in Icon::ALL {
        let Some(bytes) = icons::by_path(icon.path()) else {
            bail!("{icon:?}: {} is not embedded", icon.path());
        };
        ensure!(
            icons::looks_like_svg(bytes),
            "{icon:?}: {} is not an SVG with a viewBox",
            icon.path()
        );
    }
    for lang in [Lang::Vi, Lang::En] {
        for s in SHELL_STRINGS {
            ensure!(!t(lang, *s).trim().is_empty(), "{s:?} is empty in {lang:?}");
        }
    }
    println!(
        "smoke-ui-assets: {} icons, {} strings x 2 languages",
        Icon::ALL.len(),
        SHELL_STRINGS.len()
    );
    println!("smoke-ui-assets: PASS");
    Ok(())
}

pub fn run() -> Result<()> {
    ui_assets()?;
    let started = Instant::now();
    let (program, args) = default_shell();
    let mut full_args = args.clone();
    full_args.extend(smoke_shell_args(&program));
    let (link, reader) = LocalPty::spawn(&program, &full_args, 100, 30)?;
    let mut session = TermCore::new(link.clone(), 100, 30)?;
    let (tx, rx) = mpsc::channel();
    spawn_reader(reader, move |bytes| tx.send(bytes).is_ok());
    let mut pump = Pump { rx, closed: false };

    // 0. Palette and embedded fonts.
    ensure!(
        session.frame()?.default_colors.0 == rgb(TERM_BG),
        "default background is not TERM_BG"
    );
    let embedded = fonts::embedded();
    ensure!(embedded.len() == 5, "expected 5 embedded fonts");
    ensure!(
        embedded.iter().all(|f| fonts::has_font_magic(f)),
        "an embedded font lacks a TrueType/OpenType header"
    );
    println!("smoke: palette and fonts ok");

    // 1. Key encoding through libghostty-vt (what the window sends).
    ensure!(
        session.encode_chord("enter").as_deref() == Some(b"\r".as_slice()),
        "enter != CR"
    );
    ensure!(
        session.encode_chord("ctrl+c").as_deref() == Some(b"\x03".as_slice()),
        "ctrl+c"
    );
    ensure!(
        session.encode_chord("backspace").as_deref() == Some(b"\x7f".as_slice()),
        "bs"
    );
    ensure!(
        session.encode_chord("up").is_some(),
        "up arrow not encodable"
    );
    println!("smoke: key encoding ok");

    // 2. Shell prompt reaches the grid.
    pump.until(&mut session, "the PowerShell prompt", |lines| {
        lines
            .iter()
            .any(|l| l.trim_end().ends_with('>') || l.contains("PS "))
    })?;
    println!("smoke: prompt after {:?}", started.elapsed());

    // 3. Type a command the way the window does and read the result back.
    //    The marker is computed by the shell, so finding it proves the
    //    command ran (the typed text alone never contains it).
    session.send_text("Write-Output ('shellx-ok-' + (6*7))");
    ensure!(session.send_chord("enter"), "enter not sent");
    pump.until(&mut session, "shellx-ok-42", |lines| {
        contains(lines, "shellx-ok-42")
    })?;
    println!(
        "smoke: echo ok (shellx-ok-42 in grid) after {:?}",
        started.elapsed()
    );

    // 4. Vietnamese committed text round-trips through ConPTY into the grid
    //    (what an IME commit sends). Informational: a miss is a warning.
    session.send_text("Write-Output 'ti\u{1ebf}ng Vi\u{1ec7}t'");
    session.send_chord("enter");
    match pump.until(&mut session, "Vietnamese text", |lines| {
        lines
            .iter()
            .filter(|l| l.contains("ti\u{1ebf}ng Vi\u{1ec7}t"))
            .count()
            >= 2
    }) {
        Ok(_) => println!("smoke: unicode ok (tiếng Việt echoed by the shell)"),
        Err(e) => println!("smoke: WARN unicode round-trip: {e:#}"),
    }

    // 5. Resize VT grid + pseudoconsole, then confirm the shell sees it.
    session.resize(120, 40, 8, 16)?;
    ensure!(
        session.vt_cols_rows() == (120, 40),
        "VT grid did not resize"
    );
    session.send_text("Write-Output ('cols-' + $Host.UI.RawUI.WindowSize.Width)");
    session.send_chord("enter");
    match pump.until(&mut session, "cols-120", |lines| {
        contains(lines, "cols-120")
    }) {
        Ok(_) => println!("smoke: resize ok (shell reports 120 columns)"),
        Err(e) => println!("smoke: WARN resize not seen by shell: {e:#}"),
    }

    let lines = session.text_lines()?;
    dump(&lines);
    session.send_text("exit");
    session.send_chord("enter");
    let deadline = Instant::now() + Duration::from_secs(5);
    while !link.is_closed() && Instant::now() < deadline {
        std::thread::sleep(Duration::from_millis(100));
    }
    drop(session);
    drop(link);

    panes()?;
    println!("smoke: PASS in {:?}", started.elapsed());
    Ok(())
}

/// One pane's shell in the smoke: what `TermView` holds in the window.
/// Field order matters: the link drops (killing the shell) before `rx`, so
/// the reader thread keeps draining while the pseudoconsole closes.
struct ShellPane {
    core: TermCore,
    link: std::sync::Arc<LocalPty>,
    probe: ExitProbe,
    rx: mpsc::Receiver<Vec<u8>>,
}

impl ShellPane {
    fn spawn(_pane: PaneId, _target: &PaneTarget) -> Result<ShellPane> {
        let (program, _) = default_shell();
        let started = spawn_local_pane(80, 24, &smoke_shell_args(&program))?;
        let (tx, rx) = mpsc::channel();
        spawn_reader(started.reader, move |bytes| tx.send(bytes).is_ok());
        Ok(ShellPane {
            probe: started.link.exit_probe(),
            core: started.core,
            link: started.link,
            rx,
        })
    }

    /// Feed pending output (the grid answers ConPTY's startup queries).
    fn pump(&mut self) {
        while let Ok(bytes) = self.rx.try_recv() {
            self.core.feed(&bytes);
        }
    }
}

type Host = PaneHost<ShellPane>;

fn pump_all(host: &mut Host) {
    for (_, pane) in host.iter_mut() {
        pane.pump();
    }
}

/// Pump every pane until `done(host)` holds or `TIMEOUT` passes.
fn wait_for(host: &mut Host, what: &str, mut done: impl FnMut(&mut Host) -> bool) -> Result<()> {
    let deadline = Instant::now() + TIMEOUT;
    loop {
        pump_all(host);
        if done(host) {
            return Ok(());
        }
        if Instant::now() > deadline {
            bail!("timed out waiting for {what}");
        }
        std::thread::sleep(Duration::from_millis(100));
    }
}

fn wait_prompt(host: &mut Host, pane: PaneId) -> Result<()> {
    wait_for(host, &format!("the prompt of {pane:?}"), |host| {
        host.get_mut(pane)
            .and_then(|p| p.core.text_lines().ok())
            .is_some_and(|lines| has_prompt(&lines))
    })
}

/// Reconcile the host with the model like the window does, check the live
/// shells, then drop the removed panes and wait for their shells to exit.
fn sync(host: &mut Host, tabs: &Tabs, step: &str) -> Result<(Vec<PaneId>, Vec<PaneId>)> {
    let changed = host
        .reconcile(tabs, ShellPane::spawn)
        .with_context(|| format!("{step}: starting a pane shell"))?;
    let removed_ids: Vec<PaneId> = changed.removed.iter().map(|(p, _)| *p).collect();
    let probes: Vec<(PaneId, ExitProbe)> = changed
        .removed
        .iter()
        .map(|(p, pane)| (*p, pane.probe.clone()))
        .collect();
    drop(changed.removed);
    let deadline = Instant::now() + EXIT_TIMEOUT;
    loop {
        pump_all(host);
        let alive: Vec<PaneId> = probes
            .iter()
            .filter(|(_, probe)| !probe.exited())
            .map(|(p, _)| *p)
            .collect();
        if alive.is_empty() {
            break;
        }
        ensure!(
            Instant::now() < deadline,
            "{step}: shells of dropped panes {alive:?} still running after {EXIT_TIMEOUT:?}"
        );
        std::thread::sleep(Duration::from_millis(100));
    }
    ensure!(
        host.ids() == model_panes(tabs),
        "{step}: live shells {:?} != model panes {:?}",
        host.ids(),
        model_panes(tabs)
    );
    for pane in host.ids() {
        let closed = host.get(pane).is_some_and(|p| p.link.is_closed());
        ensure!(!closed, "{step}: the shell of {pane:?} is not running");
    }
    println!(
        "smoke: panes {step}: live {:?}, added {:?}, removed {removed_ids:?} (exited)",
        host.ids(),
        changed.added
    );
    Ok((changed.added, removed_ids))
}

pub fn panes() -> Result<()> {
    let started = Instant::now();
    let mut host = Host::new();

    // Tab 1: p1 | (p2 over p3); tab 2: p4. Four real shells.
    let (mut tabs, p1) = Tabs::new();
    let t1 = tabs.active().id;
    let p2 = tabs.split_focused(Axis::Row, PaneTarget::Local);
    let p3 = tabs.split_focused(Axis::Column, PaneTarget::Local);
    let (t2, p4) = tabs.new_tab(PaneTarget::Local);
    let (added, _) = sync(&mut host, &tabs, "open")?;
    ensure!(added == vec![p1, p2, p3, p4], "open: added {added:?}");

    // The shell in p2 exits by itself (`exit`): the window's poll sees
    // is_closed() and closes the pane; its sibling p3 takes the space.
    wait_prompt(&mut host, p2)?;
    {
        let pane = host.get_mut(p2).expect("p2 is live");
        pane.core.send_text("exit");
        ensure!(pane.core.send_chord("enter"), "enter not sent");
    }
    wait_for(&mut host, "p2's shell to exit", |host| {
        host.get(p2).is_some_and(|p| p.link.is_closed())
    })?;
    let out = tabs.close_pane(p2);
    ensure!(
        out == CloseOutcome::PaneClosed { tab: t1, focus: p3 },
        "exit p2: {out:?}"
    );
    let (_, removed) = sync(&mut host, &tabs, "shell exit -> PaneClosed")?;
    ensure!(removed == vec![p2], "exit p2 removed {removed:?}");

    // Ctrl+Shift+W on tab 1's focused pane (p3): focus moves to p1.
    ensure!(tabs.select(t1), "select tab 1");
    let focused = tabs.active().focused;
    ensure!(focused == p3, "tab 1 focus is {focused:?}, expected p3");
    let out = tabs.close_pane(focused);
    ensure!(
        out == CloseOutcome::PaneClosed { tab: t1, focus: p1 },
        "close p3: {out:?}"
    );
    sync(&mut host, &tabs, "Ctrl+Shift+W -> PaneClosed")?;

    // The last pane of tab 1 closes: the tab goes, tab 2 becomes active.
    let out = tabs.close_pane(p1);
    ensure!(
        out == CloseOutcome::TabClosed {
            closed: t1,
            active: t2
        },
        "close p1: {out:?}"
    );
    sync(&mut host, &tabs, "last pane of a tab -> TabClosed")?;

    // The last pane of the last tab closes: a fresh local tab appears.
    let CloseOutcome::Respawned { pane: p5, .. } = tabs.close_pane(p4) else {
        bail!("closing the last pane did not respawn");
    };
    let (added, removed) = sync(&mut host, &tabs, "last pane of last tab -> Respawned")?;
    ensure!(
        added == vec![p5] && removed == vec![p4],
        "respawn: added {added:?}, removed {removed:?}"
    );
    wait_prompt(&mut host, p5)?;
    println!("smoke: panes respawned shell {p5:?} shows a prompt");

    // Window close: dropping the host ends every shell.
    let probes: Vec<ExitProbe> = host
        .ids()
        .iter()
        .filter_map(|p| host.get(*p))
        .map(|p| p.probe.clone())
        .collect();
    drop(host);
    let deadline = Instant::now() + EXIT_TIMEOUT;
    while probes.iter().any(|probe| !probe.exited()) {
        ensure!(
            Instant::now() < deadline,
            "shells still running after the host was dropped"
        );
        std::thread::sleep(Duration::from_millis(100));
    }
    println!("smoke: panes ok in {:?}", started.elapsed());
    Ok(())
}
