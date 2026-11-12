//! Local shells on Windows: command lines by Windows rules, finding programs, the catalogue.

use serde::{Deserialize, Serialize};

/// The shells ShellX knows how to start.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub enum ShellKind {
    #[serde(rename = "pwsh")]
    Pwsh,
    #[serde(rename = "windows_powershell")]
    WindowsPowerShell,
    #[serde(rename = "cmd")]
    Cmd,
    #[serde(rename = "git_bash")]
    GitBash,
    #[serde(rename = "wsl")]
    Wsl,
}

/// A program to start in a pane. `kind` is `None` for a custom command line.
/// `osc7_hook` says the arguments already carry the prompt hook that reports the
/// working directory.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ShellLaunch {
    pub kind: Option<ShellKind>,
    pub program: String,
    pub args: Vec<String>,
    pub osc7_hook: bool,
}

/// What the machine tells us about where shells live. The Windows inputs are
/// `%SystemRoot%`, `%ProgramFiles%`, `%ComSpec%`, `%PATH%` and
/// `HKLM\SOFTWARE\GitForWindows\InstallPath`; an absent one is `None` (`path`: empty).
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct ShellProbe {
    pub system_root: Option<String>,
    pub program_files: Option<String>,
    pub comspec: Option<String>,
    pub path: String,
    pub git_install_path: Option<String>,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum CommandLineError {
    Empty,
    UnclosedQuote,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum CustomShellError {
    Empty,
    UnclosedQuote,
    /// The program (as typed) is not a file and is not on `PATH`.
    NotFound(String),
}

impl From<CommandLineError> for CustomShellError {
    fn from(e: CommandLineError) -> Self {
        match e {
            CommandLineError::Empty => CustomShellError::Empty,
            CommandLineError::UnclosedQuote => CustomShellError::UnclosedQuote,
        }
    }
}

fn is_blank(c: char) -> bool {
    c == ' ' || c == '\t'
}

/// Splits a command line like Windows does: argv[0] as `CommandLineToArgvW` reads it
/// (quoted up to the next quote, else up to the first blank, no escapes), later arguments by
/// the msvcrt (2008+) rules. A quote left open is an error (Windows would accept it).
pub fn parse_command_line(line: &str) -> Result<Vec<String>, CommandLineError> {
    let chars: Vec<char> = line.chars().collect();
    let mut i = 0;
    while i < chars.len() && is_blank(chars[i]) {
        i += 1;
    }
    if i == chars.len() {
        return Err(CommandLineError::Empty);
    }
    let mut out = Vec::new();
    let mut program = String::new();
    if chars[i] == '"' {
        i += 1;
        loop {
            match chars.get(i) {
                None => return Err(CommandLineError::UnclosedQuote),
                Some('"') => {
                    i += 1;
                    break;
                }
                Some(c) => program.push(*c),
            }
            i += 1;
        }
    } else {
        while i < chars.len() && !is_blank(chars[i]) {
            program.push(chars[i]);
            i += 1;
        }
    }
    if program.is_empty() {
        return Err(CommandLineError::Empty);
    }
    out.push(program);

    loop {
        while i < chars.len() && is_blank(chars[i]) {
            i += 1;
        }
        if i >= chars.len() {
            break;
        }
        let mut arg = String::new();
        let mut in_quotes = false;
        while i < chars.len() {
            let c = chars[i];
            if c == '\\' {
                let mut n = 0;
                while chars.get(i) == Some(&'\\') {
                    n += 1;
                    i += 1;
                }
                if chars.get(i) == Some(&'"') {
                    arg.extend(std::iter::repeat_n('\\', n / 2));
                    if n % 2 == 1 {
                        arg.push('"');
                        i += 1;
                    }
                } else {
                    arg.extend(std::iter::repeat_n('\\', n));
                }
            } else if c == '"' {
                if in_quotes {
                    if chars.get(i + 1) == Some(&'"') {
                        arg.push('"');
                        i += 2;
                    } else {
                        in_quotes = false;
                        i += 1;
                    }
                } else {
                    in_quotes = true;
                    i += 1;
                }
            } else if is_blank(c) && !in_quotes {
                break;
            } else {
                arg.push(c);
                i += 1;
            }
        }
        if in_quotes {
            return Err(CommandLineError::UnclosedQuote);
        }
        out.push(arg);
    }
    Ok(out)
}

fn file_name(path: &str) -> &str {
    path.rsplit(['\\', '/']).next().unwrap_or(path)
}

fn is_separator(c: char) -> bool {
    c == '\\' || c == '/'
}

/// `X:\...`, `X:/...` or `\\server\...` (two separators, then a server name). An empty, `.`,
/// relative, drive-relative (`C:x`) or bare `\\` path is not: the process would resolve it
/// against whatever folder ShellX was started from.
fn is_absolute(path: &str) -> bool {
    let c: Vec<char> = path.chars().take(3).collect();
    let drive = c.len() == 3 && c[0].is_ascii_alphabetic() && c[1] == ':' && is_separator(c[2]);
    let unc = c.len() == 3 && is_separator(c[0]) && is_separator(c[1]) && !is_separator(c[2]);
    drive || unc
}

/// Finds the file `program` names. A name with `\`, `/` or `:` must be an absolute path (a
/// relative one gives `None`); it is checked as given, then with `.exe` added when it has no
/// extension; any other name is looked up in each
/// `;`-separated `PATH` entry (quotes stripped), plain then `.exe`. Entries that are not
/// absolute (empty, `.`, relative) are skipped, so a program in ShellX's working folder is
/// never chosen. The first existing file wins.
pub fn resolve_program(
    program: &str,
    probe: &ShellProbe,
    exists: &dyn Fn(&str) -> bool,
) -> Option<String> {
    if program.is_empty() {
        return None;
    }
    if program.contains(['\\', '/', ':']) {
        // a path must be absolute: a relative one would be looked for in ShellX's folder
        if !is_absolute(program) {
            return None;
        }
        if exists(program) {
            return Some(program.to_string());
        }
        if !file_name(program).contains('.') {
            let with_exe = format!("{program}.exe");
            if exists(&with_exe) {
                return Some(with_exe);
            }
        }
        return None;
    }
    for entry in probe.path.split(';') {
        let entry = entry.trim().trim_matches('"');
        if !is_absolute(entry) {
            continue;
        }
        let dir = entry.trim_end_matches('\\');
        for candidate in [format!("{dir}\\{program}"), format!("{dir}\\{program}.exe")] {
            if exists(&candidate) {
                return Some(candidate);
            }
        }
    }
    None
}

/// A custom shell typed as a command line: its program must exist (the Settings field
/// calls this on every edit). The result has no kind and no prompt hook. A whole line that
/// is an absolute path to a file (spaces allowed, `.exe` optional) is that program with no
/// arguments. The program of a parsed line is a bare name or an absolute path, never a
/// relative path.
pub fn custom_launch(
    line: &str,
    probe: &ShellProbe,
    exists: &dyn Fn(&str) -> bool,
) -> Result<ShellLaunch, CustomShellError> {
    // An unquoted path with spaces that names a file (with or without `.exe`) is that program
    // with no arguments. Only an absolute path can be one: a bare name is looked up on PATH
    // and a relative path is refused, so the current folder is never searched.
    let whole = line.trim();
    if is_absolute(whole)
        && let Some(program) = resolve_program(whole, probe, exists)
    {
        return Ok(ShellLaunch {
            kind: None,
            program,
            args: Vec::new(),
            osc7_hook: false,
        });
    }
    let mut parts = parse_command_line(line)?.into_iter();
    let typed = parts.next().ok_or(CustomShellError::Empty)?;
    let program =
        resolve_program(&typed, probe, exists).ok_or(CustomShellError::NotFound(typed))?;
    Ok(ShellLaunch {
        kind: None,
        program,
        args: parts.collect(),
        osc7_hook: false,
    })
}

/// PowerShell: wrap the profile's `prompt` so the working directory (OSC 7) is written at
/// every prompt. The wrapper calls the original FIRST, so a theme (oh-my-posh, starship)
/// still reads the real `$?` of the user's last command, and writes OSC 7 after it. Without a
/// `prompt` function the fallback writes OSC 7 and returns the stock `PS <path>> `. The
/// profile still loads (`-Command` runs after it). Each path segment goes through
/// `[uri]::EscapeDataString` (what `osc7_url` does), so the URL is ASCII; no backslash stands
/// before a double quote, so portable-pty's quoting passes the text byte-exact.
pub const POWERSHELL_PROMPT_HOOK: &str = r#"if ($function:prompt) { $__shellxPrompt = $function:prompt; function global:prompt { $p = & $__shellxPrompt; $l = $ExecutionContext.SessionState.Path.CurrentLocation; if ($l.Provider.Name -eq 'FileSystem') { [Console]::Write([char]27 + ']7;file://' + $env:COMPUTERNAME + '/' + ((($l.ProviderPath -split '\\') | ForEach-Object { [uri]::EscapeDataString($_) }) -join '/') + [char]27 + '\') }; $p } } else { function global:prompt { $l = $ExecutionContext.SessionState.Path.CurrentLocation; if ($l.Provider.Name -eq 'FileSystem') { [Console]::Write([char]27 + ']7;file://' + $env:COMPUTERNAME + '/' + ((($l.ProviderPath -split '\\') | ForEach-Object { [uri]::EscapeDataString($_) }) -join '/') + [char]27 + '\') }; "PS $($l.Path)> " } }"#;

/// The user's choice in Settings, stored as small JSON:
/// `{"kind":"auto"}`, `{"kind":"known","shell":"pwsh"}`, `{"kind":"custom","command_line":"..."}`.
/// A stored value that does not parse means `Auto` (the caller's `unwrap_or_default`).
#[derive(Clone, Debug, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(tag = "kind", rename_all = "snake_case")]
pub enum ShellChoice {
    #[default]
    Auto,
    Known {
        shell: ShellKind,
    },
    Custom {
        command_line: String,
    },
}

/// What to start, and what to start instead when that fails to launch (once).
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct LaunchPlan {
    pub first: ShellLaunch,
    pub fallback: Option<ShellLaunch>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum ShellError {
    /// Auto found no shell at all.
    NoShellFound,
    /// The custom command line in Settings does not name a program.
    Custom(CustomShellError),
    /// `SHELLX_SHELL` does not name a program.
    Override(CustomShellError),
}

/// An environment value used as a folder: trimmed, absolute (a relative one would be the
/// current folder in disguise), without a trailing backslash.
fn base(value: &Option<String>) -> Option<&str> {
    value
        .as_deref()
        .map(str::trim)
        .filter(|v| is_absolute(v))
        .map(|v| v.trim_end_matches('\\'))
}

fn powershell(kind: ShellKind, program: String) -> ShellLaunch {
    ShellLaunch {
        kind: Some(kind),
        program,
        args: ["-NoLogo", "-NoExit", "-Command", POWERSHELL_PROMPT_HOOK]
            .map(String::from)
            .to_vec(),
        osc7_hook: true,
    }
}

fn plain(kind: ShellKind, program: String, args: &[&str]) -> ShellLaunch {
    ShellLaunch {
        kind: Some(kind),
        program,
        args: args.iter().map(|a| a.to_string()).collect(),
        osc7_hook: false,
    }
}

/// The installed shells in Auto order: PowerShell 7 (PATH first, then Program Files), Windows
/// PowerShell, Command Prompt (`%ComSpec%`, else System32), Git Bash (`--login -i`), WSL.
pub fn find_shells(probe: &ShellProbe, exists: &dyn Fn(&str) -> bool) -> Vec<ShellLaunch> {
    let system_root = base(&probe.system_root).unwrap_or(r"C:\Windows");
    let program_files = base(&probe.program_files);
    let mut found = Vec::new();

    let pwsh = resolve_program("pwsh.exe", probe, exists).or_else(|| {
        let p = format!(r"{}\PowerShell\7\pwsh.exe", program_files?);
        exists(&p).then_some(p)
    });
    if let Some(p) = pwsh {
        found.push(powershell(ShellKind::Pwsh, p));
    }

    let winps = format!(r"{system_root}\System32\WindowsPowerShell\v1.0\powershell.exe");
    if exists(&winps) {
        found.push(powershell(ShellKind::WindowsPowerShell, winps));
    }

    let comspec = probe
        .comspec
        .as_deref()
        .map(str::trim)
        .filter(|c| is_absolute(c) && exists(c))
        .map(String::from);
    let cmd = comspec.or_else(|| {
        let p = format!(r"{system_root}\System32\cmd.exe");
        exists(&p).then_some(p)
    });
    if let Some(p) = cmd {
        found.push(plain(ShellKind::Cmd, p, &[]));
    }

    let git_candidates = [
        base(&probe.git_install_path).map(|g| format!(r"{g}\bin\bash.exe")),
        program_files.map(|f| format!(r"{f}\Git\bin\bash.exe")),
    ];
    if let Some(p) = git_candidates.into_iter().flatten().find(|p| exists(p)) {
        found.push(plain(ShellKind::GitBash, p, &["--login", "-i"]));
    }

    let wsl = format!(r"{system_root}\System32\wsl.exe");
    if exists(&wsl) {
        found.push(plain(ShellKind::Wsl, wsl, &[]));
    }
    found
}

/// The shells Auto may start, in order: PowerShell 7, Windows PowerShell, Command Prompt.
/// Git Bash and WSL are only ever started by choice.
fn auto_shells(found: &[ShellLaunch]) -> impl Iterator<Item = &ShellLaunch> {
    found.iter().filter(|l| {
        matches!(
            l.kind,
            Some(ShellKind::Pwsh | ShellKind::WindowsPowerShell | ShellKind::Cmd)
        )
    })
}

/// Windows ignores case (Unicode, `Phú` and `PHÚ` are one folder) and accepts `/` for `\\`.
fn same_program(a: &str, b: &str) -> bool {
    a.replace('/', "\\").to_lowercase() == b.replace('/', "\\").to_lowercase()
}

/// The first Auto shell that is not the program in `first`: the one fallback.
fn fallback_for(found: &[ShellLaunch], first: &ShellLaunch) -> Option<ShellLaunch> {
    auto_shells(found)
        .find(|l| !same_program(&l.program, &first.program))
        .cloned()
}

fn auto_plan(found: &[ShellLaunch]) -> Result<LaunchPlan, ShellError> {
    let first = auto_shells(found)
        .next()
        .ok_or(ShellError::NoShellFound)?
        .clone();
    Ok(LaunchPlan {
        fallback: fallback_for(found, &first),
        first,
    })
}

/// What to start for the user's `choice` and the `SHELLX_SHELL` override (`env_override`,
/// which wins when it is not blank). `found` is `find_shells`. The fallback is the next Auto
/// shell (never Git Bash or WSL, never the same program), once; a chosen shell that is no
/// longer installed gives the Auto plan. The override is read like a custom command line
/// (`custom_launch`): a whole value that is a path to a file is that program with no
/// arguments (the old behaviour, for paths with spaces); a bare name is looked up on PATH.
pub fn launch_plan(
    choice: &ShellChoice,
    env_override: Option<&str>,
    found: &[ShellLaunch],
    probe: &ShellProbe,
    exists: &dyn Fn(&str) -> bool,
) -> Result<LaunchPlan, ShellError> {
    if let Some(value) = env_override.map(str::trim).filter(|v| !v.is_empty()) {
        let first = custom_launch(value, probe, exists).map_err(ShellError::Override)?;
        return Ok(LaunchPlan {
            fallback: fallback_for(found, &first),
            first,
        });
    }
    match choice {
        ShellChoice::Auto => auto_plan(found),
        ShellChoice::Known { shell } => match found.iter().find(|l| l.kind == Some(*shell)) {
            Some(first) => Ok(LaunchPlan {
                first: first.clone(),
                fallback: fallback_for(found, first),
            }),
            None => auto_plan(found),
        },
        ShellChoice::Custom { command_line } => {
            let first = custom_launch(command_line, probe, exists).map_err(ShellError::Custom)?;
            Ok(LaunchPlan {
                fallback: fallback_for(found, &first),
                first,
            })
        }
    }
}

/// The OSC 7 URL the prompt hook sends for a PowerShell provider path: `file://{computer}/`
/// then the path split on `\`, each segment percent-encoded per UTF-8 byte (only
/// `A-Z a-z 0-9 - . _ ~` stay, hex in capitals, as .NET `EscapeDataString`), joined with `/`.
pub fn osc7_url(computer_name: &str, provider_path: &str) -> String {
    let segments: Vec<String> = provider_path
        .split('\\')
        .map(|segment| {
            let mut out = String::new();
            for byte in segment.bytes() {
                if byte.is_ascii_alphanumeric() || matches!(byte, b'-' | b'.' | b'_' | b'~') {
                    out.push(char::from(byte));
                } else {
                    out.push_str(&format!("%{byte:02X}"));
                }
            }
            out
        })
        .collect();
    format!("file://{computer_name}/{}", segments.join("/"))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn exists_in<'a>(set: &'a [&'a str]) -> impl Fn(&str) -> bool + 'a {
        move |p: &str| set.contains(&p)
    }

    fn argv(line: &str) -> Vec<String> {
        parse_command_line(line).unwrap()
    }

    #[test]
    fn command_lines_split_like_windows() {
        assert_eq!(
            argv(r#""C:\Program Files\Git\bin\bash.exe" --login -i"#),
            [r"C:\Program Files\Git\bin\bash.exe", "--login", "-i"]
        );
        assert_eq!(argv("wsl.exe -d Ubuntu"), ["wsl.exe", "-d", "Ubuntu"]);
        assert_eq!(
            argv(r#"cmd.exe /k "echo hi""#),
            ["cmd.exe", "/k", "echo hi"]
        );
        assert_eq!(
            argv(r#"bash -c "echo \"a b\"""#),
            ["bash", "-c", r#"echo "a b""#]
        );
        assert_eq!(argv(r#""C:\x\\" a"#), [r"C:\x\\", "a"]);
        assert_eq!(argv(r#"x a\\\\"b c""#), ["x", r"a\\b c"]);
        assert_eq!(argv(r#"x a\\\"b"#), ["x", r#"a\"b"#]);
        assert_eq!(argv(r"x a\b"), ["x", r"a\b"]);
        assert_eq!(argv(r#"x "a""b""#), ["x", r#"a"b"#]);
        assert_eq!(argv("x\t\ty"), ["x", "y"]);
        // leading blanks, an empty quoted argument, one argument alone
        assert_eq!(argv("  pwsh "), ["pwsh"]);
        assert_eq!(argv(r#"x "" y"#), ["x", "", "y"]);
    }

    #[test]
    fn bad_command_lines_are_reported() {
        assert_eq!(parse_command_line(""), Err(CommandLineError::Empty));
        assert_eq!(parse_command_line("   "), Err(CommandLineError::Empty));
        assert_eq!(parse_command_line("\t "), Err(CommandLineError::Empty));
        assert_eq!(
            parse_command_line(r#"pwsh -Command "C:\path\""#),
            Err(CommandLineError::UnclosedQuote)
        );
        assert_eq!(
            parse_command_line(r#""C:\Program Files\x"#),
            Err(CommandLineError::UnclosedQuote)
        );
    }

    fn path_probe() -> ShellProbe {
        ShellProbe {
            path: r#"C:\Windows\system32;"C:\Program Files\Git\cmd";;C:\Users\Phú\scoop\shims"#
                .into(),
            ..ShellProbe::default()
        }
    }

    #[test]
    fn programs_resolve_by_path_or_as_given() {
        let probe = path_probe();
        let ex = exists_in(&[
            r"C:\Windows\system32\wsl.exe",
            r"C:\Users\Phú\scoop\shims\pwsh.exe",
            r"C:\Program Files\Git\bin\bash.exe",
        ]);
        let wsl = Some(r"C:\Windows\system32\wsl.exe".to_string());
        assert_eq!(resolve_program("wsl.exe", &probe, &ex), wsl);
        assert_eq!(resolve_program("wsl", &probe, &ex), wsl);
        assert_eq!(
            resolve_program("pwsh", &probe, &ex),
            Some(r"C:\Users\Phú\scoop\shims\pwsh.exe".to_string())
        );
        assert_eq!(
            resolve_program(r"C:\Program Files\Git\bin\bash.exe", &probe, &ex),
            Some(r"C:\Program Files\Git\bin\bash.exe".to_string())
        );
        // given with a path but without the extension
        assert_eq!(
            resolve_program(r"C:\Program Files\Git\bin\bash", &probe, &ex),
            Some(r"C:\Program Files\Git\bin\bash.exe".to_string())
        );
        assert_eq!(resolve_program(r"C:\Program", &probe, &ex), None);
        assert_eq!(resolve_program("nope", &probe, &ex), None);
        assert_eq!(resolve_program("", &probe, &ex), None);
    }

    #[test]
    fn a_path_entry_with_a_trailing_backslash_joins_once() {
        let probe = ShellProbe {
            path: r"C:\tools\".into(),
            ..ShellProbe::default()
        };
        let ex = exists_in(&[r"C:\tools\x.exe"]);
        assert_eq!(
            resolve_program("x", &probe, &ex),
            Some(r"C:\tools\x.exe".to_string())
        );
    }

    #[test]
    fn custom_lines_name_the_missing_program() {
        let probe = path_probe();
        let ex = exists_in(&[r"C:\Program Files\Git\bin\bash.exe"]);
        assert_eq!(
            custom_launch(
                r#""C:\Program Files\Git\bin\bash.exe" --login -i"#,
                &probe,
                &ex
            ),
            Ok(ShellLaunch {
                kind: None,
                program: r"C:\Program Files\Git\bin\bash.exe".into(),
                args: vec!["--login".into(), "-i".into()],
                osc7_hook: false,
            })
        );
        assert_eq!(
            custom_launch(r"C:\Program Files\Git\bin\bash.exe --login", &probe, &ex),
            Err(CustomShellError::NotFound(r"C:\Program".into()))
        );
        assert_eq!(custom_launch("", &probe, &ex), Err(CustomShellError::Empty));
        assert_eq!(
            custom_launch(r#"bash "x"#, &probe, &ex),
            Err(CustomShellError::UnclosedQuote)
        );
    }

    // The probe of a typical machine; `exists` compares strings exactly (Windows ignores case).
    fn probe() -> ShellProbe {
        ShellProbe {
            system_root: Some(r"C:\Windows".into()),
            program_files: Some(r"C:\Program Files".into()),
            comspec: Some(r"C:\Windows\system32\cmd.exe".into()),
            path: r"C:\Windows\System32;C:\Users\Phú\AppData\Local\Microsoft\WindowsApps".into(),
            git_install_path: Some(r"D:\Tools\Git".into()),
        }
    }
    const PWSH: &str = r"C:\Program Files\PowerShell\7\pwsh.exe";
    const WINPS: &str = r"C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe";
    const CMD: &str = r"C:\Windows\system32\cmd.exe";
    const BASH: &str = r"D:\Tools\Git\bin\bash.exe";
    const WSL: &str = r"C:\Windows\System32\wsl.exe";
    const ALL: [&str; 5] = [PWSH, WINPS, CMD, BASH, WSL];
    const APPS_PWSH: &str = r"C:\Users\Phú\AppData\Local\Microsoft\WindowsApps\pwsh.exe";

    fn ps_args() -> Vec<String> {
        vec![
            "-NoLogo".into(),
            "-NoExit".into(),
            "-Command".into(),
            POWERSHELL_PROMPT_HOOK.into(),
        ]
    }
    fn kinds(found: &[ShellLaunch]) -> Vec<Option<ShellKind>> {
        found.iter().map(|l| l.kind).collect()
    }
    fn auto_plan(set: &[&str]) -> Result<LaunchPlan, ShellError> {
        let ex = exists_in(set);
        let p = probe();
        let found = find_shells(&p, &ex);
        launch_plan(&ShellChoice::Auto, None, &found, &p, &ex)
    }

    #[test]
    fn every_installed_shell_is_found_in_order() {
        let ex = exists_in(&ALL);
        let found = find_shells(&probe(), &ex);
        assert_eq!(
            found,
            vec![
                ShellLaunch {
                    kind: Some(ShellKind::Pwsh),
                    program: PWSH.into(),
                    args: ps_args(),
                    osc7_hook: true
                },
                ShellLaunch {
                    kind: Some(ShellKind::WindowsPowerShell),
                    program: WINPS.into(),
                    args: ps_args(),
                    osc7_hook: true
                },
                ShellLaunch {
                    kind: Some(ShellKind::Cmd),
                    program: CMD.into(),
                    args: vec![],
                    osc7_hook: false
                },
                ShellLaunch {
                    kind: Some(ShellKind::GitBash),
                    program: BASH.into(),
                    args: vec!["--login".into(), "-i".into()],
                    osc7_hook: false
                },
                ShellLaunch {
                    kind: Some(ShellKind::Wsl),
                    program: WSL.into(),
                    args: vec![],
                    osc7_hook: false
                },
            ]
        );
    }

    #[test]
    fn pwsh_on_path_wins() {
        let mut set = ALL.to_vec();
        set.push(APPS_PWSH);
        let ex = exists_in(&set);
        let found = find_shells(&probe(), &ex);
        assert_eq!(found[0].kind, Some(ShellKind::Pwsh));
        assert_eq!(found[0].program, APPS_PWSH);
    }

    #[test]
    fn a_plain_windows_finds_powershell_and_cmd() {
        let ex = exists_in(&[WINPS, CMD]);
        assert_eq!(
            kinds(&find_shells(&probe(), &ex)),
            [Some(ShellKind::WindowsPowerShell), Some(ShellKind::Cmd)]
        );
        // no %ComSpec%: System32\cmd.exe is used
        let no_comspec = ShellProbe {
            comspec: None,
            ..probe()
        };
        let ex = exists_in(&[r"C:\Windows\System32\cmd.exe"]);
        let found = find_shells(&no_comspec, &ex);
        assert_eq!(kinds(&found), [Some(ShellKind::Cmd)]);
        assert_eq!(found[0].program, r"C:\Windows\System32\cmd.exe");
        // no %SystemRoot%: C:\Windows; a trailing backslash is not doubled
        let bare = ShellProbe {
            system_root: Some(r"C:\Windows\".into()),
            comspec: None,
            ..ShellProbe::default()
        };
        let ex = exists_in(&[r"C:\Windows\System32\cmd.exe"]);
        assert_eq!(
            find_shells(&bare, &ex)[0].program,
            r"C:\Windows\System32\cmd.exe"
        );
        let none = ShellProbe::default();
        assert_eq!(
            find_shells(&none, &ex)[0].program,
            r"C:\Windows\System32\cmd.exe"
        );
    }

    #[test]
    fn git_bash_falls_back_to_program_files() {
        let p = ShellProbe {
            git_install_path: None,
            ..probe()
        };
        let ex = exists_in(&[r"C:\Program Files\Git\bin\bash.exe"]);
        let found = find_shells(&p, &ex);
        assert_eq!(kinds(&found), [Some(ShellKind::GitBash)]);
        assert_eq!(found[0].program, r"C:\Program Files\Git\bin\bash.exe");
    }

    #[test]
    fn auto_prefers_pwsh_and_falls_back_once() {
        let plan = auto_plan(&ALL).unwrap();
        assert_eq!(plan.first.kind, Some(ShellKind::Pwsh));
        assert_eq!(
            plan.fallback.unwrap().kind,
            Some(ShellKind::WindowsPowerShell)
        );

        let plan = auto_plan(&[WINPS, CMD]).unwrap();
        assert_eq!(plan.first.kind, Some(ShellKind::WindowsPowerShell));
        assert_eq!(plan.fallback.unwrap().kind, Some(ShellKind::Cmd));

        let plan = auto_plan(&[CMD]).unwrap();
        assert_eq!(plan.first.kind, Some(ShellKind::Cmd));
        assert_eq!(plan.fallback, None);

        assert_eq!(auto_plan(&[]), Err(ShellError::NoShellFound));
    }

    #[test]
    fn a_chosen_shell_falls_back_to_auto() {
        let ex = exists_in(&ALL);
        let p = probe();
        let found = find_shells(&p, &ex);
        let plan = |choice: &ShellChoice| launch_plan(choice, None, &found, &p, &ex);

        let git = plan(&ShellChoice::Known {
            shell: ShellKind::GitBash,
        })
        .unwrap();
        assert_eq!(git.first.kind, Some(ShellKind::GitBash));
        assert_eq!(git.fallback.unwrap().kind, Some(ShellKind::Pwsh));

        let pwsh = plan(&ShellChoice::Known {
            shell: ShellKind::Pwsh,
        })
        .unwrap();
        assert_eq!(pwsh.first.kind, Some(ShellKind::Pwsh));
        assert_eq!(
            pwsh.fallback.unwrap().kind,
            Some(ShellKind::WindowsPowerShell)
        );

        // Git Bash was chosen and is gone: the Auto plan
        let ex2 = exists_in(&[PWSH, WINPS, CMD]);
        let found2 = find_shells(&p, &ex2);
        let gone = launch_plan(
            &ShellChoice::Known {
                shell: ShellKind::GitBash,
            },
            None,
            &found2,
            &p,
            &ex2,
        )
        .unwrap();
        assert_eq!(
            gone,
            launch_plan(&ShellChoice::Auto, None, &found2, &p, &ex2).unwrap()
        );

        // a custom command line, then Auto's first
        let wsl_path = ShellProbe {
            path: r"C:\Windows\System32".into(),
            ..probe()
        };
        let custom = launch_plan(
            &ShellChoice::Custom {
                command_line: "wsl.exe -d Ubuntu".into(),
            },
            None,
            &found,
            &wsl_path,
            &ex,
        )
        .unwrap();
        assert_eq!(custom.first.program, WSL);
        assert_eq!(custom.first.args, ["-d", "Ubuntu"]);
        assert_eq!(custom.first.kind, None);
        assert_eq!(custom.fallback.unwrap().kind, Some(ShellKind::Pwsh));

        assert_eq!(
            plan(&ShellChoice::Custom {
                command_line: "nope.exe".into()
            }),
            Err(ShellError::Custom(CustomShellError::NotFound(
                "nope.exe".into()
            )))
        );
    }

    #[test]
    fn shellx_shell_keeps_old_values_working() {
        const GIT_BASH: &str = r"C:\Program Files\Git\bin\bash.exe";
        let mut set = ALL.to_vec();
        set.extend([GIT_BASH, APPS_PWSH]);
        let ex = exists_in(&set);
        let p = probe();
        let found = find_shells(&p, &ex);
        let choice = ShellChoice::Known {
            shell: ShellKind::Pwsh,
        };
        let plan = |value: &str| launch_plan(&choice, Some(value), &found, &p, &ex);

        // unquoted, with spaces, and a file: that program with no arguments
        let old = plan(GIT_BASH).unwrap();
        assert_eq!(old.first.program, GIT_BASH);
        assert!(old.first.args.is_empty());
        assert_eq!(old.first.kind, None);
        assert_eq!(old.fallback.as_ref().unwrap().kind, Some(ShellKind::Pwsh));
        // quoted with an argument
        let quoted = plan(&format!(r#""{GIT_BASH}" -l"#)).unwrap();
        assert_eq!(quoted.first.program, GIT_BASH);
        assert_eq!(quoted.first.args, ["-l"]);
        // a bare name on PATH: the first PATH entry that has it
        let bare = plan("pwsh").unwrap();
        assert_eq!(bare.first.program, APPS_PWSH);
        // blank: ignored, the choice applies
        let blank = plan("   ").unwrap();
        assert_eq!(blank.first.kind, Some(ShellKind::Pwsh));
        // unknown: an error that names the override
        assert_eq!(
            plan("nope.exe"),
            Err(ShellError::Override(CustomShellError::NotFound(
                "nope.exe".into()
            )))
        );
    }

    #[test]
    fn the_choice_is_stored_as_small_json() {
        let cases = [
            (ShellChoice::Auto, r#"{"kind":"auto"}"#),
            (
                ShellChoice::Known {
                    shell: ShellKind::GitBash,
                },
                r#"{"kind":"known","shell":"git_bash"}"#,
            ),
            (
                ShellChoice::Known {
                    shell: ShellKind::WindowsPowerShell,
                },
                r#"{"kind":"known","shell":"windows_powershell"}"#,
            ),
            (
                ShellChoice::Custom {
                    command_line: "wsl.exe".into(),
                },
                r#"{"kind":"custom","command_line":"wsl.exe"}"#,
            ),
        ];
        for (choice, json) in cases {
            assert_eq!(serde_json::to_string(&choice).unwrap(), json);
            assert_eq!(serde_json::from_str::<ShellChoice>(json).unwrap(), choice);
        }
        for kind in ["pwsh", "cmd", "wsl"] {
            let json = format!(r#"{{"kind":"known","shell":"{kind}"}}"#);
            assert!(serde_json::from_str::<ShellChoice>(&json).is_ok(), "{kind}");
        }
        assert!(serde_json::from_str::<ShellChoice>(r#"{"kind":"bash"}"#).is_err());
        assert!(serde_json::from_str::<ShellChoice>(r#"{"kind":"known","shell":"zsh"}"#).is_err());
    }

    #[test]
    fn the_hook_percent_encodes_the_directory() {
        assert!(POWERSHELL_PROMPT_HOOK.contains("[uri]::EscapeDataString"));
        assert!(POWERSHELL_PROMPT_HOOK.contains("]7;file://"));
        assert!(!POWERSHELL_PROMPT_HOOK.contains(r"-replace '\\','/'"));
        // a backslash before a double quote would be eaten by the command-line quoting
        assert!(!POWERSHELL_PROMPT_HOOK.contains("\\\""));
    }

    #[test]
    fn osc7_urls_are_ascii_whatever_the_folder() {
        let cases = [
            (
                r"C:\Users\Phú\Tài liệu",
                "file://PC/C%3A/Users/Ph%C3%BA/T%C3%A0i%20li%E1%BB%87u",
            ),
            (r"C:\", "file://PC/C%3A/"),
            (
                r"\\srv\share\Dự án",
                "file://PC///srv/share/D%E1%BB%B1%20%C3%A1n",
            ),
            (r"C:\a%b", "file://PC/C%3A/a%25b"),
            (r"C:\a-b_c.d~e", "file://PC/C%3A/a-b_c.d~e"),
        ];
        for (path, want) in cases {
            let url = osc7_url("PC", path);
            assert_eq!(url, want, "{path}");
            assert!(url.is_ascii(), "{path}");
        }
    }

    #[test]
    fn path_entries_that_are_not_absolute_are_never_searched() {
        // a pwsh.exe in the folder ShellX was started from must not win
        let ps = ShellProbe {
            path: r".;C:\Program Files\PowerShell\7".into(),
            program_files: Some(r"C:\Program Files".into()),
            ..ShellProbe::default()
        };
        let ex = exists_in(&[r".\pwsh.exe", r"C:\Program Files\PowerShell\7\pwsh.exe"]);
        let found = find_shells(&ps, &ex);
        assert_eq!(found[0].kind, Some(ShellKind::Pwsh));
        assert_eq!(found[0].program, r"C:\Program Files\PowerShell\7\pwsh.exe");
        // only the relative copy exists: nothing is found
        let ex = exists_in(&[
            r".\pwsh.exe",
            r"\pwsh.exe",
            r"tools\pwsh.exe",
            r"C:pwsh.exe",
        ]);
        let relative = ShellProbe {
            path: r";.;tools;..\bin;C:;C:tools;\".into(),
            ..ShellProbe::default()
        };
        assert_eq!(resolve_program("pwsh", &relative, &ex), None);
        assert!(find_shells(&relative, &ex).is_empty());
        // absolute entries: drive, UNC, forward slashes
        let abs = ShellProbe {
            path: r"\\srv\tools;D:/bin;E:\x".into(),
            ..ShellProbe::default()
        };
        let ex = exists_in(&[r"\\srv\tools\a.exe", r"D:/bin\b.exe"]);
        assert_eq!(
            resolve_program("a", &abs, &ex),
            Some(r"\\srv\tools\a.exe".to_string())
        );
        assert_eq!(
            resolve_program("b.exe", &abs, &ex),
            Some(r"D:/bin\b.exe".to_string())
        );
    }

    #[test]
    fn a_bare_shellx_shell_is_looked_up_on_path_not_in_the_current_folder() {
        let p = probe();
        // "pwsh" and "pwsh.exe" exist as files in the current folder AND on PATH
        let ex = exists_in(&["pwsh", "pwsh.exe", APPS_PWSH, WINPS, CMD]);
        let found = find_shells(&p, &ex);
        for value in ["pwsh", "pwsh.exe"] {
            let plan = launch_plan(&ShellChoice::Auto, Some(value), &found, &p, &ex).unwrap();
            assert_eq!(plan.first.program, APPS_PWSH, "{value}");
        }
        // only in the current folder: not found
        let ex = exists_in(&["pwsh", "pwsh.exe"]);
        for value in ["pwsh", "pwsh.exe"] {
            assert_eq!(
                launch_plan(&ShellChoice::Auto, Some(value), &[], &p, &ex),
                Err(ShellError::Override(CustomShellError::NotFound(
                    value.into()
                ))),
                "{value}"
            );
        }
    }

    #[test]
    fn an_unquoted_shellx_shell_path_works_without_the_extension() {
        let p = probe();
        let ex = exists_in(&[r"C:\Program Files\Git\bin\bash.exe"]);
        let plan = launch_plan(
            &ShellChoice::Auto,
            Some(r"C:\Program Files\Git\bin\bash"),
            &[],
            &p,
            &ex,
        )
        .unwrap();
        assert_eq!(plan.first.program, r"C:\Program Files\Git\bin\bash.exe");
        assert!(plan.first.args.is_empty());
        // the Settings field accepts the same line
        assert_eq!(
            custom_launch(r"C:\Program Files\Git\bin\bash", &p, &ex)
                .unwrap()
                .program,
            r"C:\Program Files\Git\bin\bash.exe"
        );
        // with arguments the old rule stays: the program is what comes before the first blank
        assert_eq!(
            custom_launch(r"C:\Program Files\Git\bin\bash --login", &p, &ex),
            Err(CustomShellError::NotFound(r"C:\Program".into()))
        );
    }

    #[test]
    fn auto_never_chooses_git_bash_or_wsl_and_never_repeats_a_program() {
        // cmd + Git Bash: cmd, and no fallback
        let plan = auto_plan(&[CMD, BASH]).unwrap();
        assert_eq!(plan.first.kind, Some(ShellKind::Cmd));
        assert_eq!(plan.fallback, None);
        // only Git Bash and WSL: Auto has nothing to start
        assert_eq!(auto_plan(&[BASH, WSL]), Err(ShellError::NoShellFound));
        // pwsh + Git Bash + WSL: PowerShell 7, no fallback
        let plan = auto_plan(&[PWSH, BASH, WSL]).unwrap();
        assert_eq!(plan.first.kind, Some(ShellKind::Pwsh));
        assert_eq!(plan.fallback, None);
        // a chosen Git Bash falls back to the first Auto shell, not to WSL
        let ex = exists_in(&[BASH, WSL, CMD]);
        let p = probe();
        let found = find_shells(&p, &ex);
        let plan = launch_plan(
            &ShellChoice::Known {
                shell: ShellKind::Wsl,
            },
            None,
            &found,
            &p,
            &ex,
        )
        .unwrap();
        assert_eq!(plan.first.kind, Some(ShellKind::Wsl));
        assert_eq!(plan.fallback.unwrap().kind, Some(ShellKind::Cmd));
        // a chosen Command Prompt falls back to PowerShell, a chosen PowerShell 7 to Windows PowerShell
        let ex = exists_in(&ALL);
        let found = find_shells(&p, &ex);
        let cmd = launch_plan(
            &ShellChoice::Known {
                shell: ShellKind::Cmd,
            },
            None,
            &found,
            &p,
            &ex,
        )
        .unwrap();
        assert_eq!(cmd.fallback.unwrap().kind, Some(ShellKind::Pwsh));
        // SHELLX_SHELL=pwsh, a custom line for PowerShell 7: the fallback is another program
        let on_path = ShellProbe {
            path: r"C:\Program Files\PowerShell\7".into(),
            ..probe()
        };
        let plan = launch_plan(&ShellChoice::Auto, Some("pwsh"), &found, &on_path, &ex).unwrap();
        assert_eq!(plan.first.program, PWSH);
        assert_eq!(
            plan.fallback.unwrap().kind,
            Some(ShellKind::WindowsPowerShell)
        );
        let custom = launch_plan(
            &ShellChoice::Custom {
                command_line: format!("\"{PWSH}\" -NoProfile"),
            },
            None,
            &found,
            &p,
            &ex,
        )
        .unwrap();
        assert_eq!(
            custom.fallback.unwrap().kind,
            Some(ShellKind::WindowsPowerShell)
        );
        // ... compared without regard to case, as Windows does
        let upper = PWSH.to_uppercase();
        let plan = launch_plan(
            &ShellChoice::Custom {
                command_line: upper,
            },
            None,
            &found,
            &p,
            &exists_in(&[&PWSH.to_uppercase(), WINPS]),
        );
        assert_eq!(
            plan.unwrap().fallback.unwrap().kind,
            Some(ShellKind::WindowsPowerShell)
        );
    }

    #[test]
    fn a_bare_unc_prefix_is_not_an_absolute_path_entry() {
        let probe = ShellProbe {
            path: r"\;//;\\;C:\Program Files\PowerShell\7".into(),
            ..ShellProbe::default()
        };
        let ex = exists_in(&[
            r"\\\pwsh.exe",
            r"\pwsh.exe",
            r"C:\Program Files\PowerShell\7\pwsh.exe",
        ]);
        let found = find_shells(&probe, &ex);
        assert_eq!(found[0].program, r"C:\Program Files\PowerShell\7\pwsh.exe");
        assert_eq!(
            resolve_program("pwsh", &probe, &ex),
            Some(r"C:\Program Files\PowerShell\7\pwsh.exe".to_string())
        );
    }

    #[test]
    fn the_whole_value_rule_needs_an_absolute_path() {
        let p = probe();
        let asked = std::cell::RefCell::new(Vec::<String>::new());
        let ex = |path: &str| {
            asked.borrow_mut().push(path.to_string());
            [r"C:\Windows\System32\cmd.exe"].contains(&path)
        };
        // `cmd /k`: a bare name with an argument; PATH finds cmd, `/k` is the argument
        let on_path = ShellProbe {
            path: r"C:\Windows\System32".into(),
            ..p.clone()
        };
        let plan = launch_plan(&ShellChoice::Auto, Some("cmd /k"), &[], &on_path, &ex).unwrap();
        assert_eq!(plan.first.program, r"C:\Windows\System32\cmd.exe");
        assert_eq!(plan.first.args, ["/k"]);
        assert!(
            asked.borrow().iter().all(|q| !q.contains("cmd /k")),
            "{:?}",
            asked.borrow()
        );
    }

    #[test]
    fn a_relative_path_is_never_a_shell() {
        let p = probe();
        // every file "exists": only the rule may refuse
        let ex = |_: &str| true;
        for value in [
            r".\pwsh.exe",
            r"bin\bash",
            "tools/sh",
            r"..\x.exe",
            r"C:x.exe",
            r#""tools\sh.exe" -l"#,
        ] {
            let name = parse_command_line(value).unwrap().remove(0);
            assert_eq!(
                launch_plan(&ShellChoice::Auto, Some(value), &[], &p, &ex),
                Err(ShellError::Override(CustomShellError::NotFound(
                    name.clone()
                ))),
                "{value}"
            );
            assert_eq!(
                custom_launch(value, &p, &ex),
                Err(CustomShellError::NotFound(name)),
                "{value}"
            );
        }
        // an absolute path still works, quoted or not
        assert!(custom_launch(r"C:\tools\sh.exe", &p, &ex).is_ok());
        assert!(custom_launch(r#""C:\tools\sh.exe" -l"#, &p, &ex).is_ok());
    }

    #[test]
    fn forward_slashes_name_the_same_program() {
        let p = probe();
        let ex = exists_in(&[PWSH, WINPS, CMD, "C:/Program Files/PowerShell/7/pwsh.exe"]);
        let found = find_shells(&p, &ex);
        let plan = launch_plan(
            &ShellChoice::Auto,
            Some("C:/Program Files/PowerShell/7/pwsh.exe"),
            &found,
            &p,
            &ex,
        )
        .unwrap();
        assert_eq!(plan.first.program, "C:/Program Files/PowerShell/7/pwsh.exe");
        assert_eq!(
            plan.fallback.unwrap().kind,
            Some(ShellKind::WindowsPowerShell)
        );
    }

    #[test]
    fn environment_values_that_are_not_absolute_are_not_folders() {
        // a relative %ComSpec% falls back to System32\cmd.exe
        for comspec in ["cmd.exe", r".\cmd.exe", r"system32\cmd.exe"] {
            let p = ShellProbe {
                comspec: Some(comspec.into()),
                ..probe()
            };
            let files = [comspec, r"C:\Windows\System32\cmd.exe"];
            let ex = exists_in(&files);
            let found = find_shells(&p, &ex);
            let cmd = found
                .iter()
                .find(|l| l.kind == Some(ShellKind::Cmd))
                .unwrap();
            assert_eq!(cmd.program, r"C:\Windows\System32\cmd.exe", "{comspec}");
        }
        // a relative %ProgramFiles% gives no PowerShell 7 and no Git Bash candidate
        let p = ShellProbe {
            program_files: Some("PF".into()),
            git_install_path: Some("Git".into()),
            ..probe()
        };
        let ex = exists_in(&[
            r"PF\PowerShell\7\pwsh.exe",
            r"PF\Git\bin\bash.exe",
            r"Git\bin\bash.exe",
        ]);
        assert!(find_shells(&p, &ex).is_empty());
        // a relative %SystemRoot% counts as absent: C:\Windows
        let p = ShellProbe {
            system_root: Some("Windows".into()),
            comspec: None,
            ..probe()
        };
        let ex = exists_in(&[r"Windows\System32\cmd.exe", r"C:\Windows\System32\cmd.exe"]);
        let found = find_shells(&p, &ex);
        assert_eq!(found.len(), 1);
        assert_eq!(found[0].program, r"C:\Windows\System32\cmd.exe");
    }

    #[test]
    fn same_program_folds_case_beyond_ascii() {
        let p = probe();
        let upper = r"C:\USERS\PHÚ\TOOLS\PWSH.EXE";
        let pwsh = r"C:\Users\Phú\tools\pwsh.exe";
        let winps = r"C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe";
        let files = [upper, pwsh, winps];
        let ex = exists_in(&files);
        let found = vec![
            ShellLaunch {
                kind: Some(ShellKind::Pwsh),
                program: pwsh.into(),
                args: vec![],
                osc7_hook: true,
            },
            ShellLaunch {
                kind: Some(ShellKind::WindowsPowerShell),
                program: winps.into(),
                args: vec![],
                osc7_hook: true,
            },
        ];
        let plan = launch_plan(&ShellChoice::Auto, Some(upper), &found, &p, &ex).unwrap();
        assert_eq!(plan.first.program, upper);
        assert_eq!(
            plan.fallback.unwrap().kind,
            Some(ShellKind::WindowsPowerShell)
        );
    }
}
