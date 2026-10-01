#![cfg(all(windows, feature = "test-hooks"))]
//! shellx-term.exe in a real ConPTY "window" (spec §11.1, §12).

mod common;

use common::fake_agent::{Behavior, FakeAgent};
use common::{Harness, BIN};
use shellx_term::proto::messages::{AgentMsg, TermMsg};
use std::path::Path;
use std::time::{Duration, Instant};

const T: Duration = Duration::from_secs(30);
const CMD: &str = r"C:\Windows\System32\cmd.exe";
const PWSH: &str = r"C:\Program Files\PowerShell\7\pwsh.exe";
const POWERSHELL: &str = r"C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe";

/// A window whose LOCALAPPDATA is `dir` (endpoint and installed binary live there).
fn spawn(program: &str, args: &[&str], dir: &Path, extra: &[(&str, &str)]) -> Harness {
    let base = dir.to_str().unwrap().to_string();
    let mut env: Vec<(&str, &str)> = vec![
        ("LOCALAPPDATA", base.as_str()),
        ("SHELLX_TERM_TIMING", "fast"),
    ];
    env.extend_from_slice(extra);
    Harness::spawn(program, args, &env, 100, 30)
}

fn wrapped_cmd(dir: &Path) -> Harness {
    spawn(BIN, &["wrap", "--", CMD, "/d"], dir, &[])
}

fn wrapped_pwsh(dir: &Path) -> Harness {
    spawn(
        BIN,
        &["wrap", "--", PWSH, "-NoLogo", "-NoProfile"],
        dir,
        &[],
    )
}

#[test]
fn cmd_runs_inside_and_its_exit_code_comes_back() {
    let dir = common::temp_dir("win-cmd");
    let mut h = wrapped_cmd(&dir);
    h.send("set /a 6*7+1000\r");
    h.expect("1042", T);
    h.send("exit 7\r");
    assert_eq!(h.wait_exit(T), 7);
}

#[test]
fn the_inner_shell_carries_the_conpty_marker() {
    let dir = common::temp_dir("win-marker");
    let mut h = wrapped_cmd(&dir);
    h.send("echo [%SHELLX_TERM%]\r");
    h.expect("[conpty:", T);
    h.send("exit 0\r");
    h.wait_exit(T);
}

#[test]
fn arrow_keys_reach_the_inner_shell() {
    let dir = common::temp_dir("win-arrows");
    let mut h = wrapped_cmd(&dir);
    h.send("set /a 6*7+1000\r");
    h.expect("1042", T);
    h.send("\x1b[A\r"); // Up: cmd recalls the last command
    h.expect("1042", T); // `expect` only searches output that arrived since
    h.send("exit 0\r");
    h.wait_exit(T);
}

#[test]
fn ctrl_c_stops_the_running_command() {
    let dir = common::temp_dir("win-ctrlc");
    let mut h = wrapped_cmd(&dir);
    h.send("ping -n 60 127.0.0.1\r");
    std::thread::sleep(Duration::from_millis(1500));
    h.send_bytes(b"\x03");
    h.send("set /a 5*5+1000\r");
    h.expect("1025", T);
    h.send("exit 0\r");
    h.wait_exit(T);
}

#[test]
fn resizing_the_window_resizes_the_shell() {
    let dir = common::temp_dir("win-resize");
    let mut h = wrapped_pwsh(&dir);
    h.send("$Host.UI.RawUI.WindowSize.Width + 1000\r");
    h.expect("1100", T);
    h.resize(120, 40);
    std::thread::sleep(Duration::from_millis(500));
    h.send("$Host.UI.RawUI.WindowSize.Width + 1000\r");
    h.expect("1120", T);
    h.send("exit 0\r");
    h.wait_exit(T);
}

#[test]
fn vietnamese_and_emoji_output_arrive_intact() {
    let dir = common::temp_dir("win-utf-out");
    let mut h = wrapped_pwsh(&dir);
    h.send("'[' + 'ti' + [char]0x1EBF + 'ng' + [char]::ConvertFromUtf32(0x1F600) + ']'\r");
    h.expect("[tiếng😀]", T);
    h.send("exit 0\r");
    h.wait_exit(T);
}

#[test]
fn typed_vietnamese_reaches_the_shell() {
    let dir = common::temp_dir("win-utf-in");
    let mut h = wrapped_pwsh(&dir);
    h.send("'L=' + 'Việt'.Length + ',' + [int][char]'ệ'\r");
    h.expect("L=4,7879", T);
    h.send("exit 0\r");
    h.wait_exit(T);
}

#[test]
fn a_fault_or_a_crash_exits_222() {
    for fault in ["openpty", "spawn", "panic"] {
        let dir = common::temp_dir(&format!("win-222-{fault}"));
        let mut h = spawn(
            BIN,
            &["wrap", "--", CMD, "/d"],
            &dir,
            &[("SHELLX_TERM_FAULT", fault)],
        );
        assert_eq!(h.wait_exit(T), 222, "{fault}: {:?}", h.text());
    }
}

