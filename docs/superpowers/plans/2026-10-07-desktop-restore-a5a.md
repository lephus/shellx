# ShellX Desktop A5a — Session Restore Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Quit, crash or reboot, then open ShellX: the same workspaces, tabs (names, order, membership), pane trees (ratios, zoom, focus) and selected tab come back, each pane a fresh login shell in its saved directory, with the pane's last 2,000 lines (colours kept) painted above a dim "— Phiên được khôi phục · 14:32 —" divider.

**Architecture:** A new `apps/desktop/lib/src/restore/` package of focused units: a pure codec that re-encodes xterm cells as SGR-only text (never raw PTY bytes) plus a sanitizer for loading; a versioned JSON snapshot model; a file store (0700/0600, temp + rename, `.bak` on corruption, one scrollback file per pane); and a Riverpod `RestorePersistence` that saves the layout 1 s after each structural change and dirty scrollback every 60 s, on hide, on quit and on OS power-off. `TerminalTabs.restore` reopens panes through A3's `LocalSessions.open(cwd:)` and writes the saved text into the pane's xterm *before* the session backlog — never into the PTY or the agent's ring buffer, so phones never see it.

**Tech Stack:** Dart ^3.11 / Flutter 3.41.4 (fvm), flutter_riverpod 3, xterm 4.0.0, `flutter_test` + `fake_async`, ARB l10n via `flutter gen-l10n`, Swift (AppDelegate), C++ (Windows runner), Astro markdown (privacy page), Inno Setup.

**Spec:** `docs/superpowers/specs/2026-10-07-desktop-restore-a5a-design.md` (binding; R0–R8 and D1–D26 are final). **UI design:** `docs/superpowers/design/2026-10-07-shellx-desktop-ui-a5.md` §1–§5 and §9 rows marked A5a ("UI-A5 §N"), on top of UI-A3, UI-A4, UI-A2, UI-A1. Executors read the spec and UI-A5 before Task 1.

## Prerequisite: A3 must be merged first

A5a executes **after A3 (`feat/desktop-a3`) is merged into `main`** (which itself follows A4). Start `feat/desktop-a5a` from that `main`. A5a needs A3's `PaneNode`/`PaneLeaf`/`PaneSplit`/`SplitAxis`/`paneIds`/`removePane` (`terminal/pane_layout.dart`), `PaneSession`, the pane-tree `TerminalTab` (`layout`, `panes`, `focusedPaneId`, `zoomedPaneId`, `paneHistory`, `customTitle`), `TerminalTabs._attach(summary, {size})`, `_awaitingOpen`, `_replaceTab`, `_visibleChanged`, `PaneMetrics`, and `LocalSessions.open({cols, rows, cwd})` with `FakeLocalSessions.openCwds`.

Before Task 1 run both full suites on the fresh branch and record the counts (they must stay green throughout):

```bash
cd packages/shellx_agent && ~/fvm/versions/3.41.4/bin/dart test
cd ../../apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test
```

## Global Constraints

- The spec wins over everything else; UI-A5 (then UI-A3, UI-A4, UI-A2, UI-A1) wins for visuals and copy. Never invent a colour, size, duration or string. **No new colour tokens** (UI-A5 §1).
- Toolchain: Flutter `~/fvm/versions/3.41.4/bin/flutter`, Dart `~/fvm/versions/3.41.4/bin/dart`. Desktop tests: `cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test`. Format: `~/fvm/versions/3.41.4/bin/dart format --set-exit-if-changed <paths>`. Analyze: `cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter analyze`.
- **No agent, protocol, phone, relay or `term/` change:** no edits under `packages/`, `apps/mobile`, `relay/`, `term/`.
- **Saved text never reaches a shell or a phone (D8):** it is written only into the desktop `DesktopTerminal` through its `TerminalFeed`; never `LocalSessionView.write/reply`, never the agent.
- **Never persist raw PTY bytes (D5)**; only `encodeScrollback` output. **Always sanitize on load (D6).**
- Limits (D5, D26): 2,000 logical lines and 262,144 UTF-8 bytes per pane; a scrollback file over 524,288 bytes is ignored on load.
- Files (D2): macOS `<getApplicationSupportDirectory()>/restore/`; Windows `%LOCALAPPDATA%\ShellX\restore\`. Directories 0700, files 0600 set **before** content (POSIX), atomic temp + rename. File names are pane keys (32 lowercase hex), never user data.
- Privacy (A4 N9 extended by D22): no terminal text, titles, cwd or file paths in logs — log only `runtimeType` and fixed tags such as `restore: layout unreadable (FormatException)`.
- Timings: layout debounce **1 s**; dirty scrollback period **60 s**; power-off save bounded **2 s** (Dart) / **3 s** (macOS reply timeout); quit save bounded 2 s.
- l10n: every new string goes into both `apps/desktop/lib/l10n/app_en.arb` (with `@key` metadata) and `app_vi.arb` with identical keys, then `cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter gen-l10n`; commit the generated `lib/l10n/app_localizations*.dart`.
- Code style: match the surrounding code (doc comments that say *why*, `final class`, no `print`). Every task ends with its tests green, format and analyzer clean on touched files, the full desktop suite green, and a commit with a conventional message. Commit only the files the task lists — **never `git add -A`**.

## Review Focus

1. **A session that appears while restore is opening panes** (a phone opens one; the user presses ⌘T mid-restore) — it must become its own tab and never be grafted into a restored tree, and no restored pane may become a stray tab. Pinned by the "concurrent open during restore" test in Task 4.
2. **Wide characters, combining marks and wrapped lines at the 2,000-line / 256 KiB boundary** — no duplicated CJK glyph, no split UTF-8 or SGR sequence, a wrapped line counted once. Pinned by the codec boundary tests in Task 1.
3. **A tampered or half-written scrollback/layout file** (OSC 52 clipboard write, title change, invalid UTF-8, 10 MB file, truncated JSON) — nothing but SGR and printable text reaches xterm; a bad layout becomes `.bak` and the app starts fresh. Pinned by the sanitizer tests in Task 1 and the store tests in Task 3.
4. **Turning "Lưu nội dung terminal khi thoát" off while a periodic save is in flight** — the files must end up deleted, not re-created by the in-flight write. Pinned by the serial-queue test in Task 3 and the toggle test in Task 5.
5. **A saved cwd that is gone, on a hung network mount, or UNC** — the pane starts at home within 300 ms (A3 D17) and restore never stalls the selected tab. Pinned by the `openCwds`/order test in Task 4 (the agent side is A3's hang test).

---

## File Structure

| File | Responsibility |
|---|---|
| Create `apps/desktop/lib/src/restore/scrollback_codec.dart` | `encodeScrollback`, `sanitizeRestored`, `restoreDivider`, `formatRestoreTime` (D5, D6, D8, D23) |
| Create `apps/desktop/lib/src/restore/restore_snapshot.dart` | `RestoreSnapshot`, `SavedTab`, `SavedPaneNode`/`SavedPane`/`SavedSplit`, `SavedWorkspace`, JSON v1, `captureSnapshot`, `buildLayout`, `newPaneKey` (D1, D11, D14, D21) |
| Create `apps/desktop/lib/src/restore/restore_paths.dart` | `restoreDirectoryPath` (D2) |
| Create `apps/desktop/lib/src/restore/restore_store.dart` | `RestoreStore`: prepare, load/write layout, scrollback files, `.bak`, orphans, serial queue (D2, D3, D11, D15, D25) |
| Create `apps/desktop/lib/src/restore/restore_persistence.dart` | `RestorePersistence` Notifier + providers: keys, dirty set, debounce, 60 s timer, `flushAll`, toggle, `restoreAtStartup`, strip state (D4, D7, D12–D16) |
| Modify `apps/desktop/lib/src/terminal/terminal_tabs.dart` | `restore(RestorePlan)`, `paneOutputs`, `_restoreText`, `_restoreHeld`, `_awaitingOpens` counter |
| Modify `apps/desktop/lib/src/terminal/sidebar_workspaces.dart` | `adopt(...)` |
| Modify `apps/desktop/lib/src/platform/settings_store.dart` | `SettingKeys.terminalRestoreScrollback` |
| Modify `apps/desktop/lib/src/tray/tray_action.dart`, `tray_menu.dart`, `tray_presenter.dart`, `tray_actions.dart` | "Terminal" submenu, `TrayLocalState` |
| Modify `apps/desktop/lib/l10n/app_en.arb`, `app_vi.arb` (+ generated) | UI-A5 §9 A5a strings |
| Create `apps/desktop/lib/src/ui/terminal/info_strip.dart` | `InfoStrip` (UI-A5 §4; reused by A5b §7.5) |
| Modify `apps/desktop/lib/src/ui/terminal/terminal_pane.dart`, `terminal_overlays.dart` | strip placement, `RestorePanesFailedNotice` toast |
| Modify `apps/desktop/lib/src/platform/app_reopen.dart` | `saveBeforeExit` channel method |
| Modify `apps/desktop/lib/main.dart` | store, restore before `handleActivation`, save on hide/quit |
| Modify `apps/desktop/macos/Runner/AppDelegate.swift` | `.terminateLater` + `saveBeforeExit` (D18) |
| Modify `apps/desktop/windows/runner/flutter_window.cpp`, `flutter_window.h` | `WM_QUERYENDSESSION` → `saveBeforeExit` (D18) |
| Modify `web/src/pages/privacy.md`, `web/src/pages/en/privacy.md` | §4 bullet (D22) |
| Modify `release/windows/shellx.iss`, `release/tests/inno.test.mjs` | uninstall deletes `restore` (D22) |
| Modify `docs/superpowers/HANDOFF.md` | §15 manual checklist |
| Tests: `apps/desktop/test/restore/{scrollback_codec,restore_snapshot,restore_store,restore_persistence}_test.dart`, `test/terminal/terminal_tabs_restore_test.dart`, `test/tray/tray_terminal_menu_test.dart`, `test/ui/info_strip_test.dart` | |

---

### Task 1: Scrollback codec — encode from xterm cells, sanitize on load, divider and time (D5, D6, D8, D23, D26)

**Files:**
- Create: `apps/desktop/lib/src/restore/scrollback_codec.dart`
- Test: `apps/desktop/test/restore/scrollback_codec_test.dart`

**Interfaces:**
- Consumes: xterm 4.0.0 `Terminal`, `BufferLine` (`getCodePoint`, `getWidth`, `getForeground`, `getBackground`, `getAttributes`, `getTrimmedLength`, `isWrapped`, `length`), `CellAttr`, `CellColor`.
- Produces:
  - `const int kRestoreMaxLines = 2000; const int kRestoreMaxBytes = 262144; const int kRestoreMaxFileBytes = 524288;`
  - `String encodeScrollback(Terminal terminal, {int maxLines = kRestoreMaxLines, int maxBytes = kRestoreMaxBytes})` — `''` when nothing to save; otherwise logical lines joined by `\r\n` with a trailing `\r\n`.
  - `String sanitizeRestored(String text)`
  - `String restoreDivider(String label)` → `'\x1b[0m\x1b[2m$label\x1b[0m\r\n'`
  - `String formatRestoreTime(DateTime saved, DateTime now, {required String localeName, required String Function(String time) yesterday})`

- [ ] **Step 1: Write the failing tests**

Create `apps/desktop/test/restore/scrollback_codec_test.dart`:

```dart
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/restore/scrollback_codec.dart';
import 'package:xterm/xterm.dart';

Terminal term({int cols = 80, int rows = 24}) =>
    Terminal(maxLines: 10000)..resize(cols, rows);

