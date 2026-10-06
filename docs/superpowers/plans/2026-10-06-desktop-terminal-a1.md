# ShellX Desktop A1 — Terminal Window Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** ShellX desktop becomes the computer's main terminal: one resizable window with vertical tabs on the left and an xterm terminal on the right, where every tab is a shell session the agent keeps, the same session the phone sees, and closing the window never kills a shell.

**Architecture:** One `SessionManager` (in `packages/shellx_agent`) is created once in `apps/desktop/lib/main.dart` (inside a small `SessionCore`) and outlives every relay runtime. The window reaches it only through the new in-process `LocalSessions` / `LocalSessionView` API (spec §3.1), so A5 can move it into a daemon later. Phones keep using `SessionRouter` → `AgentService` → relay with no protocol change. Stopping the runtime (sign-out, remote access off, network loss) only disconnects phones; only Quit kills shells. The UI is a Riverpod `TerminalTabs` notifier feeding one xterm `Terminal` per tab, a sidebar, and a pane; the old fixed-size pages become dialogs over that window.

**Tech Stack:** Dart ^3.11 / Flutter 3.41.4 (fvm), `package:test` + `fake_async` (agent), `flutter_test` (desktop), flutter_riverpod 3, window_manager 0.5.2, tray_manager 0.5, xterm **4.0.0** (exact), JetBrains Mono (SIL OFL), Swift (macOS runner), ARB l10n via `flutter gen-l10n`.

**Spec:** `docs/superpowers/specs/2026-10-06-desktop-terminal-a1-design.md` (binding; decisions D1–D16 are final). **UI design:** `docs/superpowers/design/2026-10-06-shellx-desktop-ui.md` (binding for every token, measurement, state, wireframe and string; cited below as "UI §N"). Executors read both before Task 1.

## Global Constraints

