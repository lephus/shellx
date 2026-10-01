#![cfg(unix)]

mod common;

use common::{Harness, BIN};
use std::os::unix::fs::PermissionsExt;
use std::path::Path;
use std::process::{Command, Stdio};
use std::time::Duration;

// Generous: a loaded machine can take seconds to start a dozen zsh at once.
const T: Duration = Duration::from_secs(15);
const ZSH_BLOCK: &str = include_str!("../shell/block.zsh");
const BASH_BLOCK: &str = include_str!("../shell/block.bash");

/// A fake HOME whose "installed" shellx-term just reports how it was called.
fn home(name: &str) -> common::TempDir {
    let home = common::temp_dir(name);
    let bin = home.join("Library/Application Support/ShellX/bin");
    std::fs::create_dir_all(&bin).unwrap();
    let fake = bin.join("shellx-term");
    std::fs::write(
        &fake,
        "#!/bin/sh\n\
         printf '%s\\n' \"$*\" >> \"$(dirname \"$0\")/calls.log\"\n\
         if [ \"$1\" = probe ]; then printf '%s\\n' \"${SHELLX_FAKE_PROBE:-/bin/zsh}\"; exit 0; fi\n\
         printf 'WRAPPED'; for a in \"$@\"; do printf ' [%s]' \"$a\"; done\n\
         printf ' wrap=[%s] login=[%s] marker=[%s]\\n' \"${SHELLX_TERM_WRAP-}\" \"${SHELLX_TERM_WRAP_LOGIN-}\" \"${SHELLX_TERM_LOGIN-}\"\n\
         printf 'ZDOTDIR=[%s]\\n' \"${ZDOTDIR-unset}\"\n\
         exit 0\n",
    )
    .unwrap();
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
    if program.ends_with("bash") {
        // What `probe` reports: the shell binary that runs the block.
        env.push(("SHELLX_FAKE_PROBE", "/bin/bash"));
    }
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
    assert_wrapped(
        "/bin/zsh",
        &["-i"],
        "WRAPPED wrap=[/bin/zsh] login=[] marker=[]",
    );
}

#[test]
fn zsh_login_is_wrapped_as_non_login_with_the_login_marker() {
    assert_wrapped(
        "/bin/zsh",
        &["-il"],
        "WRAPPED wrap=[/bin/zsh] login=[] marker=[1]",
    );
}

#[test]
fn zsh_started_by_bare_name_is_wrapped_as_the_probed_binary() {
    // argv[0] is "zsh" (not absolute): the block wraps what `probe` reports
    // (the running shell's own binary), not $SHELL.
    assert_wrapped("zsh", &["-i"], "WRAPPED wrap=[/bin/zsh] login=[] marker=[]");
}

#[test]
fn bash_interactive_is_wrapped() {
    assert_wrapped("/bin/bash", &["-i"], "WRAPPED wrap=[/bin/bash] login=[] ");
}