void main() {
  group('encodeScrollback', () {
    test('plain lines, trailing blank rows dropped, CRLF joined', () {
      final t = term()..write('hello\r\nworld\r\n\r\n');
      expect(encodeScrollback(t), 'hello\r\nworld\r\n');
    });

    test('empty terminal gives an empty string', () {
      expect(encodeScrollback(term()), '');
    });

    test('16, 256 and truecolor foreground/background + attributes', () {
      final t = term()
        ..write('\x1b[31mred\x1b[0m \x1b[1;4;38;5;208mo\x1b[0m '
            '\x1b[48;2;1;2;3mbg\x1b[0m \x1b[7;9;3;2mx\x1b[0m\r\n');
      final out = encodeScrollback(t);
      expect(out, contains('\x1b[0;31mred'));
      expect(out, contains('\x1b[0;1;4;38;5;208mo'));
      expect(out, contains('\x1b[0;48;2;1;2;3mbg'));
      expect(out, contains('\x1b[0;2;3;7;9mx'));
      expect(out, endsWith('\x1b[0m\r\n'));
      // Bright named colours use 90–97.
      final b = term()..write('\x1b[92mg\x1b[0m\r\n');
      expect(encodeScrollback(b), contains('\x1b[0;92mg'));
    });

    test('blink is dropped, invisible cells become spaces', () {
      final t = term()..write('a\x1b[5mb\x1b[0m\x1b[8msecret\x1b[0mc\r\n');
      final out = encodeScrollback(t);
      expect(out, isNot(contains('secret')));
      expect(out.replaceAll(RegExp(r'\x1b\[[0-9;]*m'), ''), 'ab      c\r\n');
    });

    test('a wrapped line is one logical line (rewraps at a new width)', () {
      final t = term(cols: 10)..write('${'x' * 25}\r\nnext\r\n');
      expect(encodeScrollback(t), '${'x' * 25}\r\nnext\r\n');
    });

    test('wide characters are written once; gaps become spaces', () {
      final t = term()..write('中文 ok\r\na\x1b[5Cb\r\n');
      expect(encodeScrollback(t), '中文 ok\r\na     b\r\n');
    });

    test('only the main buffer is saved while an alt screen is shown', () {
      final t = term()
        ..write('shell line\r\n')
        ..write('\x1b[?1049h') // vim enters the alt screen
        ..write('VIM SCREEN');
      expect(t.isUsingAltBuffer, isTrue);
      final out = encodeScrollback(t);
      expect(out, contains('shell line'));
      expect(out, isNot(contains('VIM SCREEN')));
    });

    test('keeps the last 2000 logical lines', () {
      final t = term();
      for (var i = 1; i <= 5000; i++) {
        t.write('$i\r\n');
      }
      final lines = encodeScrollback(t).split('\r\n')..removeLast();
      expect(lines.length, 2000);
      expect(lines.first, '3001');
      expect(lines.last, '5000');
    });

    test('byte cap drops whole oldest lines, never splits UTF-8 or SGR', () {
      final t = term(cols: 200);
      for (var i = 0; i < 10; i++) {
        t.write('\x1b[32m${'ế' * 150}\x1b[0m$i\r\n');
      }
      final out = encodeScrollback(t, maxBytes: 2000);
      expect(utf8.encode(out).length, lessThanOrEqualTo(2000));
      expect(out, endsWith('9\r\n'));
      for (final line in out.split('\r\n')..removeLast()) {
        expect(line, startsWith('\x1b[0;32m'));
        expect(line, matches(RegExp(r'\x1b\[0m\d$')));
      }
      expect(() => utf8.decode(utf8.encode(out)), returnsNormally);
    });

    test('round trip: encode → write into a fresh terminal → encode', () {
      final a = term()
        ..write('\x1b[1;35mbold magenta\x1b[0m plain \x1b[38;2;9;8;7mrgb\x1b[0m\r\n'
            'second\r\n');
      final once = encodeScrollback(a);
      final b = term()..write(once);
      expect(encodeScrollback(b), once);
    });
  });

  group('sanitizeRestored', () {
    test('keeps text, CR, LF, TAB, Vietnamese and valid SGR', () {
      const ok = 'Xin chào\t\x1b[0;31mđỏ\x1b[0m\r\n';
      expect(sanitizeRestored(ok), ok);
    });

    test('removes OSC 52, OSC 0, other CSI, DCS, C1, BEL and lone ESC', () {
      const evil = 'a\x1b]52;c;ZXZpbA==\x07b\x1b]0;title\x1b\\c'
          '\x1b[2Jd\x1b[?1049he\x1bPqdcs\x1b\\f\u009b31mg\x07h\x1bZi'
          '\x1b[38;5;1;2;3;4;5;6;7;8;9;10;11;12;13;14;15;16;17;18;19;20;21;22;23m';
      expect(sanitizeRestored(evil), 'abcdefghi');
    });
  });

  group('divider and time', () {
    test('divider bytes', () {
      expect(
        restoreDivider('— Phiên được khôi phục · 14:32 —'),
        '\x1b[0m\x1b[2m— Phiên được khôi phục · 14:32 —\x1b[0m\r\n',
      );
    });

    test('today, yesterday, older — vi and en, always 24 h', () {
      final now = DateTime(2026, 10, 7, 9, 0);
      String vi(DateTime d) => formatRestoreTime(d, now,
          localeName: 'vi', yesterday: (t) => 'hôm qua $t');
      String en(DateTime d) => formatRestoreTime(d, now,
          localeName: 'en', yesterday: (t) => 'yesterday $t');
      expect(vi(DateTime(2026, 10, 7, 8, 5)), '08:05');
      expect(vi(DateTime(2026, 10, 6, 14, 32)), 'hôm qua 14:32');
      expect(en(DateTime(2026, 10, 6, 14, 32)), 'yesterday 14:32');
      expect(vi(DateTime(2026, 10, 1, 14, 32)), '1/10 14:32');
      expect(en(DateTime(2026, 10, 1, 14, 32)), 'Oct 1 14:32');
    });
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/restore/scrollback_codec_test.dart`
Expected: FAIL — `scrollback_codec.dart` does not exist.

- [ ] **Step 3: Implement**

Create `apps/desktop/lib/src/restore/scrollback_codec.dart`:

```dart
import 'dart:convert';

import 'package:xterm/xterm.dart';

/// A5a D5, D26: what one pane keeps.
const int kRestoreMaxLines = 2000;
const int kRestoreMaxBytes = 262144;

/// D6: a larger file is not a file we wrote.
const int kRestoreMaxFileBytes = 524288;

const int _keptAttrs =
    CellAttr.bold |
    CellAttr.faint |
    CellAttr.italic |
    CellAttr.underline |
    CellAttr.inverse |
    CellAttr.strikethrough;

/// The main buffer's last [maxLines] logical lines (wrapped rows joined),
/// re-encoded from the cells as printable text + SGR only (D5): never the
/// PTY's bytes, so no title, clipboard, mouse-mode or alt-screen sequence
/// can ever be saved. Lines are joined by CRLF with a trailing CRLF; blank
/// rows at the end are dropped; oldest whole lines go first when the UTF-8
/// size would pass [maxBytes]. Empty string: nothing worth saving.
String encodeScrollback(
  Terminal terminal, {
  int maxLines = kRestoreMaxLines,
  int maxBytes = kRestoreMaxBytes,
}) {
  final lines = terminal.mainBuffer.lines;
  var end = lines.length - 1;
  // Trailing blank rows (the empty screen under the prompt).
  while (end >= 0 &&
      lines[end].getTrimmedLength() == 0 &&
      (end + 1 >= lines.length || !lines[end + 1].isWrapped)) {
    end--;
  }
  final newestFirst = <String>[];
  var bytes = 0;
  while (end >= 0 && newestFirst.length < maxLines) {
    var start = end;
    // `isWrapped` marks a row that continues the row above it.
    while (start > 0 && lines[start].isWrapped) {
      start--;
    }
    final text = _encodeRows(lines, start, end);
    final size = utf8.encode(text).length + 2;
    if (bytes + size > maxBytes) break;
    bytes += size;
    newestFirst.add(text);
    end = start - 1;
  }
  if (newestFirst.isEmpty) return '';
  return '${newestFirst.reversed.join('\r\n')}\r\n';
}

String _encodeRows(dynamic lines, int start, int end) {
  final out = StringBuffer();
  var fg = 0, bg = 0, attrs = 0; // the terminal default
  var styled = false;
  for (var row = start; row <= end; row++) {
    final BufferLine line = lines[row];
    // The last row of a logical line stops at its text; earlier rows of a
    // wrapped line are full width.
    final width = row == end ? line.getTrimmedLength() : line.length;
    for (var i = 0; i < width; i++) {
      final cellWidth = line.getWidth(i);
      if (cellWidth == 0) continue; // the right half of a wide character
      var code = line.getCodePoint(i);
      var a = line.getAttributes(i);
      if (a & CellAttr.invisible != 0) code = 0x20;
      a &= _keptAttrs;
      final f = line.getForeground(i);
      final b = line.getBackground(i);
      if (f != fg || b != bg || a != attrs) {
        out.write(_sgr(f, b, a));
        fg = f;
        bg = b;
        attrs = a;
        styled = true;
      }
      out.writeCharCode(code == 0 ? 0x20 : code);
    }
  }
  if (styled && (fg != 0 || bg != 0 || attrs != 0)) out.write('\x1b[0m');
  return out.toString();
}

String _sgr(int fg, int bg, int attrs) {
  final p = <Object>[0];
  if (attrs & CellAttr.bold != 0) p.add(1);
  if (attrs & CellAttr.faint != 0) p.add(2);
  if (attrs & CellAttr.italic != 0) p.add(3);
  if (attrs & CellAttr.underline != 0) p.add(4);
  if (attrs & CellAttr.inverse != 0) p.add(7);
  if (attrs & CellAttr.strikethrough != 0) p.add(9);
  p
    ..addAll(_colour(fg, foreground: true))
    ..addAll(_colour(bg, foreground: false));
  return '\x1b[${p.join(';')}m';
}

List<Object> _colour(int c, {required bool foreground}) {
  final value = c & CellColor.valueMask;
  switch (c & CellColor.typeMask) {
    case CellColor.named:
      return value < 8
          ? [(foreground ? 30 : 40) + value]
          : [(foreground ? 90 : 100) + value - 8];
    case CellColor.palette:
      return [foreground ? 38 : 48, 5, value];
    case CellColor.rgb:
      return [
        foreground ? 38 : 48,
        2,
        (value >> 16) & 0xFF,
        (value >> 8) & 0xFF,
        value & 0xFF,
      ];
    default:
      return const [];
  }
}

final RegExp _sgrPattern = RegExp(r'\x1b\[[0-9;:]{0,64}m');

/// D6: the file is untrusted on load. Keeps printable characters (Unicode
/// included), CR, LF, TAB and well-formed SGR; every other escape sequence
/// (CSI, OSC up to BEL/ST, DCS/SOS/PM/APC up to ST, two-byte ESC), C0, DEL
/// and C1 is removed with its parameters.
String sanitizeRestored(String text) {
  final out = StringBuffer();
  var i = 0;
  while (i < text.length) {
    final c = text.codeUnitAt(i);
    if (c == 0x1b) {
      final sgr = _sgrPattern.matchAsPrefix(text, i);
      if (sgr != null) {
        out.write(sgr[0]);
        i = sgr.end;
        continue;
      }
      i = _skipEscape(text, i);
      continue;
    }
    final printable =
        c == 0x09 ||
        c == 0x0a ||
        c == 0x0d ||
        (c >= 0x20 && c != 0x7f && (c < 0x80 || c > 0x9f));
    if (printable) out.writeCharCode(c);
    i++;
  }
  return out.toString();
}

/// Index just past the escape sequence starting at [i] (an ESC).
int _skipEscape(String text, int i) {
  if (i + 1 >= text.length) return i + 1;
  final kind = text[i + 1];
  if (kind == '[') {
    var j = i + 2;
    while (j < text.length) {
      final c = text.codeUnitAt(j);
      j++;
      if (c >= 0x40 && c <= 0x7e) break; // final byte
    }
    return j;
  }
  if (kind == ']' || kind == 'P' || kind == 'X' || kind == '^' || kind == '_') {
    var j = i + 2;
    while (j < text.length) {
      final c = text.codeUnitAt(j);
      if (c == 0x07) return j + 1;
      if (c == 0x1b && j + 1 < text.length && text[j + 1] == r'\') {
        return j + 2;
      }
      j++;
    }
    return j;
  }
  return i + 2; // ESC + one byte
}

/// D8: one dim line under the restored text, never sent to the shell.
String restoreDivider(String label) => '\x1b[0m\x1b[2m$label\x1b[0m\r\n';

const List<String> _enMonths = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// D23: local time of the pane's last save, 24 h: today → "14:32";
/// yesterday → [yesterday]("14:32"); older → "6/10 14:32" (vi) or
/// "Oct 6 14:32" (en).
String formatRestoreTime(
  DateTime saved,
  DateTime now, {
  required String localeName,
  required String Function(String time) yesterday,
}) {
  final local = saved.toLocal();
  final hm =
      '${local.hour.toString().padLeft(2, '0')}:'
      '${local.minute.toString().padLeft(2, '0')}';
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(local.year, local.month, local.day);
  final days = today.difference(day).inDays;
  if (days == 0) return hm;
  if (days == 1) return yesterday(hm);
  return localeName.startsWith('vi')
      ? '${local.day}/${local.month} $hm'
      : '${_enMonths[local.month - 1]} ${local.day} $hm';
}
```

If the "wide characters" test shows the right half of a wide character reported with `getWidth == 1` and code point 0 in xterm 4.0.0, change the skip to `if (cellWidth == 0 || (i > 0 && line.getWidth(i - 1) == 2)) continue;` and keep the test unchanged.

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/restore/scrollback_codec_test.dart`
Expected: PASS (all groups).

- [ ] **Step 5: Format, analyze, commit**

```bash
~/fvm/versions/3.41.4/bin/dart format --set-exit-if-changed apps/desktop/lib/src/restore/scrollback_codec.dart apps/desktop/test/restore/scrollback_codec_test.dart
cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter analyze lib/src/restore test/restore && cd ../..
git add apps/desktop/lib/src/restore/scrollback_codec.dart apps/desktop/test/restore/scrollback_codec_test.dart
git commit -m "feat(desktop): scrollback codec — SGR-only encoding from xterm cells, load sanitizer, restore divider (A5a D5, D6, D8, D23)"
```

---

### Task 2: Snapshot model — JSON v1, strict validation, capture, layout rebuild (D1, D9–D11, D14, D21)

**Files:**
- Create: `apps/desktop/lib/src/restore/restore_snapshot.dart`
- Test: `apps/desktop/test/restore/restore_snapshot_test.dart`

**Interfaces:**
- Consumes: A3 `PaneNode`, `PaneLeaf`, `PaneSplit`, `SplitAxis`, `clampRatio`, `kMinPaneRatio`; `TerminalTabsState`, `TerminalTab` (`id`, `layout`, `panes`, `focusedPaneId`, `zoomedPaneId`, `customTitle`), `PaneSession` (`cwd`, `exited`); `SidebarState` (`workspaces`, `tabsOf`), `kDefaultWorkspaceId`.
- Produces:
  - `String newPaneKey([Random? random])` — 32 lowercase hex; `bool isPaneKey(String)`.
  - `sealed class SavedPaneNode`; `final class SavedPane extends SavedPaneNode { const SavedPane({required String key, String? cwd, int? session}); }`; `final class SavedSplit extends SavedPaneNode { const SavedSplit({required SplitAxis axis, required double ratio, required SavedPaneNode first, required SavedPaneNode second}); }`
  - `List<SavedPane> savedLeaves(SavedPaneNode node)` (reading order)
  - `final class SavedTab { const SavedTab({required String key, String? name, required String focused, String? zoomed, required SavedPaneNode layout}); }`
  - `final class SavedWorkspace { const SavedWorkspace({required String id, required List<String> tabs}); }`
  - `final class RestoreSnapshot { const RestoreSnapshot({required DateTime savedAt, required bool cleanExit, String? daemon, String? selectedTab, required List<SavedWorkspace> workspaces, required List<SavedTab> tabs}); String encode(); static RestoreSnapshot? tryParse(String text); RestoreSnapshot copyWith({DateTime? savedAt, bool? cleanExit}); Set<String> get paneKeys; bool sameLayoutAs(RestoreSnapshot other); }` (`sameLayoutAs` ignores `savedAt`/`cleanExit`)
  - `RestoreSnapshot captureSnapshot({required TerminalTabsState tabs, required SidebarState sidebar, required String Function(int sessionId) keyOf, required DateTime now, required bool cleanExit, String? daemon})`
  - `PaneNode? buildLayout(SavedPaneNode node, Map<String, int> sessionByKey)`

- [ ] **Step 1: Write the failing tests**

Create `apps/desktop/test/restore/restore_snapshot_test.dart`:

```dart
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/restore/restore_snapshot.dart';
import 'package:shellx_desktop/src/terminal/pane_layout.dart';

final k1 = 'a' * 32, k2 = 'b' * 32, k3 = 'c' * 32;

RestoreSnapshot sample() => RestoreSnapshot(
  savedAt: DateTime.utc(2026, 10, 7, 14, 32),
  cleanExit: false,
  selectedTab: k1,
  workspaces: [SavedWorkspace(id: 'default', tabs: [k1])],
  tabs: [
    SavedTab(
      key: k1,
      name: 'server',
      focused: k2,
      zoomed: k2,
      layout: SavedSplit(
        axis: SplitAxis.row,
        ratio: 0.3,
        first: SavedPane(key: k1, cwd: '/Users/a/w', session: 12),
        second: SavedSplit(
          axis: SplitAxis.column,
          ratio: 0.5,
          first: SavedPane(key: k2, session: 15),
          second: SavedPane(key: k3, cwd: '/tmp', session: 16),
        ),
      ),
    ),
  ],
);

void main() {
  test('pane keys are 32 lowercase hex', () {
    final k = newPaneKey();
    expect(isPaneKey(k), isTrue);
    expect(k, matches(RegExp(r'^[0-9a-f]{32}$')));
    expect(isPaneKey('../etc/passwd'), isFalse);
  });

  test('JSON round trip, v1 shape', () {
    final text = sample().encode();
    final map = jsonDecode(text) as Map<String, Object?>;
    expect(map['v'], 1);
    expect(map['daemon'], isNull);
    final back = RestoreSnapshot.tryParse(text)!;
    expect(back.encode(), text);
    expect(back.paneKeys, {k1, k2, k3});
    expect(savedLeaves(back.tabs.single.layout).map((p) => p.key), [k1, k2, k3]);
  });

  test('unknown keys are ignored', () {
    final map = jsonDecode(sample().encode()) as Map<String, Object?>;
    map['future'] = {'x': 1};
    expect(RestoreSnapshot.tryParse(jsonEncode(map)), isNotNull);
  });

  group('rejects (D11)', () {
    Map<String, Object?> base() =>
        jsonDecode(sample().encode()) as Map<String, Object?>;
    final cases = <String, String Function()>{
      'not JSON': () => '{"v":1,',
      'not a map': () => '[]',
      'version 2': () => jsonEncode(base()..['v'] = 2),
      'bad key': () {
        final m = base();
        ((m['tabs'] as List).first as Map)['key'] = 'nope';
        return jsonEncode(m);
      },
      'ratio out of range': () {
        final m = base();
        (((m['tabs'] as List).first as Map)['layout'] as Map)['ratio'] = 0.99;
        return jsonEncode(m);
      },
      'duplicate pane key': () {
        final m = base();
        final layout = ((m['tabs'] as List).first as Map)['layout'] as Map;
        ((layout['second'] as Map)['first'] as Map)['pane'] = k1;
        return jsonEncode(m);
      },
      'focused not in tree': () {
        final m = base();
        ((m['tabs'] as List).first as Map)['focused'] = 'd' * 32;
        return jsonEncode(m);
      },
      'name too long': () {
        final m = base();
        ((m['tabs'] as List).first as Map)['name'] = 'x' * 65;
        return jsonEncode(m);
      },
      'more than 32 panes': () {
        final m = base();
        final tabs = m['tabs'] as List;
        for (var i = 0; i < 31; i++) {
          final key = i.toRadixString(16).padLeft(32, '0');
          tabs.add({
            'key': key,
            'focused': key,
            'layout': {'pane': key},
          });
        }
        return jsonEncode(m);
      },
    };
    for (final MapEntry(:key, :value) in cases.entries) {
      test(key, () => expect(RestoreSnapshot.tryParse(value()), isNull));
    }
  });

  test('sameLayoutAs ignores savedAt and cleanExit', () {
    final a = sample();
    final b = a.copyWith(savedAt: DateTime.utc(2030), cleanExit: true);
    expect(a.sameLayoutAs(b), isTrue);
  });

  test('buildLayout replaces keys by sessions and drops missing panes', () {
    final layout = sample().tabs.single.layout;
    expect(
      buildLayout(layout, {k1: 7, k2: 8, k3: 9}),
      const PaneSplit(
        axis: SplitAxis.row,
        ratio: 0.3,
        first: PaneLeaf(7),
        second: PaneSplit(
          axis: SplitAxis.column,
          ratio: 0.5,
          first: PaneLeaf(8),
          second: PaneLeaf(9),
        ),
      ),
    );
    expect(
      buildLayout(layout, {k1: 7, k3: 9}),
      const PaneSplit(
        axis: SplitAxis.row,
        ratio: 0.3,
        first: PaneLeaf(7),
        second: PaneLeaf(9),
      ),
    );
    expect(buildLayout(layout, const {}), isNull);
  });
}
```

Append a capture test that builds state from `FakeLocalSessions` + the real providers (exited panes skipped, D9):

```dart
// Add imports:
// import 'package:flutter_riverpod/flutter_riverpod.dart';
// import 'package:shellx_desktop/l10n/app_localizations.dart';
// import 'package:shellx_desktop/src/terminal/local_sessions_provider.dart';
// import 'package:shellx_desktop/src/terminal/sidebar_workspaces.dart';
// import 'package:shellx_desktop/src/terminal/terminal_tabs.dart';
// import 'package:shellx_desktop/src/platform/settings_store.dart';
// import 'dart:ui' show Locale;
// import '../support/fake_local_sessions.dart';

  test('captureSnapshot: tabs, membership, names, tree; exited panes skipped',
      () async {
    final local = FakeLocalSessions();
    local
      ..add(local.summary(1, cwd: '/w/one'))
      ..add(local.summary(2));
    final container = ProviderContainer.test(
      overrides: [
        localSessionsProvider.overrideWithValue(local),
        settingsStoreProvider.overrideWithValue(InMemorySettingsStore()),
        appL10nProvider.overrideWithValue(
          lookupAppLocalizations(const Locale('en')),
        ),
      ],
    );
    container.read(sidebarWorkspacesProvider);
    container.read(terminalTabsProvider.notifier).rename(2, 'logs');
    local.views[1]!.end(3); // exit ≠ 0: kept on screen, not restored
    await pumpEventQueue();
    final keys = <int, String>{1: k1, 2: k2};
    final s = captureSnapshot(
      tabs: container.read(terminalTabsProvider),
      sidebar: container.read(sidebarWorkspacesProvider),
      keyOf: (id) => keys[id]!,
      now: DateTime.utc(2026),
      cleanExit: true,
    );
    expect(s.tabs.map((t) => t.key), [k2]);
    expect(s.tabs.single.name, 'logs');
    expect(s.workspaces.single.tabs, [k2]);
    expect(s.selectedTab, isNull); // the selected tab (1) is not restorable
  });
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/restore/restore_snapshot_test.dart`
Expected: FAIL — `restore_snapshot.dart` does not exist.

- [ ] **Step 3: Implement**

Create `apps/desktop/lib/src/restore/restore_snapshot.dart`:

```dart
import 'dart:convert';
import 'dart:math';

import '../terminal/pane_layout.dart';
import '../terminal/sidebar_workspaces.dart';
import '../terminal/terminal_tabs.dart';

const int _version = 1;
const int _maxPanes = 32;
const int _maxDepth = 32;
const int _maxName = 64;
const int _maxCwd = 4096;
final RegExp _keyPattern = RegExp(r'^[0-9a-f]{32}$');

/// D14: a pane's restore key, never derived from user data.
String newPaneKey([Random? random]) {
  final r = random ?? Random.secure();
  return List.generate(16, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0'))
      .join();
}

bool isPaneKey(String text) => _keyPattern.hasMatch(text);

sealed class SavedPaneNode {
  const SavedPaneNode();
}

final class SavedPane extends SavedPaneNode {
  const SavedPane({required this.key, this.cwd, this.session});
  final String key;
  final String? cwd;

  /// D21: written for A5b, ignored by A5a on load.
  final int? session;
}

final class SavedSplit extends SavedPaneNode {
  const SavedSplit({
    required this.axis,
    required this.ratio,
    required this.first,
    required this.second,
  });
  final SplitAxis axis;
  final double ratio;
  final SavedPaneNode first, second;
}

List<SavedPane> savedLeaves(SavedPaneNode node) => switch (node) {
  SavedPane() => [node],
  SavedSplit(:final first, :final second) => [
    ...savedLeaves(first),
    ...savedLeaves(second),
  ],
};

final class SavedTab {
  const SavedTab({
    required this.key,
    this.name,
    required this.focused,
    this.zoomed,
    required this.layout,
  });

  /// The key of the pane that created the tab (A3 D1).
  final String key;
  final String? name;
  final String focused;
  final String? zoomed;
  final SavedPaneNode layout;
}

final class SavedWorkspace {
  const SavedWorkspace({required this.id, required this.tabs});
  final String id;
  final List<String> tabs;
}

/// `restore/layout.json` v1 (spec §3.1).
final class RestoreSnapshot {
  const RestoreSnapshot({
    required this.savedAt,
    required this.cleanExit,
    this.daemon,
    this.selectedTab,
    required this.workspaces,
    required this.tabs,
  });

  final DateTime savedAt;
  final bool cleanExit;

  /// D21: the A5b daemon instance; always null in A5a.
  final String? daemon;
  final String? selectedTab;
  final List<SavedWorkspace> workspaces;
  final List<SavedTab> tabs;

  Set<String> get paneKeys => {
    for (final t in tabs) ...savedLeaves(t.layout).map((p) => p.key),
  };

  RestoreSnapshot copyWith({DateTime? savedAt, bool? cleanExit}) =>
      RestoreSnapshot(
        savedAt: savedAt ?? this.savedAt,
        cleanExit: cleanExit ?? this.cleanExit,
        daemon: daemon,
        selectedTab: selectedTab,
        workspaces: workspaces,
        tabs: tabs,
      );

  /// Equal apart from [savedAt] and [cleanExit]: no write needed.
  bool sameLayoutAs(RestoreSnapshot other) =>
      jsonEncode(_body()) == jsonEncode(other._body());

  Map<String, Object?> _body() => {
    'daemon': daemon,
    'selectedTab': selectedTab,
    'workspaces': [
      for (final w in workspaces) {'id': w.id, 'tabs': w.tabs},
    ],
    'tabs': [
      for (final t in tabs)
        {
          'key': t.key,
          'name': t.name,
          'focused': t.focused,
          'zoomed': t.zoomed,
          'layout': _nodeToJson(t.layout),
        },
    ],
  };

  String encode() => jsonEncode({
    'v': _version,
    'savedAt': savedAt.toUtc().toIso8601String(),
    'cleanExit': cleanExit,
    ..._body(),
  });

  /// Null for anything that is not a well-formed v1 file (D11). Unknown
  /// keys are ignored so a later version's extra fields never break this.
  static RestoreSnapshot? tryParse(String text) {
    try {
      final root = jsonDecode(text);
      if (root is! Map<String, Object?> || root['v'] != _version) return null;
      final savedAt = DateTime.tryParse(root['savedAt'] as String? ?? '');
      final clean = root['cleanExit'];
      if (savedAt == null || clean is! bool) return null;
      final seen = <String>{};
      final tabs = <SavedTab>[];
      for (final raw in root['tabs'] as List<Object?>) {
        final t = raw as Map<String, Object?>;
        final layout = _nodeFromJson(t['layout'], seen, 0);
        final keys = savedLeaves(layout).map((p) => p.key).toSet();
        final key = t['key'] as String;
        final focused = t['focused'] as String;
        final zoomed = t['zoomed'] as String?;
        final name = t['name'] as String?;
        if (!isPaneKey(key) || !keys.contains(focused)) return null;
        if (zoomed != null && !keys.contains(zoomed)) return null;
        if (name != null && (name.isEmpty || name.length > _maxName)) {
          return null;
        }
        tabs.add(SavedTab(
          key: key,
          name: name,
          focused: focused,
          zoomed: zoomed,
          layout: layout,
        ));
      }
      if (seen.length > _maxPanes) return null;
      final tabKeys = {for (final t in tabs) t.key};
      final workspaces = <SavedWorkspace>[
        for (final raw in root['workspaces'] as List<Object?>)
          SavedWorkspace(
            id: (raw as Map<String, Object?>)['id'] as String,
            tabs: [
              for (final k in raw['tabs'] as List<Object?>)
                if (tabKeys.contains(k)) k as String,
            ],
          ),
      ];
      final selected = root['selectedTab'] as String?;
      return RestoreSnapshot(
        savedAt: savedAt,
        cleanExit: clean,
        daemon: root['daemon'] as String?,
        selectedTab: tabKeys.contains(selected) ? selected : null,
        workspaces: workspaces,
        tabs: tabs,
      );
    } on Object {
      // FormatException, TypeError from a cast, StateError: not ours.
      return null;
    }
  }
}

Object _nodeToJson(SavedPaneNode node) => switch (node) {
  SavedPane(:final key, :final cwd, :final session) => {
    'pane': key,
    'cwd': cwd,
    'session': session,
  },
  SavedSplit(:final axis, :final ratio, :final first, :final second) => {
    'split': axis.name,
    'ratio': ratio,
    'first': _nodeToJson(first),
    'second': _nodeToJson(second),
  },
};

SavedPaneNode _nodeFromJson(Object? raw, Set<String> seen, int depth) {
  if (depth > _maxDepth) throw const FormatException('too deep');
  final m = raw! as Map<String, Object?>;
  if (m.containsKey('pane')) {
    final key = m['pane']! as String;
    final cwd = m['cwd'] as String?;
    if (!isPaneKey(key) || !seen.add(key)) {
      throw const FormatException('pane key');
    }
    if (cwd != null && cwd.length > _maxCwd) throw const FormatException('cwd');
    return SavedPane(key: key, cwd: cwd, session: m['session'] as int?);
  }
  final axis = SplitAxis.values.byName(m['split']! as String);
  final ratio = (m['ratio']! as num).toDouble();
  if (ratio < kMinPaneRatio || ratio > 1 - kMinPaneRatio) {
    throw const FormatException('ratio');
  }
  return SavedSplit(
    axis: axis,
    ratio: ratio,
    first: _nodeFromJson(m['first'], seen, depth + 1),
    second: _nodeFromJson(m['second'], seen, depth + 1),
  );
}

/// What is restorable right now (D9: exited panes and tabs left with no
/// live pane are skipped).
RestoreSnapshot captureSnapshot({
  required TerminalTabsState tabs,
  required SidebarState sidebar,
  required String Function(int sessionId) keyOf,
  required DateTime now,
  required bool cleanExit,
  String? daemon,
}) {
  final saved = <int, SavedTab>{};
  for (final tab in tabs.tabs) {
    final layout = _save(tab.layout, tab, keyOf);
    if (layout == null) continue;
    final keys = savedLeaves(layout).map((p) => p.key).toSet();
    String? live(int? id) =>
        id != null && keys.contains(keyOf(id)) ? keyOf(id) : null;
    saved[tab.id] = SavedTab(
      key: keyOf(tab.id),
      name: tab.customTitle,
      focused: live(tab.focusedPaneId) ?? savedLeaves(layout).first.key,
      zoomed: live(tab.zoomedPaneId),
      layout: layout,
    );
  }
  return RestoreSnapshot(
    savedAt: now,
    cleanExit: cleanExit,
    daemon: daemon,
    selectedTab: saved[tabs.selectedId]?.key,
    workspaces: [
      for (final w in sidebar.workspaces)
        SavedWorkspace(
          id: w.id,
          tabs: [
            for (final id in sidebar.tabsOf(w.id))
              if (saved[id] case final t?) t.key,
          ],
        ),
    ],
    tabs: [
      for (final id in sidebar.orderedTabIds)
        if (saved[id] case final t?) t,
      // Tabs the sidebar has not placed yet keep creation order.
      for (final t in tabs.tabs)
        if (!sidebar.orderedTabIds.contains(t.id))
          if (saved[t.id] case final s?) s,
    ],
  );
}

SavedPaneNode? _save(PaneNode node, TerminalTab tab, String Function(int) keyOf) =>
    switch (node) {
      PaneLeaf(:final sessionId) => switch (tab.panes[sessionId]) {
        final pane? when !pane.exited => SavedPane(
          key: keyOf(sessionId),
          cwd: pane.cwd,
          session: sessionId,
        ),
        _ => null,
      },
      PaneSplit(:final axis, :final ratio, :final first, :final second) => () {
        final a = _save(first, tab, keyOf);
        final b = _save(second, tab, keyOf);
        if (a == null) return b;
        if (b == null) return a;
        return SavedSplit(axis: axis, ratio: ratio, first: a, second: b);
      }(),
    };

/// The saved tree with each pane replaced by its new session; panes that
/// could not be reopened are dropped and their sibling takes the place
/// (A3 D7). Null when no pane is left.
PaneNode? buildLayout(SavedPaneNode node, Map<String, int> sessionByKey) =>
    switch (node) {
      SavedPane(:final key) => switch (sessionByKey[key]) {
        final id? => PaneLeaf(id),
        null => null,
      },
      SavedSplit(:final axis, :final ratio, :final first, :final second) => () {
        final a = buildLayout(first, sessionByKey);
        final b = buildLayout(second, sessionByKey);
        if (a == null) return b;
        if (b == null) return a;
        return PaneSplit(axis: axis, ratio: ratio, first: a, second: b);
      }(),
    };
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/restore/restore_snapshot_test.dart`
Expected: PASS.

- [ ] **Step 5: Format, analyze, commit**

```bash
~/fvm/versions/3.41.4/bin/dart format --set-exit-if-changed apps/desktop/lib/src/restore/restore_snapshot.dart apps/desktop/test/restore/restore_snapshot_test.dart
cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter analyze lib/src/restore test/restore && cd ../..
git add apps/desktop/lib/src/restore/restore_snapshot.dart apps/desktop/test/restore/restore_snapshot_test.dart
git commit -m "feat(desktop): restore snapshot v1 — strict JSON, capture from tabs/workspaces, layout rebuild (A5a D1, D9-D11, D14, D21)"
```

---

### Task 3: Restore store — paths, permissions, atomic writes, `.bak`, scrollback files, serial queue (D2, D3, D6, D11, D15, D25)

**Files:**
- Create: `apps/desktop/lib/src/restore/restore_paths.dart`
- Create: `apps/desktop/lib/src/restore/restore_store.dart`
- Test: `apps/desktop/test/restore/restore_store_test.dart`

**Interfaces:**
- Consumes: Task 1 `sanitizeRestored`, `kRestoreMaxFileBytes`; Task 2 `RestoreSnapshot`, `isPaneKey`.
- Produces:
  - `String restoreDirectoryPath({required bool windows, required Map<String, String> environment, required String appSupportPath})`
  - `final class RestoreLoad { const RestoreLoad({this.snapshot, this.corrupt = false}); final RestoreSnapshot? snapshot; final bool corrupt; }`
  - `final class RestoreStore { RestoreStore(Directory directory, {bool? posix, Future<void> Function(String path)? excludeFromBackup, void Function(String message)? log}); Directory get directory; Future<bool> prepare(); Future<RestoreLoad> loadLayout(); Future<void> writeLayout(RestoreSnapshot snapshot); Future<void> writeScrollbacks(Map<String, String> textByKey); Future<String?> readScrollback(String key); Future<DateTime?> scrollbackSavedAt(String key); Future<void> deleteScrollback(String key); Future<void> deleteAllScrollback(); Future<bool> hasScrollback(); Future<void> removeOrphans(Set<String> keep); }`
  - `prepare()` returns false when POSIX permissions could not be set (D2 table row "§5": then scrollback is never written; `writeScrollbacks` is a no-op).

- [ ] **Step 1: Write the failing tests**

Create `apps/desktop/test/restore/restore_store_test.dart`:

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/restore/restore_paths.dart';
import 'package:shellx_desktop/src/restore/restore_snapshot.dart';
import 'package:shellx_desktop/src/restore/restore_store.dart';
import 'package:shellx_desktop/src/terminal/pane_layout.dart';

final k1 = 'a' * 32, k2 = 'b' * 32;

RestoreSnapshot snap() => RestoreSnapshot(
  savedAt: DateTime.utc(2026, 10, 7),
  cleanExit: false,
  selectedTab: k1,
  workspaces: [SavedWorkspace(id: 'default', tabs: [k1])],
  tabs: [SavedTab(key: k1, focused: k1, layout: SavedPane(key: k1, cwd: '/tmp'))],
);

String mode(String path) =>
    (Process.runSync('stat', ['-f', '%Lp', path]).stdout as String).trim();

void main() {
  late Directory root;
  late RestoreStore store;
  final excluded = <String>[];
  final logs = <String>[];

  setUp(() async {
    root = await Directory.systemTemp.createTemp('restore_store_test');
    excluded.clear();
    logs.clear();
    store = RestoreStore(
      Directory('${root.path}/restore'),
      excludeFromBackup: (p) async => excluded.add(p),
      log: logs.add,
    );
    expect(await store.prepare(), isTrue);
  });
  tearDown(() => root.delete(recursive: true));

  test('paths: macOS app support, Windows LOCALAPPDATA (D2)', () {
    expect(
      restoreDirectoryPath(windows: false, environment: const {},
          appSupportPath: '/Users/a/Library/Application Support/pro.shellx.desktop'),
      '/Users/a/Library/Application Support/pro.shellx.desktop/restore',
    );
    expect(
      restoreDirectoryPath(windows: true,
          environment: const {'LOCALAPPDATA': r'C:\Users\a\AppData\Local'},
          appSupportPath: r'C:\Users\a\AppData\Roaming\pro.shellx\ShellX'),
      r'C:\Users\a\AppData\Local\ShellX\restore',
    );
  });

  test('prepare: 0700 directories, excluded from backup once', () {
    expect(mode(store.directory.path), '700');
    expect(mode('${store.directory.path}/scrollback'), '700');
    expect(excluded, [store.directory.path]);
  }, testOn: 'mac-os');

  test('layout round trip, 0600, no temp files left', () async {
    await store.writeLayout(snap());
    final load = await store.loadLayout();
    expect(load.corrupt, isFalse);
    expect(load.snapshot!.encode(), snap().encode());
    expect(mode('${store.directory.path}/layout.json'), '600');
    expect(
      store.directory.listSync().map((e) => e.path).where((p) => p.contains('.tmp-')),
      isEmpty,
    );
  }, testOn: 'mac-os');

  test('no file → no snapshot, not corrupt', () async {
    final load = await store.loadLayout();
    expect(load.snapshot, isNull);
    expect(load.corrupt, isFalse);
  });

  test('corrupt layout → .bak, fresh start, content never logged (D11)',
      () async {
    File('${store.directory.path}/layout.json').writeAsStringSync('{"v":1, garbage /secret/path');
    final load = await store.loadLayout();
    expect(load.snapshot, isNull);
    expect(load.corrupt, isTrue);
    expect(File('${store.directory.path}/layout.json').existsSync(), isFalse);
    expect(File('${store.directory.path}/layout.json.bak').readAsStringSync(),
        contains('garbage'));
    expect(logs.join(), isNot(contains('secret')));
  });

  test('scrollback: batch write, sanitized read, 0600, delete', () async {
    await store.writeScrollbacks({k1: 'one\x1b]52;c;eA==\x07\r\n', k2: 'two\r\n'});
    expect(await store.readScrollback(k1), 'one\r\n');
    expect(await store.hasScrollback(), isTrue);
    expect(await store.scrollbackSavedAt(k1), isNotNull);
    await store.deleteScrollback(k1);
    expect(await store.readScrollback(k1), isNull);
    await store.deleteAllScrollback();
    expect(await store.hasScrollback(), isFalse);
  });

  test('oversized or invalid UTF-8 scrollback is ignored (D6)', () async {
    File('${store.directory.path}/scrollback/$k1.txt')
        .writeAsBytesSync(List.filled(524289, 0x41));
    File('${store.directory.path}/scrollback/$k2.txt').writeAsBytesSync([0xff, 0xfe]);
    expect(await store.readScrollback(k1), isNull);
    expect(await store.readScrollback(k2), isNull);
  });

  test('a non-key name is never read or written', () async {
    await store.writeScrollbacks({'../x': 'nope'});
    expect(File('${store.directory.path}/x.txt').existsSync(), isFalse);
    expect(await store.readScrollback('../x'), isNull);
  });

  test('orphans and stray temp files are removed (D15)', () async {
    await store.writeScrollbacks({k1: 'a', k2: 'b'});
    File('${store.directory.path}/scrollback/$k1.txt.tmp-1-ff').writeAsStringSync('x');
    await store.removeOrphans({k1});
    final names = Directory('${store.directory.path}/scrollback')
        .listSync()
        .map((e) => e.uri.pathSegments.last)
        .toList();
    expect(names, ['$k1.txt']);
  });

  test('serial queue: delete-all after an in-flight write wins (D25)',
      () async {
    final write = store.writeScrollbacks({k1: 'a' * 200000});
    final clear = store.deleteAllScrollback();
    await Future.wait([write, clear]);
    expect(await store.hasScrollback(), isFalse);
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/restore/restore_store_test.dart`
Expected: FAIL — files do not exist.

- [ ] **Step 3: Implement**

Create `apps/desktop/lib/src/restore/restore_paths.dart`:

```dart
/// D2: macOS `<app support>/restore`; Windows `%LOCALAPPDATA%\ShellX\restore`
/// — never Roaming `%APPDATA%` (domain roaming profiles sync it).
String restoreDirectoryPath({
  required bool windows,
  required Map<String, String> environment,
  required String appSupportPath,
}) {
  if (!windows) return '$appSupportPath/restore';
  final local = environment['LOCALAPPDATA'];
  if (local == null || local.isEmpty) {
    throw StateError('LOCALAPPDATA is not set');
  }
  return '$local\\ShellX\\restore';
}
```

Create `apps/desktop/lib/src/restore/restore_store.dart`:

```dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'restore_snapshot.dart';
import 'scrollback_codec.dart';

final class RestoreLoad {
  const RestoreLoad({this.snapshot, this.corrupt = false});
  final RestoreSnapshot? snapshot;

  /// The file existed but was not ours (D11); it is now `layout.json.bak`.
  final bool corrupt;
}

/// The files of A5a (D2, D3): `layout.json` and `scrollback/<key>.txt`.
/// Every operation runs through one serial queue (D25), so a delete issued
/// after a write always wins.
final class RestoreStore {
  RestoreStore(
    this.directory, {
    bool? posix,
    Future<void> Function(String path)? excludeFromBackup,
    void Function(String message)? log,
  }) : _posix = posix ?? !Platform.isWindows,
       _exclude = excludeFromBackup,
       _log = log ?? ((_) {});

  final Directory directory;
  final bool _posix;
  final Future<void> Function(String path)? _exclude;
  final void Function(String message) _log;
  final _random = Random.secure();
  Future<void> _tail = Future.value();
  bool _scrollbackAllowed = true;

  String get _layout => '${directory.path}${Platform.pathSeparator}layout.json';
  Directory get _scrollDir =>
      Directory('${directory.path}${Platform.pathSeparator}scrollback');
  String _scrollPath(String key) =>
      '${_scrollDir.path}${Platform.pathSeparator}$key.txt';

  Future<T> _serial<T>(Future<T> Function() body) {
    final run = _tail.then((_) => body());
    _tail = run.then((_) {}, onError: (Object _) {});
    return run;
  }

  /// Creates the directories (0700) and asks the OS to keep them out of
  /// backups. False when the permissions could not be set: scrollback is
  /// then never written (the layout still is).
  Future<bool> prepare() => _serial(() async {
    await _scrollDir.create(recursive: true);
    if (_posix) {
      final ok = await _chmod('700', [directory.path, _scrollDir.path]);
      _scrollbackAllowed = ok;
      if (!ok) _log('restore: permissions not set; scrollback disabled');
    }
    try {
      await _exclude?.call(directory.path);
    } on Object catch (error) {
      _log('restore: backup exclusion failed (${error.runtimeType})');
    }
    return _scrollbackAllowed;
  });

  Future<RestoreLoad> loadLayout() => _serial(() async {
    final file = File(_layout);
    if (!await file.exists()) return const RestoreLoad();
    String? text;
    try {
      text = await file.readAsString();
    } on Object catch (error) {
      _log('restore: layout unreadable (${error.runtimeType})');
    }
    final snapshot = text == null ? null : RestoreSnapshot.tryParse(text);
    if (snapshot != null) return RestoreLoad(snapshot: snapshot);
    if (text != null) _log('restore: layout unreadable (FormatException)');
    try {
      await file.rename('$_layout.bak');
    } on Object catch (error) {
      _log('restore: keeping .bak failed (${error.runtimeType})');
    }
    return const RestoreLoad(corrupt: true);
  });

  Future<void> writeLayout(RestoreSnapshot snapshot) =>
      _serial(() => _atomic({_layout: snapshot.encode()}));

  Future<void> writeScrollbacks(Map<String, String> textByKey) => _serial(() {
    if (!_scrollbackAllowed) return Future.value();
    return _atomic({
      for (final MapEntry(:key, :value) in textByKey.entries)
        if (isPaneKey(key)) _scrollPath(key): value,
    });
  });

  /// Sanitized (D6); null when missing, oversized or not UTF-8.
  Future<String?> readScrollback(String key) => _serial(() async {
    if (!isPaneKey(key)) return null;
    final file = File(_scrollPath(key));
    try {
      if (!await file.exists()) return null;
      if (await file.length() > kRestoreMaxFileBytes) return null;
      final text = utf8.decode(await file.readAsBytes());
      return sanitizeRestored(text);
    } on Object {
      return null;
    }
  });

  Future<DateTime?> scrollbackSavedAt(String key) => _serial(() async {
    if (!isPaneKey(key)) return null;
    final file = File(_scrollPath(key));
    return await file.exists() ? file.lastModified() : null;
  });

  Future<void> deleteScrollback(String key) => _serial(() async {
    if (!isPaneKey(key)) return;
    await _deleteQuietly(File(_scrollPath(key)));
  });

  Future<void> deleteAllScrollback() => _serial(() async {
    if (!await _scrollDir.exists()) return;
    await for (final entry in _scrollDir.list()) {
      if (entry is File) await _deleteQuietly(entry);
    }
  });

  Future<bool> hasScrollback() => _serial(() async {
    if (!await _scrollDir.exists()) return false;
    return _scrollDir.list().any(
      (e) => e is File && e.path.endsWith('.txt'),
    );
  });

  /// D15: files of panes no longer in the layout, and stray temp files.
  Future<void> removeOrphans(Set<String> keep) => _serial(() async {
    await for (final entry in directory.list()) {
      if (entry is File && entry.path.contains('.tmp-')) {
        await _deleteQuietly(entry);
      }
    }
    if (!await _scrollDir.exists()) return;
    await for (final entry in _scrollDir.list()) {
      if (entry is! File) continue;
      final name = entry.uri.pathSegments.last;
      final key = name.endsWith('.txt') ? name.substring(0, name.length - 4) : '';
      if (!keep.contains(key)) await _deleteQuietly(entry);
    }
  });

  /// Temp files first, one chmod for all of them before any content goes
  /// in (D2), then content, then rename each over its target.
  Future<void> _atomic(Map<String, String> contents) async {
    if (contents.isEmpty) return;
    final temps = <String, File>{
      for (final path in contents.keys)
        path: File('$path.tmp-$pid-${_random.nextInt(1 << 32).toRadixString(16)}'),
    };
    try {
      for (final temp in temps.values) {
        await temp.writeAsBytes(const [], flush: true);
      }
      if (_posix && !await _chmod('600', [for (final t in temps.values) t.path])) {
        throw const FileSystemException('chmod 600 failed');
      }
      for (final MapEntry(:key, :value) in temps.entries) {
        await value.writeAsString(contents[key]!, flush: true);
        await value.rename(key);
      }
    } on Object catch (error) {
      _log('restore: write failed (${error.runtimeType})');
      for (final temp in temps.values) {
        await _deleteQuietly(temp);
      }
    }
  }

  static Future<void> _deleteQuietly(File file) async {
    try {
      await file.delete();
    } on FileSystemException {
      // Already gone.
    }
  }

  static Future<bool> _chmod(String mode, List<String> paths) async {
    final result = await Process.run('/bin/chmod', [mode, ...paths]);
    return result.exitCode == 0;
  }
}
```

Note: `writeLayout`/`writeScrollbacks` never throw (a failed write keeps the previous file; spec §5 "disk full").

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/restore/restore_store_test.dart`
Expected: PASS (permission tests run on macOS only; on Windows CI they are skipped by `testOn`).

- [ ] **Step 5: Format, analyze, commit**

```bash
~/fvm/versions/3.41.4/bin/dart format --set-exit-if-changed apps/desktop/lib/src/restore apps/desktop/test/restore/restore_store_test.dart
cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter analyze lib/src/restore test/restore && cd ../..
git add apps/desktop/lib/src/restore/restore_paths.dart apps/desktop/lib/src/restore/restore_store.dart apps/desktop/test/restore/restore_store_test.dart
git commit -m "feat(desktop): restore store — 0700/0600 atomic files, .bak on corruption, per-pane scrollback, serial queue (A5a D2, D3, D11, D15, D25)"
```

---

### Task 4: `TerminalTabs.restore` + `SidebarWorkspaces.adopt` + pane output events (D7–D10, D16, D17)

**Files:**
- Modify: `apps/desktop/lib/src/terminal/terminal_tabs.dart`
- Modify: `apps/desktop/lib/src/terminal/sidebar_workspaces.dart`
- Modify: `apps/desktop/lib/src/ui/terminal/terminal_overlays.dart` (toast case)
- Test: `apps/desktop/test/terminal/terminal_tabs_restore_test.dart`

**Interfaces:**
- Consumes: Task 2 `RestoreSnapshot`, `SavedTab`, `savedLeaves`, `buildLayout`; Task 1 `restoreDivider`; A3 `_attach(summary, {size})`, `_awaitingOpen`, `_replaceTab`, `_visibleChanged`, `paneIds`, `PaneSession`, `TerminalTab`; `FakeLocalSessions.openCwds`, `openGate`.
- Produces:
  - `final class RestorePlan { const RestorePlan({required RestoreSnapshot snapshot, required Map<String, String> textByKey}); }` — `textByKey` = sanitized saved text **already followed by** its divider (built by Task 5).
  - `final class RestoreOutcome { const RestoreOutcome({required Map<int, String> keyBySession, required Map<String, int> tabIdByKey, required int panesFailed}); int get tabsRestored; }`
  - `Future<RestoreOutcome> TerminalTabs.restore(RestorePlan plan)`
  - `Stream<int> TerminalTabs.paneOutputs` (session id each time a pane's feed receives output; broadcast)
  - `final class RestorePanesFailedNotice extends TabNotice { const RestorePanesFailedNotice(this.count); final int count; }`
  - `void SidebarWorkspaces.adopt(List<SavedWorkspace> workspaces, Map<String, int> tabIdByKey, {int? selectedTabId})`

- [ ] **Step 1: Write the failing tests**

Create `apps/desktop/test/terminal/terminal_tabs_restore_test.dart`:

```dart
import 'dart:async';
import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_desktop/l10n/app_localizations.dart';
import 'package:shellx_desktop/src/platform/settings_store.dart';
import 'package:shellx_desktop/src/restore/restore_snapshot.dart';
import 'package:shellx_desktop/src/terminal/local_sessions_provider.dart';
import 'package:shellx_desktop/src/terminal/pane_layout.dart';
import 'package:shellx_desktop/src/terminal/sidebar_workspaces.dart';
import 'package:shellx_desktop/src/terminal/terminal_tabs.dart';

import '../support/fake_local_sessions.dart';

final k1 = '1' * 32, k2 = '2' * 32, k3 = '3' * 32, k4 = '4' * 32;

late FakeLocalSessions local;
late ProviderContainer container;
TerminalTabs tabs() => container.read(terminalTabsProvider.notifier);
TerminalTabsState state() => container.read(terminalTabsProvider);
SidebarState sidebar() => container.read(sidebarWorkspacesProvider);

void boot({List<String> workspaces = const []}) {
  final settings = InMemorySettingsStore()
    ..strings[SettingKeys.terminalWorkspaces] = workspaces;
  container = ProviderContainer.test(
    overrides: [
      localSessionsProvider.overrideWithValue(local),
      settingsStoreProvider.overrideWithValue(settings),
      appL10nProvider.overrideWithValue(lookupAppLocalizations(const Locale('en'))),
    ],
  );
  container.read(sidebarWorkspacesProvider);
}

/// Tab A (k1 | k2, ratio 0.3, k2 focused+zoomed) in workspace w2;
/// tab B (k3) in default, selected.
RestoreSnapshot snapshot() => RestoreSnapshot(
  savedAt: DateTime.utc(2026, 10, 7, 14, 32),
  cleanExit: true,
  selectedTab: k3,
  workspaces: [
    SavedWorkspace(id: 'default', tabs: [k3]),
    SavedWorkspace(id: 'w2', tabs: [k1]),
  ],
  tabs: [
    SavedTab(
      key: k1,
      name: 'server',
      focused: k2,
      zoomed: k2,
      layout: SavedSplit(
        axis: SplitAxis.row,
        ratio: 0.3,
        first: SavedPane(key: k1, cwd: '/w/api'),
        second: SavedPane(key: k2, cwd: '/w/web'),
      ),
    ),
    SavedTab(key: k3, focused: k3, layout: SavedPane(key: k3, cwd: '/w/x')),
  ],
);

void main() {
  setUp(() => local = FakeLocalSessions());

  test('opens the selected tab first, then sidebar order, with cwd (D7)',
      () async {
    boot(workspaces: ['{"id":"default","collapsed":false}', '{"id":"w2","name":"API","collapsed":false}']);
    final out = await tabs().restore(RestorePlan(snapshot: snapshot(), textByKey: const {}));
    expect(local.openCwds, ['/w/x', '/w/api', '/w/web']);
    expect(out.tabsRestored, 2);
    expect(out.panesFailed, 0);
    expect(out.keyBySession.values.toSet(), {k1, k2, k3});
  });

  test('rebuilds tree, ratio, focus, zoom, name; selects the saved tab (D10)',
      () async {
    boot();
    final out = await tabs().restore(RestorePlan(snapshot: snapshot(), textByKey: const {}));
    final a = state().tabs.firstWhere((t) => t.id == out.tabIdByKey[k1]);
    final split = a.layout as PaneSplit;
    expect(split.ratio, 0.3);
    final s2 = out.keyBySession.entries.firstWhere((e) => e.value == k2).key;
    expect(a.focusedPaneId, s2);
    expect(a.zoomedPaneId, s2);
    expect(a.customTitle, 'server');
    expect(state().selectedId, out.tabIdByKey[k3]);
  });

  test('saved text + divider come before the backlog; nothing is written to '
      'the session (D8)', () async {
    boot();
    local.nextBacklog = 'PROMPT% ';
    await tabs().restore(RestorePlan(
      snapshot: snapshot(),
      textByKey: {k3: 'old line\r\n\x1b[0m\x1b[2m— Session restored · 14:32 —\x1b[0m\r\n'},
    ));
    final tab = state().selected!;
    final lines = [
      for (var i = 0; i < tab.terminal.mainBuffer.lines.length; i++)
        tab.terminal.mainBuffer.lines[i].getText().trimRight(),
    ].where((l) => l.isNotEmpty).toList();
    expect(lines.take(3), ['old line', '— Session restored · 14:32 —', 'PROMPT%']);
    for (final view in local.views.values) {
      expect(view.written, isEmpty);
    }
  });

  test('failed panes are dropped, an empty tab is skipped, one toast (D7)',
      () async {
    boot();
    local.failOpens = {'/w/api', '/w/x'}; // SpawnFailedException for these cwds
    final out = await tabs().restore(RestorePlan(snapshot: snapshot(), textByKey: const {}));
    expect(out.panesFailed, 2);
    expect(out.tabsRestored, 1);
    expect(state().tabs.single.layout, isA<PaneLeaf>());
    expect(state().notice, isA<RestorePanesFailedNotice>());
    expect((state().notice! as RestorePanesFailedNotice).count, 2);
  });

  test('a session opened elsewhere during restore becomes its own tab and is '
      'never grafted into a restored tree (Review Focus 1)', () async {
    boot();
    local.openGate = Completer<void>();
    final restoring = tabs().restore(RestorePlan(snapshot: snapshot(), textByKey: const {}));
    local.add(local.summary(77)); // a phone opens a session meanwhile
    local.openGate!.complete();
    local.openGate = null;
    final out = await restoring;
    expect(state().tabs.map((t) => t.id), contains(77));
    expect(state().tabs.where((t) => t.paneOrder.contains(77)).single.id, 77);
    expect(out.keyBySession.keys, isNot(contains(77)));
    expect(state().tabs.length, 3);
  });

  test('adopt places tabs in their workspaces; unknown workspace → Default',
      () async {
    boot(workspaces: ['{"id":"default","collapsed":false}', '{"id":"w2","name":"API","collapsed":true}']);
    final out = await tabs().restore(RestorePlan(snapshot: snapshot(), textByKey: const {}));
    container.read(sidebarWorkspacesProvider.notifier).adopt(
      snapshot().workspaces,
      out.tabIdByKey,
      selectedTabId: out.tabIdByKey[k3],
    );
    expect(sidebar().tabsOf('w2'), [out.tabIdByKey[k1]]);
    expect(sidebar().tabsOf('default'), [out.tabIdByKey[k3]]);
    expect(sidebar().currentId, 'default');

    local = FakeLocalSessions();
    boot(); // fresh sessions; only Default exists now
    final again = await tabs().restore(RestorePlan(snapshot: snapshot(), textByKey: const {}));
    container.read(sidebarWorkspacesProvider.notifier).adopt(
      snapshot().workspaces,
      again.tabIdByKey,
    );
    expect(sidebar().tabsOf('default').toSet(), again.tabIdByKey.values.toSet());
  });

  test('paneOutputs reports the session that printed', () async {
    local.add(local.summary(5));
    boot();
    final seen = <int>[];
    final sub = tabs().paneOutputs.listen(seen.add);
    local.views[5]!.emit('hi');
    await pumpEventQueue();
    expect(seen, [5]);
    await sub.cancel();
  });
}
```

Extend `apps/desktop/test/support/fake_local_sessions.dart` (test support, part of this task):
- `String nextBacklog = '';` used as the `backlog` of sessions created by `open`.
- `Set<String> failOpens = {};` — `open(cwd: c)` with `failOpens.contains(c)` throws `const SpawnFailedException('No such file or directory')`.
- `FakeSessionView.written` (list of `Uint8List` passed to `write`/`reply`) and `emit(String text)` (adds UTF-8 bytes to `output`) if not already present.

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/terminal/terminal_tabs_restore_test.dart`
Expected: FAIL — `restore`, `RestorePlan`, `paneOutputs`, `adopt` undefined.

- [ ] **Step 3: Implement**

(a) `terminal_tabs.dart` — imports `import '../restore/restore_snapshot.dart';`. Replace A3's `bool _awaitingOpen = false;` by a counter so a ⌘T during restore cannot release restore's hold (every `_awaitingOpen = true` becomes `_awaitingOpens++`, every `_awaitingOpen = false` in a `finally`/after `open` becomes a single `_awaitingOpens--` guarded so each increment is decremented exactly once — keep A3's structure: set a local `var held = true;` after incrementing and decrement only `if (held) { held = false; _awaitingOpens--; }`), and `_merge`'s check becomes `if (_awaitingOpens > 0 && s.origin == SessionOrigin.desktop) continue;` plus `if (_restoreHeld.contains(s.id)) continue;`.

Add the types (top level, after `PortOpenFailedNotice`):

```dart
/// A5a D7: some saved panes could not be reopened. Neutral toast.
final class RestorePanesFailedNotice extends TabNotice {
  const RestorePanesFailedNotice(this.count);
  final int count;
}

/// What restore needs: the checked snapshot and, per pane key, the saved
/// text already followed by its divider (A5a D8).
final class RestorePlan {
  const RestorePlan({required this.snapshot, required this.textByKey});
  final RestoreSnapshot snapshot;
  final Map<String, String> textByKey;
}

final class RestoreOutcome {
  const RestoreOutcome({
    required this.keyBySession,
    required this.tabIdByKey,
    required this.panesFailed,
  });
  final Map<int, String> keyBySession;
  final Map<String, int> tabIdByKey;
  final int panesFailed;
  int get tabsRestored => tabIdByKey.length;
}
```

Fields in `TerminalTabs`:

```dart
  int _awaitingOpens = 0;

  /// Sessions restore opened and has not placed in a tab yet: `_merge`
  /// never makes them tabs of their own (Review Focus 1).
  final _restoreHeld = <int>{};

  /// Saved text (+ divider) written into a pane's terminal before its
  /// backlog (A5a D8). Consumed by `_attach`.
  final _restoreText = <int, String>{};

  final _paneOutputs = StreamController<int>.broadcast(sync: true);

  /// A5a D4: the session whose pane just received output.
  Stream<int> get paneOutputs => _paneOutputs.stream;
```

In `_dispose` add `unawaited(_paneOutputs.close());`.

In `_attach`, right before `feed.add(view.backlog);`:

```dart
    // A5a D8: the saved text sits above everything the new shell prints,
    // in this terminal only — never the PTY, never a phone.
    final restored = _restoreText.remove(s.id);
    if (restored != null) feed.add(utf8.encode(restored));
```

and change the output subscription to report the pane:

```dart
      ..add(view.output.listen((bytes) {
        feed.add(bytes);
        _paneOutputs.add(s.id);
      }))
```

Add the method (after A3's pane operations):

```dart
  /// A5a D7–D10: reopens every saved pane in its directory, the selected
  /// tab first, then in sidebar order; rebuilds each tree without the
  /// panes that failed; selects the saved tab. Never throws.
  Future<RestoreOutcome> restore(RestorePlan plan) async {
    final snapshot = plan.snapshot;
    final order = [
      ...snapshot.tabs.where((t) => t.key == snapshot.selectedTab),
      for (final w in snapshot.workspaces)
        for (final key in w.tabs)
          if (key != snapshot.selectedTab)
            ...snapshot.tabs.where((t) => t.key == key),
      ...snapshot.tabs.where(
        (t) =>
            t.key != snapshot.selectedTab &&
            !snapshot.workspaces.any((w) => w.tabs.contains(t.key)),
      ),
    ];
    final keyBySession = <int, String>{};
    final tabIdByKey = <String, int>{};
    var failed = 0;
    for (final saved in order) {
      if (!ref.mounted) break;
      final sessionByKey = <String, int>{};
      for (final pane in savedLeaves(saved.layout)) {
        final id = await _openForRestore(pane.cwd, plan.textByKey[pane.key]);
        if (id == null) {
          failed++;
          continue;
        }
        sessionByKey[pane.key] = id;
        keyBySession[id] = pane.key;
      }
      if (!ref.mounted) break;
      final layout = buildLayout(saved.layout, sessionByKey);
      final tab = layout == null ? null : _assemble(saved, layout, sessionByKey);
      if (tab == null) continue;
      tabIdByKey[saved.key] = tab.id;
    }
    if (ref.mounted) {
      final selected = tabIdByKey[snapshot.selectedTab];
      _sync(); // anything opened elsewhere meanwhile becomes its own tab
      if (selected != null) _set(selectedId: selected);
      if (failed > 0) _set(notice: RestorePanesFailedNotice(failed));
    }
    return RestoreOutcome(
      keyBySession: keyBySession,
      tabIdByKey: tabIdByKey,
      panesFailed: failed,
    );
  }

  Future<int?> _openForRestore(String? cwd, String? text) async {
    _awaitingOpens++;
    var held = true;
    try {
      final id = await _local.open(cols: _grid.cols, rows: _grid.rows, cwd: cwd);
      _restoreHeld.add(id);
      if (text != null) _restoreText[id] = text;
      return id;
    } on SessionLimitException {
      return null;
    } on SpawnFailedException {
      return null;
    } finally {
      if (held) {
        held = false;
        _awaitingOpens--;
      }
    }
  }

  /// Attaches the reopened sessions and adds the tab; null when none of
  /// them is alive any more (ended in the meantime).
  TerminalTab? _assemble(
    SavedTab saved,
    PaneNode layout,
    Map<String, int> sessionByKey,
  ) {
    final summaries = {for (final s in _local.sessions) s.id: s};
    final panes = <int, PaneSession>{};
    var tree = layout;
    for (final id in paneIds(layout)) {
      _restoreHeld.remove(id);
      final summary = summaries[id];
      final pane = summary == null ? null : _attach(summary);
      if (pane == null) {
        _restoreText.remove(id);
        tree = removePane(tree, id) ?? tree;
        continue;
      }
      panes[id] = pane;
    }
    if (panes.isEmpty) return null;
    final order = paneIds(tree);
    final focused = sessionByKey[saved.focused];
    final zoomed = sessionByKey[saved.zoomed];
    final focus = panes.containsKey(focused) ? focused! : order.first;
    final tab = TerminalTab(
      id: sessionByKey[saved.key] ?? order.first,
      origin: SessionOrigin.desktop,
      layout: tree,
      panes: panes,
      focusedPaneId: focus,
      zoomedPaneId: order.length > 1 && panes.containsKey(zoomed) ? zoomed : null,
      paneHistory: [focus, ...order.where((id) => id != focus)],
      customTitle: saved.name,
    );
    _set(tabs: [...state.tabs, tab]);
    return tab;
  }
```

If the id of the creating pane failed, the tab takes its first remaining pane's id — still a session id that is never reused (A3 D1 holds).

(b) `sidebar_workspaces.dart` — add:

```dart
  /// A5a D1, D10: put restored tabs where they were saved. Workspaces no
  /// longer in the settings send their tabs to the end of Default; tabs
  /// not mentioned keep their place. The selected tab's workspace becomes
  /// current.
  void adopt(
    List<SavedWorkspace> workspaces,
    Map<String, int> tabIdByKey, {
    int? selectedTabId,
  }) {
    final moved = <int>{};
    final members = <String, List<int>>{
      for (final w in state.workspaces) w.id: <int>[],
    };
    for (final saved in workspaces) {
      final target = members.containsKey(saved.id) ? saved.id : kDefaultWorkspaceId;
      for (final key in saved.tabs) {
        final id = tabIdByKey[key];
        if (id == null || !moved.add(id)) continue;
        members[target]!.add(id);
      }
    }
    for (final w in state.workspaces) {
      members[w.id]!.addAll(state.tabsOf(w.id).where((id) => !moved.contains(id)));
    }
    state = state.copyWith(
      members: members,
      currentId: selectedTabId == null
          ? state.currentId
          : (members.entries
                    .where((e) => e.value.contains(selectedTabId))
                    .firstOrNull
                    ?.key ??
                state.currentId),
    );
  }
```

Add `import '../restore/restore_snapshot.dart';` to `sidebar_workspaces.dart`.

(c) `terminal_overlays.dart` — in the toast text switch add (neutral variant):

```dart
      RestorePanesFailedNotice(:final count) => l10n.restorePanesFailed(count),
```

The `restorePanesFailed` string is added in Task 6; until then make Step 3 compile by adding the two ARB entries now (`restorePanesFailed` in `app_en.arb` with `"@restorePanesFailed": {"placeholders": {"count": {"type": "int"}}}`, and in `app_vi.arb`), then run `flutter gen-l10n` — Task 6 adds the rest of UI-A5 §9.

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/terminal/terminal_tabs_restore_test.dart && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test`
Expected: PASS, full suite green (A3's D5 tests still pass with the counter).

- [ ] **Step 5: Format, analyze, commit**

```bash
~/fvm/versions/3.41.4/bin/dart format --set-exit-if-changed apps/desktop/lib/src/terminal apps/desktop/lib/src/ui/terminal/terminal_overlays.dart apps/desktop/test/terminal/terminal_tabs_restore_test.dart apps/desktop/test/support/fake_local_sessions.dart
cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter analyze && cd ../..
git add apps/desktop/lib/src/terminal/terminal_tabs.dart apps/desktop/lib/src/terminal/sidebar_workspaces.dart apps/desktop/lib/src/ui/terminal/terminal_overlays.dart apps/desktop/test/terminal/terminal_tabs_restore_test.dart apps/desktop/test/support/fake_local_sessions.dart apps/desktop/lib/l10n/
git commit -m "feat(desktop): restore tabs and pane trees in saved directories with saved text above the backlog (A5a D7-D10, D16)"
```

---

### Task 5: `RestorePersistence` — keys, debounce 1 s, dirty scrollback 60 s, flush, toggle, startup restore (D4, D12–D15, D23)

**Files:**
- Create: `apps/desktop/lib/src/restore/restore_persistence.dart`
- Modify: `apps/desktop/lib/src/platform/settings_store.dart` (`terminalRestoreScrollback`)
- Test: `apps/desktop/test/restore/restore_persistence_test.dart`

**Interfaces:**
- Consumes: Tasks 1–4; `settingsStoreProvider`, `appL10nProvider`, `clockProvider` (`DateTime Function()`), `terminalTabsProvider`, `sidebarWorkspacesProvider`.
- Produces:
  - `SettingKeys.terminalRestoreScrollback = 'terminal_restore_scrollback'` (in `all`; default `true`).
  - `final restoreStoreProvider = Provider<RestoreStore>((ref) => throw UnimplementedError('override in main'));`
  - `final class RestoreStripState { const RestoreStripState({required int tabs, DateTime? contentsAt}); }`
  - `final restorePersistenceProvider = NotifierProvider<RestorePersistence, RestoreStripState?>(RestorePersistence.new);` — state = the abnormal-end strip to show (null: none).
  - `RestorePersistence`: `Future<void> restoreAtStartup(RestoreLoad load)`, `Future<void> flushAll({required bool clean})`, `Future<void> setScrollbackEnabled(bool enabled)`, `Future<void> clearScrollback()`, `bool get scrollbackEnabled`, `Future<bool> hasSavedScrollback()`, `void dismissStrip()`, `String keyOf(int sessionId)`.
  - Durations: `RestorePersistence.layoutDebounce = Duration(seconds: 1)`, `scrollbackPeriod = Duration(seconds: 60)`.

- [ ] **Step 1: Write the failing tests**

Create `apps/desktop/test/restore/restore_persistence_test.dart` using a `FakeRestoreStore implements RestoreStore`-like recorder. Because `RestoreStore` is a `final class`, introduce in this task an interface it implements: add to `restore_store.dart` `abstract interface class RestoreFiles { … all RestoreStore public methods … }` and make `RestoreStore implements RestoreFiles`; `restoreStoreProvider` is `Provider<RestoreFiles>`.

```dart
import 'dart:ui';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/l10n/app_localizations.dart';
import 'package:shellx_desktop/src/agent/desktop_services.dart' show clockProvider;
import 'package:shellx_desktop/src/platform/settings_store.dart';
import 'package:shellx_desktop/src/restore/restore_persistence.dart';
import 'package:shellx_desktop/src/restore/restore_snapshot.dart';
import 'package:shellx_desktop/src/restore/restore_store.dart';
import 'package:shellx_desktop/src/terminal/local_sessions_provider.dart';
import 'package:shellx_desktop/src/terminal/sidebar_workspaces.dart';
import 'package:shellx_desktop/src/terminal/terminal_tabs.dart';

import '../support/fake_local_sessions.dart';

final class RecordingFiles implements RestoreFiles {
  final layouts = <RestoreSnapshot>[];
  final scrollbacks = <String, String>{};
  final deleted = <String>[];
  int clears = 0;
  Set<String>? keptOrphans;
  Map<String, String> stored = {};

  @override
  Future<bool> prepare() async => true;
  @override
  Future<RestoreLoad> loadLayout() async => const RestoreLoad();
  @override
  Future<void> writeLayout(RestoreSnapshot s) async => layouts.add(s);
  @override
  Future<void> writeScrollbacks(Map<String, String> m) async => scrollbacks.addAll(m);
  @override
  Future<String?> readScrollback(String key) async => stored[key];
  @override
  Future<DateTime?> scrollbackSavedAt(String key) async =>
      stored.containsKey(key) ? DateTime(2026, 10, 7, 14, 32) : null;
  @override
  Future<void> deleteScrollback(String key) async => deleted.add(key);
  @override
  Future<void> deleteAllScrollback() async => clears++;
  @override
  Future<bool> hasScrollback() async => scrollbacks.isNotEmpty;
  @override
  Future<void> removeOrphans(Set<String> keep) async => keptOrphans = keep;
}

late FakeLocalSessions local;
late RecordingFiles files;
late InMemorySettingsStore settings;
late ProviderContainer c;

RestorePersistence persistence() => c.read(restorePersistenceProvider.notifier);

void boot() {
  c = ProviderContainer.test(
    overrides: [
      localSessionsProvider.overrideWithValue(local),
      settingsStoreProvider.overrideWithValue(settings),
      restoreStoreProvider.overrideWithValue(files),
      clockProvider.overrideWithValue(() => DateTime(2026, 10, 7, 15)),
      appL10nProvider.overrideWithValue(lookupAppLocalizations(const Locale('vi'))),
    ],
  );
  c.read(sidebarWorkspacesProvider);
  c.read(restorePersistenceProvider);
}

void main() {
  setUp(() {
    local = FakeLocalSessions();
    files = RecordingFiles();
    settings = InMemorySettingsStore();
  });

  test('layout: one write 1 s after a burst of changes; none when equal',
      () => fakeAsync((async) {
    local.add(local.summary(1));
    boot();
    async.flushMicrotasks();
    c.read(terminalTabsProvider.notifier).rename(1, 'a');
    async.elapse(const Duration(milliseconds: 500));
    c.read(terminalTabsProvider.notifier).rename(1, 'b');
    async.elapse(const Duration(milliseconds: 999));
    expect(files.layouts, isEmpty);
    async.elapse(const Duration(milliseconds: 2));
    expect(files.layouts.single.tabs.single.name, 'b');
    expect(files.layouts.single.cleanExit, isFalse); // D12 while running
    c.read(terminalTabsProvider.notifier).select(1); // no layout change
    async.elapse(const Duration(seconds: 2));
    expect(files.layouts, hasLength(1));
  }));

  test('scrollback: only dirty panes, every 60 s (D4)', () => fakeAsync((async) {
    local.add(local.summary(1));
    local.add(local.summary(2));
    boot();
    async.flushMicrotasks();
    local.views[1]!.emit('hello\r\n');
    async.elapse(const Duration(seconds: 60));
    expect(files.scrollbacks.keys, [persistence().keyOf(1)]);
    expect(files.scrollbacks.values.single, 'hello\r\n');
    files.scrollbacks.clear();
    async.elapse(const Duration(seconds: 60));
    expect(files.scrollbacks, isEmpty); // nothing new
  }));

  test('flushAll(clean: true) writes layout with cleanExit and dirty panes',
      () async {
    local.add(local.summary(1));
    boot();
    local.views[1]!.emit('x\r\n');
    await pumpEventQueue();
    await persistence().flushAll(clean: true);
    expect(files.layouts.last.cleanExit, isTrue);
    expect(files.scrollbacks, isNotEmpty);
  });

  test('switch off: deletes everything now and stops writing (D13)', () async {
    local.add(local.summary(1));
    boot();
    await persistence().setScrollbackEnabled(false);
    expect(settings.values[SettingKeys.terminalRestoreScrollback], isFalse);
    expect(files.clears, 1);
    local.views[1]!.emit('x\r\n');
    await pumpEventQueue();
    await persistence().flushAll(clean: true);
    expect(files.scrollbacks, isEmpty);
  });

  test('closing a pane deletes its file at the next layout write (D15)',
      () => fakeAsync((async) {
    local.add(local.summary(1));
    local.add(local.summary(2));
    boot();
    async.flushMicrotasks();
    final key = persistence().keyOf(2);
    c.read(terminalTabsProvider.notifier).close(2);
    async.elapse(const Duration(seconds: 2));
    expect(files.deleted, [key]);
  }));

  test('restoreAtStartup: plan with text + divider, keys kept, strip after an '
      'unclean exit, orphans removed (D8, D12, D14, D15, D23)', () async {
    final key = 'e' * 32;
    files.stored = {key: 'old\r\n'};
    boot();
    final snapshot = RestoreSnapshot(
      savedAt: DateTime(2026, 10, 7, 14, 31),
      cleanExit: false,
      selectedTab: key,
      workspaces: [SavedWorkspace(id: 'default', tabs: [key])],
      tabs: [SavedTab(key: key, focused: key, layout: SavedPane(key: key, cwd: '/w'))],
    );
    await persistence().restoreAtStartup(RestoreLoad(snapshot: snapshot));
    final tab = c.read(terminalTabsProvider).tabs.single;
    expect(persistence().keyOf(tab.id), key);
    final text = [
      for (var i = 0; i < tab.terminal.mainBuffer.lines.length; i++)
        tab.terminal.mainBuffer.lines[i].getText().trimRight(),
    ].join('\n');
    expect(text, contains('old\n— Phiên được khôi phục · 14:32 —'));
    final strip = c.read(restorePersistenceProvider)!;
    expect(strip.tabs, 1);
    expect(strip.contentsAt, DateTime(2026, 10, 7, 14, 32));
    expect(files.keptOrphans, {key});
    persistence().dismissStrip();
    expect(c.read(restorePersistenceProvider), isNull);
  });

  test('clean exit → no strip; nothing restored → no strip', () async {
    boot();
    await persistence().restoreAtStartup(const RestoreLoad());
    expect(c.read(restorePersistenceProvider), isNull);
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/restore/restore_persistence_test.dart`
Expected: FAIL — `restore_persistence.dart`, `RestoreFiles`, `terminalRestoreScrollback` undefined.

- [ ] **Step 3: Implement**

(a) `settings_store.dart` — add to `SettingKeys`:

```dart
  /// A5a D13: "Lưu nội dung terminal khi thoát" (default on).
  static const String terminalRestoreScrollback = 'terminal_restore_scrollback';
```

and add `terminalRestoreScrollback` to `all`.

(b) `restore_store.dart` — add `abstract interface class RestoreFiles` declaring `prepare`, `loadLayout`, `writeLayout`, `writeScrollbacks`, `readScrollback`, `scrollbackSavedAt`, `deleteScrollback`, `deleteAllScrollback`, `hasScrollback`, `removeOrphans` with the signatures of Task 3; `final class RestoreStore implements RestoreFiles` and `@override` on each.

(c) Create `apps/desktop/lib/src/restore/restore_persistence.dart`:

```dart
import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../agent/desktop_services.dart' show clockProvider;
import '../platform/settings_store.dart';
import '../terminal/local_sessions_provider.dart';
import '../terminal/sidebar_workspaces.dart';
import '../terminal/terminal_tabs.dart';
import 'restore_snapshot.dart';
import 'restore_store.dart';
import 'scrollback_codec.dart';

final restoreStoreProvider = Provider<RestoreFiles>(
  (ref) => throw UnimplementedError('main.dart overrides restoreStoreProvider'),
);

/// UI-A5 §4: the abnormal-end strip.
final class RestoreStripState {
  const RestoreStripState({required this.tabs, this.contentsAt});
  final int tabs;

  /// The newest saved-content time; null when no content was restored.
  final DateTime? contentsAt;
}

final restorePersistenceProvider =
    NotifierProvider<RestorePersistence, RestoreStripState?>(
      RestorePersistence.new,
    );

/// A5a: keeps `restore/` in step with the window (D4) and rebuilds it at
/// startup (D7–D16). State: the abnormal-end strip, if any.
class RestorePersistence extends Notifier<RestoreStripState?> {
  static const layoutDebounce = Duration(seconds: 1);
  static const scrollbackPeriod = Duration(seconds: 60);

  final _keys = <int, String>{};
  final _dirty = <int>{};
  Timer? _debounce;
  Timer? _period;
  RestoreSnapshot? _written;
  bool _ready = false;

  RestoreFiles get _files => ref.read(restoreStoreProvider);
  SettingsStore get _settings => ref.read(settingsStoreProvider);

  bool get scrollbackEnabled => _settings.getBool(
    SettingKeys.terminalRestoreScrollback,
    defaultValue: true,
  );

  @override
  RestoreStripState? build() {
    final tabs = ref.read(terminalTabsProvider.notifier);
    final outputs = tabs.paneOutputs.listen(_dirty.add);
    ref.listen(terminalTabsProvider, (_, _) => _schedule());
    ref.listen(sidebarWorkspacesProvider, (_, _) => _schedule());
    _period = Timer.periodic(scrollbackPeriod, (_) => unawaited(_saveDirty()));
    ref.onDispose(() {
      unawaited(outputs.cancel());
      _debounce?.cancel();
      _period?.cancel();
    });
    // Without a startup restore (tests, first run) saving starts at once.
    _ready = true;
    return null;
  }

  /// D14: a key per pane, made when the pane is first seen.
  String keyOf(int sessionId) =>
      _keys.putIfAbsent(sessionId, newPaneKey);

  Future<bool> hasSavedScrollback() => _files.hasScrollback();

  void dismissStrip() => state = null;

  /// D7–D16. Runs before `handleActivation`.
  Future<void> restoreAtStartup(RestoreLoad load) async {
    final snapshot = load.snapshot;
    if (snapshot == null) {
      await _files.removeOrphans(const {});
      return;
    }
    _ready = false;
    try {
      final l10n = ref.read(appL10nProvider);
      final now = ref.read(clockProvider)();
      final text = <String, String>{};
      DateTime? newest;
      for (final key in snapshot.paneKeys) {
        final saved = await _files.readScrollback(key);
        if (saved == null || saved.isEmpty) continue;
        final at = await _files.scrollbackSavedAt(key) ?? snapshot.savedAt;
        if (newest == null || at.isAfter(newest)) newest = at;
        final time = formatRestoreTime(
          at,
          now,
          localeName: l10n.localeName,
          yesterday: l10n.restoreTimeYesterday,
        );
        text[key] = saved + restoreDivider(l10n.terminalRestoredDivider(time));
      }
      final outcome = await ref
          .read(terminalTabsProvider.notifier)
          .restore(RestorePlan(snapshot: snapshot, textByKey: text));
      _keys.addAll(outcome.keyBySession);
      ref.read(sidebarWorkspacesProvider.notifier).adopt(
        snapshot.workspaces,
        outcome.tabIdByKey,
        selectedTabId: ref.read(terminalTabsProvider).selectedId,
      );
      await _files.removeOrphans(outcome.keyBySession.values.toSet());
      if (!snapshot.cleanExit && outcome.tabsRestored > 0) {
        state = RestoreStripState(
          tabs: outcome.tabsRestored,
          contentsAt: newest,
        );
      }
    } finally {
      _ready = true;
      _schedule();
    }
  }

  /// Quit (clean), OS power-off (clean, D18), window hidden (not clean).
  Future<void> flushAll({required bool clean}) async {
    _debounce?.cancel();
    await _writeLayout(cleanExit: clean, force: true);
    await _saveDirty();
  }

  Future<void> setScrollbackEnabled(bool enabled) async {
    await _settings.setBool(SettingKeys.terminalRestoreScrollback, enabled);
    if (!enabled) await clearScrollback();
  }

  Future<void> clearScrollback() async {
    _dirty.clear();
    await _files.deleteAllScrollback();
  }

  void _schedule() {
    if (!_ready) return;
    _debounce?.cancel();
    _debounce = Timer(
      layoutDebounce,
      () => unawaited(_writeLayout(cleanExit: false)),
    );
  }

  Future<void> _writeLayout({required bool cleanExit, bool force = false}) async {
    if (!ref.mounted) return;
    final tabs = ref.read(terminalTabsProvider);
    final next = captureSnapshot(
      tabs: tabs,
      sidebar: ref.read(sidebarWorkspacesProvider),
      keyOf: keyOf,
      now: ref.read(clockProvider)(),
      cleanExit: cleanExit,
    );
    final previous = _written;
    if (!force && previous != null && previous.sameLayoutAs(next)) return;
    // D15: panes that left the layout lose their saved text.
    if (previous != null) {
      for (final gone in previous.paneKeys.difference(next.paneKeys)) {
        await _files.deleteScrollback(gone);
      }
    }
    // Keep keys of live panes and of tab ids (a tab keeps the id of the
    // pane that created it after that pane closed, A3 D1).
    _keys.removeWhere(
      (id, _) =>
          tabs.tabOfSession(id) == null && !tabs.tabs.any((t) => t.id == id),
    );
    _written = next;
    await _files.writeLayout(next);
  }

  Future<void> _saveDirty() async {
    if (!ref.mounted || _dirty.isEmpty) return;
    if (!scrollbackEnabled) {
      _dirty.clear();
      return;
    }
    final tabs = ref.read(terminalTabsProvider);
    final batch = <String, String>{};
    for (final id in _dirty) {
      final pane = tabs.tabOfSession(id)?.panes[id];
      if (pane == null || pane.exited) continue;
      final text = encodeScrollback(pane.terminal);
      if (text.isNotEmpty) batch[keyOf(id)] = text;
    }
    _dirty.clear();
    try {
      await _files.writeScrollbacks(batch);
    } on Object catch (error) {
      debugPrint('restore: scrollback not saved (${error.runtimeType})');
    }
  }
}
```

Note on the `select(1)` assertion in the first test: selecting the already-selected tab produces an equal snapshot, so `sameLayoutAs` skips the write.

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/restore/ && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test`
Expected: PASS; full suite green.

- [ ] **Step 5: Format, analyze, commit**

```bash
~/fvm/versions/3.41.4/bin/dart format --set-exit-if-changed apps/desktop/lib/src/restore apps/desktop/lib/src/platform/settings_store.dart apps/desktop/test/restore
cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter analyze && cd ../..
git add apps/desktop/lib/src/restore apps/desktop/lib/src/platform/settings_store.dart apps/desktop/test/restore/restore_persistence_test.dart
git commit -m "feat(desktop): RestorePersistence — debounced layout, 60 s dirty scrollback, flush, switch, startup restore (A5a D4, D12-D15)"
```

---

### Task 6: Strings, tray "Terminal" submenu, switch and clear actions (D13, UI-A5 §3, §9)

**Files:**
- Modify: `apps/desktop/lib/l10n/app_en.arb`, `apps/desktop/lib/l10n/app_vi.arb` (+ generated `lib/l10n/app_localizations*.dart`)
- Modify: `apps/desktop/lib/src/tray/tray_action.dart`, `tray_menu.dart`, `tray_presenter.dart`, `tray_actions.dart`
- Modify: `apps/desktop/lib/main.dart` (render the tray with the local state)
- Test: `apps/desktop/test/tray/tray_terminal_menu_test.dart`

**Interfaces:**
- Consumes: Task 5 `restorePersistenceProvider`, `scrollbackEnabled`, `setScrollbackEnabled`, `clearScrollback`, `hasSavedScrollback`.
- Produces:
  - ARB keys (UI-A5 §9, A5a rows): `terminalRestoredDivider(String time)`, `restoreTimeYesterday(String time)`, `trayTerminal`, `trayRestoreScrollback`, `trayClearSavedScrollback`, `restoreAbnormalStrip(int count, String time)`, `restoreAbnormalNoText(int count)`, `restoreStripCloseLabel` (+ `restorePanesFailed` from Task 4).
  - `final class TrayLocalState { const TrayLocalState({this.restoreScrollback = true, this.hasSavedScrollback = false}); }`
  - `Menu buildTrayMenu(AgentViewState state, AppLocalizations l10n, TrayMenuIds ids, {TrayLocalState local = const TrayLocalState()})`; `TrayPresenter.render(AgentViewState state, {TrayLocalState local = const TrayLocalState()})`
  - `TrayKeys.terminal = 'terminal'`, `TrayKeys.restoreScrollback = 'restore_scrollback'`, `TrayKeys.clearSavedScrollback = 'clear_saved_scrollback'`
  - `final class ToggleRestoreScrollback extends TrayAction`, `final class ClearSavedScrollback extends TrayAction`
  - `final trayLocalStateProvider = FutureProvider<TrayLocalState>(...)` in `tray_actions.dart`, invalidated after each of the two actions.

- [ ] **Step 1: Write the failing tests**

Create `apps/desktop/test/tray/tray_terminal_menu_test.dart`:

```dart
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/l10n/app_localizations.dart';
import 'package:shellx_desktop/src/agent/agent_state.dart';
import 'package:shellx_desktop/src/tray/tray_action.dart';
import 'package:shellx_desktop/src/tray/tray_menu.dart';
import 'package:tray_manager/tray_manager.dart';

final vi = lookupAppLocalizations(const Locale('vi'));

MenuItem? find(List<MenuItem> items, String key) {
  for (final i in items) {
    if (i.key == key) return i;
    final sub = i.submenu?.items;
    if (sub != null) {
      final hit = find(sub, key);
      if (hit != null) return hit;
    }
  }
  return null;
}

void main() {
  for (final signedIn in [false, true]) {
    test('Terminal submenu right before Thông báo (signedIn: $signedIn)', () {
      final state = signedIn
          ? const AgentViewState(phase: AuthPhase.signedIn, email: 'a@b.c')
          : const AgentViewState(phase: AuthPhase.signedOut);
      final menu = buildTrayMenu(state, vi, TrayMenuIds(),
          local: const TrayLocalState(restoreScrollback: true, hasSavedScrollback: false));
      final items = menu.items!;
      final terminal = items.indexWhere((i) => i.key == TrayKeys.terminal);
      final notifications = items.indexWhere((i) => i.key == TrayKeys.notifications);
      expect(terminal, greaterThanOrEqualTo(0));
      expect(notifications, terminal + 1);
      expect(items[terminal].label, 'Terminal');
      final check = find(items, TrayKeys.restoreScrollback)!;
      expect(check.label, 'Lưu nội dung terminal khi thoát');
      expect(check.checked, isTrue);
      final clear = find(items, TrayKeys.clearSavedScrollback)!;
      expect(clear.label, 'Xóa nội dung đã lưu');
      expect(clear.disabled, isTrue); // nothing saved yet
    });
  }

  test('keys map to actions', () {
    expect(trayActionForKey(TrayKeys.restoreScrollback), isA<ToggleRestoreScrollback>());
    expect(trayActionForKey(TrayKeys.clearSavedScrollback), isA<ClearSavedScrollback>());
  });

  test('strings (vi/en) match UI-A5 §9', () {
    final en = lookupAppLocalizations(const Locale('en'));
    expect(vi.terminalRestoredDivider('14:32'), '— Phiên được khôi phục · 14:32 —');
    expect(en.terminalRestoredDivider('14:32'), '— Session restored · 14:32 —');
    expect(vi.restoreTimeYesterday('14:32'), 'hôm qua 14:32');
    expect(en.restoreAbnormalStrip(1, '14:31'),
        "ShellX didn't close normally last time. Reopened 1 tab; contents as of 14:31.");
    expect(vi.restoreAbnormalNoText(5),
        'ShellX đã đóng bất thường lần trước. Đã mở lại 5 tab.');
    expect(en.restorePanesFailed(2), "Couldn't reopen 2 panes");
  });
}
```

Add to `test/tray/tray_actions_test.dart` (existing file; or create `test/tray/tray_restore_actions_test.dart` if structure differs) a test that `ToggleRestoreScrollback` flips `settings.values[SettingKeys.terminalRestoreScrollback]` from absent(true) to `false` and calls the store's `deleteAllScrollback`, using the `RecordingFiles` fake from Task 5 (copy it into `test/support/restore_fakes.dart` and import it in both test files).

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/tray/tray_terminal_menu_test.dart`
Expected: FAIL — keys, actions, strings undefined.

- [ ] **Step 3: Implement**

(a) ARB — add to `app_en.arb` (with metadata) and `app_vi.arb` exactly the UI-A5 §9 A5a rows:

```json
  "terminalRestoredDivider": "— Session restored · {time} —",
  "@terminalRestoredDivider": {"placeholders": {"time": {"type": "String"}}},
  "restoreTimeYesterday": "yesterday {time}",
  "@restoreTimeYesterday": {"placeholders": {"time": {"type": "String"}}},
  "trayTerminal": "Terminal",
  "trayRestoreScrollback": "Save terminal contents on quit",
  "trayClearSavedScrollback": "Clear saved contents",
  "restoreAbnormalStrip": "ShellX didn't close normally last time. Reopened {count, plural, =1{1 tab} other{{count} tabs}}; contents as of {time}.",
  "@restoreAbnormalStrip": {"placeholders": {"count": {"type": "int"}, "time": {"type": "String"}}},
  "restoreAbnormalNoText": "ShellX didn't close normally last time. Reopened {count, plural, =1{1 tab} other{{count} tabs}}.",
  "@restoreAbnormalNoText": {"placeholders": {"count": {"type": "int"}}},
  "restoreStripCloseLabel": "Dismiss restore notice"
```

```json
  "terminalRestoredDivider": "— Phiên được khôi phục · {time} —",
  "restoreTimeYesterday": "hôm qua {time}",
  "trayTerminal": "Terminal",
  "trayRestoreScrollback": "Lưu nội dung terminal khi thoát",
  "trayClearSavedScrollback": "Xóa nội dung đã lưu",
  "restoreAbnormalStrip": "{count, plural, other{ShellX đã đóng bất thường lần trước. Đã mở lại {count} tab; nội dung tính tới {time}.}}",
  "restoreAbnormalNoText": "{count, plural, other{ShellX đã đóng bất thường lần trước. Đã mở lại {count} tab.}}",
  "restoreStripCloseLabel": "Đóng thông báo khôi phục"
```

Run `cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter gen-l10n`.

(b) `tray_action.dart` — actions, keys and mapping:

```dart
/// A5a D13: "Lưu nội dung terminal khi thoát".
final class ToggleRestoreScrollback extends TrayAction {
  const ToggleRestoreScrollback();
}

/// A5a D13: "Xóa nội dung đã lưu".
final class ClearSavedScrollback extends TrayAction {
  const ClearSavedScrollback();
}
```

In `TrayKeys`: `static const String terminal = 'terminal'; static const String restoreScrollback = 'restore_scrollback'; static const String clearSavedScrollback = 'clear_saved_scrollback';`. In `trayActionForKey`'s switch: `TrayKeys.restoreScrollback => const ToggleRestoreScrollback(), TrayKeys.clearSavedScrollback => const ClearSavedScrollback(),`.

(c) `tray_menu.dart`:

```dart
/// What the tray shows that the UI process owns (A5a D13; with A5b the
/// agent state comes from the daemon and cannot carry UI settings).
final class TrayLocalState {
  const TrayLocalState({
    this.restoreScrollback = true,
    this.hasSavedScrollback = false,
  });
  final bool restoreScrollback;
  final bool hasSavedScrollback;
}
```

Add the `{TrayLocalState local = const TrayLocalState()}` parameter to `buildTrayMenu`, a local builder next to `notifications()`:

```dart
  // A5a D13, UI-A5 §3: right before "Thông báo", in both menus.
  MenuItem terminal() => sub(TrayKeys.terminal, l10n.trayTerminal, [
    check(
      TrayKeys.restoreScrollback,
      l10n.trayRestoreScrollback,
      local.restoreScrollback,
    ),
    item(
      TrayKeys.clearSavedScrollback,
      l10n.trayClearSavedScrollback,
      disabled: !local.hasSavedScrollback,
    ),
  ]);
```

and insert `terminal(),` immediately before every `notifications(),` (signed-out and signed-in menus).

(d) `tray_presenter.dart` — `render(AgentViewState state, {TrayLocalState local = const TrayLocalState()})`; remember the last `local` alongside the last state and pass it to `buildTrayMenu`.

(e) `tray_actions.dart`:

```dart
final trayLocalStateProvider = FutureProvider<TrayLocalState>((ref) async {
  final restore = ref.read(restorePersistenceProvider.notifier);
  return TrayLocalState(
    restoreScrollback: restore.scrollbackEnabled,
    hasSavedScrollback: await restore.hasSavedScrollback(),
  );
});
```

and in `_dispatch`:

```dart
      case ToggleRestoreScrollback():
        final restore = _ref.read(restorePersistenceProvider.notifier);
        await restore.setScrollbackEnabled(!restore.scrollbackEnabled);
        _ref.invalidate(trayLocalStateProvider);
      case ClearSavedScrollback():
        await _ref.read(restorePersistenceProvider.notifier).clearScrollback();
        _ref.invalidate(trayLocalStateProvider);
```

(f) `main.dart` — render the tray from both inputs: replace the `trayPresenter.render(next)` call in the agent listener with a helper `void renderTray() => _unawaitedLogged(trayPresenter.render(container.read(agentControllerProvider), local: container.read(trayLocalStateProvider).value ?? const TrayLocalState()), 'tray');` called from the existing agent listener and from a new `container.listen(trayLocalStateProvider, (_, _) => renderTray(), fireImmediately: true)`. Also invalidate `trayLocalStateProvider` once a minute? No — invalidate after each periodic save is unnecessary; instead invalidate it in `RestorePersistence._saveDirty` after a non-empty batch (`ref.invalidate(trayLocalStateProvider)` would create an import cycle; so in `main.dart` add `Timer.periodic(RestorePersistence.scrollbackPeriod, (_) => container.invalidate(trayLocalStateProvider))`).

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/tray test/l10n && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test`
Expected: PASS; `l10n_test` (key parity vi/en) green; full suite green.

- [ ] **Step 5: Format, analyze, commit**

```bash
~/fvm/versions/3.41.4/bin/dart format --set-exit-if-changed apps/desktop/lib/src/tray apps/desktop/lib/main.dart apps/desktop/test/tray apps/desktop/test/support
cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter analyze && cd ../..
git add apps/desktop/lib/l10n apps/desktop/lib/src/tray apps/desktop/lib/main.dart apps/desktop/test/tray apps/desktop/test/support/restore_fakes.dart
git commit -m "feat(desktop): tray Terminal submenu — save terminal contents switch and clear (A5a D13)"
```

---

### Task 7: Startup restore, save on hide/quit/power-off, abnormal-end strip (D12, D16, D18, D24) — manual checks marked ⚠

**Files:**
- Create: `apps/desktop/lib/src/ui/terminal/info_strip.dart`
- Modify: `apps/desktop/lib/src/ui/terminal/terminal_pane.dart` (strip under the signed-out strip)
- Modify: `apps/desktop/lib/src/platform/app_reopen.dart` (`saveBeforeExit`)
- Modify: `apps/desktop/lib/src/tray/tray_actions.dart` (`Quit` flushes first)
- Modify: `apps/desktop/lib/main.dart`
- Modify: `apps/desktop/macos/Runner/AppDelegate.swift`
- Modify: `apps/desktop/windows/runner/flutter_window.cpp`, `flutter_window.h`
- Test: `apps/desktop/test/ui/info_strip_test.dart`, `apps/desktop/test/platform/app_reopen_test.dart` (extend), `apps/desktop/test/tray/tray_restore_actions_test.dart` (extend)

**Interfaces:**
- Consumes: Task 3 `RestoreStore`, `restoreDirectoryPath`; Task 5 `restorePersistenceProvider`, `restoreStoreProvider`, `RestoreStripState`, `flushAll`, `restoreAtStartup`, `dismissStrip`; Task 1 `formatRestoreTime`.
- Produces:
  - `class InfoStrip extends StatelessWidget { const InfoStrip({super.key, required IconData icon, required Color iconColor, required String text, required String closeLabel, required VoidCallback onClose, List<Widget> actions = const []}); }` (A5b reuses it).
  - `void listenForAppChannel({required void Function() onReopen, required void Function() onQuitRequested, Future<void> Function()? onSaveBeforeExit, MethodChannel channel = appChannel})` — `saveBeforeExit` completes the platform call only after `onSaveBeforeExit` finishes.

- [ ] **Step 1: Write the failing tests**

`apps/desktop/test/ui/info_strip_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/ui/terminal/info_strip.dart';
import 'package:shellx_desktop/src/ui/theme/shellx_desktop_theme.dart';

void main() {
  testWidgets('36 px, rowSelected, live region, close button works', (t) async {
    var closed = 0;
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: InfoStrip(
          icon: Icons.history,
          iconColor: ShellxDesktopColors.textSecondary,
          text: 'ShellX đã đóng bất thường lần trước. Đã mở lại 5 tab.',
          closeLabel: 'Đóng thông báo khôi phục',
          onClose: () => closed++,
        ),
      ),
    ));
    expect(t.getSize(find.byType(InfoStrip)).height, 36);
    final box = t.widget<Container>(find.byKey(const Key('infoStrip'))).decoration! as BoxDecoration;
    expect(box.color, ShellxDesktopColors.rowSelected);
    expect(find.bySemanticsLabel('Đóng thông báo khôi phục'), findsOneWidget);
    await t.tap(find.byKey(const Key('infoStrip.close')));
    expect(closed, 1);
    final semantics = t.getSemantics(find.byKey(const Key('infoStrip')));
    expect(semantics.hasFlag(SemanticsFlag.isLiveRegion), isTrue);
  });
}
```

(add `import 'dart:ui' show SemanticsFlag;`). Extend `app_reopen_test.dart`:

```dart
  test('saveBeforeExit answers only after the save finished (A5a D18)', () async {
    final done = Completer<void>();
    var saved = false;
    listenForAppChannel(
      onReopen: () {},
      onQuitRequested: () {},
      onSaveBeforeExit: () async {
        await done.future;
        saved = true;
      },
    );
    final reply = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          appChannel.name,
          appChannel.codec.encodeMethodCall(const MethodCall('saveBeforeExit')),
          (_) {},
        );
    await pumpEventQueue();
    expect(saved, isFalse);
    done.complete();
    await reply;
    expect(saved, isTrue);
  });
```

Extend the tray restore actions test: `Quit` with no sessions calls `flushAll(clean: true)` before `AgentController.shutdown` (record the order with the existing fakes: `RecordingFiles.layouts.last.cleanExit == true` is observed by the time the fake `shutdown` runs).

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/ui/info_strip_test.dart test/platform/app_reopen_test.dart test/tray`
Expected: FAIL.

- [ ] **Step 3: Implement**

(a) `info_strip.dart` — the A1 `SignedOutStrip` layout (copy its `TextButton` style block verbatim) with a close text button `Key('infoStrip.close')` labelled `l10n.actionClose`, wrapped in `Semantics(button: true, label: closeLabel, excludeSemantics: true)`, and the whole strip in `Semantics(container: true, liveRegion: true)`; `Container(key: Key('infoStrip'), height: ShellxSizes.signedOutStrip, …)`; `actions` go before the close button; `Shortcuts`/`Actions`: Esc while focus is inside calls `onClose`.

(b) `terminal_pane.dart` — after the signed-out `AnimatedSwitcher`, add a second `AnimatedSwitcher` (same duration/curve/`_stretch`) whose child is:

```dart
            child: switch (ref.watch(restorePersistenceProvider)) {
              final strip? => InfoStrip(
                key: const Key('pane.restoreStrip'),
                icon: Icons.history,
                iconColor: ShellxDesktopColors.textSecondary,
                text: strip.contentsAt == null
                    ? l10n.restoreAbnormalNoText(strip.tabs)
                    : l10n.restoreAbnormalStrip(
                        strip.tabs,
                        formatRestoreTime(
                          strip.contentsAt!,
                          ref.read(clockProvider)(),
                          localeName: l10n.localeName,
                          yesterday: l10n.restoreTimeYesterday,
                        ),
                      ),
                closeLabel: l10n.restoreStripCloseLabel,
                onClose: () {
                  ref.read(restorePersistenceProvider.notifier).dismissStrip();
                  widget.terminalFocus.requestFocus();
                },
              ),
              null => const SizedBox.shrink(),
            },
```

(use the pane's existing names for `l10n` and the terminal focus node; announce once with `SemanticsService.announce(text, Directionality.of(context))` in a post-frame callback when the strip first appears, per UI-A5 §4.)

(c) `app_reopen.dart`:

```dart
void listenForAppChannel({
  required void Function() onReopen,
  required void Function() onQuitRequested,
  Future<void> Function()? onSaveBeforeExit,
  MethodChannel channel = appChannel,
}) {
  channel.setMethodCallHandler((call) async {
    switch (call.method) {
      case 'reopen':
        onReopen();
      case 'quitRequested':
        onQuitRequested();
      case 'saveBeforeExit':
        // A5a D18: the OS is shutting down or logging out; the native side
        // waits (macOS ≤ 3 s) for this call to return.
        await onSaveBeforeExit?.call();
    }
  });
}
```

(d) `tray_actions.dart` — in `case Quit():` right after `_quitting = true;`:

```dart
        // A5a D12: the last save is clean, contents included.
        await runBounded(
          () => _ref.read(restorePersistenceProvider.notifier).flushAll(clean: true),
          timeout: const Duration(seconds: 2),
          label: 'saving the session layout',
        );
```

(e) `main.dart`:
- After `final settings = …` and before building the container:

```dart
  final restoreStore = RestoreStore(
    Directory(restoreDirectoryPath(
      windows: Platform.isWindows,
      environment: environment,
      appSupportPath: supportDirectory.path,
    )),
    excludeFromBackup: Platform.isMacOS
        ? (path) async {
            await Process.run('/usr/bin/tmutil', ['addexclusion', path]);
          }
        : null,
    log: debugPrint,
  );
  await restoreStore.prepare();
  final restoreLoad = await restoreStore.loadLayout();
```

  (move `final environment = …` above this block if needed).
- Add `restoreStoreProvider.overrideWithValue(restoreStore)` to the container overrides.
- Window hidden → save (not clean):

```dart
  container.listen<bool>(
    windowRouterProvider.select((s) => s.visible),
    (previous, visible) {
      if (previous == true && !visible) {
        _unawaitedLogged(
          container.read(restorePersistenceProvider.notifier).flushAll(clean: false),
          'restore save',
        );
      }
    },
  );
```

- `listenForAppChannel` is now registered on **both** platforms (Windows sends only `saveBeforeExit`):

```dart
  listenForAppChannel(
    onReopen: activate,
    onQuitRequested: () => unawaited(trayActions.handle(const Quit())),
    onSaveBeforeExit: () => runBounded(
      () => container.read(restorePersistenceProvider.notifier).flushAll(clean: true),
      timeout: const Duration(seconds: 2),
      label: 'saving before power-off',
    ),
  );
```

  (keep `onReopen`/`onQuitRequested` behaviour unchanged on macOS; on Windows they are never called.)
- Startup order (D16) — replace the end of `_start`:

```dart
  await container.read(agentControllerProvider.notifier).bootstrap();
  await WidgetsBinding.instance.endOfFrame;
  // A5a D16: restore before D11 so a restored window gets no extra tab.
  await container.read(restorePersistenceProvider.notifier).restoreAtStartup(restoreLoad);
  await handleActivation(container);
```

(f) `AppDelegate.swift` — replace `applicationShouldTerminate`:

```swift
  override func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    if quitIsForPowerOff || poweringOff {
      // A5a D18: never hold up a log out or shut down for more than 3 s,
      // but let Dart write the restore files first.
      guard AppChannel.isReady else { return .terminateNow }
      var replied = false
      let reply = {
        if replied { return }
        replied = true
        NSApp.reply(toApplicationShouldTerminate: true)
      }
      AppChannel.saveBeforeExit { reply() }
      DispatchQueue.main.asyncAfter(deadline: .now() + 3) { reply() }
      return .terminateLater
    }
    if !AppChannel.isReady { return .terminateNow }
    AppChannel.quitRequested()
    return .terminateCancel
  }
```

and in `enum AppChannel`:

```swift
  static func saveBeforeExit(_ done: @escaping () -> Void) {
    guard let channel else { done(); return }
    channel.invokeMethod("saveBeforeExit", arguments: nil) { _ in done() }
  }
```

(g) Windows runner — in `flutter_window.h` add `std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> app_channel_;`; in `FlutterWindow::OnCreate` after the taskbar channel:

```cpp
  // A5a D18: tell Dart the session is ending so it saves the restore files.
  app_channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      flutter_controller_->engine()->messenger(), "pro.shellx.desktop/app",
      &flutter::StandardMethodCodec::GetInstance());
```

in `OnDestroy` `app_channel_ = nullptr;`, and in `MessageHandler`'s switch:

```cpp
    case WM_QUERYENDSESSION:
      if (app_channel_) {
        app_channel_->InvokeMethod("saveBeforeExit", nullptr);
      }
      return TRUE;
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter build macos --debug`
Expected: suite green; macOS build succeeds (Swift compiles). Windows build runs in Windows CI.

- [ ] **Step 5: ⚠ Manual checks (macOS now; Windows on a Windows machine before release) — record results in the ledger**

1. ⌘Q with two workspaces, a 3-pane tab (one ratio dragged, one pane zoomed), `seq 1 5000` in a pane → reopen: spec criteria 1–3 hold; no extra tab.
2. `kill -9 $(pgrep -x ShellX)` → reopen: strip "ShellX đã đóng bất thường lần trước…" shows; Esc/"Đóng" dismisses it; F6 reaches it.
3. Apple menu → Restart without quitting ShellX → after login, open ShellX: layout restored; contents present (macOS waited for `saveBeforeExit`); **no** strip (clean).
4. `ls -l ~/Library/Application\ Support/pro.shellx.desktop/restore{,/scrollback}` → `drwx------`, files `-rw-------`; `tmutil isexcluded ~/Library/Application\ Support/pro.shellx.desktop/restore` → `[Excluded]`.
5. ⚠ Windows: Start → Restart with ShellX open; reopen → layout restored; contents present or ≤ 60 s old; `icacls %LOCALAPPDATA%\ShellX\restore` shows only the user, SYSTEM, Administrators.

- [ ] **Step 6: Format, analyze, commit**

```bash
~/fvm/versions/3.41.4/bin/dart format --set-exit-if-changed apps/desktop/lib apps/desktop/test
cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter analyze && cd ../..
git add apps/desktop/lib/src/ui/terminal/info_strip.dart apps/desktop/lib/src/ui/terminal/terminal_pane.dart apps/desktop/lib/src/platform/app_reopen.dart apps/desktop/lib/src/tray/tray_actions.dart apps/desktop/lib/main.dart apps/desktop/macos/Runner/AppDelegate.swift apps/desktop/windows/runner/flutter_window.cpp apps/desktop/windows/runner/flutter_window.h apps/desktop/test/ui/info_strip_test.dart apps/desktop/test/platform/app_reopen_test.dart apps/desktop/test/tray
git commit -m "feat(desktop): restore at startup, save on hide/quit/power-off, abnormal-end strip (A5a D12, D16, D18, D24)"
```

---

### Task 8: Privacy page, uninstaller, HANDOFF §15, performance probe, full verification (D19, D22)

**Files:**
- Modify: `web/src/pages/privacy.md`, `web/src/pages/en/privacy.md`
- Modify: `release/windows/shellx.iss`, `release/tests/inno.test.mjs`
- Modify: `docs/superpowers/HANDOFF.md`
- Create: `apps/desktop/test/restore/restore_benchmark_test.dart`

**Interfaces:**
- Consumes: everything above.
- Produces: documentation and an uninstall rule; a non-blocking benchmark that prints timings.

- [ ] **Step 1: Write the failing tests**

In `release/tests/inno.test.mjs` add:

```js
test('uninstall deletes the restore folder (A5a D22)', () => {
  assert.match(iss, /\[UninstallDelete\][^[]*Type: filesandordirs; Name: "\{localappdata\}\\ShellX\\restore"/);
});
```

(use the file's existing `iss` variable and `test`/`assert` imports).

Create `apps/desktop/test/restore/restore_benchmark_test.dart` (prints, never fails on time — spec criterion 10 is measured, not gated):

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/restore/scrollback_codec.dart';
import 'package:xterm/xterm.dart';

void main() {
  test('encode 32 panes × 2000 colored lines (prints timing)', () {
    final panes = [
      for (var p = 0; p < 32; p++)
        Terminal(maxLines: 10000)..resize(120, 40),
    ];
    for (final t in panes) {
      for (var i = 0; i < 2000; i++) {
        t.write('\x1b[3${i % 8}mline $i ${'x' * 80}\x1b[0m\r\n');
      }
    }
    final sw = Stopwatch()..start();
    var bytes = 0;
    for (final t in panes) {
      bytes += encodeScrollback(t).length;
    }
    sw.stop();
    // ignore: avoid_print
    print('A5a encode: ${sw.elapsedMilliseconds} ms for 32 panes, $bytes chars');
    expect(bytes, greaterThan(0));
  });
}
```

- [ ] **Step 2: Run tests to verify the release test fails**

Run: `cd release && node --test tests/inno.test.mjs`
Expected: FAIL — no `restore` uninstall rule.

- [ ] **Step 3: Implement**

(a) `shellx.iss` `[UninstallDelete]` — after the `term` line:

```
; A5a D22: saved session layout and terminal contents.
Type: filesandordirs; Name: "{localappdata}\ShellX\restore"
```

(b) `web/src/pages/privacy.md` §4 — add the bullet after "Full Disk Access":

```markdown
- **Khôi phục phiên (máy tính):** để mở lại đúng chỗ làm việc sau khi thoát hoặc khởi động lại máy, ShellX lưu bố cục tab/pane, thư mục làm việc và (nếu bật "Lưu nội dung terminal khi thoát", mặc định bật) tối đa 2.000 dòng nội dung cuối của mỗi terminal vào thư mục dữ liệu của ứng dụng trên máy bạn, chỉ tài khoản của bạn đọc được, không đưa vào bản sao lưu Time Machine. Nội dung này có thể chứa bất cứ thứ gì đã hiện trên terminal; nó không bao giờ được gửi lên máy chủ, tới điện thoại hay đồng bộ đi đâu. Bạn có thể tắt hoặc xóa ngay trong menu khay hệ thống → Terminal.
```

`web/src/pages/en/privacy.md` §4:

```markdown
- **Session restore (computer):** to reopen your workspace after you quit or restart the computer, ShellX saves the tab/pane layout, working folders and (if "Save terminal contents on quit" is on, the default) up to the last 2,000 lines of each terminal in the app's data folder on your computer, readable only by your account and excluded from Time Machine backups. These contents can include anything that was shown in the terminal; they are never sent to our servers, to your phone, or synced anywhere. You can turn this off or clear it at any time from the tray menu → Terminal.
```

Run `cd web && npm test` (the site tests check both pages build and keep their sections).

(c) `docs/superpowers/HANDOFF.md` — append:

```markdown
## 15. Khôi phục phiên — A5a (2026-10-07)

Spec `specs/2026-10-07-desktop-restore-a5a-design.md`, UI `design/2026-10-07-shellx-desktop-ui-a5.md`, plan `plans/2026-10-07-desktop-restore-a5a.md`. Shell **không** sống qua thoát (A5b mới làm); A5a mở shell mới ở thư mục cũ và vẽ lại nội dung cũ trên vạch "— Phiên được khôi phục · … —".

Riêng tư: `restore/` (macOS `~/Library/Application Support/pro.shellx.desktop/restore`, Windows `%LOCALAPPDATA%\ShellX\restore`) chứa nội dung terminal (có thể có bí mật): 0700/0600, loại khỏi Time Machine, không bao giờ rời máy; tắt/xoá ở tray → Terminal; gỡ cài đặt Windows xoá thư mục. Trang chính sách §4 đã cập nhật (vi/en).

### Thử tay — macOS
- [ ] ⌘Q / mở lại: workspace, tab, tên, cây pane, tỉ lệ, phóng to, pane focus, tab chọn; không có tab thừa
- [ ] `seq 1 5000` → 3001…5000 + vạch + prompt mới; `ls --color` giữ màu; `history` không có rác
- [ ] vim mở lúc thoát → nội dung trước vim được lưu, không có màn hình vim
- [ ] `kill -9` → dải "đóng bất thường"; Esc/Đóng; F6 tới được
- [ ] Khởi động lại máy không thoát app → khôi phục đủ, không có dải
- [ ] cwd bị xoá / ổ mạng ngắt / thư mục SMB → home, không chờ
- [ ] Tray → Terminal → bỏ chọn → `restore/scrollback` rỗng ngay; "Xóa nội dung đã lưu" mờ
- [ ] `ls -l` quyền 700/600; `tmutil isexcluded` → Excluded
- [ ] Điện thoại: phiên được khôi phục **không** có nội dung cũ
- [ ] Đo: log "A5a encode" của benchmark < 500 ms

### Thử tay — Windows
- [ ] Như macOS (trừ Time Machine); Start → Restart khi ShellX mở; `icacls` thư mục `restore`
- [ ] Gỡ cài đặt xoá `%LOCALAPPDATA%\ShellX\restore`
```

(d) Ledger: append to `docs/superpowers/ledgers/a1-desktop-terminal.md` under a new `## A5a (restore) — execution` heading the measured benchmark number and the manual-check results of Task 7 Step 5.

- [ ] **Step 4: Full verification**

Run:

```bash
cd release && node --test tests/ && cd ..
cd web && npm test && cd ..
cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter analyze && cd ../..
cd packages/shellx_agent && ~/fvm/versions/3.41.4/bin/dart test && cd ../..
```

Expected: all green; desktop count = Task-0 baseline + the new tests; agent count unchanged (A5a touches no agent code).

- [ ] **Step 5: Commit**

```bash
git add release/windows/shellx.iss release/tests/inno.test.mjs web/src/pages/privacy.md web/src/pages/en/privacy.md docs/superpowers/HANDOFF.md docs/superpowers/ledgers/a1-desktop-terminal.md apps/desktop/test/restore/restore_benchmark_test.dart
git commit -m "docs(desktop): A5a privacy note, uninstall cleanup, HANDOFF §15, restore benchmark (A5a D19, D22)"
```

---

## Self-Review

**Spec coverage** (spec §1 criteria → tasks): 1 layout → T2 (capture/parse), T4 (rebuild, adopt), T5 (debounce), T7 (startup order); 2 cwd → T4 (`open(cwd:)` + A3 D17); 3 contents/colour/rewrap/not to shell or phone → T1, T4 (D8 test), T5 (divider); 4 limits → T1; 5 reboot → T7 (D18 native) + T5 (60 s); 6 crash + strip → T5 (`cleanExit`), T7 (strip); 7 corrupt → T3; 8 switch → T5, T6; 9 places/permissions/no sync → T3, T7, T8; 10 performance → T8 benchmark (measured), T5 (dirty only); 11 no regression → full suite every task. Decisions: D1 → T2/T4 (`adopt`); D2 → T3; D3 → T3; D4 → T5/T7; D5/D6 → T1/T3; D7 → T4; D8 → T4/T5; D9 → T2; D10 → T4; D11 → T2/T3; D12 → T5/T7; D13 → T5/T6; D14 → T5; D15 → T3/T5; D16 → T7; D17 → T4 (`_grid`); D18 → T7; D19 → T5/T8; D20 → no code; D21 → T2 (`session`, `daemon` written, ignored); D22 → T8; D23 → T1; D24 → T7; D25 → T3; D26 → T1.

**Placeholder scan:** every code step has code; the two "if xterm reports …" notes give the exact alternative line.

**Type consistency:** `RestoreFiles` (T5) is implemented by `RestoreStore` (T3 class gains `implements` in T5); `RestorePlan.textByKey` already includes the divider (built in T5, consumed in T4); `keyBySession`/`tabIdByKey` names match across T4/T5; `TrayLocalState` (T6) consumed in T6 `main.dart`.

**Review Focus:** 1 → T4 concurrent-open test; 2 → T1 wide/wrap/byte-cap tests; 3 → T1 sanitizer + T3 corrupt/oversized tests; 4 → T3 serial-queue test + T5 switch test; 5 → T4 order/`openCwds` test (agent hang test lives in A3 Task 1).
