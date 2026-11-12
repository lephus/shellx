//! Crash files and the crash reporter (spec §4.2 "Không lỗi nào im lặng", Rulings 8, 9, 13).
//!
//! The panic hook writes a crash file for every panic on every thread and then starts this
//! exe again as the reporter (`--report-crash <file>`), a separate process without GPUI that
//! shows the dialog: the hook itself never draws, because on the UI thread it runs inside
//! GPUI's window procedure. The texts and file names are `shellx_model::crash_report`'s; the
//! decisions the hook makes are in `handle_panic`, which the tests drive without installing
//! the global hook. Nothing in the hook unwraps: a file that cannot be written is skipped.

use std::cell::{Cell, RefCell};
use std::ffi::OsString;
use std::fs::OpenOptions;
use std::io::{ErrorKind, Write};
use std::path::{Path, PathBuf};
use std::sync::OnceLock;
use std::sync::atomic::{AtomicBool, AtomicU8, Ordering};
use std::time::{SystemTime, UNIX_EPOCH};

use shellx_model::crash_report::{self, CrashFileKind, DialogKind, PanicFacts, WindowFailureFacts};
use shellx_model::log_file::compact_utc;
use shellx_model::strings::Lang;

use crate::{build_info, logger, os_info, paths};

/// What every crash file of this process says about it, gathered at start-up.
#[derive(Clone, Debug)]
pub struct CrashContext {
    pub logs_dir: PathBuf,
    pub exe: PathBuf,
    pub version: String,
    pub commit: String,
    pub build: String,
    pub windows: String,
    pub exe_base: Option<u64>,
    pub main_thread_id: Option<u32>,
}

impl CrashContext {
    /// This process, read on the main thread (it records that thread's id).
    pub fn this_process() -> CrashContext {
        CrashContext {
            logs_dir: paths::logs_dir(),
            exe: std::env::current_exe().unwrap_or_default(),
            version: shellx_model::VERSION.to_string(),
            commit: build_info::commit().unwrap_or("unknown").to_string(),
            build: build_info::build_kind().to_string(),
            windows: os_info::os_version(),
            exe_base: exe_base(),
            main_thread_id: current_thread_id(),
        }
    }
}

/// The OS thread id (`GetCurrentThreadId`; it cannot fail); `None` off Windows.
fn current_thread_id() -> Option<u32> {
    #[cfg(windows)]
    {
        // SAFETY: no arguments, no failure.
        Some(unsafe { windows_sys::Win32::System::Threading::GetCurrentThreadId() })
    }
    #[cfg(not(windows))]
    {
        None
    }
}

/// Where the exe is loaded (`GetModuleHandleW(NULL)`: the module that created the process),
/// so `ip - base` maps backtrace frames inside it later; `None` when the call fails or off
/// Windows.
fn exe_base() -> Option<u64> {
    #[cfg(windows)]
    {
        // SAFETY: a null name asks for the process's own exe; nothing is borrowed.
        let module = unsafe {
            windows_sys::Win32::System::LibraryLoader::GetModuleHandleW(std::ptr::null())
        };
        (!module.is_null()).then_some(module as u64)
    }
    #[cfg(not(windows))]
    {
        None
    }
}

/// `Dialog`: the window and `--diagnose`; a panic starts the reporter. `FileOnly`: console
/// flags and CI; the file is written, no dialog waits on a desktop nobody sees.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum HookMode {
    Dialog,
    FileOnly,
}

/// The once-per-process reporter flag. The hook uses one static `HookState`; each test its
/// own, so parallel tests do not share it.
pub struct HookState {
    reporter_started: AtomicBool,
}

impl HookState {
    pub const fn new() -> HookState {
        HookState {
            reporter_started: AtomicBool::new(false),
        }
    }

    /// True for the first caller only.
    fn claim_reporter(&self) -> bool {
        !self.reporter_started.swap(true, Ordering::SeqCst)
    }
}

static HOOK_STATE: HookState = HookState::new();
static CONTEXT: OnceLock<CrashContext> = OnceLock::new();
static CRASH_TEST: AtomicU8 = AtomicU8::new(0);

