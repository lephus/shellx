# ShellX Desktop A4 — cmux-style Notifications Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** When a program in a tab wants the user (OSC 9, OSC 777, OSC 99, BEL, a long command finishing), the desktop shows which tab at a glance — unread badge and last-notification line in the sidebar, a ring around the terminal, a dot on collapsed workspaces, a notifications panel (⌘⇧I) with "jump to next unread" (⌘⇧U), native system notifications that jump to the tab, and a Dock/taskbar badge — while phone push stays exactly as it is.

**Architecture:** The agent's existing per-session OSC parser (the one `SessionManager._track` already runs) learns OSC 99 and stand-alone BEL; `SessionManager` turns notification events into `SessionNotice`s on a new `LocalSessions.notices` stream (rate-limited per session). The push path (`SessionNotifier`) ignores the two new event types, so push is untouched. All read/unread state is desktop UI state in a new Riverpod `TabAttention` notifier (unread per tab, 50-entry history, 1 s dwell read, next-unread), which feeds the sidebar, the terminal ring, the panel, the Dock/taskbar badge and a `DesktopNotifications` policy object that posts coalesced, rate-limited native notifications through the existing `local_notifier`.

**Tech Stack:** Dart ^3.11 / Flutter 3.41.4 (fvm), `package:test` + `fake_async` (agent), `flutter_test` + `fake_async` (desktop), flutter_riverpod 3, window_manager 0.5.2 (`setBadgeLabel`, focus events), local_notifier 0.1.6, Win32 C++ in the Windows runner (`ITaskbarList3`, `FlashWindowEx`), ARB l10n via `flutter gen-l10n`.

**Spec:** `docs/superpowers/specs/2026-10-07-desktop-notifications-a4-design.md` (binding; N1–N9 and D1–D27 are final). **UI design:** `docs/superpowers/design/2026-10-07-shellx-desktop-ui-a4.md` (binding for every measurement, state, string and wireframe; cited as "UI-A4 §N"), on top of `2026-10-07-shellx-desktop-ui-a2.md` ("UI-A2 §N") and `2026-10-06-shellx-desktop-ui.md` ("UI-A1 §N"). Executors read the spec and UI-A4 before Task 1.

## Global Constraints

- The spec wins over everything else; UI-A4 (then UI-A2, UI-A1) wins for visuals and copy. Never invent a colour, size, duration or string: take it from the UI section the task names. **No new colour tokens** (UI-A4 §1.1).
- Toolchain: Flutter `~/fvm/versions/3.41.4/bin/flutter`, Dart `~/fvm/versions/3.41.4/bin/dart`. Agent tests: `cd packages/shellx_agent && ~/fvm/versions/3.41.4/bin/dart test`. Desktop tests: `cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test`. Format: `~/fvm/versions/3.41.4/bin/dart format --set-exit-if-changed <paths>`. Analyze: `cd packages/shellx_agent && ~/fvm/versions/3.41.4/bin/dart analyze`; `cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter analyze`.
- **Push is unchanged (N8):** `AgentNotifications`, `SessionNotifier`, `NotificationSender`, `NotificationText` keep their behaviour; OSC 99 and BEL never reach `NotificationSender` (spec D1). No relay, `web/`, `apps/mobile`, `packages/shellx_core` or `term/` change.
- **Privacy (N9, D27):** notification text, program titles and command lines are never logged (not in `debugPrint`, not in injected logs, not in `toString()`), never written to settings or disk. Logs carry kinds, counts and `runtimeType` only.
- A1/A2 behaviour unchanged: driver, exit rules, every A1/A2 shortcut, workspace rules. The ring and the panel are overlays: **the terminal's constraints never change** (a resize makes the desktop the driver, A1 D6). With no notifications the window looks exactly like A2.
- Desktop notifications work **signed out** (N1).
- l10n: every new string goes into both `apps/desktop/lib/l10n/app_en.arb` (with `@key` metadata for placeholders; `count` is `int`) and `app_vi.arb` with identical keys, then `cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter gen-l10n`; generated `lib/l10n/app_localizations*.dart` are committed.
- New persisted settings keys go into `SettingKeys.all`.
- Interfaces gain members in this plan (`LocalSessions.notices`, `SystemNotifier.show(id:)`/`close`): update **every** implementer in the same task (listed per task) so the tree always compiles.
- Code style: match the surrounding code (doc comments that say *why*, `final class`, no `print`). Every task ends with its tests green, `dart format --set-exit-if-changed` clean on touched files, analyzer clean, and a commit with a conventional message. Commit only the files the task lists — **never `git add -A`** (other agents work in this checkout).

## Review Focus

1. **A program that prints notifications in a tight loop** (`yes $'\e]9;x\a'`, `yes $'\a'`, a test runner that notifies per test) must not freeze the UI, flood Notification Center or grow memory: ≤ 30 notices/min/session from the agent, one bell per 5 s, ≤ 6 system notifications/min/tab and 20/min app-wide, history capped at 50. Pinned by the limiter test (Task 2), the flood test in `tab_attention_test` (Task 4) and the burst test in `desktop_notifications_test` (Task 5).
2. **The user is looking at the tab when it notifies** (selected + focused window) — no badge, no ring, no system notification, and a BEL there is ignored completely; but the same notice with the window behind another app does notify. Pinned by the D7 tests in Task 4 and the D14 matrix in Task 5.
3. **Switching through tabs quickly** (⌃Tab past a tab with unread in < 1 s, or blurring the window during the dwell) must not mark it read; staying 1 s must. Pinned by the `fake_async` dwell tests in Task 4.
4. **A tab that closes (exit 0) or is closed while it has unread, a pending coalesced notification or a delivered system notification** — the badge and Dock count drop, the pending post is cancelled, the delivered one is removed, the history entry stays as "Tab closed" and cannot be jumped to; clicking an old system notification only raises the window. Pinned by Task 4 (`_dropGone`), Task 5 (cancel/close on read) and Task 8 (panel closed entry).
5. **A kitty OSC 99 sender that splits title/body over chunks, base64-encodes Vietnamese, sends unknown keys or never finishes** — exactly one notice with the right text, unknown keys ignored, broken base64 dropped, never-finished drafts bounded to 4. Pinned by `osc99_bell_event_test` (Task 1).

---

## File Structure

| File | Responsibility |
|---|---|
| Modify `packages/shellx_agent/lib/src/notify/osc_event_parser.dart` | `KittyNotifyRequested` (OSC 99, chunk assembly), `BellRung` (ground-state BEL) |
| Modify `packages/shellx_agent/lib/src/notify/command_tracker.dart` | Ignore the new events |
| Create `packages/shellx_agent/lib/src/session/session_notice.dart` | `SessionNotice`, `SessionNoticeKind`, `NoticeLimiter` |
| Modify `packages/shellx_agent/lib/src/session/local_sessions.dart` | `Stream<SessionNotice> get notices` |
| Modify `packages/shellx_agent/lib/src/session/session_manager.dart` | Emit notices from `_track`; `commandNoticeThreshold` |
| Modify `packages/shellx_agent/lib/shellx_agent.dart` | Export `session_notice.dart` |
| Modify `apps/desktop/lib/src/agent/session_core.dart` | Pass the threshold (D5) |
| Modify `apps/desktop/test/support/fake_local_sessions.dart`, `test/support/fakes.dart` | Fakes for the new members |
| Modify `apps/desktop/lib/l10n/app_en.arb`, `app_vi.arb` (+ generated) | UI-A4 §9 strings |
| Modify `apps/desktop/lib/src/platform/settings_store.dart` | Two keys (D20) |
| Modify `apps/desktop/lib/src/ui/theme/shellx_desktop_theme.dart` | UI-A4 §1.2 sizes |
| Create `apps/desktop/lib/src/ui/window_focus.dart` | `windowFocusProvider`, `windowActiveProvider`, `terminalFocusRequestProvider` |
| Modify `apps/desktop/lib/src/ui/window_host.dart` | `onFocusChanged` from window_manager (D25) |
| Create `apps/desktop/lib/src/terminal/tab_attention.dart` | `TabAttention` state, read rules, history, next unread, jump |
| Modify `apps/desktop/lib/src/terminal/sidebar_workspaces.dart` | `reveal(tabId)` |
| Modify `apps/desktop/lib/src/platform/notifier.dart` | `SystemNotifier` `id` + `close` (D17) |
| Create `apps/desktop/lib/src/platform/desktop_notifications.dart` | Posting policy, coalescing, limits, wiring (D14–D16) |
| Modify `apps/desktop/lib/src/agent/agent_state.dart`, `agent_controller.dart`, `lib/src/tray/tray_action.dart`, `tray_actions.dart`, `tray_menu.dart` | "Thông báo" tray submenu (D20) |
| Create `apps/desktop/lib/src/platform/attention_badge.dart` | Dock / taskbar badge (D18, D19) |
| Modify `apps/desktop/windows/runner/flutter_window.cpp`, `flutter_window.h`, `CMakeLists.txt` | `pro.shellx.desktop/taskbar` channel |
| Create `apps/desktop/lib/src/ui/terminal/attention_marks.dart` | `UnreadBadge`, `NotificationLine`, `AttentionRing` |
| Modify `apps/desktop/lib/src/ui/terminal/session_tab_row.dart`, `session_sidebar.dart`, `workspace_header.dart` | Badge, line, heights, menu, header dot, bell button |
| Create `apps/desktop/lib/src/ui/terminal/notifications_panel.dart` | Panel (UI-A4 §5) |
| Modify `apps/desktop/lib/src/ui/terminal/terminal_pane.dart`, `terminal_shortcuts.dart`, `terminal_workspace_page.dart`, `shortcut_labels.dart` | Ring, ⌘⇧I / ⌘⇧U, focus requests |
| Modify `apps/desktop/lib/main.dart` | Wiring |
| Modify `docs/superpowers/HANDOFF.md` | §13 manual checklist |

---

### Task 1: Agent — OSC 99 and BEL events (push untouched)

**Files:**
- Modify: `packages/shellx_agent/lib/src/notify/osc_event_parser.dart`
- Modify: `packages/shellx_agent/lib/src/notify/command_tracker.dart` (the `case NotifyRequested() || CwdReported():` line)
- Create: `packages/shellx_agent/test/notify/osc99_bell_event_test.dart`
- Modify: `packages/shellx_agent/test/notify/session_notifications_test.dart` (one test)

**Interfaces:**
- Consumes: sealed `OscEvent`, `OscEventParser.feed(Uint8List) → List<OscEvent>` (existing).
- Produces:
  - `final class KittyNotifyRequested extends OscEvent { const KittyNotifyRequested({required String? title, required String body}); }`
  - `final class BellRung extends OscEvent { const BellRung(); }`
  - `OscEventParser.maxKittyDrafts == 4`

- [ ] **Step 1: Write the failing tests**

Create `packages/shellx_agent/test/notify/osc99_bell_event_test.dart`:

```dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:shellx_agent/shellx_agent.dart';
import 'package:test/test.dart';

Uint8List _b(String s) => Uint8List.fromList(utf8.encode(s));

const esc = '\x1b';
const bel = '\x07';
const st = '$esc\\';

String _b64(String s) => base64.encode(utf8.encode(s));

void main() {
  group('OSC 99 (A4 D2)', () {
    test('a single title-only chunk becomes the body, with ST or BEL', () {
      expect(OscEventParser().feed(_b('$esc]99;;Xin chào$st')), [
        const KittyNotifyRequested(title: null, body: 'Xin chào'),
      ]);
      expect(OscEventParser().feed(_b('$esc]99;;Hi$bel')), [
        const KittyNotifyRequested(title: null, body: 'Hi'),
      ]);
    });

    test('title (d=0) then body chunk with the same id: one notification', () {
      final p = OscEventParser();
      expect(p.feed(_b('$esc]99;i=1:d=0;Tiêu đề$st')), isEmpty);
      expect(p.feed(_b('$esc]99;i=1:p=body;Nội dung$st')), [
        const KittyNotifyRequested(title: 'Tiêu đề', body: 'Nội dung'),
      ]);
    });

    test('chunks of the same part are appended', () {
      final p = OscEventParser();
      p.feed(_b('$esc]99;i=a:d=0:p=body;Hello $st'));
      expect(p.feed(_b('$esc]99;i=a:p=body;world$st')), [
        const KittyNotifyRequested(title: null, body: 'Hello world'),
      ]);
    });

    test('e=1 payloads are base64 UTF-8', () {
      expect(
        OscEventParser().feed(_b('$esc]99;e=1;${_b64('Build xong ✓')}$st')),
        [const KittyNotifyRequested(title: null, body: 'Build xong ✓')],
      );
    });

    test('broken base64 or UTF-8 drops the chunk', () {
      expect(OscEventParser().feed(_b('$esc]99;e=1;%%%$st')), isEmpty);
      final notUtf8 = base64.encode([0xff, 0xfe]);
      expect(OscEventParser().feed(_b('$esc]99;e=1;$notUtf8$st')), isEmpty);
    });

    test('unknown keys are ignored; unsupported payload types are dropped', () {
      expect(OscEventParser().feed(_b('$esc]99;u=2:o=unfocused:a=focus;x$st')), [
        const KittyNotifyRequested(title: null, body: 'x'),
      ]);
      expect(OscEventParser().feed(_b('$esc]99;i=1:p=?;$st')), isEmpty);
      expect(OscEventParser().feed(_b('$esc]99;i=1:p=icon;abc$st')), isEmpty);
      expect(OscEventParser().feed(_b('$esc]99;nosemicolon$st')), isEmpty);
      expect(OscEventParser().feed(_b('$esc]99;;   $st')), isEmpty);
    });

    test('at most 4 unfinished drafts: the oldest is dropped', () {
      final p = OscEventParser();
      for (var i = 0; i < 5; i++) {
        p.feed(_b('$esc]99;i=$i:d=0;T$i$st'));
      }
      // Draft 0 was evicted: its end alone is a body-only notification.
      expect(p.feed(_b('$esc]99;i=0:p=body;B$st')), [
        const KittyNotifyRequested(title: null, body: 'B'),
      ]);
      expect(p.feed(_b('$esc]99;i=4:p=body;B$st')), [
        const KittyNotifyRequested(title: 'T4', body: 'B'),
      ]);
    });

    test('split at every byte still parses; text cut to 200 characters', () {
      final long = 'á' * 300;
      final bytes = _b('$esc]99;;$long$st');
      final p = OscEventParser();
      final events = [for (final b in bytes) ...p.feed(Uint8List.fromList([b]))];
      expect(events, hasLength(1));
      expect((events.single as KittyNotifyRequested).body.runes.length, 200);
    });

    test('reset() forgets drafts', () {
      final p = OscEventParser();
      p.feed(_b('$esc]99;i=1:d=0;T$st'));
      p.reset();
      expect(p.feed(_b('$esc]99;i=1:p=body;B$st')), [
        const KittyNotifyRequested(title: null, body: 'B'),
      ]);
    });
  });

  group('BEL (A4 D3)', () {
    test('a BEL outside escape sequences rings', () {
      expect(OscEventParser().feed(_b('a${bel}b')), [const BellRung()]);
      expect(OscEventParser().feed(_b('$bel$bel')), [
        const BellRung(),
        const BellRung(),
      ]);
    });

    test('BEL ending an OSC, or right after ESC, does not ring', () {
      expect(OscEventParser().feed(_b('$esc]0;title$bel')), isEmpty);
      expect(OscEventParser().feed(_b('$esc]133;C$bel')), [
        const CommandStarted(),
      ]);
      expect(OscEventParser().feed(_b('$esc]9;hi$bel')), [
        const NotifyRequested(title: null, body: 'hi'),
      ]);
      expect(OscEventParser().feed(_b('$esc$bel')), isEmpty);
    });
  });

  test('the command tracker ignores both', () {
    final t = CommandTracker(threshold: () => Duration.zero);
    expect(t.handle(const BellRung()), isNull);
    expect(
      t.handle(const KittyNotifyRequested(title: null, body: 'x')),
      isNull,
    );
    expect(t.running, isFalse);
  });

  test('toString never contains the text (N9)', () {
    expect(
      const KittyNotifyRequested(title: 'secret', body: 'secret').toString(),
      isNot(contains('secret')),
    );
  });
}
```

Append to the `group('SessionManager (ShellX sessions)', ...)` in `packages/shellx_agent/test/notify/session_notifications_test.dart` (after the "a short command is not reported" test):

```dart
    test('OSC 99 and BEL never reach push; OSC 9/777 still do (A4 N8)',
        () async {
      await open();
      final pty = factory.ptys.single;
      pty.emit('$esc]99;;kitty$esc\\$bel$bel');
      await Future<void>.delayed(Duration.zero);
      await push.notifications.sender.idle;
      expect(push.bodies, isEmpty);
      pty.emit('$esc]9;nine$bel$esc]777;notify;T;seven$bel');
      await Future<void>.delayed(Duration.zero);
      await push.notifications.sender.idle;
      expect(push.bodies.map((b) => b['body']), ['nine', 'seven']);
    });
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd packages/shellx_agent && ~/fvm/versions/3.41.4/bin/dart test test/notify/osc99_bell_event_test.dart test/notify/session_notifications_test.dart`
Expected: FAIL — compile errors `KittyNotifyRequested` / `BellRung` undefined.

- [ ] **Step 3: Implement**

In `osc_event_parser.dart`, after `CwdReported`, add:

```dart
/// `OSC 99` (kitty's desktop notification protocol), assembled from its
/// chunks (A4 D2). A notification that only had a title has that text as
/// [body] and a null [title]. Desktop only: push ignores it (A4 D1).
final class KittyNotifyRequested extends OscEvent {
  const KittyNotifyRequested({required this.title, required this.body});
  final String? title;
  final String body;
  @override
  bool operator ==(Object other) =>
      other is KittyNotifyRequested &&
      other.title == title &&
      other.body == body;
  @override
  int get hashCode => Object.hash(title, body);
  // Never the text (A4 N9).
  @override
  String toString() => 'KittyNotifyRequested(…)';
}

/// A BEL byte outside every escape sequence: attention without text
/// (A4 D3). Desktop only: push ignores it (A4 D1).
final class BellRung extends OscEvent {
  const BellRung();
  @override
  bool operator ==(Object other) => other is BellRung;
  @override
  int get hashCode => 7;
  @override
  String toString() => 'BellRung()';
}

final class _KittyDraft {
  final title = StringBuffer();
  final body = StringBuffer();
  int get length => title.length + body.length;
}
```

Update the class doc comment's first line to "Finds OSC 7, 9, 99, 133 (C, D), 633 (E) and 777 (`notify`), and BEL outside sequences, in terminal output, …". Then in `OscEventParser`:

```dart
  static const int maxKittyDrafts = 4;
  static const _numbers = {'7', '9', '99', '133', '633', '777'};

  /// Unfinished OSC 99 notifications by id, oldest first (A4 D2).
  final _kittyDrafts = <String, _KittyDraft>{};
```

`reset()` gains `_kittyDrafts.clear();`. In `_step`, the `ground` case becomes:

```dart
      case _State.ground:
        if (byte == 0x1b) {
          _state = _State.escape;
        } else if (byte == 0x07) {
          return const BellRung();
        }
```

In `_finish`, add `'99' => _kitty(text),` to the switch, and add the method (instance, not static: it keeps drafts):

