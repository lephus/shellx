//! D35: the agent skill, embedded so it always matches this CLI. Installing
//! never connects to ShellX and never overwrites a file the user changed
//! without asking (no terminal to ask: refused unless `--force`).

use super::args::Parsed;
use super::client::ApiError;
use super::run::{already_reported, Ctx};
use super::value::{to_json, Value};
use std::io::{Read, Write};
use std::path::{Path, PathBuf};

pub const SKILL: &str = include_str!("../../../agent-skills/shellx/SKILL.md");
pub const REFERENCE: &str = include_str!("../../../agent-skills/shellx/reference.md");
pub const CLAUDE_SKILLS_DIR: &str = ".claude/skills";
/// Codex reads user skills from `$HOME/.agents/skills` (Codex docs,
/// "Build skills", checked 2026-10-07; formerly `~/.codex/skills`).
pub const CODEX_SKILLS_DIR: &str = ".agents/skills";

fn io(e: std::io::Error) -> ApiError {
    ApiError::Io(e.to_string())
}

fn refused(message: String) -> ApiError {
    ApiError::Remote {
        code: "forbidden".into(),
        message,
    }
}

/// `skills print [SKILL.md | reference]`; `--json`: `{"files":[{name, text}]}`.
pub fn print(p: &Parsed, ctx: &mut Ctx) -> Result<(), ApiError> {
    let (name, text) = match p.pos(0) {
        None | Some("SKILL.md") | Some("skill") => ("SKILL.md", SKILL),
        Some("reference") | Some("reference.md") => ("reference.md", REFERENCE),
        Some(other) => {
            return Err(ApiError::Usage(format!(
                "no skill file '{other}' (SKILL.md or reference)"
            )))
        }
    };
    if p.json {
        let file = Value::map(vec![
            ("name", Value::text(name)),
            ("text", Value::text(text)),
        ]);
        let v = Value::map(vec![("files", Value::Array(vec![file]))]);
        return writeln!(ctx.out, "{}", to_json(&v)).map_err(io);
    }
    write!(ctx.out, "{text}").map_err(io)
}

/// One line from stdin, byte by byte: nothing past the newline is taken, so
/// the next question gets its own answer.
fn answer(stdin: &mut dyn Read) -> String {
    let mut line = Vec::new();
    let mut b = [0u8; 1];
    while line.len() < 64 {
        match stdin.read(&mut b) {
            Ok(1) if b[0] != b'\n' => line.push(b[0]),
            _ => break,
        }
    }
    String::from_utf8_lossy(&line).trim().to_string()
}

/// Through a new temporary file (random name, `create_new`: never an
/// existing file or link) and a rename: never a half-written skill.
fn write_file(path: &Path, text: &str) -> Result<(), ApiError> {
    let mut r = [0u8; 8];
    getrandom::fill(&mut r).map_err(|_| ApiError::Io("no randomness".into()))?;
    let suffix: String = r.iter().map(|b| format!("{b:02x}")).collect();
    let tmp = path.with_extension(format!("tmp-{suffix}"));
    let written = std::fs::OpenOptions::new()
        .write(true)
        .create_new(true)
        .open(&tmp)
        .and_then(|mut f| f.write_all(text.as_bytes()).and_then(|()| f.sync_all()))
        .and_then(|()| std::fs::rename(&tmp, path));
    written.map_err(|e| {
        let _ = std::fs::remove_file(&tmp);
        io(e)
    })
}

fn targets(p: &Parsed, home: &Path) -> Vec<PathBuf> {
    let mut targets: Vec<PathBuf> = Vec::new();
    if p.has("claude") {
        targets.push(home.join(CLAUDE_SKILLS_DIR));
    }
    if p.has("codex") {
        targets.push(home.join(CODEX_SKILLS_DIR));
    }
    if let Some(d) = p.flag("dir") {
        targets.push(PathBuf::from(d));
    }
    if targets.is_empty() {
        if home.join(".claude").is_dir() {
            targets.push(home.join(CLAUDE_SKILLS_DIR));
        }
        if home.join(".codex").is_dir() || home.join(".agents").is_dir() {
            targets.push(home.join(CODEX_SKILLS_DIR));
        }
    }
    targets
}

fn paths(ps: &[PathBuf]) -> Value {
    Value::Array(
        ps.iter()
            .map(|p| Value::text(p.to_string_lossy()))
            .collect(),
    )
}