thread_local! {
    /// Set while this thread runs the hook body (a panic inside it does not re-enter it).
    static IN_HOOK: Cell<bool> = const { Cell::new(false) };
    /// Depth of `expect_caught` on this thread.
    static CAUGHT_DEPTH: Cell<u32> = const { Cell::new(0) };
    /// The crash file this thread wrote last (Ruling 9).
    static LAST_FILE: RefCell<Option<PathBuf>> = const { RefCell::new(None) };
    /// True on the thread that installed the hook (main), for platforms without thread ids.
    static IS_MAIN: Cell<bool> = const { Cell::new(false) };
}

/// One panic as the hook saw it. `utc` is `compact_utc` (the file name's time).
pub(crate) struct PanicParts {
    pub utc: String,
    pub location: String,
    pub message: String,
    pub thread_id: Option<u32>,
    pub main_thread: bool,
}

/// Installs the panic hook for every thread, keeping `ctx` for `context()`. The previous hook
/// runs after ours (so `--smoke` keeps its stderr output).
pub fn install_panic_hook(ctx: CrashContext, mode: HookMode) {
    let _ = IS_MAIN.try_with(|main| main.set(true));
    let _ = CONTEXT.set(ctx);
    let previous = std::panic::take_hook();
    std::panic::set_hook(Box::new(move |info| {
        run_hook(info, mode);
        previous(info);
    }));
}

/// The context the hook was installed with.
pub fn context() -> Option<&'static CrashContext> {
    CONTEXT.get()
}

fn run_hook(info: &std::panic::PanicHookInfo<'_>, mode: HookMode) {
    // A thread whose locals are gone (a panic while it exits) still gets its file.
    if IN_HOOK
        .try_with(|in_hook| in_hook.replace(true))
        .unwrap_or(false)
    {
        return;
    }
    if let Some(ctx) = CONTEXT.get() {
        let parts = panic_parts(info, ctx);
        let spawn = |file: &Path| spawn_reporter(ctx, DialogKind::Crash, file);
        // `{:#}` keeps every frame's address (Ruling 11; plan review I-2). Captured only after
        // the file and the dialog (review m2).
        let backtrace = || format!("{:#}", std::backtrace::Backtrace::force_capture());
        let _ = handle_panic(ctx, &parts, mode, &HOOK_STATE, &spawn, &backtrace);
    }
    let _ = IN_HOOK.try_with(|in_hook| in_hook.set(false));
}

fn now_secs() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_or(0, |d| d.as_secs())
}

fn panic_parts(info: &std::panic::PanicHookInfo<'_>, ctx: &CrashContext) -> PanicParts {
    let payload = info.payload();
    let message = if let Some(s) = payload.downcast_ref::<&str>() {
        (*s).to_string()
    } else if let Some(s) = payload.downcast_ref::<String>() {
        s.clone()
    } else {
        "<non-string panic payload>".to_string()
    };
    let location = info.location().map_or_else(
        || "unknown".to_string(),
        |l| format!("{}:{}:{}", l.file(), l.line(), l.column()),
    );
    let (thread_id, main_thread) = thread_facts(ctx);
    PanicParts {
        utc: compact_utc(now_secs()),
        location,
        message,
        thread_id,
        main_thread,
    }
}

/// The OS thread id and whether this is the main thread, without `std::thread::current()`
/// (Ruling 9).
fn thread_facts(ctx: &CrashContext) -> (Option<u32>, bool) {
    let id = current_thread_id();
    let main = match (id, ctx.main_thread_id) {
        (Some(id), Some(main)) => id == main,
        _ => IS_MAIN.try_with(Cell::get).unwrap_or(false),
    };
    (id, main)
}

/// Runs `f` with the hook told that a `catch_unwind` around it handles any panic (the
/// pairing job): the crash file is still written, the reporter is not started.
pub fn expect_caught<R>(f: impl FnOnce() -> R) -> R {
    struct Depth;
    impl Drop for Depth {
        fn drop(&mut self) {
            let _ = CAUGHT_DEPTH.try_with(|d| d.set(d.get().saturating_sub(1)));
        }
    }
    let _ = CAUGHT_DEPTH.try_with(|d| d.set(d.get().saturating_add(1)));
    let _depth = Depth;
    f()
}

fn caught() -> bool {
    CAUGHT_DEPTH.try_with(|d| d.get() > 0).unwrap_or(false)
}

