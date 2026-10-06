//! One table (D9) drives parsing, `help` and completions.

use std::ffi::OsStr;

pub struct Flag {
    pub name: &'static str,
    pub value: Option<&'static str>,
    pub help: &'static str,
    pub repeat: bool,
}

pub struct CommandSpec {
    pub path: &'static [&'static str],
    pub positionals: &'static [&'static str],
    pub flags: &'static [Flag],
    pub summary: &'static str,
    pub needs_ui: bool,
}

const fn f(name: &'static str, help: &'static str) -> Flag {
    Flag {
        name,
        value: None,
        help,
        repeat: false,
    }
}
const fn v(name: &'static str, value: &'static str, help: &'static str) -> Flag {
    Flag {
        name,
        value: Some(value),
        help,
        repeat: false,
    }
}
const fn r(name: &'static str, value: &'static str, help: &'static str) -> Flag {
    Flag {
        name,
        value: Some(value),
        help,
        repeat: true,
    }
}
const fn c(
    path: &'static [&'static str],
    positionals: &'static [&'static str],
    flags: &'static [Flag],
    summary: &'static str,
) -> CommandSpec {
    CommandSpec {
        path,
        positionals,
        flags,
        summary,
        needs_ui: true,
    }
}

pub static GLOBAL_FLAGS: &[Flag] = &[
    f("json", "print one JSON object (errors too) on stdout"),
    v(
        "socket",
        "ADDRESS",
        "host address (default: $SHELLX_SOCKET, then the endpoint file)",
    ),
    f("help", "show help for the command"),
];

const TIMEOUT: Flag = v(
    "timeout",
    "SECONDS",
    "give up after SECONDS (default 30, max 3600)",
);
const FOCUS: Flag = f(
    "focus",
    "select/focus the new object (default: leave the user's focus alone)",
);