- The spec wins over everything else; the UI design doc wins for visuals and copy. Never invent a colour, size, duration or string: take it from the UI doc section the task names. Controller rulings (2026-10-06) accept all UI-doc recommendations as A1 scope: F6/Shift+F6 focus cycling, middle-click closes a tab, yellow eye mark while the phone drives, ⌘W on the empty state hides the window, macOS transparent title bar with traffic lights over the 38 px sidebar header + 28 px pane header, the phone-driving pill floats over the terminal (no resize), the exit line is written into the terminal, and the corrected `confirmSignOutBody` / `confirmRemoteOffBody` strings. The UI doc's "Follow-ups for mobile" (UI §7) are **not** in this plan.
- Toolchain: Flutter is `~/fvm/versions/3.41.4/bin/flutter`, Dart `~/fvm/versions/3.41.4/bin/dart` (the fvm default 3.38 is too old for `sdk: ^3.11.0`). Agent tests: `cd packages/shellx_agent && ~/fvm/versions/3.41.4/bin/dart test`. Desktop tests need dart on PATH: `cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test`. Format: `~/fvm/versions/3.41.4/bin/dart format --set-exit-if-changed <paths>` (default page width 80; no package overrides it). Analyze: `PATH=~/fvm/versions/3.41.4/bin:$PATH flutter analyze` in `apps/desktop`, `~/fvm/versions/3.41.4/bin/dart analyze` in `packages/shellx_agent`.
- No change to `packages/shellx_core` (spec D3: `proto` unchanged), `apps/mobile`, `relay/`, `web/`, `term/`. No shared UI package (copy what desktop needs from mobile).
- `xterm: 4.0.0` pinned **exactly** in `apps/desktop/pubspec.yaml` with a comment, same version as mobile (D12).
- Limits: `SessionManager.maxSessions` default **32** (D8); ring buffer 256 KiB per session (unchanged); each tab's xterm `Terminal(maxLines: 10000)` (spec §3.2).
- Terminal font: JetBrains Mono 13 default, steps of 1, clamp 9–28, ⌘0 → 13, persisted (UI §1.3; the UI doc's clamp refines spec "13 mặc định").
- Window: min 640×400, default 1100×720, bounds remembered (spec §3.2 / UI §2).
- Shortcuts (spec criterion 2): macOS ⌘T, ⌘W, ⌘1…⌘9, ⌃Tab / ⌃⇧Tab, ⌘C (only with a selection), ⌘V, ⌘+ / ⌘− / ⌘0; Windows Ctrl+Shift+T/W, Ctrl+Shift+C/V, Ctrl+Tab / Ctrl+Shift+Tab; F6 / Shift+F6 on both (UI §3.6).
- l10n: every new UI string goes into **both** `apps/desktop/lib/l10n/app_en.arb` (with `@key` metadata for placeholders) and `app_vi.arb` with identical keys (`test/l10n/l10n_test.dart` enforces it), then `cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter gen-l10n`; generated `lib/l10n/app_localizations*.dart` are committed.
- New persisted settings keys must be added to `SettingKeys.all` (it is the shared_preferences allow-list; a missing key silently fails to persist).
- Logging: `debugPrint` with `error.runtimeType` only — never terminal output, input, titles, tokens or paths.
- Code style: match the surrounding code (doc comments that say *why*, `final class`, no `print`). Every task ends with its own tests green, `dart format --set-exit-if-changed` clean on touched files, analyzer clean, and a commit with a conventional message (`feat(agent): …`, `feat(desktop): …`, `test(desktop): …`, `docs: …`). Commit only the files the task lists (another agent works on `main` concurrently: never `git add -A`).

## Review Focus

1. **Phone and desktop typing into the same tab at the same moment** — both keystroke streams must reach the shell in arrival order, nobody gets `session.detached`, and the PTY must not be resized on every keystroke (each resize redraws full-screen programs). Pinned by the driver-hold tests in Task 2 (`interleaved typing from both sides …`).
2. **Window hidden (or tab not selected) while a command floods output** (`yes`, `cat` of a 50 MB file) — the UI must keep painting frames, desktop memory must stay bounded, and reopening shows the latest output. Pinned by the `TerminalFeed` budget/cap tests in Task 5 and measured by the benchmark in Task 9.
3. **Quitting with open tabs or a running command** (⌘Q from the macOS app menu, tray "Thoát", ⌘Q while a dialog is open) — exactly one confirmation, then every shell tree is killed and the app exits; macOS log-out/shut-down must not be blocked by ShellX. Pinned by the `quitRequested` tests in Task 7 and the shutdown test in Task 3.
4. **Using the terminal signed out, and signing out / turning remote access off while tabs run** — no login dialog forced at startup, the signed-out strip shows, and every shell keeps running with its output. Pinned by Task 3 (controller/runtime keep shells) and Task 6/7 (strip, no forced dialog).
5. **A shell ends while its tab is not selected, or is closed from the phone** — exit 0 closes that tab silently without changing the selected tab; non-zero writes the exit line into *that* tab's buffer; a tab closed by request (⌘W, phone, revoke) disappears instead of showing "exited with code -15". Pinned by `TerminalTabs` tests in Task 5.

---

## File Structure

| File | Responsibility |
|---|---|
| Modify `packages/shellx_agent/lib/src/session/session_manager.dart` | Origin, title, driver (+1 s hold), runningCommand, desktop-origin `open()`, phone close = detach for desktop-origin, `disconnectAllPhones`, `receivesDriver`, 32 limit; `LocalSessions` implementation (`view`, `close`, `_LocalView`) |
| Create `packages/shellx_agent/lib/src/session/local_sessions.dart` | `LocalSessions`, `LocalSessionView` interfaces, `SessionLimitException`, `SpawnFailedException` |
| Modify `packages/shellx_agent/lib/src/session/session_stream.dart` | `buffered` (backlog bytes) |
| Modify `packages/shellx_agent/lib/src/session/session_router.dart` | Wires `receivesDriver` to the `desktop: true` set; `disconnectAllPhones`; `dispose` |
| Modify `packages/shellx_agent/lib/src/notify/command_tracker.dart` | `running` getter |
| Modify `packages/shellx_agent/lib/shellx_agent.dart` | Export `local_sessions.dart` |
| Modify `packages/shellx_agent/test/support/session_rig.dart` | Clock, driver hold, `receivesDriver` |
| Create `packages/shellx_agent/test/session/session_unified_test.dart`, `test/session/local_sessions_test.dart` | Agent tests |
| Create `apps/desktop/lib/src/agent/session_core.dart` | Builds the process's one `SessionManager` + `AgentNotifications` + id allocator |
| Modify `apps/desktop/lib/src/agent/agent_runtime.dart` | `CoreAgentRuntime` takes `SessionCore`; stop disconnects phones; interface loses shell-session members |
| Modify `apps/desktop/lib/src/agent/desktop_services.dart`, `agent_controller.dart`, `lib/main.dart` | One `SessionManager` per process; Quit kills, the rest keeps |
| Create `apps/desktop/lib/src/terminal/terminal_input.dart`, `desktop_terminal.dart`, `terminal_style.dart`, `terminal_feed.dart`, `terminal_tabs.dart`, `terminal_font_size.dart`, `local_sessions_provider.dart` | Terminal model layer (no widgets) |
| Create `apps/desktop/lib/src/ui/theme/shellx_desktop_theme.dart`, `ui/theme/terminal_colors.dart` | UI §1 tokens; mobile terminal palette copy |
| Create `apps/desktop/lib/src/ui/terminal/terminal_workspace_page.dart`, `session_sidebar.dart`, `session_tab_row.dart`, `terminal_pane.dart`, `terminal_overlays.dart`, `close_tab.dart`, `terminal_shortcuts.dart` | Terminal window UI |
| Create `apps/desktop/lib/src/ui/dialogs/route_dialog.dart` | Legacy routes and confirms as dialogs (UI §4) |
| Modify `apps/desktop/lib/src/ui/app.dart`, `window_router.dart`, `window_host.dart`, `window_coordinator.dart`, `activation.dart`, `lib/src/platform/app_reopen.dart`, `lib/src/platform/settings_store.dart` | Window shell (D9–D11) |
| Modify `apps/desktop/lib/src/tray/tray_action.dart`, `tray_menu.dart`, `tray_actions.dart` | "Mở cửa sổ terminal", remote-off confirm |
| Modify `apps/desktop/macos/Runner/AppDelegate.swift`, `MainFlutterWindow.swift` | Activation policy, `quitRequested`, power-off pass-through |
| Modify `apps/desktop/pubspec.yaml`; create `apps/desktop/assets/fonts/JetBrainsMono-*.ttf`, `assets/licenses/JetBrainsMono-OFL.txt`, `apps/desktop/dart_test.yaml` | Deps, fonts, benchmark tag |
| Modify `apps/desktop/lib/l10n/app_en.arb`, `app_vi.arb` (+ generated) | Strings (UI §5) |
| Create/modify desktop tests under `apps/desktop/test/` (listed per task) | |
| Modify `docs/superpowers/specs/2026-09-25-shellx-v1-design.md`, `docs/superpowers/HANDOFF.md` | Amendment notes, manual checklist |

---

### Task 1: Agent — one kind of session for desktop and phone

Every shellx session gets an `origin`, a `title`, a `driver` and `runningCommand`; the computer can open sessions itself (`open`); a phone's `session.close` on a desktop-origin session only detaches it (D4); `disconnectAllPhones` (D7); the limit becomes 32 (D8); `session.driver` goes only to phones that sent `session.list {desktop: true}`.

**Files:**
- Create: `packages/shellx_agent/lib/src/session/local_sessions.dart` (exceptions only in this task)
- Modify: `packages/shellx_agent/lib/src/session/session_manager.dart` (whole file replaced, below)
- Modify: `packages/shellx_agent/lib/src/session/session_router.dart:21-130`
- Modify: `packages/shellx_agent/lib/src/notify/command_tracker.dart:36-46`
- Modify: `packages/shellx_agent/lib/shellx_agent.dart`
- Modify: `packages/shellx_agent/test/support/session_rig.dart`
- Create: `packages/shellx_agent/test/session/session_unified_test.dart`
- Modify: `packages/shellx_agent/test/session/session_router_test.dart` (append tests)

**Interfaces:**
- Consumes: existing `SessionManager`, `SessionStream`, `OscTitleParser` (`term/osc_title.dart`), `OscEventParser` + `CommandTracker` (`notify/`), `DriverSide`, `SessionDriver`, `SessionDetached`, `DetachReason.closedByHost` (shellx_core).
- Produces (later tasks rely on these exact names):
  - `enum SessionOrigin { desktop, phone }`
  - `SessionSummary` gains `final SessionOrigin origin` (default `SessionOrigin.phone`), `final String title` (default `''`), `final DriverSide driver` (default `DriverSide.phone`), `final bool runningCommand` (default `false`), getter `bool get phoneAttached`.
  - `SessionManager({..., int maxSessions = 32, Duration driverHold = const Duration(seconds: 1), DateTime Function()? clock, bool Function(String mobileId)? receivesDriver, ...})`
  - `bool Function(String mobileId) receivesDriver` (public, mutable field)
  - `Future<int> SessionManager.open({required int cols, required int rows})` — throws `SessionLimitException` / `SpawnFailedException`
  - `void SessionManager.disconnectAllPhones()`
  - `final class SessionLimitException implements Exception { const SessionLimitException(this.max); final int max; }`
  - `final class SpawnFailedException implements Exception { const SpawnFailedException(this.message); final String message; }`
  - `bool CommandTracker.running`
  - `void SessionRouter.disconnectAllPhones()`, `void SessionRouter.dispose()`

- [ ] **Step 1: Extend the test rig**

Replace `packages/shellx_agent/test/support/session_rig.dart` lines 12–32 (the class header and constructor) with:

```dart
/// A [SessionManager] over [FakePtyFactory] that records every outbound
/// message. [now] is the manager's clock (driver hold, createdAt).
final class SessionRig {
  SessionRig({
    int maxSessions = 10,
    int bufferCapacity = 256 * 1024,
    int sendWindow = 256 * 1024,
    Duration driverHold = const Duration(seconds: 1),
    Random? random,
  }) {
    manager = SessionManager(
      ptyFactory: factory,
      shellResolver: const FixedShellResolver(),
      homeDirectory: '/Users/test',
      baseEnvironment: const {'PATH': '/usr/bin'},
      maxSessions: maxSessions,
      bufferCapacity: bufferCapacity,
      sendWindow: sendWindow,
      driverHold: driverHold,
      clock: () => now,
      random: random ?? Random(1),
    );
    manager.outbound.listen(sent.add);
  }

  DateTime now = DateTime(2026, 10, 6, 9);
```

(keep the remaining members `factory`, `manager`, `sent`, `to`, `open`, `pty`, `clear` unchanged; `maxSessions = 10` stays the rig default so the existing "11th session" test keeps its meaning).

- [ ] **Step 2: Write the failing tests**

Create `packages/shellx_agent/test/session/session_unified_test.dart`:

```dart
import 'dart:convert';

import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:test/test.dart';

import '../support/fake_pty.dart';
import '../support/session_rig.dart';

const String esc = '\x1b';
const String bel = '\x07';

void main() {
  test('the default limit is 32 sessions (D8)', () async {
    final factory = FakePtyFactory();
    final manager = SessionManager(
      ptyFactory: factory,
      shellResolver: const FixedShellResolver(),
      homeDirectory: '/Users/test',
      baseEnvironment: const {},
    );
    for (var i = 0; i < 32; i++) {
      await manager.open(cols: 80, rows: 24);
    }
    await expectLater(
      manager.open(cols: 80, rows: 24),
      throwsA(isA<SessionLimitException>().having((e) => e.max, 'max', 32)),
    );
    expect(manager.sessions, hasLength(32));
  });

  test('a phone-opened session has origin phone and the phone drives', () async {
    final rig = SessionRig();
    await rig.open(phone);
    final summary = rig.manager.sessions.single;
    expect(summary.origin, SessionOrigin.phone);
    expect(summary.driver, DriverSide.phone);
    expect(summary.phoneAttached, isTrue);
    expect(summary.title, '');
    expect(summary.runningCommand, isFalse);
  });

  test('open() starts a desktop session nobody is attached to', () async {
    final rig = SessionRig();
    var changes = 0;
    var opened = 0;
    rig.manager.changes.listen((_) => changes++);
    rig.manager.opened.listen((_) => opened++);

    final id = await rig.manager.open(cols: 120, rows: 40);
    await pumpEventQueue();

    final summary = rig.manager.sessions.single;
    expect(summary.id, id);
    expect(summary.index, 1);
    expect(summary.origin, SessionOrigin.desktop);
    expect(summary.driver, DriverSide.desktop);
    expect(summary.attachedMobileId, isNull);
    expect((rig.pty(0).initialCols, rig.pty(0).initialRows), (120, 40));
    expect(rig.pty(0).workingDirectory, '/Users/test');
    expect(changes, greaterThan(0));
    expect(opened, 0); // Only phones produce "<phone> opened a session".
    expect(rig.sent, isEmpty);
    // Listed to phones like any shellx session (D3).
    expect(rig.manager.sessionInfos.single.kind, SessionKind.shellx);
  });

  test('open() reports a spawn failure as SpawnFailedException', () async {
    final rig = SessionRig();
    rig.factory.failWith = StateError('no pty');
    await expectLater(
      rig.manager.open(cols: 80, rows: 24),
      throwsA(
        isA<SpawnFailedException>().having(
          (e) => e.message,
          'message',
          contains('no pty'),
        ),
      ),
    );
    expect(rig.manager.sessions, isEmpty);
  });

  test('OSC 0 and OSC 2 titles are tracked for shellx sessions (D13)', () async {
    final rig = SessionRig();
    await rig.manager.open(cols: 80, rows: 24);
    var changes = 0;
    rig.manager.changes.listen((_) => changes++);

    rig.pty(0).emit('$esc]0;vim notes.md$bel');
    await pumpEventQueue();
    expect(rig.manager.sessions.single.title, 'vim notes.md');
    expect(changes, 1);

    rig.pty(0).emit('$esc]2;htop$esc\\');
    await pumpEventQueue();
    expect(rig.manager.sessions.single.title, 'htop');

    rig.pty(0).emit('plain output');
    await pumpEventQueue();
    expect(changes, 2); // No change event for output without a new title.
  });

  test('runningCommand is true between OSC 133;C and 133;D (D15)', () async {
    final rig = SessionRig();
    await rig.manager.open(cols: 80, rows: 24);
    expect(rig.manager.sessions.single.runningCommand, isFalse);

    rig.pty(0).emit('$esc]133;C$bel');
    await pumpEventQueue();
    expect(rig.manager.sessions.single.runningCommand, isTrue);

    rig.pty(0).emit('$esc]133;D;0$bel');
    await pumpEventQueue();
    expect(rig.manager.sessions.single.runningCommand, isFalse);
  });

  group('phones and desktop-origin sessions (D4)', () {
    test('session.close from the phone detaches, never kills', () async {
      final rig = SessionRig();
      final id = await rig.manager.open(cols: 80, rows: 24);
      await rig.manager.handle(
        phone,
        SessionAttach(id: id, cols: 50, rows: 20, lastSeq: 0),
      );
      rig.clear();

      await rig.manager.handle(phone, SessionClose(id: id));

      expect(rig.pty(0).killed, isFalse);
      expect(rig.to(phone), [
        SessionDetached(id: id, reason: DetachReason.closedByHost),
      ]);
      expect(rig.manager.sessions.single.attachedMobileId, isNull);
    });

    test('session.close from a phone that is not attached does nothing', () async {
      final rig = SessionRig();
      final id = await rig.manager.open(cols: 80, rows: 24);
      await rig.manager.handle(tablet, SessionClose(id: id));
      expect(rig.pty(0).killed, isFalse);
      expect(rig.to(tablet), isEmpty);
    });

    test('session.close on a session the phone opened still kills it', () async {
      final rig = SessionRig();
      final id = await rig.open(phone);
      await rig.manager.handle(phone, SessionClose(id: id));
      expect(rig.pty(0).killed, isTrue);
    });

    test('revoke kills what the phone opened, only detaches desktop-origin '
        'sessions', () async {
      final rig = SessionRig();
      final mine = await rig.manager.open(cols: 80, rows: 24);
      await rig.open(phone);
      await rig.manager.handle(
        phone,
        SessionAttach(id: mine, cols: 50, rows: 20, lastSeq: 0),
      );
      rig.clear();

      rig.manager.closeSessionsAttachedTo(phone);
      await pumpEventQueue();

      expect(rig.pty(0).killed, isFalse);
      expect(rig.pty(1).killed, isTrue);
      expect(
        rig.to(phone),
        contains(SessionDetached(id: mine, reason: DetachReason.closedByHost)),
      );
    });

    test('a revoke never voids a desktop open still spawning', () async {
      final rig = SessionRig();
      final opening = rig.manager.open(cols: 80, rows: 24);
      rig.manager.closeSessionsAttachedTo(phone);
      await opening;
      expect(rig.pty(0).killed, isFalse);
      expect(rig.manager.sessions, hasLength(1));
    });

    test('closeAll voids a desktop open still spawning', () async {
      final rig = SessionRig();
      final opening = rig.manager.open(cols: 80, rows: 24);
      rig.manager.closeAll();
      await expectLater(opening, throwsA(isA<SpawnFailedException>()));
      expect(rig.pty(0).killed, isTrue);
      expect(rig.manager.sessions, isEmpty);
    });
  });

  group('driver (D6)', () {
    test('attaching makes the phone the driver; session.driver goes only to '
        'phones that listed with desktop: true', () async {
      final rig = SessionRig();
      rig.manager.receivesDriver = {phone}.contains;
      final a = await rig.manager.open(cols: 100, rows: 30);
      final b = await rig.manager.open(cols: 100, rows: 30);

      await rig.manager.handle(
        phone,
        SessionAttach(id: a, cols: 50, rows: 20, lastSeq: 0),
      );
      await rig.manager.handle(
        tablet,
        SessionAttach(id: b, cols: 60, rows: 20, lastSeq: 0),
      );

      expect(
        rig.to(phone),
        contains(SessionDriver(id: a, by: DriverSide.phone)),
      );
      expect(rig.to(tablet).whereType<SessionDriver>(), isEmpty);
      expect(rig.manager.sessions.first.driver, DriverSide.phone);
      expect(rig.pty(0).resizes.last, (50, 20));
    });

    test('when the phone leaves, the desktop drives at its own size again', () async {
      final rig = SessionRig();
      final id = await rig.manager.open(cols: 100, rows: 30);
      await rig.manager.handle(
        phone,
        SessionAttach(id: id, cols: 50, rows: 20, lastSeq: 0),
      );
      expect(rig.pty(0).resizes.last, (50, 20));

      rig.manager.mobileDisconnected(phone);

      expect(rig.manager.sessions.single.driver, DriverSide.desktop);
      expect(rig.pty(0).resizes.last, (100, 30));
    });

    test('a phone-origin session nobody resized locally keeps its size when '
        'the phone leaves', () async {
      final rig = SessionRig();
      await rig.open(phone, cols: 50, rows: 20);
      rig.manager.mobileDisconnected(phone);
      expect(rig.manager.sessions.single.driver, DriverSide.desktop);
      expect(rig.pty(0).resizes, isEmpty);
    });
  });

  test('disconnectAllPhones detaches every phone and kills nothing (D7)', () async {
    final rig = SessionRig();
    final mine = await rig.manager.open(cols: 80, rows: 24);
    final theirs = await rig.open(phone);
    await rig.manager.handle(
      tablet,
      SessionAttach(id: mine, cols: 50, rows: 20, lastSeq: 0),
    );
    rig.clear();

    rig.manager.disconnectAllPhones();

    expect(rig.pty(0).killed, isFalse);
    expect(rig.pty(1).killed, isFalse);
    expect(rig.to(phone), [
      SessionDetached(id: theirs, reason: DetachReason.closedByHost),
    ]);
    expect(rig.to(tablet), [
      SessionDetached(id: mine, reason: DetachReason.closedByHost),
    ]);
    expect(
      rig.manager.sessions.map((s) => s.attachedMobileId),
      everyElement(isNull),
    );
    // Output keeps buffering for whoever attaches next; nobody is sent it.
    rig.pty(0).emitBytes(utf8.encode('still here'));
    await pumpEventQueue();
    expect(rig.sent, hasLength(2));
  });

  test('SessionSummary.phoneAttached follows attachedMobileId', () {
    final summary = SessionSummary(
      id: 1,
      index: 1,
      shell: 'zsh',
      createdAt: DateTime(2026),
      attachedMobileId: null,
    );
    expect(summary.phoneAttached, isFalse);
    expect(summary.origin, SessionOrigin.phone);
  });
}
```

Append to `packages/shellx_agent/test/session/session_router_test.dart`, inside `main()` (after the last test):

```dart
  test('only phones that listed with desktop: true get session.driver', () {
    fakeAsync((async) {
      final rig = _Rig();
      rig.router.handle(phone, const SessionList(desktop: true));
      rig.router.handle(tablet, const SessionList());
      rig.shells.open(cols: 100, rows: 30).ignore();
      async.flushMicrotasks();
      final opened = rig.shells.sessions.single.id;
      expect(rig.shells.receivesDriver(phone), isTrue);
      expect(rig.shells.receivesDriver(tablet), isFalse);
      rig.router.handle(
        phone,
        SessionAttach(id: opened, cols: 50, rows: 20, lastSeq: 0),
      );
      async.flushMicrotasks();
      expect(
        rig.to(phone),
        contains(SessionDriver(id: opened, by: DriverSide.phone)),
      );
    });
  });

  test('disconnectAllPhones reaches both managers and kills nothing', () {
    fakeAsync((async) {
      final rig = _Rig();
      rig.router.handle(phone, const SessionList(desktop: true));
      rig.router.handle(phone, const SessionOpen(cols: 80, rows: 24));
      rig.window(1);
      async.flushMicrotasks();
      final desktopId = rig.desktop.sessions.single.id;
      rig.router.handle(
        phone,
        SessionAttach(id: desktopId, cols: 50, rows: 20, lastSeq: 0),
      );
      async.flushMicrotasks();

      rig.router.disconnectAllPhones();

      expect(rig.ptys.ptys.single.killed, isFalse);
      expect(rig.shells.sessions.single.attachedMobileId, isNull);
      expect(rig.desktop.sessions.single.attachedMobileId, isNull);
    });
  });

  test('dispose stops forwarding and unwires receivesDriver', () {
    fakeAsync((async) {
      final rig = _Rig();
      rig.router.handle(phone, const SessionList(desktop: true));
      async.flushMicrotasks();
      rig.sent.clear();
      rig.router.dispose();
      async.flushMicrotasks();
      expect(rig.shells.receivesDriver(phone), isFalse);
      rig.shells.handle(phone, const SessionList());
      async.flushMicrotasks();
      expect(rig.sent, isEmpty);
    });
  });
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `cd packages/shellx_agent && ~/fvm/versions/3.41.4/bin/dart test test/session/session_unified_test.dart test/session/session_router_test.dart`
Expected: compile errors — `SessionOrigin`, `open`, `SessionLimitException`, `receivesDriver`, `driverHold`, `clock`, `disconnectAllPhones`, `dispose` are not defined.

- [ ] **Step 4: Add `CommandTracker.running`**

In `packages/shellx_agent/lib/src/notify/command_tracker.dart`, after the `_startedAt` field (line 38) add:

```dart
  /// A command started (`133;C`) and has not ended (`133;D`) yet. The
  /// desktop asks before closing such a tab (A1 D15).
  bool get running => _startedAt != null;
```

- [ ] **Step 5: Create `local_sessions.dart` with the exceptions**

```dart
// packages/shellx_agent/lib/src/session/local_sessions.dart

/// The computer already has the maximum number of sessions (A1 D8).
final class SessionLimitException implements Exception {
  const SessionLimitException(this.max);
  final int max;
  @override
  String toString() => 'SessionLimitException: $max sessions are open';
}

/// The shell could not be started. [message] is the underlying error as
/// text (it never contains terminal output).
final class SpawnFailedException implements Exception {
  const SpawnFailedException(this.message);
  final String message;
  @override
  String toString() => 'SpawnFailedException: $message';
}
```

Add `export 'src/session/local_sessions.dart';` to `packages/shellx_agent/lib/shellx_agent.dart` right after the `agent_sessions.dart` export.

- [ ] **Step 6: Replace `session_manager.dart`**

Replace the whole of `packages/shellx_agent/lib/src/session/session_manager.dart` with:

```dart
import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:shellx_core/shellx_core.dart';

import '../notify/agent_notifications.dart';
import '../notify/command_tracker.dart';
import '../notify/osc_event_parser.dart';
import '../pty/pty.dart';
import '../pty/session_environment.dart';
import '../pty/shell_integration.dart';
import '../pty/shell_resolver.dart';
import '../term/osc_title.dart';
import 'agent_sessions.dart';
import 'local_sessions.dart';
import 'session_ids.dart';
import 'session_stream.dart';

/// Who opened a session (A1 D4): the desktop may close any session, a
/// phone may only end the sessions it opened.
enum SessionOrigin { desktop, phone }

/// Read-only view of a session for the tray menu and the terminal window.
final class SessionSummary {
  const SessionSummary({
    required this.id,
    required this.index,
    required this.shell,
    required this.createdAt,
    required this.attachedMobileId,
    this.origin = SessionOrigin.phone,
    this.title = '',
    this.driver = DriverSide.phone,
    this.runningCommand = false,
  });
  final int id, index;
  final String shell;
  final DateTime createdAt;
  final String? attachedMobileId;
  final SessionOrigin origin;

  /// Latest OSC 0/2 title; empty until the shell sets one (A1 D13).
  final String title;

  /// Whose size the PTY follows right now (A1 D6).
  final DriverSide driver;

  /// Between OSC 133;C and 133;D (needs the ShellX shell hook, A1 D15).
  final bool runningCommand;

  bool get phoneAttached => attachedMobileId != null;
}

const int _minDimension = 1;
const int _maxDimension = 1000;

const Duration _outputDrainGrace = Duration(seconds: 2);

/// How long a session whose shell has exited waits for the send window to
/// clear before giving up on the blocked tail and delivering
/// `session.exited` anyway.
const Duration _drainTimeout = Duration(seconds: 30);

int _clampDimension(int value) => value.clamp(_minDimension, _maxDimension);

bool _noPhoneReceivesDriver(String mobileId) => false;

final class _Session {
  _Session({
    required this.id,
    required this.index,
    required this.shell,
    required this.createdAt,
    required this.pty,
    required this.stream,
    required this.cols,
    required this.rows,
    required this.origin,
    required this.driver,
  });

  final int id;
  final int index;
  final String shell;
  final DateTime createdAt;
  final Pty pty;
  final SessionStream stream;
  final SessionOrigin origin;

  /// The PTY's current size.
  int cols;
  int rows;

  /// Whose size the PTY follows (A1 D6).
  DriverSide driver;

  /// The attached phone's size; null while no phone is attached.
  int? phoneCols, phoneRows;

  /// The window's size for this session; null until the window sized it.
  int? localCols, localRows;

  /// Last keystroke from each side, for the driver hold.
  DateTime? lastPhoneInput, lastLocalInput;

  final titles = OscTitleParser();
  String title = '';
  final commandEvents = OscEventParser();
  final commands = CommandTracker(threshold: () => null);

  /// The session ends because someone closed it (desktop, phone, revoke,
  /// quit), not because the shell exited on its own.
  bool killedOnRequest = false;

  /// Completes with the shell's exit code (A1 `LocalSessionView.exitCode`).
  final exit = Completer<int>();

  /// Live output for local viewers (A1 §3.1: no ack, no send window).
  final local = StreamController<Uint8List>.broadcast(sync: true);

  /// Driver changes for local viewers.
  final drivers = StreamController<DriverSide>.broadcast(sync: true);

  String? get attachedMobileId => stream.attachedMobileId;
  set attachedMobileId(String? value) => stream.attachedMobileId = value;

  /// Phone that still gets `session.exited` after a `closed_by_host` detach.
  String? exitRecipient;

  /// True once the session is being torn down: a host-initiated close set
  /// this immediately, or the shell has already exited. A closing session
  /// rejects new `session.attach` calls and is hidden from listings, but
  /// stays in the manager (routing acks) until [_finish] removes it.
  bool closing = false;

  /// The shell's exit code, known once the process has actually exited.
  int? finishedExitCode;

  /// Bounds how long a closing session waits for the send window to clear
  /// before [_finish] runs anyway (see [_drainTimeout]).
  Timer? drainTimer;

  /// True as soon as [Pty.exitCode] has completed. From then on the pty is
  /// never killed, written to or resized again: its process id may already
  /// belong to another process (a tree kill would hit the wrong tree).
  bool exited = false;

  StreamSubscription<Uint8List>? output;

  /// Push notifications from this session's output (null when off).
  SessionNotifier? notifier;

  void write(Uint8List data) {
    if (!exited) pty.write(data);
  }

  void resize(int cols, int rows) {
    if (!exited) pty.resize(cols, rows);
  }

  void kill() {
    if (!exited) pty.kill();
  }
}

/// Owns every terminal session of the agent (spec v1 §6.5 and §7; A1 §3.1).
/// Created once per process (A1 D7): it outlives every relay connection.
///
/// Session ids come from [nextId]; by default a private `sessionIdAllocator`
/// (random start in [1, 2^31) from [random], default `Random.secure()`, then
/// +1), so a phone re-attaching after an agent restart cannot land on a new
/// session that reuses its old id (spec §6.4). `index` is still 1..n.
final class SessionManager implements AgentSessions {
  SessionManager({
    required PtyFactory ptyFactory,
    required ShellResolver shellResolver,
    required String homeDirectory,
    required Map<String, String> baseEnvironment,
    int maxSessions = 32,
    int bufferCapacity = 256 * 1024,
    int sendWindow = 256 * 1024,
    Duration driverHold = const Duration(seconds: 1),
    DateTime Function()? clock,
    bool Function(String mobileId)? receivesDriver,
    Random? random,
    int Function()? nextId,
    AgentNotifications? notifications,
    ShellIntegration? shellIntegration,
  }) : _ptyFactory = ptyFactory,
       _notifications = notifications,
       _shellIntegration = shellIntegration,
       _shellResolver = shellResolver,
       _homeDirectory = homeDirectory,
       _baseEnvironment = baseEnvironment,
       _maxSessions = maxSessions,
       _bufferCapacity = bufferCapacity,
       _sendWindow = sendWindow,
       _driverHold = driverHold,
       _clock = clock ?? DateTime.now,
       receivesDriver = receivesDriver ?? _noPhoneReceivesDriver,
       _nextId = nextId ?? sessionIdAllocator(random ?? Random.secure());

  final PtyFactory _ptyFactory;
  final ShellResolver _shellResolver;
  final String _homeDirectory;
  final Map<String, String> _baseEnvironment;
  final int _maxSessions;
  final int _bufferCapacity;
  final int _sendWindow;
  final AgentNotifications? _notifications;

  /// While one side typed less than this ago, a keystroke from the other
  /// side is written but does not take the driver (and the PTY size) away:
  /// two people typing at once must not resize the PTY on every key.
  final Duration _driverHold;
  final DateTime Function() _clock;

  /// Whether [mobileId] understands `session.driver` (it sent
  /// `session.list {desktop: true}`). `SessionRouter` sets this; an old app
  /// never gets a message its decoder rejects (spec §7.9).
  bool Function(String mobileId) receivesDriver;

  /// Starts zsh/bash/PowerShell with the push-notification hook (spec
  /// §4.4); null starts the resolved shell unchanged.
  final ShellIntegration? _shellIntegration;

  final _outbound = StreamController<OutboundMessage>.broadcast(sync: true);
  final _changes = StreamController<void>.broadcast();
  final _opened = StreamController<SessionOpenedEvent>.broadcast();
  final _sessions = <int, _Session>{};
  final int Function() _nextId;
  int _pendingOpens = 0;

  /// Bumped by [closeAll] and [closeSessionsAttachedTo] so a phone's open
  /// that is still awaiting [_shellResolver] can tell it was told to tear
  /// down in the meantime and kill the pty instead of registering it.
  int _epoch = 0;

  /// Bumped by [closeAll] only: a revoke never voids a window's open.
  int _closeAllEpoch = 0;

  /// Messages to deliver, in order. A synchronous broadcast stream: a
  /// listener must not call back into the manager (e.g. `handle`)
  /// synchronously from its callback. [_pump] tolerates this (it updates
  /// its own bookkeeping before each send), but other callers are not
  /// guaranteed to be reentrant-safe.
  @override
  Stream<OutboundMessage> get outbound => _outbound.stream;

  /// Fires whenever the session list, an attachment, a title, a driver or
  /// a running command changes.
  Stream<void> get changes => _changes.stream;

  @override
  Stream<SessionOpenedEvent> get opened => _opened.stream;

  List<SessionSummary> get sessions => [
    for (final s in _sessions.values)
      if (!s.closing)
        SessionSummary(
          id: s.id,
          index: s.index,
          shell: s.shell,
          createdAt: s.createdAt,
          attachedMobileId: s.attachedMobileId,
          origin: s.origin,
          title: s.title,
          driver: s.driver,
          runningCommand: s.commands.running,
        ),
  ];

  /// Listable sessions, as `session.list.result` entries.
  List<SessionInfo> get sessionInfos => [
    for (final s in _sessions.values)
      if (!s.closing)
        SessionInfo(
          id: s.id,
          index: s.index,
          shell: s.shell,
          createdAt: s.createdAt.millisecondsSinceEpoch,
          attached: s.attachedMobileId != null,
        ),
  ];

  /// Handles one decrypted message from phone [mobileId].
  @override
  Future<void> handle(String mobileId, AppMessage message) async {
    switch (message) {
      case SessionList():
        _send(mobileId, SessionListResult(sessionInfos));
      case SessionOpen(:final cols, :final rows):
        await _open(mobileId, cols, rows);
      case SessionAttach(:final id, :final cols, :final rows, :final lastSeq):
        _attach(mobileId, id, cols, rows, lastSeq);
      case InputMessage(:final id, :final data):
        final session = _attachedTo(mobileId, id);
        if (session == null) return;
        _phoneActive(session, input: true);
        session.write(data);
      case ResizeMessage(:final id, :final cols, :final rows):
        final session = _attachedTo(mobileId, id);
        if (session == null) return;
        session.phoneCols = _clampDimension(cols);
        session.phoneRows = _clampDimension(rows);
        _phoneActive(session, input: false);
      case AckMessage(:final id, :final seq):
        final session = _attachedTo(mobileId, id);
        if (session == null) return;
        session.stream.ack(seq);
        _pump(session);
      case SessionClose(:final id):
        final session = _sessions[id];
        if (session == null) {
          _notFound(mobileId, id);
          return;
        }
        if (session.origin == SessionOrigin.desktop) {
          // A1 D4: a phone never ends a terminal opened on this computer.
          if (session.attachedMobileId == mobileId && !session.closing) {
            _send(
              mobileId,
              SessionDetached(id: id, reason: DetachReason.closedByHost),
            );
            _phoneLeft(session);
            _changes.add(null);
          }
          return;
        }
        session.killedOnRequest = true;
        session.kill();
      default:
        // pair.confirm is handled by AgentService; agent→phone types are
        // never accepted from a phone.
        break;
    }
  }

  /// The channel to [mobileId] is gone: its sessions become unattached
  /// (no message is sent). A session that was already draining after its
  /// shell exited (spec: no attached phone) finishes immediately instead of
  /// waiting out the send window or the drain timeout.
  @override
  void mobileDisconnected(String mobileId) {
    var changed = false;
    for (final session in _sessions.values.toList()) {
      final wasAttached = session.attachedMobileId == mobileId;
      if (wasAttached) {
        _phoneLeft(session);
        changed = true;
      }
      if (session.exitRecipient == mobileId) session.exitRecipient = null;
      if (wasAttached && session.closing) _finish(session);
    }
    if (changed) _changes.add(null);
  }

  /// [mobileId] was revoked: the sessions it opened and is attached to are
  /// killed; a desktop-origin session it is attached to only loses it
  /// (`closed_by_host`, A1 D4).
  ///
  /// Precondition: no `session.open` from a phone is pending (awaiting the
  /// shell resolver). The epoch bump is global for phone opens, so it would
  /// also void an open in flight for another phone. AgentService guarantees
  /// this: it calls this from its inbox, which awaits every [handle] call.
  /// A window's [open] is never voided by a revoke.
  @override
  void closeSessionsAttachedTo(String mobileId) {
    _epoch++;
    var changed = false;
    for (final session in _sessions.values.toList()) {
      if (session.attachedMobileId != mobileId) continue;
      if (session.origin == SessionOrigin.phone) {
        session.killedOnRequest = true;
        session.kill();
      } else if (!session.closing) {
        _send(
          mobileId,
          SessionDetached(id: session.id, reason: DetachReason.closedByHost),
        );
        _phoneLeft(session);
        changed = true;
      }
    }
    if (changed) _changes.add(null);
  }

  /// The relay runtime stops (sign-out, remote access off, network loss —
  /// A1 D7): every phone is told `closed_by_host` and let go; no shell is
  /// killed. A session already draining after its shell exited finishes now
  /// (nobody will hear its tail).
  void disconnectAllPhones() {
    var changed = false;
    for (final session in _sessions.values.toList()) {
      session.exitRecipient = null;
      final mobileId = session.attachedMobileId;
      if (mobileId == null) continue;
      changed = true;
      if (session.closing) {
        session.attachedMobileId = null;
        _finish(session);
        continue;
      }
      _send(
        mobileId,
        SessionDetached(id: session.id, reason: DetachReason.closedByHost),
      );
      _phoneLeft(session);
    }
    if (changed) _changes.add(null);
  }

  /// Closes a session from the tray or the window: `session.detached
  /// {closed_by_host}` now, `session.exited` once the shell is gone. Marks
  /// the session closing immediately so a `session.attach` racing the kill
  /// cannot steal [_Session.exitRecipient] before the shell has actually
  /// exited.
  void closeSession(int id) {
    final session = _sessions[id];
    if (session == null || session.closing) return;
    session.closing = true;
    session.killedOnRequest = true;
    final mobileId = session.attachedMobileId;
    if (mobileId != null) {
      _send(
        mobileId,
        SessionDetached(id: id, reason: DetachReason.closedByHost),
      );
      session.attachedMobileId = null;
      session.exitRecipient = mobileId;
    }
    _changes.add(null);
    session.kill();
  }

  /// Quit only (A1 D7): every shell ends.
  void closeAll() {
    _epoch++;
    _closeAllEpoch++;
    for (final id in _sessions.keys.toList()) {
      closeSession(id);
    }
  }

  /// A session the computer opens itself (the terminal window): nobody is
  /// attached, the desktop drives. Throws [SessionLimitException] or
  /// [SpawnFailedException].
  Future<int> open({required int cols, required int rows}) async {
    final c = _clampDimension(cols);
    final r = _clampDimension(rows);
    final session = await _spawn(c, r, origin: SessionOrigin.desktop);
    if (session == null) {
      throw const SpawnFailedException('ShellX is closing every session');
    }
    session.localCols = c;
    session.localRows = r;
    _changes.add(null);
    return session.id;
  }

  Future<void> _open(String mobileId, int cols, int rows) async {
    final c = _clampDimension(cols);
    final r = _clampDimension(rows);
    final _Session? session;
    try {
      session = await _spawn(c, r, origin: SessionOrigin.phone);
    } on SessionLimitException {
      _send(
        mobileId,
        ErrorMessage(
          code: AppErrorCode.sessionLimit,
          message: 'This machine already has $_maxSessions open sessions.',
        ),
      );
      return;
    } on SpawnFailedException catch (error) {
      _send(
        mobileId,
        ErrorMessage(code: AppErrorCode.spawnFailed, message: error.message),
      );
      return;
    }
    // closeAll or closeSessionsAttachedTo ran while the shell was still
    // spawning: the opener already isn't getting a new session either way,
    // so this is dropped silently rather than answering spawn_failed.
    if (session == null) return;
    session.attachedMobileId = mobileId;
    session.phoneCols = c;
    session.phoneRows = r;
    _send(
      mobileId,
      SessionOpened(id: session.id, index: session.index, shell: session.shell),
    );
    _opened.add(SessionOpenedEvent(mobileId, session.id));
    _changes.add(null);
  }

  /// Starts a shell and registers its session (not attached, no event).
  /// Null when a teardown voided the open while the shell was spawning (the
  /// pty is killed).
  Future<_Session?> _spawn(
    int cols,
    int rows, {
    required SessionOrigin origin,
  }) async {
    if (_sessions.length + _pendingOpens >= _maxSessions) {
      throw SessionLimitException(_maxSessions);
    }
    final epoch = _epoch;
    final closeAllEpoch = _closeAllEpoch;
    _pendingOpens++;
    final ShellCommand command;
    final Pty pty;
    try {
      command = await _shellResolver.resolve();
      final launch = _launch(command);
      pty = _ptyFactory.spawn(
        launch.command,
        workingDirectory: _homeDirectory,
        environment: launch.environment,
        cols: cols,
        rows: rows,
      );
    } catch (error) {
      throw SpawnFailedException('$error');
    } finally {
      _pendingOpens--;
    }
    final voided = origin == SessionOrigin.phone
        ? epoch != _epoch
        : closeAllEpoch != _closeAllEpoch;
    if (voided) {
      pty.kill();
      return null;
    }
    final id = _nextId();
    final session = _Session(
      id: id,
      index: _lowestFreeIndex(),
      shell: command.name,
      createdAt: _clock(),
      pty: pty,
      stream: SessionStream(
        id: id,
        capacity: _bufferCapacity,
        sendWindow: _sendWindow,
        send: _send,
      ),
      cols: cols,
      rows: rows,
      origin: origin,
      driver: origin == SessionOrigin.phone
          ? DriverSide.phone
          : DriverSide.desktop,
    );
    session.notifier = _notifications?.forShell(
      sessionId: session.id,
      index: session.index,
    );
    _sessions[session.id] = session;
    _watch(session);
    return session;
  }

  ShellLaunch _launch(ShellCommand command) {
    final environment = buildSessionEnvironment(_baseEnvironment);
    final integration = _shellIntegration;
    if (integration == null) return ShellLaunch(command, environment);
    try {
      return integration.apply(command, environment);
    } catch (_) {
      return ShellLaunch(command, environment);
    }
  }

  void _attach(String mobileId, int id, int cols, int rows, int lastSeq) {
    final session = _sessions[id];
    if (session == null || session.closing) {
      // A closing session (host-initiated close, or the shell already
      // exited) is not attachable: answering not_found here, instead of
      // letting the attach succeed, keeps `exitRecipient` intact so the
      // phone the host closed still gets `session.exited`.
      _notFound(mobileId, id);
      return;
    }
    final previous = session.stream.attach(mobileId, lastSeq);
    session.exitRecipient = null;
    final c = _clampDimension(cols);
    final r = _clampDimension(rows);
    session.phoneCols = c;
    session.phoneRows = r;
    session.lastPhoneInput = null;
    _setDriver(session, DriverSide.phone); // A1 D6: attaching drives.
    if (c == session.cols && r == session.rows) {
      // Same size: bounce the height so full-screen programs redraw.
      session.resize(c, r > _minDimension ? r - 1 : r + 1);
      session.resize(c, r);
    } else {
      session.cols = c;
      session.rows = r;
      session.resize(c, r);
    }
    _send(mobileId, SessionAttached(id: id));
    if (previous != mobileId) _changes.add(null);
  }

  /// The phone typed or resized. Typing takes the driver unless the window
  /// typed less than [_driverHold] ago; a resize always takes it.
  void _phoneActive(_Session session, {required bool input}) {
    final now = _clock();
    if (session.driver != DriverSide.phone) {
      if (input && _recent(session.lastLocalInput, now)) {
        session.lastPhoneInput = now;
        return;
      }
      _setDriver(session, DriverSide.phone);
    }
    if (input) session.lastPhoneInput = now;
    final c = session.phoneCols;
    final r = session.phoneRows;
    if (c != null && r != null) _applySize(session, c, r);
  }

  /// The window typed or resized (Task 2's `LocalSessionView`); mirror of
  /// [_phoneActive].
  void _localActive(_Session session, {required bool input}) {
    final now = _clock();
    if (session.driver != DriverSide.desktop) {
      if (input && _recent(session.lastPhoneInput, now)) {
        session.lastLocalInput = now;
        return;
      }
      _setDriver(session, DriverSide.desktop);
    }
    if (input) session.lastLocalInput = now;
    final c = session.localCols;
    final r = session.localRows;
    if (c != null && r != null) _applySize(session, c, r);
  }

  bool _recent(DateTime? at, DateTime now) =>
      at != null && now.difference(at) < _driverHold;

  /// Tells local viewers and an attached phone that understands it.
  void _setDriver(_Session session, DriverSide side) {
    if (session.driver == side) return;
    session.driver = side;
    if (!session.drivers.isClosed) session.drivers.add(side);
    final mobileId = session.attachedMobileId;
    if (mobileId != null && receivesDriver(mobileId)) {
      _send(mobileId, SessionDriver(id: session.id, by: side));
    }
    _changes.add(null);
  }

  void _applySize(_Session session, int cols, int rows) {
    if (cols == session.cols && rows == session.rows) return;
    session.cols = cols;
    session.rows = rows;
    session.resize(cols, rows);
  }

  /// The attached phone is gone (detach, channel loss, revoke, runtime
  /// stop): the desktop drives again, at the window's size when known.
  void _phoneLeft(_Session session) {
    session.attachedMobileId = null;
    session.phoneCols = null;
    session.phoneRows = null;
    session.lastPhoneInput = null;
    if (session.driver != DriverSide.phone) return;
    _setDriver(session, DriverSide.desktop);
    final c = session.localCols;
    final r = session.localRows;
    if (c != null && r != null) _applySize(session, c, r);
  }

  void _watch(_Session session) {
    final outputDone = Completer<void>();
    session.output = session.pty.output.listen(
      (data) {
        session.stream.append(data);
        if (!session.local.isClosed) session.local.add(data);
        _pump(session);
        session.notifier?.feed(data);
        _track(session, data);
      },
      onDone: outputDone.complete,
      onError: (Object _) {},
    );
    session.pty.exitCode.then(
      (code) async {
        session.exited = true; // First: no kill/write/resize from here on.
        await outputDone.future.timeout(_outputDrainGrace, onTimeout: () {});
        _processExited(session, code);
      },
      onError: (Object _) {
        session.exited = true;
        _processExited(session, -1);
      },
    );
  }

  /// Title (OSC 0/2) and running command (OSC 133) from live output.
  void _track(_Session session, Uint8List data) {
    var changed = false;
    final title = session.titles.feed(data);
    if (title != null && title != session.title) {
      session.title = title;
      changed = true;
    }
    try {
      final wasRunning = session.commands.running;
      for (final event in session.commandEvents.feed(data)) {
        session.commands.handle(event);
      }
      if (session.commands.running != wasRunning) changed = true;
    } catch (_) {
      // Parsing never breaks the session.
    }
    if (changed && !session.closing) _changes.add(null);
  }

  /// The shell process has exited. If nobody is attached, finishes right
  /// away as before. Otherwise, marks the session closing (spec item 4: it
  /// stops being listable/attachable from here on) and, if the send window
  /// still has buffered bytes to deliver, keeps draining as further acks
  /// arrive rather than dropping the tail — until it is fully drained, the
  /// phone detaches ([mobileDisconnected]), or [_drainTimeout] elapses.
  void _processExited(_Session session, int exitCode) {
    if (!session.exit.isCompleted) session.exit.complete(exitCode);
    if (!identical(_sessions[session.id], session)) return;
    session.closing = true;
    session.finishedExitCode = exitCode;
    _pump(session); // may already finish (and remove) the session below.
    if (!_sessions.containsKey(session.id)) return;
    if (session.attachedMobileId == null) {
      _finish(session);
      return;
    }
    session.drainTimer = Timer(_drainTimeout, () => _finish(session));
    _changes.add(null);
  }

  /// Removes the session and delivers `session.exited` to whoever should
  /// still hear about it. Safe to call more than once for the same session.
  void _finish(_Session session) {
    if (!identical(_sessions[session.id], session)) return;
    session.drainTimer?.cancel();
    session.drainTimer = null;
    final recipient = session.attachedMobileId ?? session.exitRecipient;
    _sessions.remove(session.id);
    session.output?.cancel();
    unawaited(session.local.close());
    unawaited(session.drivers.close());
    if (recipient != null) {
      _send(
        recipient,
        SessionExited(id: session.id, exitCode: session.finishedExitCode ?? -1),
      );
    }
    _changes.add(null);
  }

  /// Sends what the send window allows; once a closing session (its shell
  /// has exited) has handed every buffered byte out, hands off to [_finish].
  void _pump(_Session session) {
    if (session.attachedMobileId == null) return;
    session.stream.pump();
    if (session.closing && session.stream.drained) _finish(session);
  }

  _Session? _attachedTo(String mobileId, int id) {
    final session = _sessions[id];
    return session != null && session.attachedMobileId == mobileId
        ? session
        : null;
  }

  int _lowestFreeIndex() {
    final used = {for (final s in _sessions.values) s.index};
    var index = 1;
    while (used.contains(index)) {
      index++;
    }
    return index;
  }

  void _notFound(String mobileId, int id) {
    _send(
      mobileId,
      ErrorMessage(
        code: AppErrorCode.sessionNotFound,
        message: 'Session $id not found',
        id: id,
      ),
    );
  }

  void _send(String mobileId, AppMessage message) =>
      _outbound.add(OutboundMessage(mobileId, message));
}
```

Notes for the implementer: `_localActive` is unused until Task 2 — add `// ignore: unused_element` above it only if the analyzer flags it, and remove that comment in Task 2. `closeSession` now fires `changes` even without a phone (the window must drop the tab at once).

- [ ] **Step 7: Router — wire `receivesDriver`, add `disconnectAllPhones` and `dispose`**

In `packages/shellx_agent/lib/src/session/session_router.dart` replace the constructor body and add members:

```dart
  SessionRouter({
    required SessionManager shells,
    required DesktopSessionManager desktop,
    required bool Function() desktopSharing,
  }) : _shells = shells,
       _desktop = desktop,
       _desktopSharing = desktopSharing {
    shells.receivesDriver = _receivesDriver;
    _subscriptions.addAll([
      shells.outbound.listen(_outbound.add),
      desktop.outbound.listen(_outbound.add),
      shells.changes.listen(_changes.add),
      desktop.changes.listen(_changes.add),
    ]);
  }

  final _subscriptions = <StreamSubscription<Object?>>[];

  /// `session.driver` is only for phones that listed with `desktop: true`
  /// (their decoder knows it, spec §7.9) — for shell sessions too (A1 D6).
  bool _receivesDriver(String mobileId) => _desktopPhones.contains(mobileId);
```

Below `closeAll()` add:

```dart
  /// The runtime stops (A1 D7): every phone is let go, nothing is killed.
  void disconnectAllPhones() {
    _shells.disconnectAllPhones();
    _desktop.disconnectAllPhones();
  }

  /// The runtime is gone; the shell sessions live on (A1 D7) and must not
  /// keep forwarding into this router or asking its phone set.
  void dispose() {
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    _subscriptions.clear();
    if (_shells.receivesDriver == _receivesDriver) {
      _shells.receivesDriver = (_) => false;
    }
  }
```

Update the doc comment on `closeAll()` to: `/// Quit: shells end, desktop terminals only lose their phones.`

- [ ] **Step 8: Run the tests to verify they pass**

Run: `cd packages/shellx_agent && ~/fvm/versions/3.41.4/bin/dart test`
Expected: all tests pass (the existing suite plus the new files). If an existing test in `session_attach_test.dart` or `session_manager_test.dart` asserted the exact message list after `closeSession` with no phone, it is unaffected (no message is sent); fix only genuine regressions, never by weakening the D4/D6/D7 tests.

- [ ] **Step 9: Format, analyze, commit**

```bash
cd packages/shellx_agent
~/fvm/versions/3.41.4/bin/dart format --set-exit-if-changed lib test
~/fvm/versions/3.41.4/bin/dart analyze
cd ../..
git add packages/shellx_agent/lib/src/session/session_manager.dart packages/shellx_agent/lib/src/session/local_sessions.dart packages/shellx_agent/lib/src/session/session_router.dart packages/shellx_agent/lib/src/notify/command_tracker.dart packages/shellx_agent/lib/shellx_agent.dart packages/shellx_agent/test/support/session_rig.dart packages/shellx_agent/test/session/session_unified_test.dart packages/shellx_agent/test/session/session_router_test.dart
git commit -m "feat(agent): one kind of shell session for desktop and phone (origin, title, driver, running command, 32 sessions, phone close of a desktop session detaches, disconnectAllPhones)"
```

---

### Task 2: Agent — `LocalSessions` API for the window

The in-process API of spec §3.1, implemented by `SessionManager`. Two additions to the spec's interface, both needed by the window: `reply` (terminal-generated answers such as cursor-position reports are written only while the desktop drives, so a phone-driven vim never gets two answers) and `dispose` (a tab that goes away stops listening); plus `closedOnRequest` so a tab closed by ⌘W, the phone or a revoke is not shown as "exited with code -15".

**Files:**
- Modify: `packages/shellx_agent/lib/src/session/local_sessions.dart` (add interfaces)
- Modify: `packages/shellx_agent/lib/src/session/session_manager.dart` (implements `LocalSessions`; `view`, `close`, `_LocalView`, `_localWrite`, `_localReply`, `_localResize`)
- Modify: `packages/shellx_agent/lib/src/session/session_stream.dart:42-49` (add `buffered`)
- Create: `packages/shellx_agent/test/session/local_sessions_test.dart`

**Interfaces:**
- Consumes (Task 1): `SessionManager.open`, `_localActive`, `_Session.local`, `_Session.drivers`, `_Session.exit`, `_Session.killedOnRequest`, `SessionLimitException`, `SpawnFailedException`, `SessionSummary` fields.
- Produces:

```dart
abstract interface class LocalSessions {
  List<SessionSummary> get sessions;
  Stream<void> get changes;
  Future<int> open({required int cols, required int rows});
  LocalSessionView view(int id); // StateError when unknown
  void close(int id);            // kills the process tree
}

abstract interface class LocalSessionView {
  int get id;
  Uint8List get backlog;          // ring buffer content at view() time (≤ 256 KiB)
  Stream<Uint8List> get output;   // live output after backlog, single listener, buffered from view()
  Stream<DriverSide> get driver;  // driver changes
  Future<int> get exitCode;
  bool get closedOnRequest;       // valid once exitCode completed
  void write(Uint8List data);     // user input → may take the driver (hold applies)
  void reply(Uint8List data);     // terminal answers → written only while the desktop drives
  void resize(int cols, int rows);// first size of a phone-driven session never takes the driver
  void dispose();
}
```
  - `Uint8List SessionStream.buffered`
  - `final class SessionManager implements AgentSessions, LocalSessions`

- [ ] **Step 1: Write the failing tests**

Create `packages/shellx_agent/test/session/local_sessions_test.dart`:

```dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:test/test.dart';

import '../support/fake_pty.dart';
import '../support/session_rig.dart';

Uint8List _b(String s) => Uint8List.fromList(utf8.encode(s));

/// Collects a view's live output as text.
final class _Collected {
  _Collected(LocalSessionView view) {
    view.output.listen(
      (data) => text.write(utf8.decode(data)),
      onDone: () => done = true,
    );
  }
  final text = StringBuffer();
  bool done = false;
}

void main() {
  test('a SessionManager is a LocalSessions', () {
    final rig = SessionRig();
    expect(rig.manager, isA<LocalSessions>());
  });

  test('view: backlog first, then live output, no ack needed', () async {
    final rig = SessionRig(sendWindow: 4);
    final id = await rig.manager.open(cols: 80, rows: 24);
    rig.pty(0).emit('hello ');
    await pumpEventQueue();

    final view = rig.manager.view(id);
    expect(utf8.decode(view.backlog), 'hello ');
    final live = _Collected(view);
    rig.pty(0).emit('world, more than the send window');
    await pumpEventQueue();

    expect(live.text.toString(), 'world, more than the send window');
  });

  test('output emitted between view() and listen is not lost', () async {
    final rig = SessionRig();
    final id = await rig.manager.open(cols: 80, rows: 24);
    final view = rig.manager.view(id);
    rig.pty(0).emit('early');
    await pumpEventQueue();
    final live = _Collected(view);
    await pumpEventQueue();
    expect(live.text.toString(), 'early');
  });

  test('the backlog is capped at the ring buffer size', () async {
    final rig = SessionRig(bufferCapacity: 16);
    final id = await rig.manager.open(cols: 80, rows: 24);
    rig.pty(0).emit('0123456789abcdefXYZ');
    await pumpEventQueue();
    expect(utf8.decode(rig.manager.view(id).backlog), '3456789abcdefXYZ');
  });

  test('view of an unknown session throws StateError', () {
    final rig = SessionRig();
    expect(() => rig.manager.view(42), throwsStateError);
  });

  test('write reaches the shell; resize resizes the PTY', () async {
    final rig = SessionRig();
    final id = await rig.manager.open(cols: 80, rows: 24);
    final view = rig.manager.view(id);
    view.write(_b('ls\r'));
    view.resize(120, 40);
    view.resize(120, 40); // same size: no second resize
    expect(rig.pty(0).writtenText, 'ls\r');
    expect(rig.pty(0).resizes, [(120, 40)]);
    expect(rig.manager.sessions.single.driver, DriverSide.desktop);
  });

  test('open() is limited like phone opens (D8)', () async {
    final rig = SessionRig(maxSessions: 2);
    await rig.manager.open(cols: 80, rows: 24);
    await rig.open(phone);
    await expectLater(
      rig.manager.open(cols: 80, rows: 24),
      throwsA(isA<SessionLimitException>().having((e) => e.max, 'max', 2)),
    );
  });

  group('a phone and the window on the same session (D5, D6)', () {
    late SessionRig rig;
    late int id;
    late LocalSessionView view;
    late List<DriverSide> drivers;
    late _Collected live;

    setUp(() async {
      rig = SessionRig();
      rig.manager.receivesDriver = {phone}.contains;
      id = await rig.manager.open(cols: 100, rows: 30);
      view = rig.manager.view(id);
      drivers = [];
      view.driver.listen(drivers.add);
      live = _Collected(view);
      await rig.manager.handle(
        phone,
        SessionAttach(id: id, cols: 50, rows: 20, lastSeq: 0),
      );
    });

    test('nobody is kicked out and both see the output', () async {
      rig.pty(0).emit('shared');
      await pumpEventQueue();
      expect(live.text.toString(), 'shared');
      expect(outputText(rig.to(phone), id), 'shared');
      expect(rig.to(phone).whereType<SessionDetached>(), isEmpty);
      expect(rig.manager.sessions.single.attachedMobileId, phone);
      expect(drivers, [DriverSide.phone]);
    });

    test('the window typing after the hold takes the driver back', () async {
      rig.now = rig.now.add(const Duration(seconds: 5));
      rig.clear();
      view.write(_b('x'));
      expect(drivers, [DriverSide.phone, DriverSide.desktop]);
      expect(rig.pty(0).resizes.last, (100, 30));
      expect(rig.to(phone), contains(SessionDriver(id: id, by: DriverSide.desktop)));
      expect(rig.pty(0).writtenText, 'x');
    });

    test('interleaved typing from both sides reaches the shell in order '
        'without resizing on every key', () async {
      rig.now = rig.now.add(const Duration(seconds: 5));
      view.write(_b('a')); // desktop takes the driver (phone idle 5 s)
      final resizesAfterTakeover = rig.pty(0).resizes.length;
      for (final key in ['b', 'c', 'd', 'e', 'f', 'g']) {
        rig.now = rig.now.add(const Duration(milliseconds: 100));
        if (key.codeUnitAt(0).isEven) {
          await rig.manager.handle(phone, InputMessage(id: id, data: _b(key)));
        } else {
          view.write(_b(key));
        }
      }
      expect(rig.pty(0).writtenText, 'abcdefg');
      expect(rig.pty(0).resizes.length, resizesAfterTakeover);
      expect(rig.manager.sessions.single.driver, DriverSide.desktop);
      expect(rig.to(phone).whereType<SessionDetached>(), isEmpty);
    });

    test('terminal replies are dropped while the phone drives', () {
      view.reply(_b('\x1b[12;1R'));
      expect(rig.pty(0).writes, isEmpty);
    });

    test('the phone leaving gives the window its size back', () {
      rig.manager.mobileDisconnected(phone);
      expect(drivers.last, DriverSide.desktop);
      expect(rig.pty(0).resizes.last, (100, 30));
    });
  });

  test('terminal replies are written while the desktop drives', () async {
    final rig = SessionRig();
    final id = await rig.manager.open(cols: 80, rows: 24);
    rig.manager.view(id).reply(_b('\x1b[1;1R'));
    expect(rig.pty(0).writtenText, '\x1b[1;1R');
  });

  test('the first window size of a phone-driven session does not take the '
      'driver; a later resize does', () async {
    final rig = SessionRig();
    final id = await rig.open(phone, cols: 50, rows: 20);
    final view = rig.manager.view(id);

    view.resize(100, 30); // the tab was laid out for the first time
    expect(rig.manager.sessions.single.driver, DriverSide.phone);
    expect(rig.pty(0).resizes, isEmpty);

    view.resize(110, 32); // the user resized the window
    expect(rig.manager.sessions.single.driver, DriverSide.desktop);
    expect(rig.pty(0).resizes.last, (110, 32));
  });

  test('close kills the process, fires changes at once and reports '
      'closedOnRequest; an attached phone gets closed_by_host', () async {
    final rig = SessionRig();
    final id = await rig.manager.open(cols: 80, rows: 24);
    await rig.manager.handle(
      phone,
      SessionAttach(id: id, cols: 50, rows: 20, lastSeq: 0),
    );
    final view = rig.manager.view(id);
    final live = _Collected(view);
    rig.clear();

    rig.manager.close(id);

    expect(rig.manager.sessions, isEmpty);
    expect(rig.pty(0).killed, isTrue);
    expect(await view.exitCode, FakePty.killExitCode);
    expect(view.closedOnRequest, isTrue);
    expect(
      rig.to(phone).first,
      SessionDetached(id: id, reason: DetachReason.closedByHost),
    );
    await pumpEventQueue();
    expect(live.done, isTrue);
  });

  test('a shell that exits on its own reports its code, not on request', () async {
    final rig = SessionRig();
    final id = await rig.manager.open(cols: 80, rows: 24);
    final view = rig.manager.view(id);
    final live = _Collected(view);
    rig.pty(0).emit('bye');
    rig.pty(0).exit(3);
    expect(await view.exitCode, 3);
    expect(view.closedOnRequest, isFalse);
    await pumpEventQueue();
    expect(live.text.toString(), 'bye');
    expect(live.done, isTrue);
    expect(rig.manager.sessions, isEmpty);
  });

  test('a phone closing the session it opened is a close on request', () async {
    final rig = SessionRig();
    final id = await rig.open(phone);
    final view = rig.manager.view(id);
    await rig.manager.handle(phone, SessionClose(id: id));
    await view.exitCode;
    expect(view.closedOnRequest, isTrue);
  });

  test('dispose stops delivery to that view only', () async {
    final rig = SessionRig();
    final id = await rig.manager.open(cols: 80, rows: 24);
    final first = rig.manager.view(id);
    final second = rig.manager.view(id);
    final a = _Collected(first);
    final b = _Collected(second);
    first.dispose();
    rig.pty(0).emit('after');
    await pumpEventQueue();
    expect(a.text.toString(), isEmpty);
    expect(b.text.toString(), 'after');
  });
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd packages/shellx_agent && ~/fvm/versions/3.41.4/bin/dart test test/session/local_sessions_test.dart`
Expected: compile errors — `LocalSessions`, `LocalSessionView`, `view`, `close` are not defined.

- [ ] **Step 3: Add the interfaces**

Prepend to `packages/shellx_agent/lib/src/session/local_sessions.dart` (above the exceptions):

```dart
import 'dart:typed_data';

import 'package:shellx_core/shellx_core.dart';

import 'session_manager.dart';

/// The terminal window's way into the agent's sessions (A1 spec §3.1). The
/// window never talks to `SessionManager` directly, so A5 can move the
/// sessions into a daemon behind this same interface.
abstract interface class LocalSessions {
  /// Listable sessions in creation order.
  List<SessionSummary> get sessions;

  /// Fires when [sessions] (or anything in a summary) changes.
  Stream<void> get changes;

  /// Starts a login shell in the home directory. Throws
  /// [SessionLimitException] or [SpawnFailedException].
  Future<int> open({required int cols, required int rows});

  /// One local viewer of session [id]. Throws [StateError] when there is no
  /// such session.
  LocalSessionView view(int id);

  /// Ends session [id] and its process tree (the desktop may close every
  /// session, A1 D4).
  void close(int id);
}

/// One local viewer of a session. It is not a phone: it has no send window
/// and never kicks a phone out (A1 D5).
abstract interface class LocalSessionView {
  int get id;

  /// What the ring buffer held when the view was made (at most 256 KiB).
  Uint8List get backlog;

  /// Live output after [backlog], buffered from the moment the view was
  /// made (single listener). Done once the session has ended.
  Stream<Uint8List> get output;

  /// Driver changes (A1 D6).
  Stream<DriverSide> get driver;

  /// The shell's exit code.
  Future<int> get exitCode;

  /// The session ended because it was closed (window, phone, revoke,
  /// quit), not on its own. Meaningful once [exitCode] has completed.
  bool get closedOnRequest;

  /// Keystrokes, paste, mouse reports: the desktop drives (unless the phone
  /// typed within the driver hold).
  void write(Uint8List data);

  /// Answers the window's terminal generates by itself (cursor position,
  /// device attributes): written only while the desktop drives, so the
  /// shell never gets two answers to one question.
  void reply(Uint8List data);

  /// The window's size for this session. The first size of a session the
  /// phone drives is only remembered (a tab being laid out is not the user
  /// asking for the terminal); later sizes make the desktop drive.
  void resize(int cols, int rows);

  /// Stops [output]; the session keeps running.
  void dispose();
}
```

- [ ] **Step 4: `SessionStream.buffered`**

In `packages/shellx_agent/lib/src/session/session_stream.dart`, after `int get end => _buffer.end;` add:

```dart
  /// Every byte the buffer still holds, oldest first (the window's backlog,
  /// A1 §3.1).
  Uint8List get buffered =>
      _buffer.read(_buffer.start, _buffer.end - _buffer.start);
```

- [ ] **Step 5: Implement `LocalSessions` in `SessionManager`**

In `session_manager.dart`:

1. Change the class header to `final class SessionManager implements AgentSessions, LocalSessions {`.
2. Add `@override` to the `sessions`, `changes` getters and to `open`.
3. Add after `closeAll()`:

```dart
  @override
  LocalSessionView view(int id) {
    final session = _sessions[id];
    if (session == null) throw StateError('No session $id');
    return _LocalView(this, session);
  }

  @override
  void close(int id) => closeSession(id);

  void _localWrite(_Session session, Uint8List data) {
    if (session.closing) return;
    _localActive(session, input: true);
    session.write(data);
  }

  void _localReply(_Session session, Uint8List data) {
    if (session.closing || session.driver != DriverSide.desktop) return;
    session.write(data);
  }

  void _localResize(_Session session, int cols, int rows) {
    if (session.closing) return;
    final c = _clampDimension(cols);
    final r = _clampDimension(rows);
    final known = session.localCols != null;
    if (known && c == session.localCols && r == session.localRows) return;
    session.localCols = c;
    session.localRows = r;
    if (!known && session.driver == DriverSide.phone) return;
    _localActive(session, input: false);
  }
```

4. Append at the end of the file:

```dart
final class _LocalView implements LocalSessionView {
  _LocalView(this._manager, this._session)
    : backlog = _session.stream.buffered {
    _subscription = _session.local.stream.listen(
      _output.add,
      onDone: () => unawaited(_output.close()),
    );
  }

  final SessionManager _manager;
  final _Session _session;
  final _output = StreamController<Uint8List>();
  late final StreamSubscription<Uint8List> _subscription;

  @override
  final Uint8List backlog;

  @override
  int get id => _session.id;
  @override
  Stream<Uint8List> get output => _output.stream;
  @override
  Stream<DriverSide> get driver => _session.drivers.stream;
  @override
  Future<int> get exitCode => _session.exit.future;
  @override
  bool get closedOnRequest => _session.killedOnRequest;

  @override
  void write(Uint8List data) => _manager._localWrite(_session, data);
  @override
  void reply(Uint8List data) => _manager._localReply(_session, data);
  @override
  void resize(int cols, int rows) =>
      _manager._localResize(_session, cols, rows);

  @override
  void dispose() {
    unawaited(_subscription.cancel());
    if (!_output.isClosed) unawaited(_output.close());
  }
}
```

5. Remove the `// ignore: unused_element` on `_localActive` if Task 1 added one.

- [ ] **Step 6: Run the tests to verify they pass**

Run: `cd packages/shellx_agent && ~/fvm/versions/3.41.4/bin/dart test`
Expected: all pass.

- [ ] **Step 7: Format, analyze, commit**

```bash
cd packages/shellx_agent
~/fvm/versions/3.41.4/bin/dart format --set-exit-if-changed lib test
~/fvm/versions/3.41.4/bin/dart analyze
cd ../..
git add packages/shellx_agent/lib/src/session/local_sessions.dart packages/shellx_agent/lib/src/session/session_manager.dart packages/shellx_agent/lib/src/session/session_stream.dart packages/shellx_agent/test/session/local_sessions_test.dart
git commit -m "feat(agent): LocalSessions API for the desktop window (backlog + live output without ack, driver stream, replies only while the desktop drives, exit code)"
```

---

### Task 3: Desktop — one `SessionManager` per process; only Quit kills shells

D7 in the app: `main.dart` builds a `SessionCore` once; `CoreAgentRuntime` receives it; `stop()` disconnects phones instead of killing; sign-out, revoke (4002) and remote access off keep every shell; Quit (`AgentController.shutdown`) still closes all sessions and waits for the tree kills. The tray's session list and Quit confirmation now count sessions even with no runtime. Strings that said sessions close are corrected (UI §5 table "Existing strings that D7 makes wrong").

**Files:**
- Create: `apps/desktop/lib/src/agent/session_core.dart`
- Modify: `apps/desktop/lib/src/agent/agent_runtime.dart` (interface lines 33-89, `CoreAgentRuntime` lines 132-343)
- Modify: `apps/desktop/lib/src/agent/desktop_services.dart` (new required field `sessions`)
- Modify: `apps/desktop/lib/src/agent/agent_controller.dart` (`build`, `setRemoteAccess` doc, `closeSession`, `closeAllSessions`, `shutdown`, `_startRuntime`, `_stopRuntime`, `_refreshSessions`, `_dispose`)
- Modify: `apps/desktop/lib/src/tray/tray_actions.dart:42-53`
- Modify: `apps/desktop/lib/main.dart:127-205`
- Modify: `apps/desktop/lib/l10n/app_en.arb`, `app_vi.arb` (+ regenerate)
- Create: `apps/desktop/test/support/fake_pty.dart`
- Modify: `apps/desktop/test/support/fakes.dart`
- Modify tests: `test/agent/core_agent_runtime_test.dart`, `core_agent_runtime_push_test.dart`, `core_agent_runtime_sharing_test.dart`, `test/terminal_sharing/end_to_end_macos_test.dart`, `test/agent/agent_controller_test.dart`, `test/ui/window_flow_test.dart`, `test/l10n/l10n_test.dart`

**Interfaces:**
- Consumes (Tasks 1–2): `SessionManager` (`LocalSessions`), `SessionManager.closeAll`, `closeSession`, `sessions`, `changes`, `SessionRouter.disconnectAllPhones`, `SessionRouter.dispose`, `sessionIdAllocator`.
- Produces:
  - `final class SessionCore { factory SessionCore({required PtyFactory ptyFactory, required ShellResolver shellResolver, required String homeDirectory, required Map<String, String> baseEnvironment, required ShellxApi api, PushNotificationsSetup? notifications, DateTime Function()? now, int Function()? sessionIds}); final int Function() ids; final AgentNotifications? notifications; final SessionManager sessions; }`
  - `CoreAgentRuntime(RuntimeParams params, {required SessionCore core, required Uri relayBaseUri, required String appVersion, String? termEndpointPath, RelaySocketConnector connector = ioRelaySocketConnector, DateTime Function()? now})`
  - `AgentRuntime` no longer has `sessions`, `closeSession`, `closeAllSessions`.
  - `DesktopServices.sessions` (`SessionManager`) — the process's one session manager; later tasks read it through `localSessionsProvider` (Task 5).
  - Test support: `FakePty`, `FakePtyFactory`, `FixedShellResolver` in `apps/desktop/test/support/fake_pty.dart`; `TestHarness.ptys` (`FakePtyFactory`), `TestHarness.sessions` (`SessionManager`); `FakeAgentRuntime.phonesDisconnected` (bool).

- [ ] **Step 1: Desktop test fakes for PTYs**

Create `apps/desktop/test/support/fake_pty.dart`:

```dart
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:shellx_agent/shellx_agent.dart';

/// Scriptable [Pty]: tests push output with [emit] and end it with [exit].
final class FakePty implements Pty {
  FakePty({required this.initialCols, required this.initialRows});

  final int initialCols;
  final int initialRows;
  final _output = StreamController<Uint8List>();
  final _exitCode = Completer<int>();
  final writes = <Uint8List>[];
  final resizes = <(int, int)>[];
  bool killed = false;

  static const int killExitCode = -15;

  @override
  Stream<Uint8List> get output => _output.stream;
  @override
  Future<int> get exitCode => _exitCode.future;
  @override
  void write(Uint8List data) => writes.add(Uint8List.fromList(data));
  @override
  void resize(int cols, int rows) => resizes.add((cols, rows));
  @override
  void kill() {
    killed = true;
    exit(killExitCode);
  }

  void emit(String text) => emitBytes(utf8.encode(text));

  void emitBytes(List<int> bytes) {
    if (!_output.isClosed) _output.add(Uint8List.fromList(bytes));
  }

  void exit(int code) {
    if (_exitCode.isCompleted) return;
    _output.close();
    _exitCode.complete(code);
  }

  String get writtenText => utf8.decode([for (final w in writes) ...w]);
}

final class FakePtyFactory implements PtyFactory {
  final ptys = <FakePty>[];
  Object? failWith;

  @override
  Pty spawn(
    ShellCommand command, {
    required String workingDirectory,
    required Map<String, String> environment,
    required int cols,
    required int rows,
  }) {
    final error = failWith;
    if (error != null) throw error;
    final pty = FakePty(initialCols: cols, initialRows: rows);
    ptys.add(pty);
    return pty;
  }
}

final class FixedShellResolver implements ShellResolver {
  const FixedShellResolver();
  @override
  Future<ShellCommand> resolve() async => const ShellCommand(
    executable: '/bin/zsh',
    arguments: ['-l'],
    name: 'zsh',
  );
}
```

- [ ] **Step 2: Write the failing tests**

(a) In `apps/desktop/test/agent/core_agent_runtime_test.dart`: add `import 'package:shellx_desktop/src/agent/session_core.dart';` and `import '../support/fake_pty.dart';`, delete `_NoPty`, and change `build()` to:

```dart
  late SessionCore core;
  late FakePtyFactory ptys;

  Future<CoreAgentRuntime> build({RelaySocketConnector? connector}) async {
    identity = await NoiseKeyPair.generate();
    final store = InMemoryKeyValueStore();
    final api = ShellxApi(baseUri: Uri.parse('https://relay.shellx.pro'));
    ptys = FakePtyFactory();
    core = SessionCore(
      ptyFactory: ptys,
      shellResolver: const FixedShellResolver(),
      homeDirectory: '/Users/phu',
      baseEnvironment: const {'HOME': '/Users/phu'},
      api: api,
    );
    return CoreAgentRuntime(
      RuntimeParams(
        credentials: const AgentCredentials(
          token: 'agent-token',
          deviceId: '22222222-2222-4222-8222-222222222222',
          userId: '11111111-1111-4111-8111-111111111111',
          email: 'phu@example.com',
        ),
        identity: identity,
        trusted: TrustedStore(store),
        api: api,
      ),
      core: core,
      relayBaseUri: Uri.parse('https://relay.shellx.pro'),
      appVersion: '1.0.0',
      connector:
          connector ??
          (uri, headers) async {
            connects.add((uri, headers));
            return socket = FakeRelaySocket();
          },
      now: () => now,
    );
  }
```

and add the test:

```dart
  test('stop() disconnects phones and keeps every shell running (A1 D7)', () async {
    final runtime = await build();
    await runtime.start();
    await pumpEventQueue();
    const phone = '33333333-3333-4333-8333-333333333333';
    await core.sessions.handle(phone, const SessionOpen(cols: 80, rows: 24));
    await core.sessions.open(cols: 100, rows: 30);
    expect(core.sessions.sessions.first.attachedMobileId, phone);

    await runtime.stop();

    expect(ptys.ptys.map((p) => p.killed), [false, false]);
    expect(core.sessions.sessions, hasLength(2));
    expect(
      core.sessions.sessions.map((s) => s.attachedMobileId),
      everyElement(isNull),
    );
    // The next runtime uses the same sessions.
    expect(runtime.shellSessions, same(core.sessions));
  });
```

(b) In `core_agent_runtime_push_test.dart`, `build()` becomes (keep `_Pty`, `_PtyFactory`, `_Zsh`):

```dart
  late SessionCore core;

  Future<CoreAgentRuntime> build({bool push = true}) async {
    final api = ShellxApi(
      baseUri: Uri.parse('https://relay.test'),
      httpClient: MockClient((request) async {
        posts.add(request);
        return http.Response('{"sent":$sentValue}', 202);
      }),
    )..token = 'agent-token';
    core = SessionCore(
      ptyFactory: ptys,
      shellResolver: _Zsh(),
      homeDirectory: '/Users/phu',
      baseEnvironment: const {'HOME': '/Users/phu'},
      api: api,
      notifications: push
          ? PushNotificationsSetup(
              threshold: () => notifyThreshold(settings),
              machineName: () => 'MacBook-Pro',
              locale: () => 'vi_VN',
              hooksDirectory: hooks.path,
            )
          : null,
      now: () => now,
    );
    return CoreAgentRuntime(
      RuntimeParams(
        credentials: const AgentCredentials(
          token: 'agent-token',
          deviceId: '22222222-2222-4222-8222-222222222222',
          userId: '11111111-1111-4111-8111-111111111111',
          email: 'phu@example.com',
        ),
        identity: await NoiseKeyPair.generate(),
        trusted: TrustedStore(InMemoryKeyValueStore()),
        api: api,
      ),
      core: core,
      relayBaseUri: Uri.parse('https://relay.test'),
      appVersion: '1.0.0',
      connector: (uri, headers) async =>
          throw const SocketException('offline in tests'),
      now: () => now,
    );
  }
```

and replace every `runtime.closeAllSessions();` in that file with `core.sessions.closeAll();`. `runtime.notifications` and `runtime.shellSessions` keep working (they now return the core's). Add one test:

```dart
  test('a tab opened in the window gets the same hook and notifications', () async {
    final runtime = await build();
    await core.sessions.open(cols: 80, rows: 24);
    final pty = ptys.ptys.single;
    expect(ptys.spawned.single.environment['ZDOTDIR'], startsWith(hooks.path));
    pty.emit('$esc]9;done$bel');
    await runtime.notifications!.sender.idle;
    expect(body(posts.single)['body'], 'done');
    core.sessions.closeAll();
  });
```

(c) `core_agent_runtime_sharing_test.dart` and `test/terminal_sharing/end_to_end_macos_test.dart`: replace the `ptyFactory:`, `shellResolver:`, `homeDirectory:`, `baseEnvironment:` arguments of `CoreAgentRuntime(` with `core: SessionCore(ptyFactory: _NoPty(), shellResolver: <the same resolver>, homeDirectory: <same>, baseEnvironment: <same>, api: <the same ShellxApi passed in RuntimeParams — hoist it into a local `api`>)`. In the sharing test replace `expect(runtime.sessions, isEmpty);` with `expect(runtime.shellSessions.sessions, isEmpty);`.

(d) `test/support/fakes.dart`:
- `import 'fake_pty.dart';`
- In `FakeAgentRuntime` delete `currentSessions`, `closedSessions`, `closedAll`, the `sessions` getter, `closeSession`, `closeAllSessions`; add `bool phonesDisconnected = false;` and make `stop()`:

```dart
  @override
  Future<void> stop() async {
    stopped = true;
    phonesDisconnected = true;
    await stopGate?.future;
  }
```

- In `TestHarness` add:

```dart
  /// The process's one SessionManager (A1 D7), over fake PTYs.
  final FakePtyFactory ptys = FakePtyFactory();
  late final SessionManager sessions = SessionManager(
    ptyFactory: ptys,
    shellResolver: const FixedShellResolver(),
    homeDirectory: '/Users/phu',
    baseEnvironment: const {'HOME': '/Users/phu'},
  );
```

  and pass `sessions: sessions,` to the `DesktopServices(` in `_services`.
- In `agent_controller_test.dart` `servicesWith`, pass `sessions: base.sessions,`.

(e) `agent_controller_test.dart` — rewrite these tests (keep their other expectations):

```dart
  // group('token revoked (4002 / 401)'):
      'keeps the shells running, drops the token, keeps key + user + trusted list',
      // … after bootstrap:
        await h.sessions.open(cols: 80, rows: 24);
      // … replace `expect(h.runtime.closedAll, isTrue);` with:
        expect(h.runtime.phonesDisconnected, isTrue);
        expect(h.ptys.ptys.single.killed, isFalse);
        expect(state().sessions, hasLength(1));

  // group('sign out'):
      'keeps the shells running, calls logout, clears token and trusted list',
      // … after bootstrap: `await h.sessions.open(cols: 80, rows: 24);`
      // replace `expect(runtime.closedAll, isTrue);` with:
        expect(runtime.phonesDisconnected, isTrue);
        expect(h.ptys.ptys.single.killed, isFalse);

    test('the session list follows the session manager, signed in or not', () async {
      boot();
      await controller().bootstrap(watchForWake: false); // signed out
      await h.sessions.open(cols: 80, rows: 24);
      await pumpEventQueue();
      expect(state().sessions.single.shell, 'zsh');
      expect(state().sessions.single.origin, SessionOrigin.desktop);
    });

    test('active channel count follows the runtime', () async {
      boot();
      await h.seedSignedIn();
      await controller().bootstrap(watchForWake: false);
      h.runtime.eventController.add(const ActiveChannelsChanged(2));
      await pumpEventQueue();
      expect(state().activeChannels, 2);
    });

    test('closing sessions goes to the session manager', () async {
      boot();
      await controller().bootstrap(watchForWake: false);
      final first = await h.sessions.open(cols: 80, rows: 24);
      await h.sessions.open(cols: 80, rows: 24);
      controller().closeSession(first);
      expect(h.ptys.ptys[0].killed, isTrue);
      expect(h.ptys.ptys[1].killed, isFalse);
      controller().closeAllSessions();
      expect(h.ptys.ptys[1].killed, isTrue);
    });

    test('remote access off keeps the shells running (A1 D7)', () async {
      boot();
      await h.seedSignedIn();
      await controller().bootstrap(watchForWake: false);
      await h.sessions.open(cols: 80, rows: 24);
      await controller().setRemoteAccess(false);
      expect(h.runtime.stopped, isTrue);
      expect(h.ptys.ptys.single.killed, isFalse);
      expect(state().sessions, hasLength(1));
    });
```

Delete the old 'active channel count and session list follow the runtime' and 'closing sessions goes to the runtime' tests. In 'shutdown closes sessions, waits for the kills, then releases keep-awake' open a session right after bootstrap (`await h.sessions.open(cols: 80, rows: 24);`), and replace `expect(runtime.closedAll, isTrue);` with `expect(h.ptys.ptys.single.killed, isTrue);`. Do the same replacement at the other `runtime.closedAll` assertion near line 1190.

(f) `test/ui/window_flow_test.dart` `group('TrayActions')`: delete `oneSession()`; then

```dart
    test(
      'remote access off with a phone connected asks first; cancel keeps it on',
      () async {
        await signedIn(settings: {'onboarding_done': true});
        h.runtime.eventController.add(const ActiveChannelsChanged(1));
        await pumpEventQueue();

        final done = tray().handle(const ToggleRemoteAccess());
        await pumpEventQueue();
        expect(
          window().confirm!.body,
          'Connected phones will be disconnected. Terminal tabs on this '
          'computer keep running.',
        );
        await answer(false);
        await done;
        expect(agentState().remoteAccess, isTrue);

        final again = tray().handle(const ToggleRemoteAccess());
        await answer(true);
        await again;
        expect(agentState().remoteAccess, isFalse);
        expect(h.runtime.stopped, isTrue);
      },
    );

    test('remote access off with tabs but no phone does not ask', () async {
      await signedIn(settings: {'onboarding_done': true});
      await h.sessions.open(cols: 80, rows: 24);
      await tray().handle(const ToggleRemoteAccess());
      expect(agentState().remoteAccess, isFalse);
      expect(window().confirm, isNull);
      expect(h.ptys.ptys.single.killed, isFalse);
    });

    test('quit with sessions asks, then kills every shell and quits', () async {
      await signedIn(settings: {'onboarding_done': true});
      await h.sessions.open(cols: 80, rows: 24);
      await pumpEventQueue();
      final done = tray().handle(const Quit());
      await answer(true);
      await done;
      expect(h.runtime.stopped, isTrue);
      expect(h.ptys.ptys.single.killed, isTrue);
      expect(h.keepAwake.last, isFalse);
      expect(h.quits, 1);
    });

    test('quit while signed out still asks about open tabs', () async {
      h = TestHarness();
      container = ProviderContainer.test(
        overrides: [desktopServicesProvider.overrideWithValue(h.services())],
      );
      await agent().bootstrap(watchForWake: false);
      await h.sessions.open(cols: 80, rows: 24);
      await pumpEventQueue();
      final done = tray().handle(const Quit());
      await pumpEventQueue();
      expect(window().confirm, isNotNull);
      await answer(true);
      await done;
      expect(h.ptys.ptys.single.killed, isTrue);
      expect(h.quits, 1);
    });

    test('close one session / all sessions go to the session manager', () async {
      await signedIn(settings: {'onboarding_done': true});
      final id = await h.sessions.open(cols: 80, rows: 24);
      await h.sessions.open(cols: 80, rows: 24);
      await tray().handle(CloseSession(id));
      expect(h.ptys.ptys[0].killed, isTrue);
      await tray().handle(const CloseAllSessions());
      expect(h.ptys.ptys[1].killed, isTrue);
    });
```

replacing the old 'remote access off with sessions asks first…', 'remote access off without sessions does not ask', 'quit with sessions asks…' and 'close one session / all sessions go to the runtime'.

(g) `test/l10n/l10n_test.dart` 'plural and select messages render in both languages': replace the three `confirmRemoteOffBody` lines with

```dart
    expect(
      en.confirmRemoteOffBody,
      'Connected phones will be disconnected. Terminal tabs on this '
      'computer keep running.',
    );
    expect(
      vi.confirmSignOutBody,
      contains('Các tab terminal trên máy này vẫn chạy.'),
    );
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/agent test/ui/window_flow_test.dart test/l10n test/terminal_sharing`
Expected: compile errors (`SessionCore`, `core:`, `sessions:`, `phonesDisconnected`, `confirmRemoteOffBody` without argument).

- [ ] **Step 4: Create `session_core.dart`**

```dart
// apps/desktop/lib/src/agent/session_core.dart
import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_core/shellx_core.dart';

import 'agent_runtime.dart';

/// What lives for the whole process (A1 D7): the one [SessionManager], the
/// id allocator it shares with each runtime's desktop terminals, and the
/// push notifications of every session. Built once in `main.dart`; every
/// [CoreAgentRuntime] borrows it.
final class SessionCore {
  SessionCore._(this.ids, this.notifications, this.sessions);

  /// [api] is the app's shared [ShellxApi]: notifications are sent with
  /// whatever token it holds and fail locally (nothing leaves the
  /// computer) while signed out.
  factory SessionCore({
    required PtyFactory ptyFactory,
    required ShellResolver shellResolver,
    required String homeDirectory,
    required Map<String, String> baseEnvironment,
    required ShellxApi api,
    PushNotificationsSetup? notifications,
    DateTime Function()? now,
    int Function()? sessionIds,
  }) {
    final ids = sessionIds ?? sessionIdAllocator();
    // One AgentNotifications for both kinds of session: the 6-per-minute
    // limit is per machine (push spec N10).
    final agentNotifications = notifications == null
        ? null
        : AgentNotifications(
            NotificationsConfig(
              api: api,
              threshold: notifications.threshold,
              machineName: notifications.machineName,
              locale: notifications.locale,
            ),
            now: now,
          );
    final hooks = notifications?.hooksDirectory;
    final sessions = SessionManager(
      ptyFactory: ptyFactory,
      shellResolver: shellResolver,
      homeDirectory: homeDirectory,
      baseEnvironment: baseEnvironment,
      nextId: ids,
      notifications: agentNotifications,
      shellIntegration: hooks == null
          ? null
          : ShellIntegration(directory: hooks),
      clock: now,
    );
    return SessionCore._(ids, agentNotifications, sessions);
  }

  final int Function() ids;
  final AgentNotifications? notifications;
  final SessionManager sessions;
}
```

- [ ] **Step 5: Rewire `CoreAgentRuntime` and the `AgentRuntime` interface**

In `agent_runtime.dart`:
- Add `import 'session_core.dart';`.
- In `AgentRuntime` delete `List<SessionSummary> get sessions;`, `void closeSession(int id);`, `void closeAllSessions();`. Change the doc of `stop()` to: `/// Disconnects every phone (\`closed_by_host\`), stops AgentService and disconnects from the relay. The shell sessions keep running (A1 D7): they belong to [SessionCore]; only Quit closes them.` (keep the rest of the paragraph about synchronous effect and the relay). Change the class doc to `/// Everything that exists only while signed in with remote access on: the relay link, AgentService, the router and the desktop-terminal sharing. The shell sessions are not here (A1 D7, [SessionCore]).` and the `sessionChanges` member doc to `/// Desktop terminals (and shell sessions, through the router) changed.`
- Replace the `CoreAgentRuntime` constructor and fields with:

```dart
final class CoreAgentRuntime implements AgentRuntime {
  CoreAgentRuntime(
    RuntimeParams params, {
    required SessionCore core,
    required Uri relayBaseUri,
    required String appVersion,
    String? termEndpointPath,
    RelaySocketConnector connector = ioRelaySocketConnector,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now,
       _core = core {
    final token = params.credentials.token;
    _relay = RelayConnection(
      wsUri: relayWebSocketUri(relayBaseUri),
      token: () => token,
      connector: connector,
    );
    _desktopSessions = DesktopSessionManager(
      nextId: core.ids,
      notifications: core.notifications,
    );
    _sharing = termEndpointPath == null
        ? null
        : TerminalSharing(
            endpointPath: termEndpointPath,
            sessions: _desktopSessions,
          );
    _router = SessionRouter(
      shells: core.sessions,
      desktop: _desktopSessions,
      desktopSharing: () => _sharing?.enabled ?? false,
    );
    _pairing = PairingCodeManager(now: _now);
    _service = AgentService(
      relay: _relay,
      api: params.api,
      deviceId: params.credentials.deviceId,
      identity: params.identity,
      trusted: params.trusted,
      sessions: _router,
      pairing: _pairing,
      appVersion: appVersion,
      clock: _now,
    );
  }

  final DateTime Function() _now;
  final SessionCore _core;
  late final RelayConnection _relay;
  late final DesktopSessionManager _desktopSessions;
  late final TerminalSharing? _sharing;
  late final SessionRouter _router;
  late final PairingCodeManager _pairing;
  late final AgentService _service;
```

- Replace `_notifications` uses with `_core.notifications`; `notifications` getter: `AgentNotifications? get notifications => _core.notifications;`; `shellSessions` getter: `SessionManager get shellSessions => _core.sessions;`.
- Replace `stop()`:

```dart
  /// AgentService.stop() drops the channels and stops the relay; first
  /// every phone is told `closed_by_host` and let go. No shell is killed
  /// (A1 D7). Desktop terminals only lose their phones (spec §7.2); the
  /// local server closes and `endpoint` goes, the windows keep running and
  /// retrying. The router is disposed last so the shell sessions stop
  /// forwarding into it.
  @override
  Future<void> stop() async {
    _running = false;
    unawaited(_eventWatch?.cancel());
    _eventWatch = null;
    _router.disconnectAllPhones();
    final stopping = _service.stop();
    try {
      await _sharing?.stop();
    } catch (_) {
      // Best effort: the windows keep running either way.
    }
    await stopping;
    _router.dispose();
  }
```

- Delete the `sessions`, `closeSession`, `closeAllSessions` overrides. In `start()`, `if (_core.notifications != null)`.

- [ ] **Step 6: `DesktopServices.sessions`**

In `desktop_services.dart` add `import 'package:shellx_agent/shellx_agent.dart';` (already imported) and a required constructor parameter `required this.sessions,` (after `runtimeFactory`) with the field:

```dart
  /// The process's one session manager (A1 D7), built in `main.dart` with
  /// [SessionCore]. It outlives every runtime: signing out or turning
  /// remote access off never ends a shell; only Quit does.
  final SessionManager sessions;
```

- [ ] **Step 7: `AgentController`**

In `agent_controller.dart`:
- Add a field `StreamSubscription<void>? _shellSubscription;`.
- `build()`:

```dart
  @override
  AgentViewState build() {
    _s = ref.watch(desktopServicesProvider);
    // Pairings, pairing_removed and revokes from AgentService all land in
    // the shared store.
    _trustedSubscription = _trusted.changes.listen(
      (_) => unawaited(_refreshTrusted()),
    );
    // Shell sessions live for the whole process (A1 D7): the tray lists
    // them and Quit counts them signed in or not.
    _shellSubscription = _s.sessions.changes.listen((_) {
      if (ref.mounted) state = state.copyWith(sessions: _s.sessions.sessions);
    });
    ref.onDispose(_dispose);
    return AgentViewState(sessions: _s.sessions.sessions);
  }
```

- `closeSession(int id) => _s.sessions.closeSession(id);` and `closeAllSessions() => _s.sessions.closeAll();` (doc: `/// Tray: ends shells; works without a runtime.`).
- `setRemoteAccess` doc: `/// Spec §8.3 as amended by A1 D7: off disconnects from the relay and every phone; the shells keep running. Remembered across restarts.`
- `shutdown()`:

```dart
  /// Before quitting (the caller then runs `quitApp`): disconnect, close
  /// every session (A1 D7: the only path that ends shells), wait (bounded)
  /// for the PTY tree kills, release the sleep assertion. Never throws, so
  /// quitting always goes on.
  Future<void> shutdown() async {
    _updateTimer?.cancel();
    _updateTimer = null;
    _wakeDetector?.stop();
    _wakeDetector = null;
    await _stopRuntime();
    _s.sessions.closeAll();
    await _settlePtyKills();
    await _bestEffort(() => _s.keepAwake.setEnabled(false));
  }
```

- `_startRuntime`: remove `sessions: runtime.sessions,` from the `copyWith`.
- `_stopRuntime`: remove `sessions: const <SessionSummary>[],` and change its doc first sentence to `/// Disconnects every phone and the relay; the shells keep running (A1 D7).`
- `_refreshSessions`: remove `sessions: runtime.sessions,` (it keeps refreshing the desktop terminals).
- `_dispose`: add `unawaited(_shellSubscription?.cancel());`.
- `signOut` / `_handleRevoked` docs: replace "closes every session" with "disconnects every phone (the shells keep running, A1 D7)".

- [ ] **Step 8: Tray remote-off confirmation**

In `tray_actions.dart` replace the `ToggleRemoteAccess` case with:

```dart
      case ToggleRemoteAccess():
        // A1 D7: turning off only disconnects phones; ask only when a phone
        // is connected right now.
        if (state.remoteAccess && state.activeChannels > 0) {
          final ok = await _router.confirm(
            ConfirmRequest(
              title: l10n.confirmRemoteOffTitle,
              body: l10n.confirmRemoteOffBody,
              confirmLabel: l10n.confirmRemoteOffAction,
            ),
          );
          if (!ok) return;
        }
        await _agent.setRemoteAccess(!state.remoteAccess);
```

and the class doc to `/// … asking for confirmation where an action is destructive or disconnects a phone.`

- [ ] **Step 9: Strings (UI §5 "Existing strings that D7 makes wrong")**

`app_en.arb`: replace `confirmRemoteOffBody` and delete its `@confirmRemoteOffBody` metadata block:

```json
  "confirmRemoteOffBody": "Connected phones will be disconnected. Terminal tabs on this computer keep running.",
  "confirmSignOutBody": "Connected phones will be disconnected and every paired phone will be removed. Terminal tabs on this computer keep running. After signing in again you must pair your phones again.",
  "confirmRevokeBody": "This phone loses access to this computer immediately and the sessions it opened are closed. Tabs opened on this computer keep running. To use it again you must pair it again.",
```

`app_vi.arb`:

```json
  "confirmRemoteOffBody": "Điện thoại đang kết nối sẽ bị ngắt. Các tab terminal trên máy này vẫn chạy.",
  "confirmSignOutBody": "Điện thoại đang kết nối sẽ bị ngắt và mọi điện thoại đã ghép sẽ bị gỡ. Các tab terminal trên máy này vẫn chạy. Sau khi đăng nhập lại, bạn phải ghép nối lại điện thoại.",
  "confirmRevokeBody": "Điện thoại này mất quyền truy cập máy tính ngay lập tức và các phiên nó mở bị đóng. Các tab mở trên máy này vẫn chạy. Muốn dùng lại phải ghép nối lại.",
```

(`confirmRevokeBody` is not in the UI doc table; it is corrected here because A1 D4 changes what a revoke ends — Task 1 kills only the sessions the phone opened.) Regenerate: `cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter gen-l10n`.

- [ ] **Step 10: `main.dart`**

Replace the block that builds `services` (from `final deviceName = …` through the `DesktopServices(` call) so the API and the core exist first:

```dart
  final deviceName = deviceNameFromHostname(Platform.localHostname);
  // Push spec §7: the threshold is read from the settings whenever a command
  // ends, so the tray choice applies at once; titles start with the name the
  // relay knows this computer by.
  final pushNotifications = PushNotificationsSetup(
    threshold: () => notifyThreshold(settings),
    machineName: () => deviceName,
    locale: () => Platform.localeName,
    hooksDirectory: '${supportDirectory.path}${Platform.pathSeparator}hooks',
  );
  // The app's one ShellxApi: the controller sets its token at sign-in.
  final api = ShellxApi(baseUri: relayBase);
  // A1 D7: the process's one SessionManager. It outlives every runtime, so
  // signing out or losing the relay never ends a shell; Quit does.
  final core = SessionCore(
    ptyFactory: ptyFactory,
    shellResolver: PlatformShellResolver(
      operatingSystem: Platform.operatingSystem,
      environment: environment,
    ),
    homeDirectory: home,
    baseEnvironment: environment,
    api: api,
    notifications: pushNotifications,
  );

  // The process's one SecureKeyValueStore; DesktopServices builds the one
  // TrustedStore over it.
  final services = DesktopServices(
    secureStore: SecureKeyValueStore(),
    settings: settings,
    api: api,
    createApi: () => ShellxApi(baseUri: relayBase),
    runtimeFactory: (params) => CoreAgentRuntime(
      params,
      core: core,
      relayBaseUri: relayBase,
      appVersion: info.version,
      termEndpointPath: sharingSetup == null
          ? null
          : termEndpointPath(
              environment: environment,
              windows: Platform.isWindows,
            ),
    ),
    sessions: core.sessions,
```

(the remaining `DesktopServices` arguments stay as they are) and add `import 'src/agent/session_core.dart';`.

- [ ] **Step 11: Run the tests to verify they pass**

Run: `cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test`
Expected: all pass (the macOS end-to-end sharing test keeps its existing skip/conditions).

- [ ] **Step 12: Format, analyze, commit**

```bash
cd apps/desktop
~/fvm/versions/3.41.4/bin/dart format --set-exit-if-changed lib test
PATH=~/fvm/versions/3.41.4/bin:$PATH flutter analyze
cd ../..
git add apps/desktop/lib/src/agent/session_core.dart apps/desktop/lib/src/agent/agent_runtime.dart apps/desktop/lib/src/agent/desktop_services.dart apps/desktop/lib/src/agent/agent_controller.dart apps/desktop/lib/src/tray/tray_actions.dart apps/desktop/lib/main.dart apps/desktop/lib/l10n apps/desktop/test/support/fake_pty.dart apps/desktop/test/support/fakes.dart apps/desktop/test/agent apps/desktop/test/ui/window_flow_test.dart apps/desktop/test/l10n/l10n_test.dart apps/desktop/test/terminal_sharing/end_to_end_macos_test.dart
git commit -m "feat(desktop): one SessionManager per process; sign-out, remote access off and relay loss only disconnect phones, Quit still kills every shell"
```

---

### Task 4: Desktop — xterm, JetBrains Mono, design tokens, terminal model helpers

Adds the pinned `xterm` dependency and the bundled font (D12, D16), the UI §1 tokens in one file, the mobile terminal palette, terminal style/grid helpers, and `DesktopTerminal`: an xterm `Terminal` that tells user input (keys, paste, mouse, IME text) apart from answers the emulator generates by itself, with mobile's cursor-key fix (vim/htop need DECCKM arrows, spec criterion 1) and paste sanitising.

**Files:**
- Modify: `apps/desktop/pubspec.yaml`
- Create: `apps/desktop/assets/fonts/JetBrainsMono-{Regular,Bold,Italic,BoldItalic}.ttf`, `apps/desktop/assets/licenses/JetBrainsMono-OFL.txt` (copies)
- Create: `apps/desktop/lib/src/ui/theme/shellx_desktop_theme.dart`
- Create: `apps/desktop/lib/src/ui/theme/terminal_colors.dart`
- Create: `apps/desktop/lib/src/ui/theme/font_licenses.dart`
- Create: `apps/desktop/lib/src/terminal/terminal_style.dart`
- Create: `apps/desktop/lib/src/terminal/terminal_input.dart`
- Create: `apps/desktop/lib/src/terminal/desktop_terminal.dart`
- Modify: `apps/desktop/lib/main.dart` (register font license)
- Test: `apps/desktop/test/ui/theme_test.dart`, `apps/desktop/test/terminal/terminal_style_test.dart`, `apps/desktop/test/terminal/desktop_terminal_test.dart`, `apps/desktop/test/platform/fonts_asset_test.dart`

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces:
  - `abstract final class ShellxDesktopColors` (every UI §1.1 token as `static const Color`, plus `primaryHover`, `primaryPressed`, `destructiveHover` from UI §3.3), `ShellxSpace`, `ShellxRadius`, `ShellxSizes`, `ShellxText`, `ShellxShadows`, `ShellxMotion`, `ThemeData buildDesktopTheme()`
  - `abstract final class TerminalColors` with `static const TerminalTheme theme`
  - `void registerFontLicenses()`
  - `const String kTerminalFontFamily = 'JetBrainsMono'`, `const double kTerminalFontSizeDefault = 13, kTerminalFontSizeMin = 9, kTerminalFontSizeMax = 28`, `TerminalStyle desktopTerminalStyle(double fontSize)`, `typedef TerminalGrid = ({int cols, int rows})`, `TerminalGrid? measureTerminalGrid(Size size, TerminalStyle style, TextScaler textScaler)`
  - `const TerminalInputHandler desktopInputHandler`, `String normalizeTypedText(String)`, `String normalizePastedText(String)`
  - `final class DesktopTerminal extends Terminal { DesktopTerminal({super.maxLines = 10000, super.platform}); void Function(String data)? onUserInput; void Function(String data)? onReply; }` — callers never set `onOutput`.

- [ ] **Step 1: Write the failing tests**

`apps/desktop/test/platform/fonts_asset_test.dart`:

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final pubspec = File('pubspec.yaml').readAsStringSync();

  test('xterm is pinned exactly to 4.0.0, like mobile (A1 D12)', () {
    expect(pubspec, contains(RegExp(r'^  xterm: 4\.0\.0$', multiLine: true)));
  });

  test('JetBrains Mono is bundled with its SIL OFL text (A1 D16)', () {
    expect(pubspec, contains('family: JetBrainsMono'));
    for (final face in ['Regular', 'Bold', 'Italic', 'BoldItalic']) {
      expect(
        File('assets/fonts/JetBrainsMono-$face.ttf').existsSync(),
        isTrue,
        reason: face,
      );
    }
    final license = File('assets/licenses/JetBrainsMono-OFL.txt');
    expect(license.readAsStringSync(), contains('SIL OPEN FONT LICENSE'));
    expect(pubspec, contains('- assets/licenses/'));
  });
}
```

`apps/desktop/test/ui/theme_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/ui/theme/shellx_desktop_theme.dart';
import 'package:shellx_desktop/src/ui/theme/terminal_colors.dart';

void main() {
  test('one dark theme built from the UI §1 tokens', () {
    final theme = buildDesktopTheme();
    expect(theme.brightness, Brightness.dark);
    expect(theme.scaffoldBackgroundColor, ShellxDesktopColors.bgTerminal);
    expect(theme.colorScheme.primary, ShellxDesktopColors.primary);
    expect(theme.colorScheme.surface, ShellxDesktopColors.surface);
    expect(theme.colorScheme.error, ShellxDesktopColors.errDialog);
  });

  test('the UI font is the platform default (no fontFamily, UI §1.3)', () {
    final theme = buildDesktopTheme();
    expect(theme.textTheme.bodyMedium?.fontFamily, isNot('JetBrainsMono'));
    expect(ShellxText.body.fontFamily, isNull);
    expect(ShellxText.body.fontSize, 13);
    expect(ShellxText.body.height! * 13, closeTo(18, 0.01));
  });

  test('tokens match UI §1.1 and the mobile terminal palette', () {
    expect(ShellxDesktopColors.bgTerminal, const Color(0xFF0B1215));
    expect(ShellxDesktopColors.bgSidebar, const Color(0xFF111B1E));
    expect(ShellxDesktopColors.accent, const Color(0xFF5FD4E2));
    expect(ShellxDesktopColors.warnBg, const Color(0xFF2A2412));
    expect(ShellxDesktopColors.scrim, const Color(0x99000000));
    expect(TerminalColors.theme.background, ShellxDesktopColors.bgTerminal);
    expect(TerminalColors.theme.selection, const Color(0x665FD4E2));
    expect(ShellxSizes.sidebarWidth, 220);
    expect(ShellxSizes.minWindow, const Size(640, 400));
    expect(ShellxSizes.defaultWindow, const Size(1100, 720));
  });
}
```

`apps/desktop/test/terminal/terminal_style_test.dart`:

```dart
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/terminal/terminal_style.dart';

void main() {
  test('JetBrains Mono 13, line height 1.2 (UI §1.3)', () {
    final style = desktopTerminalStyle(kTerminalFontSizeDefault);
    expect(style.fontFamily, 'JetBrainsMono');
    expect(style.fontSize, 13);
    expect(style.height, 1.2);
    expect((kTerminalFontSizeMin, kTerminalFontSizeMax), (9.0, 28.0));
  });

  test('grid measurement: null below one cell, columns grow with width', () {
    final style = desktopTerminalStyle(13);
    expect(
      measureTerminalGrid(const Size(1, 1), style, TextScaler.noScaling),
      isNull,
    );
    final narrow = measureTerminalGrid(
      const Size(400, 300),
      style,
      TextScaler.noScaling,
    )!;
    final wide = measureTerminalGrid(
      const Size(800, 300),
      style,
      TextScaler.noScaling,
    )!;
    expect(narrow.cols, greaterThan(0));
    expect(wide.cols, greaterThan(narrow.cols));
    expect(wide.rows, narrow.rows);
  });
}
```

`apps/desktop/test/terminal/desktop_terminal_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/terminal/desktop_terminal.dart';
import 'package:xterm/xterm.dart';

void main() {
  late DesktopTerminal terminal;
  late List<String> user;
  late List<String> replies;

  setUp(() {
    terminal = DesktopTerminal();
    user = [];
    replies = [];
    terminal
      ..onUserInput = user.add
      ..onReply = replies.add;
  });

  test('keys, text and paste are user input', () {
    terminal.keyInput(TerminalKey.enter);
    terminal.textInput('ls');
    terminal.paste('a\nb');
    expect(user, ['\r', 'ls', 'a\rb']);
    expect(replies, isEmpty);
  });

  test('answers the emulator generates are replies, not user input', () {
    terminal.write('\x1b[6n'); // cursor position report request
    expect(replies, hasLength(1));
    expect(replies.single, matches(RegExp(r'^\x1b\[\d+;\d+R$')));
    expect(user, isEmpty);
  });

  test('arrow keys follow DECCKM (vim, htop, less)', () {
    terminal.keyInput(TerminalKey.arrowUp);
    terminal.write('\x1b[?1h');
    terminal.keyInput(TerminalKey.arrowUp);
    expect(user, ['\x1b[A', '\x1bOA']);
  });

  test('pasted and IME text never carries escape sequences', () {
    terminal.paste('safe\x1b[201~evil');
    terminal.textInput('x\x1by\n');
    expect(user, ['safe[201~evil', 'xy\r']);
  });

  test('bracketed paste wraps the cleaned text', () {
    terminal.write('\x1b[?2004h');
    terminal.paste('echo hi');
    expect(user, ['\x1b[200~echo hi\x1b[201~']);
  });

  test('keeps 10 000 lines of scrollback (spec §3.2)', () {
    expect(terminal.maxLines, 10000);
  });
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/platform/fonts_asset_test.dart test/ui/theme_test.dart test/terminal`
Expected: FAIL — files/imports missing, pubspec has no xterm.

- [ ] **Step 3: Dependencies, fonts, licence**

```bash
mkdir -p apps/desktop/assets/fonts apps/desktop/assets/licenses
cp apps/mobile/assets/fonts/JetBrainsMono-Regular.ttf apps/mobile/assets/fonts/JetBrainsMono-Bold.ttf apps/mobile/assets/fonts/JetBrainsMono-Italic.ttf apps/mobile/assets/fonts/JetBrainsMono-BoldItalic.ttf apps/desktop/assets/fonts/
cp apps/mobile/assets/licenses/JetBrainsMono-OFL.txt apps/desktop/assets/licenses/
```

In `apps/desktop/pubspec.yaml` add under `dependencies:` (alphabetical, after `win32`/`window_manager`):

```yaml
  # Pinned exactly, same version as apps/mobile (A1 D12): the terminal works
  # around xterm 4.0.0's cursor-key and paste handling (terminal_input.dart),
  # which a newer version may change. Bump together with mobile, with the
  # benchmark (test/terminal/xterm_benchmark_test.dart) and a full test run.
  xterm: 4.0.0
```

and replace the `flutter:` section's `assets:` with:

```yaml
  assets:
    - assets/tray/
    - assets/licenses/
  fonts:
    # Terminal font (A1 D16), SIL OFL 1.1: assets/licenses/JetBrainsMono-OFL.txt
    - family: JetBrainsMono
      fonts:
        - asset: assets/fonts/JetBrainsMono-Regular.ttf
        - asset: assets/fonts/JetBrainsMono-Bold.ttf
          weight: 700
        - asset: assets/fonts/JetBrainsMono-Italic.ttf
          style: italic
        - asset: assets/fonts/JetBrainsMono-BoldItalic.ttf
          weight: 700
          style: italic
```

Run `cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter pub get`.

- [ ] **Step 4: Tokens (UI §1) and palette**

`apps/desktop/lib/src/ui/theme/shellx_desktop_theme.dart` — every value below is copied from the UI doc; when the doc changes, change it here only:

```dart
import 'package:flutter/material.dart';

/// UI §1.1. One dark theme for the whole window (A1 has no light theme).
abstract final class ShellxDesktopColors {
  static const Color bgTerminal = Color(0xFF0B1215);
  static const Color bgSidebar = Color(0xFF111B1E);
  static const Color rowHover = Color(0xFF172427);
  static const Color rowSelected = Color(0xFF1A272B);
  static const Color rowPressed = Color(0xFF203034);
  static const Color line = Color(0xFF243337);
  static const Color surface = Color(0xFF172023);
  static const Color surfaceInset = Color(0xFF0D1315);
  static const Color border = Color(0xFF2B373A);
  static const Color borderInput = Color(0xFF5E7176);
  static const Color textPrimary = Color(0xFFD4E1E4);
  static const Color textTitle = Color(0xFFE8F0F2);
  static const Color textSecondary = Color(0xFF93A5A9);
  static const Color textDialog2 = Color(0xFFA7B6BA);
  static const Color textPlaceholder = Color(0xFF6F8186);

  /// Decorative only (UI §1.1): never body text on the sidebar.
  static const Color dim = Color(0xFF6C8288);
  static const Color accent = Color(0xFF5FD4E2);
  static const Color primary = Color(0xFF2DBFCF);
  static const Color onPrimary = Color(0xFF04282D);
  static const Color primarySoft = Color(0xFF0E363C);
  static const Color ok = Color(0xFF7ED492);
  static const Color warn = Color(0xFFE9C46A);
  static const Color warnBg = Color(0xFF2A2412);
  static const Color warnBorder = Color(0xFF4A3F1C);
  static const Color err = Color(0xFFF07178);
  static const Color errDialog = Color(0xFFF26A70);
  static const Color onErr = Color(0xFF2A0A0C);
  static const Color noticeBg = Color(0xFF2A1416);
  static const Color noticeText = Color(0xFFFFD9DB);
  static const Color noticeBorder = Color(0xFF5A2A2E);
  static const Color scrim = Color(0x99000000);
  static const Color scrollThumb = Color(0xFF2B373A);
  static const Color scrollThumbHover = Color(0xFF3A4A4E);

  /// UI §3.3 button states.
  static const Color primaryHover = Color(0xFF4CCAD8);
  static const Color primaryPressed = Color(0xFF26A9B8);
  static const Color destructiveHover = Color(0xFFF4848A);
}

/// UI §1.2 spacing scale (px).
abstract final class ShellxSpace {
  static const double s2 = 2, s4 = 4, s6 = 6, s8 = 8, s12 = 12;
  static const double s16 = 16, s20 = 20, s24 = 24, s32 = 32;
}

/// UI §1.2 radii.
abstract final class ShellxRadius {
  static const double r4 = 4, r6 = 6, r8 = 8, r12 = 12, pill = 999;
}

/// UI §1.2 fixed sizes, §2 window, §2.2 sidebar, §2.5 pill, §2.8 toast,
/// §4 dialogs.
abstract final class ShellxSizes {
  static const double sidebarWidth = 220;
  static const double row = 30;
  static const double rowGap = 2;
  static const double headerBandMac = 38;
  static const double headerBandWindows = 36;
  static const double paneHeaderMac = 28;
  static const double signedOutStrip = 36;
  static const double driverPill = 28;
  static const double button = 32;
  static const double input = 36;
  static const double icon = 16;
  static const double iconHit = 28;
  static const double mark = 14;
  static const double dot = 8;
  static const double trafficLightsInset = 80;
  static const double listMarginH = 6;
  static const double listTop = 4;
  static const double listBottom = 8;
  static const Size minWindow = Size(640, 400);
  static const Size defaultWindow = Size(1100, 720);
  static const double dialogWidth = 400;
  static const double dialogWidthOnboarding = 480;
  static const double dialogWidthLong = 520;
  static const double toastMaxWidth = 420;
  static const double toastMinHeight = 36;
  static const double pillMaxWidth = 560;
  static const double emptyMaxWidth = 320;
  static const EdgeInsets terminalPadding = EdgeInsets.fromLTRB(10, 6, 10, 6);
}

/// UI §1.3. No fontFamily: the platform UI font (SF Pro / Segoe UI).
abstract final class ShellxText {
  static const TextStyle caption = TextStyle(
    fontSize: 11,
    height: 14 / 11,
    fontWeight: FontWeight.w500,
  );
  static const TextStyle small = TextStyle(fontSize: 12, height: 16 / 12);
  static const TextStyle body = TextStyle(fontSize: 13, height: 18 / 13);
  static const TextStyle bodyStrong = TextStyle(
    fontSize: 13,
    height: 18 / 13,
    fontWeight: FontWeight.w600,
  );
  static const TextStyle dialogBody = TextStyle(fontSize: 14, height: 20 / 14);
  static const TextStyle label = TextStyle(
    fontSize: 12.5,
    height: 16 / 12.5,
    fontWeight: FontWeight.w600,
  );
  static const TextStyle dialogTitle = TextStyle(
    fontSize: 17,
    height: 22 / 17,
    fontWeight: FontWeight.w600,
  );
  static const TextStyle emptyTitle = TextStyle(
    fontSize: 15,
    height: 20 / 15,
    fontWeight: FontWeight.w600,
  );
}

/// UI §1.4.
abstract final class ShellxShadows {
  static const List<BoxShadow> e1 = [
    BoxShadow(offset: Offset(0, 4), blurRadius: 16, color: Color(0x73000000)),
  ];
  static const List<BoxShadow> e2 = [
    BoxShadow(offset: Offset(0, 16), blurRadius: 48, color: Color(0x8C000000)),
  ];
}

/// UI §1.5. Use [of] so reduced motion turns every duration to zero.
abstract final class ShellxMotion {
  static const Duration fast = Duration(milliseconds: 80);
  static const Duration base = Duration(milliseconds: 150);
  static const Duration exit = Duration(milliseconds: 120);
  static const Duration toastIn = Duration(milliseconds: 160);
  static const Duration toastVisible = Duration(seconds: 4);
  static const Duration toastVisibleError = Duration(seconds: 6);
  static const Duration tooltipWait = Duration(milliseconds: 500);
  static const Duration scrollbarFade = Duration(milliseconds: 800);
  static const Curve fastCurve = Curves.easeOut;
  static const Curve baseCurve = Curves.easeOutCubic;
  static const Curve exitCurve = Curves.easeIn;

  static Duration of(BuildContext context, Duration duration) =>
      MediaQuery.disableAnimationsOf(context) ? Duration.zero : duration;
}

/// The window's only theme (replaces `colorSchemeSeed` in app.dart).
ThemeData buildDesktopTheme() {
  const colors = ColorScheme.dark(
    primary: ShellxDesktopColors.primary,
    onPrimary: ShellxDesktopColors.onPrimary,
    secondary: ShellxDesktopColors.accent,
    surface: ShellxDesktopColors.surface,
    onSurface: ShellxDesktopColors.textPrimary,
    error: ShellxDesktopColors.errDialog,
    onError: ShellxDesktopColors.onErr,
    outline: ShellxDesktopColors.borderInput,
    outlineVariant: ShellxDesktopColors.border,
  );
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: colors,
    scaffoldBackgroundColor: ShellxDesktopColors.bgTerminal,
    dividerColor: ShellxDesktopColors.line,
    dividerTheme: const DividerThemeData(
      color: ShellxDesktopColors.line,
      thickness: 1,
      space: 1,
    ),
    tooltipTheme: const TooltipThemeData(
      waitDuration: ShellxMotion.tooltipWait,
      textStyle: TextStyle(
        fontSize: 12,
        height: 16 / 12,
        color: ShellxDesktopColors.textPrimary,
      ),
      decoration: BoxDecoration(
        color: ShellxDesktopColors.rowSelected,
        borderRadius: BorderRadius.all(Radius.circular(ShellxRadius.r6)),
        border: Border.fromBorderSide(
          BorderSide(color: ShellxDesktopColors.border),
        ),
      ),
      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    ),
    inputDecorationTheme: const InputDecorationTheme(
      filled: true,
      fillColor: ShellxDesktopColors.surfaceInset,
      hintStyle: TextStyle(color: ShellxDesktopColors.textPlaceholder),
      labelStyle: TextStyle(color: ShellxDesktopColors.textDialog2),
      contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(ShellxRadius.r6)),
        borderSide: BorderSide(color: ShellxDesktopColors.borderInput),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(ShellxRadius.r6)),
        borderSide: BorderSide(color: ShellxDesktopColors.accent),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(ShellxRadius.r6)),
        borderSide: BorderSide(color: ShellxDesktopColors.errDialog),
      ),
    ),
  );
}
```

`apps/desktop/lib/src/ui/theme/terminal_colors.dart`: copy `apps/mobile/lib/core/design/terminal_colors.dart` **verbatim** (UI §1.1 last paragraph), changing only the doc comment's first line to `/// Terminal colours, copied verbatim from apps/mobile (UI §1.1; a shared package is a later milestone).`

