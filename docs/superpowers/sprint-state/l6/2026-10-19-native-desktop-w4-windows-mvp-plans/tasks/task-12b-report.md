# Task 12b report: request-access panel UI and sidebar hooks

Status: DONE. Commit e31b82e77d on shellx/l6-windows, pushed with `git push origin shellx/l6-windows`.

CI: run 39178302908 (head e31b82e77d) — green on the first round: model, remote-e2e, app (x86_64-pc-windows-msvc), installer all success. The GPUI UI compiled first try; shellx-app had 2 warnings, both pre-existing and none in my files. The app job's `--smoke` printed `smoke-ui-assets: 21 icons, 51 strings x 2 languages` and PASS, `smoke-pairing: denied -> no link, approved -> link saved`, and `smoke: PASS in 4.06s`.

## Built

### Carry-overs (pairing_service.rs, links_store.rs)
- **invite_file_name** no longer lossy. If sanitizing (lowercase, `[a-z0-9._-]`) changed the id, or truncation was needed, it appends `-<8 hex>`: the upper 32 bits of an FNV-1a 64 hash of the original id. No new crate. The name stays at most 64 bytes, starts with "invite-", and is stable per id. Unchanged ids (`m1`, lowercase UUIDs) keep `invite-<id>.uri`.
  - Test `invite_file_name_never_shared_after_sanitizing`: m1, M1, m/1, m:1, máy1 and two 61-char ids sharing a 60-char prefix all give distinct names that pass core's rules.
- **Corrupt links.json:** `LinksStore::load` now reads bytes. Invalid UTF-8 or JSON renames the file to `links.json.bad-<unix>` (with `-<n>` added if that name exists), logs the rename with eprintln, and returns an empty set. A later save works.
  - Tests: `corrupt_file_is_moved_aside_and_starts_fresh` (store) and `corrupt_links_file_is_moved_aside_on_load` (service).
- **Unavailable store:** new `LinksStore::unavailable(reason)` and `default_or_unavailable()`. If LOCALAPPDATA is missing, load is empty and every save fails with that reason, so the panel shows the reason instead of the app writing next to the cwd. Test `unavailable_store_is_empty_and_refuses_saves`.
- **save_error in the panel:** the Snapshot carries `save_error`. The Approved card shows an ERROR line "Không lưu được quyền truy cập: <error>". Test `save_failure_after_approval_is_reported`: Approved state, error set, access stays None.
- **execute AND finish off the UI thread:**
  - New GPUI-free `Cmd {LoadLinks, Start{machine_id, machine_name, ui_seq}, Cancel{ui_seq}, Tick{at_ms}, Done(JobResult)}`, plus `PairingService::handle(cmd, now) -> Vec<Job>` and `snapshot() -> Snapshot`. The Snapshot holds state, target, fingerprint, save_error, links, pending and ui_seq.
  - In the window, one background task owns the service and runs every Cmd. `finish` therefore runs there, including its links.json I/O.
  - Each Job runs on its own background task, so a Cancel is handled while a request is in flight. `execute_caught` wraps `execute` in catch_unwind and turns a panic into `internal` (test `execute_caught_always_delivers_a_result`), so every job delivers a JobResult.
  - Each new `tick_at` becomes a background timer that sends `Tick{at_ms}`. `handle` uses `max(now, at)`, so a timer that fires early still counts.
- **Core timeouts (checked in shellx-core/src/http.rs):** connect 10 s and global 20 s per request. `pair.request` makes one POST and `pair.poll` one GET (pairing.rs:208, 349), so every job ends within about 20 s.
- **Start = cancel current + start:** `Cmd::Start` cancels first, so a request for B while A waits stops A, and A's late result is dropped by the generation guard. Test `start_for_another_machine_cancels_the_current_one`.
- **Fingerprint:** the service now keeps the `fingerprint` from an accepted `pair.request`, which is this PC's device fingerprint (16 hex). It is cleared on start and cancel.
- **Command-driven flow test:** `commands_drive_the_flow_and_snapshots_carry_what_the_panel_shows` runs LoadLinks → Start → Waiting with fingerprint, Pending{code} and ui_seq → early Tick → Approved, then checks Granted and that a fresh service reads the saved link.

### Strings (shellx-model/src/strings.rs, 61 → 67 keys)
- **New keys:**

  | Key | vi | en |
  |---|---|---|
  | ComingSoon | "sắp có" | |
  | YourDeviceCode | "Mã thiết bị của bạn" | |
  | SaveLinkFailed | | |
  | SendingRequest | "Đang gửi yêu cầu…" | |
  | NoOtherMachines | | |
  | AddMachine | "Xin quyền truy cập máy khác" (tooltip on +) | |

- **Helpers:**
  - `request_access_to` ("Xin quyền truy cập <máy>")
  - `pairing_code_display` ("482 913")
  - `fingerprint_groups` (4×4)
  - `your_device_code`
  - `save_link_failed`
- Test `pairing_helpers`.
- SHELL_STRINGS (shell_info.rs) gains 13 keys; `--smoke-ui-assets` now reports 51 strings x 2 languages, PASS on the Mac.

### UI (cfg(windows), CI-compiled only)
- **ui/pairing.rs (new), `PairingPanel` entity:** owns the background loop above and renders the last Snapshot. Snapshots older than the UI's last Start or Cancel (`ui_seq`) are ignored, so the panel never flashes the previous attempt.
- **Panel layout:** an occluding overlay over the main area (BG at 0.6) with a centered RAISE/BORDER card, 400 px wide, holding:
  - The title "Xin quyền truy cập <máy>".
  - The code in Space Grotesk Bold 32 px TEXT_HI, `123 456`. Each digit is its own box with a 4 px gap, because GPUI 0.2.2 has no letter-spacing.
  - `Str::PairingCodeHint` in MUTED.
  - "Mã thiết bị của bạn: xxxx xxxx xxxx xxxx" in MUTED JetBrains Mono.
  - `Str::WaitingApproval` with a RUNNING dot.
  - Huỷ (secondary).