fn last_file() -> Option<PathBuf> {
    LAST_FILE
        .try_with(|f| f.try_borrow_mut().ok().and_then(|f| f.clone()))
        .ok()
        .flatten()
}

fn remember_last_file(path: &Path) {
    let _ = LAST_FILE.try_with(|f| {
        if let Ok(mut f) = f.try_borrow_mut() {
            *f = Some(path.to_path_buf());
        }
    });
}

fn file_name(path: &Path) -> String {
    path.file_name()
        .map(|n| n.to_string_lossy().into_owned())
        .unwrap_or_default()
}

/// Creates `dir/name` (or `name.2.txt` … `name.99.txt` when it exists) with `text`; `None`
/// on any other error or past 99.
fn create_new_in(dir: &Path, name: &str, text: &str) -> Option<PathBuf> {
    let _ = std::fs::create_dir_all(dir);
    for n in 1..=99u32 {
        let candidate = if n == 1 {
            name.to_string()
        } else {
            crash_report::numbered_file_name(name, n)
        };
        let path = dir.join(candidate);
        match OpenOptions::new().write(true).create_new(true).open(&path) {
            Ok(mut file) => {
                let _ = file.write_all(text.as_bytes());
                return Some(path);
            }
            Err(e) if e.kind() == ErrorKind::AlreadyExists => continue,
            Err(_) => return None,
        }
    }
    None
}

/// A new file in the logs folder, else the same name in the temp folder.
fn write_new_file(dir: &Path, name: &str, text: &str) -> Option<PathBuf> {
    create_new_in(dir, name, text).or_else(|| create_new_in(&std::env::temp_dir(), name, text))
}

fn append_text(path: &Path, text: &str) {
    if let Ok(mut file) = OpenOptions::new().append(true).open(path) {
        let _ = file.write_all(text.as_bytes());
    }
}

fn append_line(path: &Path, line: &str) {
    append_text(path, &format!("{line}\n"));
}

/// The hook's body (Rulings 8, 9). An abort follow-up (`panic in a function that cannot
/// unwind` after a real panic on this thread) is appended to that panic's file; any other
/// panic gets a new `crash.<utc>.<pid>.txt`, one line in the log, and, in `Dialog` mode and
/// outside `expect_caught`, the reporter once per `state`; only then is `backtrace` called
/// and its section appended (symbolizing can hang or fault: the file and the dialog must not
/// wait for it, review m2). A follow-up never calls `backtrace`. Returns the file written or
/// appended to. A file that cannot be written anywhere still starts the reporter, which then
/// names the intended path.
pub(crate) fn handle_panic(
    ctx: &CrashContext,
    parts: &PanicParts,
    mode: HookMode,
    state: &HookState,
    spawn: &dyn Fn(&Path) -> bool,
    backtrace: &dyn Fn() -> String,
) -> Option<PathBuf> {
    if let Some(line) = crash_report::follow_up_line(&parts.message)
        && let Some(last) = last_file()
        && last.is_file()
    {
        append_line(&last, &line);
        return Some(last);
    }
    let name = crash_report::crash_file_name(CrashFileKind::Panic, &parts.utc, std::process::id());
    let head = crash_report::panic_report_head(&PanicFacts {
        utc: parts.utc.clone(),
        version: ctx.version.clone(),
        commit: ctx.commit.clone(),
        build: ctx.build.clone(),
        windows: ctx.windows.clone(),
        exe_base: ctx.exe_base,
        thread_id: parts.thread_id,
        main_thread: parts.main_thread,
        location: parts.location.clone(),
        message: parts.message.clone(),
        backtrace: String::new(),
    });
    let written = write_new_file(&ctx.logs_dir, &name, &head);
    match &written {
        Some(path) => {
            remember_last_file(path);
            logger::try_append(&format!("panic: see {}", file_name(path)));
        }
        None => logger::try_append("panic: the crash file could not be written"),
    }
    if mode == HookMode::Dialog && !caught() && state.claim_reporter() {
        let file = written.clone().unwrap_or_else(|| ctx.logs_dir.join(&name));
        let _ = spawn(&file);
    }
    if let Some(path) = &written {
        append_text(path, &crash_report::backtrace_section(&backtrace()));
    }
    written
}