`apps/desktop/lib/src/ui/theme/font_licenses.dart`:

```dart
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// JetBrains Mono is SIL OFL 1.1, whose text must ship with it.
void registerFontLicenses() {
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks([
      'JetBrains Mono',
    ], await rootBundle.loadString('assets/licenses/JetBrainsMono-OFL.txt'));
  });
}
```

In `main.dart` `_start`, right before `runApp(`, call `registerFontLicenses();` (import `src/ui/theme/font_licenses.dart`).

- [ ] **Step 5: Terminal style, input, `DesktopTerminal`**

`apps/desktop/lib/src/terminal/terminal_style.dart`:

```dart
import 'package:flutter/painting.dart';
import 'package:xterm/xterm.dart';

/// Bundled in pubspec.yaml (A1 D16).
const String kTerminalFontFamily = 'JetBrainsMono';

/// UI §1.3: 13 by default, steps of 1, clamped to 9–28.
const double kTerminalFontSizeDefault = 13;
const double kTerminalFontSizeMin = 9;
const double kTerminalFontSizeMax = 28;

TerminalStyle desktopTerminalStyle(double fontSize) => TerminalStyle(
  fontSize: fontSize,
  height: 1.2,
  fontFamily: kTerminalFontFamily,
);

typedef TerminalGrid = ({int cols, int rows});

/// Columns × rows of [style] cells that fit in [size], measured the way
/// xterm's RenderTerminal measures a cell (width of "mmmmmmmmmm" / 10, line
/// height). Null when not even one column or row fits. Copied from mobile's
/// terminal_metrics.dart.
TerminalGrid? measureTerminalGrid(
  Size size,
  TerminalStyle style,
  TextScaler textScaler,
) {
  final painter = TextPainter(
    text: TextSpan(text: 'mmmmmmmmmm', style: style.toTextStyle()),
    textDirection: TextDirection.ltr,
    textScaler: textScaler,
  )..layout();
  final cellWidth = painter.width / 10;
  final cellHeight = painter.height;
  painter.dispose();
  if (cellWidth <= 0 || cellHeight <= 0) return null;
  final cols = (size.width / cellWidth).floor();
  final rows = (size.height / cellHeight).floor();
  if (cols < 1 || rows < 1) return null;
  return (cols: cols, rows: rows);
}
```

