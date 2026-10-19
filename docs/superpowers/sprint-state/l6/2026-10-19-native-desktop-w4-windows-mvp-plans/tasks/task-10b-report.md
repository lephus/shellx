# Task 10b report: sign-in UI, account service wiring, real machines in the sidebar

Status: DONE. Commit 2c4567107e on shellx/l6-windows, pushed with `git push origin shellx/l6-windows`. Its parent 0d9b240787 (the Task 9 fix) was already on the remote.

CI run 39175060120 (contains 2c4567107e) passed on the first round, with all four jobs green: model, remote-e2e, app (x86_64-pc-windows-msvc, 9m26s) and installer. The GPUI UI code compiled on CI on the first try.

## What was built

### Model (`windows/shellx-model`, tested on the Mac)

**`src/account.rs`: the 10a review carry-overs**
- **Re-register:** `register_requested` is reset each time the flow enters LoggedIn. If a later list lacks this machine (revoked elsewhere), the flow registers once more, then lists.
- **`not_registered`:** this error no longer stops the flow. It sets `retry_list`, arms a tick, and keeps listing every 15 s without registering again. When the machine shows up in a list, the state goes to LoggedIn.
- **ListResult during login:** a ListResult that arrives while the login call is in flight is ignored. ListResults that come back after the login (LoggingIn with no login in flight, or during register) are applied as before. This rule assumes call order, which the app guarantees: one serial worker, see below. The module doc says so.
- **Logout:**
  - New `AccountEvent::LogoutResult(Result<(), CoreErr>)`.
  - A failure keeps LoggedIn (ticks continue) and sets `notice()`.
  - `not_logged_in` and `Ok` both end in LoggedOut. `LoggedOut` is kept as an alias of `Ok`.
  - A second LogoutRequested while one is in flight is ignored.
- **Accessors:** `notice()` and `login_in_flight()`.
- **Tests:** 4 new, 13 in the module.
  - `reregisters_once_after_this_machine_disappears`
  - `not_registered_keeps_ticking_until_listed`
  - `list_result_ignored_while_login_in_flight`
  - `logout_failure_stays_logged_in_with_notice`

**`src/text_edit.rs` (new)**
- The pure single-line edit buffer behind the text field. The rules are taken from GPUI `examples/input.rs`.
- **Editing:** content, selection (reversed or not), IME marked range, `replace_text_in_range`, `replace_and_mark_text_in_range` with the caret inside the preedit, and UTF-16 ↔ UTF-8 offsets.
- **Boundaries:** chars, with zero-width chars kept with the char before them, so Backspace removes a decomposed "ế" whole.
- **Control characters:** newlines, tabs and control characters are cleaned out of the text.
- **Masked mode:**
  - Shows one "•" per char.
  - Maps display offsets ↔ content offsets.
  - `copy_text` / `cut` return None.
  - `text_for_range` returns None, so the IME never gets the password.
- **IME cancel:** an empty commit with no preedit is a no-op, so a Japanese IME cancel does not delete a selection.
- **Tests:** 8, covering Telex preedit → commit, Japanese caret, astral UTF-16 and the masked no-leak cases.

**`src/strings.rs`**
- New key `Str::SigningIn`: "Đang đăng nhập…" / "Signing in…". It is in `Str::ALL`, and the count test is now 50.
- New helper `login_failed(lang, msg)`: "Đăng nhập không thành công: <msg>".

### App, GPUI-free (tested on the Mac)

**`src/core_service.rs` (new)**
- `API_BASE` = `https://relay.shellx.pro`.
- `api_base()`: `SHELLX_API_BASE` overrides it only under `cfg(debug_assertions)`. Release builds ignore it. A test checks both cases.
- `MachineFacts::this_pc()`: `os_version` from the registry, `device_name` from COMPUTERNAME.
- `this_pc_config()`: `state_dir` = `paths::core_dir()`, app_version 2.0.0. `platform: "windows"` is sent by `config_set`. A path error becomes the readable `CoreErr("state_dir", "ShellX state folder: LOCALAPPDATA is not set")`.
- `ConfiguredCore`: a `CoreCall` that sends `config.set` before its first call, and again after a failed attempt.
- `run_account_action(core, facts, action)`:
  - CallList → `ListResult`.
  - CallLogin → `LoginResult`. The password is moved in and dropped.
  - CallRegister → `Registered`, using the same name and os as `config.set`. No `noise_public_key_b64` is sent (L0 R17).
  - CallHeartbeat → no event.
  - CallLogout → `LogoutResult`.
  - ScheduleTick → None.
