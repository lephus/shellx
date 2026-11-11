# ShellX for Windows, Usable: Part 3b, Windows-Only Details

Companion to `docs/superpowers/plans/2026-11-12-shellx-windows-usable-3-wiring-and-windows-only.md` (the plan). It holds the exact texts that Part B's tasks point to: the three GPUI patches, the native crash filter, the start-up order, the diagnostics probes and the installer and script lines. Rulings, tasks, tests and commands are in the plan; numbers like "Ruling 10" refer to it. GPUI paths are relative to `windows/vendor/gpui-0.2.2/`; line numbers are the unpatched crate's (each patch's notice line shifts its file by one).

## 1. Patch (a): `src/platform/windows/events.rs` (Task B1)

New line 1:
```rust
// Modified by ShellX: a VK_PACKET key-up is no longer translated as a second key-down, which repeated or garbled characters typed by Unikey and EVKey. See windows/vendor/README.md.
```

Upstream (`events.rs:356-360`, `:409-415`):
```rust
    fn handle_syskeyup_msg(&self, handle: HWND, wparam: WPARAM, lparam: LPARAM) -> Option<isize> {
        let mut lock = self.state.borrow_mut();
        let input = handle_key_event(handle, wparam, lparam, &mut lock, |keystroke| {
            PlatformInput::KeyUp(KeyUpEvent { keystroke })
        })?;
```
```rust
    fn handle_keyup_msg(&self, handle: HWND, wparam: WPARAM, lparam: LPARAM) -> Option<isize> {
        let mut lock = self.state.borrow_mut();
        let Some(input) = handle_key_event(handle, wparam, lparam, &mut lock, |keystroke| {
            PlatformInput::KeyUp(KeyUpEvent { keystroke })
        }) else {
            return Some(1);
        };
```
Replacement: the first statement of `handle_syskeyup_msg` becomes
```rust
        // ShellX: a VK_PACKET key-up carries no new character; handle_key_event would translate it
        // again as a forged WM_KEYDOWN. Same result as before for this key, without TranslateMessage.
        if VIRTUAL_KEY(wparam.loword()) == VK_PACKET {
            return None;
        }
```
and the first statement of `handle_keyup_msg` becomes the same block with `return Some(1);`. `VIRTUAL_KEY`, `VK_PACKET` and `loword()` are already in scope (`handle_key_event`, `events.rs:1308`, `:1326`).

Why it cannot make anything worse for people who never hit the bug:
- Any key other than `VK_PACKET`: the new `if` is false; both functions run exactly as before.
- A `VK_PACKET` key-up: before, `handle_key_event`'s `VK_PACKET` arm (`events.rs:1326-1329`) called `translate_message` and returned `None`, so `handle_keyup_msg` returned `Some(1)` (its `else`) and `handle_syskeyup_msg` returned `None` (its `?`). The patch returns the same values without the call. No `PlatformInput` was ever dispatched for `VK_PACKET`, so the app sees nothing new.
- Key-downs are untouched: `handle_keydown_msg` and `handle_syskeydown_msg` still translate a `VK_PACKET` key-down once, and that is what posts the character's `WM_CHAR`.
- A standard message loop passes key-ups to `TranslateMessage` too, which posts characters only for key-down messages (`WM_KEYDOWN` → `WM_CHAR`/`WM_DEADCHAR`, `WM_SYSKEYDOWN` → `WM_SYSCHAR`/`WM_SYSDEADCHAR`; TranslateMessage documentation). The forged `WM_KEYDOWN` (`translate_message`, `events.rs:1285-1297`) is what made a key-up produce one; after the patch a key-up behaves as in any Win32 program.
- Risk (inferred): a tool that injects only key-ups for `VK_PACKET` would lose its characters. `SendInput` with `KEYEVENTF_UNICODE` is documented and used as down/up pairs. Hands-on steps 4 and 5 decide.

Not via lParam's transition bit (bit 31): for `VK_PACKET` the high word of lParam may hold the character (R2 F1), so the bit cannot tell down from up for characters at U+8000 and above, and a check on it would drop key-downs of CJK text (Ruling 32).

README row:
`| (a) | src/platform/windows/events.rs | A VK_PACKET key-up (SendInput KEYEVENTF_UNICODE: Unikey, EVKey, OpenKey, password managers) went through translate_message, which forges a WM_KEYDOWN, so the character came twice or with a stray one (R2 F1). Both key-up handlers return early for VK_PACKET with the value they returned before, without TranslateMessage. | vendor(windows): gpui patch (a) |`

Upstream: only gpui 0.2.2 is on this machine (the cargo registry has no later gpui and no Zed checkout), so no later upstream fix could be compared.

## 2. The native crash filter and its watchdog (Task B5)

Install (`crash_native::install(ctx)`, Windows only, once, in GUI and `--diagnose` modes, after every environment change: §5 step 9g). Allocation is allowed here.
1. `create_dir_all(ctx.logs_dir)`; build `path: Vec<u16>` = `ctx.logs_dir/crash-native.<compact_utc(now)>.<pid>.txt`, UTF-16, NUL-terminated, and `header: Vec<u8>` = the first seven report lines below, each through `redact` (UTF-8). A failure here: log it and return without installing (no filter is better than a filter with half its data).
2. `go = CreateEventW(null, TRUE, FALSE, null)`, `done = CreateEventW(null, TRUE, FALSE, null)` (manual reset, not signalled).
3. Watchdog, only when both events exist: `std::thread::Builder::new().name("crash-reporter-watch".into())` with its own `cmd: Vec<u16>` = `reporter_command_line(ctx.exe, "--report-crash", path)`, UTF-16, NUL-terminated (`CreateProcessW` may write into `lpCommandLine`, so the thread owns a writable copy). Body: `WaitForSingleObject(go, INFINITE)`; `CreateProcessW(null, cmd.as_mut_ptr(), null, null, FALSE, 0, null, null, &si, &mut pi)` with `si: STARTUPINFOW` zeroed and `cb = size_of::<STARTUPINFOW>()`; on success `CloseHandle(pi.hThread)`, `CloseHandle(pi.hProcess)`; `SetEvent(done)`.
4. Store `NativeTargets { path, header, go, done }` in `static NATIVE: OnceLock<NativeTargets>`, the handles as `usize`; `go = 0` when step 2 or 3 failed (the filter then writes the file only).
5. `SetUnhandledExceptionFilter(Some(filter))`. The previous filter is the system default, which `EXCEPTION_CONTINUE_SEARCH` falls through to; it is not chained.

The filter, `unsafe extern "system" fn filter(info: *const EXCEPTION_POINTERS) -> i32`. Nothing in it allocates or can panic (stack arrays, `OnceLock::get`, `wrapping_sub`, the model's checked writer):
1. `if IN_FILTER.swap(true, Ordering::SeqCst) { return EXCEPTION_CONTINUE_SEARCH; }` (a second exception while reporting).
2. `let Some(t) = NATIVE.get() else { return EXCEPTION_CONTINUE_SEARCH };`
3. `info` and `(*info).ExceptionRecord` non-null → `code = ExceptionCode as u32`, `address = ExceptionAddress as u64`; else 0.
4. `GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS | GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT, address as PCWSTR, &mut hmod)` ≠ 0 → `offset = address.wrapping_sub(hmod as u64)` and `GetModuleFileNameW(hmod, name.as_mut_ptr(), 260)` into `name: [u16; 260]` (0 → empty). FROM_ADDRESS: "lpModuleName is an address in the module"; UNCHANGED_REFCOUNT: no `FreeLibrary` owed (GetModuleHandleExW documentation).
5. `GetSystemTime(&mut st)` → `[wYear, wMonth, wDay, wHour, wMinute, wSecond]`; `GetCurrentThreadId()`.
6. `let mut buf = [0u8; 1536]; let len = write_native_report(&mut buf, &facts);`
7. `h = CreateFileW(t.path.as_ptr(), GENERIC_WRITE, FILE_SHARE_READ, null, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, null)`; `h != INVALID_HANDLE_VALUE` → `WriteFile(h, buf.as_ptr(), len as u32, &mut written, null)`, `FlushFileBuffers(h)`, `CloseHandle(h)`. A failure skips the rest of this step; the dialog still appears.
8. `t.go != 0` → `SetEvent(go)`, `WaitForSingleObject(done, 5000)`. Process creation runs on the watchdog's stack, so a stack overflow (the filter has only the guaranteed reserve) can still report.
9. `return EXCEPTION_CONTINUE_SEARCH` ("Proceed with normal execution of UnhandledExceptionFilter": Windows Error Reporting still records the crash in Event Viewer).

What reaches it: access violations (`0xC0000005`), illegal instructions (`0xC000001D`, R1 F8), stack overflows after Rust's own message. A Rust panic does not: `abort` uses `__fastfail`, which skips every handler, and the panic hook has already reported it.

Report text (`write_native_report`; the first seven lines are `header`, the formatter writes the rest; hex in capitals, addresses 16 digits, codes 8):
```text
ShellX crash report
kind: native exception
version: 1.7.0
commit: 5dd1e2dc6a…(40 hex) | unknown
build: release | release test
windows: 10.0.26100
exe base: 0x00007FF6A0000000
time: 2026-11-12 08:15:30 UTC
exception: 0xC0000005
address: 0x00007FF6A1B2C3D4
module: C:\Users\Phú Lê\AppData\Local\Programs\ShellX Native\shellx-desktop.exe +0x1B2C3D4
thread: 4242
```
`module: unknown` when the name is empty; ` +0x…` left out when the offset is unknown; UTF-16 decoded with `char::decode_utf16` (lone surrogates → U+FFFD) and encoded into a 4-byte scratch buffer; output truncated at the buffer's end, never past it.

Features (windows-sys 0.61.2): `Win32_System_Diagnostics_Debug` + `Win32_System_Kernel` (`SetUnhandledExceptionFilter`, `EXCEPTION_POINTERS`), `Win32_System_LibraryLoader`, `Win32_Storage_FileSystem` + `Win32_Security` (`CreateFileW`, `CreateEventW`, `CreateProcessW`), `Win32_System_Threading`, `Win32_System_SystemInformation` (`GetSystemTime`).

## 3. Patch (b): `src/platform/windows/vsync.rs` (Task B7)

New line 1:
```rust
// Modified by ShellX: the vsync thread no longer divides by zero when DWM reports a refresh period under 1 ms. See windows/vendor/README.md.
```

Upstream (`vsync.rs:64-81`):
```rust
    let interval = retrieve_duration(timing_info.qpcRefreshPeriod, *QPC_TICKS_PER_SECOND);
    // Check for interval values that are impossibly low. A 29 microsecond
    // interval was seen (from a qpcRefreshPeriod of 60).
    if interval < VSYNC_INTERVAL_THRESHOLD {
        Ok(retrieve_duration(
            timing_info.rateRefresh.uiDenominator as u64,
            timing_info.rateRefresh.uiNumerator as u64,
        ))
    } else {
        Ok(interval)
    }
}

#[inline]
fn retrieve_duration(counts: u64, ticks_per_second: u64) -> Duration {
    let ticks_per_microsecond = ticks_per_second / 1_000_000;
    Duration::from_micros(counts / ticks_per_microsecond)
}
```
Replacement:
```rust
    let interval = retrieve_duration(timing_info.qpcRefreshPeriod, *QPC_TICKS_PER_SECOND);
    // Check for interval values that are impossibly low. A 29 microsecond
    // interval was seen (from a qpcRefreshPeriod of 60).
    if interval < VSYNC_INTERVAL_THRESHOLD {
        Ok(refresh_rate_interval(
            timing_info.rateRefresh.uiNumerator,
            timing_info.rateRefresh.uiDenominator,
        ))
    } else {
        Ok(interval)
    }
}

/// ShellX: one refresh period from DWM's rate in Hz (numerator / denominator). Passing the rate
/// to `retrieve_duration` divided by `rate / 1_000_000`, which is 0 for every real rate.
fn refresh_rate_interval(numerator: u32, denominator: u32) -> Duration {
    if numerator == 0 || denominator == 0 {
        return DEFAULT_VSYNC_INTERVAL;
    }
    let interval = Duration::from_secs_f64(f64::from(denominator) / f64::from(numerator));
    if interval < VSYNC_INTERVAL_THRESHOLD || interval > Duration::from_secs(1) {
        DEFAULT_VSYNC_INTERVAL
    } else {
        interval
    }
}

#[inline]
fn retrieve_duration(counts: u64, ticks_per_second: u64) -> Duration {
    let ticks_per_microsecond = ticks_per_second / 1_000_000;
    if ticks_per_microsecond == 0 {
        // ShellX: a QPC frequency under 1 MHz; 0 sends the caller to the refresh rate.
        return Duration::ZERO;
    }
    Duration::from_micros(counts / ticks_per_microsecond)
}
```

Why it cannot make anything worse: with a QPC frequency of 1 MHz or more and a `qpcRefreshPeriod` of at least 1 ms (every PC that runs the window today), `retrieve_duration` computes the same number and the fallback is never reached. The fallback was reachable only by panicking (`counts / 0` in the "VSyncProvider" thread, `platform.rs:246-271`), which killed the only thread that calls `RedrawWindow` (R1 F6); now it yields the rate's period, or 16.666 ms. `from_secs_f64` cannot panic here: both values are positive `u32`, so the quotient is finite and below 2^32 s. The interval is used only as the sleep when `DwmFlush` returns early (`vsync.rs:40-55`).

README row:
`| (b) | src/platform/windows/vsync.rs | When DWM reported a refresh period under 1 ms, the fallback passed the refresh rate to retrieve_duration, which divided by rate / 1 000 000 = 0; the VSyncProvider thread panicked and the window stopped repainting (R1 F6). The fallback now computes denominator / numerator seconds (default 16.666 ms when unusable), and a QPC frequency under 1 MHz no longer divides by zero. | vendor(windows): gpui patch (b) |`

## 4. Patch (c): `src/platform/windows/directx_renderer.rs` (Task B8)

New line 1:
```rust
// Modified by ShellX: a failed resize or device-lost recovery no longer leaves a dropped render target or releases objects twice. See windows/vendor/README.md.
```

What fails today (R1 F5, read in this file): `resize` (`:318-358`) records the new size, releases `render_target` through `ManuallyDrop::drop` and takes `render_target_view[0]` with `unwrap()` before `ResizeBuffers(...)?`; when that fails (device removed) the next `draw` panics in `pre_draw` (`:190` `.as_ref().unwrap()`), the next resize to another size panics on `.take().unwrap()` (`:330`), and the device-lost path releases `render_target` a second time (`DirectXResources::drop`, `:1008-1013`). `handle_device_lost_impl` (`:226-284`) releases `resources` and `devices`, then can fail at any `?`; the retry (`try_to_recover_from_device_lost`, five attempts) releases them again, derives `disable_direct_composition` from the `direct_composition` the first attempt already took (`:227`), and `Drop for DirectXRenderer` (`:997-1006`) releases them once more.

Changes (each is the minimum for one of those faults):
1. `struct DirectXRenderer`: add after `font_info`
   ```rust
       /// ShellX: fixed at creation (`handle_device_lost_impl` used to derive it from a field it had taken).
       disable_direct_composition: bool,
       /// ShellX: `Some((width, height))` while the device-lost path has released the old devices and
       /// resources and not yet created new ones.
       released: Option<(u32, u32)>,
   ```
   and set `disable_direct_composition, released: None,` in `DirectXRenderer::new`'s struct literal.
2. `struct DirectXResources`: `render_target: ManuallyDrop<ID3D11Texture2D>` → `render_target: Option<ID3D11Texture2D>`. `create_render_target_and_its_view` and `create_resources` return `Option<ID3D11Texture2D>` in that position (`ManuallyDrop::new(render_target)` → `Some(render_target)`). `impl Drop for DirectXResources` body → `drop(self.render_target.take());` (still released before the swap chain, as before).
3. `pre_draw`: `self.resources.render_target_view[0].as_ref().unwrap()` → `self.resources.render_target_view[0].as_ref().context("no render target to draw into")?`.
4. `draw`: first statements
   ```rust
        if self.released.is_some() {
            anyhow::bail!("the GPU device was lost; drawing resumes once it is recreated");
        }
        if self.resources.render_target_view[0].is_none() {
            // ShellX: the last resize failed; try it again at the size it recorded.
            let (width, height) = (self.resources.width, self.resources.height);
            self.resize(size(DevicePixels(width as i32), DevicePixels(height as i32)))?;
        }
   ```
5. `resize`: after computing `width`/`height`:
   ```rust
        if let Some(size) = self.released.as_mut() {
            *size = (width, height);
            return Ok(());
        }
        if self.resources.width == width
            && self.resources.height == height
            && self.resources.render_target_view[0].is_some()
        {
            return Ok(());
        }
   ```
   (the old early return lacked the `is_some()` term), and the two releases become `drop(self.resources.render_target.take());` and `drop(self.resources.render_target_view[0].take());` (no `unsafe`, no `unwrap`). The rest is unchanged.
6. `handle_device_lost_impl`: `let disable_direct_composition = self.disable_direct_composition;` replaces `:227`; the existing release block (`unsafe { … ManuallyDrop::drop(&mut self.resources); … ManuallyDrop::drop(&mut self.devices); }`) runs only when `self.released` is `None`, preceded by `let size = (self.resources.width, self.resources.height);` and followed by `self.released = Some(size);`; `DirectXResources::new` takes that `(width, height)` instead of reading the released `self.resources`; after the existing assignments `self.released = None;`.
7. `gpu_specs`: first statement `if self.released.is_some() { anyhow::bail!("the GPU device was lost"); }`.
8. `impl Drop for DirectXRenderer`: the two `ManuallyDrop::drop` calls run only `if self.released.is_none()`.

Why it cannot make anything worse for a PC whose device is never lost: `released` stays `None` and `render_target_view[0]` stays `Some`, so every new branch is a false test; the render target is released once at each resize and once at drop, in the same order as before; `disable_direct_composition` holds the value the old code derived at the first call. Behaviour changes only after a failed resize (frames are skipped and the resize is retried instead of a panic inside the window procedure) or during device-lost recovery (old objects released once; retries and the final drop skip them). Recovery that never succeeds now leaves a window that skips frames (and logs, collapsed by the log's count line) instead of a use-after-free.

README row:
`| (c) | src/platform/windows/directx_renderer.rs | After DXGI_ERROR_DEVICE_REMOVED during a resize the render target was left dropped: the next paint panicked inside the window procedure (abort), a later resize panicked, and device-lost recovery released the render target and, on retries and at drop, the devices and resources a second time (R1 F5). The render target is an Option, a failed resize is retried at the next draw, recovery releases the old objects once and remembers the composition mode. | vendor(windows): gpui patch (c) |`

## 5. Start-up order (Tasks B3, B4, B5, B6, B9)

`main()`:
1. Read the arguments.
2. `--report-crash <file>` or `--report-window <file>` → `exit(crash::run_reporter(kind, file))`. Nothing else runs: no hook, no log, no mutex, no marker, no filter.
3. Any of `--version`, `--smoke`, `--smoke-ui-assets`, `--smoke-panes`, `--diagnose` → `console::attach_parent_console()` (Windows; Ruling 29).
4. `let ctx = CrashContext::this_process();` (records the main thread id, exe path and base, version, commit, build, Windows version).
5. `crash::install_panic_hook(ctx.clone(), mode)`: `Dialog` for the GUI and `--diagnose`, `FileOnly` otherwise.
6. `--crash-test panic|native|window` → `crash::set_crash_test(..)`.
7. `--version`, `--smoke-ui-assets`, `--smoke-panes`, `--smoke`: as today (`--version` prints with `writeln!`, error ignored).
8. `--diagnose [--no-open]` → `crash_native::install(&ctx)` (Windows) → `exit(diagnose_run::run(!no_open))`.
9. The window:
   a. `logger::install(&paths::logs_dir())`; log `"<about_version()> starting on Windows <ctx.windows>"`.
   b. `let other = startup::acquire_app_mutex();` (Windows; false elsewhere).
   c. `env_forced` = `GPUI_DISABLE_DIRECT_COMPOSITION` is `"1"` or `"true"` (GPUI's own test, `platform.rs:138-139`); `is_retry` = `SHELLX_RENDER_RETRY` is `"1"`.
   d. `unsafe { std::env::remove_var("SHELLX_RENDER_RETRY") }`. SAFETY: no other thread exists yet (the hook, the logger and the mutex start none; GPUI has not started).
   e. `let (plan, remembered) = startup::plan_gui_start(paths, env_forced, is_retry, other);` (logs the decision).
   f. `plan.mode == Compatible && !env_forced` → `unsafe { std::env::set_var("GPUI_DISABLE_DIRECT_COMPOSITION", "1") }`. Same SAFETY.
   g. `crash_native::install(&ctx)` (Windows): its watchdog is the first thread, started after every environment change.
   h. `ui::run()`.

`ui/app.rs`:
- After `open_window` returns `Ok(window)`: `window.update(cx, |_, window, _| window.on_next_frame(|window, _| window.on_next_frame(|_, _| startup::first_frame_drawn())))` (Ruling 6); `crash_test()` `Panic` → a foreground task (`cx.spawn`) that panics; `Native` → a foreground task doing `unsafe { std::ptr::null_mut::<u8>().write_volatile(1) }`.
- `crash_test() == Some(Window)` and not a retry → act as if `open_window` returned `Err(anyhow!("crash test: the window was not opened"))` without calling it.
- `Err(e)` → `startup::window_failed(&e)` (never returns): log `{e:#}` (redacted by the logger); remove the marker this start wrote; `on_open_failed(&plan)`: `RelaunchCompatible` → `Command::new(current_exe).args(args_os().skip(1)).env("SHELLX_RENDER_RETRY", "1").env("GPUI_DISABLE_DIRECT_COMPOSITION", "1").spawn()`, `Ok` → `exit(0)`, `Err` → as `Report`; `Report` → `crash::write_window_failure(&ctx, &e)` (`start-failed.<utc>.<pid>.txt`: the panic report's header lines, `render mode: <mode> (<reason>)`, `error:` and the chain, each line redacted), `crash::start_reporter(&ctx, DialogKind::WindowFailed, &file)`, `exit(1)`.
- `on_window_closed`: when no window is left, `startup::orderly_quit()` (removes the marker) then `cx.quit()`.

`startup::first_frame_drawn()`: remove the marker if this start wrote it; `remember_after_first_frame(&plan, remembered)` = `Some(m)` → write `render.json` (temp file then rename); log `first frame drawn in <mode> display mode`. Every file error is logged and ignored.

## 6. `--diagnose` probes (Task B9)

Each probe fills one `DiagnosticsReport` field (foundations `diagnose.rs`), runs inside `crash::expect_caught(|| catch_unwind(..))`, and on failure writes `failed: <reason>` or `unknown` in its own field; `format_report` redacts every line. Values are written with spaces or `:` between parts (the redactor's known limits: a long joined name or an API constant name would read as a token; this report never prints constant names).

| Field | Source | Failure |
| --- | --- | --- |
| `app_version`, `commit`, `build_kind` | `build_info` (`build_kind`: `release` or `debug`, plus ` <label>`) | `unknown` |
| `created_utc` | `log_file::utc_timestamp(now)` | — |
| `windows_version` | `os_info::os_version()` (`RtlGetVersion`, Ruling 28) + `DisplayVersion` and `UBR` from `HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion` (winreg): `10.0.26100.2314 (24H2)` | the parts that were read |
| `cpu`, `cpu_features` | `HKLM\HARDWARE\DESCRIPTION\System\CentralProcessor\0` `ProcessorNameString`; `is_x86_feature_detected!` for `sse4.2`, `avx`, `avx2`, `fma`, `bmi2`, `avx512f` (listed when present; R1 F8) | `unknown` |
| `displays` | `EnumDisplayMonitors(null, null, Some(cb), &mut list as *mut _ as LPARAM)`; per monitor `GetMonitorInfoW` with `MONITORINFOEXW` (`szDevice`, `rcMonitor`, `rcWork`, `dwFlags & MONITORINFOF_PRIMARY`) and `GetDpiForMonitor(MDT_EFFECTIVE_DPI)` → `scale_percent = dpi * 100 / 96` | `displays: none` |
| `first_window` | `os_info::first_window_placement(os_info::primary_work_area())`: `1200x672 at 40,0, maximized no` | — |
| `gpus` | windows crate: `CreateDXGIFactory1::<IDXGIFactory1>()`; `EnumAdapters1(i)` until `DXGI_ERROR_NOT_FOUND`; `GetDesc1` (`Description`, `Flags & DXGI_ADAPTER_FLAG_SOFTWARE`); driver = `CheckInterfaceSupport(&IDXGIDevice::IID)` split into four 16-bit parts (GPUI's formula, `directx_renderer.rs:1748-1757`); feature level and usability = GPUI's own probe (`directx_devices.rs:155-200`): `D3D11CreateDevice(adapter, D3D_DRIVER_TYPE_UNKNOWN, HMODULE::default(), D3D11_CREATE_DEVICE_BGRA_SUPPORT, Some(&[11_1, 11_0, 10_1]), D3D11_SDK_VERSION, Some(&mut device), Some(&mut level), None)` then `CheckFeatureSupport(D3D11_FEATURE_D3D10_X_HARDWARE_OPTIONS)` → `11.1, structured buffers yes` or `not usable: <reason>`; the first usable adapter is marked `GPUI would use this one` | per adapter `unknown` |
| `chosen_gpu` | `chosen_gpu_from_log(log lines)` (Ruling 36) + ` (last run's log)` | `unknown (no log)` |
| `render_mode` | `render.json`, whether `starting.json` exists, and the last `render mode:` and `first frame drawn` log lines | `unknown` |
| `dwm_timing` | `DwmGetCompositionTimingInfo(null, &mut DWM_TIMING_INFO { cbSize, .. })` (GPUI passes a null window too) + `QueryPerformanceFrequency` → `vsync_check`: `period 16.67 ms (qpc 166667 at 10000000 Hz, rate 60/1); unpatched gpui 0.2.2 would divide by zero: no` | `unknown: <hresult>` |
| `keyboard_layouts` | `GetKeyboardLayoutList(0, null)` → `n`; `GetKeyboardLayoutList(n, buf)`; per HKL `LCIDToLocaleName(lang_id, buf, 85, 0)`: `vi-VN 0x042A042A` | `none` |
| `input_methods` | winreg `HKCU\Control Panel\International\User Profile`: each language subkey's value names (`vi: 042A:0000042A, 042A:{…}{…}`) and `InputMethodOverride` | `none` |
| `typing_tools_running` | `CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0)`, `Process32FirstW`/`Process32NextW` `szExeFile`, then `typing_tools` (only matches are written; no other process name) | `none` |
| `shells_found`, `shell_chosen` | `local_pty::settings::shells().refresh_now()`: `<label>: <program>` per shell; the choice and the plan's first program | — |
| `shell_checks` | `smoke::shell_checks(&default_shell(), 10 s)`: start, first output, then `probe_script` steps (PowerShell: `Write-Output ('shellx-ok-' + (6*7))` → `shellx-ok-42`, `Write-Output 'tiếng Việt'` → twice, resize to 120 columns → `cols-120`; Command Prompt: `set /a 6*7` → `42`, `echo tiếng Việt` → twice; others: start and first output only), each with its time | per check `failed` |
| `state_dir` | `paths::core_dir()`: write, read and delete `diag.<pid>.tmp`, timed | `failed: <io error>` |
| `sign_in` | `core_api::session_info(core)` on `ConfiguredCore::this_pc(MachineFacts::this_pc())`: `signed in with <auth_method>`; `not_logged_in` → `signed out`; other → `unknown (<code>)`. `SessionInfo.email` is never read | — |
| `relay` | `core_api::version_check(core)`, timed: ok with the status, or failed with the code (spec §4.7: the existing call, no new RPC) | `failed` |
| `crash_files` | names in `logs_dir()` starting with `crash.`, `crash-native.`, `start-failed.`, newest first by the time part of the name, at most 20 | `none` |
| `log_tail` | the last 200 lines of `shellx.log`, preceded by the end of `shellx.log.1` when shorter | `none` |

Output: `logs_dir()/diagnostics.<compact_utc>.txt`; `writeln!(stdout, "Diagnostics report: {path}")` (error ignored); unless `--no-open`, `explorer.exe /select,"<path>"` (`raw_arg`). `spawn_report_process()` = `Command::new(current_exe()?).arg("--diagnose").spawn()`.

Features: windows `Win32_Graphics_Dxgi`, `Win32_Graphics_Dxgi_Common`, `Win32_Graphics_Direct3D`, `Win32_Graphics_Direct3D11` (all already enabled by GPUI, so nothing new compiles); windows-sys `Win32_System_Console`, `Wdk_System_SystemServices` + `Win32_System_SystemInformation` (`RtlGetVersion`), `Win32_Graphics_Gdi` + `Win32_UI_HiDpi`, `Win32_Graphics_Dwm`, `Win32_System_Performance`, `Win32_System_Diagnostics_ToolHelp`, `Win32_UI_Input_KeyboardAndMouse`, `Win32_Globalization`.

## 7. Version resource, installer and build scripts (Task B10)

`windows/shellx-app/src/exe_resource.rs` (only `//` and `///` comments: `build.rs` `include!`s it, where an inner `//!` comment is not allowed). `version_resource("1.7.0")` returns exactly:
```text
1 VERSIONINFO
FILEVERSION 1,7,0,0
PRODUCTVERSION 1,7,0,0
FILEFLAGSMASK 0x3F
FILEFLAGS 0x0
FILEOS 0x40004
FILETYPE 0x1
FILESUBTYPE 0x0
BEGIN
  BLOCK "StringFileInfo"
  BEGIN
    BLOCK "040904B0"
    BEGIN
      VALUE "CompanyName", "ShellX"
      VALUE "FileDescription", "ShellX"
      VALUE "FileVersion", "1.7.0"
      VALUE "InternalName", "shellx-desktop"
      VALUE "OriginalFilename", "shellx-desktop.exe"
      VALUE "ProductName", "ShellX"
      VALUE "ProductVersion", "1.7.0"
    END
  END
  BLOCK "VarFileInfo"
  BEGIN
    VALUE "Translation", 0x409, 1200
  END
END
```
(`0x40004` = `VOS_NT_WINDOWS32`, `0x1` = `VFT_APP`; numbers instead of `winver.h` names, so no SDK header is needed.) `build.rs`, inside the existing `target_os == "windows"` branch and before `embed_resource::compile`: write that text to `$OUT_DIR/shellx-version.rc` (a version that is not `x.y.z` fails the build with `the workspace version must be x.y.z`); add `cargo:rerun-if-changed=src/exe_resource.rs`. `resources/shellx.rc` gains the line `#include "shellx-version.rc"`. `main.rs`: `#[cfg(test)] mod exe_resource;`.

`windows/installer/shellx-native.iss`:
- `[Setup]`: add `AppMutex=ShellXNative-D322DA97-3B0D-49C7-BDB2-8EBFADBA1004`, `VersionInfoCompany=ShellX`, `VersionInfoDescription=ShellX Setup`, `VersionInfoProductName=ShellX`; replace `OutputBaseFilename=ShellX-Setup-{#AppVersion}` with
  ```
  #ifdef FileLabel
  OutputBaseFilename=ShellX-Setup-{#AppVersion}-{#FileLabel}
  #else
  OutputBaseFilename=ShellX-Setup-{#AppVersion}
  #endif
  ```
  and the header comment's `/D…` list gains `[/DFileLabel=<label>-<commit10>]`.
- New section after `[Languages]`:
  ```
  [CustomMessages]
  vietnamese.DiagnoseShortcut=ShellX – Chẩn đoán
  english.DiagnoseShortcut=ShellX – Diagnostics
  ```
- `[Icons]` gains `Name: "{autoprograms}\{cm:DiagnoseShortcut}"; Filename: "{app}\{#AppExeName}"; Parameters: "--diagnose"`.
Inno checks that the named mutex exists and then shows `SetupAppRunningError` (already in `Vietnamese.isl:62`), so it asks while any ShellX window process keeps its handle open (the app never owns the mutex, `bInitialOwner` is FALSE); the uninstaller removes the new shortcut with the others. Only builds that create the mutex benefit: updating from 1.7.0 still relies on `CloseApplications`.

`windows/cross/build-in-container.sh` (after the version is read):
```bash
# libghostty-vt for the baseline x86-64 CPU on every build (R1 F8, R3 M2).
export CMUX_GHOSTTY_VT_ZIG_CPU=baseline
label="${SHELLX_BUILD_LABEL:-}"
file_label=""
if [[ -n "$label" ]]; then
  [[ "$label" =~ ^[a-z][a-z0-9]{0,9}$ ]] || { echo "SHELLX_BUILD_LABEL must be a lower-case letter then up to 9 letters or digits: '$label'" >&2; exit 1; }
  export SHELLX_BUILD_LABEL="$label"
  file_label="$label-${CMUX_TUI_BUILD_COMMIT:0:10}"
fi
setup_name="ShellX-Setup-$version${file_label:+-$file_label}.exe"
```
ISCC gains `${file_label:+"/DFileLabel=$file_label"}`; every later `ShellX-Setup-$version.exe` becomes `$setup_name`. `scripts/shellx/release/build-windows-cross.sh`: validate `SHELLX_BUILD_LABEL` the same way, pass `-e SHELLX_BUILD_LABEL=$label` to the build `docker run` when set, compute the same `setup_name` from `commit`, and use it in the remote `test -f`, the download, the checksum lines and the final `Built …` line; the header documents `SHELLX_BUILD_LABEL` and the resulting file name.

`.github/workflows/shellx-windows.yml`, job `app`: `env` gains `CMUX_GHOSTTY_VT_ZIG_CPU: baseline`; a step after "Version flag": `"./$APP_EXE" --diagnose --no-open` followed by `ls "$LOCALAPPDATA/ShellX/native/logs"/diagnostics.*.txt` (spec §5.4; informational until Actions returns).