`apps/desktop/lib/src/terminal/terminal_input.dart` — copy from `apps/mobile/lib/features/terminal/domain/terminal_input.dart` the class `CursorKeysInputHandler`, the regex `_unsafeControls`, `normalizeTypedText` and `normalizePastedText` verbatim (with their doc comments; drop `controlCharacterFor` and `applyModifiersToText`, desktop has no sticky modifiers), then add:

```dart
/// Input handler of every desktop terminal: the cursor-key fix first, then
/// xterm's defaults.
const TerminalInputHandler desktopInputHandler = CascadeInputHandler([
  CursorKeysInputHandler(),
  defaultInputHandler,
]);
```

`apps/desktop/lib/src/terminal/desktop_terminal.dart`:

```dart
import 'package:xterm/xterm.dart';

import 'terminal_input.dart';

/// xterm [Terminal] for a desktop tab. xterm reports both what the user
/// typed and what the emulator answers by itself (cursor position, device
/// attributes) through `onOutput`; this class splits them:
/// [onUserInput] takes the driver (A1 D6), [onReply] is written only while
/// the desktop drives (`LocalSessionView.reply`). Callers never set
/// `onOutput` themselves.
final class DesktopTerminal extends Terminal {
  DesktopTerminal({super.maxLines = 10000, super.platform})
    : super(inputHandler: desktopInputHandler) {
    onOutput = _route;
  }

  void Function(String data)? onUserInput;
  void Function(String data)? onReply;

  int _userDepth = 0;

  void _route(String data) =>
      (_userDepth > 0 ? onUserInput : onReply)?.call(data);

  T _asUser<T>(T Function() body) {
    _userDepth++;
    try {
      return body();
    } finally {
      _userDepth--;
    }
  }

  @override
  bool keyInput(
    TerminalKey key, {
    bool shift = false,
    bool alt = false,
    bool ctrl = false,
  }) => _asUser(() => super.keyInput(key, shift: shift, alt: alt, ctrl: ctrl));

  @override
  bool charInput(int charCode, {bool alt = false, bool ctrl = false}) =>
      _asUser(() => super.charInput(charCode, alt: alt, ctrl: ctrl));

  /// IME commits and plain text: control characters stripped, LF → CR.
  @override
  void textInput(String text) =>
      _asUser(() => super.textInput(normalizeTypedText(text)));

  /// Clipboard: cleaned so a paste can never end bracketed paste early.
  @override
  void paste(String text) =>
      _asUser(() => super.paste(normalizePastedText(text)));

  @override
  bool mouseInput(
    TerminalMouseButton button,
    TerminalMouseButtonState buttonState,
    CellOffset position,
  ) => _asUser(() => super.mouseInput(button, buttonState, position));
}
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test`
Expected: all pass.

- [ ] **Step 7: Format, analyze, commit**

```bash
cd apps/desktop
~/fvm/versions/3.41.4/bin/dart format --set-exit-if-changed lib test
PATH=~/fvm/versions/3.41.4/bin:$PATH flutter analyze
cd ../..
git add apps/desktop/pubspec.yaml apps/desktop/assets/fonts apps/desktop/assets/licenses apps/desktop/lib/src/ui/theme apps/desktop/lib/src/terminal/terminal_style.dart apps/desktop/lib/src/terminal/terminal_input.dart apps/desktop/lib/src/terminal/desktop_terminal.dart apps/desktop/lib/main.dart apps/desktop/test/platform/fonts_asset_test.dart apps/desktop/test/ui/theme_test.dart apps/desktop/test/terminal
git commit -m "feat(desktop): xterm 4.0.0 (pinned), bundled JetBrains Mono, UI design tokens, DesktopTerminal that separates user input from emulator replies"
```

---

### Task 5: Desktop — `TerminalTabs` model, output feed, font size

The window's state without widgets: one tab per session in creation order, an xterm `DesktopTerminal` per tab fed with `backlog` then `output` through a bounded `TerminalFeed`, typing → `view.write`, emulator answers → `view.reply`, layout size → `view.resize`, the D14 exit rules, the D15 "running command" check, notices for the 32-session limit and spawn failures, and the persisted font size.

**Files:**
- Create: `apps/desktop/lib/src/terminal/local_sessions_provider.dart`
- Create: `apps/desktop/lib/src/terminal/terminal_feed.dart`
- Create: `apps/desktop/lib/src/terminal/terminal_tabs.dart`
- Create: `apps/desktop/lib/src/terminal/terminal_font_size.dart`
- Modify: `apps/desktop/lib/src/platform/settings_store.dart` (`SettingKeys.terminalFontSize`)
- Modify: `apps/desktop/lib/l10n/app_en.arb`, `app_vi.arb` (`terminalExitedLine`) + regenerate
- Create: `apps/desktop/test/support/fake_local_sessions.dart`
- Test: `apps/desktop/test/terminal/terminal_feed_test.dart`, `terminal_tabs_test.dart`, `terminal_font_size_test.dart`

**Interfaces:**
- Consumes: `LocalSessions`, `LocalSessionView`, `SessionSummary` (+ `origin`, `title`, `driver`, `runningCommand`, `phoneAttached`), `SessionLimitException`, `SpawnFailedException` (Tasks 1–2); `DesktopServices.sessions`, `DesktopServices.l10n`, `DesktopServices.settings` (Task 3); `DesktopTerminal`, `TerminalGrid`, `kTerminalFontSize*` (Task 4).
- Produces:
  - `final localSessionsProvider = Provider<LocalSessions>(…)`, `final appL10nProvider = Provider<AppLocalizations>(…)`
  - `final class TerminalFeed { TerminalFeed(void Function(String) write, {int budget = 256 * 1024, int cap = 1024 * 1024, int keep = 512 * 1024, Duration tick = const Duration(milliseconds: 16)}); void add(List<int> bytes); void drain(); void dispose(); int get dropped; }`
  - `enum SpawnFailure { notFound, denied, other }`, `SpawnFailure spawnFailureOf(String message)`
  - `sealed class TabNotice`; `final class SessionLimitNotice extends TabNotice { final int max; }`; `final class SpawnFailedNotice extends TabNotice { final SpawnFailure kind; }`
  - `final class TerminalTab { int id, index; String shell, title; SessionOrigin origin; bool phoneAttached, runningCommand; DriverSide driver; DesktopTerminal terminal; TerminalController selection; int? exitCode; bool get exited; String get label; }`
  - `final class TerminalTabsState { List<TerminalTab> tabs; int? selectedId; TabNotice? notice; bool opening; TerminalTab? get selected; }`
  - `final terminalTabsProvider = NotifierProvider<TerminalTabs, TerminalTabsState>(TerminalTabs.new)` with `Future<void> openTab()`, `Future<void> ensureTab()`, `void select(int id)`, `void selectIndex(int position)` (1-based), `void next()`, `void previous()`, `bool needsCloseConfirm(int id)`, `void close(int id)`, `void dismissNotice()`, `void reportGrid(TerminalGrid grid)`
  - `final terminalFontSizeProvider = NotifierProvider<TerminalFontSize, double>(TerminalFontSize.new)` with `increase()`, `decrease()`, `reset()`
  - `SettingKeys.terminalFontSize = 'terminal_font_size'`
  - ARB `terminalExitedLine(int code)`

- [ ] **Step 1: Fake `LocalSessions` for tests**

`apps/desktop/test/support/fake_local_sessions.dart`:

```dart
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_core/shellx_core.dart';

/// Scriptable [LocalSessions]: tests add sessions (as if a phone opened
/// them), emit output and end shells.
final class FakeLocalSessions implements LocalSessions {
  final _changes = StreamController<void>.broadcast(sync: true);
  final summaries = <SessionSummary>[];
  final views = <int, FakeSessionView>{};
  final opens = <(int, int)>[];
  final closed = <int>[];
  int nextId = 100;

  /// When set, [open] throws it.
  Object? openError;

  /// When set, [open] waits for it.
  Completer<void>? openGate;

  @override
  List<SessionSummary> get sessions => List.of(summaries);
  @override
  Stream<void> get changes => _changes.stream;

  @override
  Future<int> open({required int cols, required int rows}) async {
    opens.add((cols, rows));
    await openGate?.future;
    final error = openError;
    if (error != null) throw error;
    final id = nextId++;
    add(summary(id, origin: SessionOrigin.desktop), notify: false);
    return id;
  }

  SessionSummary summary(
    int id, {
    SessionOrigin origin = SessionOrigin.phone,
    String title = '',
    bool runningCommand = false,
    String? attachedMobileId,
    DriverSide? driver,
  }) => SessionSummary(
    id: id,
    index: summaries.length + 1,
    shell: 'zsh',
    createdAt: DateTime(2026, 10, 6),
    attachedMobileId: attachedMobileId,
    origin: origin,
    title: title,
    runningCommand: runningCommand,
    driver:
        driver ??
        (origin == SessionOrigin.phone ? DriverSide.phone : DriverSide.desktop),
  );

  void add(SessionSummary summary, {bool notify = true, String backlog = ''}) {
    summaries.add(summary);
    views[summary.id] = FakeSessionView(summary.id, backlog);
    if (notify) _changes.add(null);
  }

  void replace(SessionSummary summary) {
    final i = summaries.indexWhere((s) => s.id == summary.id);
    summaries[i] = summary;
    _changes.add(null);
  }

  @override
  LocalSessionView view(int id) {
    final view = views[id];
    if (view == null) throw StateError('No session $id');
    view.viewed++;
    return view;
  }

  @override
  void close(int id) {
    closed.add(id);
    summaries.removeWhere((s) => s.id == id);
    _changes.add(null);
    views[id]?.end(-15, onRequest: true);
  }
}

final class FakeSessionView implements LocalSessionView {
  FakeSessionView(this.id, String backlogText)
    : backlog = Uint8List.fromList(utf8.encode(backlogText));

  @override
  final int id;
  @override
  final Uint8List backlog;
  final outputController = StreamController<Uint8List>();
  final driverController = StreamController<DriverSide>.broadcast(sync: true);
  final _exit = Completer<int>();
  final writes = <String>[];
  final replies = <String>[];
  final resizes = <(int, int)>[];
  int viewed = 0;
  bool disposed = false;
  bool _onRequest = false;

  void emit(String text) =>
      outputController.add(Uint8List.fromList(utf8.encode(text)));

  void end(int code, {bool onRequest = false}) {
    if (_exit.isCompleted) return;
    _onRequest = onRequest;
    _exit.complete(code);
    unawaited(outputController.close());
  }

  @override
  Stream<Uint8List> get output => outputController.stream;
  @override
  Stream<DriverSide> get driver => driverController.stream;
  @override
  Future<int> get exitCode => _exit.future;
  @override
  bool get closedOnRequest => _onRequest;
  @override
  void write(Uint8List data) => writes.add(utf8.decode(data));
  @override
  void reply(Uint8List data) => replies.add(utf8.decode(data));
  @override
  void resize(int cols, int rows) => resizes.add((cols, rows));
  @override
  void dispose() => disposed = true;
}
```

- [ ] **Step 2: Write the failing tests**

`apps/desktop/test/terminal/terminal_feed_test.dart`:

```dart
import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/terminal/terminal_feed.dart';

void main() {
  test('UTF-8 split across chunks is decoded whole', () {
    fakeAsync((async) {
      final written = <String>[];
      final feed = TerminalFeed(written.add);
      final bytes = utf8.encode('Tiếng Việt');
      feed.add(bytes.sublist(0, 3));
      feed.add(bytes.sublist(3));
      async.elapse(const Duration(milliseconds: 50));
      expect(written.join(), 'Tiếng Việt');
      feed.dispose();
    });
  });

  test('a burst is coalesced: one write now, the rest per tick', () {
    fakeAsync((async) {
      final written = <String>[];
      final feed = TerminalFeed(written.add);
      for (var i = 0; i < 1000; i++) {
        feed.add(utf8.encode('line $i\n'));
      }
      expect(written, hasLength(1)); // the first chunk, at once
      async.elapse(const Duration(milliseconds: 16));
      expect(written, hasLength(2)); // everything else in one write
      expect(written.join(), contains('line 999\n'));
      feed.dispose();
    });
  });

  test('never writes more than the budget per tick (the UI keeps painting)', () {
    fakeAsync((async) {
      final written = <String>[];
      final feed = TerminalFeed(written.add, budget: 10, cap: 1000, keep: 500);
      feed.add(utf8.encode('a')); // flushed now, starts the tick
      feed.add(utf8.encode('b' * 35));
      async.elapse(const Duration(milliseconds: 16));
      expect(written.last.length, 10);
      async.elapse(const Duration(milliseconds: 48));
      expect(written.skip(1).join(), 'b' * 35);
      expect(written.skip(1).every((w) => w.length <= 10), isTrue);
      feed.dispose();
    });
  });

  test('pending output is capped, keeping the newest whole lines', () {
    fakeAsync((async) {
      final written = <String>[];
      final feed = TerminalFeed(written.add, budget: 4, cap: 40, keep: 20);
      feed.add(utf8.encode('x')); // flushed now
      for (var i = 0; i < 20; i++) {
        feed.add(utf8.encode('row$i\n'));
      }
      expect(feed.dropped, greaterThan(0));
      feed.drain();
      final rest = written.skip(1).join();
      expect(rest, endsWith('row19\n'));
      expect(rest, isNot(contains('row0\n')));
      expect(rest.split('\n').first, startsWith('row')); // starts at a line
      feed.dispose();
    });
  });

  test('drain writes everything pending at once', () {
    fakeAsync((async) {
      final written = <String>[];
      final feed = TerminalFeed(written.add, budget: 2);
      feed.add(utf8.encode('ab'));
      feed.add(utf8.encode('cdef'));
      feed.drain();
      expect(written.join(), 'abcdef');
      feed.dispose();
    });
  });
}
```

`apps/desktop/test/terminal/terminal_tabs_test.dart`:

```dart
import 'dart:async';
import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:shellx_desktop/l10n/app_localizations.dart';
import 'package:shellx_desktop/src/terminal/local_sessions_provider.dart';
import 'package:shellx_desktop/src/terminal/terminal_tabs.dart';

import '../support/fake_local_sessions.dart';

void main() {
  late FakeLocalSessions local;
  late ProviderContainer container;

  TerminalTabs tabs() => container.read(terminalTabsProvider.notifier);
  TerminalTabsState state() => container.read(terminalTabsProvider);
  String text(int id) => state().tabs
      .firstWhere((t) => t.id == id)
      .terminal
      .buffer
      .getText();

  void boot() {
    container = ProviderContainer.test(
      overrides: [
        localSessionsProvider.overrideWithValue(local),
        appL10nProvider.overrideWithValue(
          lookupAppLocalizations(const Locale('en')),
        ),
      ],
    );
    state(); // build
  }

  setUp(() => local = FakeLocalSessions());

  test('sessions become tabs in creation order; backlog is written first', () async {
    local.add(local.summary(1), backlog: 'hello');
    local.add(local.summary(2, title: 'vim'));
    boot();
    expect(state().tabs.map((t) => t.id), [1, 2]);
    expect(text(1), contains('hello'));
    local.views[1]!.emit(' world');
    await pumpEventQueue();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(text(1), contains('hello world'));
  });

  test('the title falls back to "<shell> <index>" (D13)', () {
    local.add(local.summary(1));
    local.add(local.summary(2, title: 'htop'));
    boot();
    expect(state().tabs.map((t) => t.label), ['zsh 1', 'htop']);
  });

  test('openTab opens at the last measured grid and selects the tab', () async {
    boot();
    tabs().reportGrid((cols: 120, rows: 40));
    await tabs().openTab();
    expect(local.opens, [(120, 40)]);
    expect(state().selectedId, 100);
    expect(state().selected!.origin, SessionOrigin.desktop);
    expect(state().opening, isFalse);
  });

  test('a second openTab while one is in flight is ignored', () async {
    boot();
    local.openGate = Completer<void>();
    final first = tabs().openTab();
    expect(state().opening, isTrue);
    await tabs().openTab();
    local.openGate!.complete();
    await first;
    expect(local.opens, hasLength(1));
  });

  test('a tab opened from the phone is appended and not selected', () async {
    boot();
    await tabs().openTab();
    local.add(local.summary(7));
    await pumpEventQueue();
    expect(state().tabs.map((t) => t.id), [100, 7]);
    expect(state().selectedId, 100);
  });

  test('with nothing selected, the first tab that appears is selected', () async {
    boot();
    local.add(local.summary(7));
    await pumpEventQueue();
    expect(state().selectedId, 7);
  });

  test('the session limit becomes a notice and no tab', () async {
    boot();
    local.openError = const SessionLimitException(32);
    await tabs().openTab();
    expect(state().tabs, isEmpty);
    expect(state().notice, isA<SessionLimitNotice>());
    expect((state().notice! as SessionLimitNotice).max, 32);
    tabs().dismissNotice();
    expect(state().notice, isNull);
  });

  test('spawn failures are classified for the toast', () async {
    boot();
    local.openError = const SpawnFailedException(
      'ProcessException: No such file or directory',
    );
    await tabs().openTab();
    expect((state().notice! as SpawnFailedNotice).kind, SpawnFailure.notFound);
    expect(spawnFailureOf('Permission denied (errno = 13)'), SpawnFailure.denied);
    expect(spawnFailureOf('Bad state: boom'), SpawnFailure.other);
  });

  test('typing goes to write, emulator answers go to reply', () {
    local.add(local.summary(1));
    boot();
    final terminal = state().tabs.single.terminal;
    terminal.textInput('ls');
    terminal.write('\x1b[6n');
    expect(local.views[1]!.writes, ['ls']);
    expect(local.views[1]!.replies, hasLength(1));
  });

  test('layout size goes to resize', () {
    local.add(local.summary(1));
    boot();
    local.views[1]!.resizes.clear();
    state().tabs.single.terminal.resize(90, 30);
    expect(local.views[1]!.resizes, [(90, 30)]);
  });

  test('output keeps reaching a tab that is not selected (spec §5)', () async {
    local.add(local.summary(1));
    local.add(local.summary(2));
    boot();
    tabs().select(1);
    local.views[2]!.emit('background');
    await pumpEventQueue();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(text(2), contains('background'));
  });

  group('exit (D14)', () {
    test('exit 0 closes that tab and keeps the selection', () async {
      local.add(local.summary(1));
      local.add(local.summary(2));
      boot();
      tabs().select(1);
      local.views[2]!.end(0);
      await pumpEventQueue();
      expect(state().tabs.map((t) => t.id), [1]);
      expect(state().selectedId, 1);
      expect(local.views[2]!.disposed, isTrue);
    });

    test('a non-zero exit writes the line into that tab; Enter closes it, '
        'other keys are ignored', () async {
      local.add(local.summary(1));
      local.add(local.summary(2));
      boot();
      tabs().select(1);
      local.views[2]!.emit('error: build failed');
      local.views[2]!.end(2);
      await pumpEventQueue();
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final tab = state().tabs.firstWhere((t) => t.id == 2);
      expect(tab.exited, isTrue);
      expect(tab.exitCode, 2);
      expect(text(2), contains('error: build failed'));
      expect(text(2), contains('[Process exited with code 2]'));
      expect(state().selectedId, 1);

      tab.terminal.textInput('x');
      expect(state().tabs, hasLength(2));
      expect(local.views[2]!.writes, isEmpty);
      tab.terminal.textInput('\r');
      expect(state().tabs.map((t) => t.id), [1]);
    });

    test('a tab closed on request disappears even with a non-zero code', () async {
      local.add(local.summary(1));
      boot();
      local.views[1]!.end(-15, onRequest: true);
      await pumpEventQueue();
      expect(state().tabs, isEmpty);
    });
  });

  test('closing the selected tab kills it and selects its neighbour', () {
    local.add(local.summary(1));
    local.add(local.summary(2));
    local.add(local.summary(3));
    boot();
    tabs().select(2);
    tabs().close(2);
    expect(local.closed, [2]);
    expect(state().tabs.map((t) => t.id), [1, 3]);
    expect(state().selectedId, 3);
    tabs().close(3);
    expect(state().selectedId, 1);
    tabs().close(1);
    expect(state().selectedId, isNull);
  });

  test('closing asks only while a command runs (D15)', () {
    local.add(local.summary(1, runningCommand: true));
    local.add(local.summary(2));
    boot();
    expect(tabs().needsCloseConfirm(1), isTrue);
    expect(tabs().needsCloseConfirm(2), isFalse);
    local.replace(local.summary(1, runningCommand: false));
    expect(tabs().needsCloseConfirm(1), isFalse);
  });

  test('summary changes update the tab; driver changes arrive live', () {
    local.add(local.summary(1));
    boot();
    local.replace(
      local.summary(1, title: 'claude', attachedMobileId: 'm1'),
    );
    expect(state().tabs.single.label, 'claude');
    expect(state().tabs.single.phoneAttached, isTrue);
    local.views[1]!.driverController.add(DriverSide.desktop);
    expect(state().tabs.single.driver, DriverSide.desktop);
  });

  test('next/previous wrap; selectIndex picks the n-th tab', () {
    for (final id in [1, 2, 3]) {
      local.add(local.summary(id));
    }
    boot();
    tabs().select(3);
    tabs().next();
    expect(state().selectedId, 1);
    tabs().previous();
    expect(state().selectedId, 3);
    tabs().selectIndex(2);
    expect(state().selectedId, 2);
    tabs().selectIndex(9); // no 9th tab: unchanged
    expect(state().selectedId, 2);
  });

  test('ensureTab opens exactly one tab only when there is none', () async {
    boot();
    await Future.wait([tabs().ensureTab(), tabs().ensureTab()]);
    expect(local.opens, hasLength(1));
    await tabs().ensureTab();
    expect(local.opens, hasLength(1));
  });

  test('disposing the container disposes every view', () {
    local.add(local.summary(1));
    boot();
    container.dispose();
    expect(local.views[1]!.disposed, isTrue);
  });
}
```

