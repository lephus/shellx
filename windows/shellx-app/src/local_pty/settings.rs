//! Which shell a new local pane starts (spec §4.4; Rulings 3, 16 to 19): the stored choice
//! (`settings.json`), the catalogue of installed shells and the launch plan, all decided by
//! `shellx_model::shell`.
//!
//! Looking shells up checks files, and a PATH entry on an offline network folder can make
//! each check take seconds, so the lookup runs on a background thread and its result is
//! cached: a new pane only reads the cache. Only the very first pane waits for the first
//! lookup, at most `first_wait`; until that lookup ends every pane starts Windows PowerShell
//! by its System32 path with Command Prompt as the fallback, which needs no check
//! (CreateProcess says when a file is missing).

use std::io;
use std::path::PathBuf;
use std::sync::{Arc, Condvar, Mutex, MutexGuard, OnceLock, PoisonError};
use std::time::Duration;

use shellx_model::shell::{
    LaunchPlan, ShellChoice, ShellError, ShellKind, ShellLaunch, ShellProbe, find_shells,
    is_absolute, known_launch, launch_plan,
};

use super::{PanePlan, ShellCmd, dev_bash};

/// How long the first pane waits for the first lookup (Ruling 16).
const FIRST_WAIT: Duration = Duration::from_secs(2);

type Exists = Arc<dyn Fn(&str) -> bool + Send + Sync>;

/// Where the window runs.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ShellHost {
    /// Shells are looked up, chosen and planned.
    Windows,
    /// The macOS development build: always bash, or `SHELLX_SHELL` (Ruling 19).
    MacDev,
}

/// `settings.json` in the app's native folder: `{"shell": <ShellChoice>}` (Ruling 3). Keys
/// this version does not know are kept when it rewrites the file.
pub struct SettingsFile {
    /// `None`: there is no folder to keep it in (`LOCALAPPDATA` unset).
    path: Option<PathBuf>,
}

impl SettingsFile {
    pub fn new(path: PathBuf) -> Self {
        SettingsFile { path: Some(path) }
    }

    fn unavailable() -> Self {
        SettingsFile { path: None }
    }

    /// The stored choice. A missing or unreadable file, or a value this version does not
    /// know, means Auto.
    pub fn load(&self) -> ShellChoice {
        self.read_object()
            .and_then(|mut object| object.remove("shell"))
            .and_then(|value| serde_json::from_value(value).ok())
            .unwrap_or_default()
    }

    /// Stores `choice`, keeping the file's other keys: written to a temporary file next to
    /// it, then renamed over it. Creates the folder when it is missing.
    pub fn save(&self, choice: &ShellChoice) -> io::Result<()> {
        let path = self
            .path
            .as_ref()
            .ok_or_else(|| io::Error::new(io::ErrorKind::NotFound, "LOCALAPPDATA is not set"))?;
        let mut object = self.read_object().unwrap_or_default();
        object.insert(
            "shell".to_string(),
            serde_json::to_value(choice).map_err(io::Error::other)?,
        );
        let text = serde_json::to_string_pretty(&serde_json::Value::Object(object))
            .map_err(io::Error::other)?;
        if let Some(dir) = path.parent() {
            std::fs::create_dir_all(dir)?;
        }
        let tmp = path.with_extension(format!("json.{}.tmp", std::process::id()));
        let written = std::fs::write(&tmp, text).and_then(|()| std::fs::rename(&tmp, path));
        if written.is_err() {
            let _ = std::fs::remove_file(&tmp);
        }
        written
    }

    fn read_object(&self) -> Option<serde_json::Map<String, serde_json::Value>> {
        let text = std::fs::read_to_string(self.path.as_ref()?).ok()?;
        match serde_json::from_str(&text).ok()? {
            serde_json::Value::Object(object) => Some(object),
            _ => None,
        }
    }
}

/// "Is a program file" (Ruling 17): a file, or a link that leads to one. `symlink_metadata`
/// comes first because on Windows it reports an App Execution Alias (the Microsoft Store's
/// `WindowsApps\pwsh.exe`) as a file, which following it with `metadata` could not open.
/// Folders, drive roots, missing paths and dangling links are not.
pub fn is_program_file(path: &str) -> bool {
    if path.is_empty() {
        return false;
    }
    match std::fs::symlink_metadata(path) {
        Ok(meta) if meta.is_file() => true,
        Ok(meta) if meta.is_symlink() => std::fs::metadata(path).is_ok_and(|m| m.is_file()),
        _ => false,
    }
}

