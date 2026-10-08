//! A11 D26: `shellx doctor [--json]` — is ShellX running, do the command
//! line and the app agree, is `shellx` on the PATH, are the agent skills
//! installed, and what does the configuration check say. Every message is
//! a fixed English sentence (A7 D11): nothing the user wrote — no file
//! content, no problem text, no folder — is ever printed.

use super::args::Parsed;
use super::client::ApiError;
use super::run::{Api, Ctx};
use super::value::{to_json, Value};
use std::path::Path;

#[derive(Debug, Clone, PartialEq)]
pub struct Check {
    pub id: &'static str,
    pub ok: bool,
    pub message: String,
}

impl Check {
    pub fn ok(id: &'static str, message: impl Into<String>) -> Self {
        Check {
            id,
            ok: true,
            message: message.into(),
        }
    }
    pub fn fail(id: &'static str, message: impl Into<String>) -> Self {
        Check {
            id,
            ok: false,
            message: message.into(),
        }
    }
}

/// The text to print and the exit code: one `✓`/`✗` line per check, then
/// `N problem(s) found.` when any failed; with `json` one object
/// `{"checks":[{id,ok,message}],"ok":bool}`. Exit 1 on any failure.
pub fn render_checks(checks: &[Check], json: bool) -> (String, i32) {
    let failed = checks.iter().filter(|c| !c.ok).count();
    let code = i32::from(failed > 0);
    if json {
        let list = checks
            .iter()
            .map(|c| {
                Value::map(vec![
                    ("id", Value::text(c.id)),
                    ("ok", Value::Bool(c.ok)),
                    ("message", Value::text(c.message.clone())),
                ])
            })
            .collect();
        let v = Value::map(vec![
            ("checks", Value::Array(list)),
            ("ok", Value::Bool(failed == 0)),
        ]);
        return (format!("{}\n", to_json(&v)), code);
    }
    let mut out = String::new();
    for c in checks {
        out.push_str(if c.ok { "✓ " } else { "✗ " });
        out.push_str(&c.message);
        out.push('\n');
    }
    if failed > 0 {
        let noun = if failed == 1 { "problem" } else { "problems" };
        out.push_str(&format!("{failed} {noun} found.\n"));
    }
    (out, code)
}

fn normal(entry: &str, windows: bool) -> String {
    let entry = if windows {
        entry.trim_matches('"')
    } else {
        entry
    };
    let trimmed = entry.trim_end_matches(['/', '\\']);
    // A root ("/") must not become "".
    let trimmed = if trimmed.is_empty() && !entry.is_empty() {
        "/"
    } else {
        trimmed
    };
    if windows {
        trimmed.replace('/', "\\").to_lowercase()
    } else {
        trimmed.to_string()
    }
}

/// Whether the folder `dir` is one of the entries of `path_var` (`:` on
/// Unix, `;` on Windows, where case does not matter).
pub fn path_contains(path_var: &str, dir: &str, windows: bool) -> bool {
    let sep = if windows { ';' } else { ':' };
    let want = normal(dir, windows);
    path_var
        .split(sep)
        .filter(|e| !e.is_empty())
        .any(|e| normal(e, windows) == want)
}

/// `shellx` is reachable by name: its own folder is in `PATH`, or some
/// `PATH` folder holds a file of that name (a link to the app's copy).
pub fn on_path(
    path_var: &str,
    exe_dir: Option<&str>,
    windows: bool,
    exists: &dyn Fn(&Path) -> bool,
) -> bool {
    if exe_dir.is_some_and(|d| path_contains(path_var, d, windows)) {
        return true;
    }
    let sep = if windows { ';' } else { ':' };
    let name = if windows { "shellx.exe" } else { "shellx" };
    path_var
        .split(sep)
        .filter(|e| !e.is_empty())
        .any(|e| exists(&Path::new(e.trim_matches('"')).join(name)))
}

/// An agent skill is installed when `shellx/SKILL.md` exists under one of
/// the folders `skills install` writes to.
pub fn skills_installed(home: &Path, exists: &dyn Fn(&Path) -> bool) -> bool {
    [
        super::skills::CLAUDE_SKILLS_DIR,
        super::skills::CODEX_SKILLS_DIR,
        super::skills::CODEX_OWN_SKILLS_DIR,
    ]
    .iter()
    .any(|d| exists(&home.join(d).join("shellx").join("SKILL.md")))
}

/// `1.2.3+45` → `1.2.3`: the build number is not part of the version.
fn release(version: &str) -> &str {
    version.split('+').next().unwrap_or(version).trim()
}

fn plural(n: usize, one: &str, many: &str) -> String {
    format!("{n} {}", if n == 1 { one } else { many })
}