`apps/desktop/test/terminal/terminal_font_size_test.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/agent/desktop_services.dart';
import 'package:shellx_desktop/src/platform/settings_store.dart';
import 'package:shellx_desktop/src/terminal/terminal_font_size.dart';

import '../support/fakes.dart';

void main() {
  test('13 by default, steps of 1, clamped to 9–28, reset to 13, persisted', () {
    final h = TestHarness();
    final container = ProviderContainer.test(
      overrides: [desktopServicesProvider.overrideWithValue(h.services())],
    );
    final size = container.read(terminalFontSizeProvider.notifier);
    expect(container.read(terminalFontSizeProvider), 13);
    size.increase();
    expect(container.read(terminalFontSizeProvider), 14);
    expect(h.settings.ints[SettingKeys.terminalFontSize], 14);
    for (var i = 0; i < 40; i++) {
      size.increase();
    }
    expect(container.read(terminalFontSizeProvider), 28);
    for (var i = 0; i < 40; i++) {
      size.decrease();
    }
    expect(container.read(terminalFontSizeProvider), 9);
    size.reset();
    expect(container.read(terminalFontSizeProvider), 13);
  });

  test('a stored size is read back (and clamped)', () {
    final h = TestHarness();
    h.settings.ints[SettingKeys.terminalFontSize] = 40;
    final container = ProviderContainer.test(
      overrides: [desktopServicesProvider.overrideWithValue(h.services())],
    );
    expect(container.read(terminalFontSizeProvider), 28);
  });

  test('the key is in the shared_preferences allow-list', () {
    expect(SettingKeys.all, contains(SettingKeys.terminalFontSize));
  });
}
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/terminal`
Expected: compile errors (`TerminalFeed`, `terminalTabsProvider`, `localSessionsProvider`, `terminalFontSizeProvider`, `SettingKeys.terminalFontSize` missing).

- [ ] **Step 4: Settings key and string**

`settings_store.dart`: add to `SettingKeys`

```dart
  /// Terminal font size in points (UI §1.3: 9–28, default 13).
  static const String terminalFontSize = 'terminal_font_size';
```

and add `terminalFontSize,` to `SettingKeys.all`.

ARB (UI §5 `terminalExitedLine`): `app_en.arb`

```json
  "terminalExitedLine": "[Process exited with code {code}] — press Enter to close",
  "@terminalExitedLine": {
    "placeholders": {
      "code": {"type": "int"}
    }
  },
```

`app_vi.arb`: `"terminalExitedLine": "[Tiến trình đã thoát, mã {code}] — Enter để đóng",`. Run `flutter gen-l10n` (command in Global Constraints).

- [ ] **Step 5: Providers**

`apps/desktop/lib/src/terminal/local_sessions_provider.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shellx_agent/shellx_agent.dart';

import '../../l10n/app_localizations.dart';
import '../agent/desktop_services.dart';

/// The window's only way into the sessions (A1 spec §3.1).
final localSessionsProvider = Provider<LocalSessions>(
  (ref) => ref.watch(desktopServicesProvider).sessions,
);

/// Strings for code that has no BuildContext (the exit line).
final appL10nProvider = Provider<AppLocalizations>(
  (ref) => ref.watch(desktopServicesProvider).l10n,
);
```

- [ ] **Step 6: `TerminalFeed`**

`apps/desktop/lib/src/terminal/terminal_feed.dart`:

```dart
import 'dart:async';
import 'dart:convert';

/// Turns one tab's output bytes into xterm writes the UI can keep up with
/// (spec criterion 8, Review Focus 2): UTF-8 is decoded across chunk
/// boundaries; the first chunk after a quiet period is written at once,
/// then output is coalesced into at most [budget] characters per [tick];
/// when more than [cap] characters wait (a flood while the window is hidden
/// or the tab is not selected), only the newest [keep] — cut at a line
/// start — are kept, like the agent's ring buffer drops the oldest bytes.
final class TerminalFeed {
  TerminalFeed(
    this._write, {
    this.budget = 256 * 1024,
    this.cap = 1024 * 1024,
    this.keep = 512 * 1024,
    this.tick = const Duration(milliseconds: 16),
  }) {
    _decoder = const Utf8Decoder(
      allowMalformed: true,
    ).startChunkedConversion(StringConversionSink.fromStringSink(_pending));
  }

  final void Function(String text) _write;
  final int budget;
  final int cap;
  final int keep;
  final Duration tick;
  final _pending = StringBuffer();
  late final ByteConversionSink _decoder;
  Timer? _timer;
  bool _disposed = false;

  /// How many times older pending output was dropped.
  int dropped = 0;

  void add(List<int> bytes) {
    if (_disposed) return;
    _decoder.add(bytes);
    _trim();
    if (_timer == null) _flush();
  }

  /// Writes everything pending now (before the exit line, D14).
  void drain() {
    _timer?.cancel();
    _timer = null;
    if (_pending.isEmpty) return;
    final text = _pending.toString();
    _pending.clear();
    _write(text);
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _timer = null;
  }

  void _flush() {
    _timer = null;
    if (_disposed || _pending.isEmpty) return;
    var text = _pending.toString();
    _pending.clear();
    if (text.length > budget) {
      var cut = budget;
      // Never split a surrogate pair between two writes.
      final unit = text.codeUnitAt(cut - 1);
      if (unit >= 0xD800 && unit <= 0xDBFF) cut--;
      _pending.write(text.substring(cut));
      text = text.substring(0, cut);
    }
    _write(text);
    _timer = Timer(tick, _flush);
  }

  void _trim() {
    if (_pending.length <= cap) return;
    final text = _pending.toString();
    var start = text.length - keep;
    final newline = text.indexOf('\n', start);
    if (newline != -1 && newline < text.length - 1) start = newline + 1;
    _pending
      ..clear()
      ..write(text.substring(start));
    dropped++;
  }
}
```

- [ ] **Step 7: `TerminalTabs`**

`apps/desktop/lib/src/terminal/terminal_tabs.dart`:

```dart
import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:xterm/xterm.dart';

import 'desktop_terminal.dart';
import 'local_sessions_provider.dart';
import 'terminal_feed.dart';
import 'terminal_style.dart';

enum SpawnFailure { notFound, denied, other }

/// Picks the toast wording of UI §5 `terminalSpawnFailed` from the error
/// text (never shown to the user as is).
SpawnFailure spawnFailureOf(String message) {
  final m = message.toLowerCase();
  if (m.contains('no such file') ||
      m.contains('not found') ||
      m.contains('errno = 2)') ||
      m.contains('cannot find')) {
    return SpawnFailure.notFound;
  }
  if (m.contains('permission denied') ||
      m.contains('errno = 13') ||
      m.contains('access is denied')) {
    return SpawnFailure.denied;
  }
  return SpawnFailure.other;
}

/// The floating notice of UI §2.8.
sealed class TabNotice {
  const TabNotice();
}

final class SessionLimitNotice extends TabNotice {
  const SessionLimitNotice(this.max);
  final int max;
}

final class SpawnFailedNotice extends TabNotice {
  const SpawnFailedNotice(this.kind);
  final SpawnFailure kind;
}

@immutable
final class TerminalTab {
  const TerminalTab({
    required this.id,
    required this.index,
    required this.shell,
    required this.title,
    required this.origin,
    required this.phoneAttached,
    required this.runningCommand,
    required this.driver,
    required this.terminal,
    required this.selection,
    this.exitCode,
  });

  final int id;
  final int index;
  final String shell;
  final String title;
  final SessionOrigin origin;
  final bool phoneAttached;
  final bool runningCommand;
  final DriverSide driver;
  final DesktopTerminal terminal;

  /// xterm selection (⌘C copies it).
  final TerminalController selection;

  /// Non-null once the shell exited with a non-zero code (D14).
  final int? exitCode;

  bool get exited => exitCode != null;

  /// OSC 0/2 title, else "<shell> <index>" (D13, UI §5 terminalDefaultTitle).
  String get label => title.isNotEmpty ? title : '$shell $index';

  TerminalTab copyWith({
    String? title,
    bool? phoneAttached,
    bool? runningCommand,
    DriverSide? driver,
    int? exitCode,
  }) => TerminalTab(
    id: id,
    index: index,
    shell: shell,
    title: title ?? this.title,
    origin: origin,
    phoneAttached: phoneAttached ?? this.phoneAttached,
    runningCommand: runningCommand ?? this.runningCommand,
    driver: driver ?? this.driver,
    terminal: terminal,
    selection: selection,
    exitCode: exitCode ?? this.exitCode,
  );
}

@immutable
final class TerminalTabsState {
  const TerminalTabsState({
    this.tabs = const [],
    this.selectedId,
    this.notice,
    this.opening = false,
  });

  final List<TerminalTab> tabs;
  final int? selectedId;
  final TabNotice? notice;

  /// An open is in flight (UI §3.2 busy `+`).
  final bool opening;

  TerminalTab? get selected {
    for (final tab in tabs) {
      if (tab.id == selectedId) return tab;
    }
    return null;
  }
}

/// What a tab holds that is not state: its view, feed and subscriptions.
final class _Link {
  _Link(this.view, this.terminal, this.feed);
  final LocalSessionView view;
  final DesktopTerminal terminal;
  final TerminalFeed feed;
  final subscriptions = <StreamSubscription<Object?>>[];

  void dispose() {
    for (final s in subscriptions) {
      unawaited(s.cancel());
    }
    feed.dispose();
    view.dispose();
  }
}

final terminalTabsProvider =
    NotifierProvider<TerminalTabs, TerminalTabsState>(TerminalTabs.new);

/// The window's tabs (spec §3.2): one per session, in creation order. Tabs
/// opened here are selected; tabs a phone opened are appended and not
/// selected (unless nothing is selected at all).
class TerminalTabs extends Notifier<TerminalTabsState> {
  late LocalSessions _local;
  final _links = <int, _Link>{};
  StreamSubscription<void>? _changes;

  /// The pane's grid, so a new shell starts at the size it will be shown.
  TerminalGrid _grid = (cols: 80, rows: 24);

  @override
  TerminalTabsState build() {
    _local = ref.watch(localSessionsProvider);
    _changes = _local.changes.listen((_) => _sync());
    ref.onDispose(_dispose);
    final tabs = _merge(const []);
    return TerminalTabsState(tabs: tabs, selectedId: tabs.firstOrNull?.id);
  }

  void reportGrid(TerminalGrid grid) => _grid = grid;

  Future<void> openTab() async {
    if (state.opening) return;
    _set(opening: true);
    try {
      final id = await _local.open(cols: _grid.cols, rows: _grid.rows);
      if (!ref.mounted) return;
      _sync();
      _set(selectedId: id, opening: false);
    } on SessionLimitException catch (error) {
      if (ref.mounted) _set(notice: SessionLimitNotice(error.max), opening: false);
    } on SpawnFailedException catch (error) {
      if (ref.mounted) {
        _set(
          notice: SpawnFailedNotice(spawnFailureOf(error.message)),
          opening: false,
        );
      }
    }
  }

  /// D11: activation and startup open a tab when there is none.
  Future<void> ensureTab() async {
    if (state.tabs.isEmpty && !state.opening) await openTab();
  }

  void select(int id) {
    if (state.tabs.any((t) => t.id == id)) _set(selectedId: id);
  }

  /// ⌘1…⌘9: the n-th tab (1-based); nothing when there is none.
  void selectIndex(int position) {
    if (position >= 1 && position <= state.tabs.length) {
      _set(selectedId: state.tabs[position - 1].id);
    }
  }

  void next() => _step(1);
  void previous() => _step(-1);

  /// D15: a close asks first while a command runs.
  bool needsCloseConfirm(int id) {
    final tab = _tab(id);
    return tab != null && !tab.exited && tab.runningCommand;
  }

  /// ⌘W, "Đóng tab", middle click: the desktop may close every session (D4).
  void close(int id) {
    final tab = _tab(id);
    if (tab == null) return;
    if (!tab.exited) _local.close(id);
    _remove(id);
  }

  void dismissNotice() => _set(notice: null);

  // ---- internals --------------------------------------------------------

  void _step(int delta) {
    final tabs = state.tabs;
    if (tabs.isEmpty) return;
    final i = tabs.indexWhere((t) => t.id == state.selectedId);
    final next = i < 0 ? 0 : (i + delta) % tabs.length;
    _set(selectedId: tabs[next < 0 ? next + tabs.length : next].id);
  }

  TerminalTab? _tab(int id) {
    for (final tab in state.tabs) {
      if (tab.id == id) return tab;
    }
    return null;
  }

  void _sync() {
    if (!ref.mounted) return;
    final tabs = _merge(state.tabs);
    _set(tabs: tabs, selectedId: state.selectedId ?? tabs.firstOrNull?.id);
  }

  /// Existing tabs keep their place (and stay while their session is gone
  /// but the exit is not handled yet); new sessions are appended.
  List<TerminalTab> _merge(List<TerminalTab> current) {
    final summaries = {for (final s in _local.sessions) s.id: s};
    final next = <TerminalTab>[];
    for (final tab in current) {
      final s = summaries.remove(tab.id);
      next.add(
        s == null
            ? tab
            : tab.copyWith(
                title: s.title,
                phoneAttached: s.phoneAttached,
                runningCommand: s.runningCommand,
                driver: s.driver,
              ),
      );
    }
    for (final s in summaries.values) {
      final tab = _attach(s);
      if (tab != null) next.add(tab);
    }
    return next;
  }

  TerminalTab? _attach(SessionSummary s) {
    final LocalSessionView view;
    try {
      view = _local.view(s.id);
    } on StateError {
      return null; // Ended between the listing and now.
    }
    final terminal = DesktopTerminal(platform: _platform());
    final feed = TerminalFeed(terminal.write);
    final link = _Link(view, terminal, feed);
    _links[s.id] = link;
    // Size first, without telling the session: the backlog is laid out at
    // the pane's width, and a phone keeps driving until the user acts.
    terminal.resize(_grid.cols, _grid.rows);
    feed.add(view.backlog);
    feed.drain();
    terminal
      ..onUserInput = (data) => _onUserInput(s.id, data)
      ..onReply = (data) => view.reply(utf8.encode(data))
      ..onResize = (cols, rows, _, _) {
        _grid = (cols: cols, rows: rows);
        view.resize(cols, rows);
      };
    link.subscriptions
      ..add(view.output.listen(feed.add))
      ..add(
        view.driver.listen((side) => _update(s.id, (t) => t.copyWith(driver: side))),
      );
    unawaited(view.exitCode.then((code) => _exited(s.id, code)));
    return TerminalTab(
      id: s.id,
      index: s.index,
      shell: s.shell,
      title: s.title,
      origin: s.origin,
      phoneAttached: s.phoneAttached,
      runningCommand: s.runningCommand,
      driver: s.driver,
      terminal: terminal,
      selection: TerminalController(),
    );
  }

  void _onUserInput(int id, String data) {
    final tab = _tab(id);
    if (tab == null) return;
    if (tab.exited) {
      // UI §2.6: Enter closes an exited tab; other keys are ignored.
      if (data.contains('\r')) _remove(id);
      return;
    }
    _links[id]?.view.write(utf8.encode(data));
  }

  void _exited(int id, int code) {
    if (!ref.mounted) return;
    final link = _links[id];
    if (link == null) return; // Already closed here.
    if (code == 0 || link.view.closedOnRequest) {
      _remove(id);
      return;
    }
    link.feed.drain();
    final terminal = link.terminal;
    final line = ref.read(appL10nProvider).terminalExitedLine(code);
    final at = line.indexOf('$code');
    final before = line.substring(0, at);
    final after = line.substring(at + '$code'.length);
    final newline = terminal.buffer.cursorX == 0 ? '' : '\r\n';
    // UI §2.6: dim text, the code in red, cursor hidden.
    terminal.write(
      '$newline\x1b[2m$before\x1b[22;31m$code\x1b[39;2m$after\x1b[0m\x1b[?25l',
    );
    _update(id, (t) => t.copyWith(exitCode: code));
  }

  void _update(int id, TerminalTab Function(TerminalTab tab) change) {
    if (!ref.mounted) return;
    _set(tabs: [for (final t in state.tabs) t.id == id ? change(t) : t]);
  }

  void _remove(int id) {
    _links.remove(id)?.dispose();
    final tabs = List.of(state.tabs);
    final i = tabs.indexWhere((t) => t.id == id);
    if (i < 0) return;
    tabs.removeAt(i);
    var selected = state.selectedId;
    if (selected == id) {
      selected = tabs.isEmpty ? null : tabs[min(i, tabs.length - 1)].id;
    }
    state = TerminalTabsState(
      tabs: tabs,
      selectedId: selected,
      notice: state.notice,
      opening: state.opening,
    );
  }

  static const Object _keep = Object();

  void _set({
    List<TerminalTab>? tabs,
    Object? selectedId = _keep,
    Object? notice = _keep,
    bool? opening,
  }) {
    state = TerminalTabsState(
      tabs: tabs ?? state.tabs,
      selectedId: identical(selectedId, _keep)
          ? state.selectedId
          : selectedId as int?,
      notice: identical(notice, _keep) ? state.notice : notice as TabNotice?,
      opening: opening ?? state.opening,
    );
  }

  TerminalTargetPlatform _platform() => switch (defaultTargetPlatform) {
    TargetPlatform.macOS => TerminalTargetPlatform.macos,
    TargetPlatform.windows => TerminalTargetPlatform.windows,
    _ => TerminalTargetPlatform.unknown,
  };

  void _dispose() {
    unawaited(_changes?.cancel());
    for (final link in _links.values) {
      link.dispose();
    }
    _links.clear();
  }
}
```

Implementation notes: the `build()` path calls `_merge` before `state` exists — `_merge` must not read `state` (it does not); `_attach` must not call `_set`. If the analyzer rejects the `(cols, rows, _, _)` wildcard parameters on this SDK, name them `(cols, rows, pixelWidth, pixelHeight)`.

- [ ] **Step 8: Font size**

`apps/desktop/lib/src/terminal/terminal_font_size.dart`:

```dart
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../agent/desktop_services.dart';
import '../platform/settings_store.dart';
import 'terminal_style.dart';

final terminalFontSizeProvider =
    NotifierProvider<TerminalFontSize, double>(TerminalFontSize.new);

/// ⌘+ / ⌘− / ⌘0 (spec criterion 2, UI §1.3), persisted in the settings.
class TerminalFontSize extends Notifier<double> {
  @override
  double build() {
    final stored = ref
        .watch(desktopServicesProvider)
        .settings
        .getInt(SettingKeys.terminalFontSize);
    return _clamp((stored ?? kTerminalFontSizeDefault).toDouble());
  }

  void increase() => _set(state + 1);
  void decrease() => _set(state - 1);
  void reset() => _set(kTerminalFontSizeDefault);

  void _set(double value) {
    final next = _clamp(value);
    if (next == state) return;
    state = next;
    final settings = ref.read(desktopServicesProvider).settings;
    unawaited(
      settings
          .setInt(SettingKeys.terminalFontSize, next.round())
          .catchError((Object _) {}),
    );
  }

  static double _clamp(double value) =>
      value.clamp(kTerminalFontSizeMin, kTerminalFontSizeMax).toDouble();
}
```

- [ ] **Step 9: Run the tests to verify they pass**

Run: `cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test`
Expected: all pass.

- [ ] **Step 10: Format, analyze, commit**

```bash
cd apps/desktop
~/fvm/versions/3.41.4/bin/dart format --set-exit-if-changed lib test
PATH=~/fvm/versions/3.41.4/bin:$PATH flutter analyze
cd ../..
git add apps/desktop/lib/src/terminal apps/desktop/lib/src/platform/settings_store.dart apps/desktop/lib/l10n apps/desktop/test/support/fake_local_sessions.dart apps/desktop/test/terminal
git commit -m "feat(desktop): TerminalTabs model (tab per session, bounded output feed, D14 exit rules, D15 running check, limit/spawn notices) and persisted terminal font size"
```

---

### Task 6: Desktop — terminal workspace UI

The window content of spec §3.2 / UI §2–§3: sidebar (header band with `+`, tab rows with dot, title, marks, context menu, middle-click close), terminal pane (pane header on macOS, signed-out strip, one `TerminalView` per tab in an `IndexedStack` so hidden tabs keep receiving output, driver pill, toast, empty state) and the D15 close flow. The workspace is not mounted in the app yet (Task 7 does that); this task tests it directly.

Every colour, size, radius, text style, duration, icon and string comes from the UI doc section named in the code comments: **UI §2.1** title bar/pane header, **§2.2** sidebar and row anatomy, **§2.3** pane, **§2.4** signed-out strip, **§2.5** driver pill, **§2.6** exit state (row look), **§2.7** empty state, **§2.8** toast, **§3.1** tab row states/marks/context menu/interaction, **§3.2** `+` button, **§3.3** buttons, **§3.5** tooltip, **§3.7** semantics, **§5** strings. Use the Task 4 token classes only — no literal colours or sizes in widget files.

**Files:**
- Create: `apps/desktop/lib/src/ui/terminal/terminal_workspace_page.dart`
- Create: `apps/desktop/lib/src/ui/terminal/session_sidebar.dart`
- Create: `apps/desktop/lib/src/ui/terminal/session_tab_row.dart`
- Create: `apps/desktop/lib/src/ui/terminal/terminal_pane.dart`
- Create: `apps/desktop/lib/src/ui/terminal/terminal_overlays.dart` (driver pill, toast, signed-out strip, empty state, buttons)
- Create: `apps/desktop/lib/src/ui/terminal/close_tab.dart`
- Create: `apps/desktop/lib/src/ui/terminal/shortcut_labels.dart`
- Modify: `apps/desktop/lib/l10n/app_en.arb`, `app_vi.arb` + regenerate
- Test: `apps/desktop/test/ui/terminal_workspace_test.dart`

**Interfaces:**
- Consumes: `terminalTabsProvider` / `TerminalTabs` / `TerminalTab` / `TerminalTabsState` / `TabNotice` / `SpawnFailure`, `terminalFontSizeProvider`, `localSessionsProvider` (Task 5); `desktopTerminalStyle`, `measureTerminalGrid`, `TerminalColors`, `ShellxDesktopColors`, `ShellxSizes`, `ShellxText`, `ShellxRadius`, `ShellxShadows`, `ShellxMotion` (Task 4); `agentControllerProvider`, `AuthPhase`; `windowRouterProvider`, `WindowRouter.open`, `WindowRouter.confirm`, `ConfirmRequest`, `LoginRoute` (existing).
- Produces:
  - `class TerminalWorkspacePage extends ConsumerStatefulWidget { const TerminalWorkspacePage({super.key}); }` with public state `TerminalWorkspacePageState` exposing `FocusNode get terminalFocus`, `FocusNode get sidebarFocus`, `void focusTerminal()` (Task 8 binds F6 and shortcuts to these)
  - `Future<void> closeTabWithConfirm({required TerminalTabs tabs, required WindowRouter router, required AppLocalizations l10n, required TerminalTab tab})`
  - `bool get isMacDesktop` (`defaultTargetPlatform == TargetPlatform.macOS`), `String newTabShortcutLabel()`, `String closeTabShortcutLabel()` in `shortcut_labels.dart`
  - Widget keys used by tests and Task 7/8: `Key('sidebar.newTab')`, `ValueKey('tab.<id>')`, `Key('pane.driverPill')`, `Key('pane.toast')`, `Key('pane.toast.close')`, `Key('pane.signedOutStrip')`, `Key('pane.signIn')`, `Key('pane.empty')`, `Key('pane.empty.open')`, `ValueKey('terminal.<id>')`, `Key('menu.closeTab')`
  - ARB keys of UI §5: `terminalNewTab`, `terminalNewTabTooltip(shortcut)`, `terminalCloseTab`, `terminalDriverPhone`, `terminalSignedOutStrip`, `terminalSignedOutAction`, `terminalEmptyTitle`, `terminalEmptyBody`, `terminalEmptyAction`, `terminalSessionLimit(max)`, `terminalSpawnFailed(reason)`, `toastDismiss`, `confirmCloseRunningTitle(title)`, `confirmCloseRunningBody`, `confirmCloseRunningAction`, `sidebarLabel`, `sidebarStatusIdle`, `sidebarStatusRunning`, `sidebarStatusExited(code)`, `sidebarPhoneOrigin`, `sidebarPhoneViewing`, `sidebarPhoneDriving`, `sidebarPosition(index, count)`, `terminalPaneLabel(title)`, plus lower-case semantics variants `sidebarPhoneOriginSemantics`, `sidebarPhoneViewingSemantics`, `sidebarPhoneDrivingSemantics` (UI §5 note).

- [ ] **Step 1: Strings**

Add to `app_en.arb` (values = UI §5 "en" column; placeholders with metadata) and `app_vi.arb` (UI §5 "vi" column), exactly as written in UI §5, for every key in the Produces list. Placeholder metadata in `app_en.arb`:

```json
  "terminalNewTabTooltip": "New tab  {shortcut}",
  "@terminalNewTabTooltip": {"placeholders": {"shortcut": {"type": "String"}}},
  "terminalSessionLimit": "You've reached the limit of {max} sessions. Close a tab to open a new one.",
  "@terminalSessionLimit": {"placeholders": {"max": {"type": "int"}}},
  "terminalSpawnFailed": "Couldn't start the shell: {reason, select, notFound{shell not found} denied{permission denied} other{system error}}. Try again.",
  "@terminalSpawnFailed": {"placeholders": {"reason": {"type": "String"}}},
  "confirmCloseRunningTitle": "Close “{title}”?",
  "@confirmCloseRunningTitle": {"placeholders": {"title": {"type": "String"}}},
  "sidebarStatusExited": "exited with code {code}",
  "@sidebarStatusExited": {"placeholders": {"code": {"type": "int"}}},
  "sidebarPosition": "tab {index} of {count}",
  "@sidebarPosition": {"placeholders": {"index": {"type": "int"}, "count": {"type": "int"}}},
  "terminalPaneLabel": "Terminal {title}",
  "@terminalPaneLabel": {"placeholders": {"title": {"type": "String"}}},
  "sidebarPhoneOriginSemantics": "opened from your phone",
  "sidebarPhoneViewingSemantics": "your phone is viewing",
  "sidebarPhoneDrivingSemantics": "your phone is using it",
```

Vietnamese semantics variants: `"sidebarPhoneOriginSemantics": "mở từ điện thoại"`, `"sidebarPhoneViewingSemantics": "điện thoại đang xem"`, `"sidebarPhoneDrivingSemantics": "điện thoại đang dùng"`. (`terminalDefaultTitle` is not added: "{shell} {index}" is identical in both languages and is built by `TerminalTab.label`, which has no `BuildContext`.) Regenerate with `flutter gen-l10n`.

- [ ] **Step 2: Write the failing widget tests**

`apps/desktop/test/ui/terminal_workspace_test.dart`:

```dart
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:shellx_desktop/l10n/app_localizations.dart';
import 'package:shellx_desktop/src/agent/agent_controller.dart';
import 'package:shellx_desktop/src/agent/desktop_services.dart';
import 'package:shellx_desktop/src/terminal/local_sessions_provider.dart';
import 'package:shellx_desktop/src/terminal/terminal_tabs.dart';
import 'package:shellx_desktop/src/ui/terminal/terminal_workspace_page.dart';
import 'package:shellx_desktop/src/ui/theme/shellx_desktop_theme.dart';
import 'package:shellx_desktop/src/ui/window_router.dart';

import '../support/fake_local_sessions.dart';
import '../support/fakes.dart';

late TestHarness h;
late FakeLocalSessions local;
late ProviderContainer container;

Future<void> pumpWorkspace(WidgetTester tester, {bool signedIn = true}) async {
  h = TestHarness(settings: {'onboarding_done': true});
  container = ProviderContainer(
    overrides: [
      desktopServicesProvider.overrideWithValue(h.services()),
      localSessionsProvider.overrideWithValue(local),
    ],
  );
  addTearDown(container.dispose);
  if (signedIn) await h.seedSignedIn();
  await container.read(agentControllerProvider.notifier).bootstrap(
    watchForWake: false,
  );
  tester.view.physicalSize = const Size(1100, 720);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: buildDesktopTheme(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: const Scaffold(body: TerminalWorkspacePage()),
      ),
    ),
  );
  await tester.pump();
}

TerminalTabsState tabs() => container.read(terminalTabsProvider);

void main() {
  setUp(() => local = FakeLocalSessions());

  testWidgets('sidebar lists tabs with title, origin and viewing marks', (
    tester,
  ) async {
    local.add(local.summary(1, origin: SessionOrigin.desktop));
    local.add(local.summary(2, title: 'claude', attachedMobileId: 'm1'));
    await pumpWorkspace(tester);

    expect(find.text('zsh 1'), findsWidgets); // row + macOS pane header
    expect(find.text('claude'), findsOneWidget);
    final phoneRow = find.byKey(const ValueKey('tab.2'));
    expect(
      find.descendant(of: phoneRow, matching: find.byIcon(Icons.smartphone)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: phoneRow, matching: find.byIcon(Icons.visibility)),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('tab.1')),
        matching: find.byIcon(Icons.smartphone),
      ),
      findsNothing,
    );
    expect(tester.getSize(find.byKey(const ValueKey('tab.1'))).height, 30);
  });

  testWidgets('clicking a row selects it and shows its terminal', (tester) async {
    local.add(local.summary(1));
    local.add(local.summary(2));
    await pumpWorkspace(tester);
    await tester.tap(find.byKey(const ValueKey('tab.2')));
    await tester.pump();
    expect(tabs().selectedId, 2);
  });

  testWidgets('+ opens a tab at the measured grid', (tester) async {
    await pumpWorkspace(tester);
    await tester.tap(find.byKey(const Key('sidebar.newTab')));
    await tester.pump();
    expect(local.opens, hasLength(1));
    final (cols, rows) = local.opens.single;
    expect(cols, greaterThan(80)); // a 1100 px window is wider than 80 cols
    expect(rows, greaterThan(10));
  });

  testWidgets('the driver pill shows only while the phone drives', (tester) async {
    local.add(local.summary(1, attachedMobileId: 'm1'));
    await pumpWorkspace(tester);
    expect(find.byKey(const Key('pane.driverPill')), findsOneWidget);
    expect(
      find.text('Your phone is using this terminal — type to take it back'),
      findsOneWidget,
    );
    local.views[1]!.driverController.add(DriverSide.desktop);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('pane.driverPill')), findsNothing);
  });

  testWidgets('signed out: the strip shows and opens the login dialog', (
    tester,
  ) async {
    await pumpWorkspace(tester, signedIn: false);
    expect(find.byKey(const Key('pane.signedOutStrip')), findsOneWidget);
    expect(find.text('Sign in to use this computer from your phone'), findsOneWidget);
    await tester.tap(find.byKey(const Key('pane.signIn')));
    expect(container.read(windowRouterProvider).route, isA<LoginRoute>());
  });

  testWidgets('signed in: no strip', (tester) async {
    await pumpWorkspace(tester);
    expect(find.byKey(const Key('pane.signedOutStrip')), findsNothing);
  });

  testWidgets('no tabs: the empty state opens a tab', (tester) async {
    await pumpWorkspace(tester);
    expect(find.byKey(const Key('pane.empty')), findsOneWidget);
    expect(find.text('No tabs open'), findsOneWidget);
    await tester.tap(find.byKey(const Key('pane.empty.open')));
    await tester.pump();
    expect(local.opens, hasLength(1));
  });

  testWidgets('the session limit shows a toast that can be dismissed', (
    tester,
  ) async {
    await pumpWorkspace(tester);
    local.openError = const SessionLimitException(32);
    await tester.tap(find.byKey(const Key('sidebar.newTab')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(
      find.text(
        "You've reached the limit of 32 sessions. Close a tab to open a new one.",
      ),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('pane.toast.close')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('pane.toast')), findsNothing);
  });

  testWidgets('the toast goes away on its own after 6 s', (tester) async {
    await pumpWorkspace(tester);
    local.openError = const SpawnFailedException('No such file or directory');
    await tester.tap(find.byKey(const Key('sidebar.newTab')));
    await tester.pump();
    expect(find.textContaining('shell not found'), findsOneWidget);
    await tester.pump(const Duration(seconds: 7));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('pane.toast')), findsNothing);
  });

  testWidgets('context menu "Close tab" closes an idle tab at once', (
    tester,
  ) async {
    local.add(local.summary(1));
    await pumpWorkspace(tester);
    await tester.tap(
      find.byKey(const ValueKey('tab.1')),
      buttons: kSecondaryButton,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('menu.closeTab')));
    await tester.pumpAndSettle();
    expect(local.closed, [1]);
  });

  testWidgets('closing a tab with a running command asks first (D15)', (
    tester,
  ) async {
    local.add(local.summary(1, title: 'claude', runningCommand: true));
    await pumpWorkspace(tester);
    await tester.tap(
      find.byKey(const ValueKey('tab.1')),
      buttons: kSecondaryButton,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('menu.closeTab')));
    await tester.pump();
    final confirm = container.read(windowRouterProvider).confirm!;
    expect(confirm.title, 'Close “claude”?');
    confirm.complete(false);
    await tester.pump();
    expect(local.closed, isEmpty);

    await tester.tap(
      find.byKey(const ValueKey('tab.1')),
      buttons: kSecondaryButton,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('menu.closeTab')));
    await tester.pump();
    container.read(windowRouterProvider).confirm!.complete(true);
    await tester.pump();
    expect(local.closed, [1]);
  });

  testWidgets('a middle click closes the tab', (tester) async {
    local.add(local.summary(1));
    await pumpWorkspace(tester);
    final center = tester.getCenter(find.byKey(const ValueKey('tab.1')));
    final gesture = await tester.startGesture(
      center,
      kind: PointerDeviceKind.mouse,
      buttons: kMiddleMouseButton,
    );
    await gesture.up();
    await tester.pump();
    expect(local.closed, [1]);
  });

  testWidgets('rows announce status, origin and position (UI §3.7)', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    local.add(local.summary(1, title: 'claude', runningCommand: true));
    local.add(local.summary(2, attachedMobileId: 'm1'));
    await pumpWorkspace(tester);
    expect(
      find.bySemanticsLabel(
        'claude, running a command, opened from your phone, tab 1 of 2',
      ),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel(
        'zsh 2, idle, opened from your phone, your phone is using it, '
        'tab 2 of 2',
      ),
      findsOneWidget,
    );
    semantics.dispose();
  });

  testWidgets('every tab stays mounted so hidden tabs keep their terminal', (
    tester,
  ) async {
    local.add(local.summary(1));
    local.add(local.summary(2));
    await pumpWorkspace(tester);
    expect(find.byKey(const ValueKey('terminal.1')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('terminal.2'), skipOffstage: false),
      findsOneWidget,
    );
  });
}
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/ui/terminal_workspace_test.dart`
Expected: compile error — `terminal_workspace_page.dart` missing.

