//! `shellx integrations status|install|uninstall` (A12 D7).
//!
//! The driver around the pure planners: read, plan, show the diff (secrets
//! masked), ask, read again, back up, write atomically. Nothing is written
//! before a `y`/`--yes`, nothing outside the one agent file (plus its
//! `.shellx-bak` and `.shellx-created` neighbours) is touched, and no
//! sentence here quotes the file or anything the user typed.

use super::diff::{mask_secrets, unified_diff};
use super::real::{RealFs, RealPrompt};
use super::{
    config_path, installed, leaves_nothing, owns_file, plan_install, plan_uninstall,
    refusal_message, snippet, Agent, Fs, Plan, Prompt, ReadError, Refusal,
};
use crate::api::args::Parsed;
use crate::api::client::ApiError;
use crate::api::doctor::{binary_in_path, on_path};
use crate::api::output::plain;
use crate::api::run::Ctx;
use crate::api::value::{to_json, Value};
use std::path::{Path, PathBuf};

const BACKUP: &str = ".shellx-bak";
const CREATED: &str = ".shellx-created";

/// The real file system and terminal.
pub fn command(p: &Parsed, ctx: &mut Ctx) -> Result<(), ApiError> {
    run(p, ctx, &mut RealFs, &mut RealPrompt::default())
}

pub fn run(
    p: &Parsed,
    ctx: &mut Ctx,
    fs: &mut dyn Fs,
    prompt: &mut dyn Prompt,
) -> Result<(), ApiError> {
    let which = match p.pos(0) {
        None => None,
        Some(name) => Some(Agent::from_name(name).ok_or_else(|| {
            let all: Vec<&str> = Agent::ALL.iter().map(|a| a.name()).collect();
            ApiError::Usage(format!("unknown agent (one of: {})", all.join(", ")))
        })?),
    };
    match p.spec.path.last().copied() {
        Some("status") => status(p, ctx, fs, which),
        Some("install") => {
            let a = which.ok_or_else(|| ApiError::Usage("an agent is required".into()))?;
            install(p, ctx, fs, prompt, a)
        }
        Some("uninstall") => {
            let a = which.ok_or_else(|| ApiError::Usage("an agent is required".into()))?;
            uninstall(p, ctx, fs, prompt, a)
        }
        _ => Err(ApiError::Usage("unknown integrations command".into())),
    }
}

/// A fixed sentence on stderr and exit 1.
fn fail(ctx: &mut Ctx, message: &str) -> ApiError {
    let _ = writeln!(ctx.err, "shellx: {message}");
    ApiError::Reported("integrations".into())
}

fn home(ctx: &mut Ctx) -> Result<PathBuf, ApiError> {
    match ctx.home.clone() {
        Some(h) => Ok(h),
        None => Err(fail(ctx, "cannot find your home folder")),
    }
}

/// `~/…` for a path under the home folder.
fn shown(path: &Path, home: &Path) -> String {
    let s = match path.strip_prefix(home) {
        Ok(rest) if rest.as_os_str().is_empty() => "~".to_string(),
        Ok(rest) => {
            let sep = if cfg!(windows) { "\\" } else { "/" };
            format!("~{sep}{}", rest.display())
        }
        Err(_) => path.display().to_string(),
    };
    plain(&s)
}

fn read(ctx: &mut Ctx, fs: &dyn Fs, a: Agent, path: &Path) -> Result<Option<String>, ApiError> {
    fs.read(path).map_err(|e| {
        let m = match e {
            ReadError::TooBig => refusal_message(a, Refusal::TooBig),
            ReadError::NotText => "refusing: the file is not UTF-8 text".into(),
            ReadError::Io => "cannot read the file".into(),
        };
        fail(ctx, &m)
    })
}

fn with_suffix(p: &Path, suffix: &str) -> PathBuf {
    let mut s = p.as_os_str().to_os_string();
    s.push(suffix);
    PathBuf::from(s)
}

fn path_var(ctx: &Ctx) -> String {
    (ctx.env)("PATH").unwrap_or_default()
}

fn status(
    p: &Parsed,
    ctx: &mut Ctx,
    fs: &mut dyn Fs,
    which: Option<Agent>,
) -> Result<(), ApiError> {
    let home = home(ctx)?;
    let paths = path_var(ctx);
    let mut rows = Vec::new();
    let mut text = String::new();
    for a in Agent::ALL
        .into_iter()
        .filter(|a| which.is_none_or(|w| w == *a))
    {
        let path = config_path(a, ctx.env, &home);
        // A file ShellX cannot read safely is simply not installed.
        let current = fs.read(&path).ok().flatten();
        let is_installed = installed(a, current.as_deref());
        let found = binary_in_path(&paths, a.binary(), cfg!(windows), &|f| fs.exists(f));
        let display = shown(&path, &home);
        let (mark, state) = if is_installed {
            ('✓', format!("installed   ({display})"))
        } else if found {
            ('✗', "not installed".to_string())
        } else {
            ('-', "not found on PATH".to_string())
        };
        text.push_str(&format!("{mark} {:<10}{state}\n", a.name()));
        rows.push(Value::map(vec![
            ("agent", Value::text(a.name())),
            ("installed", Value::Bool(is_installed)),
            ("path", Value::text(display)),
            ("found", Value::Bool(found)),
        ]));
    }
    if p.json {
        let v = Value::map(vec![("agents", Value::Array(rows))]);
        let _ = writeln!(ctx.out, "{}", to_json(&v));
    } else {
        let _ = write!(ctx.out, "{text}");
    }
    Ok(())
}

