//! A9 D39: where ShellX's configuration lives and how `shellx config …`
//! prints. The path rule is the one of
//! `apps/desktop/lib/src/config/config_paths.dart`; both test suites pin
//! the same strings (the absolute-path table and the path examples).

use super::args::Parsed;
use super::client::ApiError;
use super::run::Ctx;
use super::value::{to_json, Value};

pub struct ConfigPaths {
    pub shellx: String,
    pub ghostty: Vec<String>,
}

/// The one absolute-path rule (A9 D3): POSIX starts with `/`. Windows: a
/// drive root `X:\` / `X:/` or a UNC share `\\server\share`; root-relative
/// (`\x`, `/x`), drive-relative (`C:x`), `//server/share` and the device
/// namespaces (`\\.\`, `\\?\`) are refused.
pub fn is_absolute(path: &str, windows: bool) -> bool {
    if !windows {
        return path.starts_with('/');
    }
    let b = path.as_bytes();
    if b.len() >= 3 && b[0].is_ascii_alphabetic() && b[1] == b':' && (b[2] == b'\\' || b[2] == b'/')
    {
        return true;
    }
    unc_root_len(path).is_some_and(|(len, server)| len > 0 && server != "." && server != "?")
}

/// `\\server\share` at the start: the length of that prefix and the server.
fn unc_root_len(path: &str) -> Option<(usize, &str)> {
    let rest = path.strip_prefix(r"\\")?;
    let server_end = rest.find(['\\', '/'])?;
    if server_end == 0 || !rest[server_end..].starts_with('\\') {
        return None;
    }
    let after = &rest[server_end + 1..];
    let share_end = after.find(['\\', '/']).unwrap_or(after.len());
    if share_end == 0 {
        return None;
    }
    Some((2 + server_end + 1 + share_end, &rest[..server_end]))
}

/// `p.join(..).normalize()` of the Dart rule: separators unified, `.`
/// and `..` resolved (never above the root), no trailing separator
/// (except a bare root).
fn normalize(path: &str, windows: bool) -> String {
    let sep = if windows { '\\' } else { '/' };
    let path = if windows {
        path.replace('/', "\\")
    } else {
        path.to_string()
    };
    let (root, rest) = if windows {
        match unc_root_len(&path) {
            Some((len, _)) => (path[..len].to_string(), path[len..].to_string()),
            None => (path[..3].to_string(), path[3..].to_string()),
        }
    } else {
        ("/".to_string(), path.trim_start_matches('/').to_string())
    };
    let mut parts: Vec<&str> = Vec::new();
    for part in rest.split(sep) {
        match part {
            "" | "." => {}
            ".." => {
                parts.pop();
            }
            p => parts.push(p),
        }
    }
    let mut out = root;
    let tail = parts.join(&sep.to_string());
    if !out.ends_with(sep) && !tail.is_empty() {
        out.push(sep);
    }
    out.push_str(&tail);
    out
}

fn join(base: &str, parts: &[&str], windows: bool) -> String {
    let sep = if windows { '\\' } else { '/' };
    let mut s = base.to_string();
    for part in parts {
        if !s.ends_with(['/', '\\']) {
            s.push(sep);
        }
        s.push_str(part);
    }
    normalize(&s, windows)
}