- **States:**
  - Requesting: "Đang gửi yêu cầu…" with a RUNNING dot, and Huỷ.
  - Approved: `Str::Approved` (DONE), the optional save-error line, and Đóng plus Mở. Mở is primary and disabled, with tooltip "sắp có" (Task 13b wires it).
  - Denied: `Str::Denied` (ERROR), Đóng and Thử lại.
  - Expired: `Str::Expired` (muted dot), Đóng and Thử lại.
  - Failed: "Lỗi · <core message>" (ERROR), Đóng and Thử lại.
- **Closing:** Esc, Huỷ or Đóng closes the panel. Closing while requesting or waiting sends Cancel, which stops polling. RootView refocuses the terminal on `PairingEvent::Closed`.
- **ui/sidebar.rs:**
  - RowAction::RequestAccess is now an enabled secondary button. It calls `RootView::request_access(id, name)`.
  - ShowCode shows the formatted code.
  - The machines-header `Icon::AddPlus` has the tooltip "Xin quyền truy cập máy khác" and toggles a small RAISE/BORDER list (`PickerEntry`) of the account's other machines that have no link. Online entries request access on click. Offline entries are dimmed and cannot be clicked, since approval needs the Mac. An empty list shows "Không còn máy nào để xin quyền".
  - `Tooltip` is now `pub(super)`.
- **ui/root.rs:**
  - Owns `pairing: Entity<PairingPanel>`, observes it and subscribes to Closed.
  - `build_groups` access is `pairing.access_for(id)`: link → Granted, waiting → Pending{code}, else None.
  - Picker entries are computed here.
  - `request_access` is blocked while a forced update shows. `toggle_machine_picker` is added.
  - Focus order is forced overlay > pairing > settings > terminal.
  - The main area is `relative`, with the panel as its last child. panes.rs keeps its own relative container, so pane rects are unchanged.
- **ui/mod.rs:** `mod pairing;`.

## Evidence
- Mac, CARGO_INCREMENTAL=0 --locked:
  - shellx-model: 129 passed.
  - shellx-app --bin shellx-desktop: 83 passed, including 3 links_store tests and 13 pairing_service tests.
  - `--smoke-ui-assets`: PASS (51 strings).
- rustfmt (edition 2024) is clean on every file I touched.
- `curl https://relay.shellx.pro/v2/machines` returned **404**, not the 401 the brief expected. Either the route is not at that path or it is not deployed; I did not investigate further, and there was no live login.

## Needs user
1. Live pairing on a Windows PC, signed in, with the Mac online and the cmux-based ShellX Mac app able to approve:
   1. Click "Xin quyền truy cập" on the Mac row. The panel shows "Đang gửi yêu cầu…", then the 6-digit code, the hint, your device code, and the yellow waiting line. The row shows the code.
   2. On the Mac, compare the code and the fingerprint, then approve. Within about 2 s the panel shows "Đã được chấp thuận" and a disabled Mở with "sắp có". The row loses the button (Granted). `%LOCALAPPDATA%\ShellX\native\remote\links.json` holds the link with `enrolled: false`, and `core\tickets\invite-<id>.uri` exists.
   3. Deny on the Mac: "Máy kia đã từ chối" and Thử lại.
   4. Wait 5 minutes without action: "Yêu cầu đã hết hạn".
   5. Press Esc while waiting: the panel closes, and the Mac's pending request is no longer polled (it expires server-side).
   6. Click the "+" header: the list, and clicking the Mac starts the same flow.
2. Visual check of the card at 1200×760 and of the code spacing.

## Concerns
- The UI is unverified at runtime: it is compiled on CI only (GPUI). Things to watch:
  - Focus hand-off when the panel opens from a sidebar click.
  - The tooltip on a disabled button.
  - Whether the overlay over the main area blocks pane clicks as intended. The sidebar stays clickable, so another machine can be requested; that cancels the current attempt.
- Cancel is local only. The core has no `pair.cancel`, so the server-side pairing stays pending until it expires, and the Mac may still show it. If it is approved later, nothing is saved, because the poll stopped. The invite is lost, and the user would retry.
- Links are loaded at startup and after our own saves. If Task 13b changes links.json from another path (e.g. enrolled = true), it should go through the same store and send `Cmd::LoadLinks`. A reload hook is easy to add but is unused now, so I left it out.
- Snapshots clone the Links on every command (every ~2 s while waiting). This is negligible.
- Offline machines are listed in the "+" list but cannot be clicked. The brief did not say whether to filter them.
- `/v2/machines` gave 404 rather than 401 (see Evidence).

## Files
- /Users/lehuuphu/Documents/myProjects/shellx-wt-l6/windows/shellx-app/src/ui/pairing.rs (new)
- /Users/lehuuphu/Documents/myProjects/shellx-wt-l6/windows/shellx-app/src/ui/{sidebar.rs, root.rs, mod.rs}
- /Users/lehuuphu/Documents/myProjects/shellx-wt-l6/windows/shellx-app/src/{pairing_service.rs, links_store.rs, shell_info.rs}
- /Users/lehuuphu/Documents/myProjects/shellx-wt-l6/windows/shellx-model/src/strings.rs