#[test]
fn bash_login_is_wrapped_as_login() {
    assert_wrapped("/bin/bash", &["-il"], "WRAPPED wrap=[/bin/bash] login=[1] ");
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

/// A fake HOME with the real binary "installed".
fn real_home(tag: &str) -> common::TempDir {
    let home = home(tag);
    std::fs::copy(
        BIN,
        home.join("Library/Application Support/ShellX/bin/shellx-term"),
    )
    .unwrap();
    home
}

/// Prints `expr` inside the shell as `name=[value]` and returns the value.
/// (The typed command has `name""=[`, so only the output matches.)
fn shell_value(h: &mut Harness, name: &str, expr: &str) -> String {
    h.send(&format!("echo \"{name}\"\"=[{expr}]\"\r"));
    let prefix = format!("{name}=[");
    h.expect(&prefix, T);
    h.settle(Duration::from_millis(300));
    let text = h.text();
    let start = text.rfind(&prefix).unwrap() + prefix.len();
    let end = text[start..].find(']').expect("closing bracket");
    text[start..start + end].trim().to_string()
}

/// Inside a really wrapped window the shell's parent is `shellx-term`. (`ucomm`
/// is the executable's name; `comm` shows the argv0 the block kept, `zsh`.)
fn assert_really_wrapped(h: &mut Harness) {
    let comm = shell_value(h, "PCOMM", "$(ps -o ucomm= -p $PPID)");
    assert!(
        comm.contains("shellx-term"),
        "not wrapped: parent is {comm:?}"
    );
}

#[test]
fn with_the_real_binary_the_rest_of_the_file_runs_once_inside() {
    let home = real_home("real");
    let mut h = run_shell("/bin/zsh", &["-i"], &home, &[]);
    h.send("[[ $SHELLX_TERM == $TTY ]] && echo SAME''-TTY\r");
    h.expect("SAME-TTY", T);
    assert_really_wrapped(&mut h);
    let args = shell_value(&mut h, "PARGS", "$(ps -o args= -p $PPID)");
    assert!(
        !args.contains("wrap"),
        "shellx-term got arguments: {args:?}"
    );
    assert_eq!(h.text().matches("AFTER-BLOCK").count(), 1, "{:?}", h.text());
    h.send("exit 3\r");
    assert_eq!(h.wait_exit(T), 3);
}

#[test]
fn a_zsh_login_window_keeps_login_behaviour_inside() {
    let home = real_home("real-login");
    std::fs::write(home.join(".zlogin"), "echo ZLOGIN-RAN\n").unwrap();
    let mut h = run_shell("/bin/zsh", &["-il"], &home, &[]);
    h.expect("ZLOGIN-RAN", T);
    h.send("[[ -o login ]] && echo LOGIN''-ON\r");
    h.expect("LOGIN-ON", T);
    assert_really_wrapped(&mut h);
    h.send("logout\r");
    assert_eq!(h.wait_exit(T), 0);
    assert_eq!(h.text().matches("ZLOGIN-RAN").count(), 1, "{:?}", h.text());
}

/// A plain interactive shell ignores SIGTERM; the wrapped window must too
/// (`pkill zsh` must not close windows). The block's `exec` hands us a
/// default disposition, so we ignore it ourselves.
fn assert_sigterm_does_not_close_the_window(program: &str, args: &[&str], tag: &str) {
    let home = real_home(tag);
    let mut h = run_shell(program, args, &home, &[]);
    assert_really_wrapped(&mut h);
    h.send("kill -TERM $PPID; sleep 0.3; echo al''ive\r");
    h.expect("alive", T);
    h.send("echo al''ive-again\r");
    h.expect("alive-again", T);
    h.send("exit 0\r");
    assert_eq!(h.wait_exit(T), 0);
}

#[test]
fn a_wrapped_zsh_window_ignores_sigterm_like_a_plain_interactive_shell() {
    assert_sigterm_does_not_close_the_window("/bin/zsh", &["-il"], "term-zsh");
}

#[test]
fn a_wrapped_bash_window_ignores_sigterm_like_a_plain_interactive_shell() {
    assert_sigterm_does_not_close_the_window("/bin/bash", &["-il"], "term-bash");
}

/// When wrapping fails in a block-started bash window, the plain bash that
/// takes over, and what it runs, get SIGTERM as the window had it: bash
/// passes an ignored SIGTERM on to every command.
#[cfg(feature = "test-hooks")]
#[test]
fn a_failed_wrap_leaves_sigterm_as_it_was_for_the_fallback_shell() {
    let home = real_home("fallback-sigterm");
    let mut h = run_shell(
        "/bin/bash",
        &["-il"],
        &home,
        &[("SHELLX_TERM_FAULT", "spawn")],
    );
    h.expect("could not share this terminal", T);
    h.send("/bin/sh -c 'kill -TERM $$; echo SUR''VIVED'; echo co''de=$?\r");
    let code = h.wait_number_after("code=", T);
    assert_eq!(
        code,
        143,
        "the command kept an ignored SIGTERM: {:?}",
        h.text()
    );
    assert!(!h.text().contains("SURVIVED"), "{:?}", h.text());
    h.send("exit\r");
    h.wait_exit(T);
}

#[test]
fn a_nested_shell_inside_a_wrapped_window_is_not_wrapped_again() {
    let home = real_home("real-nested");
    let mut h = run_shell("/bin/zsh", &["-i"], &home, &[]);
    assert_really_wrapped(&mut h);
    h.send("zsh -i\r");
    let comm = shell_value(&mut h, "NCOMM", "$(ps -o ucomm= -p $PPID)");
    assert!(
        comm == "zsh" && !comm.contains("shellx-term"),
        "nested shell was wrapped: parent is {comm:?}"
    );
    assert_eq!(h.text().matches("AFTER-BLOCK").count(), 2, "{:?}", h.text());
    h.send("exit\r");
    h.send("exit\r");
    assert_eq!(h.wait_exit(T), 0);
}

#[test]
fn a_terminal_app_launched_from_a_wrapped_window_wraps_its_own_terminals() {
    // Its tty differs from the one in SHELLX_TERM.
    for (program, tag) in [
        ("/bin/zsh", "other-tty-zsh"),
        ("/bin/bash", "other-tty-bash"),
    ] {
        let home = home(tag);
        let mut h = run_shell(program, &["-i"], &home, &[("SHELLX_TERM", "/dev/ttys999")]);
        h.expect("WRAPPED wrap=[/bin/", T);
        assert_eq!(h.wait_exit(T), 0);
    }
}

#[test]
fn bash_manual_source_does_not_replace_the_running_bash() {
    let home = home("bash-source");
    // The startup file has no block, so the window starts unwrapped.
    std::fs::write(home.join(".bashrc"), "echo AFTER-BLOCK\n").unwrap();
    std::fs::write(home.join("blk.sh"), BASH_BLOCK).unwrap();
    let mut h = run_shell("/bin/bash", &["-i"], &home, &[]);
    h.expect("AFTER-BLOCK", T);
    h.send(". ~/blk.sh; echo after''-src\r");
    h.expect("after-src", T);
    assert!(!h.text().contains("WRAPPED"), "{:?}", h.text());
    h.send("exit\r");
    h.wait_exit(T);
}

/// Runs `/bin/zsh -i` in a fake HOME; `setup` may add files and returns the
/// extra environment. Returns the window text after the shell exited or
/// the block fell through (AFTER-BLOCK).
fn zsh_with(
    tag: &str,
    env_of: impl FnOnce(&Path) -> Vec<(String, String)>,
) -> (common::TempDir, Harness) {
    let home = home(tag);
    let extra = env_of(&home);
    let extra: Vec<(&str, &str)> = extra
        .iter()
        .map(|(k, v)| (k.as_str(), v.as_str()))
        .collect();
    let h = run_shell("/bin/zsh", &["-i"], &home, &extra);
    (home, h)
}

fn finish_wrapped(h: &mut Harness) -> String {
    assert_eq!(h.wait_exit(T), 0);
    assert!(!h.text().contains("AFTER-BLOCK"), "{:?}", h.text());
    h.text()
}

#[test]
fn no_injector_leaves_zdotdir_as_passed() {
    let (home, mut h) = zsh_with("zd-none", |_| vec![]);
    let text = finish_wrapped(&mut h);
    let line = format!("ZDOTDIR=[{}]", home.display());
    assert!(text.contains(&line), "{text:?}");
}

#[test]
fn vscode_style_injection_repoints_zdotdir() {
    let inj = common::temp_dir("zd-vscode-inj");
    std::fs::write(
        inj.join(".zshrc"),
        "VSCODE_ZDOTDIR=$ZDOTDIR; ZDOTDIR=$USER_ZDOTDIR; . $USER_ZDOTDIR/.zshrc\n",
    )
    .unwrap();
    let inj_s = inj.to_str().unwrap().to_string();
    let (_home, mut h) = zsh_with("zd-vscode", |home| {
        vec![
            ("ZDOTDIR".into(), inj_s.clone()),
            ("USER_ZDOTDIR".into(), home.to_str().unwrap().into()),
        ]
    });
    let text = finish_wrapped(&mut h);
    assert!(
        text.contains("WRAPPED wrap=[/bin/zsh] login=[]"),
        "{text:?}"
    );
    assert!(text.contains(&format!("ZDOTDIR=[{inj_s}]")), "{text:?}");
}

#[test]
fn jetbrains_style_injection_repoints_zdotdir() {
    let inj = common::temp_dir("zd-jb-inj");
    std::fs::write(
        inj.join(".zshenv"),
        "_INTELLIJ_ZDOTDIR=$ZDOTDIR; unset ZDOTDIR\n",
    )
    .unwrap();
    let inj_s = inj.to_str().unwrap().to_string();
    // Without ZDOTDIR the user's files are found through HOME.
    let home = home("zd-jb");
    let mut h = Harness::spawn(
        "/bin/zsh",
        &["-i"],
        &[
            ("HOME", home.to_str().unwrap()),
            ("ZDOTDIR", &inj_s),
            ("SHELL", "/bin/zsh"),
        ],
        80,
        24,
    );
    let text = finish_wrapped(&mut h);
    assert!(
        text.contains("WRAPPED wrap=[/bin/zsh] login=[]"),
        "{text:?}"
    );
    assert!(text.contains(&format!("ZDOTDIR=[{inj_s}]")), "{text:?}");
}

/// An "installed" shellx-term the kernel cannot run (NULs, mode 0755).
fn break_binary(home: &Path) {
    let bin = home.join("Library/Application Support/ShellX/bin/shellx-term");
    std::fs::write(&bin, [0u8; 64]).unwrap();
    std::fs::set_permissions(&bin, std::fs::Permissions::from_mode(0o755)).unwrap();
}

#[test]
fn an_unrunnable_binary_leaves_the_shell_and_its_variables_alone() {
    let inj = common::temp_dir("broken-inj");
    std::fs::write(
        inj.join(".zshrc"),
        "VSCODE_ZDOTDIR=$ZDOTDIR; ZDOTDIR=$USER_ZDOTDIR; . $USER_ZDOTDIR/.zshrc\n",
    )
    .unwrap();
    let inj_s = inj.to_str().unwrap().to_string();
    // (program, extra env, shell-specific probe of leftover helper variables)
    for (program, with_injector) in [
        ("/bin/zsh", false),
        ("/bin/zsh", true),
        ("/bin/bash", false),
    ] {
        let tag = format!(
            "broken-{}-{with_injector}",
            program.rsplit('/').next().unwrap()
        );
        let home = home(&tag);
        break_binary(&home);
        let home_s = home.to_str().unwrap().to_string();
        let mut extra: Vec<(&str, &str)> = vec![];
        if with_injector {
            extra.push(("ZDOTDIR", &inj_s));
            extra.push(("USER_ZDOTDIR", &home_s));
        }
        let mut h = run_shell(program, &["-i"], &home, &extra);
        h.expect("AFTER-BLOCK", T);
        let probe = if program == "/bin/zsh" {
            "print -r -- \"zd=[${ZDOTDIR-unset}] n=[${(k)parameters[(I)__shellx_*]}] end\""
        } else {
            "echo zd=[${ZDOTDIR-unset}] n=[$(set | grep -c __shellx_)] end"
        };
        h.send(&format!("{probe}\r"));
        h.expect(&format!("zd=[{home_s}]"), T);
        h.settle(Duration::from_millis(300));
        let text = h.text();
        h.send("exit\r");
        h.wait_exit(T);
        assert!(!text.contains("WRAPPED"), "{tag}: {text:?}");
        let n = if program == "/bin/zsh" { "" } else { "0" };
        let want = format!("zd=[{home_s}] n=[{n}] end");
        assert!(text.contains(&want), "{tag}: {text:?}");
    }
}

#[test]
fn the_binary_is_probed_before_wrapping() {
    let home = home("probe-order");
    let mut h = run_shell("/bin/zsh", &["-i"], &home, &[]);
    assert_eq!(h.wait_exit(T), 0);
    let log =
        std::fs::read_to_string(home.join("Library/Application Support/ShellX/bin/calls.log"))
            .unwrap();
    let lines: Vec<&str> = log.lines().collect();
    assert_eq!(lines, ["probe", ""], "{log:?}");
}

#[test]
fn a_directory_at_the_installed_path_is_not_exec_d() {
    for (program, tag) in [("/bin/zsh", "dir-zsh"), ("/bin/bash", "dir-bash")] {
        let home = home(tag);
        let bin = home.join("Library/Application Support/ShellX/bin/shellx-term");
        std::fs::remove_file(&bin).unwrap();
        std::fs::create_dir(&bin).unwrap();
        let mut h = run_shell(program, &["-i"], &home, &[]);
        h.expect("AFTER-BLOCK", T);
        h.send("exit\r");
        h.wait_exit(T);
        assert!(!h.text().contains("WRAPPED"), "{tag}: {:?}", h.text());
    }
}

#[test]
fn ide_exclusions_for_bash_and_zsh() {
    assert_not_wrapped(
        "/bin/bash",
        &["-i"],
        &[("TERM_PROGRAM", "vscode")],
        "bash-vscode",
    );
    assert_not_wrapped(
        "/bin/bash",
        &["-i"],
        &[("TERMINAL_EMULATOR", "JetBrains-JediTerm")],
        "bash-jetbrains",
    );
    // zsh is handled through ZDOTDIR, not excluded.
    assert_wrapped_with("/bin/zsh", &[("TERM_PROGRAM", "vscode")], "zsh-vscode");
}

fn assert_wrapped_with(program: &str, extra: &[(&str, &str)], tag: &str) {
    let home = home(tag);
    let mut h = run_shell(program, &["-i"], &home, extra);
    h.expect("WRAPPED wrap=[/bin/zsh] login=[]", T);
    assert_eq!(h.wait_exit(T), 0);
}

#[test]
fn sourcing_the_block_by_hand_does_not_replace_the_running_zsh() {
    let home = home("zsh-source");
    // The startup file has no block, so the window starts unwrapped.
    std::fs::write(home.join(".zshrc"), "").unwrap();
    std::fs::write(home.join("blk.zsh"), ZSH_BLOCK).unwrap();
    let mut h = run_shell("/bin/zsh", &["-i"], &home, &[]);
    h.send("MYVAR=kept; source ~/blk.zsh\r");
    h.send("echo still-$MYVAR-here\r");
    h.expect("still-kept-here", T);
    assert!(!h.text().contains("WRAPPED"), "{:?}", h.text());
    h.send("exit\r");
    h.wait_exit(T);
}

#[test]
fn zsh_running_a_script_interactively_is_not_wrapped() {
    let home = home("zsh-script");
    let script = home.join("run.zsh");
    std::fs::write(&script, "echo script-ran\n").unwrap();
    let script = script.to_str().unwrap();
    let mut h = run_shell("/bin/zsh", &["-i", script], &home, &[]);
    h.expect("script-ran", T);
    assert_eq!(h.wait_exit(T), 0);
    assert!(!h.text().contains("WRAPPED"), "{:?}", h.text());
}