- [ ] **Step 4: Shortcut labels and the close flow**

`apps/desktop/lib/src/ui/terminal/shortcut_labels.dart`:

```dart
import 'package:flutter/foundation.dart';

/// macOS shows ⌘ shortcuts; Windows Ctrl+Shift (spec criterion 2). Labels
/// are built from the platform, never translated (UI §5).
bool get isMacDesktop => defaultTargetPlatform == TargetPlatform.macOS;

String newTabShortcutLabel() => isMacDesktop ? '⌘T' : 'Ctrl+Shift+T';
String closeTabShortcutLabel() => isMacDesktop ? '⌘W' : 'Ctrl+Shift+W';
```

`apps/desktop/lib/src/ui/terminal/close_tab.dart`:

```dart
import '../../../l10n/app_localizations.dart';
import '../../terminal/terminal_tabs.dart';
import '../window_router.dart';

/// ⌘W, "Đóng tab", middle click (D15, UI §3.1): asks first while the shell
/// hook reports a running command, otherwise closes at once.
Future<void> closeTabWithConfirm({
  required TerminalTabs tabs,
  required WindowRouter router,
  required AppLocalizations l10n,
  required TerminalTab tab,
}) async {
  if (tabs.needsCloseConfirm(tab.id)) {
    final ok = await router.confirm(
      ConfirmRequest(
        title: l10n.confirmCloseRunningTitle(tab.label),
        body: l10n.confirmCloseRunningBody,
        confirmLabel: l10n.confirmCloseRunningAction,
      ),
    );
    if (!ok) return;
  }
  tabs.close(tab.id);
}
```

- [ ] **Step 5: Overlays and buttons (UI §2.4–§2.8, §3.3)**

`apps/desktop/lib/src/ui/terminal/terminal_overlays.dart`:

```dart
import 'dart:async';

import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../terminal/terminal_tabs.dart';
import '../theme/shellx_desktop_theme.dart';
import 'shortcut_labels.dart';

/// UI §3.3 primary button (32 high, min 80 wide, label bodyStrong).
class ShellxPrimaryButton extends StatelessWidget {
  const ShellxPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
  });
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => FilledButton(
    onPressed: onPressed,
    style: ButtonStyle(
      minimumSize: const WidgetStatePropertyAll(Size(80, ShellxSizes.button)),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 14),
      ),
      shape: const WidgetStatePropertyAll(
        RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(ShellxRadius.r6)),
        ),
      ),
      textStyle: const WidgetStatePropertyAll(ShellxText.bodyStrong),
      foregroundColor: const WidgetStatePropertyAll(
        ShellxDesktopColors.onPrimary,
      ),
      backgroundColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.pressed)
            ? ShellxDesktopColors.primaryPressed
            : states.contains(WidgetState.hovered)
            ? ShellxDesktopColors.primaryHover
            : ShellxDesktopColors.primary,
      ),
    ),
    child: Text(label),
  );
}

/// UI §2.4.
class SignedOutStrip extends StatelessWidget {
  const SignedOutStrip({super.key, required this.onSignIn});
  final VoidCallback onSignIn;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Container(
      key: const Key('pane.signedOutStrip'),
      height: ShellxSizes.signedOutStrip,
      decoration: const BoxDecoration(
        color: ShellxDesktopColors.rowSelected,
        border: Border(bottom: BorderSide(color: ShellxDesktopColors.line)),
      ),
      padding: const EdgeInsets.only(left: ShellxSpace.s12, right: ShellxSpace.s8),
      child: Row(
        children: [
          const Icon(
            Icons.cloud_off_outlined,
            size: ShellxSizes.icon,
            color: ShellxDesktopColors.textSecondary,
          ),
          const SizedBox(width: ShellxSpace.s8),
          Expanded(
            child: Text(
              l10n.terminalSignedOutStrip,
              style: ShellxText.body.copyWith(
                color: ShellxDesktopColors.textPrimary,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          TextButton(
            key: const Key('pane.signIn'),
            onPressed: onSignIn,
            style: TextButton.styleFrom(
              minimumSize: const Size(0, 28),
              padding: const EdgeInsets.symmetric(horizontal: 10),
              foregroundColor: ShellxDesktopColors.accent,
              textStyle: ShellxText.bodyStrong,
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.all(Radius.circular(ShellxRadius.r6)),
              ),
            ).copyWith(
              overlayColor: const WidgetStatePropertyAll(
                ShellxDesktopColors.rowHover,
              ),
            ),
            child: Text(l10n.terminalSignedOutAction),
          ),
        ],
      ),
    );
  }
}

/// UI §2.5: never interactive, never resizes the terminal.
class DriverPill extends StatelessWidget {
  const DriverPill({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return IgnorePointer(
      child: Semantics(
        liveRegion: true,
        child: Container(
          key: const Key('pane.driverPill'),
          height: ShellxSizes.driverPill,
          // With the 16 px side insets of its Positioned: min(560, pane − 32).
          constraints: const BoxConstraints(maxWidth: ShellxSizes.pillMaxWidth),
          padding: const EdgeInsets.symmetric(horizontal: ShellxSpace.s12),
          decoration: BoxDecoration(
            color: ShellxDesktopColors.warnBg,
            borderRadius: BorderRadius.circular(ShellxRadius.pill),
            border: Border.all(color: ShellxDesktopColors.warnBorder),
            boxShadow: ShellxShadows.e1,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.smartphone,
                size: ShellxSizes.mark,
                color: ShellxDesktopColors.warn,
              ),
              const SizedBox(width: ShellxSpace.s6),
              Flexible(
                child: Text(
                  l10n.terminalDriverPhone,
                  style: ShellxText.body.copyWith(
                    color: ShellxDesktopColors.warn,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// UI §2.8 error toast: 6 s, paused while hovered, one at a time.
class NoticeToast extends StatefulWidget {
  const NoticeToast({super.key, required this.notice, required this.onDismiss});
  final TabNotice notice;
  final VoidCallback onDismiss;

  @override
  State<NoticeToast> createState() => _NoticeToastState();
}

class _NoticeToastState extends State<NoticeToast> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void didUpdateWidget(NoticeToast old) {
    super.didUpdateWidget(old);
    if (!identical(old.notice, widget.notice)) _start();
  }

  void _start() {
    _timer?.cancel();
    _timer = Timer(ShellxMotion.toastVisibleError, widget.onDismiss);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _text(AppLocalizations l10n) => switch (widget.notice) {
    SessionLimitNotice(:final max) => l10n.terminalSessionLimit(max),
    SpawnFailedNotice(:final kind) => l10n.terminalSpawnFailed(kind.name),
  };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return MouseRegion(
      onEnter: (_) => _timer?.cancel(),
      onExit: (_) => _start(),
      child: Semantics(
        liveRegion: true,
        child: Container(
          key: const Key('pane.toast'),
          constraints: const BoxConstraints(
            maxWidth: ShellxSizes.toastMaxWidth,
            minHeight: ShellxSizes.toastMinHeight,
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: ShellxSpace.s12,
            vertical: ShellxSpace.s8,
          ),
          decoration: BoxDecoration(
            color: ShellxDesktopColors.noticeBg,
            borderRadius: BorderRadius.circular(ShellxRadius.r8),
            border: Border.all(color: ShellxDesktopColors.noticeBorder),
            boxShadow: ShellxShadows.e1,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.error_outline,
                size: ShellxSizes.icon,
                color: ShellxDesktopColors.noticeText,
              ),
              const SizedBox(width: ShellxSpace.s8),
              Flexible(
                child: Text(
                  _text(l10n),
                  style: ShellxText.body.copyWith(
                    color: ShellxDesktopColors.noticeText,
                  ),
                ),
              ),
              const SizedBox(width: ShellxSpace.s8),
              SizedBox.square(
                dimension: 24,
                child: IconButton(
                  key: const Key('pane.toast.close'),
                  padding: EdgeInsets.zero,
                  tooltip: l10n.toastDismiss,
                  onPressed: widget.onDismiss,
                  icon: const Icon(
                    Icons.close,
                    size: 14,
                    color: ShellxDesktopColors.noticeText,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// UI §2.7.
class EmptyTerminalState extends StatelessWidget {
  const EmptyTerminalState({super.key, required this.onOpen});
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Center(
      key: const Key('pane.empty'),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: ShellxSizes.emptyMaxWidth),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.terminal,
              size: 32,
              color: ShellxDesktopColors.textSecondary,
            ),
            const SizedBox(height: ShellxSpace.s12),
            Text(
              l10n.terminalEmptyTitle,
              style: ShellxText.emptyTitle.copyWith(
                color: ShellxDesktopColors.textPrimary,
              ),
            ),
            const SizedBox(height: ShellxSpace.s6),
            Text(
              l10n.terminalEmptyBody,
              textAlign: TextAlign.center,
              style: ShellxText.body.copyWith(
                color: ShellxDesktopColors.textSecondary,
              ),
            ),
            const SizedBox(height: ShellxSpace.s16),
            ShellxPrimaryButton(
              key: const Key('pane.empty.open'),
              label: l10n.terminalEmptyAction,
              onPressed: onOpen,
            ),
            const SizedBox(height: ShellxSpace.s8),
            Text(
              newTabShortcutLabel(),
              style: ShellxText.caption.copyWith(
                color: ShellxDesktopColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 6: Tab row (UI §3.1, §3.7)**

`apps/desktop/lib/src/ui/terminal/session_tab_row.dart`:

```dart
import 'dart:math';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_core/shellx_core.dart';

import '../../../l10n/app_localizations.dart';
import '../../terminal/terminal_tabs.dart';
import '../theme/shellx_desktop_theme.dart';
import 'shortcut_labels.dart';

class SessionTabRow extends StatefulWidget {
  const SessionTabRow({
    super.key,
    required this.tab,
    required this.selected,
    required this.position,
    required this.count,
    required this.onSelect,
    required this.onClose,
  });

  final TerminalTab tab;
  final bool selected;
  final int position;
  final int count;
  final VoidCallback onSelect;
  final VoidCallback onClose;

  @override
  State<SessionTabRow> createState() => _SessionTabRowState();
}

class _SessionTabRowState extends State<SessionTabRow> {
  bool _hover = false;
  bool _pressed = false;

  /// UI §3.7: title · status · [origin] · [viewing/driving] · position.
  String _semanticsLabel(AppLocalizations l10n) {
    final tab = widget.tab;
    final parts = <String>[
      tab.label,
      if (tab.exited)
        l10n.sidebarStatusExited(tab.exitCode!)
      else if (tab.runningCommand)
        l10n.sidebarStatusRunning
      else
        l10n.sidebarStatusIdle,
      if (tab.origin == SessionOrigin.phone) l10n.sidebarPhoneOriginSemantics,
      if (tab.phoneAttached)
        tab.driver == DriverSide.phone
            ? l10n.sidebarPhoneDrivingSemantics
            : l10n.sidebarPhoneViewingSemantics,
      l10n.sidebarPosition(widget.position, widget.count),
    ];
    return parts.join(', ');
  }

