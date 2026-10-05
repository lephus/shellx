# Terminal sharing P5 — mobile

Goal: the mobile app shows the computer's open terminals (spec §9, tests §11.5) on top of what P3 put in
`packages/shellx_client`. Only `apps/mobile` and the design file change; `shellx_client` stays as it is.

Spec: `docs/superpowers/specs/2026-10-01-desktop-terminal-sharing-design.md` §8, §9, §11.5.
Ledger notes: `docs/superpowers/ledgers/terminal-sharing.md` "Ghi cho P5".

## Files

- `docs/superpowers/design/2026-09-25-shellx-mobile-ui.html` — new section "Terminal trên máy tính".
- `apps/mobile/lib/core/backend/backend.dart`, `client_backend.dart` — port: `listSessions()` always asks
  for desktop terminals, `MachineSession.desktopSharing`, `TabHandle.kind/app/title`.
- `apps/mobile/lib/features/terminal/presentation/controllers/terminal_tab_controller.dart` — desktop kind,
  driver signal, `claimSize()`, new notices `desktopClosed` / `terminalGone`, reattach after `closed_by_host`.
- `.../controllers/terminal_workspace.dart` — `SessionListing` (sessions + `desktopSharing`), `prepare()`
  returns it, new `listForPicker()` for `+`.
- `.../controllers/terminal_page_controller.dart` — `pickable()` for `+`, `close()` reports a desktop detach.
- `.../widgets/session_picker.dart` — two groups, desktop rows, three hints.
- `.../pages/terminal_page.dart` — `+` flow, desktop tab chip, `×` without confirmation + toast, driver
  banner, tap to claim size, end cards.
- `apps/mobile/lib/l10n/intl_{vi,en}.arb` + regenerated `lib/shared/src/l10n.dart`, `intl/messages_*.dart`.
- Tests: `test/support/fakes.dart`, `test/core/backend/client_backend_test.dart`,
  `test/features/terminal/{terminal_tab_controller,terminal_workspace,terminal_page}_test.dart`,
  `test/l10n_test.dart`.

## Tasks

1. **Design file** — add the states (picker with two groups + the three hints, desktop tab with computer icon and
   banner, `×` toast, the three end cards) before any UI code. Commit `docs:`.
2. **Port** — `MachineSession.listSessions()` sends `includeDesktop: true`; `bool? get desktopSharing`;
   `TabHandle.kind/app/title`. Fakes gain the same fields. Test: client_backend adapter passes `desktop: true`
   (inspect the sealed `session.list` sent through the fake relay, or the fake contract) and exposes the fields.
3. **Tab controller** — `isDesktop`; label = OSC title ?? info title ?? app ?? `shell index`; `driver` signal
   (phone after any attach/reattach, follows `TabDriver`); `showDriverBanner` = desktop driver && live;
   `claimSize()` sends `resize` at the current size even when unchanged; typing while desktop drives claims once
   per `TabDriver(desktop)`; `TabExited` on a desktop tab → `desktopClosed`; `TabDetached(terminalGone)` →
   `terminalGone`; `TabDetached(closedByHost)` on a desktop tab → `closedByHost` with reattach; `session_not_found`
   on a desktop tab → `terminalGone`. Tests first in `terminal_tab_controller_test.dart`.
4. **Workspace + page controller** — `SessionListing`; `prepare()` returns it on the first visit; `pickable()`
   lists again and filters open tabs (for `+`). `close()` returns whether a desktop toast is due. Tests in
   `terminal_workspace_test.dart`.
5. **Copy** — vi + en ARB, `dart run intl_utils:generate`. l10n test checks the spec sentences.
6. **UI** — picker groups and hints, `+` → picker or new session, desktop chip (computer icon), `×` without
   confirmation + toast "Terminal vẫn chạy trên máy tính.", driver banner + tap/typing claim, end cards with only
   "Đóng tab" or "Gắn lại"/"Đóng tab". Widget tests in `terminal_page_test.dart` (§11.5 list).
7. **Gates** — `flutter analyze`, `flutter test` in `apps/mobile`; generated code fresh; report.