- **Tests:**
  - Debug-only override.
  - config.set happens once, the call that hits a config error gets that error, and the next call retries.
  - The action→event mapping, plus `unknown_method` as a readable error.
  - `account_session_against_fake_api` drives `AccountFlow` through the real `CoreBridge` against L5's `shellx-fake-api`:
    - start → LoggedOut
    - wrong password → Error
    - login → CallList → CallRegister (once) → CallList → LoggedIn with exactly one `is_this_machine`
    - tick at 30 s → CallList + CallHeartbeat
    - logout → LoggedOut
    - restart → LoggedOut

**`src/paths.rs`**
- `native_dir()` now returns `io::Result`. On Windows an unset or empty `LOCALAPPDATA` is an error; there is no `C:\Users\Default` fallback.
- New test `windows_layout_and_missing_local_app_data` uses a pure `native_dir_from`.

**`src/os_info.rs`**
- `utc_offset_secs()` uses `GetTimeZoneInformation`, through `windows-sys` 0.61 (already in Cargo.lock through gpui). The new direct dep is under `cfg(windows)`, feature `Win32_System_Time`.
- The bias includes the standard/daylight bias for the current zone id.
- A pure `offset_from_tz` is tested (VN +7, US Pacific DST/standard, India +5:30, invalid → 0).

**`src/shell_info.rs`**
- `sidebar_machines(server_list, COMPUTERNAME)`: this PC is added first only when the server list has no `is_this_machine` entry.
- `this_machine_id(list)`.
- `SHELL_STRINGS` gained NotLoggedIn, Login, Email, Password, LoginFailed, SigningIn, Cancel, RequestAccess and Error. It now has 17 strings.

**`src/smoke.rs`**
- New `account_flow()`, called from `run()` right after `core_bridge()`. It uses a real `CoreBridge` over a temp state dir and `run_account_action` in order:
  - Start without a session must end LoggedOut (the sign-in card).
  - A login against `http://127.0.0.1:9` must end in Error with a code. No fake login is ever sent to the production API.
- It prints `smoke-account: start -> LoggedOut (sign-in card); login offline -> <code> (Đăng nhập không thành công: …)`.
- A Mac test (`core_service::tests::smoke_account_flow`) runs it as well.

`src/core_bridge.rs`: removed its `allow(dead_code)`.

### App UI (`cfg(windows)`, compiled on CI only)

**`ui/text_field.rs` (new)**
- Adapted from GPUI 0.2.2 `examples/input.rs`. The header comment names the origin: Zed Industries, Apache-2.0.
- **Input handler:** `EntityInputHandler` over `TextEdit`. The shaped-line element calls `window.handle_input` at paint, as the example does, so WM_CHAR and IMM32 composition (Telex, Japanese) go through the same path as in the terminal panes.
- **IME drawing:** the preedit is drawn underlined. `bounds_for_range` is shifted down half a line, because GPUI on Windows anchors the IME windows at `y + h/2`; the candidate list therefore opens under the field.
- **Keys:** handled in `on_key_down`; no app-wide key bindings are added.
  - Backspace and Delete.
  - ←/→, with Shift to select.
  - Home/End, with Shift to select.
  - Ctrl+A.
  - Ctrl+C / Ctrl+X / Ctrl+V, including the Ctrl+Shift forms and Ctrl/Shift+Insert, so terminal shortcuts never reach a pane while a field has focus. A masked field never copies or cuts.
  - Events: Enter → `Submit`, Esc → `Cancel`, Tab / Shift+Tab → `Next` / `Prev`.
  - Alt and Win chords are left to the app. Ctrl+Alt (AltGr) goes to WM_CHAR.
- **Mouse:** click and drag select.
- **Scrolling:** horizontal scroll keeps the cursor visible, with a content mask clip.
- **Disabled mode:** used while signing in.
- **Palette:** BG fill, BORDER (PRIMARY_LINE when focused), TEXT_HI text, MUTED placeholder, a PRIMARY cursor, and the selection at PRIMARY 30 %.