  Future<void> _menu(Offset at) async {
    final l10n = AppLocalizations.of(context);
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final choice = await showMenu<String>(
      context: context,
      color: ShellxDesktopColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(ShellxRadius.r8),
        side: const BorderSide(color: ShellxDesktopColors.border),
      ),
      position: RelativeRect.fromRect(
        at & const Size(1, 1),
        Offset.zero & overlay.size,
      ),
      constraints: const BoxConstraints(minWidth: 180),
      items: [
        PopupMenuItem<String>(
          key: const Key('menu.closeTab'),
          value: 'close',
          height: 28,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  l10n.terminalCloseTab,
                  style: ShellxText.body.copyWith(
                    color: ShellxDesktopColors.textPrimary,
                  ),
                ),
              ),
              Text(
                closeTabShortcutLabel(),
                style: ShellxText.caption.copyWith(
                  color: ShellxDesktopColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
    if (choice == 'close') widget.onClose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tab = widget.tab;
    final scale = MediaQuery.textScalerOf(context).scale(1);
    final height = max(ShellxSizes.row, 18 * scale + 12);
    final background = _pressed
        ? ShellxDesktopColors.rowPressed
        : widget.selected
        ? ShellxDesktopColors.rowSelected
        : _hover
        ? ShellxDesktopColors.rowHover
        : Colors.transparent;
    final titleStyle = tab.exited
        ? ShellxText.body.copyWith(color: ShellxDesktopColors.textSecondary)
        : widget.selected
        ? ShellxText.bodyStrong.copyWith(color: ShellxDesktopColors.textTitle)
        : ShellxText.body.copyWith(color: ShellxDesktopColors.textPrimary);

    return Semantics(
      button: true,
      selected: widget.selected,
      label: _semanticsLabel(l10n),
      onTap: widget.onSelect,
      customSemanticsActions: {
        CustomSemanticsAction(label: l10n.terminalCloseTab): widget.onClose,
      },
      excludeSemantics: true,
      child: Listener(
        onPointerDown: (event) {
          if (event.buttons == kMiddleMouseButton) widget.onClose();
        },
        child: MouseRegion(
          onEnter: (_) => setState(() => _hover = true),
          onExit: (_) => setState(() => _hover = false),
          child: GestureDetector(
            onTap: widget.onSelect,
            onTapDown: (_) => setState(() => _pressed = true),
            onTapUp: (_) => setState(() => _pressed = false),
            onTapCancel: () => setState(() => _pressed = false),
            onSecondaryTapUp: (details) => _menu(details.globalPosition),
            child: AnimatedContainer(
              duration: ShellxMotion.of(context, ShellxMotion.fast),
              curve: ShellxMotion.fastCurve,
              height: height,
              decoration: BoxDecoration(
                color: background,
                borderRadius: BorderRadius.circular(ShellxRadius.r6),
              ),
              child: Stack(
                children: [
                  if (widget.selected)
                    Positioned(
                      left: 0,
                      top: (height - 16) / 2,
                      child: Container(
                        width: 2,
                        height: 16,
                        decoration: BoxDecoration(
                          color: ShellxDesktopColors.accent,
                          borderRadius: BorderRadius.circular(ShellxRadius.r4),
                        ),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: ShellxSpace.s8,
                    ),
                    child: Row(
                      children: [
                        SizedBox(width: 16, child: Center(child: _Dot(tab))),
                        const SizedBox(width: ShellxSpace.s8),
                        Expanded(
                          child: Tooltip(
                            message: tab.label,
                            child: Text(
                              tab.label,
                              style: titleStyle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                        if (tab.origin == SessionOrigin.phone) ...[
                          const SizedBox(width: ShellxSpace.s4),
                          Tooltip(
                            message: l10n.sidebarPhoneOrigin,
                            child: const Icon(
                              Icons.smartphone,
                              size: ShellxSizes.mark,
                              color: ShellxDesktopColors.textSecondary,
                            ),
                          ),
                        ],
                        if (tab.phoneAttached) ...[
                          const SizedBox(width: ShellxSpace.s4),
                          Tooltip(
                            message: tab.driver == DriverSide.phone
                                ? l10n.sidebarPhoneDriving
                                : l10n.sidebarPhoneViewing,
                            child: Icon(
                              Icons.visibility,
                              size: ShellxSizes.mark,
                              color: tab.driver == DriverSide.phone
                                  ? ShellxDesktopColors.warn
                                  : ShellxDesktopColors.accent,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// UI §3.1 status dot: idle green, running cyan, exited hollow red.
class _Dot extends StatelessWidget {
  const _Dot(this.tab);
  final TerminalTab tab;

  @override
  Widget build(BuildContext context) {
    if (tab.exited) {
      return Container(
        width: ShellxSizes.dot,
        height: ShellxSizes.dot,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: ShellxDesktopColors.err, width: 1.5),
        ),
      );
    }
    return Container(
      width: ShellxSizes.dot,
      height: ShellxSizes.dot,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: tab.runningCommand
            ? ShellxDesktopColors.accent
            : ShellxDesktopColors.ok,
      ),
    );
  }
}
```

- [ ] **Step 7: Sidebar (UI §2.2, §3.2)**

`apps/desktop/lib/src/ui/terminal/session_sidebar.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import '../../../l10n/app_localizations.dart';
import '../../terminal/terminal_tabs.dart';
import '../theme/shellx_desktop_theme.dart';
import 'session_tab_row.dart';
import 'shortcut_labels.dart';

class SessionSidebar extends ConsumerWidget {
  const SessionSidebar({
    super.key,
    required this.focusNode,
    required this.scrollController,
    required this.onSelected,
    required this.onClose,
  });

  /// The list's single tab stop (UI §3.6).
  final FocusNode focusNode;

  /// Owned by the workspace page (outlives rebuilds).
  final ScrollController scrollController;

  /// After a click: select + focus the terminal (UI §3.1).
  final void Function(int id) onSelected;
  final void Function(TerminalTab tab) onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(terminalTabsProvider);
    final mac = isMacDesktop;
    final band = SizedBox(
      height: mac ? ShellxSizes.headerBandMac : ShellxSizes.headerBandWindows,
      child: Row(
        crossAxisAlignment: mac
            ? CrossAxisAlignment.start
            : CrossAxisAlignment.center,
        children: [
          if (mac) const SizedBox(width: ShellxSizes.trafficLightsInset),
          const Spacer(),
          Padding(
            // macOS: centred on the traffic-light line y = 14 (UI §2.1).
            padding: EdgeInsets.only(top: mac ? 14 - ShellxSizes.iconHit / 2 : 0),
            child: _NewTabButton(
              busy: state.opening,
              tooltip: l10n.terminalNewTabTooltip(newTabShortcutLabel()),
              onPressed: () =>
                  ref.read(terminalTabsProvider.notifier).openTab(),
            ),
          ),
          const SizedBox(width: ShellxSpace.s8),
        ],
      ),
    );
    final scroll = scrollController;
    return ColoredBox(
      color: ShellxDesktopColors.bgSidebar,
      child: Column(
        children: [
          if (mac) DragToMoveArea(child: band) else band,
          Expanded(
            child: Semantics(
              label: l10n.sidebarLabel,
              container: true,
              child: Focus(
                focusNode: focusNode,
                child: RawScrollbar(
                  controller: scroll,
                  thickness: 6,
                  radius: const Radius.circular(3),
                  padding: const EdgeInsets.only(right: 2),
                  thumbColor: ShellxDesktopColors.scrollThumb,
                  fadeDuration: ShellxMotion.of(
                    context,
                    ShellxMotion.fast,
                  ),
                  timeToFade: ShellxMotion.scrollbarFade,
                  child: ListView.separated(
                    controller: scroll,
                    padding: const EdgeInsets.fromLTRB(
                      ShellxSizes.listMarginH,
                      ShellxSizes.listTop,
                      ShellxSizes.listMarginH,
                      ShellxSizes.listBottom,
                    ),
                    itemCount: state.tabs.length,
                    separatorBuilder: (_, _) =>
                        const SizedBox(height: ShellxSizes.rowGap),
                    itemBuilder: (context, i) {
                      final tab = state.tabs[i];
                      return SessionTabRow(
                        key: ValueKey('tab.${tab.id}'),
                        tab: tab,
                        selected: tab.id == state.selectedId,
                        position: i + 1,
                        count: state.tabs.length,
                        onSelect: () => onSelected(tab.id),
                        onClose: () => onClose(tab),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// UI §3.2.
class _NewTabButton extends StatelessWidget {
  const _NewTabButton({
    required this.busy,
    required this.tooltip,
    required this.onPressed,
  });
  final bool busy;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: ShellxSizes.iconHit,
    child: IconButton(
      key: const Key('sidebar.newTab'),
      tooltip: tooltip,
      padding: EdgeInsets.zero,
      style: IconButton.styleFrom(
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(ShellxRadius.r6)),
        ),
        hoverColor: ShellxDesktopColors.rowHover,
        highlightColor: ShellxDesktopColors.rowPressed,
        foregroundColor: ShellxDesktopColors.textSecondary,
      ),
      onPressed: busy ? null : onPressed,
      icon: busy
          ? const SizedBox.square(
              dimension: 12,
              child: CircularProgressIndicator(strokeWidth: 1.5),
            )
          : const Icon(Icons.add, size: ShellxSizes.icon),
    ),
  );
}
```

(`busy` disables clicks only while an open is in flight; the 32 limit never disables it — UI §3.2.)

- [ ] **Step 8: Pane (UI §2.1 pane header, §2.3)**

`apps/desktop/lib/src/ui/terminal/terminal_pane.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:window_manager/window_manager.dart';
import 'package:xterm/xterm.dart';

import '../../../l10n/app_localizations.dart';
import '../../agent/agent_controller.dart';
import '../../agent/agent_state.dart';
import '../../terminal/terminal_font_size.dart';
import '../../terminal/terminal_style.dart';
import '../../terminal/terminal_tabs.dart';
import '../theme/shellx_desktop_theme.dart';
import '../theme/terminal_colors.dart';
import '../window_router.dart';
import 'shortcut_labels.dart';
import 'terminal_overlays.dart';

class TerminalPane extends ConsumerStatefulWidget {
  const TerminalPane({super.key, required this.terminalFocus, this.shortcuts});

  /// The selected tab's TerminalView focus (UI §3.6 region 1).
  final FocusNode terminalFocus;

  /// Passed to every TerminalView (Task 8: window shortcuts must win over
  /// xterm's own key handling).
  final Map<ShortcutActivator, Intent>? shortcuts;

  @override
  ConsumerState<TerminalPane> createState() => _TerminalPaneState();
}

class _TerminalPaneState extends ConsumerState<TerminalPane> {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(terminalTabsProvider);
    final fontSize = ref.watch(terminalFontSizeProvider);
    final phase = ref.watch(agentControllerProvider.select((s) => s.phase));
    final selected = state.selected;
    final style = desktopTerminalStyle(fontSize);
    final tabs = ref.read(terminalTabsProvider.notifier);
    final selectedIndex = selected == null ? 0 : state.tabs.indexOf(selected);

    return ColoredBox(
      color: ShellxDesktopColors.bgTerminal,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (isMacDesktop)
            DragToMoveArea(
              child: SizedBox(
                height: ShellxSizes.paneHeaderMac,
                child: Center(
                  child: FractionallySizedBox(
                    widthFactor: 0.6,
                    child: Text(
                      selected?.label ?? 'ShellX',
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: ShellxText.small.copyWith(
                        color: ShellxDesktopColors.textSecondary,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          AnimatedSwitcher(
            duration: ShellxMotion.of(context, ShellxMotion.base),
            child: phase == AuthPhase.signedOut
                ? SignedOutStrip(
                    onSignIn: () => ref
                        .read(windowRouterProvider.notifier)
                        .open(const LoginRoute()),
                  )
                : const SizedBox.shrink(),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final grid = measureTerminalGrid(
                  ShellxSizes.terminalPadding.deflateSize(constraints.biggest),
                  style,
                  MediaQuery.textScalerOf(context),
                );
                if (grid != null) tabs.reportGrid(grid);
                return Stack(
                  children: [
                    if (state.tabs.isEmpty)
                      EmptyTerminalState(onOpen: tabs.openTab)
                    else
                      IndexedStack(
                        index: selectedIndex < 0 ? 0 : selectedIndex,
                        sizing: StackFit.expand,
                        children: [
                          for (final tab in state.tabs)
                            Semantics(
                              key: ValueKey('terminal.${tab.id}'),
                              label: l10n.terminalPaneLabel(tab.label),
                              child: TerminalView(
                                tab.terminal,
                                controller: tab.selection,
                                focusNode: tab.id == selected?.id
                                    ? widget.terminalFocus
                                    : null,
                                autofocus: tab.id == selected?.id,
                                theme: TerminalColors.theme,
                                textStyle: style,
                                padding: ShellxSizes.terminalPadding,
                                shortcuts: widget.shortcuts,
                              ),
                            ),
                        ],
                      ),
                    if (selected != null &&
                        !selected.exited &&
                        selected.driver == DriverSide.phone)
                      const Positioned(
                        top: ShellxSpace.s8,
                        left: ShellxSpace.s16,
                        right: ShellxSpace.s16,
                        child: Center(child: DriverPill()),
                      ),
                    if (state.notice case final notice?)
                      Positioned(
                        bottom: ShellxSpace.s16,
                        left: ShellxSpace.s16,
                        right: ShellxSpace.s16,
                        child: Center(
                          child: NoticeToast(
                            notice: notice,
                            onDismiss: tabs.dismissNotice,
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
```

Notes: the driver pill must appear without a fade gap in tests that `pumpAndSettle`; if you add the UI §1.5 `base` fade-in / `exit` fade-out, use `AnimatedSwitcher` with `ShellxMotion.of`. `reportGrid` only stores a field (no state change), so calling it during layout is safe.

- [ ] **Step 9: Workspace page**

`apps/desktop/lib/src/ui/terminal/terminal_workspace_page.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../../terminal/terminal_tabs.dart';
import '../theme/shellx_desktop_theme.dart';
import '../window_router.dart';
import 'close_tab.dart';
import 'session_sidebar.dart';
import 'terminal_pane.dart';

/// Spec §3.2: `Row(Sidebar 220 px, VerticalDivider, TerminalPane)`.
class TerminalWorkspacePage extends ConsumerStatefulWidget {
  const TerminalWorkspacePage({super.key});

  @override
  ConsumerState<TerminalWorkspacePage> createState() =>
      TerminalWorkspacePageState();
}

class TerminalWorkspacePageState extends ConsumerState<TerminalWorkspacePage> {
  final terminalFocus = FocusNode(debugLabel: 'terminal');
  final sidebarFocus = FocusNode(debugLabel: 'sidebar');
  final sidebarScroll = ScrollController();

  /// Map of shortcuts handed to every TerminalView (filled by Task 8).
  Map<ShortcutActivator, Intent>? terminalShortcuts;

  /// After the frame, so a TerminalView that just got [terminalFocus] (a
  /// new selection) is attached first.
  void focusTerminal() => WidgetsBinding.instance.addPostFrameCallback(
    (_) => terminalFocus.requestFocus(),
  );

  Future<void> closeTab(TerminalTab tab) => closeTabWithConfirm(
    tabs: ref.read(terminalTabsProvider.notifier),
    router: ref.read(windowRouterProvider.notifier),
    l10n: AppLocalizations.of(context),
    tab: tab,
  );

  @override
  void dispose() {
    terminalFocus.dispose();
    sidebarFocus.dispose();
    sidebarScroll.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    focusTerminal(); // UI §3.6: the terminal has the initial focus.
  }

  @override
  Widget build(BuildContext context) {
    // A new selection gets the keyboard (UI §3.6), except while the
    // sidebar has it: its arrow keys (Task 8) move the selection and must
    // keep the focus in the list.
    ref.listen(terminalTabsProvider.select((s) => s.selectedId), (_, id) {
      if (id != null && !sidebarFocus.hasFocus) focusTerminal();
    });
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: ShellxSizes.sidebarWidth,
          child: SessionSidebar(
            focusNode: sidebarFocus,
            scrollController: sidebarScroll,
            onSelected: (id) {
              ref.read(terminalTabsProvider.notifier).select(id);
              focusTerminal();
            },
            onClose: closeTab,
          ),
        ),
        const VerticalDivider(width: 1),
        Expanded(
          child: TerminalPane(
            terminalFocus: terminalFocus,
            shortcuts: terminalShortcuts,
          ),
        ),
      ],
    );
  }
}
```

- [ ] **Step 10: Run the tests to verify they pass**

Run: `cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/ui/terminal_workspace_test.dart`
Expected: PASS. Then run the whole suite (`flutter test`) — nothing else changed.

- [ ] **Step 11: Format, analyze, commit**

```bash
cd apps/desktop
~/fvm/versions/3.41.4/bin/dart format --set-exit-if-changed lib test
PATH=~/fvm/versions/3.41.4/bin:$PATH flutter analyze
cd ../..
git add apps/desktop/lib/src/ui/terminal apps/desktop/lib/l10n apps/desktop/test/ui/terminal_workspace_test.dart
git commit -m "feat(desktop): terminal workspace UI (sidebar with status dots and phone marks, xterm pane per tab, driver pill, signed-out strip, empty state, toast, close with confirm while a command runs)"
```

---

### Task 7: Desktop — the terminal window shell (D9, D10, D11)

The single window becomes the terminal window: resizable (min 640×400, default 1100×720), bounds remembered, title `"{tab} — ShellX"`, closing hides it (shells keep running), the old routes and confirms become dialogs over it (UI §4), macOS shows a Dock icon / ⌘Tab / app menu while the window is visible and hands ⌘Q to Dart's Quit flow, Windows shows a taskbar button, every launch and reactivation opens the window and a tab if there is none, the tray gets "Mở cửa sổ terminal" first, and signing out no longer forces the login dialog at startup (the strip invites instead).

**Files:**
- Modify: `apps/desktop/lib/src/ui/window_router.dart` (whole `WindowState` / `WindowRouter`)
- Modify: `apps/desktop/lib/src/ui/window_host.dart` (whole file)
- Create: `apps/desktop/lib/src/ui/window_bounds.dart`
- Create: `apps/desktop/lib/src/ui/dialogs/route_dialog.dart`
- Modify: `apps/desktop/lib/src/ui/app.dart` (whole file)
- Modify: `apps/desktop/lib/src/ui/window_coordinator.dart`
- Modify: `apps/desktop/lib/src/ui/activation.dart` (whole file)
- Modify: `apps/desktop/lib/src/platform/app_reopen.dart` (whole file)
- Modify: `apps/desktop/lib/src/platform/settings_store.dart` (window bounds keys)
- Modify: `apps/desktop/lib/src/tray/tray_action.dart`, `tray_menu.dart`, `tray_actions.dart`
- Modify: `apps/desktop/lib/main.dart`
- Modify: `apps/desktop/macos/Runner/AppDelegate.swift` (whole file), `apps/desktop/macos/Runner/MainFlutterWindow.swift:16`
- Modify: `apps/desktop/lib/l10n/app_en.arb`, `app_vi.arb` + regenerate
- Test: `apps/desktop/test/ui/window_flow_test.dart`, `test/ui/pages_test.dart`, `test/ui/window_bounds_test.dart` (new), `test/ui/app_dialogs_test.dart` (new), `test/platform/app_reopen_test.dart`, `test/tray/tray_menu_test.dart`

**Interfaces:**
- Consumes: `TerminalWorkspacePage` / `TerminalWorkspacePageState.focusTerminal` (Task 6), `terminalTabsProvider` / `TerminalTabs.ensureTab` / `TerminalTabsState.selected` / `TerminalTab.label` (Task 5), `buildDesktopTheme`, `ShellxDesktopColors`, `ShellxSizes`, `ShellxRadius`, `ShellxShadows`, `ShellxSpace` (Task 4), `isMacDesktop` (Task 6), `SettingsStore` (existing), `TrayActions.handle(const Quit())` (existing).
- Produces:
  - `WindowState({WindowRoute? route, ConfirmRequest? confirm, bool terminal = false})`, `bool get dialogOpen`, `bool get visible`
  - `WindowRouter.showTerminal()`, `WindowRouter.hideWindow()`; `open`/`confirm` also show the window; `close()` closes only the dialog
  - `abstract interface class WindowHost { Future<void> show(); Future<void> hide(); Future<void> setTitle(String title); }`
  - `Size dialogSizeFor(WindowState state)`, `String windowTitleFor(TerminalTab? selected, AppLocalizations l10n)`
  - `final class WindowBoundsStore { WindowBoundsStore(SettingsStore settings); Rect? read(); Future<void> write(Rect bounds); }`
  - `Future<void> openTerminalWindow({required WindowRouter router, required TerminalTabs tabs})`, `Future<void> handleActivation(ProviderContainer container)`
  - `const MethodChannel appChannel`, `void listenForAppChannel({required void Function() onReopen, required void Function() onQuitRequested, MethodChannel channel = appChannel})`, `Future<void> setDockVisible(bool visible, {MethodChannel channel = appChannel})`
  - `final class OpenTerminalWindow extends TrayAction`, `TrayKeys.openTerminal = 'open_terminal'`
  - `SettingKeys.windowX/windowY/windowWidth/windowHeight`
  - ARB: `trayOpenTerminal`, `windowTitle(title)`, `dialogClose`; `notifyAlreadyRunningTitle` / `notifyAlreadyRunningBody` removed

- [ ] **Step 1: Strings**

`app_en.arb` (values from UI §5 and §4):

```json
  "trayOpenTerminal": "Open terminal window",
  "windowTitle": "{title} — ShellX",
  "@windowTitle": {"placeholders": {"title": {"type": "String"}}},
  "dialogClose": "Close",
```

`app_vi.arb`: `"trayOpenTerminal": "Mở cửa sổ terminal"`, `"windowTitle": "{title} — ShellX"`, `"dialogClose": "Đóng"`.

`onboardingTrayHint` (UI §5): prefix each branch — en `Your terminal lives in the ShellX window. ` + the existing text; vi `Terminal của bạn ở cửa sổ ShellX. ` + the existing text (inside both `macos{…}` and `other{…}` branches). Delete `notifyAlreadyRunningTitle`, `notifyAlreadyRunningBody` and `@notifyAlreadyRunningBody` from both files (activation no longer notifies). Regenerate with `flutter gen-l10n`.

- [ ] **Step 2: Write the failing tests**

(a) `apps/desktop/test/ui/window_bounds_test.dart`:

```dart
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/platform/settings_store.dart';
import 'package:shellx_desktop/src/ui/window_bounds.dart';

void main() {
  test('nothing stored: null (the host centres 1100×720)', () {
    expect(WindowBoundsStore(InMemorySettingsStore()).read(), isNull);
  });

  test('bounds round-trip through the settings', () async {
    final settings = InMemorySettingsStore();
    final store = WindowBoundsStore(settings);
    await store.write(const Rect.fromLTWH(40, 60, 1200, 800));
    expect(store.read(), const Rect.fromLTWH(40, 60, 1200, 800));
  });

  test('bounds below the minimum size are ignored', () async {
    final settings = InMemorySettingsStore();
    final store = WindowBoundsStore(settings);
    await store.write(const Rect.fromLTWH(0, 0, 300, 200));
    expect(store.read(), isNull);
  });

  test('a failing settings write is swallowed', () async {
    final settings = InMemorySettingsStore()..fail = true;
    await WindowBoundsStore(settings).write(const Rect.fromLTWH(0, 0, 900, 600));
  });

  test('the keys are in the shared_preferences allow-list', () {
    expect(
      SettingKeys.all,
      containsAll([
        SettingKeys.windowX,
        SettingKeys.windowY,
        SettingKeys.windowWidth,
        SettingKeys.windowHeight,
      ]),
    );
  });
}
```

(b) `apps/desktop/test/platform/app_reopen_test.dart` — replace with:

```dart
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/platform/app_reopen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  Future<void> send(String method) => messenger.handlePlatformMessage(
    appChannel.name,
    appChannel.codec.encodeMethodCall(MethodCall(method)),
    (_) {},
  );

  tearDown(() {
    appChannel.setMethodCallHandler(null);
    messenger.setMockMethodCallHandler(appChannel, null);
  });

  test('reopen and quitRequested from AppDelegate reach their handlers', () async {
    var reopens = 0;
    var quits = 0;
    listenForAppChannel(onReopen: () => reopens++, onQuitRequested: () => quits++);
    await send('reopen');
    await send('reopen');
    await send('quitRequested');
    await send('somethingElse');
    expect((reopens, quits), (2, 1));
  });

  test('setDockVisible calls the native side with a bool', () async {
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(appChannel, (call) async {
      calls.add(call);
      return null;
    });
    await setDockVisible(true);
    await setDockVisible(false);
    expect([for (final c in calls) (c.method, c.arguments)], [
      ('setDockVisible', true),
      ('setDockVisible', false),
    ]);
  });

  test('the channel name matches AppDelegate.swift', () {
    expect(appChannel.name, 'pro.shellx.desktop/app');
  });
}
```

(c) `test/ui/window_flow_test.dart`:
- `_FakeWindowHost` becomes:

```dart
final class _FakeWindowHost implements WindowHost {
  final List<String> calls = [];
  @override
  Future<void> show() async => calls.add('show');
  @override
  Future<void> hide() async => calls.add('hide');
  @override
  Future<void> setTitle(String title) async => calls.add('title $title');
}
```

- In 'closing the QR window invalidates the pairing code' replace `expect(window().visible, isFalse);` with `expect(window().route, isNull); expect(window().visible, isTrue); // the terminal window stays`.
- In 'a phone finishing pairing closes the QR window' replace `expect(window().visible, isFalse);` with `expect(window().route, isNull);`.
- In 'signing in from the login window hides it (onboarding already done)' rename to '… closes it …' and replace the last expectation with `expect(window().route, isNull);`.
- Replace 'startup signed out opens the login window' with:

```dart
    test('startup signed out opens no dialog: the strip invites (D11)', () async {
      h = TestHarness();
      container = ProviderContainer.test(
        overrides: [desktopServicesProvider.overrideWithValue(h.services())],
      );
      container.listen(
        agentControllerProvider,
        (prev, next) => coordinateWindows(prev, next, router()),
      );
      await agent().bootstrap(watchForWake: false);
      expect(window().route, isNull);
    });

    test('a user sign-out still shows the login dialog', () async {
      await signedIn(settings: {'onboarding_done': true});
      await agent().signOut();
      expect(window().route, isA<LoginRoute>());
    });
```

- Replace the whole `group('handleActivation (second launch, macOS reopen)', …)` with:

```dart
  group('handleActivation (launch, second launch, Dock, macOS reopen)', () {
    test('signed out: the terminal window with one tab, no login dialog', () async {
      h = TestHarness();
      container = ProviderContainer.test(
        overrides: [desktopServicesProvider.overrideWithValue(h.services())],
      );
      await agent().bootstrap(watchForWake: false);
      await handleActivation(container);
      expect(window().terminal, isTrue);
      expect(window().route, isNull);
      expect(h.ptys.ptys, hasLength(1));
      expect(h.notifier.shown, isEmpty);
    });

    test('again: the window comes forward, no second tab', () async {
      await signedIn(settings: {'onboarding_done': true});
      await handleActivation(container);
      router().hideWindow();
      await handleActivation(container);
      expect(window().visible, isTrue);
      expect(h.ptys.ptys, hasLength(1));
    });

    test('a phone-opened session counts as a tab (none is added)', () async {
      await signedIn(settings: {'onboarding_done': true});
      await h.sessions.handle(
        '33333333-3333-4333-8333-333333333333',
        const SessionOpen(cols: 80, rows: 24),
      );
      await pumpEventQueue();
      await handleActivation(container);
      expect(h.ptys.ptys, hasLength(1));
    });
  });

  group('window close (D9)', () {
    test('hides the window, cancels an open confirm, keeps the shells', () async {
      await signedIn(settings: {'onboarding_done': true});
      await handleActivation(container);
      final pending = router().confirm(
        ConfirmRequest(title: 't', body: 'b', confirmLabel: 'ok'),
      );
      router().hideWindow();
      expect(await pending, isFalse);
      expect(window().visible, isFalse);
      expect(h.ptys.ptys.single.killed, isFalse);
    });

    test('Escape-style close only closes the dialog', () async {
      await signedIn(settings: {'onboarding_done': true});
      await handleActivation(container);
      router().open(const ChangePasswordRoute());
      router().close();
      expect(window().route, isNull);
      expect(window().visible, isTrue);
    });
  });
```

- In `group('TrayActions')` add:

```dart
    test('"Open terminal window" shows the window with a tab', () async {
      await signedIn(settings: {'onboarding_done': true});
      await tray().handle(const OpenTerminalWindow());
      expect(window().terminal, isTrue);
      expect(h.ptys.ptys, hasLength(1));
    });

    test('a second ⌘Q while the quit confirm is open leaves one confirm and '
        'quits once', () async {
      await signedIn(settings: {'onboarding_done': true});
      await h.sessions.open(cols: 80, rows: 24);
      await pumpEventQueue();
      final first = tray().handle(const Quit());
      await pumpEventQueue();
      final second = tray().handle(const Quit());
      await pumpEventQueue();
      await first; // replaced: answered "no"
      expect(window().confirm, isNotNull);
      window().confirm!.complete(true);
      await second;
      expect(h.quits, 1);
      expect(h.ptys.ptys.single.killed, isTrue);
    });
```

- Replace the `WindowPresenter` test with:

```dart
  test('WindowPresenter shows once while anything is visible, hides when '
      'nothing is', () async {
    final host = _FakeWindowHost();
    final presenter = WindowPresenter(host);
    await presenter.apply(const WindowState(terminal: true));
    await presenter.apply(
      const WindowState(terminal: true, route: LoginRoute()),
    );
    await presenter.apply(const WindowState());
    await presenter.apply(const WindowState(route: PairingRoute()));
    expect(host.calls, ['show', 'hide', 'show']);
  });

  test('window title: "<tab> — ShellX", or "ShellX" without tabs', () {
    final l10n = lookupAppLocalizations(const Locale('vi'));
    expect(windowTitleFor(null, l10n), 'ShellX');
  });

  test('dialog sizes follow UI §4 widths', () {
    expect(dialogSizeFor(const WindowState(route: LoginRoute())).width, 400);
    expect(
      dialogSizeFor(const WindowState(route: OnboardingRoute())).width,
      480,
    );
    expect(
      dialogSizeFor(
        WindowState(
          confirm: ConfirmRequest(
            title: 't',
            body: 'b',
            confirmLabel: 'ok',
            long: true,
          ),
        ),
      ).width,
      520,
    );
  });
```

  (imports to add: `package:shellx_desktop/l10n/app_localizations.dart`, `package:shellx_desktop/src/ui/dialogs/route_dialog.dart`; drop `dart:ui`'s `Size` usage if unused.)

(d) `test/ui/pages_test.dart`: change `tester.view.physicalSize = const Size(520, 700);` to `const Size(1100, 720)` (UI §2 default window: the dialogs need their full height). Any expectation that the window became invisible after a page finished (e.g. 'closes itself once the phone is paired') becomes `expect(router().current, isNull)`.

(e) New `apps/desktop/test/ui/app_dialogs_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/agent/agent_controller.dart';
import 'package:shellx_desktop/src/agent/desktop_services.dart';
import 'package:shellx_desktop/src/ui/app.dart';
import 'package:shellx_desktop/src/ui/window_router.dart';

import '../support/fakes.dart';

void main() {
  late TestHarness h;
  late ProviderContainer container;

  Future<void> pump(WidgetTester tester) async {
    h = TestHarness(settings: {'onboarding_done': true});
    container = ProviderContainer(
      overrides: [desktopServicesProvider.overrideWithValue(h.services())],
    );
    addTearDown(container.dispose);
    await container.read(agentControllerProvider.notifier).bootstrap(
      watchForWake: false,
    );
    tester.view.physicalSize = const Size(1100, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const ShellxDesktopApp(locale: Locale('en')),
      ),
    );
    await tester.pump();
  }

  testWidgets('the terminal window is the base; a route is a dialog over it', (
    tester,
  ) async {
    await pump(tester);
    expect(find.byKey(const Key('sidebar.newTab')), findsOneWidget);
    container.read(windowRouterProvider.notifier).open(const LoginRoute());
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('dialog')), findsOneWidget);
    expect(tester.getSize(find.byKey(const Key('dialog'))).width, 400);
    expect(find.byKey(const Key('sidebar.newTab')), findsOneWidget);
  });

  testWidgets('Escape closes the dialog, not the window', (tester) async {
    await pump(tester);
    container.read(windowRouterProvider.notifier)
      ..showTerminal()
      ..open(const ChangePasswordRoute());
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(container.read(windowRouterProvider).route, isNull);
    expect(container.read(windowRouterProvider).visible, isTrue);
  });

  testWidgets('with no dialog, Escape reaches the shell (vim)', (tester) async {
    await pump(tester);
    await h.sessions.open(cols: 80, rows: 24);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(h.ptys.ptys.single.writtenText, '\x1b');
  });

  testWidgets('a confirm is a dialog; its buttons answer it', (tester) async {
    await pump(tester);
    final answer = container
        .read(windowRouterProvider.notifier)
        .confirm(
          ConfirmRequest(title: 'Close “claude”?', body: 'b', confirmLabel: 'Close tab'),
        );
    await tester.pumpAndSettle();
    expect(find.text('Close “claude”?'), findsOneWidget);
    await tester.tap(find.byKey(const Key('confirm.cancel')));
    expect(await answer, isFalse);
  });
}
```

(f) `test/tray/tray_menu_test.dart`: prepend `'Mở cửa sổ terminal', '---',` to both expected label lists ('signed-in menu is exactly spec §8.3, in order' and 'signed-out menu offers…', the latter becoming `['Mở cửa sổ terminal', '---', '○ Chưa đăng nhập', '---', 'Đăng nhập…', 'Thoát']`); every `menu.items![n]` index shifts by 2 (e.g. `menu.items![1].key, TrayKeys.downloadUpdate` → `menu.items![3]`). Add:

```dart
  test('"Mở cửa sổ terminal" maps to OpenTerminalWindow', () {
    expect(trayActionForKey(TrayKeys.openTerminal), isA<OpenTerminalWindow>());
  });
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/ui test/platform/app_reopen_test.dart test/tray`
Expected: compile errors (`terminal:`, `showTerminal`, `hideWindow`, `WindowBoundsStore`, `appChannel`, `OpenTerminalWindow`, `dialogSizeFor`, …).

- [ ] **Step 4: Settings keys and bounds store**

`settings_store.dart` `SettingKeys`:

```dart
  /// The terminal window's last bounds (A1 D9), logical pixels.
  static const String windowX = 'window_x';
  static const String windowY = 'window_y';
  static const String windowWidth = 'window_width';
  static const String windowHeight = 'window_height';
```

and add all four to `SettingKeys.all`.

`apps/desktop/lib/src/ui/window_bounds.dart`:

```dart
import 'dart:ui';

import '../platform/settings_store.dart';
import 'theme/shellx_desktop_theme.dart';

/// Remembers where the terminal window was (A1 D9).
final class WindowBoundsStore {
  WindowBoundsStore(this._settings);

  final SettingsStore _settings;

  /// Null when nothing usable is stored.
  Rect? read() {
    final x = _settings.getInt(SettingKeys.windowX);
    final y = _settings.getInt(SettingKeys.windowY);
    final w = _settings.getInt(SettingKeys.windowWidth);
    final h = _settings.getInt(SettingKeys.windowHeight);
    if (x == null || y == null || w == null || h == null) return null;
    if (w < ShellxSizes.minWindow.width || h < ShellxSizes.minWindow.height) {
      return null;
    }
    return Rect.fromLTWH(x.toDouble(), y.toDouble(), w.toDouble(), h.toDouble());
  }

  /// Best effort: a failed write keeps the previous bounds.
  Future<void> write(Rect bounds) async {
    try {
      await _settings.setInt(SettingKeys.windowX, bounds.left.round());
      await _settings.setInt(SettingKeys.windowY, bounds.top.round());
      await _settings.setInt(SettingKeys.windowWidth, bounds.width.round());
      await _settings.setInt(SettingKeys.windowHeight, bounds.height.round());
    } catch (_) {
      // Nothing to do: the window opens at the default size next time.
    }
  }
}
```

- [ ] **Step 5: `WindowRouter`**

Replace `WindowState` and `WindowRouter` in `window_router.dart` (keep the route classes and `ConfirmRequest`):

```dart
@immutable
final class WindowState {
  const WindowState({this.route, this.confirm, this.terminal = false});

  final WindowRoute? route;
  final ConfirmRequest? confirm;

  /// The terminal window is shown (A1 D9). Closing it only hides it.
  final bool terminal;

  /// A legacy page or a confirm is shown as a dialog over the terminal.
  bool get dialogOpen => route != null || confirm != null;

  bool get visible => terminal || dialogOpen;
}

final windowRouterProvider = NotifierProvider<WindowRouter, WindowState>(
  WindowRouter.new,
);

/// What the window shows: always the terminal workspace, with at most one
/// dialog (a legacy route, and a confirm on top of it) over it.
class WindowRouter extends Notifier<WindowState> {
  @override
  WindowState build() => const WindowState();

  WindowRoute? get current => state.route;

  /// D11: launch, Dock, second launch, tray "Mở cửa sổ terminal".
  void showTerminal() => state = WindowState(
    route: state.route,
    confirm: state.confirm,
    terminal: true,
  );

  /// Opens [route] as a dialog; the window shows first if it was hidden
  /// (UI §4).
  void open(WindowRoute route) {
    final leaving = state.route;
    state = WindowState(route: route, confirm: state.confirm, terminal: true);
    _leave(leaving, next: route);
  }

  /// Escape, Cancel, or a page that is done: closes the dialog on top. The
  /// window stays.
  void close() {
    final confirm = state.confirm;
    if (confirm != null) {
      confirm.complete(false);
      state = WindowState(route: state.route, terminal: state.terminal);
      return;
    }
    final leaving = state.route;
    state = WindowState(terminal: state.terminal);
    _leave(leaving, next: null);
  }

  /// The window's close button (A1 D9): the window hides, dialogs are
  /// cancelled, every shell keeps running.
  void hideWindow() {
    state.confirm?.complete(false);
    final leaving = state.route;
    state = const WindowState();
    _leave(leaving, next: null);
  }

  Future<bool> confirm(ConfirmRequest request) async {
    state.confirm?.complete(false);
    state = WindowState(route: state.route, confirm: request, terminal: true);
    final result = await request.result;
    if (ref.mounted && identical(state.confirm, request)) {
      state = WindowState(route: state.route, terminal: state.terminal);
    }
    return result;
  }

  void _leave(WindowRoute? current, {required WindowRoute? next}) {
    final agent = ref.read(agentControllerProvider.notifier);
    if (current is PairingRoute && next is! PairingRoute) {
      // Closing the QR dialog invalidates the pairing code (spec §5.3).
      agent.cancelPairing();
    }
    if (current is OnboardingRoute &&
        next is! OnboardingRoute &&
        !ref.read(agentControllerProvider).onboardingDone) {
      unawaited(agent.completeOnboarding()); // Never throws.
    }
  }
}
```

- [ ] **Step 6: Coordinator — no login dialog at startup**

`window_coordinator.dart`, first branch:

```dart
  final before = previous?.phase;
  if (next.phase == AuthPhase.signedOut && before == AuthPhase.signedIn) {
    // A sign-out or a 4002 while running: ask to sign in again. At startup
    // the signed-out strip invites instead (A1 D11: the terminal works
    // signed out).
    router.open(const LoginRoute());
  } else if (next.phase == AuthPhase.signedIn && before != AuthPhase.signedIn) {
```

(the rest unchanged; update the doc comment: "startup" no longer opens login).

- [ ] **Step 7: Dialog host (UI §4)**

`apps/desktop/lib/src/ui/dialogs/route_dialog.dart`:

```dart
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../../terminal/terminal_tabs.dart';
import '../pages/change_password_page.dart';
import '../pages/confirm_page.dart';
import '../pages/login_page.dart';
import '../pages/onboarding_page.dart';
import '../pages/pairing_page.dart';
import '../terminal/shortcut_labels.dart';
import '../theme/shellx_desktop_theme.dart';
import '../window_router.dart';

/// UI §4 widths; heights are the old fixed windows' (the page bodies are
/// reused as they are and lay out for them).
Size dialogSizeFor(WindowState state) {
  final confirm = state.confirm;
  if (confirm != null) {
    return confirm.long
        ? const Size(ShellxSizes.dialogWidthLong, 560)
        : const Size(ShellxSizes.dialogWidth, 260);
  }
  return switch (state.route) {
    LoginRoute() => const Size(ShellxSizes.dialogWidth, 620),
    OnboardingRoute() => const Size(ShellxSizes.dialogWidthOnboarding, 660),
    PairingRoute() => const Size(ShellxSizes.dialogWidth, 660),
    ChangePasswordRoute() => const Size(ShellxSizes.dialogWidth, 480),
    null => const Size(ShellxSizes.dialogWidth, 260),
  };
}

/// UI §2: "{tab} — ShellX", or "ShellX" with no tabs.
String windowTitleFor(TerminalTab? selected, AppLocalizations l10n) =>
    selected == null ? 'ShellX' : l10n.windowTitle(selected.label);

/// The legacy route or confirm as a dialog over the terminal (UI §4):
/// scrim, focus trapped, Escape = close, informational dialogs (pairing)
/// close on a scrim click, forms and confirms do not.
class RouteDialogHost extends ConsumerWidget {
  const RouteDialogHost({super.key, required this.state});
  final WindowState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.read(windowRouterProvider.notifier);
    final confirm = state.confirm;
    final Widget page = confirm != null
        ? ConfirmPage(key: ValueKey(confirm), request: confirm)
        : switch (state.route) {
            LoginRoute() => const LoginPage(),
            OnboardingRoute() => const OnboardingPage(),
            PairingRoute() => const PairingPage(),
            ChangePasswordRoute() => const ChangePasswordPage(),
            null => const SizedBox.shrink(),
          };
    final informational = confirm == null && state.route is PairingRoute;
    final screen = MediaQuery.sizeOf(context);
    final size = dialogSizeFor(state);
    final maxHeight = confirm?.long ?? false
        ? screen.height * 0.8
        : screen.height - 2 * ShellxSpace.s24;
    return Stack(
      children: [
        ModalBarrier(
          color: ShellxDesktopColors.scrim,
          dismissible: informational,
          onDismiss: router.close,
        ),
        Center(
          child: FocusScope(
            autofocus: true,
            child: CallbackShortcuts(
              bindings: {
                const SingleActivator(LogicalKeyboardKey.escape): router.close,
              },
              child: Container(
                key: const Key('dialog'),
                width: size.width,
                height: min(size.height, maxHeight),
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: ShellxDesktopColors.surface,
                  borderRadius: BorderRadius.circular(ShellxRadius.r12),
                  border: Border.all(color: ShellxDesktopColors.border),
                  boxShadow: ShellxShadows.e2,
                ),
                child: Material(
                  type: MaterialType.transparency,
                  child: Stack(
                    children: [
                      Positioned.fill(child: page),
                      if (!isMacDesktop)
                        Positioned(
                          top: ShellxSpace.s12,
                          right: ShellxSpace.s12,
                          child: SizedBox.square(
                            dimension: ShellxSizes.iconHit,
                            child: IconButton(
                              key: const Key('dialog.close'),
                              padding: EdgeInsets.zero,
                              tooltip: AppLocalizations.of(context).dialogClose,
                              onPressed: router.close,
                              icon: const Icon(Icons.close, size: ShellxSizes.icon),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
```

(The pages keep their own 24 px padding, which is the dialog padding of UI §4. Re-styling the page bodies' buttons/fields to UI §3.3/§3.4 is done through `buildDesktopTheme()`; do not rewrite the pages.)

- [ ] **Step 8: App root**

Replace `apps/desktop/lib/src/ui/app.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import 'dialogs/route_dialog.dart';
import 'terminal/terminal_workspace_page.dart';
import 'theme/shellx_desktop_theme.dart';
import 'window_router.dart';

/// Root widget: the terminal window (A1 D9), dark only (UI §1).
class ShellxDesktopApp extends StatelessWidget {
  const ShellxDesktopApp({super.key, required this.locale});

  final Locale locale;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      theme: buildDesktopTheme(),
      themeMode: ThemeMode.dark,
      home: const WindowContent(),
    );
  }
}

class WindowContent extends ConsumerStatefulWidget {
  const WindowContent({super.key});

  @override
  ConsumerState<WindowContent> createState() => _WindowContentState();
}

class _WindowContentState extends ConsumerState<WindowContent> {
  final _workspace = GlobalKey<TerminalWorkspacePageState>();

  @override
  Widget build(BuildContext context) {
    final window = ref.watch(windowRouterProvider);
    // UI §3.6: the terminal regains focus after any dialog closes.
    ref.listen(windowRouterProvider.select((w) => w.dialogOpen), (_, open) {
      if (!open) {
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _workspace.currentState?.focusTerminal(),
        );
      }
    });
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: ExcludeFocus(
              excluding: window.dialogOpen,
              child: TerminalWorkspacePage(key: _workspace),
            ),
          ),
          if (window.dialogOpen)
            Positioned.fill(child: RouteDialogHost(state: window)),
        ],
      ),
    );
  }
}
```

(The window-level Escape binding is gone on purpose: Escape belongs to the shell; dialogs bind it themselves.)

- [ ] **Step 9: Window host (D9, D10)**

Replace `apps/desktop/lib/src/ui/window_host.dart`:

```dart
import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart' show Brightness;
import 'package:window_manager/window_manager.dart';

import '../platform/app_reopen.dart';
import 'theme/shellx_desktop_theme.dart';
import 'window_bounds.dart';
import 'window_router.dart';

abstract interface class WindowHost {
  Future<void> show();
  Future<void> hide();
  Future<void> setTitle(String title);
}

/// Shows/hides the single window to follow the router.
final class WindowPresenter {
  WindowPresenter(this._host);

  final WindowHost _host;
  bool _visible = false;

  Future<void> apply(WindowState state) async {
    if (state.visible == _visible) return;
    _visible = state.visible;
    await (state.visible ? _host.show() : _host.hide());
  }
}

/// [WindowHost] over package window_manager. The close button hides the
/// window through [onCloseRequested] instead of quitting (A1 D9).
///
/// This relies on window_manager's `setPreventClose(true)` fully intercepting
/// the native WM_CLOSE / performClose before the OS default handler runs, so
/// it always wins over Windows' `Win32Window::SetQuitOnClose(true)` (plan 04
/// Task 1): window_manager 0.5.2's Windows plugin returns early from the
/// top-level WindowProc for WM_CLOSE when prevent-close is on.
final class WindowManagerHost with WindowListener implements WindowHost {
  WindowManagerHost({required this.onCloseRequested, required this.bounds});

  final void Function() onCloseRequested;
  final WindowBoundsStore bounds;
  bool _placed = false;
  Timer? _save;

  Future<void> init() async {
    await windowManager.ensureInitialized();
    await windowManager.setPreventClose(true);
    await windowManager.setTitle('ShellX');
    await windowManager.setResizable(true);
    await windowManager.setMaximizable(true);
    await windowManager.setMinimumSize(ShellxSizes.minWindow);
    if (Platform.isMacOS) {
      // UI §2.1: transparent title bar, traffic lights over the sidebar.
      await windowManager.setTitleBarStyle(
        TitleBarStyle.hidden,
        windowButtonVisibility: true,
      );
    } else {
      // UI §2.1: native title bar, dark.
      await windowManager.setBrightness(Brightness.dark);
    }
    windowManager.addListener(this);
  }

  @override
  Future<void> show() async {
    if (!_placed) {
      _placed = true;
      final saved = bounds.read();
      if (saved != null) {
        await windowManager.setBounds(saved);
      } else {
        await windowManager.setSize(ShellxSizes.defaultWindow);
        await windowManager.center();
      }
    }
    // D10: Dock icon, ⌘Tab and the app menu (⌘Q) while visible.
    if (Platform.isMacOS) await setDockVisible(true);
    if (Platform.isWindows) await windowManager.setSkipTaskbar(false);
    await windowManager.show();
    await windowManager.focus();
  }

  @override
  Future<void> hide() async {
    await windowManager.hide();
    if (Platform.isMacOS) await setDockVisible(false);
  }

  @override
  Future<void> setTitle(String title) => windowManager.setTitle(title);

  @override
  void onWindowClose() => onCloseRequested();

  @override
  void onWindowResized() => _remember();

  @override
  void onWindowMoved() => _remember();

  void _remember() {
    _save?.cancel();
    _save = Timer(const Duration(milliseconds: 400), () async {
      try {
        await bounds.write(await windowManager.getBounds());
      } catch (_) {
        // Best effort.
      }
    });
  }
}
```

- [ ] **Step 10: App channel (Dart) and activation**

Replace `apps/desktop/lib/src/platform/app_reopen.dart`:

```dart
import 'package:flutter/services.dart';

/// `pro.shellx.desktop/app` (AppDelegate.swift). Native → Dart: `reopen`
/// (Finder/Spotlight/Dock reopen the running app) and `quitRequested` (⌘Q
/// or the app menu's Quit, A1 D10). Dart → native: `setDockVisible`.
const MethodChannel appChannel = MethodChannel('pro.shellx.desktop/app');

void listenForAppChannel({
  required void Function() onReopen,
  required void Function() onQuitRequested,
  MethodChannel channel = appChannel,
}) {
  channel.setMethodCallHandler((call) async {
    switch (call.method) {
      case 'reopen':
        onReopen();
      case 'quitRequested':
        onQuitRequested();
    }
  });
}

/// macOS: `.regular` activation policy while the window is visible (Dock
/// icon, ⌘Tab, menu bar with ⌘Q), `.accessory` while hidden (A1 D10).
Future<void> setDockVisible(bool visible, {MethodChannel channel = appChannel}) =>
    channel.invokeMethod<void>('setDockVisible', visible);
```

Replace `apps/desktop/lib/src/ui/activation.dart`:

```dart
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../terminal/terminal_tabs.dart';
import 'window_router.dart';

/// A1 D11: launch, a second launch, the Dock, a macOS reopen and the tray
/// all show the terminal window; with no tab at all, one is opened. Never
/// throws.
Future<void> openTerminalWindow({
  required WindowRouter router,
  required TerminalTabs tabs,
}) async {
  router.showTerminal();
  try {
    await tabs.ensureTab();
  } catch (error) {
    debugPrint('ShellX: opening a tab failed: ${error.runtimeType}');
  }
}

Future<void> handleActivation(ProviderContainer container) =>
    openTerminalWindow(
      router: container.read(windowRouterProvider.notifier),
      tabs: container.read(terminalTabsProvider.notifier),
    );
```

- [ ] **Step 11: Tray**

`tray_action.dart`: add

```dart
/// A1 D11: the first tray item.
final class OpenTerminalWindow extends TrayAction {
  const OpenTerminalWindow();
}
```

`TrayKeys.openTerminal = 'open_terminal'` and `TrayKeys.openTerminal => const OpenTerminalWindow(),` in `trayActionForKey`.

`tray_menu.dart` `buildTrayMenu`: both menus start with `item(TrayKeys.openTerminal, l10n.trayOpenTerminal), sep(),` (UI §5 "Tray" paragraph): the signed-out list becomes `[open, sep, status, sep, signIn, quit]`, the signed-in list gets the two entries before the status line.

`tray_actions.dart`: `import '../terminal/terminal_tabs.dart';` and `import '../ui/activation.dart';`; add

```dart
      case OpenTerminalWindow():
        await openTerminalWindow(
          router: _router,
          tabs: _ref.read(terminalTabsProvider.notifier),
        );
```

- [ ] **Step 12: macOS native side**

Replace `apps/desktop/macos/Runner/AppDelegate.swift`:

```swift
import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  /// macOS is logging out, restarting or shutting down: never hold it up.
  private var poweringOff = false

  override func applicationDidFinishLaunching(_ notification: Notification) {
    NSWorkspace.shared.notificationCenter.addObserver(
      self, selector: #selector(willPowerOff(_:)),
      name: NSWorkspace.willPowerOffNotification, object: nil)
    super.applicationDidFinishLaunching(notification)
  }

  @objc private func willPowerOff(_ notification: Notification) {
    poweringOff = true
  }

  // ShellX lives in the menu bar; closing or hiding its window must not quit it.
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return false
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  // Opening ShellX again (Finder, Spotlight, Launchpad, Dock) while it runs
  // reopens this process instead of starting a second one. Dart decides what
  // to show (lib/src/ui/activation.dart).
  override func applicationShouldHandleReopen(
    _ sender: NSApplication, hasVisibleWindows flag: Bool
  ) -> Bool {
    AppChannel.reopen()
    return false
  }

  // ⌘Q and the app menu's Quit (shown while the Dock icon is, A1 D10) go
  // through Dart's quit flow: confirm, close every shell tree, then exit(0),
  // which never comes back here. Log out / shut down is never blocked.
  override func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    if poweringOff || !AppChannel.isReady {
      return .terminateNow
    }
    AppChannel.quitRequested()
    return .terminateCancel
  }
}

/// `pro.shellx.desktop/app` (lib/src/platform/app_reopen.dart).
enum AppChannel {
  private static var channel: FlutterMethodChannel?

  static var isReady: Bool { channel != nil }

  static func register(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "pro.shellx.desktop/app", binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "setDockVisible":
        let visible = call.arguments as? Bool ?? false
        NSApp.setActivationPolicy(visible ? .regular : .accessory)
        if visible {
          NSApp.activate(ignoringOtherApps: true)
        }
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    self.channel = channel
  }

  static func reopen() {
    channel?.invokeMethod("reopen", arguments: nil)
  }

  static func quitRequested() {
    channel?.invokeMethod("quitRequested", arguments: nil)
  }
}
```

In `MainFlutterWindow.swift` replace `AppReopenChannel.register(messenger: flutterViewController.engine.binaryMessenger)` with `AppChannel.register(messenger: flutterViewController.engine.binaryMessenger)`. `Info.plist` keeps `LSUIElement` true (D10). Build check: `cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter build macos --debug` must succeed.

- [ ] **Step 13: `main.dart` wiring**

In `_start`:
1. Move `final settings = await SharedPrefsSettingsStore.open();` above the window host, and build the host with bounds:

```dart
  final settings = await SharedPrefsSettingsStore.open();
  late final ProviderContainer container;
  final windowHost = WindowManagerHost(
    // A1 D9: the close button hides the window; shells keep running.
    onCloseRequested: () =>
        container.read(windowRouterProvider.notifier).hideWindow(),
    bounds: WindowBoundsStore(settings),
  );
  await windowHost.init();
```

2. Replace the activation block (from `void activate() =>` through `if (Platform.isMacOS) listenForReopen(activate);`) with:

```dart
  // A1 D11: a second launch (Windows, `open -n`), a macOS reopen (Finder,
  // Spotlight, Dock) and the tray all show the terminal window.
  void activate() => unawaited(handleActivation(container));
  lock.activationRequests().listen(
    (_) => activate(),
    onError: (Object error) =>
        debugPrint('ShellX: activation watch failed: ${error.runtimeType}'),
  );
  if (Platform.isMacOS) {
    listenForAppChannel(
      onReopen: activate,
      // ⌘Q / app menu Quit (A1 D10): the same flow as the tray's "Thoát".
      onQuitRequested: () => unawaited(trayActions.handle(const Quit())),
    );
  }
  container.listen(
    terminalTabsProvider.select((s) => s.selected),
    (_, selected) => _unawaitedLogged(
      windowHost.setTitle(windowTitleFor(selected, l10n)),
      'window title',
    ),
  );
```

3. After `runApp(...)` and before `await container.read(agentControllerProvider.notifier).bootstrap();` add `container.read(windowRouterProvider.notifier).showTerminal();`; after the bootstrap add:

```dart
  // D11: every start opens the terminal window with a tab, sized to the
  // laid-out pane.
  await WidgetsBinding.instance.endOfFrame;
  await handleActivation(container);
```

Imports: `src/ui/window_bounds.dart`, `src/ui/dialogs/route_dialog.dart`, `src/terminal/terminal_tabs.dart`, `src/tray/tray_action.dart`; drop the old `listenForReopen` use.

- [ ] **Step 14: Run the tests to verify they pass**

Run: `cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test`
Expected: all pass.

- [ ] **Step 15: Format, analyze, build, commit**

```bash
cd apps/desktop
~/fvm/versions/3.41.4/bin/dart format --set-exit-if-changed lib test
PATH=~/fvm/versions/3.41.4/bin:$PATH flutter analyze
PATH=~/fvm/versions/3.41.4/bin:$PATH flutter build macos --debug
cd ../..
git add apps/desktop/lib apps/desktop/macos/Runner/AppDelegate.swift apps/desktop/macos/Runner/MainFlutterWindow.swift apps/desktop/test/ui apps/desktop/test/platform/app_reopen_test.dart apps/desktop/test/tray/tray_menu_test.dart
git commit -m "feat(desktop): the terminal window (resizable, remembered bounds, legacy pages as dialogs, Dock icon and ⌘Q through the Quit flow on macOS, taskbar on Windows, opens with a tab on every launch, tray 'Open terminal window')"
```

---

### Task 8: Desktop — window shortcuts (spec criterion 2, UI §3.6)

One shortcut table per platform, installed twice from the same map: as `Shortcuts` around the workspace (focus in the sidebar or strip) and as the `shortcuts:` of every `TerminalView` (xterm consumes keys like Ctrl+Tab and Ctrl+Shift+T before they could bubble up, so the terminal's own shortcut manager must know them; it invokes the same `Actions`).

| Action | macOS | Windows |
|---|---|---|
| New tab | ⌘T | Ctrl+Shift+T |
| Close tab (D15 confirm; empty state → hide window) | ⌘W | Ctrl+Shift+W |
| Select tab n | ⌘1…⌘9 | Ctrl+Alt+1…9 |
| Next / previous tab | ⌃Tab / ⌃⇧Tab | Ctrl+Tab / Ctrl+Shift+Tab |
| Copy (only with a selection; otherwise the key goes to the shell) | ⌘C | Ctrl+Shift+C |
| Paste (sanitised, bracketed when enabled) | ⌘V | Ctrl+Shift+V |
| Font bigger / smaller / reset | ⌘= (⌘+) / ⌘− / ⌘0 | Ctrl+= / Ctrl+− / Ctrl+0 |
| Next / previous focus region | F6 / ⇧F6 | F6 / Shift+F6 |

(Windows tab-number and font chords are not in the spec; they follow Windows Terminal, which leaves Ctrl+digit to the shell.)

**Files:**
- Create: `apps/desktop/lib/src/ui/terminal/terminal_shortcuts.dart`
- Modify: `apps/desktop/lib/src/ui/terminal/terminal_workspace_page.dart` (Shortcuts/Actions, regions)
- Modify: `apps/desktop/lib/src/ui/terminal/session_sidebar.dart` (arrow keys, Enter/Esc)
- Modify: `apps/desktop/lib/src/ui/terminal/terminal_pane.dart`, `terminal_overlays.dart` (strip focus node)
- Test: `apps/desktop/test/ui/terminal_shortcuts_test.dart`

**Interfaces:**
- Consumes: `TerminalWorkspacePageState` (`terminalFocus`, `sidebarFocus`, `focusTerminal`, `closeTab`, `terminalShortcuts`), `TerminalTabs` (`openTab`, `selectIndex`, `next`, `previous`, `select`), `TerminalTab.selection` / `.terminal`, `TerminalFontSize` (`increase`, `decrease`, `reset`), `WindowRouter.hideWindow` (Tasks 5–7).
- Produces: intents `NewTabIntent`, `CloseTabIntent`, `SelectTabIntent(int position)`, `NextTabIntent`, `PreviousTabIntent`, `CopySelectionIntent`, `PasteClipboardIntent`, `FontBiggerIntent`, `FontSmallerIntent`, `FontResetIntent`, `NextRegionIntent`, `PreviousRegionIntent`; `Map<ShortcutActivator, Intent> desktopShortcuts(TargetPlatform platform)`.

- [ ] **Step 1: Write the failing tests**

`apps/desktop/test/ui/terminal_shortcuts_test.dart`:

```dart
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_desktop/l10n/app_localizations.dart';
import 'package:shellx_desktop/src/agent/agent_controller.dart';
import 'package:shellx_desktop/src/agent/desktop_services.dart';
import 'package:shellx_desktop/src/terminal/local_sessions_provider.dart';
import 'package:shellx_desktop/src/terminal/terminal_font_size.dart';
import 'package:shellx_desktop/src/terminal/terminal_tabs.dart';
import 'package:shellx_desktop/src/ui/terminal/terminal_shortcuts.dart';
import 'package:shellx_desktop/src/ui/terminal/terminal_workspace_page.dart';
import 'package:shellx_desktop/src/ui/theme/shellx_desktop_theme.dart';
import 'package:shellx_desktop/src/ui/window_router.dart';

import '../support/fake_local_sessions.dart';
import '../support/fakes.dart';

late FakeLocalSessions local;
late ProviderContainer container;

Future<void> pumpWorkspace(WidgetTester tester) async {
  final h = TestHarness(settings: {'onboarding_done': true});
  container = ProviderContainer(
    overrides: [
      desktopServicesProvider.overrideWithValue(h.services()),
      localSessionsProvider.overrideWithValue(local),
    ],
  );
  addTearDown(container.dispose);
  await container.read(agentControllerProvider.notifier).bootstrap(
    watchForWake: false,
  );
  container.read(windowRouterProvider.notifier).showTerminal();
  tester.view.physicalSize = const Size(1100, 720);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: buildDesktopTheme(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: const Scaffold(body: TerminalWorkspacePage()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

TerminalTabsState tabs() => container.read(terminalTabsProvider);

Future<void> chord(
  WidgetTester tester,
  List<LogicalKeyboardKey> modifiers,
  LogicalKeyboardKey key,
) async {
  for (final m in modifiers) {
    await tester.sendKeyDownEvent(m);
  }
  await tester.sendKeyEvent(key);
  for (final m in modifiers.reversed) {
    await tester.sendKeyUpEvent(m);
  }
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => local = FakeLocalSessions());

  test('the tables follow spec criterion 2', () {
    final mac = desktopShortcuts(TargetPlatform.macOS);
    final win = desktopShortcuts(TargetPlatform.windows);
    expect(
      mac[const SingleActivator(LogicalKeyboardKey.keyT, meta: true)],
      isA<NewTabIntent>(),
    );
    expect(
      win[const SingleActivator(
        LogicalKeyboardKey.keyT,
        control: true,
        shift: true,
      )],
      isA<NewTabIntent>(),
    );
    expect(
      win[const SingleActivator(LogicalKeyboardKey.tab, control: true)],
      isA<NextTabIntent>(),
    );
    expect(
      mac[const SingleActivator(LogicalKeyboardKey.digit3, meta: true)],
      isA<SelectTabIntent>().having((i) => i.position, 'position', 3),
    );
    // Plain Ctrl+letters always reach the shell.
    expect(
      win[const SingleActivator(LogicalKeyboardKey.keyC, control: true)],
      isNull,
    );
  });

  for (final platform in [TargetPlatform.macOS, TargetPlatform.windows]) {
    final mac = platform == TargetPlatform.macOS;
    final primary = mac
        ? [LogicalKeyboardKey.metaLeft]
        : [LogicalKeyboardKey.controlLeft, LogicalKeyboardKey.shiftLeft];

    group(platform.name, () {
      setUp(() => debugDefaultTargetPlatformOverride = platform);
      tearDown(() => debugDefaultTargetPlatformOverride = null);

      testWidgets('new tab, then close it, from inside the terminal', (
        tester,
      ) async {
        await pumpWorkspace(tester);
        await chord(tester, primary, LogicalKeyboardKey.keyT);
        expect(local.opens, hasLength(1));
        expect(tabs().tabs, hasLength(1));
        await chord(tester, primary, LogicalKeyboardKey.keyW);
        expect(local.closed, [100]);
        debugDefaultTargetPlatformOverride = null;
      });

      testWidgets('tab number and next/previous', (tester) async {
        for (final id in [1, 2, 3]) {
          local.add(local.summary(id));
        }
        await pumpWorkspace(tester);
        await chord(
          tester,
          mac
              ? [LogicalKeyboardKey.metaLeft]
              : [LogicalKeyboardKey.controlLeft, LogicalKeyboardKey.altLeft],
          LogicalKeyboardKey.digit3,
        );
        expect(tabs().selectedId, 3);
        await chord(
          tester,
          [LogicalKeyboardKey.controlLeft],
          LogicalKeyboardKey.tab,
        );
        expect(tabs().selectedId, 1);
        await chord(
          tester,
          [LogicalKeyboardKey.controlLeft, LogicalKeyboardKey.shiftLeft],
          LogicalKeyboardKey.tab,
        );
        expect(tabs().selectedId, 3);
        // The shell never saw these chords.
        expect(local.views[1]!.writes, isEmpty);
        expect(local.views[3]!.writes, isEmpty);
        debugDefaultTargetPlatformOverride = null;
      });

      testWidgets('font size bigger / smaller / reset', (tester) async {
        local.add(local.summary(1));
        await pumpWorkspace(tester);
        final fontKeys = mac
            ? [LogicalKeyboardKey.metaLeft]
            : [LogicalKeyboardKey.controlLeft];
        await chord(tester, fontKeys, LogicalKeyboardKey.equal);
        expect(container.read(terminalFontSizeProvider), 14);
        await chord(tester, fontKeys, LogicalKeyboardKey.minus);
        await chord(tester, fontKeys, LogicalKeyboardKey.minus);
        expect(container.read(terminalFontSizeProvider), 12);
        await chord(tester, fontKeys, LogicalKeyboardKey.digit0);
        expect(container.read(terminalFontSizeProvider), 13);
        debugDefaultTargetPlatformOverride = null;
      });

      testWidgets('paste goes to the shell cleaned; copy without a selection '
          'lets the key through', (tester) async {
        local.add(local.summary(1, origin: SessionOrigin.desktop));
        await pumpWorkspace(tester);
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async => call.method == 'Clipboard.getData'
              ? {'text': 'echo hi\x1b[201~'}
              : null,
        );
        await chord(tester, primary, LogicalKeyboardKey.keyV);
        expect(local.views[1]!.writes, ['echo hi[201~']);
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        );
        debugDefaultTargetPlatformOverride = null;
      });

      testWidgets('close with nothing open hides the window (UI §2.7)', (
        tester,
      ) async {
        await pumpWorkspace(tester);
        await chord(tester, primary, LogicalKeyboardKey.keyW);
        expect(container.read(windowRouterProvider).visible, isFalse);
        debugDefaultTargetPlatformOverride = null;
      });

      testWidgets('F6 moves between the terminal and the sidebar; Esc comes '
          'back', (tester) async {
        local.add(local.summary(1));
        local.add(local.summary(2));
        await pumpWorkspace(tester);
        final page = tester.state<TerminalWorkspacePageState>(
          find.byType(TerminalWorkspacePage),
        );
        expect(page.terminalFocus.hasFocus, isTrue);
        await tester.sendKeyEvent(LogicalKeyboardKey.f6);
        await tester.pumpAndSettle();
        expect(page.sidebarFocus.hasFocus, isTrue);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pumpAndSettle();
        expect(tabs().selectedId, 2);
        expect(page.sidebarFocus.hasFocus, isTrue);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(page.terminalFocus.hasFocus, isTrue);
        debugDefaultTargetPlatformOverride = null;
      });
    });
  }
}
```

(Each `testWidgets` resets `debugDefaultTargetPlatformOverride` before it ends because the framework checks it at the end of the test body.)

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/ui/terminal_shortcuts_test.dart`
Expected: compile error — `terminal_shortcuts.dart` missing.

- [ ] **Step 3: The table**

`apps/desktop/lib/src/ui/terminal/terminal_shortcuts.dart`:

```dart
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

class NewTabIntent extends Intent {
  const NewTabIntent();
}

class CloseTabIntent extends Intent {
  const CloseTabIntent();
}

class SelectTabIntent extends Intent {
  const SelectTabIntent(this.position);

  /// 1-based.
  final int position;
}

class NextTabIntent extends Intent {
  const NextTabIntent();
}

class PreviousTabIntent extends Intent {
  const PreviousTabIntent();
}

class CopySelectionIntent extends Intent {
  const CopySelectionIntent();
}

class PasteClipboardIntent extends Intent {
  const PasteClipboardIntent();
}

class FontBiggerIntent extends Intent {
  const FontBiggerIntent();
}

class FontSmallerIntent extends Intent {
  const FontSmallerIntent();
}

class FontResetIntent extends Intent {
  const FontResetIntent();
}

class NextRegionIntent extends Intent {
  const NextRegionIntent();
}

class PreviousRegionIntent extends Intent {
  const PreviousRegionIntent();
}

const _digits = [
  LogicalKeyboardKey.digit1,
  LogicalKeyboardKey.digit2,
  LogicalKeyboardKey.digit3,
  LogicalKeyboardKey.digit4,
  LogicalKeyboardKey.digit5,
  LogicalKeyboardKey.digit6,
  LogicalKeyboardKey.digit7,
  LogicalKeyboardKey.digit8,
  LogicalKeyboardKey.digit9,
];

/// Spec criterion 2 and UI §3.6. The same map goes to the workspace's
/// `Shortcuts` and to every `TerminalView` (xterm would otherwise consume
/// Ctrl+Tab, Ctrl+Shift+T… as terminal input).
Map<ShortcutActivator, Intent> desktopShortcuts(TargetPlatform platform) {
  final mac = platform == TargetPlatform.macOS;
  SingleActivator primary(LogicalKeyboardKey key) => mac
      ? SingleActivator(key, meta: true)
      : SingleActivator(key, control: true, shift: true);
  SingleActivator font(LogicalKeyboardKey key) => mac
      ? SingleActivator(key, meta: true)
      : SingleActivator(key, control: true);
  return {
    primary(LogicalKeyboardKey.keyT): const NewTabIntent(),
    primary(LogicalKeyboardKey.keyW): const CloseTabIntent(),
    primary(LogicalKeyboardKey.keyC): const CopySelectionIntent(),
    primary(LogicalKeyboardKey.keyV): const PasteClipboardIntent(),
    for (var i = 0; i < _digits.length; i++)
      (mac
              ? SingleActivator(_digits[i], meta: true)
              : SingleActivator(_digits[i], control: true, alt: true)):
          SelectTabIntent(i + 1),
    const SingleActivator(LogicalKeyboardKey.tab, control: true):
        const NextTabIntent(),
    const SingleActivator(LogicalKeyboardKey.tab, control: true, shift: true):
        const PreviousTabIntent(),
    font(LogicalKeyboardKey.equal): const FontBiggerIntent(),
    (mac
            ? const SingleActivator(
                LogicalKeyboardKey.equal,
                meta: true,
                shift: true,
              )
            : const SingleActivator(
                LogicalKeyboardKey.equal,
                control: true,
                shift: true,
              )):
        const FontBiggerIntent(),
    font(LogicalKeyboardKey.minus): const FontSmallerIntent(),
    font(LogicalKeyboardKey.digit0): const FontResetIntent(),
    const SingleActivator(LogicalKeyboardKey.f6): const NextRegionIntent(),
    const SingleActivator(LogicalKeyboardKey.f6, shift: true):
        const PreviousRegionIntent(),
  };
}
```

- [ ] **Step 4: Actions in the workspace**

In `terminal_workspace_page.dart`:
- imports: `package:flutter/foundation.dart`, `package:flutter/services.dart`, `../../terminal/terminal_font_size.dart`, `terminal_shortcuts.dart`, `../../agent/agent_controller.dart`, `../../agent/agent_state.dart`.
- add `final stripFocus = FocusNode(debugLabel: 'signed-out strip');` (disposed with the others) and pass it to `TerminalPane(stripFocus: stripFocus, …)`.
- in `build`, compute `final shortcuts = desktopShortcuts(defaultTargetPlatform);`, store it in `terminalShortcuts` and pass it to `TerminalPane(shortcuts: shortcuts, …)`; wrap the returned `Row` as:

```dart
    return Shortcuts(
      shortcuts: shortcuts,
      child: Actions(
        actions: <Type, Action<Intent>>{
          NewTabIntent: CallbackAction<NewTabIntent>(
            onInvoke: (_) {
              ref.read(terminalTabsProvider.notifier).openTab();
              focusTerminal();
              return null;
            },
          ),
          CloseTabIntent: CallbackAction<CloseTabIntent>(
            onInvoke: (_) {
              final selected = ref.read(terminalTabsProvider).selected;
              if (selected == null) {
                // UI §2.7 (accepted): ⌘W on the empty state hides the window.
                ref.read(windowRouterProvider.notifier).hideWindow();
              } else {
                closeTab(selected);
              }
              return null;
            },
          ),
          SelectTabIntent: CallbackAction<SelectTabIntent>(
            onInvoke: (intent) {
              ref.read(terminalTabsProvider.notifier).selectIndex(intent.position);
              focusTerminal();
              return null;
            },
          ),
          NextTabIntent: CallbackAction<NextTabIntent>(
            onInvoke: (_) {
              ref.read(terminalTabsProvider.notifier).next();
              focusTerminal();
              return null;
            },
          ),
          PreviousTabIntent: CallbackAction<PreviousTabIntent>(
            onInvoke: (_) {
              ref.read(terminalTabsProvider.notifier).previous();
              focusTerminal();
              return null;
            },
          ),
          CopySelectionIntent: _CopyAction(ref),
          PasteClipboardIntent: CallbackAction<PasteClipboardIntent>(
            onInvoke: (_) async {
              final tab = ref.read(terminalTabsProvider).selected;
              final data = await Clipboard.getData(Clipboard.kTextPlain);
              final text = data?.text;
              if (tab != null && text != null && text.isNotEmpty) {
                tab.terminal.paste(text); // sanitised by DesktopTerminal
              }
              return null;
            },
          ),
          FontBiggerIntent: CallbackAction<FontBiggerIntent>(
            onInvoke: (_) {
              ref.read(terminalFontSizeProvider.notifier).increase();
              return null;
            },
          ),
          FontSmallerIntent: CallbackAction<FontSmallerIntent>(
            onInvoke: (_) {
              ref.read(terminalFontSizeProvider.notifier).decrease();
              return null;
            },
          ),
          FontResetIntent: CallbackAction<FontResetIntent>(
            onInvoke: (_) {
              ref.read(terminalFontSizeProvider.notifier).reset();
              return null;
            },
          ),
          NextRegionIntent: CallbackAction<NextRegionIntent>(
            onInvoke: (_) {
              _cycleRegion(1);
              return null;
            },
          ),
          PreviousRegionIntent: CallbackAction<PreviousRegionIntent>(
            onInvoke: (_) {
              _cycleRegion(-1);
              return null;
            },
          ),
        },
        // Keeps a focused node inside the Shortcuts even with no tab (the
        // empty state), so ⌘T / ⌘W work there too.
        child: Focus(
          autofocus: true,
          debugLabel: 'workspace',
          child: Row(/* the Row from Task 6, unchanged */),
        ),
      ),
    );
```

- add to the state class:

```dart
  /// UI §3.6 regions: terminal, sidebar, signed-out strip (when shown).
  void _cycleRegion(int step) {
    final signedOut =
        ref.read(agentControllerProvider).phase == AuthPhase.signedOut;
    final regions = [terminalFocus, sidebarFocus, if (signedOut) stripFocus];
    final current = regions.indexWhere((node) => node.hasFocus);
    final next = regions[((current < 0 ? 0 : current) + step) % regions.length];
    next.requestFocus();
  }
```

  (`%` in Dart is always non-negative for a positive divisor, so `-1 % n` is `n - 1`.)
- add at the bottom of the file:

```dart
/// ⌘C / Ctrl+Shift+C copies only when there is a selection; when disabled
/// the shortcut manager leaves the key to the terminal (spec §3.2).
class _CopyAction extends Action<CopySelectionIntent> {
  _CopyAction(this._ref);
  final WidgetRef _ref;

  @override
  bool isEnabled(CopySelectionIntent intent) =>
      _ref.read(terminalTabsProvider).selected?.selection.selection != null;

  @override
  Object? invoke(CopySelectionIntent intent) {
    final tab = _ref.read(terminalTabsProvider).selected;
    final range = tab?.selection.selection;
    if (tab == null || range == null) return null;
    Clipboard.setData(ClipboardData(text: tab.terminal.buffer.getText(range)));
    tab.selection.clearSelection();
    return null;
  }
}
```

- [ ] **Step 5: Sidebar keys and strip focus**

`session_sidebar.dart`: give the list's `Focus` an `onKeyEvent`:

```dart
              child: Focus(
                focusNode: focusNode,
                onKeyEvent: (node, event) {
                  if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
                    return KeyEventResult.ignored;
                  }
                  final tabs = ref.read(terminalTabsProvider.notifier);
                  switch (event.logicalKey) {
                    case LogicalKeyboardKey.arrowDown:
                      tabs.next();
                    case LogicalKeyboardKey.arrowUp:
                      tabs.previous();
                    case LogicalKeyboardKey.home:
                      tabs.selectIndex(1);
                    case LogicalKeyboardKey.end:
                      tabs.selectIndex(ref.read(terminalTabsProvider).tabs.length);
                    case LogicalKeyboardKey.enter ||
                        LogicalKeyboardKey.space ||
                        LogicalKeyboardKey.escape:
                      final id = ref.read(terminalTabsProvider).selectedId;
                      if (id != null) {
                        onSelected(id); // selects + focuses the terminal
                      } else {
                        onEscape();
                      }
                    default:
                      return KeyEventResult.ignored;
                  }
                  return KeyEventResult.handled;
                },
```

(import `package:flutter/services.dart`), and add the parameter `required this.onEscape` / `final VoidCallback onEscape;` to `SessionSidebar`, wired as `onEscape: focusTerminal` in the workspace. In A1 the arrow keys move the selection itself (the terminal on the right follows; the workspace's selection listener does not steal the focus while the sidebar has it) instead of a separate highlight; Enter/Space/Esc hand the keyboard back to the terminal — a deliberate simplification of UI §3.6's roving focus.

`terminal_overlays.dart` `SignedOutStrip`: add `final FocusNode? focusNode;` (constructor `this.focusNode`) and pass it to the `TextButton(focusNode: focusNode, …)`. `terminal_pane.dart`: add `final FocusNode? stripFocus;` and pass it to `SignedOutStrip(focusNode: widget.stripFocus, …)`.

- [ ] **Step 6: Run the tests to verify they pass**

Run: `cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test`
Expected: all pass (including Task 6/7 widget tests).

- [ ] **Step 7: Format, analyze, commit**

```bash
cd apps/desktop
~/fvm/versions/3.41.4/bin/dart format --set-exit-if-changed lib test
PATH=~/fvm/versions/3.41.4/bin:$PATH flutter analyze
cd ../..
git add apps/desktop/lib/src/ui/terminal apps/desktop/test/ui/terminal_shortcuts_test.dart
git commit -m "feat(desktop): terminal window shortcuts (⌘T/⌘W/⌘1–9/⌃Tab/⌘C/⌘V/⌘+−0 on macOS, Ctrl+Shift on Windows, F6 regions)"
```

---

### Task 9: Desktop — xterm benchmark (D12, criterion 8)

Measures what the UI isolate pays to parse heavy output through `DesktopTerminal` in `TerminalFeed`-sized slices. It prints numbers and never fails on them (D12: if criterion 8 is missed, the numbers are recorded and A1 ships; a renderer change is a separate project). It is tagged so a normal `flutter test` skips it.

**Files:**
- Create: `apps/desktop/dart_test.yaml`
- Create: `apps/desktop/test/terminal/xterm_benchmark_test.dart`

**Interfaces:**
- Consumes: `DesktopTerminal` (Task 4), `TerminalFeed` defaults (`budget` 256 Ki characters, Task 5).
- Produces: nothing used by later tasks; Task 10 copies its printed numbers into HANDOFF.

- [ ] **Step 1: Tag config**

`apps/desktop/dart_test.yaml`:

```yaml
tags:
  benchmark:
    skip: "Benchmark (prints numbers): flutter test --run-skipped --tags benchmark test/terminal/xterm_benchmark_test.dart"
```

- [ ] **Step 2: The benchmark**

`apps/desktop/test/terminal/xterm_benchmark_test.dart`:

```dart
@Tags(['benchmark'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/terminal/desktop_terminal.dart';
import 'package:shellx_desktop/src/terminal/terminal_feed.dart';

/// One run: [text] written in slices of [slice] characters, as TerminalFeed
/// does per frame. Returns (total ms, slowest slice ms, MB/s).
(int, int, double) _run(String text, {int slice = 256 * 1024}) {
  final terminal = DesktopTerminal();
  terminal.resize(160, 48);
  final total = Stopwatch()..start();
  var slowest = 0;
  for (var start = 0; start < text.length; start += slice) {
    final end = (start + slice).clamp(0, text.length);
    final one = Stopwatch()..start();
    terminal.write(text.substring(start, end));
    one.stop();
    if (one.elapsedMilliseconds > slowest) slowest = one.elapsedMilliseconds;
  }
  total.stop();
  final mb = text.length / (1024 * 1024);
  final seconds = total.elapsedMicroseconds / 1e6;
  return (total.elapsedMilliseconds, slowest, mb / seconds);
}

void _report(String name, (int, int, double) r) {
  final (total, slowest, rate) = r;
  // ignore: avoid_print
  print(
    'xterm benchmark — $name: total ${total}ms, slowest 256 KiB slice '
    '${slowest}ms, ${rate.toStringAsFixed(1)} MB/s '
    '(criterion 8: a slice under 1000 ms keeps the UI painting: '
    '${slowest < 1000 ? 'met' : 'NOT met'})',
  );
}

void main() {
  test('yes | head -n 2000000', () {
    _report('yes x2M', _run('y\r\n' * 2000000));
  });

  test('cat of a 50 MB text file (80-column lines)', () {
    final line = '${'0123456789abcdefghijklmnopqrstuvwxyz' * 2}01234567\r\n';
    final count = (50 * 1024 * 1024) ~/ line.length;
    _report('cat 50 MB', _run(line * count));
  });

  test('colourful output (SGR every few characters, like ls --color)', () {
    const chunk = '\x1b[1;34mdir\x1b[0m  \x1b[32mfile.sh\x1b[0m  plain.txt\r\n';
    _report('SGR 8 MB', _run(chunk * ((8 * 1024 * 1024) ~/ chunk.length)));
  });

  test('TerminalFeed caps a hidden flood at 1 MiB pending', () {
    var written = 0;
    final feed = TerminalFeed((text) => written += text.length);
    final chunk = List<int>.filled(64 * 1024, 0x79); // 'y'
    for (var i = 0; i < 800; i++) {
      feed.add(chunk); // 50 MiB arriving faster than any tick
    }
    feed.drain();
    feed.dispose();
    // ignore: avoid_print
    print(
      'TerminalFeed: 50 MiB in, ${(written / (1024 * 1024)).toStringAsFixed(2)} '
      'MiB written, ${feed.dropped} drops',
    );
    expect(written, lessThan(2 * 1024 * 1024));
  });
}
```

- [ ] **Step 3: Check it is skipped by default and runs on request**

Run: `cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/terminal/xterm_benchmark_test.dart`
Expected: 4 tests skipped.

Run: `cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test --run-skipped --tags benchmark test/terminal/xterm_benchmark_test.dart`
Expected: PASS, with four `xterm benchmark — …` / `TerminalFeed: …` lines printed. Copy those lines; Task 10 records them.

- [ ] **Step 4: Format, analyze, commit**

```bash
cd apps/desktop
~/fvm/versions/3.41.4/bin/dart format --set-exit-if-changed test/terminal/xterm_benchmark_test.dart
PATH=~/fvm/versions/3.41.4/bin:$PATH flutter analyze
cd ../..
git add apps/desktop/dart_test.yaml apps/desktop/test/terminal/xterm_benchmark_test.dart
git commit -m "test(desktop): xterm benchmark for heavy output (tagged, prints numbers, never fails CI)"
```

---

### Task 10: Docs — v1 spec amendments, HANDOFF checklist, privacy note

**Files:**
- Modify: `docs/superpowers/specs/2026-09-25-shellx-v1-design.md` (D2 row line 31, §3.2 line 53, §8.3 "Tắt Cho phép truy cập từ xa" bullet)
- Modify: `docs/superpowers/HANDOFF.md` (new section at the end)

**Interfaces:**
- Consumes: the printed benchmark lines from Task 9; the shipped behaviour of Tasks 1–8.
- Produces: nothing for code.

- [ ] **Step 1: Amend the v1 spec**

In `docs/superpowers/specs/2026-09-25-shellx-v1-design.md`:
- D2 row: append to the decision cell ` **Sửa 2026-10-06 (A1):** desktop có cửa sổ terminal; phiên dùng chung với điện thoại — xem \`2026-10-06-desktop-terminal-a1-design.md\` (D2–D7).`
- §3.2: replace `- Hiển thị/mirror terminal trên desktop.` with `- ~~Hiển thị/mirror terminal trên desktop.~~ Nay trong phạm vi (2026-10-06): \`2026-10-06-desktop-terminal-a1-design.md\`.`
- §8.3: replace the bullet `**Tắt "Cho phép truy cập từ xa":** ngắt WebSocket tới relay và đóng mọi phiên; hỏi xác nhận nếu đang có phiên. …` with `**Tắt "Cho phép truy cập từ xa":** ngắt WebSocket tới relay và ngắt mọi điện thoại; **các phiên vẫn chạy** trong cửa sổ terminal (sửa 2026-10-06, A1 D7); hỏi xác nhận nếu đang có điện thoại kết nối. Trạng thái bật/tắt được nhớ qua các lần khởi động.` Also add to the tray drawing in §8.3 a first line `  Mở cửa sổ terminal` followed by the separator.

- [ ] **Step 2: HANDOFF section**

Append to `docs/superpowers/HANDOFF.md` (fill the benchmark lines with the real output of Task 9 Step 3 and the test counts with the real `dart test` / `flutter test` summaries — never invent numbers):

```markdown
## 11. Cửa sổ terminal trên desktop — A1 (2026-10-06)

- Spec: `docs/superpowers/specs/2026-10-06-desktop-terminal-a1-design.md`; UI: `docs/superpowers/design/2026-10-06-shellx-desktop-ui.md`; plan: `docs/superpowers/plans/2026-10-06-desktop-terminal-a1.md`.
- Trạng thái: code A1 đã vào `main`. Test: agent <N> xanh, desktop <N> xanh. Windows **chưa thử trên máy thật**.
- Benchmark xterm (`flutter test --run-skipped --tags benchmark test/terminal/xterm_benchmark_test.dart`, máy <model>):
  - <dán 4 dòng in ra>
- Sửa spec v1: D2, §3.2, §8.3 (tắt truy cập từ xa / đăng xuất không còn đóng phiên; chỉ Thoát mới đóng).
- Quyền riêng tư: **không đổi** — nội dung terminal của cửa sổ chỉ ở trong tiến trình ShellX trên máy; điện thoại vẫn nhận qua kênh mã hóa đầu cuối như cũ; không thêm dữ liệu nào gửi lên relay; thông báo đẩy khi chưa đăng nhập không rời máy (API không có token thì từ chối ngay tại chỗ). Không cần sửa `web/src/pages/privacy.md` / `en/privacy.md`.

### Thử tay — macOS (máy thật)

1. Mở ShellX từ Finder/Launchpad: cửa sổ terminal hiện, có một tab zsh (`-l`) ở `~`, gõ được ngay; icon ShellX ở Dock, có trong ⌘Tab, thanh menu có "Quit ShellX ⌘Q".
2. `vim`, `htop`, `less` (phím mũi tên, Esc, màu 256/truecolor: `printf '\e[38;2;255;100;0mTRUECOLOR\e[0m\n'`), Claude Code; kéo đổi cỡ cửa sổ → chương trình vẽ lại đúng.
3. Bộ gõ tiếng Việt (Telex, Unikey/macOS VN): gõ "Tiếng Việt" trong zsh và trong vim, không mất/lặp ký tự.
4. ⌘T, ⌘W (tab rảnh: đóng ngay; tab đang chạy `sleep 100`: hỏi xác nhận), ⌘1…⌘9, ⌃Tab/⌃⇧Tab, chọn chữ rồi ⌘C, ⌘V (dán nhiều dòng trong vim khi bracketed paste bật), ⌘+/⌘−/⌘0; F6 sang sidebar, ↑/↓, Esc về terminal.
5. Điện thoại: tab mở trên desktop hiện trong danh sách phiên của điện thoại ≤ 2 s; gõ cùng lúc trên cả hai, không ai bị đẩy ra; khi điện thoại gõ, dải vàng "Điện thoại đang dùng…" hiện, cỡ PTY theo điện thoại; gõ trên desktop (sau 1 s) lấy lại. Điện thoại mở phiên → tab mới có biểu tượng điện thoại, không tự chọn.
6. Điện thoại "Đóng" một tab mở trên desktop → chỉ tách, shell vẫn chạy trên desktop.
7. Nút đỏ đóng cửa sổ → ẩn, icon Dock biến mất; điện thoại vẫn dùng được; mở lại từ Dock/Finder/tray "Mở cửa sổ terminal" → tab còn nguyên, nội dung gần nhất hiện lại; vị trí/cỡ cửa sổ được nhớ (kể cả sau khi thoát và mở lại app).
8. Đăng xuất (tray) → điện thoại bị ngắt, shell vẫn chạy, dải "Đăng nhập để dùng từ điện thoại" hiện; mở lại app khi chưa đăng nhập → không bật hộp thoại đăng nhập, terminal dùng được.
9. Tắt "Cho phép truy cập từ xa" khi có điện thoại kết nối → hỏi (câu mới), shell vẫn chạy.
10. ⌘Q với tab đang mở → một hộp xác nhận; đồng ý → mọi shell (cả cây tiến trình, kiểm tra `ps`) bị đóng, app thoát. ⌘Q lần hai khi hộp đang mở → vẫn chỉ một hộp. Đăng xuất macOS / Tắt máy khi ShellX đang chạy → không bị ShellX chặn.
11. `yes` chạy 10 s rồi Ctrl+C, và `cat` một file 50 MB: UI không treo quá 1 s; ẩn cửa sổ trong lúc chạy rồi mở lại → thấy output mới nhất.
12. Shell thoát mã 0 (`exit`) ở tab không được chọn → tab đó tự đóng, tab đang chọn giữ nguyên; `exit 3` → dòng "[Tiến trình đã thoát, mã 3] — Enter để đóng", Enter đóng tab.
13. Rút màn hình ngoài nơi cửa sổ đang nằm rồi mở lại cửa sổ → cửa sổ hiện trên màn hình còn lại (nếu không: ghi lại, sửa ở mốc sau).

### Thử tay — Windows (máy thật, Windows 10 1809+ / 11)

1. Mở ShellX từ Start menu: cửa sổ terminal hiện với một tab PowerShell ở `%USERPROFILE%`; có nút trên taskbar khi cửa sổ hiện; title bar hệ thống tối.
2. Ctrl+Shift+T / Ctrl+Shift+W / Ctrl+Alt+1…9 / Ctrl+Tab / Ctrl+Shift+Tab / Ctrl+Shift+C (có vùng chọn) / Ctrl+Shift+V / Ctrl+= / Ctrl+− / Ctrl+0; Ctrl+C trong PowerShell vẫn ngắt lệnh; Ctrl+Shift+C không có vùng chọn không làm gì sai.
3. Mục 2, 3 (bộ gõ tiếng Việt Unikey/EVKey), 5–9, 11, 12 như macOS.
4. Alt+F4 / nút X → ẩn vào khay, shell vẫn chạy; mở lại lần hai (chạy ShellX.exe lần nữa) → cửa sổ hiện lại, không có tab thứ hai.
5. Tray "Thoát" với tab đang mở → hỏi; đồng ý → `Get-Process pwsh,powershell` không còn tiến trình con của ShellX.
6. Snap layouts (Win+Z) và kéo đổi cỡ: tối thiểu 640×400, nhớ vị trí.
```

- [ ] **Step 3: Commit**

```bash
git add docs/superpowers/specs/2026-09-25-shellx-v1-design.md docs/superpowers/HANDOFF.md
git commit -m "docs: A1 amends v1 D2/§3.2/§8.3; HANDOFF manual checklist for the desktop terminal window (macOS, Windows), benchmark numbers, privacy unaffected"
```

---

## Self-Review

**1. Spec coverage**

| Spec item | Task |
|---|---|
| D1 Flutter macOS + Windows | all (Windows paths in Tasks 7–8, checklist Task 10) |
| D2 shells in the agent process behind `LocalSessions` | 2, 3, 5 (`localSessionsProvider` is the only way in) |
| D3 one `SessionKind.shellx` session kind, proto unchanged | 1 (`sessionInfos` unchanged), Global Constraints |
| D4 desktop closes all; phone `session.close` on desktop-origin = detach | 1 (incl. revoke), 2 (`close`) |
| D5 local viewer separate from the attached phone | 2 (`phone and window on the same session`) |
| D6 driver, `session.driver` only to opted-in phones, strip on desktop | 1, 2 (hold, first-resize rule), 6 (pill) |
| D7 `SessionManager` once at startup; stop disconnects; only Quit kills | 1 (`disconnectAllPhones`), 3 |
| D8 32 sessions | 1 |
| D9 one resizable window, remembered bounds, close = hide, routes as dialogs | 7 |
| D10 activation policy, ⌘Q via Dart Quit, Windows taskbar | 7 |
| D11 every launch/reactivation opens the window + a tab; signed-out strip | 6 (strip), 7 |
| D12 xterm 4.0.0 pinned, benchmark | 4, 9 |
| D13 OSC titles for shellx sessions, fallback `<shell> <index>` | 1, 5 |
| D14 exit 0 closes; non-zero line + Enter | 5, 6 |
| D15 ⌘W confirm while a command runs | 1 (`runningCommand`), 5, 6, 8 |
| D16 JetBrains Mono, dark palette, cmux-like window | 4, 6 |
| Criterion 2 shortcuts | 8 |
| Criterion 3 desktop tab visible to the phone ≤ 2 s | 1 (`changes` + `sessionInfos`; mobile refreshes on its own cadence — HANDOFF check 5) |
| Criterion 5 backlog ≤ 256 KiB on reopen | 2 (`backlog`), 5 |
| Criterion 7 Quit confirm + tree kill | 3, 7 |
| Criterion 8 heavy output | 5 (`TerminalFeed`), 9 |
| §5 limit / spawn failure toasts, hidden-tab output | 5, 6 |
| §6 tests | 1–9 |
| v1 spec amendments, HANDOFF | 10 |

**2. Placeholder scan** — no "TBD"/"similar to"; the only fill-ins are measured numbers in HANDOFF (Task 10 says to paste real output, never invent).

**3. Type consistency** — checked: `SessionManager.open/view/close/disconnectAllPhones/receivesDriver`, `LocalSessionView.reply/dispose/closedOnRequest`, `SessionCore.sessions/ids/notifications`, `DesktopServices.sessions`, `TerminalTabs.openTab/ensureTab/select/selectIndex/next/previous/needsCloseConfirm/close/dismissNotice/reportGrid`, `TerminalTab.label/selection/terminal/exitCode`, `WindowRouter.showTerminal/hideWindow`, `WindowHost.show/hide/setTitle`, `openTerminalWindow`, `handleActivation(container)`, `listenForAppChannel`, `setDockVisible`, `desktopShortcuts` are spelled the same in every task that uses them.

**4. Review Focus** — each of the five lines has its pinning test in the owning task (Task 2 interleaved typing; Task 5 feed cap/budget + Task 9; Task 7 double ⌘Q + Task 3 shutdown; Task 3 signed-out/remote-off keep shells + Task 7 no forced login; Task 5 exit/selection/closedOnRequest).