fn install(
    p: &Parsed,
    ctx: &mut Ctx,
    fs: &mut dyn Fs,
    prompt: &mut dyn Prompt,
    a: Agent,
) -> Result<(), ApiError> {
    if p.has("print") {
        let _ = write!(ctx.out, "{}", snippet(a));
        return Ok(());
    }
    let home = home(ctx)?;
    let path = config_path(a, ctx.env, &home);
    let current = read(ctx, fs, a, &path)?;
    let plan = match plan_install(a, current.as_deref()) {
        Ok(plan) => plan,
        Err(r) => return Err(fail(ctx, &refusal_message(a, r))),
    };
    if !plan.changed {
        if p.json {
            let _ = writeln!(ctx.out, "{{\"changed\":false,\"backup\":false}}");
        } else {
            let _ = writeln!(ctx.out, "Already installed.");
        }
        return Ok(());
    }
    apply(p, ctx, fs, prompt, a, &path, plan, Change::Install)
}

fn uninstall(
    p: &Parsed,
    ctx: &mut Ctx,
    fs: &mut dyn Fs,
    prompt: &mut dyn Prompt,
    a: Agent,
) -> Result<(), ApiError> {
    let home = home(ctx)?;
    let path = config_path(a, ctx.env, &home);
    let nothing = |ctx: &mut Ctx| {
        if p.json {
            let _ = writeln!(ctx.out, "{{\"changed\":false,\"backup\":false}}");
        } else {
            let _ = writeln!(ctx.out, "Not installed.");
        }
        Ok(())
    };
    let Some(current) = read(ctx, fs, a, &path)? else {
        return nothing(ctx);
    };
    let plan = match plan_uninstall(a, &current) {
        Ok(plan) => plan,
        Err(r) => return Err(fail(ctx, &refusal_message(a, r))),
    };
    if !plan.changed {
        return nothing(ctx);
    }
    apply(p, ctx, fs, prompt, a, &path, plan, Change::Uninstall)
}

#[derive(Clone, Copy, PartialEq, Eq)]
enum Change {
    Install,
    Uninstall,
}