/// Null when the home directory is empty or not absolute; an
/// `XDG_CONFIG_HOME` or `APPDATA` that is not absolute is ignored.
pub fn config_paths(env: &dyn Fn(&str) -> Option<String>, windows: bool) -> Option<ConfigPaths> {
    let home = env(if windows { "USERPROFILE" } else { "HOME" })?;
    if !is_absolute(&home, windows) {
        return None;
    }
    let absolute = |name: &str| env(name).filter(|v| is_absolute(v, windows));
    let xdg = absolute("XDG_CONFIG_HOME");
    let shellx_dir = match (&xdg, windows) {
        (Some(x), _) => join(x, &["shellx"], windows),
        (None, true) => {
            let app = absolute("APPDATA")
                .unwrap_or_else(|| join(&home, &["AppData", "Roaming"], windows));
            join(&app, &["ShellX"], windows)
        }
        (None, false) => join(&home, &[".config", "shellx"], windows),
    };
    let base = xdg.unwrap_or_else(|| join(&home, &[".config"], windows));
    let ghostty_dir = join(&base, &["ghostty"], windows);
    let mut ghostty = vec![
        join(&ghostty_dir, &["config.ghostty"], windows),
        join(&ghostty_dir, &["config"], windows),
    ];
    if !windows {
        let mac = join(
            &home,
            &["Library", "Application Support", "com.mitchellh.ghostty"],
            windows,
        );
        ghostty.push(join(&mac, &["config.ghostty"], windows));
        ghostty.push(join(&mac, &["config"], windows));
    }
    Some(ConfigPaths {
        shellx: join(&shellx_dir, &["config"], windows),
        ghostty,
    })
}

/// `shellx config path [--ghostty]`: local, ShellX need not run.
pub fn print_path(p: &Parsed, ctx: &mut Ctx) -> Result<(), ApiError> {
    let paths = config_paths(ctx.env, cfg!(windows)).ok_or_else(|| {
        ApiError::Usage("the home directory is not set to an absolute path".into())
    })?;
    let io = |e: std::io::Error| ApiError::Io(e.to_string());
    if p.json {
        let v = Value::map(vec![
            ("shellx", Value::text(paths.shellx.clone())),
            (
                "ghostty",
                Value::Array(paths.ghostty.iter().map(Value::text).collect()),
            ),
        ]);
        return writeln!(ctx.out, "{}", to_json(&v)).map_err(io);
    }
    writeln!(ctx.out, "{}", paths.shellx).map_err(io)?;
    if p.has("ghostty") {
        for g in &paths.ghostty {
            writeln!(ctx.out, "{g}").map_err(io)?;
        }
    }
    Ok(())
}

fn text<'a>(v: &'a Value, key: &str) -> &'a str {
    v.get(key).and_then(Value::as_str).unwrap_or("")
}

