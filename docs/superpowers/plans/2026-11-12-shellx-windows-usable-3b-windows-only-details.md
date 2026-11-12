# ShellX for Windows, Usable: Part 3b, Windows-Only Details

Companion to `docs/superpowers/plans/2026-11-12-shellx-windows-usable-3-wiring-and-windows-only.md` (the plan). It holds the exact texts that Part B's tasks point to: the three GPUI patches, the native crash filter, the start-up order, the diagnostics probes and the installer and script lines. Rulings, tasks, tests and commands are in the plan; numbers like "Ruling 10" refer to it. GPUI paths are relative to `windows/vendor/gpui-0.2.2/`; line numbers are the unpatched crate's (each patch's notice line shifts its file by one). The plan review's corrections (`.superpowers/sdd/2026-11-11-windows-usable/w3-plan-review.md`) are folded in and marked "(plan review I-n)" or "(plan review M-n)"; the ones not applied are listed at the end of the plan.

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
Replacement (plan review M-1: an insertion, nothing is replaced): insert before the first statement of `handle_syskeyup_msg` (`let mut lock = self.state.borrow_mut();`, which stays)
```rust
        // ShellX: a VK_PACKET key-up carries no new character; handle_key_event would translate it
        // again as a forged WM_KEYDOWN. Same result as before for this key, without TranslateMessage.
        if VIRTUAL_KEY(wparam.loword()) == VK_PACKET {
            return None;
        }
```
and insert before the first statement of `handle_keyup_msg` the same block with `return Some(1);`. `VIRTUAL_KEY`, `VK_PACKET` and `loword()` are already in scope (`handle_key_event`, `events.rs:1309` `let virtual_key = VIRTUAL_KEY(wparam.loword());`, `:1326`). The early return comes before `self.state.borrow_mut()`, so no borrow changes.

Why it cannot make anything worse for people who never hit the bug:
- Any key other than `VK_PACKET`: the new `if` is false; both functions run exactly as before.
- A `VK_PACKET` key-up: before, `handle_key_event`'s `VK_PACKET` arm (`events.rs:1326-1329`) called `translate_message` and returned `None`, so `handle_keyup_msg` returned `Some(1)` (its `else`) and `handle_syskeyup_msg` returned `None` (its `?`). The patch returns the same values without the call. No `PlatformInput` was ever dispatched for `VK_PACKET`, so the app sees nothing new.
- Key-downs are untouched: `handle_keydown_msg` and `handle_syskeydown_msg` still translate a `VK_PACKET` key-down once, and that is what posts the character's `WM_CHAR`.
- Every standard message loop passes key-ups to `TranslateMessage` too and gets one character per key press (KEYBDINPUT documentation: for `VK_PACKET`, "passing the message to TranslateMessage posts a WM_CHAR message with the Unicode character originally specified by wScan"; Notepad gets one character per `SendInput` down+up pair). GPUI's `translate_message` (`events.rs:1285-1297`) always builds a `WM_KEYDOWN`, so a forged key-down from the key-up asked for the character a second time; after the patch a key-up behaves as in any Win32 program (wording: plan review M-1).
- Risk (inferred): a tool that injects only key-ups for `VK_PACKET` would lose its characters. `SendInput` with `KEYEVENTF_UNICODE` is documented and used as down/up pairs. Hands-on steps 4 and 5 decide.

Not via lParam's transition bit (bit 31): for `VK_PACKET` the high word of lParam may hold the character (R2 F1), so the bit cannot tell down from up for characters at U+8000 and above, and a check on it would drop key-downs of CJK text (Ruling 32).

README row:
`| (a) | src/platform/windows/events.rs | A VK_PACKET key-up (SendInput KEYEVENTF_UNICODE: Unikey, EVKey, OpenKey, password managers) went through translate_message, which forges a WM_KEYDOWN, so the character came twice or with a stray one (R2 F1). Both key-up handlers return early for VK_PACKET with the value they returned before, without TranslateMessage. | vendor(windows): gpui patch (a) |`

Upstream (read by the plan review, `crates/gpui_windows/src/` on Zed's `main`): PR #41259 rewrote the message loop "in a traditional Win32 style" (`TranslateMessage` on the real message unless a key-down was handled; `translate_message` gone; `handle_key_event` has `VK_PACKET => None`). Same `VK_PACKET` result as this patch: one translation per key-down, none per key-up, `handle_keyup_msg` returning `Some(1)`. The rewrite depends on the new loop, AltGr and dead-key changes and does not port to 0.2.2; the small patch is the right size.

## 2. The native crash filter and its watchdog (Task B5)

Install (`crash_native::install(ctx, mode)`, Windows only, once, in GUI and `--diagnose` modes, after the start-up environment changes: §5 steps 8 and 9g; `mode` is the panic hook's, §5 step 5). Allocation is allowed here.
1. `create_dir_all(ctx.logs_dir)`; build `path: Vec<u16>` = `ctx.logs_dir/crash-native.<compact_utc(now)>.<pid>.txt`, UTF-16, NUL-terminated (the name's time is therefore the process start; the file's `time:` line holds the crash's: plan review M-9), and `header: Vec<u8>` = the first seven report lines below, each through `redact` (UTF-8). A failure here: log it and return without installing (no filter is better than a filter with half its data).
2. Only in `Dialog` mode (plan review M-13: `FileOnly`, used by `--diagnose --no-open` in CI, starts no reporter, so it skips steps 2 and 3 and the filter writes the file only): `go = CreateEventW(null, TRUE, FALSE, null)`, `done = CreateEventW(null, TRUE, FALSE, null)` (manual reset, not signalled).
3. Watchdog, only when both events exist: `std::thread::Builder::new().name("crash-reporter-watch".into())` with its own `cmd: Vec<u16>` = `reporter_command_line(ctx.exe, "--report-crash", path)`, UTF-16, NUL-terminated (`CreateProcessW` may write into `lpCommandLine`, so the thread owns a writable copy). Body: `WaitForSingleObject(go, INFINITE)`; `CreateProcessW(null, cmd.as_mut_ptr(), null, null, FALSE, 0, null, null, &si, &mut pi)` with `si: STARTUPINFOW` zeroed and `cb = size_of::<STARTUPINFOW>()`; on success `CloseHandle(pi.hThread)`, `CloseHandle(pi.hProcess)`; `SetEvent(done)`.
4. Store `NativeTargets { path, header, go, done }` in `static NATIVE: OnceLock<NativeTargets>`, the handles as `usize`; `go = 0` in `FileOnly` mode or when step 2 or 3 failed (the filter then writes the file only).
5. `SetUnhandledExceptionFilter(Some(filter))`. The previous filter is not chained. It may be the system default or, with the static MSVC CRT, the CRT's C++-exception filter; replacing it is harmless, because Rust panics never reach the top level (caught by `lang_start`, by std's threads, or turned into `__fastfail` aborts) (plan review M-8).

The filter, `unsafe extern "system" fn filter(info: *const EXCEPTION_POINTERS) -> i32`. Its own code allocates nothing and cannot panic (stack arrays, `OnceLock::get`, `wrapping_sub`, the model's checked writer). The Win32 calls it makes may use the process heap or the loader lock internally (`CreateFileW` converts the path on the process heap; `GetModuleHandleExW` and `GetModuleFileNameW` take the loader lock), and they run before the bounded 5 s wait: a fault while another thread holds one of those locks can stall the filter there. Accepted; this is the one place a native crash can still end without a file (plan review M-8).
1. `if IN_FILTER.swap(true, Ordering::SeqCst) { return EXCEPTION_CONTINUE_SEARCH; }` (a second exception while reporting).
2. `let Some(t) = NATIVE.get() else { return EXCEPTION_CONTINUE_SEARCH };`
3. `info` and `(*info).ExceptionRecord` non-null → `code = ExceptionCode as u32`, `address = ExceptionAddress as u64`; else 0.
4. `GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS | GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT, address as PCWSTR, &mut hmod)` ≠ 0 → `offset = address.wrapping_sub(hmod as u64)` and `GetModuleFileNameW(hmod, name.as_mut_ptr(), 260)` into `name: [u16; 260]` (0 → empty). FROM_ADDRESS: "lpModuleName is an address in the module"; UNCHANGED_REFCOUNT: no `FreeLibrary` owed (GetModuleHandleExW documentation).
5. `GetSystemTime(&mut st)` → `[wYear, wMonth, wDay, wHour, wMinute, wSecond]`; `GetCurrentThreadId()`.
6. `let mut buf = [0u8; 1536]; let len = write_native_report(&mut buf, &facts);`
7. `h = CreateFileW(t.path.as_ptr(), GENERIC_WRITE, FILE_SHARE_READ, null, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, null)`; `h != INVALID_HANDLE_VALUE` → `WriteFile(h, buf.as_ptr(), len as u32, &mut written, null)`, `FlushFileBuffers(h)`, `CloseHandle(h)`. A failure skips the rest of this step; the dialog still appears (in `Dialog` mode).
8. `t.go != 0` → `SetEvent(go)`, `WaitForSingleObject(done, 5000)`. Process creation runs on the watchdog's stack, so a stack overflow (the filter has only the guaranteed reserve) can still report.
9. `return EXCEPTION_CONTINUE_SEARCH` ("Proceed with normal execution of UnhandledExceptionFilter": Windows Error Reporting still records the crash in Event Viewer).

What reaches it: access violations (`0xC0000005`), illegal instructions (`0xC000001D`, R1 F8), stack overflows after Rust's own message. A Rust panic does not: `abort` uses `__fastfail`, which skips every handler, and the panic hook has already reported it. Windows still records such aborts (`0xC0000409`) and stack overflows past the guarantee as "Application Error" events, which `--diagnose` lists (§6, Ruling 38).

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

Features (windows-sys 0.61.2): `Win32_System_Diagnostics_Debug` + `Win32_System_Kernel` (`SetUnhandledExceptionFilter`, `EXCEPTION_POINTERS`), `Win32_System_LibraryLoader`, `Win32_Storage_FileSystem` + `Win32_Security` (`CreateFileW`, `CreateEventW`, `CreateProcessW`), `Win32_System_IO` (`WriteFile` is gated by it, `Storage/FileSystem/mod.rs:463-464`, because it takes `*mut OVERLAPPED`; it compiles today only because `polling` and `socket2` enable it on the same windows-sys: plan review M-7), `Win32_System_Threading`, `Win32_System_SystemInformation` (`GetSystemTime`).

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

## 4. Patch (c): `src/platform/windows/directx_renderer.rs` and `draw_window` in `src/platform/windows/events.rs` (Task B8)

One commit, two files (plan review I-3). `events.rs` already carries patch (a)'s line 1 notice, which stays; the README row (c) names both files.

New line 1 of `directx_renderer.rs`:
```rust
// Modified by ShellX: a failed resize or device-lost recovery no longer leaves a dropped render target, releases objects twice or presents a frame that names the emptied atlas. See windows/vendor/README.md.
```

What fails today (R1 F5, read in this file): `resize` (`:318-358`) records the new size, releases `render_target` through `ManuallyDrop::drop` and takes `render_target_view[0]` with `unwrap()` before `ResizeBuffers(...)?`; when that fails (device removed) the next `draw` panics in `pre_draw` (`:190` `.as_ref().unwrap()`), the next resize to another size panics on `.take().unwrap()` (`:330`), and the device-lost path releases `render_target` a second time (`DirectXResources::drop`, `:1008-1013`). `handle_device_lost_impl` (`:226-284`) releases `resources` and `devices`, then can fail at any `?`; the retry (`try_to_recover_from_device_lost`, five attempts) releases them again, derives `disable_direct_composition` from the `direct_composition` the first attempt already took (`:227`), and `Drop for DirectXRenderer` (`:997-1006`) releases them once more. A failed attempt also leaks what it created: `DirectXRendererDevices::new` and `DirectXResources::new` return `ManuallyDrop<…>`, so when `globals`, `pipelines` or `DirectComposition` then fail with `?`, the new devices and resources are never released; in compatible mode the leaked swap chain stays bound to the window, so every later `CreateSwapChainForHwnd` for it fails and recovery can never succeed (plan review M-4; the one-swap-chain-per-window consequence is inferred). And a recovery that succeeds can still crash (plan review I-3): `self.atlas.handle_device_lost(...)` empties the atlas (`directx_atlas.rs:56-66`), while GPUI re-presents the previous scene without rendering it again whenever the window is not dirty but `needs_present` holds (active, and input within the last second: `src/window.rs:1039-1058`; `present()` draws `rendered_frame.scene`, `:2007-2011`). That scene's sprites name textures that no longer exist, `get_texture_view` indexes `textures[id.index]` of an empty list (`directx_atlas.rs:236-242`), and the panic inside WM_PAINT aborts the process. The vsync thread sends `WM_GPUI_FORCE_UPDATE_WINDOW` only 200 ms after the recovery (`platform.rs:1082-1092`), so a stray WM_PAINT or the size-move timer in between is enough. Upstream fixed exactly this ("skip until a fresh frame").

Changes (each is the minimum for one of those faults):
1. `struct DirectXRenderer`: add after `font_info`
   ```rust
       /// ShellX: fixed at creation (`handle_device_lost_impl` used to derive it from a field it had taken).
       disable_direct_composition: bool,
       /// ShellX: `Some((width, height))` while the device-lost path has released the old devices and
       /// resources and not yet created new ones.
       released: Option<(u32, u32)>,
       /// ShellX: set by a successful device-lost recovery: the atlas is empty, so nothing may be drawn
       /// until `draw_window` forces a frame that rebuilds the scene (item 9).
       needs_fresh_frame: bool,
   ```
   and set `disable_direct_composition, released: None, needs_fresh_frame: false,` in `DirectXRenderer::new`'s struct literal.
2. `struct DirectXResources`: `render_target: ManuallyDrop<ID3D11Texture2D>` → `render_target: Option<ID3D11Texture2D>`. `create_render_target_and_its_view` and `create_resources` return `Option<ID3D11Texture2D>` in that position (`ManuallyDrop::new(render_target)` → `Some(render_target)`). `impl Drop for DirectXResources` body → `drop(self.render_target.take());` (still released before the swap chain, as before).
3. `pre_draw`: `self.resources.render_target_view[0].as_ref().unwrap()` → `self.resources.render_target_view[0].as_ref().context("no render target to draw into")?`.
4. `draw`: first statements
   ```rust
        if self.released.is_some() {
            anyhow::bail!("the GPU device was lost; drawing resumes once it is recreated");
        }
        if self.needs_fresh_frame {
            // ShellX: this scene was built before the recovery and names atlas textures that no
            // longer exist; skip it until draw_window forces a fresh frame (item 9).
            return Ok(());
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
6. `handle_device_lost_impl` (plan review M-2: the size must exist on a retry too; M-4: a failed attempt releases what it made):
   ```rust
        let disable_direct_composition = self.disable_direct_composition;   // replaces :227
        let (width, height) = match self.released {
            Some(size) => size,
            None => {
                let size = (self.resources.width, self.resources.height);
                unsafe {
                    // the existing release block, unchanged (both report_live_objects calls stay inside)
                }
                self.released = Some(size);
                size
            }
        };

        let devices = ManuallyDrop::into_inner(
            DirectXRendererDevices::new(directx_devices, disable_direct_composition)
                .context("Recreating DirectX devices")?,
        );
        let resources = ManuallyDrop::into_inner(DirectXResources::new(
            &devices,
            width,
            height,
            self.hwnd,
            disable_direct_composition,
        )?);
   ```
   then the existing `globals`, `pipelines`, `direct_composition` and `self.atlas.handle_device_lost(&devices.device, &devices.device_context)` lines, unchanged; a `?` among them now drops `resources` (its `Drop` releases the render target, then the swap chain) and `devices`. The assignments wrap again: `self.devices = ManuallyDrop::new(devices); self.resources = ManuallyDrop::new(resources);` (the other three unchanged), then the existing `OMSetRenderTargets` block, then `self.released = None; self.needs_fresh_frame = true;` before `Ok(())`. A second loss during recovery: the vsync thread sees the still-lost device and repeats the whole recovery, so `released` is cleared once a device works (`platform.rs:243-270, 1033-1100`).
7. `gpu_specs`: first statement `if self.released.is_some() { anyhow::bail!("the GPU device was lost"); }`.
8. `impl Drop for DirectXRenderer` (plan review M-3: the debug-only `report_live_objects` read the released devices):
   ```rust
    fn drop(&mut self) {
        if self.released.is_some() {
            return;
        }
        #[cfg(debug_assertions)]
        report_live_objects(&self.devices.device).ok();
        unsafe {
            ManuallyDrop::drop(&mut self.devices);
            ManuallyDrop::drop(&mut self.resources);
        }
    }
   ```
9. Skip until a fresh frame (plan review I-3; upstream's fix). In `impl DirectXRenderer`:
   ```rust
    /// ShellX: true once after a successful device-lost recovery; `draw_window` then forces a
    /// frame that rebuilds the scene, which refills the atlas, before anything is presented.
    pub(crate) fn take_needs_fresh_frame(&mut self) -> bool {
        std::mem::take(&mut self.needs_fresh_frame)
    }
   ```
   In `events.rs`, `draw_window` (`:1196-1205`), right after `request_frame` is taken:
   ```rust
        let mut request_frame = self.state.borrow_mut().callbacks.request_frame.take()?;
        // ShellX (patch (c)): the first frame after a device-lost recovery rebuilds the scene.
        let force_render = force_render || self.state.borrow_mut().renderer.take_needs_fresh_frame();
        request_frame(RequestFrameOptions {
            require_presentation: false,
            force_render,
        });
   ```
   (`renderer` is a `pub` field of the window state, `window.rs:51`; the borrow ends with the statement, before `request_frame` runs.) `draw_window` is the only caller of `request_frame` (`events.rs:1197`), so no stale scene reaches the renderer: the forced frame runs `window.draw(cx)` then `present()`, and ShellX has no `.cached(` views, so the whole scene is rebuilt. A minimised window has no `request_frame` (`events.rs:175-177`): `draw_window` returns before taking the flag, which waits for the restore.

Why it cannot make anything worse for a PC whose device is never lost: `released` stays `None`, `needs_fresh_frame` stays `false` and `render_target_view[0]` stays `Some`, so every new branch is a false test (`draw_window` gains one `RefCell` borrow per frame and passes `force_render` unchanged); the render target is released once at each resize and once at drop, in the same order as before; `disable_direct_composition` holds the value the old code derived at the first call. Behaviour changes only after a failed resize (frames are skipped and the resize is retried instead of a panic inside the window procedure) or during device-lost recovery (old objects released once; a failed attempt releases what it made; retries and the final drop skip released objects; the first frame afterwards is rendered afresh). Recovery that never succeeds now leaves a window that skips frames (and logs, collapsed by the log's count line) instead of a use-after-free. One case stays (plan review M-5, documented, not handled): if the vsync thread recovers its devices but the window's five attempts all fail, no further device-lost event comes (`check_device_lost` sees a healthy device) and `released` stays `Some`, so the window draws nothing until it is closed, with no dialog (before the patch: a crash, which B4 would now report).

README row:
`| (c) | src/platform/windows/directx_renderer.rs, src/platform/windows/events.rs (draw_window) | After DXGI_ERROR_DEVICE_REMOVED during a resize the render target was left dropped: the next paint panicked inside the window procedure (abort), a later resize panicked, and device-lost recovery released the render target and, on retries and at drop, the devices and resources a second time; a failed recovery attempt leaked its swap chain, and a successful one emptied the atlas while the old scene could still be presented (R1 F5). The render target is an Option, a failed resize is retried at the next draw, recovery releases the old objects once, releases what a failed attempt made and remembers the composition mode, and after a recovery nothing is drawn until draw_window forces a fresh frame (upstream's fix). | vendor(windows): gpui patch (c) |`

## 5. Start-up order (Tasks B3, B4, B5, B6, B9)

`main()`:
1. Read the arguments with `std::env::args_os()` (today `args()`, `main.rs:35`, which panics on a non-Unicode argument before any hook exists; flags compare as `OsStr`, the reporter's file stays an `OsString`/`PathBuf`: plan review M-22).
2. `--report-crash <file>` or `--report-window <file>` → `exit(crash::run_reporter(kind, file))`. Nothing else runs: no hook, no log, no mutex, no marker, no filter.
3. Any of `--version`, `--smoke`, `--smoke-ui-assets`, `--smoke-panes`, `--diagnose` → `console::attach_parent_console()` (Windows; Ruling 29).
4. `let ctx = CrashContext::this_process();` (records the main thread id, exe path and base, version, commit, build, Windows version).
5. `crash::install_panic_hook(ctx.clone(), mode)`: `Dialog` for the GUI and for `--diagnose` without `--no-open`; `FileOnly` otherwise (plan review M-13: in CI a reporter would wait on a desktop nobody sees).
6. `--crash-test panic|native|window` → `crash::set_crash_test(..)`.
7. `--version`, `--smoke-ui-assets`, `--smoke-panes`, `--smoke`: as today (`--version` prints with `writeln!`, error ignored; `--smoke` starts Windows PowerShell itself, Ruling 39).
8. `--diagnose [--no-open]` → `crash_native::install(&ctx, mode)` (Windows; the same `mode` as step 5) → `exit(diagnose_run::run(!no_open))`.
9. The window:
   a. `logger::install(&paths::logs_dir())`; log the start line: B3 writes `ShellX <VERSION> starting`; B4 makes it `"<about_version()> starting on Windows <ctx.windows>"` (plan review M-17).
   b. `let other = startup::acquire_app_mutex();` (Windows; false elsewhere).
   c. `env_forced` = `GPUI_DISABLE_DIRECT_COMPOSITION` is `"1"` or `"true"` (GPUI's own test, `platform.rs:138-139`); `is_retry` = `SHELLX_RENDER_RETRY` is `"1"`.
   d. Windows only: `unsafe { std::env::remove_var("SHELLX_RENDER_RETRY") }`. SAFETY (plan review M-11): `set_var`/`remove_var` are safe on Windows at any time (Rust documentation); on macOS GPUI ignores the variable and nothing relaunches, so steps 9d and 9f run on Windows only. (The former "no other thread exists yet" was not quite true on Windows: the loader's worker threads exist from process start.)
   e. `let (plan, remembered) = startup::plan_gui_start(paths, env_forced, is_retry, other);` (logs `start_guard::start_line(&plan)`).
   f. Windows only: `plan.mode == Compatible && !env_forced` → `unsafe { std::env::set_var("GPUI_DISABLE_DIRECT_COMPOSITION", "1") }` (same SAFETY), and `startup` records that this start set it.
   g. `crash_native::install(&ctx, HookMode::Dialog)` (Windows): its watchdog thread starts after the start-up environment changes.
   h. `ui::run()`. At the top of the `Application::run` closure, once `Application::new()` has built the platform (GPUI reads the variable only in `WindowsPlatform::new`): `startup::forget_render_variable()`, which on Windows removes `GPUI_DISABLE_DIRECT_COMPOSITION` when this start set it (9f) or is a retry (whose parent set it), so the shells in the window, and a ShellX started from them, never inherit it; a variable the person set stays (plan review M-11; cmux-pty starts every shell from the process environment, `clean_environment` false).

`ui/app.rs`:
- After `open_window` returns `Ok(window)`: `window.update(cx, |_, window, _| window.on_next_frame(|window, _| window.on_next_frame(|_, _| startup::first_frame_drawn())))` (Ruling 6); `crash_test()` `Panic` → a foreground task (`cx.spawn`) that first calls `startup::orderly_quit()` (it only removes the marker this start wrote) and then panics; `Native` → the same task, then `unsafe { std::ptr::null_mut::<u8>().write_volatile(1) }`. A crash test therefore never changes the next start's display mode; it still runs inside GPUI's window procedure, the real path. (Plan review I-4: `cx.spawn` posts a message, which GetMessage handles before WM_PAINT, so the task runs before the first frame. B4 and B5 write the task without the call, since no marker exists before B6; B6 adds it.)
- `crash_test() == Some(Window)` and not a retry → act as if `open_window` returned `Err(anyhow!("crash test: the window was not opened"))` without calling it.
- `Err(e)` → `startup::window_failed(&e)` (never returns): log `{e:#}` (redacted by the logger); remove the marker this start wrote; `on_open_failed(&plan)`: `RelaunchCompatible` (Windows; elsewhere handled as `Report`, since the variable changes nothing on macOS) → `Command::new(current_exe).args(args_os().skip(1)).env("SHELLX_RENDER_RETRY", "1").env("GPUI_DISABLE_DIRECT_COMPOSITION", "1").spawn()`, `Ok` → `exit(0)`, `Err` → as `Report`; `Report` → `crash::write_window_failure(&ctx, &e, Some(&start_line(&plan)))` (`start-failed.<utc>.<pid>.txt`: the panic report's header lines, the `render mode: …` line, `error:` and the chain, each line redacted; plan review M-19), `crash::start_reporter(&ctx, DialogKind::WindowFailed, &file)`, `exit(1)`.
- `on_window_closed`: when no window is left, `startup::orderly_quit()` (removes the marker) then `cx.quit()`.

`startup::first_frame_drawn()`: remove the marker if this start wrote it; `remember_after_first_frame(&plan, remembered)` = `Some(m)` → write `render.json` (temp file then rename); log `first_frame_line(plan.mode)` (`first frame drawn in <mode> display mode`). Every file error is logged and ignored.

## 6. `--diagnose` probes (Task B9)

Each probe fills one `DiagnosticsReport` field (foundations `diagnose.rs`), runs on its own thread through `diagnose_run::bounded` (inside `crash::expect_caught(|| catch_unwind(..))`, waited for with `recv_timeout`: 10 s, 60 s for `shell_checks`; plan review I-7), and on failure writes `failed: <reason>`, `timed out after 10 s` (or `60 s`) or `unknown` in its own field; `format_report` redacts every line. Phase 1, the probes that cannot hang on a driver, the network or a shell, run together and are written first: `app_version`/`commit`/`build_kind`, `created_utc`, `windows_version`, `cpu`, `displays`, `first_window`, `render_mode`, `keyboard_layouts`, `input_methods`, `typing_tools_running`, `state_dir`, `sign_in`, `crash_files`, `log_tail`. Phase 2 runs together after that write: `chosen_gpu`, `gpus`, `dwm_timing`, `shells_found`, `shell_chosen`, `shell_checks`, `relay`, `windows_error_events`. Values are written with spaces or `:` between parts (the redactor's known limits: a long joined name or an API constant name would read as a token; this report never prints constant names).

| Field | Source | Failure |
| --- | --- | --- |
| `app_version`, `commit`, `build_kind` | `build_info` (`build_kind`: `release` or `debug`, plus ` <label>`) | `unknown` |
| `created_utc` | `log_file::utc_timestamp(now)` | — |
| `windows_version` | `os_info::os_version()` (`RtlGetVersion`, Ruling 28) + `DisplayVersion` and `UBR` from `HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion` (winreg): `10.0.26100.2314 (24H2)` | the parts that were read |
| `cpu`, `cpu_features` | `HKLM\HARDWARE\DESCRIPTION\System\CentralProcessor\0` `ProcessorNameString`; `is_x86_feature_detected!` for `sse4.2`, `avx`, `avx2`, `fma`, `bmi2`, `avx512f` (listed when present; R1 F8) | `unknown` |
| `displays` | `EnumDisplayMonitors(null, null, Some(cb), &mut list as *mut _ as LPARAM)`, whose `unsafe extern "system"` callback only pushes the `HMONITOR` into `list` and returns `TRUE` (a panic there would abort whatever surrounds the probe: plan review M-26); after `EnumDisplayMonitors` returns, per monitor `GetMonitorInfoW` with `MONITORINFOEXW` (`szDevice`, `rcMonitor`, `rcWork`, `dwFlags & MONITORINFOF_PRIMARY`) and `GetDpiForMonitor(MDT_EFFECTIVE_DPI)` → `scale_percent = dpi * 100 / 96` | `displays: none` |
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
| `windows_error_events` (Ruling 38) | Windows only (`None` elsewhere: no line). `Command::new(<system_root>\System32\wevtutil.exe)` (`local_pty::settings::system_root(&probe_from_system())`) with the arguments `qe`, `Application`, `/c:5`, `/rd:true`, `/f:xml`, `/q:*[System[Provider[@Name='Application Error']] and EventData[Data='shellx-desktop.exe']]` (one argument each; Rust quotes the query, which has spaces), `creation_flags(CREATE_NO_WINDOW)` (no console window flashes for a GUI-subsystem caller), `output()`; exit 0 → `Some(Ok(windows_error_summaries(stdout)))`: one line per event, `<SystemTime> <the Data values, comma-separated, empty ones left out>`, entities decoded (`&amp; &lt; &gt; &quot; &apos;`, `&#N;`, `&#xH;`), whitespace runs as one space, at most 300 characters; written as `windows error event: <line>` in `[crash files]` after the file names, or `windows error events: none found`. A `wevtutil` left running when `run` gives up is not killed: it ends by itself, and its pipes close when this process exits | `Some(Err(..))` → `windows error events: unavailable (<reason>)`: `could not start wevtutil: <io error>`, `wevtutil exit <code>: <first stderr line>`, `timed out after 10 s` |
| `log_tail` | the last 200 lines of `shellx.log`, preceded by the end of `shellx.log.1` when shorter | `none` |

Output (plan review I-7, M-15): `--diagnose` checks only the shell new tabs start. Every probe runs on its own thread; `run` waits for it with `recv_timeout(10 s)` (60 s for `shell_checks`, whose steps keep their own 10 s bound); a probe that has not answered writes `timed out after 10 s` (or `60 s`) in its field and is abandoned (it may keep running; `run` ends with `std::process::exit`, which ends it). The relay call is bounded the same way (the core's own timeouts reach 20 s, `shellx-core/src/http.rs:27-28`). The report is written twice under the same name, `logs_dir()/diagnostics.<compact_utc>.<pid>.txt`, each time to `<name>.tmp` and then renamed over it: first after phase 1, with `slow_checks_pending` set, so `chosen gpu`, `gpus`, `dwm timing`, the `[shells]` lines, `relay` and the Windows error events read `not run yet`; then complete, after phase 2. So a hang or a native crash in the GPU probe still leaves a report next to the `crash-native` file. A report takes at most about 70 s. After the second write: `writeln!(stdout, "Diagnostics report: {path}")` (error ignored); unless `--no-open`, `explorer.exe /select,"<path>"` (`raw_arg`). `spawn_report_process()` = `Command::new(current_exe()?).arg("--diagnose").spawn()`.

Features: windows `Win32_Graphics_Dxgi`, `Win32_Graphics_Dxgi_Common`, `Win32_Graphics_Direct3D`, `Win32_Graphics_Direct3D11` (all already enabled by GPUI, so nothing new compiles); windows-sys `Win32_System_Console`, `Wdk_System_SystemServices` + `Win32_System_SystemInformation` (`RtlGetVersion`), `Win32_Graphics_Gdi` + `Win32_UI_HiDpi`, `Win32_Graphics_Dwm`, `Win32_System_Performance`, `Win32_System_Diagnostics_ToolHelp`, `Win32_UI_Input_KeyboardAndMouse`, `Win32_Globalization`, and `Win32_System_Threading` (`CREATE_NO_WINDOW`; already enabled by B4).

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
