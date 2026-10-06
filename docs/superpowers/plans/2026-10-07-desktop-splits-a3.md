# ShellX Desktop A3 — Split Panes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A sidebar tab holds a binary tree of panes (split right ⌘D, split down ⌘⇧D), each pane one agent session with its own grid size, with directional focus, divider drag and keyboard resize, zoom, equalize, per-pane close, cwd inheritance, and A4 attention aggregated per tab with the ring on the pane that notified — while a one-pane tab stays exactly A4.

**Architecture:** A pure-Dart pane tree (`pane_layout.dart`) is held by each `TerminalTab`; the former per-session tab record becomes `PaneSession`, and `TerminalTab`'s old getters delegate to the focused pane so the sidebar, workspaces and A4 compile unchanged. `TerminalTabs` gains pane operations and reports grid sizes only for visible panes. A new `PaneTreeView` widget lays the tree out (dividers, 22 px pane headers, focus outline, zoom via Offstage, per-pane ring and driver pill). The agent only gains `LocalSessions.open(cwd:)`; the protocol and the phone app do not change.

**Tech Stack:** Dart ^3.11 / Flutter 3.41.4 (fvm), `package:test` + `fake_async` (agent), `flutter_test` + `fake_async` (desktop), flutter_riverpod 3, xterm 4.0.0, ARB l10n via `flutter gen-l10n`.

**Spec:** `docs/superpowers/specs/2026-10-07-desktop-splits-a3-design.md` (binding; P1–P9 and D1–D30 are final). **UI design:** `docs/superpowers/design/2026-10-07-shellx-desktop-ui-a3.md` (binding for every measurement, colour, string and wireframe; cited as "UI-A3 §N"), on top of `2026-10-07-shellx-desktop-ui-a4.md` ("UI-A4 §N"), `2026-10-07-shellx-desktop-ui-a2.md` ("UI-A2 §N") and `2026-10-06-shellx-desktop-ui.md` ("UI-A1 §N"). Executors read the spec and UI-A3 before Task 1.

## Prerequisite: A4 must be merged first

A3 executes **after A4 (`feat/desktop-a4`) is merged into `main`**. Start a fresh branch `feat/desktop-a3` from that `main`.

| Task | Depends on A4 being merged? | Why |
|---|---|---|
| 1 Agent `open(cwd:)` | No (touches `local_sessions.dart`, `session_manager.dart`, which A4 also edits → do it on post-A4 `main` to avoid conflicts) | Only conflict risk |
| 2 Pane tree model | No (new file) | — |
| 3 Strings, sizes, intents | **Yes** | Edits `terminal_shortcuts.dart`, `shortcut_labels.dart`, ARB files and `ShellxSizes`, all changed by A4 |
| 4 Tab holds panes | **Yes** | `terminal_tabs.dart` (A4 adds `NoUnreadNotice`); A4's `TabAttention` must keep compiling against the new `TerminalTab` |
| 5 Pane operations | **Yes** | Builds on Task 4; toast switch in `terminal_overlays.dart` (A4 adds a case) |
| 6 `PaneTreeView` | **Yes** | Moves A4's `AttentionRing` into each pane |
| 7 Actions, menus, sidebar | **Yes** | `terminal_workspace_page.dart`, `session_tab_row.dart`, `session_sidebar.dart` carry A4 code |
| 8 Attention per pane | **Yes (hard)** | Rewrites parts of A4's `TabAttention` |
| 9 Parity, HANDOFF | **Yes** | HANDOFF §13 is A4's; A3 adds §14 |

Before Task 1 run both full suites on the fresh branch and record the counts (they must stay green throughout):

```bash
cd packages/shellx_agent && ~/fvm/versions/3.41.4/bin/dart test
cd ../../apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test
```

## Global Constraints

- The spec wins over everything else; UI-A3 (then UI-A4, UI-A2, UI-A1) wins for visuals and copy. Never invent a colour, size, duration or string: take it from the UI section the task names. **No new colour tokens** (UI-A3 §1.1).
- Toolchain: Flutter `~/fvm/versions/3.41.4/bin/flutter`, Dart `~/fvm/versions/3.41.4/bin/dart`. Agent tests: `cd packages/shellx_agent && ~/fvm/versions/3.41.4/bin/dart test`. Desktop tests: `cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test`. Format: `~/fvm/versions/3.41.4/bin/dart format --set-exit-if-changed <paths>`. Analyze: `cd packages/shellx_agent && ~/fvm/versions/3.41.4/bin/dart analyze`; `cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter analyze`.
- **No protocol change, no phone change (P1, D24):** no edits to `packages/shellx_core`, `apps/mobile`, `web/`, relay, `term/`. Phone-opened sessions always become new tabs.
- **One-pane tab = A4 (criterion 13):** no pane header, no focus outline, no divider, same `Semantics` label "Terminal {title}", same ring rect, same resize calls. Task 9 pins it.
- **Tab id = id of the session that created the tab and never changes (D1).** Never call `LocalSessions.close(tab.id)` — close `tab.paneIds`.
- **Grid sizes (P5, D13):** only *visible* panes (selected tab, not hidden by zoom) call `LocalSessionView.resize`. A resize makes the desktop the driver (A1 D6) — never resize a hidden pane's session.
- Shortcuts: chords with Alt on Windows fire only with the **left** Alt (AltGr guard, D20), like A1's Ctrl+Alt+digit.
- Privacy (A4 N9) unchanged: no terminal text, titles, cwd or notification text in logs (the agent logs only "cwd fallback").
- l10n: every new string goes into both `apps/desktop/lib/l10n/app_en.arb` (with `@key` metadata; `index`/`count` are `int`) and `app_vi.arb` with identical keys, then `cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter gen-l10n`; commit the generated `lib/l10n/app_localizations*.dart`.
- Interfaces gaining members (`LocalSessions.open(cwd:)`): update **every** implementer in the same task (`SessionManager`, `apps/desktop/test/support/fake_local_sessions.dart`).
- Code style: match the surrounding code (doc comments that say *why*, `final class`, no `print`). Every task ends with its tests green, `dart format --set-exit-if-changed` clean on touched files, analyzer clean, the full desktop suite green (from Task 4 on), and a commit with a conventional message. Commit only the files the task lists — **never `git add -A`**.

## Review Focus

1. **A pane's shell exits or is closed while it is focused, zoomed, mid-drag, or the only other pane is being opened** — focus must land on the most recently used remaining pane, zoom must clear, a stale divider drag must be ignored, a pane opened for a tab that vanished becomes its own tab, and no phantom tab appears. Pinned by the `closePane`/exit tests and the D5 race test in Task 4, the vanished-tab test in Task 5, and the stale-path test in Task 5.
2. **Window resize, tab switch or zoom with several panes, some driven by a phone** — only visible panes resize their sessions; a hidden pane the phone drives keeps the phone size; unzoom re-sends the grids of panes that became visible. Pinned by the `resizes` tests in Task 5 and the widget resize test in Task 6.
3. **Splitting a pane that is too small, at the 32-session limit, or when the shell fails to start** — no tree change, the right toast, `+`/splits usable again (`opening` reset). Pinned by Task 5 tests.
4. **A cwd the agent cannot use** (deleted directory, relative path, UNC share, a slow network mount that hangs `stat`) — the new pane starts at home within 300 ms, never blocks or fails. Pinned by Task 1 (`fake_async` hang test).
5. **AltGr on Windows layouts that type characters with AltGr+Shift/AltGr+arrows** (German, Polish) — split-down, equalize, focus and resize chords must not fire on right Alt, so the shell gets the character. Pinned by the AltGr test in Task 7.

---

## File Structure

| File | Responsibility |
|---|---|
| Modify `packages/shellx_agent/lib/src/session/local_sessions.dart` | `open({cols, rows, String? cwd})` |
| Modify `packages/shellx_agent/lib/src/session/session_manager.dart` | `directoryExists`, `_workingDirectoryFor`, `_spawn(cwd:)` |
| Modify `packages/shellx_agent/test/support/session_rig.dart` | Pass-through `directoryExists`, `windowsPaths` |
| Modify `packages/shellx_agent/test/session/local_sessions_test.dart` | `open(cwd:)` group |
| Create `apps/desktop/lib/src/terminal/pane_layout.dart` | Pane tree + pure operations |
| Create `apps/desktop/test/terminal/pane_layout_test.dart` | Model tests |
| Modify `apps/desktop/lib/l10n/app_en.arb`, `app_vi.arb` (+ generated) | UI-A3 §7 strings |
| Modify `apps/desktop/lib/src/ui/theme/shellx_desktop_theme.dart` | UI-A3 §1.2 sizes |
| Modify `apps/desktop/lib/src/ui/terminal/terminal_shortcuts.dart`, `shortcut_labels.dart` | Pane intents, chords, labels |
| Modify `apps/desktop/lib/src/terminal/terminal_tabs.dart` | `PaneSession`, `TerminalTab` with tree, pane operations, visible-pane sizing |
| Modify `apps/desktop/test/support/fake_local_sessions.dart` | `open(cwd:)`, `openCwds` |
| Create `apps/desktop/test/terminal/terminal_tabs_panes_test.dart` | Tab/pane model tests |
| Modify `apps/desktop/lib/src/ui/terminal/terminal_overlays.dart` | `PaneNoRoomNotice` toast |
| Create `apps/desktop/lib/src/ui/terminal/pane_tree_view.dart` | Tree layout, dividers, pane header, outline, zoom, per-pane ring/pill, terminal menu |
| Modify `apps/desktop/lib/src/ui/terminal/terminal_pane.dart` | `IndexedStack` of `PaneTreeView`, `PaneMetrics` |
| Modify `apps/desktop/lib/src/ui/terminal/terminal_workspace_page.dart` | Pane actions, focus follows focused pane, announcements |
| Modify `apps/desktop/lib/src/ui/terminal/close_tab.dart` | `closePaneWithConfirm`, multi-pane tab confirm |
| Modify `apps/desktop/lib/src/ui/terminal/session_tab_row.dart`, `session_sidebar.dart` | Pane-count mark, labels, row menu |
| Modify `apps/desktop/lib/src/terminal/tab_attention.dart` | Per-pane unread, dwell, ring set, jump to pane |
| Create `apps/desktop/test/ui/pane_tree_view_test.dart`, `test/ui/pane_shortcuts_test.dart`, `test/terminal/tab_attention_panes_test.dart`, `test/ui/one_pane_parity_test.dart` | Widget/attention/parity tests |
| Modify `docs/superpowers/HANDOFF.md` | §14 manual checklist |

---

### Task 1: Agent — `LocalSessions.open(cwd:)` (D17)

**Files:**
- Modify: `packages/shellx_agent/lib/src/session/local_sessions.dart` (`open`)
- Modify: `packages/shellx_agent/lib/src/session/session_manager.dart` (constructor, `open`, `_spawn`, new `_workingDirectoryFor`, `_isAbsoluteLocal`)
- Modify: `packages/shellx_agent/test/support/session_rig.dart`
- Modify: `packages/shellx_agent/test/session/local_sessions_test.dart`
- Modify: `apps/desktop/test/support/fake_local_sessions.dart`

**Interfaces:**
- Consumes: `SessionManager._spawn`, `FakePty.workingDirectory` (existing).
- Produces:
  - `LocalSessions.open({required int cols, required int rows, String? cwd}) → Future<int>`
  - `SessionManager({…, Future<bool> Function(String path)? directoryExists})`, `SessionManager.cwdProbeTimeout == Duration(milliseconds: 300)`
  - `FakeLocalSessions.openCwds → List<String?>` (one entry per `open` call)

- [ ] **Step 1: Write the failing tests**

In `packages/shellx_agent/test/support/session_rig.dart` add two constructor parameters and pass them on:

```dart
    Future<bool> Function(String path)? directoryExists,
    bool windowsPaths = false,
```

```dart
      directoryExists: directoryExists,
      windowsPaths: windowsPaths,
```

Append to `packages/shellx_agent/test/session/local_sessions_test.dart` (inside `main`; add `import 'dart:async';` and `import 'package:fake_async/fake_async.dart';` if missing):

```dart
  group('open(cwd:) (A3 D17)', () {
    test('an existing absolute directory is the working directory', () async {
      final probed = <String>[];
      final rig = SessionRig(
        directoryExists: (path) async {
          probed.add(path);
          return path == '/Users/test/work/shellx';
        },
      );
      await rig.manager.open(cols: 80, rows: 24, cwd: '/Users/test/work/shellx');
      expect(rig.pty(0).workingDirectory, '/Users/test/work/shellx');
      expect(probed, ['/Users/test/work/shellx']);
    });

    test('null, empty, relative or missing → home, relative never probed',
        () async {
      final probed = <String>[];
      final rig = SessionRig(
        directoryExists: (path) async {
          probed.add(path);
          return false;
        },
      );
      for (final cwd in [null, '', 'work/shellx', '/Users/test/gone']) {
        await rig.manager.open(cols: 80, rows: 24, cwd: cwd);
      }
      expect(
        [for (final p in rig.factory.ptys) p.workingDirectory],
        List.filled(4, '/Users/test'),
      );
      expect(probed, ['/Users/test/gone']);
    });

    test('a probe that throws → home', () async {
      final rig = SessionRig(
        directoryExists: (_) async =>
            throw const FileSystemException('denied'),
      );
      await rig.manager.open(cols: 80, rows: 24, cwd: '/private');
      expect(rig.pty(0).workingDirectory, '/Users/test');
    });

    test('a probe that hangs → home after 300 ms', () {
      fakeAsync((async) {
        final rig = SessionRig(
          directoryExists: (_) => Completer<bool>().future, // never completes
        );
        int? id;
        unawaited(
          rig.manager
              .open(cols: 80, rows: 24, cwd: '/Volumes/nas')
              .then((value) => id = value),
        );
        async.elapse(const Duration(milliseconds: 299));
        expect(id, isNull);
        async.elapse(const Duration(milliseconds: 2));
        async.flushMicrotasks();
        expect(id, isNotNull);
        expect(rig.pty(0).workingDirectory, '/Users/test');
      });
    });

    test('Windows: a drive path is used; UNC is never probed', () async {
      final probed = <String>[];
      final rig = SessionRig(
        windowsPaths: true,
        directoryExists: (path) async {
          probed.add(path);
          return true;
        },
      );
      await rig.manager.open(cols: 80, rows: 24, cwd: r'C:\work\shellx');
      await rig.manager.open(cols: 80, rows: 24, cwd: r'\\server\share\x');
      expect(rig.pty(0).workingDirectory, r'C:\work\shellx');
      expect(rig.pty(1).workingDirectory, '/Users/test');
      expect(probed, [r'C:\work\shellx']);
    });

    test('phone opens still start at home', () async {
      final rig = SessionRig(directoryExists: (_) async => true);
      await rig.open(phone);
      expect(rig.pty(0).workingDirectory, '/Users/test');
    });
  });
```

(Add `import 'dart:io' show FileSystemException;` if the file does not import `dart:io`.)

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd packages/shellx_agent && ~/fvm/versions/3.41.4/bin/dart test test/session/local_sessions_test.dart`
Expected: FAIL — compile errors: no named parameter `cwd` / `directoryExists`.

- [ ] **Step 3: Implement**

`local_sessions.dart` — replace the `open` declaration:

```dart
  /// Starts a login shell in [cwd] when it is an absolute, local directory
  /// that exists (checked within [SessionManager.cwdProbeTimeout]);
  /// otherwise — no cwd, relative, a UNC share, missing, slow — in the home
  /// directory (A3 D17). Throws [SessionLimitException] or
  /// [SpawnFailedException].
  Future<int> open({required int cols, required int rows, String? cwd});
```

`session_manager.dart`:

1. Constructor: add the parameter `Future<bool> Function(String path)? directoryExists,` after `commandNoticeThreshold`, and the initializer `_directoryExists = directoryExists ?? _directoryExistsOnDisk,`. Fields and helpers next to `_homeDirectory`:

```dart
  final Future<bool> Function(String path) _directoryExists;

  static Future<bool> _directoryExistsOnDisk(String path) =>
      Directory(path).exists();

  /// A3 D17: how long a new pane waits for its directory to be confirmed
  /// before it starts at home (a hung network mount must not hold a split).
  static const cwdProbeTimeout = Duration(milliseconds: 300);