/// What this machine says about where shells live: `%SystemRoot%`, `%ProgramFiles%`,
/// `%ComSpec%`, `%PATH%` and Git for Windows' install folder (Ruling 18).
pub fn probe_from_system() -> ShellProbe {
    let var = |name: &str| {
        std::env::var_os(name)
            .map(|v| v.to_string_lossy().into_owned())
            .filter(|v| !v.trim().is_empty())
    };
    ShellProbe {
        system_root: var("SystemRoot"),
        program_files: var("ProgramFiles"),
        comspec: var("ComSpec"),
        path: var("PATH").unwrap_or_default(),
        git_install_path: git_install_path(),
    }
}

/// `InstallPath` under `HKLM\SOFTWARE\GitForWindows`, then the same key under `HKCU`
/// (per-user installs); only an absolute value counts.
#[cfg(windows)]
fn git_install_path() -> Option<String> {
    use winreg::RegKey;
    use winreg::enums::{HKEY_CURRENT_USER, HKEY_LOCAL_MACHINE};
    [HKEY_LOCAL_MACHINE, HKEY_CURRENT_USER]
        .into_iter()
        .find_map(|root| {
            RegKey::predef(root)
                .open_subkey(r"SOFTWARE\GitForWindows")
                .ok()?
                .get_value::<String, _>("InstallPath")
                .ok()
                .filter(|v| is_absolute(v.trim()))
        })
}

#[cfg(not(windows))]
fn git_install_path() -> Option<String> {
    None
}

/// `%SystemRoot%` as a folder: trimmed, absolute, without a trailing backslash; else
/// `C:\Windows`.
pub(crate) fn system_root(probe: &ShellProbe) -> &str {
    probe
        .system_root
        .as_deref()
        .map(str::trim)
        .filter(|v| is_absolute(v))
        .map(|v| v.trim_end_matches('\\'))
        .unwrap_or(r"C:\Windows")
}

/// The plan before the first lookup ends (Ruling 16): Windows PowerShell by its System32
/// path, with the prompt hook, and Command Prompt as the fallback. Nothing is checked.
pub fn startup_plan(probe: &ShellProbe) -> PanePlan {
    let root = system_root(probe);
    PanePlan {
        first: ShellCmd::from_launch(&known_launch(
            ShellKind::WindowsPowerShell,
            format!(r"{root}\System32\WindowsPowerShell\v1.0\powershell.exe"),
        )),
        fallback: Some(ShellCmd::from_launch(&known_launch(
            ShellKind::Cmd,
            format!(r"{root}\System32\cmd.exe"),
        ))),
    }
}

/// What the shell settings know now (Settings › Terminal, `--diagnose`).
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ShellSnapshot {
    pub choice: ShellChoice,
    /// `SHELLX_SHELL`, when it is set and not blank: it wins over `choice`.
    pub env_override: Option<String>,
    /// The installed shells (`find_shells`); empty until the first lookup ends.
    pub found: Vec<ShellLaunch>,
    /// `None` until the first lookup ends.
    pub plan: Option<Result<LaunchPlan, ShellError>>,
}

/// One lookup's result.
struct Computed {
    found: Vec<ShellLaunch>,
    plan: Result<LaunchPlan, ShellError>,
}

struct State {
    choice: ShellChoice,
    /// The newest lookup's result; never goes back to `None`.
    computed: Option<Computed>,
    /// Numbers the lookups; only the newest one's result is kept.
    generation: u64,
    /// Lookups started and not ended.
    running: usize,
    /// The first pane already asked (only it ever waits).
    asked: bool,
}

struct Inner {
    file: SettingsFile,
    probe: ShellProbe,
    env_override: Option<String>,
    exists: Exists,
    host: ShellHost,
    first_wait: Duration,
    state: Mutex<State>,
    ended: Condvar,
}

impl Inner {
    fn lock(&self) -> MutexGuard<'_, State> {
        self.state.lock().unwrap_or_else(PoisonError::into_inner)
    }

    /// Counts a lookup as started; returns its number and the choice it plans for.
    fn begin(&self, state: &mut State) -> (u64, ShellChoice) {
        state.generation += 1;
        state.running += 1;
        (state.generation, state.choice.clone())
    }

    /// The file checks: call without the lock.
    fn compute(&self, choice: &ShellChoice) -> Computed {
        let exists = |path: &str| (self.exists)(path);
        let found = find_shells(&self.probe, &exists);
        let plan = launch_plan(
            choice,
            self.env_override.as_deref(),
            &found,
            &self.probe,
            &exists,
        );
        Computed { found, plan }
    }

    fn end(&self, generation: u64, computed: Option<Computed>) {
        let mut state = self.lock();
        state.running -= 1;
        if let Some(computed) = computed
            && state.generation == generation
        {
            state.computed = Some(computed);
        }
        self.ended.notify_all();
    }
}

