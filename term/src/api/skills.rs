//! D35: the agent skill, embedded so it always matches this CLI. Installing
//! never connects to ShellX and never overwrites a file the user changed
//! without asking (no terminal to ask: refused unless `--force`).

use super::args::Parsed;
use super::client::ApiError;
use super::run::Ctx;
use std::io::Read;
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

/// `skills print [SKILL.md | reference]`.
pub fn print(p: &Parsed, ctx: &mut Ctx) -> Result<(), ApiError> {
    let text = match p.pos(0) {
        None | Some("SKILL.md") | Some("skill") => SKILL,
        Some("reference") | Some("reference.md") => REFERENCE,
        Some(other) => {
            return Err(ApiError::Usage(format!(
                "no skill file '{other}' (SKILL.md or reference)"
            )))
        }
    };
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

/// Through a temporary file and a rename: never a half-written skill.
fn write_file(path: &Path, text: &str) -> Result<(), ApiError> {
    let tmp = path.with_extension(format!("tmp-{}", std::process::id()));
    std::fs::write(&tmp, text).map_err(io)?;
    std::fs::rename(&tmp, path).map_err(|e| {
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

/// `skills install [--claude] [--codex] [--dir D] [--force]`.
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
    for base in targets {
        let dir = base.join("shellx");
        for (name, text) in [("SKILL.md", SKILL), ("reference.md", REFERENCE)] {
            let path = dir.join(name);
            match std::fs::read(&path) {
                Ok(old) if old == text.as_bytes() => {
                    writeln!(ctx.out, "{} is up to date", path.display()).ok();
                    continue;
                }
                Ok(_) if !p.has("force") => {
                    if !ctx.stdin_is_tty {
                        return Err(refused(format!(
                            "{} was changed; rerun with --force to overwrite",
                            path.display()
                        )));
                    }
                    write!(ctx.err, "Overwrite {}? [y/N] ", path.display()).ok();
                    ctx.err.flush().ok();
                    if !matches!(
                        answer(ctx.stdin).as_str(),
                        "y" | "Y" | "yes" | "YES" | "Yes"
                    ) {
                        return Err(refused(format!("{} not overwritten", path.display())));
                    }
                }
                _ => {}
            }
            std::fs::create_dir_all(&dir).map_err(io)?;
            write_file(&path, text)?;
            writeln!(ctx.out, "installed {}", path.display()).ok();
        }
    }
    Ok(())
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
}