```dart
  /// `99 ; <k=v:k=v…> ; <payload>`: `i` id, `d=0` more chunks follow, `p`
  /// title (default) or body, `e=1` base64. Other `p` kinds and every other
  /// key are ignored (A4 D2); a `p=?` query gets no answer.
  OscEvent? _kitty(String text) {
    final split = text.indexOf(';');
    if (split < 0) return null;
    var id = '';
    var done = true;
    var part = 'title';
    var encoded = false;
    for (final pair in text.substring(0, split).split(':')) {
      final eq = pair.indexOf('=');
      if (eq <= 0) continue;
      final value = pair.substring(eq + 1);
      switch (pair.substring(0, eq)) {
        case 'i':
          id = value;
        case 'd':
          done = value != '0';
        case 'p':
          part = value;
        case 'e':
          encoded = value == '1';
      }
    }
    if (part != 'title' && part != 'body') return null;
    var payload = text.substring(split + 1);
    if (encoded) {
      try {
        payload = utf8.decode(base64.decode(base64.normalize(payload)));
      } on FormatException {
        return null;
      }
    }
    final draft = _kittyDrafts.remove(id) ?? _KittyDraft();
    (part == 'title' ? draft.title : draft.body).write(payload);
    if (draft.length > maxPayload) return null; // dropped with its chunks
    if (!done) {
      if (_kittyDrafts.length >= maxKittyDrafts) {
        _kittyDrafts.remove(_kittyDrafts.keys.first);
      }
      _kittyDrafts[id] = draft;
      return null;
    }
    final title = draft.title.toString().trim();
    final body = draft.body.toString().trim();
    if (body.isEmpty) {
      return title.isEmpty
          ? null
          : KittyNotifyRequested(title: null, body: _clip(title));
    }
    return KittyNotifyRequested(
      title: title.isEmpty ? null : _clip(title),
      body: _clip(body),
    );
  }
```

In `command_tracker.dart` replace `case NotifyRequested() || CwdReported():` with:

```dart
      case NotifyRequested() ||
          CwdReported() ||
          KittyNotifyRequested() ||
          BellRung():
```

`SessionNotifier._handle` (push) needs no change: it only matches `NotifyRequested`; everything else goes to the tracker, which ignores the new events.

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd packages/shellx_agent && ~/fvm/versions/3.41.4/bin/dart test test/notify`
Expected: PASS (all, including the existing parser and push tests).

- [ ] **Step 5: Format, analyze, commit**

```bash
cd packages/shellx_agent && ~/fvm/versions/3.41.4/bin/dart format --set-exit-if-changed lib/src/notify test/notify && ~/fvm/versions/3.41.4/bin/dart analyze
cd ../.. && git add packages/shellx_agent/lib/src/notify/osc_event_parser.dart packages/shellx_agent/lib/src/notify/command_tracker.dart packages/shellx_agent/test/notify/osc99_bell_event_test.dart packages/shellx_agent/test/notify/session_notifications_test.dart
git commit -m "feat(agent): OSC 99 and bell events for desktop notifications, push unchanged (A4 D1-D3)"
```

---

### Task 2: Agent — `SessionNotice` stream on `LocalSessions`

**Files:**
- Create: `packages/shellx_agent/lib/src/session/session_notice.dart`
- Modify: `packages/shellx_agent/lib/src/session/local_sessions.dart`
- Modify: `packages/shellx_agent/lib/src/session/session_manager.dart` (constructor, `_Session`, `_track`, new `_notice`)
- Modify: `packages/shellx_agent/lib/shellx_agent.dart`
- Modify: `packages/shellx_agent/test/support/session_rig.dart` (pass-through parameter)
- Create: `packages/shellx_agent/test/session/session_notice_test.dart`
- Modify: `apps/desktop/lib/src/agent/session_core.dart`
- Modify: `apps/desktop/test/support/fake_local_sessions.dart`

**Interfaces:**
- Consumes: `KittyNotifyRequested`, `BellRung` (Task 1); `CompletedCommand`, `CommandTracker({threshold, now})`, `NotifyRequested` (existing).
- Produces:
  - `enum SessionNoticeKind { message, command, bell }`
  - `final class SessionNotice { const SessionNotice({required int sessionId, required SessionNoticeKind kind, required DateTime at, String? title, String? body, CompletedCommand? command}); }`
  - `final class NoticeLimiter { NoticeLimiter({Duration bellGap = 5 s, int maxPerWindow = 30, Duration window = 60 s}); bool allow(SessionNoticeKind kind, DateTime now); int get dropped; }`
  - `LocalSessions.notices → Stream<SessionNotice>` (broadcast)
  - `SessionManager({…, Duration? Function()? commandNoticeThreshold})`
  - `FakeLocalSessions.notice(int id, SessionNoticeKind kind, {String? title, String? body, CompletedCommand? command, DateTime? at})` (desktop tests)

- [ ] **Step 1: Write the failing tests**

In `packages/shellx_agent/test/support/session_rig.dart`, add a constructor parameter `Duration? Function()? commandNoticeThreshold,` and pass `commandNoticeThreshold: commandNoticeThreshold,` to `SessionManager(...)`.

Create `packages/shellx_agent/test/session/session_notice_test.dart`:

```dart
import 'package:shellx_agent/shellx_agent.dart';
import 'package:test/test.dart';

import '../support/session_rig.dart';

const esc = '\x1b';
const bel = '\x07';

void main() {
  late SessionRig rig;
  late List<SessionNotice> got;

  Future<void> boot({Duration? threshold}) async {
    rig = SessionRig(commandNoticeThreshold: () => threshold);
    got = [];
    rig.manager.notices.listen(got.add);
    await rig.manager.open(cols: 80, rows: 24);
  }

  Future<void> emit(String text) async {
    rig.pty(0).emit(text);
    await pumpEventQueue();
  }

  test('OSC 9, 777 and 99 become message notices with the session id',
      () async {
    await boot();
    final id = rig.manager.sessions.single.id;
    await emit('$esc]9;nine$bel');
    await emit('$esc]777;notify;CI;green$bel');
    await emit('$esc]99;;kitty$esc\\');
    expect(got.map((n) => (n.sessionId, n.kind, n.title, n.body)), [
      (id, SessionNoticeKind.message, null, 'nine'),
      (id, SessionNoticeKind.message, 'CI', 'green'),
      (id, SessionNoticeKind.message, null, 'kitty'),
    ]);
    expect(got.first.at, rig.now);
  });

  test('a bell rings at most once per 5 s (D3)', () async {
    await boot();
    await emit('$bel$bel$bel');
    expect(got.map((n) => n.kind), [SessionNoticeKind.bell]);
    rig.now = rig.now.add(const Duration(seconds: 4));
    await emit(bel);
    expect(got, hasLength(1));
    rig.now = rig.now.add(const Duration(seconds: 1));
    await emit(bel);
    expect(got, hasLength(2));
  });

  test('a command over the threshold becomes a command notice (D5)',
      () async {
    await boot(threshold: const Duration(seconds: 10));
    await emit('$esc]633;E;sleep 11; false$bel$esc]133;C$bel');
    rig.now = rig.now.add(const Duration(seconds: 11));
    await emit('$esc]133;D;1$bel');
    final notice = got.single;
    expect(notice.kind, SessionNoticeKind.command);
    expect(notice.command!.exitCode, 1);
    expect(notice.command!.commandLine, 'sleep 11; false');
    expect(notice.command!.duration, const Duration(seconds: 11));
    // runningCommand still follows 133 C/D (A1 D15).
    expect(rig.manager.sessions.single.runningCommand, isFalse);
  });

  test('no threshold ("Tắt") or a short command: no command notice',
      () async {
    await boot();
    await emit('$esc]133;C$bel');
    rig.now = rig.now.add(const Duration(minutes: 5));
    await emit('$esc]133;D;0$bel');
    expect(got, isEmpty);
  });

  test('at most 30 message notices per 60 s per session (D6)', () async {
    await boot();
    await emit([for (var i = 0; i < 31; i++) '$esc]9;$i$bel'].join());
    expect(got, hasLength(30));
    rig.now = rig.now.add(const Duration(seconds: 60));
    await emit('$esc]9;again$bel');
    expect(got.last.body, 'again');
  });

  test('a closing session emits nothing', () async {
    await boot();
    final id = rig.manager.sessions.single.id;
    rig.manager.close(id);
    await emit('$esc]9;late$bel');
    expect(got, isEmpty);
  });

  test('toString never contains the text (N9)', () {
    final n = SessionNotice(
      sessionId: 1,
      kind: SessionNoticeKind.message,
      at: DateTime(2026),
      title: 'secret',
      body: 'secret',
    );
    expect(n.toString(), isNot(contains('secret')));
  });

  group('NoticeLimiter', () {
    test('bell gap and window are independent', () {
      final l = NoticeLimiter(maxPerWindow: 1);
      final t = DateTime(2026);
      expect(l.allow(SessionNoticeKind.message, t), isTrue);
      expect(l.allow(SessionNoticeKind.command, t), isFalse);
      expect(l.allow(SessionNoticeKind.bell, t), isTrue);
      expect(l.dropped, 1);
    });
  });
}
```

In `apps/desktop/test/support/fake_local_sessions.dart`, add to `FakeLocalSessions`:

```dart
  final _notices = StreamController<SessionNotice>.broadcast(sync: true);

  @override
  Stream<SessionNotice> get notices => _notices.stream;

  /// A notice from session [id], as the agent would emit it (A4).
  void notice(
    int id,
    SessionNoticeKind kind, {
    String? title,
    String? body,
    CompletedCommand? command,
    DateTime? at,
  }) => _notices.add(
    SessionNotice(
      sessionId: id,
      kind: kind,
      at: at ?? DateTime(2026, 10, 7, 9),
      title: title,
      body: body,
      command: command,
    ),
  );
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd packages/shellx_agent && ~/fvm/versions/3.41.4/bin/dart test test/session/session_notice_test.dart`
Expected: FAIL — `SessionNotice`, `notices`, `commandNoticeThreshold` undefined.

- [ ] **Step 3: Implement**

Create `packages/shellx_agent/lib/src/session/session_notice.dart`:

```dart
import '../notify/command_tracker.dart';

/// What asked for the user (A4 N1).
enum SessionNoticeKind { message, command, bell }

/// A session asked for attention (A4 D4): a program's message (OSC 9, 777,
/// 99), a long command that ended, or a bell. The desktop decides what is
/// read; the agent only reports. [toString] never shows the text (N9).
final class SessionNotice {
  const SessionNotice({
    required this.sessionId,
    required this.kind,
    required this.at,
    this.title,
    this.body,
    this.command,
  });

  final int sessionId;
  final SessionNoticeKind kind;
  final DateTime at;

  /// The program's title (OSC 777 / 99), if it gave one.
  final String? title;

  /// The message text ([SessionNoticeKind.message] only).
  final String? body;

  /// The command that ended ([SessionNoticeKind.command] only).
  final CompletedCommand? command;

  @override
  String toString() => 'SessionNotice($sessionId, ${kind.name})';
}

/// Per-session flood guard (A4 D3, D6): one bell per [bellGap]; at most
/// [maxPerWindow] messages and commands in any [window].
final class NoticeLimiter {
  NoticeLimiter({
    this.bellGap = const Duration(seconds: 5),
    this.maxPerWindow = 30,
    this.window = const Duration(seconds: 60),
  });

  final Duration bellGap;
  final int maxPerWindow;
  final Duration window;
  final _recent = <DateTime>[];
  DateTime? _lastBell;
  int _dropped = 0;

  /// Notices refused so far.
  int get dropped => _dropped;

  bool allow(SessionNoticeKind kind, DateTime now) {
    if (kind == SessionNoticeKind.bell) {
      final last = _lastBell;
      if (last != null && now.difference(last) < bellGap) {
        _dropped++;
        return false;
      }
      _lastBell = now;
      return true;
    }
    _recent.removeWhere((t) => now.difference(t) >= window);
    if (_recent.length >= maxPerWindow) {
      _dropped++;
      return false;
    }
    _recent.add(now);
    return true;
  }
}
```

Export it in `packages/shellx_agent/lib/shellx_agent.dart`: `export 'src/session/session_notice.dart';` (alphabetically after `session_manager.dart`).

In `local_sessions.dart`, add `import 'session_notice.dart';` and inside `LocalSessions`:

```dart
  /// Programs asking for attention (A4 D4): live output only, never a
  /// replay. Broadcast; delivered asynchronously.
  Stream<SessionNotice> get notices;
```

In `session_manager.dart`:

1. `import 'session_notice.dart';`
2. `_Session`: replace `final commands = CommandTracker(threshold: () => null);` by a constructor-initialised field. Add two required constructor parameters and initialiser:

```dart
  _Session({
    // …existing parameters…
    required Duration? Function() commandThreshold,
    required DateTime Function() clock,
  }) : commands = CommandTracker(threshold: commandThreshold, now: clock);

  /// 133 C/D: `runningCommand` (A1 D15) and long commands (A4 D5).
  final CommandTracker commands;

  /// A4 D3/D6.
  final noticeLimit = NoticeLimiter();
```

3. `SessionManager` constructor: new parameter `Duration? Function()? commandNoticeThreshold,` stored as `_commandNoticeThreshold = commandNoticeThreshold ?? _noThreshold`, with top-level `Duration? _noThreshold() => null;`; also store the existing `log` parameter as `final void Function(String message)? _log;` (`_log = log`). Field `final _notices = StreamController<SessionNotice>.broadcast();` and

```dart
  @override
  Stream<SessionNotice> get notices => _notices.stream;