pub static COMMANDS: &[CommandSpec] = &[
    CommandSpec {
        needs_ui: false,
        ..c(
            &["ls"],
            &[],
            &[f("ids", "print only ids, one per line")],
            "list workspaces, tabs and panes",
        )
    },
    c(
        &["new-tab"],
        &[],
        &[
            v("workspace", "W", "workspace id or name"),
            v("cwd", "DIR", "start directory"),
            v("cmd", "COMMAND", "type COMMAND once the shell is ready"),
            FOCUS,
        ],
        "open a tab; prints its id",
    ),
    c(
        &["split"],
        &[],
        &[
            f("right", "new pane to the right (default)"),
            f("down", "new pane below"),
            v(
                "pane",
                "PANE",
                "pane to split (default @self, else @focused)",
            ),
            v("cwd", "DIR", "start directory (default: the pane's)"),
            v("cmd", "COMMAND", "type COMMAND once the shell is ready"),
            FOCUS,
        ],
        "split a pane; prints the new pane's id",
    ),
    c(
        &["focus"],
        &["TARGET"],
        &[f("raise", "also bring the ShellX window to the front")],
        "select a tab or focus a pane (p<id>, t<id>, @self, @tab)",
    ),
    c(
        &["close"],
        &["TARGET"],
        &[f("force", "close even while a command runs")],
        "close a pane or a whole tab",
    ),
    c(
        &["send"],
        &["PANE"],
        &[
            v("text", "TEXT", "text to paste"),
            f("stdin", "paste text read from stdin"),
            f("enter", "press Enter after the text"),
            r(
                "key",
                "KEY",
                "press KEY (enter, tab, esc, up, ctrl-c, …); repeatable",
            ),
        ],
        "type into a pane as a paste",
    ),
    c(
        &["read"],
        &["PANE"],
        &[
            v(
                "lines",
                "N",
                "last N lines including scrollback (default: the screen)",
            ),
            f("ansi", "keep colors as SGR escapes"),
        ],
        "print a pane's screen or scrollback",
    ),
    c(
        &["rename"],
        &["TAB", "NAME..."],
        &[],
        "rename a tab (empty name: automatic title)",
    ),
    c(
        &["workspace", "new"],
        &["NAME?"],
        &[FOCUS],
        "create a workspace with one tab; prints its id",
    ),
    c(
        &["workspace", "rename"],
        &["WORKSPACE", "NAME..."],
        &[],
        "rename a workspace",
    ),
    c(
        &["workspace", "move"],
        &["TAB", "WORKSPACE"],
        &[],
        "move a tab to a workspace",
    ),
    CommandSpec {
        needs_ui: false,
        ..c(
            &["notify"],
            &["TEXT..."],
            &[
                v("title", "TITLE", "notification title"),
                v("pane", "PANE", "pane the notice belongs to (default @self)"),
            ],
            "show a ShellX notification (and push to the phone from a pane)",
        )
    },
    c(
        &["wait"],
        &["PANE"],
        &[
            f("idle", "until the shell is back at its prompt"),
            f("exit", "until the shell exits; prints its exit code"),
            v("match", "REGEX", "until REGEX matches the pane's text"),
            f("from-now", "with --match: only text after this call"),
            v("quiet", "MS", "with --idle: quiet time (default 500)"),
            TIMEOUT,
        ],
        "wait for a pane",
    ),
    c(
        &["events"],
        &[],
        &[
            f("follow", "keep printing until interrupted"),
            v("for", "SECONDS", "print events for SECONDS then exit"),
            v("kinds", "LIST", "comma-separated kinds (default: all)"),
        ],
        "print ShellX events as JSON lines",
    ),
    c(&["browser", "ls"], &[], &[], "list browser panes"),
    c(
        &["browser", "open"],
        &["URL"],
        &[
            v("tab", "TAB", "tab to split (default: the selected tab)"),
            v("pane", "PANE", "pane to split"),
            f("down", "below instead of right"),
            FOCUS,
        ],
        "open a browser pane; prints its id",
    ),
    c(
        &["browser", "nav"],
        &["PANE", "URL"],
        &[f("no-wait", "do not wait for the page to load"), TIMEOUT],
        "navigate a browser pane",
    ),
    c(&["browser", "back"], &["PANE"], &[], "go back"),
    c(&["browser", "forward"], &["PANE"], &[], "go forward"),
    c(&["browser", "reload"], &["PANE"], &[], "reload"),
    c(&["browser", "stop"], &["PANE"], &[], "stop loading"),
    c(
        &["browser", "close"],
        &["PANE"],
        &[],
        "close a browser pane",
    ),
    c(
        &["browser", "wait"],
        &["PANE"],
        &[TIMEOUT],
        "wait until the page has loaded",
    ),
    c(
        &["browser", "eval"],
        &["PANE"],
        &[
            v("script", "JS", "async function body; `return` a JSON value"),
            v("file", "FILE", "read the body from FILE ('-' = stdin)"),
            TIMEOUT,
        ],
        "run JavaScript; prints the JSON result",
    ),
    c(
        &["browser", "screenshot"],
        &["PANE"],
        &[v("out", "FILE", "copy the PNG to FILE")],
        "capture the visible page; prints the PNG path",
    ),
    c(
        &["browser", "console"],
        &["PANE"],
        &[
            v("since", "SEQ", "entries after SEQ"),
            v("level", "LEVEL", "log, info, warn, error or debug"),
            v("limit", "N", "at most N entries (≤ 200)"),
        ],
        "print console entries",
    ),
    c(
        &["browser", "network"],
        &["PANE"],
        &[
            v("since", "SEQ", "entries after SEQ"),
            v("limit", "N", "at most N entries (≤ 200)"),
        ],
        "print network entries (best effort)",
    ),
    c(
        &["browser", "query"],
        &["PANE", "SELECTOR"],
        &[v("limit", "N", "at most N elements (default 50)")],
        "text, value and href of matching elements",
    ),
    c(
        &["browser", "click"],
        &["PANE", "SELECTOR"],
        &[],
        "click the first matching element",
    ),
    c(
        &["browser", "fill"],
        &["PANE", "SELECTOR", "TEXT..."],
        &[],
        "set an input's value and fire input/change",
    ),
    CommandSpec {
        needs_ui: false,
        ..c(
            &["skills", "install"],
            &[],
            &[
                f(
                    "claude",
                    "install for Claude Code (~/.claude/skills/shellx)",
                ),
                f("codex", "install for Codex (~/.codex/skills/shellx)"),
                v("dir", "DIR", "install into DIR/shellx"),
                f("force", "overwrite without asking"),
            ],
            "install the ShellX skill for AI agents",
        )
    },
    CommandSpec {
        needs_ui: false,
        ..c(
            &["skills", "print"],
            &["FILE?"],
            &[],
            "print SKILL.md (or 'reference')",
        )
    },
    CommandSpec {
        needs_ui: false,
        ..c(
            &["completions"],
            &["SHELL"],
            &[],
            "print a completion script for zsh, bash or pwsh",
        )
    },
];

