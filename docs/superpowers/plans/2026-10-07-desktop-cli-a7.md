# ShellX Desktop A7 — `shellx` CLI and Socket API Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Scripts and AI agents drive ShellX from any terminal through a `shellx` command (tabs, panes, workspaces, send/read/wait, notifications, browser panes, events) over the authenticated local socket of A5b — served by the window process today and by the `shellx-mux` daemon once A5b lands — plus installable agent skills.

**Architecture:** The Rust `shellx-term` binary gains a `term/src/api/` module (own full CBOR codec, A5b frame + mutual-HMAC handshake client, table-driven argument parser, command runner, embedded skills) and switches to CLI mode when invoked as `shellx`. `packages/shellx_agent` gains a pure-Dart `CliHost` that listens on the A5b socket/pipe address with role `cli`, answers `api.*`/`cli.*` itself and hands `ui.*` to the desktop's `UiCommandHandler` (`apps/desktop/lib/src/cli/`), which drives `TerminalTabs`, `SidebarWorkspaces`, `TabAttention` and A6's `BrowserCommandHandler`. The agent gains `LocalSessions.open(tabId:)`, `LocalSessions.notify` and per-pane environment variables. After A5b, the daemon accepts role `cli` and forwards `ui.*` to the attached window; one contract suite covers both hosts.

**Tech Stack:** Rust 2021 (`~/.cargo/bin/cargo`, existing deps only: `hmac`, `sha2`, `getrandom`, `libc`, `winapi`), Dart ^3.11 / Flutter 3.41.4 via fvm (`~/fvm/versions/3.41.4/bin/dart`, `PATH=~/fvm/versions/3.41.4/bin:$PATH flutter`), `package:test` + `fake_async`, `flutter_test`, flutter_riverpod 3, xterm 4.0.0, `shellx_core` CBOR (`encodeCbor`/`decodeCbor`), A5b mux wire (`MuxMessage`, `serverHandshake`, `MuxTransport`).

**Spec:** `docs/superpowers/specs/2026-10-07-desktop-cli-a7-design.md` (binding; C1–C7 and D1–D40 are final). Read alongside: A5b spec + plan Tasks 2–4 (wire, endpoint, transports, `MuxServer`), A6 spec §3.6 and plan Task 10 (`BrowserCommandHandler`), A3 spec D1–D17, A4 spec D4–D16, A5a plan Task 1 (`encodeScrollback`).

## Prerequisite: A3, A4, A5a, A6 merged; A5b optional

Start `feat/desktop-a7` from `main` **after A3, A4, A5a and A6 are merged** (spec D1). A5b may or may not be merged: Task 2 and Task 11 branch on it — check once at the start:

```bash
test -f packages/shellx_agent/lib/src/mux/mux_server.dart && echo "A5b merged" || echo "A5b not merged"
```

Record the answer in `docs/superpowers/ledgers/a1-desktop-terminal.md` under a new heading `## A7 (CLI) — execution`. If A6 is **not** merged, Task 8 skips its browser step and records "browser pending A6" in the ledger; the CLI then reports `unknown_type` for `shellx browser` (exit 7).

Tasks marked **⚠ MANUAL** need a real Mac (macOS 13+) and a real Windows 10 1809+/11 machine; an executor without the machine records "pending manual" in the ledger section and continues — **the branch is not merged until every ⚠ step is recorded as passed.**

Baseline before Task 1 (record the counts in the ledger):

```bash
cd term && ~/.cargo/bin/cargo test --features test-hooks && cd ..
cd packages/shellx_agent && ~/fvm/versions/3.41.4/bin/dart test && cd ../..
cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test && cd ../..
```

## Global Constraints

- The spec wins. User-facing app strings in vi + en ARB; the CLI's own output is **English only** (D11). In Vietnamese UI copy keep "pane", "tab", "workspace", "Agent" in English (A3 §7).
- **Phone protocol unchanged (D28):** no edits to `packages/shellx_core/lib/src/protocol/messages.dart`, `apps/mobile`, `relay/`. No new dependencies in any `pubspec.yaml` or `term/Cargo.toml`.
- **Terminal-sharing link unchanged (D6):** `term/src/proto/*`, `term/src/wrap.rs`, `term/src/winwrap.rs`, `term/shell/*` keep their bytes; all existing `cargo test --features test-hooks` tests stay green.
- Wire: A5b frames (4-byte big-endian length + one CBOR map, ≤ 65,536 bytes), `kMuxProtocol = 1`, handshake labels `shellx-mux/daemon` / `shellx-mux/client`, nonces 32 bytes, handshake timeout 2 s. `kCliApi = 1`. Unknown keys ignored; unknown request types → `error{code: unknown_type}`.
- Role `cli` may send only `api.*`, `cli.*`, `ui.*`, `daemon.status`; anything else → `error{code: forbidden}` (connection stays open) (D3).
- Error codes (D5): `unknown_type`, `bad_request`, `not_found`, `busy`, `unsupported_role`, `session_limit`, `spawn_failed`, `internal`, `forbidden`, `cli_disabled`, `no_ui`, `timeout`, `exited`, `running_command`, `no_room`, `ambiguous`, plus A6 §3.6 browser codes.
- Exit codes (D10): 0 ok · 1 other error · 2 usage · 3 not running/connect/handshake · 4 not found/ambiguous · 5 timeout · 6 refused (`cli_disabled`, `forbidden`, `forbidden_origin`, `running_command`, skill overwrite refused) · 7 incompatible (`api`, missing cap, `unknown_type`) · 8 `no_ui`.
- Limits: ≤ 8 authenticated `cli` connections, ≤ 4 handshaking, requests on one connection run serially; text fields ≤ 49,152 bytes (48 KiB); `--cmd` ≤ 16,384 bytes; `read --lines` 1–10,000; read pages ≤ 49,152 bytes; `wait` timeout default 30 s, max 3,600 s; regex ≤ 1,024 chars, scanned text ≤ 2,000 lines / 262,144 chars; events queue ≤ 1,000 per listener, ≤ 4 listeners; notify body ≤ 1,024 chars, title ≤ 128 chars; open-busy wait 10 s polling 50 ms; Agent mark 10 s, announcement ≤ 1 per 60 s; `--cmd` readiness: first cwd report, else 1.5 s quiet after first output, max 5 s; `idle` quiet default 500 ms, unhooked 2 s.
- Settings (UI-owned per A5b D13): `cli_control_enabled` (bool, default `true`), `cli_path_installed` (bool, default `false`).
- Environment in every ShellX shell (D29): `SHELLX=1`, `SHELLX_PANE_ID`, `SHELLX_TAB_ID`, `SHELLX_SOCKET`, `PATH` prefixed with the CLI directory.
- Paths: CLI binary macOS `~/Library/Application Support/ShellX/cli/shellx`, Windows `%LOCALAPPDATA%\ShellX\cli\shellx.exe`; endpoint macOS `~/Library/Application Support/pro.shellx.desktop/mux/endpoint`, Windows `%LOCALAPPDATA%\ShellX\mux\endpoint`.
- Privacy (D38): never log request/response contents, typed or read text, regexes, scripts, URLs, notification text, secrets or user paths — only message type, error code, `runtimeType`.
- Every interface gaining members updates **every** implementer in the same task (`SessionManager`, `FakeLocalSessions`, and `RemoteLocalSessions` when A5b is merged).
- Code style as in A1–A6. Every task ends green (its tests + the full suite of every package it touched), `dart format --set-exit-if-changed`, `flutter analyze`/`dart analyze`, `cargo fmt --check` + `cargo clippy --all-targets -- -D warnings` for Rust tasks, and a commit containing only the listed files — never `git add -A`.

## Review Focus

1. **An agent sends hostile text** (`ESC[201~` inside `--text`, control bytes, a 1 MB `--stdin`) — it must arrive as a paste, never as keystrokes, and oversize input must be refused before anything is written. Pinned by `ui_command_handler_send_test` (Task 7) and the Rust size check in `run` (Task 10).
2. **The pane, tab or workspace an agent names is gone or ambiguous** (closed between `ls` and `send`, two workspaces named "api", `@self` outside ShellX, a browser pane passed to `read`) — clear error and exit 4/2/1, never acting on a different object. Pinned by `cli_targets_test` (Task 6) and `run_test` (Task 10).
3. **A CLI client disappears mid-request** (Ctrl+C during `wait`/`events`, killed process, half a frame) — the host cancels the waiter/subscription, frees the connection slot and never throws into the UI. Pinned by `cli_host_test` "a client closing mid-request" (Task 5), `pane_waiter_test` "a client that goes away ends the wait at once" (Task 7) and `cli_e2e_test` "killing it frees the host" (Task 11).
4. **The user is mid-action when an agent acts** (a split already opening, the user typing in pane A while `split` runs, a confirm dialog open) — the agent waits for the in-flight open, never steals focus or selection without `--focus`, and never opens dialogs. Pinned by `ui_command_handler_test` "split: any tab, right/down, keeps focus unless asked" and "waits for an open in flight (D33)" (Task 6).
5. **A mismatched pair** (new CLI, old ShellX without a cap; old daemon `protocol`; stale endpoint file; a squatter without the secret) — exit 7 or 3 with an actionable message, never a hang and never a request sent before the peer proved the secret. Pinned by Rust client tests (Task 3) and `run_test` caps tests (Task 10).

---

## File Structure

| File | Responsibility |
|---|---|
| Modify `packages/shellx_agent/lib/src/session/local_sessions.dart` | `open(tabId:)`, `notify` (D23, D29) |
| Modify `packages/shellx_agent/lib/src/session/session_manager.dart` | id before spawn, pane env, `notify` |
| Modify `packages/shellx_agent/lib/src/pty/session_environment.dart` | `SHELLX_PANE_ID`, `SHELLX_TAB_ID` |
| Modify `packages/shellx_agent/lib/src/notify/agent_notifications.dart` | `SessionNotifier.message` |
| Create (if A5b not merged) `packages/shellx_agent/lib/src/mux/{mux_messages,mux_handshake,mux_endpoint,mux_transport}.dart`, `apps/desktop/lib/src/mux/{windows_pipe_transport,mux_paths}.dart` | A5b wire, verbatim from A5b plan Tasks 2, 3, 7 |
| Create `packages/shellx_agent/lib/src/mux/cli_wire.dart` | A7 constants: `kCliApi`, `CliType`, `CliError` |
| Create `packages/shellx_agent/lib/src/mux/{ui_api,cli_host}.dart` | `UiApi`, `CliFailure`, `CliHost` (pure Dart; reused by the A5b daemon and the e2e test) |
| Create `term/protocol/mux_vectors.txt` | Rust↔Dart golden vectors (D37b) |
| Create `term/src/api/{mod,value,wire,endpoint,client,args,run,browser_js,skills,output}.rs` | the CLI |
| Modify `term/src/lib.rs`, `term/src/main.rs` | `pub mod api`; name dispatch (D6) |
| Create `agent-skills/shellx/SKILL.md`, `agent-skills/shellx/reference.md` | skills (D35) |
| Create `apps/desktop/lib/src/cli/{cli_targets,ui_command_handler,pane_text,pane_waiter,cli_event_bus,agent_marks,cli_install,cli_install_windows,cli_service}.dart`, `apps/desktop/lib/src/ui/terminal/agent_chip.dart` | UI handler, waits, events, install, service, chip |
| Modify `apps/desktop/lib/src/terminal/terminal_tabs.dart` | `openTabFor`, `splitPane`, `paneSession`, `tabId` on opens |
| Modify `apps/desktop/lib/src/terminal/sidebar_workspaces.dart` | `createFor` (named, no focus) |
| Modify `apps/desktop/lib/src/terminal/tab_attention.dart` | command-line entries (tabless) |
| Modify `apps/desktop/lib/src/restore/scrollback_codec.dart` | expose `encodeLogicalLines` for `read --ansi` |
| Modify `apps/desktop/lib/src/platform/settings_store.dart` | `cliControlEnabled`, `cliPathInstalled` |
| Modify `apps/desktop/lib/src/tray/{tray_action,tray_menu,tray_actions}.dart` | "Dòng lệnh" submenu |
| Modify `apps/desktop/lib/src/ui/terminal/session_tab_row.dart`, `pane_tree_view.dart` | Agent chip |
| Modify `apps/desktop/lib/l10n/app_en.arb`, `app_vi.arb` (+ generated) | strings |
| Modify `apps/desktop/lib/main.dart` | start `CliService`, base environment |
| Modify `apps/desktop/test/support/fake_local_sessions.dart` | new members |
| Create `apps/desktop/test/cli/**`, `packages/shellx_e2e/test/cli_e2e_test.dart` | tests |
| Modify `release/windows/shellx.iss`, `release/tests/inno.test.mjs`, `term/src/uninstall.rs` | remove `cli/` and the user PATH entry on uninstall |
| Modify `docs/superpowers/HANDOFF.md`, ledger | manual checklist |

---

### Task 1: Agent — pane environment, `open(tabId:)`, `LocalSessions.notify` (D23, D29)

**Files:**
- Modify: `packages/shellx_agent/lib/src/pty/session_environment.dart`, `packages/shellx_agent/lib/src/session/local_sessions.dart`, `packages/shellx_agent/lib/src/session/session_manager.dart`, `packages/shellx_agent/lib/src/notify/agent_notifications.dart`
- Modify: `apps/desktop/test/support/fake_local_sessions.dart`; if A5b merged also `packages/shellx_agent/lib/src/mux/remote_local_sessions.dart` + `mux_server.dart` (`sessions.open` gains `tab`; new one-way `sessions.notify{id, title?, body}`)
- Test: `packages/shellx_agent/test/session/local_sessions_test.dart`, `packages/shellx_agent/test/notify/session_notifications_test.dart`, `packages/shellx_agent/test/pty/shell_resolver_test.dart`

**Interfaces:**
- Produces:
  - `Map<String, String> buildSessionEnvironment(Map<String, String> base, {int? paneId, int? tabId})` — adds `SHELLX_PANE_ID`/`SHELLX_TAB_ID` when given.
  - `LocalSessions.open({required int cols, required int rows, String? cwd, int? tabId})` — `SHELLX_TAB_ID = tabId ?? <new id>`.
  - `bool LocalSessions.notify(int id, {String? title, required String body})` — false when no live session `id`; otherwise exactly what an OSC 777 from that session does: push via `SessionNotifier.message` and a `SessionNotice(kind: message)` on `notices`, under the same per-session limiter.
  - `void SessionNotifier.message({String? title, required String body})`.
  - `FakeLocalSessions.openTabIds` (`List<int?>`), `FakeLocalSessions.notified` (`List<(int, String?, String)>`), `FakeLocalSessions.notify` emits a notice for known ids.

- [ ] **Step 1: Write the failing tests**

Append to `packages/shellx_agent/test/pty/shell_resolver_test.dart` inside `group('buildSessionEnvironment', …)`:

```dart
    test('pane and tab ids (A7 D29)', () {
      final env = buildSessionEnvironment({'PATH': '/bin'}, paneId: 41, tabId: 7);
      expect(env['SHELLX'], '1');
      expect(env['SHELLX_PANE_ID'], '41');
      expect(env['SHELLX_TAB_ID'], '7');
      final none = buildSessionEnvironment({'PATH': '/bin'});
      expect(none.containsKey('SHELLX_PANE_ID'), isFalse);
      expect(none.containsKey('SHELLX_TAB_ID'), isFalse);
    });
```

Append to `packages/shellx_agent/test/session/local_sessions_test.dart` (it already builds a `SessionRig`; follow its `main` layout):

```dart
  group('A7 D29 pane environment', () {
    test('a new tab session gets its own id as pane and tab', () async {
      final rig = SessionRig();
      final id = await rig.manager.open(cols: 80, rows: 24);
      final env = rig.pty(0).environment;
      expect(env['SHELLX_PANE_ID'], '$id');
      expect(env['SHELLX_TAB_ID'], '$id');
      expect(env['PATH'], '/usr/bin');
    });

    test('a split passes the tab id; a phone session is its own tab', () async {
      final rig = SessionRig();
      final first = await rig.manager.open(cols: 80, rows: 24);
      final second = await rig.manager.open(cols: 40, rows: 24, tabId: first);
      expect(rig.pty(1).environment['SHELLX_PANE_ID'], '$second');
      expect(rig.pty(1).environment['SHELLX_TAB_ID'], '$first');
      final phoneId = await rig.open(phone);
      expect(rig.pty(2).environment['SHELLX_PANE_ID'], '$phoneId');
      expect(rig.pty(2).environment['SHELLX_TAB_ID'], '$phoneId');
    });
  });

  group('A7 D23 notify', () {
    test('a live session reports a message notice; unknown ids are false', () async {
      final rig = SessionRig();
      final id = await rig.manager.open(cols: 80, rows: 24);
      final notices = <SessionNotice>[];
      rig.manager.notices.listen(notices.add);
      expect(rig.manager.notify(id, title: 'CI', body: 'Build xong'), isTrue);
      expect(rig.manager.notify(id + 999, body: 'x'), isFalse);
      await Future<void>.delayed(Duration.zero);
      expect(notices.single.sessionId, id);
      expect(notices.single.kind, SessionNoticeKind.message);
      expect(notices.single.title, 'CI');
      expect(notices.single.body, 'Build xong');
    });

    test('shares the 30-per-minute limiter with OSC notices (A4 D6)', () async {
      final rig = SessionRig();
      final id = await rig.manager.open(cols: 80, rows: 24);
      final notices = <SessionNotice>[];
      rig.manager.notices.listen(notices.add);
      for (var i = 0; i < 31; i++) {
        rig.manager.notify(id, body: '$i');
      }
      await Future<void>.delayed(Duration.zero);
      expect(notices, hasLength(30));
    });
  });
```

Append inside `group('SessionManager (ShellX sessions)', …)` of `packages/shellx_agent/test/notify/session_notifications_test.dart`:

```dart
    test('LocalSessions.notify pushes exactly like OSC 777 (A7 D23)', () async {
      final id = await open();
      expect(manager.notify(id, title: 'CI', body: 'Build xong'), isTrue);
      await push.notifications.sender.idle;
      expect(push.bodies.single['title'], 'CI');
      expect(push.bodies.single['body'], 'Build xong');
      expect((push.bodies.single['data'] as Map)['kind'], 'message');
      expect((push.bodies.single['data'] as Map)['session_id'], '$id');
    });
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd packages/shellx_agent && ~/fvm/versions/3.41.4/bin/dart test test/pty/shell_resolver_test.dart test/session/local_sessions_test.dart test/notify/session_notifications_test.dart`
Expected: FAIL — `paneId` is not a parameter, `tabId` is not a parameter, `notify` is not defined.

- [ ] **Step 3: Implement**

`session_environment.dart`:

```dart
/// Environment for a new terminal session (spec §7): the agent's own
/// environment plus `TERM=xterm-256color`, `COLORTERM=truecolor`,
/// `LANG=en_US.UTF-8` when LANG is unset or empty, `SHELLX=1`, and (A7 D29)
/// `SHELLX_PANE_ID` / `SHELLX_TAB_ID` so programs in the pane can target it.
Map<String, String> buildSessionEnvironment(
  Map<String, String> base, {
  int? paneId,
  int? tabId,
}) {
  final environment = Map<String, String>.of(base);
  environment['TERM'] = 'xterm-256color';
  environment['COLORTERM'] = 'truecolor';
  if ((environment['LANG'] ?? '').isEmpty) {
    environment['LANG'] = 'en_US.UTF-8';
  }
  environment['SHELLX'] = '1';
  if (paneId != null) environment['SHELLX_PANE_ID'] = '$paneId';
  if (tabId != null) environment['SHELLX_TAB_ID'] = '$tabId';
  return environment;
}
```

`local_sessions.dart` — replace the `open` declaration and add `notify` after `close`:

```dart
  /// … (keep the A3 D17 text) … [tabId] (A7 D29) is the tab the new pane
  /// joins; null means the session starts its own tab, whose id is its own
  /// (A3 D1). Exposed to the shell as `SHELLX_TAB_ID`.
  Future<int> open({
    required int cols,
    required int rows,
    String? cwd,
    int? tabId,
  });

  /// A7 D23: `shellx notify` for session [id] — the same as the session
  /// printing OSC 777 (push to the phone and a [SessionNotice] on
  /// [notices], under the session's flood limit). False when there is no
  /// live session [id].
  bool notify(int id, {String? title, required String body});
```

`agent_notifications.dart` — in `SessionNotifier`, add `message` and make `_handle` use it:

```dart
  /// A program's message (OSC 9/777 or `shellx notify`, A7 D23).
  void message({String? title, required String body}) {
    try {
      final text = _text();
      _owner.sender.send(
        AgentNotification(
          title: title ?? _title(text),
          body: body,
          data: _data('message'),
        ),
      );
    } catch (_) {
      // A notification must never break the session.
    }
  }

  void _handle(OscEvent event) {
    if (event is NotifyRequested) {
      message(title: event.title, body: event.body);
      return;
    }
    // … unchanged command branch …
  }
```

(`NotifyRequested.body` is non-null in the parser; if its type is `String?`, pass `event.body ?? ''`.)

`session_manager.dart`:

1. `open` gains `int? tabId` and passes it: `final session = await _spawn(c, r, origin: SessionOrigin.desktop, cwd: cwd, tabId: tabId);`
2. In `_spawn`, add the `int? tabId` parameter, move `final id = _nextId();` to **before** `_ptyFactory.spawn` (right after `_pendingOpens++` and the limit check), and build the launch with the ids. Remove the later `final id = _nextId();`:

```dart
    _pendingOpens++;
    // A7 D29: the id is known before the shell starts so it can be in its
    // environment. Ids are never reused, so a failed spawn only skips one.
    final id = _nextId();
    final ShellCommand command;
    final Pty pty;
    try {
      command = await _shellResolver.resolve();
      final workingDirectory = await _workingDirectoryFor(cwd);
      final launch = _launch(command, paneId: id, tabId: tabId ?? id);
      // … spawn unchanged …
```

3. `_launch`:

```dart
  ShellLaunch _launch(ShellCommand command, {required int paneId, required int tabId}) {
    final environment = buildSessionEnvironment(
      _baseEnvironment,
      paneId: paneId,
      tabId: tabId,
    );
    // … rest unchanged …
  }
```

4. `notify`:

```dart
  @override
  bool notify(int id, {String? title, required String body}) {
    final session = _sessions[id];
    if (session == null || session.closing || session.exited) return false;
    session.notifier?.message(title: title, body: body);
    _notice(session, SessionNoticeKind.message, title: title, body: body);
    return true;
  }
```

Check the `_notice` limiter also guards the push: if the A4 limiter refuses, the push still went out — to keep "same as OSC 777" exact, call `session.notifier?.message` **only** when `_notice` admitted the notice. Change `_notice` to return `bool` (`return false` on the early exits and when `!allowed`, `return true` after `_notices.add`) and write `if (_notice(...)) session.notifier?.message(...)`. OSC 777 today pushes through `notifier.feed` independently of the A4 limiter; record in the ledger that `notify` is the stricter of the two (cost: a burst over 30/min pushes fewer).

Other `_launch` callers (term-sharing `DesktopSessionManager`, if it calls `buildSessionEnvironment`) keep calling it without ids.

`apps/desktop/test/support/fake_local_sessions.dart`:

```dart
  /// The `tabId` of each [open] call (A7 D29).
  final openTabIds = <int?>[];

  /// Every [notify] call: (id, title, body).
  final notified = <(int, String?, String)>[];

  @override
  Future<int> open({
    required int cols,
    required int rows,
    String? cwd,
    int? tabId,
  }) async {
    opens.add((cols, rows));
    openCwds.add(cwd);
    openTabIds.add(tabId);
    // … rest unchanged …
  }

  @override
  bool notify(int id, {String? title, required String body}) {
    notified.add((id, title, body));
    if (!summaries.any((s) => s.id == id)) return false;
    notice(id, SessionNoticeKind.message, title: title, body: body);
    return true;
  }
```

If A5b is merged: `RemoteLocalSessions.open` adds `'tab': tabId` (omit when null) to `sessions.open`; `RemoteLocalSessions.notify` sends a request `sessions.notify{id, title?, body}` and returns `true` optimistically (the daemon answers `not_found` for unknown ids — log the code only); `MuxServer` handles `sessions.notify` by calling `sessions.notify` and answering `result{}` / `error{not_found}`; it reads `tab` in `sessions.open`. Add one round-trip test per new key to `packages/shellx_agent/test/mux/mux_server_test.dart`.

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd packages/shellx_agent && ~/fvm/versions/3.41.4/bin/dart test` then `cd ../../apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test`
Expected: PASS (every suite).

- [ ] **Step 5: Format, analyze, commit**

```bash
cd packages/shellx_agent && ~/fvm/versions/3.41.4/bin/dart format --set-exit-if-changed lib test && ~/fvm/versions/3.41.4/bin/dart analyze && cd ../..
cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH dart format --set-exit-if-changed test/support && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter analyze && cd ../..
git add packages/shellx_agent/lib/src/pty/session_environment.dart packages/shellx_agent/lib/src/session/local_sessions.dart packages/shellx_agent/lib/src/session/session_manager.dart packages/shellx_agent/lib/src/notify/agent_notifications.dart packages/shellx_agent/test/pty/shell_resolver_test.dart packages/shellx_agent/test/session/local_sessions_test.dart packages/shellx_agent/test/notify/session_notifications_test.dart apps/desktop/test/support/fake_local_sessions.dart
# if A5b merged, also: packages/shellx_agent/lib/src/mux/remote_local_sessions.dart packages/shellx_agent/lib/src/mux/mux_server.dart packages/shellx_agent/test/mux/mux_server_test.dart
git commit -m "feat(agent): SHELLX_PANE_ID/SHELLX_TAB_ID in every shell, open(tabId:), LocalSessions.notify (A7 D23, D29)"
```

---

### Task 2: Mux wire for the CLI — A5b wire if missing, A7 constants, golden vectors (D2, D4, D5, D37b)

**Files:**
- If A5b is **not** merged — create exactly as written in the A5b plan (`docs/superpowers/plans/2026-10-07-desktop-daemon-a5b.md`), test files included:
  - A5b Task 2 → `packages/shellx_agent/lib/src/mux/mux_messages.dart`, `mux_handshake.dart`, `mux_transport.dart` (interface + `MemoryMuxTransport`), tests `test/mux/mux_messages_test.dart`, `test/mux/mux_handshake_test.dart`
  - A5b Task 3 → `mux_endpoint.dart`, `mux_transport.dart` additions (`MuxListener`, `MuxTransport`, `UnixMuxTransport`, `socketPathFor`, `StreamMuxConnection`), `apps/desktop/lib/src/mux/windows_pipe_transport.dart`, tests `test/mux/mux_endpoint_test.dart`, `test/mux/unix_mux_transport_test.dart`, `apps/desktop/test/mux/windows_pipe_transport_test.dart`
  - A5b Task 7, only the `MuxPaths` class → `apps/desktop/lib/src/mux/mux_paths.dart` + its test cases from A5b Task 7
  - The exports A5b adds to `packages/shellx_agent/lib/shellx_agent.dart`
- Always — create: `packages/shellx_agent/lib/src/mux/cli_wire.dart`, `packages/shellx_agent/test/mux/cli_wire_test.dart`, `term/protocol/mux_vectors.txt`; modify `packages/shellx_agent/lib/shellx_agent.dart`

**Interfaces:**
- Consumes (A5b): `MuxMessage`, `MuxType`, `MuxError`, `encodeMux`, `MuxFrameDecoder`, `daemonProof`, `clientProof`, `MuxPeerInfo`, `serverHandshake`, `clientHandshake`, `MuxHandshakeException`, `MuxConnection`, `MuxListener`, `MuxTransport`, `MemoryMuxTransport.pair()`, `UnixMuxTransport`, `socketPathFor`, `MuxEndpointInfo`, `MuxEndpointFile`, `MuxPaths`, `WindowsPipeTransport`, `pipeNameForUser`.
- Produces:
  - `const int kCliApi = 1;`
  - `abstract final class CliType { apiVersion = 'api.version', cliNotify = 'cli.notify', cliEventsSubscribe = 'cli.events.subscribe', event = 'event', uiLs = 'ui.ls', uiTabNew = 'ui.tab.new', uiTabRename = 'ui.tab.rename', uiPaneSplit = 'ui.pane.split', uiFocus = 'ui.focus', uiClose = 'ui.close', uiPaneSend = 'ui.pane.send', uiPaneRead = 'ui.pane.read', uiPaneWait = 'ui.pane.wait', uiWorkspaceNew = 'ui.workspace.new', uiWorkspaceRename = 'ui.workspace.rename', uiWorkspaceMove = 'ui.workspace.move', uiNotify = 'ui.notify', uiEventsSubscribe = 'ui.events.subscribe', uiBrowserPrefix = 'ui.browser.'; static bool allowedForCli(String t) }`
  - `abstract final class CliError { forbidden, cliDisabled = 'cli_disabled', noUi = 'no_ui', timeout, exited, runningCommand = 'running_command', noRoom = 'no_room', ambiguous }`
  - `const List<String> kCliCaps` — every `ui.*`/`cli.*` type the host supports plus `'ui.browser'`.
  - `MuxMessage cliResult(int? q, [Map<String, Object?> fields])`, `MuxMessage cliErrorMessage(int? q, String code, [String? message])`.
  - `term/protocol/mux_vectors.txt` lines `name=hex`, pinned by `cli_wire_test.dart` (writer + reader) and consumed by Rust in Task 3.

- [ ] **Step 1: A5b wire (only if A5b is not merged)**

Follow A5b plan Task 2 Steps 1–5, then Task 3 Steps 1–5, exactly (TDD order, same tests, same code). Then add `MuxPaths` from A5b plan Task 7 with its tests. Use commit messages `feat(agent): mux wire for the CLI host — A5b Task 2 (A7 D2)` and `feat(agent): mux endpoint and transports — A5b Task 3 (A7 D2)`. Windows pipe tests are `@TestOn('windows')` — ⚠ MANUAL on a Windows machine (record in ledger). Append to the ledger: `A7 created the A5b wire (Tasks 2, 3, MuxPaths): A5b executor verifies these files instead of writing them.`

If A5b **is** merged, skip this step.

- [ ] **Step 2: Write the failing test for the A7 constants and vectors**

Create `packages/shellx_agent/test/mux/cli_wire_test.dart`:

```dart
import 'dart:io';
import 'dart:typed_data';

import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:test/test.dart';

/// Shared with `term/` (Rust reads the same file, A7 D37b).
final _vectorsFile = File('../../term/protocol/mux_vectors.txt');

final _secret = Uint8List.fromList(List.filled(32, 0x42));
final _nonceClient = Uint8List.fromList(List.generate(32, (i) => i + 1));
final _nonceDaemon = Uint8List.fromList(List.generate(32, (i) => 0x80 + i));

/// name → CBOR bytes of the payload (no length prefix), keys in the
/// insertion order written here (Dart maps keep it).
Map<String, Uint8List> _samples() => {
  'cli.hello': encodeCbor({
    't': 'hello', 'protocol': 1, 'app': 'shellx-cli/0.1.0', 'role': 'cli',
    'nonce': _nonceClient,
  }),
  'cli.auth': encodeCbor({
    't': 'auth', 'proof': clientProof(_secret, _nonceDaemon, _nonceClient),
  }),
  'cli.api_version': encodeCbor({'t': 'api.version', 'q': 1}),
  'host.api_version': encodeCbor({
    't': 'result', 'q': 1, 'api': 1, 'app': '1.7.0', 'host': 'ui', 'ui': true,
    'caps': ['ui.ls', 'ui.browser'],
  }),
  'host.error': encodeCbor({
    't': 'error', 'q': 2, 'code': 'not_found', 'message': 'no pane p12',
  }),
  'host.event': encodeCbor({
    't': 'event', 'kind': 'pane.exited', 'pane': 12, 'tab': -3, 'exitCode': null,
  }),
};

String _hex(Uint8List b) => b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

void main() {
  test('cli role allowlist (A7 D3)', () {
    for (final t in ['api.version', 'cli.notify', 'ui.ls', 'ui.browser.eval', 'daemon.status']) {
      expect(CliType.allowedForCli(t), isTrue, reason: t);
    }
    for (final t in ['sessions.open', 'view.write', 'agent.call', 'daemon.quit', 'hello', 'uix']) {
      expect(CliType.allowedForCli(t), isFalse, reason: t);
    }
  });

  test('result and error helpers', () {
    expect(cliResult(3, {'pane': 9}).fields, {'pane': 9});
    expect(cliResult(3).type, MuxType.result);
    final e = cliErrorMessage(4, CliError.cliDisabled, 'off');
    expect([e.type, e.q, e.get<String>('code'), e.get<String>('message')],
        [MuxType.error, 4, 'cli_disabled', 'off']);
  });

  test('golden vectors match term/protocol/mux_vectors.txt', () {
    final lines = {
      for (final l in _vectorsFile.readAsLinesSync())
        if (l.isNotEmpty && !l.startsWith('#')) l.split('=')[0]: l.split('=')[1],
    };
    final samples = _samples();
    final expected = {
      'auth.secret': _hex(_secret),
      'auth.nonce_client': _hex(_nonceClient),
      'auth.nonce_daemon': _hex(_nonceDaemon),
      'auth.daemon_proof': _hex(daemonProof(_secret, _nonceClient, _nonceDaemon)),
      'auth.client_proof': _hex(clientProof(_secret, _nonceDaemon, _nonceClient)),
      for (final e in samples.entries) e.key: _hex(e.value),
    };
    if (Platform.environment['WRITE_VECTORS'] == '1') {
      _vectorsFile.writeAsStringSync([
        '# A5b mux / A7 CLI reference bytes. name=hex of the CBOR map (no length prefix).',
        '# Generated by packages/shellx_agent/test/mux/cli_wire_test.dart (WRITE_VECTORS=1);',
        '# read by term/src/api tests. Never edit by hand.',
        for (final e in expected.entries) '${e.key}=${e.value}',
        '',
      ].join('\n'));
    }
    expect(lines, expected);
  });
}
```

- [ ] **Step 3: Run test to verify it fails**

Run: `cd packages/shellx_agent && ~/fvm/versions/3.41.4/bin/dart test test/mux/cli_wire_test.dart`
Expected: FAIL — `CliType` undefined.

- [ ] **Step 4: Implement**

Create `packages/shellx_agent/lib/src/mux/cli_wire.dart`:

```dart
import 'mux_messages.dart';

/// A7 D4: the CLI API version, separate from A5b's `protocol`. Bump only
/// for a breaking change; additions go in [kCliCaps].
const int kCliApi = 1;

abstract final class CliType {
  static const apiVersion = 'api.version';
  static const cliNotify = 'cli.notify';
  static const cliEventsSubscribe = 'cli.events.subscribe';
  static const event = 'event';
  static const uiLs = 'ui.ls';
  static const uiTabNew = 'ui.tab.new';
  static const uiTabRename = 'ui.tab.rename';
  static const uiPaneSplit = 'ui.pane.split';
  static const uiFocus = 'ui.focus';
  static const uiClose = 'ui.close';
  static const uiPaneSend = 'ui.pane.send';
  static const uiPaneRead = 'ui.pane.read';
  static const uiPaneWait = 'ui.pane.wait';
  static const uiWorkspaceNew = 'ui.workspace.new';
  static const uiWorkspaceRename = 'ui.workspace.rename';
  static const uiWorkspaceMove = 'ui.workspace.move';
  static const uiNotify = 'ui.notify';
  static const uiEventsSubscribe = 'ui.events.subscribe';
  static const uiBrowserPrefix = 'ui.browser.';

  /// D3: what a `cli` client may send. Everything else is `forbidden`.
  static bool allowedForCli(String t) =>
      t.startsWith('api.') ||
      t.startsWith('cli.') ||
      t.startsWith('ui.') ||
      t == MuxType.daemonStatus;
}

abstract final class CliError {
  static const forbidden = 'forbidden';
  static const cliDisabled = 'cli_disabled';
  static const noUi = 'no_ui';
  static const timeout = 'timeout';
  static const exited = 'exited';
  static const runningCommand = 'running_command';
  static const noRoom = 'no_room';
  static const ambiguous = 'ambiguous';
}

/// D4: what this host serves (the CLI checks before sending).
const List<String> kCliCaps = [
  CliType.cliNotify,
  CliType.cliEventsSubscribe,
  CliType.uiLs,
  CliType.uiTabNew,
  CliType.uiTabRename,
  CliType.uiPaneSplit,
  CliType.uiFocus,
  CliType.uiClose,
  CliType.uiPaneSend,
  CliType.uiPaneRead,
  CliType.uiPaneWait,
  CliType.uiWorkspaceNew,
  CliType.uiWorkspaceRename,
  CliType.uiWorkspaceMove,
  'ui.browser',
];

MuxMessage cliResult(int? q, [Map<String, Object?> fields = const {}]) =>
    MuxMessage(MuxType.result, q: q, fields: fields);

MuxMessage cliErrorMessage(int? q, String code, [String? message]) =>
    MuxMessage(
      MuxType.error,
      q: q,
      fields: {'code': code, 'message': ?message},
    );
```

Export it from `packages/shellx_agent/lib/shellx_agent.dart`: `export 'src/mux/cli_wire.dart';`.

Generate the vectors once, then review them:

```bash
cd packages/shellx_agent && touch ../../term/protocol/mux_vectors.txt && WRITE_VECTORS=1 ~/fvm/versions/3.41.4/bin/dart test test/mux/cli_wire_test.dart; cat ../../term/protocol/mux_vectors.txt
```

Check by hand that `cli.api_version` is `a2617467617069…` (a 2-key map, `t` then `q`) and `host.event` contains `f6` (CBOR null) and `22` (−3). From now on the file is frozen; any later change is a breaking wire change.

- [ ] **Step 5: Run tests to verify they pass**

Run: `cd packages/shellx_agent && ~/fvm/versions/3.41.4/bin/dart test`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
cd packages/shellx_agent && ~/fvm/versions/3.41.4/bin/dart format --set-exit-if-changed lib test && ~/fvm/versions/3.41.4/bin/dart analyze && cd ../..
git add packages/shellx_agent/lib/src/mux/cli_wire.dart packages/shellx_agent/lib/shellx_agent.dart packages/shellx_agent/test/mux/cli_wire_test.dart term/protocol/mux_vectors.txt
git commit -m "feat(agent): CLI wire constants, cli role allowlist and Rust/Dart golden vectors (A7 D3-D5, D37b)"
```

---

### Task 3: Rust — CBOR values, JSON, frames, endpoint, authenticated client (D6, D30, D31, D37b)

**Files:**
- Create: `term/src/api/mod.rs`, `term/src/api/value.rs`, `term/src/api/wire.rs`, `term/src/api/endpoint.rs`, `term/src/api/client.rs`
- Modify: `term/src/lib.rs` (`pub mod api;`)
- Test: unit tests inside each file; `term/tests/api_client.rs` (fake host over a real Unix socket)

**Interfaces:**
- Consumes: `shellx_term::proto::frame::{read_frame, write_frame, MAX_FRAME}`; `hmac`, `sha2`, `getrandom`.
- Produces:
  - `api::value`: `enum Value { Null, Bool(bool), Int(i64), Bytes(Vec<u8>), Text(String), Array(Vec<Value>), Map(Vec<(String, Value)>) }`; `pub const MAX_DEPTH: usize = 8`; `pub fn encode(&Value) -> Vec<u8>`; `pub fn decode(&[u8]) -> Result<Value, DecodeError>`; `impl Value { fn get(&self, key: &str) -> Option<&Value>; fn as_i64(&self) -> Option<i64>; fn as_str(&self) -> Option<&str>; fn as_bool(&self) -> Option<bool>; fn as_array(&self) -> Option<&[Value]>; fn as_bytes(&self) -> Option<&[u8]>; fn text(s: impl Into<String>) -> Value; fn map(entries: Vec<(&str, Value)>) -> Value }`; `pub fn to_json(&Value) -> String`; `pub fn json_string(&str) -> String`.
  - `api::wire`: `struct Message { pub t: String, pub q: Option<i64>, pub fields: Vec<(String, Value)> }` with `fn new(t, fields)`, `fn get(&self, k) -> Option<&Value>`, `fn encode(&self) -> Vec<u8>` (CBOR, no prefix), `fn decode(&[u8]) -> Result<Message, DecodeError>`, `fn to_value(&self) -> Value`; `fn send(w: &mut impl Write, m: &Message) -> io::Result<()>`; `fn recv(r: &mut impl Read) -> io::Result<Message>`.
  - `api::endpoint`: `struct MuxEndpoint { pub address: String, pub secret: [u8; 32], pub protocol: i64, pub app: String }` (Debug redacts the secret); `fn parse(&str) -> Option<MuxEndpoint>`; `fn default_path(get: impl Fn(&str) -> Option<String>) -> Option<PathBuf>`.
  - `api::client`: `enum ApiError { NotRunning(String), Incompatible(String), Remote { code: String, message: String }, Usage(String), Io(String) }` with `fn exit_code(&self) -> i32`; `trait Session { fn request(&mut self, t: &str, fields: Vec<(&str, Value)>) -> Result<Message, ApiError>; fn next_event(&mut self) -> Result<Message, ApiError>; }`; `struct Conn` implementing `Session`; `fn connect(endpoint: &MuxEndpoint, address: &str, timeout: Duration) -> Result<Conn, ApiError>`; `pub const CLI_APP: &str` = `concat!("shellx-cli/", env!("CARGO_PKG_VERSION"))`; `pub fn daemon_proof(secret, nc, nd) -> [u8; 32]`, `pub fn client_proof(secret, nd, nc) -> [u8; 32]`.

- [ ] **Step 1: Write the failing tests**

Create `term/src/api/value.rs` with only the test module first (the implementation goes in Step 3, above it):

```rust
#[cfg(test)]
mod tests {
    use super::*;

    fn hex(b: &[u8]) -> String {
        b.iter().map(|x| format!("{x:02x}")).collect()
    }

    #[test]
    fn round_trips_every_type() {
        let v = Value::map(vec![
            ("n", Value::Null),
            ("b", Value::Bool(true)),
            ("i", Value::Int(-3)),
            ("big", Value::Int(1 << 40)),
            ("min", Value::Int(i64::MIN)),
            ("y", Value::Bytes(vec![0, 255])),
            ("s", Value::text("tiếng Việt")),
            ("a", Value::Array(vec![Value::Int(1), Value::text("x")])),
            ("m", Value::map(vec![("k", Value::Bool(false))])),
        ]);
        assert_eq!(decode(&encode(&v)).unwrap(), v);
    }

    #[test]
    fn shortest_forms() {
        assert_eq!(hex(&encode(&Value::Int(-1))), "20");
        assert_eq!(hex(&encode(&Value::Int(-25))), "3818");
        assert_eq!(hex(&encode(&Value::Int(24))), "1818");
        assert_eq!(hex(&encode(&Value::Null)), "f6");
    }

    #[test]
    fn nesting_beyond_eight_is_refused() {
        let mut v = Value::Int(0);
        for _ in 0..8 {
            v = Value::Array(vec![v]);
        }
        assert!(decode(&encode(&v)).is_ok());
        let deeper = Value::Array(vec![v]);
        assert!(decode(&encode(&deeper)).is_err());
    }

    #[test]
    fn refuses_floats_tags_indefinite_trailing_and_non_text_keys() {
        for bad in ["f93c00", "c100", "9fff", "0000", "a10101", "5f"] {
            let bytes: Vec<u8> = (0..bad.len())
                .step_by(2)
                .map(|i| u8::from_str_radix(&bad[i..i + 2], 16).unwrap())
                .collect();
            assert!(decode(&bytes).is_err(), "{bad}");
        }
    }

    #[test]
    fn json_escapes_and_bytes_as_base64() {
        let v = Value::map(vec![
            ("s", Value::text("a\"b\\c\n\u{1}é")),
            ("y", Value::Bytes(vec![0xfb, 0xff])),
            ("n", Value::Null),
            ("a", Value::Array(vec![Value::Int(-2), Value::Bool(false)])),
        ]);
        assert_eq!(
            to_json(&v),
            r#"{"s":"a\"b\\c\n\u0001é","y":"+/8=","n":null,"a":[-2,false]}"#
        );
    }
}
```

Create `term/src/api/endpoint.rs` tests:

```rust
#[cfg(test)]
mod tests {
    use super::*;

    const TEXT: &str = "v=1\naddress=/tmp/x.sock\nsecret=abababababababababababababababababababababababababababababababab\npid=42\ninstance=ffffffffffffffffffffffffffffffff\nprotocol=1\napp=1.7.0\n";

    #[test]
    fn parses_the_a5b_file() {
        let e = parse(TEXT).unwrap();
        assert_eq!(e.address, "/tmp/x.sock");
        assert_eq!(e.secret, [0xab; 32]);
        assert_eq!(e.protocol, 1);
        assert_eq!(e.app, "1.7.0");
        assert!(!format!("{e:?}").contains("abab"));
    }

    #[test]
    fn refuses_other_versions_and_missing_keys() {
        assert!(parse(&TEXT.replace("v=1", "v=2")).is_none());
        assert!(parse(&TEXT.replace("secret=ab", "secret=zz")).is_none());
        assert!(parse("v=1\naddress=/x\n").is_none());
        assert!(parse("").is_none());
    }

    #[cfg(unix)]
    #[test]
    fn default_path_follows_home() {
        let p = default_path(|k| (k == "HOME").then(|| "/Users/me".to_string())).unwrap();
        assert_eq!(
            p,
            std::path::PathBuf::from("/Users/me/Library/Application Support/pro.shellx.desktop/mux/endpoint")
        );
        let o = default_path(|k| match k {
            "SHELLX_ENDPOINT" => Some("/tmp/ep".into()),
            _ => None,
        })
        .unwrap();
        assert_eq!(o, std::path::PathBuf::from("/tmp/ep"));
    }
}
```

Create `term/src/api/client.rs` tests (vectors):

```rust
#[cfg(test)]
mod tests {
    use super::*;

    fn vector(name: &str) -> Vec<u8> {
        let text = include_str!("../../protocol/mux_vectors.txt");
        let hex = text
            .lines()
            .find_map(|l| l.strip_prefix(&format!("{name}=")))
            .unwrap_or_else(|| panic!("no vector {name}"));
        (0..hex.len())
            .step_by(2)
            .map(|i| u8::from_str_radix(&hex[i..i + 2], 16).unwrap())
            .collect()
    }

    fn arr(name: &str) -> [u8; 32] {
        vector(name).try_into().unwrap()
    }

    #[test]
    fn proofs_match_dart() {
        let (s, nc, nd) = (arr("auth.secret"), arr("auth.nonce_client"), arr("auth.nonce_daemon"));
        assert_eq!(daemon_proof(&s, &nc, &nd).to_vec(), vector("auth.daemon_proof"));
        assert_eq!(client_proof(&s, &nd, &nc).to_vec(), vector("auth.client_proof"));
    }

    #[test]
    fn dart_frames_decode() {
        let m = Message::decode(&vector("host.api_version")).unwrap();
        assert_eq!(m.t, "result");
        assert_eq!(m.q, Some(1));
        assert_eq!(m.get("host").and_then(Value::as_str), Some("ui"));
        let e = Message::decode(&vector("host.event")).unwrap();
        assert_eq!(e.get("tab").and_then(Value::as_i64), Some(-3));
        assert_eq!(e.get("exitCode"), Some(&Value::Null));
        // Our api.version request decodes to the same message Dart wrote.
        let ours = Message { t: "api.version".into(), q: Some(1), fields: vec![] };
        assert_eq!(Message::decode(&ours.encode()).unwrap(), Message::decode(&vector("cli.api_version")).unwrap());
    }

    #[test]
    fn exit_codes_follow_d10() {
        let r = |c: &str| ApiError::Remote { code: c.into(), message: String::new() }.exit_code();
        assert_eq!(r("eval_error"), 1);
        assert_eq!(r("not_found"), 4);
        assert_eq!(r("ambiguous"), 4);
        assert_eq!(r("timeout"), 5);
        assert_eq!(r("cli_disabled"), 6);
        assert_eq!(r("forbidden_origin"), 6);
        assert_eq!(r("running_command"), 6);
        assert_eq!(r("unknown_type"), 7);
        assert_eq!(r("no_ui"), 8);
        assert_eq!(r("bad_request"), 2);
        assert_eq!(ApiError::NotRunning("x".into()).exit_code(), 3);
        assert_eq!(ApiError::Incompatible("x".into()).exit_code(), 7);
        assert_eq!(ApiError::Usage("x".into()).exit_code(), 2);
    }
}
```

Create `term/tests/api_client.rs` (Unix only) — a fake host thread that plays the Dart side:

```rust
#![cfg(unix)]
use shellx_term::api::client::{client_proof, connect, daemon_proof, ApiError, Session};
use shellx_term::api::endpoint::MuxEndpoint;
use shellx_term::api::value::Value;
use shellx_term::api::wire::{recv, send, Message};
use std::os::unix::net::UnixListener;
use std::time::Duration;

const SECRET: [u8; 32] = [7; 32];

fn host(path: &std::path::Path, honest: bool, script: fn(&mut std::os::unix::net::UnixStream)) -> std::thread::JoinHandle<()> {
    let listener = UnixListener::bind(path).unwrap();
    std::thread::spawn(move || {
        let (mut s, _) = listener.accept().unwrap();
        let hello = recv(&mut s).unwrap();
        assert_eq!(hello.get("role").and_then(Value::as_str), Some("cli"));
        let nc: [u8; 32] = hello.get("nonce").and_then(Value::as_bytes).unwrap().try_into().unwrap();
        let nd = [9u8; 32];
        let proof = if honest { daemon_proof(&SECRET, &nc, &nd) } else { [0; 32] };
        send(&mut s, &Message::new("hello", vec![
            ("protocol", Value::Int(1)), ("app", Value::text("1.7.0")),
            ("nonce", Value::Bytes(nd.to_vec())), ("proof", Value::Bytes(proof.to_vec())),
        ])).unwrap();
        if !honest {
            // The client must close without sending auth.
            assert!(recv(&mut s).is_err());
            return;
        }
        let auth = recv(&mut s).unwrap();
        assert_eq!(auth.get("proof").and_then(Value::as_bytes).unwrap(), &client_proof(&SECRET, &nd, &nc));
        send(&mut s, &Message::new("ready", vec![])).unwrap();
        script(&mut s);
    })
}

fn endpoint(path: &std::path::Path) -> MuxEndpoint {
    MuxEndpoint { address: path.display().to_string(), secret: SECRET, protocol: 1, app: "1.7.0".into() }
}

fn temp_sock(name: &str) -> std::path::PathBuf {
    let p = std::env::temp_dir().join(format!("shellx-cli-{}-{name}.sock", std::process::id()));
    let _ = std::fs::remove_file(&p);
    p
}

#[test]
fn request_matches_q_and_skips_events() {
    let p = temp_sock("ok");
    let h = host(&p, true, |s| {
        let req = recv(s).unwrap();
        assert_eq!(req.t, "ui.ls");
        let q = req.q.unwrap();
        send(s, &Message::new("event", vec![("kind", Value::text("tab.opened"))])).unwrap();
        let mut res = Message::new("result", vec![("workspaces", Value::Array(vec![]))]);
        res.q = Some(q);
        send(s, &res).unwrap();
    });
    let mut c = connect(&endpoint(&p), &p.display().to_string(), Duration::from_secs(2)).unwrap();
    let res = c.request("ui.ls", vec![]).unwrap();
    assert!(res.get("workspaces").is_some());
    h.join().unwrap();
}

#[test]
fn remote_errors_become_api_errors() {
    let p = temp_sock("err");
    let h = host(&p, true, |s| {
        let req = recv(s).unwrap();
        let mut e = Message::new("error", vec![("code", Value::text("not_found")), ("message", Value::text("no pane p1"))]);
        e.q = req.q;
        send(s, &e).unwrap();
    });
    let mut c = connect(&endpoint(&p), &p.display().to_string(), Duration::from_secs(2)).unwrap();
    match c.request("ui.pane.read", vec![("pane", Value::Int(1))]) {
        Err(ApiError::Remote { code, message }) => {
            assert_eq!(code, "not_found");
            assert_eq!(message, "no pane p1");
        }
        other => panic!("{other:?}"),
    }
    h.join().unwrap();
}

#[test]
fn a_host_without_the_secret_never_gets_auth() {
    let p = temp_sock("squat");
    let h = host(&p, false, |_| {});
    let r = connect(&endpoint(&p), &p.display().to_string(), Duration::from_secs(2));
    assert!(matches!(r, Err(ApiError::NotRunning(_))), "{r:?}");
    h.join().unwrap();
}

#[test]
fn nothing_listening_is_not_running() {
    let p = temp_sock("none");
    let r = connect(&endpoint(&p), &p.display().to_string(), Duration::from_millis(300));
    assert!(matches!(r, Err(ApiError::NotRunning(_))));
}

#[test]
fn silence_times_out_as_not_running() {
    let p = temp_sock("silent");
    let listener = UnixListener::bind(&p).unwrap();
    let h = std::thread::spawn(move || {
        let (_s, _) = listener.accept().unwrap();
        std::thread::sleep(Duration::from_millis(800));
    });
    let t = std::time::Instant::now();
    let r = connect(&endpoint(&p), &p.display().to_string(), Duration::from_millis(300));
    assert!(matches!(r, Err(ApiError::NotRunning(_))));
    assert!(t.elapsed() < Duration::from_millis(700));
    h.join().unwrap();
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd term && ~/.cargo/bin/cargo test api`
Expected: FAIL to compile — `api` module missing.

- [ ] **Step 3: Implement**

`term/src/lib.rs`: add `pub mod api;` (keep the other modules).

`term/src/api/mod.rs`:

```rust
//! `shellx` — the ShellX command line (A7 spec:
//! docs/superpowers/specs/2026-10-07-desktop-cli-a7-design.md). Talks to the
//! ShellX window (or the A5b daemon) over the local mux socket. Separate
//! from `proto`, which is the terminal-sharing link and must not change.

pub mod client;
pub mod endpoint;
pub mod value;
pub mod wire;
```

`term/src/api/value.rs` (above the tests):

```rust
//! The CBOR subset `shellx_core.encodeCbor` writes: null, bool, 64-bit
//! integers, byte and text strings, arrays, maps with text keys. Definite
//! lengths only, nesting ≤ 8 (A5b D6). Plus JSON output for `--json`.

#[derive(Debug, Clone, PartialEq)]
pub enum Value {
    Null,
    Bool(bool),
    Int(i64),
    Bytes(Vec<u8>),
    Text(String),
    Array(Vec<Value>),
    Map(Vec<(String, Value)>),
}

pub const MAX_DEPTH: usize = 8;

#[derive(Debug, PartialEq, Eq)]
pub struct DecodeError(pub &'static str);

impl Value {
    pub fn text(s: impl Into<String>) -> Value {
        Value::Text(s.into())
    }
    pub fn map(entries: Vec<(&str, Value)>) -> Value {
        Value::Map(entries.into_iter().map(|(k, v)| (k.to_string(), v)).collect())
    }
    pub fn get(&self, key: &str) -> Option<&Value> {
        match self {
            Value::Map(m) => m.iter().find(|(k, _)| k == key).map(|(_, v)| v),
            _ => None,
        }
    }
    pub fn as_i64(&self) -> Option<i64> {
        if let Value::Int(n) = self { Some(*n) } else { None }
    }
    pub fn as_str(&self) -> Option<&str> {
        if let Value::Text(s) = self { Some(s) } else { None }
    }
    pub fn as_bool(&self) -> Option<bool> {
        if let Value::Bool(b) = self { Some(*b) } else { None }
    }
    pub fn as_array(&self) -> Option<&[Value]> {
        if let Value::Array(a) = self { Some(a) } else { None }
    }
    pub fn as_bytes(&self) -> Option<&[u8]> {
        if let Value::Bytes(b) = self { Some(b) } else { None }
    }
}

fn head(out: &mut Vec<u8>, major: u8, n: u64) {
    let m = major << 5;
    if n < 24 {
        out.push(m | n as u8);
    } else if n <= 0xff {
        out.extend_from_slice(&[m | 24, n as u8]);
    } else if n <= 0xffff {
        out.push(m | 25);
        out.extend_from_slice(&(n as u16).to_be_bytes());
    } else if n <= 0xffff_ffff {
        out.push(m | 26);
        out.extend_from_slice(&(n as u32).to_be_bytes());
    } else {
        out.push(m | 27);
        out.extend_from_slice(&n.to_be_bytes());
    }
}

pub fn encode(v: &Value) -> Vec<u8> {
    let mut out = Vec::new();
    put(&mut out, v);
    out
}

fn put(out: &mut Vec<u8>, v: &Value) {
    match v {
        Value::Null => out.push(0xf6),
        Value::Bool(b) => out.push(if *b { 0xf5 } else { 0xf4 }),
        Value::Int(n) if *n >= 0 => head(out, 0, *n as u64),
        // -1 - n, computed without overflow for i64::MIN.
        Value::Int(n) => head(out, 1, !(*n as u64)),
        Value::Bytes(b) => {
            head(out, 2, b.len() as u64);
            out.extend_from_slice(b);
        }
        Value::Text(s) => {
            head(out, 3, s.len() as u64);
            out.extend_from_slice(s.as_bytes());
        }
        Value::Array(a) => {
            head(out, 4, a.len() as u64);
            a.iter().for_each(|x| put(out, x));
        }
        Value::Map(m) => {
            head(out, 5, m.len() as u64);
            for (k, x) in m {
                head(out, 3, k.len() as u64);
                out.extend_from_slice(k.as_bytes());
                put(out, x);
            }
        }
    }
}

pub fn decode(bytes: &[u8]) -> Result<Value, DecodeError> {
    let mut r = Reader { b: bytes, pos: 0 };
    let v = r.value(0)?;
    if r.pos != bytes.len() {
        return Err(DecodeError("trailing bytes"));
    }
    Ok(v)
}

struct Reader<'a> {
    b: &'a [u8],
    pos: usize,
}

impl<'a> Reader<'a> {
    fn byte(&mut self) -> Result<u8, DecodeError> {
        let x = *self.b.get(self.pos).ok_or(DecodeError("truncated"))?;
        self.pos += 1;
        Ok(x)
    }
    fn take(&mut self, n: u64) -> Result<&'a [u8], DecodeError> {
        let n = usize::try_from(n).map_err(|_| DecodeError("too long"))?;
        let end = self.pos.checked_add(n).filter(|e| *e <= self.b.len()).ok_or(DecodeError("truncated"))?;
        let s = &self.b[self.pos..end];
        self.pos = end;
        Ok(s)
    }
    fn head(&mut self) -> Result<(u8, u64), DecodeError> {
        let x = self.byte()?;
        let n = match x & 0x1f {
            i @ 0..=23 => u64::from(i),
            24 => u64::from(self.byte()?),
            25 => u64::from(u16::from_be_bytes(self.take(2)?.try_into().unwrap())),
            26 => u64::from(u32::from_be_bytes(self.take(4)?.try_into().unwrap())),
            27 => u64::from_be_bytes(self.take(8)?.try_into().unwrap()),
            _ => return Err(DecodeError("indefinite or reserved length")),
        };
        Ok((x >> 5, n))
    }
    fn text(&mut self, n: u64) -> Result<String, DecodeError> {
        String::from_utf8(self.take(n)?.to_vec()).map_err(|_| DecodeError("text is not UTF-8"))
    }
    /// `depth` = containers already open around this value.
    fn value(&mut self, depth: usize) -> Result<Value, DecodeError> {
        match self.b.get(self.pos) {
            Some(0xf4) => { self.pos += 1; return Ok(Value::Bool(false)); }
            Some(0xf5) => { self.pos += 1; return Ok(Value::Bool(true)); }
            Some(0xf6) => { self.pos += 1; return Ok(Value::Null); }
            _ => {}
        }
        let (major, n) = self.head()?;
        match major {
            0 => i64::try_from(n).map(Value::Int).map_err(|_| DecodeError("integer too large")),
            1 => i64::try_from(n).map(|n| Value::Int(-1 - n)).map_err(|_| DecodeError("integer too small")),
            2 => Ok(Value::Bytes(self.take(n)?.to_vec())),
            3 => self.text(n).map(Value::Text),
            4 | 5 if depth >= MAX_DEPTH => Err(DecodeError("nested too deeply")),
            4 => {
                let mut a = Vec::new();
                for _ in 0..n {
                    a.push(self.value(depth + 1)?);
                }
                Ok(Value::Array(a))
            }
            5 => {
                let mut m: Vec<(String, Value)> = Vec::new();
                for _ in 0..n {
                    let (km, kn) = self.head()?;
                    if km != 3 {
                        return Err(DecodeError("map key is not text"));
                    }
                    let k = self.text(kn)?;
                    let v = self.value(depth + 1)?;
                    m.push((k, v));
                }
                Ok(Value::Map(m))
            }
            _ => Err(DecodeError("unsupported item")),
        }
    }
}

pub fn json_string(s: &str) -> String {
    let mut out = String::with_capacity(s.len() + 2);
    out.push('"');
    for c in s.chars() {
        match c {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            c if (c as u32) < 0x20 => out.push_str(&format!("\\u{:04x}", c as u32)),
            c => out.push(c),
        }
    }
    out.push('"');
    out
}

fn base64(b: &[u8]) -> String {
    const T: &[u8; 64] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    let mut out = String::new();
    for chunk in b.chunks(3) {
        let n = (u32::from(chunk[0]) << 16)
            | (u32::from(*chunk.get(1).unwrap_or(&0)) << 8)
            | u32::from(*chunk.get(2).unwrap_or(&0));
        for i in 0..4 {
            if i <= chunk.len() {
                out.push(T[((n >> (18 - 6 * i)) & 63) as usize] as char);
            } else {
                out.push('=');
            }
        }
    }
    out
}

pub fn to_json(v: &Value) -> String {
    match v {
        Value::Null => "null".into(),
        Value::Bool(b) => b.to_string(),
        Value::Int(n) => n.to_string(),
        Value::Bytes(b) => json_string(&base64(b)),
        Value::Text(s) => json_string(s),
        Value::Array(a) => format!("[{}]", a.iter().map(to_json).collect::<Vec<_>>().join(",")),
        Value::Map(m) => format!(
            "{{{}}}",
            m.iter().map(|(k, x)| format!("{}:{}", json_string(k), to_json(x))).collect::<Vec<_>>().join(",")
        ),
    }
}
```

`term/src/api/wire.rs`:

```rust
//! A5b messages: `{"t": type, "q": id?, …}` in one CBOR map per frame.

use super::value::{decode, encode, DecodeError, Value};
use crate::proto::frame::{read_frame, write_frame};
use std::io::{self, Read, Write};

#[derive(Debug, Clone, PartialEq)]
pub struct Message {
    pub t: String,
    pub q: Option<i64>,
    pub fields: Vec<(String, Value)>,
}

impl Message {
    pub fn new(t: &str, fields: Vec<(&str, Value)>) -> Message {
        Message { t: t.into(), q: None, fields: fields.into_iter().map(|(k, v)| (k.into(), v)).collect() }
    }
    pub fn get(&self, key: &str) -> Option<&Value> {
        self.fields.iter().find(|(k, _)| k == key).map(|(_, v)| v)
    }
    pub fn to_value(&self) -> Value {
        let mut m = vec![("t".to_string(), Value::Text(self.t.clone()))];
        if let Some(q) = self.q {
            m.push(("q".into(), Value::Int(q)));
        }
        m.extend(self.fields.iter().cloned());
        Value::Map(m)
    }
    pub fn encode(&self) -> Vec<u8> {
        encode(&self.to_value())
    }
    pub fn decode(bytes: &[u8]) -> Result<Message, DecodeError> {
        let Value::Map(entries) = decode(bytes)? else {
            return Err(DecodeError("not a map"));
        };
        let mut t = None;
        let mut q = None;
        let mut fields = Vec::new();
        for (k, v) in entries {
            match (k.as_str(), v) {
                ("t", Value::Text(s)) => t = Some(s),
                ("t", _) => return Err(DecodeError("t is not text")),
                ("q", Value::Int(n)) => q = Some(n),
                ("q", Value::Null) => {}
                ("q", _) => return Err(DecodeError("q is not an integer")),
                (_, v) => fields.push((k, v)),
            }
        }
        Ok(Message { t: t.ok_or(DecodeError("no t"))?, q, fields })
    }
}

pub fn send(w: &mut impl Write, m: &Message) -> io::Result<()> {
    write_frame(w, &m.encode())?;
    w.flush()
}

pub fn recv(r: &mut impl Read) -> io::Result<Message> {
    let payload = read_frame(r)?;
    Message::decode(&payload).map_err(|e| io::Error::new(io::ErrorKind::InvalidData, e.0))
}
```

`term/src/api/endpoint.rs` (above tests):

```rust
//! Where the host listens: A5b D5 `mux/endpoint` (7 lines, 0600).

use std::path::PathBuf;

#[derive(Clone, PartialEq, Eq)]
pub struct MuxEndpoint {
    pub address: String,
    pub secret: [u8; 32],
    pub protocol: i64,
    pub app: String,
}

impl std::fmt::Debug for MuxEndpoint {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("MuxEndpoint")
            .field("address", &self.address)
            .field("secret", &"<redacted>")
            .field("protocol", &self.protocol)
            .field("app", &self.app)
            .finish()
    }
}

pub fn parse(text: &str) -> Option<MuxEndpoint> {
    let mut lines = text.lines();
    if lines.next()? != "v=1" {
        return None;
    }
    let mut kv = std::collections::HashMap::new();
    for l in lines {
        let (k, v) = l.split_once('=')?;
        kv.insert(k, v);
    }
    let hex = kv.get("secret")?;
    if hex.len() != 64 || !hex.bytes().all(|b| b.is_ascii_hexdigit()) {
        return None;
    }
    let mut secret = [0u8; 32];
    for (i, s) in secret.iter_mut().enumerate() {
        *s = u8::from_str_radix(&hex[2 * i..2 * i + 2], 16).ok()?;
    }
    Some(MuxEndpoint {
        address: kv.get("address").filter(|a| !a.is_empty())?.to_string(),
        secret,
        protocol: kv.get("protocol")?.parse().ok()?,
        app: kv.get("app").unwrap_or(&"").to_string(),
    })
}

/// D30: `$SHELLX_ENDPOINT` (tests), else the A5b location for this user.
#[allow(clippy::let_and_return)] // one binding per platform
pub fn default_path(get: impl Fn(&str) -> Option<String>) -> Option<PathBuf> {
    if let Some(p) = get("SHELLX_ENDPOINT").filter(|p| !p.is_empty()) {
        return Some(PathBuf::from(p));
    }
    #[cfg(unix)]
    let path = get("HOME")
        .filter(|h| !h.is_empty())
        .map(|h| PathBuf::from(h).join("Library/Application Support/pro.shellx.desktop/mux/endpoint"));
    #[cfg(windows)]
    let path = get("LOCALAPPDATA")
        .filter(|h| !h.is_empty())
        .map(|h| PathBuf::from(h).join("ShellX").join("mux").join("endpoint"));
    path
}
```

`term/src/api/client.rs` (above tests):

```rust
//! The authenticated, synchronous client (A7 D30, D31): one request at a
//! time, never reading and writing at once (Windows serializes I/O on a
//! synchronous pipe handle).

use super::endpoint::MuxEndpoint;
use super::value::Value;
use super::wire::{recv, send, Message};
use hmac::{Hmac, KeyInit, Mac};
use sha2::Sha256;
use std::time::Duration;
#[cfg(windows)]
use std::time::Instant;

pub const CLI_APP: &str = concat!("shellx-cli/", env!("CARGO_PKG_VERSION"));
pub const MUX_PROTOCOL: i64 = 1;

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ApiError {
    NotRunning(String),
    Incompatible(String),
    Remote { code: String, message: String },
    Usage(String),
    Io(String),
}

impl ApiError {
    /// Spec D10.
    pub fn exit_code(&self) -> i32 {
        match self {
            ApiError::NotRunning(_) => 3,
            ApiError::Incompatible(_) => 7,
            ApiError::Usage(_) => 2,
            ApiError::Io(_) => 1,
            ApiError::Remote { code, .. } => match code.as_str() {
                "bad_request" => 2,
                "not_found" | "ambiguous" => 4,
                "timeout" => 5,
                "cli_disabled" | "forbidden" | "forbidden_origin" | "running_command" => 6,
                "unknown_type" | "unsupported_role" => 7,
                "no_ui" => 8,
                _ => 1,
            },
        }
    }
}

type HmacSha256 = Hmac<Sha256>;

fn proof(secret: &[u8; 32], label: &[u8], a: &[u8; 32], b: &[u8; 32]) -> [u8; 32] {
    let mut m = <HmacSha256 as KeyInit>::new_from_slice(secret).expect("any key length");
    m.update(label);
    m.update(a);
    m.update(b);
    m.finalize().into_bytes().into()
}

/// HMAC(secret, "shellx-mux/daemon" ‖ nonceClient ‖ nonceDaemon).
pub fn daemon_proof(secret: &[u8; 32], nc: &[u8; 32], nd: &[u8; 32]) -> [u8; 32] {
    proof(secret, b"shellx-mux/daemon", nc, nd)
}

/// HMAC(secret, "shellx-mux/client" ‖ nonceDaemon ‖ nonceClient).
pub fn client_proof(secret: &[u8; 32], nd: &[u8; 32], nc: &[u8; 32]) -> [u8; 32] {
    proof(secret, b"shellx-mux/client", nd, nc)
}

pub trait Session {
    fn request(&mut self, t: &str, fields: Vec<(&str, Value)>) -> Result<Message, ApiError>;
    fn next_event(&mut self) -> Result<Message, ApiError>;
}

#[cfg(unix)]
type RawStream = std::os::unix::net::UnixStream;
#[cfg(windows)]
type RawStream = std::fs::File;

pub struct Conn {
    stream: RawStream,
    next_q: i64,
}

fn not_running(why: &str) -> ApiError {
    ApiError::NotRunning(format!("ShellX is not running (open ShellX and try again) [{why}]"))
}

#[cfg(unix)]
fn open(address: &str, timeout: Duration) -> Result<RawStream, ApiError> {
    let s = RawStream::connect(address).map_err(|_| not_running("connect"))?;
    s.set_read_timeout(Some(timeout)).ok();
    s.set_write_timeout(Some(timeout)).ok();
    Ok(s)
}

#[cfg(windows)]
fn open(address: &str, timeout: Duration) -> Result<RawStream, ApiError> {
    // D31: ERROR_PIPE_BUSY (231) → retry every 50 ms up to `timeout`.
    let deadline = Instant::now() + timeout;
    loop {
        match std::fs::OpenOptions::new().read(true).write(true).open(address) {
            Ok(f) => return Ok(f),
            Err(e) if e.raw_os_error() == Some(231) && Instant::now() < deadline => {
                std::thread::sleep(Duration::from_millis(50))
            }
            Err(_) => return Err(not_running("connect")),
        }
    }
}

pub fn connect(endpoint: &MuxEndpoint, address: &str, timeout: Duration) -> Result<Conn, ApiError> {
    let mut stream = open(address, timeout)?;
    let mut nc = [0u8; 32];
    getrandom::fill(&mut nc).map_err(|_| ApiError::Io("no randomness".into()))?;
    let hello = Message::new("hello", vec![
        ("protocol", Value::Int(MUX_PROTOCOL)),
        ("app", Value::text(CLI_APP)),
        ("role", Value::text("cli")),
        ("nonce", Value::Bytes(nc.to_vec())),
    ]);
    send(&mut stream, &hello).map_err(|_| not_running("hello"))?;
    // A read timeout (Unix) surfaces here as an error → not running.
    let theirs = recv(&mut stream).map_err(|_| not_running("handshake"))?;
    let nd: [u8; 32] = theirs
        .get("nonce")
        .and_then(Value::as_bytes)
        .and_then(|b| b.try_into().ok())
        .ok_or_else(|| not_running("handshake"))?;
    let expected = daemon_proof(&endpoint.secret, &nc, &nd);
    let got = theirs.get("proof").and_then(Value::as_bytes).unwrap_or(&[]);
    // Constant time. The host proves first; a squatter gets nothing (A5b D6).
    if got.len() != 32 || got.iter().zip(expected.iter()).fold(0u8, |d, (a, b)| d | (a ^ b)) != 0 {
        return Err(not_running("proof"));
    }
    if theirs.get("protocol").and_then(Value::as_i64) != Some(MUX_PROTOCOL) {
        return Err(ApiError::Incompatible(
            "this ShellX speaks another protocol: update shellx or ShellX".into(),
        ));
    }
    let auth = Message::new("auth", vec![(
        "proof",
        Value::Bytes(client_proof(&endpoint.secret, &nd, &nc).to_vec()),
    )]);
    send(&mut stream, &auth).map_err(|_| not_running("auth"))?;
    let ready = recv(&mut stream).map_err(|_| not_running("ready"))?;
    if ready.t != "ready" {
        return Err(not_running("ready"));
    }
    // A refusal after `ready` (busy, unsupported_role) is an error with no q:
    // `request` returns it (D10: busy → 1, unsupported_role → 7).
    #[cfg(unix)]
    {
        // `wait` and `events` may block for a long time.
        stream.set_read_timeout(None).ok();
        stream.set_write_timeout(None).ok();
    }
    Ok(Conn { stream, next_q: 1 })
}

impl Session for Conn {
    fn request(&mut self, t: &str, fields: Vec<(&str, Value)>) -> Result<Message, ApiError> {
        let q = self.next_q;
        self.next_q += 1;
        let mut m = Message::new(t, fields);
        m.q = Some(q);
        send(&mut self.stream, &m).map_err(|e| ApiError::Io(e.to_string()))?;
        loop {
            let r = recv(&mut self.stream).map_err(|_| ApiError::NotRunning("ShellX closed the connection".into()))?;
            if r.q != Some(q) {
                // A host-level refusal (`busy`, `unsupported_role`) has no q.
                if r.t == "error" && r.q.is_none() {
                    return Err(ApiError::Remote {
                        code: r.get("code").and_then(Value::as_str).unwrap_or("internal").into(),
                        message: "ShellX refused the connection".into(),
                    });
                }
                continue; // events and stale answers
            }
            return match r.t.as_str() {
                "result" => Ok(r),
                "error" => Err(ApiError::Remote {
                    code: r.get("code").and_then(Value::as_str).unwrap_or("internal").into(),
                    message: r.get("message").and_then(Value::as_str).unwrap_or("").into(),
                }),
                _ => continue,
            };
        }
    }

    fn next_event(&mut self) -> Result<Message, ApiError> {
        loop {
            let r = recv(&mut self.stream).map_err(|_| ApiError::NotRunning("ShellX closed the connection".into()))?;
            if r.t == "event" {
                return Ok(r);
            }
        }
    }
}
```



- [ ] **Step 4: Run tests to verify they pass**

Run: `cd term && ~/.cargo/bin/cargo test api && ~/.cargo/bin/cargo test --test api_client && ~/.cargo/bin/cargo test --features test-hooks`
Expected: PASS (new and all existing tests).

- [ ] **Step 5: Lint and commit**

```bash
cd term && ~/.cargo/bin/cargo fmt --check && ~/.cargo/bin/cargo clippy --all-targets -- -D warnings && cd ..
git add term/src/lib.rs term/src/api/mod.rs term/src/api/value.rs term/src/api/wire.rs term/src/api/endpoint.rs term/src/api/client.rs term/tests/api_client.rs
git commit -m "feat(term): shellx API client — full CBOR, A5b frames, endpoint, mutual-HMAC handshake (A7 D6, D30, D31)"
```

---

### Task 4: Rust — command table, parser, help, completions, `shellx` name dispatch (D6, D9, D10, D11, D36)

**Files:**
- Create: `term/src/api/args.rs`
- Modify: `term/src/api/mod.rs` (`pub mod args;`), `term/src/main.rs` (dispatch)
- Test: unit tests in `args.rs`; `term/tests/cli_dispatch.rs`

**Interfaces:**
- Produces:
  - `pub struct Flag { pub name: &'static str, pub value: Option<&'static str>, pub help: &'static str, pub repeat: bool }`
  - `pub struct CommandSpec { pub path: &'static [&'static str], pub positionals: &'static [&'static str], pub flags: &'static [Flag], pub summary: &'static str, pub needs_ui: bool }` — positional names ending `?` are optional; `...` takes the rest.
  - `pub static COMMANDS: &[CommandSpec]`; `pub static GLOBAL_FLAGS: &[Flag]` (`--json`, `--socket PATH`, `--help`).
  - `pub struct Parsed { pub spec: &'static CommandSpec, pub positionals: Vec<String>, pub flags: Vec<(&'static str, Option<String>)>, pub json: bool, pub socket: Option<String> }` with `fn flag(&self, name) -> Option<&str>`, `fn has(&self, name) -> bool`, `fn all(&self, name) -> Vec<&str>`, `fn pos(&self, i) -> Option<&str>`.
  - `pub enum Invocation { Run(Parsed), Help(Option<&'static CommandSpec>), Version, Completions(String) }`
  - `pub fn parse(args: &[String]) -> Result<Invocation, String>` (Err = usage message, exit 2).
  - `pub fn help_text(spec: Option<&CommandSpec>) -> String`; `pub fn completion_script(shell: &str) -> Option<String>`.
  - `pub fn is_cli_name(argv0: &OsStr) -> bool` (`shellx` / `shellx.exe`, case-insensitive on Windows).

- [ ] **Step 1: Write the failing tests**

Tests at the bottom of `term/src/api/args.rs`:

```rust
#[cfg(test)]
mod tests {
    use super::*;

    fn p(args: &[&str]) -> Result<Invocation, String> {
        parse(&args.iter().map(|s| s.to_string()).collect::<Vec<_>>())
    }
    fn run(args: &[&str]) -> Parsed {
        match p(args).unwrap() {
            Invocation::Run(x) => x,
            _ => panic!("not a run: {args:?}"),
        }
    }

    #[test]
    fn every_spec_command_exists() {
        let names: Vec<String> = COMMANDS.iter().map(|c| c.path.join(" ")).collect();
        for want in [
            "ls", "new-tab", "split", "focus", "close", "send", "read", "rename",
            "workspace new", "workspace rename", "workspace move", "notify", "wait", "events",
            "browser ls", "browser open", "browser nav", "browser back", "browser forward",
            "browser reload", "browser stop", "browser close", "browser wait", "browser eval",
            "browser screenshot", "browser console", "browser network", "browser query",
            "browser click", "browser fill", "skills install", "skills print", "completions",
        ] {
            assert!(names.contains(&want.to_string()), "{want}");
        }
    }

    #[test]
    fn flags_and_positionals() {
        let x = run(&["split", "--down", "--cmd=npm run dev", "--json"]);
        assert_eq!(x.spec.path, &["split"]);
        assert!(x.has("down"));
        assert_eq!(x.flag("cmd"), Some("npm run dev"));
        assert!(x.json);
        let s = run(&["send", "p12", "--text", "ls -la", "--enter", "--key", "ctrl-c", "--key", "up"]);
        assert_eq!(s.pos(0), Some("p12"));
        assert_eq!(s.all("key"), vec!["ctrl-c", "up"]);
        let n = run(&["notify", "--title", "CI", "Build", "xong"]);
        assert_eq!(n.positionals, vec!["Build", "xong"]);
        let w = run(&["workspace", "rename", "api", "Back end"]);
        assert_eq!(w.positionals, vec!["api", "Back end"]);
        let d = run(&["send", "p1", "--text", "--", "--enter"]);
        assert_eq!(d.flag("text"), Some("--"));
    }

    #[test]
    fn usage_errors() {
        for bad in [
            &["bogus"][..],
            &["split", "--sideways"],
            &["read"],
            &["send", "p1", "--text"],
            &["workspace"],
            &["focus", "p1", "extra"],
            &["split", "--right", "--right"],
        ] {
            assert!(p(bad).is_err(), "{bad:?}");
        }
    }

    #[test]
    fn help_version_completions() {
        assert!(matches!(p(&[]).unwrap(), Invocation::Help(None)));
        assert!(matches!(p(&["help"]).unwrap(), Invocation::Help(None)));
        assert!(matches!(p(&["--version"]).unwrap(), Invocation::Version));
        match p(&["help", "split"]).unwrap() {
            Invocation::Help(Some(c)) => assert_eq!(c.path, &["split"]),
            _ => panic!(),
        }
        assert!(matches!(p(&["split", "--help"]).unwrap(), Invocation::Help(Some(_))));
        let all = help_text(None);
        for c in COMMANDS {
            assert!(all.contains(&c.path.join(" ")), "{:?}", c.path);
        }
        assert!(all.contains("Exit codes"));
        for sh in ["zsh", "bash", "pwsh"] {
            let s = completion_script(sh).unwrap();
            assert!(s.contains("new-tab") && s.contains("--enter") && s.contains("ls --ids"), "{sh}");
        }
        assert!(completion_script("fish").is_none());
    }

    #[test]
    fn name_dispatch() {
        use std::ffi::OsStr;
        assert!(is_cli_name(OsStr::new("/Users/a/cli/shellx")));
        assert!(is_cli_name(OsStr::new("shellx")));
        assert!(!is_cli_name(OsStr::new("/x/shellx-term")));
        #[cfg(windows)]
        assert!(is_cli_name(OsStr::new(r"C:\x\SHELLX.EXE")));
    }
}
```

`term/tests/cli_dispatch.rs` (runs the real binary):

```rust
#![cfg(unix)]
use std::process::Command;

fn bin() -> std::path::PathBuf {
    std::path::PathBuf::from(env!("CARGO_BIN_EXE_shellx-term"))
}

fn shellx_link() -> std::path::PathBuf {
    let dir = std::env::temp_dir().join(format!("shellx-dispatch-{}", std::process::id()));
    std::fs::create_dir_all(&dir).unwrap();
    let link = dir.join("shellx");
    let _ = std::fs::remove_file(&link);
    std::os::unix::fs::symlink(bin(), &link).unwrap();
    link
}

#[test]
fn shellx_name_is_the_cli_and_never_starts_a_shell() {
    let out = Command::new(shellx_link()).arg("bogus").output().unwrap();
    assert_eq!(out.status.code(), Some(2));
    assert!(String::from_utf8_lossy(&out.stderr).contains("unknown command"));
    let v = Command::new(shellx_link()).arg("--version").output().unwrap();
    assert!(String::from_utf8_lossy(&v.stdout).starts_with("shellx "));
}

#[test]
fn shellx_term_cli_subcommand_and_old_paths_unchanged() {
    let out = Command::new(bin()).args(["cli", "help"]).output().unwrap();
    assert_eq!(out.status.code(), Some(0));
    assert!(String::from_utf8_lossy(&out.stdout).contains("Usage: shellx"));
    let v = Command::new(bin()).arg("--version").output().unwrap();
    assert!(String::from_utf8_lossy(&v.stdout).starts_with("shellx-term "));
}

#[test]
fn not_running_is_exit_3() {
    let out = Command::new(shellx_link())
        .arg("ls")
        .env("SHELLX_ENDPOINT", "/nonexistent/endpoint")
        .output()
        .unwrap();
    assert_eq!(out.status.code(), Some(3));
    assert!(String::from_utf8_lossy(&out.stderr).contains("ShellX is not running"));
}
```

(`not_running_is_exit_3` needs Task 10's runner; mark it `#[ignore = "enabled in Task 10"]` now and remove the attribute in Task 10.)

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd term && ~/.cargo/bin/cargo test args && ~/.cargo/bin/cargo test --test cli_dispatch`
Expected: FAIL to compile.

- [ ] **Step 3: Implement**

`term/src/api/args.rs` (above tests):

```rust
//! One table (D9) drives parsing, `help` and completions.

use std::ffi::OsStr;

pub struct Flag {
    pub name: &'static str,
    pub value: Option<&'static str>,
    pub help: &'static str,
    pub repeat: bool,
}

pub struct CommandSpec {
    pub path: &'static [&'static str],
    pub positionals: &'static [&'static str],
    pub flags: &'static [Flag],
    pub summary: &'static str,
    pub needs_ui: bool,
}

const fn f(name: &'static str, help: &'static str) -> Flag {
    Flag { name, value: None, help, repeat: false }
}
const fn v(name: &'static str, value: &'static str, help: &'static str) -> Flag {
    Flag { name, value: Some(value), help, repeat: false }
}
const fn r(name: &'static str, value: &'static str, help: &'static str) -> Flag {
    Flag { name, value: Some(value), help, repeat: true }
}
const fn c(
    path: &'static [&'static str],
    positionals: &'static [&'static str],
    flags: &'static [Flag],
    summary: &'static str,
) -> CommandSpec {
    CommandSpec { path, positionals, flags, summary, needs_ui: true }
}

pub static GLOBAL_FLAGS: &[Flag] = &[
    f("json", "print one JSON object (errors too) on stdout"),
    v("socket", "ADDRESS", "host address (default: $SHELLX_SOCKET, then the endpoint file)"),
    f("help", "show help for the command"),
];

const TIMEOUT: Flag = v("timeout", "SECONDS", "give up after SECONDS (default 30, max 3600)");
const FOCUS: Flag = f("focus", "select/focus the new object (default: leave the user's focus alone)");

pub static COMMANDS: &[CommandSpec] = &[
    CommandSpec { needs_ui: false, ..c(&["ls"], &[], &[f("ids", "print only ids, one per line")], "list workspaces, tabs and panes") },
    c(&["new-tab"], &[], &[v("workspace", "W", "workspace id or name"), v("cwd", "DIR", "start directory"), v("cmd", "COMMAND", "type COMMAND once the shell is ready"), FOCUS], "open a tab; prints its id"),
    c(&["split"], &[], &[f("right", "new pane to the right (default)"), f("down", "new pane below"), v("pane", "PANE", "pane to split (default @self, else @focused)"), v("cwd", "DIR", "start directory (default: the pane's)"), v("cmd", "COMMAND", "type COMMAND once the shell is ready"), FOCUS], "split a pane; prints the new pane's id"),
    c(&["focus"], &["TARGET"], &[f("raise", "also bring the ShellX window to the front")], "select a tab or focus a pane (p<id>, t<id>, @self, @tab)"),
    c(&["close"], &["TARGET"], &[f("force", "close even while a command runs")], "close a pane or a whole tab"),
    c(&["send"], &["PANE"], &[v("text", "TEXT", "text to paste"), f("stdin", "paste text read from stdin"), f("enter", "press Enter after the text"), r("key", "KEY", "press KEY (enter, tab, esc, up, ctrl-c, …); repeatable")], "type into a pane as a paste"),
    c(&["read"], &["PANE"], &[v("lines", "N", "last N lines including scrollback (default: the screen)"), f("ansi", "keep colors as SGR escapes")], "print a pane's screen or scrollback"),
    c(&["rename"], &["TAB", "NAME..."], &[], "rename a tab (empty name: automatic title)"),
    c(&["workspace", "new"], &["NAME?"], &[FOCUS], "create a workspace with one tab; prints its id"),
    c(&["workspace", "rename"], &["WORKSPACE", "NAME..."], &[], "rename a workspace"),
    c(&["workspace", "move"], &["TAB", "WORKSPACE"], &[], "move a tab to a workspace"),
    CommandSpec { needs_ui: false, ..c(&["notify"], &["TEXT..."], &[v("title", "TITLE", "notification title"), v("pane", "PANE", "pane the notice belongs to (default @self)")], "show a ShellX notification (and push to the phone from a pane)") },
    c(&["wait"], &["PANE"], &[f("idle", "until the shell is back at its prompt"), f("exit", "until the shell exits; prints its exit code"), v("match", "REGEX", "until REGEX matches the pane's text"), f("from-now", "with --match: only text after this call"), v("quiet", "MS", "with --idle: quiet time (default 500)"), TIMEOUT], "wait for a pane"),
    c(&["events"], &[], &[f("follow", "keep printing until interrupted"), v("for", "SECONDS", "print events for SECONDS then exit"), v("kinds", "LIST", "comma-separated kinds (default: all)")], "print ShellX events as JSON lines"),
    c(&["browser", "ls"], &[], &[], "list browser panes"),
    c(&["browser", "open"], &["URL"], &[v("tab", "TAB", "tab to split (default: the selected tab)"), v("pane", "PANE", "pane to split"), f("down", "below instead of right"), FOCUS], "open a browser pane; prints its id"),
    c(&["browser", "nav"], &["PANE", "URL"], &[f("no-wait", "do not wait for the page to load"), TIMEOUT], "navigate a browser pane"),
    c(&["browser", "back"], &["PANE"], &[], "go back"),
    c(&["browser", "forward"], &["PANE"], &[], "go forward"),
    c(&["browser", "reload"], &["PANE"], &[], "reload"),
    c(&["browser", "stop"], &["PANE"], &[], "stop loading"),
    c(&["browser", "close"], &["PANE"], &[], "close a browser pane"),
    c(&["browser", "wait"], &["PANE"], &[TIMEOUT], "wait until the page has loaded"),
    c(&["browser", "eval"], &["PANE"], &[v("script", "JS", "async function body; `return` a JSON value"), v("file", "FILE", "read the body from FILE ('-' = stdin)"), TIMEOUT], "run JavaScript; prints the JSON result"),
    c(&["browser", "screenshot"], &["PANE"], &[v("out", "FILE", "copy the PNG to FILE")], "capture the visible page; prints the PNG path"),
    c(&["browser", "console"], &["PANE"], &[v("since", "SEQ", "entries after SEQ"), v("level", "LEVEL", "log, info, warn, error or debug"), v("limit", "N", "at most N entries (≤ 200)")], "print console entries"),
    c(&["browser", "network"], &["PANE"], &[v("since", "SEQ", "entries after SEQ"), v("limit", "N", "at most N entries (≤ 200)")], "print network entries (best effort)"),
    c(&["browser", "query"], &["PANE", "SELECTOR"], &[v("limit", "N", "at most N elements (default 50)")], "text, value and href of matching elements"),
    c(&["browser", "click"], &["PANE", "SELECTOR"], &[], "click the first matching element"),
    c(&["browser", "fill"], &["PANE", "SELECTOR", "TEXT..."], &[], "set an input's value and fire input/change"),
    CommandSpec { needs_ui: false, ..c(&["skills", "install"], &[], &[f("claude", "install for Claude Code (~/.claude/skills/shellx)"), f("codex", "install for Codex (~/.codex/skills/shellx)"), v("dir", "DIR", "install into DIR/shellx"), f("force", "overwrite without asking")], "install the ShellX skill for AI agents") },
    CommandSpec { needs_ui: false, ..c(&["skills", "print"], &["FILE?"], &[], "print SKILL.md (or 'reference')") },
    CommandSpec { needs_ui: false, ..c(&["completions"], &["SHELL"], &[], "print a completion script for zsh, bash or pwsh") },
];

pub struct Parsed {
    pub spec: &'static CommandSpec,
    pub positionals: Vec<String>,
    pub flags: Vec<(&'static str, Option<String>)>,
    pub json: bool,
    pub socket: Option<String>,
}

impl Parsed {
    pub fn flag(&self, name: &str) -> Option<&str> {
        self.flags.iter().find(|(n, _)| *n == name).and_then(|(_, v)| v.as_deref())
    }
    pub fn has(&self, name: &str) -> bool {
        self.flags.iter().any(|(n, _)| *n == name)
    }
    pub fn all(&self, name: &str) -> Vec<&str> {
        self.flags.iter().filter(|(n, _)| *n == name).filter_map(|(_, v)| v.as_deref()).collect()
    }
    pub fn pos(&self, i: usize) -> Option<&str> {
        self.positionals.get(i).map(String::as_str)
    }
}

pub enum Invocation {
    Run(Parsed),
    Help(Option<&'static CommandSpec>),
    Version,
    Completions(String),
}

fn find(words: &[String]) -> Option<(&'static CommandSpec, usize)> {
    COMMANDS
        .iter()
        .filter(|c| c.path.len() <= words.len() && c.path.iter().zip(words).all(|(a, b)| a == b))
        .max_by_key(|c| c.path.len())
        .map(|c| (c, c.path.len()))
}

pub fn parse(args: &[String]) -> Result<Invocation, String> {
    match args.first().map(String::as_str) {
        None => return Ok(Invocation::Help(None)),
        Some("--version") if args.len() == 1 => return Ok(Invocation::Version),
        Some("help") | Some("--help") | Some("-h") => {
            let rest = &args[1..];
            if rest.is_empty() {
                return Ok(Invocation::Help(None));
            }
            return find(rest)
                .map(|(c, _)| Invocation::Help(Some(c)))
                .ok_or_else(|| format!("unknown command '{}'", rest.join(" ")));
        }
        _ => {}
    }
    let (spec, used) = find(args).ok_or_else(|| format!("unknown command '{}' (try: shellx help)", args[0]))?;
    let mut parsed = Parsed { spec, positionals: vec![], flags: vec![], json: false, socket: None };
    let mut it = args[used..].iter();
    let mut only_positionals = false;
    while let Some(a) = it.next() {
        if only_positionals || !a.starts_with("--") || a == "-" {
            parsed.positionals.push(a.clone());
            continue;
        }
        if a == "--" {
            only_positionals = true;
            continue;
        }
        let (name, inline) = match a[2..].split_once('=') {
            Some((n, v)) => (n, Some(v.to_string())),
            None => (&a[2..], None),
        };
        if name == "help" {
            return Ok(Invocation::Help(Some(spec)));
        }
        let flag = spec
            .flags
            .iter()
            .chain(GLOBAL_FLAGS)
            .find(|fl| fl.name == name)
            .ok_or_else(|| format!("unknown flag --{name} for '{}'", spec.path.join(" ")))?;
        let value = match (flag.value, inline) {
            (None, None) => None,
            (None, Some(_)) => return Err(format!("--{name} takes no value")),
            (Some(_), Some(v)) => Some(v),
            (Some(p), None) => Some(it.next().cloned().ok_or_else(|| format!("--{name} needs {p}"))?),
        };
        if !flag.repeat && parsed.has(flag.name) {
            return Err(format!("--{name} given twice"));
        }
        match flag.name {
            "json" => parsed.json = true,
            "socket" => parsed.socket = value,
            _ => parsed.flags.push((flag.name, value)),
        }
    }
    let required = spec.positionals.iter().filter(|p| !p.ends_with('?')).count();
    let rest = spec.positionals.last().is_some_and(|p| p.ends_with("..."));
    let n = parsed.positionals.len();
    if n < required || (!rest && n > spec.positionals.len()) {
        return Err(format!("usage: shellx {} {}", spec.path.join(" "), spec.positionals.join(" ")));
    }
    if spec.path == ["completions"] {
        return Ok(Invocation::Completions(parsed.positionals[0].clone()));
    }
    Ok(Invocation::Run(parsed))
}

pub const EXIT_CODES: &str = "Exit codes: 0 ok · 1 error · 2 usage · 3 ShellX not running · 4 not found · 5 timeout · 6 refused · 7 incompatible ShellX · 8 ShellX window closed";

pub fn help_text(spec: Option<&CommandSpec>) -> String {
    let mut s = String::new();
    match spec {
        None => {
            s.push_str("Usage: shellx <command> [flags]   (drive ShellX from scripts and AI agents)\n\nCommands:\n");
            for c in COMMANDS {
                s.push_str(&format!("  {:<22} {}\n", c.path.join(" "), c.summary));
            }
            s.push_str("\nTargets: p<id> pane, t<id> tab, w:<id> or a name for workspaces, @self (this pane), @tab (this tab), @focused.\n");
            s.push_str("Global flags: --json, --socket ADDRESS, --help.\n");
            s.push_str(EXIT_CODES);
            s.push_str("\nMore: shellx help <command>; shellx skills print reference\n");
        }
        Some(c) => {
            s.push_str(&format!("Usage: shellx {} {}\n\n{}\n\nFlags:\n", c.path.join(" "), c.positionals.join(" "), c.summary));
            for fl in c.flags.iter().chain(GLOBAL_FLAGS) {
                let name = match fl.value {
                    Some(v) => format!("--{} {v}", fl.name),
                    None => format!("--{}", fl.name),
                };
                s.push_str(&format!("  {name:<22} {}\n", fl.help));
            }
            s.push('\n');
            s.push_str(EXIT_CODES);
            s.push('\n');
        }
    }
    s
}

fn words_after(prefix: &[&str]) -> Vec<&'static str> {
    let mut out: Vec<&'static str> = COMMANDS
        .iter()
        .filter(|c| c.path.len() > prefix.len() && c.path[..prefix.len()] == *prefix)
        .map(|c| c.path[prefix.len()])
        .collect();
    out.dedup();
    out
}

pub fn completion_script(shell: &str) -> Option<String> {
    let top = words_after(&[]).join(" ");
    let mut cases = String::new();
    for c in COMMANDS {
        let flags: Vec<String> = c.flags.iter().chain(GLOBAL_FLAGS).map(|f| format!("--{}", f.name)).collect();
        cases.push_str(&format!("{}|{}\n", c.path.join(" "), flags.join(" ")));
    }
    let subs = format!("workspace:{} browser:{} skills:{}", words_after(&["workspace"]).join(","), words_after(&["browser"]).join(","), words_after(&["skills"]).join(","));
    match shell {
        "bash" | "zsh" => Some(format!(
            r#"# shellx completion ({shell}). Load with: source <(shellx completions {shell})
{zsh}_shellx_flags() {{
  local key="$1"
  while IFS='|' read -r path flags; do [ "$path" = "$key" ] && echo "$flags"; done <<'EOF'
{cases}EOF
}}
_shellx() {{
  local cur="${{COMP_WORDS[COMP_CWORD]}}" w1="${{COMP_WORDS[1]}}" w2="${{COMP_WORDS[2]}}"
  if [ "$COMP_CWORD" -eq 1 ]; then COMPREPLY=($(compgen -W "{top}" -- "$cur")); return; fi
  case "{subs}" in *"$w1:"*) if [ "$COMP_CWORD" -eq 2 ]; then
      local s="{subs}"; s="${{s#*$w1:}}"; s="${{s%% *}}"; COMPREPLY=($(compgen -W "${{s//,/ }}" -- "$cur")); return; fi;; esac
  local key="$w1"; case "$w1" in workspace|browser|skills) key="$w1 $w2";; esac
  if [[ "$cur" == --* ]]; then COMPREPLY=($(compgen -W "$(_shellx_flags "$key")" -- "$cur")); return; fi
  COMPREPLY=($(compgen -W "$(shellx ls --ids 2>/dev/null)" -- "$cur"))
}}
complete -F _shellx shellx
"#,
            zsh = if shell == "zsh" { "autoload -U +X bashcompinit && bashcompinit\n" } else { "" },
        )),
        "pwsh" => Some(format!(
            r#"# shellx completion (PowerShell). Load with: shellx completions pwsh | Out-String | Invoke-Expression
$__shellxFlags = @'
{cases}'@
Register-ArgumentCompleter -Native -CommandName shellx, shellx.exe -ScriptBlock {{
  param($word, $ast, $cursor)
  $w = $ast.CommandElements | Select-Object -Skip 1 | ForEach-Object {{ $_.ToString() }}
  if ($w.Count -le 1 -and -not $word.StartsWith('-')) {{ $c = '{top}'.Split(' ') }}
  elseif ($word.StartsWith('--')) {{
    $key = if ('workspace','browser','skills' -contains $w[0]) {{ "$($w[0]) $($w[1])" }} else {{ $w[0] }}
    $line = ($__shellxFlags -split "`n") | Where-Object {{ $_.StartsWith("$key|") }} | Select-Object -First 1
    $c = if ($line) {{ $line.Split('|')[1].Split(' ') }} else {{ @() }}
  }} else {{ $c = (& shellx ls --ids 2>$null) }}
  $c | Where-Object {{ $_ -like "$word*" }} | ForEach-Object {{ [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_) }}
}}
"#
        )),
        _ => None,
    }
}

#[allow(clippy::let_and_return)] // one binding per platform
pub fn is_cli_name(argv0: &OsStr) -> bool {
    let name = std::path::Path::new(argv0).file_name().and_then(OsStr::to_str).unwrap_or("");
    #[cfg(windows)]
    let name = name.to_ascii_lowercase();
    #[cfg(windows)]
    let name = name.strip_suffix(".exe").unwrap_or(&name).to_string();
    name == "shellx"
}
```

`term/src/api/mod.rs`: add `pub mod args;`.

`term/src/main.rs` — at the very top of **both** `main` functions (Unix and Windows), before `cli::parse`, add:

```rust
    {
        let mut argv = std::env::args_os();
        let argv0 = argv.next().unwrap_or_default();
        let rest: Vec<std::ffi::OsString> = argv.collect();
        let cli_sub = rest.first().is_some_and(|a| a == "cli");
        if shellx_term::api::args::is_cli_name(&argv0) || cli_sub {
            let args = if cli_sub { rest[1..].to_vec() } else { rest };
            std::process::exit(shellx_term::api::main(args));
        }
    }
```

and in `api/mod.rs` a minimal `main` for now (Task 10 replaces its body with the full runner):

```rust
/// Entry point of the `shellx` command. Returns the exit code (D10).
pub fn main(args: Vec<std::ffi::OsString>) -> i32 {
    use std::io::Write;
    let args: Vec<String> = match args.into_iter().map(|a| a.into_string()).collect() {
        Ok(a) => a,
        Err(_) => {
            let _ = writeln!(std::io::stderr(), "shellx: arguments must be valid UTF-8 (usage)");
            return 2;
        }
    };
    match args::parse(&args) {
        Err(msg) => {
            let _ = writeln!(std::io::stderr(), "shellx: {msg}");
            2
        }
        Ok(args::Invocation::Help(spec)) => {
            let _ = write!(std::io::stdout(), "{}", args::help_text(spec));
            0
        }
        Ok(args::Invocation::Version) => {
            let _ = writeln!(std::io::stdout(), "shellx {} (api 1)", env!("CARGO_PKG_VERSION"));
            0
        }
        Ok(args::Invocation::Completions(sh)) => match args::completion_script(&sh) {
            Some(s) => {
                let _ = write!(std::io::stdout(), "{s}");
                0
            }
            None => {
                let _ = writeln!(std::io::stderr(), "shellx: completions for zsh, bash or pwsh");
                2
            }
        },
        Ok(args::Invocation::Run(_)) => {
            let _ = writeln!(std::io::stderr(), "shellx: ShellX is not running (open ShellX and try again)");
            3
        }
    }
}
```

The unknown-command message must contain "unknown command" (the dispatch test checks it).

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd term && ~/.cargo/bin/cargo test args && ~/.cargo/bin/cargo test --test cli_dispatch && ~/.cargo/bin/cargo test --features test-hooks`
Expected: PASS (`not_running_is_exit_3` ignored).

Smoke-check the completion scripts parse: `./target/debug/shellx-term cli completions bash | bash -n` and `… completions zsh | zsh -n` → no output, exit 0.

- [ ] **Step 5: Lint and commit**

```bash
cd term && ~/.cargo/bin/cargo fmt --check && ~/.cargo/bin/cargo clippy --all-targets -- -D warnings && cd ..
git add term/src/api/mod.rs term/src/api/args.rs term/src/main.rs term/tests/cli_dispatch.rs
git commit -m "feat(term): shellx command table, parser, help, completions and name dispatch (A7 D6, D9, D10, D36)"
```

---

### Task 5: Agent package — `CliHost`: listen, handshake, role `cli`, allowlist, switch, limits, `api.version` (D2–D5, D26, D32)

**Files:**
- Create: `packages/shellx_agent/lib/src/mux/ui_api.dart`, `packages/shellx_agent/lib/src/mux/cli_host.dart` (pure Dart: the A5b daemon and the e2e test reuse it)
- Modify: `packages/shellx_agent/lib/shellx_agent.dart` (exports), `apps/desktop/lib/src/platform/settings_store.dart` (keys)
- Test: `packages/shellx_agent/test/mux/cli_host_test.dart`, `packages/shellx_agent/test/support/cli_api_contract.dart`, `packages/shellx_agent/test/support/fake_ui_api.dart`

**Interfaces:**
- Consumes: A5b `MuxTransport`, `MuxListener`, `MuxConnection`, `MemoryMuxTransport.pair`, `serverHandshake`, `clientHandshake`, `MuxPeerInfo`, `MuxEndpointInfo`, `MuxEndpointFile`, `MuxMessage`, `MuxType`; Task 2 `CliType`, `CliError`, `kCliApi`, `kCliCaps`, `cliResult`, `cliErrorMessage`.
- Produces:
  - `ui_api.dart` (exported by `shellx_agent.dart`):
    ```dart
    final class CliFailure implements Exception { const CliFailure(this.code, [this.message]); final String code; final String? message; }
    abstract interface class UiApi {
      /// One `ui.*` request → result fields. Throws [CliFailure].
      /// [cancelled] completes when the asking client went away (D21: a
      /// `wait` stops then).
      Future<Map<String, Object?>> handle(MuxMessage request, {Future<void>? cancelled});
      /// D24 events (already filtered to what the UI emits).
      Stream<Map<String, Object?>> events();
      /// D23 without a pane: system notification + "Dòng lệnh" panel entry.
      Future<void> notifyApp({String? title, required String body});
      /// D23 with a pane: `LocalSessions.notify`. False: no such session.
      bool notifyPane(int pane, {String? title, required String body});
    }
    ```
  - `cli_host.dart`: `final class CliHost { CliHost({required MuxTransport transport, required String address, required MuxEndpointFile endpointFile, required UiApi ui, required bool Function() enabled, required String appVersion, int maxClients = 8, int maxListeners = 4}); Future<void> start(); Future<void> stop(); int get clientCount; }`
  - Settings: `SettingKeys.cliControlEnabled = 'cli_control_enabled'`, `SettingKeys.cliPathInstalled = 'cli_path_installed'` (both in `SettingKeys.all`; UI-owned in A5b's ownership test when present).
  - Test support: `abstract interface class CliTestHost { Future<MuxConnection> connect({String role}); Uint8List get secret; Future<void> close(); }`, `void cliApiContract(String name, Future<CliTestHost> Function(FakeUiApi ui, bool Function() enabled) make)`.

- [ ] **Step 1: Write the failing tests**

`packages/shellx_agent/test/support/fake_ui_api.dart`:

```dart
import 'dart:async';

import 'package:shellx_agent/shellx_agent.dart';

final class FakeUiApi implements UiApi {
  final requests = <MuxMessage>[];
  final appNotices = <(String?, String)>[];
  final paneNotices = <(int, String?, String)>[];
  final eventsOut = StreamController<Map<String, Object?>>.broadcast();
  Set<int> livePanes = {12};
  Completer<void>? gate;

  @override
  Future<Map<String, Object?>> handle(MuxMessage request, {Future<void>? cancelled}) async {
    requests.add(request);
    await gate?.future;
    if (request.type == 'ui.fail') throw const CliFailure('not_found', 'no pane p1');
    return {'echo': request.type};
  }

  @override
  Stream<Map<String, Object?>> events() => eventsOut.stream;

  @override
  Future<void> notifyApp({String? title, required String body}) async =>
      appNotices.add((title, body));

  @override
  bool notifyPane(int pane, {String? title, required String body}) {
    paneNotices.add((pane, title, body));
    return livePanes.contains(pane);
  }
}
```

`packages/shellx_agent/test/support/cli_api_contract.dart`:

```dart
import 'dart:async';
import 'dart:typed_data';

import 'package:shellx_agent/shellx_agent.dart';
import 'package:test/test.dart';

import 'fake_ui_api.dart';

abstract interface class CliTestHost {
  /// Connected and authenticated as [role] (handshake done by the test).
  Future<MuxConnection> connect({String role = 'cli'});
  Uint8List get secret;
  Future<void> close();
}

/// A7 D37a: one suite, every host.
void cliApiContract(
  String name,
  Future<CliTestHost> Function(FakeUiApi ui, bool Function() enabled) make,
) {
  group('CLI API contract — $name', () {
    late FakeUiApi ui;
    late CliTestHost host;
    var enabled = true;

    setUp(() async {
      ui = FakeUiApi();
      enabled = true;
      host = await make(ui, () => enabled);
    });
    tearDown(() => host.close());

    Future<MuxMessage> ask(MuxConnection c, String t, [Map<String, Object?> f = const {}]) {
      final answer = c.messages.firstWhere((m) => m.q == 77);
      c.send(MuxMessage(t, q: 77, fields: f));
      return answer.timeout(const Duration(seconds: 2));
    }

    test('api.version', () async {
      final c = await host.connect();
      final r = await ask(c, 'api.version');
      expect(r.type, 'result');
      expect(r.get<int>('api'), 1);
      expect(r.get<List<Object?>>('caps'), containsAll(['ui.ls', 'ui.pane.send', 'cli.notify']));
      expect(r.get<String>('host'), anyOf('ui', 'daemon'));
    });

    test('forbidden types keep the connection', () async {
      final c = await host.connect();
      for (final t in ['sessions.open', 'view.write', 'agent.call', 'daemon.quit']) {
        final r = await ask(c, t);
        expect([r.type, r.get<String>('code')], ['error', 'forbidden'], reason: t);
      }
      expect((await ask(c, 'api.version')).type, 'result');
    });

    test('ui.* reaches the UI; failures carry code and message', () async {
      final c = await host.connect();
      final r = await ask(c, 'ui.ls', {'x': 1});
      expect(r.get<String>('echo'), 'ui.ls');
      expect(ui.requests.single.get<int>('x'), 1);
      final e = await ask(c, 'ui.fail');
      expect([e.get<String>('code'), e.get<String>('message')], ['not_found', 'no pane p1']);
      expect((await ask(c, 'cli.nope')).get<String>('code'), 'unknown_type');
    });

    test('switch off: ui.* and events refused, version and notify allowed (D26)', () async {
      enabled = false;
      final c = await host.connect();
      expect((await ask(c, 'ui.ls')).get<String>('code'), 'cli_disabled');
      expect((await ask(c, 'cli.events.subscribe')).get<String>('code'), 'cli_disabled');
      expect((await ask(c, 'api.version')).type, 'result');
      expect((await ask(c, 'cli.notify', {'body': 'x'})).type, 'result');
    });

    test('cli.notify routes by pane (D23)', () async {
      final c = await host.connect();
      expect((await ask(c, 'cli.notify', {'pane': 12, 'title': 'CI', 'body': 'ok'})).type, 'result');
      expect(ui.paneNotices.single, (12, 'CI', 'ok'));
      expect((await ask(c, 'cli.notify', {'pane': 99, 'body': 'x'})).get<String>('code'), 'not_found');
      expect((await ask(c, 'cli.notify', {'body': 'app'})).type, 'result');
      expect(ui.appNotices.single, (null, 'app'));
      expect((await ask(c, 'cli.notify', {})).get<String>('code'), 'bad_request');
      final long = 'x' * 2000;
      await ask(c, 'cli.notify', {'body': long, 'title': 'y' * 300});
      expect(ui.appNotices.last.$2.length, 1024);
      expect(ui.appNotices.last.$1!.length, 128);
    });

    test('events stream after subscribe, filtered by kinds', () async {
      final c = await host.connect();
      expect((await ask(c, 'cli.events.subscribe', {'kinds': ['tab.opened']})).type, 'result');
      final got = c.messages.firstWhere((m) => m.type == 'event');
      ui.eventsOut.add({'kind': 'pane.closed', 'pane': 1});
      ui.eventsOut.add({'kind': 'tab.opened', 'tab': 5});
      final e = await got.timeout(const Duration(seconds: 2));
      expect([e.get<String>('kind'), e.get<int>('tab')], ['tab.opened', 5]);
    });

    test('requests on one connection run in order', () async {
      final c = await host.connect();
      ui.gate = Completer<void>();
      final order = <int>[];
      c.messages.where((m) => m.type == 'result').listen((m) => order.add(m.q!));
      c.send(const MuxMessage('ui.a', q: 1));
      c.send(const MuxMessage('api.version', q: 2));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(order, isEmpty); // api.version waits behind ui.a
      ui.gate!.complete();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(order, [1, 2]);
    });
  });
}
```

`packages/shellx_agent/test/mux/cli_host_test.dart`:

```dart
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:shellx_agent/shellx_agent.dart';
import 'package:test/test.dart';

import '../support/cli_api_contract.dart';
import '../support/fake_ui_api.dart';

/// Hands out [MemoryMuxTransport] pairs: `connect` gives the client side,
/// the listener yields the server side.
final class PairTransport implements MuxTransport {
  final _incoming = StreamController<MuxConnection>();
  @override
  Future<MuxListener> listen(String address) async => _Listener(_incoming.stream, address);
  @override
  Future<MuxConnection> connect(String address, {Duration timeout = const Duration(seconds: 1)}) async {
    final (client, server) = MemoryMuxTransport.pair();
    _incoming.add(server);
    return client;
  }
}

final class _Listener implements MuxListener {
  _Listener(this.connections, this.address);
  @override
  final Stream<MuxConnection> connections;
  @override
  final String address;
  @override
  Future<void> close() async {}
}

final class InUiHost implements CliTestHost {
  InUiHost._(this._host, this._transport, this._file);
  final CliHost _host;
  final PairTransport _transport;
  final MuxEndpointFile _file;
  @override
  late final Uint8List secret;

  static Future<InUiHost> start(FakeUiApi ui, bool Function() enabled, Directory dir) async {
    final t = PairTransport();
    final file = MuxEndpointFile('${dir.path}/mux/endpoint');
    final host = CliHost(transport: t, address: 'mem', endpointFile: file, ui: ui, enabled: enabled, appVersion: '1.7.0');
    await host.start();
    final h = InUiHost._(host, t, file);
    h.secret = (await file.read())!.secret;
    return h;
  }

  @override
  Future<MuxConnection> connect({String role = 'cli'}) async {
    final c = await _transport.connect('mem');
    await clientHandshake(c, secret: secret, app: 'test', role: role);
    return c;
  }

  @override
  Future<void> close() => _host.stop();
}

void main() {
  late Directory dir;
  setUp(() async => dir = await Directory.systemTemp.createTemp('cli_host'));
  tearDown(() => dir.delete(recursive: true));

  cliApiContract('in-UI host', (ui, enabled) => InUiHost.start(ui, enabled, dir));

  test('endpoint written with a fresh secret; stop deletes it', () async {
    final h = await InUiHost.start(FakeUiApi(), () => true, dir);
    final info = (await MuxEndpointFile('${dir.path}/mux/endpoint').read())!;
    expect(info.address, 'mem');
    expect(info.protocol, 1);
    await h.close();
    expect(File('${dir.path}/mux/endpoint').existsSync(), isFalse);
  });

  test('role ui is refused with unsupported_role (D2)', () async {
    final h = await InUiHost.start(FakeUiApi(), () => true, dir);
    final c = await h._transport.connect('mem');
    // Listen before the handshake: the refusal follows `ready` at once.
    final refusal = c.messages.firstWhere((m) => m.type == 'error');
    final info = await clientHandshake(c, secret: h.secret, app: 't', role: 'ui');
    expect(info.protocol, 1);
    final e = await refusal.timeout(const Duration(seconds: 1));
    expect([e.type, e.get<String>('code')], ['error', 'unsupported_role']);
    await c.done.timeout(const Duration(seconds: 1));
    await h.close();
  });

  test('a wrong secret never reaches the UI', () async {
    final ui = FakeUiApi();
    final h = await InUiHost.start(ui, () => true, dir);
    final c = await h._transport.connect('mem');
    await expectLater(
      clientHandshake(c, secret: Uint8List(32), app: 't', role: 'cli'),
      throwsA(isA<MuxHandshakeException>()),
    );
    expect(ui.requests, isEmpty);
    await h.close();
  });

  test('a ninth client gets busy; a closed client frees its slot (D32)', () async {
    final h = await InUiHost.start(FakeUiApi(), () => true, dir);
    final clients = [for (var i = 0; i < 8; i++) await h.connect()];
    final ninth = await h._transport.connect('mem');
    final refusal = ninth.messages.firstWhere((m) => m.type == 'error');
    await clientHandshake(ninth, secret: h.secret, app: 't', role: 'cli');
    final e = await refusal.timeout(const Duration(seconds: 1));
    expect(e.get<String>('code'), 'busy');
    await clients.first.close();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    final tenth = await h.connect();
    final ok = tenth.messages.firstWhere((m) => m.q == 1);
    tenth.send(const MuxMessage('api.version', q: 1));
    expect((await ok).type, 'result');
    await h.close();
  });

  test('a client closing mid-request does not throw into the host', () async {
    final ui = FakeUiApi()..gate = Completer<void>();
    final h = await InUiHost.start(ui, () => true, dir);
    final c = await h.connect();
    c.send(const MuxMessage('ui.ls', q: 1));
    await Future<void>.delayed(const Duration(milliseconds: 10));
    await c.close();
    ui.gate!.complete();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(h._host.clientCount, 0);
    await h.close();
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd packages/shellx_agent && ~/fvm/versions/3.41.4/bin/dart test test/mux/cli_host_test.dart`
Expected: FAIL — `CliHost` undefined.

- [ ] **Step 3: Implement**

`apps/desktop/lib/src/platform/settings_store.dart` — add to `SettingKeys` and to `all`:

```dart
  /// A7 D26: "Cho phép điều khiển ShellX bằng dòng lệnh" (default on).
  static const String cliControlEnabled = 'cli_control_enabled';

  /// A7 D8: the `shellx` link/PATH entry for other terminals is installed.
  static const String cliPathInstalled = 'cli_path_installed';
```

If A5b is merged, add both to `UiSettingKeys` (A5b D13) — the ownership test then covers them.

`packages/shellx_agent/lib/src/mux/ui_api.dart` — exactly the interface in **Interfaces** above (it imports `mux_messages.dart` for `MuxMessage`), with doc comments. Export both new files from `packages/shellx_agent/lib/shellx_agent.dart`.

`packages/shellx_agent/lib/src/mux/cli_host.dart`:

```dart
import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'cli_wire.dart';
import 'mux_endpoint.dart';
import 'mux_handshake.dart';
import 'mux_messages.dart';
import 'mux_transport.dart';
import 'ui_api.dart';

/// A7 D2: the CLI API served by the window process (before A5b, and the
/// shape A5b's daemon reuses). Listens on the A5b address, writes the A5b
/// endpoint file, authenticates with the A5b handshake, accepts only
/// `role: "cli"`.
final class CliHost {
  CliHost({
    required MuxTransport transport,
    required this.address,
    required MuxEndpointFile endpointFile,
    required UiApi ui,
    required bool Function() enabled,
    required this.appVersion,
    this.maxClients = 8,
    this.maxListeners = 4,
    void Function(String message)? log,
  }) : _transport = transport,
       _file = endpointFile,
       _ui = ui,
       _enabled = enabled,
       _log = log ?? ((_) {});

  final String address;
  final String appVersion;
  final int maxClients;
  final int maxListeners;
  final MuxTransport _transport;
  final MuxEndpointFile _file;
  final UiApi _ui;
  final bool Function() _enabled;
  final void Function(String) _log;

  MuxListener? _listener;
  StreamSubscription<MuxConnection>? _accept;
  String? _written;
  late Uint8List _secret;
  late String _instance;
  final _clients = <_Client>{};
  int _handshaking = 0;
  int _listeners = 0;

  int get clientCount => _clients.length;

  Future<void> start() async {
    final r = Random.secure();
    _secret = Uint8List.fromList(List.generate(32, (_) => r.nextInt(256)));
    _instance = List.generate(16, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
    _listener = await _transport.listen(address);
    _accept = _listener!.connections.listen(_onConnection);
    _written = await _file.write(MuxEndpointInfo(
      address: address,
      secret: _secret,
      pid: pid,
      instance: _instance,
      protocol: kMuxProtocol,
      app: appVersion,
    ));
  }

  Future<void> stop() async {
    await _accept?.cancel();
    await _listener?.close();
    for (final c in _clients.toList()) {
      await c.close();
    }
    final written = _written;
    if (written != null) await _file.deleteIfOwned(written);
  }

  Future<void> _onConnection(MuxConnection c) async {
    if (_handshaking >= 4) {
      await c.close();
      return;
    }
    _handshaking++;
    final MuxPeerInfo peer;
    try {
      peer = await serverHandshake(
        c,
        secret: _secret,
        self: MuxPeerInfo(
          protocol: kMuxProtocol,
          app: appVersion,
          instance: _instance,
          pid: pid,
          caps: const ['host.ui'],
        ),
      );
    } on Object catch (e) {
      _log('cli handshake failed: ${e.runtimeType}');
      return;
    } finally {
      _handshaking--;
    }
    if (peer.role != 'cli') {
      c.send(cliErrorMessage(null, MuxError.unsupportedRole));
      await c.close();
      return;
    }
    if (_clients.length >= maxClients) {
      c.send(cliErrorMessage(null, MuxError.busy));
      await c.close();
      return;
    }
    final client = _Client(this, c);
    _clients.add(client);
    unawaited(c.done.whenComplete(() {
      _clients.remove(client);
      client.dispose();
    }));
  }

  /// One request → one answer (never throws).
  Future<MuxMessage> _answer(MuxMessage m, _Client client) async {
    final q = m.q;
    try {
      if (!CliType.allowedForCli(m.type)) {
        return cliErrorMessage(q, CliError.forbidden);
      }
      switch (m.type) {
        case CliType.apiVersion:
          return cliResult(q, {
            'api': kCliApi,
            'app': appVersion,
            'host': 'ui',
            'ui': true,
            'caps': kCliCaps,
          });
        case MuxType.daemonStatus:
          return cliResult(q, {'host': 'ui', 'clients': _clients.length});
        case CliType.cliNotify:
          return _notify(m);
        case CliType.cliEventsSubscribe:
          if (!_enabled()) return cliErrorMessage(q, CliError.cliDisabled);
          if (client.events == null && _listeners >= maxListeners) {
            return cliErrorMessage(q, MuxError.busy);
          }
          client.subscribe(m.get<List<Object?>>('kinds')?.whereType<String>().toSet());
          return cliResult(q);
      }
      if (m.type.startsWith('ui.')) {
        if (!_enabled()) {
          return cliErrorMessage(q, CliError.cliDisabled,
              'Command-line control is off in ShellX (tray → Command line)');
        }
        return cliResult(q, await _ui.handle(m, cancelled: client.connection.done));
      }
      return cliErrorMessage(q, MuxError.unknownType);
    } on CliFailure catch (f) {
      return cliErrorMessage(q, f.code, f.message);
    } on Object catch (e) {
      _log('cli request ${m.type} failed: ${e.runtimeType}');
      return cliErrorMessage(q, MuxError.internal);
    }
  }

  Future<MuxMessage> _notify(MuxMessage m) async {
    final rawBody = m.get<String>('body');
    if (rawBody == null || rawBody.trim().isEmpty) {
      return cliErrorMessage(m.q, MuxError.badRequest, 'notify needs text');
    }
    final body = _clip(_stripControls(rawBody), 1024);
    final rawTitle = m.get<String>('title');
    final title = rawTitle == null ? null : _clip(_stripControls(rawTitle), 128);
    final pane = m.get<int>('pane');
    if (pane != null) {
      return _ui.notifyPane(pane, title: title, body: body)
          ? cliResult(m.q)
          : cliErrorMessage(m.q, MuxError.notFound, 'no pane p$pane');
    }
    await _ui.notifyApp(title: title, body: body);
    return cliResult(m.q);
  }

  static String _stripControls(String s) =>
      s.replaceAll(RegExp('[\\x00-\\x1F\\x7F\\u0080-\\u009F]'), ' ');

  static String _clip(String s, int max) =>
      s.runes.length <= max ? s : String.fromCharCodes(s.runes.take(max));
}

final class _Client {
  _Client(this.host, this.connection) {
    _sub = connection.messages.listen((m) {
      // D32: requests on one connection run in order.
      _chain = _chain.then((_) async {
        final answer = await host._answer(m, this);
        if (!_closed) connection.send(answer);
      });
    });
  }

  final CliHost host;
  final MuxConnection connection;
  late final StreamSubscription<MuxMessage> _sub;
  Future<void> _chain = Future.value();
  StreamSubscription<Map<String, Object?>>? events;
  bool _closed = false;
  int _queued = 0;
  int _dropped = 0;

  void subscribe(Set<String>? kinds) {
    if (events != null) return;
    host._listeners++;
    events = host._ui.events().listen((e) {
      if (kinds != null && !kinds.contains(e['kind'])) return;
      // D24: ≤ 1000 queued; the memory transport and sockets buffer
      // writes, so count what we have not seen flushed.
      if (_queued >= 1000) {
        _dropped++;
        return;
      }
      if (_dropped > 0) {
        connection.send(MuxMessage(CliType.event, fields: {'kind': 'overflow', 'dropped': _dropped}));
        _dropped = 0;
      }
      _queued++;
      connection.send(MuxMessage(CliType.event, fields: e));
      scheduleMicrotask(() => _queued--);
    });
  }

  Future<void> close() async {
    _closed = true;
    await connection.close();
  }

  void dispose() {
    _closed = true;
    unawaited(_sub.cancel());
    if (events != null) {
      host._listeners--;
      unawaited(events!.cancel());
    }
  }
}
```

(`_queued` is decremented in a microtask because `MuxConnection.send` hands the frame to the transport synchronously; the cap protects against a UI emitting faster than the event loop drains. A real socket's write buffer is the remaining back-pressure; document that in the class comment.)

The in-UI run of the contract lives in `cli_host_test.dart`; Task 11 adds the daemon run.

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd packages/shellx_agent && ~/fvm/versions/3.41.4/bin/dart test && cd ../../apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test`
Expected: PASS.

- [ ] **Step 5: Format, analyze, commit**

```bash
cd packages/shellx_agent && ~/fvm/versions/3.41.4/bin/dart format --set-exit-if-changed lib test && ~/fvm/versions/3.41.4/bin/dart analyze && cd ../..
cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH dart format --set-exit-if-changed lib/src/platform/settings_store.dart && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter analyze && cd ../..
git add packages/shellx_agent/lib/src/mux/ui_api.dart packages/shellx_agent/lib/src/mux/cli_host.dart packages/shellx_agent/lib/shellx_agent.dart packages/shellx_agent/test/mux/cli_host_test.dart packages/shellx_agent/test/support/cli_api_contract.dart packages/shellx_agent/test/support/fake_ui_api.dart apps/desktop/lib/src/platform/settings_store.dart
git commit -m "feat(agent): CliHost — A5b socket and handshake for role cli, allowlist, switch, limits, api.version, notify routing (A7 D2-D5, D23, D26, D32)"
```

---
### Task 6: Desktop — targets, `ls`, tabs, splits, focus, close, rename, workspaces, Agent marks (D12–D15, D17, D18, D22, D27, D33)

**Files:**
- Create: `apps/desktop/lib/src/cli/cli_targets.dart`, `apps/desktop/lib/src/cli/agent_marks.dart`, `apps/desktop/lib/src/cli/ui_command_handler.dart`
- Modify: `apps/desktop/lib/src/terminal/terminal_tabs.dart` (`openTabFor`, `splitPane`, exceptions, `tabId` on every open), `apps/desktop/lib/src/terminal/sidebar_workspaces.dart` (`createFor`)
- Test: `apps/desktop/test/cli/cli_targets_test.dart`, `apps/desktop/test/cli/agent_marks_test.dart`, `apps/desktop/test/cli/ui_command_handler_test.dart`, `apps/desktop/test/terminal/terminal_tabs_panes_test.dart` (add: split passes `tabId`)

**Interfaces:**
- Consumes: Task 5 `UiApi`, `CliFailure`; Task 2 `CliType`, `CliError`; `TerminalTabs`, `TerminalTabsState.tabOfSession`, `TerminalTab` (`id`, `panes`, `paneOrder`, `focusedPaneId`, `zoomedPaneId`, `label`, `customTitle`), `PaneSession` (`id`, `title`, `cwd`, `gitBranch`, `ports`, `runningCommand`, `exitCode`, `exited`, `phoneAttached`, `driver`, `terminal`), `SplitAxis.row/column`, `SidebarWorkspaces` (`moveTab`, `rename`, `reveal`), `SidebarState` (`workspaces`, `currentId`, `tabsOf`, `workspaceOf`), `kDefaultWorkspaceId`, `tabAttentionProvider` (`AttentionState.unread[tabId].count`), A6 `browserCommandHandlerProvider` (`handle({'t': 'ui.browser.list'})`), A1 window activation (`WindowCoordinator`/`activation.dart` — use the same call the tray's `OpenTerminalWindow` uses).
- Produces:
  - `cli_targets.dart`: `sealed class CliTarget`; `PaneRef(int id)`, `TabRef(int id)`, `FocusedRef()`; `CliTarget parseTarget(Object? pane, Object? tab)` (wire: `pane`/`tab` are an int id or the string `"@focused"`; exactly one present else `CliFailure(bad_request)`); `int resolvePane(TerminalTabsState s, CliTarget t)` (terminal panes only; throws `not_found`); `int resolveTab(TerminalTabsState s, CliTarget t)`; `String resolveWorkspace(SidebarState s, String key, String Function(String id) displayName)` (id, else case-insensitive name; `ambiguous`/`not_found`).
  - `agent_marks.dart`: `final agentMarksProvider = NotifierProvider<AgentMarks, AgentMarksState>(AgentMarks.new)`; `AgentMarksState { Map<int, DateTime> tabs; Map<int, DateTime> panes; bool tabActive(int id, DateTime now); bool paneActive(int id, DateTime now) }`; `AgentMarks.touch({required int tab, int? pane})`; `const kAgentMarkFor = Duration(seconds: 10)`, `const kAgentAnnounceGap = Duration(seconds: 60)`; `AgentMarks.announce` hook `void Function(int tabId)? onAnnounce` set by the UI (Task 9).
  - `terminal_tabs.dart`: `final class OpenBusyException`, `final class PaneNoRoomException`, `final class PaneGoneException`; `Future<int> openTabFor({String? cwd, bool select = false})` → tab id; `Future<int> splitPane(int target, SplitAxis axis, {String? cwd, bool focus = false})` → new pane id. `split(axis)` and `openTab()` keep their behavior (notices) and are re-expressed on top of these.
  - `sidebar_workspaces.dart`: `String createFor({String? name})` — appends a workspace (named or "Workspace N"), saves, does **not** change `currentId` or open a rename field; returns its id.
  - `ui_command_handler.dart`: `final class UiCommandHandler implements UiApi { UiCommandHandler(Ref ref, {DateTime Function()? clock, Duration openWait = const Duration(seconds: 10)}); }` handling `ui.ls`, `ui.tab.new`, `ui.tab.rename`, `ui.pane.split`, `ui.focus`, `ui.close`, `ui.workspace.new`, `ui.workspace.rename`, `ui.workspace.move` here; Tasks 7–8 add the rest. `final uiCommandHandlerProvider = Provider<UiCommandHandler>((ref) => UiCommandHandler(ref));`

- [ ] **Step 1: Write the failing tests**

`apps/desktop/test/cli/cli_targets_test.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/cli/cli_targets.dart';
import 'package:shellx_desktop/src/terminal/local_sessions_provider.dart';
import 'package:shellx_desktop/src/terminal/sidebar_workspaces.dart';
import 'package:shellx_desktop/src/terminal/terminal_tabs.dart';

import '../support/fake_local_sessions.dart';
import '../support/fakes.dart';

void main() {
  late ProviderContainer c;
  late FakeLocalSessions local;

  setUp(() async {
    local = FakeLocalSessions();
    c = ProviderContainer(overrides: [
      localSessionsProvider.overrideWithValue(local),
      ...testDesktopOverrides(), // settings/l10n fakes used by A2–A4 tests
    ]);
    addTearDown(c.dispose);
    await c.read(terminalTabsProvider.notifier).openTab();
    await c.read(terminalTabsProvider.notifier).split(SplitAxis.row);
  });

  test('wire forms', () {
    expect(parseTarget(12, null), isA<PaneRef>());
    expect(parseTarget(null, 7), isA<TabRef>());
    expect(parseTarget('@focused', null), isA<FocusedRef>());
    for (final bad in [(null, null), (1, 2), ('x', null), (1.5, null)]) {
      expect(() => parseTarget(bad.$1, bad.$2),
          throwsA(isA<CliFailure>().having((f) => f.code, 'code', 'bad_request')));
    }
  });

  test('panes and tabs resolve; focused = focused pane of the selected tab', () {
    final s = c.read(terminalTabsProvider);
    final tab = s.selected!;
    expect(resolvePane(s, const FocusedRef()), tab.focusedPaneId);
    expect(resolveTab(s, PaneRef(tab.paneOrder.last)), tab.id);
    expect(resolvePane(s, PaneRef(tab.paneOrder.first)), tab.paneOrder.first);
    expect(() => resolvePane(s, const PaneRef(4242)),
        throwsA(isA<CliFailure>().having((f) => f.code, 'code', 'not_found')));
    expect(() => resolveTab(s, const TabRef(4242)), throwsA(isA<CliFailure>()));
  });

  test('workspace by id or case-insensitive name; duplicates are ambiguous', () {
    final side = c.read(sidebarWorkspacesProvider.notifier);
    final a = side.createFor(name: 'API');
    side.createFor(name: 'web');
    side.createFor(name: 'Web');
    final s = c.read(sidebarWorkspacesProvider);
    String name(String id) => side.displayName(id);
    expect(resolveWorkspace(s, a, name), a);
    expect(resolveWorkspace(s, 'api', name), a);
    expect(() => resolveWorkspace(s, 'web', name),
        throwsA(isA<CliFailure>().having((f) => f.code, 'code', 'ambiguous')));
    expect(() => resolveWorkspace(s, 'nope', name),
        throwsA(isA<CliFailure>().having((f) => f.code, 'code', 'not_found')));
  });
}
```

(If `testDesktopOverrides()` does not exist, use the override list the existing `test/terminal/terminal_tabs_panes_test.dart` builds its container with; copy it into `test/cli/support/cli_container.dart` as `ProviderContainer cliContainer(FakeLocalSessions local)` and use that in every Task 6–8 test.)

`apps/desktop/test/cli/agent_marks_test.dart`:

```dart
import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/cli/agent_marks.dart';

void main() {
  test('10 s mark per tab and pane; one announcement per 60 s', () {
    fakeAsync((async) {
      var now = DateTime(2026, 10, 7, 9);
      final c = ProviderContainer(overrides: [
        agentMarksClockProvider.overrideWithValue(() => now),
      ]);
      final announced = <int>[];
      c.read(agentMarksProvider.notifier).onAnnounce = announced.add;
      c.read(agentMarksProvider.notifier).touch(tab: 5, pane: 6);
      expect(c.read(agentMarksProvider).tabActive(5, now), isTrue);
      expect(c.read(agentMarksProvider).paneActive(6, now), isTrue);
      expect(announced, [5]);
      now = now.add(const Duration(seconds: 9));
      c.read(agentMarksProvider.notifier).touch(tab: 5);
      expect(announced, [5]); // within 60 s
      now = now.add(const Duration(seconds: 10));
      async.elapse(const Duration(seconds: 20));
      expect(c.read(agentMarksProvider).tabActive(5, now), isFalse);
      expect(c.read(agentMarksProvider).tabs, isEmpty); // expired entries pruned
      now = now.add(const Duration(seconds: 60));
      c.read(agentMarksProvider.notifier).touch(tab: 5);
      expect(announced, [5, 5]);
      c.dispose();
    });
  });
}
```

`apps/desktop/test/cli/ui_command_handler_test.dart`:

```dart
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_desktop/src/cli/agent_marks.dart';
import 'package:shellx_desktop/src/cli/ui_command_handler.dart';
import 'package:shellx_desktop/src/terminal/sidebar_workspaces.dart';
import 'package:shellx_desktop/src/terminal/terminal_tabs.dart';

import 'support/cli_container.dart';
import '../support/fake_local_sessions.dart';

void main() {
  late ProviderContainer c;
  late FakeLocalSessions local;
  late UiCommandHandler h;

  Future<Map<String, Object?>> call(String t, [Map<String, Object?> f = const {}]) =>
      h.handle(MuxMessage(t, q: 1, fields: f));

  Matcher fails(String code) =>
      throwsA(isA<CliFailure>().having((e) => e.code, 'code', code));

  setUp(() async {
    local = FakeLocalSessions();
    c = cliContainer(local);
    addTearDown(c.dispose);
    h = c.read(uiCommandHandlerProvider);
    await c.read(terminalTabsProvider.notifier).openTab(); // user's tab 100
  });

  test('ls: workspaces → tabs → panes with ids and context', () async {
    final ls = await call('ui.ls');
    final ws = (ls['workspaces']! as List).single as Map;
    expect(ws['id'], 'default');
    expect(ws['current'], isTrue);
    final tab = (ws['tabs']! as List).single as Map;
    expect(tab['id'], 100);
    expect(tab['selected'], isTrue);
    final pane = (tab['panes']! as List).single as Map;
    expect([pane['id'], pane['kind'], pane['focused']], [100, 'terminal', true]);
    expect(ls['selectedTab'], 100);
    expect(ls['focusedPane'], 100);
  });

  test('new tab: not selected by default, in the named workspace, cwd passed', () async {
    final side = c.read(sidebarWorkspacesProvider.notifier);
    final ws = side.createFor(name: 'api');
    final r = await call('ui.tab.new', {'workspace': 'api', 'cwd': '/w'});
    expect(r['tab'], 101);
    expect(r['pane'], 101);
    expect(c.read(terminalTabsProvider).selectedId, 100);
    expect(c.read(sidebarWorkspacesProvider).workspaceOf(101), ws);
    expect(local.openCwds.last, '/w');
    expect(c.read(agentMarksProvider).tabs.keys, contains(101));
    final f = await call('ui.tab.new', {'focus': true});
    expect(c.read(terminalTabsProvider).selectedId, f['tab']);
  });

  test('split: any tab, right/down, keeps focus unless asked, passes tabId', () async {
    await call('ui.tab.new'); // tab 101, not selected
    final r = await call('ui.pane.split', {'pane': 101, 'direction': 'down'});
    expect(r, {'pane': 102, 'tab': 101});
    final tab = c.read(terminalTabsProvider).tabOfSession(102)!;
    expect(tab.focusedPaneId, 101); // D15: no focus change
    expect(c.read(terminalTabsProvider).selectedId, 100); // nor selection
    expect(local.openTabIds.last, 101);
    final f = await call('ui.pane.split', {'pane': '@focused', 'focus': true});
    expect(c.read(terminalTabsProvider).tabOfSession(f['pane']! as int)!.focusedPaneId, f['pane']);
    expect(() => call('ui.pane.split', {'pane': 101, 'direction': 'up'}), fails('bad_request'));
    expect(() => call('ui.pane.split', {'pane': 999}), fails('not_found'));
  });

  test('waits for an open in flight (D33), then busy after the limit', () async {
    local.openGate = Completer<void>();
    final userOpen = c.read(terminalTabsProvider.notifier).openTab();
    final cli = call('ui.tab.new');
    await Future<void>.delayed(const Duration(milliseconds: 120));
    local.openGate!.complete();
    await userOpen;
    expect((await cli)['tab'], isA<int>());
  });

  test('no room → no_room and no toast', () async {
    c.read(terminalTabsProvider.notifier).reportPaneMetrics(tinyPaneMetrics());
    expect(() => call('ui.pane.split', {'pane': 100}), fails('no_room'));
    expect(c.read(terminalTabsProvider).notice, isNull);
  });

  test('focus selects and focuses; tab target expands its workspace', () async {
    await call('ui.tab.new');
    await call('ui.pane.split', {'pane': 101});
    await call('ui.focus', {'pane': 101});
    final s = c.read(terminalTabsProvider);
    expect(s.selectedId, 101);
    expect(s.selected!.focusedPaneId, 101);
    await call('ui.focus', {'tab': 100});
    expect(c.read(terminalTabsProvider).selectedId, 100);
  });

  test('close: running command refused without force; pane vs tab', () async {
    await call('ui.pane.split', {'pane': 100}); // 101
    local.setRunning(101, true);
    expect(() => call('ui.close', {'pane': 101}), fails('running_command'));
    await call('ui.close', {'pane': 101, 'force': true});
    expect(local.closed, contains(101));
    expect(c.read(terminalTabsProvider).tabOfSession(100)!.paneCount, 1);
    await call('ui.close', {'tab': 100});
    expect(c.read(terminalTabsProvider).tabs, isEmpty);
  });

  test('rename tab and workspaces; move a tab', () async {
    await call('ui.tab.rename', {'tab': 100, 'name': '  build  '});
    expect(c.read(terminalTabsProvider).selected!.customTitle, 'build');
    await call('ui.tab.rename', {'tab': 100, 'name': ''});
    expect(c.read(terminalTabsProvider).selected!.customTitle, isNull);
    final w = await call('ui.workspace.new', {'name': 'web'});
    final wsId = w['workspace']! as String;
    expect(c.read(sidebarWorkspacesProvider).currentId, 'default'); // no focus
    expect(c.read(sidebarWorkspacesProvider).tabsOf(wsId), [w['tab']]);
    await call('ui.workspace.rename', {'workspace': 'web', 'name': 'frontend'});
    expect(c.read(sidebarWorkspacesProvider.notifier).displayName(wsId), 'frontend');
    await call('ui.workspace.move', {'tab': 100, 'workspace': wsId});
    expect(c.read(sidebarWorkspacesProvider).workspaceOf(100), wsId);
  });

  test('unknown ui type', () async {
    expect(() => call('ui.nope'), fails('unknown_type'));
  });
}
```

Add to `FakeLocalSessions` (if missing) `void setRunning(int id, bool running)` that replaces the summary's `runningCommand` and fires `changes`; add `PaneMetrics tinyPaneMetrics()` to `test/cli/support/cli_container.dart` returning metrics where a 20×5 split cannot fit (copy the construction used by A3's `no room` test in `terminal_tabs_panes_test.dart`).

Add to `apps/desktop/test/terminal/terminal_tabs_panes_test.dart`:

```dart
  test('A7 D29: a split opens with the tab id; a new tab with none', () async {
    await tabs.openTab();
    await tabs.split(SplitAxis.row);
    expect(local.openTabIds, [null, 100]);
  });
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/cli/ test/terminal/terminal_tabs_panes_test.dart`
Expected: FAIL — missing files/members.

- [ ] **Step 3: Implement**

`terminal_tabs.dart` — add above `TerminalTabs`:

```dart
/// A7 D33: another open is in flight.
final class OpenBusyException implements Exception {
  const OpenBusyException();
}

/// A3 D4 for a command-line split (no toast).
final class PaneNoRoomException implements Exception {
  const PaneNoRoomException();
}

/// The pane or the new shell is gone.
final class PaneGoneException implements Exception {
  const PaneGoneException();
}
```

Inside `TerminalTabs`, add and re-express:

```dart
  /// A7 D14: a tab for the command line, placed like any desktop tab (the
  /// current workspace) and **not** selected unless [select]. Returns its
  /// id. Throws [OpenBusyException], [SessionLimitException],
  /// [SpawnFailedException], [PaneGoneException].
  Future<int> openTabFor({String? cwd, bool select = false}) async {
    if (state.opening) throw const OpenBusyException();
    _set(opening: true);
    _awaitingOpen = true;
    var synced = false;
    try {
      final id = await _local.open(cols: _grid.cols, rows: _grid.rows, cwd: cwd);
      if (!ref.mounted) return id;
      _awaitingOpen = false;
      _sync();
      synced = true;
      final tab = state.tabOfSession(id);
      if (tab == null) throw const PaneGoneException();
      if (select) _set(selectedId: tab.id);
      return tab.id;
    } finally {
      _awaitingOpen = false;
      if (ref.mounted) {
        if (!synced) _sync();
        _set(opening: false);
      }
    }
  }

  /// A3 D3 for any pane of any tab (A7 D15). The new pane is focused only
  /// when [focus]; [cwd] defaults to the target's (A3 P4). Throws
  /// [OpenBusyException], [PaneNoRoomException], [PaneGoneException],
  /// [SessionLimitException], [SpawnFailedException].
  Future<int> splitPane(
    int target,
    SplitAxis axis, {
    String? cwd,
    bool focus = false,
  }) async {
    final tab = state.tabOfSession(target);
    final pane = tab?.panes[target];
    if (tab == null || pane == null) throw const PaneGoneException();
    if (state.opening) throw const OpenBusyException();
    if (!_roomToSplit(tab, target, axis)) throw const PaneNoRoomException();
    final grid = _halfGrid(pane, axis);
    _set(opening: true);
    _awaitingOpen = true;
    var synced = false;
    try {
      final id = await _local.open(
        cols: grid.cols,
        rows: grid.rows,
        cwd: cwd ?? pane.cwd,
        tabId: tab.id,
      );
      if (!ref.mounted) return id;
      _awaitingOpen = false;
      _adoptPane(id, tabId: tab.id, target: target, axis: axis, size: grid);
      synced = true;
      if (!focus && state.tabOfSession(target) != null) focusPane(target);
      return id;
    } finally {
      _awaitingOpen = false;
      if (ref.mounted) {
        if (!synced) _sync();
        _set(opening: false);
      }
    }
  }
```

Replace the body of the A3 `split(SplitAxis axis)` with:

```dart
  Future<void> split(SplitAxis axis) async {
    final tab = state.selected;
    if (tab == null || state.opening) return;
    try {
      await splitPane(tab.focusedPaneId, axis, focus: true);
    } on PaneNoRoomException {
      if (ref.mounted) _set(notice: const PaneNoRoomNotice());
    } on SessionLimitException catch (error) {
      if (ref.mounted) _set(notice: SessionLimitNotice(error.max));
    } on SpawnFailedException catch (error) {
      if (ref.mounted) {
        _set(notice: SpawnFailedNotice(spawnFailureOf(error.message)));
      }
    } on PaneGoneException {
      // The pane ended meanwhile: nothing to split.
    }
  }
```

(`focusPane(target)` used by `splitPane` must not re-select the tab; it only changes the tab's focused pane — confirmed by A3's `focusPane`, which calls `_replaceTab` only. If A6 changed `focusPane` to also select the tab, add a private `_focusWithinTab(tabId, paneId)` that updates `focusedPaneId`/`paneHistory` without touching `selectedId`, and call it here instead.)

`sidebar_workspaces.dart`:

```dart
  /// A7 D22: a workspace for the command line — appended, saved, not
  /// current, no rename field. Returns its id.
  String createFor({String? name}) {
    final id = _newId();
    final clean = name?.trim() ?? '';
    state = state.copyWith(
      workspaces: [
        ...state.workspaces,
        Workspace(id: id, name: clean.isEmpty ? _numberedName() : _clip(clean)),
      ],
      members: {...state.members, id: const <int>[]},
    );
    _save();
    return id;
  }
```

`cli_targets.dart`:

```dart
import '../terminal/sidebar_workspaces.dart';
import '../terminal/terminal_tabs.dart';
import 'package:shellx_agent/shellx_agent.dart';

sealed class CliTarget {
  const CliTarget();
}

final class PaneRef extends CliTarget {
  const PaneRef(this.id);
  final int id;
}

final class TabRef extends CliTarget {
  const TabRef(this.id);
  final int id;
}

final class FocusedRef extends CliTarget {
  const FocusedRef();
}

const _focused = '@focused';

CliFailure _bad(String m) => CliFailure('bad_request', m);

/// D12 on the wire: exactly one of `pane`/`tab`, an int id or "@focused".
CliTarget parseTarget(Object? pane, Object? tab) {
  if ((pane == null) == (tab == null)) throw _bad('give exactly one pane or tab');
  final v = pane ?? tab;
  if (v == _focused) return const FocusedRef();
  if (v is! int) throw _bad('a target is an id or @focused');
  return pane != null ? PaneRef(v) : TabRef(v);
}

int resolvePane(TerminalTabsState s, CliTarget t) {
  switch (t) {
    case FocusedRef():
      final tab = s.selected;
      if (tab == null) throw const CliFailure('not_found', 'no tab is selected');
      return tab.focusedPaneId;
    case PaneRef(:final id):
      if (s.tabOfSession(id)?.panes.containsKey(id) ?? false) return id;
      throw CliFailure('not_found', 'no pane p$id');
    case TabRef(:final id):
      final tab = s.tabs.where((x) => x.id == id).firstOrNull;
      if (tab == null) throw CliFailure('not_found', 'no tab t$id');
      return tab.focusedPaneId;
  }
}

int resolveTab(TerminalTabsState s, CliTarget t) {
  switch (t) {
    case FocusedRef():
      return s.selected?.id ?? (throw const CliFailure('not_found', 'no tab is selected'));
    case TabRef(:final id):
      if (s.tabs.any((x) => x.id == id)) return id;
      throw CliFailure('not_found', 'no tab t$id');
    case PaneRef(:final id):
      return s.tabOfSession(id)?.id ?? (throw CliFailure('not_found', 'no pane p$id'));
  }
}

String resolveWorkspace(
  SidebarState s,
  String key,
  String Function(String id) displayName,
) {
  final k = key.startsWith('w:') ? key.substring(2) : key;
  if (s.workspace(k) != null) return k;
  final lower = k.toLowerCase();
  final hits = [
    for (final w in s.workspaces)
      if (displayName(w.id).toLowerCase() == lower) w.id,
  ];
  if (hits.length == 1) return hits.single;
  if (hits.isEmpty) throw CliFailure('not_found', 'no workspace "$key"');
  throw CliFailure('ambiguous', '${hits.length} workspaces are named "$key"; use w:<id> (shellx ls)');
}
```

`agent_marks.dart`:

```dart
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const kAgentMarkFor = Duration(seconds: 10);
const kAgentAnnounceGap = Duration(seconds: 60);

final agentMarksClockProvider = Provider<DateTime Function()>((_) => DateTime.now);

@immutable
final class AgentMarksState {
  const AgentMarksState({this.tabs = const {}, this.panes = const {}});

  /// Last command per tab / pane.
  final Map<int, DateTime> tabs;
  final Map<int, DateTime> panes;

  bool tabActive(int id, DateTime now) => _active(tabs[id], now);
  bool paneActive(int id, DateTime now) => _active(panes[id], now);
  static bool _active(DateTime? at, DateTime now) =>
      at != null && now.difference(at) < kAgentMarkFor;
}

final agentMarksProvider = NotifierProvider<AgentMarks, AgentMarksState>(AgentMarks.new);

/// A7 D27: the "Agent" chip on the tab row and pane header for 10 s after
/// the last command-line action on them; one announcement per 60 s.
class AgentMarks extends Notifier<AgentMarksState> {
  Timer? _expiry;
  DateTime? _lastAnnounce;

  /// Set by the UI (Task 9): `SemanticsService.announce` with the tab label.
  void Function(int tabId)? onAnnounce;

  DateTime get _now => ref.read(agentMarksClockProvider)();

  @override
  AgentMarksState build() {
    ref.onDispose(() => _expiry?.cancel());
    return const AgentMarksState();
  }

  void touch({required int tab, int? pane}) {
    final now = _now;
    state = AgentMarksState(
      tabs: {...state.tabs, tab: now},
      panes: {...state.panes, if (pane != null) pane: now},
    );
    final last = _lastAnnounce;
    if (last == null || now.difference(last) >= kAgentAnnounceGap) {
      _lastAnnounce = now;
      onAnnounce?.call(tab);
    }
    _expiry?.cancel();
    _expiry = Timer(kAgentMarkFor, _prune);
  }

  void _prune() {
    final now = _now;
    state = AgentMarksState(
      tabs: {
        for (final e in state.tabs.entries)
          if (AgentMarksState._active(e.value, now)) e.key: e.value,
      },
      panes: {
        for (final e in state.panes.entries)
          if (AgentMarksState._active(e.value, now)) e.key: e.value,
      },
    );
    if (state.tabs.isNotEmpty || state.panes.isNotEmpty) {
      _expiry = Timer(const Duration(seconds: 1), _prune);
    }
  }
}
```

`ui_command_handler.dart`:

```dart
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shellx_agent/shellx_agent.dart';

import '../browser/browser_commands.dart';
import '../browser/browser_host.dart';
import '../terminal/local_sessions_provider.dart';
import '../terminal/sidebar_workspaces.dart';
import '../terminal/tab_attention.dart';
import '../terminal/terminal_tabs.dart';
import 'agent_marks.dart';
import 'cli_targets.dart';

final uiCommandHandlerProvider = Provider<UiCommandHandler>(
  (ref) => UiCommandHandler(ref),
);

CliFailure _bad(String m) => CliFailure('bad_request', m);

/// A7 §3.3: every `ui.*` request, for the in-UI host and (after A5b) for
/// requests the daemon forwards.
final class UiCommandHandler implements UiApi {
  UiCommandHandler(
    this._ref, {
    this.openWait = const Duration(seconds: 10),
  });

  final Ref _ref;
  final Duration openWait;

  /// The current request's client-gone signal (requests on one connection
  /// are serial, D32; the daemon path passes none).
  Future<void>? _cancelled;

  TerminalTabs get _tabs => _ref.read(terminalTabsProvider.notifier);
  TerminalTabsState get _tabsState => _ref.read(terminalTabsProvider);
  SidebarWorkspaces get _side => _ref.read(sidebarWorkspacesProvider.notifier);
  SidebarState get _sideState => _ref.read(sidebarWorkspacesProvider);
  AgentMarks get _marks => _ref.read(agentMarksProvider.notifier);

  @override
  Future<Map<String, Object?>> handle(MuxMessage r, {Future<void>? cancelled}) async {
    _cancelled = cancelled;
    final t = r.type;
    if (t.startsWith(CliType.uiBrowserPrefix)) return _browser(r);
    return switch (t) {
      CliType.uiLs => _ls(),
      CliType.uiTabNew => _tabNew(r),
      CliType.uiTabRename => _tabRename(r),
      CliType.uiPaneSplit => _split(r),
      CliType.uiFocus => _focus(r),
      CliType.uiClose => _close(r),
      CliType.uiWorkspaceNew => _workspaceNew(r),
      CliType.uiWorkspaceRename => _workspaceRename(r),
      CliType.uiWorkspaceMove => _workspaceMove(r),
      // Task 7: ui.pane.send / read / wait. Task 8: ui.events.subscribe.
      _ => throw CliFailure(MuxError.unknownType, 'unknown request $t'),
    };
  }

  // ---- helpers ----------------------------------------------------------

  String? _string(MuxMessage r, String k, {int max = 4096}) {
    final v = r.fields[k];
    if (v == null) return null;
    if (v is! String || v.length > max) throw _bad('$k must be text ≤ $max');
    return v;
  }

  bool _flag(MuxMessage r, String k) => r.fields[k] == true;

  /// D33: wait for an open in flight, polling every 50 ms up to [openWait].
  Future<T> _opening<T>(Future<T> Function() open) async {
    final deadline = DateTime.now().add(openWait);
    while (true) {
      try {
        return await open();
      } on OpenBusyException {
        if (DateTime.now().isAfter(deadline)) {
          throw const CliFailure('busy', 'ShellX is opening another shell; try again');
        }
        await Future<void>.delayed(const Duration(milliseconds: 50));
      } on PaneNoRoomException {
        throw const CliFailure(CliError.noRoom, 'not enough room to split this pane');
      } on PaneGoneException {
        throw const CliFailure('not_found', 'the pane ended');
      } on SessionLimitException catch (e) {
        throw CliFailure('session_limit', 'ShellX already has ${e.max} shells');
      } on SpawnFailedException {
        throw const CliFailure('spawn_failed', 'the shell could not start');
      }
    }
  }

  // ---- ls ---------------------------------------------------------------

  Future<Map<String, Object?>> _ls() async {
    final tabs = _tabsState;
    final side = _sideState;
    final unread = _ref.read(tabAttentionProvider).unread;
    final marks = _ref.read(agentMarksProvider);
    final now = _ref.read(agentMarksClockProvider)();
    final browsers = <int, List<Map<String, Object?>>>{};
    try {
      final list = await _ref.read(browserCommandHandlerProvider).handle({'t': 'ui.browser.list'});
      for (final p in (list['panes'] as List?) ?? const []) {
        final m = p as Map<String, Object?>;
        (browsers[m['tab']! as int] ??= []).add({
          'id': m['pane'],
          'kind': 'browser',
          'title': m['title'],
          'url': m['url'],
          'loading': m['loading'],
          'focused': false,
        });
      }
    } on Object {
      // A6 absent or failing: terminal panes only.
    }
    Map<String, Object?> tabMap(TerminalTab tab) => {
      'id': tab.id,
      'title': tab.label,
      'custom': tab.customTitle != null,
      'selected': tab.id == tabs.selectedId,
      'unread': unread[tab.id]?.count ?? 0,
      'running': tab.panes.values.any((p) => !p.exited && p.runningCommand),
      'agent': marks.tabActive(tab.id, now),
      'panes': [
        for (final id in tab.paneOrder)
          if (tab.panes[id] case final p?)
            {
              'id': p.id,
              'kind': 'terminal',
              'title': p.automaticLabel,
              'cwd': p.cwd,
              'branch': p.gitBranch,
              'ports': p.ports,
              'running': !p.exited && p.runningCommand,
              'exited': p.exited,
              'exitCode': p.exitCode,
              'focused': id == tab.focusedPaneId,
              'zoomed': id == tab.zoomedPaneId,
              'phone': p.phoneAttached,
              'driver': p.driver.name,
            },
        ...?browsers[tab.id],
      ],
    };
    return {
      'workspaces': [
        for (final w in side.workspaces)
          {
            'id': w.id,
            'name': _side.displayName(w.id),
            'current': w.id == side.currentId,
            'collapsed': w.collapsed,
            'tabs': [
              for (final id in side.tabsOf(w.id))
                if (tabs.tabs.where((t) => t.id == id).firstOrNull case final tab?)
                  tabMap(tab),
            ],
          },
      ],
      'selectedTab': tabs.selectedId,
      'focusedPane': tabs.selected?.focusedPaneId,
    };
  }

  // ---- tabs and panes ---------------------------------------------------

  Future<Map<String, Object?>> _tabNew(MuxMessage r) async {
    final wsKey = _string(r, 'workspace');
    final ws = wsKey == null ? null : resolveWorkspace(_sideState, wsKey, _side.displayName);
    final cwd = _string(r, 'cwd');
    final cmd = _string(r, 'cmd', max: 16384);
    final select = _flag(r, 'focus');
    final tab = await _opening(() => _tabs.openTabFor(cwd: cwd, select: select));
    if (ws != null) _side.moveTab(tab, ws);
    if (select) _side.reveal(tab);
    _marks.touch(tab: tab, pane: tab);
    if (cmd != null) _runWhenReady(tab, cmd);
    return {'tab': tab, 'pane': tab};
  }

  Future<Map<String, Object?>> _split(MuxMessage r) async {
    final target = resolvePane(_tabsState, parseTarget(r.fields['pane'], null));
    final axis = switch (r.fields['direction'] ?? 'right') {
      'right' => SplitAxis.row,
      'down' => SplitAxis.column,
      _ => throw _bad('direction is right or down'),
    };
    final cmd = _string(r, 'cmd', max: 16384);
    final pane = await _opening(
      () => _tabs.splitPane(target, axis, cwd: _string(r, 'cwd'), focus: _flag(r, 'focus')),
    );
    final tab = _tabsState.tabOfSession(pane)?.id ?? _tabsState.tabOfSession(target)!.id;
    _marks.touch(tab: tab, pane: pane);
    if (cmd != null) _runWhenReady(pane, cmd);
    return {'pane': pane, 'tab': tab};
  }

  /// D16 — implemented in Task 7 (`CommandInjector`); until then a no-op.
  void _runWhenReady(int pane, String cmd) => onCommand?.call(pane, cmd);

  /// Task 7 sets this to `CommandInjector.inject`.
  void Function(int pane, String cmd)? onCommand;

  Future<Map<String, Object?>> _focus(MuxMessage r) async {
    final target = parseTarget(r.fields['pane'], r.fields['tab']);
    final s = _tabsState;
    final tab = resolveTab(s, target);
    _tabs.select(tab);
    _side.reveal(tab);
    if (target is PaneRef || target is FocusedRef) {
      _tabs.focusPane(resolvePane(s, target));
    }
    if (_flag(r, 'raise')) await onRaise?.call();
    _marks.touch(tab: tab, pane: target is PaneRef ? target.id : null);
    return const {};
  }

  /// Task 9 sets this to the A1 D11 activation (show + focus the window).
  Future<void> Function()? onRaise;

  Future<Map<String, Object?>> _close(MuxMessage r) async {
    final target = parseTarget(r.fields['pane'], r.fields['tab']);
    final force = _flag(r, 'force');
    final s = _tabsState;
    if (target is TabRef) {
      final tab = resolveTab(s, target);
      if (!force && _tabs.needsCloseConfirm(tab)) {
        throw const CliFailure(CliError.runningCommand, 'a command is running; use --force');
      }
      _marks.touch(tab: tab);
      _tabs.close(tab);
      return const {};
    }
    final pane = resolvePane(s, target);
    if (!force && _tabs.needsPaneCloseConfirm(pane)) {
      throw const CliFailure(CliError.runningCommand, 'a command is running; use --force');
    }
    _marks.touch(tab: s.tabOfSession(pane)!.id, pane: pane);
    _tabs.closePane(pane);
    return const {};
  }

  Future<Map<String, Object?>> _tabRename(MuxMessage r) async {
    final tab = resolveTab(_tabsState, parseTarget(null, r.fields['tab']));
    _tabs.rename(tab, _string(r, 'name', max: 1024) ?? '');
    _marks.touch(tab: tab);
    return const {};
  }

  // ---- workspaces -------------------------------------------------------

  Future<Map<String, Object?>> _workspaceNew(MuxMessage r) async {
    final ws = _side.createFor(name: _string(r, 'name', max: 1024));
    final focus = _flag(r, 'focus');
    final tab = await _opening(() => _tabs.openTabFor(select: focus));
    _side.moveTab(tab, ws);
    if (focus) _side.reveal(tab);
    _marks.touch(tab: tab, pane: tab);
    return {'workspace': ws, 'tab': tab};
  }

  Future<Map<String, Object?>> _workspaceRename(MuxMessage r) async {
    final key = _string(r, 'workspace') ?? (throw _bad('workspace is required'));
    final ws = resolveWorkspace(_sideState, key, _side.displayName);
    final name = _string(r, 'name', max: 1024) ?? '';
    if (name.trim().isEmpty) throw _bad('a workspace name cannot be empty');
    _side.rename(ws, name);
    return const {};
  }

  Future<Map<String, Object?>> _workspaceMove(MuxMessage r) async {
    final tab = resolveTab(_tabsState, parseTarget(null, r.fields['tab']));
    final key = _string(r, 'workspace') ?? (throw _bad('workspace is required'));
    _side.moveTab(tab, resolveWorkspace(_sideState, key, _side.displayName));
    _marks.touch(tab: tab);
    return const {};
  }

  // ---- browser (Task 8 completes) ---------------------------------------

  Future<Map<String, Object?>> _browser(MuxMessage r) async =>
      throw CliFailure(MuxError.unknownType, 'unknown request ${r.type}');

  // ---- UiApi members completed in Task 8 --------------------------------

  @override
  Stream<Map<String, Object?>> events() => const Stream.empty();

  @override
  Future<void> notifyApp({String? title, required String body}) async {}

  @override
  bool notifyPane(int pane, {String? title, required String body}) =>
      _ref.read(localSessionsProvider).notify(pane, title: title, body: body);
}
```

(`moveTab(tab, ws)` puts the tab at the end of `ws` — A2 D18 default index. `PaneSession.automaticLabel` exists in A3's `terminal_tabs.dart`; if A6 renamed it, use the pane title getter A3 D15's header shows.)

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test`
Expected: PASS (whole desktop suite: A3 split behavior unchanged).

- [ ] **Step 5: Format, analyze, commit**

```bash
cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH dart format --set-exit-if-changed lib test && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter analyze && cd ../..
git add apps/desktop/lib/src/cli/cli_targets.dart apps/desktop/lib/src/cli/agent_marks.dart apps/desktop/lib/src/cli/ui_command_handler.dart apps/desktop/lib/src/terminal/terminal_tabs.dart apps/desktop/lib/src/terminal/sidebar_workspaces.dart apps/desktop/test/cli/cli_targets_test.dart apps/desktop/test/cli/agent_marks_test.dart apps/desktop/test/cli/ui_command_handler_test.dart apps/desktop/test/cli/support/cli_container.dart apps/desktop/test/terminal/terminal_tabs_panes_test.dart apps/desktop/test/support/fake_local_sessions.dart
git commit -m "feat(desktop): ui.* tabs, splits, focus, close, rename, workspaces and ls for the command line; Agent marks (A7 D12-D15, D17, D18, D22, D27, D33)"
```

---

### Task 7: Desktop — `send`, `read`, `wait`, `--cmd` (D16, D19, D20, D21)

**Files:**
- Create: `apps/desktop/lib/src/cli/pane_text.dart`, `apps/desktop/lib/src/cli/pane_waiter.dart`
- Modify: `apps/desktop/lib/src/cli/ui_command_handler.dart`, `apps/desktop/lib/src/restore/scrollback_codec.dart` (public `encodeLogicalLines`), `apps/desktop/lib/src/terminal/terminal_tabs.dart` (`paneOutput(int id)` stream, if A5a did not already add a per-pane output event)
- Test: `apps/desktop/test/cli/pane_text_test.dart`, `apps/desktop/test/cli/pane_waiter_test.dart`, `apps/desktop/test/cli/ui_command_handler_send_test.dart`

**Interfaces:**
- Consumes: `DesktopTerminal` (`paste`, `keyInput`, `charInput`, `buffer`, `mainBuffer`, `isUsingAltBuffer`, `viewHeight`), xterm `BufferLine` (`getText`, `isWrapped`, `getTrimmedLength`), `TerminalKey`; A5a `encodeScrollback` internals; A5a "pane output events" (A5a Task 4 added them for dirty tracking — reuse that stream; otherwise add `Stream<int> paneOutput` that emits the pane id whenever its feed writes).
- Produces:
  - `pane_text.dart`: `const kReadPageBytes = 49152; const kReadMaxLines = 10000;` `List<String> logicalLines(Buffer buffer, {int? last, int? fromRow})` (soft-wrapped rows joined; trailing blank rows dropped); `String screenText(Terminal t)`; `({String text, int? next}) readPage(Terminal t, {int? lines, bool ansi = false, int offset = 0})` (UTF-8 byte pages ≤ `kReadPageBytes`, never splitting a line unless one line exceeds a page); `int cursorRow(Terminal t)` (absolute row of the cursor in the active buffer).
  - `pane_waiter.dart`: `sealed class WaitOutcome`; `Future<Map<String, Object?>> waitIdle(PaneProbe p, {Duration quiet, Duration timeout})`, `waitExit(PaneProbe p, {Duration timeout})`, `waitMatch(PaneProbe p, RegExp re, {bool fromNow, Duration timeout})`; `abstract interface class PaneProbe { bool get hooked; bool get running; bool get exited; int? get exitCode; Stream<void> get output; Stream<void> get changes; Terminal get terminal; }`; `final class CommandInjector { CommandInjector(PaneProbe Function(int pane) probe, void Function(int pane, String text) paste); void inject(int pane, String cmd); }` (D16 readiness).
  - `ui_command_handler.dart`: handles `ui.pane.send`, `ui.pane.read`, `ui.pane.wait`; wires `onCommand` to a `CommandInjector`.
  - `scrollback_codec.dart`: `String encodeLogicalLines(List<BufferLine> rows, int start, int end)` (the former private `_encodeRows`, made public; `encodeScrollback` calls it).

- [ ] **Step 1: Write the failing tests**

`apps/desktop/test/cli/pane_text_test.dart`:

```dart
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/cli/pane_text.dart';
import 'package:xterm/xterm.dart';

Terminal term(String output, {int cols = 10, int rows = 4}) =>
    Terminal(maxLines: 1000)..resize(cols, rows)..write(output);

void main() {
  test('screen text: visible rows, wrapped rows joined, trailing blanks dropped', () {
    final t = term('one\r\ntwo\r\n0123456789abc\r\n');
    expect(screenText(t), 'two\n0123456789abc\n');
  });

  test('--lines reaches into the scrollback', () {
    final t = term([for (var i = 0; i < 20; i++) 'line $i'].join('\r\n'));
    expect(readPage(t, lines: 3).text, 'line 17\nline 18\nline 19\n');
    expect(readPage(t, lines: 100).text.split('\n').first, 'line 0');
  });

  test('alt screen: the screen is what vim shows', () {
    final t = term('shell\r\n\x1b[?1049h\x1b[Hvim here');
    expect(screenText(t), 'vim here\n');
  });

  test('--ansi keeps SGR only, never title or clipboard sequences', () {
    final t = term('\x1b]0;title\x07\x1b[31mred\x1b[0m ok\x1b]52;c;aGk=\x07', cols: 20);
    final text = readPage(t, lines: 5, ansi: true).text;
    expect(text, contains('\x1b[31m'));
    expect(text, isNot(contains(']0;')));
    expect(text, isNot(contains(']52;')));
  });

  test('pages are ≤ 48 KiB of UTF-8 and chain with next', () {
    final line = 'é' * 300; // 600 bytes
    final t = Terminal(maxLines: 10000)..resize(400, 5);
    for (var i = 0; i < 200; i++) {
      t.write('$line\r\n');
    }
    final first = readPage(t, lines: 200);
    expect(utf8.encode(first.text).length, lessThanOrEqualTo(kReadPageBytes));
    expect(first.next, isNotNull);
    final rest = readPage(t, lines: 200, offset: first.next!);
    expect('${first.text}${rest.text}'.split('\n').where((l) => l.isNotEmpty).length, 200);
    expect(rest.next, isNull);
  });
}
```

`apps/desktop/test/cli/pane_waiter_test.dart`:

```dart
import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/cli/pane_waiter.dart';
import 'package:xterm/xterm.dart';

final class FakeProbe implements PaneProbe {
  @override
  bool hooked = true;
  @override
  bool running = true;
  @override
  bool exited = false;
  @override
  int? exitCode;
  final out = StreamController<void>.broadcast(sync: true);
  final ch = StreamController<void>.broadcast(sync: true);
  @override
  Stream<void> get output => out.stream;
  @override
  Stream<void> get changes => ch.stream;
  @override
  final Terminal terminal = Terminal(maxLines: 1000)..resize(40, 5);
  void print(String s) {
    terminal.write(s);
    out.add(null);
  }
}

void main() {
  test('idle: prompt back and quiet for 500 ms', () {
    fakeAsync((async) {
      final p = FakeProbe();
      Map<String, Object?>? r;
      waitIdle(p, quiet: const Duration(milliseconds: 500), timeout: const Duration(seconds: 30))
          .then((v) => r = v);
      async.elapse(const Duration(seconds: 2));
      expect(r, isNull); // still running
      p.running = false;
      p.ch.add(null);
      async.elapse(const Duration(milliseconds: 400));
      p.print('x');
      async.elapse(const Duration(milliseconds: 400));
      expect(r, isNull); // output reset the quiet timer
      async.elapse(const Duration(milliseconds: 150));
      expect(r, isNotNull);
    });
  });

  test('idle without hooks: 2 s of silence', () {
    fakeAsync((async) {
      final p = FakeProbe()..hooked = false;
      Map<String, Object?>? r;
      waitIdle(p, quiet: const Duration(milliseconds: 500), timeout: const Duration(seconds: 30))
          .then((v) => r = v);
      async.elapse(const Duration(milliseconds: 1900));
      expect(r, isNull);
      async.elapse(const Duration(milliseconds: 200));
      expect(r, isNotNull);
    });
  });

  test('exit returns the code; timeout fails with timeout', () {
    fakeAsync((async) {
      final p = FakeProbe();
      Map<String, Object?>? r;
      waitExit(p, timeout: const Duration(seconds: 5)).then((v) => r = v);
      p.exited = true;
      p.exitCode = 3;
      p.ch.add(null);
      async.flushMicrotasks();
      expect(r, {'exitCode': 3});
      Object? err;
      waitExit(FakeProbe(), timeout: const Duration(seconds: 5)).catchError((Object e) {
        err = e;
        return <String, Object?>{};
      });
      async.elapse(const Duration(seconds: 6));
      expect(err, isA<CliFailure>().having((f) => f.code, 'code', 'timeout'));
    });
  });

  test('match: existing text counts unless fromNow; later output matches', () {
    fakeAsync((async) {
      final p = FakeProbe()..print('Serving HTTP on 0.0.0.0\r\n');
      Map<String, Object?>? old;
      waitMatch(p, RegExp('Serving HTTP', multiLine: true), fromNow: false, timeout: const Duration(seconds: 5))
          .then((v) => old = v);
      async.elapse(const Duration(milliseconds: 150));
      expect(old!['match'], 'Serving HTTP');
      Map<String, Object?>? fresh;
      waitMatch(p, RegExp(r'ready in \d+', multiLine: true), fromNow: true, timeout: const Duration(seconds: 5))
          .then((v) => fresh = v);
      async.elapse(const Duration(milliseconds: 150));
      expect(fresh, isNull);
      p.print('ready in 42 ms\r\n');
      async.elapse(const Duration(milliseconds: 150));
      expect(fresh!['match'], 'ready in 42');
      expect(fresh!['line'], 'ready in 42 ms');
    });
  });

  test('a client that goes away ends the wait at once (D21)', () {
    fakeAsync((async) {
      final gone = Completer<void>();
      Object? err;
      final timers = async.pendingTimers.length;
      waitIdle(FakeProbe(), quiet: const Duration(milliseconds: 500),
              timeout: const Duration(minutes: 60), cancelled: gone.future)
          .catchError((Object e) {
        err = e;
        return <String, Object?>{};
      });
      gone.complete();
      async.flushMicrotasks();
      expect(err, isA<CliFailure>().having((f) => f.code, 'code', 'cancelled'));
      expect(async.pendingTimers.length, timers); // the 60-minute timer is gone
    });
  });

  test('a pane that exits fails idle/match with exited', () {
    fakeAsync((async) {
      final p = FakeProbe();
      Object? err;
      waitMatch(p, RegExp('never'), fromNow: false, timeout: const Duration(seconds: 5))
          .catchError((Object e) {
        err = e;
        return <String, Object?>{};
      });
      p.exited = true;
      p.ch.add(null);
      async.elapse(const Duration(milliseconds: 150));
      expect(err, isA<CliFailure>().having((f) => f.code, 'code', 'exited'));
    });
  });

  test('CommandInjector: pastes after the first cwd report, or after quiet', () {
    fakeAsync((async) {
      final p = FakeProbe()..hooked = false;
      final pasted = <(int, String)>[];
      final inj = CommandInjector((_) => p, (pane, text) => pasted.add((pane, text)));
      inj.inject(7, 'npm run dev');
      p.print('Last login…\r\n');
      async.elapse(const Duration(milliseconds: 1400));
      expect(pasted, isEmpty);
      async.elapse(const Duration(milliseconds: 200)); // 1.5 s quiet
      expect(pasted, [(7, 'npm run dev')]);

      final q = FakeProbe()..hooked = false;
      final pasted2 = <String>[];
      CommandInjector((_) => q, (_, t) => pasted2.add(t)).inject(8, 'ls');
      q.hooked = true; // first OSC 7
      q.ch.add(null);
      async.flushMicrotasks();
      expect(pasted2, ['ls']);

      final r = FakeProbe()..hooked = false;
      final pasted3 = <String>[];
      CommandInjector((_) => r, (_, t) => pasted3.add(t)).inject(9, 'x');
      for (var i = 0; i < 10; i++) {
        r.print('.');
        async.elapse(const Duration(milliseconds: 500));
      }
      expect(pasted3, ['x']); // 5 s cap
    });
  });
}
```

`apps/desktop/test/cli/ui_command_handler_send_test.dart`:

```dart
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_desktop/src/cli/ui_command_handler.dart';
import 'package:shellx_desktop/src/terminal/terminal_tabs.dart';

import 'support/cli_container.dart';
import '../support/fake_local_sessions.dart';

void main() {
  late ProviderContainer c;
  late FakeLocalSessions local;
  late UiCommandHandler h;

  Future<Map<String, Object?>> call(String t, Map<String, Object?> f) =>
      h.handle(MuxMessage(t, q: 1, fields: f));
  String written(int id) => utf8.decode(local.views[id]!.written.expand((b) => b).toList());
  Matcher fails(String code) => throwsA(isA<CliFailure>().having((e) => e.code, 'code', code));

  setUp(() async {
    local = FakeLocalSessions();
    c = cliContainer(local);
    addTearDown(c.dispose);
    h = c.read(uiCommandHandlerProvider);
    await c.read(terminalTabsProvider.notifier).openTab(); // 100
  });

  test('text is a paste: controls stripped, LF → CR, Enter after', () async {
    await call('ui.pane.send', {'pane': 100, 'text': 'echo a\necho \x1b[201~b', 'enter': true});
    expect(written(100), 'echo a\recho [201~b\r');
  });

  test('bracketed paste when the shell asked for it', () async {
    local.emit(100, '\x1b[?2004h');
    await pumpFeed(); // let TerminalFeed write into the pane's terminal
    await call('ui.pane.send', {'pane': 100, 'text': 'ls'});
    expect(written(100), '\x1b[200~ls\x1b[201~');
  });

  test('keys', () async {
    await call('ui.pane.send', {'pane': 100, 'keys': ['ctrl-c', 'up', 'enter', 'tab', 'esc']});
    expect(written(100), '\x03\x1b[A\r\t\x1b');
    expect(() => call('ui.pane.send', {'pane': 100, 'keys': ['hyper-x']}), fails('bad_request'));
  });

  test('size limit, empty send, exited pane', () async {
    expect(() => call('ui.pane.send', {'pane': 100, 'text': 'x' * 49153}), fails('bad_request'));
    expect(() => call('ui.pane.send', {'pane': 100}), fails('bad_request'));
    local.exit(100, 1);
    await pumpFeed();
    expect(() => call('ui.pane.send', {'pane': 100, 'text': 'x'}), fails('exited'));
  });

  test('read pages through ui.pane.read', () async {
    local.emit(100, 'hello\r\nworld\r\n');
    await pumpFeed();
    final r = await call('ui.pane.read', {'pane': 100});
    expect(r['text'], 'hello\nworld\n');
    expect(r.containsKey('next'), isFalse);
    expect(() => call('ui.pane.read', {'pane': 100, 'lines': 0}), fails('bad_request'));
    expect(() => call('ui.pane.read', {'pane': 100, 'lines': 10001}), fails('bad_request'));
  });

  test('wait match with a bad regex is bad_request', () async {
    expect(() => call('ui.pane.wait', {'pane': 100, 'mode': 'match', 'pattern': '(', 'timeoutMs': 1000}),
        fails('bad_request'));
    expect(() => call('ui.pane.wait', {'pane': 100, 'mode': 'idle', 'timeoutMs': 3600001}),
        fails('bad_request'));
  });
}
```

`pumpFeed()`, `FakeSessionView.written`, `FakeLocalSessions.emit`/`exit` — use the helpers the A1/A3 tests already use to push output into a pane and to see what the view wrote (names in `test/support/fake_local_sessions.dart`; if `pumpFeed` does not exist, it is `await Future<void>.delayed(const Duration(milliseconds: 20))` — `TerminalFeed` flushes per frame/microtask). Put `pumpFeed` in `test/cli/support/cli_container.dart`.

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/cli/pane_text_test.dart test/cli/pane_waiter_test.dart test/cli/ui_command_handler_send_test.dart`
Expected: FAIL — missing files.

- [ ] **Step 3: Implement**

`scrollback_codec.dart`: rename `_encodeRows(dynamic lines, int start, int end)` to `String encodeLogicalLines(List<BufferLine> rows, int start, int end)` (typed; body unchanged) with a doc comment "Rows [start]..[end] of one logical line (soft-wrapped rows joined) as printable text + SGR (A5a D5). A7 `read --ansi` uses it too." and update its caller in `encodeScrollback`. If `terminal.mainBuffer.lines` is an `IndexAwareCircularBuffer<BufferLine>` rather than a `List`, accept that type (`IndexAwareCircularBuffer<BufferLine>`) in the signature instead — whatever `encodeScrollback` passes today.

`pane_text.dart`:

```dart
import 'dart:convert';

import 'package:xterm/xterm.dart';

import '../restore/scrollback_codec.dart';

const kReadPageBytes = 49152;
const kReadMaxLines = 10000;

/// One logical line per entry (soft-wrapped rows joined), oldest first.
/// [fromRow]: start at this absolute row (it is moved back to the start of
/// its logical line). [last]: keep only the last N. Trailing blank rows are
/// dropped. [ansi]: SGR re-encoded from the cells (A5a D5).
List<String> logicalLines(
  Buffer buffer, {
  int? last,
  int? fromRow,
  bool ansi = false,
}) {
  final rows = buffer.lines;
  var end = rows.length - 1;
  while (end >= 0 &&
      rows[end].getTrimmedLength() == 0 &&
      (end + 1 >= rows.length || !rows[end + 1].isWrapped)) {
    end--;
  }
  var first = fromRow ?? 0;
  while (first > 0 && first < rows.length && rows[first].isWrapped) {
    first--;
  }
  final out = <String>[];
  var i = end;
  while (i >= first && (last == null || out.length < last)) {
    var start = i;
    while (start > first && rows[start].isWrapped) {
      start--;
    }
    out.add(ansi
        ? encodeLogicalLines(rows, start, i)
        : [for (var r = start; r <= i; r++) rows[r].getText()].join().trimRight());
    i = start - 1;
  }
  return out.reversed.toList();
}

/// D20: the screen of the buffer in use (alt screen while vim runs).
String screenText(Terminal t) {
  final b = t.buffer;
  final top = b.lines.length - b.height;
  final lines = logicalLines(b, fromRow: top < 0 ? 0 : top);
  return lines.isEmpty ? '' : '${lines.join('\n')}\n';
}

int cursorRow(Terminal t) => t.buffer.absoluteCursorY;

/// D20 paging: [offset] counts logical lines already sent.
({String text, int? next}) readPage(
  Terminal t, {
  int? lines,
  bool ansi = false,
  int offset = 0,
}) {
  final b = t.buffer;
  final all = lines == null
      ? logicalLines(b, fromRow: (b.lines.length - b.height).clamp(0, b.lines.length), ansi: ansi)
      : logicalLines(b, last: lines, ansi: ansi);
  final out = StringBuffer();
  var bytes = 0;
  var i = offset;
  while (i < all.length) {
    final line = '${all[i]}\n';
    final size = utf8.encode(line).length;
    if (bytes + size > kReadPageBytes) {
      if (bytes == 0) {
        // One line longer than a page: cut it at a character boundary.
        var cut = all[i];
        while (utf8.encode('$cut\n').length > kReadPageBytes) {
          cut = cut.substring(0, cut.length - 64.clamp(1, cut.length));
        }
        out.write('$cut\n');
        i++;
      }
      break;
    }
    out.write(line);
    bytes += size;
    i++;
  }
  return (text: out.toString(), next: i < all.length ? i : null);
}
```

`pane_waiter.dart`:

```dart
import 'dart:async';

import 'package:xterm/xterm.dart';

import 'package:shellx_agent/shellx_agent.dart';

import 'pane_text.dart';

/// What a wait needs to know about one terminal pane.
abstract interface class PaneProbe {
  /// The shell reported a cwd (OSC 7): its hooks run (A2 C1).
  bool get hooked;

  /// A4 `runningCommand`.
  bool get running;
  bool get exited;
  int? get exitCode;

  /// Fires after the pane's terminal received output.
  Stream<void> get output;

  /// Fires when [hooked]/[running]/[exited] may have changed.
  Stream<void> get changes;
  Terminal get terminal;
}

const _unhookedQuiet = Duration(seconds: 2);
const _matchThrottle = Duration(milliseconds: 100);
const _matchMaxLines = 2000;
const _matchMaxChars = 262144;

Future<Map<String, Object?>> _race(
  PaneProbe p,
  Duration timeout,
  Future<void>? cancelled,
  void Function(Completer<Map<String, Object?>> done, List<StreamSubscription<void>> subs, List<Timer> timers) arm,
) {
  final done = Completer<Map<String, Object?>>();
  final subs = <StreamSubscription<void>>[];
  final timers = <Timer>[
    Timer(timeout, () {
      if (!done.isCompleted) done.completeError(const CliFailure('timeout', 'timed out'));
    }),
  ];
  cancelled?.then((_) {
    if (!done.isCompleted) done.completeError(const CliFailure('cancelled', 'the client went away'));
  });
  arm(done, subs, timers);
  return done.future.whenComplete(() {
    for (final s in subs) {
      unawaited(s.cancel());
    }
    for (final t in timers) {
      t.cancel();
    }
  });
}

/// D21 idle.
Future<Map<String, Object?>> waitIdle(
  PaneProbe p, {
  required Duration quiet,
  required Duration timeout,
  Future<void>? cancelled,
}) => _race(p, timeout, cancelled, (done, subs, timers) {
  Timer? q;
  void check() {
    if (done.isCompleted) return;
    if (p.exited) {
      done.completeError(const CliFailure('exited', 'the pane exited'));
      return;
    }
    q?.cancel();
    if (p.hooked && p.running) return;
    q = Timer(p.hooked ? quiet : _unhookedQuiet, () {
      if (!done.isCompleted && !(p.hooked && p.running) && !p.exited) {
        done.complete(const {});
      }
    });
    timers.add(q!);
  }

  subs
    ..add(p.output.listen((_) => check()))
    ..add(p.changes.listen((_) => check()));
  check();
});

/// D21 exit.
Future<Map<String, Object?>> waitExit(
  PaneProbe p, {
  required Duration timeout,
  Future<void>? cancelled,
}) => _race(p, timeout, cancelled, (done, subs, _) {
      void check() {
        if (!done.isCompleted && p.exited) done.complete({'exitCode': p.exitCode});
      }

      subs.add(p.changes.listen((_) => check()));
      check();
    });

/// D21 match.
Future<Map<String, Object?>> waitMatch(
  PaneProbe p,
  RegExp re, {
  required bool fromNow,
  required Duration timeout,
  Future<void>? cancelled,
}) {
  final from = fromNow ? cursorRow(p.terminal) : null;
  return _race(p, timeout, cancelled, (done, subs, timers) {
    Timer? pending;
    void scan() {
      pending = null;
      if (done.isCompleted) return;
      final lines = logicalLines(p.terminal.buffer, last: _matchMaxLines, fromRow: from);
      var text = lines.join('\n');
      if (text.length > _matchMaxChars) text = text.substring(text.length - _matchMaxChars);
      final m = re.firstMatch(text);
      if (m != null) {
        final lineStart = text.lastIndexOf('\n', m.start) + 1;
        final lineEnd = text.indexOf('\n', m.end);
        done.complete({
          'match': m.group(0),
          'line': text.substring(lineStart, lineEnd < 0 ? text.length : lineEnd),
        });
      } else if (p.exited) {
        done.completeError(const CliFailure('exited', 'the pane exited'));
      }
    }

    void soon() {
      if (pending != null) return;
      pending = Timer(_matchThrottle, scan);
      timers.add(pending!);
    }

    subs
      ..add(p.output.listen((_) => soon()))
      ..add(p.changes.listen((_) => soon()));
    soon();
  });
}

/// D16: type `--cmd` once the shell is ready.
final class CommandInjector {
  CommandInjector(this._probe, this._paste);
  final PaneProbe Function(int pane) _probe;
  final void Function(int pane, String text) _paste;

  static const quiet = Duration(milliseconds: 1500);
  static const cap = Duration(seconds: 5);

  void inject(int pane, String cmd) {
    final p = _probe(pane);
    final subs = <StreamSubscription<void>>[];
    Timer? q;
    late final Timer capTimer;
    var sent = false;
    void send() {
      if (sent) return;
      sent = true;
      q?.cancel();
      capTimer.cancel();
      for (final s in subs) {
        unawaited(s.cancel());
      }
      if (!p.exited) _paste(pane, cmd);
    }

    capTimer = Timer(cap, send);
    if (p.hooked) {
      send();
      return;
    }
    subs
      ..add(p.changes.listen((_) {
        if (p.hooked || p.exited) send();
      }))
      ..add(p.output.listen((_) {
        q?.cancel();
        q = Timer(quiet, send);
      }));
  }
}
```

(`Buffer.absoluteCursorY` and `Buffer.height` are xterm 4.0.0 members used by `DesktopTerminal.resize`; `BufferLine.getText()` with no arguments returns the row's text.)

In `ui_command_handler.dart` add the imports `dart:convert`, `package:xterm/xterm.dart`, `../terminal/desktop_terminal.dart`, `pane_text.dart`, `pane_waiter.dart`, then add the three cases to the `switch` and these members; also construct the injector in the constructor body: `onCommand = CommandInjector(_probe, (pane, text) => _send(pane, text: text, enter: true)).inject;`

```dart
      CliType.uiPaneSend => _sendReq(r),
      CliType.uiPaneRead => _read(r),
      CliType.uiPaneWait => _wait(r),
```

```dart
  static const kSendMaxBytes = 49152;

  PaneSession _pane(int id) {
    final p = _tabsState.tabOfSession(id)?.panes[id];
    if (p == null) {
      throw CliFailure('not_found', id < 0 ? 'p$id is a browser pane' : 'no pane p$id');
    }
    return p;
  }

  int _paneArg(MuxMessage r) {
    final raw = r.fields['pane'];
    if (raw is int && raw < 0) throw _bad('p$raw is a browser pane; use shellx browser');
    return resolvePane(_tabsState, parseTarget(raw, null));
  }

  Future<Map<String, Object?>> _sendReq(MuxMessage r) async {
    final pane = _paneArg(r);
    final text = _string(r, 'text', max: kSendMaxBytes);
    final keys = (r.fields['keys'] as List?)?.cast<Object?>() ?? const [];
    if (text != null && utf8.encode(text).length > kSendMaxBytes) {
      throw _bad('text is over 48 KiB');
    }
    if ((text == null || text.isEmpty) && keys.isEmpty && !_flag(r, 'enter')) {
      throw _bad('nothing to send');
    }
    final parsed = [for (final k in keys) _key(k)];
    _send(pane, text: text, keys: parsed, enter: _flag(r, 'enter'));
    return const {};
  }

  void _send(int pane, {String? text, List<void Function(DesktopTerminal)> keys = const [], bool enter = false}) {
    final p = _pane(pane);
    if (p.exited) throw const CliFailure(CliError.exited, 'the pane exited');
    final t = p.terminal;
    if (text != null && text.isNotEmpty) t.paste(text); // A1: sanitized, bracketed when on
    for (final k in keys) {
      k(t);
    }
    if (enter) t.keyInput(TerminalKey.enter);
    _marks.touch(tab: _tabsState.tabOfSession(pane)!.id, pane: pane);
  }

  static final _named = <String, TerminalKey>{
    'enter': TerminalKey.enter, 'tab': TerminalKey.tab, 'esc': TerminalKey.escape,
    'backspace': TerminalKey.backspace, 'up': TerminalKey.arrowUp, 'down': TerminalKey.arrowDown,
    'left': TerminalKey.arrowLeft, 'right': TerminalKey.arrowRight, 'home': TerminalKey.home,
    'end': TerminalKey.end, 'pageup': TerminalKey.pageUp, 'pagedown': TerminalKey.pageDown,
  };

  void Function(DesktopTerminal) _key(Object? name) {
    if (name is! String) throw _bad('a key is a name');
    final k = _named[name];
    if (k != null) return (t) => t.keyInput(k);
    final ctrl = RegExp(r'^ctrl-([a-z\\\]])$').firstMatch(name);
    if (ctrl != null) {
      final ch = ctrl.group(1)!.codeUnitAt(0);
      return (t) => t.charInput(ch, ctrl: true);
    }
    throw _bad('unknown key "$name"');
  }

  Future<Map<String, Object?>> _read(MuxMessage r) async {
    final pane = _paneArg(r);
    final lines = r.fields['lines'];
    if (lines != null && (lines is! int || lines < 1 || lines > kReadMaxLines)) {
      throw _bad('lines is 1–$kReadMaxLines');
    }
    final offset = r.fields['offset'];
    if (offset != null && (offset is! int || offset < 0)) throw _bad('bad offset');
    final page = readPage(
      _pane(pane).terminal,
      lines: lines as int?,
      ansi: _flag(r, 'ansi'),
      offset: (offset as int?) ?? 0,
    );
    _marks.touch(tab: _tabsState.tabOfSession(pane)!.id, pane: pane);
    return {'text': page.text, 'next': ?page.next};
  }

  Future<Map<String, Object?>> _wait(MuxMessage r) async {
    final pane = _paneArg(r);
    final ms = r.fields['timeoutMs'] ?? 30000;
    if (ms is! int || ms < 1 || ms > 3600000) throw _bad('timeout is 1 ms–3600 s');
    final timeout = Duration(milliseconds: ms);
    _marks.touch(tab: _tabsState.tabOfSession(pane)!.id, pane: pane);
    final probe = _probe(pane);
    switch (r.fields['mode']) {
      case 'idle':
        final quiet = r.fields['quietMs'] ?? 500;
        if (quiet is! int || quiet < 0 || quiet > 60000) throw _bad('quiet is 0–60000 ms');
        return waitIdle(probe, quiet: Duration(milliseconds: quiet), timeout: timeout, cancelled: _cancelled);
      case 'exit':
        return waitExit(probe, timeout: timeout, cancelled: _cancelled);
      case 'match':
        final pattern = _string(r, 'pattern', max: 1024) ?? (throw _bad('pattern is required'));
        final RegExp re;
        try {
          re = RegExp(pattern, multiLine: true);
        } on FormatException {
          throw _bad('invalid regular expression');
        }
        return waitMatch(probe, re, fromNow: _flag(r, 'fromNow'), timeout: timeout, cancelled: _cancelled);
      default:
        throw _bad('mode is idle, exit or match');
    }
  }

  /// A live view of one pane for waits and `--cmd`.
  PaneProbe _probe(int pane) => _LivePane(_ref, pane);
```

and at the bottom of the file:

```dart
final class _LivePane implements PaneProbe {
  _LivePane(this._ref, this.id);
  final Ref _ref;
  final int id;

  PaneSession? get _p => _ref.read(terminalTabsProvider).tabOfSession(id)?.panes[id];

  @override
  bool get hooked => _p?.cwd != null;
  @override
  bool get running => _p?.runningCommand ?? false;
  @override
  bool get exited => _p == null || _p!.exited;
  @override
  int? get exitCode => _p?.exitCode;
  @override
  Terminal get terminal => _p!.terminal;
  @override
  Stream<void> get output =>
      _ref.read(terminalTabsProvider.notifier).paneOutput.where((p) => p == id).map((_) {});
  @override
  Stream<void> get changes {
    final c = StreamController<void>();
    final sub = _ref.listen(terminalTabsProvider, (_, _) => c.add(null));
    c.onCancel = sub.close;
    return c.stream;
  }
}
```

`exitCode` subtlety: a pane that exits with code 0 is **removed** from the tree (A3 D7), so `_p` becomes null — `exited` is then true and `exitCode` null. Keep the last exit code: in `TerminalTabs`, record `lastExitCodes[id] = code` (a bounded map, 64 entries) when a pane's view reports exit, and make `_LivePane.exitCode` read `_p?.exitCode ?? notifier.lastExitCode(id)`. Add that map + `int? lastExitCode(int id)` in this task with a unit test in `pane_waiter_test.dart`-style using the container: open, `local.exit(100, 0)`, `waitExit` → `{'exitCode': 0}`.

`paneOutput`: if A5a added a per-pane output stream for scrollback dirtiness (A5a Task 4 "pane output events"), expose it as `Stream<int> get paneOutput` (pane ids) — otherwise add a broadcast `StreamController<int>` in `TerminalTabs`, `add(id)` right after the pane's `TerminalFeed` writes, and close it in `_dispose`.

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test`
Expected: PASS (A5a scrollback tests unchanged after the rename).

- [ ] **Step 5: Format, analyze, commit**

```bash
cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH dart format --set-exit-if-changed lib test && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter analyze && cd ../..
git add apps/desktop/lib/src/cli/pane_text.dart apps/desktop/lib/src/cli/pane_waiter.dart apps/desktop/lib/src/cli/ui_command_handler.dart apps/desktop/lib/src/restore/scrollback_codec.dart apps/desktop/lib/src/terminal/terminal_tabs.dart apps/desktop/test/cli/pane_text_test.dart apps/desktop/test/cli/pane_waiter_test.dart apps/desktop/test/cli/ui_command_handler_send_test.dart apps/desktop/test/cli/support/cli_container.dart
git commit -m "feat(desktop): ui.pane.send as a safe paste, read with paging and SGR, wait idle/exit/match, --cmd once the shell is ready (A7 D16, D19-D21)"
```

---

### Task 8: Desktop — notifications, events, browser forwarding (D23, D24, D25, D34 UI side)

**Files:**
- Create: `apps/desktop/lib/src/cli/cli_event_bus.dart`
- Modify: `apps/desktop/lib/src/cli/ui_command_handler.dart` (`events`, `notifyApp`, `ui.events.subscribe`, `ui.notify`, `ui.browser.*`), `apps/desktop/lib/src/terminal/tab_attention.dart` (command-line entries), `apps/desktop/lib/src/ui/terminal/notifications_panel.dart` (render "Dòng lệnh" entries), `apps/desktop/lib/l10n/app_en.arb`, `app_vi.arb` (+ `flutter gen-l10n`)
- Test: `apps/desktop/test/cli/cli_event_bus_test.dart`, `apps/desktop/test/cli/ui_command_handler_notify_test.dart`, `apps/desktop/test/cli/ui_command_handler_browser_test.dart`, `apps/desktop/test/terminal/tab_attention_test.dart` (add)

**Interfaces:**
- Consumes: `terminalTabsProvider`, `sidebarWorkspacesProvider`, `localSessionsProvider.notices`, `TabAttention`, A4 `DesktopNotifications` (the system-notification sender used by `TabAttention` arrivals; method that shows one notification with id/title/body — reuse its rate limits, A4 D15), A6 `browserCommandHandlerProvider`, `browserRegistryProvider` (`existing(id)?.agentCommand()`).
- Produces:
  - `cli_event_bus.dart`: `final cliEventBusProvider = Provider<CliEventBus>(…)`; `final class CliEventBus { Stream<Map<String, Object?>> get events; }` emitting D24 kinds: `tab.opened{tab, workspace}`, `tab.closed{tab}`, `tab.renamed{tab, title}`, `tab.selected{tab}`, `tab.moved{tab, workspace}`, `pane.opened{pane, tab}`, `pane.closed{pane, tab}`, `pane.exited{pane, tab, exitCode}`, `pane.focused{pane, tab}`, `pane.changed{pane, tab, title, cwd, branch, ports, running}` (coalesced 250 ms per pane, only when different), `workspace.created{workspace, name}`, `workspace.renamed{workspace, name}`, `workspace.deleted{workspace}`, `notice{pane, tab, kind, title?, body?}`.
  - `TabAttention.addCommandLine({String? title, required String body})` — history entry with `tabId: kCommandLineTabId` (`0`, never a session id), label from `l10n.cliNoticeSource`, `read: false`, no unread badge; `jumpTo(0)` only raises the window.
  - `UiCommandHandler.notifyApp` → `TabAttention.addCommandLine` + one system notification (A4 D14 rules with "window not focused" treated as true for command-line entries, A4 D15 app limit).
  - `ui.browser.*` → A6 handler; marks the tab/pane and calls the A6 `agentCommand()` for the pane.
  - Strings: `cliNoticeSource` ("Dòng lệnh" / "Command line").

- [ ] **Step 1: Write the failing tests**

`apps/desktop/test/cli/cli_event_bus_test.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_desktop/src/cli/cli_event_bus.dart';
import 'package:shellx_desktop/src/terminal/sidebar_workspaces.dart';
import 'package:shellx_desktop/src/terminal/terminal_tabs.dart';

import 'support/cli_container.dart';
import '../support/fake_local_sessions.dart';

void main() {
  test('tab, pane, workspace and notice events', () async {
    final local = FakeLocalSessions();
    final c = cliContainer(local);
    addTearDown(c.dispose);
    final got = <Map<String, Object?>>[];
    c.read(cliEventBusProvider).events.listen(got.add);
    final tabs = c.read(terminalTabsProvider.notifier);
    await tabs.openTab(); // 100
    await tabs.split(SplitAxis.row); // 101
    tabs.rename(100, 'build');
    final ws = c.read(sidebarWorkspacesProvider.notifier).createFor(name: 'api');
    c.read(sidebarWorkspacesProvider.notifier).moveTab(100, ws);
    local.notice(101, SessionNoticeKind.message, title: 'CI', body: 'ok');
    tabs.closePane(101);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    final kinds = got.map((e) => e['kind']).toList();
    expect(kinds, containsAllInOrder([
      'tab.opened', 'pane.opened', 'tab.renamed', 'workspace.created', 'tab.moved', 'notice', 'pane.closed',
    ]));
    expect(got.firstWhere((e) => e['kind'] == 'notice'),
        {'kind': 'notice', 'pane': 101, 'tab': 100, 'type': 'message', 'title': 'CI', 'body': 'ok'});
    expect(got.firstWhere((e) => e['kind'] == 'pane.opened'), {'kind': 'pane.opened', 'pane': 101, 'tab': 100});
  });

  test('pane.changed is coalesced to one event per 250 ms with the latest values', () async {
    final local = FakeLocalSessions();
    final c = cliContainer(local);
    addTearDown(c.dispose);
    await c.read(terminalTabsProvider.notifier).openTab();
    final got = <Map<String, Object?>>[];
    c.read(cliEventBusProvider).events.listen(got.add);
    local.setCwd(100, '/a');
    local.setCwd(100, '/b');
    await Future<void>.delayed(const Duration(milliseconds: 300));
    final changed = got.where((e) => e['kind'] == 'pane.changed').toList();
    expect(changed, hasLength(1));
    expect(changed.single['cwd'], '/b');
  });
}
```

(`FakeLocalSessions.setCwd(id, cwd)` — add it beside `setRunning` if missing: replace the summary's `cwd` and fire `changes`.)

`apps/desktop/test/cli/ui_command_handler_notify_test.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/cli/ui_command_handler.dart';
import 'package:shellx_desktop/src/terminal/tab_attention.dart';
import 'package:shellx_desktop/src/terminal/terminal_tabs.dart';

import 'support/cli_container.dart';
import '../support/fake_local_sessions.dart';

void main() {
  test('pane notify goes through LocalSessions.notify; app notify is a command-line entry', () async {
    final local = FakeLocalSessions();
    final c = cliContainer(local);
    addTearDown(c.dispose);
    await c.read(terminalTabsProvider.notifier).openTab();
    final h = c.read(uiCommandHandlerProvider);
    expect(h.notifyPane(100, title: 'CI', body: 'ok'), isTrue);
    expect(local.notified.single, (100, 'CI', 'ok'));
    expect(h.notifyPane(999, body: 'x'), isFalse);
    await h.notifyApp(title: 'cron', body: 'backup done');
    final entry = c.read(tabAttentionProvider).history.first;
    expect(entry.tabId, kCommandLineTabId);
    expect(c.read(tabAttentionProvider).unread, isEmpty); // no badge
    expect(systemNotificationsSent(c).single.body, 'backup done');
  });
}
```

(`systemNotificationsSent(c)` reads the fake `SystemNotifier` the A4 tests install via the container overrides; add the helper to `cli_container.dart` using the same fake A4's `desktop_notifications_test.dart` uses.)

`apps/desktop/test/cli/ui_command_handler_browser_test.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_desktop/src/browser/browser_commands.dart';
import 'package:shellx_desktop/src/browser/browser_host.dart';
import 'package:shellx_desktop/src/cli/agent_marks.dart';
import 'package:shellx_desktop/src/cli/ui_command_handler.dart';
import 'package:shellx_desktop/src/terminal/terminal_tabs.dart';

import 'support/cli_container.dart';
import '../support/fake_local_sessions.dart';

final class RecordingBrowserHandler implements BrowserCommandHandler {
  final seen = <Map<String, Object?>>[];
  @override
  Future<Map<String, Object?>> handle(Map<String, Object?> request) async {
    seen.add(request);
    if (request['t'] == 'ui.browser.eval') {
      return {'t': 'error', 'q': request['q'], 'code': 'forbidden_origin', 'message': 'not local'};
    }
    return {'t': 'result', 'q': request['q'], 'pane': -1, 'tab': 100};
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('ui.browser.* is handed to A6 unchanged; errors become CliFailure', () async {
    final local = FakeLocalSessions();
    final rec = RecordingBrowserHandler();
    final c = cliContainer(local, overrides: [browserCommandHandlerProvider.overrideWithValue(rec)]);
    addTearDown(c.dispose);
    await c.read(terminalTabsProvider.notifier).openTab();
    final h = c.read(uiCommandHandlerProvider);
    final r = await h.handle(const MuxMessage('ui.browser.open', q: 3, fields: {'url': 'http://localhost:3000/'}));
    expect(r, {'pane': -1, 'tab': 100});
    expect(rec.seen.single, {'t': 'ui.browser.open', 'q': 3, 'url': 'http://localhost:3000/'});
    expect(c.read(agentMarksProvider).tabs.keys, contains(100));
    expect(
      () => h.handle(const MuxMessage('ui.browser.eval', q: 4, fields: {'pane': -1, 'script': 'return 1'})),
      throwsA(isA<CliFailure>().having((f) => f.code, 'code', 'forbidden_origin')),
    );
  });
}
```

(If `BrowserCommandHandler` is `final`, make the test fake implement a small `abstract interface class BrowserCommands { Future<Map<String, Object?>> handle(Map<String, Object?>); }` that you add next to it in A6's file, have `BrowserCommandHandler implements BrowserCommands`, and type `browserCommandHandlerProvider` as `Provider<BrowserCommands>`; adjust Task 6's `_ls` import accordingly.)

Add to `apps/desktop/test/terminal/tab_attention_test.dart`:

```dart
  test('A7 D23: command-line entries are history only', () {
    final a = container.read(tabAttentionProvider.notifier);
    a.addCommandLine(title: 'cron', body: 'done');
    final s = container.read(tabAttentionProvider);
    expect(s.history.first.tabId, kCommandLineTabId);
    expect(s.history.first.tabLabel, 'Command line');
    expect(s.unread, isEmpty);
    expect(a.jumpTo(kCommandLineTabId), isFalse); // raises the window only
  });
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/cli test/terminal/tab_attention_test.dart`
Expected: FAIL.

- [ ] **Step 3: Implement**

ARB (`app_en.arb` / `app_vi.arb`), then `PATH=~/fvm/versions/3.41.4/bin:$PATH flutter gen-l10n`:

```json
"cliNoticeSource": "Command line",
"@cliNoticeSource": {"description": "A7 D23: label of a notification sent by `shellx notify` from outside a ShellX pane"}
```

```json
"cliNoticeSource": "Dòng lệnh"
```

`tab_attention.dart`:

```dart
/// A7 D23: history entries from `shellx notify` outside a pane. Session ids
/// start at 1 (`sessionIdAllocator`), so 0 is never a tab.
const int kCommandLineTabId = 0;
```

and in `TabAttention`:

```dart
  /// A7 D23: a command-line notification — a panel entry, no badge, no
  /// ring. Returns the entry so the caller can send the system notification.
  AttentionEntry addCommandLine({String? title, required String body}) {
    final notice = SessionNotice(
      sessionId: kCommandLineTabId,
      kind: SessionNoticeKind.message,
      at: DateTime.now(),
      title: title,
      body: body,
    );
    final entry = AttentionEntry(
      seq: _nextSeq++,
      tabId: kCommandLineTabId,
      tabLabel: ref.read(appL10nProvider).cliNoticeSource,
      kind: AttentionKind.message,
      notice: notice,
      at: notice.at,
    );
    state = AttentionState(
      unread: state.unread,
      history: [entry, ...state.history].take(kAttentionHistory).toList(),
    );
    return entry;
  }
```

(Use the real names of the sequence counter and history cap in `tab_attention.dart` — A4 D11's 50-entry cap — and the clock `TabAttention` already uses instead of `DateTime.now()` if it has one.) In `jumpTo`, add at the top: `if (tabId == kCommandLineTabId) { _raiseWindow(); return false; }` using the same window-raise call `jumpTo` makes today. `markRead`/`_dropGone` must skip `kCommandLineTabId` (it is never in `TerminalTabsState`, so `_dropGone` must not mark these entries `closed`). In `notifications_panel.dart`, an entry with `tabId == kCommandLineTabId` shows `tabLabel` and never the "Tab đã đóng" style.

`ui_command_handler.dart`:

```dart
  @override
  Stream<Map<String, Object?>> events() => _ref.read(cliEventBusProvider).events;

  @override
  Future<void> notifyApp({String? title, required String body}) async {
    final entry = _ref.read(tabAttentionProvider.notifier).addCommandLine(title: title, body: body);
    _ref.read(desktopNotificationsProvider).showCommandLine(entry);
  }
```

Add `showCommandLine(AttentionEntry entry)` to A4's `DesktopNotifications`: if `desktop_notifications_enabled` is off → nothing; else send one system notification (id `shellx.cli.<seq>`, title = `entry.notice.title ?? l10n.cliNoticeSource`, body = text) through the same app-wide limiter (A4 D15: ≤ 20 per 60 s); clicking it raises the window (A4 D16 with no tab).

Browser forwarding (replace the Task 6 stub):

```dart
  Future<Map<String, Object?>> _browser(MuxMessage r) async {
    final request = <String, Object?>{'t': r.type, 'q': r.q, ...r.fields};
    final answer = await _ref.read(browserCommandHandlerProvider).handle(request);
    if (answer['t'] == 'error') {
      throw CliFailure(answer['code']! as String, answer['message'] as String?);
    }
    final pane = (answer['pane'] ?? r.fields['pane']) as int?;
    final tab = (answer['tab'] as int?) ?? (pane == null ? null : _browserTab(pane));
    if (tab != null && r.type != 'ui.browser.list') _marks.touch(tab: tab, pane: pane);
    return {
      for (final e in answer.entries)
        if (e.key != 't' && e.key != 'q') e.key: e.value,
    };
  }

  int? _browserTab(int pane) {
    // A6: browser panes live in the tab tree with negative ids.
    for (final tab in _tabsState.tabs) {
      if (paneIds(tab.layout).contains(pane)) return tab.id;
    }
    return null;
  }
```

(A6 D25 already turns on the toolbar Agent mark inside `BrowserController` for every handler command; nothing more is needed for the pane. `paneIds(layout)` is A3's tree walk in `pane_layout.dart`.)

`ui.events.subscribe` (used by the daemon after A5b, Task 11) and `ui.notify` (daemon → UI for app notifications) — add to the switch:

```dart
      CliType.uiNotify => () async {
        await notifyApp(title: _string(r, 'title', max: 128), body: _string(r, 'body', max: 1024) ?? '');
        return const <String, Object?>{};
      }(),
      CliType.uiEventsSubscribe => Future.value(const <String, Object?>{}),
```

(For `ui.events.subscribe` the daemon-side forwarder in Task 11 listens to `event` messages the UI pushes on its mux link; this request only arms `UiMuxResponder` to forward `events()` — see Task 11.)

`cli_event_bus.dart`:

```dart
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shellx_agent/shellx_agent.dart';

import '../terminal/local_sessions_provider.dart';
import '../terminal/sidebar_workspaces.dart';
import '../terminal/terminal_tabs.dart';

final cliEventBusProvider = Provider<CliEventBus>((ref) {
  final bus = CliEventBus._(ref);
  ref.onDispose(bus._dispose);
  return bus;
});

/// A7 D24: what changed in the window, as small maps (ids, never text of
/// the terminal). Built by diffing successive states.
final class CliEventBus {
  CliEventBus._(this._ref) {
    _subs.add(_ref.listen(terminalTabsProvider, _tabs, fireImmediately: false));
    _subs.add(_ref.listen(sidebarWorkspacesProvider, _side, fireImmediately: false));
    _notices = _ref.read(localSessionsProvider).notices.listen(_notice);
  }

  final Ref _ref;
  final _out = StreamController<Map<String, Object?>>.broadcast();
  final _subs = <ProviderSubscription<Object?>>[];
  late final StreamSubscription<SessionNotice> _notices;
  final _pendingChange = <int, Timer>{};
  final _lastSent = <int, Map<String, Object?>>{};

  Stream<Map<String, Object?>> get events => _out.stream;

  void _emit(Map<String, Object?> e) {
    if (_out.hasListener) _out.add(e);
  }

  void _tabs(TerminalTabsState? before, TerminalTabsState after) {
    final old = {for (final t in before?.tabs ?? const <TerminalTab>[]) t.id: t};
    final now = {for (final t in after.tabs) t.id: t};
    for (final t in after.tabs) {
      final o = old[t.id];
      if (o == null) {
        _emit({'kind': 'tab.opened', 'tab': t.id, 'workspace': _ref.read(sidebarWorkspacesProvider).workspaceOf(t.id)});
      } else if (o.label != t.label) {
        _emit({'kind': 'tab.renamed', 'tab': t.id, 'title': t.label});
      }
      for (final p in t.panes.values) {
        final op = o?.panes[p.id];
        if (op == null) {
          if (o != null) _emit({'kind': 'pane.opened', 'pane': p.id, 'tab': t.id});
          continue;
        }
        if (!op.exited && p.exited) {
          _emit({'kind': 'pane.exited', 'pane': p.id, 'tab': t.id, 'exitCode': p.exitCode});
        }
        _paneChanged(t.id, p);
      }
      if (o != null) {
        for (final id in o.panes.keys) {
          if (!t.panes.containsKey(id)) _emit({'kind': 'pane.closed', 'pane': id, 'tab': t.id});
        }
        if (o.focusedPaneId != t.focusedPaneId) {
          _emit({'kind': 'pane.focused', 'pane': t.focusedPaneId, 'tab': t.id});
        }
      }
    }
    for (final id in old.keys) {
      if (!now.containsKey(id)) _emit({'kind': 'tab.closed', 'tab': id});
    }
    if (before?.selectedId != after.selectedId && after.selectedId != null) {
      _emit({'kind': 'tab.selected', 'tab': after.selectedId});
    }
  }

  void _paneChanged(int tab, PaneSession p) {
    final snap = <String, Object?>{
      'kind': 'pane.changed', 'pane': p.id, 'tab': tab, 'title': p.automaticLabel,
      'cwd': p.cwd, 'branch': p.gitBranch, 'ports': p.ports, 'running': p.runningCommand,
    };
    _pendingChange[p.id]?.cancel();
    _pendingChange[p.id] = Timer(const Duration(milliseconds: 250), () {
      _pendingChange.remove(p.id);
      final last = _lastSent[p.id];
      if (last != null && _same(last, snap)) return;
      _lastSent[p.id] = snap;
      _emit(snap);
    });
  }

  static bool _same(Map<String, Object?> a, Map<String, Object?> b) =>
      a.length == b.length &&
      a.keys.every((k) => '${a[k]}' == '${b[k]}');

  void _side(SidebarState? before, SidebarState after) {
    final names = _ref.read(sidebarWorkspacesProvider.notifier);
    final old = {for (final w in before?.workspaces ?? const <Workspace>[]) w.id: w};
    for (final w in after.workspaces) {
      final o = old[w.id];
      if (o == null) {
        _emit({'kind': 'workspace.created', 'workspace': w.id, 'name': names.displayName(w.id)});
      } else if (o.name != w.name) {
        _emit({'kind': 'workspace.renamed', 'workspace': w.id, 'name': names.displayName(w.id)});
      }
    }
    for (final id in old.keys) {
      if (after.workspace(id) == null) _emit({'kind': 'workspace.deleted', 'workspace': id});
    }
    if (before == null) return;
    for (final w in after.workspaces) {
      for (final tab in after.tabsOf(w.id)) {
        final was = before.workspaceOf(tab);
        if (was != null && was != w.id) _emit({'kind': 'tab.moved', 'tab': tab, 'workspace': w.id});
      }
    }
  }

  void _notice(SessionNotice n) {
    final tab = _ref.read(terminalTabsProvider).tabOfSession(n.sessionId)?.id;
    _emit({
      'kind': 'notice',
      'pane': n.sessionId,
      'tab': tab,
      'type': n.kind.name,
      'title': ?n.title,
      'body': ?n.body,
    });
  }

  void _dispose() {
    for (final s in _subs) {
      s.close();
    }
    unawaited(_notices.cancel());
    for (final t in _pendingChange.values) {
      t.cancel();
    }
    unawaited(_out.close());
  }
}
```

The first pane of a new tab is reported only as `tab.opened` (its pane id equals the tab id, A3 D1); spec D24 lists `pane.opened` for panes added by splits — say so in the reference doc (Task 10). In the `notice` event the wire key for the notice kind is `type` (because `kind` names the event); update spec D24 wording is not needed — the reference doc documents it.

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test`
Expected: PASS. If A6 is not merged, delete `ui_command_handler_browser_test.dart`, make `_browser` throw `unknown_type`, drop `'ui.browser'` from `kCliCaps` (Task 2 file) and record "browser pending A6" in the ledger.

- [ ] **Step 5: Format, analyze, commit**

```bash
cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH dart format --set-exit-if-changed lib test && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter analyze && cd ../..
git add apps/desktop/lib/src/cli/cli_event_bus.dart apps/desktop/lib/src/cli/ui_command_handler.dart apps/desktop/lib/src/terminal/tab_attention.dart apps/desktop/lib/src/platform/desktop_notifications.dart apps/desktop/lib/src/ui/terminal/notifications_panel.dart apps/desktop/lib/l10n apps/desktop/test/cli apps/desktop/test/terminal/tab_attention_test.dart apps/desktop/test/support/fake_local_sessions.dart
git commit -m "feat(desktop): command-line notifications, event stream and browser forwarding (A7 D23-D25)"
```

---

### Task 9: Desktop — wiring and UI: host at startup, environment, CLI install, PATH install, tray "Dòng lệnh", Agent chips (D7, D8, D26, D27, D29, D39)

**Files:**
- Create: `apps/desktop/lib/src/cli/cli_install.dart`, `apps/desktop/lib/src/cli/cli_service.dart`
- Modify: `apps/desktop/lib/main.dart` (base environment; start/stop `CliService`), `apps/desktop/lib/src/terminal_sharing/term_binary.dart` (extract the copy logic into a reusable `BinaryCopier`), `apps/desktop/lib/src/tray/tray_action.dart`, `tray_menu.dart`, `tray_actions.dart`, `apps/desktop/lib/src/ui/terminal/session_tab_row.dart`, `apps/desktop/lib/src/ui/terminal/pane_tree_view.dart`, `apps/desktop/lib/src/ui/theme/shellx_desktop_theme.dart` (chip size), `apps/desktop/lib/l10n/app_en.arb`, `app_vi.arb`, `apps/desktop/macos/Runner/*` only if `osascript` needs an entitlement (it does not for a non-sandboxed app — verify), `release/windows/shellx.iss`, `release/tests/inno.test.mjs`, `term/src/uninstall.rs`
- Test: `apps/desktop/test/cli/cli_install_test.dart`, `apps/desktop/test/cli/cli_service_test.dart`, `apps/desktop/test/tray/tray_cli_menu_test.dart`, `apps/desktop/test/ui/agent_chip_test.dart`, `release/tests/inno.test.mjs` (case), `term/tests/uninstall.rs` (case)

**Interfaces:**
- Consumes: Tasks 5–8; A5b `MuxPaths`, `UnixMuxTransport`, `WindowsPipeTransport`, `pipeNameForUser`, `MuxEndpointFile`; `TermBinaryInstaller` logic; `SessionCore` construction in `main.dart` (its `baseEnvironment`); tray model (`TrayKeys`, `TrayMenuIds`, `sub(...)`, `check(...)` helpers in `tray_menu.dart`); A1 window activation.
- Produces:
  - `cli_install.dart`: `final class CliPaths { factory CliPaths.macos({required String home, required String executable}); factory CliPaths.windows({required String localAppData, required String executable}); final String dir; final String binary; final String bundledBinary; final String systemLink; /* macOS '/usr/local/bin/shellx'; Windows '' */ }`; `final class CliBinaryInstaller { CliBinaryInstaller(CliPaths paths, {Chmod chmod}); Future<bool> ensureCurrent(); Future<void> remove(); }`; `abstract interface class PathInstaller { Future<bool> get installed; Future<PathInstallResult> install(); Future<void> uninstall(); }`; `enum PathInstallResult { installed, cancelled, failed }`; `MacPathInstaller(CliPaths, {ProcessRunner run, Future<bool> Function(String dir) writable})` (symlink directly when writable, else `osascript -e 'do shell script "ln -sf … && …" with administrator privileges'`); `WindowsPathInstaller(CliPaths, {RegistryAccess reg, void Function() broadcast})` (HKCU `Environment\Path`, `REG_EXPAND_SZ`, add/remove our dir exactly once, `SendMessageTimeout(HWND_BROADCAST, WM_SETTINGCHANGE, 0, "Environment")`).
  - `cli_service.dart`: `final class CliService { static Future<CliService> start(ProviderContainer c, {required String appVersion}); Future<void> stop(); String get address; }` — picks the transport/address from `MuxPaths`, runs `CliBinaryInstaller.ensureCurrent()` (failures logged by type only), starts `CliHost` with `enabled: () => settings.getBool(cli_control_enabled) ?? true`.
  - `Map<String, String> cliSessionEnvironment(Map<String, String> base, {required String cliDir, required String socket, required bool windows})` — prefixes `PATH` (`:` / `;`, Windows key match is case-insensitive: `Path`), sets `SHELLX_SOCKET`.
  - Tray: `TrayKeys.commandLine`, `TrayKeys.cliControl`, `TrayKeys.cliPath`, `TrayKeys.cliSkills`; actions `ToggleCliControl`, `ToggleCliPath`, `CopySkillsCommand`.
  - Widgets: `AgentChip({required bool large})` used by `SessionTabRow` (after the pane-count mark, before 📱) and the A3 pane header (before ×).

- [ ] **Step 1: Write the failing tests**

`apps/desktop/test/cli/cli_install_test.dart`:

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/cli/cli_install.dart';

void main() {
  late Directory dir;
  setUp(() async => dir = await Directory.systemTemp.createTemp('cli_install'));
  tearDown(() => dir.delete(recursive: true));

  test('paths', () {
    final m = CliPaths.macos(home: '/Users/me', executable: '/Applications/ShellX.app/Contents/MacOS/ShellX');
    expect(m.binary, '/Users/me/Library/Application Support/ShellX/cli/shellx');
    expect(m.bundledBinary, '/Applications/ShellX.app/Contents/Helpers/shellx-term');
    expect(m.systemLink, '/usr/local/bin/shellx');
    final w = CliPaths.windows(localAppData: r'C:\Users\me\AppData\Local', executable: r'C:\Program Files\ShellX\ShellX.exe');
    expect(w.binary, r'C:\Users\me\AppData\Local\ShellX\cli\shellx.exe');
    expect(w.bundledBinary, r'C:\Program Files\ShellX\shellx-term.exe');
  });

  test('environment: PATH first, SHELLX_SOCKET', () {
    final mac = cliSessionEnvironment({'PATH': '/usr/bin'}, cliDir: '/c', socket: '/s', windows: false);
    expect(mac['PATH'], '/c:/usr/bin');
    expect(mac['SHELLX_SOCKET'], '/s');
    final win = cliSessionEnvironment({'Path': r'C:\Windows'}, cliDir: r'C:\c', socket: r'\\.\pipe\x', windows: true);
    expect(win['Path'], r'C:\c;C:\Windows');
    expect(win.containsKey('PATH'), isFalse);
    expect(cliSessionEnvironment({}, cliDir: '/c', socket: '/s', windows: false)['PATH'], '/c');
  });

  test('installs a copy named shellx when different; idempotent', () async {
    final bundled = File('${dir.path}/app/shellx-term')..createSync(recursive: true)..writeAsStringSync('v1');
    final paths = CliPaths.forTest(dir: '${dir.path}/cli', binary: '${dir.path}/cli/shellx', bundled: bundled.path);
    final modes = <String>[];
    final i = CliBinaryInstaller(paths, chmod: (mode, path) async => modes.add(mode));
    expect(await i.ensureCurrent(), isTrue);
    expect(File(paths.binary).readAsStringSync(), 'v1');
    expect(modes, ['755']);
    expect(await i.ensureCurrent(), isFalse); // already current
    bundled.writeAsStringSync('v2');
    expect(await i.ensureCurrent(), isTrue);
    expect(File(paths.binary).readAsStringSync(), 'v2');
    await i.remove();
    expect(Directory(paths.dir).existsSync(), isFalse);
  });

  test('macOS PATH install: direct symlink when writable, admin prompt otherwise', () async {
    final paths = CliPaths.forTest(dir: '/c', binary: '/c/shellx', bundled: '/b', systemLink: '${dir.path}/bin/shellx');
    Directory('${dir.path}/bin').createSync();
    final direct = MacPathInstaller(paths, run: (exe, args) async => throw StateError('no prompt'), writable: (_) async => true);
    expect(await direct.install(), PathInstallResult.installed);
    expect(Link('${dir.path}/bin/shellx').targetSync(), '/c/shellx');
    expect(await direct.installed, isTrue);
    await direct.uninstall();
    expect(Link('${dir.path}/bin/shellx').existsSync(), isFalse);

    final calls = <List<String>>[];
    final prompt = MacPathInstaller(paths, run: (exe, args) async {
      calls.add([exe, ...args]);
      return const ProcessOutcome(exitCode: 1, stderr: 'User canceled. (-128)');
    }, writable: (_) async => false);
    expect(await prompt.install(), PathInstallResult.cancelled);
    expect(calls.single.first, '/usr/bin/osascript');
    expect(calls.single.last, contains('with administrator privileges'));
    expect(calls.single.last, contains("ln -sf '/c/shellx' '${dir.path}/bin/shellx'"));
  });

  test('Windows PATH install edits HKCU Path once and broadcasts', () async {
    final reg = MemoryRegistry({'Path': r'C:\Tools;%USERPROFILE%\bin'});
    var broadcasts = 0;
    final paths = CliPaths.forTest(dir: r'C:\L\ShellX\cli', binary: r'C:\L\ShellX\cli\shellx.exe', bundled: 'x');
    final w = WindowsPathInstaller(paths, reg: reg, broadcast: () => broadcasts++);
    expect(await w.install(), PathInstallResult.installed);
    expect(await w.install(), PathInstallResult.installed);
    expect(reg.values['Path'], r'C:\Tools;%USERPROFILE%\bin;C:\L\ShellX\cli');
    expect(await w.installed, isTrue);
    await w.uninstall();
    expect(reg.values['Path'], r'C:\Tools;%USERPROFILE%\bin');
    expect(broadcasts, 2);
  });
}
```

`apps/desktop/test/cli/cli_service_test.dart` (macOS/Linux): starts `CliService` against a temp `MuxPaths`, connects with `UnixMuxTransport` + `clientHandshake(role: 'cli')`, sends `api.version`, flips `cli_control_enabled` to false in the fake settings store and sees `cli_disabled` for `ui.ls`, then `stop()` removes the endpoint file. Write it with the same `ProviderContainer` as `cliContainer` plus overrides for `MuxPaths` (`cliMuxPathsProvider`, defined in `cli_service.dart` with the real value computed in `main.dart`).

```dart
@TestOn('mac-os || linux')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_desktop/src/cli/cli_service.dart';
import 'package:shellx_desktop/src/mux/mux_paths.dart';
import 'package:shellx_desktop/src/platform/settings_store.dart';

import 'support/cli_container.dart';
import '../support/fake_local_sessions.dart';

void main() {
  test('serves api.version over a real socket; the switch applies at once', () async {
    final dir = await Directory.systemTemp.createTemp('cli_svc');
    addTearDown(() => dir.delete(recursive: true));
    final paths = MuxPaths(muxDirectory: '${dir.path}/mux', tmpDirectory: dir.path, uid: 501, windows: false);
    final c = cliContainer(FakeLocalSessions(), overrides: [cliMuxPathsProvider.overrideWithValue(paths)]);
    addTearDown(c.dispose);
    final svc = await CliService.start(c, appVersion: '1.7.0', installBinary: false);
    final info = (await MuxEndpointFile(paths.endpoint).read())!;
    final conn = await UnixMuxTransport().connect(info.address);
    await clientHandshake(conn, secret: info.secret, app: 't', role: 'cli');
    Future<MuxMessage> ask(String t, int q) {
      final f = conn.messages.firstWhere((m) => m.q == q);
      conn.send(MuxMessage(t, q: q));
      return f;
    }
    expect((await ask('api.version', 1)).get<int>('api'), 1);
    await c.read(settingsStoreProvider).setBool(SettingKeys.cliControlEnabled, false);
    expect((await ask('ui.ls', 2)).get<String>('code'), 'cli_disabled');
    await conn.close();
    await svc.stop();
    expect(File(paths.endpoint).existsSync(), isFalse);
  });
}
```

(Use the real settings provider/store API from `settings_store.dart`; `setBool`/`getBool` are illustrative names — match the existing ones.)

`apps/desktop/test/tray/tray_cli_menu_test.dart`: build the tray menu model (as `tray_terminal_menu_test.dart` from A5a does) and assert the "Dòng lệnh" submenu sits right after "Trình duyệt" with: a checked item `trayCliControl` reflecting `cli_control_enabled`, `trayCliInstallPath` when `cli_path_installed` is false / `trayCliRemovePath` when true, and `trayCliCopySkills`; each item emits `ToggleCliControl`, `ToggleCliPath`, `CopySkillsCommand`. Then test the action handler: `ToggleCliControl` flips the setting; `CopySkillsCommand` writes `shellx skills install` to the fake clipboard; `ToggleCliPath` calls the fake `PathInstaller` and stores `cli_path_installed` only on `installed`; a `failed` install shows the toast `cliPathFailed` with the path.

`apps/desktop/test/ui/agent_chip_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/cli/agent_marks.dart';

import '../cli/support/cli_container.dart';
import '../support/fake_local_sessions.dart';
import '../support/fakes.dart';

void main() {
  testWidgets('the tab row shows "Agent" for 10 s after a command; semantics label', (tester) async {
    final local = FakeLocalSessions();
    final c = cliContainer(local);
    await pumpTerminalWindow(tester, c); // the helper A3/A4 widget tests use
    await c.read(terminalTabsOpen(c)); // opens tab 100 (helper in cli_container)
    c.read(agentMarksProvider.notifier).touch(tab: 100);
    await tester.pump();
    expect(find.text('Agent'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('Agent')), findsWidgets);
    await tester.pump(const Duration(seconds: 11));
    expect(find.text('Agent'), findsNothing);
  });
}
```

(Replace `pumpTerminalWindow`/`terminalTabsOpen` with the real helpers in `test/support/fakes.dart` used by `one_pane_parity_test.dart`.)

Inno test (`release/tests/inno.test.mjs`) — add a case asserting `[UninstallDelete]` contains `{localappdata}\ShellX\cli` and `[Code]` `CurUninstallStepChanged` removes `{localappdata}\ShellX\cli` from `HKCU\Environment\Path`. Rust `term/tests/uninstall.rs` — add a case: `shellx-term uninstall` with a fake HOME removes `~/Library/Application Support/ShellX/cli` and, when `/usr/local/bin/shellx` (under a test-root override the existing uninstall tests use) is a symlink into that dir, removes the link — never a regular file and never a link pointing elsewhere.

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/cli test/tray/tray_cli_menu_test.dart test/ui/agent_chip_test.dart`
Expected: FAIL.

- [ ] **Step 3: Implement**

`cli_install.dart`:

```dart
import 'dart:io';

import 'package:path/path.dart' as p;

import '../terminal_sharing/term_binary.dart' show Chmod;

final class CliPaths {
  const CliPaths._({
    required this.dir,
    required this.binary,
    required this.bundledBinary,
    required this.systemLink,
    required this.windows,
  });

  factory CliPaths.macos({required String home, required String executable}) {
    final dir = p.posix.join(home, 'Library', 'Application Support', 'ShellX', 'cli');
    return CliPaths._(
      dir: dir,
      binary: p.posix.join(dir, 'shellx'),
      bundledBinary: p.posix.normalize(
        p.posix.join(p.posix.dirname(executable), '..', 'Helpers', 'shellx-term'),
      ),
      systemLink: '/usr/local/bin/shellx',
      windows: false,
    );
  }

  factory CliPaths.windows({required String localAppData, required String executable}) {
    final dir = p.windows.join(localAppData, 'ShellX', 'cli');
    return CliPaths._(
      dir: dir,
      binary: p.windows.join(dir, 'shellx.exe'),
      bundledBinary: p.windows.join(p.windows.dirname(executable), 'shellx-term.exe'),
      systemLink: '',
      windows: true,
    );
  }

  @visibleForTesting
  factory CliPaths.forTest({
    required String dir,
    required String binary,
    required String bundled,
    String systemLink = '/usr/local/bin/shellx',
    bool windows = false,
  }) => CliPaths._(dir: dir, binary: binary, bundledBinary: bundled, systemLink: systemLink, windows: windows);

  final String dir;
  final String binary;
  final String bundledBinary;
  final String systemLink;
  final bool windows;
}

/// D29: what every ShellX shell gets on top of the agent's environment.
Map<String, String> cliSessionEnvironment(
  Map<String, String> base, {
  required String cliDir,
  required String socket,
  required bool windows,
}) {
  final env = Map<String, String>.of(base);
  final key = windows
      ? env.keys.firstWhere((k) => k.toUpperCase() == 'PATH', orElse: () => 'Path')
      : 'PATH';
  final old = env[key] ?? '';
  env[key] = old.isEmpty ? cliDir : '$cliDir${windows ? ';' : ':'}$old';
  env['SHELLX_SOCKET'] = socket;
  return env;
}
```

`CliBinaryInstaller` — extract `TermBinaryInstaller.install`'s copy/rename/`.old-<n>` logic into a top-level `Future<void> copyBinary({required String from, required String to, required bool windows, required Chmod chmod})` in `term_binary.dart` (TermBinaryInstaller calls it; its tests stay green), then:

```dart
final class CliBinaryInstaller {
  CliBinaryInstaller(this.paths, {Chmod? chmod}) : _chmod = chmod ?? systemChmod;
  final CliPaths paths;
  final Chmod _chmod;

  /// D7: copies the app's binary to `cli/shellx` when missing or different.
  /// True when it copied.
  Future<bool> ensureCurrent() async {
    final from = File(paths.bundledBinary);
    final to = File(paths.binary);
    if (!await from.exists()) return false;
    if (await to.exists() &&
        await to.length() == await from.length() &&
        _same(await to.readAsBytes(), await from.readAsBytes())) {
      return false;
    }
    await copyBinary(from: from.path, to: to.path, windows: paths.windows, chmod: _chmod);
    return true;
  }

  Future<void> remove() async {
    final d = Directory(paths.dir);
    if (await d.exists()) await d.delete(recursive: true);
  }

  static bool _same(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
```

(`systemChmod` = the existing private `_systemChmod` in `term_binary.dart`, made public.)

`MacPathInstaller`:

```dart
final class ProcessOutcome {
  const ProcessOutcome({required this.exitCode, this.stderr = ''});
  final int exitCode;
  final String stderr;
}

typedef ProcessRunner = Future<ProcessOutcome> Function(String exe, List<String> args);

enum PathInstallResult { installed, cancelled, failed }

abstract interface class PathInstaller {
  Future<bool> get installed;
  Future<PathInstallResult> install();
  Future<void> uninstall();
}

String _sq(String s) => "'${s.replaceAll("'", r"'\''")}'";

final class MacPathInstaller implements PathInstaller {
  MacPathInstaller(this.paths, {required this.run, required this.writable});
  final CliPaths paths;
  final ProcessRunner run;
  final Future<bool> Function(String dir) writable;

  @override
  Future<bool> get installed async {
    final l = Link(paths.systemLink);
    return await l.exists() && await l.target() == paths.binary;
  }

  @override
  Future<PathInstallResult> install() async {
    final linkDir = p.posix.dirname(paths.systemLink);
    if (await writable(linkDir)) {
      final l = Link(paths.systemLink);
      if (await l.exists()) await l.delete();
      await l.create(paths.binary);
      return PathInstallResult.installed;
    }
    final script = 'mkdir -p ${_sq(linkDir)} && ln -sf ${_sq(paths.binary)} ${_sq(paths.systemLink)}';
    final r = await run('/usr/bin/osascript', [
      '-e',
      'do shell script "${script.replaceAll('"', r'\"')}" with administrator privileges',
    ]);
    if (r.exitCode == 0) return PathInstallResult.installed;
    return r.stderr.contains('-128') ? PathInstallResult.cancelled : PathInstallResult.failed;
  }

  @override
  Future<void> uninstall() async {
    if (!await installed) return; // never touch someone else's file
    final linkDir = p.posix.dirname(paths.systemLink);
    if (await writable(linkDir)) {
      await Link(paths.systemLink).delete();
      return;
    }
    await run('/usr/bin/osascript', [
      '-e',
      'do shell script "rm -f ${_sq(paths.systemLink).replaceAll('"', r'\"')}" with administrator privileges',
    ]);
  }
}
```

`WindowsPathInstaller`:

```dart
abstract interface class RegistryAccess {
  String? read(String name);
  void write(String name, String value); // REG_EXPAND_SZ under HKCU\Environment
}

final class MemoryRegistry implements RegistryAccess {
  MemoryRegistry(this.values);
  final Map<String, String> values;
  @override
  String? read(String name) => values[name];
  @override
  void write(String name, String value) => values[name] = value;
}

final class WindowsPathInstaller implements PathInstaller {
  WindowsPathInstaller(this.paths, {required this.reg, required this.broadcast});
  final CliPaths paths;
  final RegistryAccess reg;
  final void Function() broadcast;

  List<String> _parts() =>
      (reg.read('Path') ?? '').split(';').where((s) => s.isNotEmpty).toList();
  bool _ours(String s) => s.toLowerCase().replaceAll(RegExp(r'\\+$'), '') == paths.dir.toLowerCase();

  @override
  Future<bool> get installed async => _parts().any(_ours);

  @override
  Future<PathInstallResult> install() async {
    final parts = _parts();
    if (!parts.any(_ours)) {
      reg.write('Path', [...parts, paths.dir].join(';'));
      broadcast();
    }
    return PathInstallResult.installed;
  }

  @override
  Future<void> uninstall() async {
    final parts = _parts();
    if (!parts.any(_ours)) return;
    reg.write('Path', parts.where((s) => !_ours(s)).join(';'));
    broadcast();
  }
}
```

The real `RegistryAccess` for Windows uses `package:win32` (`RegOpenKeyEx(HKEY_CURRENT_USER, 'Environment')`, `RegQueryValueEx`, `RegSetValueEx` with `REG_EXPAND_SZ`) and `broadcast` = `SendMessageTimeout(HWND_BROADCAST, WM_SETTINGCHANGE, 0, TEXT('Environment'), SMTO_ABORTIFHUNG, 5000, nullptr)` — put both in `cli_install_windows.dart` behind a conditional import (`win32` is already a desktop dependency from A5b; if A5b is not merged and `win32` is absent from `apps/desktop/pubspec.yaml`, use the Windows runner channel the A4 taskbar code uses: add methods `getUserPath`/`setUserPath` to `pro.shellx.desktop/taskbar`'s C++ handler — no new dependency). ⚠ MANUAL on Windows.

`cli_service.dart`:

```dart
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shellx_agent/shellx_agent.dart';

import '../mux/mux_paths.dart';
import '../mux/windows_pipe_transport.dart';
import '../platform/settings_store.dart';
import 'agent_marks.dart';
import 'cli_install.dart';
import 'ui_command_handler.dart';

/// Set in `main.dart` from the platform (A5b `MuxPaths`).
final cliMuxPathsProvider = Provider<MuxPaths>((_) => throw UnimplementedError());
final cliPathsProvider = Provider<CliPaths>((_) => throw UnimplementedError());

final class CliService {
  CliService._(this._host, this.address);
  final CliHost _host;
  final String address;

  static Future<CliService> start(
    ProviderContainer c, {
    required String appVersion,
    bool installBinary = true,
  }) async {
    if (installBinary) {
      try {
        await CliBinaryInstaller(c.read(cliPathsProvider)).ensureCurrent();
      } on Object catch (e) {
        debugPrint('cli binary install failed: ${e.runtimeType}');
      }
    }
    final paths = c.read(cliMuxPathsProvider);
    final MuxTransport transport = paths.windows ? WindowsPipeTransport() : UnixMuxTransport();
    final handler = c.read(uiCommandHandlerProvider);
    final settings = c.read(settingsStoreProvider);
    final host = CliHost(
      transport: transport,
      address: paths.address,
      endpointFile: MuxEndpointFile(paths.endpoint),
      ui: handler,
      enabled: () => settings.getBool(SettingKeys.cliControlEnabled) ?? true,
      appVersion: appVersion,
    );
    await host.start();
    return CliService._(host, paths.address);
  }

  Future<void> stop() => _host.stop();
}
```

`main.dart`:
1. Before `SessionCore(...)` is constructed, compute `MuxPaths` (A5b Task 7 formula: macOS `muxDirectory = <getApplicationSupportDirectory()>/mux`, `tmpDirectory = Platform.environment['TMPDIR']`, `uid` via `id -u` already used by A5b — or `MuxPaths` helper; Windows `%LOCALAPPDATA%\ShellX\mux` and `pipeNameForUser(sid)`) and `CliPaths` (`CliPaths.macos(home: HOME, executable: Platform.resolvedExecutable)` / `CliPaths.windows(...)`), and pass `cliSessionEnvironment(Platform.environment, cliDir: cliPaths.dir, socket: muxPaths.address, windows: Platform.isWindows)` as the `SessionManager` base environment (find where `Platform.environment` is passed today).
2. Override `cliMuxPathsProvider` and `cliPathsProvider` in the root `ProviderScope`/container.
3. After the window and providers are up (where A4/A5a start their services), `final cli = await CliService.start(container, appVersion: packageInfo.version);` wrapped in `try`/`catch` (log `runtimeType`; the app runs without the CLI). On quit (the same place `flushAll` runs), `await cli.stop()`.
4. Set `container.read(agentMarksProvider.notifier).onAnnounce = (tab) => SemanticsService.announce(l10n.cliAnnounceAgent(label of tab), TextDirection.ltr)` and `container.read(uiCommandHandlerProvider).onRaise = <the A1 D11 activation used by the tray's OpenTerminalWindow>`.

If A5b **is** merged, skip 1's base-environment change for `SessionManager` here (sessions live in the daemon): instead the daemon's `daemonMain` applies `cliSessionEnvironment` to its `SessionManager` base environment, and `CliService.start` is not called in the UI — Task 11 wires the daemon.

Tray (`tray_action.dart`): add `final class ToggleCliControl extends TrayAction`, `ToggleCliPath`, `CopySkillsCommand`. `tray_menu.dart`: a `commandLine()` submenu built like `notifications()`, placed right after A6's "Trình duyệt" submenu in both signed-in and signed-out menus:

```dart
  MenuItem commandLine() => sub(TrayKeys.commandLine, l10n.trayCommandLine, [
    check(TrayKeys.cliControl, l10n.trayCliControl, state.cliControlEnabled),
    item(TrayKeys.cliPath, state.cliPathInstalled ? l10n.trayCliRemovePath : l10n.trayCliInstallPath),
    item(TrayKeys.cliSkills, l10n.trayCliCopySkills),
  ]);
```

(`state.cliControlEnabled`/`cliPathInstalled` come from the tray presenter's settings snapshot — add both fields the way A4 added `desktopNotifications`.) `tray_actions.dart` handles them: toggle the setting; for the path item run `PathInstaller` (macOS: `MacPathInstaller(paths, run: <Process.run wrapper>, writable: <FileStat + access(W_OK) via `test -w`>)`; Windows: `WindowsPathInstaller`), store `cli_path_installed` on success, show toast `cliPathFailed(path)` on `failed`, nothing on `cancelled`; copy `shellx skills install` with `Clipboard.setData` and show toast `cliSkillsCopied`.

Strings (en / vi) — add to both ARB files, regenerate:

| key | en | vi |
|---|---|---|
| `trayCommandLine` | Command line | Dòng lệnh |
| `trayCliControl` | Allow controlling ShellX from the command line | Cho phép điều khiển ShellX bằng dòng lệnh |
| `trayCliInstallPath` | Install the shellx command for all terminals… | Cài lệnh shellx cho mọi terminal… |
| `trayCliRemovePath` | Remove the shellx command from other terminals | Gỡ lệnh shellx khỏi terminal khác |
| `trayCliCopySkills` | Copy the agent skill install command | Sao chép lệnh cài skill cho agent |
| `cliSkillsCopied` | Copied “shellx skills install” — paste it in a terminal | Đã sao chép “shellx skills install” — dán vào terminal |
| `cliPathFailed` | Couldn’t install the shellx command. Add {path} to your PATH. | Không cài được lệnh shellx. Hãy thêm {path} vào PATH. |
| `agentChip` | Agent | Agent |
| `agentChipTooltip` | A program is controlling this tab through the ShellX command line | Một chương trình đang điều khiển tab này qua dòng lệnh ShellX |
| `cliAnnounceAgent` | An agent is controlling {tab} | Agent đang điều khiển {tab} |

Agent chip (`apps/desktop/lib/src/ui/terminal/agent_chip.dart`, added to the File Structure list of this task): `Icons.smart_toy_outlined` 12 (row) / 14 (pane header) + text `agentChip` in `caption` w600, `warnBg` fill, `warnBorder` 1 px, `rPill`, height 16 (row) / 20 (pane header), horizontal padding 6/8; `Semantics(label: agentChipTooltip)`, `Tooltip(agentChipTooltip)`, excluded from focus traversal. `SessionTabRow` watches `agentMarksProvider` + a 1 s ticker only while a mark is active and shows the chip after the A3 pane-count mark, before 📱; the A3 pane header shows it before ×. Theme sizes `agentChipRowHeight = 16`, `agentChipPaneHeight = 20` in `shellx_desktop_theme.dart` (no new colours).

Uninstall: `release/windows/shellx.iss` — `[UninstallDelete] Type: filesandordirs; Name: "{localappdata}\ShellX\cli"` and, in `CurUninstallStepChanged(usUninstall)`, read `HKCU\Environment\Path`, drop the entry equal to `ExpandConstant('{localappdata}\ShellX\cli')` (case-insensitive), write back with `RegWriteExpandStringValue`. `term/src/uninstall.rs` — remove `<support>/cli` and the `/usr/local/bin/shellx` link only when it is a symlink whose target is inside `<support>/cli` (best effort; no prompt — if it needs root, leave it and print the path).

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test && cd ../../release && node --test tests/inno.test.mjs && cd ../term && ~/.cargo/bin/cargo test --features test-hooks`
Expected: PASS.

- [ ] **Step 5: ⚠ MANUAL (macOS) smoke**

`cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter run -d macos`, then in a ShellX tab: `command -v shellx` → `…/ShellX/cli/shellx`; `echo $SHELLX_PANE_ID $SHELLX_TAB_ID $SHELLX_SOCKET`; `ls -l ~/Library/Application\ Support/pro.shellx.desktop/mux/` → socket `srw-------`, endpoint `-rw-------`. (The CLI commands themselves are verified after Task 10.) Tray → "Dòng lệnh" shows three items. Record results in the ledger.

- [ ] **Step 6: Format, analyze, commit**

```bash
cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH dart format --set-exit-if-changed lib test && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter analyze && cd ../..
git add apps/desktop/lib/src/cli/cli_install.dart apps/desktop/lib/src/cli/cli_install_windows.dart apps/desktop/lib/src/cli/cli_service.dart apps/desktop/lib/src/ui/terminal/agent_chip.dart apps/desktop/lib/main.dart apps/desktop/lib/src/terminal_sharing/term_binary.dart apps/desktop/lib/src/tray apps/desktop/lib/src/ui/terminal/session_tab_row.dart apps/desktop/lib/src/ui/terminal/pane_tree_view.dart apps/desktop/lib/src/ui/theme/shellx_desktop_theme.dart apps/desktop/lib/l10n apps/desktop/test/cli apps/desktop/test/tray/tray_cli_menu_test.dart apps/desktop/test/ui/agent_chip_test.dart release/windows/shellx.iss release/tests/inno.test.mjs term/src/uninstall.rs term/tests/uninstall.rs
git commit -m "feat(desktop): start the CLI host, shellx on PATH in every shell, install for other terminals, tray Command line menu, Agent chips (A7 D7, D8, D26, D27, D29)"
```

---
### Task 10: Rust — the command runner, notify fallbacks, browser helpers, skills, `agent-skills/` (D10–D25, D30, D35)

**Files:**
- Create: `term/src/api/run.rs`, `term/src/api/output.rs`, `term/src/api/browser_js.rs`, `term/src/api/skills.rs`, `agent-skills/shellx/SKILL.md`, `agent-skills/shellx/reference.md`
- Modify: `term/src/api/mod.rs` (modules + real `main`), `term/tests/cli_dispatch.rs` (un-ignore)
- Test: unit tests in `run.rs`, `output.rs`, `browser_js.rs`, `skills.rs`

**Interfaces:**
- Consumes: Task 3 (`Value`, `to_json`, `json_string`, `Message`, `Session`, `ApiError`, `connect`, `MuxEndpoint`, `endpoint::{parse, default_path}`), Task 4 (`Parsed`, `parse`, `Invocation`, `help_text`, `completion_script`, `COMMANDS`).
- Produces:
  - `run.rs`: `pub struct Ctx<'a> { pub env: &'a dyn Fn(&str) -> Option<String>, pub out: &'a mut dyn Write, pub err: &'a mut dyn Write, pub stdin: &'a mut dyn Read, pub stdin_is_tty: bool, pub cwd: PathBuf, pub home: Option<PathBuf>, pub tty: Option<&'a mut dyn Write>, pub shared_terminal: bool, pub connect: &'a dyn Fn(Option<&str>) -> Result<Box<dyn Session>, ApiError> }`; `pub fn run(p: &Parsed, ctx: &mut Ctx) -> i32`.
  - `output.rs`: `pub fn result_json(m: &Message) -> Value` (top-level `pane`/`tab`/`workspace` ids → `"p…"`/`"t…"`/`"w:…"`), `pub fn ls_json(m: &Message) -> Value`, `pub fn ls_human(m: &Message, home: Option<&Path>) -> String`, `pub fn ls_ids(m: &Message) -> String`, `pub fn event_json(m: &Message) -> Value`.
  - `browser_js.rs`: `pub fn query(selector: &str, limit: i64) -> String`, `pub fn click(selector: &str) -> String`, `pub fn fill(selector: &str, text: &str) -> String`.
  - `skills.rs`: `pub const SKILL: &str`, `pub const REFERENCE: &str` (`include_str!`), `pub fn install(p: &Parsed, ctx: &mut Ctx) -> Result<(), ApiError>`, `pub fn print(p: &Parsed, ctx: &mut Ctx) -> Result<(), ApiError>`; `pub const CODEX_SKILLS_DIR: &str = ".codex/skills"`.

- [ ] **Step 1: Write the skill files**

`agent-skills/shellx/SKILL.md`:

````markdown
---
name: shellx
description: Drive the ShellX terminal from the command line — split a pane to run a dev server, read its output, wait for a pattern, open a browser pane on localhost and inspect it, and notify the user. Use when $SHELLX is set (you run inside a ShellX pane) or the user asks to use ShellX panes, tabs or its browser.
---

# ShellX command line

You are inside ShellX when `$SHELLX` is `1`. `$SHELLX_PANE_ID` is your pane, `$SHELLX_TAB_ID` your tab. The `shellx` command talks to the ShellX window over a private local socket.

## Rules

- Never take the user's focus: do not pass `--focus` or `--raise` unless the user asked.
- Never close panes or tabs you did not create. Keep the ids you create and close only those.
- Use `--json` whenever you parse output. Ids look like `p123` (pane), `t123` (tab), `w:abc` (workspace), `p-2` (browser pane).
- `send` types like a paste. Prefer `--cmd` on `split`/`new-tab` to start a program.
- If a command exits 6 with `cli_disabled`, tell the user to enable "Allow controlling ShellX from the command line" in the ShellX tray menu. Exit 3 means ShellX is not running.

## Recipes

Run a dev server next to you and wait until it is ready:

```bash
p=$(shellx split --right --cmd "npm run dev")
shellx wait "$p" --match 'ready|listening|Local:' --timeout 60
shellx read "$p" --lines 40
```

Run a command in a pane and wait for it to finish:

```bash
shellx send "$p" --text "npm test" --enter
shellx wait "$p" --idle --timeout 600
shellx read "$p" --lines 200
```

Open the app in a browser pane and check it:

```bash
b=$(shellx browser open http://localhost:5173 --pane "$p")
shellx browser wait "$b"
shellx browser eval "$b" --script 'return document.title'
shellx browser query "$b" 'h1'
shellx browser console "$b" --level error
shellx browser screenshot "$b" --out /tmp/page.png
```

Tell the user you are done (shows on their computer and phone):

```bash
shellx notify --title "Claude" "Tests pass — ready for review"
```

See everything that is open: `shellx ls` (or `shellx ls --json`). Full reference: `shellx skills print reference`.

## Exit codes

0 ok · 1 error · 2 usage · 3 ShellX not running · 4 not found · 5 timeout · 6 refused · 7 ShellX too old · 8 ShellX window closed
````

`agent-skills/shellx/reference.md` — one section per command in `COMMANDS` order, each with the usage line, every flag, the JSON result shape and the exit codes it can return. Generate the first draft with `./target/debug/shellx-term cli help <command>` for every command, then add, by hand: the target syntax (D12: `p<id>`, `t<id>`, `w:<id>`/name, `@self`, `@tab`, `@focused`; bare numbers mean a pane except for `rename`/`workspace move`), the `ls --json` schema (spec §3.4), the event kinds (D24: the first pane of a new tab is reported as `tab.opened` only; `notice` events carry the notice kind in `type`), the `--cmd` readiness rule (D16), the `read` rules (D20: screen by default, `--lines` includes scrollback, `--ansi` is SGR only), the `wait` rules (D21, including "regex is JavaScript/Dart syntax, multi-line") and the browser origin gate (A6 D20: eval/screenshot/console/network only on localhost pages unless the user enabled "Allow agents to control every page").

- [ ] **Step 2: Write the failing tests**

At the bottom of `term/src/api/run.rs`:

```rust
#[cfg(test)]
mod tests {
    use super::*;
    use crate::api::args::{parse, Invocation};
    use std::cell::RefCell;
    use std::collections::VecDeque;
    use std::rc::Rc;

    type Log = Rc<RefCell<Vec<Message>>>;

    struct Fake {
        log: Log,
        caps: Vec<&'static str>,
        answers: VecDeque<(&'static str, Result<Message, ApiError>)>,
        events: VecDeque<Message>,
    }

    impl Session for Fake {
        fn request(&mut self, t: &str, fields: Vec<(&str, Value)>) -> Result<Message, ApiError> {
            self.log.borrow_mut().push(Message::new(t, fields));
            if t == "api.version" {
                let caps = self.caps.iter().map(|c| Value::text(*c)).collect();
                return Ok(Message::new("result", vec![("api", Value::Int(1)), ("caps", Value::Array(caps))]));
            }
            match self.answers.iter().position(|(n, _)| *n == t) {
                Some(i) => self.answers.remove(i).unwrap().1,
                None => Ok(Message::new("result", vec![])),
            }
        }
        fn next_event(&mut self) -> Result<Message, ApiError> {
            self.events.pop_front().ok_or(ApiError::NotRunning("closed".into()))
        }
    }

    const ALL: &[&str] = &[
        "cli.notify", "cli.events.subscribe", "ui.ls", "ui.tab.new", "ui.tab.rename", "ui.pane.split",
        "ui.focus", "ui.close", "ui.pane.send", "ui.pane.read", "ui.pane.wait", "ui.workspace.new",
        "ui.workspace.rename", "ui.workspace.move", "ui.browser",
    ];

    struct Out {
        code: i32,
        out: String,
        err: String,
        log: Vec<Message>,
        tty: String,
        connected: bool,
    }

    fn ok(fields: Vec<(&str, Value)>) -> Result<Message, ApiError> {
        Ok(Message::new("result", fields))
    }
    fn remote(code: &str, message: &str) -> Result<Message, ApiError> {
        Err(ApiError::Remote { code: code.into(), message: message.into() })
    }

    fn go(
        args: &[&str],
        env: &[(&str, &str)],
        answers: Vec<(&'static str, Result<Message, ApiError>)>,
        stdin: &str,
        opts: (bool, bool, Option<ApiError>), // (has tty, shared terminal, connect error)
    ) -> Out {
        let args: Vec<String> = args.iter().map(|s| s.to_string()).collect();
        let Ok(Invocation::Run(p)) = parse(&args) else { panic!("not a run") };
        let env: Vec<(String, String)> = env.iter().map(|(k, v)| (k.to_string(), v.to_string())).collect();
        let get = move |k: &str| env.iter().find(|(n, _)| n == k).map(|(_, v)| v.clone());
        let log: Log = Rc::new(RefCell::new(vec![]));
        let connected = Rc::new(RefCell::new(false));
        let answers = RefCell::new(Some(answers));
        let (log2, connected2, err) = (log.clone(), connected.clone(), opts.2.clone());
        let connect = move |_: Option<&str>| -> Result<Box<dyn Session>, ApiError> {
            *connected2.borrow_mut() = true;
            if let Some(e) = err.clone() {
                return Err(e);
            }
            Ok(Box::new(Fake {
                log: log2.clone(),
                caps: ALL.to_vec(),
                answers: answers.borrow_mut().take().unwrap_or_default().into(),
                events: VecDeque::new(),
            }))
        };
        let (mut out, mut errb, mut tty) = (Vec::new(), Vec::new(), Vec::new());
        let mut input = stdin.as_bytes();
        let code = {
            let mut ctx = Ctx {
                env: &get,
                out: &mut out,
                err: &mut errb,
                stdin: &mut input,
                stdin_is_tty: false,
                cwd: PathBuf::from("/work"),
                home: Some(PathBuf::from("/Users/me")),
                tty: if opts.0 { Some(&mut tty as &mut dyn Write) } else { None },
                shared_terminal: opts.1,
                connect: &connect,
            };
            run(&p, &mut ctx)
        };
        let log = log.borrow().clone();
        Out {
            code,
            out: String::from_utf8(out).unwrap(),
            err: String::from_utf8(errb).unwrap(),
            log,
            tty: String::from_utf8(tty).unwrap(),
            connected: *connected.borrow(),
        }
    }

    const PLAIN: (bool, bool, Option<ApiError>) = (false, false, None);

    fn sent<'a>(o: &'a Out, t: &str) -> &'a Message {
        o.log.iter().find(|m| m.t == t).unwrap_or_else(|| panic!("no {t} in {:?}", o.log))
    }

    #[test]
    fn split_defaults_to_self_and_prints_only_the_id() {
        let o = go(&["split", "--cmd", "npm run dev"], &[("SHELLX_PANE_ID", "100")],
            vec![("ui.pane.split", ok(vec![("pane", Value::Int(102)), ("tab", Value::Int(100))]))], "", PLAIN);
        assert_eq!((o.code, o.out.as_str()), (0, "p102\n"));
        let m = sent(&o, "ui.pane.split");
        assert_eq!(m.get("pane"), Some(&Value::Int(100)));
        assert_eq!(m.get("direction"), Some(&Value::text("right")));
        assert_eq!(m.get("cmd"), Some(&Value::text("npm run dev")));
        assert_eq!(m.get("focus"), Some(&Value::Bool(false)));
        let outside = go(&["split", "--down"], &[], vec![], "", PLAIN);
        let m = sent(&outside, "ui.pane.split");
        assert_eq!(m.get("pane"), Some(&Value::text("@focused")));
        assert_eq!(m.get("direction"), Some(&Value::text("down")));
    }

    #[test]
    fn new_tab_absolutizes_cwd_and_json_uses_prefixed_ids() {
        let o = go(&["new-tab", "--cwd", "app", "--json"], &[],
            vec![("ui.tab.new", ok(vec![("tab", Value::Int(101)), ("pane", Value::Int(101))]))], "", PLAIN);
        assert_eq!(sent(&o, "ui.tab.new").get("cwd"), Some(&Value::text("/work/app")));
        assert_eq!(o.out, "{\"tab\":\"t101\",\"pane\":\"p101\"}\n");
    }

    #[test]
    fn send_refuses_oversize_stdin_before_connecting() {
        let big = "x".repeat(49_153);
        let o = go(&["send", "p1", "--stdin"], &[], vec![], &big, PLAIN);
        assert_eq!(o.code, 2);
        assert!(!o.connected);
        let k = go(&["send", "1", "--key", "ctrl-c", "--key", "up", "--enter"], &[], vec![], "", PLAIN);
        let m = sent(&k, "ui.pane.send");
        assert_eq!(m.get("keys"), Some(&Value::Array(vec![Value::text("ctrl-c"), Value::text("up")])));
        assert_eq!(m.get("enter"), Some(&Value::Bool(true)));
    }

    #[test]
    fn read_follows_pages() {
        let o = go(&["read", "p1", "--lines", "500"], &[], vec![
            ("ui.pane.read", ok(vec![("text", Value::text("a\nb\n")), ("next", Value::Int(2))])),
            ("ui.pane.read", ok(vec![("text", Value::text("c\n"))])),
        ], "", PLAIN);
        assert_eq!(o.out, "a\nb\nc\n");
        let reads: Vec<_> = o.log.iter().filter(|m| m.t == "ui.pane.read").collect();
        assert_eq!(reads[1].get("offset"), Some(&Value::Int(2)));
        assert_eq!(reads[0].get("lines"), Some(&Value::Int(500)));
    }

    #[test]
    fn wait_modes_and_timeouts() {
        assert_eq!(go(&["wait", "p1"], &[], vec![], "", PLAIN).code, 2);
        assert_eq!(go(&["wait", "p1", "--idle", "--exit"], &[], vec![], "", PLAIN).code, 2);
        let e = go(&["wait", "p1", "--exit"], &[], vec![("ui.pane.wait", ok(vec![("exitCode", Value::Int(3))]))], "", PLAIN);
        assert_eq!((e.code, e.out.as_str()), (0, "3\n"));
        let m = go(&["wait", "p1", "--match", "ready", "--timeout", "1.5", "--from-now"], &[],
            vec![("ui.pane.wait", ok(vec![("match", Value::text("ready")), ("line", Value::text("ready in 4 ms"))]))], "", PLAIN);
        assert_eq!(m.out, "ready in 4 ms\n");
        let w = sent(&m, "ui.pane.wait");
        assert_eq!(w.get("timeoutMs"), Some(&Value::Int(1500)));
        assert_eq!(w.get("fromNow"), Some(&Value::Bool(true)));
        let t = go(&["wait", "p1", "--idle"], &[], vec![("ui.pane.wait", remote("timeout", "timed out"))], "", PLAIN);
        assert_eq!(t.code, 5);
        assert_eq!(go(&["wait", "p1", "--idle", "--timeout", "3601"], &[], vec![], "", PLAIN).code, 2);
    }

    #[test]
    fn errors_human_and_json() {
        let h = go(&["read", "p1"], &[], vec![("ui.pane.read", remote("not_found", "no pane p1"))], "", PLAIN);
        assert_eq!(h.code, 4);
        assert_eq!(h.err, "shellx: no pane p1 (not_found)\n");
        let j = go(&["read", "p1", "--json"], &[], vec![("ui.pane.read", remote("not_found", "no pane p1"))], "", PLAIN);
        assert_eq!(j.out, "{\"error\":{\"code\":\"not_found\",\"message\":\"no pane p1\"}}\n");
        let n = go(&["ls"], &[], vec![], "", (false, false, Some(ApiError::NotRunning("ShellX is not running".into()))));
        assert_eq!(n.code, 3);
    }

    #[test]
    fn missing_cap_is_incompatible() {
        // A host without ui.browser (A6 absent).
        let args: Vec<String> = ["browser", "ls"].iter().map(|s| s.to_string()).collect();
        let Ok(Invocation::Run(p)) = parse(&args) else { panic!() };
        let get = |_: &str| None;
        let connect = |_: Option<&str>| -> Result<Box<dyn Session>, ApiError> {
            Ok(Box::new(Fake { log: Rc::new(RefCell::new(vec![])), caps: vec!["ui.ls"], answers: VecDeque::new(), events: VecDeque::new() }))
        };
        let (mut out, mut err) = (Vec::new(), Vec::new());
        let mut input: &[u8] = b"";
        let mut ctx = Ctx { env: &get, out: &mut out, err: &mut err, stdin: &mut input, stdin_is_tty: false,
            cwd: PathBuf::from("/"), home: None, tty: None, shared_terminal: false, connect: &connect };
        assert_eq!(run(&p, &mut ctx), 7);
        assert!(String::from_utf8(err).unwrap().contains("update ShellX"));
    }

    #[test]
    fn targets() {
        assert_eq!(go(&["read", "@self"], &[], vec![], "", PLAIN).code, 2);
        let f = go(&["focus", "12"], &[], vec![], "", PLAIN);
        assert_eq!(sent(&f, "ui.focus").get("pane"), Some(&Value::Int(12)));
        let t = go(&["focus", "t5", "--raise"], &[], vec![], "", PLAIN);
        assert_eq!(sent(&t, "ui.focus").get("tab"), Some(&Value::Int(5)));
        assert_eq!(sent(&t, "ui.focus").get("raise"), Some(&Value::Bool(true)));
        let b = go(&["browser", "reload", "p-3"], &[], vec![], "", PLAIN);
        assert_eq!(sent(&b, "ui.browser.reload").get("pane"), Some(&Value::Int(-3)));
        let r = go(&["rename", "@tab", "build", "server"], &[("SHELLX_TAB_ID", "7")], vec![], "", PLAIN);
        let m = sent(&r, "ui.tab.rename");
        assert_eq!((m.get("tab"), m.get("name")), (Some(&Value::Int(7)), Some(&Value::text("build server"))));
        assert_eq!(go(&["send", "t5", "--text", "x"], &[], vec![], "", PLAIN).code, 2);
    }

    #[test]
    fn notify_paths() {
        // (1) in a pane: the API with the pane.
        let a = go(&["notify", "Build", "xong"], &[("SHELLX_PANE_ID", "12")], vec![], "", PLAIN);
        let m = sent(&a, "cli.notify");
        assert_eq!((m.get("pane"), m.get("body")), (Some(&Value::Int(12)), Some(&Value::text("Build xong"))));
        // (2) a shared terminal without a pane: OSC 777 to the tty, no socket.
        let b = go(&["notify", "--title", "CI", "ok\u{7}\u{1b}x"], &[], vec![], "", (true, true, None));
        assert!(!b.connected);
        assert_eq!(b.tty, "\u{1b}]777;notify;CI;okx\u{7}");
        // Not running, in a pane with a tty: OSC fallback, exit 0.
        let c = go(&["notify", "x"], &[("SHELLX_PANE_ID", "12")], vec![], "", (true, false, Some(ApiError::NotRunning("no".into()))));
        assert_eq!((c.code, c.tty.as_str()), (0, "\u{1b}]777;notify;;x\u{7}"));
        // Not running, nowhere to fall back: exit 3.
        let d = go(&["notify", "x"], &[], vec![], "", (false, false, Some(ApiError::NotRunning("no".into()))));
        assert_eq!(d.code, 3);
    }

    #[test]
    fn browser_eval_prints_raw_json_and_helpers_escape() {
        let e = go(&["browser", "eval", "p-1", "--script", "return {a: 1}"], &[],
            vec![("ui.browser.eval", ok(vec![("json", Value::text("{\"a\":1}"))]))], "", PLAIN);
        assert_eq!(e.out, "{\"a\":1}\n");
        let f = go(&["browser", "fill", "p-1", "input[name=\"q\"]", "it's", "\"x\""], &[], vec![], "", PLAIN);
        let script = sent(&f, "ui.browser.eval").get("script").and_then(Value::as_str).unwrap().to_string();
        assert!(script.contains(r#""input[name=\"q\"]""#), "{script}");
        assert!(script.contains(r#""it's \"x\"""#), "{script}");
        let big = "x".repeat(32 * 1024 + 1);
        assert_eq!(go(&["browser", "eval", "p-1", "--script", &big], &[], vec![], "", PLAIN).code, 2);
    }

    #[test]
    fn ls_human_and_ids() {
        let tree = Value::Array(vec![Value::map(vec![
            ("id", Value::text("default")), ("name", Value::text("Default")), ("current", Value::Bool(true)),
            ("tabs", Value::Array(vec![Value::map(vec![
                ("id", Value::Int(100)), ("title", Value::text("build")), ("selected", Value::Bool(true)),
                ("unread", Value::Int(2)), ("agent", Value::Bool(false)),
                ("panes", Value::Array(vec![Value::map(vec![
                    ("id", Value::Int(100)), ("kind", Value::text("terminal")), ("title", Value::text("zsh")),
                    ("cwd", Value::text("/Users/me/app")), ("branch", Value::text("main")),
                    ("ports", Value::Array(vec![Value::Int(3000)])), ("focused", Value::Bool(true)),
                ])])),
            ])])),
        ])]);
        let o = go(&["ls"], &[], vec![("ui.ls", ok(vec![("workspaces", tree.clone())]))], "", PLAIN);
        assert!(o.out.contains("t100") && o.out.contains("p100") && o.out.contains("~/app")
            && o.out.contains("main") && o.out.contains(":3000") && o.out.contains("●2"), "{}", o.out);
        let ids = go(&["ls", "--ids"], &[], vec![("ui.ls", ok(vec![("workspaces", tree)]))], "", PLAIN);
        assert_eq!(ids.out, "t100\np100\n");
    }

    #[test]
    fn events_print_json_lines_until_closed() {
        let args: Vec<String> = ["events", "--follow", "--kinds", "tab.opened,notice"].iter().map(|s| s.to_string()).collect();
        let Ok(Invocation::Run(p)) = parse(&args) else { panic!() };
        let log: Log = Rc::new(RefCell::new(vec![]));
        let l2 = log.clone();
        let connect = move |_: Option<&str>| -> Result<Box<dyn Session>, ApiError> {
            Ok(Box::new(Fake {
                log: l2.clone(),
                caps: ALL.to_vec(),
                answers: VecDeque::new(),
                events: VecDeque::from(vec![
                    Message::new("event", vec![("kind", Value::text("tab.opened")), ("tab", Value::Int(5))]),
                ]),
            }))
        };
        let get = |_: &str| None;
        let (mut out, mut err) = (Vec::new(), Vec::new());
        let mut input: &[u8] = b"";
        let mut ctx = Ctx { env: &get, out: &mut out, err: &mut err, stdin: &mut input, stdin_is_tty: false,
            cwd: PathBuf::from("/"), home: None, tty: None, shared_terminal: false, connect: &connect };
        assert_eq!(run(&p, &mut ctx), 3); // ShellX closed the stream
        assert_eq!(String::from_utf8(out).unwrap(), "{\"kind\":\"tab.opened\",\"tab\":\"t5\"}\n");
        let sub = log.borrow().iter().find(|m| m.t == "cli.events.subscribe").unwrap().clone();
        assert_eq!(sub.get("kinds"), Some(&Value::Array(vec![Value::text("tab.opened"), Value::text("notice")])));
    }
}
```

`term/src/api/skills.rs` tests:

```rust
#[cfg(test)]
mod tests {
    use super::*;
    use crate::api::args::{parse, Invocation};
    use crate::api::client::{ApiError, Session};
    use std::path::PathBuf;

    fn run_skills(args: &[&str], home: &std::path::Path, stdin: &str, tty: bool) -> (i32, String, String) {
        let args: Vec<String> = args.iter().map(|s| s.to_string()).collect();
        let Ok(Invocation::Run(p)) = parse(&args) else { panic!() };
        let get = |_: &str| None;
        let connect = |_: Option<&str>| -> Result<Box<dyn Session>, ApiError> { panic!("skills never connect") };
        let (mut out, mut err) = (Vec::new(), Vec::new());
        let mut input = stdin.as_bytes();
        let code = {
            let mut ctx = crate::api::run::Ctx { env: &get, out: &mut out, err: &mut err, stdin: &mut input,
                stdin_is_tty: tty, cwd: PathBuf::from("/"), home: Some(home.to_path_buf()), tty: None,
                shared_terminal: false, connect: &connect };
            crate::api::run::run(&p, &mut ctx)
        };
        (code, String::from_utf8(out).unwrap(), String::from_utf8(err).unwrap())
    }

    fn temp_home(name: &str) -> PathBuf {
        let d = std::env::temp_dir().join(format!("shellx-skills-{}-{name}", std::process::id()));
        let _ = std::fs::remove_dir_all(&d);
        std::fs::create_dir_all(&d).unwrap();
        d
    }

    #[test]
    fn embedded_files_cover_every_command() {
        assert!(SKILL.starts_with("---\nname: shellx\n"));
        for c in crate::api::args::COMMANDS {
            assert!(REFERENCE.contains(&format!("shellx {}", c.path.join(" "))), "{:?}", c.path);
        }
    }

    #[test]
    fn install_asks_before_overwriting() {
        let home = temp_home("ask");
        let target = home.join(".claude/skills/shellx/SKILL.md");
        assert_eq!(run_skills(&["skills", "install", "--claude"], &home, "", false).0, 0);
        assert_eq!(std::fs::read_to_string(&target).unwrap(), SKILL);
        let (code, out, _) = run_skills(&["skills", "install", "--claude"], &home, "", false);
        assert_eq!(code, 0);
        assert!(out.contains("up to date"));
        std::fs::write(&target, "edited").unwrap();
        assert_eq!(run_skills(&["skills", "install", "--claude"], &home, "", false).0, 6);
        assert_eq!(std::fs::read_to_string(&target).unwrap(), "edited");
        assert_eq!(run_skills(&["skills", "install", "--claude"], &home, "n\n", true).0, 6);
        assert_eq!(run_skills(&["skills", "install", "--claude"], &home, "y\n", true).0, 0);
        assert_eq!(std::fs::read_to_string(&target).unwrap(), SKILL);
        std::fs::write(&target, "edited").unwrap();
        assert_eq!(run_skills(&["skills", "install", "--claude", "--force"], &home, "", false).0, 0);
        assert!(home.join(".claude/skills/shellx/reference.md").exists());
    }

    #[test]
    fn default_targets_are_existing_agent_dirs() {
        let home = temp_home("default");
        let (code, _, err) = run_skills(&["skills", "install"], &home, "", false);
        assert_eq!(code, 1);
        assert!(err.contains("--claude"), "{err}");
        std::fs::create_dir_all(home.join(".codex")).unwrap();
        assert_eq!(run_skills(&["skills", "install"], &home, "", false).0, 0);
        assert!(home.join(CODEX_SKILLS_DIR).join("shellx/SKILL.md").exists());
        assert!(!home.join(".claude").exists());
    }
}
```

`term/src/api/browser_js.rs` tests:

```rust
#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn selectors_and_text_are_json_literals() {
        let s = click("a[href=\"/x\"]</script>");
        assert!(s.contains(r#""a[href=\"/x\"]</script>""#));
        assert!(!s.contains("eval("));
        let f = fill("#q", "line1\nline2");
        assert!(f.contains(r#""line1\nline2""#));
        assert!(f.contains("dispatchEvent(new Event('input', {bubbles: true}))"));
        assert!(query("li", 5).contains(".slice(0, 5)"));
    }
}
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `cd term && ~/.cargo/bin/cargo test api::run api::skills api::browser_js`
Expected: FAIL to compile.

- [ ] **Step 4: Implement**

`term/src/api/mod.rs`:

```rust
pub mod args;
pub mod browser_js;
pub mod client;
pub mod endpoint;
pub mod output;
pub mod run;
pub mod skills;
pub mod value;
pub mod wire;

use std::io::{IsTerminal, Write};
use std::time::Duration;

/// Entry point of the `shellx` command (D6). Returns the exit code (D10).
pub fn main(args: Vec<std::ffi::OsString>) -> i32 {
    let args: Vec<String> = match args.into_iter().map(|a| a.into_string()).collect() {
        Ok(a) => a,
        Err(_) => {
            let _ = writeln!(std::io::stderr(), "shellx: arguments must be valid UTF-8 (usage)");
            return 2;
        }
    };
    let parsed = match args::parse(&args) {
        Err(msg) => {
            let _ = writeln!(std::io::stderr(), "shellx: {msg}");
            return 2;
        }
        Ok(args::Invocation::Help(spec)) => {
            let _ = write!(std::io::stdout(), "{}", args::help_text(spec));
            return 0;
        }
        Ok(args::Invocation::Version) => {
            let _ = writeln!(std::io::stdout(), "shellx {} (api 1)", env!("CARGO_PKG_VERSION"));
            return 0;
        }
        Ok(args::Invocation::Completions(sh)) => {
            return match args::completion_script(&sh) {
                Some(s) => {
                    let _ = write!(std::io::stdout(), "{s}");
                    0
                }
                None => {
                    let _ = writeln!(std::io::stderr(), "shellx: completions for zsh, bash or pwsh");
                    2
                }
            };
        }
        Ok(args::Invocation::Run(p)) => p,
    };
    let get = |k: &str| std::env::var(k).ok().filter(|v| !v.is_empty());
    let connect = |socket: Option<&str>| -> Result<Box<dyn client::Session>, client::ApiError> {
        let not_running = || client::ApiError::NotRunning("ShellX is not running (open ShellX and try again)".into());
        let path = endpoint::default_path(get).ok_or_else(not_running)?;
        let text = std::fs::read_to_string(path).map_err(|_| not_running())?;
        let ep = endpoint::parse(&text).ok_or_else(not_running)?;
        let address = socket.map(String::from).or_else(|| get("SHELLX_SOCKET")).unwrap_or_else(|| ep.address.clone());
        Ok(Box::new(client::connect(&ep, &address, Duration::from_secs(2))?))
    };
    #[cfg(unix)]
    let mut tty_file = std::fs::OpenOptions::new().write(true).open("/dev/tty").ok();
    #[cfg(windows)]
    let mut tty_file = std::fs::OpenOptions::new().write(true).open("CONOUT$").ok();
    let shared_terminal = shared_terminal(&get);
    let stdout = std::io::stdout();
    let stderr = std::io::stderr();
    let (mut out, mut err) = (stdout.lock(), stderr.lock());
    let stdin = std::io::stdin();
    let stdin_is_tty = stdin.is_terminal();
    let mut input = stdin.lock();
    let mut ctx = run::Ctx {
        env: &get,
        out: &mut out,
        err: &mut err,
        stdin: &mut input,
        stdin_is_tty,
        cwd: std::env::current_dir().unwrap_or_default(),
        home: get(if cfg!(windows) { "USERPROFILE" } else { "HOME" }).map(Into::into),
        tty: tty_file.as_mut().map(|f| f as &mut dyn Write),
        shared_terminal,
        connect: &connect,
    };
    run::run(&parsed, &mut ctx)
}

/// D23 (2): `$SHELLX_TERM` names this terminal — the window is shared with
/// the phone by `shellx-term wrap` (Unix: its tty path; Windows: `conpty:<pid>`).
#[allow(clippy::let_and_return)] // one binding per platform
fn shared_terminal(get: &dyn Fn(&str) -> Option<String>) -> bool {
    let Some(term) = get("SHELLX_TERM") else { return false };
    #[cfg(unix)]
    let shared = {
        // SAFETY: ttyname returns null or a pointer to a static buffer that
        // stays valid until the next ttyname call (none in between).
        let name = unsafe { libc::ttyname(0) };
        !name.is_null() && unsafe { std::ffi::CStr::from_ptr(name) }.to_string_lossy() == term
    };
    #[cfg(windows)]
    let shared = term.starts_with("conpty:");
    shared
}
```

`term/src/api/output.rs`:

```rust
//! Human and JSON renderings (D11, spec §3.4).

use super::value::Value;
use super::wire::Message;
use std::path::Path;

fn prefixed(key: &str, v: &Value) -> Value {
    match (key, v) {
        ("pane" | "focusedPane", Value::Int(n)) => Value::text(format!("p{n}")),
        ("tab" | "selectedTab", Value::Int(n)) => Value::text(format!("t{n}")),
        ("workspace", Value::Text(s)) => Value::text(format!("w:{s}")),
        _ => v.clone(),
    }
}

/// A result's fields with ids in the form users type back (`p12`, `t7`, `w:x`).
pub fn result_json(m: &Message) -> Value {
    Value::Map(m.fields.iter().map(|(k, v)| (k.clone(), prefixed(k, v))).collect())
}

pub fn event_json(m: &Message) -> Value {
    result_json(m)
}

fn map_ids(v: &Value, prefix: &str) -> Value {
    match v {
        Value::Map(m) => Value::Map(
            m.iter()
                .map(|(k, x)| match (k.as_str(), x) {
                    ("id", Value::Int(n)) => (k.clone(), Value::text(format!("{prefix}{n}"))),
                    ("id", Value::Text(s)) if prefix == "w:" => (k.clone(), Value::text(format!("w:{s}"))),
                    ("tabs", Value::Array(a)) => (k.clone(), Value::Array(a.iter().map(|t| map_ids(t, "t")).collect())),
                    ("panes", Value::Array(a)) => (k.clone(), Value::Array(a.iter().map(|p| map_ids(p, "p")).collect())),
                    _ => (k.clone(), x.clone()),
                })
                .collect(),
        ),
        _ => v.clone(),
    }
}

pub fn ls_json(m: &Message) -> Value {
    Value::Map(
        m.fields
            .iter()
            .map(|(k, v)| match (k.as_str(), v) {
                ("workspaces", Value::Array(a)) => (k.clone(), Value::Array(a.iter().map(|w| map_ids(w, "w:")).collect())),
                (_, v) => (k.clone(), prefixed(k, v)),
            })
            .collect(),
    )
}

fn arr<'a>(v: Option<&'a Value>) -> &'a [Value] {
    v.and_then(Value::as_array).unwrap_or(&[])
}

fn tilde(path: &str, home: Option<&Path>) -> String {
    match home.and_then(|h| h.to_str()) {
        Some(h) if path == h => "~".into(),
        Some(h) if path.starts_with(&format!("{h}/")) => format!("~{}", &path[h.len()..]),
        _ => path.into(),
    }
}

fn context(v: &Value, home: Option<&Path>) -> String {
    let mut parts = Vec::new();
    if let Some(c) = v.get("cwd").and_then(Value::as_str) {
        parts.push(tilde(c, home));
    }
    if let Some(b) = v.get("branch").and_then(Value::as_str) {
        parts.push(b.to_string());
    }
    for p in arr(v.get("ports")) {
        if let Some(n) = p.as_i64() {
            parts.push(format!(":{n}"));
        }
    }
    if let Some(u) = v.get("url").and_then(Value::as_str) {
        parts.push(u.to_string());
    }
    parts.join("  ")
}

pub fn ls_human(m: &Message, home: Option<&Path>) -> String {
    let mut s = String::new();
    if m.get("ui").and_then(Value::as_bool) == Some(false) {
        s.push_str("ShellX window is closed; shells still running:\n");
        for x in arr(m.get("sessions")) {
            let id = x.get("id").and_then(Value::as_i64).unwrap_or(0);
            let title = x.get("title").and_then(Value::as_str).unwrap_or("");
            s.push_str(&format!("  p{id}  {title}  {}\n", context(x, home)));
        }
        return s;
    }
    for w in arr(m.get("workspaces")) {
        let name = w.get("name").and_then(Value::as_str).unwrap_or("");
        let id = w.get("id").and_then(Value::as_str).unwrap_or("");
        let current = if w.get("current").and_then(Value::as_bool) == Some(true) { "  (current)" } else { "" };
        s.push_str(&format!("{name}  w:{id}{current}\n"));
        for t in arr(w.get("tabs")) {
            let tid = t.get("id").and_then(Value::as_i64).unwrap_or(0);
            let title = t.get("title").and_then(Value::as_str).unwrap_or("");
            let mut marks = String::new();
            if let Some(n) = t.get("unread").and_then(Value::as_i64).filter(|n| *n > 0) {
                marks.push_str(&format!("  ●{n}"));
            }
            if t.get("selected").and_then(Value::as_bool) == Some(true) {
                marks.push_str("  (selected)");
            }
            if t.get("agent").and_then(Value::as_bool) == Some(true) {
                marks.push_str("  [agent]");
            }
            s.push_str(&format!("  t{tid}  {title}{marks}\n"));
            for p in arr(t.get("panes")) {
                let pid = p.get("id").and_then(Value::as_i64).unwrap_or(0);
                let ptitle = p.get("title").and_then(Value::as_str).unwrap_or("");
                let kind = if p.get("kind").and_then(Value::as_str) == Some("browser") { " browser" } else { "" };
                let focused = if p.get("focused").and_then(Value::as_bool) == Some(true) { "  (focused)" } else { "" };
                let exited = match p.get("exitCode").and_then(Value::as_i64) {
                    Some(c) => format!("  [exited {c}]"),
                    None => String::new(),
                };
                s.push_str(&format!("    p{pid}{kind}  {ptitle}  {}{focused}{exited}\n", context(p, home)));
            }
        }
    }
    s
}

pub fn ls_ids(m: &Message) -> String {
    let mut s = String::new();
    for w in arr(m.get("workspaces")) {
        for t in arr(w.get("tabs")) {
            if let Some(id) = t.get("id").and_then(Value::as_i64) {
                s.push_str(&format!("t{id}\n"));
            }
            for p in arr(t.get("panes")) {
                if let Some(id) = p.get("id").and_then(Value::as_i64) {
                    s.push_str(&format!("p{id}\n"));
                }
            }
        }
    }
    s
}
```

(The `ls_human` test expects `~/app` from `/Users/me/app` with `home = /Users/me`; trailing double spaces are acceptable.)

`term/src/api/browser_js.rs`:

```rust
//! D25: DOM helpers built on `ui.browser.eval` (async function bodies).
//! Every caller value is a JSON string literal, never spliced raw.

use super::value::json_string;

pub fn query(selector: &str, limit: i64) -> String {
    format!(
        "const els = [...document.querySelectorAll({sel})].slice(0, {limit});\n\
         return els.map(e => ({{tag: e.tagName.toLowerCase(), text: (e.innerText || e.textContent || '').trim().slice(0, 500), value: ('value' in e) ? String(e.value) : null, href: e.href || null}}));",
        sel = json_string(selector)
    )
}

pub fn click(selector: &str) -> String {
    format!(
        "const sel = {sel};\nconst e = document.querySelector(sel);\n\
         if (!e) throw new Error('no element matches ' + sel);\n\
         e.scrollIntoView({{block: 'center'}});\ne.click();\nreturn true;",
        sel = json_string(selector)
    )
}

pub fn fill(selector: &str, text: &str) -> String {
    format!(
        "const sel = {sel};\nconst e = document.querySelector(sel);\n\
         if (!e) throw new Error('no element matches ' + sel);\n\
         e.focus();\ne.value = {text};\n\
         e.dispatchEvent(new Event('input', {{bubbles: true}}));\n\
         e.dispatchEvent(new Event('change', {{bubbles: true}}));\nreturn true;",
        sel = json_string(selector),
        text = json_string(text)
    )
}
```

`term/src/api/skills.rs`:

```rust
//! D35: the agent skill, embedded so it always matches this CLI.

use super::args::Parsed;
use super::client::ApiError;
use super::run::Ctx;
use std::io::{BufRead, Write};
use std::path::PathBuf;

pub const SKILL: &str = include_str!("../../../agent-skills/shellx/SKILL.md");
pub const REFERENCE: &str = include_str!("../../../agent-skills/shellx/reference.md");
pub const CLAUDE_SKILLS_DIR: &str = ".claude/skills";
/// Verify against the Codex documentation when implementing (spec D35).
pub const CODEX_SKILLS_DIR: &str = ".codex/skills";

pub fn print(p: &Parsed, ctx: &mut Ctx) -> Result<(), ApiError> {
    let text = match p.pos(0) {
        None | Some("SKILL.md") | Some("skill") => SKILL,
        Some("reference") | Some("reference.md") => REFERENCE,
        Some(other) => return Err(ApiError::Usage(format!("no skill file '{other}' (SKILL.md or reference)"))),
    };
    write!(ctx.out, "{text}").map_err(|e| ApiError::Io(e.to_string()))
}

pub fn install(p: &Parsed, ctx: &mut Ctx) -> Result<(), ApiError> {
    let home = ctx.home.clone().ok_or_else(|| ApiError::Usage("HOME is not set".into()))?;
    let mut targets: Vec<PathBuf> = Vec::new();
    if p.has("claude") {
        targets.push(home.join(CLAUDE_SKILLS_DIR));
    }
    if p.has("codex") {
        targets.push(home.join(CODEX_SKILLS_DIR));
    }
    if let Some(d) = p.flag("dir") {
        targets.push(PathBuf::from(d));
    }
    if targets.is_empty() {
        if home.join(".claude").is_dir() {
            targets.push(home.join(CLAUDE_SKILLS_DIR));
        }
        if home.join(".codex").is_dir() {
            targets.push(home.join(CODEX_SKILLS_DIR));
        }
    }
    if targets.is_empty() {
        return Err(ApiError::Remote {
            code: "not_installed".into(),
            message: "no ~/.claude or ~/.codex found; pass --claude, --codex or --dir DIR".into(),
        });
    }
    for base in targets {
        let dir = base.join("shellx");
        for (name, text) in [("SKILL.md", SKILL), ("reference.md", REFERENCE)] {
            let path = dir.join(name);
            match std::fs::read_to_string(&path) {
                Ok(old) if old == text => {
                    writeln!(ctx.out, "{} is up to date", path.display()).ok();
                    continue;
                }
                Ok(_) if !p.has("force") => {
                    if !ctx.stdin_is_tty {
                        return Err(ApiError::Remote {
                            code: "forbidden".into(),
                            message: format!("{} was changed; rerun with --force to overwrite", path.display()),
                        });
                    }
                    write!(ctx.err, "Overwrite {}? [y/N] ", path.display()).ok();
                    let mut line = String::new();
                    std::io::BufReader::new(&mut *ctx.stdin).read_line(&mut line).ok();
                    if !matches!(line.trim(), "y" | "Y" | "yes") {
                        return Err(ApiError::Remote { code: "forbidden".into(), message: "not overwritten".into() });
                    }
                }
                _ => {}
            }
            std::fs::create_dir_all(&dir).map_err(|e| ApiError::Io(e.to_string()))?;
            std::fs::write(&path, text).map_err(|e| ApiError::Io(e.to_string()))?;
            writeln!(ctx.out, "installed {}", path.display()).ok();
        }
    }
    Ok(())
}
```

(`not_installed` maps to exit 1 by `exit_code`'s default arm; `forbidden` to 6.)

`term/src/api/run.rs` (above the tests):

```rust
//! Runs one parsed command (A7 §3.1). Everything outside the process is in
//! [Ctx], so tests use buffers and a scripted session.

use super::args::Parsed;
use super::browser_js;
use super::client::{ApiError, Session};
use super::output;
use super::skills;
use super::value::{to_json, Value};
use super::wire::Message;
use std::io::{Read, Write};
use std::path::PathBuf;

pub struct Ctx<'a> {
    pub env: &'a dyn Fn(&str) -> Option<String>,
    pub out: &'a mut dyn Write,
    pub err: &'a mut dyn Write,
    pub stdin: &'a mut dyn Read,
    pub stdin_is_tty: bool,
    pub cwd: PathBuf,
    pub home: Option<PathBuf>,
    pub tty: Option<&'a mut dyn Write>,
    pub shared_terminal: bool,
    pub connect: &'a dyn Fn(Option<&str>) -> Result<Box<dyn Session>, ApiError>,
}

const MAX_TEXT: usize = 49_152;
const MAX_SCRIPT: usize = 32 * 1024;

fn usage(m: impl Into<String>) -> ApiError {
    ApiError::Usage(m.into())
}

pub fn run(p: &Parsed, ctx: &mut Ctx) -> i32 {
    match execute(p, ctx) {
        Ok(()) => 0,
        Err(e) => {
            let (code, message) = describe(&e);
            if p.json {
                let v = Value::map(vec![("error", Value::map(vec![("code", Value::text(code)), ("message", Value::text(message))]))]);
                let _ = writeln!(ctx.out, "{}", to_json(&v));
            } else {
                let _ = writeln!(ctx.err, "shellx: {message} ({code})");
            }
            e.exit_code()
        }
    }
}

fn describe(e: &ApiError) -> (String, String) {
    match e {
        ApiError::NotRunning(m) => ("not_running".into(), m.clone()),
        ApiError::Incompatible(m) => ("incompatible".into(), m.clone()),
        ApiError::Usage(m) => ("usage".into(), m.clone()),
        ApiError::Io(m) => ("io".into(), m.clone()),
        ApiError::Remote { code, message } => (
            code.clone(),
            if message.is_empty() { code.replace('_', " ") } else { message.clone() },
        ),
    }
}

struct Api {
    s: Box<dyn Session>,
    caps: Vec<String>,
}

impl Api {
    fn open(p: &Parsed, ctx: &mut Ctx) -> Result<Api, ApiError> {
        let mut s = (ctx.connect)(p.socket.as_deref())?;
        let v = s.request("api.version", vec![])?;
        if v.get("api").and_then(Value::as_i64) != Some(1) {
            return Err(ApiError::Incompatible("ShellX speaks another command-line API: update shellx or ShellX".into()));
        }
        let caps = v
            .get("caps")
            .and_then(Value::as_array)
            .map(|a| a.iter().filter_map(|x| x.as_str().map(String::from)).collect())
            .unwrap_or_default();
        Ok(Api { s, caps })
    }

    fn call(&mut self, t: &str, fields: Vec<(&str, Option<Value>)>) -> Result<Message, ApiError> {
        let cap = if t.starts_with("ui.browser.") { "ui.browser" } else { t };
        if !self.caps.iter().any(|c| c == cap) {
            return Err(ApiError::Incompatible(format!("this ShellX is too old for '{t}': update ShellX")));
        }
        self.s.request(t, fields.into_iter().filter_map(|(k, v)| v.map(|v| (k, v))).collect())
    }
}

#[derive(Clone, Copy, PartialEq)]
enum Want {
    Pane,
    Tab,
    Any,
}

fn env_id(ctx: &Ctx, var: &str, what: &str) -> Result<i64, ApiError> {
    (ctx.env)(var)
        .and_then(|v| v.parse().ok())
        .ok_or_else(|| usage(format!("{what} needs {var} (run inside a ShellX pane)")))
}

/// D12: user text → (`pane` | `tab`, wire value).
fn target(raw: &str, want: Want, ctx: &Ctx) -> Result<(&'static str, Value), ApiError> {
    let num = |s: &str| s.parse::<i64>().ok();
    let r = match raw {
        "@self" if want == Want::Tab => ("tab", Value::Int(env_id(ctx, "SHELLX_TAB_ID", "@self")?)),
        "@self" => ("pane", Value::Int(env_id(ctx, "SHELLX_PANE_ID", "@self")?)),
        "@tab" if want == Want::Pane => return Err(usage("@tab names a tab; this command needs a pane")),
        "@tab" => ("tab", Value::Int(env_id(ctx, "SHELLX_TAB_ID", "@tab")?)),
        "@focused" => (if want == Want::Tab { "tab" } else { "pane" }, Value::text("@focused")),
        s if s.starts_with('p') && num(&s[1..]).is_some() => {
            if want == Want::Tab {
                return Err(usage(format!("{s} is a pane; this command needs a tab (t<id>)")));
            }
            ("pane", Value::Int(num(&s[1..]).unwrap()))
        }
        s if s.starts_with('t') && num(&s[1..]).is_some() => {
            if want == Want::Pane {
                return Err(usage(format!("{s} is a tab; this command needs a pane (p<id>)")));
            }
            ("tab", Value::Int(num(&s[1..]).unwrap()))
        }
        s if num(s).is_some() => (if want == Want::Tab { "tab" } else { "pane" }, Value::Int(num(s).unwrap())),
        s => return Err(usage(format!("'{s}' is not a target (p<id>, t<id>, @self, @tab, @focused)"))),
    };
    Ok(r)
}

fn pane(raw: &str, ctx: &Ctx) -> Result<Value, ApiError> {
    Ok(target(raw, Want::Pane, ctx)?.1)
}

fn tab(raw: &str, ctx: &Ctx) -> Result<Value, ApiError> {
    Ok(target(raw, Want::Tab, ctx)?.1)
}

fn text(s: Option<&str>) -> Option<Value> {
    s.map(Value::text)
}

fn flag(p: &Parsed, name: &str) -> Option<Value> {
    Some(Value::Bool(p.has(name)))
}

fn abs_dir(d: Option<&str>, ctx: &Ctx) -> Option<Value> {
    d.map(|d| {
        let path = PathBuf::from(d);
        let full = if path.is_absolute() { path } else { ctx.cwd.join(path) };
        Value::text(full.to_string_lossy())
    })
}

fn timeout_ms(p: &Parsed, max_s: f64) -> Result<Option<Value>, ApiError> {
    match p.flag("timeout") {
        None => Ok(None),
        Some(s) => {
            let secs: f64 = s.parse().map_err(|_| usage("--timeout takes seconds"))?;
            if !(secs > 0.0 && secs <= max_s) {
                return Err(usage(format!("--timeout is between 0 and {max_s} seconds")));
            }
            Ok(Some(Value::Int((secs * 1000.0).round() as i64)))
        }
    }
}

fn int_flag(p: &Parsed, name: &str) -> Result<Option<Value>, ApiError> {
    p.flag(name)
        .map(|s| s.parse::<i64>().map(Value::Int).map_err(|_| usage(format!("--{name} takes a number"))))
        .transpose()
}

fn print_result(p: &Parsed, ctx: &mut Ctx, r: &Message, id_key: &str, prefix: &str) -> Result<(), ApiError> {
    if p.json {
        writeln!(ctx.out, "{}", to_json(&output::result_json(r))).ok();
    } else if let Some(v) = r.get(id_key) {
        match v {
            Value::Int(n) => writeln!(ctx.out, "{prefix}{n}").ok(),
            Value::Text(s) => writeln!(ctx.out, "{prefix}{s}").ok(),
            _ => None,
        };
    }
    Ok(())
}

fn quiet(p: &Parsed, ctx: &mut Ctx, r: &Message) -> Result<(), ApiError> {
    if p.json {
        writeln!(ctx.out, "{}", to_json(&output::result_json(r))).ok();
    }
    Ok(())
}

fn read_all(ctx: &mut Ctx, max: usize) -> Result<String, ApiError> {
    let mut buf = Vec::new();
    (&mut *ctx.stdin).take(max as u64 + 1).read_to_end(&mut buf).map_err(|e| ApiError::Io(e.to_string()))?;
    if buf.len() > max {
        return Err(usage(format!("input is over {} KiB", max / 1024)));
    }
    String::from_utf8(buf).map_err(|_| usage("input is not UTF-8"))
}

fn execute(p: &Parsed, ctx: &mut Ctx) -> Result<(), ApiError> {
    let path = p.spec.path.join(" ");
    match path.as_str() {
        "skills install" => return skills::install(p, ctx),
        "skills print" => return skills::print(p, ctx),
        "notify" => return notify(p, ctx),
        _ => {}
    }
    // Everything that can fail locally fails before connecting.
    let prepared = prepare(p, ctx, &path)?;
    let mut api = Api::open(p, ctx)?;
    match prepared {
        Prepared::Simple { t, fields, id_key, prefix } => {
            let r = api.call(t, fields)?;
            match id_key {
                Some(k) => print_result(p, ctx, &r, k, prefix),
                None => quiet(p, ctx, &r),
            }
        }
        Prepared::Ls => {
            let r = api.call("ui.ls", vec![])?;
            if p.json {
                writeln!(ctx.out, "{}", to_json(&output::ls_json(&r))).ok();
            } else if p.has("ids") {
                write!(ctx.out, "{}", output::ls_ids(&r)).ok();
            } else {
                let home = ctx.home.clone();
                write!(ctx.out, "{}", output::ls_human(&r, home.as_deref())).ok();
            }
            Ok(())
        }
        Prepared::Read { pane, lines, ansi } => {
            let mut offset = 0i64;
            let mut all = String::new();
            loop {
                let r = api.call("ui.pane.read", vec![
                    ("pane", Some(pane.clone())),
                    ("lines", lines.clone()),
                    ("ansi", Some(Value::Bool(ansi))),
                    ("offset", (offset > 0).then_some(Value::Int(offset))),
                ])?;
                let page = r.get("text").and_then(Value::as_str).unwrap_or("");
                if p.json {
                    all.push_str(page);
                } else {
                    write!(ctx.out, "{page}").ok();
                }
                match r.get("next").and_then(Value::as_i64) {
                    Some(n) => offset = n,
                    None => break,
                }
            }
            if p.json {
                writeln!(ctx.out, "{}", to_json(&Value::map(vec![("text", Value::text(all))]))).ok();
            }
            Ok(())
        }
        Prepared::Wait { fields, mode } => {
            let r = api.call("ui.pane.wait", fields)?;
            if p.json {
                writeln!(ctx.out, "{}", to_json(&output::result_json(&r))).ok();
            } else if mode == "exit" {
                let code = r.get("exitCode").and_then(Value::as_i64).map(|c| c.to_string()).unwrap_or_else(|| "null".into());
                writeln!(ctx.out, "{code}").ok();
            } else if mode == "match" {
                writeln!(ctx.out, "{}", r.get("line").and_then(Value::as_str).unwrap_or("")).ok();
            }
            Ok(())
        }
        Prepared::Events { kinds } => {
            api.call("cli.events.subscribe", vec![("kinds", kinds)])?;
            if let Some(secs) = p.flag("for").and_then(|s| s.parse::<f64>().ok()).filter(|s| *s > 0.0) {
                std::thread::spawn(move || {
                    std::thread::sleep(std::time::Duration::from_secs_f64(secs));
                    std::process::exit(0);
                });
            } else if !p.has("follow") {
                return Ok(());
            }
            loop {
                let e = api.s.next_event()?;
                writeln!(ctx.out, "{}", to_json(&output::event_json(&e))).ok();
                ctx.out.flush().ok();
            }
        }
        Prepared::Eval { pane, script, print } => {
            let r = api.call("ui.browser.eval", vec![("pane", Some(pane)), ("script", Some(Value::text(script))), ("timeoutMs", timeout_ms(p, 30.0)?)])?;
            let json = r.get("json").and_then(Value::as_str).unwrap_or("null");
            if print || p.json {
                writeln!(ctx.out, "{json}").ok();
            }
            Ok(())
        }
        Prepared::Screenshot { pane } => {
            let r = api.call("ui.browser.screenshot", vec![("pane", Some(pane))])?;
            let from = r.get("path").and_then(Value::as_str).unwrap_or("").to_string();
            let shown = match p.flag("out") {
                Some(out) => {
                    let dest = if PathBuf::from(out).is_absolute() { PathBuf::from(out) } else { ctx.cwd.join(out) };
                    std::fs::copy(&from, &dest).map_err(|e| ApiError::Io(e.to_string()))?;
                    dest.to_string_lossy().into_owned()
                }
                None => from,
            };
            if p.json {
                let mut v = output::result_json(&r);
                if let Value::Map(m) = &mut v {
                    m.retain(|(k, _)| k != "path");
                    m.push(("path".into(), Value::text(shown)));
                }
                writeln!(ctx.out, "{}", to_json(&v)).ok();
            } else {
                writeln!(ctx.out, "{shown}").ok();
            }
            Ok(())
        }
        Prepared::Entries { t, fields } => {
            let r = api.call(t, fields)?;
            if p.json {
                writeln!(ctx.out, "{}", to_json(&output::result_json(&r))).ok();
                return Ok(());
            }
            for e in r.get("entries").and_then(Value::as_array).unwrap_or(&[]) {
                let seq = e.get("seq").and_then(Value::as_i64).unwrap_or(0);
                if t == "ui.browser.console" {
                    let level = e.get("level").and_then(Value::as_str).unwrap_or("");
                    let text = e.get("text").and_then(Value::as_str).unwrap_or("");
                    writeln!(ctx.out, "{seq}  {level:<5}  {text}").ok();
                } else {
                    let method = e.get("method").and_then(Value::as_str).unwrap_or("");
                    let status = e.get("status").and_then(Value::as_i64).map(|s| s.to_string()).unwrap_or_default();
                    let url = e.get("url").and_then(Value::as_str).unwrap_or("");
                    writeln!(ctx.out, "{seq}  {method:<6} {status:<3}  {url}").ok();
                }
            }
            Ok(())
        }
        Prepared::BrowserList => {
            let r = api.call("ui.browser.list", vec![])?;
            if p.json {
                writeln!(ctx.out, "{}", to_json(&output::result_json(&r))).ok();
                return Ok(());
            }
            for x in r.get("panes").and_then(Value::as_array).unwrap_or(&[]) {
                let id = x.get("pane").and_then(Value::as_i64).unwrap_or(0);
                let t = x.get("tab").and_then(Value::as_i64).unwrap_or(0);
                let title = x.get("title").and_then(Value::as_str).unwrap_or("");
                let url = x.get("url").and_then(Value::as_str).unwrap_or("");
                writeln!(ctx.out, "p{id}  t{t}  {title}  {url}").ok();
            }
            Ok(())
        }
    }
}

enum Prepared {
    Simple { t: &'static str, fields: Vec<(&'static str, Option<Value>)>, id_key: Option<&'static str>, prefix: &'static str },
    Ls,
    Read { pane: Value, lines: Option<Value>, ansi: bool },
    Wait { fields: Vec<(&'static str, Option<Value>)>, mode: &'static str },
    Events { kinds: Option<Value> },
    Eval { pane: Value, script: String, print: bool },
    Screenshot { pane: Value },
    Entries { t: &'static str, fields: Vec<(&'static str, Option<Value>)> },
    BrowserList,
}

fn simple(t: &'static str, fields: Vec<(&'static str, Option<Value>)>) -> Prepared {
    Prepared::Simple { t, fields, id_key: None, prefix: "" }
}

fn prepare(p: &Parsed, ctx: &mut Ctx, path: &str) -> Result<Prepared, ApiError> {
    let pos = |i: usize| p.pos(i).unwrap_or("");
    let rest = |i: usize| p.positionals[i.min(p.positionals.len())..].join(" ");
    Ok(match path {
        "ls" => Prepared::Ls,
        "new-tab" => Prepared::Simple {
            t: "ui.tab.new",
            fields: vec![("workspace", text(p.flag("workspace"))), ("cwd", abs_dir(p.flag("cwd"), ctx)), ("cmd", text(p.flag("cmd"))), ("focus", flag(p, "focus"))],
            id_key: Some("tab"),
            prefix: "t",
        },
        "split" => {
            if p.has("right") && p.has("down") {
                return Err(usage("choose --right or --down"));
            }
            let target = match p.flag("pane") {
                Some(r) => pane(r, ctx)?,
                None if (ctx.env)("SHELLX_PANE_ID").is_some() => pane("@self", ctx)?,
                None => Value::text("@focused"),
            };
            if p.flag("cmd").is_some_and(|c| c.len() > 16_384) {
                return Err(usage("--cmd is over 16 KiB"));
            }
            Prepared::Simple {
                t: "ui.pane.split",
                fields: vec![
                    ("pane", Some(target)),
                    ("direction", Some(Value::text(if p.has("down") { "down" } else { "right" }))),
                    ("cwd", abs_dir(p.flag("cwd"), ctx)),
                    ("cmd", text(p.flag("cmd"))),
                    ("focus", flag(p, "focus")),
                ],
                id_key: Some("pane"),
                prefix: "p",
            }
        }
        "focus" | "close" => {
            let (k, v) = target(pos(0), Want::Any, ctx)?;
            let extra = if path == "focus" { ("raise", flag(p, "raise")) } else { ("force", flag(p, "force")) };
            simple(if path == "focus" { "ui.focus" } else { "ui.close" }, vec![(k, Some(v)), extra])
        }
        "send" => {
            let pane = pane(pos(0), ctx)?;
            let body = match (p.flag("text"), p.has("stdin")) {
                (Some(_), true) => return Err(usage("use --text or --stdin, not both")),
                (Some(t), false) => Some(t.to_string()),
                (None, true) => Some(read_all(ctx, MAX_TEXT)?),
                (None, false) => None,
            };
            if body.as_ref().is_some_and(|b| b.len() > MAX_TEXT) {
                return Err(usage("text is over 48 KiB"));
            }
            let keys: Vec<Value> = p.all("key").into_iter().map(Value::text).collect();
            if body.is_none() && keys.is_empty() && !p.has("enter") {
                return Err(usage("nothing to send: --text, --stdin, --key or --enter"));
            }
            simple("ui.pane.send", vec![
                ("pane", Some(pane)),
                ("text", body.map(Value::text)),
                ("keys", (!keys.is_empty()).then_some(Value::Array(keys))),
                ("enter", flag(p, "enter")),
            ])
        }
        "read" => {
            let lines = int_flag(p, "lines")?;
            if let Some(Value::Int(n)) = lines {
                if !(1..=10_000).contains(&n) {
                    return Err(usage("--lines is 1–10000"));
                }
            }
            Prepared::Read { pane: pane(pos(0), ctx)?, lines, ansi: p.has("ansi") }
        }
        "rename" => simple("ui.tab.rename", vec![("tab", Some(tab(pos(0), ctx)?)), ("name", Some(Value::text(rest(1))))]),
        "workspace new" => Prepared::Simple {
            t: "ui.workspace.new",
            fields: vec![("name", (!p.positionals.is_empty()).then(|| Value::text(rest(0)))), ("focus", flag(p, "focus"))],
            id_key: Some("workspace"),
            prefix: "w:",
        },
        "workspace rename" => simple("ui.workspace.rename", vec![("workspace", Some(Value::text(pos(0)))), ("name", Some(Value::text(rest(1))))]),
        "workspace move" => simple("ui.workspace.move", vec![("tab", Some(tab(pos(0), ctx)?)), ("workspace", Some(Value::text(pos(1))))]),
        "wait" => {
            let modes: Vec<&'static str> = [("idle", p.has("idle")), ("exit", p.has("exit")), ("match", p.flag("match").is_some())]
                .into_iter()
                .filter(|(_, on)| *on)
                .map(|(m, _)| m)
                .collect();
            let [mode] = modes[..] else {
                return Err(usage("choose exactly one of --idle, --exit, --match REGEX"));
            };
            if p.flag("match").is_some_and(|r| r.len() > 1024) {
                return Err(usage("--match is over 1024 characters"));
            }
            Prepared::Wait {
                fields: vec![
                    ("pane", Some(pane(pos(0), ctx)?)),
                    ("mode", Some(Value::text(mode))),
                    ("pattern", text(p.flag("match"))),
                    ("quietMs", int_flag(p, "quiet")?),
                    ("timeoutMs", timeout_ms(p, 3600.0)?),
                    ("fromNow", flag(p, "from-now")),
                ],
                mode,
            }
        }
        "events" => Prepared::Events {
            kinds: p.flag("kinds").map(|k| Value::Array(k.split(',').filter(|s| !s.is_empty()).map(Value::text).collect())),
        },
        "browser ls" => Prepared::BrowserList,
        "browser open" => {
            let (k, v) = match (p.flag("tab"), p.flag("pane")) {
                (Some(_), Some(_)) => return Err(usage("use --tab or --pane, not both")),
                (Some(t), None) => ("tab", Some(tab(t, ctx)?)),
                (None, Some(x)) => ("target", Some(pane(x, ctx)?)),
                (None, None) => ("tab", None),
            };
            Prepared::Simple {
                t: "ui.browser.open",
                fields: vec![("url", Some(Value::text(pos(0)))), (k, v), ("direction", Some(Value::text(if p.has("down") { "down" } else { "right" }))), ("focus", flag(p, "focus"))],
                id_key: Some("pane"),
                prefix: "p",
            }
        }
        "browser nav" => simple("ui.browser.navigate", vec![
            ("pane", Some(pane(pos(0), ctx)?)),
            ("url", Some(Value::text(pos(1)))),
            ("wait", Some(Value::text(if p.has("no-wait") { "none" } else { "load" }))),
            ("timeoutMs", timeout_ms(p, 60.0)?),
        ]),
        "browser back" | "browser forward" | "browser reload" | "browser stop" | "browser close" => {
            let t = match path {
                "browser back" => "ui.browser.back",
                "browser forward" => "ui.browser.forward",
                "browser reload" => "ui.browser.reload",
                "browser stop" => "ui.browser.stop",
                _ => "ui.browser.close",
            };
            simple(t, vec![("pane", Some(pane(pos(0), ctx)?))])
        }
        "browser wait" => simple("ui.browser.wait", vec![("pane", Some(pane(pos(0), ctx)?)), ("timeoutMs", timeout_ms(p, 60.0)?)]),
        "browser eval" => {
            let script = match (p.flag("script"), p.flag("file")) {
                (Some(s), None) => s.to_string(),
                (None, Some("-")) => read_all(ctx, MAX_SCRIPT)?,
                (None, Some(f)) => std::fs::read_to_string(f).map_err(|e| usage(format!("cannot read {f}: {e}")))?,
                _ => return Err(usage("give exactly one of --script or --file")),
            };
            if script.len() > MAX_SCRIPT {
                return Err(usage("the script is over 32 KiB"));
            }
            Prepared::Eval { pane: pane(pos(0), ctx)?, script, print: true }
        }
        "browser query" => {
            let limit = match int_flag(p, "limit")? {
                Some(Value::Int(n)) if (1..=200).contains(&n) => n,
                Some(_) => return Err(usage("--limit is 1–200")),
                None => 50,
            };
            Prepared::Eval { pane: pane(pos(0), ctx)?, script: browser_js::query(pos(1), limit), print: true }
        }
        "browser click" => Prepared::Eval { pane: pane(pos(0), ctx)?, script: browser_js::click(pos(1)), print: false },
        "browser fill" => Prepared::Eval { pane: pane(pos(0), ctx)?, script: browser_js::fill(pos(1), &rest(2)), print: false },
        "browser screenshot" => Prepared::Screenshot { pane: pane(pos(0), ctx)? },
        "browser console" => Prepared::Entries {
            t: "ui.browser.console",
            fields: vec![("pane", Some(pane(pos(0), ctx)?)), ("since", int_flag(p, "since")?), ("level", text(p.flag("level"))), ("limit", int_flag(p, "limit")?)],
        },
        "browser network" => Prepared::Entries {
            t: "ui.browser.network",
            fields: vec![("pane", Some(pane(pos(0), ctx)?)), ("since", int_flag(p, "since")?), ("limit", int_flag(p, "limit")?)],
        },
        other => return Err(usage(format!("'{other}' is not implemented"))),
    })
}

fn clean(s: &str) -> String {
    s.chars().filter(|c| !c.is_control()).collect()
}

/// D23: pane → API; shared window without a pane → OSC 777 on the tty;
/// otherwise the API without a pane; API unreachable inside a ShellX pane →
/// OSC 777 on the tty.
fn notify(p: &Parsed, ctx: &mut Ctx) -> Result<(), ApiError> {
    let body = p.positionals.join(" ");
    if body.trim().is_empty() {
        return Err(usage("notify needs text"));
    }
    let title = p.flag("title");
    let pane_id = match p.flag("pane") {
        Some(r) => pane(r, ctx)?.as_i64(),
        None => (ctx.env)("SHELLX_PANE_ID").and_then(|v| v.parse().ok()),
    };
    if pane_id.is_none() && ctx.shared_terminal && ctx.tty.is_some() {
        return osc(ctx, title, &body);
    }
    let attempt = Api::open(p, ctx).and_then(|mut api| {
        api.call("cli.notify", vec![
            ("pane", pane_id.map(Value::Int)),
            ("title", text(title)),
            ("body", Some(Value::text(body.clone()))),
        ])
    });
    match attempt {
        Ok(_) => Ok(()),
        Err(ApiError::NotRunning(_)) if pane_id.is_some() && ctx.tty.is_some() => osc(ctx, title, &body),
        Err(e) => Err(e),
    }
}

fn osc(ctx: &mut Ctx, title: Option<&str>, body: &str) -> Result<(), ApiError> {
    let t = clean(title.unwrap_or("")).replace(';', ",");
    let line = format!("\u{1b}]777;notify;{t};{}\u{7}", clean(body));
    let tty = ctx.tty.as_mut().ok_or_else(|| ApiError::NotRunning("no terminal".into()))?;
    tty.write_all(line.as_bytes()).and_then(|_| tty.flush()).map_err(|e| ApiError::Io(e.to_string()))
}
```

Remove the `#[ignore]` from `not_running_is_exit_3` in `term/tests/cli_dispatch.rs`.

- [ ] **Step 5: Run tests to verify they pass**

Run: `cd term && ~/.cargo/bin/cargo test && ~/.cargo/bin/cargo test --features test-hooks`
Expected: PASS (all old and new tests).

- [ ] **Step 6: Lint and commit**

```bash
cd term && ~/.cargo/bin/cargo fmt --check && ~/.cargo/bin/cargo clippy --all-targets -- -D warnings && cd ..
git add term/src/api agent-skills term/tests/cli_dispatch.rs
git commit -m "feat(term): shellx commands — tabs, panes, send/read/wait, notify fallbacks, events, browser helpers, skills install (A7 D10-D25, D35)"
```

---

### Task 11: End to end, A5b daemon routing, HANDOFF, manual verification (D34, D37c, D39, D40)

**Files:**
- Create: `packages/shellx_e2e/test/cli_e2e_test.dart`
- If A5b merged — create `packages/shellx_agent/lib/src/mux/daemon_ui_proxy.dart`, `apps/desktop/lib/src/cli/ui_mux_responder.dart`, `packages/shellx_agent/test/mux/daemon_cli_contract_test.dart`; modify `packages/shellx_agent/lib/src/mux/cli_host.dart` (`adopt`, `hostKind`, `uiAttached`), `packages/shellx_agent/lib/src/mux/mux_server.dart` (role `cli` → `CliHost.adopt`), `packages/shellx_agent/lib/src/mux/remote_local_sessions.dart` (`MuxClient.onRequest`), `apps/desktop/lib/daemon_main.dart`, `apps/desktop/lib/main.dart`
- Modify: `docs/superpowers/HANDOFF.md`, `docs/superpowers/ledgers/a1-desktop-terminal.md`

**Interfaces:**
- Consumes: everything above; `buildTermBinaries()`/cargo env helper from `packages/shellx_e2e/test/support/term_window.dart`.
- Produces (A5b merged only):
  - `CliHost` gains `String hostKind = 'ui'`, `bool Function() uiAttached = () => true` (both reported by `api.version`), and `void adopt(MuxConnection c)` (post-handshake path, used by `MuxServer` for role `cli`; `_onConnection` calls it too).
  - `final class DaemonUiProxy implements UiApi { DaemonUiProxy({required LocalSessions sessions}); void attach(MuxConnection ui); void detach(); }` — `handle` forwards `ui.*` to the attached UI with a fresh `q` and maps the answer back; no UI → `ui.ls` answered from `sessions` as `{ui: false, sessions: [summaryToWire…]}`, everything else `CliFailure('no_ui', 'the ShellX window is closed')`; `events()` sends `ui.events.subscribe` to the UI while ≥ 1 listener and re-emits the UI's `event` messages plus `ui.attached`/`ui.detached`; `notifyPane` → `sessions.notify`; `notifyApp` → forwards `ui.notify` (no UI → `CliFailure('no_ui')`).
  - `final class UiMuxResponder { UiMuxResponder(MuxClient client, UiApi handler); }` — answers daemon → UI `ui.*` requests with `handler.handle`, and on `ui.events.subscribe` forwards `handler.events()` as `event` messages until the link closes.

- [ ] **Step 1: Write the e2e test**

`packages/shellx_e2e/test/cli_e2e_test.dart`:

```dart
@TestOn('mac-os || linux')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:shellx_agent/shellx_agent.dart';
import 'package:test/test.dart';

import 'support/term_window.dart';

final class ScriptedUi implements UiApi {
  final requests = <MuxMessage>[];
  final paneNotices = <(int, String?, String)>[];
  final events$ = StreamController<Map<String, Object?>>.broadcast();
  @override
  Future<Map<String, Object?>> handle(MuxMessage r, {Future<void>? cancelled}) async {
    requests.add(r);
    return switch (r.type) {
      'ui.ls' => {
        'workspaces': [
          {'id': 'default', 'name': 'Default', 'current': true, 'collapsed': false, 'tabs': [
            {'id': 100, 'title': 'build', 'selected': true, 'unread': 0, 'panes': [
              {'id': 100, 'kind': 'terminal', 'title': 'zsh', 'focused': true, 'ports': <int>[]},
            ]},
          ]},
        ],
        'selectedTab': 100,
        'focusedPane': 100,
      },
      'ui.pane.split' => {'pane': 101, 'tab': 100},
      _ => const {},
    };
  }

  @override
  Stream<Map<String, Object?>> events() => events$.stream;
  @override
  Future<void> notifyApp({String? title, required String body}) async {}
  @override
  bool notifyPane(int pane, {String? title, required String body}) {
    paneNotices.add((pane, title, body));
    return true;
  }
}

void main() {
  late Directory dir;
  late String shellx;
  late CliHost host;
  late ScriptedUi ui;
  var enabled = true;

  setUpAll(() async {
    final bins = await buildTermBinaries();
    dir = await Directory.systemTemp.createTemp('cli_e2e');
    shellx = '${dir.path}/shellx';
    await Link(shellx).create(bins.shellxTerm);
  });

  setUp(() async {
    ui = ScriptedUi();
    enabled = true;
    host = CliHost(
      transport: UnixMuxTransport(),
      address: '${dir.path}/mux.sock',
      endpointFile: MuxEndpointFile('${dir.path}/mux/endpoint'),
      ui: ui,
      enabled: () => enabled,
      appVersion: '1.7.0',
    );
    await host.start();
  });
  tearDown(() => host.stop());
  tearDownAll(() => dir.delete(recursive: true));

  Future<ProcessResult> sh(List<String> args, {Map<String, String> env = const {}}) => Process.run(
    shellx,
    args,
    environment: {'SHELLX_ENDPOINT': '${dir.path}/mux/endpoint', 'HOME': dir.path, ...env},
    includeParentEnvironment: false,
  );

  test('ls --json over a real socket, ids prefixed', () async {
    final r = await sh(['ls', '--json']);
    expect(r.exitCode, 0, reason: '${r.stderr}');
    final j = jsonDecode(r.stdout as String) as Map<String, dynamic>;
    expect(j['selectedTab'], 't100');
    expect(((j['workspaces'] as List).single as Map)['tabs'][0]['panes'][0]['id'], 'p100');
  });

  test('split from inside a pane prints only the new id', () async {
    final r = await sh(['split', '--cmd', 'npm run dev'], env: {'SHELLX_PANE_ID': '100'});
    expect((r.exitCode, r.stdout), (0, 'p101\n'));
    expect(ui.requests.last.get<int>('pane'), 100);
  });

  test('notify inside a pane reaches LocalSessions.notify', () async {
    final r = await sh(['notify', 'Build', 'xong'], env: {'SHELLX_PANE_ID': '100'});
    expect(r.exitCode, 0, reason: '${r.stderr}');
    expect(ui.paneNotices.single, (100, null, 'Build xong'));
  });

  test('switch off → exit 6; wrong secret → exit 3; not running → exit 3', () async {
    enabled = false;
    expect((await sh(['send', 'p100', '--text', 'x'])).exitCode, 6);
    final ep = File('${dir.path}/mux/endpoint');
    final good = await ep.readAsString();
    await ep.writeAsString(good.replaceFirst(RegExp('secret=[0-9a-f]{64}'), 'secret=${'0' * 64}'));
    expect((await sh(['ls'])).exitCode, 3);
    await ep.writeAsString(good);
    await host.stop();
    expect((await sh(['ls'])).exitCode, 3);
    await host.start();
  });

  test('events --follow streams JSON lines; killing it frees the host', () async {
    final p = await Process.start(shellx, ['events', '--follow'],
        environment: {'SHELLX_ENDPOINT': '${dir.path}/mux/endpoint'}, includeParentEnvironment: false);
    final lines = p.stdout.transform(utf8.decoder).transform(const LineSplitter());
    await Future<void>.delayed(const Duration(milliseconds: 300));
    ui.events$.add({'kind': 'tab.opened', 'tab': 5});
    expect(jsonDecode(await lines.first.timeout(const Duration(seconds: 3))), {'kind': 'tab.opened', 'tab': 't5'});
    p.kill();
    await p.exitCode;
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(host.clientCount, 0);
  });

  test('performance: a simple command under 50 ms (D40, measured, generous gate 250 ms in CI)', () async {
    final sw = Stopwatch()..start();
    await sh(['ls']);
    expect(sw.elapsedMilliseconds, lessThan(250));
    // Record the real number in the ledger.
    print('shellx ls: ${sw.elapsedMilliseconds} ms');
  });
}
```

- [ ] **Step 2: Run it**

Run: `cd packages/shellx_e2e && ~/fvm/versions/3.41.4/bin/dart test test/cli_e2e_test.dart`
Expected: PASS (it builds `shellx-term` with cargo first). Fix any mismatch at its source task's file, re-run that task's tests, and amend nothing — commit fixes as `fix(...)` commits.

- [ ] **Step 3: A5b routing (only if A5b is merged; otherwise append to the ledger "A5b obligation: implement plan 2026-10-07-desktop-cli-a7 Task 11 Step 3 when A5b merges" and skip to Step 5)**

Write `packages/shellx_agent/test/mux/daemon_cli_contract_test.dart` that runs `cliApiContract('daemon', …)` with: a `MuxServer` over a `SessionManager` rig (A5b test support), a `CliHost(hostKind: 'daemon', uiAttached: proxy.attached, ui: proxy)` adopted by the server for role `cli`, and a UI side made of `MemoryMuxTransport.pair()` + `MuxClient` + `UiMuxResponder(client, fakeUi)`. Add three daemon-only tests:

```dart
  test('no UI: ls is the flat session list, other ui.* is no_ui (D34)', () async {
    proxy.detach();
    final c = await host.connect();
    final ls = await ask(c, 'ui.ls');
    expect(ls.get<bool>('ui'), isFalse);
    expect(ls.get<List<Object?>>('sessions'), isNotNull);
    expect((await ask(c, 'ui.pane.send', {'pane': 1, 'text': 'x'})).get<String>('code'), 'no_ui');
    expect((await ask(c, 'api.version')).get<bool>('ui'), isFalse);
  });

  test('notify with a pane works without a UI', () async {
    proxy.detach();
    final id = await rig.manager.open(cols: 80, rows: 24);
    final c = await host.connect();
    expect((await ask(c, 'cli.notify', {'pane': id, 'body': 'ok'})).type, 'result');
  });

  test('events: ui.attached / ui.detached around a UI', () async {
    final c = await host.connect();
    await ask(c, 'cli.events.subscribe');
    final kinds = c.messages.where((m) => m.type == 'event').map((m) => m.get<String>('kind')).take(2).toList();
    proxy.detach();
    proxy.attach(uiConnection);
    expect(await kinds, ['ui.detached', 'ui.attached']);
  });
```

Then implement:

`cli_host.dart` — split `_onConnection` after the role check into `void adopt(MuxConnection c)` (busy check + `_Client`), add constructor params `this.hostKind = 'ui'`, `bool Function()? uiAttached` (default `() => true`), and use them in `api.version` (`'host': hostKind, 'ui': uiAttached()`). The in-UI path is unchanged.

`daemon_ui_proxy.dart`:

```dart
import 'dart:async';

import '../session/local_sessions.dart';
import 'cli_wire.dart';
import 'mux_messages.dart';
import 'mux_transport.dart';
import 'ui_api.dart';

/// A7 D34: the daemon's [UiApi] — the attached window does the work.
final class DaemonUiProxy implements UiApi {
  DaemonUiProxy({required this.sessions});
  final LocalSessions sessions;

  MuxConnection? _ui;
  StreamSubscription<MuxMessage>? _uiSub;
  int _q = 1 << 20; // never collides with the UI's own request ids
  final _pending = <int, Completer<MuxMessage>>{};
  final _events = StreamController<Map<String, Object?>>.broadcast();
  int _listeners = 0;

  bool attached() => _ui != null;

  void attach(MuxConnection ui) {
    detach(silent: true);
    _ui = ui;
    _uiSub = ui.messages.listen((m) {
      if (m.type == CliType.event) {
        _events.add(m.fields);
        return;
      }
      final waiter = m.q == null ? null : _pending.remove(m.q);
      waiter?.complete(m);
    });
    _events.add(const {'kind': 'ui.attached'});
    if (_listeners > 0) ui.send(const MuxMessage(CliType.uiEventsSubscribe));
  }

  void detach({bool silent = false}) {
    if (_ui == null) return;
    unawaited(_uiSub?.cancel());
    _ui = null;
    for (final w in _pending.values) {
      w.completeError(const CliFailure('no_ui', 'the ShellX window closed'));
    }
    _pending.clear();
    if (!silent) _events.add(const {'kind': 'ui.detached'});
  }

  Future<MuxMessage> _forward(MuxMessage r) {
    final ui = _ui;
    if (ui == null) throw const CliFailure('no_ui', 'the ShellX window is closed');
    final q = _q++;
    final w = Completer<MuxMessage>();
    _pending[q] = w;
    ui.send(MuxMessage(r.type, q: q, fields: r.fields));
    return w.future;
  }

  @override
  Future<Map<String, Object?>> handle(MuxMessage r, {Future<void>? cancelled}) async {
    // A CLI that leaves mid-`wait` is not forwarded: the window's wait ends
    // at its own timeout (bounded, D21).
    if (_ui == null && r.type == CliType.uiLs) {
      return {'ui': false, 'sessions': [for (final s in sessions.sessions) summaryToWire(s)]};
    }
    final answer = await _forward(r);
    if (answer.type == MuxType.error) {
      throw CliFailure(answer.get<String>('code') ?? 'internal', answer.get<String>('message'));
    }
    return answer.fields;
  }

  @override
  Stream<Map<String, Object?>> events() {
    late final StreamController<Map<String, Object?>> c;
    StreamSubscription<Map<String, Object?>>? sub;
    c = StreamController<Map<String, Object?>>(
      onListen: () {
        if (_listeners++ == 0) _ui?.send(const MuxMessage(CliType.uiEventsSubscribe));
        sub = _events.stream.listen(c.add);
      },
      onCancel: () async {
        _listeners--;
        await sub?.cancel();
      },
    );
    return c.stream;
  }

  @override
  bool notifyPane(int pane, {String? title, required String body}) =>
      sessions.notify(pane, title: title, body: body);

  @override
  Future<void> notifyApp({String? title, required String body}) async {
    final answer = await _forward(MuxMessage(CliType.uiNotify, fields: {'title': ?title, 'body': body}));
    if (answer.type == MuxType.error) {
      throw CliFailure(answer.get<String>('code') ?? 'internal');
    }
  }
}
```

`mux_server.dart` (A5b): after `serverHandshake`, `role == 'cli'` → `cliHost.adopt(connection)` (the server takes a `CliHost?` constructor argument; without one, keep `unsupported_role`); `role == 'ui'` → existing path plus `uiProxy.attach(connection)` and `uiProxy.detach()` when that connection ends. `MuxClient` (A5b `remote_local_sessions.dart`) gains `void Function(MuxMessage request)? onRequest` called for incoming messages whose `type` starts with `ui.` and that carry a `q`, plus `void send(MuxMessage m)` if not already public.

`apps/desktop/lib/src/cli/ui_mux_responder.dart`:

```dart
import 'dart:async';

import 'package:shellx_agent/shellx_agent.dart';

/// A7 D34, window side: answers the daemon's forwarded `ui.*` requests.
final class UiMuxResponder {
  UiMuxResponder(this._client, this._ui) {
    _client.onRequest = _onRequest;
  }

  final MuxClient _client;
  final UiApi _ui;
  StreamSubscription<Map<String, Object?>>? _events;

  Future<void> _onRequest(MuxMessage r) async {
    if (r.type == CliType.uiEventsSubscribe) {
      _events ??= _ui.events().listen((e) => _client.send(MuxMessage(CliType.event, fields: e)));
      return;
    }
    try {
      _client.send(cliResult(r.q, await _ui.handle(r)));
    } on CliFailure catch (f) {
      _client.send(cliErrorMessage(r.q, f.code, f.message));
    } on Object {
      _client.send(cliErrorMessage(r.q, MuxError.internal));
    }
  }

  void dispose() => unawaited(_events?.cancel());
}
```

`ui.notify` arrives through `_ui.handle` (Task 8 handles `CliType.uiNotify`). `daemon_main.dart`: build `DaemonUiProxy(sessions: sessionManager)` and `CliHost(transport: <the daemon's transport>, …, ui: proxy, hostKind: 'daemon', uiAttached: proxy.attached, enabled: () => true)` — the switch is enforced in the window (`UiCommandHandler.handle` must throw `CliFailure('cli_disabled')` when `cli_control_enabled` is false; move the check there in this step and keep the `CliHost` check for the in-UI host), pass it to `MuxServer`, and **do not** call `start()` on it (the daemon's `MuxServer` owns the listener and endpoint; `adopt` is the only entry). Apply `cliSessionEnvironment` to the daemon's `SessionManager` base environment. `main.dart` (UI): do not start `CliService`; create `UiMuxResponder(muxClient, container.read(uiCommandHandlerProvider))` after attaching.

Run: `cd packages/shellx_agent && ~/fvm/versions/3.41.4/bin/dart test && cd ../../apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test` → PASS. Commit:

```bash
git add packages/shellx_agent/lib/src/mux/daemon_ui_proxy.dart packages/shellx_agent/lib/src/mux/cli_host.dart packages/shellx_agent/lib/src/mux/mux_server.dart packages/shellx_agent/lib/src/mux/remote_local_sessions.dart packages/shellx_agent/lib/shellx_agent.dart packages/shellx_agent/test/mux/daemon_cli_contract_test.dart apps/desktop/lib/src/cli/ui_mux_responder.dart apps/desktop/lib/src/cli/ui_command_handler.dart apps/desktop/lib/daemon_main.dart apps/desktop/lib/main.dart
git commit -m "feat(mux): the daemon serves role cli and forwards ui.* to the window; one contract suite for both hosts (A7 D34, C7)"
```

- [ ] **Step 4: Commit the e2e test**

```bash
cd packages/shellx_e2e && ~/fvm/versions/3.41.4/bin/dart format --set-exit-if-changed test && ~/fvm/versions/3.41.4/bin/dart analyze && cd ../..
git add packages/shellx_e2e/test/cli_e2e_test.dart
git commit -m "test(e2e): shellx binary against a real CliHost over a Unix socket (A7 D37c)"
```

- [ ] **Step 5: HANDOFF section and ledger**

Add a section to `docs/superpowers/HANDOFF.md`, numbered after the last existing section, titled `## N. Dòng lệnh shellx — A7 (2026-10-07)`: what it is (spec/plan paths), where things live (CLI `~/Library/Application Support/ShellX/cli/shellx`, `%LOCALAPPDATA%\ShellX\cli\shellx.exe`; endpoint and socket paths), the tray "Dòng lệnh" submenu, and this **⚠ MANUAL checklist** (each line recorded pass/fail with date and machine in the ledger):

1. macOS: in a ShellX tab, spec criteria 1–8 and 10 verbatim (`command -v shellx`, `$SHELLX_PANE_ID`, `shellx ls`, the dev-server recipe with `python3 -m http.server 8000`, send with `ESC[201~`, wait idle/exit/match, notify in a pane → A4 badge **and** phone push, notify from Terminal.app → system notification + "Command line" entry, `events --follow`, switch off → exit 6, Agent chip 10 s, VoiceOver reads "An agent is controlling …" once).
2. macOS PATH install: with `/usr/local/bin` writable (no prompt) and not writable (password prompt; Cancel → nothing changes); a new Terminal.app window finds `shellx`; "Remove…" removes only our link.
3. macOS permissions: `ls -l` shows the socket `srw-------`, endpoint `-rw-------`, `mux/` `drwx------`; another macOS account cannot `shellx ls` (exit 3).
4. ⚠ Windows: `where shellx` in a ShellX tab; the same commands in PowerShell and cmd; tray "Install…" then a **new** Windows Terminal window finds `shellx`; uninstall removes `cli\` and the Path entry; Setup over a running ShellX replaces `shellx.exe` (the old one renamed `.old-<n>`); pipe ACL via `[System.IO.Directory]::GetAccessControl('\\.\pipe\shellx-mux-…')` shows only the user; Narrator announces the Agent mark.
5. Claude Code: `shellx skills install --claude`, restart Claude Code, ask it to "run the dev server in a ShellX pane next to you, open it in the browser pane and tell me the page title" — it uses `shellx split --cmd`, `wait --match`, `browser open/eval`, `notify`, and never steals focus.
6. Completions: `source <(shellx completions zsh)`, `bash`, and `shellx completions pwsh | Out-String | Invoke-Expression` complete commands, flags and live pane ids.
7. Performance (D40): `time shellx ls` ≤ 50 ms on a Mac with an idle ShellX; `shellx read p… --lines 10000` ≤ 100 ms server time.

Ledger (`docs/superpowers/ledgers/a1-desktop-terminal.md`, section `## A7 (CLI) — execution`): record the A5b/A6 state found at the start, every deviation from this plan (with "cost if wrong"), the D40 numbers, and the manual checklist results.

```bash
git add docs/superpowers/HANDOFF.md docs/superpowers/ledgers/a1-desktop-terminal.md
git commit -m "docs: A7 HANDOFF checklist and ledger"
```

- [ ] **Step 6: Full verification**

```bash
cd term && ~/.cargo/bin/cargo fmt --check && ~/.cargo/bin/cargo clippy --all-targets -- -D warnings && ~/.cargo/bin/cargo test && ~/.cargo/bin/cargo test --features test-hooks && cd ..
cd packages/shellx_core && ~/fvm/versions/3.41.4/bin/dart test && cd ../shellx_agent && ~/fvm/versions/3.41.4/bin/dart analyze && ~/fvm/versions/3.41.4/bin/dart test && cd ../shellx_e2e && ~/fvm/versions/3.41.4/bin/dart test && cd ../..
cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter analyze && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test && cd ../..
cd apps/mobile && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test && cd ../..
cd release && node --test tests/ && cd ..
```

Expected: everything green; test counts ≥ the baseline plus the new tests. `git diff main --stat -- packages/shellx_core/lib/src/protocol apps/mobile relay term/src/proto term/src/wrap.rs term/src/winwrap.rs term/shell` is empty (D6, D28). The branch merges only after every ⚠ MANUAL line is recorded as passed.

---

## Self-review notes (for the executor)

- Spec coverage: C1/D2 → Tasks 2, 5, 9, 11; C2/D6/D9–D11/D36 → Tasks 3, 4, 10; C3 → Tasks 6–8, 10; C4/D3/D26–D28 → Tasks 2, 5, 6, 9; C5/D29 → Tasks 1, 9; C6/D35 → Task 10; C7/D4/D37 → Tasks 2, 5, 11; D7/D8 → Task 9; D12–D25 → Tasks 6–8, 10; D30/D31 → Task 3; D32/D33 → Tasks 5, 6; D34 → Task 11; D38 → every task's logging; D39 → Tasks 2, 3, 9, 11 (⚠); D40 → Task 11.
- Names used across tasks: `CliType`/`CliError`/`kCliCaps`/`cliResult`/`cliErrorMessage` (Task 2); `UiApi`/`CliFailure`/`CliHost` (Task 5, `shellx_agent`); `parseTarget`/`resolvePane`/`resolveTab`/`resolveWorkspace`, `AgentMarks.touch`, `TerminalTabs.openTabFor`/`splitPane`, `SidebarWorkspaces.createFor` (Task 6); `readPage`/`logicalLines`/`waitIdle`/`waitExit`/`waitMatch`/`CommandInjector`/`paneOutput`/`lastExitCode` (Task 7); `CliEventBus`, `TabAttention.addCommandLine`, `kCommandLineTabId` (Task 8); `CliPaths`/`CliBinaryInstaller`/`cliSessionEnvironment`/`CliService`/`cliMuxPathsProvider` (Task 9); Rust `api::{value, wire, endpoint, client, args, run, output, browser_js, skills}` (Tasks 3, 4, 10).
- Where this plan says "use the real name of …" (A4/A5a/A6 internals written by other plans), look the name up in that plan's Interfaces block before inventing one; record any rename in the ledger.

## Amendment (controller ruling, 2026-10-07) — binding over every task above
Default access is ShellX shells only: the host accepts a `cli` client only when its handshake carries the per-launch token the window puts in `SHELLX_CLI_TOKEN` for every ShellX-spawned shell. The endpoint-file HMAC handshake for other processes is refused (`forbidden`, exit code for permission) until the tray "Dòng lệnh" submenu's "Cho phép terminal khác" (`cli_allow_external`, default false) is ticked. `notify` and `api.version` keep their rules. Implementers add tests for: token accepted, missing/wrong token refused, external allowed only with the setting on.