/// The start-failure file `start-failed.<utc>.<pid>.txt`: the crash header, `render` (one
/// more line, as given, when `Some`), `error:` and the chain; every line redacted.
pub fn write_window_failure(
    ctx: &CrashContext,
    error: &anyhow::Error,
    render: Option<&str>,
) -> Option<PathBuf> {
    let utc = compact_utc(now_secs());
    let report = crash_report::window_failure_report(&WindowFailureFacts {
        utc: utc.clone(),
        version: ctx.version.clone(),
        commit: ctx.commit.clone(),
        build: ctx.build.clone(),
        windows: ctx.windows.clone(),
        exe_base: ctx.exe_base,
        render: render.map(str::to_string),
        errors: error.chain().map(|e| e.to_string()).collect(),
    });
    let name = crash_report::crash_file_name(CrashFileKind::WindowFailed, &utc, std::process::id());
    write_new_file(&ctx.logs_dir, &name, &report)
}

fn spawn_reporter(ctx: &CrashContext, kind: DialogKind, file: &Path) -> bool {
    std::process::Command::new(&ctx.exe)
        .arg(kind.reporter_flag())
        .arg(file)
        .spawn()
        .is_ok()
}

/// Starts `<this exe> --report-crash|--report-window <file>`, at most once per process
/// (shared with the panic hook). False when it already ran or could not start.
pub fn start_reporter(ctx: &CrashContext, kind: DialogKind, file: &Path) -> bool {
    HOOK_STATE.claim_reporter() && spawn_reporter(ctx, kind, file)
}

/// The reporter process: asks whether to open the folder that holds `file` and opens it with
/// Explorer on Yes. No GPUI, no hook, no log. Off Windows it prints the title and body to
/// stderr. Always 0: a box that cannot be shown counts as No.
pub fn run_reporter(kind: DialogKind, file: &Path) -> i32 {
    let lang = Lang::from_system(
        std::env::var("SHELLX_LANG").ok().as_deref(),
        os_info::ui_language_id(),
    );
    let text = crash_report::report_dialog(lang, kind, &file.to_string_lossy());
    #[cfg(windows)]
    {
        if ask_yes_no(&text) {
            open_folder_of(file);
        }
    }
    #[cfg(not(windows))]
    {
        let _ = writeln!(std::io::stderr(), "{}\n{}", text.title, text.body);
    }
    0
}

/// NUL-terminated UTF-16; a NUL inside (impossible in our texts) becomes a space.
#[cfg(windows)]
fn wide(text: &str) -> Vec<u16> {
    text.encode_utf16()
        .map(|u| if u == 0 { 0x20 } else { u })
        .chain(std::iter::once(0))
        .collect()
}

/// `MessageBoxW` with Yes/No; `MB_TOPMOST` keeps it above other windows even when Windows
/// refuses it the foreground (plan review M-12). 0 (failure) or No → false.
#[cfg(windows)]
fn ask_yes_no(text: &crash_report::DialogText) -> bool {
    use windows_sys::Win32::UI::WindowsAndMessaging::{
        IDYES, MB_ICONERROR, MB_SETFOREGROUND, MB_TOPMOST, MB_YESNO, MessageBoxW,
    };
    let title = wide(&text.title);
    let body = wide(&text.body);
    // SAFETY: both buffers are NUL-terminated UTF-16 that outlive the call; a null owner
    // window is allowed.
    let answer = unsafe {
        MessageBoxW(
            std::ptr::null_mut(),
            body.as_ptr(),
            title.as_ptr(),
            MB_YESNO | MB_ICONERROR | MB_SETFOREGROUND | MB_TOPMOST,
        )
    };
    answer == IDYES
}

/// `%SystemRoot%\explorer.exe /select,"<file>"`; a start that fails is ignored. Explorer
/// parses its own command line, so the argument goes raw (Windows paths cannot hold `"`).
#[cfg(windows)]
fn open_folder_of(file: &Path) {
    use std::os::windows::process::CommandExt;
    let mut arg = OsString::from("/select,\"");
    arg.push(file.as_os_str());
    arg.push("\"");
    let _ = std::process::Command::new(explorer_exe(std::env::var_os("SystemRoot")))
        .raw_arg(arg)
        .spawn();
}