```

4. Where `_Session(` is constructed (the `final session = _Session(` in the open path), pass `commandThreshold: _commandNoticeThreshold, clock: _clock,`.

5. In `_track`, replace the loop

```dart
      for (final event in session.commandEvents.feed(data)) {
        session.commands.handle(event);
        switch (event) {
```

with

```dart
      for (final event in session.commandEvents.feed(data)) {
        final completed = session.commands.handle(event);
        if (completed != null) {
          _notice(session, SessionNoticeKind.command, command: completed);
        }
        switch (event) {
          case NotifyRequested(:final title, :final body):
            _notice(session, SessionNoticeKind.message, title: title, body: body);
          case KittyNotifyRequested(:final title, :final body):
            _notice(session, SessionNoticeKind.message, title: title, body: body);
          case BellRung():
            _notice(session, SessionNoticeKind.bell);
```

keeping the existing `CwdReported` / `CommandFinished` / `default` cases after them.

6. Add:

```dart
  /// A4 D4: live output only (`_track` never sees a replay); a session
  /// being closed says nothing more. Never the text in the log (N9).
  void _notice(
    _Session session,
    SessionNoticeKind kind, {
    String? title,
    String? body,
    CompletedCommand? command,
  }) {
    if (session.closing) return;
    final now = _clock();
    if (!session.noticeLimit.allow(kind, now)) {
      final dropped = session.noticeLimit.dropped;
      if (dropped == 1 || dropped % 100 == 0) {
        _log?.call('session notices dropped: $dropped');
      }
      return;
    }
    _notices.add(
      SessionNotice(
        sessionId: session.id,
        kind: kind,
        at: now,
        title: title,
        body: body,
        command: command,
      ),
    );
  }
```

In `apps/desktop/lib/src/agent/session_core.dart`, pass `commandNoticeThreshold: notifications?.threshold,` to `SessionManager(` (D5: the same live setting push reads).

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd packages/shellx_agent && ~/fvm/versions/3.41.4/bin/dart test`
Expected: PASS (whole agent suite; `runningCommand` tests unchanged).
Run: `cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/terminal test/agent`
Expected: PASS (fake compiles).

- [ ] **Step 5: Format, analyze, commit**

```bash
cd packages/shellx_agent && ~/fvm/versions/3.41.4/bin/dart format --set-exit-if-changed lib test && ~/fvm/versions/3.41.4/bin/dart analyze
cd ../../apps/desktop && ~/fvm/versions/3.41.4/bin/dart format --set-exit-if-changed lib/src/agent/session_core.dart test/support/fake_local_sessions.dart && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter analyze
cd ../.. && git add packages/shellx_agent/lib/src/session/session_notice.dart packages/shellx_agent/lib/src/session/local_sessions.dart packages/shellx_agent/lib/src/session/session_manager.dart packages/shellx_agent/lib/shellx_agent.dart packages/shellx_agent/test/support/session_rig.dart packages/shellx_agent/test/session/session_notice_test.dart apps/desktop/lib/src/agent/session_core.dart apps/desktop/test/support/fake_local_sessions.dart
git commit -m "feat(agent): LocalSessions.notices with per-session limits and long-command notices (A4 D4-D6)"
```

---

### Task 3: Desktop — A4 strings, settings keys, sizes, window focus

**Files:**
- Modify: `apps/desktop/lib/l10n/app_en.arb`, `app_vi.arb` (+ generated `app_localizations*.dart`)
- Modify: `apps/desktop/lib/src/platform/settings_store.dart`
- Modify: `apps/desktop/lib/src/ui/theme/shellx_desktop_theme.dart`
- Create: `apps/desktop/lib/src/ui/window_focus.dart`
- Modify: `apps/desktop/lib/src/ui/window_host.dart`
- Create: `apps/desktop/test/ui/window_focus_test.dart`
- Modify: `apps/desktop/test/ui/window_host_test.dart` (one test)

**Interfaces:**
- Consumes: `windowRouterProvider` (`WindowState.visible`), `WindowManagerHost` (existing, `with WindowListener`).
- Produces:
  - ARB keys of UI-A4 §9 (exact names).
  - `SettingKeys.desktopNotifications = 'desktop_notifications_enabled'`, `SettingKeys.desktopNotificationsOnlyUnfocused = 'desktop_notifications_only_unfocused'`.
  - `ShellxSizes.badgeHeight … bellDot` (UI-A4 §1.2 names and values).
  - `windowFocusProvider` (`NotifierProvider<WindowFocus, bool>`, `WindowFocus.set(bool)`), `windowActiveProvider` (`Provider<bool>` = focused && visible), `terminalFocusRequestProvider` (`NotifierProvider<FocusRequest, int>`, `FocusRequest.request()`).
  - `WindowManagerHost({…, void Function(bool focused)? onFocusChanged})`.

- [ ] **Step 1: Write the failing tests**

Create `apps/desktop/test/ui/window_focus_test.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/ui/window_focus.dart';
import 'package:shellx_desktop/src/ui/window_router.dart';

void main() {
  test('active = focused and visible (D25)', () {
    final c = ProviderContainer.test();
    expect(c.read(windowActiveProvider), isFalse);
    c.read(windowFocusProvider.notifier).set(true);
    expect(c.read(windowActiveProvider), isFalse); // hidden
    c.read(windowRouterProvider.notifier).showTerminal();
    expect(c.read(windowActiveProvider), isTrue);
    c.read(windowRouterProvider.notifier).hideWindow();
    expect(c.read(windowActiveProvider), isFalse);
  });

  test('focus requests count up', () {
    final c = ProviderContainer.test();
    c.read(terminalFocusRequestProvider.notifier).request();
    c.read(terminalFocusRequestProvider.notifier).request();
    expect(c.read(terminalFocusRequestProvider), 2);
  });
}
```

In `apps/desktop/test/ui/window_host_test.dart`, add (using the file's existing way of building a `WindowManagerHost` with a fake `NativeWindow`; pass `onFocusChanged: focus.add` with `final focus = <bool>[];`):

```dart
  test('window_manager focus and blur reach onFocusChanged (A4 D25)', () {
    final focus = <bool>[];
    final host = WindowManagerHost(
      onCloseRequested: () {},
      bounds: WindowBoundsStore(InMemorySettingsStore()),
      native: FakeNativeWindow(),
      onFocusChanged: focus.add,
    );
    host.onWindowFocus();
    host.onWindowBlur();
    expect(focus, [true, false]);
  });
```

(Use the fake native window class the file already defines; rename `FakeNativeWindow` to that name.)

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/ui/window_focus_test.dart test/ui/window_host_test.dart`
Expected: FAIL — `window_focus.dart` missing, `onFocusChanged` undefined.

- [ ] **Step 3: Implement**

Create `apps/desktop/lib/src/ui/window_focus.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'window_router.dart';

/// The native window has the keyboard focus (A4 D25), from window_manager's
/// focus/blur events (`main.dart`).
final windowFocusProvider = NotifierProvider<WindowFocus, bool>(
  WindowFocus.new,
);

class WindowFocus extends Notifier<bool> {
  @override
  bool build() => false;

  void set(bool focused) {
    if (state != focused) state = focused;
  }
}

/// The user can be looking at the window: shown and focused (A4 D7, D10,
/// D14). Minimized or hidden is never active.
final windowActiveProvider = Provider<bool>(
  (ref) =>
      ref.watch(windowFocusProvider) && ref.watch(windowRouterProvider).visible,
);

/// Bumped when something outside the page (a notification click, the
/// panel, next unread) wants the keyboard in the selected tab's terminal;
/// `TerminalWorkspacePage` listens.
final terminalFocusRequestProvider = NotifierProvider<FocusRequest, int>(
  FocusRequest.new,
);

class FocusRequest extends Notifier<int> {
  @override
  int build() => 0;

  void request() => state++;
}
```

In `window_host.dart`, `WindowManagerHost`: add constructor parameter `this.onFocusChanged,` and field

```dart
  /// A4 D25: the window gained (true) or lost the focus.
  final void Function(bool focused)? onFocusChanged;
```

and overrides next to the other `WindowListener` overrides:

```dart
  @override
  void onWindowFocus() => onFocusChanged?.call(true);

  @override
  void onWindowBlur() => onFocusChanged?.call(false);
```

In `settings_store.dart` `SettingKeys`:

```dart
  /// A4 D20: "Thông báo trên máy tính" (default on).
  static const String desktopNotifications = 'desktop_notifications_enabled';

  /// A4 D20: "Chỉ khi cửa sổ không ở phía trước" (default on).
  static const String desktopNotificationsOnlyUnfocused =
      'desktop_notifications_only_unfocused';
```

and add both to `all`.

In `shellx_desktop_theme.dart` `ShellxSizes`, after the A2 block:

```dart
  /// UI-A4 §1.2.
  static const double badgeHeight = 16;
  static const double badgeMinWidth = 16;
  static const double badgePadH = 4;
  static const double badgeGap = 4;
  static const double notificationLine = 14;
  static const double notificationGap = 2;
  static const double notificationIcon = 11;
  static const double notificationIconGap = 4;
  static const double rowWithNotification = 46;
  static const double rowWithNotificationAndContext = 62;
  static const double ringWidth = 2;
  static const double ringGlowWidth = 1;
  static const double aggregateDot = 6;
  static const double panelWidth = 360;
  static const double panelMaxHeight = 480;
  static const double panelOffsetY = 4;
  static const double panelHeader = 36;
  static const double panelItem = 52;
  static const double panelUnreadSlot = 16;
  static const double panelEmptyIcon = 24;
  static const double headerBellGap = 4;
  static const double bellDot = 6;
```

ARB: add every key of UI-A4 §9 to both files. `app_en.arb` entries (with metadata):

```json
  "attentionBell": "Bell",
  "attentionBellRepeat": "Bell ×{count}",
  "@attentionBellRepeat": {"placeholders": {"count": {"type": "int"}}},
  "attentionBellBody": "Bell in this tab",
  "attentionUnreadCount": "{count, plural, =1{1 unread notification} other{{count} unread notifications}}",
  "@attentionUnreadCount": {"placeholders": {"count": {"type": "int"}}},
  "attentionRowSemantics": "{count, plural, =1{1 unread notification} other{{count} unread notifications}}, latest: {text}",
  "@attentionRowSemantics": {"placeholders": {"count": {"type": "int"}, "text": {"type": "String"}}},
  "attentionMarkRead": "Mark as read",
  "attentionMarkAllRead": "Mark all as read",
  "attentionAnnounce": "New notification from {tab}: {text}",
  "@attentionAnnounce": {"placeholders": {"tab": {"type": "String"}, "text": {"type": "String"}}},
  "workspaceHasUnread": "has unread notifications",
  "terminalPaneUnreadLabel": "Terminal {title}, has unread notifications",
  "@terminalPaneUnreadLabel": {"placeholders": {"title": {"type": "String"}}},
  "notificationsPanelTitle": "Notifications",
  "notificationsPanelTooltip": "Notifications  {shortcut}",
  "@notificationsPanelTooltip": {"placeholders": {"shortcut": {"type": "String"}}},
  "notificationsPanelEmptyTitle": "No notifications yet",
  "notificationsPanelEmptyBody": "Programs in your tabs send notifications with OSC 9, 99, 777 or the shellx notify command.",
  "notificationsPanelNextHint": "Next unread  {shortcut}",
  "@notificationsPanelNextHint": {"placeholders": {"shortcut": {"type": "String"}}},
  "notificationsPanelOpened": "{count, plural, =1{Notifications, 1 item} other{Notifications, {count} items}}",
  "@notificationsPanelOpened": {"placeholders": {"count": {"type": "int"}}},
  "notificationsTabClosed": "Tab closed",
  "notificationsTimeNow": "now",
  "notificationsTimeMinutes": "{count} min",
  "@notificationsTimeMinutes": {"placeholders": {"count": {"type": "int"}}},
  "notificationsTimeHours": "{count} h",
  "@notificationsTimeHours": {"placeholders": {"count": {"type": "int"}}},
  "notificationsItemUnread": "unread",
  "noUnreadNotifications": "No unread notifications",
  "systemNotifyCoalesced": "{count} new notifications · {text}",
  "@systemNotifyCoalesced": {"placeholders": {"count": {"type": "int"}, "text": {"type": "String"}}},
  "trayNotifications": "Notifications",
  "trayDesktopNotifications": "Notifications on this computer",
  "trayDesktopNotificationsUnfocused": "Only when the window isn't in front"
```

`app_vi.arb` (same keys, no metadata needed beyond what the file's convention uses — copy the `@` blocks if the vi file carries them):

```json
  "attentionBell": "Chuông",
  "attentionBellRepeat": "Chuông ×{count}",
  "attentionBellBody": "Chuông trong tab này",
  "attentionUnreadCount": "{count, plural, other{{count} thông báo chưa đọc}}",
  "attentionRowSemantics": "{count, plural, other{{count} thông báo chưa đọc}}, mới nhất: {text}",
  "attentionMarkRead": "Đánh dấu đã đọc",
  "attentionMarkAllRead": "Đánh dấu tất cả đã đọc",
  "attentionAnnounce": "Thông báo mới từ {tab}: {text}",
  "workspaceHasUnread": "có thông báo chưa đọc",
  "terminalPaneUnreadLabel": "Terminal {title}, có thông báo chưa đọc",
  "notificationsPanelTitle": "Thông báo",
  "notificationsPanelTooltip": "Thông báo  {shortcut}",
  "notificationsPanelEmptyTitle": "Chưa có thông báo nào",
  "notificationsPanelEmptyBody": "Chương trình trong tab gửi thông báo bằng OSC 9, 99, 777 hoặc lệnh shellx notify.",
  "notificationsPanelNextHint": "Chưa đọc tiếp theo  {shortcut}",
  "notificationsPanelOpened": "{count, plural, other{Thông báo, {count} mục}}",
  "notificationsTabClosed": "Tab đã đóng",
  "notificationsTimeNow": "vừa xong",
  "notificationsTimeMinutes": "{count} phút",
  "notificationsTimeHours": "{count} giờ",
  "notificationsItemUnread": "chưa đọc",
  "noUnreadNotifications": "Không còn thông báo chưa đọc",
  "systemNotifyCoalesced": "{count} thông báo mới · {text}",
  "trayNotifications": "Thông báo",
  "trayDesktopNotifications": "Thông báo trên máy tính",
  "trayDesktopNotificationsUnfocused": "Chỉ khi cửa sổ không ở phía trước"
```

Then `cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter gen-l10n`.

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/ui/window_focus_test.dart test/ui/window_host_test.dart test/l10n test/platform/storage_test.dart`
Expected: PASS (the l10n parity test sees identical keys in both ARB files).

- [ ] **Step 5: Format, analyze, commit**

```bash
cd apps/desktop && ~/fvm/versions/3.41.4/bin/dart format --set-exit-if-changed lib/src/ui lib/src/platform/settings_store.dart test/ui && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter analyze
cd ../.. && git add apps/desktop/lib/l10n apps/desktop/lib/src/platform/settings_store.dart apps/desktop/lib/src/ui/theme/shellx_desktop_theme.dart apps/desktop/lib/src/ui/window_focus.dart apps/desktop/lib/src/ui/window_host.dart apps/desktop/test/ui/window_focus_test.dart apps/desktop/test/ui/window_host_test.dart
git commit -m "feat(desktop): A4 strings, notification settings keys, sizes and window focus state"
```

---

### Task 4: Desktop — `TabAttention` (unread, history, 1 s read, next unread, jump)

**Files:**
- Create: `apps/desktop/lib/src/terminal/tab_attention.dart`
- Modify: `apps/desktop/lib/src/terminal/sidebar_workspaces.dart` (add `reveal`)
- Create: `apps/desktop/test/terminal/tab_attention_test.dart`

**Interfaces:**
- Consumes: `LocalSessions.notices`, `SessionNotice`, `SessionNoticeKind` (Task 2); `NotificationText(locale).commandBody(CompletedCommand)` (existing, shellx_agent); `terminalTabsProvider` (`TerminalTabsState.tabs/selectedId`, `TerminalTabs.select`); `sidebarWorkspacesProvider` (`SidebarState.orderedTabIds`, `workspaceOf`, `setCollapsed`); `appL10nProvider`; `windowActiveProvider`, `terminalFocusRequestProvider` (Task 3).
- Produces:
  - `enum AttentionKind { message, command, bell }`
  - `TabUnread {int count; String text; AttentionKind kind; DateTime at}`
  - `AttentionEntry {int seq; int tabId; String tabLabel; AttentionKind kind; String text; DateTime at; bool read; int repeat; bool closed}`
  - `AttentionState {Map<int, TabUnread> unread; List<AttentionEntry> history; int get totalUnread; bool hasUnread(int)}`
  - `AttentionArrival {int tabId; AttentionKind kind; String text; DateTime at}`
  - `String unreadBadgeLabel(int count)` (`'99+'` over 99)
  - `String noticeText(SessionNotice n, AppLocalizations l10n)`
  - `tabAttentionProvider` (`NotifierProvider<TabAttention, AttentionState>`); `TabAttention.arrivals → Stream<AttentionArrival>`, `TabAttention.reads → Stream<int>` (tab ids marked read), `markRead(int)`, `markAllRead()`, `int? nextUnread()`, `bool jumpTo(int tabId)`; `TabAttention.historyLimit = 50`, `TabAttention.dwell = Duration(seconds: 1)`.
  - `SidebarWorkspaces.reveal(int tabId)`

- [ ] **Step 1: Write the failing tests**

Create `apps/desktop/test/terminal/tab_attention_test.dart`:

```dart
import 'dart:ui';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_desktop/l10n/app_localizations.dart';
import 'package:shellx_desktop/src/platform/settings_store.dart';
import 'package:shellx_desktop/src/terminal/local_sessions_provider.dart';
import 'package:shellx_desktop/src/terminal/sidebar_workspaces.dart';
import 'package:shellx_desktop/src/terminal/tab_attention.dart';
import 'package:shellx_desktop/src/terminal/terminal_tabs.dart';
import 'package:shellx_desktop/src/ui/window_focus.dart';
import 'package:shellx_desktop/src/ui/window_router.dart';

import '../support/fake_local_sessions.dart';

void main() {
  late FakeLocalSessions local;
  late ProviderContainer c;

  AttentionState state() => c.read(tabAttentionProvider);
  TabAttention attention() => c.read(tabAttentionProvider.notifier);

  void boot({bool active = false, String locale = 'en'}) {
    c = ProviderContainer.test(
      overrides: [
        localSessionsProvider.overrideWithValue(local),
        appL10nProvider.overrideWithValue(
          lookupAppLocalizations(Locale(locale)),
        ),
        settingsStoreProvider.overrideWithValue(InMemorySettingsStore()),
      ],
    );
    c.read(terminalTabsProvider);
    c.read(sidebarWorkspacesProvider);
    state();
    setActive(active);
  }

  void setActive(bool active) {
    final router = c.read(windowRouterProvider.notifier);
    active ? router.showTerminal() : router.hideWindow();
    c.read(windowFocusProvider.notifier).set(active);
  }

  setUp(() {
    local = FakeLocalSessions();
    local.add(local.summary(1, origin: SessionOrigin.desktop, title: 'zsh'));
    local.add(local.summary(2, title: 'api'));
    local.add(local.summary(3, title: 'web'));
  });

  test('a notice for an unselected tab is unread with its text (D8, D9)',
      () {
    boot(active: true);
    final arrivals = <AttentionArrival>[];
    attention().arrivals.listen(arrivals.add);
    local.notice(2, SessionNoticeKind.message, title: 'CI', body: 'green\nok');
    local.notice(2, SessionNoticeKind.message, body: 'two');
    expect(state().unread[2]!.count, 2);
    expect(state().unread[2]!.text, 'two');
    expect(state().history.first.text, 'two');
    expect(state().history.last.text, 'CI: green ok');
    expect(state().totalUnread, 2);
    expect(arrivals.map((a) => a.tabId), [2, 2]);
  });

  test('a command notice uses the push wording in the app language (D5)', () {
    boot(locale: 'vi');
    local.notice(
      2,
      SessionNoticeKind.command,
      command: const CompletedCommand(
        commandLine: 'npm test',
        exitCode: 1,
        duration: Duration(seconds: 45),
      ),
    );
    expect(state().unread[2]!.text, '✗ npm test · mã 1 · 45 giây');
  });

  test('selected tab + active window: seen, no unread, no arrival; a bell '
      'there is dropped (D7)', () {
    boot(active: true); // tab 1 is selected
    final arrivals = <AttentionArrival>[];
    attention().arrivals.listen(arrivals.add);
    local.notice(1, SessionNoticeKind.message, body: 'seen');
    local.notice(1, SessionNoticeKind.bell);
    expect(state().unread, isEmpty);
    expect(state().history.single.read, isTrue);
    expect(arrivals, isEmpty);
  });

  test('selected tab while the window is inactive: unread + arrival', () {
    boot();
    local.notice(1, SessionNoticeKind.message, body: 'away');
    expect(state().hasUnread(1), isTrue);
  });

  test('reading needs 1 s on the tab with the window active (D10)', () {
    fakeAsync((async) {
      boot(active: true);
      local.notice(2, SessionNoticeKind.message, body: 'x');
      c.read(terminalTabsProvider.notifier).select(2);
      async.elapse(const Duration(milliseconds: 900));
      c.read(terminalTabsProvider.notifier).select(3);
      async.elapse(const Duration(seconds: 2));
      expect(state().hasUnread(2), isTrue); // left before 1 s
      c.read(terminalTabsProvider.notifier).select(2);
      async.elapse(const Duration(milliseconds: 500));
      setActive(false); // blur restarts
      async.elapse(const Duration(seconds: 2));
      expect(state().hasUnread(2), isTrue);
      setActive(true);
      // A notice for another tab meanwhile does not restart the clock.
      async.elapse(const Duration(milliseconds: 600));
      local.notice(3, SessionNoticeKind.message, body: 'y');
      async.elapse(const Duration(milliseconds: 400));
      expect(state().hasUnread(2), isFalse);
      expect(state().history.where((e) => e.tabId == 2).every((e) => e.read),
          isTrue);
    });
  });

  test('markRead / markAllRead; reads stream reports tab ids (D23)', () {
    boot();
    final reads = <int>[];
    attention().reads.listen(reads.add);
    local.notice(2, SessionNoticeKind.message, body: 'a');
    local.notice(3, SessionNoticeKind.bell);
    attention().markRead(2);
    expect(state().hasUnread(2), isFalse);
    attention().markAllRead();
    expect(state().unread, isEmpty);
    expect(reads, [2, 3]);
  });

  test('consecutive bells of a tab merge in history (D11)', () {
    boot();
    final t = DateTime(2026, 10, 7, 9);
    local.notice(2, SessionNoticeKind.bell, at: t);
    local.notice(2, SessionNoticeKind.bell, at: t.add(const Duration(seconds: 6)));
    expect(state().history, hasLength(1));
    expect(state().history.single.repeat, 2);
    expect(state().unread[2]!.count, 2);
    expect(state().unread[2]!.text, 'Bell');
  });

  test('history keeps the newest 50 (D11)', () {
    boot();
    for (var i = 0; i < 60; i++) {
      local.notice(2, SessionNoticeKind.message, body: '$i');
    }
    expect(state().history, hasLength(TabAttention.historyLimit));
    expect(state().history.first.text, '59');
    expect(state().unread[2]!.count, 60);
  });

  test('a removed tab loses its unread; its history stays, closed (D26)', () {
    boot();
    local.notice(2, SessionNoticeKind.message, body: 'bye');
    c.read(terminalTabsProvider.notifier).close(2);
    expect(state().hasUnread(2), isFalse);
    expect(state().history.single.closed, isTrue);
    expect(state().history.single.tabLabel, 'api');
  });

  test('next unread follows sidebar order after the selected tab, wrapping '
      '(D13)', () {
    boot();
    expect(attention().nextUnread(), isNull);
    local.notice(3, SessionNoticeKind.bell);
    local.notice(2, SessionNoticeKind.bell);
    expect(attention().nextUnread(), 2); // selected is 1
    c.read(terminalTabsProvider.notifier).select(2);
    expect(attention().nextUnread(), 3);
    c.read(terminalTabsProvider.notifier).select(3);
    expect(attention().nextUnread(), 2);
  });

  test('jumpTo selects, expands the workspace, reads, asks for focus (D16)',
      () async {
    boot();
    final workspaces = c.read(sidebarWorkspacesProvider.notifier);
    await workspaces.create(moveTab: 3);
    final ws = c.read(sidebarWorkspacesProvider).workspaceOf(3)!;
    workspaces.setCollapsed(ws, true);
    local.notice(3, SessionNoticeKind.message, body: 'here');
    expect(attention().jumpTo(3), isTrue);
    expect(c.read(terminalTabsProvider).selectedId, 3);
    expect(c.read(sidebarWorkspacesProvider).workspace(ws)!.collapsed, isFalse);
    expect(state().hasUnread(3), isFalse);
    expect(c.read(terminalFocusRequestProvider), 1);
    expect(attention().jumpTo(99), isFalse);
  });

  test('badge label caps at 99+', () {
    expect(unreadBadgeLabel(1), '1');
    expect(unreadBadgeLabel(99), '99');
    expect(unreadBadgeLabel(100), '99+');
  });
}
```

(If `SidebarWorkspaces.create` opens a tab in the real code path, use the existing test pattern from `sidebar_workspaces_test.dart` to put tab 3 in a second workspace — e.g. `create()` then `moveTab(3, newId)`.)

- [ ] **Step 2: Run test to verify it fails**

Run: `cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/terminal/tab_attention_test.dart`
Expected: FAIL — `tab_attention.dart` missing.

- [ ] **Step 3: Implement**

Add to `SidebarWorkspaces` (sidebar_workspaces.dart), next to `setCollapsed`:

```dart
  /// A4 D13/D16: the workspace holding [tabId] is expanded.
  void reveal(int tabId) {
    final id = state.workspaceOf(tabId);
    if (id != null) setCollapsed(id, false);
  }
```

Create `apps/desktop/lib/src/terminal/tab_attention.dart`:

```dart
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shellx_agent/shellx_agent.dart';

import '../../l10n/app_localizations.dart';
import '../ui/window_focus.dart';
import 'local_sessions_provider.dart';
import 'sidebar_workspaces.dart';
import 'terminal_tabs.dart';

enum AttentionKind { message, command, bell }

/// A tab's unread notifications since it was last read (A4 D8, D9).
@immutable
final class TabUnread {
  const TabUnread({
    required this.count,
    required this.text,
    required this.kind,
    required this.at,
  });
  final int count;

  /// The last one's text (the sidebar line).
  final String text;
  final AttentionKind kind;
  final DateTime at;
}

/// One panel entry (A4 D11). Text lives only in memory (N9).
@immutable
final class AttentionEntry {
  const AttentionEntry({
    required this.seq,
    required this.tabId,
    required this.tabLabel,
    required this.kind,
    required this.text,
    required this.at,
    this.read = false,
    this.repeat = 1,
    this.closed = false,
  });
  final int seq;
  final int tabId;

  /// The tab's label when it arrived (shown once the tab is gone).
  final String tabLabel;
  final AttentionKind kind;
  final String text;
  final DateTime at;
  final bool read;

  /// Merged consecutive bells ("Chuông ×N").
  final int repeat;

  /// The tab is gone: shown as "Tab đã đóng", not jumpable.
  final bool closed;

  AttentionEntry copyWith({bool? read, int? repeat, DateTime? at, bool? closed}) =>
      AttentionEntry(
        seq: seq,
        tabId: tabId,
        tabLabel: tabLabel,
        kind: kind,
        text: text,
        at: at ?? this.at,
        read: read ?? this.read,
        repeat: repeat ?? this.repeat,
        closed: closed ?? this.closed,
      );
}

@immutable
final class AttentionState {
  const AttentionState({this.unread = const {}, this.history = const []});

  final Map<int, TabUnread> unread;

  /// Newest first, at most [TabAttention.historyLimit].
  final List<AttentionEntry> history;

  int get totalUnread => unread.values.fold(0, (sum, u) => sum + u.count);
  bool hasUnread(int tabId) => unread.containsKey(tabId);
}

/// A notice the user has not seen (not D7): system notification, taskbar
/// flash, screen-reader announcement.
@immutable
final class AttentionArrival {
  const AttentionArrival({
    required this.tabId,
    required this.kind,
    required this.text,
    required this.at,
  });
  final int tabId;
  final AttentionKind kind;
  final String text;
  final DateTime at;
}

/// UI-A4 §2.1, D8.
String unreadBadgeLabel(int count) => count > 99 ? '99+' : '$count';

final _controls = RegExp(r'\s*[\x00-\x1f\x7f]+\s*');

/// A4 D9: the line a notice shows, on one line.
String noticeText(SessionNotice n, AppLocalizations l10n) {
  final text = switch (n.kind) {
    SessionNoticeKind.message =>
      n.title == null ? (n.body ?? '') : '${n.title}: ${n.body ?? ''}',
    SessionNoticeKind.command => NotificationText(
      l10n.localeName,
    ).commandBody(n.command!),
    SessionNoticeKind.bell => l10n.attentionBell,
  };
  return text.replaceAll(_controls, ' ').trim();
}

final tabAttentionProvider = NotifierProvider<TabAttention, AttentionState>(
  TabAttention.new,
);

/// Which tabs want the user (A4 N2–N5, D4, D7–D13, D26). UI state of this
/// window only; the agent just reports notices.
class TabAttention extends Notifier<AttentionState> {
  static const int historyLimit = 50;
  static const Duration dwell = Duration(seconds: 1);

  final _arrivals = StreamController<AttentionArrival>.broadcast(sync: true);
  final _reads = StreamController<int>.broadcast(sync: true);
  Timer? _dwell;
  int? _dwellFor;
  int _seq = 0;

  Stream<AttentionArrival> get arrivals => _arrivals.stream;

  /// Tab ids that were marked read (their system notification is removed).
  Stream<int> get reads => _reads.stream;

  @override
  AttentionState build() {
    final local = ref.watch(localSessionsProvider);
    final sub = local.notices.listen(_onNotice);
    ref.listen<TerminalTabsState>(terminalTabsProvider, (_, tabs) {
      _dropGone(tabs);
      _armDwell();
    });
    ref.listen<bool>(windowActiveProvider, (_, _) => _armDwell());
    ref.onDispose(() {
      unawaited(sub.cancel());
      _dwell?.cancel();
      unawaited(_arrivals.close());
      unawaited(_reads.close());
    });
    return const AttentionState();
  }

  void markRead(int tabId) {
    final had = state.hasUnread(tabId);
    final unread = Map.of(state.unread)..remove(tabId);
    state = AttentionState(
      unread: unread,
      history: [
        for (final e in state.history)
          e.tabId == tabId && !e.read ? e.copyWith(read: true) : e,
      ],
    );
    if (_dwellFor == tabId) _cancelDwell();
    if (had) _reads.add(tabId);
  }

  void markAllRead() {
    for (final id in state.unread.keys.toList()) {
      markRead(id);
    }
  }

  /// D13: the next tab with unread after the selected one, in sidebar
  /// order (collapsed workspaces included), wrapping.
  int? nextUnread() {
    if (state.unread.isEmpty) return null;
    final order = ref.read(sidebarWorkspacesProvider).orderedTabIds;
    if (order.isEmpty) return null;
    final start = order.indexOf(ref.read(terminalTabsProvider).selectedId ?? -1);
    for (var step = 1; step <= order.length; step++) {
      final id = order[(start + step) % order.length];
      if (state.hasUnread(id)) return id;
    }
    return null;
  }

  /// D16 / panel Enter / next unread: select, expand its workspace, read
  /// at once (the user asked), keyboard to the terminal. False when the
  /// tab is gone.
  bool jumpTo(int tabId) {
    if (!ref.read(terminalTabsProvider).tabs.any((t) => t.id == tabId)) {
      return false;
    }
    ref.read(sidebarWorkspacesProvider.notifier).reveal(tabId);
    ref.read(terminalTabsProvider.notifier).select(tabId);
    markRead(tabId);
    ref.read(terminalFocusRequestProvider.notifier).request();
    return true;
  }

  // ---- internals --------------------------------------------------------

  void _onNotice(SessionNotice notice) {
    if (!ref.mounted) return;
    final tabs = ref.read(terminalTabsProvider);
    TerminalTab? tab;
    for (final t in tabs.tabs) {
      if (t.id == notice.sessionId) tab = t;
    }
    if (tab == null) return; // not (or no longer) a tab of this window
    final seen = tabs.selectedId == tab.id && ref.read(windowActiveProvider);
    if (seen && notice.kind == SessionNoticeKind.bell) return; // D7
    final kind = AttentionKind.values.byName(notice.kind.name);
    final text = noticeText(notice, ref.read(appL10nProvider));
    final history = _withEntry(tab, kind, text, notice.at, read: seen);
    if (seen) {
      state = AttentionState(unread: state.unread, history: history);
      return;
    }
    final before = state.unread[tab.id];
    state = AttentionState(
      unread: {
        ...state.unread,
        tab.id: TabUnread(
          count: (before?.count ?? 0) + 1,
          text: text,
          kind: kind,
          at: notice.at,
        ),
      },
      history: history,
    );
    _arrivals.add(
      AttentionArrival(tabId: tab.id, kind: kind, text: text, at: notice.at),
    );
    _armDwell();
  }

  List<AttentionEntry> _withEntry(
    TerminalTab tab,
    AttentionKind kind,
    String text,
    DateTime at, {
    required bool read,
  }) {
    final history = state.history;
    final first = history.firstOrNull;
    if (kind == AttentionKind.bell &&
        first != null &&
        first.kind == AttentionKind.bell &&
        first.tabId == tab.id &&
        first.read == read) {
      return [first.copyWith(repeat: first.repeat + 1, at: at), ...history.skip(1)];
    }
    return [
      AttentionEntry(
        seq: _seq++,
        tabId: tab.id,
        tabLabel: tab.label,
        kind: kind,
        text: text,
        at: at,
        read: read,
      ),
      ...history.take(historyLimit - 1),
    ];
  }

  /// D26: tabs that went away lose their unread; history keeps them.
  void _dropGone(TerminalTabsState tabs) {
    final ids = {for (final t in tabs.tabs) t.id};
    final gone = state.unread.keys.where((id) => !ids.contains(id)).toList();
    final closing = state.history.any((e) => !e.closed && !ids.contains(e.tabId));
    if (gone.isEmpty && !closing) return;
    state = AttentionState(
      unread: Map.of(state.unread)..removeWhere((id, _) => !ids.contains(id)),
      history: [
        for (final e in state.history)
          !e.closed && !ids.contains(e.tabId) ? e.copyWith(closed: true) : e,
      ],
    );
    for (final id in gone) {
      _reads.add(id);
    }
  }

  /// D10: one timer for the selected tab while it has unread and the
  /// window is active; unchanged conditions keep the running timer.
  void _armDwell() {
    if (!ref.mounted) return;
    final id = ref.read(terminalTabsProvider).selectedId;
    final wanted =
        id != null && state.hasUnread(id) && ref.read(windowActiveProvider);
    if (!wanted) {
      _cancelDwell();
      return;
    }
    if (_dwellFor == id && (_dwell?.isActive ?? false)) return;
    _cancelDwell();
    _dwellFor = id;
    _dwell = Timer(dwell, () {
      _dwellFor = null;
      if (!ref.mounted) return;
      if (ref.read(terminalTabsProvider).selectedId == id &&
          ref.read(windowActiveProvider)) {
        markRead(id);
      }
    });
  }

  void _cancelDwell() {
    _dwell?.cancel();
    _dwell = null;
    _dwellFor = null;
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/terminal`
Expected: PASS.

- [ ] **Step 5: Format, analyze, commit**

```bash
cd apps/desktop && ~/fvm/versions/3.41.4/bin/dart format --set-exit-if-changed lib/src/terminal test/terminal && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter analyze
cd ../.. && git add apps/desktop/lib/src/terminal/tab_attention.dart apps/desktop/lib/src/terminal/sidebar_workspaces.dart apps/desktop/test/terminal/tab_attention_test.dart
git commit -m "feat(desktop): TabAttention — unread per tab, history, 1 s read, next unread, jump (A4 D7-D13)"
```

---

### Task 5: Desktop — system notifications and the "Thông báo" tray submenu

**Files:**
- Modify: `apps/desktop/lib/src/platform/notifier.dart`
- Create: `apps/desktop/lib/src/platform/desktop_notifications.dart`
- Modify: `apps/desktop/test/support/fakes.dart` (`RecordingNotifier`, `ShownNotification`)
- Modify: `apps/desktop/lib/src/agent/agent_state.dart`, `apps/desktop/lib/src/agent/agent_controller.dart`
- Modify: `apps/desktop/lib/src/tray/tray_action.dart`, `tray_actions.dart`, `tray_menu.dart`
- Create: `apps/desktop/test/platform/desktop_notifications_test.dart`
- Create: `apps/desktop/test/tray/tray_notifications_test.dart`
- Modify: `apps/desktop/test/tray/tray_notify_threshold_test.dart`, `tray_menu_test.dart` (the threshold submenu moved)

**Interfaces:**
- Consumes: `AttentionArrival`, `AttentionKind`, `tabAttentionProvider` (`arrivals`, `reads`, `jumpTo`) (Task 4); `windowActiveProvider` (Task 3); `SettingKeys.desktopNotifications*` (Task 3); `terminalTabsProvider`, `sidebarWorkspacesProvider` (`showHeaders`, `workspaceOf`, `displayName`), `windowRouterProvider.showTerminal()`.
- Produces:
  - `SystemNotifier.show({required String title, String? body, String? id, void Function()? onClick})`, `SystemNotifier.close(String id)`
  - `final class DesktopNotifications { DesktopNotifications({required SystemNotifier notifier, required SettingsStore settings, required AppLocalizations l10n, required void Function(int tabId) onOpen, DateTime Function()? now, Duration coalesce = 3 s, int perTab = 6, int perApp = 20, Duration window = 60 s, void Function(String)? log}); void arrived(AttentionArrival a, {required String title, required bool windowFocused, required bool tabSelected}); void tabRead(int tabId); void dispose(); static String idFor(int tabId); }`
  - `void listenForDesktopNotifications({required ProviderContainer container, required DesktopNotifications notifications})`
  - `String systemNotificationTitle(TerminalTab tab, SidebarState sidebar, AppLocalizations l10n)`
  - `AgentViewState.desktopNotifications`, `.desktopNotificationsOnlyUnfocused` (bool, default true); `AgentController.setDesktopNotifications(bool)`, `setDesktopNotificationsOnlyUnfocused(bool)`; tray actions `ToggleDesktopNotifications`, `ToggleDesktopNotificationsOnlyUnfocused`; `TrayKeys.notifications`, `desktopNotifications`, `desktopNotificationsOnlyUnfocused`.

- [ ] **Step 1: Write the failing tests**

Update `apps/desktop/test/support/fakes.dart`:

```dart
final class ShownNotification {
  const ShownNotification(this.title, this.body, this.onClick, {this.id});
  final String title;
  final String? body;
  final void Function()? onClick;
  final String? id;
}

final class RecordingNotifier implements SystemNotifier {
  final List<ShownNotification> shown = [];
  final List<String> closed = [];

  /// Throws instead of showing (notifications denied by the OS).
  bool fail = false;

  @override
  Future<void> show({
    required String title,
    String? body,
    String? id,
    void Function()? onClick,
  }) async {
    if (fail) throw Exception('notifications denied');
    shown.add(ShownNotification(title, body, onClick, id: id));
  }

  @override
  Future<void> close(String id) async => closed.add(id);
}
```

Create `apps/desktop/test/platform/desktop_notifications_test.dart`:

```dart
import 'dart:ui';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/l10n/app_localizations.dart';
import 'package:shellx_desktop/src/platform/desktop_notifications.dart';
import 'package:shellx_desktop/src/platform/settings_store.dart';
import 'package:shellx_desktop/src/terminal/tab_attention.dart';

import '../support/fakes.dart';

void main() {
  late RecordingNotifier notifier;
  late InMemorySettingsStore settings;
  late List<int> opened;
  late DateTime now;
  late DesktopNotifications n;

  AttentionArrival msg(int tab, String text, {AttentionKind kind = AttentionKind.message}) =>
      AttentionArrival(tabId: tab, kind: kind, text: text, at: now);

  void boot() {
    notifier = RecordingNotifier();
    settings = InMemorySettingsStore();
    opened = [];
    now = DateTime(2026, 10, 7, 9);
    n = DesktopNotifications(
      notifier: notifier,
      settings: settings,
      l10n: lookupAppLocalizations(const Locale('en')),
      onOpen: opened.add,
      now: () => now,
    );
  }

  test('D14 matrix with "only when not in front" on (default)', () {
    fakeAsync((async) {
      boot();
      n.arrived(msg(1, 'a'), title: 'api', windowFocused: true, tabSelected: false);
      n.arrived(msg(2, 'b'), title: 'web', windowFocused: false, tabSelected: true);
      async.flushMicrotasks();
      expect(notifier.shown.map((s) => (s.title, s.body, s.id)), [
        ('web', 'b', DesktopNotifications.idFor(2)),
      ]);
    });
  });

  test('"only when not in front" off: an unselected tab notifies even when '
      'focused; a bell still needs an unfocused window', () {
    fakeAsync((async) {
      boot();
      settings.values[SettingKeys.desktopNotificationsOnlyUnfocused] = false;
      n.arrived(msg(1, 'a'), title: 'api', windowFocused: true, tabSelected: false);
      n.arrived(msg(3, 'Bell', kind: AttentionKind.bell),
          title: 'zsh', windowFocused: true, tabSelected: false);
      n.arrived(msg(4, 'Bell', kind: AttentionKind.bell),
          title: 'vim', windowFocused: false, tabSelected: false);
      async.flushMicrotasks();
      expect(notifier.shown.map((s) => (s.title, s.body)), [
        ('api', 'a'),
        ('vim', 'Bell in this tab'),
      ]);
    });
  });

  test('switched off: nothing is posted', () {
    fakeAsync((async) {
      boot();
      settings.values[SettingKeys.desktopNotifications] = false;
      n.arrived(msg(1, 'a'), title: 'api', windowFocused: false, tabSelected: false);
      async.flushMicrotasks();
      expect(notifier.shown, isEmpty);
    });
  });

  test('a burst posts the first at once and one coalesced after 3 s (D15)',
      () {
    fakeAsync((async) {
      boot();
      for (var i = 1; i <= 20; i++) {
        n.arrived(msg(1, '$i'), title: 'api', windowFocused: false, tabSelected: false);
      }
      async.flushMicrotasks();
      expect(notifier.shown.single.body, '1');
      async.elapse(const Duration(seconds: 3));
      expect(notifier.shown.map((s) => s.body), [
        '1',
        '19 new notifications · 20',
      ]);
      expect(notifier.shown.map((s) => s.id).toSet(), {DesktopNotifications.idFor(1)});
    });
  });

  test('at most 6 posts per tab per 60 s, 20 per app (D15)', () {
    fakeAsync((async) {
      boot();
      for (var i = 0; i < 10; i++) {
        n.arrived(msg(1, '$i'), title: 'api', windowFocused: false, tabSelected: false);
        async.elapse(const Duration(seconds: 4)); // past each burst window
        now = now.add(const Duration(seconds: 4));
      }
      expect(notifier.shown, hasLength(6));
      for (var tab = 10; tab < 40; tab++) {
        n.arrived(msg(tab, 'x'), title: 't', windowFocused: false, tabSelected: false);
      }
      async.flushMicrotasks();
      expect(notifier.shown, hasLength(20));
    });
  });

  test('reading a tab cancels its pending burst and removes the delivered '
      'notification', () {
    fakeAsync((async) {
      boot();
      n.arrived(msg(1, 'a'), title: 'api', windowFocused: false, tabSelected: false);
      n.arrived(msg(1, 'b'), title: 'api', windowFocused: false, tabSelected: false);
      n.tabRead(1);
      async.elapse(const Duration(seconds: 5));
      expect(notifier.shown, hasLength(1));
      expect(notifier.closed, [DesktopNotifications.idFor(1)]);
    });
  });

  test('a click opens the tab (D16); an OS failure is swallowed', () {
    fakeAsync((async) {
      boot();
      n.arrived(msg(7, 'a'), title: 'api', windowFocused: false, tabSelected: false);
      async.flushMicrotasks();
      notifier.shown.single.onClick!();
      expect(opened, [7]);
      notifier.fail = true;
      n.arrived(msg(8, 'b'), title: 'x', windowFocused: false, tabSelected: false);
      async.flushMicrotasks(); // no unhandled error
    });
  });

  test('title and body are cut (UI-A4 §6)', () {
    fakeAsync((async) {
      boot();
      n.arrived(msg(1, 'b' * 300), title: 't' * 100, windowFocused: false, tabSelected: false);
      async.flushMicrotasks();
      expect(notifier.shown.single.title.runes.length, 80);
      expect(notifier.shown.single.body!.runes.length, 200);
    });
  });
}
```

Create `apps/desktop/test/tray/tray_notifications_test.dart` (follow `tray_notify_threshold_test.dart`'s setup with `buildTrayMenu`, `TrayMenuIds`, `AgentViewState`):

```dart
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/l10n/app_localizations.dart';
import 'package:shellx_desktop/src/agent/agent_state.dart';
import 'package:shellx_desktop/src/tray/tray_action.dart';
import 'package:shellx_desktop/src/tray/tray_menu.dart';
import 'package:tray_manager/tray_manager.dart';

void main() {
  final l10n = lookupAppLocalizations(const Locale('vi'));

  MenuItem notifications(Menu menu) =>
      menu.items!.firstWhere((i) => i.key == TrayKeys.notifications);

  for (final signedIn in [true, false]) {
    test('"Thông báo" submenu, signed in: $signedIn (D20)', () {
      final state = AgentViewState(
        phase: signedIn ? AuthPhase.signedIn : AuthPhase.signedOut,
        desktopNotifications: true,
        desktopNotificationsOnlyUnfocused: false,
      );
      final menu = buildTrayMenu(state, l10n, TrayMenuIds());
      final sub = notifications(menu);
      expect(sub.label, 'Thông báo');
      final items = sub.submenu!.items!;
      expect(items[0].key, TrayKeys.desktopNotifications);
      expect(items[0].checked, isTrue);
      expect(items[1].key, TrayKeys.desktopNotificationsOnlyUnfocused);
      expect(items[1].checked, isFalse);
      expect(items[1].disabled, isFalse);
      expect(items.last.key, TrayKeys.notifyThreshold);
    });
  }

  test('"only when not in front" is disabled while notifications are off', () {
    final menu = buildTrayMenu(
      const AgentViewState(
        phase: AuthPhase.signedOut,
        desktopNotifications: false,
      ),
      l10n,
      TrayMenuIds(),
    );
    expect(notifications(menu).submenu!.items![1].disabled, isTrue);
  });

  test('keys map to actions', () {
    expect(
      trayActionForKey(TrayKeys.desktopNotifications),
      isA<ToggleDesktopNotifications>(),
    );
    expect(
      trayActionForKey(TrayKeys.desktopNotificationsOnlyUnfocused),
      isA<ToggleDesktopNotificationsOnlyUnfocused>(),
    );
  });
}
```

(Use whatever `AuthPhase` value names and `AgentViewState` signed-in flag the existing tray tests use; the assertions above are what matter.) In `tray_notify_threshold_test.dart` and `tray_menu_test.dart`, update lookups of `TrayKeys.notifyThreshold` to look inside the `TrayKeys.notifications` submenu.

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/platform/desktop_notifications_test.dart test/tray`
Expected: FAIL — missing `desktop_notifications.dart`, `close`, new tray keys/state.

- [ ] **Step 3: Implement**

`apps/desktop/lib/src/platform/notifier.dart`:

```dart
import 'package:local_notifier/local_notifier.dart';

abstract interface class SystemNotifier {
  /// [id]: a later notification with the same id replaces this one
  /// (A4 D15); [close] removes it.
  Future<void> show({
    required String title,
    String? body,
    String? id,
    void Function()? onClick,
  });

  /// Removes the notification shown with [id], if it is still delivered.
  Future<void> close(String id);
}

/// Package local_notifier (NSUserNotification on macOS, WinToast on Windows).
final class LocalSystemNotifier implements SystemNotifier {
  LocalSystemNotifier._();

  static Future<LocalSystemNotifier> setup() async {
    await localNotifier.setup(
      appName: 'ShellX',
      shortcutPolicy: ShortcutPolicy.requireCreate,
    );
    return LocalSystemNotifier._();
  }

  final _shown = <String, LocalNotification>{};

  @override
  Future<void> show({
    required String title,
    String? body,
    String? id,
    void Function()? onClick,
  }) async {
    if (id != null) await close(id);
    final notification = LocalNotification(
      identifier: id,
      title: title,
      body: body,
    );
    notification.onClick = onClick;
    if (id != null) _shown[id] = notification;
    await notification.show();
  }

  @override
  Future<void> close(String id) async {
    final previous = _shown.remove(id);
    if (previous != null) await previous.close();
  }
}
```

Create `apps/desktop/lib/src/platform/desktop_notifications.dart`:

```dart
import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../terminal/sidebar_workspaces.dart';
import '../terminal/tab_attention.dart';
import '../terminal/terminal_tabs.dart';
import '../ui/window_focus.dart';
import 'notifier.dart';
import 'settings_store.dart';

final class _Burst {
  _Burst(this.title);
  String title;
  int extra = 0;
  String latest = '';
  Timer? timer;
}

/// Native notifications for tabs (A4 N6, D14–D17). Never throws; never
/// logs a title or text (N9).
final class DesktopNotifications {
  DesktopNotifications({
    required SystemNotifier notifier,
    required SettingsStore settings,
    required AppLocalizations l10n,
    required void Function(int tabId) onOpen,
    DateTime Function()? now,
    this.coalesce = const Duration(seconds: 3),
    this.perTab = 6,
    this.perApp = 20,
    this.window = const Duration(seconds: 60),
    void Function(String message)? log,
  }) : _notifier = notifier,
       _settings = settings,
       _l10n = l10n,
       _onOpen = onOpen,
       _now = now ?? DateTime.now,
       _log = log ?? debugPrint;

  static const int maxTitle = 80;
  static const int maxBody = 200;

  static String idFor(int tabId) => 'shellx.tab.$tabId';

  final SystemNotifier _notifier;
  final SettingsStore _settings;
  final AppLocalizations _l10n;
  final void Function(int tabId) _onOpen;
  final DateTime Function() _now;
  final void Function(String message) _log;
  final Duration coalesce;
  final int perTab;
  final int perApp;
  final Duration window;
  final _bursts = <int, _Burst>{};
  final _postsByTab = <int, List<DateTime>>{};
  final _posts = <DateTime>[];

  /// D14: whether [a] becomes a system notification, then D15.
  void arrived(
    AttentionArrival a, {
    required String title,
    required bool windowFocused,
    required bool tabSelected,
  }) {
    if (!_settings.getBool(SettingKeys.desktopNotifications, defaultValue: true)) {
      return;
    }
    final onlyUnfocused = _settings.getBool(
      SettingKeys.desktopNotificationsOnlyUnfocused,
      defaultValue: true,
    );
    final post = a.kind == AttentionKind.bell
        ? !windowFocused
        : !windowFocused || (!onlyUnfocused && !tabSelected);
    if (!post) return;
    final body = a.kind == AttentionKind.bell ? _l10n.attentionBellBody : a.text;
    final burst = _bursts[a.tabId];
    if (burst != null) {
      burst
        ..title = title
        ..extra += 1
        ..latest = body;
      return;
    }
    final fresh = _Burst(title);
    fresh.timer = Timer(coalesce, () => _flush(a.tabId));
    _bursts[a.tabId] = fresh;
    _post(a.tabId, title, body);
  }

  /// The tab was read (or closed): no pending burst, and its delivered
  /// notification leaves Notification/Action Center (D15).
  void tabRead(int tabId) {
    _bursts.remove(tabId)?.timer?.cancel();
    unawaited(_guard(() => _notifier.close(idFor(tabId))));
  }

  void dispose() {
    for (final b in _bursts.values) {
      b.timer?.cancel();
    }
    _bursts.clear();
  }

  void _flush(int tabId) {
    final burst = _bursts.remove(tabId);
    if (burst == null || burst.extra == 0) return;
    _post(
      tabId,
      burst.title,
      _l10n.systemNotifyCoalesced(burst.extra, burst.latest),
    );
  }

  void _post(int tabId, String title, String body) {
    final now = _now();
    bool full(List<DateTime> times, int max) {
      times.removeWhere((t) => now.difference(t) >= window);
      return times.length >= max;
    }

    final tabPosts = _postsByTab.putIfAbsent(tabId, () => []);
    if (full(tabPosts, perTab) || full(_posts, perApp)) {
      _log('ShellX: system notification skipped (rate limit)');
      return;
    }
    tabPosts.add(now);
    _posts.add(now);
    unawaited(
      _guard(
        () => _notifier.show(
          id: idFor(tabId),
          title: _clip(title, maxTitle),
          body: _clip(body, maxBody),
          onClick: () => _onOpen(tabId),
        ),
      ),
    );
  }

  Future<void> _guard(Future<void> Function() call) async {
    try {
      await call();
    } catch (error) {
      _log('ShellX: system notification failed: ${error.runtimeType}');
    }
  }

  static String _clip(String text, int max) {
    final runes = text.runes;
    return runes.length <= max
        ? text
        : '${String.fromCharCodes(runes.take(max - 1))}…';
  }
}

/// UI-A4 §6: "<tab>" or "<tab> · <workspace>" when headers show.
String systemNotificationTitle(
  TerminalTab tab,
  SidebarState sidebar,
  AppLocalizations l10n,
) {
  if (!sidebar.showHeaders) return tab.label;
  final ws = sidebar.workspaceOf(tab.id);
  final name = ws == null ? null : sidebar.workspace(ws)?.displayName(l10n);
  return name == null ? tab.label : '${tab.label} · $name';
}

/// `main.dart`: arrivals → [DesktopNotifications.arrived], reads →
/// [DesktopNotifications.tabRead]. Reading [tabAttentionProvider] here
/// also builds it at startup, so no notice is missed.
void listenForDesktopNotifications({
  required ProviderContainer container,
  required DesktopNotifications notifications,
  required AppLocalizations l10n,
}) {
  final attention = container.read(tabAttentionProvider.notifier);
  attention.arrivals.listen((a) {
    final tabs = container.read(terminalTabsProvider);
    TerminalTab? tab;
    for (final t in tabs.tabs) {
      if (t.id == a.tabId) tab = t;
    }
    if (tab == null) return;
    notifications.arrived(
      a,
      title: systemNotificationTitle(
        tab,
        container.read(sidebarWorkspacesProvider),
        l10n,
      ),
      windowFocused: container.read(windowActiveProvider),
      tabSelected: tabs.selectedId == a.tabId,
    );
  });
  attention.reads.listen(notifications.tabRead);
}
```

Tray / settings (D20):

- `agent_state.dart`: add fields `this.desktopNotifications = true, this.desktopNotificationsOnlyUnfocused = true,` (constructor), `final bool desktopNotifications; final bool desktopNotificationsOnlyUnfocused;`, and both in `copyWith` the same way as `keepAwake`.
- `agent_controller.dart`: in the state built at bootstrap (next to `notifyThresholdSeconds: notifyThresholdSeconds(settings),`):

```dart
      desktopNotifications: settings.getBool(
        SettingKeys.desktopNotifications,
        defaultValue: true,
      ),
      desktopNotificationsOnlyUnfocused: settings.getBool(
        SettingKeys.desktopNotificationsOnlyUnfocused,
        defaultValue: true,
      ),
```

and next to `setNotifyThreshold`:

```dart
  /// A4 D20: read by DesktopNotifications on every notice (no restart).
  Future<void> setDesktopNotifications(bool enabled) async {
    await _s.settings.setBool(SettingKeys.desktopNotifications, enabled);
    if (!ref.mounted) return;
    state = state.copyWith(desktopNotifications: enabled);
  }

  Future<void> setDesktopNotificationsOnlyUnfocused(bool enabled) async {
    await _s.settings.setBool(
      SettingKeys.desktopNotificationsOnlyUnfocused,
      enabled,
    );
    if (!ref.mounted) return;
    state = state.copyWith(desktopNotificationsOnlyUnfocused: enabled);
  }
```

- `tray_action.dart`:

```dart
final class ToggleDesktopNotifications extends TrayAction {
  const ToggleDesktopNotifications();
}

final class ToggleDesktopNotificationsOnlyUnfocused extends TrayAction {
  const ToggleDesktopNotificationsOnlyUnfocused();
}
```

`TrayKeys`: `static const String notifications = 'notifications';`, `static const String desktopNotifications = 'desktop_notifications';`, `static const String desktopNotificationsOnlyUnfocused = 'desktop_notifications_only_unfocused';`; in `trayActionForKey`'s final switch: `TrayKeys.desktopNotifications => const ToggleDesktopNotifications(), TrayKeys.desktopNotificationsOnlyUnfocused => const ToggleDesktopNotificationsOnlyUnfocused(),`.
- `tray_actions.dart` `handle` switch:

```dart
      case ToggleDesktopNotifications():
        await _agent.setDesktopNotifications(!state.desktopNotifications);
      case ToggleDesktopNotificationsOnlyUnfocused():
        await _agent.setDesktopNotificationsOnlyUnfocused(
          !state.desktopNotificationsOnlyUnfocused,
        );
```

- `tray_menu.dart`: inside `buildTrayMenu`, after the `sub(...)` helper, define

```dart
  // A4 D20: in both menus; the threshold submenu moved in here.
  MenuItem notifications() => sub(TrayKeys.notifications, l10n.trayNotifications, [
    check(
      TrayKeys.desktopNotifications,
      l10n.trayDesktopNotifications,
      state.desktopNotifications,
    ),
    check(
      TrayKeys.desktopNotificationsOnlyUnfocused,
      l10n.trayDesktopNotificationsUnfocused,
      state.desktopNotificationsOnlyUnfocused,
      disabled: !state.desktopNotifications,
    ),
    sep(),
    sub(TrayKeys.notifyThreshold, l10n.trayNotifyThreshold, [
      for (final seconds in kNotifyThresholdChoices)
        check(
          TrayKeys.notifyThresholdChoice(seconds),
          notifyThresholdLabel(seconds, l10n),
          seconds == state.notifyThresholdSeconds,
        ),
    ]),
  ]);
```

In the signed-out menu insert `notifications(), sep(),` right after the first `sep()`; in the signed-in menu replace the existing `// Push spec §7.` threshold `sub(...)` with `notifications(),`.

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/platform test/tray test/agent`
Expected: PASS.

- [ ] **Step 5: Format, analyze, commit**

```bash
cd apps/desktop && ~/fvm/versions/3.41.4/bin/dart format --set-exit-if-changed lib/src/platform lib/src/agent lib/src/tray test/platform test/tray test/support && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter analyze
cd ../.. && git add apps/desktop/lib/src/platform/notifier.dart apps/desktop/lib/src/platform/desktop_notifications.dart apps/desktop/lib/src/agent/agent_state.dart apps/desktop/lib/src/agent/agent_controller.dart apps/desktop/lib/src/tray/tray_action.dart apps/desktop/lib/src/tray/tray_actions.dart apps/desktop/lib/src/tray/tray_menu.dart apps/desktop/test/support/fakes.dart apps/desktop/test/platform/desktop_notifications_test.dart apps/desktop/test/tray/tray_notifications_test.dart apps/desktop/test/tray/tray_notify_threshold_test.dart apps/desktop/test/tray/tray_menu_test.dart
git commit -m "feat(desktop): coalesced, rate-limited system notifications and the Notifications tray submenu (A4 D14-D17, D20)"
```

---

### Task 6: Desktop — Dock badge (macOS) and taskbar overlay + flash (Windows)

**Files:**
- Create: `apps/desktop/lib/src/platform/attention_badge.dart`
- Create: `apps/desktop/test/platform/attention_badge_test.dart`
- Modify: `apps/desktop/windows/runner/flutter_window.h`, `flutter_window.cpp`, `CMakeLists.txt`

**Interfaces:**
- Consumes: `tabAttentionProvider` (`totalUnread`, `arrivals`), `unreadBadgeLabel` (Task 4); `windowActiveProvider` (Task 3); `windowRouterProvider` (`visible`); `AppLocalizations.attentionUnreadCount`.
- Produces:
  - `abstract interface class BadgeHost { Future<void> setUnread(int count, String description); Future<void> flash(); }`
  - `MacDockBadge`, `WindowsTaskbarBadge` (channel `pro.shellx.desktop/taskbar`: `setUnread {count:int, description:String}`, `flash`), `NoBadge`
  - `void listenForAttentionBadge({required ProviderContainer container, required BadgeHost host, required AppLocalizations l10n, required void Function(Future<void>) run})`

- [ ] **Step 1: Write the failing test**

Create `apps/desktop/test/platform/attention_badge_test.dart`:

```dart
import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_desktop/l10n/app_localizations.dart';
import 'package:shellx_desktop/src/platform/attention_badge.dart';
import 'package:shellx_desktop/src/platform/settings_store.dart';
import 'package:shellx_desktop/src/terminal/local_sessions_provider.dart';
import 'package:shellx_desktop/src/terminal/sidebar_workspaces.dart';
import 'package:shellx_desktop/src/terminal/tab_attention.dart';
import 'package:shellx_desktop/src/terminal/terminal_tabs.dart';
import 'package:shellx_desktop/src/ui/window_focus.dart';
import 'package:shellx_desktop/src/ui/window_router.dart';

import '../support/fake_local_sessions.dart';

final class _Host implements BadgeHost {
  final unread = <(int, String)>[];
  int flashes = 0;
  @override
  Future<void> setUnread(int count, String description) async =>
      unread.add((count, description));
  @override
  Future<void> flash() async => flashes++;
}

void main() {
  test('total unread drives the badge, re-applied when the window shows; '
      'flash only while inactive (D18, D19)', () async {
    final local = FakeLocalSessions();
    local.add(local.summary(1, title: 'a'));
    local.add(local.summary(2, title: 'b'));
    final c = ProviderContainer.test(
      overrides: [
        localSessionsProvider.overrideWithValue(local),
        appL10nProvider.overrideWithValue(
          lookupAppLocalizations(const Locale('en')),
        ),
        settingsStoreProvider.overrideWithValue(InMemorySettingsStore()),
      ],
    );
    c.read(terminalTabsProvider);
    final host = _Host();
    listenForAttentionBadge(
      container: c,
      host: host,
      l10n: lookupAppLocalizations(const Locale('en')),
      run: (f) {},
    );
    expect(host.unread, [(0, '0 unread notifications')]);
    local.notice(2, SessionNoticeKind.message, body: 'x');
    local.notice(2, SessionNoticeKind.message, body: 'y');
    expect(host.unread.last, (2, '2 unread notifications'));
    expect(host.flashes, 2); // window inactive
    c.read(windowRouterProvider.notifier).showTerminal();
    expect(host.unread.last.$1, 2); // re-applied on show
    c.read(windowFocusProvider.notifier).set(true);
    local.notice(2, SessionNoticeKind.message, body: 'z');
    expect(host.flashes, 2);
    c.read(tabAttentionProvider.notifier).markAllRead();
    expect(host.unread.last.$1, 0);
  });

  test('dock label', () {
    expect(dockBadgeLabel(0), '');
    expect(dockBadgeLabel(5), '5');
    expect(dockBadgeLabel(120), '99+');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/platform/attention_badge_test.dart`
Expected: FAIL — file missing.

- [ ] **Step 3: Implement**

Create `apps/desktop/lib/src/platform/attention_badge.dart`:

```dart
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import '../../l10n/app_localizations.dart';
import '../terminal/tab_attention.dart';
import '../ui/window_focus.dart';
import '../ui/window_router.dart';

/// The app icon's unread mark (A4 N7).
abstract interface class BadgeHost {
  /// [description] is for assistive technology (Windows overlay).
  Future<void> setUnread(int count, String description);

  /// A new notice while the window is not active (Windows: taskbar flash).
  Future<void> flash();
}

/// D18 / UI-A4 §1.1: '' clears; '99+' over 99.
String dockBadgeLabel(int count) => count <= 0 ? '' : unreadBadgeLabel(count);

/// macOS: `NSApp.dockTile.badgeLabel` through window_manager (D18).
final class MacDockBadge implements BadgeHost {
  const MacDockBadge();
  @override
  Future<void> setUnread(int count, String description) =>
      windowManager.setBadgeLabel(dockBadgeLabel(count));
  @override
  Future<void> flash() async {}
}

/// Windows: overlay dot + flash in the runner (D19).
final class WindowsTaskbarBadge implements BadgeHost {
  const WindowsTaskbarBadge({
    MethodChannel channel = const MethodChannel('pro.shellx.desktop/taskbar'),
  }) : _channel = channel;
  final MethodChannel _channel;

  @override
  Future<void> setUnread(int count, String description) =>
      _channel.invokeMethod<void>('setUnread', {
        'count': count,
        'description': description,
      });

  @override
  Future<void> flash() => _channel.invokeMethod<void>('flash');
}

final class NoBadge implements BadgeHost {
  const NoBadge();
  @override
  Future<void> setUnread(int count, String description) async {}
  @override
  Future<void> flash() async {}
}

/// `main.dart`. [run] logs a failed call by type (never the count's text).
void listenForAttentionBadge({
  required ProviderContainer container,
  required BadgeHost host,
  required AppLocalizations l10n,
  required void Function(Future<void> call) run,
}) {
  void apply(int count) =>
      run(host.setUnread(count, l10n.attentionUnreadCount(count)));
  container.listen<int>(
    tabAttentionProvider.select((s) => s.totalUnread),
    (_, count) => apply(count),
    fireImmediately: true,
  );
  // The Dock icon comes back with the window (A1 D10): set it again.
  container.listen<bool>(windowRouterProvider.select((s) => s.visible), (
    _,
    shown,
  ) {
    if (shown) apply(container.read(tabAttentionProvider).totalUnread);
  });
  container.read(tabAttentionProvider.notifier).arrivals.listen((_) {
    if (!container.read(windowActiveProvider)) run(host.flash());
  });
}
```

Windows runner. In `flutter_window.h` add `#include <flutter/method_channel.h>` and `#include <shobjidl.h>`, and private members:

```cpp
  // A4 D19: taskbar overlay dot + flash (pro.shellx.desktop/taskbar).
  void HandleTaskbar(
      const flutter::MethodCall<flutter::EncodableValue>& call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  HICON UnreadIcon();
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      taskbar_channel_;
  ITaskbarList3* taskbar_ = nullptr;
  HICON unread_icon_ = nullptr;
```

In `flutter_window.cpp` add includes `#include <flutter/standard_method_codec.h>` and `#include <string>`; at the end of `OnCreate()` before `return true;`:

```cpp
  taskbar_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(),
          "pro.shellx.desktop/taskbar",
          &flutter::StandardMethodCodec::GetInstance());
  taskbar_channel_->SetMethodCallHandler(
      [this](const auto& call, auto result) {
        HandleTaskbar(call, std::move(result));
      });
```

In `OnDestroy()` before `Win32Window::OnDestroy();`:

```cpp
  taskbar_channel_ = nullptr;
  if (taskbar_) {
    taskbar_->Release();
    taskbar_ = nullptr;
  }
  if (unread_icon_) {
    DestroyIcon(unread_icon_);
    unread_icon_ = nullptr;
  }
```

New functions:

```cpp
// 16 px accent (#5FD4E2) dot, drawn once (no .ico asset).
HICON FlutterWindow::UnreadIcon() {
  if (unread_icon_) return unread_icon_;
  const int size = 16;
  BITMAPV5HEADER bi = {};
  bi.bV5Size = sizeof(bi);
  bi.bV5Width = size;
  bi.bV5Height = -size;
  bi.bV5Planes = 1;
  bi.bV5BitCount = 32;
  bi.bV5Compression = BI_BITFIELDS;
  bi.bV5RedMask = 0x00FF0000;
  bi.bV5GreenMask = 0x0000FF00;
  bi.bV5BlueMask = 0x000000FF;
  bi.bV5AlphaMask = 0xFF000000;
  HDC dc = GetDC(nullptr);
  void* bits = nullptr;
  HBITMAP color = CreateDIBSection(dc, reinterpret_cast<BITMAPINFO*>(&bi),
                                   DIB_RGB_COLORS, &bits, nullptr, 0);
  ReleaseDC(nullptr, dc);
  if (!color || !bits) return nullptr;
  auto* px = static_cast<uint32_t*>(bits);
  const double c = (size - 1) / 2.0, r = size / 2.0 - 1;
  for (int y = 0; y < size; ++y) {
    for (int x = 0; x < size; ++x) {
      const double dx = x - c, dy = y - c;
      const bool in = dx * dx + dy * dy <= r * r;
      // Premultiplied ARGB: opaque accent inside, transparent outside.
      px[y * size + x] = in ? 0xFF5FD4E2 : 0x00000000;
    }
  }
  HBITMAP mask = CreateBitmap(size, size, 1, 1, nullptr);
  ICONINFO info = {};
  info.fIcon = TRUE;
  info.hbmColor = color;
  info.hbmMask = mask;
  unread_icon_ = CreateIconIndirect(&info);
  DeleteObject(color);
  DeleteObject(mask);
  return unread_icon_;
}

void FlutterWindow::HandleTaskbar(
    const flutter::MethodCall<flutter::EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  HWND hwnd = GetHandle();
  if (call.method_name() == "flash") {
    if (GetForegroundWindow() != hwnd) {
      FLASHWINFO info = {sizeof(info), hwnd, FLASHW_TRAY | FLASHW_TIMERNOFG,
                         0, 0};
      FlashWindowEx(&info);
    }
    result->Success();
    return;
  }
  if (call.method_name() != "setUnread") {
    result->NotImplemented();
    return;
  }
  const auto* args = std::get_if<flutter::EncodableMap>(call.arguments());
  int count = 0;
  std::string description;
  if (args) {
    auto c = args->find(flutter::EncodableValue("count"));
    if (c != args->end()) count = std::get<int>(c->second);
    auto d = args->find(flutter::EncodableValue("description"));
    if (d != args->end()) description = std::get<std::string>(d->second);
  }
  if (!taskbar_ &&
      FAILED(CoCreateInstance(CLSID_TaskbarList, nullptr, CLSCTX_INPROC_SERVER,
                              IID_PPV_ARGS(&taskbar_)))) {
    taskbar_ = nullptr;
    result->Error("taskbar", "ITaskbarList3 unavailable");
    return;
  }
  // UTF-8 (Dart) → UTF-16 (Win32): the description is Vietnamese.
  std::wstring wide;
  int n = MultiByteToWideChar(CP_UTF8, 0, description.c_str(), -1, nullptr, 0);
  if (n > 1) {
    wide.resize(n - 1);
    MultiByteToWideChar(CP_UTF8, 0, description.c_str(), -1, wide.data(), n);
  }
  HRESULT hr = taskbar_->SetOverlayIcon(hwnd, count > 0 ? UnreadIcon() : nullptr,
                                        count > 0 ? wide.c_str() : L"");
  if (FAILED(hr)) {
    result->Error("taskbar", "SetOverlayIcon failed");
    return;
  }
  result->Success();
}
```

(COM is already initialised by the Flutter runner's `main.cpp` via `CoInitializeEx`; if `main.cpp` does not, add `::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);` at the top of `wWinMain` — check before editing.) In `windows/runner/CMakeLists.txt` add `target_link_libraries(${BINARY_NAME} PRIVATE "ole32.lib")` next to the `dwmapi.lib` line.

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/platform/attention_badge_test.dart`
Expected: PASS. The C++ is verified by the Windows CI build / manual checklist (HANDOFF §13) — it cannot build on macOS.

- [ ] **Step 5: Format, analyze, commit**

```bash
cd apps/desktop && ~/fvm/versions/3.41.4/bin/dart format --set-exit-if-changed lib/src/platform/attention_badge.dart test/platform/attention_badge_test.dart && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter analyze
cd ../.. && git add apps/desktop/lib/src/platform/attention_badge.dart apps/desktop/test/platform/attention_badge_test.dart apps/desktop/windows/runner/flutter_window.h apps/desktop/windows/runner/flutter_window.cpp apps/desktop/windows/runner/CMakeLists.txt
git commit -m "feat(desktop): Dock badge and Windows taskbar overlay + flash for unread notifications (A4 D18, D19)"
```

---

### Task 7: Desktop — sidebar badge, notification line, header dot, row menu

**Files:**
- Create: `apps/desktop/lib/src/ui/terminal/attention_marks.dart` (`UnreadBadge`, `NotificationLine`; `AttentionRing` is added in Task 8)
- Modify: `apps/desktop/lib/src/ui/terminal/session_tab_row.dart`
- Modify: `apps/desktop/lib/src/ui/terminal/session_sidebar.dart`
- Modify: `apps/desktop/lib/src/ui/terminal/workspace_header.dart`
- Create: `apps/desktop/test/ui/sidebar_attention_test.dart`

**Interfaces:**
- Consumes: `tabAttentionProvider` (`unread`, `hasUnread`, `markRead`, `markAllRead`, `totalUnread`), `TabUnread`, `unreadBadgeLabel` (Task 4); `ShellxSizes.badge*`, `notification*`, `rowWithNotification*`, `aggregateDot` (Task 3); UI-A4 §2, §3, §8, §10.4.
- Produces:
  - `class UnreadBadge extends StatelessWidget { const UnreadBadge({super.key, required int count}); }`
  - `class NotificationLine extends StatelessWidget { const NotificationLine({super.key, required String text}); }`
  - `SessionTabRow({…, TabUnread? unread, VoidCallback? onMarkRead})`; `SessionTabRow.heightFor(TextScaler, {bool context = false, bool notification = false})`
  - `WorkspaceHeader({…, bool hasUnread = false})`
  - Keys: `Key('row.badge')`, `Key('row.notification')`, `Key('header.unreadDot')`, `Key('menu.markRead')`, `Key('menu.markAllRead')`

- [ ] **Step 1: Write the failing tests**

Create `apps/desktop/test/ui/sidebar_attention_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_desktop/src/terminal/tab_attention.dart';

import '../support/fake_local_sessions.dart';
import 'sidebar_test_harness.dart';

void main() {
  setUp(() {
    local = FakeLocalSessions();
    local.add(local.summary(1, title: 'zsh'));
    local.add(local.summary(2, title: 'api', cwd: '/Users/test/api'));
  });

  testSidebar('an unread tab shows a badge and its last text; reading '
      'removes both (UI-A4 §2)', (tester) async {
    await pumpSidebar(tester);
    expect(find.byKey(const Key('row.badge')), findsNothing);
    local.notice(2, SessionNoticeKind.message, body: 'Build xong');
    local.notice(2, SessionNoticeKind.message, body: 'Lần hai');
    await tester.pump();
    expect(
      find.descendant(of: row(2), matching: find.byKey(const Key('row.badge'))),
      findsOneWidget,
    );
    expect(find.descendant(of: row(2), matching: find.text('2')), findsOneWidget);
    expect(find.text('Lần hai'), findsOneWidget);
    // title + notification + context line: 62 (UI-A4 §1.3).
    expect(tester.getSize(row(2)).height, 62);
    container.read(tabAttentionProvider.notifier).markRead(2);
    await tester.pump();
    expect(find.byKey(const Key('row.badge')), findsNothing);
    expect(find.text('Lần hai'), findsNothing);
    expect(tester.getSize(row(2)).height, 46);
  });

  testSidebar('a row without context grows to 46 with a notification',
      (tester) async {
    await pumpSidebar(tester);
    // The harness never focuses the window, so the selected tab 1 still
    // gets unread (D7 needs an active window).
    local.notice(1, SessionNoticeKind.bell);
    await tester.pump();
    expect(tester.getSize(row(1)).height, 46);
    expect(find.text('Bell'), findsOneWidget);
  });

  testSidebar('99+ over 99', (tester) async {
    await pumpSidebar(tester);
    for (var i = 0; i < 4; i++) {
      // 4 × 30 (agent limit is not in the fake): 120 unread.
      for (var j = 0; j < 30; j++) {
        local.notice(2, SessionNoticeKind.message, body: '$i$j');
      }
    }
    await tester.pump();
    expect(find.text('99+'), findsOneWidget);
  });

  testSidebar('the row label says the unread count and latest text '
      '(UI-A4 §8)', (tester) async {
    await pumpSidebar(tester);
    local.notice(2, SessionNoticeKind.message, title: 'CI', body: 'đỏ');
    await tester.pump();
    expect(
      tester.getSemantics(row(2)).label,
      contains('1 unread notification, latest: CI: đỏ'),
    );
  });

  testSidebar('row menu: Mark as read / Mark all as read (D23)',
      (tester) async {
    await pumpSidebar(tester);
    local.notice(2, SessionNoticeKind.message, body: 'a');
    local.notice(1, SessionNoticeKind.message, body: 'b');
    await tester.pump();
    await tester.tap(row(2), buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('menu.markRead')));
    await tester.pumpAndSettle();
    final attention = container.read(tabAttentionProvider);
    expect(attention.hasUnread(2), isFalse);
    expect(attention.hasUnread(1), isTrue);
    await tester.tap(row(2), buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('menu.markAllRead')));
    await tester.pumpAndSettle();
    expect(container.read(tabAttentionProvider).unread, isEmpty);
  });

  testSidebar('a collapsed workspace with unread shows the dot (D22)',
      (tester) async {
    await pumpSidebar(tester);
    await workspaces().create(moveTab: 2);
    await tester.pump();
    final ws = sidebar().workspaceOf(2)!;
    workspaces().setCollapsed(ws, true);
    local.notice(2, SessionNoticeKind.message, body: 'x');
    await tester.pump();
    expect(find.byKey(const Key('header.unreadDot')), findsOneWidget);
    workspaces().setCollapsed(ws, false);
    await tester.pump();
    expect(find.byKey(const Key('header.unreadDot')), findsNothing);
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/ui/sidebar_attention_test.dart`
Expected: FAIL — no badge/line widgets.

- [ ] **Step 3: Implement**

Create `apps/desktop/lib/src/ui/terminal/attention_marks.dart`:

```dart
import 'dart:math';
import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';

import '../../terminal/tab_attention.dart';
import '../theme/shellx_desktop_theme.dart';

/// UI-A4 §2.1: accent pill with the unread count (`99+`).
class UnreadBadge extends StatelessWidget {
  const UnreadBadge({super.key, required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    final height = max(ShellxSizes.badgeHeight, scaler.scale(14) + 2);
    return ExcludeSemantics(
      child: Container(
        key: const Key('row.badge'),
        height: height,
        constraints: BoxConstraints(minWidth: max(ShellxSizes.badgeMinWidth, height)),
        padding: const EdgeInsets.symmetric(horizontal: ShellxSizes.badgePadH),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: ShellxDesktopColors.accent,
          borderRadius: BorderRadius.circular(ShellxRadius.pill),
        ),
        child: Text(
          unreadBadgeLabel(count),
          maxLines: 1,
          style: ShellxText.caption.copyWith(
            fontWeight: FontWeight.w600,
            color: ShellxDesktopColors.onPrimary,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ),
    );
  }
}

/// UI-A4 §2.1: icon + the last unread text, one line.
class NotificationLine extends StatelessWidget {
  const NotificationLine({super.key, required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Row(
      key: const Key('row.notification'),
      children: [
        const Icon(
          Icons.notifications_none,
          size: ShellxSizes.notificationIcon,
          color: ShellxDesktopColors.accent,
        ),
        const SizedBox(width: ShellxSizes.notificationIconGap),
        Expanded(
          child: Tooltip(
            message: text,
            excludeFromSemantics: true,
            waitDuration: ShellxMotion.tooltipWait,
            constraints: const BoxConstraints(
              maxWidth: ShellxSizes.titleTooltipMaxWidth,
            ),
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: ShellxText.caption.copyWith(
                color: ShellxDesktopColors.textSecondary,
              ),
            ),
          ),
        ),
      ],
    ),
  );
}
```

(Use the radius constant the theme defines for `rPill` — check `ShellxRadius`; if it is named `rPill`, use that.)

`session_tab_row.dart`:

1. Constructor: add `this.unread,` and `this.onMarkRead,`; fields:

```dart
  /// A4: unread notifications of this tab (badge + line), null when none.
  final TabUnread? unread;

  /// "Đánh dấu đã đọc" custom semantics action (UI-A4 §8).
  final VoidCallback? onMarkRead;
```

2. `heightFor`:

```dart
  /// UI-A1/A2 §1.3 + UI-A4 §1.3: title line, then an optional notification
  /// line and an optional context line, each 14·s plus a 2 px gap.
  static double heightFor(
    TextScaler textScaler, {
    bool context = false,
    bool notification = false,
  }) {
    final lines = (context ? 1 : 0) + (notification ? 1 : 0);
    if (lines == 0) {
      return max(
        ShellxSizes.row,
        textScaler.scale(ShellxSizes.rowTextLine) + ShellxSizes.rowTextPadding,
      );
    }
    final minimum = lines == 2
        ? ShellxSizes.rowWithNotificationAndContext
        : ShellxSizes.rowWithContext;
    return max(
      minimum,
      textScaler.scale(ShellxSizes.rowTextLine) +
          lines * (textScaler.scale(ShellxSizes.contextLine) + ShellxSizes.contextGap) +
          2 * ShellxSizes.rowContextPadding,
    );
  }
```

3. In `build`: `final withNotification = widget.unread != null;` (the line also shows while renaming; the badge does not — UI-A4 §2.2, handled in step 4), height `SessionTabRow.heightFor(scaler, context: withContext, notification: withNotification)`.

4. In `titleRow`, replace the title `Expanded(child: renaming ? InlineNameField(…) : _Title(tab.label, titleStyle))` with:

```dart
        Expanded(
          child: renaming
              ? InlineNameField(
                  initial: tab.label,
                  style: ShellxText.body,
                  label: l10n.tabNameField,
                  identity: ('tab', tab.id),
                  onCommit: (text) => widget.onRename?.call(text),
                  onCancel: () => widget.onCancelRename?.call(),
                )
              // UI-A4 §2.1: the badge follows the title; the title gives
              // way first.
              : Row(
                  children: [
                    Flexible(child: _Title(tab.label, titleStyle)),
                    if (widget.unread case final u?) ...[
                      const SizedBox(width: ShellxSizes.badgeGap),
                      UnreadBadge(count: u.count),
                    ],
                  ],
                ),
        ),
```

5. Layout of the lines. Replace `if (!withContext)` with `if (!withContext && !withNotification)`, and in the `else ...[` branch compute, before `contextTop` is used:

```dart
    final notificationLine = scaler.scale(ShellxSizes.notificationLine);
    final notificationTop =
        ShellxSizes.rowContextPadding + titleLine + ShellxSizes.notificationGap;
    final shift = withNotification
        ? notificationLine + ShellxSizes.notificationGap
        : 0.0;
```

change `contextTop` to add `+ shift` (so `overlap` becomes 0 when the line pushes ports down), and in the `else` branch add, between the title `Positioned` and the context `Positioned`:

```dart
                      if (widget.unread case final u?)
                        Positioned(
                          left: ShellxSizes.contextInset,
                          right: ShellxSpace.s8,
                          top: notificationTop,
                          height: notificationLine,
                          child: NotificationLine(text: u.text),
                        ),
```

and wrap the existing context `Positioned` in `if (withContext)`.

6. `_semanticsLabel`: after the status entry add

```dart
      if (widget.unread case final u?) l10n.attentionRowSemantics(u.count, u.text),
```

7. `customSemanticsActions`: add `if (widget.unread != null && widget.onMarkRead != null) CustomSemanticsAction(label: l10n.attentionMarkRead): widget.onMarkRead!,`.

`session_sidebar.dart`:

1. `final attention = ref.watch(tabAttentionProvider);` in `build`.
2. `_RowItem`: add `final bool notified;` (constructor param) and set it where `_RowItem(` is built: `notified: attention.hasUnread(tab.id)`. `_extent`: `_RowItem(:final tab, :final notified) => SessionTabRow.heightFor(scaler, context: tab.hasContext, notification: notified),`.
3. `SessionTabRow(` construction: add `unread: attention.unread[tab.id], onMarkRead: () => ref.read(tabAttentionProvider.notifier).markRead(tab.id),`.
4. `_RowAction` enum: add `markRead, markAllRead`. In `_rowMenu`, insert at the top of `entries`:

```dart
        ShellxMenuEntry(
          key: const Key('menu.markRead'),
          value: _RowAction.markRead,
          label: l10n.attentionMarkRead,
          enabled: ref.read(tabAttentionProvider).hasUnread(tab.id),
        ),
        ShellxMenuEntry(
          key: const Key('menu.markAllRead'),
          value: _RowAction.markAllRead,
          label: l10n.attentionMarkAllRead,
          enabled: ref.read(tabAttentionProvider).totalUnread > 0,
        ),
```

give the existing `menu.renameTab` entry `dividerBefore: true`, and in the `switch (choice)`:

```dart
      case _RowAction.markRead:
        ref.read(tabAttentionProvider.notifier).markRead(tab.id);
      case _RowAction.markAllRead:
        ref.read(tabAttentionProvider.notifier).markAllRead();
```

5. `WorkspaceHeader(` construction: `hasUnread: w.collapsed && sidebar.tabsOf(w.id).any(attention.hasUnread),`.

`workspace_header.dart`: add `this.hasUnread = false,` / `final bool hasUnread;`; in the semantics `label` list add `if (widget.hasUnread) l10n.workspaceHasUnread,`; in the header `Row`, immediately before the tab-count box (the widget with `minWidth: ShellxSizes.headerCountMin`):

```dart
        if (widget.hasUnread) ...[
          Container(
            key: const Key('header.unreadDot'),
            width: ShellxSizes.aggregateDot,
            height: ShellxSizes.aggregateDot,
            decoration: const BoxDecoration(
              color: ShellxDesktopColors.accent,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: ShellxSpace.s4),
        ],
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/ui`
Expected: PASS (new tests and every A1/A2 sidebar test: without unread the rows are unchanged).

- [ ] **Step 5: Format, analyze, commit**

```bash
cd apps/desktop && ~/fvm/versions/3.41.4/bin/dart format --set-exit-if-changed lib/src/ui/terminal test/ui && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter analyze
cd ../.. && git add apps/desktop/lib/src/ui/terminal/attention_marks.dart apps/desktop/lib/src/ui/terminal/session_tab_row.dart apps/desktop/lib/src/ui/terminal/session_sidebar.dart apps/desktop/lib/src/ui/terminal/workspace_header.dart apps/desktop/test/ui/sidebar_attention_test.dart
git commit -m "feat(desktop): unread badge, notification line, workspace dot and mark-as-read in the sidebar (A4 N3, N4)"
```

---

### Task 8: Desktop — terminal ring, notifications panel, ⌘⇧I / ⌘⇧U, bell button

**Files:**
- Modify: `apps/desktop/lib/src/ui/terminal/attention_marks.dart` (add `AttentionRing`)
- Create: `apps/desktop/lib/src/ui/terminal/notifications_panel.dart`
- Modify: `apps/desktop/lib/src/ui/terminal/terminal_pane.dart` (ring layer, pane label)
- Modify: `apps/desktop/lib/src/ui/terminal/terminal_shortcuts.dart` (2 intents)
- Modify: `apps/desktop/lib/src/ui/terminal/shortcut_labels.dart` (2 labels)
- Modify: `apps/desktop/lib/src/ui/terminal/terminal_workspace_page.dart` (actions, focus requests, panel overlay)
- Modify: `apps/desktop/lib/src/ui/terminal/session_sidebar.dart` (bell button)
- Create: `apps/desktop/test/ui/attention_ring_test.dart`, `apps/desktop/test/ui/notifications_panel_test.dart`
- Modify: `apps/desktop/test/ui/terminal_shortcuts_test.dart`

**Interfaces:**
- Consumes: `tabAttentionProvider` (`history`, `unread`, `nextUnread`, `jumpTo`, `markAllRead`), `AttentionEntry`, `AttentionKind` (Task 4); `terminalFocusRequestProvider` (Task 3); `sidebarWorkspacesProvider`; `TerminalTabs.showNotice` with a neutral notice; UI-A4 §4, §5, §8.
- Produces:
  - `class AttentionRing extends StatelessWidget { const AttentionRing({super.key, required bool visible}); }` (`Key('pane.ring')`)
  - `class NotificationsPanel extends ConsumerStatefulWidget { const NotificationsPanel({super.key, required VoidCallback onClose}); }`
  - `String relativeTime(DateTime at, DateTime now, AppLocalizations l10n)`
  - `ToggleNotificationsPanelIntent`, `JumpToNextUnreadIntent` (⌘⇧I/⌘⇧U, Ctrl+Shift+I/U, `includeRepeats: false`)
  - `notificationsShortcutLabel()`, `nextUnreadShortcutLabel()`
  - `final class NoUnreadNotice extends TabNotice { const NoUnreadNotice(); }` (neutral toast, in `terminal_tabs.dart`)
  - `TerminalWorkspacePageState.panelOpen` (bool), keys `Key('sidebar.bell')`, `Key('panel')`, `Key('panel.item.<seq>')`, `Key('panel.markAll')`

- [ ] **Step 1: Write the failing tests**

Create `apps/desktop/test/ui/attention_ring_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_desktop/src/terminal/tab_attention.dart';

import '../support/fake_local_sessions.dart';
import 'sidebar_test_harness.dart';

void main() {
  setUp(() {
    local = FakeLocalSessions();
    local.add(local.summary(1, title: 'claude'));
  });

  Finder ring() => find.byKey(const Key('pane.ring'));
  double opacity(WidgetTester t) =>
      t.widget<AnimatedOpacity>(find.ancestor(of: ring(), matching: find.byType(AnimatedOpacity)).first).opacity;

  testSidebar('the selected tab with unread gets the ring; reading removes '
      'it; the terminal is never resized (D21)', (tester) async {
    await pumpSidebar(tester);
    final resizes = List.of(local.views[1]!.resizes);
    local.notice(1, SessionNoticeKind.message, body: 'need you');
    await tester.pumpAndSettle();
    expect(opacity(tester), 1);
    expect(local.views[1]!.resizes, resizes);
    container.read(tabAttentionProvider.notifier).markRead(1);
    await tester.pumpAndSettle();
    expect(opacity(tester), 0);
    expect(local.views[1]!.resizes, resizes);
  });

  testSidebar('reduced motion: the ring appears at once', (tester) async {
    await pumpSidebar(tester);
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await tester.pump();
    local.notice(1, SessionNoticeKind.message, body: 'x');
    await tester.pump();
    final animated = tester.widget<AnimatedOpacity>(
      find.ancestor(of: ring(), matching: find.byType(AnimatedOpacity)).first,
    );
    expect(animated.duration, Duration.zero);
    expect(animated.opacity, 1);
  });
}
```

(If the harness wraps the app in its own `MediaQuery`, set `disableAnimations: true` there instead — add a `disableAnimations` parameter to `pumpSidebar` that copies into `MediaQueryData`.)

Create `apps/desktop/test/ui/notifications_panel_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_desktop/l10n/app_localizations_en.dart';
import 'package:shellx_desktop/src/terminal/tab_attention.dart';
import 'package:shellx_desktop/src/terminal/terminal_tabs.dart';
import 'package:shellx_desktop/src/ui/terminal/notifications_panel.dart';

import '../support/fake_local_sessions.dart';
import 'sidebar_test_harness.dart';

void main() {
  setUp(() {
    local = FakeLocalSessions();
    local.add(local.summary(1, title: 'zsh'));
    local.add(local.summary(2, title: 'api'));
    local.add(local.summary(3, title: 'web'));
  });

  Future<void> openPanel(WidgetTester tester) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyI);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pumpAndSettle();
  }

  testSidebar('⌘⇧I opens the panel with the newest first; Esc closes it',
      (tester) async {
    await pumpSidebar(tester);
    local.notice(2, SessionNoticeKind.message, body: 'first');
    local.notice(3, SessionNoticeKind.message, body: 'second');
    await tester.pump();
    await openPanel(tester);
    expect(find.byKey(const Key('panel')), findsOneWidget);
    final texts = tester
        .widgetList<Text>(find.descendant(of: find.byKey(const Key('panel')), matching: find.byType(Text)))
        .map((t) => t.data)
        .toList();
    expect(texts.indexOf('second'), lessThan(texts.indexOf('first')));
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('panel')), findsNothing);
  });

  testSidebar('↓ + Enter jumps to the tab, reads it and closes (N5)',
      (tester) async {
    await pumpSidebar(tester);
    local.notice(2, SessionNoticeKind.message, body: 'a');
    local.notice(3, SessionNoticeKind.message, body: 'b');
    await tester.pump();
    await openPanel(tester); // cursor on the first unread: "b" (tab 3)
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown); // "a" (tab 2)
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(tabs().selectedId, 2);
    expect(container.read(tabAttentionProvider).hasUnread(2), isFalse);
    expect(find.byKey(const Key('panel')), findsNothing);
  });

  testSidebar('a closed tab entry says so and does not jump', (tester) async {
    await pumpSidebar(tester);
    local.notice(2, SessionNoticeKind.message, body: 'gone');
    await tester.pump();
    container.read(terminalTabsProvider.notifier).close(2);
    await tester.pump();
    await openPanel(tester);
    expect(find.textContaining('Tab closed'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('panel')), findsOneWidget);
  });

  testSidebar('empty state and disabled "Mark all as read"', (tester) async {
    await pumpSidebar(tester);
    await openPanel(tester);
    expect(find.text('No notifications yet'), findsOneWidget);
    expect(
      tester.widget<Opacity>(find.ancestor(of: find.byKey(const Key('panel.markAll')), matching: find.byType(Opacity)).first).opacity,
      0.38,
    );
  });

  testSidebar('⌘⇧U jumps to the next unread; none left shows a toast (D13)',
      (tester) async {
    await pumpSidebar(tester);
    local.notice(3, SessionNoticeKind.bell);
    await tester.pump();
    Future<void> next() async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyU);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pumpAndSettle();
    }

    await next();
    expect(tabs().selectedId, 3);
    await next();
    expect(tabs().notice, isA<NoUnreadNotice>());
  });

  test('relative time (UI-A4 §5.2)', () {
    final l10n = AppLocalizationsEn();
    final now = DateTime(2026, 10, 7, 12);
    expect(relativeTime(now.subtract(const Duration(seconds: 30)), now, l10n), 'now');
    expect(relativeTime(now.add(const Duration(seconds: 30)), now, l10n), 'now');
    expect(relativeTime(now.subtract(const Duration(minutes: 5)), now, l10n), '5 min');
    expect(relativeTime(now.subtract(const Duration(hours: 3)), now, l10n), '3 h');
    expect(relativeTime(DateTime(2026, 10, 5, 9, 4), now, l10n), '09:04');
  });
}
```

In `terminal_shortcuts_test.dart`, add expectations that `desktopShortcuts(TargetPlatform.macOS)` maps `SingleActivator(keyI, meta: true, shift: true, includeRepeats: false)` to `ToggleNotificationsPanelIntent` and `keyU` to `JumpToNextUnreadIntent`, and Windows maps `Ctrl+Shift+I/U`.

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/ui/attention_ring_test.dart test/ui/notifications_panel_test.dart test/ui/terminal_shortcuts_test.dart`
Expected: FAIL — missing ring, panel, intents.

- [ ] **Step 3: Implement**

Append to `attention_marks.dart`:

```dart
/// UI-A4 §4: 2 px accent + 1 px accent 40 % inside, over the terminal
/// area; fades in `base`, out `exit`; never loops; static (instant) with
/// reduced motion. Paint only: the terminal's size never changes (A1 D6).
class AttentionRing extends StatelessWidget {
  const AttentionRing({super.key, required this.visible});
  final bool visible;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: AnimatedOpacity(
      opacity: visible ? 1 : 0,
      duration: ShellxMotion.of(
        context,
        visible ? ShellxMotion.base : ShellxMotion.exit,
      ),
      curve: visible ? ShellxMotion.baseCurve : ShellxMotion.exitCurve,
      child: DecoratedBox(
        key: const Key('pane.ring'),
        decoration: BoxDecoration(
          border: Border.all(
            color: ShellxDesktopColors.accent,
            width: ShellxSizes.ringWidth,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(ShellxSizes.ringWidth),
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border.all(
                color: ShellxDesktopColors.accent.withValues(alpha: 0.4),
                width: ShellxSizes.ringGlowWidth,
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
```

`terminal_pane.dart`: `final attention = ref.watch(tabAttentionProvider);`, `final ringed = selected != null && attention.hasUnread(selected.id);`. In the `Stack`, directly after the `IndexedStack`'s `Positioned.fill` (before the driver pill), add:

```dart
                    if (selected != null)
                      Positioned.fill(child: AttentionRing(visible: ringed)),
```

and give the selected tab's `_TabTerminal` label `ringed ? l10n.terminalPaneUnreadLabel(tab.label) : l10n.terminalPaneLabel(tab.label)`.

`terminal_tabs.dart`: add

```dart
/// ⌘⇧U found nothing (A4 D13). Neutral toast.
final class NoUnreadNotice extends TabNotice {
  const NoUnreadNotice();
}
```

and in `terminal_overlays.dart`'s toast text switch add `NoUnreadNotice() => l10n.noUnreadNotifications,` in the neutral group (like `WorkspaceDeletedNotice`).

`terminal_shortcuts.dart`:

```dart
/// ⌘⇧I / Ctrl+Shift+I (A4 N5).
class ToggleNotificationsPanelIntent extends Intent {
  const ToggleNotificationsPanelIntent();
}

/// ⌘⇧U / Ctrl+Shift+U (A4 N5, D13).
class JumpToNextUnreadIntent extends Intent {
  const JumpToNextUnreadIntent();
}
```

In `_windowShortcuts`, next to `NewWorkspaceIntent`, using the same mac/Windows shape:

```dart
    (mac
            ? const SingleActivator(LogicalKeyboardKey.keyI, meta: true, shift: true, includeRepeats: false)
            : const SingleActivator(LogicalKeyboardKey.keyI, control: true, shift: true, includeRepeats: false)):
        const ToggleNotificationsPanelIntent(),
    (mac
            ? const SingleActivator(LogicalKeyboardKey.keyU, meta: true, shift: true, includeRepeats: false)
            : const SingleActivator(LogicalKeyboardKey.keyU, control: true, shift: true, includeRepeats: false)):
        const JumpToNextUnreadIntent(),
```

`shortcut_labels.dart` (same pattern as the existing labels):

```dart
String notificationsShortcutLabel() => isMacDesktop ? '⌘⇧I' : 'Ctrl+Shift+I';
String nextUnreadShortcutLabel() => isMacDesktop ? '⌘⇧U' : 'Ctrl+Shift+U';
```

Create `apps/desktop/lib/src/ui/terminal/notifications_panel.dart`:

```dart
import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../../terminal/sidebar_workspaces.dart';
import '../../terminal/tab_attention.dart';
import '../../terminal/terminal_tabs.dart';
import '../theme/shellx_desktop_theme.dart';
import 'shortcut_labels.dart';

/// UI-A4 §5.2.
String relativeTime(DateTime at, DateTime now, AppLocalizations l10n) {
  final d = now.difference(at);
  if (d.inSeconds < 60) return l10n.notificationsTimeNow;
  if (d.inMinutes < 60) return l10n.notificationsTimeMinutes(d.inMinutes);
  if (d.inHours < 24) return l10n.notificationsTimeHours(d.inHours);
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(at.hour)}:${two(at.minute)}';
}

/// UI-A4 §5: the last 50 notifications, keyboard first (A4 N5).
class NotificationsPanel extends ConsumerStatefulWidget {
  const NotificationsPanel({super.key, required this.onClose});
  final VoidCallback onClose;

  @override
  ConsumerState<NotificationsPanel> createState() => _NotificationsPanelState();
}

class _NotificationsPanelState extends ConsumerState<NotificationsPanel> {
  final _list = FocusNode(debugLabel: 'notifications panel');
  final _scroll = ScrollController();
  int _cursor = 0;
  bool _keyboard = true;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    final history = ref.read(tabAttentionProvider).history;
    final firstUnread = history.indexWhere((e) => !e.read);
    _cursor = max(0, firstUnread);
    _tick = Timer.periodic(const Duration(seconds: 30), (_) => setState(() {}));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _list.requestFocus();
      SemanticsService.sendAnnouncement(
        View.of(context),
        AppLocalizations.of(context).notificationsPanelOpened(history.length),
        Directionality.of(context),
      );
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    _list.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _open(AttentionEntry e) {
    if (e.closed) {
      SemanticsService.sendAnnouncement(
        View.of(context),
        AppLocalizations.of(context).notificationsTabClosed,
        Directionality.of(context),
      );
      return;
    }
    widget.onClose();
    ref.read(tabAttentionProvider.notifier).jumpTo(e.tabId);
  }

  KeyEventResult _key(FocusNode _, KeyEvent event, List<AttentionEntry> items) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    void move(int to) => setState(() {
      _keyboard = true;
      _cursor = to.clamp(0, max(0, items.length - 1));
      final top = _cursor * ShellxSizes.panelItem;
      if (_scroll.hasClients) {
        final v = _scroll.position;
        if (top < v.pixels) _scroll.jumpTo(top);
        if (top + ShellxSizes.panelItem > v.pixels + v.viewportDimension) {
          _scroll.jumpTo(top + ShellxSizes.panelItem - v.viewportDimension);
        }
      }
    });
    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowDown:
        move(_cursor + 1);
      case LogicalKeyboardKey.arrowUp:
        move(_cursor - 1);
      case LogicalKeyboardKey.home:
        move(0);
      case LogicalKeyboardKey.end:
        move(items.length - 1);
      case LogicalKeyboardKey.enter ||
          LogicalKeyboardKey.numpadEnter ||
          LogicalKeyboardKey.space:
        if (items.isNotEmpty) _open(items[_cursor]);
      case LogicalKeyboardKey.escape:
        widget.onClose();
      default:
        return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final attention = ref.watch(tabAttentionProvider);
    final tabs = ref.watch(terminalTabsProvider);
    final sidebar = ref.watch(sidebarWorkspacesProvider);
    final items = attention.history;
    final now = DateTime.now();
    final height = MediaQuery.sizeOf(context).height;
    final markAllEnabled = attention.totalUnread > 0;

    String label(AttentionEntry e) {
      TerminalTab? tab;
      for (final t in tabs.tabs) {
        if (t.id == e.tabId) tab = t;
      }
      final name = tab?.label ?? e.tabLabel;
      if (e.closed) return '${l10n.notificationsTabClosed} · $name';
      final ws = sidebar.showHeaders ? sidebar.workspaceOf(e.tabId) : null;
      final wsName = ws == null ? null : sidebar.workspace(ws)?.displayName(l10n);
      return wsName == null ? name : '$name · $wsName';
    }

    String text(AttentionEntry e) => e.kind == AttentionKind.bell && e.repeat > 1
        ? l10n.attentionBellRepeat(e.repeat)
        : e.text;

    final header = SizedBox(
      height: ShellxSizes.panelHeader,
      child: Row(
        children: [
          const SizedBox(width: ShellxSpace.s8),
          Expanded(
            child: Text(
              l10n.notificationsPanelTitle,
              style: ShellxText.small.copyWith(
                fontWeight: FontWeight.w600,
                color: ShellxDesktopColors.textPrimary,
              ),
            ),
          ),
          Opacity(
            opacity: markAllEnabled ? 1 : 0.38,
            child: TextButton(
              key: const Key('panel.markAll'),
              onPressed: markAllEnabled
                  ? () => ref.read(tabAttentionProvider.notifier).markAllRead()
                  : null,
              style: TextButton.styleFrom(
                minimumSize: const Size(0, ShellxSizes.textButton),
                padding: const EdgeInsets.symmetric(horizontal: ShellxSpace.s8),
                foregroundColor: ShellxDesktopColors.accent,
                textStyle: ShellxText.small.copyWith(fontWeight: FontWeight.w600),
              ),
              child: Text(l10n.attentionMarkAllRead),
            ),
          ),
        ],
      ),
    );

    Widget item(int i) {
      final e = items[i];
      final cursor = i == _cursor;
      final parts = [
        label(e),
        text(e),
        relativeTime(e.at, now, l10n),
        if (!e.read) l10n.notificationsItemUnread,
      ];
      return Semantics(
        button: !e.closed,
        selected: cursor,
        label: parts.join(', '),
        excludeSemantics: true,
        child: MouseRegion(
          cursor: e.closed ? MouseCursor.defer : SystemMouseCursors.click,
          child: GestureDetector(
            onTap: () => _open(e),
            child: Container(
              key: Key('panel.item.${e.seq}'),
              height: ShellxSizes.panelItem,
              padding: const EdgeInsets.symmetric(
                vertical: ShellxSpace.s8,
                horizontal: ShellxSpace.s8,
              ),
              decoration: BoxDecoration(
                color: cursor ? ShellxDesktopColors.rowSelected : null,
                borderRadius: BorderRadius.circular(ShellxRadius.r6),
                border: cursor && _keyboard && _list.hasFocus
                    ? Border.all(
                        color: ShellxDesktopColors.accent,
                        width: ShellxSizes.focusRing,
                      )
                    : null,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: ShellxSizes.panelUnreadSlot,
                    height: 16,
                    child: e.read
                        ? null
                        : Center(
                            child: Container(
                              width: ShellxSizes.bellDot,
                              height: ShellxSizes.bellDot,
                              decoration: const BoxDecoration(
                                color: ShellxDesktopColors.accent,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                label(e),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: ShellxText.small.copyWith(
                                  color: ShellxDesktopColors.textSecondary,
                                ),
                              ),
                            ),
                            const SizedBox(width: ShellxSpace.s8),
                            Text(
                              relativeTime(e.at, now, l10n),
                              style: ShellxText.caption.copyWith(
                                color: ShellxDesktopColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          text(e),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: ShellxText.body.copyWith(
                            color: e.read
                                ? ShellxDesktopColors.textSecondary
                                : ShellxDesktopColors.textPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    final body = items.isEmpty
        ? Padding(
            padding: const EdgeInsets.all(ShellxSpace.s24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.notifications_none,
                  size: ShellxSizes.panelEmptyIcon,
                  color: ShellxDesktopColors.textSecondary,
                ),
                const SizedBox(height: ShellxSpace.s8),
                Text(
                  l10n.notificationsPanelEmptyTitle,
                  style: ShellxText.body.copyWith(
                    color: ShellxDesktopColors.textPrimary,
                  ),
                ),
                const SizedBox(height: ShellxSpace.s4),
                Text(
                  l10n.notificationsPanelEmptyBody,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  style: ShellxText.caption.copyWith(
                    color: ShellxDesktopColors.textSecondary,
                  ),
                ),
              ],
            ),
          )
        : Flexible(
            child: ListView.builder(
              controller: _scroll,
              shrinkWrap: true,
              itemCount: items.length,
              itemExtent: ShellxSizes.panelItem,
              itemBuilder: (_, i) => item(i),
            ),
          );

    return Semantics(
      scopesRoute: true,
      namesRoute: true,
      explicitChildNodes: true,
      label: l10n.notificationsPanelTitle,
      child: Focus(
        focusNode: _list,
        onKeyEvent: (node, event) => _key(node, event, items),
        child: Container(
          key: const Key('panel'),
          width: ShellxSizes.panelWidth,
          constraints: BoxConstraints(
            maxHeight: min(ShellxSizes.panelMaxHeight, height - 64),
          ),
          padding: const EdgeInsets.all(ShellxSpace.s4),
          decoration: BoxDecoration(
            color: ShellxDesktopColors.surface,
            borderRadius: BorderRadius.circular(ShellxRadius.r8),
            border: Border.all(color: ShellxDesktopColors.border),
            boxShadow: ShellxElevation.e1,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              header,
              Container(height: 1, color: ShellxDesktopColors.line),
              body,
              if (items.isNotEmpty)
                SizedBox(
                  height: 24,
                  child: Padding(
                    padding: const EdgeInsets.only(left: ShellxSpace.s8),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        l10n.notificationsPanelNextHint(nextUnreadShortcutLabel()),
                        style: ShellxText.caption.copyWith(
                          color: ShellxDesktopColors.textSecondary,
                        ),
                      ),
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
```

(Use the theme's real names for the `e1` shadow and radii — `ShellxElevation.e1` / `ShellxRadius.r8` — as `terminal_overlays.dart` uses them for the toast; if `SemanticsService.sendAnnouncement` is not available in Flutter 3.41.4, use `SemanticsService.announce(text, Directionality.of(context))`, the call the sidebar already uses for move announcements.)

`terminal_workspace_page.dart`:

1. State: `bool panelOpen = false; FocusNode? _beforePanel;`.
2. `void _togglePanel() { setState(() { if (!panelOpen) _beforePanel = FocusManager.instance.primaryFocus; panelOpen = !panelOpen; }); if (!panelOpen) _beforePanel?.requestFocus(); }` and `void _closePanel() { if (panelOpen) _togglePanel(); }`.
3. `_actions()` gains:

```dart
      ToggleNotificationsPanelIntent: run<ToggleNotificationsPanelIntent>(
        (_) => _togglePanel(),
      ),
      JumpToNextUnreadIntent: run<JumpToNextUnreadIntent>((_) {
        _closePanel();
        final attention = ref.read(tabAttentionProvider.notifier);
        final next = attention.nextUnread();
        if (next == null || !attention.jumpTo(next)) {
          ref.read(terminalTabsProvider.notifier).showNotice(const NoUnreadNotice());
          SemanticsService.announce(
            AppLocalizations.of(context).noUnreadNotifications,
            Directionality.of(context),
          );
        }
      }),
```

and `NewTabIntent`, `CloseTabIntent`, `SelectTabIntent` bodies call `_closePanel();` first.
4. In `build`: `ref.listen<int>(terminalFocusRequestProvider, (_, _) => focusTerminal());`.
5. Wrap the page body in a `Stack`; when `panelOpen`, add a full-size `GestureDetector(behavior: HitTestBehavior.opaque, onTap: _closePanel)` and the panel `Positioned(left: ShellxSpace.s8, top: (isMacDesktop ? ShellxSizes.headerBandMac : ShellxSizes.headerBandWindows) + ShellxSizes.panelOffsetY, child: NotificationsPanel(onClose: _closePanel))`, inside an `AnimatedSwitcher` with `ShellxMotion.of(context, ShellxMotion.base)` / `exit` (fade + `SlideTransition` from `Offset(0, -4 / 480)`), so reduced motion is instant.
6. Pass `panelOpen` and `onToggleNotifications: _togglePanel` to `SessionSidebar` for the bell button.

`session_sidebar.dart` header band: add params `final bool panelOpen; final VoidCallback onToggleNotifications;` and, before `newTab` in the band's `Row`, the bell:

```dart
    final total = ref.watch(tabAttentionProvider).totalUnread;
    final bellShortcut = notificationsShortcutLabel();
    final bell = Stack(
      children: [
        ShellxIconButton(
          key: const Key('sidebar.bell'),
          icon: total > 0 ? Icons.notifications : Icons.notifications_none,
          semanticLabel: total > 0
              ? '${l10n.notificationsPanelTitle}, ${l10n.attentionUnreadCount(total)}'
              : l10n.notificationsPanelTitle,
          tooltip: shortcutTooltip(
            l10n.notificationsPanelTooltip(bellShortcut),
            bellShortcut,
          ),
          onPressed: widget.onToggleNotifications,
        ),
        if (total > 0)
          Positioned(
            // Centre (19, 7) in the 24 visual, which sits 2 px inside 28.
            left: 2 + 19 - ShellxSizes.bellDot / 2,
            top: 2 + 7 - ShellxSizes.bellDot / 2,
            child: IgnorePointer(
              child: Container(
                width: ShellxSizes.bellDot,
                height: ShellxSizes.bellDot,
                decoration: const BoxDecoration(
                  color: ShellxDesktopColors.accent,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),
      ],
    );
```

and in the band put `bell, const SizedBox(width: ShellxSizes.headerBellGap),` before the padded `newTab` (same top padding on macOS). When `panelOpen`, wrap `bell` in a `DecoratedBox` with `rowSelected` and `r6` (UI-A4 §5.1 "on" state).

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/ui`
Expected: PASS (all A1/A2 UI tests too).

- [ ] **Step 5: Format, analyze, commit**

```bash
cd apps/desktop && ~/fvm/versions/3.41.4/bin/dart format --set-exit-if-changed lib/src/ui lib/src/terminal/terminal_tabs.dart test/ui && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter analyze
cd ../.. && git add apps/desktop/lib/src/ui/terminal/attention_marks.dart apps/desktop/lib/src/ui/terminal/notifications_panel.dart apps/desktop/lib/src/ui/terminal/terminal_pane.dart apps/desktop/lib/src/ui/terminal/terminal_shortcuts.dart apps/desktop/lib/src/ui/terminal/shortcut_labels.dart apps/desktop/lib/src/ui/terminal/terminal_workspace_page.dart apps/desktop/lib/src/ui/terminal/session_sidebar.dart apps/desktop/lib/src/ui/terminal/terminal_overlays.dart apps/desktop/lib/src/terminal/terminal_tabs.dart apps/desktop/test/ui/attention_ring_test.dart apps/desktop/test/ui/notifications_panel_test.dart apps/desktop/test/ui/terminal_shortcuts_test.dart
git commit -m "feat(desktop): notification ring, notifications panel, next unread and the sidebar bell (A4 N3, N5, D12, D13, D21)"
```

---

### Task 9: Desktop — wiring in `main.dart`, announcements, HANDOFF checklist

**Files:**
- Modify: `apps/desktop/lib/main.dart`
- Create: `apps/desktop/lib/src/terminal/attention_announcer.dart`
- Create: `apps/desktop/test/terminal/attention_announcer_test.dart`
- Modify: `docs/superpowers/HANDOFF.md` (new §13)

**Interfaces:**
- Consumes: everything above — `windowFocusProvider` (Task 3), `tabAttentionProvider` (Task 4), `DesktopNotifications`, `listenForDesktopNotifications` (Task 5), `listenForAttentionBadge`, `MacDockBadge`, `WindowsTaskbarBadge` (Task 6); `windowRouterProvider.showTerminal()`.
- Produces:
  - `final class AttentionAnnouncer { AttentionAnnouncer({required void Function(String) announce, required AppLocalizations l10n, DateTime Function()? now, Duration gap = 3 s}); void arrived(AttentionArrival a, {required String tab, required bool windowFocused, required bool tabSelected}); }`
  - `void openTabFromNotification(ProviderContainer container, int tabId)`

- [ ] **Step 1: Write the failing test**

Create `apps/desktop/test/terminal/attention_announcer_test.dart`:

```dart
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/l10n/app_localizations.dart';
import 'package:shellx_desktop/src/terminal/attention_announcer.dart';
import 'package:shellx_desktop/src/terminal/tab_attention.dart';

void main() {
  test('focused window, other tab: announced at most once per 3 s per tab '
      '(D24)', () {
    final said = <String>[];
    var now = DateTime(2026, 10, 7, 9);
    final a = AttentionAnnouncer(
      announce: said.add,
      l10n: lookupAppLocalizations(const Locale('en')),
      now: () => now,
    );
    AttentionArrival arrival(String text) => AttentionArrival(
      tabId: 2,
      kind: AttentionKind.message,
      text: text,
      at: now,
    );
    a.arrived(arrival('one'), tab: 'api', windowFocused: true, tabSelected: false);
    a.arrived(arrival('two'), tab: 'api', windowFocused: true, tabSelected: false);
    a.arrived(arrival('x'), tab: 'api', windowFocused: false, tabSelected: false);
    now = now.add(const Duration(seconds: 3));
    a.arrived(arrival('three'), tab: 'api', windowFocused: true, tabSelected: false);
    expect(said, [
      'New notification from api: one',
      'New notification from api: three',
    ]);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/terminal/attention_announcer_test.dart`
Expected: FAIL — file missing.

- [ ] **Step 3: Implement**

Create `apps/desktop/lib/src/terminal/attention_announcer.dart`:

```dart
import '../../l10n/app_localizations.dart';
import 'tab_attention.dart';

/// A4 D24: a screen reader hears a new notice for another tab while the
/// window is in use — at most once per [gap] per tab.
final class AttentionAnnouncer {
  AttentionAnnouncer({
    required void Function(String text) announce,
    required AppLocalizations l10n,
    DateTime Function()? now,
    this.gap = const Duration(seconds: 3),
  }) : _announce = announce,
       _l10n = l10n,
       _now = now ?? DateTime.now;

  final void Function(String text) _announce;
  final AppLocalizations _l10n;
  final DateTime Function() _now;
  final Duration gap;
  final _last = <int, DateTime>{};

  void arrived(
    AttentionArrival a, {
    required String tab,
    required bool windowFocused,
    required bool tabSelected,
  }) {
    if (!windowFocused || tabSelected) return;
    final now = _now();
    final last = _last[a.tabId];
    if (last != null && now.difference(last) < gap) return;
    _last[a.tabId] = now;
    _announce(_l10n.attentionAnnounce(tab, a.text));
  }
}
```

`main.dart`:

1. Imports: `src/platform/attention_badge.dart`, `src/platform/desktop_notifications.dart`, `src/terminal/attention_announcer.dart`, `src/terminal/tab_attention.dart`, `src/terminal/terminal_tabs.dart`, `src/ui/window_focus.dart`, `package:flutter/semantics.dart`.
2. `WindowManagerHost(` gains `onFocusChanged: (focused) => container.read(windowFocusProvider.notifier).set(focused),`.
3. After `listenForPortWatch(...)`:

```dart
  // A4: tab attention — system notifications (D14–D16), Dock/taskbar
  // badge (D18–D19), screen-reader announcements (D24). Reading the
  // attention provider here builds it before the first shell starts.
  final desktopNotifications = DesktopNotifications(
    notifier: notifier,
    settings: settings,
    l10n: l10n,
    onOpen: (id) => openTabFromNotification(container, id),
  );
  listenForDesktopNotifications(
    container: container,
    notifications: desktopNotifications,
    l10n: l10n,
  );
  listenForAttentionBadge(
    container: container,
    host: Platform.isMacOS
        ? const MacDockBadge()
        : Platform.isWindows
        ? const WindowsTaskbarBadge()
        : const NoBadge(),
    l10n: l10n,
    run: (call) => _unawaitedLogged(call, 'badge'),
  );
  final announcer = AttentionAnnouncer(
    l10n: l10n,
    announce: (text) => unawaited(
      SemanticsService.announce(text, TextDirection.ltr),
    ),
  );
  container.read(tabAttentionProvider.notifier).arrivals.listen((a) {
    final tabs = container.read(terminalTabsProvider);
    final tab = tabs.tabs.where((t) => t.id == a.tabId).firstOrNull;
    if (tab == null) return;
    announcer.arrived(
      a,
      tab: tab.label,
      windowFocused: container.read(windowActiveProvider),
      tabSelected: tabs.selectedId == a.tabId,
    );
  });
```

4. Top-level function in `main.dart`:

```dart
/// A4 D16: a system notification was clicked — the window comes to the
/// front (no new tab, unlike activation), then the tab is selected, its
/// workspace expanded, read, and the terminal focused. A closed tab only
/// raises the window.
void openTabFromNotification(ProviderContainer container, int tabId) {
  container.read(windowRouterProvider.notifier).showTerminal();
  if (Platform.isMacOS) _unawaitedLogged(activateMacApp(), 'activate');
  container.read(tabAttentionProvider.notifier).jumpTo(tabId);
}
```

(`activateMacApp` is in `src/platform/app_reopen.dart`; `showTerminal()` bumps `raise`, so `WindowPresenter` brings a shown-but-hidden-behind window to the front.)

`docs/superpowers/HANDOFF.md`: add a section after §12:

```markdown
## 13. Thông báo kiểu cmux — A4 (2026-10-07)

Thử tay trên macOS 14/15 và Windows 10/11 thật (CI không có):

1. Tab B không chọn: `printf '\e]9;Build xong\a'` → badge 1 + dòng "Build xong" ≤ 200 ms; Dock hiện 1.
2. `printf '\e]777;notify;CI;Đã xanh\a'`, `shellx notify xong`, `printf '\e]99;;Xin chào\e\\'`, OSC 99 hai mảnh (`i=1:d=0` rồi `i=1:p=body`), `e=1` base64 tiếng Việt.
3. Claude Code với `preferredNotifChannel` = `kitty`, `iterm2`, `terminal_bell`: tab của nó có badge khi chờ trả lời.
4. `printf '\a'` liên tục 10 s → tối đa 2 chuông; gõ Tab-completion sai trong tab đang xem → không có gì.
5. Ngưỡng 10 s: `sleep 11; false` trong tab không chọn → "✗ … · mã 1 · 11 giây"; Tắt → không.
6. Chọn tab có badge, rời trước 1 s → còn; ở lại 1 s → mất; vòng sáng quanh terminal khi cửa sổ ở sau app khác rồi focus lại; giảm chuyển động (Cài đặt hệ thống) → vòng tĩnh.
7. ⌘⇧I / Ctrl+Shift+I: bảng, ↑/↓/Enter nhảy tới tab trong workspace thu gọn; ⌘⇧U lần lượt các tab chưa đọc; hết → toast.
8. Cửa sổ ở sau app khác / thu nhỏ / ở Space khác: thông báo hệ thống tới; bấm → cửa sổ lên trước, đúng tab, gõ được ngay; vòng lặp 20 OSC 9 → 2 thông báo; đọc tab → thông báo biến khỏi Notification Center.
9. Tray → Thông báo: tắt "Thông báo trên máy tính" → không còn thông báo hệ thống (badge vẫn); tắt "Chỉ khi…" → tab không chọn khi cửa sổ đang trước cũng thông báo; còn sau khi khởi động lại; dùng được khi **chưa đăng nhập**.
10. Ẩn cửa sổ rồi hiện lại → Dock badge vẫn đúng số.
11. Windows: chấm accent trên nút taskbar khi có chưa đọc (Narrator đọc "N thông báo chưa đọc"), nháy khi có thông báo mới lúc cửa sổ không focus; gỡ khi đọc hết.
12. Điện thoại đã ghép: OSC 9/777 và lệnh chạy lâu vẫn push như trước; OSC 99 và BEL không push.
13. VoiceOver/Narrator: dòng tab đọc "N thông báo chưa đọc, mới nhất: …"; thông báo tới tab khác được đọc một lần.
14. Focus/Không làm phiền bật → không lỗi, badge/vòng vẫn chạy.
```

- [ ] **Step 4: Run the full suites**

Run: `cd packages/shellx_agent && ~/fvm/versions/3.41.4/bin/dart test`
Expected: PASS.
Run: `cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test`
Expected: PASS (whole desktop suite).
Run: `cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter build macos --debug`
Expected: builds (the wiring compiles against the real plugins).

- [ ] **Step 5: Format, analyze, commit**

```bash
cd apps/desktop && ~/fvm/versions/3.41.4/bin/dart format --set-exit-if-changed lib/main.dart lib/src/terminal/attention_announcer.dart test/terminal/attention_announcer_test.dart && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter analyze
cd ../.. && git add apps/desktop/lib/main.dart apps/desktop/lib/src/terminal/attention_announcer.dart apps/desktop/test/terminal/attention_announcer_test.dart docs/superpowers/HANDOFF.md
git commit -m "feat(desktop): wire A4 notifications — system notifications, badge, focus, announcements; HANDOFF §13"
```

---

## Self-Review

**Spec coverage.** N1 sources: OSC 9/777 (existing parser, Task 2 emits), OSC 99 + BEL (Task 1), command threshold (Task 2 D5); signed-out works (Task 5 tray in both menus, no API use). N2/D4 seam: Task 2 (`notices`) + Task 4 (`TabAttention`), `SessionSummary` untouched. N3: badge + line (Task 7), ring (Task 8), header dot (Task 7). N4: dwell (Task 4), menu (Task 7), mark all (Tasks 7, 8). N5: panel + ⌘⇧I/⌘⇧U (Task 8), jump (Task 4). N6/D14–D17: Task 5, click wiring Task 9. N7/D18–D19: Task 6. N8: Task 1 push test, `SessionNotifier` untouched. N9/D27: `toString` tests (Tasks 1, 2), log-by-type only in Tasks 5, 6. D3/D6 limits: Task 2. D7–D13, D26: Task 4. D20: Tasks 3, 5. D21: Task 8. D22–D23: Task 7. D24: Task 9. D25: Task 3 + Task 9 wiring. Success criterion 14 (no A1/A2 regression): every UI task runs the whole `test/ui`.

**Placeholder scan.** No TBD/TODO. Three steps tell the executor to match an existing name they will see in the file (fake native window class in `window_host_test`, `ShellxRadius.pill`/`ShellxElevation.e1`, `AuthPhase` value names) — each gives the expected shape and the exact assertion.

**Type consistency.** `SessionNotice`/`SessionNoticeKind` (Task 2) are used unchanged in Tasks 4–8; `AttentionKind.values.byName(kind.name)` relies on identical enum names (`message`, `command`, `bell`). `AttentionArrival(tabId, kind, text, at)`, `TabUnread(count, text, kind, at)`, `AttentionEntry(seq, …, repeat, closed)` match across Tasks 4–9. `DesktopNotifications.arrived(a, title:, windowFocused:, tabSelected:)` is the same in Task 5's tests, Task 5's `listenForDesktopNotifications` and Task 9. `SystemNotifier.show(id:)`/`close` match `RecordingNotifier`. `SessionTabRow.heightFor(context:, notification:)` matches the sidebar's `_extent`. `jumpTo` returns `bool` and is used as such in Task 8's next-unread action.

**Review Focus coverage.** (1) flood: Task 2 limiter test, Task 4 history-limit test, Task 5 burst + rate tests. (2) looking-at-it: Task 4 D7 tests, Task 5 D14 matrix. (3) quick switching: Task 4 dwell test. (4) closing tabs: Task 4 `_dropGone` test, Task 5 read-cancels test, Task 8 closed-entry test. (5) kitty chunks: Task 1 tests.