/// A lookup in progress. However it ends, by returning or by a panic in a file check,
/// dropping it counts it as ended, so the next pane can start another one; only a lookup
/// that finished leaves its `result`.
struct Lookup {
    inner: Arc<Inner>,
    generation: u64,
    result: Option<Computed>,
}

impl Drop for Lookup {
    fn drop(&mut self) {
        self.inner.end(self.generation, self.result.take());
    }
}

/// The shell settings and the cached catalogue. `shells()` is the app's one instance.
pub struct Shells {
    inner: Arc<Inner>,
}

impl Shells {
    /// Reads the stored choice from `file`; looks nothing up yet. `exists` answers "is this
    /// a program file" (`is_program_file`); a blank `env_override` is no override.
    pub fn new(
        file: SettingsFile,
        probe: ShellProbe,
        env_override: Option<String>,
        exists: Exists,
        host: ShellHost,
        first_wait: Duration,
    ) -> Shells {
        let choice = file.load();
        Shells {
            inner: Arc::new(Inner {
                file,
                probe,
                env_override: env_override.filter(|v| !v.trim().is_empty()),
                exists,
                host,
                first_wait,
                state: Mutex::new(State {
                    choice,
                    computed: None,
                    generation: 0,
                    running: 0,
                    asked: false,
                }),
                ended: Condvar::new(),
            }),
        }
    }

    pub fn probe(&self) -> ShellProbe {
        self.inner.probe.clone()
    }

    pub fn snapshot(&self) -> ShellSnapshot {
        let state = self.inner.lock();
        ShellSnapshot {
            choice: state.choice.clone(),
            env_override: self.inner.env_override.clone(),
            found: state
                .computed
                .as_ref()
                .map(|c| c.found.clone())
                .unwrap_or_default(),
            plan: state.computed.as_ref().map(|c| c.plan.clone()),
        }
    }

    /// What a new pane starts. Reads the cache; the first call starts the first lookup and
    /// waits for it at most `first_wait`. Until a lookup has ended: `startup_plan`. On the
    /// Mac: bash (or `SHELLX_SHELL`), without a fallback.
    pub fn plan_for_new_pane(&self) -> Result<PanePlan, ShellError> {
        let inner = &self.inner;
        if inner.host == ShellHost::MacDev {
            return Ok(PanePlan {
                first: dev_bash(inner.env_override.as_deref()),
                fallback: None,
            });
        }
        let mut state = inner.lock();
        if state.computed.is_none() && state.running == 0 {
            self.spawn_lookup(&mut state);
        }
        if !state.asked {
            state.asked = true;
            state = inner
                .ended
                .wait_timeout_while(state, inner.first_wait, |s| s.computed.is_none())
                .unwrap_or_else(PoisonError::into_inner)
                .0;
        }
        match &state.computed {
            Some(computed) => computed
                .plan
                .as_ref()
                .map(PanePlan::from_plan)
                .map_err(Clone::clone),
            None => Ok(startup_plan(&inner.probe)),
        }
    }

    fn spawn_lookup(&self, state: &mut State) {
        let (generation, choice) = self.inner.begin(state);
        let inner = self.inner.clone();
        let spawned = std::thread::Builder::new()
            .name("shell-lookup".into())
            .spawn(move || {
                let mut lookup = Lookup {
                    inner,
                    generation,
                    result: None,
                };
                lookup.result = Some(lookup.inner.compute(&choice));
            });
        if spawned.is_err() {
            // no thread: the panes keep the startup plan
            state.running -= 1;
        }
    }
}

#[allow(dead_code)] // Settings › Terminal (Task A6) and --diagnose (Task B9)
impl Shells {
    pub fn choice(&self) -> ShellChoice {
        self.inner.lock().choice.clone()
    }

