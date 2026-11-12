//! Crashes that are not panics (access violations, illegal instructions): the unhandled-
//! exception filter writes a minimal crash file and starts the same reporter dialog (spec
//! §4.2, Ruling 10, plan 3b §2). Windows only.
//!
//! `install` prepares everything at start-up, when allocating is allowed: the file's UTF-16
//! path, the report's header bytes, two events and a watchdog thread that owns the
//! reporter's command line. The filter itself allocates nothing, takes no lock and cannot
//! panic: stack buffers, `OnceLock::get`, the model's fixed-buffer formatter, `CreateFileW` /
//! `WriteFile` / `FlushFileBuffers` / `CloseHandle`, `SetEvent`, a wait of at most 5 s, then
//! `EXCEPTION_CONTINUE_SEARCH`, so Windows Error Reporting still records the crash. The
//! Win32 calls may use the process heap or the loader lock inside Windows (`CreateFileW`
//! converts the path; `GetModuleHandleExW`/`GetModuleFileNameW` take the loader lock): a
//! fault while another thread holds one of those can stop the filter before the file is
//! written (accepted, plan review M-8).

use std::ffi::OsStr;
use std::os::windows::ffi::OsStrExt;
use std::path::Path;
use std::ptr::{null, null_mut};
use std::sync::OnceLock;
use std::sync::atomic::{AtomicBool, Ordering};
use std::time::{SystemTime, UNIX_EPOCH};

use shellx_model::crash_report::{self, CrashFileKind, DialogKind, NativeFacts};
use shellx_model::log_file::compact_utc;
use windows_sys::Win32::Foundation::{
    CloseHandle, GENERIC_WRITE, HANDLE, HMODULE, INVALID_HANDLE_VALUE, SYSTEMTIME, WAIT_OBJECT_0,
};
use windows_sys::Win32::Storage::FileSystem::{
    CREATE_ALWAYS, CreateFileW, FILE_ATTRIBUTE_NORMAL, FILE_SHARE_READ, FlushFileBuffers, WriteFile,
};
use windows_sys::Win32::System::Diagnostics::Debug::{
    EXCEPTION_CONTINUE_SEARCH, EXCEPTION_POINTERS, SetUnhandledExceptionFilter,
};
use windows_sys::Win32::System::LibraryLoader::{
    GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS, GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
    GetModuleFileNameW, GetModuleHandleExW,
};
use windows_sys::Win32::System::SystemInformation::GetSystemTime;
use windows_sys::Win32::System::Threading::{
    CreateEventW, CreateProcessW, GetCurrentThreadId, INFINITE, PROCESS_INFORMATION, STARTUPINFOW,
    SetEvent, WaitForSingleObject,
};

use crate::crash::{CrashContext, HookMode};

/// The report buffer on the filter's stack (the longest report fits: model test
/// `native_report_never_overruns_its_buffer`).
const REPORT_BYTES: usize = 1_536;
/// `GetModuleFileNameW`'s buffer (MAX_PATH).
const MODULE_NAME_UNITS: usize = 260;
/// How long the filter waits for the watchdog to start the reporter.
const REPORTER_WAIT_MS: u32 = 5_000;

/// What the filter needs, built at start-up. Handles are stored as `usize` (0 = none) and
/// never closed once the filter is installed.
struct NativeTargets {
    /// `<logs>\crash-native.<process start>.<pid>.txt`, UTF-16, NUL-terminated.
    path: Vec<u16>,
    /// `native_report_header`'s bytes.
    header: Vec<u8>,
    /// Manual-reset event the filter sets to wake the watchdog; 0 = no reporter.
    go: usize,
    /// Manual-reset event the watchdog sets once it tried to start the reporter.
    done: usize,
}

static NATIVE: OnceLock<NativeTargets> = OnceLock::new();
static IN_FILTER: AtomicBool = AtomicBool::new(false);

fn wide_nul(text: &OsStr) -> Vec<u16> {
    text.encode_wide().chain(std::iter::once(0)).collect()
}

fn close(handle: HANDLE) {
    if !handle.is_null() {
        // SAFETY: a handle this module created and nothing else uses.
        unsafe { CloseHandle(handle) };
    }
}