pub struct Parsed {
    pub spec: &'static CommandSpec,
    pub positionals: Vec<String>,
    pub flags: Vec<(&'static str, Option<String>)>,
    pub json: bool,
    pub socket: Option<String>,
}

impl Parsed {
    pub fn flag(&self, name: &str) -> Option<&str> {
        self.flags
            .iter()
            .find(|(n, _)| *n == name)
            .and_then(|(_, v)| v.as_deref())
    }
    pub fn has(&self, name: &str) -> bool {
        self.flags.iter().any(|(n, _)| *n == name)
    }
    pub fn all(&self, name: &str) -> Vec<&str> {
        self.flags
            .iter()
            .filter(|(n, _)| *n == name)
            .filter_map(|(_, v)| v.as_deref())
            .collect()
    }
    pub fn pos(&self, i: usize) -> Option<&str> {
        self.positionals.get(i).map(String::as_str)
    }
}

pub enum Invocation {
    Run(Parsed),
    Help(Option<&'static CommandSpec>),
    Version,
    Completions(String),
}

fn find(words: &[String]) -> Option<(&'static CommandSpec, usize)> {
    COMMANDS
        .iter()
        .filter(|c| c.path.len() <= words.len() && c.path.iter().zip(words).all(|(a, b)| a == b))
        .max_by_key(|c| c.path.len())
        .map(|c| (c, c.path.len()))
}

pub fn parse(args: &[String]) -> Result<Invocation, String> {
    match args.first().map(String::as_str) {
        None => return Ok(Invocation::Help(None)),
        Some("--version") if args.len() == 1 => return Ok(Invocation::Version),
        Some("help") | Some("--help") | Some("-h") => {
            let rest = &args[1..];
            if rest.is_empty() {
                return Ok(Invocation::Help(None));
            }
            return find(rest)
                .map(|(c, _)| Invocation::Help(Some(c)))
                .ok_or_else(|| format!("unknown command '{}'", rest.join(" ")));
        }
        _ => {}
    }
    let (spec, used) =
        find(args).ok_or_else(|| format!("unknown command '{}' (try: shellx help)", args[0]))?;
    let mut parsed = Parsed {
        spec,
        positionals: vec![],
        flags: vec![],
        json: false,
        socket: None,
    };
    let mut it = args[used..].iter();
    let mut only_positionals = false;
    while let Some(a) = it.next() {
        if only_positionals || !a.starts_with("--") || a == "-" {
            parsed.positionals.push(a.clone());
            continue;
        }
        if a == "--" {
            only_positionals = true;
            continue;
        }
        let (name, inline) = match a[2..].split_once('=') {
            Some((n, v)) => (n, Some(v.to_string())),
            None => (&a[2..], None),
        };
        if name == "help" {
            return Ok(Invocation::Help(Some(spec)));
        }
        let flag = spec
            .flags
            .iter()
            .chain(GLOBAL_FLAGS)
            .find(|fl| fl.name == name)
            .ok_or_else(|| format!("unknown flag --{name} for '{}'", spec.path.join(" ")))?;
        let value = match (flag.value, inline) {
            (None, None) => None,
            (None, Some(_)) => return Err(format!("--{name} takes no value")),
            (Some(_), Some(v)) => Some(v),
            (Some(p), None) => Some(
                it.next()
                    .cloned()
                    .ok_or_else(|| format!("--{name} needs {p}"))?,
            ),
        };
        if !flag.repeat && parsed.has(flag.name) {
            return Err(format!("--{name} given twice"));
        }
        match flag.name {
            "json" => parsed.json = true,
            "socket" => parsed.socket = value,
            _ => parsed.flags.push((flag.name, value)),
        }
    }
    let required = spec
        .positionals
        .iter()
        .filter(|p| !p.ends_with('?'))
        .count();
    let rest = spec.positionals.last().is_some_and(|p| p.ends_with("..."));
    let n = parsed.positionals.len();
    if n < required || (!rest && n > spec.positionals.len()) {
        return Err(format!(
            "usage: shellx {} {}",
            spec.path.join(" "),
            spec.positionals.join(" ")
        ));
    }
    if spec.path == ["completions"] {
        return Ok(Invocation::Completions(parsed.positionals[0].clone()));
    }
    Ok(Invocation::Run(parsed))
}

pub const EXIT_CODES: &str = "Exit codes: 0 ok · 1 error · 2 usage · 3 ShellX not running · 4 not found · 5 timeout · 6 refused · 7 incompatible ShellX · 8 ShellX window closed";

pub fn help_text(spec: Option<&CommandSpec>) -> String {
    let mut s = String::new();
    match spec {
        None => {
            s.push_str("Usage: shellx <command> [flags]   (drive ShellX from scripts and AI agents)\n\nCommands:\n");
            for c in COMMANDS {
                s.push_str(&format!("  {:<22} {}\n", c.path.join(" "), c.summary));
            }
            s.push_str("\nTargets: p<id> pane, t<id> tab, w:<id> or a name for workspaces, @self (this pane), @tab (this tab), @focused.\n");
            s.push_str("Global flags: --json, --socket ADDRESS, --help.\n");
            s.push_str(EXIT_CODES);
            s.push_str("\nMore: shellx help <command>; shellx skills print reference\n");
        }
        Some(c) => {
            s.push_str(&format!(
                "Usage: shellx {} {}\n\n{}\n\nFlags:\n",
                c.path.join(" "),
                c.positionals.join(" "),
                c.summary
            ));
            for fl in c.flags.iter().chain(GLOBAL_FLAGS) {
                let name = match fl.value {
                    Some(v) => format!("--{} {v}", fl.name),
                    None => format!("--{}", fl.name),
                };
                s.push_str(&format!("  {name:<22} {}\n", fl.help));
            }
            s.push('\n');
            s.push_str(EXIT_CODES);
            s.push('\n');
        }
    }
    s
}

fn words_after(prefix: &[&str]) -> Vec<&'static str> {
    let mut out: Vec<&'static str> = COMMANDS
        .iter()
        .filter(|c| c.path.len() > prefix.len() && c.path[..prefix.len()] == *prefix)
        .map(|c| c.path[prefix.len()])
        .collect();
    out.dedup();
    out
}

pub fn completion_script(shell: &str) -> Option<String> {
    let top = words_after(&[]).join(" ");
    let mut cases = String::new();
    for c in COMMANDS {
        let flags: Vec<String> = c
            .flags
            .iter()
            .chain(GLOBAL_FLAGS)
            .map(|f| format!("--{}", f.name))
            .collect();
        cases.push_str(&format!("{}|{}\n", c.path.join(" "), flags.join(" ")));
    }
    let subs = format!(
        "workspace:{} browser:{} skills:{}",
        words_after(&["workspace"]).join(","),
        words_after(&["browser"]).join(","),
        words_after(&["skills"]).join(",")
    );
    match shell {
        "bash" | "zsh" => Some(format!(
            r#"# shellx completion ({shell}). Load with: source <(shellx completions {shell})
{zsh}_shellx_flags() {{
  local key="$1"
  while IFS='|' read -r path flags; do [ "$path" = "$key" ] && echo "$flags"; done <<'EOF'
{cases}EOF
}}
_shellx() {{
  local cur="${{COMP_WORDS[COMP_CWORD]}}" w1="${{COMP_WORDS[1]}}" w2="${{COMP_WORDS[2]}}"
  if [ "$COMP_CWORD" -eq 1 ]; then COMPREPLY=($(compgen -W "{top}" -- "$cur")); return; fi
  case "{subs}" in *"$w1:"*) if [ "$COMP_CWORD" -eq 2 ]; then
      local s="{subs}"; s="${{s#*$w1:}}"; s="${{s%% *}}"; COMPREPLY=($(compgen -W "${{s//,/ }}" -- "$cur")); return; fi;; esac
  local key="$w1"; case "$w1" in workspace|browser|skills) key="$w1 $w2";; esac
  if [[ "$cur" == --* ]]; then COMPREPLY=($(compgen -W "$(_shellx_flags "$key")" -- "$cur")); return; fi
  COMPREPLY=($(compgen -W "$(shellx ls --ids 2>/dev/null)" -- "$cur"))
}}
complete -F _shellx shellx
"#,
            zsh = if shell == "zsh" {
                "autoload -U +X bashcompinit && bashcompinit\n"
            } else {
                ""
            },
        )),
        "pwsh" => Some(format!(
            r#"# shellx completion (PowerShell). Load with: shellx completions pwsh | Out-String | Invoke-Expression
$__shellxFlags = @'
{cases}'@
Register-ArgumentCompleter -Native -CommandName shellx, shellx.exe -ScriptBlock {{
  param($word, $ast, $cursor)
  $w = $ast.CommandElements | Select-Object -Skip 1 | ForEach-Object {{ $_.ToString() }}
  if ($w.Count -le 1 -and -not $word.StartsWith('-')) {{ $c = '{top}'.Split(' ') }}
  elseif ($word.StartsWith('--')) {{
    $key = if ('workspace','browser','skills' -contains $w[0]) {{ "$($w[0]) $($w[1])" }} else {{ $w[0] }}
    $line = ($__shellxFlags -split "`n") | Where-Object {{ $_.StartsWith("$key|") }} | Select-Object -First 1
    $c = if ($line) {{ $line.Split('|')[1].Split(' ') }} else {{ @() }}
  }} else {{ $c = (& shellx ls --ids 2>$null) }}
  $c | Where-Object {{ $_ -like "$word*" }} | ForEach-Object {{ [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_) }}
}}
"#
        )),
        _ => None,
    }
}