    /// Stores the choice, then looks shells up again in the background. Auto and a known
    /// shell need only the cached catalogue, so the plan follows them at once and the next
    /// tab already starts the new choice; a custom line needs file checks and waits for the
    /// lookup. Nothing changes when the file cannot be written.
    pub fn set_choice(&self, choice: ShellChoice) -> io::Result<()> {
        let mut state = self.inner.lock();
        self.inner.file.save(&choice)?;
        let replan =
            self.inner.env_override.is_none() && !matches!(choice, ShellChoice::Custom { .. });
        if replan && let Some(computed) = state.computed.as_mut() {
            // no file is checked for Auto or a known shell
            computed.plan = launch_plan(&choice, None, &computed.found, &self.inner.probe, &|_| {
                false
            });
        }
        state.choice = choice;
        // Under the same lock: a lookup already running for the old choice gets an older
        // number now, so it can no longer overwrite the plan made above (review M2).
        self.spawn_lookup(&mut state);
        Ok(())
    }

    /// Looks shells up again on a background thread.
    pub fn refresh(&self) {
        let mut state = self.inner.lock();
        self.spawn_lookup(&mut state);
    }

    /// Looks shells up on this thread and returns what it found. Blocks for as long as the
    /// file checks take: never call it on the UI thread.
    pub fn refresh_now(&self) -> ShellSnapshot {
        let (generation, choice) = {
            let mut state = self.inner.lock();
            self.inner.begin(&mut state)
        };
        let mut lookup = Lookup {
            inner: self.inner.clone(),
            generation,
            result: None,
        };
        let computed = self.inner.compute(&choice);
        let snapshot = ShellSnapshot {
            choice,
            env_override: self.inner.env_override.clone(),
            found: computed.found.clone(),
            plan: Some(computed.plan.clone()),
        };
        lookup.result = Some(computed);
        drop(lookup);
        snapshot
    }
}