```

(`dart:io` is already imported by `session_manager.dart`; if not, add `import 'dart:io';`.)

2. `open`:

```dart
  @override
  Future<int> open({required int cols, required int rows, String? cwd}) async {
    final c = _clampDimension(cols);
    final r = _clampDimension(rows);
    final session = await _spawn(c, r, origin: SessionOrigin.desktop, cwd: cwd);
```

(rest unchanged).

3. `_spawn` gets `String? cwd` and resolves the directory inside the existing `try` (so `_pendingOpens` still covers the wait):

```dart
  Future<_Session?> _spawn(
    int cols,
    int rows, {
    required SessionOrigin origin,
    String? cwd,
  }) async {
```

```dart
    try {
      command = await _shellResolver.resolve();
      final workingDirectory = await _workingDirectoryFor(cwd);
      final launch = _launch(command);
      pty = _ptyFactory.spawn(
        launch.command,
        workingDirectory: workingDirectory,
        environment: launch.environment,
        cols: cols,
        rows: rows,
      );
```

4. New private methods (below `_spawn`):

```dart
  /// D17: [cwd] when it is usable, else home. Never throws.
  Future<String> _workingDirectoryFor(String? cwd) async {
    if (cwd == null || cwd.isEmpty || !_isAbsoluteLocal(cwd)) {
      return _homeDirectory;
    }
    try {
      if (await _directoryExists(cwd).timeout(cwdProbeTimeout)) return cwd;
    } on Object {
      // TimeoutException, FileSystemException: start at home instead.
    }
    _log?.call('session: cwd fallback to home'); // never the path (N9)
    return _homeDirectory;
  }

  /// Absolute and on this machine: `/…` (POSIX), `C:\…` / `C:/…` (Windows).
  /// UNC shares are refused: cmd.exe cannot start in one, and a dead
  /// server would stall the probe.
  bool _isAbsoluteLocal(String path) {
    if (_windowsPaths) {
      if (path.startsWith(r'\\') || path.startsWith('//')) return false;
      return RegExp(r'^[A-Za-z]:[\\/]').hasMatch(path);
    }
    return path.startsWith('/');
  }
```

`apps/desktop/test/support/fake_local_sessions.dart`: add `final openCwds = <String?>[];` next to `opens` and change `open`:

```dart
  @override
  Future<int> open({required int cols, required int rows, String? cwd}) async {
    opens.add((cols, rows));
    openCwds.add(cwd);
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd packages/shellx_agent && ~/fvm/versions/3.41.4/bin/dart test`
Expected: PASS (whole agent suite).
Run: `cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/terminal`
Expected: PASS.

- [ ] **Step 5: Format, analyze, commit**

```bash
cd packages/shellx_agent && ~/fvm/versions/3.41.4/bin/dart format --set-exit-if-changed lib/src/session test/session test/support && ~/fvm/versions/3.41.4/bin/dart analyze
cd ../../apps/desktop && ~/fvm/versions/3.41.4/bin/dart format --set-exit-if-changed test/support && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter analyze
cd ../.. && git add packages/shellx_agent/lib/src/session/local_sessions.dart packages/shellx_agent/lib/src/session/session_manager.dart packages/shellx_agent/test/support/session_rig.dart packages/shellx_agent/test/session/local_sessions_test.dart apps/desktop/test/support/fake_local_sessions.dart
git commit -m "feat(agent): LocalSessions.open(cwd:) — a new pane starts in the focused pane's directory, home when unusable (A3 D17)"
```

---

### Task 2: Desktop — pane tree model (`pane_layout.dart`)

**Files:**
- Create: `apps/desktop/lib/src/terminal/pane_layout.dart`
- Create: `apps/desktop/test/terminal/pane_layout_test.dart`

**Interfaces:**
- Consumes: nothing.
- Produces (all top-level in `pane_layout.dart`):
  - `enum SplitAxis { row, column }` (`row`: side by side = split right; `column`: stacked = split down)
  - `enum PaneDirection { left, right, up, down }`
  - `typedef PanePath = String;` (`''` root, then `'0'` first / `'1'` second per level)
  - `sealed class PaneNode`; `final class PaneLeaf extends PaneNode { const PaneLeaf(int sessionId); }`; `final class PaneSplit extends PaneNode { const PaneSplit({required SplitAxis axis, required double ratio, required PaneNode first, required PaneNode second}); PaneSplit copyWith({double? ratio, PaneNode? first, PaneNode? second}); }`
  - `const double kMinPaneRatio = 0.05;` `double clampRatio(double ratio)`
  - `List<int> paneIds(PaneNode node)` (reading order, D23)
  - `PaneNode splitPane(PaneNode node, int target, int newId, SplitAxis axis)`
  - `PaneNode? removePane(PaneNode node, int id)`
  - `int? siblingLeaf(PaneNode node, int id)` (first leaf of the removed leaf's sibling, D8)
  - `Map<int, Rect> paneRects(PaneNode node, [Rect area = const Rect.fromLTWH(0, 0, 1, 1)])`
  - `Rect? splitRect(PaneNode node, PanePath path, [Rect area = …unit…])`
  - `int? neighbourPane(PaneNode node, int from, PaneDirection direction, {List<int> mru = const []})` (D9)
  - `int paneSpan(PaneNode node, SplitAxis axis)`, `PaneNode equalized(PaneNode node)`, `PaneNode equalizedAt(PaneNode node, PanePath path)` (D11)
  - `PaneNode? nodeAt(PaneNode node, PanePath path)`, `PaneNode withRatio(PaneNode node, PanePath path, double ratio)`
  - `PanePath? ancestorSplit(PaneNode node, int id, SplitAxis axis)` (D12)

- [ ] **Step 1: Write the failing tests**

Create `apps/desktop/test/terminal/pane_layout_test.dart`:

```dart
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/terminal/pane_layout.dart';

/// 1 | (2 / 3): split 1 right, then split 2 down.
PaneNode tee() => splitPane(
  splitPane(const PaneLeaf(1), 1, 2, SplitAxis.row),
  2,
  3,
  SplitAxis.column,
);

void main() {
  test('split puts the new pane after the target, ratio 0.5 (D3)', () {
    final t = tee();
    expect(paneIds(t), [1, 2, 3]);
    expect(
      t,
      const PaneSplit(
        axis: SplitAxis.row,
        ratio: 0.5,
        first: PaneLeaf(1),
        second: PaneSplit(
          axis: SplitAxis.column,
          ratio: 0.5,
          first: PaneLeaf(2),
          second: PaneLeaf(3),
        ),
      ),
    );
    expect(splitPane(t, 99, 4, SplitAxis.row), t); // unknown target
  });

  test('remove lets the sibling take the place; last leaf → null', () {
    expect(paneIds(removePane(tee(), 2)!), [1, 3]);
    expect(removePane(tee(), 1), isA<PaneSplit>());
    expect(paneIds(removePane(tee(), 1)!), [2, 3]);
    expect(removePane(const PaneLeaf(1), 1), isNull);
    expect(removePane(tee(), 42), tee());
  });

  test('sibling leaf is the first leaf of the other branch (D8)', () {
    expect(siblingLeaf(tee(), 1), 2);
    expect(siblingLeaf(tee(), 3), 2);
    expect(siblingLeaf(tee(), 2), 3);
    expect(siblingLeaf(const PaneLeaf(1), 1), isNull);
  });

  test('rects in the unit square', () {
    final r = paneRects(tee());
    expect(r[1], const Rect.fromLTRB(0, 0, 0.5, 1));
    expect(r[2], const Rect.fromLTRB(0.5, 0, 1, 0.5));
    expect(r[3], const Rect.fromLTRB(0.5, 0.5, 1, 1));
    expect(splitRect(tee(), '1'), const Rect.fromLTRB(0.5, 0, 1, 1));
    expect(splitRect(tee(), '0'), isNull); // a leaf, not a split
  });

  group('neighbour (D9)', () {
    test('left/right/up/down in a T, no wrap', () {
      final t = tee();
      expect(neighbourPane(t, 2, PaneDirection.left), 1);
      expect(neighbourPane(t, 3, PaneDirection.left), 1);
      expect(neighbourPane(t, 2, PaneDirection.down), 3);
      expect(neighbourPane(t, 3, PaneDirection.up), 2);
      expect(neighbourPane(t, 1, PaneDirection.left), isNull);
      expect(neighbourPane(t, 2, PaneDirection.up), isNull);
    });

    test('the pane holding the centre line wins; else MRU on a tie', () {
      // 1's centre y is 0.5: [0.5, 1) holds it → 3 (half-open intervals).
      expect(neighbourPane(tee(), 1, PaneDirection.right), 3);
      // Move the inner divider: 2 now spans y 0..0.7 and holds 0.5.
      final moved = withRatio(tee(), '1', 0.7);
      expect(neighbourPane(moved, 1, PaneDirection.right), 2);
    });

    test('2×2 grid moves straight', () {
      var g = splitPane(const PaneLeaf(1), 1, 2, SplitAxis.row);
      g = splitPane(g, 1, 3, SplitAxis.column);
      g = splitPane(g, 2, 4, SplitAxis.column);
      // 1 2
      // 3 4
      expect(neighbourPane(g, 1, PaneDirection.right), 2);
      expect(neighbourPane(g, 3, PaneDirection.right), 4);
      expect(neighbourPane(g, 4, PaneDirection.up), 2);
    });
  });

  test('equalize three columns → 1/3 each; nested axes count max (D11)', () {
    var c = splitPane(const PaneLeaf(1), 1, 2, SplitAxis.row);
    c = splitPane(c, 2, 3, SplitAxis.row);
    final e = equalized(c) as PaneSplit;
    expect(e.ratio, closeTo(1 / 3, 1e-9));
    expect((e.second as PaneSplit).ratio, 0.5);
    final rects = paneRects(e);
    for (final id in [1, 2, 3]) {
      expect(rects[id]!.width, closeTo(1 / 3, 1e-9));
    }
    expect(paneSpan(tee(), SplitAxis.row), 2);
    expect(paneSpan(tee(), SplitAxis.column), 2);
    final only = equalizedAt(withRatio(c, '', 0.8), '1');
    expect((only as PaneSplit).ratio, 0.8); // root untouched
  });

  test('withRatio clamps to [0.05, 0.95]; a path to a leaf changes nothing',
      () {
    expect((withRatio(tee(), '', 0.99) as PaneSplit).ratio, 0.95);
    expect((withRatio(tee(), '', -1) as PaneSplit).ratio, 0.05);
    expect(withRatio(tee(), '0', 0.3), tee());
    expect(nodeAt(tee(), '10'), const PaneLeaf(2));
    expect(nodeAt(tee(), '00'), isNull);
  });

  test('nearest ancestor split of an axis (D12)', () {
    expect(ancestorSplit(tee(), 3, SplitAxis.column), '1');
    expect(ancestorSplit(tee(), 3, SplitAxis.row), '');
    expect(ancestorSplit(tee(), 1, SplitAxis.column), isNull);
    expect(ancestorSplit(const PaneLeaf(1), 1, SplitAxis.row), isNull);
  });
}
```

Note the centre-line rule: pane 1's right neighbour in the T is 3, because 1's centre y = 0.5 lies in 3's half-open span [0.5, 1), not in 2's [0, 0.5).

- [ ] **Step 2: Run test to verify it fails**

Run: `cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/terminal/pane_layout_test.dart`
Expected: FAIL — `pane_layout.dart` missing.

- [ ] **Step 3: Implement**

Create `apps/desktop/lib/src/terminal/pane_layout.dart`:

```dart
import 'dart:math' as math;
import 'dart:ui' show Rect;

import 'package:flutter/foundation.dart';

/// A3 D2. `row`: the two halves side by side (split right); `column`:
/// stacked (split down).
enum SplitAxis { row, column }

enum PaneDirection { left, right, up, down }

/// Where a split sits in a tree: `''` is the root, then one character per
/// level, `'0'` for `first`, `'1'` for `second`. Paths change when the tree
/// does; users re-check the node they find ([nodeAt]).
typedef PanePath = String;

/// A tab's pane tree (A3 P1). Immutable; every operation returns a new tree.
@immutable
sealed class PaneNode {
  const PaneNode();
}

@immutable
final class PaneLeaf extends PaneNode {
  const PaneLeaf(this.sessionId);
  final int sessionId;

  @override
  bool operator ==(Object other) =>
      other is PaneLeaf && other.sessionId == sessionId;
  @override
  int get hashCode => sessionId.hashCode;
  @override
  String toString() => 'PaneLeaf($sessionId)';
}

@immutable
final class PaneSplit extends PaneNode {
  const PaneSplit({
    required this.axis,
    required this.ratio,
    required this.first,
    required this.second,
  });

  final SplitAxis axis;

  /// The share of [first] along [axis], in [kMinPaneRatio, 1 − kMinPaneRatio].
  final double ratio;
  final PaneNode first;
  final PaneNode second;

  PaneSplit copyWith({double? ratio, PaneNode? first, PaneNode? second}) =>
      PaneSplit(
        axis: axis,
        ratio: ratio ?? this.ratio,
        first: first ?? this.first,
        second: second ?? this.second,
      );

  @override
  bool operator ==(Object other) =>
      other is PaneSplit &&
      other.axis == axis &&
      other.ratio == ratio &&
      other.first == first &&
      other.second == second;
  @override
  int get hashCode => Object.hash(axis, ratio, first, second);
  @override
  String toString() => 'PaneSplit($axis, $ratio, $first, $second)';
}

/// The model's own floor; pixel minimums (A3 D4) are applied by the tab
/// list, which knows the pane area.
const double kMinPaneRatio = 0.05;

double clampRatio(double ratio) =>
    ratio.clamp(kMinPaneRatio, 1 - kMinPaneRatio).toDouble();

const Rect _unit = Rect.fromLTWH(0, 0, 1, 1);

/// D23: reading order — `first` before `second`, depth first.
List<int> paneIds(PaneNode node) => switch (node) {
  PaneLeaf(:final sessionId) => [sessionId],
  PaneSplit(:final first, :final second) => [
    ...paneIds(first),
    ...paneIds(second),
  ],
};

/// D3: [target] becomes a split of [axis] with [newId] after it, half each.
PaneNode splitPane(PaneNode node, int target, int newId, SplitAxis axis) =>
    switch (node) {
      PaneLeaf(:final sessionId) when sessionId == target => PaneSplit(
        axis: axis,
        ratio: 0.5,
        first: node,
        second: PaneLeaf(newId),
      ),
      PaneLeaf() => node,
      final PaneSplit s => s.copyWith(
        first: splitPane(s.first, target, newId, axis),
        second: splitPane(s.second, target, newId, axis),
      ),
    };

/// D7: the tree without [id]; its sibling takes its parent's place. Null
/// when [id] was the only pane.
PaneNode? removePane(PaneNode node, int id) => switch (node) {
  PaneLeaf(:final sessionId) => sessionId == id ? null : node,
  final PaneSplit s => _rejoin(
    s,
    removePane(s.first, id),
    removePane(s.second, id),
  ),
};

PaneNode? _rejoin(PaneSplit s, PaneNode? first, PaneNode? second) {
  if (first == null) return second;
  if (second == null) return first;
  if (identical(first, s.first) && identical(second, s.second)) return s;
  return s.copyWith(first: first, second: second);
}

/// D8 fallback: the first leaf (reading order) of [id]'s sibling branch.
int? siblingLeaf(PaneNode node, int id) {
  if (node is! PaneSplit) return null;
  if (node.first == PaneLeaf(id)) return paneIds(node.second).first;
  if (node.second == PaneLeaf(id)) return paneIds(node.first).first;
  return siblingLeaf(node.first, id) ?? siblingLeaf(node.second, id);
}

/// Every leaf's rectangle inside [area] (the unit square by default).
Map<int, Rect> paneRects(PaneNode node, [Rect area = _unit]) {
  final out = <int, Rect>{};
  void visit(PaneNode n, Rect r) {
    switch (n) {
      case PaneLeaf(:final sessionId):
        out[sessionId] = r;
      case PaneSplit(:final axis, :final ratio, :final first, :final second):
        final (a, b) = _halves(r, axis, ratio);
        visit(first, a);
        visit(second, b);
    }
  }

  visit(node, area);
  return out;
}

(Rect, Rect) _halves(Rect r, SplitAxis axis, double ratio) {
  if (axis == SplitAxis.row) {
    final x = r.left + r.width * ratio;
    return (
      Rect.fromLTRB(r.left, r.top, x, r.bottom),
      Rect.fromLTRB(x, r.top, r.right, r.bottom),
    );
  }
  final y = r.top + r.height * ratio;
  return (
    Rect.fromLTRB(r.left, r.top, r.right, y),
    Rect.fromLTRB(r.left, y, r.right, r.bottom),
  );
}

/// The rectangle of the split at [path]; null when [path] is not a split.
Rect? splitRect(PaneNode node, PanePath path, [Rect area = _unit]) {
  var n = node;
  var r = area;
  for (final step in path.split('')) {
    if (n is! PaneSplit) return null;
    final (a, b) = _halves(r, n.axis, n.ratio);
    (n, r) = step == '0' ? (n.first, a) : (n.second, b);
  }
  return n is PaneSplit ? r : null;
}

const double _eps = 1e-6;

/// D9: the pane next to [from] in [direction] — touching edge, overlapping
/// on the other axis; the one holding [from]'s centre line, else the
/// largest overlap, ties by [mru] (most recent first). Null: none (no wrap).
int? neighbourPane(
  PaneNode node,
  int from,
  PaneDirection direction, {
  List<int> mru = const [],
}) {
  final rects = paneRects(node);
  final f = rects[from];
  if (f == null) return null;
  final sideways =
      direction == PaneDirection.left || direction == PaneDirection.right;
  final overlaps = <int, double>{};
  for (final MapEntry(key: id, value: r) in rects.entries) {
    if (id == from) continue;
    final touches = switch (direction) {
      PaneDirection.left => (r.right - f.left).abs() < _eps,
      PaneDirection.right => (r.left - f.right).abs() < _eps,
      PaneDirection.up => (r.bottom - f.top).abs() < _eps,
      PaneDirection.down => (r.top - f.bottom).abs() < _eps,
    };
    if (!touches) continue;
    final overlap = sideways
        ? math.min(r.bottom, f.bottom) - math.max(r.top, f.top)
        : math.min(r.right, f.right) - math.max(r.left, f.left);
    if (overlap > _eps) overlaps[id] = overlap;
  }
  if (overlaps.isEmpty) return null;
  final centre = sideways ? f.center.dy : f.center.dx;
  for (final id in overlaps.keys) {
    final r = rects[id]!;
    final (lo, hi) = sideways ? (r.top, r.bottom) : (r.left, r.right);
    if (lo <= centre + _eps && centre < hi - _eps) return id;
  }
  final best = overlaps.values.reduce(math.max);
  final pool = [
    for (final MapEntry(key: id, value: o) in overlaps.entries)
      if ((o - best).abs() < _eps) id,
  ];
  for (final id in mru) {
    if (pool.contains(id)) return id;
  }
  return pool.first;
}

/// D11: how many panes line up along [axis].
int paneSpan(PaneNode node, SplitAxis axis) => switch (node) {
  PaneLeaf() => 1,
  PaneSplit(axis: final a, :final first, :final second) =>
    a == axis
        ? paneSpan(first, axis) + paneSpan(second, axis)
        : math.max(paneSpan(first, axis), paneSpan(second, axis)),
};

double _evenRatio(PaneSplit s) {
  final a = paneSpan(s.first, s.axis);
  return a / (a + paneSpan(s.second, s.axis));
}

/// D11: every split shares its extent by span (three columns → 1/3 each).
PaneNode equalized(PaneNode node) => switch (node) {
  PaneLeaf() => node,
  final PaneSplit s => PaneSplit(
    axis: s.axis,
    ratio: _evenRatio(s),
    first: equalized(s.first),
    second: equalized(s.second),
  ),
};

/// D11 (double-click a divider): only the split at [path].
PaneNode equalizedAt(PaneNode node, PanePath path) =>
    _replaceAt(node, path, (s) => s.copyWith(ratio: _evenRatio(s)));

PaneNode? nodeAt(PaneNode node, PanePath path) {
  PaneNode n = node;
  for (final step in path.split('')) {
    if (n is! PaneSplit) return null;
    n = step == '0' ? n.first : n.second;
  }
  return n;
}

/// The split at [path] with [ratio] (clamped); anything else unchanged.
PaneNode withRatio(PaneNode node, PanePath path, double ratio) =>
    _replaceAt(node, path, (s) => s.copyWith(ratio: clampRatio(ratio)));

PaneNode _replaceAt(
  PaneNode node,
  PanePath path,
  PaneSplit Function(PaneSplit split) change,
) {
  if (node is! PaneSplit) return node;
  if (path.isEmpty) return change(node);
  final rest = path.substring(1);
  return path[0] == '0'
      ? node.copyWith(first: _replaceAt(node.first, rest, change))
      : node.copyWith(second: _replaceAt(node.second, rest, change));
}

/// D12: the deepest split of [axis] above [id]; null when none.
PanePath? ancestorSplit(PaneNode node, int id, SplitAxis axis) {
  PanePath? found;
  bool visit(PaneNode n, PanePath path) {
    switch (n) {
      case PaneLeaf(:final sessionId):
        return sessionId == id;
      case final PaneSplit s:
        final inside = visit(s.first, '${path}0') || visit(s.second, '${path}1');
        if (inside && found == null && s.axis == axis) found = path;
        return inside;
    }
  }

  visit(node, '');
  return found;
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/terminal/pane_layout_test.dart`
Expected: PASS.

- [ ] **Step 5: Format, analyze, commit**

```bash
cd apps/desktop && ~/fvm/versions/3.41.4/bin/dart format --set-exit-if-changed lib/src/terminal/pane_layout.dart test/terminal/pane_layout_test.dart && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter analyze
cd ../.. && git add apps/desktop/lib/src/terminal/pane_layout.dart apps/desktop/test/terminal/pane_layout_test.dart
git commit -m "feat(desktop): pane tree model — split, remove, rects, directional neighbour, equalize, ratios (A3 D2-D12)"
```

---

### Task 3: Desktop — A3 strings, sizes, pane intents and chords (after A4 merge)

**Files:**
- Modify: `apps/desktop/lib/l10n/app_en.arb`, `apps/desktop/lib/l10n/app_vi.arb` (+ generated `lib/l10n/app_localizations*.dart`)
- Modify: `apps/desktop/lib/src/ui/theme/shellx_desktop_theme.dart` (`ShellxSizes`)
- Modify: `apps/desktop/lib/src/ui/terminal/terminal_shortcuts.dart`
- Modify: `apps/desktop/lib/src/ui/terminal/shortcut_labels.dart`
- Create: `apps/desktop/test/ui/pane_shortcuts_test.dart`

**Interfaces:**
- Consumes: `SplitAxis`, `PaneDirection` (Task 2); `_windowShortcuts` (existing).
- Produces:
  - ARB keys (UI-A3 §7): `paneSplitRight`, `paneSplitDown`, `paneZoom`, `paneUnzoom`, `paneEqualize`, `paneClose`, `paneCloseTooltip(shortcut)`, `paneZoomedIndicator(index, count)`, `paneRegionLabel(index, count, title)`, `paneRegionUnreadLabel(index, count, title)`, `paneDividerLabel`, `paneSplitNoRoom`, `paneAnnounceSplit(index, count)`, `paneAnnounceClosed(count)`, `paneAnnounceZoomed`, `paneAnnounceUnzoomed`, `sidebarPaneCount(count)`, `terminalCloseTabAllPanes`, `confirmCloseRunningPaneBody`, `confirmCloseRunningPaneAction`, `confirmCloseRunningPanesBody(count)`
  - `ShellxSizes.paneDivider = 1`, `paneDividerHit = 6`, `paneHeader = 22`, `paneHeaderPadH = 8`, `paneHeaderDot = 6`, `paneHeaderClose = 18`, `paneFocusOutline = 1`, `paneMinCols = 20`, `paneMinRows = 5`, `paneResizeStep = 0.05`, `paneCountIcon = 12`, `paneCountGap = 2`; `static double paneHeaderFor(TextScaler s) => max(22, s.scale(16) + 6)`
  - Intents: `SplitPaneIntent(SplitAxis axis)`, `FocusPaneIntent(PaneDirection direction)`, `TogglePaneZoomIntent()`, `EqualizePanesIntent()`, `ResizePaneIntent(PaneDirection direction)` (⌘W stays `CloseTabIntent`; its action closes the focused pane in Task 7)
  - Labels: `splitRightShortcutLabel()`, `splitDownShortcutLabel()`, `zoomPaneShortcutLabel()`, `equalizePanesShortcutLabel()`, `closePaneShortcutLabel()` (= `closeTabShortcutLabel()`)

- [ ] **Step 1: Write the failing tests**

Create `apps/desktop/test/ui/pane_shortcuts_test.dart`:

```dart
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/terminal/pane_layout.dart';
import 'package:shellx_desktop/src/ui/terminal/terminal_shortcuts.dart';

Intent? _find(
  Map<ShortcutActivator, Intent> map,
  LogicalKeyboardKey key, {
  bool meta = false,
  bool control = false,
  bool shift = false,
  bool alt = false,
}) {
  for (final MapEntry(key: a, value: i) in map.entries) {
    if (a is SingleActivator &&
        a.trigger == key &&
        a.meta == meta &&
        a.control == control &&
        a.shift == shift &&
        a.alt == alt) {
      return i;
    }
  }
  return null;
}

void main() {
  for (final (name, build) in [
    ('TerminalView', terminalViewShortcuts),
    ('workspace', desktopShortcuts),
  ]) {
    test('$name: macOS pane chords (P3)', () {
      final m = build(TargetPlatform.macOS);
      expect(
        (_find(m, LogicalKeyboardKey.keyD, meta: true) as SplitPaneIntent).axis,
        SplitAxis.row,
      );
      expect(
        (_find(m, LogicalKeyboardKey.keyD, meta: true, shift: true)
                as SplitPaneIntent)
            .axis,
        SplitAxis.column,
      );
      expect(
        (_find(m, LogicalKeyboardKey.arrowLeft, meta: true, alt: true)
                as FocusPaneIntent)
            .direction,
        PaneDirection.left,
      );
      expect(
        _find(m, LogicalKeyboardKey.enter, meta: true, shift: true),
        isA<TogglePaneZoomIntent>(),
      );
      expect(
        _find(m, LogicalKeyboardKey.equal, meta: true, control: true),
        isA<EqualizePanesIntent>(),
      );
      expect(
        (_find(m, LogicalKeyboardKey.arrowDown, meta: true, control: true)
                as ResizePaneIntent)
            .direction,
        PaneDirection.down,
      );
    });

    test('$name: Windows pane chords (D20), no clash with font keys', () {
      final m = build(TargetPlatform.windows);
      expect(
        (_find(m, LogicalKeyboardKey.keyD, control: true, shift: true)
                as SplitPaneIntent)
            .axis,
        SplitAxis.row,
      );
      expect(
        (_find(m, LogicalKeyboardKey.keyD,
                    control: true, shift: true, alt: true)
                as SplitPaneIntent)
            .axis,
        SplitAxis.column,
      );
      expect(
        _find(m, LogicalKeyboardKey.arrowRight, control: true, alt: true),
        isA<FocusPaneIntent>(),
      );
      expect(
        _find(m, LogicalKeyboardKey.enter, control: true, shift: true),
        isA<TogglePaneZoomIntent>(),
      );
      expect(
        _find(m, LogicalKeyboardKey.equal,
            control: true, shift: true, alt: true),
        isA<EqualizePanesIntent>(),
      );
      expect(
        _find(m, LogicalKeyboardKey.arrowUp,
            control: true, shift: true, alt: true),
        isA<ResizePaneIntent>(),
      );
      // A1 font keys are untouched.
      expect(
        _find(m, LogicalKeyboardKey.equal, control: true, shift: true),
        isA<FontBiggerIntent>(),
      );
    });
  }

  test('split, zoom and equalize ignore key repeat; focus/resize repeat', () {
    final m = terminalViewShortcuts(TargetPlatform.macOS);
    for (final MapEntry(key: a, value: i) in m.entries) {
      if (a is! SingleActivator) continue;
      if (i is SplitPaneIntent ||
          i is TogglePaneZoomIntent ||
          i is EqualizePanesIntent) {
        expect(a.includeRepeats, isFalse, reason: '$i');
      }
      if (i is FocusPaneIntent || i is ResizePaneIntent) {
        expect(a.includeRepeats, isTrue, reason: '$i');
      }
    }
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/ui/pane_shortcuts_test.dart`
Expected: FAIL — `SplitPaneIntent` undefined.

- [ ] **Step 3: Implement**

`terminal_shortcuts.dart` — add `import '../../terminal/pane_layout.dart';` and the intents after `NewWorkspaceIntent`:

```dart
/// ⌘D / ⌘⇧D (A3 P3): split the focused pane of the selected tab.
class SplitPaneIntent extends Intent {
  const SplitPaneIntent(this.axis);
  final SplitAxis axis;
}

/// ⌘⌥arrows / Ctrl+Alt+arrows (D9).
class FocusPaneIntent extends Intent {
  const FocusPaneIntent(this.direction);
  final PaneDirection direction;
}

/// ⌘⇧↩ / Ctrl+Shift+Enter (D10).
class TogglePaneZoomIntent extends Intent {
  const TogglePaneZoomIntent();
}

/// ⌘⌃= / Ctrl+Shift+Alt+= (D11).
class EqualizePanesIntent extends Intent {
  const EqualizePanesIntent();
}

/// ⌘⌃arrows / Ctrl+Shift+Alt+arrows (D12).
class ResizePaneIntent extends Intent {
  const ResizePaneIntent(this.direction);
  final PaneDirection direction;
}

const _arrows = {
  LogicalKeyboardKey.arrowLeft: PaneDirection.left,
  LogicalKeyboardKey.arrowRight: PaneDirection.right,
  LogicalKeyboardKey.arrowUp: PaneDirection.up,
  LogicalKeyboardKey.arrowDown: PaneDirection.down,
};
```

In `_windowShortcuts`, add before the `font(...)` entries:

```dart
    // A3 P3 / D20. Windows chords with Alt are guarded against AltGr in
    // the actions (Task 7), like Ctrl+Alt+digit.
    SingleActivator(
      LogicalKeyboardKey.keyD,
      meta: mac,
      control: !mac,
      shift: !mac,
      includeRepeats: false,
    ): const SplitPaneIntent(SplitAxis.row),
    SingleActivator(
      LogicalKeyboardKey.keyD,
      meta: mac,
      control: !mac,
      shift: true,
      alt: !mac,
      includeRepeats: false,
    ): const SplitPaneIntent(SplitAxis.column),
    for (final MapEntry(key: key, value: direction) in _arrows.entries) ...{
      SingleActivator(key, meta: mac, control: !mac, alt: true):
          FocusPaneIntent(direction),
      SingleActivator(
        key,
        meta: mac,
        control: true,
        shift: !mac,
        alt: !mac,
      ): ResizePaneIntent(direction),
    },
    for (final enter in [
      LogicalKeyboardKey.enter,
      LogicalKeyboardKey.numpadEnter,
    ])
      SingleActivator(
        enter,
        meta: mac,
        control: !mac,
        shift: true,
        includeRepeats: false,
      ): const TogglePaneZoomIntent(),
    SingleActivator(
      LogicalKeyboardKey.equal,
      meta: mac,
      control: true,
      shift: !mac,
      alt: !mac,
      includeRepeats: false,
    ): const EqualizePanesIntent(),
```

`shortcut_labels.dart` — append:

```dart
String splitRightShortcutLabel() => isMacDesktop ? '⌘D' : 'Ctrl+Shift+D';
String splitDownShortcutLabel() => isMacDesktop ? '⌘⇧D' : 'Ctrl+Shift+Alt+D';
String zoomPaneShortcutLabel() => isMacDesktop ? '⌘⇧↩' : 'Ctrl+Shift+Enter';
String equalizePanesShortcutLabel() =>
    isMacDesktop ? '⌘⌃=' : 'Ctrl+Shift+Alt+=';
String closePaneShortcutLabel() => closeTabShortcutLabel();
```

`shellx_desktop_theme.dart` — in `ShellxSizes` (UI-A3 §1.2, §1.3; `dart:math` `max` is already imported there or add `import 'dart:math';`):

```dart
  // A3 (UI-A3 §1.2).
  static const double paneDivider = 1;
  static const double paneDividerHit = 6;
  static const double paneHeader = 22;
  static const double paneHeaderPadH = 8;
  static const double paneHeaderDot = 6;
  static const double paneHeaderClose = 18;
  static const double paneFocusOutline = 1;
  static const int paneMinCols = 20;
  static const int paneMinRows = 5;
  static const double paneResizeStep = 0.05;
  static const double paneCountIcon = 12;
  static const double paneCountGap = 2;

  /// UI-A3 §1.3.
  static double paneHeaderFor(TextScaler scaler) =>
      max(paneHeader, scaler.scale(16) + 6);
```

ARB — add to `app_en.arb`:

```json
  "paneSplitRight": "Split right",
  "paneSplitDown": "Split down",
  "paneZoom": "Zoom pane",
  "paneUnzoom": "Unzoom pane",
  "paneEqualize": "Equalize panes",
  "paneClose": "Close pane",
  "paneCloseTooltip": "Close pane  {shortcut}",
  "@paneCloseTooltip": {"placeholders": {"shortcut": {"type": "String"}}},
  "paneZoomedIndicator": "Zoomed · {index}/{count}",
  "@paneZoomedIndicator": {"placeholders": {"index": {"type": "int"}, "count": {"type": "int"}}},
  "paneRegionLabel": "Pane {index} of {count} — {title}",
  "@paneRegionLabel": {"placeholders": {"index": {"type": "int"}, "count": {"type": "int"}, "title": {"type": "String"}}},
  "paneRegionUnreadLabel": "Pane {index} of {count} — {title}, has unread notifications",
  "@paneRegionUnreadLabel": {"placeholders": {"index": {"type": "int"}, "count": {"type": "int"}, "title": {"type": "String"}}},
  "paneDividerLabel": "Pane divider",
  "paneSplitNoRoom": "Not enough room to split this pane",
  "paneAnnounceSplit": "Split, pane {index} of {count}",
  "@paneAnnounceSplit": {"placeholders": {"index": {"type": "int"}, "count": {"type": "int"}}},
  "paneAnnounceClosed": "{count, plural, =1{Pane closed, 1 left} other{Pane closed, {count} left}}",
  "@paneAnnounceClosed": {"placeholders": {"count": {"type": "int"}}},
  "paneAnnounceZoomed": "Pane zoomed",
  "paneAnnounceUnzoomed": "Pane unzoomed",
  "sidebarPaneCount": "{count, plural, =1{1 pane} other{{count} panes}}",
  "@sidebarPaneCount": {"placeholders": {"count": {"type": "int"}}},
  "terminalCloseTabAllPanes": "Close tab (all panes)",
  "confirmCloseRunningPaneBody": "The command running in this pane will be stopped.",
  "confirmCloseRunningPaneAction": "Close pane",
  "confirmCloseRunningPanesBody": "{count, plural, =1{The command running in 1 pane will be stopped.} other{The commands running in {count} panes will be stopped.}}",
  "@confirmCloseRunningPanesBody": {"placeholders": {"count": {"type": "int"}}}
```

and to `app_vi.arb` (same keys, no `@` metadata needed beyond what the vi file already does — copy the convention of the file):

```json
  "paneSplitRight": "Chia sang phải",
  "paneSplitDown": "Chia xuống dưới",
  "paneZoom": "Phóng to pane",
  "paneUnzoom": "Bỏ phóng to",
  "paneEqualize": "Cân bằng pane",
  "paneClose": "Đóng pane",
  "paneCloseTooltip": "Đóng pane  {shortcut}",
  "paneZoomedIndicator": "Phóng to · {index}/{count}",
  "paneRegionLabel": "Pane {index} trên {count} — {title}",
  "paneRegionUnreadLabel": "Pane {index} trên {count} — {title}, có thông báo chưa đọc",
  "paneDividerLabel": "Đường chia pane",
  "paneSplitNoRoom": "Không đủ chỗ để chia pane này",
  "paneAnnounceSplit": "Đã chia, pane {index} trên {count}",
  "paneAnnounceClosed": "Đã đóng pane, còn {count}",
  "paneAnnounceZoomed": "Đã phóng to pane",
  "paneAnnounceUnzoomed": "Đã bỏ phóng to",
  "sidebarPaneCount": "{count} pane",
  "terminalCloseTabAllPanes": "Đóng tab (mọi pane)",
  "confirmCloseRunningPaneBody": "Lệnh đang chạy trong pane này sẽ bị dừng.",
  "confirmCloseRunningPaneAction": "Đóng pane",
  "confirmCloseRunningPanesBody": "{count} pane đang chạy lệnh sẽ bị dừng."
```

Then run `cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter gen-l10n`. `test/l10n/l10n_test.dart` (existing) checks both ARB files have the same keys — it must pass.

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/ui/pane_shortcuts_test.dart test/l10n test/ui`
Expected: PASS (existing shortcut tests too: no A1/A4 chord changed).

- [ ] **Step 5: Format, analyze, commit**

```bash
cd apps/desktop && ~/fvm/versions/3.41.4/bin/dart format --set-exit-if-changed lib/src/ui test/ui && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter analyze
cd ../.. && git add apps/desktop/lib/l10n apps/desktop/lib/src/ui/theme/shellx_desktop_theme.dart apps/desktop/lib/src/ui/terminal/terminal_shortcuts.dart apps/desktop/lib/src/ui/terminal/shortcut_labels.dart apps/desktop/test/ui/pane_shortcuts_test.dart
git commit -m "feat(desktop): A3 strings, pane sizes, split/focus/zoom/equalize/resize chords (A3 P3, D20)"
```

---
### Task 4: Desktop — a tab holds panes (`PaneSession`, `TerminalTab` tree, D5) (after A4 merge)

The refactor that makes a tab a pane tree while every tab still has exactly one pane. No new user-visible behaviour: the whole existing desktop suite (A1/A2/A4) must stay green.

**Files:**
- Modify: `apps/desktop/lib/src/terminal/terminal_tabs.dart`
- Create: `apps/desktop/test/terminal/terminal_tabs_panes_test.dart`

**Interfaces:**
- Consumes: `PaneNode`, `PaneLeaf`, `paneIds`, `removePane`, `siblingLeaf` (Task 2); `LocalSessions.open(cwd:)` (Task 1).
- Produces:
  - `final class PaneSession` — exactly the former `TerminalTab` fields **minus** `customTitle`: `id, index, shell, title, origin, phoneAttached, runningCommand, driver, terminal, selection, cwd, gitBranch, ports, exitCode`; getters `exited`, `automaticLabel`, `hasContext`; `copyWith({String? title, bool? phoneAttached, bool? runningCommand, DriverSide? driver, int? exitCode, Object? cwd, Object? gitBranch, List<int>? ports})`.
  - `final class TerminalTab { const TerminalTab({required int id, required SessionOrigin origin, required PaneNode layout, required Map<int, PaneSession> panes, required int focusedPaneId, int? zoomedPaneId, List<int> paneHistory = const [], String? customTitle}); factory TerminalTab.single(PaneSession pane); }` with `focused`, `paneOrder` (`List<int>`, D23), `paneCount`, `isSplit`, `int paneNumber(int sessionId)` (1-based), `phoneDriving`, `withPane(int, PaneSession Function(PaneSession))`, `copyWith({PaneNode? layout, Map<int, PaneSession>? panes, int? focusedPaneId, Object? zoomedPaneId, List<int>? paneHistory, Object? customTitle})`, and the A1/A2 getters delegating to the focused pane: `index, shell, title, runningCommand, terminal, selection, cwd, gitBranch, ports, exitCode, exited, automaticLabel, label, hasContext`; `phoneAttached` (any pane), `driver` (phone when any attached pane is phone-driven, else the focused pane's).
  - `TerminalTabsState.tabOfSession(int sessionId) → TerminalTab?`
  - `TerminalTabs.runningPaneCount(int tabId) → int`, `needsPaneCloseConfirm(int sessionId) → bool`, `closePane(int sessionId)`; `close(int tabId)` closes every pane; `needsCloseConfirm(tabId)` = `runningPaneCount(tabId) > 0`.

- [ ] **Step 1: Write the failing tests**

Create `apps/desktop/test/terminal/terminal_tabs_panes_test.dart`:

```dart
import 'dart:async';
import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:shellx_desktop/l10n/app_localizations.dart';
import 'package:shellx_desktop/src/terminal/local_sessions_provider.dart';
import 'package:shellx_desktop/src/terminal/pane_layout.dart';
import 'package:shellx_desktop/src/terminal/terminal_tabs.dart';

import '../support/fake_local_sessions.dart';

late FakeLocalSessions local;
late ProviderContainer container;

TerminalTabs tabs() => container.read(terminalTabsProvider.notifier);
TerminalTabsState state() => container.read(terminalTabsProvider);

void boot() {
  container = ProviderContainer.test(
    overrides: [
      localSessionsProvider.overrideWithValue(local),
      appL10nProvider.overrideWithValue(
        lookupAppLocalizations(const Locale('en')),
      ),
    ],
  );
  state();
}

void main() {
  setUp(() => local = FakeLocalSessions());

  test('a session becomes a one-pane tab that reads like A2 (D1, D2)', () {
    local.add(local.summary(1, title: 'vim', cwd: '/Users/test/w'));
    boot();
    final tab = state().tabs.single;
    expect(tab.id, 1);
    expect(tab.layout, const PaneLeaf(1));
    expect(tab.paneOrder, [1]);
    expect(tab.focusedPaneId, 1);
    expect(tab.isSplit, isFalse);
    expect(tab.label, 'vim');
    expect(tab.cwd, '/Users/test/w');
    expect(identical(tab.terminal, tab.panes[1]!.terminal), isTrue);
    expect(state().tabOfSession(1), same(tab));
    expect(state().tabOfSession(2), isNull);
  });

  test('summary changes update the pane inside its tab', () {
    local.add(local.summary(1));
    boot();
    local.replace(local.summary(1, title: 'htop', runningCommand: true));
    expect(state().tabs.single.panes[1]!.title, 'htop');
    expect(state().tabs.single.runningCommand, isTrue);
    expect(tabs().runningPaneCount(1), 1);
    expect(tabs().needsCloseConfirm(1), isTrue);
    expect(tabs().needsPaneCloseConfirm(1), isTrue);
  });

  test('D5: a desktop session that appears while an open is pending waits '
      'for the opener; a phone session does not', () async {
    local.add(local.summary(1, origin: SessionOrigin.desktop));
    boot();
    local.openGate = Completer<void>();
    final opening = tabs().openTab();
    local.add(local.summary(7, origin: SessionOrigin.desktop));
    local.add(local.summary(8)); // phone
    expect(state().tabs.map((t) => t.id), [1, 8]);
    local.openGate!.complete();
    await opening;
    expect(state().tabs.map((t) => t.id), [1, 8, 7, 100]);
    expect(state().selectedId, 100);
  });

  test('close(tab) closes every pane session and removes the tab', () {
    local.add(local.summary(1));
    local.add(local.summary(2));
    boot();
    tabs().close(1);
    expect(local.closed, [1]);
    expect(state().tabs.map((t) => t.id), [2]);
  });

  test('closePane on a one-pane tab closes the tab (D6)', () {
    local.add(local.summary(1));
    boot();
    tabs().closePane(1);
    expect(local.closed, [1]);
    expect(state().tabs, isEmpty);
  });

  test('a non-zero exit keeps the tab; Enter closes it (A1 D14)', () async {
    local.add(local.summary(1));
    boot();
    local.views[1]!.end(3);
    await pumpEventQueue();
    expect(state().tabs.single.exited, isTrue);
    expect(state().tabs.single.panes[1]!.exitCode, 3);
    state().tabs.single.terminal.keyInput(TerminalKey.enter);
    expect(state().tabs, isEmpty);
  });
}
```

Add `import 'package:xterm/xterm.dart' show TerminalKey;` to the imports.

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/terminal/terminal_tabs_panes_test.dart`
Expected: FAIL — `layout`, `paneOrder`, `tabOfSession`, `runningPaneCount`… undefined.

- [ ] **Step 3: Implement**

In `terminal_tabs.dart` add `import 'pane_layout.dart';`.

(a) Rename the class `TerminalTab` (the per-session record) to `PaneSession`, delete its `customTitle` field, constructor parameter, `label` getter and `customTitle` `copyWith` parameter, and update its doc comment:

```dart
/// One pane of a tab: one session's view (A3 D2). These are the fields the
/// A1/A2 tab record had; the tab now holds one per pane.
@immutable
final class PaneSession {
```

(b) Add the new tab class after `PaneSession`:

```dart
/// A sidebar tab (A3 P1): a tree of panes, one session each. Its id is the
/// id of the session that created it and never changes (D1). The A1/A2
/// getters read the focused pane, so the sidebar, the workspaces and A4
/// read a tab exactly as before.
@immutable
final class TerminalTab {
  const TerminalTab({
    required this.id,
    required this.origin,
    required this.layout,
    required this.panes,
    required this.focusedPaneId,
    this.zoomedPaneId,
    this.paneHistory = const [],
    this.customTitle,
  });

  factory TerminalTab.single(PaneSession pane) => TerminalTab(
    id: pane.id,
    origin: pane.origin,
    layout: PaneLeaf(pane.id),
    panes: {pane.id: pane},
    focusedPaneId: pane.id,
    paneHistory: [pane.id],
  );

  final int id;

  /// Where the session that created the tab came from (the 📱 mark, D19).
  final SessionOrigin origin;
  final PaneNode layout;
  final Map<int, PaneSession> panes;
  final int focusedPaneId;

  /// D10: the pane drawn over the whole area; null when not zoomed.
  final int? zoomedPaneId;

  /// D8: most recently focused first.
  final List<int> paneHistory;

  /// C6: the user's name for this tab (desktop only); wins over [title].
  final String? customTitle;

  PaneSession get focused => panes[focusedPaneId]!;

  /// D23: reading order.
  List<int> get paneOrder => paneIds(layout);
  int get paneCount => panes.length;
  bool get isSplit => panes.length > 1;

  /// 1-based position of [sessionId] in [paneOrder] ("Pane 2 of 3").
  int paneNumber(int sessionId) => paneOrder.indexOf(sessionId) + 1;

  int get index => focused.index;
  String get shell => focused.shell;
  String get title => focused.title;
  bool get runningCommand => focused.runningCommand;
  DesktopTerminal get terminal => focused.terminal;
  TerminalController get selection => focused.selection;
  String? get cwd => focused.cwd;
  String? get gitBranch => focused.gitBranch;
  List<int> get ports => focused.ports;
  int? get exitCode => focused.exitCode;
  bool get exited => focused.exited;
  String get automaticLabel => focused.automaticLabel;
  String get label => customTitle ?? automaticLabel;
  bool get hasContext => focused.hasContext;

  /// D19: 👁 when any pane has a phone attached.
  bool get phoneAttached => panes.values.any((p) => p.phoneAttached);

  /// D19: the 👁 turns `warn` when any attached pane is phone-driven.
  bool get phoneDriving => panes.values.any(
    (p) => p.phoneAttached && p.driver == DriverSide.phone,
  );
  DriverSide get driver => phoneDriving ? DriverSide.phone : focused.driver;

  TerminalTab withPane(int id, PaneSession Function(PaneSession pane) change) {
    final pane = panes[id];
    return pane == null ? this : copyWith(panes: {...panes, id: change(pane)});
  }

  TerminalTab copyWith({
    PaneNode? layout,
    Map<int, PaneSession>? panes,
    int? focusedPaneId,
    Object? zoomedPaneId = _unset,
    List<int>? paneHistory,
    Object? customTitle = _unset,
  }) => TerminalTab(
    id: id,
    origin: origin,
    layout: layout ?? this.layout,
    panes: panes ?? this.panes,
    focusedPaneId: focusedPaneId ?? this.focusedPaneId,
    zoomedPaneId: identical(zoomedPaneId, _unset)
        ? this.zoomedPaneId
        : zoomedPaneId as int?,
    paneHistory: paneHistory ?? this.paneHistory,
    customTitle: identical(customTitle, _unset)
        ? this.customTitle
        : customTitle as String?,
  );
}
```

(c) `TerminalTabsState` — add:

```dart
  /// The tab holding session [sessionId] (A3 D1: not always `tab.id`).
  TerminalTab? tabOfSession(int sessionId) {
    for (final tab in tabs) {
      if (tab.panes.containsKey(sessionId)) return tab;
    }
    return null;
  }
```

(d) `TerminalTabs` — field `bool _awaitingOpen = false;` (D5) next to `_grid`, and these replacements (everything not shown stays as it is):

```dart
  Future<void> openTab() async {
    if (state.opening) return;
    _set(opening: true);
    _awaitingOpen = true;
    try {
      final id = await _local.open(cols: _grid.cols, rows: _grid.rows);
      if (!ref.mounted) return;
      _awaitingOpen = false;
      _sync();
      // The new shell may already be gone (exit 0, or ended before it could
      // be viewed): then keep a selection that exists.
      final opened = state.tabOfSession(id);
      _set(
        selectedId:
            opened?.id ?? state.selected?.id ?? state.tabs.firstOrNull?.id,
      );
    } on SessionLimitException catch (error) {
      if (ref.mounted) _set(notice: SessionLimitNotice(error.max));
    } on SpawnFailedException catch (error) {
      if (ref.mounted) {
        _set(notice: SpawnFailedNotice(spawnFailureOf(error.message)));
      }
    } finally {
      _awaitingOpen = false;
      // Whatever happened (an unexpected error too), `+` is usable again.
      if (ref.mounted) _set(opening: false);
    }
  }

  /// D15 for a tab: how many of its panes run a command.
  int runningPaneCount(int tabId) =>
      _tab(tabId)?.panes.values
          .where((p) => !p.exited && p.runningCommand)
          .length ??
      0;

  /// D15: a close asks first while a command runs (any pane of the tab).
  bool needsCloseConfirm(int id) => runningPaneCount(id) > 0;

  /// D6: one pane's D15.
  bool needsPaneCloseConfirm(int sessionId) {
    final pane = state.tabOfSession(sessionId)?.panes[sessionId];
    return pane != null && !pane.exited && pane.runningCommand;
  }

  /// "Đóng tab", the row ×, middle click: every pane (D6). The desktop may
  /// close every session (A1 D4).
  void close(int id) {
    final tab = _tab(id);
    if (tab == null) return;
    for (final pane in tab.panes.values) {
      if (!pane.exited) _local.close(pane.id);
    }
    _removeTab(id);
  }

  /// ⌘W on a split tab, the pane ×, "Đóng pane" (D6): the last pane closes
  /// the tab.
  void closePane(int sessionId) {
    final pane = state.tabOfSession(sessionId)?.panes[sessionId];
    if (pane == null) return;
    if (!pane.exited) _local.close(sessionId);
    _removePane(sessionId);
  }
```

`_merge` (D5):

```dart
  /// Existing tabs keep their place (and their panes stay while a session
  /// is gone but its exit is not handled yet); new sessions are appended as
  /// one-pane tabs — except a desktop session while this window's own open
  /// is pending (D5): the opener decides whether it is a tab or a pane.
  List<TerminalTab> _merge(List<TerminalTab> current) {
    final summaries = {for (final s in _local.sessions) s.id: s};
    final next = <TerminalTab>[];
    for (final tab in current) {
      var updated = tab;
      for (final id in tab.panes.keys) {
        final s = summaries.remove(id);
        if (s == null) continue;
        updated = updated.withPane(
          id,
          (p) => p.copyWith(
            title: s.title,
            phoneAttached: s.phoneAttached,
            runningCommand: s.runningCommand,
            driver: s.driver,
            cwd: s.cwd,
            gitBranch: s.gitBranch,
            ports: s.ports,
          ),
        );
      }
      next.add(updated);
    }
    for (final s in summaries.values) {
      if (_awaitingOpen && s.origin == SessionOrigin.desktop) continue;
      final pane = _attach(s);
      if (pane != null) next.add(TerminalTab.single(pane));
    }
    return next;
  }
```

`_attach` — signature `PaneSession? _attach(SessionSummary s, {TerminalGrid? size})`; size the terminal with `final grid = size ?? _grid; terminal.resize(grid.cols, grid.rows);`; the resize hook and driver listener become:

```dart
    terminal.onResize = (cols, rows, _, _) {
      // A3 D13 (A1's rule, per pane): every pane is laid out (IndexedStack,
      // Offstage under zoom); only visible ones tell their session, so a
      // hidden pane the phone drives keeps the phone driver and its size.
      if (!_reportsSize(s.id)) return;
      if (state.tabOfSession(s.id)?.isSplit == false) {
        _grid = (cols: cols, rows: rows);
      }
      view.resize(cols, rows);
    };
```

```dart
        view.driver.listen(
          (side) => _updatePane(s.id, (p) => p.copyWith(driver: side)),
        ),
```

and it returns `PaneSession(...)` (same arguments as the old `TerminalTab(...)` return).

`_onUserInput`, `_exited`:

```dart
  void _onUserInput(int id, String data) {
    final pane = state.tabOfSession(id)?.panes[id];
    if (pane == null) return;
    if (pane.exited) {
      // UI §2.6: Enter closes an exited pane (D7); other keys are ignored.
      if (data.contains('\r')) _removePane(id);
      return;
    }
    _links[id]?.view.write(utf8.encode(data));
  }
```

In `_exited` replace `_remove(id)` with `_removePane(id)` and the last line with `_updatePane(id, (p) => p.copyWith(exitCode: code));`.

Replace `_remove` with `_removeTab` + `_removePane`, add `_updatePane`, `_replaceTab`, `_tabById` alias not needed (`_tab` already exists), `_reportsSize`, and rename `_selectionChanged` → `_visibleChanged` (also inside `_set`):

```dart
  void _updatePane(int sessionId, PaneSession Function(PaneSession) change) {
    if (!ref.mounted) return;
    _set(
      tabs: [
        for (final t in state.tabs)
          t.panes.containsKey(sessionId) ? t.withPane(sessionId, change) : t,
      ],
    );
  }

  void _replaceTab(TerminalTab tab) =>
      _set(tabs: [for (final t in state.tabs) t.id == tab.id ? tab : t]);

  void _removeTab(int tabId) {
    final tabs = List.of(state.tabs);
    final i = tabs.indexWhere((t) => t.id == tabId);
    if (i < 0) return;
    for (final id in tabs[i].panes.keys) {
      _links.remove(id)?.dispose();
    }
    tabs.removeAt(i);
    var selected = state.selectedId;
    if (selected == tabId) selected = _successorOf(tabId, tabs);
    final before = state.selectedId;
    state = TerminalTabsState(
      tabs: tabs,
      selectedId: selected,
      notice: state.notice,
      opening: state.opening,
    );
    if (state.selectedId != before) _visibleChanged();
  }

  /// D7/D8: the sibling takes the place; focus goes to the most recently
  /// used remaining pane. The last pane takes the tab with it.
  void _removePane(int sessionId) {
    final tab = state.tabOfSession(sessionId);
    if (tab == null) {
      _links.remove(sessionId)?.dispose();
      return;
    }
    if (!tab.isSplit) {
      _removeTab(tab.id);
      return;
    }
    _links.remove(sessionId)?.dispose();
    final layout = removePane(tab.layout, sessionId)!;
    final remaining = paneIds(layout);
    final history = [
      for (final id in tab.paneHistory)
        if (id != sessionId && remaining.contains(id)) id,
    ];
    var focused = tab.focusedPaneId;
    if (focused == sessionId) {
      focused =
          history.firstOrNull ??
          siblingLeaf(tab.layout, sessionId) ??
          remaining.first;
    }
    final unzoom = tab.zoomedPaneId == sessionId;
    _replaceTab(
      tab.copyWith(
        layout: layout,
        panes: Map.of(tab.panes)..remove(sessionId),
        focusedPaneId: focused,
        paneHistory: [focused, ...history.where((id) => id != focused)],
        zoomedPaneId: unzoom ? null : tab.zoomedPaneId,
      ),
    );
    if (unzoom && state.selectedId == tab.id) _visibleChanged();
  }

  /// D13: the selected tab's panes, minus those a zoom hides.
  bool _reportsSize(int sessionId) {
    final tab = state.tabOfSession(sessionId);
    if (tab == null || tab.id != state.selectedId) return false;
    final zoomed = tab.zoomedPaneId;
    return zoomed == null || zoomed == sessionId;
  }

  /// Panes that just became visible (a new selection, an unzoom) tell
  /// their sessions the size they were laid out at while hidden; a size
  /// that did not change is ignored by the agent.
  void _visibleChanged() {
    final tab = state.selected;
    if (tab == null) return;
    for (final id in tab.paneOrder) {
      final pane = tab.panes[id];
      final link = _links[id];
      if (pane == null || link == null || pane.exited) continue;
      if (!_reportsSize(id)) continue;
      final terminal = link.terminal;
      if (!tab.isSplit) {
        _grid = (cols: terminal.viewWidth, rows: terminal.viewHeight);
      }
      link.view.resize(terminal.viewWidth, terminal.viewHeight);
    }
  }
```

Every other reference to `TerminalTab(` inside the notifier is gone; `rename` and `_update` keep working on tabs (`copyWith(customTitle:)` exists on the new class).

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/terminal/terminal_tabs_panes_test.dart`
Expected: PASS.
Run: `cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test`
Expected: PASS — the full A1/A2/A4 suite (every `tab.*` read goes through the delegating getters). If an A4 file constructs `TerminalTab(` directly, switch it to `TerminalTab.single(PaneSession(...))`.

- [ ] **Step 5: Format, analyze, commit**

```bash
cd apps/desktop && ~/fvm/versions/3.41.4/bin/dart format --set-exit-if-changed lib/src/terminal test/terminal && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter analyze
cd ../.. && git add apps/desktop/lib/src/terminal/terminal_tabs.dart apps/desktop/test/terminal/terminal_tabs_panes_test.dart
git commit -m "refactor(desktop): a tab holds a pane tree of PaneSessions; getters read the focused pane; desktop opens wait for their opener (A3 D1, D2, D5)"
```

---

### Task 5: Desktop — pane operations (split, focus, close, zoom, equalize, resize, sizing) (after A4 merge)

**Files:**
- Modify: `apps/desktop/lib/src/terminal/terminal_tabs.dart`
- Modify: `apps/desktop/lib/src/ui/terminal/terminal_overlays.dart` (toast text + neutral variant)
- Modify: `apps/desktop/test/terminal/terminal_tabs_panes_test.dart`

**Interfaces:**
- Consumes: Task 2 functions (`splitPane`, `paneRects`, `splitRect`, `neighbourPane`, `equalized`, `equalizedAt`, `nodeAt`, `withRatio`, `ancestorSplit`, `paneSpan`, `clampRatio`); Task 4 (`TerminalTab`, `_attach(size:)`, `_awaitingOpen`, `_replaceTab`, `_visibleChanged`, `_reportsSize`); `ShellxSizes.paneResizeStep` (Task 3); `l10n.paneSplitNoRoom` (Task 3).
- Produces:
  - `@immutable final class PaneMetrics { const PaneMetrics({required Size area, required Size minPane, required double divider}); }`
  - `final class PaneNoRoomNotice extends TabNotice { const PaneNoRoomNotice(); }` (neutral toast)
  - `TerminalTabs.reportPaneMetrics(PaneMetrics)`, `Future<void> split(SplitAxis axis)`, `void focusPane(int sessionId)`, `bool focusDirection(PaneDirection)`, `bool toggleZoom()` (returns the new zoomed state; false and no-op on a one-pane tab), `void equalize()`, `void equalizeAt(int tabId, PanePath path)`, `void setRatio(int tabId, PanePath path, double ratio)`, `void resizeFocused(PaneDirection)`

- [ ] **Step 1: Write the failing tests**

Append to `apps/desktop/test/terminal/terminal_tabs_panes_test.dart` inside `main` (helper above `main`: `TerminalTab only() => state().tabs.single;`):

```dart
  group('pane operations (A3)', () {
    setUp(() {
      local.add(
        local.summary(1, origin: SessionOrigin.desktop, cwd: '/Users/test/w'),
      );
    });

    test('split right: cwd, half grid, new pane after and focused '
        '(D3, D13, D17)', () async {
      boot();
      await tabs().split(SplitAxis.row);
      expect(local.openCwds.single, '/Users/test/w');
      expect(local.opens.single, (39, 23)); // 80×24 → (80−1)~/2 × (24−1)
      expect(only().id, 1);
      expect(
        only().layout,
        const PaneSplit(
          axis: SplitAxis.row,
          ratio: 0.5,
          first: PaneLeaf(1),
          second: PaneLeaf(100),
        ),
      );
      expect(only().focusedPaneId, 100);
      expect(only().terminal.viewWidth, 39);
      expect(state().opening, isFalse);
    });

    test('split down estimates half the rows', () async {
      boot();
      await tabs().split(SplitAxis.column);
      expect(local.opens.single, (80, 10)); // (24−1)~/2 − 1
    });

    test('D5: changes fired inside open() never make the pane a tab',
        () async {
      boot();
      local.afterOpen = (id) => local.replace(local.summaries.last);
      await tabs().split(SplitAxis.row);
      expect(state().tabs, hasLength(1));
      expect(only().paneOrder, [1, 100]);
    });

    test('the tab vanished while the pane was opening → own tab', () async {
      boot();
      local.openGate = Completer<void>();
      final split = tabs().split(SplitAxis.row);
      tabs().close(1);
      local.openGate!.complete();
      await split;
      expect(state().tabs.map((t) => t.id), [100]);
      expect(state().selectedId, 100);
    });

    test('limit / spawn failure: tree unchanged, toast, usable again',
        () async {
      boot();
      local.openError = const SessionLimitException(32);
      await tabs().split(SplitAxis.row);
      expect(only().paneOrder, [1]);
      expect(state().notice, isA<SessionLimitNotice>());
      expect(state().opening, isFalse);
    });

    test('no room (D4): no open, neutral notice; the other axis fits', () async {
      boot();
      tabs().reportPaneMetrics(
        const PaneMetrics(
          area: Size(300, 400),
          minPane: Size(176, 100),
          divider: 1,
        ),
      );
      await tabs().split(SplitAxis.row);
      expect(local.opens, isEmpty);
      expect(state().notice, isA<PaneNoRoomNotice>());
      await tabs().split(SplitAxis.column);
      expect(local.opens, hasLength(1));
    });

    test('close focuses the most recently used pane; the tab keeps its id '
        'when its first pane closes (D1, D8)', () async {
      boot();
      await tabs().split(SplitAxis.row); // 1 | 100
      tabs().focusPane(1);
      await tabs().split(SplitAxis.column); // (1 / 101) | 100
      expect(only().focusedPaneId, 101);
      tabs().closePane(101);
      expect(only().focusedPaneId, 1);
      tabs().closePane(1);
      expect(only().id, 1);
      expect(only().paneOrder, [100]);
      expect(only().focusedPaneId, 100);
      expect(local.closed, [101, 1]);
      tabs().closePane(100);
      expect(state().tabs, isEmpty);
    });

    test('pane exits: 0 removes it, non-zero keeps it until Enter (D7)',
        () async {
      boot();
      await tabs().split(SplitAxis.row);
      await tabs().split(SplitAxis.row); // 1 | 100 | 101
      local.views[101]!.end(0);
      await pumpEventQueue();
      expect(only().paneOrder, [1, 100]);
      local.views[100]!.end(2);
      await pumpEventQueue();
      expect(only().panes[100]!.exited, isTrue);
      only().panes[100]!.terminal.keyInput(TerminalKey.enter);
      expect(only().paneOrder, [1]);
    });

    test('only visible panes resize their sessions; unzoom re-sends (D10, '
        'D13)', () async {
      local.add(local.summary(2)); // a phone tab, not selected
      boot();
      await tabs().split(SplitAxis.row);
      final r1 = local.views[1]!.resizes;
      final r2 = local.views[2]!.resizes;
      TerminalTab only1() => state().tabs.firstWhere((t) => t.id == 1);
      expect(tabs().toggleZoom(), isTrue); // zooms 100
      final before = r1.length;
      only1().panes[1]!.terminal.resize(50, 20);
      expect(r1.length, before); // hidden by the zoom
      state().tabs.firstWhere((t) => t.id == 2).terminal.resize(60, 20);
      expect(r2, isEmpty); // not the selected tab
      expect(tabs().toggleZoom(), isFalse);
      expect(r1.last, (50, 20));
    });

    test('directional focus, unzooming first; no wrap (D9)', () async {
      boot();
      await tabs().split(SplitAxis.row);
      tabs().toggleZoom();
      expect(tabs().focusDirection(PaneDirection.left), isTrue);
      expect(only().focusedPaneId, 1);
      expect(only().zoomedPaneId, isNull);
      expect(tabs().focusDirection(PaneDirection.left), isFalse);
    });

    test('split while zoomed unzooms; focusing a hidden pane unzooms',
        () async {
      boot();
      await tabs().split(SplitAxis.row);
      tabs().toggleZoom();
      await tabs().split(SplitAxis.column);
      expect(only().zoomedPaneId, isNull);
      tabs().toggleZoom(); // zoom 101
      tabs().focusPane(1);
      expect(only().zoomedPaneId, isNull);
    });

    test('equalize; keyboard resize moves the nearest same-axis divider; '
        'pixel minimums clamp; stale paths are ignored (D4, D11, D12)',
        () async {
      boot();
      await tabs().split(SplitAxis.row);
      await tabs().split(SplitAxis.row); // 1 | (100 | 101)
      tabs().equalize();
      expect((only().layout as PaneSplit).ratio, closeTo(1 / 3, 1e-9));
      tabs().resizeFocused(PaneDirection.right); // 101 → split '1'
      expect(
        ((only().layout as PaneSplit).second as PaneSplit).ratio,
        closeTo(0.55, 1e-9),
      );
      tabs().resizeFocused(PaneDirection.down); // no column split: no-op
      tabs().reportPaneMetrics(
        const PaneMetrics(
          area: Size(1000, 600),
          minPane: Size(176, 100),
          divider: 1,
        ),
      );
      tabs().setRatio(1, '', 0.05);
      expect((only().layout as PaneSplit).ratio, closeTo(0.176, 1e-9));
      tabs().setRatio(1, '', 0.99); // second side holds two panes
      expect(
        (only().layout as PaneSplit).ratio,
        closeTo(1 - (2 * 176 + 1 + 1) / 1000, 1e-9),
      );
      tabs().equalizeAt(1, '1');
      expect(((only().layout as PaneSplit).second as PaneSplit).ratio, 0.5);
      tabs().setRatio(1, '0', 0.3); // a leaf: ignored
      tabs().setRatio(99, '', 0.3); // no such tab: ignored
    });
  });
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/terminal/terminal_tabs_panes_test.dart`
Expected: FAIL — `split`, `PaneMetrics`, `PaneNoRoomNotice`… undefined.

- [ ] **Step 3: Implement**

`terminal_tabs.dart` — add `import 'dart:ui' show Size;` and `import '../ui/theme/shellx_desktop_theme.dart' show ShellxSizes;` (or inline `0.05` with a comment pointing at UI-A3 §1.2 if importing UI code from `terminal/` is not done elsewhere — check `sidebar_workspaces.dart`; prefer the inline constant `const double _resizeStep = 0.05; // UI-A3 §1.2 paneResizeStep` to keep `terminal/` free of `ui/` imports).

Next to the other notices:

```dart
/// D4: the focused pane is too small to hold two (neutral toast).
final class PaneNoRoomNotice extends TabNotice {
  const PaneNoRoomNotice();
}

/// What the pane area looks like (D4), reported by the terminal pane on
/// every layout: the tab list needs pixels to refuse a split or clamp a
/// divider.
@immutable
final class PaneMetrics {
  const PaneMetrics({
    required this.area,
    required this.minPane,
    required this.divider,
  });

  /// The whole terminal area of a tab.
  final Size area;

  /// 20 columns × 5 rows of the current font, plus padding and the pane
  /// header (UI-A3 §1.2).
  final Size minPane;
  final double divider;
}
```

In `TerminalTabs` add `PaneMetrics? _metrics;` and:

```dart
  /// Stores the size for later decisions only: safe during layout.
  void reportPaneMetrics(PaneMetrics metrics) => _metrics = metrics;

  /// ⌘D / ⌘⇧D (D3): the selected tab's focused pane, in its directory
  /// (D17), at half its grid; the new pane is focused.
  Future<void> split(SplitAxis axis) async {
    final tab = state.selected;
    if (tab == null || state.opening) return;
    final target = tab.focusedPaneId;
    if (!_roomToSplit(tab, target, axis)) {
      _set(notice: const PaneNoRoomNotice());
      return;
    }
    final pane = tab.panes[target]!;
    final grid = _halfGrid(pane, axis);
    _set(opening: true);
    _awaitingOpen = true;
    try {
      final id = await _local.open(
        cols: grid.cols,
        rows: grid.rows,
        cwd: pane.cwd,
      );
      if (!ref.mounted) return;
      _awaitingOpen = false;
      _adoptPane(id, tabId: tab.id, target: target, axis: axis, size: grid);
    } on SessionLimitException catch (error) {
      if (ref.mounted) _set(notice: SessionLimitNotice(error.max));
    } on SpawnFailedException catch (error) {
      if (ref.mounted) {
        _set(notice: SpawnFailedNotice(spawnFailureOf(error.message)));
      }
    } finally {
      _awaitingOpen = false;
      if (ref.mounted) _set(opening: false);
    }
  }

  /// A click in a pane, a jump to a notification: [sessionId]'s tab is
  /// selected and the pane focused; a zoom that hides it ends (D10).
  void focusPane(int sessionId) {
    final tab = state.tabOfSession(sessionId);
    if (tab == null) return;
    final unzoom = tab.zoomedPaneId != null && tab.zoomedPaneId != sessionId;
    if (tab.focusedPaneId != sessionId || unzoom) {
      _replaceTab(
        tab.copyWith(
          focusedPaneId: sessionId,
          paneHistory: [
            sessionId,
            ...tab.paneHistory.where((id) => id != sessionId),
          ],
          zoomedPaneId: unzoom ? null : tab.zoomedPaneId,
        ),
      );
    }
    if (state.selectedId != tab.id) {
      _set(selectedId: tab.id);
    } else if (unzoom) {
      _visibleChanged();
    }
  }

  /// ⌘⌥arrows (D9). False when there is no pane that way.
  bool focusDirection(PaneDirection direction) {
    final tab = state.selected;
    if (tab == null || !tab.isSplit) return false;
    final next = neighbourPane(
      tab.layout,
      tab.focusedPaneId,
      direction,
      mru: tab.paneHistory,
    );
    if (next == null) return false;
    if (tab.zoomedPaneId != null) {
      _replaceTab(tab.copyWith(zoomedPaneId: null));
      _visibleChanged();
    }
    focusPane(next);
    return true;
  }

  /// ⌘⇧↩ (D10): the new state; a one-pane tab is never zoomed.
  bool toggleZoom() {
    final tab = state.selected;
    if (tab == null || !tab.isSplit) return false;
    final zoom = tab.zoomedPaneId == null;
    _replaceTab(tab.copyWith(zoomedPaneId: zoom ? tab.focusedPaneId : null));
    if (!zoom) _visibleChanged();
    return zoom;
  }

  /// ⌘⌃= (D11).
  void equalize() {
    final tab = state.selected;
    if (tab == null || !tab.isSplit) return;
    _replaceTab(tab.copyWith(layout: equalized(tab.layout)));
  }

  /// Double-click on a divider (D11).
  void equalizeAt(int tabId, PanePath path) {
    final tab = _tab(tabId);
    if (tab == null || nodeAt(tab.layout, path) is! PaneSplit) return;
    _replaceTab(tab.copyWith(layout: equalizedAt(tab.layout, path)));
  }

  /// A divider drag (D14): ignored when [path] is no longer a split (a
  /// pane closed mid-drag); clamped to the pixel minimums (D4).
  void setRatio(int tabId, PanePath path, double ratio) {
    final tab = _tab(tabId);
    if (tab == null || nodeAt(tab.layout, path) is! PaneSplit) return;
    _replaceTab(
      tab.copyWith(
        layout: withRatio(tab.layout, path, _clampForPixels(tab, path, ratio)),
      ),
    );
  }

  /// ⌘⌃arrows (D12): the nearest split of the arrow's axis above the
  /// focused pane moves 5 % the arrow's way.
  void resizeFocused(PaneDirection direction) {
    final tab = state.selected;
    if (tab == null || !tab.isSplit) return;
    final sideways =
        direction == PaneDirection.left || direction == PaneDirection.right;
    final path = ancestorSplit(
      tab.layout,
      tab.focusedPaneId,
      sideways ? SplitAxis.row : SplitAxis.column,
    );
    if (path == null) return;
    final split = nodeAt(tab.layout, path)! as PaneSplit;
    final forward =
        direction == PaneDirection.right || direction == PaneDirection.down;
    setRatio(tab.id, path, split.ratio + (forward ? _resizeStep : -_resizeStep));
  }

  // ---- pane internals ---------------------------------------------------

  void _adoptPane(
    int id, {
    required int tabId,
    required int target,
    required SplitAxis axis,
    required TerminalGrid size,
  }) {
    final summary = _local.sessions.where((s) => s.id == id).firstOrNull;
    final tab = _tab(tabId);
    if (summary == null || tab == null) {
      // Ended already, or its tab went while it opened: the normal rules
      // apply (a tab of its own, selected).
      _sync();
      if (state.tabOfSession(id) case final own?) _set(selectedId: own.id);
      return;
    }
    final pane = _attach(summary, size: size);
    if (pane == null) return;
    final at = tab.panes.containsKey(target) ? target : tab.paneOrder.first;
    final wasZoomed = tab.zoomedPaneId != null;
    _replaceTab(
      tab.copyWith(
        layout: splitPane(tab.layout, at, id, axis),
        panes: {...tab.panes, id: pane},
        focusedPaneId: id,
        zoomedPaneId: null,
        paneHistory: [id, ...tab.paneHistory],
      ),
    );
    _sync();
    if (state.selectedId != tabId) {
      _set(selectedId: tabId);
    } else if (wasZoomed) {
      _visibleChanged();
    }
  }

  /// D13 estimate; the real grid follows at the next layout.
  TerminalGrid _halfGrid(PaneSession pane, SplitAxis axis) {
    final cols = pane.terminal.viewWidth;
    final rows = pane.terminal.viewHeight;
    return axis == SplitAxis.row
        ? (cols: max(1, (cols - 1) ~/ 2), rows: max(1, rows - 1))
        : (cols: cols, rows: max(1, (rows - 1) ~/ 2 - 1));
  }

  /// D4: room for two minimum panes and the divider.
  bool _roomToSplit(TerminalTab tab, int target, SplitAxis axis) {
    final m = _metrics;
    if (m == null) return true;
    final unit = paneRects(tab.layout)[target];
    if (unit == null) return false;
    final w = unit.width * m.area.width;
    final h = unit.height * m.area.height;
    return axis == SplitAxis.row
        ? w >= 2 * m.minPane.width + m.divider && h >= m.minPane.height
        : h >= 2 * m.minPane.height + m.divider && w >= m.minPane.width;
  }

  /// D4: each side keeps its panes at their minimum along the axis.
  double _clampForPixels(TerminalTab tab, PanePath path, double ratio) {
    final m = _metrics;
    final node = nodeAt(tab.layout, path);
    final rect = splitRect(tab.layout, path);
    if (m == null || node is! PaneSplit || rect == null) {
      return clampRatio(ratio);
    }
    final row = node.axis == SplitAxis.row;
    final extent = row ? rect.width * m.area.width : rect.height * m.area.height;
    final minPane = row ? m.minPane.width : m.minPane.height;
    double need(PaneNode side) {
      final n = paneSpan(side, node.axis);
      return n * minPane + (n - 1) * m.divider;
    }

    final lo = need(node.first) / extent;
    final hi = 1 - (need(node.second) + m.divider) / extent;
    if (lo > hi) return node.ratio; // no room to move at all
    return clampRatio(ratio.clamp(lo, hi).toDouble());
  }
```

with `const double _resizeStep = 0.05; // UI-A3 §1.2 paneResizeStep` at the top of the file. (`max` comes from the existing `dart:math` import.)

`terminal_overlays.dart` (toast): add `PaneNoRoomNotice() => l10n.paneSplitNoRoom,` to `_text`, and extend the neutral test with `|| widget.notice is PaneNoRoomNotice` (keep whatever A4 added there, e.g. `NoUnreadNotice`).

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/terminal/terminal_tabs_panes_test.dart`
Expected: PASS. Then the whole suite: `PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test` — PASS.

- [ ] **Step 5: Format, analyze, commit**

```bash
cd apps/desktop && ~/fvm/versions/3.41.4/bin/dart format --set-exit-if-changed lib/src/terminal lib/src/ui/terminal/terminal_overlays.dart test/terminal && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter analyze
cd ../.. && git add apps/desktop/lib/src/terminal/terminal_tabs.dart apps/desktop/lib/src/ui/terminal/terminal_overlays.dart apps/desktop/test/terminal/terminal_tabs_panes_test.dart
git commit -m "feat(desktop): pane operations — split in cwd, focus by direction, close with MRU focus, zoom, equalize, resize; only visible panes size their sessions (A3 D3-D13)"
```

---

### Task 6: Desktop — `PaneTreeView`: layout, dividers, pane header, focus outline, zoom (after A4 merge)

**Files:**
- Create: `apps/desktop/lib/src/ui/terminal/pane_tree_view.dart`
- Modify: `apps/desktop/lib/src/ui/terminal/terminal_pane.dart` (move `_TabTerminal` → `PaneTerminal` and `_DriverPillSlot` → `DriverPillSlot` into the new file; `IndexedStack` of `PaneTreeView`; `PaneMetrics`; drop the area-level ring and pill)
- Modify: `apps/desktop/lib/src/ui/terminal/close_tab.dart` (`closePaneWithConfirm`)
- Modify: `apps/desktop/lib/src/ui/terminal/terminal_workspace_page.dart` (focus follows the focused pane; `onClosePane`)
- Create: `apps/desktop/test/ui/pane_tree_view_test.dart`

**Interfaces:**
- Consumes: Task 5 (`split`, `focusPane`, `setRatio`, `equalizeAt`, `toggleZoom`, `reportPaneMetrics`, `PaneMetrics`); Task 3 sizes and strings; A4 `AttentionRing({required bool visible})` (`Key('pane.ring')`), `tabAttentionProvider` (`hasUnread`); A1 `DriverPill`, `ShellxScrollbar`, `TerminalColors`.
- Produces:
  - `class PaneTreeView extends ConsumerStatefulWidget { const PaneTreeView({super.key, required TerminalTab tab, required bool selected, required FocusNode terminalFocus, required TerminalStyle style, required Map<ShortcutActivator, Intent>? shortcuts, required ScrollController Function(int sessionId) scrollFor, required void Function(int sessionId) onClosePane, Set<int> ringed = const {}, bool hiddenUnread = false, bool toastShowing = false}); }`
  - `class PaneTerminal extends StatelessWidget` (the old `_TabTerminal` body without its `Semantics`), `class DriverPillSlot` (the old `_DriverPillSlot`, unchanged)
  - Keys: `Key('pane.header.<id>')`, `Key('pane.close.<id>')`, `Key('pane.focusOutline')`, `Key('pane.divider.<path>')` (root `'pane.divider.'`), `Key('pane.zoomed')`
  - `TerminalPane({…, required void Function(int sessionId) onClosePane})`
  - `Future<void> closePaneWithConfirm({required TerminalTabs tabs, required WindowRouter router, required AppLocalizations l10n, required TerminalTab tab, required int paneId})`

- [ ] **Step 1: Write the failing tests**

Create `apps/desktop/test/ui/pane_tree_view_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_desktop/src/terminal/pane_layout.dart';
import 'package:shellx_desktop/src/terminal/terminal_tabs.dart';
import 'package:shellx_desktop/src/ui/terminal/terminal_workspace_page.dart';
import 'package:xterm/xterm.dart';

import '../support/fake_local_sessions.dart';
import 'sidebar_test_harness.dart';

TerminalTabs panes() => container.read(terminalTabsProvider.notifier);
TerminalTab only() => tabs().tabs.single;

TerminalView viewOf(WidgetTester tester, int sessionId) => tester
    .widgetList<TerminalView>(find.byType(TerminalView))
    .firstWhere((v) => identical(v.terminal, only().panes[sessionId]!.terminal));

Future<void> splitRight(WidgetTester tester) async {
  await panes().split(SplitAxis.row);
  await tester.pump();
  await tester.pump();
}

void main() {
  setUp(() {
    local = FakeLocalSessions();
    local.add(local.summary(1, origin: SessionOrigin.desktop));
  });

  testSidebar('a one-pane tab has no header, outline or divider', (t) async {
    final semantics = t.ensureSemantics();
    addTearDown(semantics.dispose);
    await pumpSidebar(t);
    expect(find.byKey(const Key('pane.header.1')), findsNothing);
    expect(find.byKey(const Key('pane.focusOutline')), findsNothing);
    expect(find.byKey(const Key('pane.divider.')), findsNothing);
    expect(find.bySemanticsLabel('Terminal zsh 1'), findsOneWidget);
  });

  testSidebar('split right: two terminals, headers, outline on the new pane, '
      'keyboard in the new pane', (t) async {
    final semantics = t.ensureSemantics();
    addTearDown(semantics.dispose);
    await pumpSidebar(t);
    await splitRight(t);
    expect(find.byType(TerminalView), findsNWidgets(2));
    expect(find.byKey(const Key('pane.header.1')), findsOneWidget);
    expect(find.byKey(const Key('pane.header.100')), findsOneWidget);
    final outline = t.getRect(find.byKey(const Key('pane.focusOutline')));
    final right = t.getRect(find.byKey(const Key('pane.header.100')));
    expect(outline.left, right.left);
    final page = t.state<TerminalWorkspacePageState>(
      find.byType(TerminalWorkspacePage),
    );
    expect(viewOf(t, 100).focusNode, same(page.terminalFocus));
    expect(page.terminalFocus.hasFocus, isTrue);
    expect(find.bySemanticsLabel('Pane 2 of 2 — zsh 2'), findsOneWidget);
    // Each pane told its own session its own grid (P5).
    expect(local.views[1]!.resizes.last.$1, lessThan(80));
    expect(local.views[100]!.resizes, isNotEmpty);
  });

  testSidebar('a click focuses the pane under the pointer', (t) async {
    await pumpSidebar(t);
    await splitRight(t);
    await t.tap(find.byKey(const Key('pane.header.1')));
    await t.pump();
    await t.pump();
    expect(only().focusedPaneId, 1);
    expect(viewOf(t, 1).focusNode, isNotNull);
  });

  testSidebar('dragging the divider resizes both sessions; double-click '
      'equalizes', (t) async {
    await pumpSidebar(t);
    await splitRight(t);
    final before1 = local.views[1]!.resizes.length;
    await t.drag(find.byKey(const Key('pane.divider.')), const Offset(-120, 0));
    await t.pump();
    expect((only().layout as PaneSplit).ratio, lessThan(0.5));
    expect(local.views[1]!.resizes.length, greaterThan(before1));
    await t.tap(find.byKey(const Key('pane.divider.')));
    await t.pump(kDoubleTapMinTime);
    await t.tap(find.byKey(const Key('pane.divider.')));
    // Not pumpAndSettle: the terminal cursor keeps scheduling frames.
    await t.pump(kDoubleTapTimeout);
    expect((only().layout as PaneSplit).ratio, 0.5);
  });

  testSidebar('zoom shows only the focused pane with its indicator', (t) async {
    await pumpSidebar(t);
    await splitRight(t);
    panes().toggleZoom();
    await t.pump();
    expect(find.byKey(const Key('pane.header.1')), findsNothing); // offstage
    expect(find.byKey(const Key('pane.zoomed')), findsOneWidget);
    expect(find.text('Zoomed · 2/2'), findsOneWidget);
    expect(find.byKey(const Key('pane.focusOutline')), findsNothing);
  });

  testSidebar('the pane × closes that pane (no command running)', (t) async {
    await pumpSidebar(t);
    await splitRight(t);
    await t.tap(find.byKey(const Key('pane.close.100')));
    await t.pump();
    expect(only().paneOrder, [1]);
    expect(find.byKey(const Key('pane.header.1')), findsNothing);
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/ui/pane_tree_view_test.dart`
Expected: FAIL — no `pane.header.*` keys (the tab still renders one `_TabTerminal` with the focused pane only).

- [ ] **Step 3: Implement**

`close_tab.dart` — add:

```dart
/// ⌘W on a split tab, the pane ×, "Đóng pane" (D6, D28): asks while that
/// pane runs a command. A one-pane tab goes through [closeTabWithConfirm]
/// (the A1 dialog, word for word).
Future<void> closePaneWithConfirm({
  required TerminalTabs tabs,
  required WindowRouter router,
  required AppLocalizations l10n,
  required TerminalTab tab,
  required int paneId,
}) async {
  final pane = tab.panes[paneId];
  if (pane == null) return;
  if (!tab.isSplit) {
    return closeTabWithConfirm(tabs: tabs, router: router, l10n: l10n, tab: tab);
  }
  if (tabs.needsPaneCloseConfirm(paneId)) {
    final ok = await router.confirm(
      ConfirmRequest(
        title: l10n.confirmCloseRunningTitle(pane.automaticLabel),
        body: l10n.confirmCloseRunningPaneBody,
        confirmLabel: l10n.confirmCloseRunningPaneAction,
      ),
    );
    if (!ok) return;
  }
  tabs.closePane(paneId);
}
```

Create `apps/desktop/lib/src/ui/terminal/pane_tree_view.dart`:

```dart
import 'package:flutter/gestures.dart' show kMiddleMouseButton;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:xterm/xterm.dart';

import '../../../l10n/app_localizations.dart';
import '../../terminal/pane_layout.dart';
import '../../terminal/terminal_tabs.dart';
import '../theme/shellx_desktop_theme.dart';
import '../theme/terminal_colors.dart';
import 'attention_marks.dart' show AttentionRing;
import 'shellx_menu.dart';
import 'shortcut_labels.dart';
import 'terminal_overlays.dart' show DriverPill, ShellxScrollbar, kPhoneIcon;
import 'terminal_shortcuts.dart';

/// One tab's panes (A3 P1, UI-A3 §2). A one-pane tab is exactly A4's single
/// terminal: no header, outline or divider (criterion 13).
class PaneTreeView extends ConsumerStatefulWidget {
  const PaneTreeView({
    super.key,
    required this.tab,
    required this.selected,
    required this.terminalFocus,
    required this.style,
    required this.shortcuts,
    required this.scrollFor,
    required this.onClosePane,
    this.ringed = const {},
    this.hiddenUnread = false,
    this.toastShowing = false,
  });

  final TerminalTab tab;

  /// The tab is the selected one: its focused pane gets [terminalFocus].
  final bool selected;
  final FocusNode terminalFocus;
  final TerminalStyle style;
  final Map<ShortcutActivator, Intent>? shortcuts;
  final ScrollController Function(int sessionId) scrollFor;
  final void Function(int sessionId) onClosePane;

  /// Panes drawn with A4's ring (D18).
  final Set<int> ringed;

  /// A pane hidden by the zoom has unread notifications (D18).
  final bool hiddenUnread;

  /// The toast owns the bottom of the area: driver pills stay on top.
  final bool toastShowing;

  @override
  ConsumerState<PaneTreeView> createState() => _PaneTreeViewState();
}

class _PaneTreeViewState extends ConsumerState<PaneTreeView> {
  /// One key per pane, so a pane's TerminalView keeps its state (scroll,
  /// focus, IME) when a split moves it into a new subtree.
  final _keys = <int, GlobalKey>{};

  GlobalKey _keyFor(int id) => _keys.putIfAbsent(id, GlobalKey.new);

  TerminalTabs get _tabs => ref.read(terminalTabsProvider.notifier);

  @override
  Widget build(BuildContext context) {
    final tab = widget.tab;
    _keys.removeWhere((id, _) => !tab.panes.containsKey(id));
    if (!tab.isSplit) return _pane(tab.focusedPaneId, header: false);
    final zoomed = tab.zoomedPaneId;
    final tree = _node(tab.layout, '', hide: zoomed);
    if (zoomed == null) return tree;
    // D10: the other panes keep their tree rectangles (so their grids stay
    // right) but are neither painted nor hit-tested nor sized to sessions.
    return Stack(
      fit: StackFit.expand,
      children: [
        Offstage(child: tree),
        _pane(zoomed, header: true),
      ],
    );
  }

  Widget _node(PaneNode node, PanePath path, {int? hide}) => switch (node) {
    PaneLeaf(:final sessionId) =>
      sessionId == hide
          ? const SizedBox.expand()
          : _pane(sessionId, header: true),
    final PaneSplit s => _SplitBox(
      key: ValueKey('split.$path'),
      split: s,
      path: path,
      onRatio: (ratio) => _tabs.setRatio(widget.tab.id, path, ratio),
      onEqualize: () => _tabs.equalizeAt(widget.tab.id, path),
      first: _node(s.first, '${path}0', hide: hide),
      second: _node(s.second, '${path}1', hide: hide),
    ),
  };

  Widget _pane(int id, {required bool header}) {
    final l10n = AppLocalizations.of(context);
    final tab = widget.tab;
    final pane = tab.panes[id]!;
    final focused = id == tab.focusedPaneId;
    final ringed = widget.ringed.contains(id);
    final zoomed = tab.zoomedPaneId == id;
    final number = tab.paneNumber(id);
    final label = !tab.isSplit
        ? (ringed
              ? l10n.terminalPaneUnreadLabel(tab.label)
              : l10n.terminalPaneLabel(tab.label))
        : (ringed
              ? l10n.paneRegionUnreadLabel(number, tab.paneCount, pane.automaticLabel)
              : l10n.paneRegionLabel(number, tab.paneCount, pane.automaticLabel));
    final phoneDrives = !pane.exited && pane.driver == DriverSide.phone;
    return KeyedSubtree(
      key: _keyFor(id),
      child: Listener(
        // Before xterm handles the press: the model focuses this pane, the
        // workspace then hands it the terminal focus (D2, UI-A3 §6).
        onPointerDown: (_) {
          if (!focused || !widget.selected) _tabs.focusPane(id);
        },
        child: Semantics(
          container: true,
          label: label,
          child: Stack(
            children: [
              Positioned.fill(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (header)
                      _PaneHeader(
                        key: Key('pane.header.$id'),
                        pane: pane,
                        focused: focused,
                        unread: ringed,
                        zoomed: zoomed
                            ? l10n.paneZoomedIndicator(number, tab.paneCount)
                            : null,
                        hiddenUnread: zoomed && widget.hiddenUnread,
                        closeTooltip: l10n.paneCloseTooltip(
                          closePaneShortcutLabel(),
                        ),
                        onClose: () => widget.onClosePane(id),
                        onToggleZoom: () {
                          _tabs.focusPane(id);
                          _tabs.toggleZoom();
                        },
                      ),
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, constraints) => Stack(
                          children: [
                            Positioned.fill(
                              child: PaneTerminal(
                                pane: pane,
                                scrollController: widget.scrollFor(id),
                                focusNode: widget.selected && focused
                                    ? widget.terminalFocus
                                    : null,
                                style: widget.style,
                                shortcuts: widget.shortcuts,
                                onMenu: (at) => _menu(id, at),
                              ),
                            ),
                            Positioned.fill(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: ShellxSpace.s8,
                                  horizontal: ShellxSpace.s12,
                                ),
                                child: DriverPillSlot(
                                  terminal: pane.terminal,
                                  cellHeight: measureTerminalCell(
                                    widget.style,
                                    MediaQuery.textScalerOf(context),
                                  ).height,
                                  canMoveDown: !widget.toastShowing,
                                  child: phoneDrives
                                      ? DriverPill(
                                          compact: constraints.maxWidth <
                                              ShellxSizes.pillCompactBelow,
                                        )
                                      : const SizedBox.shrink(),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (tab.isSplit && focused && tab.zoomedPaneId == null)
                const Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      key: Key('pane.focusOutline'),
                      decoration: BoxDecoration(
                        border: Border.fromBorderSide(
                          BorderSide(
                            color: ShellxDesktopColors.accent,
                            width: ShellxSizes.paneFocusOutline,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              // UI-A3 §2.5: A4's ring, per pane (one pane: A4's rect).
              Positioned.fill(child: AttentionRing(visible: ringed)),
            ],
          ),
        ),
      ),
    );
  }

  /// A1 ruling I6 entries; the pane under the pointer is focused first
  /// (D21) so the window actions act on it.
  Future<void> _menu(int id, Offset at) async {
    _tabs.focusPane(id);
    final l10n = AppLocalizations.of(context);
    final pane = widget.tab.panes[id];
    if (pane == null) return;
    final intent = await showShellxMenu<Intent>(
      context: context,
      at: at,
      entries: [
        ShellxMenuEntry(
          key: const Key('menu.copy'),
          value: const CopySelectionIntent(),
          label: l10n.terminalCopy,
          shortcut: copyShortcutLabel(),
          enabled: pane.selection.selection != null,
        ),
        ShellxMenuEntry(
          key: const Key('menu.paste'),
          value: const PasteClipboardIntent(),
          label: l10n.terminalPaste,
          shortcut: pasteShortcutLabel(),
        ),
        ShellxMenuEntry(
          key: const Key('menu.selectAll'),
          value: const SelectAllIntent(fromMenu: true),
          label: l10n.terminalSelectAll,
          shortcut: selectAllShortcutLabel(),
        ),
      ],
    );
    if (intent == null || !mounted) return;
    Actions.maybeInvoke(context, intent);
    widget.terminalFocus.requestFocus();
  }
}

/// UI-A3 §2.2: the 1 px line, a 6 px hit area centred on it.
class _SplitBox extends StatelessWidget {
  const _SplitBox({
    super.key,
    required this.split,
    required this.path,
    required this.onRatio,
    required this.onEqualize,
    required this.first,
    required this.second,
  });

  final PaneSplit split;
  final PanePath path;
  final ValueChanged<double> onRatio;
  final VoidCallback onEqualize;
  final Widget first;
  final Widget second;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      final row = split.axis == SplitAxis.row;
      final extent = row ? c.maxWidth : c.maxHeight;
      const line = ShellxSizes.paneDivider;
      const hit = ShellxSizes.paneDividerHit;
      final a = ((extent - line) * split.ratio).roundToDouble();
      final hitStart = a + line / 2 - hit / 2;
      void drag(Offset global) {
        final box = context.findRenderObject()! as RenderBox;
        final local = box.globalToLocal(global);
        onRatio((row ? local.dx : local.dy) / extent);
      }

      final divider = _PaneDivider(
        key: Key('pane.divider.$path'),
        axis: split.axis,
        ratio: split.ratio,
        onDrag: drag,
        onEqualize: onEqualize,
        onStep: (delta) => onRatio(split.ratio + delta),
      );
      return Stack(
        children: row
            ? [
                Positioned(left: 0, top: 0, bottom: 0, width: a, child: first),
                Positioned(
                  left: a + line,
                  top: 0,
                  right: 0,
                  bottom: 0,
                  child: second,
                ),
                Positioned(
                  left: hitStart,
                  top: 0,
                  bottom: 0,
                  width: hit,
                  child: divider,
                ),
              ]
            : [
                Positioned(left: 0, top: 0, right: 0, height: a, child: first),
                Positioned(
                  left: 0,
                  top: a + line,
                  right: 0,
                  bottom: 0,
                  child: second,
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  top: hitStart,
                  height: hit,
                  child: divider,
                ),
              ],
      );
    },
  );
}

class _PaneDivider extends StatefulWidget {
  const _PaneDivider({
    super.key,
    required this.axis,
    required this.ratio,
    required this.onDrag,
    required this.onEqualize,
    required this.onStep,
  });

  final SplitAxis axis;
  final double ratio;
  final ValueChanged<Offset> onDrag;
  final VoidCallback onEqualize;
  final ValueChanged<double> onStep;

  @override
  State<_PaneDivider> createState() => _PaneDividerState();
}

class _PaneDividerState extends State<_PaneDivider> {
  bool _hovered = false;
  bool _dragging = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final row = widget.axis == SplitAxis.row;
    final active = _hovered || _dragging;
    return Semantics(
      slider: true,
      label: l10n.paneDividerLabel,
      value: '${(widget.ratio * 100).round()} %',
      onIncrease: () => widget.onStep(ShellxSizes.paneResizeStep),
      onDecrease: () => widget.onStep(-ShellxSizes.paneResizeStep),
      child: MouseRegion(
        cursor: row
            ? SystemMouseCursors.resizeColumn
            : SystemMouseCursors.resizeRow,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanStart: (_) => setState(() => _dragging = true),
          onPanUpdate: (d) => widget.onDrag(d.globalPosition),
          onPanEnd: (_) => setState(() => _dragging = false),
          onPanCancel: () => setState(() => _dragging = false),
          onDoubleTap: widget.onEqualize,
          child: Center(
            child: AnimatedContainer(
              duration: ShellxMotion.of(context, ShellxMotion.fast),
              width: row ? ShellxSizes.paneDivider : double.infinity,
              height: row ? double.infinity : ShellxSizes.paneDivider,
              color: active
                  ? ShellxDesktopColors.accent
                  : ShellxDesktopColors.line,
            ),
          ),
        ),
      ),
    );
  }
}

/// UI-A3 §2.1: 22 px, only when a tab has panes.
class _PaneHeader extends StatefulWidget {
  const _PaneHeader({
    super.key,
    required this.pane,
    required this.focused,
    required this.unread,
    required this.zoomed,
    required this.hiddenUnread,
    required this.closeTooltip,
    required this.onClose,
    required this.onToggleZoom,
  });

  final PaneSession pane;
  final bool focused;
  final bool unread;

  /// "Zoomed · 2/3" while this pane is zoomed.
  final String? zoomed;
  final bool hiddenUnread;
  final String closeTooltip;
  final VoidCallback onClose;
  final VoidCallback onToggleZoom;

  @override
  State<_PaneHeader> createState() => _PaneHeaderState();
}

class _PaneHeaderState extends State<_PaneHeader> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final pane = widget.pane;
    final focused = widget.focused;
    final scaler = MediaQuery.textScalerOf(context);
    final dot = pane.exited
        ? ShellxDesktopColors.err
        : pane.runningCommand
        ? ShellxDesktopColors.accent
        : ShellxDesktopColors.ok;
    return Listener(
      onPointerDown: (event) {
        if (event.buttons == kMiddleMouseButton) widget.onClose();
      },
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onDoubleTap: widget.onToggleZoom,
          child: Container(
            height: ShellxSizes.paneHeaderFor(scaler),
            color: focused
                ? ShellxDesktopColors.rowSelected
                : _hovered
                ? ShellxDesktopColors.rowHover
                : ShellxDesktopColors.bgSidebar,
            padding: const EdgeInsets.symmetric(
              horizontal: ShellxSizes.paneHeaderPadH,
            ),
            child: ExcludeSemantics(
              child: Row(
                children: [
                  SizedBox(
                    width: 12,
                    child: Center(
                      child: Container(
                        width: ShellxSizes.paneHeaderDot,
                        height: ShellxSizes.paneHeaderDot,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: pane.exited ? null : dot,
                          border: pane.exited
                              ? Border.all(color: dot, width: 1.5)
                              : null,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: ShellxSpace.s6),
                  Expanded(
                    child: Text(
                      pane.automaticLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: ShellxText.small.copyWith(
                        color: focused && !pane.exited
                            ? ShellxDesktopColors.textPrimary
                            : ShellxDesktopColors.textSecondary,
                      ),
                    ),
                  ),
                  if (pane.origin == SessionOrigin.phone) ...[
                    const SizedBox(width: ShellxSpace.s4),
                    const Icon(
                      kPhoneIcon,
                      size: 12,
                      color: ShellxDesktopColors.textSecondary,
                    ),
                  ],
                  if (pane.phoneAttached) ...[
                    const SizedBox(width: ShellxSpace.s4),
                    Icon(
                      Icons.visibility_outlined,
                      size: 12,
                      color: pane.driver == DriverSide.phone
                          ? ShellxDesktopColors.warn
                          : ShellxDesktopColors.accent,
                    ),
                  ],
                  if (widget.unread) ...[
                    const SizedBox(width: ShellxSpace.s4),
                    const _Dot(),
                  ],
                  if (widget.zoomed case final zoomed?) ...[
                    const SizedBox(width: ShellxSpace.s4),
                    GestureDetector(
                      key: const Key('pane.zoomed'),
                      onTap: widget.onToggleZoom,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (widget.hiddenUnread) ...[
                            const _Dot(),
                            const SizedBox(width: ShellxSpace.s4),
                          ],
                          Text(
                            zoomed,
                            style: ShellxText.caption.copyWith(
                              color: ShellxDesktopColors.accent,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(width: ShellxSpace.s4),
                  Visibility(
                    visible: focused || _hovered,
                    maintainSize: true,
                    maintainAnimation: true,
                    maintainState: true,
                    child: Tooltip(
                      message: widget.closeTooltip,
                      excludeFromSemantics: true,
                      child: _HeaderClose(
                        key: Key('pane.close.${pane.id}'),
                        onPressed: widget.onClose,
                      ),
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

class _Dot extends StatelessWidget {
  const _Dot();

  @override
  Widget build(BuildContext context) => Container(
    width: ShellxSizes.paneHeaderDot,
    height: ShellxSizes.paneHeaderDot,
    decoration: const BoxDecoration(
      shape: BoxShape.circle,
      color: ShellxDesktopColors.accent,
    ),
  );
}

class _HeaderClose extends StatefulWidget {
  const _HeaderClose({super.key, required this.onPressed});
  final VoidCallback onPressed;

  @override
  State<_HeaderClose> createState() => _HeaderCloseState();
}

class _HeaderCloseState extends State<_HeaderClose> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) => MouseRegion(
    onEnter: (_) => setState(() => _hovered = true),
    onExit: (_) => setState(() => _hovered = false),
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onPressed,
      child: SizedBox.square(
        dimension: ShellxSizes.paneHeader,
        child: Center(
          child: Container(
            width: ShellxSizes.paneHeaderClose,
            height: ShellxSizes.paneHeaderClose,
            decoration: BoxDecoration(
              color: _hovered ? ShellxDesktopColors.rowPressed : null,
              borderRadius: BorderRadius.circular(ShellxRadius.r4),
            ),
            child: Icon(
              Icons.close,
              size: 12,
              color: _hovered
                  ? ShellxDesktopColors.textPrimary
                  : ShellxDesktopColors.textSecondary,
            ),
          ),
        ),
      ),
    ),
  );
}
```

Then **move** (cut, unchanged bodies) from `terminal_pane.dart` into `pane_tree_view.dart`:
- `_TabTerminal` → `PaneTerminal`, with the constructor `const PaneTerminal({super.key, required PaneSession pane, required ScrollController scrollController, required FocusNode? focusNode, required TerminalStyle style, required Map<ShortcutActivator, Intent>? shortcuts, required void Function(Offset globalPosition) onMenu})`; its `build` is the old one **without** the outer `Semantics` (the pane carries it) and with `onSecondaryTapUp: (details, _) => onMenu(details.globalPosition)`; `tab.terminal`/`tab.selection` become `pane.terminal`/`pane.selection`; its old `_menu` is deleted (now `_PaneTreeViewState._menu`).
- `_DriverPillSlot`/`_DriverPillSlotState` → `DriverPillSlot`/`_DriverPillSlotState` (public widget, body unchanged).

Add `import '../../terminal/terminal_style.dart';` for `measureTerminalCell`. The `terminal_overlays.dart show …` import is indicative: import `DriverPill`, `ShellxScrollbar` and `kPhoneIcon` from wherever `terminal_pane.dart` and `session_tab_row.dart` import them today, and use the theme's real token names (`ShellxRadius.r4`, `ShellxSpace.s6`, `ShellxMotion.fast`, `ShellxSizes.pillCompactBelow`) — the analyzer tells you at once if one differs.

`terminal_pane.dart`:
- Add `required this.onClosePane` (`final void Function(int sessionId) onClosePane;`).
- `_dropClosed`: `final ids = {for (final tab in tabs) ...tab.panes.keys};`.
- In the `LayoutBuilder`, right after `if (grid != null) tabs.reportGrid(grid);`:

```dart
                final scaler = MediaQuery.textScalerOf(context);
                final cell = measureTerminalCell(style, scaler);
                // D4: 20 × 5 cells + padding + the pane header.
                tabs.reportPaneMetrics(
                  PaneMetrics(
                    area: constraints.biggest,
                    minPane: Size(
                      ShellxSizes.paneMinCols * cell.width +
                          ShellxSizes.terminalPadding.horizontal,
                      ShellxSizes.paneMinRows * cell.height +
                          ShellxSizes.terminalPadding.vertical +
                          ShellxSizes.paneHeaderFor(scaler),
                    ),
                    divider: ShellxSizes.paneDivider,
                  ),
                );
```

- The `IndexedStack` children become:

```dart
                            for (final tab in state.tabs)
                              PaneTreeView(
                                key: ValueKey('terminal.${tab.id}'),
                                tab: tab,
                                selected: tab.id == selected?.id,
                                terminalFocus: widget.terminalFocus,
                                style: style,
                                shortcuts: widget.shortcuts,
                                scrollFor: _scrollFor,
                                onClosePane: widget.onClosePane,
                                // Task 8 narrows this to the panes that
                                // notified; until then A4's tab-level ring.
                                ringed:
                                    tab.id == selected?.id &&
                                        attention.hasUnread(tab.id)
                                    ? tab.panes.keys.toSet()
                                    : const <int>{},
                                toastShowing: notice != null,
                              ),
```

- Delete the area-level `_DriverPillSlot` `Positioned.fill` and A4's area-level `Positioned.fill(child: AttentionRing(...))` (both now per pane), and the now-unused `phoneDrives` local. Keep the toast.

`terminal_workspace_page.dart`:
- Add `closePane`:

```dart
  Future<void> closePane(TerminalTab tab, int paneId) async {
    await closePaneWithConfirm(
      tabs: ref.read(terminalTabsProvider.notifier),
      router: ref.read(windowRouterProvider.notifier),
      l10n: AppLocalizations.of(context),
      tab: tab,
      paneId: paneId,
    );
    focusTerminal();
  }
```

- Pass `onClosePane: (id) { final tab = ref.read(terminalTabsProvider).tabOfSession(id); if (tab != null) unawaited(closePane(tab, id)); },` to `TerminalPane`.
- Replace the `selectedId` listener so a new focused pane also gets the keyboard:

```dart
    ref.listen(
      terminalTabsProvider.select(
        (s) => (s.selectedId, s.selected?.focusedPaneId),
      ),
      (_, next) {
        if (next.$1 != null &&
            !sidebarFocus.hasFocus &&
            ref.read(sidebarWorkspacesProvider).renaming == null) {
          focusTerminal();
        }
      },
    );
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/ui/pane_tree_view_test.dart`
Expected: PASS. Then the whole suite (A4's `attention_ring_test` must still pass: the one-pane ring is the same rect) — PASS.

- [ ] **Step 5: Format, analyze, commit**

```bash
cd apps/desktop && ~/fvm/versions/3.41.4/bin/dart format --set-exit-if-changed lib/src/ui/terminal test/ui && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter analyze
cd ../.. && git add apps/desktop/lib/src/ui/terminal/pane_tree_view.dart apps/desktop/lib/src/ui/terminal/terminal_pane.dart apps/desktop/lib/src/ui/terminal/close_tab.dart apps/desktop/lib/src/ui/terminal/terminal_workspace_page.dart apps/desktop/test/ui/pane_tree_view_test.dart
git commit -m "feat(desktop): PaneTreeView — split layout, draggable dividers, 22 px pane headers, focus outline, zoom, per-pane ring and driver pill (A3 D10, D14-D16)"
```

---
### Task 7: Desktop — pane actions, ⌘W closes the pane, menus, sidebar pane count, announcements (after A4 merge)

**Files:**
- Modify: `apps/desktop/lib/src/ui/terminal/terminal_workspace_page.dart` (actions, `_leftAltOnly`, `_split`, `_announce`)
- Modify: `apps/desktop/lib/src/ui/terminal/pane_tree_view.dart` (terminal menu entries)
- Modify: `apps/desktop/lib/src/ui/terminal/close_tab.dart` (multi-pane tab confirm, D28)
- Modify: `apps/desktop/lib/src/ui/terminal/session_tab_row.dart` (pane-count mark, label, × tooltip)
- Modify: `apps/desktop/lib/src/ui/terminal/session_sidebar.dart` (row menu, row custom actions)
- Create: `apps/desktop/test/ui/pane_actions_test.dart`

**Interfaces:**
- Consumes: Task 3 intents/labels/strings; Task 5 operations; Task 6 `closePane`, `closePaneWithConfirm`, `PaneTreeView._menu`.
- Produces:
  - Keys: `Key('row.paneCount.<tabId>')`, menu keys `Key('menu.splitRight')`, `Key('menu.splitDown')`, `Key('menu.zoomPane')`, `Key('menu.equalize')`, `Key('menu.closePane')` (terminal menu) and `Key('menu.row.splitRight')`, `Key('menu.row.splitDown')`, `Key('menu.row.equalize')` (row menu)
  - `TerminalWorkspacePageState.closePane(TerminalTab tab, int paneId)` announces `paneAnnounceClosed`

- [ ] **Step 1: Write the failing tests**

Create `apps/desktop/test/ui/pane_actions_test.dart`:

```dart
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_desktop/src/terminal/pane_layout.dart';
import 'package:shellx_desktop/src/terminal/terminal_tabs.dart';

import '../support/fake_local_sessions.dart';
import 'sidebar_test_harness.dart';

TerminalTab only() => tabs().tabs.single;

Future<void> chord(
  WidgetTester t,
  List<LogicalKeyboardKey> modifiers,
  LogicalKeyboardKey key,
) async {
  for (final m in modifiers) {
    await t.sendKeyDownEvent(m);
  }
  await t.sendKeyEvent(key);
  for (final m in modifiers.reversed) {
    await t.sendKeyUpEvent(m);
  }
  await t.pump();
  await t.pump();
}

const meta = LogicalKeyboardKey.metaLeft;
const shift = LogicalKeyboardKey.shiftLeft;
const alt = LogicalKeyboardKey.altLeft;
const control = LogicalKeyboardKey.controlLeft;

void main() {
  setUp(() {
    local = FakeLocalSessions();
    local.add(local.summary(1, origin: SessionOrigin.desktop));
  });

  testSidebar('⌘D splits right and announces; ⌘⌥← focuses back; ⌘W closes '
      'the focused pane, not the tab', (t) async {
    await pumpSidebar(t);
    await chord(t, [meta], LogicalKeyboardKey.keyD);
    expect(only().paneOrder, [1, 100]);
    expect(
      t.takeAnnouncements().map((a) => a.message),
      contains('Split, pane 2 of 2'),
    );
    await chord(t, [meta, alt], LogicalKeyboardKey.arrowLeft);
    expect(only().focusedPaneId, 1);
    await chord(t, [meta], LogicalKeyboardKey.keyW);
    expect(only().paneOrder, [100]);
    expect(tabs().tabs, hasLength(1));
    expect(
      t.takeAnnouncements().map((a) => a.message),
      contains('Pane closed, 1 left'),
    );
  });

  testSidebar('⌘⇧D splits down; ⌘⇧↩ zooms; ⌘⌃= equalizes', (t) async {
    await pumpSidebar(t);
    await chord(t, [meta, shift], LogicalKeyboardKey.keyD);
    expect((only().layout as PaneSplit).axis, SplitAxis.column);
    await chord(t, [meta, shift], LogicalKeyboardKey.enter);
    expect(only().zoomedPaneId, 100);
    await chord(t, [meta, shift], LogicalKeyboardKey.enter);
    expect(only().zoomedPaneId, isNull);
    await chord(t, [meta, control], LogicalKeyboardKey.arrowDown);
    expect((only().layout as PaneSplit).ratio, closeTo(0.55, 1e-9));
    await chord(t, [meta, control], LogicalKeyboardKey.equal);
    expect((only().layout as PaneSplit).ratio, 0.5);
  });

  testSidebar('⌘W on a pane running a command asks with the pane wording '
      '(D28)', (t) async {
    await pumpSidebar(t);
    await chord(t, [meta], LogicalKeyboardKey.keyD);
    local.replace(
      local.summary(100, origin: SessionOrigin.desktop, runningCommand: true),
    );
    await t.pump();
    await chord(t, [meta], LogicalKeyboardKey.keyW);
    expect(
      find.text('The command running in this pane will be stopped.'),
      findsOneWidget,
    );
  });

  testSidebar('terminal menu: split entries always, pane entries with two '
      'panes; Close pane closes the pane under the pointer (D21)', (t) async {
    await pumpSidebar(t);
    final area = t.getRect(find.byKey(const ValueKey('terminal.1')));
    await t.tapAt(area.center, buttons: kSecondaryMouseButton);
    await t.pump();
    expect(find.byKey(const Key('menu.splitRight')), findsOneWidget);
    expect(find.byKey(const Key('menu.closePane')), findsNothing);
    await t.tap(find.byKey(const Key('menu.splitRight')));
    await t.pump();
    await t.pump();
    expect(only().paneOrder, [1, 100]);
    final left = t.getRect(find.byKey(const Key('pane.header.1')));
    await t.tapAt(left.bottomCenter + const Offset(0, 40),
        buttons: kSecondaryMouseButton);
    await t.pump();
    expect(only().focusedPaneId, 1);
    expect(find.byKey(const Key('menu.zoomPane')), findsOneWidget);
    await t.tap(find.byKey(const Key('menu.closePane')));
    await t.pump();
    expect(only().paneOrder, [100]);
  });

  testSidebar('row: pane count, label, row menu split, close hint only for '
      'one pane (D6, D19, D21)', (t) async {
    final semantics = t.ensureSemantics();
    addTearDown(semantics.dispose);
    await pumpSidebar(t);
    expect(find.byKey(const Key('row.paneCount.1')), findsNothing);
    await t.tap(row(1), buttons: kSecondaryMouseButton);
    await t.pump();
    await t.tap(find.byKey(const Key('menu.row.splitDown')));
    await t.pump();
    await t.pump();
    expect((only().layout as PaneSplit).axis, SplitAxis.column);
    expect(
      find.descendant(
        of: find.byKey(const Key('row.paneCount.1')),
        matching: find.text('2'),
      ),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel(RegExp(r'^zsh 2, 2 panes, ')), findsOneWidget);
    await t.tap(row(1), buttons: kSecondaryMouseButton);
    await t.pump();
    expect(find.byKey(const Key('menu.row.equalize')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('menu.closeTab')),
        matching: find.text('⌘W'),
      ),
      findsNothing,
    );
  });

  testWidgets(
    'Windows: AltGr never fires split down; left Alt does (D20)',
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
    (t) async {
      try {
        await pumpSidebar(t);
        await chord(t, [
          control,
          shift,
          LogicalKeyboardKey.altRight,
        ], LogicalKeyboardKey.keyD);
        expect(only().paneOrder, [1]);
        await chord(t, [control, shift, alt], LogicalKeyboardKey.keyD);
        expect((only().layout as PaneSplit).axis, SplitAxis.column);
        await chord(t, [control, LogicalKeyboardKey.altRight],
            LogicalKeyboardKey.arrowUp);
        expect(only().focusedPaneId, 100); // unchanged
        await chord(t, [control, alt], LogicalKeyboardKey.arrowUp);
        expect(only().focusedPaneId, 1);
      } finally {
        await t.pumpWidget(const SizedBox());
        container.dispose();
      }
    },
  );
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/ui/pane_actions_test.dart`
Expected: FAIL — ⌘D does nothing (no action for `SplitPaneIntent`), no pane menu entries, no pane-count mark.

- [ ] **Step 3: Implement**

`terminal_workspace_page.dart`:

1. Imports: `package:flutter/semantics.dart` (if not already there for `SemanticsService`) and `'../../terminal/pane_layout.dart'`.
2. Helpers in the state class:

```dart
  /// D20 / A1: on Windows AltGr arrives as Ctrl+Alt; with the right Alt
  /// held, a chord stays the shell's (AltGr+Shift+D, AltGr+arrows type on
  /// German or Polish layouts).
  static bool _leftAltOnly(Intent _) =>
      defaultTargetPlatform != TargetPlatform.windows ||
      !HardwareKeyboard.instance.logicalKeysPressed.contains(
        LogicalKeyboardKey.altRight,
      );

  bool _split(Intent _) =>
      _leftAltOnly(_) && ref.read(terminalTabsProvider).selected != null;

  bool _isSplit(Intent _) =>
      _leftAltOnly(_) &&
      (ref.read(terminalTabsProvider).selected?.isSplit ?? false);

  /// D22: polite, once.
  void _announce(String message) => unawaited(
    SemanticsService.sendAnnouncement(
      View.of(context),
      message,
      Directionality.of(context),
    ),
  );

  void _announceFocusedPane() {
    final tab = ref.read(terminalTabsProvider).selected;
    if (tab == null || !tab.isSplit) return;
    _announce(
      AppLocalizations.of(context).paneRegionLabel(
        tab.paneNumber(tab.focusedPaneId),
        tab.paneCount,
        tab.focused.automaticLabel,
      ),
    );
  }

  Future<void> _splitPane(SplitAxis axis) async {
    final before = ref.read(terminalTabsProvider).selected?.paneCount ?? 0;
    await ref.read(terminalTabsProvider.notifier).split(axis);
    if (!mounted) return;
    final tab = ref.read(terminalTabsProvider).selected;
    if (tab != null && tab.paneCount > before) {
      _announce(
        AppLocalizations.of(context).paneAnnounceSplit(
          tab.paneNumber(tab.focusedPaneId),
          tab.paneCount,
        ),
      );
    }
    focusTerminal();
  }
```

3. `closePane` (from Task 6) announces:

```dart
  Future<void> closePane(TerminalTab tab, int paneId) async {
    final l10n = AppLocalizations.of(context);
    await closePaneWithConfirm(
      tabs: ref.read(terminalTabsProvider.notifier),
      router: ref.read(windowRouterProvider.notifier),
      l10n: l10n,
      tab: tab,
      paneId: paneId,
    );
    if (!mounted) return;
    final left = ref
        .read(terminalTabsProvider)
        .tabs
        .where((t) => t.id == tab.id)
        .firstOrNull
        ?.paneCount;
    if (tab.isSplit && left != null && left < tab.paneCount) {
      _announce(l10n.paneAnnounceClosed(left));
    }
    focusTerminal();
  }
```

4. In `_actions()`: `SelectTabIntent`'s `enabled:` becomes `enabled: _leftAltOnly` (same behaviour). `CloseTabIntent` closes the focused pane of a split tab:

```dart
        final selected = ref.read(terminalTabsProvider).selected;
        if (selected == null) {
          // UI §2.7 (accepted): ⌘W on the empty state hides the window.
          ref.read(windowRouterProvider.notifier).hideWindow();
        } else if (selected.isSplit) {
          unawaited(closePane(selected, selected.focusedPaneId)); // A3 D6
        } else {
          unawaited(closeTab(selected));
        }
```

and the new actions:

```dart
      SplitPaneIntent: run<SplitPaneIntent>(
        (intent) => unawaited(_splitPane(intent.axis)),
        enabled: _split,
      ),
      FocusPaneIntent: run<FocusPaneIntent>((intent) {
        if (tabs.focusDirection(intent.direction)) {
          focusTerminal();
          _announceFocusedPane();
        }
      }, enabled: _isSplit),
      TogglePaneZoomIntent: run<TogglePaneZoomIntent>((_) {
        final l10n = AppLocalizations.of(context);
        _announce(
          tabs.toggleZoom() ? l10n.paneAnnounceZoomed : l10n.paneAnnounceUnzoomed,
        );
        focusTerminal();
      }, enabled: _isSplit),
      EqualizePanesIntent: run<EqualizePanesIntent>(
        (_) => tabs.equalize(),
        enabled: _isSplit,
      ),
      ResizePaneIntent: run<ResizePaneIntent>(
        (intent) => tabs.resizeFocused(intent.direction),
        enabled: _isSplit,
      ),
```

(Disabled actions let the key reach the shell, like A1's ⌘C without a selection.)

`pane_tree_view.dart` — `_menu` entries after "Select all" (D21, UI-A3 §4.1):

```dart
        ShellxMenuEntry(
          key: const Key('menu.splitRight'),
          value: const SplitPaneIntent(SplitAxis.row),
          label: l10n.paneSplitRight,
          shortcut: splitRightShortcutLabel(),
          dividerBefore: true,
        ),
        ShellxMenuEntry(
          key: const Key('menu.splitDown'),
          value: const SplitPaneIntent(SplitAxis.column),
          label: l10n.paneSplitDown,
          shortcut: splitDownShortcutLabel(),
        ),
        if (widget.tab.isSplit) ...[
          ShellxMenuEntry(
            key: const Key('menu.zoomPane'),
            value: const TogglePaneZoomIntent(),
            label: widget.tab.zoomedPaneId == null
                ? l10n.paneZoom
                : l10n.paneUnzoom,
            shortcut: zoomPaneShortcutLabel(),
          ),
          ShellxMenuEntry(
            key: const Key('menu.equalize'),
            value: const EqualizePanesIntent(),
            label: l10n.paneEqualize,
            shortcut: equalizePanesShortcutLabel(),
          ),
          ShellxMenuEntry(
            key: const Key('menu.closePane'),
            // ⌘W's action closes the focused pane of a split tab; the menu
            // focused this pane first.
            value: const CloseTabIntent(),
            label: l10n.paneClose,
            shortcut: closePaneShortcutLabel(),
            dividerBefore: true,
          ),
        ],
```

`close_tab.dart` — `closeTabWithConfirm` (D28):

```dart
Future<void> closeTabWithConfirm({
  required TerminalTabs tabs,
  required WindowRouter router,
  required AppLocalizations l10n,
  required TerminalTab tab,
}) async {
  final running = tabs.runningPaneCount(tab.id);
  if (running > 0) {
    final ok = await router.confirm(
      ConfirmRequest(
        title: l10n.confirmCloseRunningTitle(tab.label),
        body: tab.isSplit
            ? l10n.confirmCloseRunningPanesBody(running)
            : l10n.confirmCloseRunningBody,
        confirmLabel: l10n.confirmCloseRunningAction,
      ),
    );
    if (!ok) return;
  }
  tabs.close(tab.id);
}
```

`session_tab_row.dart`:

1. In the title `Row`, directly after A4's unread badge (and before the `SessionOrigin.phone` mark) — UI-A3 §3:

```dart
        if (tab.isSplit) ...[
          const SizedBox(width: ShellxSpace.s4),
          Tooltip(
            message: l10n.sidebarPaneCount(tab.paneCount),
            excludeFromSemantics: true,
            child: Row(
              key: Key('row.paneCount.${tab.id}'),
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.view_column_outlined,
                  size: ShellxSizes.paneCountIcon,
                  color: ShellxDesktopColors.textSecondary,
                ),
                const SizedBox(width: ShellxSizes.paneCountGap),
                Text(
                  '${tab.paneCount}',
                  style: ShellxText.caption.copyWith(
                    color: ShellxDesktopColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
```

2. `_semanticsLabel`: after `tab.label,` add `if (tab.isSplit) l10n.sidebarPaneCount(tab.paneCount),`.
3. The row ×'s tooltip: `tooltip: tab.isSplit ? l10n.terminalCloseTabAllPanes : shortcutTooltip(l10n.terminalCloseTabTooltip(shortcut), shortcut),`.

`session_sidebar.dart`:

1. `_RowAction` gains `splitRight, splitDown, equalize`.
2. In `_rowMenu` entries, after the `automaticName` entry:

```dart
          ShellxMenuEntry(
            key: const Key('menu.row.splitRight'),
            value: _RowAction.splitRight,
            label: l10n.paneSplitRight,
            shortcut: splitRightShortcutLabel(),
            dividerBefore: true,
          ),
          ShellxMenuEntry(
            key: const Key('menu.row.splitDown'),
            value: _RowAction.splitDown,
            label: l10n.paneSplitDown,
            shortcut: splitDownShortcutLabel(),
          ),
          if (tab.isSplit)
            ShellxMenuEntry(
              key: const Key('menu.row.equalize'),
              value: _RowAction.equalize,
              label: l10n.paneEqualize,
              shortcut: equalizePanesShortcutLabel(),
            ),
```

and the close entry's `shortcut:` becomes `tab.isSplit ? null : closeTabShortcutLabel(),` (D6). Cases:

```dart
        case _RowAction.splitRight:
          _splitFromRow(tab, SplitAxis.row);
        case _RowAction.splitDown:
          _splitFromRow(tab, SplitAxis.column);
        case _RowAction.equalize:
          widget.onSelected(tab.id);
          Actions.maybeInvoke(context, const EqualizePanesIntent());
```

with

```dart
  /// D21/D30: the row's tab is selected first, then the window's split
  /// action runs (announcement and focus included).
  void _splitFromRow(TerminalTab tab, SplitAxis axis) {
    widget.onSelected(tab.id);
    Actions.maybeInvoke(context, SplitPaneIntent(axis));
  }
```

3. `_rowActions(l10n, tab)` (row custom semantics actions) adds:

```dart
      CustomSemanticsAction(label: l10n.paneSplitRight): () =>
          _splitFromRow(tab, SplitAxis.row),
      CustomSemanticsAction(label: l10n.paneSplitDown): () =>
          _splitFromRow(tab, SplitAxis.column),
```

Imports: `pane_layout.dart`, `terminal_shortcuts.dart` (if not imported), `shortcut_labels.dart`.

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/ui/pane_actions_test.dart`
Expected: PASS. Then the whole suite — PASS (A1's "⌘W closes the tab" tests still pass: one-pane tabs).

- [ ] **Step 5: Format, analyze, commit**

```bash
cd apps/desktop && ~/fvm/versions/3.41.4/bin/dart format --set-exit-if-changed lib/src/ui/terminal test/ui && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter analyze
cd ../.. && git add apps/desktop/lib/src/ui/terminal/terminal_workspace_page.dart apps/desktop/lib/src/ui/terminal/pane_tree_view.dart apps/desktop/lib/src/ui/terminal/close_tab.dart apps/desktop/lib/src/ui/terminal/session_tab_row.dart apps/desktop/lib/src/ui/terminal/session_sidebar.dart apps/desktop/test/ui/pane_actions_test.dart
git commit -m "feat(desktop): pane shortcuts and menus — ⌘W closes the focused pane, split/zoom/equalize/resize, sidebar pane count, announcements, AltGr guard (A3 P3, D6, D19-D22)"
```

---

### Task 8: Desktop — A4 attention aggregated per pane (requires A4 merged)

**Files:**
- Modify: `apps/desktop/lib/src/terminal/tab_attention.dart`
- Modify: `apps/desktop/lib/src/ui/terminal/terminal_pane.dart` (`ringed`, `hiddenUnread`)
- Create: `apps/desktop/test/terminal/tab_attention_panes_test.dart`
- Modify: `apps/desktop/test/ui/pane_tree_view_test.dart` (one ring test)

**Interfaces:**
- Consumes: A4 `TabAttention`, `AttentionState`, `TabUnread`, `AttentionEntry`, `AttentionArrival`, `windowActiveProvider`, `windowFocusProvider`, `FakeLocalSessions.notice(...)`; Task 4/5 `tabOfSession`, `focusedPaneId`, `focusPane`, `closePane`, `split`.
- Produces:
  - `TabUnread.panes → Map<int, int>` (session id → unread count; `count` = sum)
  - `AttentionEntry.paneId → int`
  - `AttentionState.paneHasUnread(int tabId, int paneId) → bool`, `AttentionState.unreadPanes(int tabId) → Set<int>`
  - `TabAttention.markPaneRead(int tabId, int paneId)`; `markRead(tabId)` reads every pane; `reads` still emits **tab** ids, only when a tab has no unread left; `jumpTo(tabId)` focuses the pane with the newest unread notice.

- [ ] **Step 1: Write the failing tests**

Create `apps/desktop/test/terminal/tab_attention_panes_test.dart`:

```dart
import 'dart:async';
import 'dart:ui';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:shellx_desktop/l10n/app_localizations.dart';
import 'package:shellx_desktop/src/platform/settings_store.dart';
import 'package:shellx_desktop/src/terminal/local_sessions_provider.dart';
import 'package:shellx_desktop/src/terminal/pane_layout.dart';
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
  TerminalTabs tabs() => c.read(terminalTabsProvider.notifier);

  void setActive(bool active) {
    final router = c.read(windowRouterProvider.notifier);
    active ? router.showTerminal() : router.hideWindow();
    c.read(windowFocusProvider.notifier).set(active);
  }

  /// Tab 1 = panes 1 | 100, pane 100 focused; tab 2 alone.
  Future<void> boot({bool active = true}) async {
    c = ProviderContainer.test(
      overrides: [
        localSessionsProvider.overrideWithValue(local),
        appL10nProvider.overrideWithValue(
          lookupAppLocalizations(const Locale('en')),
        ),
        settingsStoreProvider.overrideWithValue(InMemorySettingsStore()),
      ],
    );
    c.read(terminalTabsProvider);
    c.read(sidebarWorkspacesProvider);
    state();
    await tabs().split(SplitAxis.row);
    setActive(active);
  }

  setUp(() {
    local = FakeLocalSessions();
    local.add(local.summary(1, origin: SessionOrigin.desktop, title: 'zsh'));
    local.add(local.summary(2, title: 'api'));
  });

  test('the focused pane is "seen"; another pane of the same tab is unread, '
      'bells included (D18)', () async {
    await boot();
    final arrivals = <AttentionArrival>[];
    attention().arrivals.listen(arrivals.add);
    local.notice(100, SessionNoticeKind.message, body: 'seen');
    local.notice(100, SessionNoticeKind.bell); // dropped (A4 D7)
    expect(state().unread, isEmpty);
    local.notice(1, SessionNoticeKind.message, body: 'build ok');
    local.notice(1, SessionNoticeKind.bell);
    expect(state().unread[1]!.count, 2);
    expect(state().unread[1]!.panes, {1: 2});
    expect(state().unreadPanes(1), {1});
    expect(state().paneHasUnread(1, 100), isFalse);
    expect(arrivals.map((a) => a.tabId), [1, 1]);
    expect(state().history.first.paneId, 1);
  });

  test('badge = sum over panes; dwell reads only the focused pane', () {
    fakeAsync((async) {
      unawaited(boot(active: false));
      async.flushMicrotasks();
      local.notice(1, SessionNoticeKind.message, body: 'a');
      local.notice(100, SessionNoticeKind.message, body: 'b');
      expect(state().unread[1]!.count, 2);
      final reads = <int>[];
      attention().reads.listen(reads.add);
      setActive(true);
      async.elapse(const Duration(seconds: 2));
      expect(state().unread[1]!.panes, {1: 1}); // 100 (focused) read
      expect(reads, isEmpty); // the tab still has unread
      tabs().focusPane(1);
      async.elapse(const Duration(milliseconds: 999));
      expect(state().paneHasUnread(1, 1), isTrue);
      async.elapse(const Duration(milliseconds: 2));
      expect(state().hasUnread(1), isFalse);
      expect(reads, [1]);
    });
  });

  test('markRead(tab) reads every pane', () async {
    await boot(active: false);
    local.notice(1, SessionNoticeKind.message, body: 'a');
    local.notice(100, SessionNoticeKind.message, body: 'b');
    attention().markRead(1);
    expect(state().unread, isEmpty);
    expect(state().history.every((e) => e.read), isTrue);
  });

  test('a closed pane drops its unread; the tab id stays', () async {
    await boot();
    local.notice(1, SessionNoticeKind.message, body: 'a');
    final reads = <int>[];
    attention().reads.listen(reads.add);
    tabs().closePane(1);
    expect(state().hasUnread(1), isFalse);
    expect(reads, [1]);
    expect(c.read(terminalTabsProvider).tabs.first.id, 1);
  });

  test('jumpTo focuses the pane with the newest unread notice', () async {
    await boot(active: false);
    tabs().select(2);
    local.notice(100, SessionNoticeKind.message, body: 'older');
    local.notice(1, SessionNoticeKind.message, body: 'newest');
    expect(attention().jumpTo(1), isTrue);
    final tab = c.read(terminalTabsProvider).selected!;
    expect(tab.id, 1);
    expect(tab.focusedPaneId, 1);
    expect(state().hasUnread(1), isFalse);
  });
}
```

Append to `apps/desktop/test/ui/pane_tree_view_test.dart`:

```dart
  testSidebar('the ring surrounds only the pane that notified (D18)',
      (t) async {
    await pumpSidebar(t);
    await splitRight(t); // pane 100 focused
    container.read(windowFocusProvider.notifier).set(false);
    local.notice(1, SessionNoticeKind.message, body: 'done');
    await t.pump();
    final rings = find.byWidgetPredicate(
      (w) => w is AttentionRing && w.visible,
    );
    expect(rings, findsOneWidget);
    final ring = t.getRect(rings);
    expect(ring.left, t.getRect(find.byKey(const Key('pane.header.1'))).left);
    expect(
      ring.right,
      lessThan(t.getRect(find.byKey(const Key('pane.header.100'))).left),
    );
  });
```

(imports: `tab_attention.dart`, `attention_marks.dart`, `window_focus.dart`.)

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/terminal/tab_attention_panes_test.dart test/ui/pane_tree_view_test.dart`
Expected: FAIL — `panes`, `paneId`, `unreadPanes` undefined; notices from pane 100 are dropped (A4 looked tabs up by `t.id == sessionId`).

- [ ] **Step 3: Implement**

`tab_attention.dart`:

1. `TabUnread` gains `required this.panes` (`final Map<int, int> panes;` doc: "A3 D18: unread per pane (session id); [count] is their sum").
2. `AttentionEntry` gains `required this.paneId` (`final int paneId;`), carried by `copyWith`.
3. `AttentionState`:

```dart
  bool paneHasUnread(int tabId, int paneId) =>
      (unread[tabId]?.panes[paneId] ?? 0) > 0;

  Set<int> unreadPanes(int tabId) =>
      unread[tabId]?.panes.keys.toSet() ?? const {};
```

4. `_onNotice` — the tab lookup and "seen" (D18):

```dart
    final tabs = ref.read(terminalTabsProvider);
    final tab = tabs.tabOfSession(notice.sessionId);
    if (tab == null) return; // not (or no longer) a pane of this window
    final pane = notice.sessionId;
    final seen =
        tabs.selectedId == tab.id &&
        tab.focusedPaneId == pane &&
        ref.read(windowActiveProvider);
```

`_withEntry` takes `int paneId` and stores it (the bell merge also requires `first.paneId == paneId`); the unread update:

```dart
    final before = state.unread[tab.id];
    state = AttentionState(
      unread: {
        ...state.unread,
        tab.id: TabUnread(
          count: (before?.count ?? 0) + 1,
          panes: {...?before?.panes, pane: (before?.panes[pane] ?? 0) + 1},
          text: text,
          kind: kind,
          at: notice.at,
        ),
      },
      history: history,
    );
```

5. Reading:

```dart
  /// D18: one pane read (the 1 s dwell on the focused pane). The tab's
  /// system notification goes ([reads]) only when no pane is left unread.
  void markPaneRead(int tabId, int paneId) {
    final before = state.unread[tabId];
    if (before == null || !before.panes.containsKey(paneId)) return;
    final panes = Map.of(before.panes)..remove(paneId);
    final unread = Map.of(state.unread);
    if (panes.isEmpty) {
      unread.remove(tabId);
    } else {
      unread[tabId] = TabUnread(
        count: before.count - before.panes[paneId]!,
        panes: panes,
        text: before.text,
        kind: before.kind,
        at: before.at,
      );
    }
    state = AttentionState(
      unread: unread,
      history: [
        for (final e in state.history)
          e.tabId == tabId && e.paneId == paneId && !e.read
              ? e.copyWith(read: true)
              : e,
      ],
    );
    if (_dwellFor == (tabId, paneId)) _cancelDwell();
    if (panes.isEmpty) _reads.add(tabId);
  }
```

`markRead(tabId)` stays as A4 wrote it (removes the whole entry, marks every entry of the tab read, emits `reads`); change its `_dwellFor == tabId` check to `_dwellFor?.$1 == tabId`.

6. `_dwellFor` becomes `(int, int)? _dwellFor;` and `_armDwell`:

```dart
  void _armDwell() {
    if (!ref.mounted) return;
    final tab = ref.read(terminalTabsProvider).selected;
    final key = tab == null ? null : (tab.id, tab.focusedPaneId);
    final wanted =
        key != null &&
        state.paneHasUnread(key.$1, key.$2) &&
        ref.read(windowActiveProvider);
    if (!wanted) {
      _cancelDwell();
      return;
    }
    if (_dwellFor == key && (_dwell?.isActive ?? false)) return;
    _cancelDwell();
    _dwellFor = key;
    _dwell = Timer(dwell, () {
      _dwellFor = null;
      if (!ref.mounted) return;
      final now = ref.read(terminalTabsProvider).selected;
      if (now?.id == key.$1 &&
          now?.focusedPaneId == key.$2 &&
          ref.read(windowActiveProvider)) {
        markPaneRead(key.$1, key.$2);
      }
    });
  }
```

7. `_dropGone` — also drop panes that left a tab that is still there:

```dart
  void _dropGone(TerminalTabsState tabs) {
    final present = {for (final t in tabs.tabs) t.id: t};
    final unread = <int, TabUnread>{};
    final emptied = <int>[];
    for (final MapEntry(key: id, value: u) in state.unread.entries) {
      final tab = present[id];
      if (tab == null) {
        emptied.add(id);
        continue;
      }
      final panes = {
        for (final MapEntry(key: p, value: n) in u.panes.entries)
          if (tab.panes.containsKey(p)) p: n,
      };
      if (panes.isEmpty) {
        emptied.add(id);
      } else if (panes.length == u.panes.length) {
        unread[id] = u;
      } else {
        unread[id] = TabUnread(
          count: panes.values.fold(0, (a, b) => a + b),
          panes: panes,
          text: u.text,
          kind: u.kind,
          at: u.at,
        );
      }
    }
    final closing = state.history.any(
      (e) => !e.closed && !present.containsKey(e.tabId),
    );
    if (emptied.isEmpty && unread.length == state.unread.length && !closing) {
      if (unread.entries.every((e) => identical(e.value, state.unread[e.key]))) {
        return;
      }
    }
    state = AttentionState(
      unread: unread,
      history: [
        for (final e in state.history)
          !e.closed && !present.containsKey(e.tabId)
              ? e.copyWith(closed: true)
              : e,
      ],
    );
    for (final id in emptied) {
      _reads.add(id);
    }
  }
```

8. `jumpTo` — keep A4's opening check (`return false` when the tab is gone); replace the rest of the body so the newest unread pane is focused before reading:

```dart
    final newest = state.history
        .where((e) => e.tabId == tabId && !e.read)
        .map((e) => e.paneId)
        .firstOrNull;
    ref.read(sidebarWorkspacesProvider.notifier).reveal(tabId);
    ref.read(terminalTabsProvider.notifier).select(tabId);
    final tab = ref.read(terminalTabsProvider).tabs.firstWhere(
      (t) => t.id == tabId,
    );
    if (newest != null && tab.panes.containsKey(newest)) {
      ref.read(terminalTabsProvider.notifier).focusPane(newest);
    }
    markRead(tabId);
    ref.read(terminalFocusRequestProvider.notifier).request();
    return true;
```

`terminal_pane.dart` — replace the Task 6 interim `ringed:` and add `hiddenUnread:`:

```dart
                                ringed: tab.id == selected?.id
                                    ? attention.unreadPanes(tab.id)
                                    : const <int>{},
                                hiddenUnread:
                                    tab.zoomedPaneId != null &&
                                    attention
                                        .unreadPanes(tab.id)
                                        .any((id) => id != tab.zoomedPaneId),
```

A4's existing `tab_attention_test.dart` keeps passing: every one-pane tab has `panes == {tabId: count}` and the focused pane is the tab's only pane. If an A4 test builds `TabUnread(...)`/`AttentionEntry(...)` by hand, add `panes: {id: count}` / `paneId: id`.

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/terminal test/ui`
Expected: PASS (A4's `tab_attention_test`, `attention_ring_test`, `notifications_panel_test`, `desktop_notifications_test` included).

- [ ] **Step 5: Format, analyze, commit**

```bash
cd apps/desktop && ~/fvm/versions/3.41.4/bin/dart format --set-exit-if-changed lib/src/terminal lib/src/ui/terminal test/terminal test/ui && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter analyze
cd ../.. && git add apps/desktop/lib/src/terminal/tab_attention.dart apps/desktop/lib/src/ui/terminal/terminal_pane.dart apps/desktop/test/terminal/tab_attention_panes_test.dart apps/desktop/test/ui/pane_tree_view_test.dart
git commit -m "feat(desktop): attention per pane — badge sums panes, the focused pane is seen and read after 1 s, ring on the pane that notified, jump focuses it (A3 D18)"
```

---

### Task 9: Desktop — one-pane parity, HANDOFF §14, full verification (after A4 merge)

**Files:**
- Create: `apps/desktop/test/ui/one_pane_parity_test.dart`
- Modify: `docs/superpowers/HANDOFF.md` (new §14 after A4's §13)

**Interfaces:**
- Consumes: everything above; A4 `AttentionRing`, `windowFocusProvider`, `FakeLocalSessions.notice`.
- Produces: nothing new.

- [ ] **Step 1: Write the parity test (criterion 13)**

Create `apps/desktop/test/ui/one_pane_parity_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_desktop/src/terminal/terminal_font_size.dart';
import 'package:shellx_desktop/src/terminal/terminal_style.dart';
import 'package:shellx_desktop/src/ui/terminal/attention_marks.dart';
import 'package:shellx_desktop/src/ui/theme/shellx_desktop_theme.dart';
import 'package:shellx_desktop/src/ui/window_focus.dart';
import 'package:xterm/xterm.dart';

import '../support/fake_local_sessions.dart';
import 'sidebar_test_harness.dart';

void main() {
  setUp(() {
    local = FakeLocalSessions();
    local.add(local.summary(1, origin: SessionOrigin.desktop));
  });

  testSidebar('a one-pane tab is laid out, labelled, ringed and sized '
      'exactly like A4', (t) async {
    final semantics = t.ensureSemantics();
    addTearDown(semantics.dispose);
    await pumpSidebar(t);
    await t.pump();
    // Layout: the terminal fills the area under the macOS pane header.
    final view = t.getRect(find.byType(TerminalView));
    expect(view.left, ShellxSizes.sidebarWidth + 1);
    expect(view.top, ShellxSizes.paneHeaderMac);
    expect(view.right, 1100);
    expect(view.bottom, 720);
    // No A3 chrome.
    expect(find.byKey(const Key('pane.header.1')), findsNothing);
    expect(find.byKey(const Key('pane.focusOutline')), findsNothing);
    expect(find.byKey(const Key('pane.divider.')), findsNothing);
    expect(find.byKey(const Key('row.paneCount.1')), findsNothing);
    expect(find.bySemanticsLabel('Terminal zsh 1'), findsOneWidget);
    // Size: the session got the grid of the whole area (A1).
    final grid = measureTerminalGrid(
      ShellxSizes.terminalPadding.deflateSize(view.size),
      desktopTerminalStyle(container.read(terminalFontSizeProvider)),
      TextScaler.noScaling,
    )!;
    expect(local.views[1]!.resizes.last, (grid.cols, grid.rows));
    // Ring: A4's rect (the terminal area).
    container.read(windowFocusProvider.notifier).set(false);
    local.notice(1, SessionNoticeKind.message, body: 'done');
    await t.pump();
    final ring = find.byWidgetPredicate((w) => w is AttentionRing && w.visible);
    expect(t.getRect(ring), view);
  });
}
```

- [ ] **Step 2: Run it**

Run: `cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/ui/one_pane_parity_test.dart`
Expected: PASS. If it fails, the A3 code changed a one-pane tab: fix the code (Task 6 `PaneTreeView`/`TerminalPane`), never the test.

- [ ] **Step 3: Add HANDOFF §14**

Append to `docs/superpowers/HANDOFF.md` after A4's §13:

```markdown
## 14. Chia pane — A3 (2026-10-07)

Thử tay trên **macOS và Windows thật** (spec `2026-10-07-desktop-splits-a3-design.md` §6):

- [ ] ⌘D / Ctrl+Shift+D trong `~/work/shellx` (zsh, bash, PowerShell có hook) → pane mới bên phải, `pwd` đúng thư mục; ⌘⇧D / Ctrl+Shift+Alt+D → bên dưới. Shell không hook (fish, cmd) → home.
- [ ] Thư mục trên ổ mạng chậm/không phản hồi (`/Volumes/nas`, ổ ánh xạ) → pane mới ở home trong ≤ 0,3 s, không treo; UNC trên Windows → home.
- [ ] `vim`, `htop`, Claude Code trong hai pane cạnh nhau: `tput cols` mỗi pane đúng cỡ của nó; kéo đường chia → cả hai vẽ lại đúng; nháy đúp đường chia → 50/50.
- [ ] ⌘⌥mũi tên / Ctrl+Alt+mũi tên chuyển focus đúng theo hình (chữ T, lưới 2×2); máy Windows có driver Intel cũ: kiểm Ctrl+Alt+mũi tên không xoay màn hình (nếu có, ghi lại).
- [ ] Bàn phím Đức/Ba Lan trên Windows: AltGr+Shift+D, AltGr+mũi tên vẫn gõ ký tự vào shell, không chia/không chuyển pane.
- [ ] ⌘⇧↩ phóng to/bỏ; pane ẩn vẫn chạy (`ping` vẫn chạy khi quay lại); ⌘⌃= cân bằng ba cột; ⌘⌃mũi tên dời đường chia; không pane nào < 20 cột.
- [ ] ⌘W đóng pane đang focus, focus về pane dùng gần nhất; pane đang chạy `sleep 100` → hỏi "Lệnh đang chạy trong pane này…"; × dòng sidebar đóng cả tab, hỏi "2 pane đang chạy lệnh…".
- [ ] `exit` (0) trong một pane → pane biến mất; `exit 3` → dòng thoát, Enter đóng đúng pane đó.
- [ ] Điện thoại: mỗi pane là một phiên trong danh sách; gõ trên điện thoại vào pane 2 → dải driver chỉ ở pane 2; điện thoại mở phiên → tab mới.
- [ ] Thông báo: pane không focus `printf '\e]9;xong\a'` → badge dòng, vòng chỉ quanh pane đó; bấm pane đó, chờ 1 s → tắt; ⌘⇧U focus đúng pane.
- [ ] VoiceOver / Narrator: đọc "Pane 2 trên 3 — vim" khi chuyển focus bằng phím; đọc khi chia/đóng/phóng to; đường chia là thanh trượt tăng/giảm được.
- [ ] Tab một pane trông giống hệt trước A3 (so ảnh chụp với bản A4).
```

- [ ] **Step 4: Full verification**

```bash
cd packages/shellx_agent && ~/fvm/versions/3.41.4/bin/dart analyze && ~/fvm/versions/3.41.4/bin/dart test
cd ../../apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter analyze && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test
```

Expected: both suites PASS with at least the pre-Task-1 counts plus the new tests; analyzer clean.

- [ ] **Step 5: Commit**

```bash
git add apps/desktop/test/ui/one_pane_parity_test.dart docs/superpowers/HANDOFF.md
git commit -m "test(desktop): one-pane tab parity with A4; HANDOFF §14 manual checklist for split panes (A3)"
```

---

## Self-Review

**Spec coverage** (spec §1 criteria → tasks): 1–2 split + cwd → T1, T5, T7; 3 per-pane sizes → T4 (`_reportsSize`), T5, T6; 4 focus → T2 (`neighbourPane`), T5, T6 (click), T7 (chords); 5 close/exit → T4, T5, T6 (×), T7 (⌘W, confirm); 6 zoom → T5, T6, T7; 7 equalize/resize/min size → T2, T5, T6 (`PaneMetrics`), T7; 8 menus → T7; 9 sidebar → T4 (getters), T7 (mark, label); 10 attention → T8; 11 phone unchanged → no protocol task; D5 phone sessions not held (T4 test); 12 accessibility → T6 (region labels, divider slider), T7 (announcements, row actions); 13 no regression / parity → every task runs the full suite, T9 parity test. D29 (font change keeps ratios) needs no code: ratios are stored, not columns. P7/P8 out of scope (spec §7).

**Placeholder scan:** none; the only "use the real name" notes (Task 6 imports/tokens) point at names that exist in the files listed.

**Type consistency:** `SplitAxis.row/column`, `PaneDirection`, `PanePath` (String), `PaneMetrics(area, minPane, divider)`, `TerminalTab.paneOrder/paneNumber/isSplit/focusedPaneId/zoomedPaneId`, `PaneSession`, `split/focusPane/focusDirection/closePane/toggleZoom/equalize/equalizeAt/setRatio/resizeFocused`, `closePaneWithConfirm`, `AttentionState.unreadPanes/paneHasUnread`, `TabUnread.panes`, `AttentionEntry.paneId`, `markPaneRead` — same spelling in every task.

**Review Focus:** each of the five lines has its pinning test in the owning task (Task 1 hang test; Task 4 D5 test; Task 5 vanished-tab, stale-path, limit, no-room, resize tests; Task 6 drag test; Task 7 AltGr test).