#[allow(clippy::let_and_return)] // one binding per platform
pub fn is_cli_name(argv0: &OsStr) -> bool {
    let name = std::path::Path::new(argv0)
        .file_name()
        .and_then(OsStr::to_str)
        .unwrap_or("");
    #[cfg(windows)]
    let name = name.to_ascii_lowercase();
    #[cfg(windows)]
    let name = name.strip_suffix(".exe").unwrap_or(&name).to_string();
    name == "shellx"
}

#[cfg(test)]
mod tests {
    use super::*;

    fn p(args: &[&str]) -> Result<Invocation, String> {
        parse(&args.iter().map(|s| s.to_string()).collect::<Vec<_>>())
    }
    fn run(args: &[&str]) -> Parsed {
        match p(args).unwrap() {
            Invocation::Run(x) => x,
            _ => panic!("not a run: {args:?}"),
        }
    }

    #[test]
    fn every_spec_command_exists() {
        let names: Vec<String> = COMMANDS.iter().map(|c| c.path.join(" ")).collect();
        for want in [
            "ls",
            "new-tab",
            "split",
            "focus",
            "close",
            "send",
            "read",
            "rename",
            "workspace new",
            "workspace rename",
            "workspace move",
            "notify",
            "wait",
            "events",
            "browser ls",
            "browser open",
            "browser nav",
            "browser back",
            "browser forward",
            "browser reload",
            "browser stop",
            "browser close",
            "browser wait",
            "browser eval",
            "browser screenshot",
            "browser console",
            "browser network",
            "browser query",
            "browser click",
            "browser fill",
            "skills install",
            "skills print",
            "completions",
        ] {
            assert!(names.contains(&want.to_string()), "{want}");
        }
    }