**`ui/button.rs` (new)**
- Mockup `.btn.pri`: PRIMARY_SOFT fill, PRIMARY_LINE border, PRIMARY_TEXT label, semibold.
- `.btn`: RAISE fill, BORDER, TEXT.
- Solid fills, no gradients. Disabled is drawn at 50 % opacity.

**`ui/account.rs` (new): `AccountService` entity**
- **Worker:** one `cx.background_spawn` worker reads actions from an unbounded channel and runs `run_account_action` in order. Results come back over a channel to a `cx.spawn` loop that applies them with `this.update`. No core call runs on the UI thread.
- **Ticks:** every `ScheduleTick{at_ms}` becomes a detached GPUI `background_executor().timer`, which delivers `Tick(max(now, at_ms))`. The clock is monotonic from service start.
- **UTC offset:** refreshed on every list result.
- **API:**
  - `state()`, `machines()`, `login_in_flight()`, `utc_offset_secs()`
  - `notice()` (for Task 11)
  - `login(email, password)`
  - `logout()`: the AppCommand-free method Task 11's settings panel calls.
- `Services` (ui/app.rs) now holds `core: Arc<dyn CoreCall>` = `ConfiguredCore::this_pc(..)`, for Task 11 (version.check) and Task 12b (pairing).

**`ui/login.rs` (new): `LoginPanel` entity, drawn in the sidebar under this PC's sessions**
- **Signed out:** a RAISE/BORDER card with "Chưa đăng nhập" and the primary "Đăng nhập" button.
- **Panel:** opened by the button.
  - Fields: Email, Mật khẩu (masked).
  - Buttons: the primary "Đăng nhập" button and a secondary "Huỷ".
  - On a failed login, an ERROR-colored line: `login_failed` + the core message.
- **Keys:** Enter in either field submits. If a field is empty, focus moves to it instead. Tab switches fields. Esc closes.
- **Submit:**
  - The password field is cleared immediately and the password is moved into the event.
  - While the call runs the fields are disabled and the button reads "Đang đăng nhập…".
  - On LoggedIn the panel closes and emits `Closed`, and RootView refocuses the terminal.
- **Other account errors:** offline at start, a state-folder problem, unknown_method or a register error show as one muted "Lỗi · <message>" line. Local terminals are unaffected, and the flow keeps retrying.

**`ui/sidebar.rs` / `ui/root.rs`**
- RootView owns the `AccountService` and `LoginPanel` entities. It observes the service and re-renders.
- The sidebar uses `build_groups(sidebar_machines(account.machines()), |_| Access::None, utc_offset_secs, lang)`:
  - This PC comes first, using its server id when signed in. Local sessions and the "+" stay under it.
  - Other machines follow, online first.
  - Offline machines are dimmed with "ngoại tuyến · lần cuối HH:MM" in local time.
  - An online machine without access shows "Xin quyền truy cập" as a disabled secondary button, until Task 12 wires it.
  - `ShowCode` shows the code. `Open` is left for Task 13.
- The session bar's machine name comes from the same list.
- `RootView::account()` is exposed for Task 11.

I did not touch `ui/term_view.rs`, `ui/panes.rs`, the workflow, or anything under `shellx-core/`.

## Evidence

**Mac** (CARGO_INCREMENTAL=0, `--locked`):
- `cargo test --locked -p shellx-model` → 126 passed. That includes the 13 account tests and 8 text_edit tests, plus the strings count test (50).
- `cargo test --locked -p shellx-app --bin shellx-desktop` → 46 passed. That includes 6 core_service tests (one is the fake-API session e2e, one is the smoke `account_flow`), 2 paths, 3 os_info and 5 shell_info tests.

**CI 39175060120, app job, `--smoke` (release exe on windows-2025):**
```
smoke-ui-assets: 21 icons, 17 strings x 2 languages
smoke-ui-assets: PASS
smoke-core: config.set OK, machines.list -> not_logged_in
smoke-account: start -> LoggedOut (sign-in card); login offline -> network (Đăng nhập không thành công: /v1/auth/login: io: No connection could be made because the target machine actively refused it. (os error 10061))
smoke-pairing: denied -> no link, approved -> link saved
smoke-input: bracketed paste, IME commit (one UTF-8 write), copy ok
smoke: … echo ok … unicode ok (tiếng Việt echoed by the shell) … resize ok … panes ok
smoke: PASS in 3.8782466s
```
**Windows build warnings for shellx-app:** 3. Two are pre-existing (`TermCore::size`, `PaneHost::len/is_empty`). The third, `AccountService::notice` never used, is mine: Task 11 will use it, and I did not spend another CI round on an `allow`.