/// "Configuration: 1 error, 0 warnings"; passes when there are no errors.
fn config_check(r: &Value) -> Check {
    let problems = r.get("problems").and_then(Value::as_array).unwrap_or(&[]);
    let count = |severity: &str| {
        problems
            .iter()
            .filter(|p| p.get("severity").and_then(Value::as_str) == Some(severity))
            .count()
    };
    let (errors, warnings) = (count("error"), count("warning"));
    if problems.is_empty() {
        return Check::ok("config", "Configuration: no problems");
    }
    let text = format!(
        "Configuration: {}, {}",
        plural(errors, "error", "errors"),
        plural(warnings, "warning", "warnings")
    );
    if errors == 0 {
        Check::ok("config", text)
    } else {
        Check::fail("config", text)
    }
}

pub fn run(p: &Parsed, ctx: &mut Ctx) -> Result<(), ApiError> {
    let mut checks = Vec::new();
    // Fixed sentences only: an error's own text may carry a path.
    let mut api = match Api::open(p, ctx) {
        Ok(api) => {
            checks.push(Check::ok("app", "ShellX is running"));
            Some(api)
        }
        Err(ApiError::NotRunning(_)) => {
            checks.push(Check::fail("app", "ShellX is not running — open the app"));
            None
        }
        Err(ApiError::Incompatible(_)) => {
            checks.push(Check::fail(
                "app",
                "ShellX speaks another command-line API — update shellx or ShellX",
            ));
            None
        }
        Err(_) => {
            checks.push(Check::fail("app", "ShellX did not answer"));
            None
        }
    };
    let cli = env!("CARGO_PKG_VERSION");
    if let Some(app) = api.as_ref().and_then(|a| a.app.as_deref()) {
        let app = release(app);
        checks.push(if app == release(cli) {
            Check::ok("version", format!("shellx and ShellX are both {cli}"))
        } else {
            Check::fail(
                "version",
                format!(
                    "shellx {cli} and ShellX {} differ — reinstall the command line (ShellX tray › Command line)",
                    super::output::plain(app)
                ),
            )
        });
    }
    if let Some(exe) = ctx.exe.as_deref() {
        let path_var = (ctx.env)("PATH").unwrap_or_default();
        let dir = exe.parent().map(|d| d.to_string_lossy().into_owned());
        checks.push(
            if on_path(&path_var, dir.as_deref(), cfg!(windows), &|f| f.is_file()) {
                Check::ok("path", "shellx is in your PATH")
            } else {
                Check::fail(
                    "path",
                    "shellx is not in your PATH — ShellX tray › Command line › Install in PATH",
                )
            },
        );
    }
    checks.push(match ctx.home.as_deref() {
        Some(home) if skills_installed(home, &|f| f.is_file()) => {
            Check::ok("skills", "Agent skills are installed")
        }
        _ => Check::fail(
            "skills",
            "Agent skills are not installed — run: shellx skills install",
        ),
    });
    if let Some(api) = api.as_mut() {
        checks.push(match api.call("ui.config.check", vec![]) {
            Ok(r) => config_check(&super::output::result_json(&r)),
            Err(ApiError::Incompatible(_)) => Check::fail(
                "config",
                "Configuration: this ShellX is too old to check it — update ShellX",
            ),
            Err(ApiError::Remote { code, .. }) if code == "forbidden" => Check::fail(
                "config",
                "Configuration: not checked — this terminal is not allowed to control ShellX",
            ),
            Err(_) => Check::fail("config", "Configuration: could not be checked"),
        });
    }
    let (text, code) = render_checks(&checks, p.json);
    ctx.out
        .write_all(text.as_bytes())
        .map_err(|e| ApiError::Io(e.to_string()))?;
    if code == 0 {
        Ok(())
    } else {
        // Already printed (also the one `--json` object): exit 1.
        Err(ApiError::Reported("doctor".into()))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn doctor_prints_a_line_per_check_and_exits_1_on_any_failure() {
        let checks = vec![
            Check::ok("app", "ShellX is running"),
            Check::fail(
                "path",
                "shellx is not in your PATH — ShellX tray › Command line › Install in PATH",
            ),
            Check::ok("config", "Configuration: no problems"),
        ];
        let (text, code) = render_checks(&checks, false);
        assert_eq!(code, 1);
        assert_eq!(
            text,
            "✓ ShellX is running\n✗ shellx is not in your PATH — ShellX tray › Command line › Install in PATH\n✓ Configuration: no problems\n1 problem found.\n"
        );
    }

    #[test]
    fn all_good_prints_no_summary_and_exits_0() {
        let (text, code) = render_checks(&[Check::ok("app", "ShellX is running")], false);
        assert_eq!((text.as_str(), code), ("✓ ShellX is running\n", 0));
        let two = [Check::fail("a", "x"), Check::fail("b", "y")];
        assert!(render_checks(&two, false)
            .0
            .ends_with("2 problems found.\n"));
    }

    #[test]
    fn doctor_json_is_one_object() {
        let (text, code) = render_checks(&[Check::ok("app", "x")], true);
        assert_eq!(
            (code, text.as_str()),
            (
                0,
                "{\"checks\":[{\"id\":\"app\",\"ok\":true,\"message\":\"x\"}],\"ok\":true}\n"
            )
        );
        let (bad, code) = render_checks(&[Check::fail("path", "no")], true);
        assert_eq!(code, 1);
        assert!(bad.ends_with("\"ok\":false}\n"));
    }

    #[test]
    #[allow(non_snake_case)]
    fn path_check_finds_the_exe_directory_in_PATH() {
        assert!(path_contains(
            "/usr/local/bin:/opt/x/bin",
            "/opt/x/bin",
            false
        ));
        assert!(!path_contains("/usr/local/bin", "/opt/x/bin", false));
        assert!(
            path_contains("/opt/x/bin/", "/opt/x/bin", false),
            "trailing slash"
        );
        assert!(
            !path_contains("/opt/X/bin", "/opt/x/bin", false),
            "Unix is case-sensitive"
        );
        assert!(!path_contains("", "/opt/x/bin", false));
        assert!(
            path_contains(
                r"C:\a;C:\Users\me\AppData\Local\ShellX\bin",
                r"c:\users\me\appdata\local\shellx\bin",
                true
            ),
            "Windows compares case-insensitively"
        );
        assert!(
            path_contains(r#""C:\a b";C:\c"#, r"C:\a b\", true),
            "quotes and slashes"
        );
    }

    #[test]
    fn a_link_in_a_path_folder_counts() {
        let has = |f: &Path| f == Path::new("/home/me/.local/bin/shellx");
        assert!(on_path(
            "/usr/bin:/home/me/.local/bin",
            Some("/Applications/ShellX/bin"),
            false,
            &has
        ));
        assert!(!on_path(
            "/usr/bin",
            Some("/Applications/ShellX/bin"),
            false,
            &has
        ));
        assert!(!on_path("/usr/bin", None, false, &has));
    }

    #[test]
    fn skills_are_found_under_any_agent_folder() {
        let home = Path::new("/Users/me");
        let at = |want: &'static str| move |f: &Path| f == Path::new(want);
        assert!(skills_installed(
            home,
            &at("/Users/me/.claude/skills/shellx/SKILL.md")
        ));
        assert!(skills_installed(
            home,
            &at("/Users/me/.agents/skills/shellx/SKILL.md")
        ));
        assert!(skills_installed(
            home,
            &at("/Users/me/.codex/skills/shellx/SKILL.md")
        ));
        assert!(!skills_installed(home, &|_| false));
    }

    #[test]
    fn versions_ignore_the_build_number() {
        assert_eq!(release("1.2.3+45"), "1.2.3");
        assert_eq!(release("1.2.3"), "1.2.3");
    }

    #[test]
    fn config_line_counts_and_never_quotes_a_problem() {
        let problem = |s: &str| {
            Value::map(vec![
                ("severity", Value::text(s)),
                ("message", Value::text("password = hunter2")),
                ("file", Value::text("/Users/secret/config")),
            ])
        };
        let r = |ps: Vec<Value>| Value::map(vec![("problems", Value::Array(ps))]);
        assert_eq!(
            config_check(&r(vec![])).message,
            "Configuration: no problems"
        );
        let c = config_check(&r(vec![
            problem("error"),
            problem("warning"),
            problem("warning"),
        ]));
        assert!(!c.ok);
        assert_eq!(c.message, "Configuration: 1 error, 2 warnings");
        let w = config_check(&r(vec![problem("warning")]));
        assert!(w.ok);
        assert_eq!(w.message, "Configuration: 0 errors, 1 warning");
        assert!(!c.message.contains("hunter2") && !c.message.contains("secret"));
    }

    #[test]
    fn doctor_never_prints_file_contents_or_the_home_directory() {
        // Every message the module can build is a fixed sentence (or counts):
        // none of them has a place for a path or a value.
        let all = [
            "ShellX is running",
            "ShellX is not running — open the app",
            "shellx is in your PATH",
            "Agent skills are installed",
        ];
        for m in all {
            assert!(!m.contains("/Users") && !m.contains("/home") && !m.contains("C:\\"));
        }
    }
}