/// Installs the filter once (GUI and `--diagnose`). `HookMode::FileOnly` (`--diagnose
/// --no-open`) creates no watchdog: the filter then writes the file and starts no reporter
/// (plan review M-13). A failure while preparing is logged and nothing is installed.
pub fn install(ctx: &CrashContext, mode: HookMode) {
    if NATIVE.get().is_some() {
        return;
    }
    if let Err(error) = std::fs::create_dir_all(&ctx.logs_dir) {
        log::warn!("crash filter not installed: the logs folder cannot be created ({error})");
        return;
    }
    let started = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_or(0, |d| d.as_secs());
    // The name's time is the process start; the file's `time:` line is the crash's (M-9).
    let name = crash_report::crash_file_name(
        CrashFileKind::Native,
        &compact_utc(started),
        std::process::id(),
    );
    let file = ctx.logs_dir.join(name);
    let header = crash_report::native_report_header(
        &ctx.version,
        &ctx.commit,
        &ctx.build,
        &ctx.windows,
        ctx.exe_base,
    )
    .into_bytes();
    let (go, done) = match mode {
        HookMode::Dialog => start_watchdog(ctx, &file),
        HookMode::FileOnly => (0, 0),
    };
    let targets = NativeTargets {
        path: wide_nul(file.as_os_str()),
        header,
        go,
        done,
    };
    if NATIVE.set(targets).is_err() {
        return;
    }
    // SAFETY: `filter` has the LPTOP_LEVEL_EXCEPTION_FILTER signature and lives as long as
    // the program. The previous filter is not chained (plan review M-8).
    unsafe { SetUnhandledExceptionFilter(Some(filter)) };
}

/// Two unsignalled manual-reset events and the watchdog thread; `(0, 0)` when any of them
/// cannot be made (the filter then writes the file only).
fn start_watchdog(ctx: &CrashContext, file: &Path) -> (usize, usize) {
    // SAFETY: null attributes and name: an unnamed, manual-reset, unsignalled event.
    let go = unsafe { CreateEventW(null(), 1, 0, null()) };
    // SAFETY: as above.
    let done = unsafe { CreateEventW(null(), 1, 0, null()) };
    if go.is_null() || done.is_null() {
        close(go);
        close(done);
        log::warn!("crash filter: no reporter for native crashes (CreateEventW failed)");
        return (0, 0);
    }
    let line = crash_report::reporter_command_line(
        &ctx.exe.to_string_lossy(),
        DialogKind::Crash.reporter_flag(),
        &file.to_string_lossy(),
    );
    // CreateProcessW may write into its command line, so the thread owns a writable copy.
    let mut command: Vec<u16> = line.encode_utf16().chain(std::iter::once(0)).collect();
    let (go_handle, done_handle) = (go as usize, done as usize);
    let watchdog = std::thread::Builder::new()
        .name("crash-reporter-watch".into())
        .spawn(move || {
            // SAFETY: the events stay open for the whole process once the filter is set.
            // Anything but the event's signal (WAIT_FAILED) must not start a crash dialog in a
            // healthy app (B-1b review m-7).
            if unsafe { WaitForSingleObject(go_handle as HANDLE, INFINITE) } != WAIT_OBJECT_0 {
                return;
            }
            let startup = STARTUPINFOW {
                cb: std::mem::size_of::<STARTUPINFOW>() as u32,
                ..Default::default()
            };
            let mut process = PROCESS_INFORMATION::default();
            // SAFETY: `command` is a writable NUL-terminated buffer this thread owns; the
            // structs are live; null application name, attributes, environment and folder;
            // no handles inherited.
            let started = unsafe {
                CreateProcessW(
                    null(),
                    command.as_mut_ptr(),
                    null(),
                    null(),
                    0,
                    0,
                    null(),
                    null(),
                    &startup,
                    &mut process,
                )
            };
            if started != 0 {
                close(process.hThread);
                close(process.hProcess);
            }
            // SAFETY: as above.
            unsafe { SetEvent(done_handle as HANDLE) };
        });
    match watchdog {
        Ok(_) => (go_handle, done_handle),
        Err(error) => {
            close(go);
            close(done);
            log::warn!("crash filter: no reporter for native crashes ({error})");
            (0, 0)
        }
    }
}

/// The exception's code and address; zeros when Windows passed no record.
fn code_and_address(info: *const EXCEPTION_POINTERS) -> (u32, u64) {
    if info.is_null() {
        return (0, 0);
    }
    // SAFETY: Windows passes the filter a valid EXCEPTION_POINTERS (checked for null above).
    let record = unsafe { (*info).ExceptionRecord };
    if record.is_null() {
        return (0, 0);
    }
    // SAFETY: a non-null ExceptionRecord points at this exception's record.
    let (code, address) = unsafe { ((*record).ExceptionCode, (*record).ExceptionAddress) };
    (code as u32, address as usize as u64)
}