/// `skills install [--claude] [--codex] [--dir D] [--force]`. A changed
/// file the user does not let us overwrite (declined, or no terminal to
/// ask) is skipped; the others are still installed, and the command exits
/// 6 at the end (review M5). `--json`: one object
/// `{"installed","upToDate","skipped"[, "error"]}`.
pub fn install(p: &Parsed, ctx: &mut Ctx) -> Result<(), ApiError> {
    let home = ctx
        .home
        .clone()
        .ok_or_else(|| ApiError::Usage("HOME is not set; pass --dir DIR".into()))?;
    let targets = targets(p, &home);
    if targets.is_empty() {
        return Err(ApiError::Remote {
            code: "not_installed".into(),
            message:
                "no ~/.claude, ~/.codex or ~/.agents found; pass --claude, --codex or --dir DIR"
                    .into(),
        });
    }
    let (mut installed, mut up_to_date, mut skipped) = (vec![], vec![], vec![]);
    for base in targets {
        let dir = base.join("shellx");
        for (name, text) in [("SKILL.md", SKILL), ("reference.md", REFERENCE)] {
            let path = dir.join(name);
            match std::fs::read(&path) {
                Ok(old) if old == text.as_bytes() => {
                    if !p.json {
                        writeln!(ctx.out, "{} is up to date", path.display()).ok();
                    }
                    up_to_date.push(path);
                    continue;
                }
                Ok(_) if !p.has("force") => {
                    let yes = ctx.stdin_is_tty && {
                        write!(ctx.err, "Overwrite {}? [y/N] ", path.display()).ok();
                        ctx.err.flush().ok();
                        matches!(
                            answer(ctx.stdin).as_str(),
                            "y" | "Y" | "yes" | "YES" | "Yes"
                        )
                    };
                    if !yes {
                        if !p.json {
                            writeln!(ctx.err, "kept your changed {}", path.display()).ok();
                        }
                        skipped.push(path);
                        continue;
                    }
                }
                _ => {}
            }
            std::fs::create_dir_all(&dir).map_err(io)?;
            write_file(&path, text)?;
            if !p.json {
                writeln!(ctx.out, "installed {}", path.display()).ok();
            }
            installed.push(path);
        }
    }
    let refusal = (!skipped.is_empty()).then(|| {
        format!(
            "{} changed file(s) not overwritten; rerun with --force to overwrite",
            skipped.len()
        )
    });
    if p.json {
        let mut v = vec![
            ("installed", paths(&installed)),
            ("upToDate", paths(&up_to_date)),
            ("skipped", paths(&skipped)),
        ];
        if let Some(m) = &refusal {
            v.push((
                "error",
                Value::map(vec![
                    ("code", Value::text("forbidden")),
                    ("message", Value::text(m)),
                ]),
            ));
        }
        writeln!(ctx.out, "{}", to_json(&Value::map(v))).ok();
        if refusal.is_some() {
            return Err(already_reported("forbidden"));
        }
        return Ok(());
    }
    match refusal {
        Some(message) => Err(refused(message)),
        None => Ok(()),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::api::args::{parse, Invocation};
    use crate::api::client::{ApiError, Session};
    use std::path::PathBuf;

    fn run_skills(
        args: &[&str],
        home: &std::path::Path,
        stdin: &str,
        tty: bool,
    ) -> (i32, String, String) {
        let args: Vec<String> = args.iter().map(|s| s.to_string()).collect();
        let Ok(Invocation::Run(p)) = parse(&args) else {
            panic!()
        };
        let get = |_: &str| None;
        let connect = |_: Option<&str>| -> Result<Box<dyn Session>, ApiError> {
            panic!("skills never connect")
        };
        let (mut out, mut err) = (Vec::new(), Vec::new());
        let mut input = stdin.as_bytes();
        let code = {
            let mut ctx = crate::api::run::Ctx {
                env: &get,
                out: &mut out,
                err: &mut err,
                stdin: &mut input,
                stdin_is_tty: tty,
                cwd: PathBuf::from("/"),
                home: Some(home.to_path_buf()),
                tty: None,
                shared_terminal: false,
                connect: &connect,
                stdout_gone: None,
            };
            crate::api::run::run(&p, &mut ctx)
        };
        (
            code,
            String::from_utf8(out).unwrap(),
            String::from_utf8(err).unwrap(),
        )
    }

    fn temp_home(name: &str) -> PathBuf {
        let d = std::env::temp_dir().join(format!("shellx-skills-{}-{name}", std::process::id()));
        let _ = std::fs::remove_dir_all(&d);
        std::fs::create_dir_all(&d).unwrap();
        d
    }

    #[test]
    fn embedded_files_cover_every_command() {
        assert!(SKILL.starts_with("---\nname: shellx\n"));
        for c in crate::api::args::COMMANDS {
            assert!(
                REFERENCE.contains(&format!("shellx {}", c.path.join(" "))),
                "{:?}",
                c.path
            );
        }
        // Rulings the skill must carry (A7 amendment, A6 absent).
        assert!(
            SKILL.contains("Allow other terminals") && REFERENCE.contains("Allow other terminals")
        );
        assert!(SKILL.contains("browser panes") && REFERENCE.contains("no browser panes yet"));
        assert!(REFERENCE.contains("pattern is too slow"));
    }

    #[test]
    fn print_files() {
        let home = temp_home("print");
        let (code, out, _) = run_skills(&["skills", "print"], &home, "", false);
        assert_eq!((code, out.as_str()), (0, SKILL));
        assert_eq!(
            run_skills(&["skills", "print", "reference"], &home, "", false).1,
            REFERENCE
        );
        assert_eq!(
            run_skills(&["skills", "print", "other"], &home, "", false).0,
            2
        );
    }

    #[test]
    fn install_asks_before_overwriting() {
        let home = temp_home("ask");
        let target = home.join(".claude/skills/shellx/SKILL.md");
        assert_eq!(
            run_skills(&["skills", "install", "--claude"], &home, "", false).0,
            0
        );
        assert_eq!(std::fs::read_to_string(&target).unwrap(), SKILL);
        let (code, out, _) = run_skills(&["skills", "install", "--claude"], &home, "", false);
        assert_eq!(code, 0);
        assert!(out.contains("up to date"));
        std::fs::write(&target, "edited").unwrap();
        assert_eq!(
            run_skills(&["skills", "install", "--claude"], &home, "", false).0,
            6
        );
        assert_eq!(std::fs::read_to_string(&target).unwrap(), "edited");
        let (code, _, err) = run_skills(&["skills", "install", "--claude"], &home, "n\n", true);
        assert_eq!(code, 6);
        assert!(err.contains("Overwrite"), "{err}");
        assert_eq!(
            run_skills(&["skills", "install", "--claude"], &home, "y\n", true).0,
            0
        );
        assert_eq!(std::fs::read_to_string(&target).unwrap(), SKILL);
        std::fs::write(&target, "edited").unwrap();
        assert_eq!(
            run_skills(
                &["skills", "install", "--claude", "--force"],
                &home,
                "",
                false
            )
            .0,
            0
        );
        assert_eq!(std::fs::read_to_string(&target).unwrap(), SKILL);
        assert!(home.join(".claude/skills/shellx/reference.md").exists());
    }

    #[test]
    fn each_changed_file_gets_its_own_answer() {
        let home = temp_home("two");
        let dir = home.join("custom");
        assert_eq!(
            run_skills(
                &["skills", "install", "--dir", dir.to_str().unwrap()],
                &home,
                "",
                false
            )
            .0,
            0
        );
        std::fs::write(dir.join("shellx/SKILL.md"), "a").unwrap();
        std::fs::write(dir.join("shellx/reference.md"), "b").unwrap();
        let (code, _, err) = run_skills(
            &["skills", "install", "--dir", dir.to_str().unwrap()],
            &home,
            "y\nyes\n",
            true,
        );
        assert_eq!(code, 0, "{err}");
        assert_eq!(
            std::fs::read_to_string(dir.join("shellx/reference.md")).unwrap(),
            REFERENCE
        );
    }

    #[test]
    fn default_targets_are_existing_agent_dirs() {
        let home = temp_home("default");
        let (code, _, err) = run_skills(&["skills", "install"], &home, "", false);
        assert_eq!(code, 1);
        assert!(err.contains("--claude"), "{err}");
        std::fs::create_dir_all(home.join(".codex")).unwrap();
        assert_eq!(run_skills(&["skills", "install"], &home, "", false).0, 0);
        assert!(home.join(CODEX_SKILLS_DIR).join("shellx/SKILL.md").exists());
        assert!(!home.join(".claude").exists());
        // Codex reads user skills from ~/.agents/skills (Codex docs).
        assert_eq!(CODEX_SKILLS_DIR, ".agents/skills");
        let other = temp_home("agents-only");
        std::fs::create_dir_all(other.join(".agents")).unwrap();
        assert_eq!(run_skills(&["skills", "install"], &other, "", false).0, 0);
        assert!(other.join(".agents/skills/shellx/reference.md").exists());
    }

    #[test]
    fn declining_one_file_keeps_the_others() {
        let home = temp_home("decline");
        let dir = home.join("d");
        let d = dir.to_str().unwrap();
        assert_eq!(
            run_skills(&["skills", "install", "--dir", d], &home, "", false).0,
            0
        );
        std::fs::write(dir.join("shellx/SKILL.md"), "a").unwrap();
        std::fs::write(dir.join("shellx/reference.md"), "b").unwrap();
        // No to the first, yes to the second: the second is still asked.
        let (code, _, err) = run_skills(&["skills", "install", "--dir", d], &home, "n\ny\n", true);
        assert_eq!(code, 6, "{err}");
        assert_eq!(
            std::fs::read_to_string(dir.join("shellx/SKILL.md")).unwrap(),
            "a"
        );
        assert_eq!(
            std::fs::read_to_string(dir.join("shellx/reference.md")).unwrap(),
            REFERENCE
        );
        // No terminal: a changed file is skipped, a missing one installed.
        std::fs::remove_file(dir.join("shellx/reference.md")).unwrap();
        assert_eq!(
            run_skills(&["skills", "install", "--dir", d], &home, "", false).0,
            6
        );
        assert_eq!(
            std::fs::read_to_string(dir.join("shellx/SKILL.md")).unwrap(),
            "a"
        );
        assert_eq!(
            std::fs::read_to_string(dir.join("shellx/reference.md")).unwrap(),
            REFERENCE
        );
    }

    #[test]
    fn a_skipped_target_does_not_stop_the_next() {
        let home = temp_home("targets");
        assert_eq!(
            run_skills(&["skills", "install", "--claude"], &home, "", false).0,
            0
        );
        std::fs::write(home.join(".claude/skills/shellx/SKILL.md"), "mine").unwrap();
        let (code, _, _) = run_skills(
            &["skills", "install", "--claude", "--codex"],
            &home,
            "",
            false,
        );
        assert_eq!(code, 6);
        assert_eq!(
            std::fs::read_to_string(home.join(".agents/skills/shellx/SKILL.md")).unwrap(),
            SKILL
        );
        assert_eq!(
            std::fs::read_to_string(home.join(".claude/skills/shellx/SKILL.md")).unwrap(),
            "mine"
        );
    }

    #[test]
    fn json_is_one_object() {
        let home = temp_home("json");
        let dir = home.join("j");
        let d = dir.to_str().unwrap();
        let (skill, reference) = (dir.join("shellx/SKILL.md"), dir.join("shellx/reference.md"));
        let (code, out, err) = run_skills(
            &["skills", "install", "--dir", d, "--json"],
            &home,
            "",
            false,
        );
        assert_eq!((code, err.as_str()), (0, ""));
        let list = |ps: &[&std::path::Path]| {
            ps.iter()
                .map(|p| crate::api::value::json_string(p.to_str().unwrap()))
                .collect::<Vec<_>>()
                .join(",")
        };
        assert_eq!(
            out,
            format!(
                "{{\"installed\":[{}],\"upToDate\":[],\"skipped\":[]}}\n",
                list(&[&skill, &reference])
            )
        );
        std::fs::write(&skill, "a").unwrap();
        let (code, out, err) = run_skills(
            &["skills", "install", "--dir", d, "--json"],
            &home,
            "",
            false,
        );
        assert_eq!((code, err.as_str()), (6, ""));
        assert_eq!(out.lines().count(), 1, "{out}");
        assert!(out.starts_with(&format!("{{\"installed\":[],\"upToDate\":[{}],\"skipped\":[{}],\"error\":{{\"code\":\"forbidden\"", list(&[&reference]), list(&[&skill]))), "{out}");
        let (code, out, _) = run_skills(
            &["skills", "print", "reference", "--json"],
            &home,
            "",
            false,
        );
        assert_eq!(code, 0);
        assert_eq!(
            out,
            format!(
                "{{\"files\":[{{\"name\":\"reference.md\",\"text\":{}}}]}}\n",
                crate::api::value::json_string(REFERENCE)
            )
        );
    }

    #[cfg(unix)]
    #[test]
    fn the_temporary_file_is_never_an_existing_one() {
        // A file (or link) already at a predictable temporary name is never
        // written through.
        let home = temp_home("tmp");
        let dir = home.join("t/shellx");
        std::fs::create_dir_all(&dir).unwrap();
        let victim = home.join("victim");
        std::fs::write(&victim, "keep").unwrap();
        for name in ["SKILL", "reference"] {
            let link = dir.join(format!("{name}.tmp-{}", std::process::id()));
            std::os::unix::fs::symlink(&victim, link).unwrap();
        }
        let d = home.join("t");
        assert_eq!(
            run_skills(
                &["skills", "install", "--dir", d.to_str().unwrap()],
                &home,
                "",
                false
            )
            .0,
            0
        );
        assert_eq!(std::fs::read_to_string(&victim).unwrap(), "keep");
        assert_eq!(
            std::fs::read_to_string(dir.join("SKILL.md")).unwrap(),
            SKILL
        );
    }
}