/// The app's shell settings: `settings.json` in `paths::native_dir()`, this machine's probe,
/// `SHELLX_SHELL`, real file checks, Windows or the Mac development build, a 2 s first wait.
pub fn shells() -> &'static Shells {
    static SHELLS: OnceLock<Shells> = OnceLock::new();
    SHELLS.get_or_init(|| {
        let file = match crate::paths::native_dir() {
            Ok(dir) => SettingsFile::new(dir.join("settings.json")),
            Err(_) => SettingsFile::unavailable(),
        };
        let host = if cfg!(windows) {
            ShellHost::Windows
        } else {
            ShellHost::MacDev
        };
        Shells::new(
            file,
            probe_from_system(),
            std::env::var("SHELLX_SHELL").ok(),
            Arc::new(is_program_file),
            host,
            FIRST_WAIT,
        )
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::collections::HashSet;
    use std::path::PathBuf;
    use std::sync::Arc;
    use std::time::{Duration, Instant};

    use shellx_model::shell::{
        CustomShellError, POWERSHELL_PROMPT_HOOK, ShellChoice, ShellError, ShellKind, ShellLaunch,
        ShellProbe,
    };

    use crate::local_pty::{ShellCmd, command_prompt_for};

    const PWSH: &str = r"C:\Program Files\PowerShell\7\pwsh.exe";
    const WINPS: &str = r"C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe";
    const CMD: &str = r"C:\Windows\system32\cmd.exe";
    const SYSTEM32_CMD: &str = r"C:\Windows\System32\cmd.exe";

    /// A Windows machine as the probe sees it (the tests run on a Mac).
    fn probe() -> ShellProbe {
        ShellProbe {
            system_root: Some(r"C:\Windows".into()),
            program_files: Some(r"C:\Program Files".into()),
            comspec: Some(CMD.into()),
            path: r"C:\Windows\System32".into(),
            git_install_path: None,
        }
    }

    type Exists = Arc<dyn Fn(&str) -> bool + Send + Sync>;

    fn exists_in(files: &[&str]) -> Exists {
        let set: HashSet<String> = files.iter().map(|f| f.to_string()).collect();
        Arc::new(move |p: &str| set.contains(p))
    }

    /// Every answer takes `delay`: an offline network folder on PATH.
    fn slow(delay: Duration, files: &[&str]) -> Exists {
        let fast = exists_in(files);
        Arc::new(move |p: &str| {
            std::thread::sleep(delay);
            fast(p)
        })
    }

    /// `settings.json` in a folder whose name has Vietnamese letters and a space.
    fn settings_path() -> (tempfile::TempDir, PathBuf) {
        let dir = tempfile::tempdir().unwrap();
        let folder = dir.path().join("Phú Lê");
        std::fs::create_dir_all(&folder).unwrap();
        let path = folder.join("settings.json");
        (dir, path)
    }

    fn windows(path: &PathBuf, exists: Exists, env: Option<&str>, wait: Duration) -> Shells {
        Shells::new(
            SettingsFile::new(path.clone()),
            probe(),
            env.map(String::from),
            exists,
            ShellHost::Windows,
            wait,
        )
    }

    /// The catalogue's entry for `kind` on `probe()` with every shell installed: what a
    /// lookup would start.
    fn catalogue_entry(kind: ShellKind) -> ShellCmd {
        let all = exists_in(&[PWSH, WINPS, CMD]);
        let found = find_shells(&probe(), &|p: &str| all(p));
        ShellCmd::from_launch(found.iter().find(|l| l.kind == Some(kind)).unwrap())
    }

    /// The PowerShell arguments end with the OSC 7 prompt hook (R3 m1).
    fn carries_the_prompt_hook(cmd: &ShellCmd) -> bool {
        cmd.args
            .ends_with(&["-Command".to_string(), POWERSHELL_PROMPT_HOOK.to_string()])
    }

    fn kinds(found: &[ShellLaunch]) -> Vec<Option<ShellKind>> {
        found.iter().map(|l| l.kind).collect()
    }

    fn json(path: &PathBuf) -> serde_json::Value {
        serde_json::from_str(&std::fs::read_to_string(path).unwrap()).unwrap()
    }

    #[test]
    fn the_stored_choice_round_trips_and_keeps_other_keys() {
        let (_dir, path) = settings_path();
        std::fs::write(
            &path,
            r#"{"shell":{"kind":"known","shell":"git_bash"},"future":1}"#,
        )
        .unwrap();
        let file = SettingsFile::new(path.clone());
        assert_eq!(
            file.load(),
            ShellChoice::Known {
                shell: ShellKind::GitBash
            }
        );
        file.save(&ShellChoice::Auto).unwrap();
        assert_eq!(
            json(&path),
            serde_json::json!({"shell": {"kind": "auto"}, "future": 1})
        );
        let custom = ShellChoice::Custom {
            command_line: r#""C:\Program Files\Git\bin\bash.exe" -l"#.into(),
        };
        file.save(&custom).unwrap();
        assert_eq!(file.load(), custom);
        assert_eq!(json(&path)["future"], 1);
        // the temporary file was renamed over settings.json: nothing else is left
        let names: Vec<_> = std::fs::read_dir(path.parent().unwrap())
            .unwrap()
            .map(|e| e.unwrap().file_name())
            .collect();
        assert_eq!(names, ["settings.json"]);
        // a folder that does not exist yet is created
        let nested = path.parent().unwrap().join("native").join("settings.json");
        SettingsFile::new(nested.clone())
            .save(&ShellChoice::Auto)
            .unwrap();
        assert_eq!(SettingsFile::new(nested).load(), ShellChoice::Auto);
    }

    #[test]
    fn a_missing_or_unreadable_file_means_auto() {
        let (_dir, path) = settings_path();
        let file = SettingsFile::new(path.clone());
        assert_eq!(file.load(), ShellChoice::Auto);
        for text in [
            "{",
            "[]",
            r#"{"shell":{"kind":"bash"}}"#,
            r#"{"shell":3}"#,
            "",
        ] {
            std::fs::write(&path, text).unwrap();
            assert_eq!(file.load(), ShellChoice::Auto, "{text}");
        }
        // saving over an unreadable file leaves a readable one
        std::fs::write(&path, "[]").unwrap();
        let cmd = ShellChoice::Known {
            shell: ShellKind::Cmd,
        };
        file.save(&cmd).unwrap();
        assert_eq!(file.load(), cmd);
    }

    #[test]
    fn the_catalogue_follows_the_choice_and_shellx_shell() {
        let (_dir, path) = settings_path();
        let files = [PWSH, WINPS, CMD];
        let shells = windows(&path, exists_in(&files), None, Duration::from_millis(100));
        assert_eq!(shells.choice(), ShellChoice::Auto);
        let snap = shells.refresh_now();
        assert_eq!(snap.choice, ShellChoice::Auto);
        assert_eq!(snap.env_override, None);
        assert_eq!(
            kinds(&snap.found),
            [
                Some(ShellKind::Pwsh),
                Some(ShellKind::WindowsPowerShell),
                Some(ShellKind::Cmd)
            ]
        );
        let plan = snap.plan.unwrap().unwrap();
        assert_eq!(plan.first.kind, Some(ShellKind::Pwsh));
        assert_eq!(
            plan.fallback.as_ref().unwrap().kind,
            Some(ShellKind::WindowsPowerShell)
        );
        // the OSC 7 prompt hook travels in PowerShell's arguments
        let first = ShellCmd::from_launch(&plan.first);
        assert_eq!(first.program, PWSH);
        assert!(carries_the_prompt_hook(&first), "{:?}", first.args);
        assert!(first.env.is_empty());
        assert_eq!(first.label, "PowerShell 7");
        assert_eq!(first.kind, Some(ShellKind::Pwsh));

        // a stored choice: saved, then the next plan starts it
        let cmd = ShellChoice::Known {
            shell: ShellKind::Cmd,
        };
        shells.set_choice(cmd.clone()).unwrap();
        assert_eq!(shells.choice(), cmd);
        assert_eq!(SettingsFile::new(path.clone()).load(), cmd);
        let plan = shells.refresh_now().plan.unwrap().unwrap();
        assert_eq!(plan.first.kind, Some(ShellKind::Cmd));
        assert!(plan.first.args.is_empty());
        assert_eq!(plan.fallback.unwrap().kind, Some(ShellKind::Pwsh));
        let pane = shells.plan_for_new_pane().unwrap();
        assert_eq!(pane.first.label, "Command Prompt");
        assert_eq!(pane.first.program, CMD);
        assert_eq!(pane.fallback.unwrap().label, "PowerShell 7");

        // SHELLX_SHELL wins over the stored choice and takes arguments
        let over = windows(
            &path,
            exists_in(&files),
            Some(r"C:\Windows\system32\cmd.exe /k"),
            Duration::from_millis(100),
        );
        let snap = over.refresh_now();
        assert_eq!(
            snap.env_override.as_deref(),
            Some(r"C:\Windows\system32\cmd.exe /k")
        );
        let plan = snap.plan.unwrap().unwrap();
        assert_eq!(plan.first.program, CMD);
        assert_eq!(plan.first.args, ["/k"]);
        // a blank SHELLX_SHELL is no override
        let blank = windows(&path, exists_in(&files), Some("  "), Duration::ZERO);
        assert_eq!(blank.refresh_now().env_override, None);

        // a custom line that names no program is an error, not another shell
        shells
            .set_choice(ShellChoice::Custom {
                command_line: "nope.exe".into(),
            })
            .unwrap();
        let missing = ShellError::Custom(CustomShellError::NotFound("nope.exe".into()));
        assert_eq!(shells.refresh_now().plan, Some(Err(missing.clone())));
        assert_eq!(shells.plan_for_new_pane(), Err(missing));
    }

    #[test]
    fn the_first_pane_waits_at_most_the_bound_then_starts_windows_powershell() {
        let (_dir, path) = settings_path();
        let shells = windows(
            &path,
            slow(Duration::from_secs(1), &[PWSH, WINPS, CMD]),
            None,
            Duration::from_millis(100),
        );
        let started = Instant::now();
        let plan = shells.plan_for_new_pane().unwrap();
        let took = started.elapsed();
        assert!(took >= Duration::from_millis(90), "{took:?}");
        assert!(took < Duration::from_secs(1), "{took:?}");
        // exactly what a lookup would start for Windows PowerShell, prompt hook included
        assert_eq!(plan.first, catalogue_entry(ShellKind::WindowsPowerShell));
        assert_eq!(plan.first.program, WINPS);
        assert!(carries_the_prompt_hook(&plan.first));
        let fallback = plan.fallback.unwrap();
        assert_eq!(fallback.program, SYSTEM32_CMD);
        assert!(fallback.args.is_empty());
        assert_eq!(fallback.label, "Command Prompt");
        // the probe is still running: nothing is known yet
        assert_eq!(shells.snapshot().plan, None);
        assert!(shells.snapshot().found.is_empty());
    }

    #[test]
    fn a_new_pane_uses_the_catalogue_once_it_is_ready() {
        let (_dir, path) = settings_path();
        let shells = windows(
            &path,
            exists_in(&[PWSH, WINPS, CMD]),
            None,
            Duration::from_millis(100),
        );
        shells.refresh_now();
        assert_eq!(
            shells.plan_for_new_pane().unwrap().first.label,
            "PowerShell 7"
        );

        // the probe the first pane started feeds the panes after it
        let shells = windows(
            &path,
            slow(Duration::from_millis(20), &[PWSH, WINPS, CMD]),
            None,
            Duration::ZERO,
        );
        assert_eq!(
            shells.plan_for_new_pane().unwrap().first.label,
            "Windows PowerShell"
        );
        let deadline = Instant::now() + Duration::from_secs(10);
        while shells.snapshot().plan.is_none() {
            assert!(
                Instant::now() < deadline,
                "the background probe never ended"
            );
            std::thread::sleep(Duration::from_millis(10));
        }
        assert_eq!(
            shells.plan_for_new_pane().unwrap().first.label,
            "PowerShell 7"
        );
    }

    #[test]
    fn a_new_choice_reaches_the_next_pane_before_the_lookup_ends() {
        use std::sync::atomic::{AtomicBool, Ordering};

        let (_dir, path) = settings_path();
        let files = exists_in(&[PWSH, WINPS, CMD]);
        // while the gate is shut every file check waits: no lookup can end
        let gate_open = Arc::new(AtomicBool::new(true));
        let exists: Exists = {
            let gate_open = gate_open.clone();
            Arc::new(move |p: &str| {
                while !gate_open.load(Ordering::SeqCst) {
                    std::thread::sleep(Duration::from_millis(2));
                }
                files(p)
            })
        };
        let shells = windows(&path, exists, None, Duration::ZERO);
        shells.refresh_now();
        gate_open.store(false, Ordering::SeqCst);

        // Auto and a known shell are planned from the cached catalogue at once
        shells
            .set_choice(ShellChoice::Known {
                shell: ShellKind::Cmd,
            })
            .unwrap();
        let plan = shells.plan_for_new_pane().unwrap();
        assert_eq!(plan.first.label, "Command Prompt");
        assert_eq!(plan.fallback.unwrap().label, "PowerShell 7");
        shells.set_choice(ShellChoice::Auto).unwrap();
        assert_eq!(
            shells.plan_for_new_pane().unwrap().first.label,
            "PowerShell 7"
        );

        // a custom line needs file checks: it waits for the lookup
        shells
            .set_choice(ShellChoice::Custom {
                command_line: CMD.into(),
            })
            .unwrap();
        assert_eq!(
            shells.plan_for_new_pane().unwrap().first.label,
            "PowerShell 7"
        );
        gate_open.store(true, Ordering::SeqCst);
        let deadline = Instant::now() + Duration::from_secs(5);
        while shells.plan_for_new_pane().unwrap().first.kind.is_some() {
            assert!(Instant::now() < deadline, "the custom line never applied");
            std::thread::sleep(Duration::from_millis(10));
        }
        assert_eq!(shells.plan_for_new_pane().unwrap().first.program, CMD);
    }

    #[test]
    fn a_lookup_that_panics_does_not_stop_the_next_one() {
        use std::sync::atomic::{AtomicBool, Ordering};

        let (_dir, path) = settings_path();
        let files = exists_in(&[PWSH, WINPS, CMD]);
        let failed_once = Arc::new(AtomicBool::new(false));
        let exists: Exists = {
            let failed_once = failed_once.clone();
            Arc::new(move |p: &str| {
                if !failed_once.swap(true, Ordering::SeqCst) {
                    panic!("a file check failed (test)");
                }
                files(p)
            })
        };
        let shells = windows(&path, exists, None, Duration::from_millis(100));
        // the first lookup dies: the first pane gets the startup plan
        assert_eq!(
            shells.plan_for_new_pane().unwrap().first.label,
            "Windows PowerShell"
        );
        // a later pane starts another lookup, which ends
        let deadline = Instant::now() + Duration::from_secs(5);
        while shells.plan_for_new_pane().unwrap().first.label != "PowerShell 7" {
            assert!(
                Instant::now() < deadline,
                "no lookup ran again after one panicked"
            );
            std::thread::sleep(Duration::from_millis(10));
        }
    }

    #[test]
    fn only_the_first_pane_ever_waits() {
        let (_dir, path) = settings_path();
        let shells = windows(
            &path,
            slow(Duration::from_secs(1), &[PWSH, WINPS, CMD]),
            None,
            Duration::from_millis(100),
        );
        let started = Instant::now();
        let first = shells.plan_for_new_pane().unwrap();
        assert!(started.elapsed() >= Duration::from_millis(90));
        let started = Instant::now();
        let second = shells.plan_for_new_pane().unwrap();
        assert!(
            started.elapsed() < Duration::from_millis(20),
            "{:?}",
            started.elapsed()
        );
        assert_eq!(first.first.program, WINPS);
        assert_eq!(second.first.program, WINPS);
    }

    #[test]
    fn the_mac_harness_keeps_bash() {
        let (_dir, path) = settings_path();
        SettingsFile::new(path.clone())
            .save(&ShellChoice::Known {
                shell: ShellKind::Cmd,
            })
            .unwrap();
        let mac = |env: Option<&str>| {
            Shells::new(
                SettingsFile::new(path.clone()),
                ShellProbe::default(),
                env.map(String::from),
                exists_in(&[]),
                ShellHost::MacDev,
                Duration::from_secs(2),
            )
        };
        let plan = mac(None).plan_for_new_pane().unwrap();
        assert_eq!(plan.first.program, "/bin/bash");
        assert_eq!(plan.first.args, ["--noprofile", "--norc", "-i"]);
        assert!(
            plan.first
                .env
                .iter()
                .any(|(k, v)| k == "PROMPT_COMMAND" && v.contains("]7;file://"))
        );
        assert_eq!(plan.first.label, "bash");
        // SHELLX_SHELL: that program, without arguments
        let plan = mac(Some("/bin/zsh")).plan_for_new_pane().unwrap();
        assert_eq!(plan.first.program, "/bin/zsh");
        assert!(plan.first.args.is_empty());
        assert_eq!(plan.fallback, None);
    }

    #[cfg(unix)]
    #[test]
    fn program_files_are_files_folders_are_not_links_are_followed() {
        let dir = tempfile::tempdir().unwrap();
        let at = |name: &str| dir.path().join(name).to_str().unwrap().to_string();
        std::fs::write(at("a.exe"), b"MZ").unwrap();
        std::fs::create_dir(at("d")).unwrap();
        std::os::unix::fs::symlink(at("a.exe"), at("l.exe")).unwrap();
        std::os::unix::fs::symlink(at("gone.exe"), at("dangling.exe")).unwrap();
        std::os::unix::fs::symlink(at("d"), at("dir-link")).unwrap();
        assert!(is_program_file(&at("a.exe")));
        assert!(!is_program_file(&at("d")));
        assert!(is_program_file(&at("l.exe")));
        assert!(!is_program_file(&at("dangling.exe")));
        assert!(!is_program_file(&at("dir-link")));
        assert!(!is_program_file(&at("missing.exe")));
        assert!(!is_program_file(""));
    }

    #[test]
    fn command_prompt_prefers_the_catalogue_then_comspec_then_system32() {
        let found = vec![ShellLaunch {
            kind: Some(ShellKind::Cmd),
            program: CMD.into(),
            args: vec![],
            osc7_hook: false,
        }];
        let cmd = command_prompt_for(&found, &probe());
        assert_eq!(cmd.program, CMD);
        assert_eq!(cmd.label, "Command Prompt");
        assert_eq!(cmd.kind, Some(ShellKind::Cmd));
        assert!(cmd.args.is_empty() && cmd.env.is_empty());

        let comspec = ShellProbe {
            comspec: Some(r"D:\cmd\cmd.exe".into()),
            ..probe()
        };
        assert_eq!(command_prompt_for(&[], &comspec).program, r"D:\cmd\cmd.exe");

        let relative = ShellProbe {
            comspec: Some("cmd.exe".into()),
            ..probe()
        };
        let cmd = command_prompt_for(&[], &relative);
        assert_eq!(cmd.program, SYSTEM32_CMD);
        assert_eq!(cmd.label, "Command Prompt");
        // nothing usable at all: C:\Windows
        let bare = ShellProbe {
            system_root: Some("Windows".into()),
            comspec: None,
            ..ShellProbe::default()
        };
        assert_eq!(command_prompt_for(&[], &bare).program, SYSTEM32_CMD);
    }

    #[test]
    fn the_startup_plan_reads_system_root_without_probing() {
        let plan = startup_plan(&ShellProbe {
            system_root: Some(r"D:\Win\".into()),
            ..ShellProbe::default()
        });
        assert_eq!(
            plan.first.program,
            r"D:\Win\System32\WindowsPowerShell\v1.0\powershell.exe"
        );
        assert_eq!(plan.fallback.unwrap().program, r"D:\Win\System32\cmd.exe");
        let plan = startup_plan(&ShellProbe::default());
        assert_eq!(plan.first.program, WINPS);
    }
}
