//! The generated completion scripts, executed by the real shells. A fake
//! `shellx` on PATH prints hostile ids: they must stay text.
#![cfg(unix)]
use std::path::{Path, PathBuf};
use std::process::Command;

fn script(shell: &str) -> String {
    let out = Command::new(env!("CARGO_BIN_EXE_shellx-term"))
        .args(["cli", "completions", shell])
        .output()
        .unwrap();
    assert_eq!(out.status.code(), Some(0));
    String::from_utf8(out.stdout).unwrap()
}

fn have(sh: &str) -> bool {
    Command::new(sh).arg("-c").arg("true").status().is_ok()
}

/// A temp dir with a fake `shellx` whose `ls --ids` prints a hostile id.
fn fake(name: &str) -> PathBuf {
    let d = std::env::temp_dir().join(format!("shellx-compl-{}-{name}", std::process::id()));
    let _ = std::fs::remove_dir_all(&d);
    std::fs::create_dir_all(&d).unwrap();
    let bin = d.join("shellx");
    let evil = format!("$(touch {}/PWNED)", d.display());
    std::fs::write(
        &bin,
        format!(
            "#!/bin/sh\ncat <<'EOF'\np1\np2\n{evil}\n`touch {}/PWNED2`\nEOF\n",
            d.display()
        ),
    )
    .unwrap();
    use std::os::unix::fs::PermissionsExt;
    std::fs::set_permissions(&bin, std::fs::Permissions::from_mode(0o755)).unwrap();
    d
}

fn run(shell: &str, d: &Path, code: &str) -> String {
    let path = format!("{}:{}", d.display(), std::env::var("PATH").unwrap());
    let out = Command::new(shell)
        .args(["-c", code])
        .env("PATH", path)
        .output()
        .unwrap();
    assert!(
        out.status.success(),
        "{}",
        String::from_utf8_lossy(&out.stderr)
    );
    String::from_utf8(out.stdout).unwrap()
}

#[test]
fn bash_completion_never_evaluates_ids() {
    if !have("bash") {
        return;
    }
    let d = fake("bash");
    let s = d.join("c.bash");
    std::fs::write(&s, script("bash")).unwrap();
    let load = format!("source {}; ", s.display());
    let out = run(
        "bash",
        &d,
        &format!(
            r#"{load} COMP_WORDS=(shellx send ""); COMP_CWORD=2; _shellx; printf '%s\n' "${{COMPREPLY[@]}}""#
        ),
    );
    assert!(out.contains("p1\n") && out.contains("p2\n"), "{out}");
    assert!(out.contains("$(touch "), "ids stay literal: {out}");
    assert!(!d.join("PWNED").exists() && !d.join("PWNED2").exists());
    // Subcommands match exactly, not as a substring.
    let out = run(
        "bash",
        &d,
        &format!(
            r#"{load} COMP_WORDS=(shellx xworkspacex ""); COMP_CWORD=2; _shellx; printf '%s\n' "${{COMPREPLY[@]}}""#
        ),
    );
    assert!(!out.contains("rename"), "{out}");
    let out = run(
        "bash",
        &d,
        &format!(
            r#"{load} COMP_WORDS=(shellx workspace re); COMP_CWORD=2; _shellx; printf '%s\n' "${{COMPREPLY[@]}}""#
        ),
    );
    assert_eq!(out.trim(), "rename");
    let out = run(
        "bash",
        &d,
        &format!(
            r#"{load} COMP_WORDS=(shellx split --d); COMP_CWORD=2; _shellx; printf '%s\n' "${{COMPREPLY[@]}}""#
        ),
    );
    assert_eq!(out.trim(), "--down");
}

#[test]
fn zsh_completion_keeps_path_and_never_evaluates_ids() {
    if !have("zsh") {
        return;
    }
    let d = fake("zsh");
    let s = d.join("_shellx");
    std::fs::write(&s, script("zsh")).unwrap();
    assert!(script("zsh").starts_with("#compdef shellx"));
    let stubs = "compdef(){ :; }; _arguments(){ print -r -- \"ARGS $CURRENT ${words[*]}\"; }; _describe(){ print -r -- \"DESC ${(@P)4}\"; }; compadd(){ print -r -- \"ADD $*\"; }; ";
    let code = format!(
        r#"{stubs} before=$PATH; source {s}; words=(shellx split ""); CURRENT=3; _shellx; words=(shellx workspace ""); CURRENT=3; _shellx; words=(shellx workspace rename ""); CURRENT=4; _shellx; _shellx_ids; [[ $PATH == $before ]] && print PATH_OK"#,
        s = s.display()
    );
    let out = run("zsh", &d, &code);
    assert!(out.contains("PATH_OK"), "{out}");
    assert!(
        out.contains("ARGS 2 shellx "),
        "words are shifted past the command: {out}"
    );
    assert!(out.contains("DESC") && out.contains("rename"), "{out}");
    assert!(out.contains("ADD -- p1 p2 $(touch "), "{out}");
    assert!(!d.join("PWNED").exists() && !d.join("PWNED2").exists());
}