    #[test]
    fn flags_and_positionals() {
        let x = run(&["split", "--down", "--cmd=npm run dev", "--json"]);
        assert_eq!(x.spec.path, &["split"]);
        assert!(x.has("down"));
        assert_eq!(x.flag("cmd"), Some("npm run dev"));
        assert!(x.json);
        let s = run(&[
            "send", "p12", "--text", "ls -la", "--enter", "--key", "ctrl-c", "--key", "up",
        ]);
        assert_eq!(s.pos(0), Some("p12"));
        assert_eq!(s.all("key"), vec!["ctrl-c", "up"]);
        let n = run(&["notify", "--title", "CI", "Build", "xong"]);
        assert_eq!(n.positionals, vec!["Build", "xong"]);
        let w = run(&["workspace", "rename", "api", "Back end"]);
        assert_eq!(w.positionals, vec!["api", "Back end"]);
        let d = run(&["send", "p1", "--text", "--", "--enter"]);
        assert_eq!(d.flag("text"), Some("--"));
    }

    #[test]
    fn usage_errors() {
        for bad in [
            &["bogus"][..],
            &["split", "--sideways"],
            &["read"],
            &["send", "p1", "--text"],
            &["workspace"],
            &["focus", "p1", "extra"],
            &["split", "--right", "--right"],
        ] {
            assert!(p(bad).is_err(), "{bad:?}");
        }
    }