/// `C:\…` or `\\server\…`.
#[cfg_attr(not(windows), allow(dead_code))]
fn is_windows_absolute(path: &str) -> bool {
    let b = path.as_bytes();
    let drive =
        b.len() >= 3 && b[0].is_ascii_alphabetic() && b[1] == b':' && matches!(b[2], b'\\' | b'/');
    drive || path.starts_with(r"\\")
}

/// `<SystemRoot>\explorer.exe` when `SystemRoot` is absolute, else `C:\Windows\explorer.exe`
/// (never a PATH lookup).
#[cfg_attr(not(windows), allow(dead_code))]
pub(crate) fn explorer_exe(system_root: Option<OsString>) -> PathBuf {
    let root = system_root
        .filter(|root| is_windows_absolute(&root.to_string_lossy()))
        .unwrap_or_else(|| OsString::from(r"C:\Windows"));
    PathBuf::from(root).join("explorer.exe")
}

/// `--crash-test panic|native|window` (Ruling 31): developer flags that do nothing unless
/// passed.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum CrashTest {
    Panic,
    Native,
    Window,
}

/// The value after `--crash-test`; an unknown or missing value is no crash test.
pub(crate) fn crash_test_from(args: &[OsString]) -> Option<CrashTest> {
    let i = args.iter().position(|a| a == "--crash-test")?;
    match args.get(i + 1)?.to_str()? {
        "panic" => Some(CrashTest::Panic),
        "native" => Some(CrashTest::Native),
        "window" => Some(CrashTest::Window),
        _ => None,
    }
}

pub fn set_crash_test(test: Option<CrashTest>) {
    let code = match test {
        None => 0,
        Some(CrashTest::Panic) => 1,
        Some(CrashTest::Native) => 2,
        Some(CrashTest::Window) => 3,
    };
    CRASH_TEST.store(code, Ordering::SeqCst);
}

pub fn crash_test() -> Option<CrashTest> {
    match CRASH_TEST.load(Ordering::SeqCst) {
        1 => Some(CrashTest::Panic),
        2 => Some(CrashTest::Native),
        3 => Some(CrashTest::Window),
        _ => None,
    }
}

#[cfg(test)]
mod tests {
    use std::cell::RefCell;
    use std::path::{Path, PathBuf};

    use super::*;

    const T43: &str = "AbCdEfGhIjKlMnOpQrStUvWxYz0123456789_-AbCdE"; // 43 chars, base64url

    fn ctx(dir: &Path) -> CrashContext {
        CrashContext {
            logs_dir: dir.join("logs"),
            exe: PathBuf::from("/nowhere/shellx-desktop"),
            version: "1.7.0".into(),
            commit: "unknown".into(),
            build: "release".into(),
            windows: "10.0.26100".into(),
            exe_base: Some(0x7FF6_A000_0000),
            main_thread_id: Some(7),
        }
    }

    fn parts(message: &str, location: &str) -> PanicParts {
        PanicParts {
            utc: "20261112-081530".into(),
            location: location.into(),
            message: message.into(),
            thread_id: Some(7),
            main_thread: true,
        }
    }

    /// The backtrace a test's panic has (`{:#}` form).
    fn backtrace() -> String {
        "   0:     0x7ff6a1b2c3d4 - <unknown>".to_string()
    }

    fn files_in(dir: &Path) -> Vec<String> {
        let mut names: Vec<String> = std::fs::read_dir(dir)
            .unwrap()
            .map(|e| e.unwrap().file_name().to_string_lossy().into_owned())
            .collect();
        names.sort();
        names
    }