**Formatting:** my new files and my parts of the shared files are rustfmt-formatted. I restored the other lane's formatting in smoke.rs; the diff there is my additions only.

**rustls only:** unchanged from 10a. The only new dependency is `windows-sys` 0.61.2, under cfg(windows); it was already in the tree. `Cargo.lock` gained only the `"windows-sys 0.61.2"` edge for shellx-app.

## Needs user
1. **Live sign-in** on a Windows PC against the deployed API with your own account. Expected sequence:
   1. Start: the card under this PC reads "Chưa đăng nhập" with "Đăng nhập".
   2. Click "Đăng nhập", type the email and password, press Enter.
   3. The button reads "Đang đăng nhập…".
   4. The card disappears.
   5. This PC is now listed under its account name with "· máy này", and your Mac is listed below it. If the Mac is online, the row shows a disabled "Xin quyền truy cập". If it is offline, the row is dimmed with "ngoại tuyến · lần cuối HH:MM" in your local time.
   6. Check on the server, or in another client, that the PC was registered once and that its heartbeat continues (last_seen updates every 30 s).
2. **Wrong password:** the panel shows "Đăng nhập không thành công: <server message>", the password field is cleared and focused, and Esc closes the panel.
3. **Offline after sign-in:** disconnect the network. The list stays and nothing logs out. Reconnect, and it refreshes within about 15 s.
4. **Telex in the email field:** typing (e.g. a name in a test field) composes inline and the candidate list opens under the field. The password field shows only dots.
5. **Restart:** the app comes back signed in, with no card and no second register.

## Concerns / deviations
1. **Runtime behavior not seen yet.** The GPUI UI code (text_field, login, account, button, and the sidebar/root wiring) cannot be built on the Mac. It was written against the gpui 0.2.2 sources and compiled cleanly on CI, but nobody has watched it run yet. Focus moves, IME placement in the field, the card layout at 290 px and scrolling of long emails need the manual checks under "Needs user".
2. **Serial worker.** All account calls run one at a time on one background worker, so a slow login delays the next heartbeat or list. This ordering is what makes "ignore ListResult while the login is in flight" correct. The pairing service (Task 12b) can use `Services.core` with its own worker; `Core` locks its own state.
3. **Password cleared on submit.** It must be retyped after a failed login. This was chosen to keep it in memory for as short a time as possible.
4. **Unregistered list fallback.** If the server list lacks this PC (just before register), this PC is shown under `LOCAL_MACHINE_ID` with COMPUTERNAME, so local tabs always have a group.
5. **Dropped timers.** Tick timers are detached, not cancelled. The flow asks for at most one tick at a time, and a tick that finds nothing due does nothing.
6. **Error text is the core's message.** Messages are shown as the core gives them, so they can be technical and in English: CI shows "/v1/auth/login: io: No connection could be made …". Turning error codes into Vietnamese texts (e.g. network → "Không kết nối được máy chủ") would need a code → Str table; I left it out of the MVP. It is a candidate for Task 11 or a polish pass.

K-change requests: none.

## Files
- /Users/lehuuphu/Documents/myProjects/shellx-wt-l6/windows/shellx-model/src/{account.rs, text_edit.rs (new), strings.rs, lib.rs}
- /Users/lehuuphu/Documents/myProjects/shellx-wt-l6/windows/shellx-app/src/{core_service.rs (new), core_bridge.rs, paths.rs, os_info.rs, shell_info.rs, smoke.rs, main.rs}
- /Users/lehuuphu/Documents/myProjects/shellx-wt-l6/windows/shellx-app/src/ui/{text_field.rs, login.rs, account.rs, button.rs (all new), sidebar.rs, root.rs, app.rs, mod.rs}
- /Users/lehuuphu/Documents/myProjects/shellx-wt-l6/windows/shellx-app/Cargo.toml, /Users/lehuuphu/Documents/myProjects/shellx-wt-l6/windows/Cargo.lock