    #[test]
    fn help_version_completions() {
        assert!(matches!(p(&[]).unwrap(), Invocation::Help(None)));
        assert!(matches!(p(&["help"]).unwrap(), Invocation::Help(None)));
        assert!(matches!(p(&["--version"]).unwrap(), Invocation::Version));
        match p(&["help", "split"]).unwrap() {
            Invocation::Help(Some(c)) => assert_eq!(c.path, &["split"]),
            _ => panic!(),
        }
        assert!(matches!(
            p(&["split", "--help"]).unwrap(),
            Invocation::Help(Some(_))
        ));
        let all = help_text(None);
        for c in COMMANDS {
            assert!(all.contains(&c.path.join(" ")), "{:?}", c.path);
        }
        assert!(all.contains("Exit codes"));
        for sh in ["zsh", "bash", "pwsh"] {
            let s = completion_script(sh).unwrap();
            assert!(
                s.contains("new-tab") && s.contains("--enter") && s.contains("ls --ids"),
                "{sh}"
            );
        }
        assert!(completion_script("fish").is_none());
    }

    #[test]
    fn name_dispatch() {
        use std::ffi::OsStr;
        assert!(is_cli_name(OsStr::new("/Users/a/cli/shellx")));
        assert!(is_cli_name(OsStr::new("shellx")));
        assert!(!is_cli_name(OsStr::new("/x/shellx-term")));
        #[cfg(windows)]
        assert!(is_cli_name(OsStr::new(r"C:\x\SHELLX.EXE")));
    }
}
