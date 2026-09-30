mod common;

use common::{Harness, BIN};
use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::time::Duration;

const T: Duration = Duration::from_secs(5);
const ZSH_BLOCK: &str = include_str!("../shell/block.zsh");
const BASH_BLOCK: &str = include_str!("../shell/block.bash");

/// A fake HOME whose "installed" shellx-term just reports how it was called.
fn home(name: &str) -> PathBuf {
    let home = common::temp_dir(name);
    let bin = home.join("Library/Application Support/ShellX/bin");
    std::fs::create_dir_all(&bin).unwrap();
    let fake = bin.join("shellx-term");
    std::fs::write(&fake, "#!/bin/sh\nprintf 'WRAPPED'\nfor a in \"$@\"; do printf ' [%s]' \"$a\"; done\nprintf '\\n'\nexit 0\n").unwrap();
    std::fs::set_permissions(&fake, std::fs::Permissions::from_mode(0o755)).unwrap();
    std::fs::write(
        home.join(".zshrc"),
        format!("{ZSH_BLOCK}echo AFTER-BLOCK\n"),
    )
    .unwrap();
    std::fs::write(
        home.join(".bashrc"),
        format!("{BASH_BLOCK}echo AFTER-BLOCK\n"),
    )
    .unwrap();
    std::fs::write(
        home.join(".bash_profile"),
        format!("{BASH_BLOCK}echo AFTER-BLOCK\n"),
    )
    .unwrap();
    home
}

fn env_for(home: &Path) -> Vec<(&'static str, String)> {
    let h = home.to_str().unwrap().to_string();
    vec![
        ("HOME", h.clone()),
        ("ZDOTDIR", h),
        ("SHELL", "/bin/zsh".to_string()),
    ]
}

fn run_shell(program: &str, args: &[&str], home: &Path, extra: &[(&str, &str)]) -> Harness {
    let base = env_for(home);
    let mut env: Vec<(&str, &str)> = base.iter().map(|(k, v)| (*k, v.as_str())).collect();
    env.extend_from_slice(extra);
    Harness::spawn(program, args, &env, 80, 24)
}

fn assert_wrapped(program: &str, args: &[&str], expected: &str) {
    let home = home(&format!(
        "wrap-{}-{}",
        program.replace('/', "_"),
        args.join("")
    ));
    let mut h = run_shell(program, args, &home, &[]);
    h.expect(expected, T);
    assert_eq!(h.wait_exit(T), 0);
    assert!(
        !h.text().contains("AFTER-BLOCK"),
        "rest of the file ran: {:?}",
        h.text()
    );
}

fn assert_not_wrapped(program: &str, args: &[&str], extra: &[(&str, &str)], tag: &str) {
    let home = home(&format!("skip-{tag}"));
    let mut h = run_shell(program, args, &home, extra);
    h.expect("AFTER-BLOCK", T);
    assert!(
        !h.text().contains("WRAPPED"),
        "{tag}: wrapped anyway: {:?}",
        h.text()
    );
    h.send("exit\r");
    h.wait_exit(T);
}

#[test]
fn blocks_are_ascii_with_exact_markers() {
    for block in [ZSH_BLOCK, BASH_BLOCK] {
        assert!(block.is_ascii());
        let lines: Vec<&str> = block.lines().collect();
        assert_eq!(lines.first(), Some(&"# >>> ShellX >>>"));
        assert_eq!(lines.last(), Some(&"# <<< ShellX <<<"));
        assert!(block.ends_with('\n'));
    }
}

#[test]
fn zsh_interactive_is_wrapped() {
    assert_wrapped("/bin/zsh", &["-i"], "WRAPPED [wrap] [--] [/bin/zsh]");
}

#[test]
fn zsh_login_is_wrapped_as_login() {
    assert_wrapped(
        "/bin/zsh",
        &["-il"],
        "WRAPPED [wrap] [--login] [--] [/bin/zsh]",
    );
}

#[test]
fn zsh_started_by_bare_name_resolves_to_the_login_shell() {
    // argv[0] is "zsh" (not absolute): the block uses $SHELL.
    assert_wrapped("zsh", &["-i"], "WRAPPED [wrap] [--] [/bin/zsh]");
}

#[test]
fn bash_interactive_is_wrapped() {
    assert_wrapped("/bin/bash", &["-i"], "WRAPPED [wrap] [--] [/bin/bash]");
}

#[test]
fn bash_login_is_wrapped_as_login() {
    assert_wrapped(
        "/bin/bash",
        &["-il"],
        "WRAPPED [wrap] [--login] [--] [/bin/bash]",
    );
}

#[test]
fn editor_environment_probes_are_not_wrapped() {
    for (program, tag) in [("/bin/zsh", "zsh-ilc"), ("/bin/bash", "bash-ilc")] {
        let home = home(tag);
        let mut h = run_shell(program, &["-ilc", "echo pl''ain"], &home, &[]);
        h.expect("plain", T);
        assert_eq!(h.wait_exit(T), 0);
        assert!(!h.text().contains("WRAPPED"), "{tag}: {:?}", h.text());
    }
}

#[test]
fn nested_and_excluded_shells_are_not_wrapped() {
    let cases = [
        ("SHELLX_TERM", "1"),
        ("SHELLX_TERM", "0"),
        ("SHELLX", "1"),
        ("TMUX", "/tmp/tmux-1/default,1,0"),
        ("STY", "1.pts"),
        ("TERM_PROGRAM", "WarpTerminal"),
    ];
    for (i, (name, value)) in cases.into_iter().enumerate() {
        assert_not_wrapped("/bin/zsh", &["-i"], &[(name, value)], &format!("zsh-{i}"));
        assert_not_wrapped("/bin/bash", &["-i"], &[(name, value)], &format!("bash-{i}"));
    }
}

#[test]
fn a_missing_binary_leaves_the_shell_alone() {
    let home = home("missing");
    std::fs::remove_file(home.join("Library/Application Support/ShellX/bin/shellx-term")).unwrap();
    let mut h = run_shell("/bin/zsh", &["-i"], &home, &[]);
    h.expect("AFTER-BLOCK", T);
    h.send("exit\r");
    h.wait_exit(T);
}

#[test]
fn no_terminal_means_no_wrapping() {
    let home = home("no-tty");
    let out = Command::new("/bin/zsh")
        .arg("-i")
        .envs(env_for(&home))
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .output()
        .unwrap();
    let stdout = String::from_utf8_lossy(&out.stdout);
    assert!(stdout.contains("AFTER-BLOCK"), "{stdout:?}");
    assert!(!stdout.contains("WRAPPED"), "{stdout:?}");
}

#[test]
fn with_the_real_binary_the_rest_of_the_file_runs_once_inside() {
    let home = home("real");
    std::fs::copy(
        BIN,
        home.join("Library/Application Support/ShellX/bin/shellx-term"),
    )
    .unwrap();
    let mut h = run_shell("/bin/zsh", &["-i"], &home, &[]);
    h.send("echo m=$SHELLX_TERM\r");
    h.expect("m=1", T);
    assert_eq!(h.text().matches("AFTER-BLOCK").count(), 1, "{:?}", h.text());
    h.send("exit 3\r");
    assert_eq!(h.wait_exit(T), 3);
}