/// The stdout text and exit code of `config check|reload|show` for a
/// result; with `--json` exactly one JSON object (A7 D11). `check` and
/// `reload` exit 1 when a problem is an error.
pub fn render(path: &str, json: bool, result: &Value) -> (String, i32) {
    let problems = result
        .get("problems")
        .and_then(Value::as_array)
        .unwrap_or(&[]);
    let errors = problems.iter().any(|p| text(p, "severity") == "error");
    let code = i32::from(errors);
    if json {
        return (format!("{}\n", to_json(result)), code);
    }
    let mut out = String::new();
    if path == "config show" {
        if let Some(t) = result.get("template").and_then(Value::as_str) {
            return (t.to_string(), 0);
        }
        for v in result
            .get("values")
            .and_then(Value::as_array)
            .unwrap_or(&[])
        {
            out.push_str(&format!(
                "{} = {}  # {}\n",
                text(v, "key"),
                text(v, "value"),
                text(v, "source")
            ));
        }
        return (out, 0);
    }
    for p in problems {
        let line = p.get("line").and_then(Value::as_i64).unwrap_or(0);
        let place = if line > 0 {
            format!("{}:{line}", text(p, "file"))
        } else {
            text(p, "file").to_string()
        };
        out.push_str(&format!(
            "{place}: {}: {}\n",
            text(p, "severity"),
            text(p, "message")
        ));
    }
    if problems.is_empty() && path == "config check" {
        out.push_str("no problems\n");
    }
    (out, code)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn env<'a>(pairs: &'a [(&'a str, &'a str)]) -> impl Fn(&str) -> Option<String> + 'a {
        move |k| {
            pairs
                .iter()
                .find(|(n, _)| *n == k)
                .map(|(_, v)| v.to_string())
        }
    }

    // The same strings as apps/desktop/test/config/config_paths_test.dart.
    #[test]
    fn macos_without_xdg() {
        let p = config_paths(&env(&[("HOME", "/Users/me")]), false).unwrap();
        assert_eq!(p.shellx, "/Users/me/.config/shellx/config");
        assert_eq!(
            p.ghostty,
            vec![
                "/Users/me/.config/ghostty/config.ghostty",
                "/Users/me/.config/ghostty/config",
                "/Users/me/Library/Application Support/com.mitchellh.ghostty/config.ghostty",
                "/Users/me/Library/Application Support/com.mitchellh.ghostty/config",
            ]
        );
    }

    #[test]
    fn xdg_absolute_only() {
        let p = config_paths(
            &env(&[("HOME", "/Users/me"), ("XDG_CONFIG_HOME", "/x/cfg")]),
            false,
        )
        .unwrap();
        assert_eq!(p.shellx, "/x/cfg/shellx/config");
        assert_eq!(p.ghostty[0], "/x/cfg/ghostty/config.ghostty");
        let r = config_paths(
            &env(&[("HOME", "/Users/me"), ("XDG_CONFIG_HOME", "cfg")]),
            false,
        )
        .unwrap();
        assert_eq!(r.shellx, "/Users/me/.config/shellx/config");
        // Normalised: a trailing slash or a dot segment does not show.
        let n = config_paths(
            &env(&[("HOME", "/Users/me"), ("XDG_CONFIG_HOME", "/x/./cfg//")]),
            false,
        )
        .unwrap();
        assert_eq!(n.shellx, "/x/cfg/shellx/config");
    }

    #[test]
    fn windows_appdata() {
        let p = config_paths(
            &env(&[
                ("USERPROFILE", r"C:\Users\me"),
                ("APPDATA", r"C:\Users\me\AppData\Roaming"),
            ]),
            true,
        )
        .unwrap();
        assert_eq!(p.shellx, r"C:\Users\me\AppData\Roaming\ShellX\config");
        assert_eq!(
            p.ghostty,
            vec![
                r"C:\Users\me\.config\ghostty\config.ghostty",
                r"C:\Users\me\.config\ghostty\config"
            ]
        );
        let q = config_paths(&env(&[("USERPROFILE", r"C:\Users\me")]), true).unwrap();
        assert_eq!(q.shellx, r"C:\Users\me\AppData\Roaming\ShellX\config");
        assert!(config_paths(&env(&[]), true).is_none());
    }

    #[test]
    fn windows_xdg_and_appdata_must_be_absolute() {
        for xdg in [r"\cfg", "/cfg", "C:cfg", r"\\.\cfg", "cfg"] {
            let p = config_paths(
                &env(&[
                    ("USERPROFILE", r"C:\Users\me"),
                    ("XDG_CONFIG_HOME", xdg),
                    ("APPDATA", r"\AppData"),
                ]),
                true,
            )
            .unwrap();
            assert_eq!(
                p.shellx, r"C:\Users\me\AppData\Roaming\ShellX\config",
                "{xdg}"
            );
            assert_eq!(p.ghostty[0], r"C:\Users\me\.config\ghostty\config.ghostty");
        }
        let d = config_paths(
            &env(&[
                ("USERPROFILE", r"C:\Users\me"),
                ("XDG_CONFIG_HOME", "D:/cfg"),
            ]),
            true,
        )
        .unwrap();
        assert_eq!(d.shellx, r"D:\cfg\shellx\config");
        assert_eq!(d.ghostty[0], r"D:\cfg\ghostty\config.ghostty");
        let u = config_paths(
            &env(&[
                ("USERPROFILE", r"C:\Users\me"),
                ("APPDATA", r"\\srv\home\me"),
            ]),
            true,
        )
        .unwrap();
        assert_eq!(u.shellx, r"\\srv\home\me\ShellX\config");
    }

    #[test]
    fn an_empty_or_relative_home_is_refused() {
        for (windows, home) in [
            (false, ""),
            (false, "Users/me"),
            (true, ""),
            (true, r"\Users\me"),
            (true, r"C:Users\me"),
        ] {
            let key = if windows { "USERPROFILE" } else { "HOME" };
            assert!(
                config_paths(&env(&[(key, home)]), windows).is_none(),
                "{home}"
            );
        }
        assert!(config_paths(&env(&[]), false).is_none());
    }

    // The table of config_paths_test.dart, string for string.
    #[test]
    fn the_shared_absolute_path_table() {
        let windows = [
            (r"C:\", true),
            (r"C:\x", true),
            ("C:/x", true),
            (r"c:\Users\me", true),
            (r"\\server\share", true),
            (r"\\server\share\x", true),
            (r"\x", false),
            ("/x", false),
            ("C:x", false),
            ("C:", false),
            (r"\\.\pipe\x", false),
            (r"\\?\C:\x", false),
            (r"\\server", false),
            (r"\\server\", false),
            (r"\\.\share", false),
            (r"\\?\share", false),
            ("//server/share", false),
            (r"~\x", false),
            ("~", false),
            (r".\x", false),
            ("x", false),
            ("", false),
        ];
        for (path, want) in windows {
            assert_eq!(is_absolute(path, true), want, "windows {path:?}");
        }
        let posix = [
            ("/", true),
            ("/x", true),
            ("/Users/me", true),
            ("x", false),
            ("./x", false),
            ("~/x", false),
            ("~", false),
            (r"C:\x", false),
            ("", false),
        ];
        for (path, want) in posix {
            assert_eq!(is_absolute(path, false), want, "posix {path:?}");
        }
    }

    fn problem(sev: &str, line: i64) -> Value {
        Value::map(vec![
            ("file", Value::text("/c/config")),
            ("line", Value::Int(line)),
            ("severity", Value::text(sev)),
            ("code", Value::text("badValue")),
            (
                "message",
                Value::text("font-size: “to” is not valid (expected 9–28)"),
            ),
        ])
    }

    #[test]
    fn check_prints_file_line_severity_and_exits_1_on_errors() {
        let v = Value::map(vec![
            (
                "problems",
                Value::Array(vec![problem("error", 3), problem("warning", 0)]),
            ),
            ("generation", Value::Int(1)),
        ]);
        let (out, code) = render("config check", false, &v);
        assert_eq!(
            out,
            "/c/config:3: error: font-size: “to” is not valid (expected 9–28)\n/c/config: warning: font-size: “to” is not valid (expected 9–28)\n"
        );
        assert_eq!(code, 1);
        let (json, code) = render("config check", true, &v);
        assert_eq!(json.lines().count(), 1);
        assert!(json.starts_with('{'));
        assert_eq!(code, 1);
    }

    #[test]
    fn clean_check_and_reload() {
        let v = Value::map(vec![
            ("problems", Value::Array(vec![])),
            ("generation", Value::Int(2)),
        ]);
        assert_eq!(
            render("config check", false, &v),
            ("no problems\n".to_string(), 0)
        );
        assert_eq!(render("config reload", false, &v), (String::new(), 0));
        let warn = Value::map(vec![(
            "problems",
            Value::Array(vec![problem("warning", 1)]),
        )]);
        assert_eq!(render("config reload", false, &warn).1, 0);
        assert_eq!(render("config reload", true, &warn).1, 0);
    }

    #[test]
    fn show_values_and_template() {
        let v = Value::map(vec![(
            "values",
            Value::Array(vec![Value::map(vec![
                ("key", Value::text("font-size")),
                ("value", Value::text("16")),
                ("source", Value::text("/c/config:2")),
            ])]),
        )]);
        assert_eq!(
            render("config show", false, &v),
            ("font-size = 16  # /c/config:2\n".to_string(), 0)
        );
        let t = Value::map(vec![("template", Value::text("# hi\n"))]);
        assert_eq!(render("config show", false, &t), ("# hi\n".to_string(), 0));
    }
}