/// The module that holds `address`: its file name's length in `name` (0 when unknown) and
/// the offset of `address` inside it.
fn module_of(address: u64, name: &mut [u16; MODULE_NAME_UNITS]) -> (usize, Option<u64>) {
    let mut module: HMODULE = null_mut();
    // SAFETY: with FROM_ADDRESS the "name" is an address inside the module, not read as a
    // string; UNCHANGED_REFCOUNT means no FreeLibrary is owed; `module` is a live out-pointer.
    let found = unsafe {
        GetModuleHandleExW(
            GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS | GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
            std::ptr::without_provenance::<u16>(address as usize),
            &mut module,
        )
    };
    if found == 0 || module.is_null() {
        return (0, None);
    }
    let offset = address.wrapping_sub(module as usize as u64);
    // SAFETY: `name` holds MODULE_NAME_UNITS units, the size passed; 0 means failure.
    let copied = unsafe { GetModuleFileNameW(module, name.as_mut_ptr(), MODULE_NAME_UNITS as u32) };
    let copied = (copied as usize).min(MODULE_NAME_UNITS);
    // A truncated name ends in a NUL inside the count: stop at the first NUL.
    let len = name
        .iter()
        .take(copied)
        .position(|&unit| unit == 0)
        .unwrap_or(copied);
    (len, Some(offset))
}

/// Creates (or replaces) the crash file and writes `bytes`; any failure is skipped.
fn write_report(path: &[u16], bytes: &[u8]) {
    // SAFETY: `path` is NUL-terminated (built at install); null attributes and template.
    let file = unsafe {
        CreateFileW(
            path.as_ptr(),
            GENERIC_WRITE,
            FILE_SHARE_READ,
            null(),
            CREATE_ALWAYS,
            FILE_ATTRIBUTE_NORMAL,
            null_mut(),
        )
    };
    if file == INVALID_HANDLE_VALUE || file.is_null() {
        return;
    }
    let mut written = 0u32;
    // SAFETY: `bytes` is live for the call (at most REPORT_BYTES long); synchronous write
    // (no OVERLAPPED); the handle is ours.
    unsafe {
        WriteFile(
            file,
            bytes.as_ptr(),
            bytes.len() as u32,
            &mut written,
            null_mut(),
        );
        FlushFileBuffers(file);
    }
    close(file);
}

/// The unhandled-exception filter (Ruling 10). Allocates nothing and cannot panic: atomics,
/// `OnceLock::get`, stack arrays, the model's fixed-buffer formatter and Win32 calls.
unsafe extern "system" fn filter(info: *const EXCEPTION_POINTERS) -> i32 {
    // A second exception while reporting (or on another thread) is left to Windows.
    if IN_FILTER.swap(true, Ordering::SeqCst) {
        return EXCEPTION_CONTINUE_SEARCH;
    }
    let Some(targets) = NATIVE.get() else {
        return EXCEPTION_CONTINUE_SEARCH;
    };
    let (code, address) = code_and_address(info);
    let mut name = [0u16; MODULE_NAME_UNITS];
    let (name_len, module_offset) = module_of(address, &mut name);
    let mut now = SYSTEMTIME::default();
    // SAFETY: `now` is a live SYSTEMTIME.
    unsafe { GetSystemTime(&mut now) };
    // SAFETY: no arguments, no failure.
    let thread_id = unsafe { GetCurrentThreadId() };
    let facts = NativeFacts {
        utc: [
            now.wYear,
            now.wMonth,
            now.wDay,
            now.wHour,
            now.wMinute,
            now.wSecond,
        ],
        header: targets.header.as_slice(),
        code,
        address,
        module: name.get(..name_len).unwrap_or(&[]),
        module_offset,
        thread_id,
    };
    let mut report = [0u8; REPORT_BYTES];
    let len = crash_report::write_native_report(&mut report, &facts);
    write_report(&targets.path, report.get(..len).unwrap_or(&[]));
    // The panic hook and the filter share one dialog per process: a panic that ends as an
    // unhandled exception (0xE06D7363), or a native crash after a panic's dialog, gets its
    // file but no second dialog (B-1a review §6). `claim_reporter` is one atomic swap.
    if targets.go != 0 && crate::crash::claim_reporter() {
        // SAFETY: both events were created at install and are never closed afterwards.
        // Process creation runs on the watchdog's stack, so a stack overflow can still report.
        unsafe {
            SetEvent(targets.go as HANDLE);
            WaitForSingleObject(targets.done as HANDLE, REPORTER_WAIT_MS);
        }
    }
    // "Proceed with normal execution of UnhandledExceptionFilter": WER still records it.
    EXCEPTION_CONTINUE_SEARCH
}