#[test]
fn the_phone_sees_output_and_types_through_the_agent_link() {
    let dir = common::temp_dir("win-link");
    let mut h = wrapped_cmd(&dir);
    h.send("set /a 6*7+1000\r");
    h.expect("1042", T);
    let agent = FakeAgent::start(&dir, Behavior::Normal);
    let mut s = agent.next_session(T);
    assert!(String::from_utf8_lossy(&s.snapshot(T)).contains("1042"));
    assert_eq!(s.info.shell, "cmd");
    assert_eq!(s.info.app, ""); // the harness clears WT_SESSION
    s.send(&AgentMsg::In {
        data: b"set /a 7*9+1000\r".to_vec(),
    });
    h.expect("1063", T);
    s.expect_out("1063", T);
    h.send("exit 3\r");
    assert_eq!(h.wait_exit(T), 3);
    assert_eq!(
        s.expect_msg(|m| matches!(m, TermMsg::Exit { .. }), T),
        TermMsg::Exit { code: 3 }
    );
}

#[test]
fn killing_shellx_term_ends_the_inner_shell() {
    let dir = common::temp_dir("win-kill");
    let mut h = wrapped_pwsh(&dir);
    h.send("'PID=' + $PID\r");
    let inner = h.wait_number_after("PID=", T);
    h.send("ping -n 300 127.0.0.1\r");
    std::thread::sleep(Duration::from_millis(1500));
    // Only shellx-term.exe, as when its window is torn down; not the tree.
    let status = std::process::Command::new("taskkill")
        .args(["/PID", &h.pid().to_string(), "/F"])
        .status()
        .unwrap();
    assert!(status.success());
    h.wait_exit(T);
    let until = Instant::now() + Duration::from_secs(15);
    loop {
        let out = std::process::Command::new("tasklist")
            .args(["/FI", &format!("PID eq {inner}"), "/NH"])
            .output()
            .unwrap();
        if !String::from_utf8_lossy(&out.stdout).contains(&inner.to_string()) {
            break;
        }
        assert!(
            Instant::now() < until,
            "inner shell {inner} outlived shellx-term"
        );
        std::thread::sleep(Duration::from_millis(200));
    }
}

/// `dir\ShellX\bin\shellx-term.exe`: the real binary, or `bytes`.
fn install(dir: &Path, bytes: Option<&[u8]>) {
    let bin = dir.join(r"ShellX\bin");
    std::fs::create_dir_all(&bin).unwrap();
    let exe = bin.join("shellx-term.exe");
    match bytes {
        Some(bytes) => std::fs::write(exe, bytes).unwrap(),
        None => {
            std::fs::copy(BIN, exe).unwrap();
        }
    }
}

const BLOCK: &str = concat!(env!("CARGO_MANIFEST_DIR"), r"\shell\block.ps1");

/// A PowerShell window whose first command dot-sources the block, then
/// prints AFTER-BLOCK (typed in two halves, so only output matches).
fn shell_with_block(program: &str, dir: &Path, extra: &[(&str, &str)]) -> Harness {
    let mut h = spawn(program, &["-NoLogo", "-NoProfile"], dir, extra);
    h.send(&format!(". '{BLOCK}'; 'AFTER' + '-BLOCK'\r"));
    h
}

#[test]
fn the_block_wraps_and_the_inner_exit_code_closes_the_window() {
    for program in [PWSH, POWERSHELL] {
        let dir = common::temp_dir("win-block");
        install(&dir, None);
        let mut h = shell_with_block(program, &dir, &[]);
        h.send("'[' + $env:SHELLX_TERM + ']'\r");
        h.expect("[conpty:", T);
        h.send("exit 5\r");
        assert_eq!(h.wait_exit(T), 5, "{program}: {:?}", h.text());
    }
}

#[test]
fn a_corrupt_binary_leaves_the_window_working() {
    let dir = common::temp_dir("win-corrupt");
    install(&dir, Some(b"MZ this is not a real executable"));
    let mut h = shell_with_block(PWSH, &dir, &[]);
    h.expect("AFTER-BLOCK", T);
    h.send("6*7+1000\r");
    h.expect("1042", T);
    h.send("exit 0\r");
    assert_eq!(h.wait_exit(T), 0);
}

#[test]
fn could_not_wrap_carries_on_in_the_outer_shell() {
    let dir = common::temp_dir("win-carry-on");
    install(&dir, None);
    let mut h = shell_with_block(PWSH, &dir, &[("SHELLX_TERM_FAULT", "spawn")]);
    h.expect("AFTER-BLOCK", T);
    h.send("'[' + $env:SHELLX_TERM + '|' + $LASTEXITCODE + ']'\r");
    h.expect("[|]", T);
    h.send("exit 0\r");
    assert_eq!(h.wait_exit(T), 0);
}

#[test]
fn a_dot_source_after_a_command_does_not_wrap() {
    let dir = common::temp_dir("win-manual");
    install(&dir, None);
    let mut h = spawn(PWSH, &["-NoLogo", "-NoProfile"], &dir, &[]);
    h.send("6*7+1000\r");
    h.expect("1042", T);
    h.send(&format!(". '{BLOCK}'; '[' + $env:SHELLX_TERM + ']'\r"));
    h.expect("[]", T);
    h.send("exit 0\r");
    h.wait_exit(T);
}

#[test]
fn a_command_line_start_is_not_wrapped() {
    let dir = common::temp_dir("win-cmdline");
    install(&dir, None);
    let script = format!(". '{BLOCK}'; '[' + $env:SHELLX_TERM + ']'");
    let mut h = spawn(
        PWSH,
        &["-NoLogo", "-NoProfile", "-Command", &script],
        &dir,
        &[],
    );
    h.expect("[]", T);
    assert_eq!(h.wait_exit(T), 0);
}