#[allow(clippy::too_many_arguments)]
fn apply(
    p: &Parsed,
    ctx: &mut Ctx,
    fs: &mut dyn Fs,
    prompt: &mut dyn Prompt,
    a: Agent,
    path: &Path,
    plan: Plan,
    change: Change,
) -> Result<(), ApiError> {
    let home = home(ctx)?;
    let name = shown(path, &home);
    let Some(diff) = unified_diff(plan.before.as_deref().unwrap_or(""), &plan.after, 2) else {
        return Err(fail(ctx, "refusing: the change is too long to show"));
    };
    let show = |ctx: &mut Ctx| {
        let _ = write!(
            ctx.out,
            "--- {name}\n+++ {name} (after)\n{}",
            mask_secrets(&diff)
        );
    };
    if p.has("dry-run") {
        if p.json {
            let _ = writeln!(ctx.out, "{{\"changed\":false,\"backup\":false}}");
        } else {
            show(ctx);
        }
        return Ok(());
    }
    let yes = p.has("yes");
    // The diff is what is approved: with nobody to show it to, or to ask,
    // `--yes` is the only way on.
    if !yes && (p.json || !prompt.available()) {
        return Err(ApiError::Usage("needs --yes when not interactive".into()));
    }
    if !p.json {
        show(ctx);
    }
    if !yes {
        let answer = prompt.ask(&format!("Apply these changes to {name}? [y/N] "));
        let said_yes = answer
            .map(|s| s.trim().to_lowercase())
            .is_some_and(|s| s == "y" || s == "yes");
        if !said_yes {
            let _ = writeln!(ctx.out, "No changes made.");
            return Ok(());
        }
    }
    // The file may have changed while the question was open.
    let now = read(ctx, fs, a, path)?;
    if now != plan.before {
        return Err(fail(
            ctx,
            "the file changed while waiting; nothing was written",
        ));
    }
    let real = fs.resolve(path);
    let existed = plan.before.is_some();
    let io_fail = |ctx: &mut Ctx| fail(ctx, "cannot write the file; nothing more was changed");
    let marker = with_suffix(&real, CREATED);
    // A file ShellX made, or one it owns outright, goes away whole.
    let note = (change == Change::Uninstall)
        .then(|| fs.read(&marker).ok().flatten())
        .flatten();
    let delete = change == Change::Uninstall
        && (owns_file(a) || (note.is_some() && leaves_nothing(a, &plan.after)));
    let mut backed_up = false;
    if existed && !delete {
        let bak = with_suffix(&real, BACKUP);
        // The first copy is the one worth keeping: never over an older one.
        if !fs.exists(&bak) {
            if fs.copy_mode_file(&real, &bak).is_err() {
                return Err(io_fail(ctx));
            }
            backed_up = true;
        }
    }
    let mut removed = false;
    match change {
        Change::Install => {
            let dir = real.parent().map(Path::to_path_buf);
            let made_dir = !existed && dir.as_deref().is_some_and(|d| !fs.exists(d));
            if let (false, Some(d)) = (existed, dir.as_deref()) {
                if fs.create_dir_all(d).is_err() {
                    return Err(io_fail(ctx));
                }
            }
            if fs
                .write_atomic(&real, &plan.after, existed.then_some(real.as_path()))
                .is_err()
            {
                return Err(io_fail(ctx));
            }
            if !existed {
                // So that uninstall knows the file (and folder) are ours.
                let _ = fs.write_atomic(&marker, if made_dir { "dir\n" } else { "" }, None);
            }
        }
        Change::Uninstall => {
            if delete {
                if fs.remove(&real).is_err() {
                    return Err(io_fail(ctx));
                }
                let _ = fs.remove(&marker);
                if note.is_some_and(|n| n.contains("dir")) {
                    if let Some(d) = real.parent() {
                        // Only if nothing else lives there.
                        let _ = fs.remove(d);
                    }
                }
                removed = true;
            } else {
                if fs.write_atomic(&real, &plan.after, Some(&real)).is_err() {
                    return Err(io_fail(ctx));
                }
                if note.is_some() {
                    let _ = fs.remove(&marker);
                }
            }
        }
    }
    if p.json {
        let _ = writeln!(ctx.out, "{{\"changed\":true,\"backup\":{backed_up}}}");
        return Ok(());
    }
    if backed_up {
        let _ = writeln!(ctx.out, "Backed up the old file to {name}{BACKUP}");
    }
    match change {
        Change::Install => {
            let _ = writeln!(
                ctx.out,
                "Installed. Restart running {} sessions for the hooks to apply.",
                a.product()
            );
            let exe_dir = ctx
                .exe
                .as_deref()
                .and_then(Path::parent)
                .map(|d| d.to_string_lossy().into_owned());
            let paths = path_var(ctx);
            if !on_path(&paths, exe_dir.as_deref(), cfg!(windows), &|f| fs.exists(f)) {
                let _ = writeln!(
                    ctx.out,
                    "Warning: shellx is not in your PATH; the hooks will not run until it is."
                );
            }
        }
        Change::Uninstall if removed => {
            let _ = writeln!(ctx.out, "Removed {name}.");
        }
        Change::Uninstall => {
            let _ = writeln!(ctx.out, "Removed the ShellX entries from {name}.");
        }
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::api::args::{parse, Invocation};
    use crate::api::client::{ApiError, Session};
    use crate::api::integrations::{Fs, Prompt, ReadError};
    use std::cell::RefCell;
    use std::collections::{BTreeMap, BTreeSet, VecDeque};
    use std::io;
    use std::path::{Path, PathBuf};
    use std::rc::Rc;

    #[derive(Default)]
    struct State {
        files: BTreeMap<PathBuf, (String, u32)>,
        dirs: BTreeSet<PathBuf>,
        links: BTreeMap<PathBuf, PathBuf>,
        big: BTreeSet<PathBuf>,
        writes: Vec<PathBuf>,
    }

    #[derive(Clone, Default)]
    struct FakeFs(Rc<RefCell<State>>);

    impl FakeFs {
        fn put(&self, p: &str, text: &str, mode: u32) {
            let mut s = self.0.borrow_mut();
            s.files.insert(PathBuf::from(p), (text.into(), mode));
            let mut d = PathBuf::from(p);
            while d.pop() {
                s.dirs.insert(d.clone());
            }
        }
        fn text(&self, p: &str) -> Option<String> {
            self.0.borrow().files.get(Path::new(p)).map(|f| f.0.clone())
        }
        fn mode(&self, p: &str) -> Option<u32> {
            self.0.borrow().files.get(Path::new(p)).map(|f| f.1)
        }
        fn writes(&self) -> usize {
            self.0.borrow().writes.len()
        }
        fn is_dir(&self, p: &str) -> bool {
            self.0.borrow().dirs.contains(Path::new(p))
        }
    }

    impl Fs for FakeFs {
        fn read(&self, p: &Path) -> Result<Option<String>, ReadError> {
            let s = self.0.borrow();
            let p = self.resolve(p);
            if s.big.contains(&p) {
                return Err(ReadError::TooBig);
            }
            Ok(s.files.get(&p).map(|f| f.0.clone()))
        }
        fn exists(&self, p: &Path) -> bool {
            let s = self.0.borrow();
            let p = self.resolve(p);
            s.files.contains_key(&p) || s.dirs.contains(&p)
        }
        fn resolve(&self, p: &Path) -> PathBuf {
            self.0
                .borrow()
                .links
                .get(p)
                .cloned()
                .unwrap_or_else(|| p.to_path_buf())
        }
        fn write_atomic(&mut self, p: &Path, text: &str, like: Option<&Path>) -> io::Result<()> {
            let mut s = self.0.borrow_mut();
            let mode = like
                .and_then(|l| s.files.get(l).map(|f| f.1))
                .unwrap_or(0o600);
            s.files.insert(p.to_path_buf(), (text.into(), mode));
            s.writes.push(p.to_path_buf());
            Ok(())
        }
        fn copy_mode_file(&mut self, from: &Path, to: &Path) -> io::Result<()> {
            let mut s = self.0.borrow_mut();
            let f = s.files.get(from).cloned().ok_or(io::ErrorKind::NotFound)?;
            s.files.insert(to.to_path_buf(), f);
            s.writes.push(to.to_path_buf());
            Ok(())
        }
        fn remove(&mut self, p: &Path) -> io::Result<()> {
            let mut s = self.0.borrow_mut();
            if s.files.remove(p).is_some() {
                return Ok(());
            }
            let busy = s.files.keys().any(|f| f.starts_with(p));
            if s.dirs.contains(p) && !busy {
                s.dirs.remove(p);
                return Ok(());
            }
            Err(io::ErrorKind::NotFound.into())
        }
        fn create_dir_all(&mut self, p: &Path) -> io::Result<()> {
            let mut s = self.0.borrow_mut();
            let mut d = p.to_path_buf();
            loop {
                s.dirs.insert(d.clone());
                if !d.pop() {
                    break;
                }
            }
            Ok(())
        }
    }

    struct FakePrompt {
        tty: bool,
        answers: VecDeque<Option<String>>,
        asked: Rc<RefCell<Vec<String>>>,
        /// Runs when the question is asked (the file changes under us).
        on_ask: Option<Box<dyn FnMut()>>,
    }

    impl FakePrompt {
        fn says(answers: &[Option<&str>]) -> FakePrompt {
            FakePrompt {
                tty: true,
                answers: answers.iter().map(|a| a.map(String::from)).collect(),
                asked: Rc::default(),
                on_ask: None,
            }
        }
        fn no_tty() -> FakePrompt {
            FakePrompt {
                tty: false,
                ..FakePrompt::says(&[])
            }
        }
    }

    impl Prompt for FakePrompt {
        fn available(&mut self) -> bool {
            self.tty
        }
        fn ask(&mut self, q: &str) -> Option<String> {
            self.asked.borrow_mut().push(q.to_string());
            if let Some(f) = self.on_ask.as_mut() {
                f();
            }
            self.answers.pop_front().flatten()
        }
    }

    const HOME: &str = "/h";
    const SETTINGS: &str = "/h/.claude/settings.json";
    const ORIGINAL: &str = "{\n  \"model\": \"sonnet\"\n}\n";

    struct Out {
        code: i32,
        out: String,
        err: String,
    }

    fn go(args: &[&str], fs: &FakeFs, prompt: &mut FakePrompt, on_path: &[&str]) -> Out {
        let mut all = vec!["integrations"];
        all.extend_from_slice(args);
        let all: Vec<String> = all.iter().map(|s| s.to_string()).collect();
        let Ok(Invocation::Run(p)) = parse(&all) else {
            panic!("{all:?}")
        };
        let path_dirs: Vec<String> = on_path.iter().map(|s| s.to_string()).collect();
        let get = move |k: &str| (k == "PATH").then(|| path_dirs.join(":"));
        let clock = || 0i64;
        let connect = |_: Option<&str>| -> Result<Box<dyn Session>, ApiError> {
            panic!("integrations never connect")
        };
        let (mut out, mut err) = (Vec::new(), Vec::new());
        let mut input: &[u8] = b"";
        let mut shell = fs.clone();
        let code = {
            let mut ctx = crate::api::run::Ctx {
                env: &get,
                out: &mut out,
                err: &mut err,
                stdin: &mut input,
                stdin_is_tty: false,
                cwd: PathBuf::from("/"),
                home: Some(PathBuf::from(HOME)),
                tty: None,
                shared_terminal: false,
                connect: &connect,
                stdout_gone: None,
                exe: Some(PathBuf::from("/opt/shellx/shellx")),
                now_ms: &clock,
                stdout_is_tty: false,
            };
            match run(&p, &mut ctx, &mut shell, prompt) {
                Ok(()) => 0,
                Err(ApiError::Reported(_)) => 1,
                Err(e) => {
                    let _ = write!(ctx.err, "{}", describe_for_test(&e));
                    e.exit_code()
                }
            }
        };
        Out {
            code,
            out: String::from_utf8(out).unwrap(),
            err: String::from_utf8(err).unwrap(),
        }
    }

    fn describe_for_test(e: &ApiError) -> String {
        match e {
            ApiError::Usage(m) | ApiError::Io(m) => m.clone(),
            other => format!("{other:?}"),
        }
    }

    fn with_settings(text: &str) -> FakeFs {
        let fs = FakeFs::default();
        fs.put(SETTINGS, text, 0o600);
        fs
    }

    #[test]
    fn y_writes_with_a_backup_that_keeps_the_mode() {
        let fs = with_settings(ORIGINAL);
        let mut pr = FakePrompt::says(&[Some("y")]);
        let r = go(&["install", "claude"], &fs, &mut pr, &[]);
        assert_eq!(r.code, 0, "{}", r.err);
        assert!(r.out.contains("--- ~/.claude/settings.json\n"), "{}", r.out);
        assert!(r.out.contains("+++ ~/.claude/settings.json (after)\n"));
        assert!(r.out.contains("+    \"SessionStart\": ["), "{}", r.out);
        assert_eq!(
            pr.asked.borrow().as_slice(),
            ["Apply these changes to ~/.claude/settings.json? [y/N] "]
        );
        assert!(fs
            .text(SETTINGS)
            .unwrap()
            .contains("shellx agent-event claude stop"));
        let bak = "/h/.claude/settings.json.shellx-bak";
        assert_eq!(fs.text(bak).as_deref(), Some(ORIGINAL));
        assert_eq!(fs.mode(bak), Some(0o600));
        assert_eq!(fs.mode(SETTINGS), Some(0o600));
        assert!(r
            .out
            .contains("Backed up the old file to ~/.claude/settings.json.shellx-bak\n"));
        assert!(r
            .out
            .contains("Installed. Restart running Claude Code sessions for the hooks to apply.\n"));
        assert!(
            r.out.contains("Warning: shellx is not in your PATH"),
            "{}",
            r.out
        );
    }

    #[test]
    fn n_empty_and_end_of_input_write_nothing() {
        for answer in [Some("n"), Some(""), Some("no"), Some("maybe"), None] {
            let fs = with_settings(ORIGINAL);
            let mut pr = FakePrompt::says(&[answer]);
            let r = go(&["install", "claude"], &fs, &mut pr, &[]);
            assert_eq!(r.code, 0, "{answer:?}");
            assert!(r.out.ends_with("No changes made.\n"), "{}", r.out);
            assert_eq!(fs.writes(), 0, "{answer:?}");
            assert_eq!(fs.text(SETTINGS).as_deref(), Some(ORIGINAL));
        }
    }

    #[test]
    fn yes_skips_the_prompt_and_accepts_y_in_any_case() {
        let fs = with_settings(ORIGINAL);
        let mut pr = FakePrompt::says(&[]);
        assert_eq!(
            go(&["install", "claude", "--yes"], &fs, &mut pr, &[]).code,
            0
        );
        assert!(pr.asked.borrow().is_empty());
        assert!(fs.text(SETTINGS).unwrap().contains("agent-event"));
        let fs = with_settings(ORIGINAL);
        let mut pr = FakePrompt::says(&[Some(" YES ")]);
        go(&["install", "claude"], &fs, &mut pr, &[]);
        assert!(fs.text(SETTINGS).unwrap().contains("agent-event"));
    }

    #[test]
    fn without_a_terminal_and_without_yes_nothing_happens() {
        let fs = with_settings(ORIGINAL);
        let r = go(&["install", "claude"], &fs, &mut FakePrompt::no_tty(), &[]);
        assert_eq!(r.code, 2);
        assert!(
            r.err.contains("needs --yes when not interactive"),
            "{}",
            r.err
        );
        assert_eq!(fs.writes(), 0);
        assert!(!r.out.contains("@@"), "no diff is printed to nobody");
        let r = go(
            &["uninstall", "claude"],
            &fs,
            &mut FakePrompt::no_tty(),
            &[],
        );
        assert_eq!(r.code, 0, "nothing to remove needs no consent: {}", r.err);
    }

    #[test]
    fn a_file_that_changes_while_waiting_is_not_written() {
        let fs = with_settings(ORIGINAL);
        let mut pr = FakePrompt::says(&[Some("y")]);
        let other = fs.clone();
        pr.on_ask = Some(Box::new(move || {
            other.put(SETTINGS, "{\"theme\":\"dark\"}", 0o600);
        }));
        let r = go(&["install", "claude"], &fs, &mut pr, &[]);
        assert_eq!(r.code, 1);
        assert!(
            r.err
                .contains("the file changed while waiting; nothing was written"),
            "{}",
            r.err
        );
        assert_eq!(fs.writes(), 0);
        assert_eq!(fs.text(SETTINGS).as_deref(), Some("{\"theme\":\"dark\"}"));
        // A file that appears (or vanishes) while waiting counts too.
        let fs = FakeFs::default();
        let mut pr = FakePrompt::says(&[Some("y")]);
        let other = fs.clone();
        pr.on_ask = Some(Box::new(move || other.put(SETTINGS, "{}", 0o600)));
        assert_eq!(go(&["install", "claude"], &fs, &mut pr, &[]).code, 1);
        assert_eq!(fs.text(SETTINGS).as_deref(), Some("{}"));
    }

    #[test]
    fn a_symlinked_file_is_written_through_and_the_link_stays() {
        let fs = FakeFs::default();
        fs.put("/dot/settings.json", ORIGINAL, 0o644);
        fs.0.borrow_mut()
            .links
            .insert(PathBuf::from(SETTINGS), PathBuf::from("/dot/settings.json"));
        let r = go(
            &["install", "claude", "--yes"],
            &fs,
            &mut FakePrompt::no_tty(),
            &[],
        );
        assert_eq!(r.code, 0, "{}", r.err);
        assert!(fs
            .text("/dot/settings.json")
            .unwrap()
            .contains("agent-event"));
        assert!(fs.0.borrow().links.contains_key(Path::new(SETTINGS)));
        assert!(fs.text(SETTINGS).is_none() || fs.text(SETTINGS) == fs.text("/dot/settings.json"));
        assert_eq!(
            fs.text("/dot/settings.json.shellx-bak").as_deref(),
            Some(ORIGINAL)
        );
        assert_eq!(fs.mode("/dot/settings.json"), Some(0o644));
    }

    #[test]
    fn a_created_file_leaves_a_marker_and_uninstall_removes_both() {
        let fs = FakeFs::default();
        let r = go(
            &["install", "claude", "--yes"],
            &fs,
            &mut FakePrompt::no_tty(),
            &[],
        );
        assert_eq!(r.code, 0, "{}", r.err);
        assert!(
            r.out.contains("+{\n"),
            "the whole file is the diff: {}",
            r.out
        );
        assert!(fs.text(SETTINGS).is_some());
        assert!(fs.text("/h/.claude/settings.json.shellx-created").is_some());
        assert!(
            fs.text("/h/.claude/settings.json.shellx-bak").is_none(),
            "no original, no backup"
        );
        let r = go(
            &["uninstall", "claude", "--yes"],
            &fs,
            &mut FakePrompt::no_tty(),
            &[],
        );
        assert_eq!(r.code, 0, "{}", r.err);
        assert!(fs.text(SETTINGS).is_none());
        assert!(fs.text("/h/.claude/settings.json.shellx-created").is_none());
        assert!(!fs.is_dir("/h/.claude"), "the folder we made goes too");
        assert!(
            fs.text("/h/.claude/settings.json.shellx-bak").is_none(),
            "nothing to back up"
        );
        assert!(
            r.out.contains("Removed ~/.claude/settings.json"),
            "{}",
            r.out
        );
    }

    #[test]
    fn a_folder_that_was_there_is_kept() {
        let fs = FakeFs::default();
        fs.0.borrow_mut().dirs.insert(PathBuf::from("/h/.claude"));
        go(
            &["install", "claude", "--yes"],
            &fs,
            &mut FakePrompt::no_tty(),
            &[],
        );
        go(
            &["uninstall", "claude", "--yes"],
            &fs,
            &mut FakePrompt::no_tty(),
            &[],
        );
        assert!(fs.text(SETTINGS).is_none() && fs.is_dir("/h/.claude"));
    }

    #[test]
    fn install_then_uninstall_returns_the_original_bytes() {
        let fs = with_settings(ORIGINAL);
        go(
            &["install", "claude", "--yes"],
            &fs,
            &mut FakePrompt::no_tty(),
            &[],
        );
        let r = go(
            &["uninstall", "claude", "--yes"],
            &fs,
            &mut FakePrompt::no_tty(),
            &[],
        );
        assert_eq!(r.code, 0, "{}", r.err);
        assert_eq!(fs.text(SETTINGS).as_deref(), Some(ORIGINAL));
        assert!(
            fs.text(SETTINGS).is_some(),
            "a file that was ours-and-theirs stays"
        );
    }

    #[test]
    fn dry_run_prints_the_diff_and_writes_nothing() {
        let fs = with_settings(ORIGINAL);
        let mut pr = FakePrompt::says(&[Some("y")]);
        let r = go(&["install", "claude", "--dry-run"], &fs, &mut pr, &[]);
        assert_eq!(r.code, 0);
        assert!(
            r.out.contains("@@") && !r.out.contains("Apply these"),
            "{}",
            r.out
        );
        assert!(pr.asked.borrow().is_empty());
        assert_eq!(fs.writes(), 0);
        // Even without a terminal.
        let r = go(
            &["install", "claude", "--dry-run"],
            &fs,
            &mut FakePrompt::no_tty(),
            &[],
        );
        assert_eq!(r.code, 0);
    }

    #[test]
    fn print_shows_only_what_to_add() {
        let fs = with_settings("{ // comment\n}");
        let r = go(
            &["install", "claude", "--print"],
            &fs,
            &mut FakePrompt::no_tty(),
            &[],
        );
        assert_eq!(r.code, 0, "{}", r.err);
        assert!(r.out.contains("shellx agent-event claude stop"));
        assert!(
            !r.out.contains("comment") && !r.out.contains("---"),
            "{}",
            r.out
        );
        assert_eq!(fs.writes(), 0);
    }

    #[test]
    fn a_second_install_is_a_no_op_and_keeps_the_first_backup() {
        let fs = with_settings(ORIGINAL);
        go(
            &["install", "claude", "--yes"],
            &fs,
            &mut FakePrompt::no_tty(),
            &[],
        );
        let bak = "/h/.claude/settings.json.shellx-bak";
        assert_eq!(fs.text(bak).as_deref(), Some(ORIGINAL));
        let after_first = fs.text(SETTINGS);
        let n = fs.writes();
        let r = go(
            &["install", "claude", "--yes"],
            &fs,
            &mut FakePrompt::no_tty(),
            &[],
        );
        assert_eq!(r.code, 0);
        assert!(r.out.contains("Already installed."), "{}", r.out);
        assert_eq!((fs.writes(), fs.text(SETTINGS)), (n, after_first));
        assert_eq!(fs.text(bak).as_deref(), Some(ORIGINAL));
    }

    #[test]
    fn an_older_backup_is_never_overwritten() {
        let fs = with_settings(ORIGINAL);
        fs.put(
            "/h/.claude/settings.json.shellx-bak",
            "THE FIRST ONE",
            0o600,
        );
        go(
            &["install", "claude", "--yes"],
            &fs,
            &mut FakePrompt::no_tty(),
            &[],
        );
        assert_eq!(
            fs.text("/h/.claude/settings.json.shellx-bak").as_deref(),
            Some("THE FIRST ONE")
        );
    }

    #[test]
    fn refusals_exit_1_with_a_fixed_sentence_and_write_nothing() {
        let fs = with_settings("{ // mine\n  \"password\": \"hunter2\"\n}");
        let r = go(
            &["install", "claude", "--yes"],
            &fs,
            &mut FakePrompt::no_tty(),
            &[],
        );
        assert_eq!(r.code, 1);
        assert!(
            r.err.contains("refusing: the file has comments"),
            "{}",
            r.err
        );
        assert!(r.err.contains("--print"));
        assert!(!r.err.contains("hunter2") && !r.out.contains("hunter2"));
        assert_eq!(fs.writes(), 0);
        let fs = with_settings(ORIGINAL);
        fs.0.borrow_mut().big.insert(PathBuf::from(SETTINGS));
        let r = go(
            &["install", "claude", "--yes"],
            &fs,
            &mut FakePrompt::no_tty(),
            &[],
        );
        assert_eq!(r.code, 1);
        assert!(r.err.contains("over 1 MiB"), "{}", r.err);
        let r = go(
            &["uninstall", "claude", "--yes"],
            &fs,
            &mut FakePrompt::no_tty(),
            &[],
        );
        assert_eq!(r.code, 1);
    }

    #[test]
    fn the_diff_never_shows_a_secret() {
        let secret = "{\n  \"env\": {\n    \"ANTHROPIC_API_KEY\": \"sk-ant-FAKE\",\n    \"HTTPS_PROXY\": \"http://user:FAKEPASS@proxy.example:8080\"\n  },\n  \"apiKeyHelper\": \"echo FAKE\"\n}\n";
        let fs = with_settings(secret);
        let r = go(
            &["install", "claude", "--dry-run"],
            &fs,
            &mut FakePrompt::no_tty(),
            &[],
        );
        assert_eq!(r.code, 0, "{}", r.err);
        for leak in ["sk-ant-FAKE", "FAKEPASS", "echo FAKE"] {
            assert!(!r.out.contains(leak), "{leak} in {}", r.out);
        }
        assert!(r.out.contains("\"apiKeyHelper\": \"…\""), "{}", r.out);
    }

    #[test]
    fn json_output_has_no_file_content() {
        let secret = "{\n  \"apiKeyHelper\": \"echo FAKE\",\n  \"model\": \"sonnet\"\n}\n";
        let fs = with_settings(secret);
        let r = go(
            &["install", "claude", "--yes", "--json"],
            &fs,
            &mut FakePrompt::no_tty(),
            &[],
        );
        assert_eq!(r.out, "{\"changed\":true,\"backup\":true}\n");
        assert!(!r.out.contains("sonnet") && !r.out.contains(".claude"));
        let r = go(
            &["install", "claude", "--yes", "--json"],
            &fs,
            &mut FakePrompt::no_tty(),
            &[],
        );
        assert_eq!(r.out, "{\"changed\":false,\"backup\":false}\n");
        let r = go(
            &["status", "claude", "--json"],
            &fs,
            &mut FakePrompt::no_tty(),
            &["/bin"],
        );
        assert_eq!(
            r.out,
            "{\"agents\":[{\"agent\":\"claude\",\"installed\":true,\"path\":\"~/.claude/settings.json\",\"found\":false}]}\n"
        );
        // Without --yes there is nobody to ask and nothing to show: refused.
        let fs = with_settings(ORIGINAL);
        let r = go(
            &["install", "claude", "--json"],
            &fs,
            &mut FakePrompt::says(&[Some("y")]),
            &[],
        );
        assert_eq!(r.code, 2);
        assert_eq!(fs.writes(), 0);
    }

    #[test]
    fn status_lists_each_agent_and_whether_its_program_is_found() {
        let fs = FakeFs::default();
        fs.put("/bin/claude", "", 0o755);
        let r = go(&["status"], &fs, &mut FakePrompt::no_tty(), &["/bin"]);
        assert_eq!(
            r.out,
            "✗ claude    not installed\n- codex     not found on PATH\n- gemini    not found on PATH\n"
        );
        let r = go(
            &["status", "claude"],
            &fs,
            &mut FakePrompt::no_tty(),
            &["/nowhere"],
        );
        assert_eq!(r.out, "- claude    not found on PATH\n");
        go(
            &["install", "claude", "--yes"],
            &fs,
            &mut FakePrompt::no_tty(),
            &[],
        );
        let r = go(
            &["status", "claude"],
            &fs,
            &mut FakePrompt::no_tty(),
            &["/bin"],
        );
        assert_eq!(r.out, "✓ claude    installed   (~/.claude/settings.json)\n");
        // Installed wins over "not found".
        let r = go(&["status"], &fs, &mut FakePrompt::no_tty(), &["/nowhere"]);
        assert!(r.out.starts_with("✓ claude    installed"), "{}", r.out);
        // A file ShellX cannot read safely is simply not installed.
        fs.put(SETTINGS, "{ // c", 0o600);
        assert!(go(&["status"], &fs, &mut FakePrompt::no_tty(), &["/bin"])
            .out
            .starts_with("✗"));
    }

    #[test]
    fn a_shellx_on_the_path_silences_the_warning() {
        let fs = with_settings(ORIGINAL);
        fs.put("/opt/shellx/shellx", "", 0o755);
        let r = go(
            &["install", "claude", "--yes"],
            &fs,
            &mut FakePrompt::no_tty(),
            &["/opt/shellx"],
        );
        assert!(!r.out.contains("Warning"), "{}", r.out);
    }

    const CODEX: &str = "/h/.codex/config.toml";

    #[test]
    fn codex_install_is_a_two_line_diff_and_uninstall_returns_the_bytes() {
        let original = "# my config\nmodel = \"o3\"\n\n[tui]\nx = 1\n";
        let fs = FakeFs::default();
        fs.put(CODEX, original, 0o600);
        let r = go(
            &["install", "codex", "--yes"],
            &fs,
            &mut FakePrompt::no_tty(),
            &[],
        );
        assert_eq!(r.code, 0, "{}", r.err);
        assert!(r.out.contains("--- ~/.codex/config.toml\n"), "{}", r.out);
        assert!(r
            .out
            .contains("+notify = [\"shellx\", \"agent-event\", \"codex\", \"turn-complete\"]\n"));
        assert!(
            r.out.contains("Restart running Codex sessions"),
            "{}",
            r.out
        );
        assert_eq!(
            fs.text("/h/.codex/config.toml.shellx-bak").as_deref(),
            Some(original)
        );
        let again = go(
            &["install", "codex", "--yes"],
            &fs,
            &mut FakePrompt::no_tty(),
            &[],
        );
        assert!(again.out.contains("Already installed."));
        let r = go(
            &["uninstall", "codex", "--yes"],
            &fs,
            &mut FakePrompt::no_tty(),
            &[],
        );
        assert_eq!(r.code, 0, "{}", r.err);
        assert_eq!(fs.text(CODEX).as_deref(), Some(original));
    }

    #[test]
    fn a_users_notify_is_refused_with_the_fixed_sentence_and_print_helps() {
        let fs = FakeFs::default();
        fs.put(CODEX, "notify = [\"my-script\"]\n", 0o600);
        let r = go(
            &["install", "codex", "--yes"],
            &fs,
            &mut FakePrompt::no_tty(),
            &[],
        );
        assert_eq!(r.code, 1);
        assert!(
            r.err.contains("refusing: \"notify\" is already set in config.toml (shellx will not replace it; see --print)"),
            "{}",
            r.err
        );
        assert!(!r.err.contains("my-script") && !r.out.contains("my-script"));
        assert_eq!(fs.writes(), 0);
        let r = go(
            &["install", "codex", "--print"],
            &fs,
            &mut FakePrompt::no_tty(),
            &[],
        );
        assert_eq!(r.code, 0);
        assert!(
            r.out.contains("agent-event") && !r.out.contains("my-script"),
            "{}",
            r.out
        );
    }

    #[test]
    fn a_codex_file_we_created_is_removed_with_its_folder() {
        let fs = FakeFs::default();
        go(
            &["install", "codex", "--yes"],
            &fs,
            &mut FakePrompt::no_tty(),
            &[],
        );
        assert!(fs.text(CODEX).unwrap().starts_with("# shellx:"));
        let r = go(
            &["uninstall", "codex", "--yes"],
            &fs,
            &mut FakePrompt::no_tty(),
            &[],
        );
        assert_eq!(r.code, 0, "{}", r.err);
        assert!(fs.text(CODEX).is_none() && !fs.is_dir("/h/.codex"));
        assert!(r.out.contains("Removed ~/.codex/config.toml."), "{}", r.out);
    }

    #[test]
    fn unknown_or_missing_agents_are_usage_errors() {
        let fs = with_settings(ORIGINAL);
        let r = go(&["install", "cursor"], &fs, &mut FakePrompt::no_tty(), &[]);
        assert_eq!(r.code, 2);
        assert!(
            !r.err.contains("cursor"),
            "what the user typed is not echoed"
        );
        assert_eq!(
            go(&["status", "cursor"], &fs, &mut FakePrompt::no_tty(), &[]).code,
            2
        );
        let args = vec!["integrations".to_string(), "install".to_string()];
        assert!(parse(&args).is_err(), "AGENT is required");
    }

    #[test]
    fn uninstall_of_something_never_installed_is_a_quiet_success() {
        let fs = FakeFs::default();
        let r = go(
            &["uninstall", "claude", "--yes"],
            &fs,
            &mut FakePrompt::no_tty(),
            &[],
        );
        assert_eq!((r.code, r.out.as_str()), (0, "Not installed.\n"));
        let fs = with_settings(ORIGINAL);
        let r = go(
            &["uninstall", "claude", "--yes"],
            &fs,
            &mut FakePrompt::no_tty(),
            &[],
        );
        assert_eq!((r.code, r.out.as_str()), (0, "Not installed.\n"));
        assert_eq!(fs.writes(), 0);
    }
}
