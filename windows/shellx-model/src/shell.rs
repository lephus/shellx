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

/// Finds the file `program` names. A name with `\`, `/` or `:` is checked as given, then
/// with `.exe` added when it has no extension; any other name is looked up in each
/// `;`-separated `PATH` entry (quotes stripped, empty entries skipped), plain then `.exe`.
/// The first existing file wins.
pub fn resolve_program(
    program: &str,
    probe: &ShellProbe,
    exists: &dyn Fn(&str) -> bool,
) -> Option<String> {
    if program.is_empty() {
        return None;
    }
    if program.contains(['\\', '/', ':']) {
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
        if entry.is_empty() {
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
/// calls this on every edit). The result has no kind and no prompt hook.
pub fn custom_launch(
    line: &str,
    probe: &ShellProbe,
    exists: &dyn Fn(&str) -> bool,
) -> Result<ShellLaunch, CustomShellError> {
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
}