    #[test]
    fn the_hook_writes_a_file_and_asks_for_one_reporter() {
        let tmp = tempfile::tempdir().unwrap();
        let ctx = ctx(tmp.path());
        let state = HookState::new();
        let spawned: RefCell<Vec<PathBuf>> = RefCell::new(Vec::new());
        let spawn = |file: &Path| {
            spawned.borrow_mut().push(file.to_path_buf());
            true
        };
        let pid = std::process::id();
        let first = handle_panic(
            &ctx,
            &parts("the first panic", "src/a.rs:1:1"),
            HookMode::Dialog,
            &state,
            &spawn,
            &backtrace,
        )
        .unwrap();
        let second = handle_panic(
            &ctx,
            &parts("another panic", "src/b.rs:2:2"),
            HookMode::Dialog,
            &state,
            &spawn,
            &backtrace,
        )
        .unwrap();
        assert_eq!(
            first,
            ctx.logs_dir
                .join(format!("crash.20261112-081530.{pid}.txt"))
        );
        assert_eq!(
            second,
            ctx.logs_dir
                .join(format!("crash.20261112-081530.{pid}.2.txt"))
        );
        let one = std::fs::read_to_string(&first).unwrap();
        let two = std::fs::read_to_string(&second).unwrap();
        assert!(one.lines().any(|l| l == "location: src/a.rs:1:1"), "{one}");
        assert!(two.lines().any(|l| l == "location: src/b.rs:2:2"), "{two}");
        assert!(
            one.lines().any(|l| l == "message: the first panic"),
            "{one}"
        );
        assert_eq!(*spawned.borrow(), vec![first]);
    }

    #[test]
    fn an_abort_follow_up_is_appended_to_the_first_report() {
        let tmp = tempfile::tempdir().unwrap();
        let ctx = ctx(tmp.path());
        let state = HookState::new();
        let spawned = RefCell::new(0);
        let spawn = |_: &Path| {
            *spawned.borrow_mut() += 1;
            true
        };
        let first = handle_panic(
            &ctx,
            &parts("the real panic", "src/ui/app.rs:9:9"),
            HookMode::Dialog,
            &state,
            &spawn,
            &backtrace,
        )
        .unwrap();
        let second = handle_panic(
            &ctx,
            &parts(
                "panic in a function that cannot unwind",
                "/rustc/0000/library/core/src/panicking.rs:225:5",
            ),
            HookMode::Dialog,
            &state,
            &spawn,
            &backtrace,
        )
        .unwrap();
        assert_eq!(second, first);
        assert_eq!(files_in(&ctx.logs_dir).len(), 1);
        let text = std::fs::read_to_string(&first).unwrap();
        let locations: Vec<&str> = text
            .lines()
            .filter(|l| l.starts_with("location:"))
            .collect();
        assert_eq!(locations, vec!["location: src/ui/app.rs:9:9"]);
        let thens: Vec<&str> = text.lines().filter(|l| l.starts_with("then:")).collect();
        assert_eq!(
            thens,
            vec!["then: panic in a function that cannot unwind (the process aborts)"]
        );
        assert_eq!(text.lines().last(), Some(thens[0]));
        assert_eq!(*spawned.borrow(), 1);
    }

    #[test]
    fn a_caught_panic_writes_a_file_but_starts_no_reporter() {
        let tmp = tempfile::tempdir().unwrap();
        let ctx = ctx(tmp.path());
        let state = HookState::new();
        let spawned = RefCell::new(0);
        let spawn = |_: &Path| {
            *spawned.borrow_mut() += 1;
            true
        };
        let caught = expect_caught(|| {
            handle_panic(
                &ctx,
                &parts("a core call panicked", "src/x.rs:1:1"),
                HookMode::Dialog,
                &state,
                &spawn,
                &backtrace,
            )
        })
        .unwrap();
        assert!(caught.is_file());
        assert_eq!(*spawned.borrow(), 0);
        // FileOnly writes the file and starts no reporter either.
        let file_only = handle_panic(
            &ctx,
            &parts("in --smoke", "src/y.rs:1:1"),
            HookMode::FileOnly,
            &state,
            &spawn,
            &backtrace,
        )
        .unwrap();
        assert!(file_only.is_file());
        assert_eq!(*spawned.borrow(), 0);
        // Outside expect_caught, in Dialog mode, the reporter starts.
        handle_panic(
            &ctx,
            &parts("a real one", "src/z.rs:1:1"),
            HookMode::Dialog,
            &state,
            &spawn,
            &backtrace,
        );
        assert_eq!(*spawned.borrow(), 1);
        assert_eq!(files_in(&ctx.logs_dir).len(), 3);
    }

    #[test]
    fn the_backtrace_is_taken_after_the_file_and_never_for_a_follow_up() {
        // Review m2: symbolizing can hang or fault, so the file and the dialog come first.
        let tmp = tempfile::tempdir().unwrap();
        let ctx = ctx(tmp.path());
        let state = HookState::new();
        let events: RefCell<Vec<&str>> = RefCell::new(Vec::new());
        let spawn = |_: &Path| {
            events.borrow_mut().push("reporter");
            true
        };
        let backtrace = || {
            events.borrow_mut().push("backtrace");
            "   0:     0x7ff6a1b2c3d4 - <unknown>".to_string()
        };
        let file = handle_panic(
            &ctx,
            &parts("the real panic", "src/ui/app.rs:9:9"),
            HookMode::Dialog,
            &state,
            &spawn,
            &backtrace,
        )
        .unwrap();
        assert_eq!(*events.borrow(), ["reporter", "backtrace"]);
        let text = std::fs::read_to_string(&file).unwrap();
        let message = text.lines().position(|l| l == "message: the real panic").unwrap();
        let lines: Vec<&str> = text.lines().collect();
        assert_eq!(lines[message + 1], "backtrace:");
        assert_eq!(lines[message + 2], "   0:     0x7ff6a1b2c3d4 - <unknown>");
        // The abort follow-up takes no backtrace.
        handle_panic(
            &ctx,
            &parts("panic in a function that cannot unwind", "core/src/panicking.rs:225:5"),
            HookMode::Dialog,
            &state,
            &spawn,
            &backtrace,
        );
        assert_eq!(*events.borrow(), ["reporter", "backtrace"]);
        assert!(std::fs::read_to_string(&file).unwrap().ends_with("(the process aborts)\n"));
    }

    #[test]
    fn the_start_failure_file_is_redacted() {
        let tmp = tempfile::tempdir().unwrap();
        let ctx = ctx(tmp.path());
        let error = anyhow::anyhow!("the relay refused token {T43}, code 123456")
            .context("signed in as a@b.co")
            .context("could not open the window");
        let file =
            write_window_failure(&ctx, &error, Some("render mode: standard (default)")).unwrap();
        let name = file.file_name().unwrap().to_string_lossy().into_owned();
        assert!(
            name.starts_with("start-failed.") && name.ends_with(".txt"),
            "{name}"
        );
        let text = std::fs::read_to_string(&file).unwrap();
        assert!(
            text.lines().any(|l| l == "render mode: standard (default)"),
            "{text}"
        );
        assert!(
            text.lines()
                .any(|l| l == "error: could not open the window"),
            "{text}"
        );
        assert!(!text.contains("a@b.co") && !text.contains(T43), "{text}");
        assert!(!text.contains("123456"), "{text}");
    }

    #[test]
    fn crash_test_flags_are_read_from_the_arguments() {
        use std::ffi::OsString;
        let args = |v: &[&str]| v.iter().map(OsString::from).collect::<Vec<_>>();
        assert_eq!(
            crash_test_from(&args(&["--crash-test", "panic"])),
            Some(CrashTest::Panic)
        );
        assert_eq!(
            crash_test_from(&args(&["--crash-test", "native"])),
            Some(CrashTest::Native)
        );
        assert_eq!(
            crash_test_from(&args(&["x", "--crash-test", "window"])),
            Some(CrashTest::Window)
        );
        assert_eq!(crash_test_from(&args(&["--crash-test", "other"])), None);
        assert_eq!(crash_test_from(&args(&["--crash-test"])), None);
        assert_eq!(crash_test_from(&args(&["panic"])), None);
        set_crash_test(Some(CrashTest::Window));
        assert_eq!(crash_test(), Some(CrashTest::Window));
        set_crash_test(None);
        assert_eq!(crash_test(), None);
    }

    #[test]
    fn explorer_comes_from_the_system_root() {
        assert_eq!(
            explorer_exe(Some(r"D:\Windows".into())),
            PathBuf::from(r"D:\Windows").join("explorer.exe")
        );
        assert_eq!(
            explorer_exe(None),
            PathBuf::from(r"C:\Windows").join("explorer.exe")
        );
        assert_eq!(
            explorer_exe(Some("Windows".into())),
            PathBuf::from(r"C:\Windows").join("explorer.exe")
        );
    }
}
