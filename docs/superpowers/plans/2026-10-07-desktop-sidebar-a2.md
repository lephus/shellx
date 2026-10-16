# ShellX Desktop A2 — Rich Sidebar Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Every sidebar tab shows a context line "git branch · ~/cwd · :ports" (ports are clickable), tabs can be renamed in place, and tabs are grouped into named, collapsible, drag-and-drop workspaces — cmux parity step A2.

**Architecture:** The agent (`packages/shellx_agent`) learns each session's directory from an OSC 7 its shell hooks now print at every prompt, resolves the git branch by reading `.git`/`HEAD` in pure Dart (never spawning `git`), and maps listening TCP ports to sessions by walking the process tree of each shell's PID — polling only while the window is shown. These arrive in `SessionSummary` (and, for opted-in phones, as optional `SessionInfo.cwd/branch`). The desktop keeps workspace membership and tab names as UI state (`SidebarWorkspaces`, `TerminalTabs`), persists only the workspace list, and renders headers, context lines, inline rename and drag-and-drop in the existing sidebar.

**Tech Stack:** Dart ^3.11 / Flutter 3.41.4 (fvm), `package:test` + `fake_async` (agent), `flutter_test` (desktop), flutter_riverpod 3, xterm 4.0.0 (unchanged), ARB l10n via `flutter gen-l10n`; `lsof`/`ps` (macOS), `netstat`/PowerShell CIM (Windows).

**Spec:** `docs/superpowers/specs/2026-10-07-desktop-sidebar-a2-design.md` (binding; decisions C1–C8 and D1–D19 are final). **UI design:** `docs/superpowers/design/2026-10-07-shellx-desktop-ui-a2.md` (binding for every measurement, state, string and wireframe; cited below as "UI-A2 §N"), on top of the A1 UI doc `docs/superpowers/design/2026-10-06-shellx-desktop-ui.md` ("UI-A1 §N"). Executors read the spec and UI-A2 before Task 1.

## Global Constraints

- The spec wins over everything else; UI-A2 (then UI-A1) wins for visuals and copy. Never invent a colour, size, duration or string: take it from the UI section the task names. **No new colour tokens** (UI-A2 §1.1).
- Toolchain: Flutter is `~/fvm/versions/3.41.4/bin/flutter`, Dart `~/fvm/versions/3.41.4/bin/dart`. Agent tests: `cd packages/shellx_agent && ~/fvm/versions/3.41.4/bin/dart test`. Core tests: `cd packages/shellx_core && ~/fvm/versions/3.41.4/bin/dart test`. Desktop tests: `cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test`. Format: `~/fvm/versions/3.41.4/bin/dart format --set-exit-if-changed <paths>`. Analyze: `~/fvm/versions/3.41.4/bin/dart analyze` in each package, `PATH=~/fvm/versions/3.41.4/bin:$PATH flutter analyze` in `apps/desktop`.
- **Do not touch `apps/mobile`** (another agent works there; mobile UI for cwd/branch is out of scope, spec §7). `relay/`, `web/` unchanged. `term/` changes only `term/shell/block.{zsh,bash,ps1}` (Task 2, spec D1).
- `packages/shellx_core` changes only `SessionInfo` (optional `cwd`, `branch`; spec C4). The decoder already ignores unknown keys; never add a required key.
- Agent never runs `git` (C2). Every child process has a timeout (2 s; Windows CIM 5 s) and is killed on timeout (D5). Nothing is spawned while the window is hidden or no session exists (spec criterion 4).
- Logging: `debugPrint`/the injected log with `runtimeType`, exit codes and counts only — **never** paths, branch names, ports, titles, command lines or terminal output.
- A1 behaviour is unchanged (C8): driver, exit rules, every A1 shortcut including Ctrl+F6. With only the Default workspace the sidebar renders exactly like A1 (D10).
- l10n: every new string goes into both `apps/desktop/lib/l10n/app_en.arb` (with `@key` metadata for placeholders) and `app_vi.arb` with identical keys, then `cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter gen-l10n`; generated `lib/l10n/app_localizations*.dart` are committed.
- New persisted settings keys must be added to `SettingKeys.all` (the shared_preferences allow-list).
- Interfaces gain members in this plan (`LocalSessions.watchPorts`, `UrlOpener.openLocalPort`): update **every** implementer in the same task (listed per task) so the tree always compiles.
- Code style: match the surrounding code (doc comments that say *why*, `final class`, no `print`). Every task ends with its tests green, `dart format --set-exit-if-changed` clean on touched files, analyzer clean, and a commit with a conventional message. Commit only the files the task lists — **never `git add -A`** (another agent works in this checkout).

## Review Focus

1. **A directory whose name has spaces, Vietnamese letters or `%`** (`~/Tài liệu/a b/100%`) must show exactly that name, never `%20` or mojibake, after a round trip through the shell hook and the agent. Pinned by `cwd_url_test` (Task 1) and the real-shell `hook_cwd_test` (Task 2).
2. **Many tabs in one huge repo, or a cwd on a slow network mount** — branch lookups must never block the UI, never pile up, and a late answer for an old directory must never overwrite the new one. Pinned by the coalescing/timeout tests in Task 3 and the stale-generation test in Task 5.
3. **A dev server started in the background, inside a nested shell, then killed** (`zsh` → `npm run dev &` → `vite`) — its port appears on the right tab within one scan and disappears after it dies; nothing is spawned while the window is hidden. Pinned by `PortWatcher` tests in Task 4 (nested owner, removal, hidden = no probe call) and Task 5 (`watchPorts`).
4. **Tabs closing, or a phone opening a tab, while a workspace is collapsed, being renamed or receiving a drag** — the closed tab leaves its workspace, an open rename of a closed tab is dropped, a phone tab lands in Default unselected. Pinned by `sidebar_workspaces_test` reconcile tests (Task 7).
5. **Settings from an older or corrupted install** (`terminal_workspaces` missing, bad JSON, duplicate ids, no Default) — the app starts with a usable Default workspace and drops only the bad entries. Pinned by the load tests in Task 7.

---

## File Structure

| File | Responsibility |
|---|---|
| Modify `packages/shellx_agent/lib/src/notify/osc_event_parser.dart` | `CwdReported` event for OSC 7 |
| Modify `packages/shellx_agent/lib/src/notify/command_tracker.dart` | Ignore `CwdReported` |
| Create `packages/shellx_agent/lib/src/context/cwd_url.dart` | `parseCwdUrl` → `LocalCwd` / `RemoteCwd` / null |
| Modify `packages/shellx_agent/lib/src/pty/shell_hook_scripts.dart`, `term/shell/block.zsh`, `block.bash`, `block.ps1` | OSC 7 at every prompt (D1) |
| Create `packages/shellx_agent/lib/src/context/git_head.dart` | `GitBranchLookup`, `GitHeadReader`, `GitFiles`, `parseGitHead` |
| Create `packages/shellx_agent/lib/src/context/listening_ports.dart` | Parsers, `PortProbe` (mac/win), `ownerOf`, `PortWatcher` |
| Modify `packages/shellx_agent/lib/src/pty/pty.dart`, `process_pty.dart` | `PtyProcessId` (D3) |
| Modify `packages/shellx_agent/lib/src/session/session_manager.dart`, `local_sessions.dart`, `session_router.dart` | cwd/branch/ports per session, `watchPorts`, `sessionInfosWithContext` |
| Modify `packages/shellx_agent/lib/shellx_agent.dart` | Exports |
| Modify `packages/shellx_core/lib/src/protocol/messages.dart` | `SessionInfo.cwd`, `.branch` |
| Modify `apps/desktop/lib/src/agent/session_core.dart`, `lib/main.dart`, `lib/src/platform/pty/flutter_pty_factory.dart`, `lib/src/platform/url_opener.dart` | Wiring, PID, `openLocalPort` |
| Create `apps/desktop/lib/src/terminal/port_watch.dart` | `listenForPortWatch` (D8) |
| Modify `apps/desktop/lib/src/terminal/terminal_tabs.dart`, `local_sessions_provider.dart` | Context fields, `customTitle`, `rename`, `showNotice`, `homeDirectoryProvider` |
| Create `apps/desktop/lib/src/terminal/sidebar_workspaces.dart` | Workspaces model, membership, visible order, persistence |
| Create `apps/desktop/lib/src/terminal/context_line.dart` | `displayPath`, ellipsis helpers, `layoutContextLine` (pure) |
| Create `apps/desktop/lib/src/ui/terminal/inline_name_field.dart` | Inline rename field (UI-A2 §4) |
| Create `apps/desktop/lib/src/ui/terminal/workspace_header.dart` | Header row (UI-A2 §3) |
| Modify `apps/desktop/lib/src/ui/terminal/session_tab_row.dart`, `session_sidebar.dart`, `shellx_menu.dart`, `terminal_shortcuts.dart`, `terminal_workspace_page.dart`, `terminal_overlays.dart`, `shortcut_labels.dart`, `lib/src/ui/theme/shellx_desktop_theme.dart`, `lib/src/platform/settings_store.dart` | UI |
| Modify `apps/desktop/lib/l10n/app_en.arb`, `app_vi.arb` (+ generated) | Strings (UI-A2 §7) |
| Tests listed per task | |
| Modify `docs/superpowers/specs/2026-09-25-shellx-v1-design.md`, `docs/superpowers/HANDOFF.md` | Protocol note, manual checklist |

---

### Task 1: Agent — OSC 7 events and `parseCwdUrl`

The parser reports `OSC 7 ; file://host/path` as `CwdReported(url)`; `parseCwdUrl` turns the URL into a local path, a "remote" signal (spec D2) or null (malformed).

**Files:**
- Modify: `packages/shellx_agent/lib/src/notify/osc_event_parser.dart`
- Modify: `packages/shellx_agent/lib/src/notify/command_tracker.dart:81`
- Create: `packages/shellx_agent/lib/src/context/cwd_url.dart`
- Modify: `packages/shellx_agent/lib/shellx_agent.dart`
- Create: `packages/shellx_agent/test/notify/osc7_event_test.dart`
- Create: `packages/shellx_agent/test/context/cwd_url_test.dart`

**Interfaces:**
- Consumes: `OscEventParser`, sealed `OscEvent` (existing).
- Produces:
  - `final class CwdReported extends OscEvent { const CwdReported(this.url); final String url; }`
  - `sealed class ReportedCwd`, `final class LocalCwd extends ReportedCwd { const LocalCwd(this.path); final String path; }`, `final class RemoteCwd extends ReportedCwd { const RemoteCwd(); }`
  - `ReportedCwd? parseCwdUrl(String url, {required bool windows, required String localHostName})`

- [ ] **Step 1: Write the failing tests**

Create `packages/shellx_agent/test/notify/osc7_event_test.dart`:

```dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:shellx_agent/shellx_agent.dart';
import 'package:test/test.dart';

Uint8List _b(String s) => Uint8List.fromList(utf8.encode(s));

void main() {
  test('OSC 7 is reported with BEL or ST, across chunks (A2 C1)', () {
    final parser = OscEventParser();
    expect(parser.feed(_b('\x1b]7;file://mbp/Users/r/a%20b\x07')), [
      const CwdReported('file://mbp/Users/r/a%20b'),
    ]);
    expect(parser.feed(_b('ls\r\n\x1b]7;file:///t')), isEmpty);
    expect(parser.feed(_b('mp\x1b\\')), [const CwdReported('file:///tmp')]);
  });

  test('a non-file URL and an oversized payload are ignored', () {
    final parser = OscEventParser();
    expect(parser.feed(_b('\x1b]7;http://x/y\x07')), isEmpty);
    expect(parser.feed(_b('\x1b]7;file:///${'a' * 5000}\x07')), isEmpty);
    // The parser is back in its ground state afterwards.
    expect(parser.feed(_b('\x1b]133;C\x07')), [const CommandStarted()]);
  });

  test('CommandTracker ignores CwdReported', () {
    final tracker = CommandTracker(threshold: () => Duration.zero);
    expect(tracker.handle(const CwdReported('file:///tmp')), isNull);
    expect(tracker.running, isFalse);
  });
}
```

Create `packages/shellx_agent/test/context/cwd_url_test.dart`:

```dart
import 'package:shellx_agent/shellx_agent.dart';
import 'package:test/test.dart';

String? local(ReportedCwd? cwd) => cwd is LocalCwd ? cwd.path : null;

void main() {
  ReportedCwd? mac(String url) =>
      parseCwdUrl(url, windows: false, localHostName: 'Richards-MBP.local');
  ReportedCwd? win(String url) =>
      parseCwdUrl(url, windows: true, localHostName: 'DESKTOP-1');

  group('POSIX', () {
    test('empty host, localhost and this machine are local', () {
      expect(local(mac('file:///Users/r')), '/Users/r');
      expect(local(mac('file://localhost/Users/r')), '/Users/r');
      expect(local(mac('file://richards-mbp/Users/r')), '/Users/r');
      expect(local(mac('file://Richards-MBP.local/Users/r')), '/Users/r');
    });

    test('percent-encoding is UTF-8: spaces, Vietnamese, % itself', () {
      expect(
        local(mac('file:///Users/r/T%C3%A0i%20li%E1%BB%87u/100%25')),
        '/Users/r/Tài liệu/100%',
      );
      // Raw non-ASCII (a hook that did not encode) is accepted as is.
      expect(local(mac('file:///Users/r/ư')), '/Users/r/ư');
    });

    test('another host is remote (D2): the caller forgets the directory', () {
      expect(mac('file://build-server/home/r'), isA<RemoteCwd>());
    });

    test('malformed URLs are null (ignored)', () {
      expect(mac('http:///Users/r'), isNull);
      expect(mac('file://'), isNull);
      expect(mac('file:///bad%zz'), isNull);
      expect(mac('file:///trunc%4'), isNull);
      expect(mac('file:///bad%FF%FE'), isNull); // not UTF-8
      expect(mac('file:///nul%00x'), isNull);
    });
  });

  group('Windows', () {
    test('a drive path becomes C:\\…', () {
      expect(local(win('file:///C:/Users/r/a%20b')), r'C:\Users\r\a b');
      expect(local(win('file:///d:')), r'D:\');
      expect(local(win('file://localhost/C:/x')), r'C:\x');
    });

    test('a server host is a UNC path, not remote', () {
      expect(local(win('file://nas/share/src')), r'\\nas\share\src');
    });

    test('a local URL without a drive is ignored', () {
      expect(win('file:///home/r'), isNull);
    });
  });
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd packages/shellx_agent && ~/fvm/versions/3.41.4/bin/dart test test/notify/osc7_event_test.dart test/context/cwd_url_test.dart`
Expected: FAIL — `CwdReported`, `parseCwdUrl`, `LocalCwd` are not defined.

- [ ] **Step 3: Add `CwdReported` to the parser**

In `packages/shellx_agent/lib/src/notify/osc_event_parser.dart`, after the `NotifyRequested` class add:

```dart
/// `OSC 7 ; file://<host>/<path>`: the shell's working directory, printed
/// by the ShellX hooks at every prompt (A2 C1). [url] is as sent;
/// `parseCwdUrl` decodes it.
final class CwdReported extends OscEvent {
  const CwdReported(this.url);
  final String url;
  @override
  bool operator ==(Object other) => other is CwdReported && other.url == url;
  @override
  int get hashCode => url.hashCode;
  @override
  String toString() => 'CwdReported(…)';
}
```

(`toString` hides the path on purpose: events may end up in test failure output or logs.)

Change the class doc comment's first line to `/// Finds OSC 7, 133 (C, D), 633 (E), 9 and 777 (\`notify\`) in terminal output,` and the number set:

```dart
  static const _numbers = {'7', '133', '633', '9', '777'};
```

In `_finish()` add the case before `'133'`:

```dart
      '7' => _osc7(text),
```

and add next to `_osc9`:

```dart
  static OscEvent? _osc7(String text) =>
      text.startsWith('file://') ? CwdReported(text) : null;
```

- [ ] **Step 4: Let `CommandTracker` ignore it**

In `packages/shellx_agent/lib/src/notify/command_tracker.dart` replace

```dart
      case NotifyRequested():
        break;
```

with

```dart
      case NotifyRequested() || CwdReported():
        break;
```

- [ ] **Step 5: Write `parseCwdUrl`**

Create `packages/shellx_agent/lib/src/context/cwd_url.dart`:

```dart
import 'dart:convert';

/// What an `OSC 7` URL says about a session's directory (A2 C1, D2).
sealed class ReportedCwd {
  const ReportedCwd();
}

/// A directory on this computer.
final class LocalCwd extends ReportedCwd {
  const LocalCwd(this.path);
  final String path;
  @override
  bool operator ==(Object other) => other is LocalCwd && other.path == path;
  @override
  int get hashCode => path.hashCode;
}

/// A directory on another host (a shell inside `ssh` that reports its own
/// directory): the session's directory and branch are forgotten rather
/// than shown wrong (D2).
final class RemoteCwd extends ReportedCwd {
  const RemoteCwd();
  @override
  bool operator ==(Object other) => other is RemoteCwd;
  @override
  int get hashCode => 7;
}

final _driveUrl = RegExp(r'^/([A-Za-z]):(/.*)?$');
final _hexDigit = RegExp(r'^[0-9A-Fa-f]$');

/// Decodes `file://<host>/<percent-encoded path>`. Null when the URL is not
/// a `file:` URL, its percent-encoding or UTF-8 is broken, or it holds a
/// NUL: the caller ignores it and keeps the directory it had.
///
/// [localHostName] is `Platform.localHostname`; a host is this computer
/// when it is empty, `localhost`, or has the same first DNS label (zsh's
/// `$HOST` is often the short name, the OS the `.local` one).
///
/// Windows: `file:///C:/x` is `C:\x`; a URL with a host that is not this
/// computer is a UNC path `\\host\share\x` (that is how PowerShell's
/// `[Uri]` writes one), never [RemoteCwd].
ReportedCwd? parseCwdUrl(
  String url, {
  required bool windows,
  required String localHostName,
}) {
  const scheme = 'file://';
  if (url.length <= scheme.length ||
      url.substring(0, scheme.length).toLowerCase() != scheme) {
    return null;
  }
  final rest = url.substring(scheme.length);
  final slash = rest.indexOf('/');
  if (slash < 0) return null;
  final host = rest.substring(0, slash);
  final path = _percentDecode(rest.substring(slash));
  if (path == null || path.contains('\u0000')) return null;
  final isLocal = _isLocalHost(host, localHostName);
  if (windows) {
    if (!isLocal) return LocalCwd(r'\\' + host + path.replaceAll('/', r'\'));
    final drive = _driveUrl.firstMatch(path);
    if (drive == null) return null;
    final tail = (drive[2] ?? '/').replaceAll('/', r'\');
    return LocalCwd('${drive[1]!.toUpperCase()}:$tail');
  }
  return isLocal ? LocalCwd(path) : const RemoteCwd();
}

bool _isLocalHost(String host, String localHostName) {
  if (host.isEmpty) return true;
  final h = host.toLowerCase();
  if (h == 'localhost') return true;
  String label(String name) => name.toLowerCase().split('.').first;
  return localHostName.isNotEmpty && label(h) == label(localHostName);
}

/// `%XX` → byte; other characters as their UTF-8; the bytes must be UTF-8.
String? _percentDecode(String text) {
  final runes = text.runes.toList();
  final bytes = <int>[];
  for (var i = 0; i < runes.length; i++) {
    final rune = runes[i];
    if (rune != 0x25) {
      bytes.addAll(utf8.encode(String.fromCharCode(rune)));
      continue;
    }
    if (i + 2 >= runes.length) return null;
    final hi = String.fromCharCode(runes[i + 1]);
    final lo = String.fromCharCode(runes[i + 2]);
    if (!_hexDigit.hasMatch(hi) || !_hexDigit.hasMatch(lo)) return null;
    bytes.add(int.parse('$hi$lo', radix: 16));
    i += 2;
  }
  try {
    return utf8.decode(bytes);
  } on FormatException {
    return null;
  }
}
```

Add to `packages/shellx_agent/lib/shellx_agent.dart` (keep the list sorted):

```dart
export 'src/context/cwd_url.dart';
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `cd packages/shellx_agent && ~/fvm/versions/3.41.4/bin/dart test test/notify test/context`
Expected: PASS (all old notify tests too).

- [ ] **Step 7: Format, analyze, commit**

```bash
cd packages/shellx_agent
~/fvm/versions/3.41.4/bin/dart format --set-exit-if-changed lib/src/notify lib/src/context lib/shellx_agent.dart test/notify/osc7_event_test.dart test/context
~/fvm/versions/3.41.4/bin/dart analyze
cd ../..
git add packages/shellx_agent/lib/src/notify/osc_event_parser.dart packages/shellx_agent/lib/src/notify/command_tracker.dart packages/shellx_agent/lib/src/context/cwd_url.dart packages/shellx_agent/lib/shellx_agent.dart packages/shellx_agent/test/notify/osc7_event_test.dart packages/shellx_agent/test/context/cwd_url_test.dart
git commit -m "feat(agent): OSC 7 working-directory events and parseCwdUrl (A2 C1, D2)"
```

---

### Task 2: Agent — the shell hooks print OSC 7 at every prompt

zsh, bash and PowerShell hooks print `ESC ] 7 ; file://<host><percent-encoded $PWD> BEL` at each prompt (spec C1). The same lines go into the inner-shell branch of `term/shell/block.*` (spec D1; `shell_hook_sync_test.dart` enforces identical code).

**Files:**
- Modify: `packages/shellx_agent/lib/src/pty/shell_hook_scripts.dart` (`zshHookBody`, `bashHookBody`, `powerShellHookBody`)
- Modify: `term/shell/block.zsh`, `term/shell/block.bash`, `term/shell/block.ps1` (the copies of those bodies)
- Create: `packages/shellx_agent/test/pty/hook_cwd_test.dart`

**Interfaces:**
- Consumes: `SessionManager.open`, `.view` (A1), `ShellIntegration`, `ProcessPtyFactory`.
- Produces: shells started by ShellX print OSC 7 at the first prompt and after every command line (including an empty Enter). Bytes outside `-/._~A-Za-z0-9` are `%XX` (upper case) of the UTF-8 bytes. zsh host: `$HOST`; bash: `$HOSTNAME`; PowerShell: none (`[Uri].AbsoluteUri` → `file:///C:/…`).

- [ ] **Step 1: Write the failing real-shell test**

Create `packages/shellx_agent/test/pty/hook_cwd_test.dart`:

```dart
@TestOn('mac-os || linux')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:shellx_agent/shellx_agent.dart';
import 'package:test/test.dart';

import '../support/fake_pty.dart' show FixedShellResolver;

final _plain = RegExp(r'^[-/._~A-Za-z0-9]$');

/// The hooks' encoding: every byte outside `-/._~A-Za-z0-9` as `%XX`.
String _encode(String path) {
  final out = StringBuffer();
  for (final byte in utf8.encode(path)) {
    final c = String.fromCharCode(byte);
    if (byte < 0x80 && _plain.hasMatch(c)) {
      out.write(c);
    } else {
      out.write('%${byte.toRadixString(16).toUpperCase().padLeft(2, '0')}');
    }
  }
  return out.toString();
}

void main() {
  for (final shell in const [
    ShellCommand(executable: '/bin/zsh', arguments: ['-i'], name: 'zsh'),
    ShellCommand(executable: '/bin/bash', arguments: ['-i'], name: 'bash'),
  ]) {
    test('${shell.name}: the first prompt and every later one print OSC 7 '
        'with the percent-encoded directory (A2 C1)', () async {
      final temp = Directory.systemTemp.createTempSync('shellx-osc7-');
      addTearDown(() => temp.deleteSync(recursive: true));
      final home = Directory('${temp.path}/home')..createSync();
      final target = Directory('${temp.path}/a b/Tài liệu 100%')
        ..createSync(recursive: true);
      final manager = SessionManager(
        ptyFactory: const ProcessPtyFactory(),
        shellResolver: FixedShellResolver(shell),
        homeDirectory: home.path,
        baseEnvironment: {
          'HOME': home.path,
          'PATH': '/usr/bin:/bin',
          'LANG': 'en_US.UTF-8',
          'BASH_SILENCE_DEPRECATION_WARNING': '1',
        },
        shellIntegration: ShellIntegration(directory: '${temp.path}/hooks'),
      );
      addTearDown(manager.closeAll);
      final id = await manager.open(cols: 80, rows: 24);
      final view = manager.view(id);
      final text = StringBuffer();
      final sub = view.output.listen(
        (data) => text.write(utf8.decode(data, allowMalformed: true)),
      );
      addTearDown(sub.cancel);

      Future<void> waitFor(String needle) async {
        final deadline = DateTime.now().add(const Duration(seconds: 15));
        while (!text.toString().contains(needle)) {
          if (DateTime.now().isAfter(deadline)) {
            fail('no ${jsonEncode(needle)} in the output');
          }
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
      }

      await waitFor('${_encode(home.path)}\x07'); // first prompt, in $HOME
      view.write(utf8.encode("cd '${target.path}'\n"));
      await waitFor('${_encode(target.path)}\x07');
      expect(text.toString(), contains('\x1b]7;file://'));
    });
  }
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd packages/shellx_agent && ~/fvm/versions/3.41.4/bin/dart test test/pty/hook_cwd_test.dart`
Expected: FAIL — `no "…\u0007" in the output` (no hook prints OSC 7 yet).

- [ ] **Step 3: zsh — `__shellx_osc7`, called from `__shellx_precmd` and `__shellx_install`**

In `zshHookBody` (`shell_hook_scripts.dart`), insert as the first definition inside `if (( ! ${+functions[__shellx_precmd]} )); then`:

```
    __shellx_osc7() {
      local url_path= i ch hexch LC_CTYPE=C LC_COLLATE=C LC_ALL= LANG=
      for (( i = 1; i <= ${#PWD}; ++i )); do
        ch=${PWD[i]}
        if [[ $ch == [-/._~A-Za-z0-9] ]]; then
          url_path+=$ch
        else
          builtin printf -v hexch '%02X' "'$ch"
          url_path+="%${hexch: -2:2}"
        fi
      done
      builtin printf '\e]7;file://%s%s\a' "${HOST-}" "$url_path"
    }
```

(`LC_CTYPE=C` makes `${PWD[i]}` one byte, as in macOS's own `/etc/zshrc_Apple_Terminal`; `${hexch: -2:2}` keeps the last two digits where `printf` sign-extends a byte ≥ 0x80.)

Replace `__shellx_precmd` with:

```
    __shellx_precmd() {
      local ret=$?
      if [[ -n ${__shellx_running-} ]]; then
        builtin printf '\e]133;D;%s\a' "$ret"
        builtin unset __shellx_running
      fi
      __shellx_osc7
      return ret
    }
```

and append one line at the end of `__shellx_install`'s body (after the `shellx()` block's closing `fi`), so the first prompt reports too (the precmd that installs us runs before ours is in the list):

```
      __shellx_osc7
```

- [ ] **Step 4: bash — `__shellx_osc7`, called from both prompt paths**

In `bashHookBody`, insert after the `__shellx_esc() { … }` function:

```
  __shellx_osc7() {
    local LC_ALL=C s=$PWD out= c h i
    for ((i = 0; i < ${#s}; i++)); do
      c=${s:i:1}
      case "$c" in
        [-/._~A-Za-z0-9]) out+=$c ;;
        *) builtin printf -v h '%02X' "'$c"; out+="%${h: -2:2}" ;;
      esac
    done
    builtin printf '\033]7;file://%s%s\007' "${HOSTNAME-}" "$out"
  }
```

In `__shellx_bp_precmd`, insert `__shellx_osc7` on its own line right before `return $ret`. In `__shellx_prompt_start`, insert `__shellx_osc7` on its own line right after the `fi` that closes the `__shellx_running` block (before the bash-preexec check). Both keep `$?` because `ret` was saved first.

- [ ] **Step 5: PowerShell — append OSC 7 to the prompt mark**

In `powerShellHookBody`, inside `$global:__ShellxPrompt`, insert after the closing `}` of `if ($global:__ShellxRunning) { … }` and before `$text = …`:

```
      $loc = $executionContext.SessionState.Path.CurrentLocation
      if ($loc.Provider.Name -eq 'FileSystem') {
        try { $mark += "$([char]27)]7;$(([System.Uri]$loc.ProviderPath).AbsoluteUri)$([char]7)" } catch { }
      }
```

(`[Uri]'C:\a b'` → `file:///C:/a%20b`; `\\nas\share` → `file://nas/share`. ASCII only, as the file header requires.)

- [ ] **Step 6: Copy the same edits into `term/shell/block.*`**

`term/shell/block.zsh`, `block.bash`, `block.ps1` contain the same bodies inside their inner-shell branch, indented deeper. Apply Steps 3–5 there at the matching lines (same text, the block's indentation). The sync test compares trimmed lines in order.

Run: `cd packages/shellx_agent && ~/fvm/versions/3.41.4/bin/dart test test/pty/shell_hook_sync_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 7: Run the hook tests**

Run: `cd packages/shellx_agent && ~/fvm/versions/3.41.4/bin/dart test test/pty test/notify/hook_notifications_test.dart`
Expected: PASS — `hook_cwd_test` (zsh, bash) and the existing notification e2e tests (OSC 7 must not disturb 133/633).

- [ ] **Step 8: Format, analyze, commit**

```bash
cd packages/shellx_agent
~/fvm/versions/3.41.4/bin/dart format --set-exit-if-changed lib/src/pty/shell_hook_scripts.dart test/pty/hook_cwd_test.dart
~/fvm/versions/3.41.4/bin/dart analyze
cd ../..
git add packages/shellx_agent/lib/src/pty/shell_hook_scripts.dart packages/shellx_agent/test/pty/hook_cwd_test.dart term/shell/block.zsh term/shell/block.bash term/shell/block.ps1
git commit -m "feat(agent): shell hooks report the working directory as OSC 7 at every prompt (A2 C1, D1)"
```

---
### Task 3: Agent — `GitHeadReader` (branch from `.git`/`HEAD`, pure Dart)

Finds the git directory above a path (following `gitdir:` files for worktrees and submodules), reads `HEAD`, caches `directory → git dir`, coalesces concurrent lookups and gives up after 500 ms (spec C2, §5). Never throws, never spawns `git`.

**Files:**
- Create: `packages/shellx_agent/lib/src/context/git_head.dart`
- Modify: `packages/shellx_agent/lib/shellx_agent.dart`
- Create: `packages/shellx_agent/test/context/git_head_test.dart`

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces:
  - `abstract interface class GitBranchLookup { Future<String?> branchFor(String directory, {bool refresh = false}); }`
  - `final class GitHeadReader implements GitBranchLookup` — `GitHeadReader({GitFiles files = const IoGitFiles(), Duration timeout = const Duration(milliseconds: 500), int maxDepth = 64, int cacheSize = 64, bool? windows})`
  - `enum GitEntry { none, file, directory }`
  - `abstract interface class GitFiles { Future<GitEntry> entry(String path); Future<String> readSmall(String path, int limit); }`, `final class IoGitFiles implements GitFiles`
  - `String? parseGitHead(String content)`

- [ ] **Step 1: Write the failing tests**

Create `packages/shellx_agent/test/context/git_head_test.dart`:

```dart
import 'dart:async';
import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:test/test.dart';

/// In-memory [GitFiles]: counts `entry` calls; [gate] holds every `entry`.
final class _Files implements GitFiles {
  _Files(this.entries, this.contents);
  final Map<String, GitEntry> entries;
  final Map<String, String> contents;
  int entryCalls = 0;
  Completer<void>? gate;

  @override
  Future<GitEntry> entry(String path) async {
    entryCalls++;
    await gate?.future;
    return entries[path] ?? GitEntry.none;
  }

  @override
  Future<String> readSmall(String path, int limit) async {
    final content = contents[path];
    if (content == null) throw FileSystemException('missing', path);
    return content;
  }
}

void main() {
  test('parseGitHead: branch, other refs, detached SHA-1/SHA-256, junk', () {
    expect(parseGitHead('ref: refs/heads/main\n'), 'main');
    expect(parseGitHead('ref: refs/heads/feat/a2'), 'feat/a2');
    expect(parseGitHead('ref: refs/remotes/origin/x'), 'remotes/origin/x');
    expect(parseGitHead('${'a1b2c3d4' * 5}\n'), 'a1b2c3d');
    expect(parseGitHead('b' * 64), 'bbbbbbb');
    expect(parseGitHead('hello'), isNull);
    expect(parseGitHead('ref: refs/heads/${'x' * 300}')!.length, 200);
  });

  group('on disk', () {
    late Directory temp;
    setUp(() => temp = Directory.systemTemp.createTempSync('shellx-git-'));
    tearDown(() => temp.deleteSync(recursive: true));

    String repo(String name, String head) {
      final git = Directory('${temp.path}/$name/.git')
        ..createSync(recursive: true);
      File('${git.path}/HEAD').writeAsStringSync(head);
      return '${temp.path}/$name';
    }

    test('a repo and a deep subdirectory give its branch; HEAD is re-read '
        'on every lookup', () async {
      final root = repo('app', 'ref: refs/heads/main\n');
      final deep = Directory('$root/a/b/c')..createSync(recursive: true);
      final reader = GitHeadReader();
      expect(await reader.branchFor(root), 'main');
      expect(await reader.branchFor(deep.path), 'main');
      File('$root/.git/HEAD').writeAsStringSync('ref: refs/heads/dev\n');
      expect(await reader.branchFor(deep.path), 'dev');
    });

    test('detached HEAD gives the short SHA', () async {
      final root = repo('det', '0123456789abcdef0123456789abcdef01234567\n');
      expect(await GitHeadReader().branchFor(root), '0123456');
    });

    test('a worktree follows an absolute gitdir: file', () async {
      final root = repo('main', 'ref: refs/heads/main\n');
      final wtGit = Directory('$root/.git/worktrees/wt')
        ..createSync(recursive: true);
      File('${wtGit.path}/HEAD').writeAsStringSync('ref: refs/heads/feature\n');
      final wt = Directory('${temp.path}/wt')..createSync();
      File('${wt.path}/.git').writeAsStringSync('gitdir: ${wtGit.path}\n');
      expect(await GitHeadReader().branchFor(wt.path), 'feature');
    });

    test('a submodule follows a relative gitdir: file', () async {
      final root = repo('super', 'ref: refs/heads/main\n');
      final modGit = Directory('$root/.git/modules/lib')
        ..createSync(recursive: true);
      File('${modGit.path}/HEAD').writeAsStringSync('ref: refs/heads/pin\n');
      final src = Directory('$root/lib/src')..createSync(recursive: true);
      File('$root/lib/.git').writeAsStringSync('gitdir: ../.git/modules/lib\n');
      expect(await GitHeadReader().branchFor(src.path), 'pin');
    });

    test(
      'an unreadable HEAD gives null and never throws',
      () async {
        final root = repo('locked', 'ref: refs/heads/main\n');
        final head = '$root/.git/HEAD';
        Process.runSync('chmod', ['000', head]);
        addTearDown(() => Process.runSync('chmod', ['644', head]));
        expect(await GitHeadReader().branchFor(root), isNull);
      },
      testOn: 'mac-os || linux',
    );
  });

  test('not a repo: walks to the root once, then answers from the cache', () async {
    final files = _Files({}, {});
    final reader = GitHeadReader(files: files, windows: false);
    expect(await reader.branchFor('/a/b'), isNull);
    expect(files.entryCalls, 3); // /a/b/.git, /a/.git, /.git
    expect(await reader.branchFor('/a/b'), isNull);
    expect(files.entryCalls, 3);
    expect(await reader.branchFor('/a/b', refresh: true), isNull);
    expect(files.entryCalls, 6);
  });

  test('concurrent lookups of one directory share one walk', () async {
    final files = _Files(
      {'/r/.git': GitEntry.directory},
      {'/r/.git/HEAD': 'ref: refs/heads/main'},
    )..gate = Completer<void>();
    final reader = GitHeadReader(files: files, windows: false);
    final first = reader.branchFor('/r/src');
    final second = reader.branchFor('/r/src');
    files.gate!.complete();
    expect(await Future.wait([first, second]), ['main', 'main']);
    expect(files.entryCalls, 2); // /r/src/.git, /r/.git
  });

  test('Windows paths: backslashes, drive root ends the walk', () async {
    final files = _Files(
      {r'C:\r\.git': GitEntry.directory},
      {r'C:\r\.git\HEAD': 'ref: refs/heads/win'},
    );
    final reader = GitHeadReader(files: files, windows: true);
    expect(await reader.branchFor(r'C:\r\src'), 'win');
    expect(await reader.branchFor(r'D:\x'), isNull);
    expect(files.entryCalls, 4); // C:\r\src, C:\r; D:\x, D:\ (root ends it)
  });

  test('a lookup slower than 500 ms gives null', () {
    fakeAsync((async) {
      final files = _Files({}, {})..gate = Completer<void>();
      final reader = GitHeadReader(files: files, windows: false);
      String? result = 'pending';
      reader.branchFor('/slow/mount').then((b) => result = b);
      async.elapse(const Duration(milliseconds: 499));
      expect(result, 'pending');
      async.elapse(const Duration(milliseconds: 2));
      expect(result, isNull);
    });
  });
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd packages/shellx_agent && ~/fvm/versions/3.41.4/bin/dart test test/context/git_head_test.dart`
Expected: FAIL — `GitHeadReader`, `GitFiles`, `parseGitHead` not defined.

- [ ] **Step 3: Write `git_head.dart`**

Create `packages/shellx_agent/lib/src/context/git_head.dart`:

```dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// The git branch of a directory (A2 C2). Never throws.
abstract interface class GitBranchLookup {
  /// The branch name, a 7-character SHA when HEAD is detached, or null
  /// (not a repo, unreadable, too slow). [refresh] forgets what is cached
  /// for [directory] first (a command just ran: `git init`, `git switch`).
  Future<String?> branchFor(String directory, {bool refresh = false});
}

enum GitEntry { none, file, directory }

/// The file-system calls [GitHeadReader] makes (faked in tests).
abstract interface class GitFiles {
  /// What [path] is; [GitEntry.none] when it is missing or not readable.
  Future<GitEntry> entry(String path);

  /// At most [limit] bytes of [path] as text. Throws [FileSystemException].
  Future<String> readSmall(String path, int limit);
}

final class IoGitFiles implements GitFiles {
  const IoGitFiles();

  @override
  Future<GitEntry> entry(String path) async =>
      switch (await FileSystemEntity.type(path)) {
        FileSystemEntityType.directory => GitEntry.directory,
        FileSystemEntityType.file => GitEntry.file,
        _ => GitEntry.none,
      };

  @override
  Future<String> readSmall(String path, int limit) async {
    final file = await File(path).open();
    try {
      return utf8.decode(await file.read(limit), allowMalformed: true);
    } finally {
      await file.close();
    }
  }
}

final _sha = RegExp(r'^[0-9a-f]{40}([0-9a-f]{24})?$');

/// `ref: refs/heads/<name>` → `<name>`; another `ref: refs/<x>` → `<x>`;
/// a 40/64-hex SHA (detached) → its first 7 characters; else null. At
/// most 200 characters.
String? parseGitHead(String content) {
  final text = content.trim();
  String clip(String s) => String.fromCharCodes(
    s.runes.take(GitHeadReader.maxBranchLength),
  );
  if (text.startsWith('ref:')) {
    final ref = text.substring(4).trim();
    if (ref.isEmpty) return null;
    const heads = 'refs/heads/';
    if (ref.startsWith(heads)) return clip(ref.substring(heads.length));
    return clip(ref.startsWith('refs/') ? ref.substring(5) : ref);
  }
  return _sha.hasMatch(text) ? text.substring(0, 7) : null;
}

/// Finds `.git` above a directory (a directory, or a `gitdir:` file for
/// worktrees and submodules) and reads its `HEAD` (C2). Only `.git` is
/// stat-ed per level and only two small files are read, so a huge repo
/// costs the same as a tiny one. `directory → git dir` is cached (LRU,
/// [cacheSize]), including "not a repo"; HEAD is read again every time.
/// One lookup per directory runs at a time; one that takes longer than
/// [timeout] (a slow network mount) answers null and finishes in the
/// background.
final class GitHeadReader implements GitBranchLookup {
  GitHeadReader({
    GitFiles files = const IoGitFiles(),
    this.timeout = const Duration(milliseconds: 500),
    this.maxDepth = 64,
    this.cacheSize = 64,
    bool? windows,
  }) : _files = files,
       _windows = windows ?? Platform.isWindows;

  static const int maxFileBytes = 4096;
  static const int maxBranchLength = 200;

  final GitFiles _files;
  final Duration timeout;
  final int maxDepth;
  final int cacheSize;
  final bool _windows;

  /// A map literal keeps insertion order: the first key is the least
  /// recently used.
  final _gitDirs = <String, String?>{};
  final _inFlight = <String, Future<String?>>{};

  @override
  Future<String?> branchFor(String directory, {bool refresh = false}) {
    if (refresh) _gitDirs.remove(directory);
    final running = _inFlight[directory];
    if (running != null && !refresh) return running;
    final lookup = _resolve(directory)
        .timeout(timeout, onTimeout: () => null)
        .catchError((Object _) => null);
    _inFlight[directory] = lookup;
    unawaited(
      lookup.whenComplete(() {
        if (identical(_inFlight[directory], lookup)) {
          _inFlight.remove(directory);
        }
      }),
    );
    return lookup;
  }

  Future<String?> _resolve(String directory) async {
    final String? gitDir;
    if (_gitDirs.containsKey(directory)) {
      gitDir = _gitDirs.remove(directory);
      _gitDirs[directory] = gitDir; // most recently used
    } else {
      gitDir = await _findGitDir(directory);
      _remember(directory, gitDir);
    }
    if (gitDir == null) return null;
    try {
      return parseGitHead(
        await _files.readSmall(_join(gitDir, 'HEAD'), maxFileBytes),
      );
    } on FileSystemException {
      return null;
    }
  }

  Future<String?> _findGitDir(String directory) async {
    var current = _trim(directory);
    for (var depth = 0; depth < maxDepth; depth++) {
      final dotGit = _join(current, '.git');
      switch (await _files.entry(dotGit)) {
        case GitEntry.directory:
          return dotGit;
        case GitEntry.file:
          return _followGitFile(dotGit, current);
        case GitEntry.none:
          break;
      }
      final parent = _parent(current);
      if (parent == null) return null;
      current = parent;
    }
    return null;
  }

  /// A worktree's or submodule's `.git` file: `gitdir: <path>`, relative
  /// to the directory that holds the file.
  Future<String?> _followGitFile(String dotGit, String holder) async {
    final String text;
    try {
      text = await _files.readSmall(dotGit, maxFileBytes);
    } on FileSystemException {
      return null;
    }
    final line = const LineSplitter().convert(text).firstOrNull?.trim() ?? '';
    const prefix = 'gitdir:';
    if (!line.startsWith(prefix)) return null;
    final target = line.substring(prefix.length).trim();
    if (target.isEmpty) return null;
    return _isAbsolute(target) ? target : _join(holder, target);
  }

  void _remember(String directory, String? gitDir) {
    _gitDirs.remove(directory);
    _gitDirs[directory] = gitDir;
    while (_gitDirs.length > cacheSize) {
      _gitDirs.remove(_gitDirs.keys.first);
    }
  }

  bool _isSep(String c) => c == '/' || (_windows && c == r'\');

  String _join(String dir, String name) =>
      _isSep(dir[dir.length - 1]) ? '$dir$name' : '$dir${_windows ? r'\' : '/'}$name';

  static final _windowsAbsolute = RegExp(r'^([A-Za-z]:[\\/]|[\\/]{2})');
  static final _driveRoot = RegExp(r'^[A-Za-z]:[\\/]?$');
  static final _uncRoot = RegExp(r'^[\\/]{2}[^\\/]+[\\/][^\\/]+[\\/]?$');

  bool _isAbsolute(String path) => _windows
      ? _windowsAbsolute.hasMatch(path) || path.startsWith('/')
      : path.startsWith('/');

  bool _isRoot(String path) => _windows
      ? _driveRoot.hasMatch(path) || _uncRoot.hasMatch(path)
      : path == '/';

  String _trim(String path) {
    var p = path;
    while (p.length > 1 && _isSep(p[p.length - 1]) && !_isRoot(p)) {
      p = p.substring(0, p.length - 1);
    }
    return p;
  }

  /// The parent directory; null at a root (`/`, `C:\`, `\\server\share`).
  String? _parent(String path) {
    if (_isRoot(path)) return null;
    var end = path.length;
    while (end > 0 && !_isSep(path[end - 1])) {
      end--;
    }
    if (end == 0) return null;
    final parent = path.substring(0, end); // with its trailing separator
    return _isRoot(parent) ? parent : _trim(parent);
  }
}
```

Export it from `packages/shellx_agent/lib/shellx_agent.dart`:

```dart
export 'src/context/git_head.dart';
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd packages/shellx_agent && ~/fvm/versions/3.41.4/bin/dart test test/context/git_head_test.dart`
Expected: PASS (10 tests; the chmod test is skipped on Windows).

- [ ] **Step 5: Format, analyze, commit**

```bash
cd packages/shellx_agent
~/fvm/versions/3.41.4/bin/dart format --set-exit-if-changed lib/src/context/git_head.dart lib/shellx_agent.dart test/context/git_head_test.dart
~/fvm/versions/3.41.4/bin/dart analyze
cd ../..
git add packages/shellx_agent/lib/src/context/git_head.dart packages/shellx_agent/lib/shellx_agent.dart packages/shellx_agent/test/context/git_head_test.dart
git commit -m "feat(agent): GitHeadReader resolves the branch from .git/HEAD without running git (A2 C2)"
```

---

### Task 4: Agent — listening ports: parsers, probes, `PortWatcher`, shell PID

Finds the TCP ports each session's process tree listens on (spec C3, D3–D7). `PortWatcher` owns the schedule: on only while visible and with sessions; one scan at a time, 3 s after the last finished, backing off when slow or failing; the process table is read only when a listening PID is not classified yet.

**Files:**
- Modify: `packages/shellx_agent/lib/src/pty/pty.dart` (add `PtyProcessId`)
- Modify: `packages/shellx_agent/lib/src/pty/process_pty.dart` (`_ProcessPty implements Pty, PtyProcessId`)
- Create: `packages/shellx_agent/lib/src/context/listening_ports.dart`
- Modify: `packages/shellx_agent/lib/shellx_agent.dart`
- Create: `packages/shellx_agent/test/context/listening_ports_test.dart`
- Create: `packages/shellx_agent/test/context/port_watcher_test.dart`

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces:
  - `abstract interface class PtyProcessId { int? get processId; }`
  - `final class ProbeOutput { const ProbeOutput(this.exitCode, this.stdout); final int exitCode; final String stdout; }`
  - `typedef TimedCommandRunner = Future<ProbeOutput> Function(String executable, List<String> arguments, {required Duration timeout});`
  - `Future<ProbeOutput> runWithTimeout(String executable, List<String> arguments, {required Duration timeout})`
  - `final class PortProbeException implements Exception { const PortProbeException(this.message); final String message; }`
  - `Map<int, Set<int>> parseLsofListen(String)`, `Map<int, Set<int>> parseNetstatListen(String)`, `Map<int, int> parseParentTable(String)`
  - `int? ownerOf(int pid, Map<int, int> parents, Map<int, int> shellToSession)`
  - `abstract interface class PortProbe { Future<Map<int, Set<int>>> listening(); Future<Map<int, int>> parents(); }`; `MacPortProbe({TimedCommandRunner run = runWithTimeout})`, `WindowsPortProbe({TimedCommandRunner run = runWithTimeout})`
  - `final class PortWatcher` — `PortWatcher({required PortProbe probe, required Map<int, int> Function() shells, required void Function(Map<int, List<int>> ports) onPorts, DateTime Function()? now, Duration interval = const Duration(seconds: 3), Duration slowScan = const Duration(milliseconds: 1500), Duration maxInterval = const Duration(seconds: 15), void Function(String message)? log})`; `void setVisible(bool visible)`, `void sessionsChanged()`, `void dispose()`. `shells()` maps **session id → shell pid**; `onPorts` gets **session id → ascending ports** (sessions without ports absent).

- [ ] **Step 1: Write the failing parser/probe tests**

Create `packages/shellx_agent/test/context/listening_ports_test.dart`:

```dart
import 'package:shellx_agent/shellx_agent.dart';
import 'package:test/test.dart';

const _lsof = '''
p612
f12
n*:5173
f13
n[::1]:5173
p701
f4
n127.0.0.1:8080
f5
n127.0.0.1:8080->127.0.0.1:50000
''';

const _netstat = '''

Active Connections

  Proto  Local Address          Foreign Address        State           PID
  TCP    0.0.0.0:135            0.0.0.0:0              LISTENING       1012
  TCP    127.0.0.1:5173         0.0.0.0:0              ABHÖREN         4321
  TCP    127.0.0.1:5173         127.0.0.1:50000        ESTABLISHED     4321
  TCP    [::]:3000              [::]:0                 LISTENING       4400
  TCP    0.0.0.0:445            0.0.0.0:0              LISTENING       0
  UDP    0.0.0.0:5353           *:*                                    2000
''';

void main() {
  test('lsof -Fpn: ports per pid, IPv4/IPv6 merged, peers ignored', () {
    expect(parseLsofListen(_lsof), {
      612: {5173},
      701: {8080},
    });
  });

  test('netstat -ano: listening = foreign port 0, whatever the state word '
      '(translated on some Windows languages, D7)', () {
    expect(parseNetstatListen(_netstat), {
      1012: {135},
      4321: {5173},
      4400: {3000},
    });
  });

  test('ps / CIM "pid ppid" lines', () {
    expect(parseParentTable('  1     0\n 100     1\n 200   100\nbad line\n'), {
      1: 0,
      100: 1,
      200: 100,
    });
  });

  test('ownerOf: nearest shell ancestor; cycles and dead parents end', () {
    final parents = {300: 200, 200: 100, 100: 1, 7: 8, 8: 7};
    expect(ownerOf(300, parents, {100: 1}), 1);
    expect(ownerOf(300, parents, {100: 1, 200: 2}), 2); // nested shell
    expect(ownerOf(100, parents, {100: 1}), 1); // the shell itself
    expect(ownerOf(7, parents, {100: 1}), isNull); // cycle
    expect(ownerOf(999, parents, {100: 1}), isNull); // unknown
  });

  group('MacPortProbe', () {
    test('runs lsof and ps with the exact arguments and a 2 s timeout', () async {
      final calls = <String>[];
      final probe = MacPortProbe(
        run: (exe, args, {required timeout}) async {
          calls.add('$exe ${args.join(' ')} ${timeout.inSeconds}');
          return ProbeOutput(0, exe.endsWith('lsof') ? _lsof : '100 1\n');
        },
      );
      expect(await probe.listening(), hasLength(2));
      expect(await probe.parents(), {100: 1});
      expect(calls, [
        '/usr/sbin/lsof -nP -iTCP -sTCP:LISTEN -Fpn 2',
        '/bin/ps -axo pid=,ppid= 2',
      ]);
    });

    test('lsof exit 1 with no output means no ports (D6)', () async {
      final probe = MacPortProbe(
        run: (exe, args, {required timeout}) async => const ProbeOutput(1, ''),
      );
      expect(await probe.listening(), isEmpty);
    });

    test('another exit code is a PortProbeException', () async {
      final probe = MacPortProbe(
        run: (exe, args, {required timeout}) async => const ProbeOutput(2, ''),
      );
      expect(probe.listening(), throwsA(isA<PortProbeException>()));
      expect(probe.parents(), throwsA(isA<PortProbeException>()));
    });
  });

  test('WindowsPortProbe runs netstat -ano and CIM through PowerShell '
      '(5 s), never wmic', () async {
    final calls = <String>[];
    final probe = WindowsPortProbe(
      run: (exe, args, {required timeout}) async {
        calls.add('$exe ${args.first} ${timeout.inSeconds}');
        return ProbeOutput(0, exe == 'netstat' ? _netstat : '4321 100\n');
      },
    );
    expect(await probe.listening(), hasLength(3));
    expect(await probe.parents(), {4321: 100});
    expect(calls, ['netstat -ano 2', 'powershell -NoProfile 5']);
  });

  test(
    'runWithTimeout returns the output, and kills a command that is too slow',
    () async {
      final echo = await runWithTimeout(
        '/bin/echo',
        ['hi'],
        timeout: const Duration(seconds: 2),
      );
      expect((echo.exitCode, echo.stdout), (0, 'hi\n'));
      final started = DateTime.now();
      await expectLater(
        runWithTimeout(
          '/bin/sleep',
          ['5'],
          timeout: const Duration(milliseconds: 200),
        ),
        throwsA(isA<PortProbeException>()),
      );
      expect(DateTime.now().difference(started).inSeconds, lessThan(2));
      await expectLater(
        runWithTimeout('/no/such/tool', [], timeout: const Duration(seconds: 1)),
        throwsA(isA<PortProbeException>()),
      );
    },
    testOn: 'mac-os || linux',
  );
}
```

Create `packages/shellx_agent/test/context/port_watcher_test.dart`:

```dart
import 'package:fake_async/fake_async.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:test/test.dart';

final class _Probe implements PortProbe {
  Map<int, Set<int>> ports = {};
  Map<int, int> tree = {};
  int listeningCalls = 0;
  int parentCalls = 0;
  Duration delay = Duration.zero;
  Object? fail;

  @override
  Future<Map<int, Set<int>>> listening() async {
    listeningCalls++;
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    final error = fail;
    if (error != null) throw error;
    return {for (final e in ports.entries) e.key: {...e.value}};
  }

  @override
  Future<Map<int, int>> parents() async {
    parentCalls++;
    return Map.of(tree);
  }
}

void main() {
  late _Probe probe;
  late Map<int, int> shells; // session id → shell pid
  late List<Map<int, List<int>>> published;

  setUp(() {
    probe = _Probe()
      ..tree = {200: 100, 300: 200, 400: 1}
      ..ports = {
        300: {5173, 3000},
        400: {9999}, // not in any session's tree
      };
    shells = {1: 100};
    published = [];
  });

  PortWatcher watcher(FakeAsync async) => PortWatcher(
    probe: probe,
    shells: () => shells,
    onPorts: published.add,
    now: () => DateTime(2026, 10, 7).add(async.elapsed),
  );

  test('hidden: nothing is ever spawned (spec criterion 4)', () {
    fakeAsync((async) {
      watcher(async);
      async.elapse(const Duration(seconds: 30));
      expect(probe.listeningCalls, 0);
    });
  });

  test('visible without sessions: nothing is spawned', () {
    fakeAsync((async) {
      shells = {};
      watcher(async).setVisible(true);
      async.elapse(const Duration(seconds: 30));
      expect(probe.listeningCalls, 0);
    });
  });

  test('visible: scans at once, then 3 s after each scan; the process table '
      'is read only for an unclassified pid (D4, D5)', () {
    fakeAsync((async) {
      watcher(async).setVisible(true);
      async.elapse(Duration.zero);
      expect(published.last, {
        1: [3000, 5173],
      });
      expect((probe.listeningCalls, probe.parentCalls), (1, 1));
      async.elapse(const Duration(milliseconds: 2999));
      expect(probe.listeningCalls, 1);
      async.elapse(const Duration(milliseconds: 2));
      expect((probe.listeningCalls, probe.parentCalls), (2, 1));
      probe.ports[500] = {8080};
      probe.tree[500] = 100;
      async.elapse(const Duration(seconds: 3));
      expect(probe.parentCalls, 2);
      expect(published.last, {
        1: [3000, 5173, 8080],
      });
    });
  });

  test('a nested shell owns the ports of its own children', () {
    fakeAsync((async) {
      shells = {1: 100, 2: 200};
      watcher(async).setVisible(true);
      async.elapse(Duration.zero);
      expect(published.last, {
        2: [3000, 5173],
      });
    });
  });

  test('a server that stops listening disappears at the next scan', () {
    fakeAsync((async) {
      watcher(async).setVisible(true);
      async.elapse(Duration.zero);
      probe.ports.remove(300);
      async.elapse(const Duration(seconds: 3));
      expect(published.last, isEmpty);
    });
  });

  test('hiding stops scanning; showing again scans at once', () {
    fakeAsync((async) {
      final w = watcher(async)..setVisible(true);
      async.elapse(Duration.zero);
      w.setVisible(false);
      async.elapse(const Duration(seconds: 30));
      expect(probe.listeningCalls, 1);
      w.setVisible(true);
      async.elapse(Duration.zero);
      expect(probe.listeningCalls, 2);
    });
  });

  test('a scan slower than 1.5 s doubles the gap, up to 15 s (D5)', () {
    fakeAsync((async) {
      probe.delay = const Duration(seconds: 2);
      watcher(async).setVisible(true);
      async.elapse(const Duration(seconds: 2)); // first scan done at 2 s
      expect(probe.listeningCalls, 1);
      async.elapse(const Duration(milliseconds: 5900)); // 7.9 s
      expect(probe.listeningCalls, 1);
      async.elapse(const Duration(milliseconds: 200)); // 8.1 s: 2 + 6
      expect(probe.listeningCalls, 2);
    });
  });

  test('one failure keeps the ports, a second clears them and backs off '
      'to 15 s (D6)', () {
    fakeAsync((async) {
      watcher(async).setVisible(true);
      async.elapse(Duration.zero);
      expect(published, hasLength(1));
      probe.fail = const PortProbeException('lsof exited with code 2');
      async.elapse(const Duration(seconds: 3));
      expect(published, hasLength(1));
      async.elapse(const Duration(seconds: 15));
      expect(published.last, isEmpty);
      final calls = probe.listeningCalls;
      async.elapse(const Duration(seconds: 14));
      expect(probe.listeningCalls, calls);
    });
  });

  test('sessionsChanged reclassifies and restarts a watcher that stopped '
      'for lack of sessions', () {
    fakeAsync((async) {
      shells = {};
      final w = watcher(async)..setVisible(true);
      async.elapse(Duration.zero);
      expect(probe.listeningCalls, 0);
      shells = {1: 100};
      w.sessionsChanged();
      async.elapse(Duration.zero);
      expect(published.last, {
        1: [3000, 5173],
      });
      w.dispose();
      async.elapse(const Duration(seconds: 30));
      expect(probe.listeningCalls, 1);
    });
  });
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd packages/shellx_agent && ~/fvm/versions/3.41.4/bin/dart test test/context/listening_ports_test.dart test/context/port_watcher_test.dart`
Expected: FAIL — `PortWatcher`, `PortProbe`, `parseLsofListen`… not defined.

- [ ] **Step 3: `PtyProcessId`**

Append to `packages/shellx_agent/lib/src/pty/pty.dart`:

```dart
/// A [Pty] that knows its shell's process id (A2 D3), for finding the
/// ports its process tree listens on. A separate interface so the many
/// [Pty] fakes stay valid; a pty without it simply has no ports.
abstract interface class PtyProcessId {
  /// Null until the process has started.
  int? get processId;
}
```

In `packages/shellx_agent/lib/src/pty/process_pty.dart` change `final class _ProcessPty implements Pty {` to `final class _ProcessPty implements Pty, PtyProcessId {` and add:

```dart
  @override
  int? get processId => _process?.pid;
```

- [ ] **Step 4: Write `listening_ports.dart`**

Create `packages/shellx_agent/lib/src/context/listening_ports.dart`:

```dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

/// A child process's exit code and standard output.
final class ProbeOutput {
  const ProbeOutput(this.exitCode, this.stdout);
  final int exitCode;
  final String stdout;
}

typedef TimedCommandRunner =
    Future<ProbeOutput> Function(
      String executable,
      List<String> arguments, {
      required Duration timeout,
    });

/// Ports could not be looked up. [message] names the tool and an exit
/// code or OS error number, never output or paths.
final class PortProbeException implements Exception {
  const PortProbeException(this.message);
  final String message;
  @override
  String toString() => 'PortProbeException: $message';
}

String _tool(String executable) =>
    executable.split(RegExp(r'[\\/]')).last;

/// Runs [executable] and kills it when it takes longer than [timeout]
/// (D5). Throws [PortProbeException] when it cannot start or is killed.
Future<ProbeOutput> runWithTimeout(
  String executable,
  List<String> arguments, {
  required Duration timeout,
}) async {
  final Process process;
  try {
    process = await Process.start(executable, arguments);
  } on ProcessException catch (error) {
    throw PortProbeException(
      'cannot run ${_tool(executable)} (OS error ${error.errorCode})',
    );
  }
  unawaited(process.stdin.close().catchError((Object _) {}));
  unawaited(process.stderr.drain<void>().catchError((Object _) {}));
  final stdout = process.stdout
      .transform(const Utf8Decoder(allowMalformed: true))
      .join();
  try {
    final code = await process.exitCode.timeout(timeout);
    return ProbeOutput(code, await stdout);
  } on TimeoutException {
    process.kill(ProcessSignal.sigkill);
    stdout.ignore();
    throw PortProbeException('${_tool(executable)} timed out');
  }
}

int? _portOf(String address) {
  if (address.contains('->')) return null; // a connection, not a listener
  final colon = address.lastIndexOf(':');
  if (colon < 0) return null;
  final port = int.tryParse(address.substring(colon + 1));
  return port != null && port > 0 && port <= 65535 ? port : null;
}

/// `lsof -nP -iTCP -sTCP:LISTEN -Fpn`: a `p<pid>` line, then `f<fd>` and
/// `n<address>` lines of that process (`*:3000`, `127.0.0.1:5173`,
/// `[::1]:8080`). IPv4 and IPv6 sockets of one port count once.
Map<int, Set<int>> parseLsofListen(String output) {
  final result = <int, Set<int>>{};
  int? pid;
  for (final line in const LineSplitter().convert(output)) {
    if (line.isEmpty) continue;
    switch (line[0]) {
      case 'p':
        pid = int.tryParse(line.substring(1));
      case 'n':
        final port = _portOf(line.substring(1));
        if (pid != null && port != null) {
          result.putIfAbsent(pid, () => <int>{}).add(port);
        }
    }
  }
  return result;
}

final _spaces = RegExp(r'\s+');

/// `netstat -ano` (Windows): `TCP <local> <foreign> <state> <pid>`. A
/// listening socket's foreign address ends in `:0` (`0.0.0.0:0`,
/// `[::]:0`); the state word is translated on some Windows languages, so
/// it is not read (D7). PID 0 (the system) is skipped.
Map<int, Set<int>> parseNetstatListen(String output) {
  final result = <int, Set<int>>{};
  for (final line in const LineSplitter().convert(output)) {
    final parts = line.trim().split(_spaces);
    if (parts.length != 5 || parts[0].toUpperCase() != 'TCP') continue;
    if (!parts[2].endsWith(':0')) continue;
    final port = _portOf(parts[1]);
    final pid = int.tryParse(parts[4]);
    if (port == null || pid == null || pid == 0) continue;
    result.putIfAbsent(pid, () => <int>{}).add(port);
  }
  return result;
}

/// `pid ppid` per line (`ps -axo pid=,ppid=`, and the CIM query below).
Map<int, int> parseParentTable(String output) {
  final result = <int, int>{};
  for (final line in const LineSplitter().convert(output)) {
    final parts = line.trim().split(_spaces);
    if (parts.length < 2) continue;
    final pid = int.tryParse(parts[0]);
    final parent = int.tryParse(parts[1]);
    if (pid != null && parent != null) result[pid] = parent;
  }
  return result;
}

/// The session whose shell is [pid] or its nearest ancestor (D4), walking
/// at most 64 parent links; null on a cycle, a missing or dead parent.
int? ownerOf(int pid, Map<int, int> parents, Map<int, int> shellToSession) {
  var current = pid;
  final seen = <int>{};
  for (var step = 0; step < 64; step++) {
    final session = shellToSession[current];
    if (session != null) return session;
    if (!seen.add(current)) return null;
    final parent = parents[current];
    if (parent == null || parent <= 0 || parent == current) return null;
    current = parent;
  }
  return null;
}

/// Where listening ports and the process tree come from.
abstract interface class PortProbe {
  /// Listening TCP ports by pid. Throws [PortProbeException].
  Future<Map<int, Set<int>>> listening();

  /// Parent pid by pid. Throws [PortProbeException].
  Future<Map<int, int>> parents();
}

/// macOS: `lsof` and `ps` (C3).
final class MacPortProbe implements PortProbe {
  MacPortProbe({TimedCommandRunner run = runWithTimeout}) : _run = run;
  final TimedCommandRunner _run;
  static const timeout = Duration(seconds: 2);

  @override
  Future<Map<int, Set<int>>> listening() async {
    final out = await _run('/usr/sbin/lsof', const [
      '-nP',
      '-iTCP',
      '-sTCP:LISTEN',
      '-Fpn',
    ], timeout: timeout);
    // lsof exits 1 when nothing matched (D6).
    if (out.exitCode == 1 && out.stdout.trim().isEmpty) return const {};
    if (out.exitCode != 0) {
      throw PortProbeException('lsof exited with code ${out.exitCode}');
    }
    return parseLsofListen(out.stdout);
  }

  @override
  Future<Map<int, int>> parents() async {
    final out = await _run('/bin/ps', const [
      '-axo',
      'pid=,ppid=',
    ], timeout: timeout);
    if (out.exitCode != 0) {
      throw PortProbeException('ps exited with code ${out.exitCode}');
    }
    return parseParentTable(out.stdout);
  }
}

/// Windows: `netstat -ano` for ports (fast), CIM through PowerShell for
/// the process tree (about a second, so only when D4 needs it). Not
/// `wmic`: Windows 11 24H2 removed it (D7).
final class WindowsPortProbe implements PortProbe {
  WindowsPortProbe({TimedCommandRunner run = runWithTimeout}) : _run = run;
  final TimedCommandRunner _run;
  static const timeout = Duration(seconds: 2);
  static const cimTimeout = Duration(seconds: 5);

  @override
  Future<Map<int, Set<int>>> listening() async {
    final out = await _run('netstat', const ['-ano'], timeout: timeout);
    if (out.exitCode != 0) {
      throw PortProbeException('netstat exited with code ${out.exitCode}');
    }
    return parseNetstatListen(out.stdout);
  }

  @override
  Future<Map<int, int>> parents() async {
    final out = await _run('powershell', const [
      '-NoProfile',
      '-NonInteractive',
      '-Command',
      r"Get-CimInstance Win32_Process -Property ProcessId,ParentProcessId | "
          r"ForEach-Object { '{0} {1}' -f $_.ProcessId, $_.ParentProcessId }",
    ], timeout: cimTimeout);
    if (out.exitCode != 0) {
      throw PortProbeException('powershell exited with code ${out.exitCode}');
    }
    return parseParentTable(out.stdout);
  }
}

/// Polls [PortProbe] for the sessions' listening ports (C3, D4–D6).
///
/// Runs only while [setVisible] is true **and** [shells] is not empty: no
/// child process otherwise (spec criterion 4). One scan at a time; the
/// next starts [interval] after the last one finished, twice the last gap
/// (up to [maxInterval]) when a scan took longer than [slowScan], and
/// [maxInterval] after a failure. One failure keeps the last ports; two in
/// a row clear them. Listening pids are classified once (the process
/// table is read only when one is new, or after [sessionsChanged]).
final class PortWatcher {
  PortWatcher({
    required PortProbe probe,
    required Map<int, int> Function() shells,
    required void Function(Map<int, List<int>> ports) onPorts,
    DateTime Function()? now,
    this.interval = const Duration(seconds: 3),
    this.slowScan = const Duration(milliseconds: 1500),
    this.maxInterval = const Duration(seconds: 15),
    void Function(String message)? log,
  }) : _probe = probe,
       _shells = shells,
       _onPorts = onPorts,
       _now = now ?? DateTime.now,
       _log = log ?? ((_) {}),
       _gap = interval;

  final PortProbe _probe;
  final Map<int, int> Function() _shells;
  final void Function(Map<int, List<int>> ports) _onPorts;
  final DateTime Function() _now;
  final void Function(String message) _log;
  final Duration interval;
  final Duration slowScan;
  final Duration maxInterval;

  bool _visible = false;
  bool _scanning = false;
  bool _disposed = false;
  Timer? _timer;
  Duration _gap;
  int _failures = 0;

  /// Listening pid → owning session id (null: none of ours).
  final _owners = <int, int?>{};

  void setVisible(bool visible) {
    if (_disposed || _visible == visible) return;
    _visible = visible;
    if (visible) {
      _gap = interval;
      _kick();
    } else {
      _timer?.cancel();
      _timer = null;
    }
  }

  /// A session started or ended: classify again; start if idle.
  void sessionsChanged() {
    _owners.clear();
    if (_visible && !_disposed && _timer == null && !_scanning) _kick();
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _timer = null;
  }

  void _kick() {
    _timer?.cancel();
    _timer = Timer(Duration.zero, _tick);
  }

  Future<void> _tick() async {
    _timer = null;
    if (_disposed || !_visible || _scanning) return;
    final shells = _shells();
    if (shells.isEmpty) {
      _owners.clear();
      return; // sessionsChanged starts us again
    }
    _scanning = true;
    final started = _now();
    try {
      _onPorts(await _scan(shells));
      _failures = 0;
    } catch (error) {
      _failures++;
      _log(
        'port scan failed: '
        '${error is PortProbeException ? error.message : error.runtimeType}',
      );
      if (_failures >= 2) _onPorts(const {});
    } finally {
      _scanning = false;
    }
    if (_disposed || !_visible) return;
    final took = _now().difference(started);
    _gap = _failures > 0
        ? maxInterval
        : took > slowScan
        ? Duration(
            microseconds: min(
              (_gap * 2).inMicroseconds,
              maxInterval.inMicroseconds,
            ),
          )
        : interval;
    _timer = Timer(_gap, _tick);
  }

  Future<Map<int, List<int>>> _scan(Map<int, int> shells) async {
    final listening = await _probe.listening();
    _owners.removeWhere((pid, _) => !listening.containsKey(pid));
    if (listening.keys.any((pid) => !_owners.containsKey(pid))) {
      final parents = await _probe.parents();
      final shellToSession = {
        for (final e in shells.entries) e.value: e.key,
      };
      for (final pid in listening.keys) {
        _owners.putIfAbsent(
          pid,
          () => ownerOf(pid, parents, shellToSession),
        );
      }
    }
    final bySession = <int, Set<int>>{};
    for (final MapEntry(key: pid, value: ports) in listening.entries) {
      final session = _owners[pid];
      if (session != null && shells.containsKey(session)) {
        bySession.putIfAbsent(session, () => <int>{}).addAll(ports);
      }
    }
    return {
      for (final e in bySession.entries) e.key: e.value.toList()..sort(),
    };
  }
}
```

Export it from `packages/shellx_agent/lib/shellx_agent.dart`:

```dart
export 'src/context/listening_ports.dart';
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `cd packages/shellx_agent && ~/fvm/versions/3.41.4/bin/dart test test/context test/pty/process_pty_test.dart`
Expected: PASS.

- [ ] **Step 6: Format, analyze, commit**

```bash
cd packages/shellx_agent
~/fvm/versions/3.41.4/bin/dart format --set-exit-if-changed lib/src/pty/pty.dart lib/src/pty/process_pty.dart lib/src/context/listening_ports.dart lib/shellx_agent.dart test/context
~/fvm/versions/3.41.4/bin/dart analyze
cd ../..
git add packages/shellx_agent/lib/src/pty/pty.dart packages/shellx_agent/lib/src/pty/process_pty.dart packages/shellx_agent/lib/src/context/listening_ports.dart packages/shellx_agent/lib/shellx_agent.dart packages/shellx_agent/test/context/listening_ports_test.dart packages/shellx_agent/test/context/port_watcher_test.dart
git commit -m "feat(agent): listening ports per session process tree with a visibility-gated PortWatcher (A2 C3, D3-D7)"
```

---

### Task 5: Agent + core — cwd, branch and ports in each session; `watchPorts`; `SessionInfo.cwd/branch`

`SessionManager` tracks OSC 7 (cwd), looks up the branch on cwd change and at OSC 133;D, applies `PortWatcher` results, and exposes them in `SessionSummary`. `LocalSessions.watchPorts(bool)` gates scanning. `SessionInfo` gains optional `cwd`/`branch`, sent only to phones that listed with `desktop: true` (spec C4).

**Files:**
- Modify: `packages/shellx_agent/lib/src/session/session_manager.dart`
- Modify: `packages/shellx_agent/lib/src/session/local_sessions.dart`
- Modify: `packages/shellx_agent/lib/src/session/session_router.dart:69-77`
- Modify: `packages/shellx_core/lib/src/protocol/messages.dart:124-187` (`SessionInfo`)
- Modify: `packages/shellx_agent/test/support/fake_pty.dart`, `test/support/session_rig.dart`
- Create: `packages/shellx_agent/test/session/session_context_test.dart`
- Modify: `packages/shellx_agent/test/session/session_router_test.dart` (append a test)
- Modify: `packages/shellx_core/test/protocol/messages_test.dart` (append a test)

**Interfaces:**
- Consumes: `CwdReported`, `parseCwdUrl`, `LocalCwd`, `RemoteCwd` (Task 1); `GitBranchLookup` (Task 3); `PortProbe`, `PortWatcher`, `PtyProcessId` (Task 4).
- Produces:
  - `SessionManager({…, GitBranchLookup? gitHeads, PortProbe? portProbe, bool windowsPaths = false, String localHostName = '', void Function(String message)? log})`
  - `SessionSummary` gains `final String? cwd`, `final String? gitBranch`, `final List<int> ports` (default `const []`), constructor params `this.cwd, this.gitBranch, this.ports = const []`.
  - `LocalSessions.watchPorts(bool visible)` (interface member; `SessionManager` implements it).
  - `List<SessionInfo> SessionManager.sessionInfosWithContext`
  - `SessionInfo({…, this.cwd = '', this.branch = ''})`, `final String cwd`, `final String branch`; wire keys `cwd`, `branch`, written only when non-empty.

- [ ] **Step 1: Let the test fakes carry a pid and the rig take the new options**

In `packages/shellx_agent/test/support/fake_pty.dart`, change `final class FakePty implements Pty {` to `final class FakePty implements Pty, PtyProcessId {` and add below `bool killed = false;`:

```dart
  /// The shell's pid for port tests (A2 D3); null = unknown.
  @override
  int? processId;
```

In `packages/shellx_agent/test/support/session_rig.dart`, add two constructor parameters and pass them on (keep every other line):

```dart
  SessionRig({
    int maxSessions = 10,
    int bufferCapacity = 256 * 1024,
    int sendWindow = 256 * 1024,
    Duration driverHold = const Duration(seconds: 1),
    Random? random,
    GitBranchLookup? gitHeads,
    PortProbe? portProbe,
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
      gitHeads: gitHeads,
      portProbe: portProbe,
      localHostName: 'mbp.local',
    );
    manager.outbound.listen(sent.add);
  }
```

- [ ] **Step 2: Write the failing tests**

Create `packages/shellx_agent/test/session/session_context_test.dart`:

```dart
import 'dart:async';
import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:test/test.dart';

import '../support/session_rig.dart';

const _esc = '\x1b';
const _bel = '\x07';
String _osc7(String path, {String host = ''}) => '$_esc]7;file://$host$path$_bel';

/// Answers each lookup when the test completes its completer.
final class _Lookup implements GitBranchLookup {
  final calls = <(String, bool)>[];
  final answers = <Completer<String?>>[];

  @override
  Future<String?> branchFor(String directory, {bool refresh = false}) {
    calls.add((directory, refresh));
    final answer = Completer<String?>();
    answers.add(answer);
    return answer.future;
  }
}

final class _Probe implements PortProbe {
  int calls = 0;
  @override
  Future<Map<int, Set<int>>> listening() async {
    calls++;
    return {
      300: {5173, 3000},
    };
  }

  @override
  Future<Map<int, int>> parents() async => {300: 100};
}

void main() {
  test('OSC 7 sets the summary cwd (decoded) and fires changes', () async {
    final rig = SessionRig();
    await rig.manager.open(cols: 80, rows: 24);
    var changes = 0;
    rig.manager.changes.listen((_) => changes++);
    rig.pty(0).emit(_osc7('/Users/test/T%C3%A0i%20li%E1%BB%87u'));
    await pumpEventQueue();
    expect(rig.manager.sessions.single.cwd, '/Users/test/Tài liệu');
    expect(changes, greaterThan(0));
  });

  test('a malformed OSC 7 keeps the cwd; another host clears cwd and '
      'branch (D2)', () async {
    final lookup = _Lookup();
    final rig = SessionRig(gitHeads: lookup);
    await rig.manager.open(cols: 80, rows: 24);
    rig.pty(0).emit(_osc7('/r'));
    lookup.answers.last.complete('main');
    await pumpEventQueue();
    expect(rig.manager.sessions.single.gitBranch, 'main');
    rig.pty(0).emit('$_esc]7;file:///bad%zz$_bel');
    await pumpEventQueue();
    expect(rig.manager.sessions.single.cwd, '/r');
    rig.pty(0).emit(_osc7('/home/r', host: 'build-server'));
    await pumpEventQueue();
    final summary = rig.manager.sessions.single;
    expect((summary.cwd, summary.gitBranch), (null, null));
  });

  test('a late answer for an older directory is dropped (Review Focus 2)', () async {
    final lookup = _Lookup();
    final rig = SessionRig(gitHeads: lookup);
    await rig.manager.open(cols: 80, rows: 24);
    rig.pty(0).emit(_osc7('/a'));
    rig.pty(0).emit(_osc7('/b'));
    await pumpEventQueue();
    expect(lookup.calls, [('/a', false), ('/b', false)]);
    lookup.answers[1].complete('b-branch');
    await pumpEventQueue();
    lookup.answers[0].complete('a-branch');
    await pumpEventQueue();
    expect(rig.manager.sessions.single.gitBranch, 'b-branch');
  });

  test('OSC 133;D looks the branch up again with refresh', () async {
    final lookup = _Lookup();
    final rig = SessionRig(gitHeads: lookup);
    await rig.manager.open(cols: 80, rows: 24);
    rig.pty(0).emit(_osc7('/r'));
    rig.pty(0).emit('$_esc]133;C$_bel$_esc]133;D;0$_bel');
    await pumpEventQueue();
    expect(lookup.calls.last, ('/r', true));
  });

  test('a real repository: the branch appears, and follows git switch', () async {
    final temp = Directory.systemTemp.createTempSync('shellx-ctx-');
    addTearDown(() => temp.deleteSync(recursive: true));
    Directory('${temp.path}/.git').createSync();
    final head = File('${temp.path}/.git/HEAD')
      ..writeAsStringSync('ref: refs/heads/main\n');
    final rig = SessionRig(gitHeads: GitHeadReader());
    await rig.manager.open(cols: 80, rows: 24);

    Future<void> until(String branch) async {
      for (var i = 0; i < 200; i++) {
        if (rig.manager.sessions.single.gitBranch == branch) return;
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      fail('branch never became $branch');
    }

    rig.pty(0).emit(_osc7(Uri.directory(temp.path).path));
    await until('main');
    head.writeAsStringSync('ref: refs/heads/dev\n');
    rig.pty(0).emit('$_esc]133;C$_bel$_esc]133;D;0$_bel');
    await until('dev');
  }, testOn: 'mac-os || linux');

  test('watchPorts: ports of the shell tree reach the summary; hidden = no '
      'probe call (spec criterion 4)', () {
    fakeAsync((async) {
      final probe = _Probe();
      final rig = SessionRig(portProbe: probe);
      rig.manager.open(cols: 80, rows: 24);
      async.flushMicrotasks();
      rig.pty(0).processId = 100;
      async.elapse(const Duration(seconds: 10));
      expect(probe.calls, 0);
      rig.manager.watchPorts(true);
      async.elapse(Duration.zero);
      expect(rig.manager.sessions.single.ports, [3000, 5173]);
      rig.manager.watchPorts(false);
      final calls = probe.calls;
      async.elapse(const Duration(seconds: 30));
      expect(probe.calls, calls);
    });
  });

  test('sessionInfos is unchanged (A1); sessionInfosWithContext adds cwd '
      'and branch', () async {
    final lookup = _Lookup();
    final rig = SessionRig(gitHeads: lookup);
    await rig.manager.open(cols: 80, rows: 24);
    rig.pty(0).emit(_osc7('/w'));
    lookup.answers.last.complete('main');
    await pumpEventQueue();
    expect(rig.manager.sessionInfos.single.toMap().containsKey('cwd'), isFalse);
    final rich = rig.manager.sessionInfosWithContext.single;
    expect((rich.cwd, rich.branch), ('/w', 'main'));
  });
}
```

(`Uri.directory(temp.path).path` percent-encodes the temp path the way a hook would.)

Append to `packages/shellx_agent/test/session/session_router_test.dart` inside `main()`:

```dart
  test('session.list {desktop: true} carries cwd; desktop: false is the A1 '
      'list exactly (A2 C4)', () async {
    final rig = _Rig();
    await rig.shells.open(cols: 80, rows: 24);
    rig.ptys.ptys[0].emit('\x1b]7;file:///Users/test/w\x07');
    await pumpEventQueue();
    await rig.router.handle(phone, const SessionList());
    final old = rig.to(phone).whereType<SessionListResult>().last;
    expect(old.sessions.single.toMap().keys, [
      'id',
      'index',
      'shell',
      'created_at',
      'attached',
    ]);
    await rig.router.handle(tablet, const SessionList(desktop: true));
    final rich = rig.to(tablet).whereType<SessionListResult>().last;
    expect(rich.sessions.first.toMap()['cwd'], '/Users/test/w');
    expect(rich.sessions.first.toMap().containsKey('branch'), isFalse);
  });
```

Append to `packages/shellx_core/test/protocol/messages_test.dart` inside `main()`:

```dart
  test('SessionInfo cwd/branch are optional keys: absent when empty, '
      'round-trip when set (A2 C4)', () {
    const plain = SessionInfo(
      id: 1,
      index: 1,
      shell: 'zsh',
      createdAt: 5,
      attached: false,
    );
    expect(plain.toMap().keys, [
      'id',
      'index',
      'shell',
      'created_at',
      'attached',
    ]);
    const rich = SessionListResult([
      SessionInfo(
        id: 1,
        index: 1,
        shell: 'zsh',
        createdAt: 5,
        attached: false,
        cwd: '/Users/r/Tài liệu',
        branch: 'feat/a2',
      ),
    ]);
    final decoded = decodeBatch(encodeBatch([rich])).single;
    expect(decoded, rich);
    final info = (decoded as SessionListResult).sessions.single;
    expect((info.cwd, info.branch), ('/Users/r/Tài liệu', 'feat/a2'));
  });
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `cd packages/shellx_agent && ~/fvm/versions/3.41.4/bin/dart test test/session/session_context_test.dart`
Expected: FAIL — compile errors: `gitHeads`/`portProbe` are not parameters of `SessionManager`, `cwd` is not a getter of `SessionSummary`.

- [ ] **Step 4: `SessionInfo.cwd/branch` (shellx_core)**

In `packages/shellx_core/lib/src/protocol/messages.dart`, `SessionInfo`:

```dart
  const SessionInfo({
    required this.id,
    required this.index,
    required this.shell,
    required this.createdAt,
    required this.attached,
    this.kind = SessionKind.shellx,
    this.app = '',
    this.title = '',
    this.cwd = '',
    this.branch = '',
  });
```

add after `title`:

```dart
  /// The session's working directory (A2 C4), empty when unknown. Sent
  /// only to phones that listed with `desktop: true`; an optional key, so
  /// every released decoder (which skips unknown keys) reads the list as
  /// before.
  final String cwd;

  /// The git branch of [cwd] (A2 C4), empty when unknown.
  final String branch;
```

in `toMap()` after `'attached': attached,`:

```dart
    if (cwd.isNotEmpty) 'cwd': cwd,
    if (branch.isNotEmpty) 'branch': branch,
```

and in `_fromMap` after `title: …`:

```dart
      cwd: f.optionalString('cwd') ?? '',
      branch: f.optionalString('branch') ?? '',
```

Run: `cd packages/shellx_core && ~/fvm/versions/3.41.4/bin/dart test test/protocol`
Expected: PASS.

- [ ] **Step 5: `LocalSessions.watchPorts`**

In `packages/shellx_agent/lib/src/session/local_sessions.dart`, add to `LocalSessions` after `close`:

```dart
  /// The terminal window is shown (true) or hidden (A2 D8). Listening
  /// ports are looked up only while it is shown and a session exists;
  /// shown again → looked up at once.
  void watchPorts(bool visible);
```

- [ ] **Step 6: `SessionSummary` and the session's context fields**

In `session_manager.dart`, add imports:

```dart
import '../context/cwd_url.dart';
import '../context/git_head.dart';
import '../context/listening_ports.dart';
```

Extend `SessionSummary`'s constructor with `this.cwd, this.gitBranch, this.ports = const [],` and add fields:

```dart
  /// The shell's directory from its hook's OSC 7 (A2 C1); null without a
  /// hook, or after an OSC 7 from another host (D2).
  final String? cwd;

  /// The git branch of [cwd] (C2); null when not a repository or unknown.
  final String? gitBranch;

  /// Listening TCP ports of the session's process tree, ascending (C3).
  final List<int> ports;
```

In `_Session`, after `String title = '';` add:

```dart
  String? cwd;
  String? gitBranch;
  List<int> ports = const [];

  /// Bumped by every branch lookup: a late answer to an older one is
  /// dropped (the directory changed meanwhile).
  int branchGeneration = 0;
```

- [ ] **Step 7: Constructor, port watcher, listings**

Add the constructor parameters after `ShellIntegration? shellIntegration,`:

```dart
    GitBranchLookup? gitHeads,
    PortProbe? portProbe,
    bool windowsPaths = false,
    String localHostName = '',
    void Function(String message)? log,
```

and to the initializer list `_gitHeads = gitHeads, _windowsPaths = windowsPaths, _localHostName = localHostName,`; replace the constructor's terminating `;` (after `_nextId = …`) with a body:

```dart
  {
    if (portProbe != null) {
      _portWatcher = PortWatcher(
        probe: portProbe,
        shells: _shellPids,
        onPorts: _applyPorts,
        now: _clock,
        log: log,
      );
    }
  }
```

Fields:

```dart
  /// Branch lookups (A2 C2); null: no branches.
  final GitBranchLookup? _gitHeads;

  /// OSC 7 paths are Windows paths (`C:\…`, UNC).
  final bool _windowsPaths;

  /// `Platform.localHostname`: which OSC 7 hosts are this computer (D2).
  final String _localHostName;

  /// Listening ports (A2 C3); null: no ports.
  PortWatcher? _portWatcher;
```

In the `sessions` getter's `SessionSummary(...)` add `cwd: s.cwd, gitBranch: s.gitBranch, ports: s.ports,`. Replace the `sessionInfos` getter with:

```dart
  /// Listable sessions, as `session.list.result` entries (A1: no context).
  List<SessionInfo> get sessionInfos => _infos(context: false);

  /// The same with `cwd` and `branch`, for phones that listed with
  /// `desktop: true` (A2 C4).
  List<SessionInfo> get sessionInfosWithContext => _infos(context: true);

  List<SessionInfo> _infos({required bool context}) => [
    for (final s in _sessions.values)
      if (!s.closing)
        SessionInfo(
          id: s.id,
          index: s.index,
          shell: s.shell,
          createdAt: s.createdAt.millisecondsSinceEpoch,
          attached: s.attachedMobileId != null,
          cwd: context ? s.cwd ?? '' : '',
          branch: context ? s.gitBranch ?? '' : '',
        ),
  ];
```

Add after `close(int id)`:

```dart
  @override
  void watchPorts(bool visible) => _portWatcher?.setVisible(visible);

  /// Session id → shell pid, for [PortWatcher] (D3: ptys without a pid
  /// have no ports).
  Map<int, int> _shellPids() {
    final pids = <int, int>{};
    for (final s in _sessions.values) {
      if (s.closing) continue;
      final pty = s.pty;
      final pid = pty is PtyProcessId ? (pty as PtyProcessId).processId : null;
      if (pid != null) pids[s.id] = pid;
    }
    return pids;
  }

  void _applyPorts(Map<int, List<int>> ports) {
    var changed = false;
    for (final s in _sessions.values) {
      final next = ports[s.id] ?? const <int>[];
      if (_sameInts(next, s.ports)) continue;
      s.ports = List.unmodifiable(next);
      changed = true;
    }
    if (changed) _changes.add(null);
  }

  static bool _sameInts(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
```

In `_spawn`, after `_watch(session);` add `_portWatcher?.sessionsChanged();`. In `_finish`, after `_sessions.remove(session.id);` add `_portWatcher?.sessionsChanged();`.

- [ ] **Step 8: Track OSC 7 and 133;D in `_track`**

Replace the loop in `_track`

```dart
      for (final event in session.commandEvents.feed(data)) {
        session.commands.handle(event);
      }
```

with

```dart
      for (final event in session.commandEvents.feed(data)) {
        session.commands.handle(event);
        switch (event) {
          case CwdReported(:final url):
            if (_setCwd(session, url)) changed = true;
          case CommandFinished():
            _lookUpBranch(session, refresh: true); // git switch, git init…
          default:
            break;
        }
      }
```

and add after `_track`:

```dart
  /// A2 C1/D2. True when the summary changed.
  bool _setCwd(_Session session, String url) {
    final reported = parseCwdUrl(
      url,
      windows: _windowsPaths,
      localHostName: _localHostName,
    );
    switch (reported) {
      case null:
        return false; // malformed: keep what we had
      case RemoteCwd():
        if (session.cwd == null && session.gitBranch == null) return false;
        session.cwd = null;
        session.gitBranch = null;
        session.branchGeneration++;
        return true;
      case LocalCwd(:final path):
        if (path == session.cwd) return false;
        session.cwd = path;
        // The old branch stays until the lookup answers (no flicker).
        _lookUpBranch(session, refresh: false);
        return true;
    }
  }

  void _lookUpBranch(_Session session, {required bool refresh}) {
    final git = _gitHeads;
    final cwd = session.cwd;
    if (git == null || cwd == null) return;
    final generation = ++session.branchGeneration;
    if (cwd.startsWith(r'\\')) {
      _setBranch(session, null, generation); // UNC: never looked up (§5)
      return;
    }
    unawaited(
      git
          .branchFor(cwd, refresh: refresh)
          .then((branch) => _setBranch(session, branch, generation)),
    );
  }

  void _setBranch(_Session session, String? branch, int generation) {
    if (generation != session.branchGeneration ||
        session.closing ||
        !identical(_sessions[session.id], session) ||
        branch == session.gitBranch) {
      return;
    }
    session.gitBranch = branch;
    _changes.add(null);
  }
```

- [ ] **Step 9: The router lists with context for opted-in phones**

In `session_router.dart`, `case SessionList(:final desktop):`, replace `..._shells.sessionInfos,` with:

```dart
            ...(desktop
                ? _shells.sessionInfosWithContext
                : _shells.sessionInfos),
```

- [ ] **Step 10: Run every agent and core test**

Run: `cd packages/shellx_agent && ~/fvm/versions/3.41.4/bin/dart test && cd ../shellx_core && ~/fvm/versions/3.41.4/bin/dart test`
Expected: PASS (A1's 386 agent tests plus the new ones; the desktop fakes are updated in Task 6, so do not run desktop tests yet).

- [ ] **Step 11: Format, analyze, commit**

```bash
cd packages/shellx_agent
~/fvm/versions/3.41.4/bin/dart format --set-exit-if-changed lib/src/session test/support test/session/session_context_test.dart test/session/session_router_test.dart
~/fvm/versions/3.41.4/bin/dart analyze
cd ../shellx_core
~/fvm/versions/3.41.4/bin/dart format --set-exit-if-changed lib/src/protocol/messages.dart test/protocol/messages_test.dart
~/fvm/versions/3.41.4/bin/dart analyze
cd ../..
git add packages/shellx_agent/lib/src/session/session_manager.dart packages/shellx_agent/lib/src/session/local_sessions.dart packages/shellx_agent/lib/src/session/session_router.dart packages/shellx_agent/test/support/fake_pty.dart packages/shellx_agent/test/support/session_rig.dart packages/shellx_agent/test/session/session_context_test.dart packages/shellx_agent/test/session/session_router_test.dart packages/shellx_core/lib/src/protocol/messages.dart packages/shellx_core/test/protocol/messages_test.dart
git commit -m "feat(agent): sessions carry cwd, git branch and listening ports; opted-in phones get cwd/branch (A2 C4)"
```

> The desktop does not compile between this commit and Task 6 (`FakeLocalSessions` lacks `watchPorts`). Task 6 fixes it first thing; do not push in between.

---

### Task 6: Desktop — wiring, PID, `openLocalPort`, tab context and names, A2 strings

Wires the agent's context into the app: the real git reader and port probe, the pty's PID, `watchPorts` following the window, `UrlOpener.openLocalPort` (D9), `TerminalTab` context fields and `customTitle` (C6), two new notices, and every A2 string (so Tasks 7–9 only use keys).

**Files:**
- Modify: `apps/desktop/test/support/fake_local_sessions.dart` (`watchPorts`, context in `summary`) — first, so the desktop compiles again
- Modify: `apps/desktop/test/support/fakes.dart` (`RecordingUrlOpener.openLocalPort`)
- Modify: `apps/desktop/lib/src/platform/pty/flutter_pty_factory.dart` (`FlutterPtyAdapter implements Pty, PtyProcessId`)
- Modify: `apps/desktop/lib/src/agent/session_core.dart`, `apps/desktop/lib/main.dart`
- Create: `apps/desktop/lib/src/terminal/port_watch.dart`
- Modify: `apps/desktop/lib/src/platform/url_opener.dart`
- Modify: `apps/desktop/lib/src/terminal/terminal_tabs.dart`, `apps/desktop/lib/src/terminal/local_sessions_provider.dart`
- Modify: `apps/desktop/lib/src/ui/terminal/terminal_overlays.dart` (`NoticeToast`)
- Modify: `apps/desktop/lib/src/ui/terminal/shortcut_labels.dart`
- Modify: `apps/desktop/lib/l10n/app_en.arb`, `app_vi.arb` (+ generated `app_localizations*.dart`)
- Create: `apps/desktop/test/terminal/port_watch_test.dart`, `apps/desktop/test/platform/url_opener_local_port_test.dart`
- Modify: `apps/desktop/test/terminal/terminal_tabs_test.dart`, `apps/desktop/test/ui/terminal_workspace_test.dart` (append tests)

**Interfaces:**
- Consumes: `LocalSessions.watchPorts`, `SessionSummary.cwd/gitBranch/ports`, `GitHeadReader`, `MacPortProbe`, `WindowsPortProbe`, `PtyProcessId`, `GitBranchLookup`, `PortProbe` (Tasks 3–5).
- Produces:
  - `UrlOpener.openLocalPort(int port)` → opens `http://localhost:<port>/`; throws `ArgumentError` outside 1–65535.
  - `void listenForPortWatch({required ProviderContainer container, required LocalSessions sessions})`
  - `final homeDirectoryProvider = Provider<String>(…)`
  - `TerminalTab`: `String? cwd`, `String? gitBranch`, `List<int> ports`, `String? customTitle`, `String get automaticLabel`, `String get label` (= `customTitle ?? automaticLabel`), `bool get hasContext`.
  - `const int kTabNameMaxLength = 64;`, `void TerminalTabs.rename(int id, String? name)`, `void TerminalTabs.showNotice(TabNotice notice)`
  - `final class WorkspaceDeletedNotice extends TabNotice { const WorkspaceDeletedNotice({required this.name, required this.movedTo}); }`, `final class PortOpenFailedNotice extends TabNotice { const PortOpenFailedNotice(); }`
  - `String renameShortcutLabel()` (`F2`), `String moveUpShortcutLabel()` (`⌥↑` / `Alt+↑`), `String moveDownShortcutLabel()` (`⌥↓` / `Alt+↓`), `String newWorkspaceShortcutLabel()` (`⌘⇧N` / `Ctrl+Shift+N`)
  - `FakeLocalSessions.watched` (`List<bool>`), `FakeLocalSessions.summary(…, String? cwd, String? gitBranch, List<int> ports = const [])`, `RecordingUrlOpener.ports` (`List<int>`)
  - ARB keys of UI-A2 §7 (listed in Step 9).

- [ ] **Step 1: Make the fakes compile against the new interfaces**

In `apps/desktop/test/support/fake_local_sessions.dart`, add to `FakeLocalSessions`:

```dart
  /// Every `watchPorts` call, in order (A2 D8).
  final watched = <bool>[];

  @override
  void watchPorts(bool visible) => watched.add(visible);
```

and extend `summary(...)` with `String? cwd, String? gitBranch, List<int> ports = const [],` passed as `cwd: cwd, gitBranch: gitBranch, ports: ports,` to `SessionSummary`.

In `apps/desktop/test/support/fakes.dart`, `RecordingUrlOpener`, add:

```dart
  final List<int> ports = [];

  @override
  Future<void> openLocalPort(int port) async {
    if (fail) throw const ProcessException('/usr/bin/open', [], 'failed');
    ports.add(port);
  }
```

- [ ] **Step 2: Write the failing tests**

Create `apps/desktop/test/terminal/port_watch_test.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/terminal/port_watch.dart';
import 'package:shellx_desktop/src/ui/window_router.dart';

import '../support/fake_local_sessions.dart';

void main() {
  test('watchPorts follows whether the window is shown (A2 D8)', () {
    final local = FakeLocalSessions();
    final container = ProviderContainer.test();
    listenForPortWatch(container: container, sessions: local);
    expect(local.watched, [false]);
    container.read(windowRouterProvider.notifier).showTerminal();
    container.read(windowRouterProvider.notifier).showTerminal();
    expect(local.watched, [false, true]);
    container.read(windowRouterProvider.notifier).hideWindow();
    expect(local.watched, [false, true, false]);
  });
}
```

Create `apps/desktop/test/platform/url_opener_local_port_test.dart`:

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/platform/url_opener.dart';

void main() {
  for (final windows in [false, true]) {
    test('openLocalPort opens http://localhost:PORT/ only '
        '(${windows ? 'Windows' : 'macOS'}, A2 D9)', () async {
      final runs = <String>[];
      final opener = SystemUrlOpener(
        isWindows: windows,
        run: (exe, args) async {
          runs.add('$exe ${args.join(' ')}');
          return ProcessResult(0, 0, '', '');
        },
      );
      await opener.openLocalPort(5173);
      expect(runs.single, endsWith('http://localhost:5173/'));
      for (final bad in [0, -1, 65536]) {
        expect(() => opener.openLocalPort(bad), throwsArgumentError);
      }
      // open() still refuses plain http.
      expect(
        () => opener.open(Uri.parse('http://localhost:5173/')),
        throwsArgumentError,
      );
      expect(runs, hasLength(1));
    });
  }
}
```

Append to `apps/desktop/test/terminal/terminal_tabs_test.dart` inside `main()`:

```dart
  test('cwd, branch and ports follow the summary and stay after an exit '
      '(A2 C7)', () async {
    local.add(local.summary(1, cwd: '/w', gitBranch: 'main', ports: [3000]));
    boot();
    var tab = state().tabs.single;
    expect((tab.cwd, tab.gitBranch, tab.hasContext), ('/w', 'main', true));
    expect(tab.ports, [3000]);
    local.replace(local.summary(1, cwd: '/w/api'));
    tab = state().tabs.single;
    expect((tab.cwd, tab.gitBranch), ('/w/api', null));
    expect(tab.ports, isEmpty);
    local.views[1]!.end(2);
    await pumpEventQueue();
    expect(state().tabs.single.cwd, '/w/api');
  });

  test('rename: a name wins over the OSC title; blank restores it; at most '
      '64 characters (C6, D19)', () {
    local.add(local.summary(1, title: 'vim'));
    boot();
    tabs().rename(1, '  api server  ');
    expect(state().tabs.single.label, 'api server');
    local.replace(local.summary(1, title: 'htop'));
    expect(state().tabs.single.label, 'api server');
    expect(state().tabs.single.automaticLabel, 'htop');
    tabs().rename(1, '   ');
    expect(state().tabs.single.label, 'htop');
    tabs().rename(1, 'x' * 100);
    expect(state().tabs.single.label, 'x' * kTabNameMaxLength);
    tabs().rename(999, 'nobody'); // unknown id: nothing happens
  });

  test('showNotice replaces the current notice', () {
    boot();
    tabs().showNotice(const PortOpenFailedNotice());
    expect(state().notice, isA<PortOpenFailedNotice>());
    tabs().showNotice(
      const WorkspaceDeletedNotice(name: 'Ops', movedTo: 'Default'),
    );
    expect(state().notice, isA<WorkspaceDeletedNotice>());
  });
```

Append to `apps/desktop/test/ui/terminal_workspace_test.dart` inside `main()`:

```dart
  testWorkspace('a deleted-workspace notice is a neutral toast; a port '
      'failure an error toast (UI-A2 §7)', (tester) async {
    await pumpWorkspace(tester);
    container
        .read(terminalTabsProvider.notifier)
        .showNotice(const WorkspaceDeletedNotice(name: 'Ops', movedTo: 'Default'));
    await tester.pump();
    expect(
      find.text('Deleted workspace “Ops”. Its tabs moved to Default.'),
      findsOneWidget,
    );
    final box = tester.widget<Container>(find.byKey(const Key('pane.toast')));
    expect(
      (box.decoration! as BoxDecoration).color,
      ShellxDesktopColors.rowSelected,
    );
    container
        .read(terminalTabsProvider.notifier)
        .showNotice(const PortOpenFailedNotice());
    await tester.pump();
    expect(find.text("Couldn't open the browser."), findsOneWidget);
  });
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/terminal/port_watch_test.dart test/platform/url_opener_local_port_test.dart test/terminal/terminal_tabs_test.dart`
Expected: FAIL — `port_watch.dart` missing; `openLocalPort` not a member of `SystemUrlOpener`; `rename`, `cwd` undefined.

- [ ] **Step 4: PID from the flutter_pty adapter**

In `apps/desktop/lib/src/platform/pty/flutter_pty_factory.dart`, change `final class FlutterPtyAdapter implements Pty {` to `final class FlutterPtyAdapter implements Pty, PtyProcessId {` and below the existing `int get pid => _native.pid;` add:

```dart
  /// A2 D3: the shell's pid, for the ports its process tree listens on.
  @override
  int? get processId => _native.pid;
```

- [ ] **Step 5: `SessionCore` and `main.dart` pass the real reader and probe**

In `apps/desktop/lib/src/agent/session_core.dart`, add `import 'dart:io';`, factory parameters `GitBranchLookup? gitHeads, PortProbe? portProbe,` and pass them to `SessionManager(...)` with:

```dart
      gitHeads: gitHeads,
      portProbe: portProbe,
      windowsPaths: Platform.isWindows,
      localHostName: Platform.localHostname,
      log: (message) => debugPrint('ShellX ports: $message'),
```

(add `import 'package:flutter/foundation.dart' show debugPrint;`). Tests that build `SessionCore` without these keep no branches and no ports.

Create `apps/desktop/lib/src/terminal/port_watch.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shellx_agent/shellx_agent.dart';

import '../ui/window_router.dart';

/// A2 D8: listening ports are looked up only while the window is shown
/// (a dialog over it counts). Called once from `main.dart`.
void listenForPortWatch({
  required ProviderContainer container,
  required LocalSessions sessions,
}) {
  container.listen<bool>(
    windowRouterProvider.select((s) => s.visible),
    (_, shown) => sessions.watchPorts(shown),
    fireImmediately: true,
  );
}
```

In `apps/desktop/lib/main.dart`: in `SessionCore(...)` add

```dart
    gitHeads: GitHeadReader(),
    portProbe: Platform.isWindows ? WindowsPortProbe() : MacPortProbe(),
```

add `homeDirectoryProvider.overrideWithValue(home),` to the container's `overrides` list (next to `desktopServicesProvider.overrideWithValue(services)`), and right after the `listenForWindowTitle(...)` call:

```dart
  listenForPortWatch(container: container, sessions: core.sessions);
```

(import `src/terminal/port_watch.dart` and `src/terminal/local_sessions_provider.dart`).

- [ ] **Step 6: `openLocalPort`**

In `apps/desktop/lib/src/platform/url_opener.dart`, add to `UrlOpener`:

```dart
  /// A2 D9: `http://localhost:<port>/` in the default browser — the only
  /// non-https URL that ever opens. Throws [ArgumentError] for a port
  /// outside 1–65535.
  Future<void> openLocalPort(int port);
```

and to `SystemUrlOpener`:

```dart
  @override
  Future<void> openLocalPort(int port) async {
    if (port < 1 || port > 65535) {
      throw ArgumentError.value(port, 'port', 'Not a TCP port');
    }
    // Built from the number alone: nothing user-typed reaches the command.
    final url = 'http://localhost:$port/';
    if (_isWindows) {
      await _run('rundll32', ['url.dll,FileProtocolHandler', url]);
    } else {
      await _run('/usr/bin/open', [url]);
    }
  }
```

Extend the class doc comment's second paragraph: "…plus `http://localhost:<port>/` through [openLocalPort]".

- [ ] **Step 7: `TerminalTab` context and names**

In `apps/desktop/lib/src/terminal/local_sessions_provider.dart` add (with `import 'dart:io';`):

```dart
/// The user's home, for showing `~` (UI-A2 §2.3). `main.dart` overrides
/// it with the home the shells start in.
final homeDirectoryProvider = Provider<String>(
  (ref) =>
      Platform.environment[Platform.isWindows ? 'USERPROFILE' : 'HOME'] ?? '',
);
```

In `apps/desktop/lib/src/terminal/terminal_tabs.dart`:

Add after the `SpawnFailedNotice` class:

```dart
/// A workspace was deleted; its tabs moved to [movedTo] (spec D16).
/// Neutral toast.
final class WorkspaceDeletedNotice extends TabNotice {
  const WorkspaceDeletedNotice({required this.name, required this.movedTo});
  final String name;
  final String movedTo;
}

/// The browser could not be started for a port link (UI-A2 §2.4).
final class PortOpenFailedNotice extends TabNotice {
  const PortOpenFailedNotice();
}

/// D19: the longest tab name, in characters.
const int kTabNameMaxLength = 64;

const Object _unset = Object();
```

Replace `TerminalTab` with:

```dart
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
    this.cwd,
    this.gitBranch,
    this.ports = const [],
    this.customTitle,
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

  /// A2 C1–C3, from the session; the last values stay after an exit.
  final String? cwd;
  final String? gitBranch;
  final List<int> ports;

  /// C6: the user's name for this tab (desktop only); wins over [title].
  final String? customTitle;

  /// Non-null once the shell exited with a non-zero code (D14).
  final int? exitCode;

  bool get exited => exitCode != null;

  /// OSC 0/2 title, else `<shell> <index>` (D13, UI §5 terminalDefaultTitle).
  String get automaticLabel => title.isNotEmpty ? title : '$shell $index';

  /// What the sidebar, the window title and dialogs show.
  String get label => customTitle ?? automaticLabel;

  /// The row has a context line (UI-A2 §2.1).
  bool get hasContext => cwd != null || gitBranch != null || ports.isNotEmpty;

  TerminalTab copyWith({
    String? title,
    bool? phoneAttached,
    bool? runningCommand,
    DriverSide? driver,
    int? exitCode,
    Object? cwd = _unset,
    Object? gitBranch = _unset,
    List<int>? ports,
    Object? customTitle = _unset,
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
    cwd: identical(cwd, _unset) ? this.cwd : cwd as String?,
    gitBranch: identical(gitBranch, _unset)
        ? this.gitBranch
        : gitBranch as String?,
    ports: ports ?? this.ports,
    customTitle: identical(customTitle, _unset)
        ? this.customTitle
        : customTitle as String?,
    exitCode: exitCode ?? this.exitCode,
  );
}
```

In `_merge`, the `tab.copyWith(...)` for a known session gains `cwd: s.cwd, gitBranch: s.gitBranch, ports: s.ports,`. In `_attach`, the returned `TerminalTab(...)` gains `cwd: s.cwd, gitBranch: s.gitBranch, ports: s.ports,`.

Add public methods after `dismissNotice()`:

```dart
  /// C6/D19: the user's name for tab [id]; trimmed, at most
  /// [kTabNameMaxLength] characters; blank restores the automatic title.
  void rename(int id, String? name) {
    final trimmed = name?.trim() ?? '';
    final value = trimmed.isEmpty
        ? null
        : String.fromCharCodes(trimmed.runes.take(kTabNameMaxLength));
    _update(id, (t) => t.copyWith(customTitle: value));
  }

  /// A notice from outside the tab list (workspaces, port links).
  void showNotice(TabNotice notice) => _set(notice: notice);
```

- [ ] **Step 8: The toast knows the new notices (neutral variant)**

In `apps/desktop/lib/src/ui/terminal/terminal_overlays.dart`, `_NoticeToastState`:

`_text` gains:

```dart
    WorkspaceDeletedNotice(:final name, :final movedTo) => l10n.workspaceDeleted(
      name,
      movedTo,
    ),
    PortOpenFailedNotice() => l10n.portOpenFailed,
```

add

```dart
  /// UI-A1 §2.8: the neutral variant (reserved in A1) for information.
  bool get _neutral => widget.notice is WorkspaceDeletedNotice;
```

in `_start()` use `_neutral ? ShellxMotion.toastVisible : ShellxMotion.toastVisibleError`; in `build`, the decoration becomes `color: _neutral ? ShellxDesktopColors.rowSelected : ShellxDesktopColors.noticeBg`, `border: Border.all(color: _neutral ? ShellxDesktopColors.border : ShellxDesktopColors.noticeBorder)`; the icon `_neutral ? Icons.info_outline : Icons.error_outline` (drop the `const` on that `ExcludeSemantics`); every `ShellxDesktopColors.noticeText` in the row becomes `_neutral ? ShellxDesktopColors.textPrimary : ShellxDesktopColors.noticeText` (text, icon, close button colours).

- [ ] **Step 9: Shortcut labels and A2 strings**

Append to `apps/desktop/lib/src/ui/terminal/shortcut_labels.dart`:

```dart
String renameShortcutLabel() => 'F2';
String moveUpShortcutLabel() => isMacDesktop ? '⌥↑' : 'Alt+↑';
String moveDownShortcutLabel() => isMacDesktop ? '⌥↓' : 'Alt+↓';
String newWorkspaceShortcutLabel() => isMacDesktop ? '⌘⇧N' : 'Ctrl+Shift+N';
```

In `apps/desktop/lib/l10n/app_en.arb`, put a comma after the last entry and add before the closing `}`:

```json
  "workspaceDefaultName": "Default",
  "workspaceNumberedName": "Workspace {n}",
  "@workspaceNumberedName": {"placeholders": {"n": {"type": "int"}}},
  "workspaceNew": "New workspace",
  "workspaceNewTab": "New tab in this workspace",
  "workspaceRename": "Rename workspace",
  "workspaceDelete": "Delete workspace",
  "workspaceCollapse": "Collapse",
  "workspaceExpand": "Expand",
  "workspaceEmptyHint": "Empty. Drag a tab here or press +.",
  "workspaceNameField": "Workspace name",
  "workspaceDeleted": "Deleted workspace “{name}”. Its tabs moved to {defaultName}.",
  "@workspaceDeleted": {"placeholders": {"name": {"type": "String"}, "defaultName": {"type": "String"}}},
  "workspaceHeaderSemantics": "Workspace {name}, {count, plural, =1{1 tab} other{{count} tabs}}",
  "@workspaceHeaderSemantics": {"placeholders": {"name": {"type": "String"}, "count": {"type": "int"}}},
  "workspaceContainsSelected": "contains the selected tab",
  "tabRename": "Rename tab",
  "tabNameField": "Tab name",
  "tabUseAutomaticName": "Use automatic name",
  "tabMoveTo": "Move to workspace…",
  "tabMoveUp": "Move up",
  "tabMoveDown": "Move down",
  "tabOpenPort": "Open port {port} in browser",
  "@tabOpenPort": {"placeholders": {"port": {"type": "int"}}},
  "portOpenTooltip": "Open http://localhost:{port}",
  "@portOpenTooltip": {"placeholders": {"port": {"type": "int"}}},
  "portsMoreTooltip": "Listening ports: {ports}",
  "@portsMoreTooltip": {"placeholders": {"ports": {"type": "String"}}},
  "portOpenFailed": "Couldn't open the browser.",
  "sidebarBranch": "branch {branch}",
  "@sidebarBranch": {"placeholders": {"branch": {"type": "String"}}},
  "sidebarFolder": "folder {path}",
  "@sidebarFolder": {"placeholders": {"path": {"type": "String"}}},
  "sidebarPorts": "{count, plural, =1{port {ports}} other{ports {ports}}}",
  "@sidebarPorts": {"placeholders": {"count": {"type": "int"}, "ports": {"type": "String"}}},
  "sidebarPositionInWorkspace": "tab {index} of {count} in {workspace}",
  "@sidebarPositionInWorkspace": {"placeholders": {"index": {"type": "int"}, "count": {"type": "int"}, "workspace": {"type": "String"}}}
```

In `apps/desktop/lib/l10n/app_vi.arb` likewise:

```json
  "workspaceDefaultName": "Mặc định",
  "workspaceNumberedName": "Workspace {n}",
  "workspaceNew": "Workspace mới",
  "workspaceNewTab": "Tab mới trong workspace này",
  "workspaceRename": "Đổi tên workspace",
  "workspaceDelete": "Xóa workspace",
  "workspaceCollapse": "Thu gọn",
  "workspaceExpand": "Mở rộng",
  "workspaceEmptyHint": "Trống. Kéo tab vào đây hoặc bấm +.",
  "workspaceNameField": "Tên workspace",
  "workspaceDeleted": "Đã xóa workspace “{name}”. Các tab đã chuyển về {defaultName}.",
  "workspaceHeaderSemantics": "Workspace {name}, {count} tab",
  "workspaceContainsSelected": "có tab đang chọn",
  "tabRename": "Đổi tên tab",
  "tabNameField": "Tên tab",
  "tabUseAutomaticName": "Dùng tên tự động",
  "tabMoveTo": "Chuyển tới workspace…",
  "tabMoveUp": "Chuyển lên",
  "tabMoveDown": "Chuyển xuống",
  "tabOpenPort": "Mở cổng {port} trong trình duyệt",
  "portOpenTooltip": "Mở http://localhost:{port}",
  "portsMoreTooltip": "Cổng đang nghe: {ports}",
  "portOpenFailed": "Không mở được trình duyệt.",
  "sidebarBranch": "nhánh {branch}",
  "sidebarFolder": "thư mục {path}",
  "sidebarPorts": "{count, plural, other{cổng {ports}}}",
  "sidebarPositionInWorkspace": "tab {index} trên {count} trong {workspace}"
```

Generate: `cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter gen-l10n`
Expected: no warnings about missing translations; `lib/l10n/app_localizations*.dart` updated.

- [ ] **Step 10: Run the desktop tests**

Run: `cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test`
Expected: PASS — A1's 627 tests (`test/l10n/l10n_test.dart` checks the two ARB files have the same keys) plus the new ones; the benchmark stays skipped.

- [ ] **Step 11: Format, analyze, commit**

```bash
cd apps/desktop
~/fvm/versions/3.41.4/bin/dart format --set-exit-if-changed lib test
PATH=~/fvm/versions/3.41.4/bin:$PATH flutter analyze
cd ../..
git add apps/desktop/test/support/fake_local_sessions.dart apps/desktop/test/support/fakes.dart apps/desktop/lib/src/platform/pty/flutter_pty_factory.dart apps/desktop/lib/src/agent/session_core.dart apps/desktop/lib/main.dart apps/desktop/lib/src/terminal/port_watch.dart apps/desktop/lib/src/platform/url_opener.dart apps/desktop/lib/src/terminal/terminal_tabs.dart apps/desktop/lib/src/terminal/local_sessions_provider.dart apps/desktop/lib/src/ui/terminal/terminal_overlays.dart apps/desktop/lib/src/ui/terminal/shortcut_labels.dart apps/desktop/lib/l10n/ apps/desktop/test/terminal/port_watch_test.dart apps/desktop/test/platform/url_opener_local_port_test.dart apps/desktop/test/terminal/terminal_tabs_test.dart apps/desktop/test/ui/terminal_workspace_test.dart
git commit -m "feat(desktop): wire cwd/branch/ports, watchPorts with the window, openLocalPort, tab names and A2 strings"
```

---

### Task 7: Desktop — `SidebarWorkspaces` (membership, visible order, persistence, ⌘⇧N)

The model behind workspaces (spec C5, D10–D18): the list (persisted), membership and order of tabs (memory), the current workspace, the open rename, and every operation the UI needs. The window's tab shortcuts and the A1 sidebar switch to the **visible order**; ⌘⇧N / Ctrl+Shift+N creates a workspace. Headers, rename fields and drag-and-drop come in Tasks 8–9.

**Files:**
- Modify: `apps/desktop/lib/src/platform/settings_store.dart` (`SettingKeys.terminalWorkspaces`)
- Create: `apps/desktop/lib/src/terminal/sidebar_workspaces.dart`
- Modify: `apps/desktop/lib/src/ui/terminal/terminal_shortcuts.dart` (`NewWorkspaceIntent`)
- Modify: `apps/desktop/lib/src/ui/terminal/terminal_workspace_page.dart` (actions, focus rule)
- Modify: `apps/desktop/lib/src/ui/terminal/session_sidebar.dart` (rows and arrow keys in visible order)
- Create: `apps/desktop/test/terminal/sidebar_workspaces_test.dart`
- Modify: `apps/desktop/test/ui/terminal_shortcuts_test.dart`, `apps/desktop/test/ui/terminal_workspace_test.dart` (append tests)

**Interfaces:**
- Consumes: `terminalTabsProvider`, `TerminalTabs.select/openTab/showNotice`, `WorkspaceDeletedNotice`, `appL10nProvider`, `desktopServicesProvider` (A1, Task 6); ARB keys `workspaceDefaultName`, `workspaceNumberedName` (Task 6).
- Produces (Tasks 8–9 rely on these exact names):
  - `const String kDefaultWorkspaceId = 'default';`, `const int kWorkspaceNameMaxLength = 64;`
  - `final class Workspace { id, String? name, bool collapsed, bool get isDefault, String displayName(AppLocalizations l10n), String encode(), static Workspace? decode(String) }`
  - `List<Workspace> loadWorkspaces(List<String> stored)`
  - `sealed class RenameTarget`; `RenameTab(int id)`; `RenameWorkspace(String id)` (value equality)
  - `final class SidebarState { List<Workspace> workspaces; Map<String, List<int>> members; String currentId; RenameTarget? renaming; bool get showHeaders; Workspace get defaultWorkspace; Workspace? workspace(String id); List<int> tabsOf(String id); String? workspaceOf(int tabId); List<int> get orderedTabIds; List<int> get visibleTabIds; }`
  - `final settingsStoreProvider = Provider<SettingsStore>(…)`, `final sidebarWorkspacesProvider = NotifierProvider<SidebarWorkspaces, SidebarState>(…)`
  - `SidebarWorkspaces`: `Future<void> create({int? moveTab})`, `Future<void> openTabIn(String id)`, `void rename(String id, String name)`, `void toggleCollapsed(String id)`, `void setCollapsed(String id, bool collapsed)`, `void delete(String id)`, `void moveTab(int tabId, String workspaceId, [int? index])`, `bool canMoveUp(int tabId)`, `bool canMoveDown(int tabId)`, `void moveUp(int tabId)`, `void moveDown(int tabId)`, `void selectVisible(int position)`, `void step(int delta)`, `void startRename(RenameTarget target)`, `void endRename()`, `String displayName(String id)`
  - `class NewWorkspaceIntent extends Intent`

- [ ] **Step 1: Write the failing model tests**

Create `apps/desktop/test/terminal/sidebar_workspaces_test.dart`:

```dart
import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_desktop/l10n/app_localizations.dart';
import 'package:shellx_desktop/src/platform/settings_store.dart';
import 'package:shellx_desktop/src/terminal/local_sessions_provider.dart';
import 'package:shellx_desktop/src/terminal/sidebar_workspaces.dart';
import 'package:shellx_desktop/src/terminal/terminal_tabs.dart';

import '../support/fake_local_sessions.dart';

void main() {
  late FakeLocalSessions local;
  late InMemorySettingsStore settings;
  late ProviderContainer container;

  SidebarWorkspaces sidebar() =>
      container.read(sidebarWorkspacesProvider.notifier);
  SidebarState state() => container.read(sidebarWorkspacesProvider);
  TerminalTabs tabs() => container.read(terminalTabsProvider.notifier);
  int? selected() => container.read(terminalTabsProvider).selectedId;
  List<String>? saved() => settings.strings[SettingKeys.terminalWorkspaces];

  void boot() {
    container = ProviderContainer.test(
      overrides: [
        localSessionsProvider.overrideWithValue(local),
        appL10nProvider.overrideWithValue(
          lookupAppLocalizations(const Locale('en')),
        ),
        settingsStoreProvider.overrideWithValue(settings),
      ],
    );
    state(); // build
  }

  void addDesktop(int id) =>
      local.add(local.summary(id, origin: SessionOrigin.desktop));

  setUp(() {
    local = FakeLocalSessions();
    settings = InMemorySettingsStore();
  });

  group('loadWorkspaces (Review Focus 5)', () {
    test('drops broken, duplicate and nameless entries; Default first when '
        'missing', () {
      final list = loadWorkspaces([
        'not json',
        '{"id": 5}',
        '[1, 2]',
        '{"id":"w1","name":"  Backend  ","collapsed":true}',
        '{"id":"w1","name":"dupe"}',
        '{"id":"w2"}',
        '{"id":"w3","name":"   "}',
        '{"id":"w4","name":"Ops","collapsed":"yes"}',
      ]);
      expect(list.map((w) => w.id), [kDefaultWorkspaceId, 'w1']);
      expect((list[1].name, list[1].collapsed), ('Backend', true));
      expect(loadWorkspaces(const []).single.isDefault, isTrue);
    });

    test('a stored Default keeps its place, name and collapsed state', () {
      final list = loadWorkspaces([
        '{"id":"w1","name":"A"}',
        '{"id":"default","name":"Home","collapsed":true}',
      ]);
      expect(list.map((w) => w.id), ['w1', kDefaultWorkspaceId]);
      expect((list[1].name, list[1].collapsed), ('Home', true));
    });

    test('encode/decode round trip; names are clipped to 64', () {
      final w = Workspace(id: 'w9', name: 'x' * 80, collapsed: true);
      final back = Workspace.decode(w.encode())!;
      expect((back.id, back.name!.length, back.collapsed), ('w9', 64, true));
    });
  });

  test('desktop tabs join the current workspace, phone tabs Default; a '
      'closed tab leaves and its open rename is dropped (Review Focus 4)', () async {
    boot();
    await sidebar().create(); // "Workspace 2" with tab 100
    final ws = state().workspaces.last.id;
    expect(state().workspace(ws)!.name, 'Workspace 2');
    expect(state().renaming, RenameWorkspace(ws));
    expect(state().tabsOf(ws), [100]);
    await tabs().openTab(); // current = ws (tab 100 selected)
    expect(state().tabsOf(ws), [100, 101]);
    local.add(local.summary(7, origin: SessionOrigin.phone));
    expect(state().tabsOf(kDefaultWorkspaceId), [7]);
    expect(selected(), 101); // a phone tab is not selected
    sidebar().startRename(const RenameTab(101));
    local.close(101);
    await pumpEventQueue();
    expect(state().tabsOf(ws), [100]);
    expect(state().renaming, isNull);
  });

  test('openTabIn puts the next tab there and expands it, whatever is '
      'selected', () async {
    addDesktop(1);
    boot();
    await sidebar().create(); // ws with tab 100, selected
    final ws = state().workspaces.last.id;
    sidebar().setCollapsed(kDefaultWorkspaceId, true);
    await sidebar().openTabIn(kDefaultWorkspaceId);
    expect(state().tabsOf(kDefaultWorkspaceId), [1, 101]);
    expect(state().workspace(kDefaultWorkspaceId)!.collapsed, isFalse);
    expect(state().tabsOf(ws), [100]);
  });

  test('the visible order skips collapsed workspaces; ⌘N and Ctrl+Tab use '
      'it, also from a hidden selected tab (C5)', () async {
    addDesktop(1);
    addDesktop(2);
    boot();
    await sidebar().create(); // tab 100
    sidebar().endRename();
    expect(state().visibleTabIds, [1, 2, 100]);
    sidebar().selectVisible(1);
    expect(selected(), 1);
    sidebar().step(-1);
    expect(selected(), 100); // wraps
    sidebar().toggleCollapsed(kDefaultWorkspaceId);
    expect(state().visibleTabIds, [100]);
    sidebar().selectVisible(2);
    expect(selected(), 100); // no second visible tab: unchanged
    tabs().select(1); // hidden (a click before collapsing)
    sidebar().step(1);
    expect(selected(), 100);
  });

  test('with one workspace, collapsed is ignored (no headers, D10)', () {
    addDesktop(1);
    boot();
    sidebar().setCollapsed(kDefaultWorkspaceId, true);
    expect(state().showHeaders, isFalse);
    expect(state().visibleTabIds, [1]);
  });

  test('moveTab reorders and crosses workspaces; move up/down cross '
      'boundaries; a target expands (D18)', () async {
    addDesktop(1);
    addDesktop(2);
    addDesktop(3);
    boot();
    sidebar().moveTab(1, kDefaultWorkspaceId, 3);
    expect(state().tabsOf(kDefaultWorkspaceId), [2, 3, 1]);
    sidebar().moveUp(1);
    expect(state().tabsOf(kDefaultWorkspaceId), [2, 1, 3]);
    expect(sidebar().canMoveUp(2), isFalse);
    expect(sidebar().canMoveDown(3), isFalse); // one workspace: the end
    await sidebar().create(); // tab 100
    final ws = state().workspaces.last.id;
    expect(sidebar().canMoveDown(3), isTrue);
    sidebar().moveDown(3); // last of Default → first of ws
    expect(state().tabsOf(ws), [3, 100]);
    sidebar().moveUp(3);
    expect(state().tabsOf(kDefaultWorkspaceId), [2, 1, 3]);
    sidebar().setCollapsed(ws, true);
    sidebar().moveTab(2, ws);
    expect(state().tabsOf(ws), [100, 2]);
    expect(state().workspace(ws)!.collapsed, isFalse);
  });

  test('delete: tabs to the end of Default (expanded), a neutral notice; '
      'Default cannot be deleted; the list persists (D11, D16, D17)', () async {
    addDesktop(1);
    boot();
    await sidebar().create(); // tab 100
    final ws = state().workspaces.last.id;
    sidebar().rename(ws, '  Backend  ');
    sidebar().rename(ws, '   '); // blank keeps the name
    sidebar().setCollapsed(kDefaultWorkspaceId, true);
    final stored = loadWorkspaces(saved()!);
    expect(stored.map((w) => (w.name, w.collapsed)), [
      (null, true),
      ('Backend', false),
    ]);
    sidebar().delete(kDefaultWorkspaceId);
    expect(state().workspaces, hasLength(2));
    sidebar().delete(ws);
    expect(state().workspaces.single.isDefault, isTrue);
    expect(state().tabsOf(kDefaultWorkspaceId), [1, 100]);
    expect(state().workspaces.single.collapsed, isFalse);
    final notice =
        container.read(terminalTabsProvider).notice! as WorkspaceDeletedNotice;
    expect((notice.name, notice.movedTo), ('Backend', 'Default'));
    expect(saved(), hasLength(1));
  });

  test('numbered names take the smallest free number', () async {
    boot();
    await sidebar().create();
    await sidebar().create();
    final names = [for (final w in state().workspaces) w.name];
    expect(names, [null, 'Workspace 2', 'Workspace 3']);
    sidebar().rename(state().workspaces[1].id, 'API');
    await sidebar().create();
    expect(state().workspaces.last.name, 'Workspace 2');
  });

  test('a new container over the same settings gets the same workspaces', () async {
    boot();
    await sidebar().create();
    sidebar().rename(state().workspaces.last.id, 'Ops');
    container.dispose();
    boot();
    expect(state().workspaces.map((w) => w.name), [null, 'Ops']);
    expect(state().tabsOf(state().workspaces.last.id), isEmpty);
  });
}
```

- [ ] **Step 2: Run them to verify they fail**

Run: `cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/terminal/sidebar_workspaces_test.dart`
Expected: FAIL — `sidebar_workspaces.dart` does not exist.

- [ ] **Step 3: The settings key**

In `apps/desktop/lib/src/platform/settings_store.dart`, `SettingKeys`:

```dart
  /// A2 D17: the sidebar's workspaces, in order — one JSON object
  /// `{"id","name","collapsed"}` per entry. Membership is not stored.
  static const String terminalWorkspaces = 'terminal_workspaces';
```

and add `terminalWorkspaces,` to `all`.

- [ ] **Step 4: Write `sidebar_workspaces.dart`**

Create `apps/desktop/lib/src/terminal/sidebar_workspaces.dart`:

```dart
import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shellx_agent/shellx_agent.dart';

import '../../l10n/app_localizations.dart';
import '../agent/desktop_services.dart';
import '../platform/settings_store.dart';
import 'local_sessions_provider.dart';
import 'terminal_tabs.dart';

const String kDefaultWorkspaceId = 'default';
const int kWorkspaceNameMaxLength = 64;

String _clip(String text) =>
    String.fromCharCodes(text.runes.take(kWorkspaceNameMaxLength));

/// A named group of tabs in the sidebar (spec C5).
@immutable
final class Workspace {
  const Workspace({required this.id, this.name, this.collapsed = false});

  final String id;

  /// Null only for the Default workspace never renamed: it shows the
  /// localized "Mặc định"/"Default" (D11).
  final String? name;
  final bool collapsed;

  bool get isDefault => id == kDefaultWorkspaceId;

  String displayName(AppLocalizations l10n) =>
      name ?? l10n.workspaceDefaultName;

  Workspace copyWith({String? name, bool? collapsed}) => Workspace(
    id: id,
    name: name ?? this.name,
    collapsed: collapsed ?? this.collapsed,
  );

  String encode() => jsonEncode({
    'id': id,
    if (name != null) 'name': name,
    'collapsed': collapsed,
  });

  /// Null for anything that is not a well-formed entry (Review Focus 5).
  static Workspace? decode(String text) {
    final Object? value;
    try {
      value = jsonDecode(text);
    } on FormatException {
      return null;
    }
    if (value is! Map<String, Object?>) return null;
    final id = value['id'];
    final name = value['name'];
    final collapsed = value['collapsed'];
    if (id is! String || id.isEmpty || id.length > 64) return null;
    if (name != null && name is! String) return null;
    if (collapsed != null && collapsed is! bool) return null;
    final clean = (name as String?)?.trim() ?? '';
    if (clean.isEmpty && id != kDefaultWorkspaceId) return null;
    return Workspace(
      id: id,
      name: clean.isEmpty ? null : _clip(clean),
      collapsed: collapsed as bool? ?? false,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is Workspace &&
      other.id == id &&
      other.name == name &&
      other.collapsed == collapsed;

  @override
  int get hashCode => Object.hash(id, name, collapsed);
}

/// The stored list, without broken or duplicate entries, and always with
/// a Default (first when it was missing).
List<Workspace> loadWorkspaces(List<String> stored) {
  final result = <Workspace>[];
  final ids = <String>{};
  for (final text in stored) {
    final workspace = Workspace.decode(text);
    if (workspace == null || !ids.add(workspace.id)) continue;
    result.add(workspace);
  }
  if (!ids.contains(kDefaultWorkspaceId)) {
    result.insert(0, const Workspace(id: kDefaultWorkspaceId));
  }
  return result;
}

/// The item whose inline name field is open (UI-A2 §4).
sealed class RenameTarget {
  const RenameTarget();
}

final class RenameTab extends RenameTarget {
  const RenameTab(this.id);
  final int id;
  @override
  bool operator ==(Object other) => other is RenameTab && other.id == id;
  @override
  int get hashCode => id.hashCode;
}

final class RenameWorkspace extends RenameTarget {
  const RenameWorkspace(this.id);
  final String id;
  @override
  bool operator ==(Object other) => other is RenameWorkspace && other.id == id;
  @override
  int get hashCode => id.hashCode;
}

const Object _keep = Object();

@immutable
final class SidebarState {
  const SidebarState({
    required this.workspaces,
    required this.members,
    this.currentId = kDefaultWorkspaceId,
    this.renaming,
  });

  final List<Workspace> workspaces;

  /// Tab ids per workspace id, in sidebar order. Never mutated in place.
  final Map<String, List<int>> members;

  /// Where ⌘T opens a tab: the selected tab's workspace (UI-A2 §3.3).
  final String currentId;
  final RenameTarget? renaming;

  /// D10: headers only from two workspaces on.
  bool get showHeaders => workspaces.length > 1;

  Workspace get defaultWorkspace => workspaces.firstWhere((w) => w.isDefault);

  Workspace? workspace(String id) {
    for (final w in workspaces) {
      if (w.id == id) return w;
    }
    return null;
  }

  List<int> tabsOf(String id) => members[id] ?? const [];

  String? workspaceOf(int tabId) {
    for (final MapEntry(key: id, value: tabs) in members.entries) {
      if (tabs.contains(tabId)) return id;
    }
    return null;
  }

  List<int> get orderedTabIds => [
    for (final w in workspaces) ...tabsOf(w.id),
  ];

  /// What the sidebar shows, top to bottom; ⌘1–9, Ctrl+Tab and ↑/↓ follow
  /// it (C5). Collapsed only counts while headers show.
  List<int> get visibleTabIds => [
    for (final w in workspaces)
      if (!showHeaders || !w.collapsed) ...tabsOf(w.id),
  ];

  SidebarState copyWith({
    List<Workspace>? workspaces,
    Map<String, List<int>>? members,
    String? currentId,
    Object? renaming = _keep,
  }) => SidebarState(
    workspaces: workspaces ?? this.workspaces,
    members: members ?? this.members,
    currentId: currentId ?? this.currentId,
    renaming: identical(renaming, _keep)
        ? this.renaming
        : renaming as RenameTarget?,
  );
}

final settingsStoreProvider = Provider<SettingsStore>(
  (ref) => ref.watch(desktopServicesProvider).settings,
);

final sidebarWorkspacesProvider =
    NotifierProvider<SidebarWorkspaces, SidebarState>(SidebarWorkspaces.new);

/// Workspaces of the sidebar (spec C5, D10–D18). The list, names and
/// collapsed states are saved in the settings; which tab is where lives
/// only in memory (sessions end with the app until A5).
class SidebarWorkspaces extends Notifier<SidebarState> {
  final _random = Random();

  /// The next tab opened on this computer goes here (header `+`, ⌘⇧N),
  /// whatever is selected meanwhile; cleared once used.
  String? _pendingTarget;

  @override
  SidebarState build() {
    final stored = ref
        .watch(settingsStoreProvider)
        .getStrings(SettingKeys.terminalWorkspaces);
    ref.listen<TerminalTabsState>(
      terminalTabsProvider,
      (_, tabs) => state = _reconcile(state, tabs),
    );
    return _reconcile(
      SidebarState(workspaces: loadWorkspaces(stored), members: const {}),
      ref.read(terminalTabsProvider),
    );
  }

  AppLocalizations get _l10n => ref.read(appL10nProvider);
  TerminalTabs get _tabs => ref.read(terminalTabsProvider.notifier);

  String displayName(String id) =>
      state.workspace(id)?.displayName(_l10n) ?? '';

  /// D15: "Workspace N" at the end, current, its name field open; with a
  /// new tab in it, or with [moveTab] moved into it ("Move to workspace…
  /// → New workspace").
  Future<void> create({int? moveTab}) async {
    final id = _newId();
    state = state.copyWith(
      workspaces: [
        ...state.workspaces,
        Workspace(id: id, name: _numberedName()),
      ],
      members: {...state.members, id: const <int>[]},
      currentId: id,
      renaming: RenameWorkspace(id),
    );
    _save();
    if (moveTab != null) {
      this.moveTab(moveTab, id);
    } else {
      await openTabIn(id);
    }
  }

  /// Header `+` (UI-A2 §3.1): a new tab in [id], which expands.
  Future<void> openTabIn(String id) async {
    if (state.workspace(id) == null) return;
    _pendingTarget = id;
    setCollapsed(id, false);
    try {
      await _tabs.openTab();
    } finally {
      _pendingTarget = null;
    }
  }

  /// Blank keeps the old name (UI-A2 §4).
  void rename(String id, String name) {
    final clean = name.trim();
    if (clean.isEmpty || state.workspace(id) == null) return;
    state = state.copyWith(
      workspaces: [
        for (final w in state.workspaces)
          w.id == id
              ? Workspace(id: w.id, name: _clip(clean), collapsed: w.collapsed)
              : w,
      ],
    );
    _save();
  }

  void toggleCollapsed(String id) {
    final w = state.workspace(id);
    if (w != null) setCollapsed(id, !w.collapsed);
  }

  void setCollapsed(String id, bool collapsed) {
    final w = state.workspace(id);
    if (w == null || w.collapsed == collapsed) return;
    state = state.copyWith(
      workspaces: [
        for (final x in state.workspaces)
          x.id == id ? x.copyWith(collapsed: collapsed) : x,
      ],
    );
    _save();
  }

  /// D16: no confirmation; the tabs go to the end of Default, which
  /// expands; a neutral toast says so. Default itself stays (D11).
  void delete(String id) {
    final w = state.workspace(id);
    if (w == null || w.isDefault) return;
    final moved = state.tabsOf(id);
    state = state.copyWith(
      workspaces: [
        for (final x in state.workspaces)
          if (x.id != id)
            x.isDefault && moved.isNotEmpty ? x.copyWith(collapsed: false) : x,
      ],
      members: {
        for (final e in state.members.entries)
          if (e.key != id)
            e.key: e.key == kDefaultWorkspaceId ? [...e.value, ...moved] : e.value,
      },
      currentId: state.currentId == id ? kDefaultWorkspaceId : state.currentId,
      renaming: state.renaming == RenameWorkspace(id) ? null : state.renaming,
    );
    _save();
    _tabs.showNotice(
      WorkspaceDeletedNotice(
        name: w.displayName(_l10n),
        movedTo: state.defaultWorkspace.displayName(_l10n),
      ),
    );
  }

  /// Moves [tabId] into [workspaceId] at [index], counted in the target
  /// list as it is before the move (null: the end). The target expands.
  void moveTab(int tabId, String workspaceId, [int? index]) {
    final from = state.workspaceOf(tabId);
    if (from == null || state.workspace(workspaceId) == null) return;
    var at = index ?? state.tabsOf(workspaceId).length;
    if (from == workspaceId && state.tabsOf(from).indexOf(tabId) < at) at--;
    final members = {
      for (final e in state.members.entries)
        e.key: [
          for (final id in e.value)
            if (id != tabId) id,
        ],
    };
    final target = members[workspaceId]!;
    target.insert(at.clamp(0, target.length), tabId);
    final selected = ref.read(terminalTabsProvider).selectedId == tabId;
    state = state.copyWith(
      members: members,
      currentId: selected ? workspaceId : state.currentId,
    );
    setCollapsed(workspaceId, false);
  }

  bool canMoveUp(int tabId) => _neighbour(tabId, -1) != null;
  bool canMoveDown(int tabId) => _neighbour(tabId, 1) != null;
  void moveUp(int tabId) => _move(tabId, -1);
  void moveDown(int tabId) => _move(tabId, 1);

  void _move(int tabId, int step) {
    final to = _neighbour(tabId, step);
    if (to != null) moveTab(tabId, to.$1, to.$2);
  }

  /// Where one step moves [tabId] (workspace, index before the move), or
  /// null at the very top/bottom. Crosses a workspace boundary only while
  /// headers show.
  (String, int)? _neighbour(int tabId, int step) {
    final from = state.workspaceOf(tabId);
    if (from == null) return null;
    final list = state.tabsOf(from);
    final next = list.indexOf(tabId) + step;
    if (next >= 0 && next < list.length) {
      return (from, step > 0 ? next + 1 : next);
    }
    if (!state.showHeaders) return null;
    final w = state.workspaces.indexWhere((x) => x.id == from) + step;
    if (w < 0 || w >= state.workspaces.length) return null;
    final target = state.workspaces[w].id;
    return (target, step > 0 ? 0 : state.tabsOf(target).length);
  }

  /// ⌘1…⌘9 (C5): the n-th visible tab; nothing when there is none.
  void selectVisible(int position) {
    final ids = state.visibleTabIds;
    if (position >= 1 && position <= ids.length) {
      _tabs.select(ids[position - 1]);
    }
  }

  /// Ctrl+Tab / ↑↓: the next visible tab, wrapping. From a hidden selected
  /// tab (its workspace collapsed), the nearest visible one that way.
  void step(int delta) {
    final visible = state.visibleTabIds;
    if (visible.isEmpty) return;
    final selected = ref.read(terminalTabsProvider).selectedId;
    final i = selected == null ? -1 : visible.indexOf(selected);
    if (i >= 0) {
      _tabs.select(visible[(i + delta) % visible.length]);
      return;
    }
    final ordered = state.orderedTabIds;
    final at = selected == null ? -1 : ordered.indexOf(selected);
    final ahead = delta > 0
        ? ordered.skip(at + 1)
        : ordered.take(max(at, 0)).toList().reversed;
    final next = ahead.where(visible.contains).firstOrNull;
    _tabs.select(next ?? (delta > 0 ? visible.first : visible.last));
  }

  void startRename(RenameTarget target) =>
      state = state.copyWith(renaming: target);

  void endRename() => state = state.copyWith(renaming: null);

  // ---- internals --------------------------------------------------------

  SidebarState _reconcile(SidebarState s, TerminalTabsState tabs) {
    final live = {for (final t in tabs.tabs) t.id: t};
    final members = <String, List<int>>{
      for (final w in s.workspaces)
        w.id: [
          for (final id in s.tabsOf(w.id))
            if (live.containsKey(id)) id,
        ],
    };
    final placed = {for (final ids in members.values) ...ids};
    final expand = <String>{};
    for (final tab in tabs.tabs) {
      if (placed.contains(tab.id)) continue;
      if (tab.origin == SessionOrigin.phone) {
        members[kDefaultWorkspaceId]!.add(tab.id);
        continue;
      }
      final pending = _pendingTarget;
      final target = pending != null && members.containsKey(pending)
          ? pending
          : members.containsKey(s.currentId)
          ? s.currentId
          : kDefaultWorkspaceId;
      _pendingTarget = null;
      members[target]!.add(tab.id);
      expand.add(target); // a tab opened here is never born hidden
    }
    var current = s.currentId;
    final selected = tabs.selectedId;
    if (selected != null) {
      for (final MapEntry(key: id, value: ids) in members.entries) {
        if (ids.contains(selected)) current = id;
      }
    }
    if (!members.containsKey(current)) current = kDefaultWorkspaceId;
    final renaming = switch (s.renaming) {
      RenameTab(:final id) when !live.containsKey(id) => null,
      final other => other,
    };
    final workspaces = expand.isEmpty
        ? s.workspaces
        : [
            for (final w in s.workspaces)
              expand.contains(w.id) ? w.copyWith(collapsed: false) : w,
          ];
    final next = s.copyWith(
      workspaces: workspaces,
      members: members,
      currentId: current,
      renaming: renaming,
    );
    if (!identical(workspaces, s.workspaces)) {
      scheduleMicrotask(_save);
    }
    return next;
  }

  String _newId() {
    String id;
    do {
      id = 'w${_random.nextInt(1 << 30).toRadixString(36)}';
    } while (state.workspace(id) != null);
    return id;
  }

  String _numberedName() {
    final used = {for (final w in state.workspaces) w.name};
    for (var n = 2; ; n++) {
      final name = _l10n.workspaceNumberedName(n);
      if (!used.contains(name)) return name;
    }
  }

  void _save() {
    if (!ref.mounted) return;
    final settings = ref.read(settingsStoreProvider);
    unawaited(
      settings
          .setStrings(SettingKeys.terminalWorkspaces, [
            for (final w in state.workspaces) w.encode(),
          ])
          .catchError(
            (Object e) => debugPrint('workspaces not saved: ${e.runtimeType}'),
          ),
    );
  }
}
```

(`_reconcile` runs inside `build` before `state` exists, so its save is a microtask; `_newId` and `_numberedName` only run after `build`.)

- [ ] **Step 5: Run the model tests**

Run: `cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/terminal/sidebar_workspaces_test.dart`
Expected: PASS.

- [ ] **Step 6: Write the failing shortcut/page tests**

Append to `apps/desktop/test/ui/terminal_shortcuts_test.dart` inside `main()`:

```dart
  test('⌘⇧N / Ctrl+Shift+N make a workspace, without key repeat (C5)', () {
    final mac = desktopShortcuts(TargetPlatform.macOS);
    final win = desktopShortcuts(TargetPlatform.windows);
    const macKey = SingleActivator(
      LogicalKeyboardKey.keyN,
      meta: true,
      shift: true,
      includeRepeats: false,
    );
    const winKey = SingleActivator(
      LogicalKeyboardKey.keyN,
      control: true,
      shift: true,
      includeRepeats: false,
    );
    expect(mac[macKey], isA<NewWorkspaceIntent>());
    expect(win[winKey], isA<NewWorkspaceIntent>());
    expect(terminalViewShortcuts(TargetPlatform.macOS)[macKey], isA<NewWorkspaceIntent>());
  });
```

Append to `apps/desktop/test/ui/terminal_workspace_test.dart` inside `main()`:

```dart
  testWorkspace(
    '⌘⇧N makes a workspace with a tab; ⌘1 and ↓ in the list follow the '
    'visible order (C5)',
    (tester) async {
      local.add(local.summary(1, origin: SessionOrigin.desktop));
      await pumpWorkspace(tester);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pumpAndSettle();
      final sidebar = container.read(sidebarWorkspacesProvider);
      expect(sidebar.workspaces, hasLength(2));
      final ws = sidebar.workspaces.last.id;
      final created = sidebar.tabsOf(ws).single;
      container.read(sidebarWorkspacesProvider.notifier)
        ..endRename()
        ..setCollapsed(kDefaultWorkspaceId, true);
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.digit1);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pump();
      expect(tabs().selectedId, created);
      expect(find.byKey(const ValueKey('tab.1')), findsNothing); // collapsed
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );
```

(add `import 'package:shellx_desktop/src/terminal/sidebar_workspaces.dart';` to both test files that need it, and `import 'package:flutter/services.dart';` where `LogicalKeyboardKey` is not imported yet).

Run: `cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/ui/terminal_shortcuts_test.dart test/ui/terminal_workspace_test.dart`
Expected: FAIL — `NewWorkspaceIntent` undefined.

- [ ] **Step 7: `NewWorkspaceIntent` and its keys**

In `apps/desktop/lib/src/ui/terminal/terminal_shortcuts.dart` add:

```dart
/// ⌘⇧N / Ctrl+Shift+N (A2 C5): a new workspace with a tab in it.
class NewWorkspaceIntent extends Intent {
  const NewWorkspaceIntent();
}
```

and in `_windowShortcuts`, after the `CloseTabIntent` entry:

```dart
    (mac
            ? const SingleActivator(
                LogicalKeyboardKey.keyN,
                meta: true,
                shift: true,
                includeRepeats: false,
              )
            : const SingleActivator(
                LogicalKeyboardKey.keyN,
                control: true,
                shift: true,
                includeRepeats: false,
              )):
        const NewWorkspaceIntent(),
```

- [ ] **Step 8: The page uses the visible order and the new action**

In `apps/desktop/lib/src/ui/terminal/terminal_workspace_page.dart` (import `../../terminal/sidebar_workspaces.dart`), in `_actions()`:

```dart
    final workspaces = ref.read(sidebarWorkspacesProvider.notifier);
```

then change the three tab-order actions and add one:

```dart
      SelectTabIntent: run<SelectTabIntent>(
        (intent) {
          workspaces.selectVisible(intent.position);
          focusTerminal();
        },
        // (keep the existing AltGr `enabled:` callback unchanged)
      ),
      NextTabIntent: run<NextTabIntent>((_) {
        workspaces.step(1);
        focusTerminal();
      }),
      PreviousTabIntent: run<PreviousTabIntent>((_) {
        workspaces.step(-1);
        focusTerminal();
      }),
      // The new workspace's name field takes the keyboard (D15); it hands
      // it to the terminal when it closes.
      NewWorkspaceIntent: run<NewWorkspaceIntent>((_) {
        unawaited(workspaces.create());
      }),
```

In `build`, the selection listener must not steal the keyboard from an open name field (D15):

```dart
    ref.listen(terminalTabsProvider.select((s) => s.selectedId), (_, id) {
      if (id != null &&
          !sidebarFocus.hasFocus &&
          ref.read(sidebarWorkspacesProvider).renaming == null) {
        focusTerminal();
      }
    });
```

- [ ] **Step 9: The A1 sidebar lists rows in the visible order**

In `apps/desktop/lib/src/ui/terminal/session_sidebar.dart` (import `../../terminal/sidebar_workspaces.dart`):

Add to `_SessionSidebarState`:

```dart
  /// The rows on screen, in the sidebar's visible order (C5).
  List<TerminalTab> _visibleTabs() {
    final byId = {for (final t in ref.read(terminalTabsProvider).tabs) t.id: t};
    return [
      for (final id in ref.read(sidebarWorkspacesProvider).visibleTabIds)
        ?byId[id],
    ];
  }
```

In `_onKey` replace the arrow/Home/End cases:

```dart
      case LogicalKeyboardKey.arrowDown:
        workspaces.step(1);
      case LogicalKeyboardKey.arrowUp:
        workspaces.step(-1);
      case LogicalKeyboardKey.home:
        workspaces.selectVisible(1);
      case LogicalKeyboardKey.end:
        workspaces.selectVisible(_visibleTabs().length);
```

with `final workspaces = ref.read(sidebarWorkspacesProvider.notifier);` next to `final tabs = …` (remove `tabs` if it becomes unused). In `_reveal`, use `_visibleTabs()` instead of `ref.read(terminalTabsProvider).tabs`. In `build`, add `ref.watch(sidebarWorkspacesProvider);` after watching `terminalTabsProvider`, compute `final rows = _visibleTabs();`, and build the list from `rows` (`itemCount: rows.length`, `final tab = rows[i];`, `count: rows.length`, `ids` from `rows`, `canRequestFocus`/`skipTraversal` from `rows.isEmpty`).

(`?byId[id]` is Dart 3.8 null-aware collection element; the SDK constraint is ^3.11.)

- [ ] **Step 10: Run all desktop tests**

Run: `cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test`
Expected: PASS (A1 sidebar tests keep passing: with one workspace the visible order is the creation order).

- [ ] **Step 11: Format, analyze, commit**

```bash
cd apps/desktop
~/fvm/versions/3.41.4/bin/dart format --set-exit-if-changed lib test
PATH=~/fvm/versions/3.41.4/bin:$PATH flutter analyze
cd ../..
git add apps/desktop/lib/src/platform/settings_store.dart apps/desktop/lib/src/terminal/sidebar_workspaces.dart apps/desktop/lib/src/ui/terminal/terminal_shortcuts.dart apps/desktop/lib/src/ui/terminal/terminal_workspace_page.dart apps/desktop/lib/src/ui/terminal/session_sidebar.dart apps/desktop/test/terminal/sidebar_workspaces_test.dart apps/desktop/test/ui/terminal_shortcuts_test.dart apps/desktop/test/ui/terminal_workspace_test.dart
git commit -m "feat(desktop): workspaces model with visible-order tab shortcuts and ⌘⇧N (A2 C5)"
```

---

### Task 8: Desktop — the context line, inline tab rename, the new tab menu

Each row gets its context line (UI-A2 §2: branch · `~`-path · clickable ports, laid out by a pure function), the inline name field (§4), the new row menu with "Move to workspace…" (§5.1, §5.3), F2 and ⌥↑/⌥↓ in the list, and the extended semantics (§8).

**Files:**
- Modify: `apps/desktop/lib/src/ui/theme/shellx_desktop_theme.dart` (UI-A2 §1.2 sizes)
- Create: `apps/desktop/lib/src/terminal/context_line.dart`
- Create: `apps/desktop/lib/src/ui/terminal/inline_name_field.dart`
- Modify: `apps/desktop/lib/src/ui/terminal/shellx_menu.dart` (`dividerBefore`)
- Modify: `apps/desktop/lib/src/ui/terminal/session_tab_row.dart`
- Modify: `apps/desktop/lib/src/ui/terminal/session_sidebar.dart`
- Create: `apps/desktop/test/terminal/context_line_test.dart`
- Create: `apps/desktop/test/ui/sidebar_test_harness.dart`, `apps/desktop/test/ui/sidebar_rows_test.dart`

**Interfaces:**
- Consumes: `TerminalTab.cwd/gitBranch/ports/customTitle/label/automaticLabel/hasContext`, `TerminalTabs.rename/showNotice`, `PortOpenFailedNotice`, `homeDirectoryProvider`, shortcut labels, ARB keys (Task 6); `sidebarWorkspacesProvider`, `RenameTab`, `SidebarWorkspaces.startRename/endRename/moveTab/moveUp/moveDown/canMoveUp/canMoveDown/create` (Task 7); `UrlOpener.openLocalPort` via `desktopServicesProvider` (Task 6).
- Produces:
  - `String displayPath(String path, {required String home, required bool windows})`
  - `String ellipsizeEnd(String text, double maxWidth, double Function(String) measure)`, `String ellipsizeMiddle(String text, double maxWidth, double Function(String) measure)`, `String ellipsizePath(String path, double maxWidth, double Function(String) measure, {required bool windows})`
  - `final class ContextLineLayout { String? branch; String? path; List<int> ports; int morePorts; bool truncated; bool get isEmpty; }`, `ContextLineLayout layoutContextLine({required String? branch, required String? path, required List<int> ports, required double width, required double Function(String) measure, required bool windows})`
  - `class InlineNameField extends StatefulWidget` — `InlineNameField({Key? key, required String initial, required TextStyle style, required String label, required void Function(String text) onCommit, required VoidCallback onCancel})`
  - `ShellxMenuEntry({…, bool dividerBefore = false})`
  - `SessionTabRow.heightFor(TextScaler, {bool context = false})`; new `SessionTabRow` params `renaming`, `onStartRename`, `onRename`, `onCancelRename`, `onOpenPort`, `onMenu`, `positionLabel`, `extraActions`, `home`
  - Widget keys: `port.<n>` (port link), `row.contextLine`, `row.renameField`, `menu.renameTab`, `menu.automaticName`, `menu.moveTo`, `menu.moveUp`, `menu.moveDown`, `menu.port.<n>`, `menu.closeTab` (A1), `menu.moveTo.<workspaceId>`, `menu.moveTo.new`

- [ ] **Step 1: Write the failing pure tests**

Create `apps/desktop/test/terminal/context_line_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/terminal/context_line.dart';

/// 6 px per character: widths are easy to reason about.
double _m(String s) => s.runes.length * 6.0;

void main() {
  group('displayPath (UI-A2 §2.3)', () {
    test('POSIX: home becomes ~ only on a whole component', () {
      String d(String p) => displayPath(p, home: '/Users/r', windows: false);
      expect(d('/Users/r'), '~');
      expect(d('/Users/r/work/x'), '~/work/x');
      expect(d('/Users/r2/x'), '/Users/r2/x');
      expect(d('/opt'), '/opt');
      expect(displayPath('/Users/r/w', home: '/Users/r/', windows: false), '~/w');
      expect(displayPath('/Users/R/w', home: '/Users/r', windows: false), '/Users/R/w');
    });

    test('Windows: case-insensitive, both separators', () {
      String d(String p) => displayPath(p, home: r'C:\Users\r', windows: true);
      expect(d(r'c:\users\R\src'), r'~\src');
      expect(d(r'C:\Users\r'), '~');
      expect(d(r'D:\src'), r'D:\src');
    });
  });

  group('ellipsis', () {
    test('ellipsizeEnd keeps the start', () {
      expect(ellipsizeEnd('feature-branch', 48, _m), 'feature…');
      expect(ellipsizeEnd('main', 48, _m), 'main');
      expect(ellipsizeEnd('main', 3, _m), '');
    });

    test('ellipsizePath drops middle components first, then characters', () {
      const p = '~/work/shellx/apps/desktop';
      expect(ellipsizePath(p, 999, _m, windows: false), p);
      expect(ellipsizePath(p, 126, _m, windows: false), '~/…/apps/desktop');
      expect(ellipsizePath(p, 66, _m, windows: false), '~/…/desktop');
      expect(ellipsizePath(p, 40, _m, windows: false), ellipsizeMiddle(p, 40, _m));
      expect(
        ellipsizePath(r'C:\a\b\c\d', 48, _m, windows: true),
        r'C:\…\c\d',
      );
    });

    test('ellipsizeMiddle keeps both ends', () {
      expect(ellipsizeMiddle('~/workspace', 36, _m), '~/w…ce');
    });
  });

  group('layoutContextLine (UI-A2 §2.2)', () {
    test('everything fits', () {
      final l = layoutContextLine(
        branch: 'main',
        path: '~/w',
        ports: [3000],
        width: 168,
        measure: _m,
        windows: false,
      );
      expect((l.branch, l.path, l.morePorts, l.truncated), (
        'main',
        '~/w',
        0,
        false,
      ));
      expect(l.ports, [3000]);
    });

    test('the path is cut in the middle first', () {
      final l = layoutContextLine(
        branch: 'main',
        path: '~/work/shellx/apps/desktop',
        ports: const [],
        width: 168,
        measure: _m,
        windows: false,
      );
      expect((l.branch, l.path, l.truncated), ('main', '~/…/apps/desktop', true));
    });

    test('ports keep at most 60 % and are never cut; the rest is +N', () {
      final l = layoutContextLine(
        branch: null,
        path: null,
        ports: [3000, 5173, 8080, 9229, 24678],
        width: 168,
        measure: _m,
        windows: false,
      );
      expect(l.ports, [3000, 5173]);
      expect((l.morePorts, l.truncated), (3, true));
    });

    test('a long branch is cut at the end; no room → the path is dropped', () {
      final l = layoutContextLine(
        branch: 'feature-very-long-name',
        path: '~/w',
        ports: [3000],
        width: 100,
        measure: _m,
        windows: false,
      );
      expect((l.branch, l.path, l.ports.single, l.truncated), (
        'feature…',
        null,
        3000,
        true,
      ));
    });

    test('nothing known → empty', () {
      final l = layoutContextLine(
        branch: null,
        path: null,
        ports: const [],
        width: 168,
        measure: _m,
        windows: false,
      );
      expect(l.isEmpty, isTrue);
    });
  });
}
```

Run: `cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/terminal/context_line_test.dart`
Expected: FAIL — `context_line.dart` does not exist.

- [ ] **Step 2: Write `context_line.dart`**

Create `apps/desktop/lib/src/terminal/context_line.dart`:

```dart
import 'dart:math';

import 'package:flutter/foundation.dart';

/// UI-A2 §2.2 shares.
const double _portPadding = 4; // 2 × ShellxSizes.portPadH
const double _portGap = 4;
const double _portsMaxShare = 0.6;
const double _branchMaxShare = 0.45;
const double _branchMin = 48;
const double _pathMin = 24;
const String _separator = ' · ';

/// UI-A2 §2.3: the home directory as `~`, only on a whole component;
/// Windows compares without case and accepts `\` and `/`.
String displayPath(String path, {required String home, required bool windows}) {
  if (home.isEmpty) return path;
  bool sep(String c) => c == '/' || (windows && c == r'\');
  var h = home;
  while (h.length > 1 && sep(h[h.length - 1])) {
    h = h.substring(0, h.length - 1);
  }
  final starts = windows
      ? path.toLowerCase().startsWith(h.toLowerCase())
      : path.startsWith(h);
  if (!starts) return path;
  if (path.length == h.length) return '~';
  if (!sep(path[h.length])) return path;
  return '~${path.substring(h.length)}';
}

/// The longest start of [text] + `…` that fits; '' when not even that.
String ellipsizeEnd(
  String text,
  double maxWidth,
  double Function(String) measure,
) {
  if (measure(text) <= maxWidth) return text;
  final runes = text.runes.toList();
  String cut(int n) => '${String.fromCharCodes(runes.take(n))}…';
  var lo = 0;
  var hi = runes.length - 1;
  while (lo < hi) {
    final mid = (lo + hi + 1) ~/ 2;
    if (measure(cut(mid)) <= maxWidth) {
      lo = mid;
    } else {
      hi = mid - 1;
    }
  }
  return lo == 0 ? '' : cut(lo);
}

/// Both ends of [text] around `…` (the start gets the extra character).
String ellipsizeMiddle(
  String text,
  double maxWidth,
  double Function(String) measure,
) {
  if (measure(text) <= maxWidth) return text;
  final runes = text.runes.toList();
  String cut(int n) {
    final head = (n + 1) ~/ 2;
    final tail = n - head;
    return '${String.fromCharCodes(runes.take(head))}…'
        '${String.fromCharCodes(runes.skip(runes.length - tail))}';
  }

  var lo = 0;
  var hi = runes.length - 1;
  while (lo < hi) {
    final mid = (lo + hi + 1) ~/ 2;
    if (measure(cut(mid)) <= maxWidth) {
      lo = mid;
    } else {
      hi = mid - 1;
    }
  }
  return lo == 0 ? '' : cut(lo);
}

/// UI-A2 §2.2 step 4: keep the first component (`~`, `/`, `C:`), replace
/// middle components with `…`, keep as many last components as fit; then
/// [ellipsizeMiddle] on characters.
String ellipsizePath(
  String path,
  double maxWidth,
  double Function(String) measure, {
  required bool windows,
}) {
  if (measure(path) <= maxWidth) return path;
  final sep = windows ? r'\' : '/';
  final parts = path.split(windows ? RegExp(r'[\\/]') : RegExp('/'));
  if (parts.length > 2) {
    for (var keep = parts.length - 2; keep >= 1; keep--) {
      final candidate = [
        parts.first,
        '…',
        ...parts.sublist(parts.length - keep),
      ].join(sep);
      if (measure(candidate) <= maxWidth) return candidate;
    }
  }
  return ellipsizeMiddle(path, maxWidth, measure);
}

@immutable
final class ContextLineLayout {
  const ContextLineLayout({
    this.branch,
    this.path,
    this.ports = const [],
    this.morePorts = 0,
    this.truncated = false,
  });

  final String? branch;
  final String? path;

  /// The ports shown (ascending), and how many more hide behind `+N`.
  final List<int> ports;
  final int morePorts;

  /// Something was cut or left out: the row shows the full-line tooltip.
  final bool truncated;

  bool get isEmpty => branch == null && path == null && ports.isEmpty;
}

/// UI-A2 §2.2: ports (never cut, ≤ 60 %) > branch (≤ 45 % of the rest,
/// end-cut) > path (middle-cut, dropped under 24 px).
ContextLineLayout layoutContextLine({
  required String? branch,
  required String? path,
  required List<int> ports,
  required double width,
  required double Function(String) measure,
  required bool windows,
}) {
  final sepWidth = measure(_separator);
  double portsWidth(List<int> shown, int more) {
    if (shown.isEmpty) return 0;
    var w = _portGap * (shown.length - 1);
    for (final p in shown) {
      w += measure(':$p') + _portPadding;
    }
    if (more > 0) w += _portGap + measure('+$more');
    return w;
  }

  var shown = ports.take(3).toList();
  var more = ports.length - shown.length;
  while (shown.length > 1 && portsWidth(shown, more) > width * _portsMaxShare) {
    shown = shown.sublist(0, shown.length - 1);
    more++;
  }
  var truncated = more > 0;
  var remaining = width - portsWidth(shown, more);
  if (shown.isNotEmpty && (branch != null || path != null)) {
    remaining -= sepWidth;
  }

  String? b = branch;
  if (b != null) {
    final cap = remaining < _branchMin
        ? remaining
        : max(_branchMin, remaining * _branchMaxShare);
    if (measure(b) > cap) {
      b = ellipsizeEnd(b, cap, measure);
      truncated = true;
      if (b.isEmpty) b = null;
    }
    if (b != null) remaining -= measure(b);
  }

  String? p = path;
  if (p != null) {
    if (b != null) remaining -= sepWidth;
    if (remaining < _pathMin) {
      p = null;
      truncated = true;
    } else if (measure(p) > remaining) {
      p = ellipsizePath(p, remaining, measure, windows: windows);
      truncated = true;
      if (p.isEmpty) p = null;
    }
  }
  return ContextLineLayout(
    branch: b,
    path: p,
    ports: shown,
    morePorts: more,
    truncated: truncated,
  );
}
```

Run: `cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/terminal/context_line_test.dart`
Expected: PASS.

- [ ] **Step 3: Sizes, menu divider, the name field**

In `shellx_desktop_theme.dart`, `ShellxSizes`, add:

```dart
  /// UI-A2 §1.2: a row with a context line (6 + 18 + 2 + 14 + 6).
  static const double rowWithContext = 46;
  static const double rowContextPadding = 6;
  static const double contextLine = 14;
  static const double contextGap = 2;
  static const double contextInset = 32;
  static const double portHit = 24;
  static const double portGap = 4;
  static const double portPadH = 2;

  /// UI-A2 §3 workspace header.
  static const double workspaceHeader = 28;
  static const double workspaceHeaderTop = 8;
  static const double workspaceHeaderText = 16;
  static const double chevronHit = 20;
  static const double headerAddHit = 24;
  static const double headerAddVisual = 20;
  static const double headerCountMin = 16;
  static const double collapsedMarkHeight = 12;
  static const double emptyWorkspaceRow = 30;

  /// UI-A2 §4, §6.
  static const double renameField = 22;
  static const double dropLine = 2;
  static const double dragAutoScrollZone = 32;
  static const double dragAutoScrollSpeed = 240;
  static const double menuDivider = 9;
```

and to `ShellxMotion`:

```dart
  /// UI-A2 §6: hovering a dragged tab over a collapsed header expands it.
  static const Duration dragExpandDelay = Duration(milliseconds: 600);
```

In `shellx_menu.dart`, add to `ShellxMenuEntry` the field and constructor parameter:

```dart
  /// UI-A2 §5: a 1 px `line` separator above this item (4 px above/below).
  final bool dividerBefore;
```

(`this.dividerBefore = false,`), and in `showShellxMenu` replace `items: [for (final entry in entries) _ShellxMenuItem<T>(entry)],` with:

```dart
    items: [
      for (final entry in entries) ...[
        if (entry.dividerBefore)
          const PopupMenuDivider(
            height: ShellxSizes.menuDivider,
            thickness: 1,
            color: ShellxDesktopColors.line,
          ),
        _ShellxMenuItem<T>(entry),
      ],
    ],
```

Create `apps/desktop/lib/src/ui/terminal/inline_name_field.dart`:

```dart
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/shellx_desktop_theme.dart';

/// UI-A2 §4: rename in place. Opens with the text selected; Enter or
/// losing the focus commits, Esc cancels — exactly one of the two calls.
/// ⌘A/⌘C/⌘V/⌘X (Ctrl on Windows) edit the field instead of reaching the
/// window's terminal shortcuts.
class InlineNameField extends StatefulWidget {
  const InlineNameField({
    super.key,
    required this.initial,
    required this.style,
    required this.label,
    required this.onCommit,
    required this.onCancel,
  });

  final String initial;
  final TextStyle style;

  /// The field's accessible name ("Tên tab" / "Tên workspace").
  final String label;
  final void Function(String text) onCommit;
  final VoidCallback onCancel;

  /// Matches `kTabNameMaxLength` and `kWorkspaceNameMaxLength`.
  static const int maxLength = 64;

  @override
  State<InlineNameField> createState() => _InlineNameFieldState();
}

class _InlineNameFieldState extends State<InlineNameField> {
  late final _controller = TextEditingController(text: widget.initial)
    ..selection = TextSelection(
      baseOffset: 0,
      extentOffset: widget.initial.length,
    );
  final _focus = FocusNode(debugLabel: 'inline name');
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocus);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  void _onFocus() {
    if (!_focus.hasFocus) _commit();
  }

  void _commit() {
    if (_done) return;
    _done = true;
    widget.onCommit(_controller.text);
  }

  void _cancel() {
    if (_done) return;
    _done = true;
    widget.onCancel();
  }

  @override
  void dispose() {
    _focus.removeListener(_onFocus);
    _focus.dispose();
    _controller.dispose();
    super.dispose();
  }

  static Map<ShortcutActivator, Intent> _editing() {
    final mac = defaultTargetPlatform == TargetPlatform.macOS;
    SingleActivator key(LogicalKeyboardKey k) =>
        mac ? SingleActivator(k, meta: true) : SingleActivator(k, control: true);
    return {
      key(LogicalKeyboardKey.keyA): const SelectAllTextIntent(
        SelectionChangedCause.keyboard,
      ),
      key(LogicalKeyboardKey.keyC): CopySelectionTextIntent.copy,
      key(LogicalKeyboardKey.keyX): const CopySelectionTextIntent.cut(
        SelectionChangedCause.keyboard,
      ),
      key(LogicalKeyboardKey.keyV): const PasteTextIntent(
        SelectionChangedCause.keyboard,
      ),
    };
  }

  @override
  Widget build(BuildContext context) {
    const outline = OutlineInputBorder(
      borderRadius: BorderRadius.all(Radius.circular(ShellxRadius.r4)),
      borderSide: BorderSide(color: ShellxDesktopColors.accent),
    );
    return Shortcuts(
      shortcuts: _editing(),
      child: CallbackShortcuts(
        bindings: {const SingleActivator(LogicalKeyboardKey.escape): _cancel},
        child: SizedBox(
          height: ShellxSizes.renameField,
          child: Semantics(
            label: widget.label,
            textField: true,
            child: TextField(
            key: const Key('row.renameField'),
            controller: _controller,
            focusNode: _focus,
            style: widget.style.copyWith(color: ShellxDesktopColors.textTitle),
            cursorColor: ShellxDesktopColors.accent,
            maxLines: 1,
            maxLength: InlineNameField.maxLength,
            maxLengthEnforcement: MaxLengthEnforcement.enforced,
            onSubmitted: (_) => _commit(),
            decoration: InputDecoration(
              isDense: true,
              filled: true,
              fillColor: ShellxDesktopColors.surfaceInset,
              counterText: '',
              semanticCounterText: '',
              contentPadding: const EdgeInsets.symmetric(
                horizontal: ShellxSpace.s4,
                vertical: ShellxSpace.s2,
              ),
              border: outline,
              enabledBorder: outline,
              focusedBorder: outline,
            ),
          ),
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Write the failing widget tests**

Create `apps/desktop/test/ui/sidebar_test_harness.dart` (shared by Tasks 8–9):

```dart
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/l10n/app_localizations.dart';
import 'package:shellx_desktop/src/agent/agent_controller.dart';
import 'package:shellx_desktop/src/agent/desktop_services.dart';
import 'package:shellx_desktop/src/terminal/local_sessions_provider.dart';
import 'package:shellx_desktop/src/terminal/sidebar_workspaces.dart';
import 'package:shellx_desktop/src/terminal/terminal_tabs.dart';
import 'package:shellx_desktop/src/ui/terminal/terminal_workspace_page.dart';
import 'package:shellx_desktop/src/ui/theme/shellx_desktop_theme.dart';

import '../support/fake_local_sessions.dart';
import '../support/fakes.dart';

late TestHarness h;
late FakeLocalSessions local;
late ProviderContainer container;

const testHome = '/Users/test';

Future<void> pumpSidebar(WidgetTester tester, {double textScale = 1}) async {
  h = TestHarness(settings: {'onboarding_done': true});
  container = ProviderContainer(
    overrides: [
      desktopServicesProvider.overrideWithValue(h.services()),
      localSessionsProvider.overrideWithValue(local),
      homeDirectoryProvider.overrideWithValue(testHome),
    ],
  );
  await h.seedSignedIn();
  await container
      .read(agentControllerProvider.notifier)
      .bootstrap(watchForWake: false);
  tester.view.physicalSize = const Size(1100, 720);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
        child: MaterialApp(
          theme: buildDesktopTheme(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: const Scaffold(body: TerminalWorkspacePage()),
        ),
      ),
    ),
  );
  await tester.pump();
}

TerminalTabsState tabs() => container.read(terminalTabsProvider);
SidebarState sidebar() => container.read(sidebarWorkspacesProvider);
SidebarWorkspaces workspaces() =>
    container.read(sidebarWorkspacesProvider.notifier);
Finder row(int id) => find.byKey(ValueKey('tab.$id'));

/// macOS only (⌘ labels); the body tears the container down itself
/// (bootstrap leaves a periodic timer, as in terminal_workspace_test).
void testSidebar(String description, Future<void> Function(WidgetTester) body) =>
    testWidgets(
      description,
      variant: TargetPlatformVariant.only(TargetPlatform.macOS),
      (tester) async {
        try {
          await body(tester);
        } finally {
          await tester.pumpWidget(const SizedBox());
          container.dispose();
        }
      },
    );

void setUpSidebar() => setUp(() => local = FakeLocalSessions());

bool get isMac => defaultTargetPlatform == TargetPlatform.macOS;
```

Create `apps/desktop/test/ui/sidebar_rows_test.dart`:

```dart
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_desktop/src/terminal/sidebar_workspaces.dart';
import 'package:shellx_desktop/src/terminal/terminal_tabs.dart';
import 'package:shellx_desktop/src/ui/theme/shellx_desktop_theme.dart';

import 'sidebar_test_harness.dart';

void main() {
  setUpSidebar();

  testSidebar('a row with context shows branch · ~/path · ports and is 46 '
      'high; a row without context stays 30 (UI-A2 §2.1)', (tester) async {
    local
      ..add(
        local.summary(
          1,
          origin: SessionOrigin.desktop,
          cwd: '$testHome/work',
          gitBranch: 'main',
          ports: [5173, 3000],
        ),
      )
      ..add(local.summary(2, origin: SessionOrigin.desktop));
    await pumpSidebar(tester);
    expect(tester.getSize(row(1)).height, ShellxSizes.rowWithContext);
    expect(tester.getSize(row(2)).height, ShellxSizes.row);
    final line = find.descendant(
      of: row(1),
      matching: find.byKey(const Key('row.contextLine')),
    );
    expect(find.descendant(of: line, matching: find.text('main')), findsOneWidget);
    expect(find.descendant(of: line, matching: find.text('~/work')), findsOneWidget);
    expect(find.byKey(const Key('port.5173')), findsOneWidget);
    expect(find.byKey(const Key('port.3000')), findsOneWidget);
    expect(tester.getSize(find.byKey(const Key('port.3000'))).height, 24);
  });

  testSidebar('a large text scale grows the row (UI-A2 §1.3)', (tester) async {
    local.add(
      local.summary(1, origin: SessionOrigin.desktop, gitBranch: 'main'),
    );
    await pumpSidebar(tester, textScale: 2);
    expect(tester.getSize(row(1)).height, 18 * 2 + 14 * 2 + 14);
  });

  testSidebar('clicking a port opens http://localhost:PORT without '
      'selecting the tab; a failure shows a toast (UI-A2 §2.4)', (tester) async {
    local
      ..add(local.summary(1, origin: SessionOrigin.desktop))
      ..add(local.summary(2, origin: SessionOrigin.desktop, ports: [8080]));
    await pumpSidebar(tester);
    expect(tabs().selectedId, 1);
    await tester.tap(find.byKey(const Key('port.8080')));
    await tester.pumpAndSettle();
    expect(h.urlOpener.ports, [8080]);
    expect(tabs().selectedId, 1);
    h.urlOpener.fail = true;
    await tester.tap(find.byKey(const Key('port.8080')));
    await tester.pumpAndSettle();
    expect(find.text("Couldn't open the browser."), findsOneWidget);
  });

  testSidebar('double-click renames in place: Enter keeps, Esc cancels, '
      'blank restores the automatic title (C6)', (tester) async {
    local.add(local.summary(1, origin: SessionOrigin.desktop, title: 'vim'));
    await pumpSidebar(tester);
    await tester.tap(row(1));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(row(1));
    await tester.pumpAndSettle();
    final field = find.byKey(const Key('row.renameField'));
    expect(field, findsOneWidget);
    await tester.enterText(field, 'api server');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(tabs().tabs.single.label, 'api server');
    expect(sidebar().renaming, isNull);

    workspaces().startRename(const RenameTab(1));
    await tester.pumpAndSettle();
    await tester.enterText(field, 'nope');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(tabs().tabs.single.label, 'api server');

    workspaces().startRename(const RenameTab(1));
    await tester.pumpAndSettle();
    await tester.enterText(field, '   ');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(tabs().tabs.single.label, 'vim');
  });

  testSidebar('F2 in the list renames; ⌥↓ moves the selected tab down '
      '(UI-A2 §8)', (tester) async {
    local
      ..add(local.summary(1, origin: SessionOrigin.desktop))
      ..add(local.summary(2, origin: SessionOrigin.desktop));
    await pumpSidebar(tester);
    // Put the keyboard in the list (Ctrl+F6 from the terminal, UI-A1 §3.6).
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.f6);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.pump();
    expect(sidebar().tabsOf(kDefaultWorkspaceId), [2, 1]);
    await tester.sendKeyEvent(LogicalKeyboardKey.f2);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('row.renameField')), findsOneWidget);
  });

  testSidebar('row menu: rename, move up/down enabled by position, one '
      'entry per port, Move to → New workspace (UI-A2 §5)', (tester) async {
    local
      ..add(local.summary(1, origin: SessionOrigin.desktop, ports: [3000]))
      ..add(local.summary(2, origin: SessionOrigin.desktop));
    await pumpSidebar(tester);
    await tester.tap(row(1), buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('menu.renameTab')), findsOneWidget);
    expect(find.byKey(const Key('menu.automaticName')), findsNothing);
    expect(find.byKey(const Key('menu.port.3000')), findsOneWidget);
    final up = tester.widget<PopupMenuItem<Object>>(
      find.byKey(const Key('menu.moveUp')),
    );
    expect(up.enabled, isFalse);
    await tester.tap(find.byKey(const Key('menu.moveTo')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('menu.moveTo.new')));
    await tester.pumpAndSettle();
    final ws = sidebar().workspaces.last.id;
    expect(sidebar().tabsOf(ws), [1]);
    expect(sidebar().renaming, RenameWorkspace(ws));
  });

  testSidebar('the row label reads branch, folder and ports (UI-A2 §8)', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    local.add(
      local.summary(
        1,
        origin: SessionOrigin.desktop,
        title: 'claude',
        cwd: '$testHome/work/shellx',
        gitBranch: 'main',
        ports: [3000, 5173],
      ),
    );
    await pumpSidebar(tester);
    expect(
      find.bySemanticsLabel(
        'claude, idle, branch main, folder ~/work/shellx, '
        'ports 3000, 5173, tab 1 of 1',
      ),
      findsOneWidget,
    );
    handle.dispose();
  });
}
```

Run:

`cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/ui/sidebar_rows_test.dart`
Expected: FAIL — no `row.contextLine`, no port links, no rename field.

- [ ] **Step 5: The row — context line, rename, menu hook, semantics**

In `apps/desktop/lib/src/ui/terminal/session_tab_row.dart` (imports: `package:flutter/foundation.dart`, `../../terminal/context_line.dart`, `inline_name_field.dart`):

Replace `heightFor` with:

```dart
  /// UI-A1 §1.3 / UI-A2 §1.3: max(30, 18·s + 12); with a context line
  /// max(46, 18·s + 14·s + 14).
  static double heightFor(TextScaler textScaler, {bool context = false}) =>
      context
      ? max(
          ShellxSizes.rowWithContext,
          textScaler.scale(ShellxSizes.rowTextLine) +
              textScaler.scale(ShellxSizes.contextLine) +
              2 * ShellxSizes.rowContextPadding +
              ShellxSizes.contextGap,
        )
      : max(
          ShellxSizes.row,
          textScaler.scale(ShellxSizes.rowTextLine) +
              ShellxSizes.rowTextPadding,
        );
```

Add parameters (all optional, so A1 call sites still compile):

```dart
    this.renaming = false,
    this.onStartRename,
    this.onRename,
    this.onCancelRename,
    this.onOpenPort,
    this.onMenu,
    this.positionLabel,
    this.extraActions = const {},
    this.home = '',
```

```dart
  /// UI-A2 §4: the name field replaces the title.
  final bool renaming;
  final VoidCallback? onStartRename;
  final void Function(String text)? onRename;
  final VoidCallback? onCancelRename;

  /// UI-A2 §2.4: a port link was clicked.
  final void Function(int port)? onOpenPort;

  /// The sidebar's row menu (UI-A2 §5.1) at a global position; null: the
  /// A1 menu.
  final void Function(Offset at)? onMenu;

  /// Replaces "tab i of n" (UI-A2 §8: "… in <workspace>").
  final String? positionLabel;

  /// More custom semantics actions (rename, move, ports — UI-A2 §8).
  final Map<CustomSemanticsAction, VoidCallback> extraActions;

  /// The user's home, for `~` (UI-A2 §2.3).
  final String home;
```

In the state add the double-click detector (a plain `onDoubleTap` would delay every single click by the double-tap timeout, and A1 switches tabs instantly):

```dart
  DateTime? _lastTap;

  void _onTap() {
    widget.onSelect();
    final now = DateTime.now();
    final last = _lastTap;
    if (last != null && now.difference(last) < kDoubleTapTimeout) {
      _lastTap = null;
      widget.onStartRename?.call();
    } else {
      _lastTap = now;
    }
  }
```

and use `onTap: _onTap` on the row's `GestureDetector`. `_menu` becomes:

```dart
  void _menu(Offset at) {
    final custom = widget.onMenu;
    if (custom != null) {
      custom(at);
    } else {
      showTabContextMenu(context: context, at: at, onClose: widget.onClose);
    }
  }
```

`_semanticsLabel` becomes:

```dart
  String _semanticsLabel(AppLocalizations l10n) {
    final tab = widget.tab;
    final windows = defaultTargetPlatform == TargetPlatform.windows;
    final parts = <String>[
      tab.label,
      if (tab.exited)
        l10n.sidebarStatusExited(tab.exitCode!)
      else if (tab.runningCommand)
        l10n.sidebarStatusRunning
      else
        l10n.sidebarStatusIdle,
      if (tab.gitBranch case final branch?) l10n.sidebarBranch(branch),
      if (tab.cwd case final cwd?)
        l10n.sidebarFolder(displayPath(cwd, home: widget.home, windows: windows)),
      if (tab.ports.isNotEmpty)
        l10n.sidebarPorts(tab.ports.length, tab.ports.join(', ')),
      if (tab.origin == SessionOrigin.phone) l10n.sidebarPhoneOriginSemantics,
      if (tab.phoneAttached)
        tab.driver == DriverSide.phone
            ? l10n.sidebarPhoneDrivingSemantics
            : l10n.sidebarPhoneViewingSemantics,
      widget.positionLabel ?? l10n.sidebarPosition(widget.position, widget.count),
    ];
    return parts.join(', ');
  }
```

`customSemanticsActions:` becomes `{CustomSemanticsAction(label: l10n.terminalCloseTab): widget.onClose, ...widget.extraActions}`.

In `build`, compute:

```dart
    final scaler = MediaQuery.textScalerOf(context);
    final withContext = tab.hasContext;
    final height = SessionTabRow.heightFor(scaler, context: withContext);
```

(replacing the A1 `final height = …` line). Keep `showClose` but make it `!widget.renaming && (_hover || widget.selected)`. Replace `Expanded(child: _Title(tab.label, titleStyle))` with:

```dart
                            Expanded(
                              child: widget.renaming
                                  ? InlineNameField(
                                      initial: tab.label,
                                      style: ShellxText.body,
                                      label: l10n.tabNameField,
                                      onCommit: (text) =>
                                          widget.onRename?.call(text),
                                      onCancel: () =>
                                          widget.onCancelRename?.call(),
                                    )
                                  : _Title(tab.label, titleStyle),
                            ),
```

Extract the existing title `Row(children: [dot, title, marks, close])` into a local `final titleRow = Row(...)` and replace the `Padding(... child: Column(...))` child of the `Stack` with:

```dart
                  if (!withContext)
                    Padding(
                      padding: rowPadding,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [titleRow],
                      ),
                    )
                  else ...[
                    Positioned(
                      left: 0,
                      right: 0,
                      // The title line's centre stays 6 + line/2 from the
                      // top; the box is as tall as the 24 px close button.
                      top: ShellxSizes.rowContextPadding +
                          titleLine / 2 -
                          titleBox / 2,
                      height: titleBox,
                      child: Padding(padding: rowPadding, child: titleRow),
                    ),
                    Positioned(
                      left: ShellxSizes.contextInset,
                      right: ShellxSpace.s8,
                      top: ShellxSizes.rowContextPadding +
                          titleLine +
                          ShellxSizes.contextGap -
                          (contextBox - contextLine) / 2,
                      height: contextBox,
                      child: _ContextLine(
                        tab: tab,
                        home: widget.home,
                        onOpenPort: widget.onOpenPort,
                      ),
                    ),
                  ],
```

with, before `return Semantics(...)`:

```dart
    const rowPadding = EdgeInsets.only(
      left: ShellxSpace.s8,
      right:
          ShellxSpace.s8 -
          (ShellxSizes.rowCloseHit - ShellxSizes.rowCloseVisual) / 2,
    );
    final titleLine = scaler.scale(ShellxSizes.rowTextLine);
    final titleBox = max(titleLine, ShellxSizes.rowCloseHit);
    final contextLine = scaler.scale(ShellxSizes.contextLine);
    final contextBox = max(contextLine, ShellxSizes.portHit);
```

Add the context line widgets at the end of the file:

```dart
/// UI-A2 §2: branch · ~/path · :ports, laid out by [layoutContextLine].
class _ContextLine extends StatelessWidget {
  const _ContextLine({
    required this.tab,
    required this.home,
    required this.onOpenPort,
  });

  final TerminalTab tab;
  final String home;
  final void Function(int port)? onOpenPort;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final windows = defaultTargetPlatform == TargetPlatform.windows;
    final style = ShellxText.caption.copyWith(
      color: ShellxDesktopColors.textSecondary,
    );
    final full = DefaultTextStyle.of(context).style.merge(style);
    final scaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);
    final path = tab.cwd == null
        ? null
        : displayPath(tab.cwd!, home: home, windows: windows);
    return LayoutBuilder(
      key: const Key('row.contextLine'),
      builder: (context, constraints) {
        final widths = <String, double>{};
        double measure(String text) => widths.putIfAbsent(text, () {
          final painter = TextPainter(
            text: TextSpan(text: text, style: full),
            textDirection: direction,
            textScaler: scaler,
            maxLines: 1,
          )..layout();
          final width = painter.width;
          painter.dispose();
          return width;
        });
        final layout = layoutContextLine(
          branch: tab.gitBranch,
          path: path,
          ports: tab.ports,
          width: constraints.maxWidth,
          measure: measure,
          windows: windows,
        );
        Widget text(String s) =>
            Text(s, style: style, maxLines: 1, softWrap: false);
        final children = <Widget>[];
        void separator() {
          if (children.isNotEmpty) children.add(text(' · '));
        }

        if (layout.branch case final branch?) children.add(text(branch));
        if (layout.path case final p?) {
          separator();
          children.add(text(p));
        }
        if (layout.ports.isNotEmpty) {
          separator();
          for (final (i, port) in layout.ports.indexed) {
            if (i > 0) children.add(const SizedBox(width: ShellxSizes.portGap));
            children.add(
              _PortLink(
                port: port,
                live: !tab.exited && onOpenPort != null,
                onOpen: onOpenPort,
              ),
            );
          }
          if (layout.morePorts > 0) {
            children
              ..add(const SizedBox(width: ShellxSizes.portGap))
              ..add(
                Tooltip(
                  message: l10n.portsMoreTooltip(tab.ports.join(', ')),
                  excludeFromSemantics: true,
                  positionDelegate: besideSidebar,
                  child: text('+${layout.morePorts}'),
                ),
              );
          }
        }
        Widget line = ClipRect(
          child: OverflowBox(
            alignment: Alignment.centerLeft,
            maxWidth: double.infinity,
            child: Row(mainAxisSize: MainAxisSize.min, children: children),
          ),
        );
        if (layout.truncated) {
          final whole = [
            ?tab.gitBranch,
            ?path,
            if (tab.ports.isNotEmpty) tab.ports.map((p) => ':$p').join(' '),
          ].join(' · ');
          line = Tooltip(
            message: whole,
            excludeFromSemantics: true,
            positionDelegate: besideSidebar,
            waitDuration: ShellxMotion.tooltipWait,
            constraints: const BoxConstraints(
              maxWidth: ShellxSizes.titleTooltipMaxWidth,
            ),
            child: line,
          );
        }
        return ExcludeSemantics(child: line);
      },
    );
  }
}

/// UI-A2 §2.4: `:3000` in `accent`, a 24 px hit area, underline + fill on
/// hover; plain `textSecondary` once the tab exited.
class _PortLink extends StatefulWidget {
  const _PortLink({required this.port, required this.live, this.onOpen});
  final int port;
  final bool live;
  final void Function(int port)? onOpen;

  @override
  State<_PortLink> createState() => _PortLinkState();
}

class _PortLinkState extends State<_PortLink> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final live = widget.live;
    final style = ShellxText.caption.copyWith(
      color: live
          ? ShellxDesktopColors.accent
          : ShellxDesktopColors.textSecondary,
      decoration: live && _hover ? TextDecoration.underline : null,
      decorationColor: ShellxDesktopColors.accent,
    );
    final box = AnimatedContainer(
      key: Key('port.${widget.port}'),
      duration: ShellxMotion.of(context, ShellxMotion.fast),
      curve: ShellxMotion.fastCurve,
      height: ShellxSizes.portHit,
      padding: const EdgeInsets.symmetric(horizontal: ShellxSizes.portPadH),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: live && _hover
            ? ShellxDesktopColors.rowPressed
            : Colors.transparent,
        borderRadius: BorderRadius.circular(ShellxRadius.r4),
      ),
      child: Text(':${widget.port}', style: style, maxLines: 1),
    );
    if (!live) return box;
    return Tooltip(
      message: AppLocalizations.of(context).portOpenTooltip(widget.port),
      excludeFromSemantics: true,
      positionDelegate: besideSidebar,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          // Wins the arena over the row's tap: a port click never selects.
          onTap: () => widget.onOpen?.call(widget.port),
          child: box,
        ),
      ),
    );
  }
}
```

- [ ] **Step 6: The sidebar — callbacks, menu, F2, ⌥↑/⌥↓, row heights**

In `apps/desktop/lib/src/ui/terminal/session_sidebar.dart` (imports: `dart:async`, `package:flutter/semantics.dart`, `../../agent/desktop_services.dart`, `../../terminal/local_sessions_provider.dart`, `../../terminal/sidebar_workspaces.dart`, `shellx_menu.dart`):

Add to `_SessionSidebarState`:

```dart
  static const _newWorkspace = '\u0000new';

  Future<void> _openPort(int port) async {
    try {
      await ref.read(desktopServicesProvider).urlOpener.openLocalPort(port);
    } catch (_) {
      if (mounted) {
        ref.read(terminalTabsProvider.notifier).showNotice(
          const PortOpenFailedNotice(),
        );
      }
    }
  }

  void _commitTabName(int id, String text) {
    ref.read(terminalTabsProvider.notifier).rename(id, text);
    ref.read(sidebarWorkspacesProvider.notifier).endRename();
  }

  /// After a keyboard move: say where the tab is now (UI-A2 §8).
  void _announceMove(TerminalTab tab) {
    final l10n = AppLocalizations.of(context);
    final s = ref.read(sidebarWorkspacesProvider);
    final ws = s.workspaceOf(tab.id);
    if (ws == null) return;
    final list = s.tabsOf(ws);
    final where = s.showHeaders
        ? l10n.sidebarPositionInWorkspace(
            list.indexOf(tab.id) + 1,
            list.length,
            ref.read(sidebarWorkspacesProvider.notifier).displayName(ws),
          )
        : l10n.sidebarPosition(list.indexOf(tab.id) + 1, list.length);
    unawaited(
      SemanticsService.sendAnnouncement(
        View.of(context),
        '${tab.label}, $where',
        Directionality.of(context),
      ),
    );
  }

  Future<void> _rowMenu(TerminalTab tab, Offset at) async {
    final l10n = AppLocalizations.of(context);
    final workspaces = ref.read(sidebarWorkspacesProvider.notifier);
    final ports = tab.exited ? const <int>[] : tab.ports.take(5).toList();
    final choice = await showShellxMenu<Object>(
      context: context,
      at: at,
      entries: [
        ShellxMenuEntry(
          key: const Key('menu.renameTab'),
          value: _RowAction.rename,
          label: l10n.tabRename,
          shortcut: renameShortcutLabel(),
        ),
        if (tab.customTitle != null)
          ShellxMenuEntry(
            key: const Key('menu.automaticName'),
            value: _RowAction.automaticName,
            label: l10n.tabUseAutomaticName,
          ),
        ShellxMenuEntry(
          key: const Key('menu.moveTo'),
          value: _RowAction.moveTo,
          label: l10n.tabMoveTo,
          dividerBefore: true,
        ),
        ShellxMenuEntry(
          key: const Key('menu.moveUp'),
          value: _RowAction.moveUp,
          label: l10n.tabMoveUp,
          shortcut: moveUpShortcutLabel(),
          enabled: workspaces.canMoveUp(tab.id),
        ),
        ShellxMenuEntry(
          key: const Key('menu.moveDown'),
          value: _RowAction.moveDown,
          label: l10n.tabMoveDown,
          shortcut: moveDownShortcutLabel(),
          enabled: workspaces.canMoveDown(tab.id),
        ),
        for (final (i, port) in ports.indexed)
          ShellxMenuEntry(
            key: Key('menu.port.$port'),
            value: port,
            label: l10n.tabOpenPort(port),
            dividerBefore: i == 0,
          ),
        ShellxMenuEntry(
          key: const Key('menu.closeTab'),
          value: _RowAction.close,
          label: l10n.terminalCloseTab,
          shortcut: closeTabShortcutLabel(),
          dividerBefore: true,
        ),
      ],
    );
    if (!mounted) return;
    switch (choice) {
      case _RowAction.rename:
        workspaces.startRename(RenameTab(tab.id));
      case _RowAction.automaticName:
        ref.read(terminalTabsProvider.notifier).rename(tab.id, null);
      case _RowAction.moveTo:
        await _moveToMenu(tab, at);
      case _RowAction.moveUp:
        workspaces.moveUp(tab.id);
        _announceMove(tab);
      case _RowAction.moveDown:
        workspaces.moveDown(tab.id);
        _announceMove(tab);
      case _RowAction.close:
        widget.onClose(tab);
      case final int port:
        await _openPort(port);
    }
  }

  /// UI-A2 §5.3.
  Future<void> _moveToMenu(TerminalTab tab, Offset at) async {
    final l10n = AppLocalizations.of(context);
    final s = ref.read(sidebarWorkspacesProvider);
    final from = s.workspaceOf(tab.id);
    final others = [
      for (final w in s.workspaces)
        if (w.id != from) w,
    ];
    final choice = await showShellxMenu<String>(
      context: context,
      at: at,
      entries: [
        for (final w in others)
          ShellxMenuEntry(
            key: Key('menu.moveTo.${w.id}'),
            value: w.id,
            label: w.displayName(l10n),
          ),
        ShellxMenuEntry(
          key: const Key('menu.moveTo.new'),
          value: _newWorkspace,
          label: l10n.workspaceNew,
          shortcut: newWorkspaceShortcutLabel(),
          dividerBefore: others.isNotEmpty,
        ),
      ],
    );
    if (choice == null || !mounted) return;
    final workspaces = ref.read(sidebarWorkspacesProvider.notifier);
    if (choice == _newWorkspace) {
      await workspaces.create(moveTab: tab.id);
    } else {
      workspaces.moveTab(tab.id, choice);
      _announceMove(tab);
    }
  }
```

and at file level:

```dart
enum _RowAction { rename, automaticName, moveTo, moveUp, moveDown, close }
```

In `_onKey`, before the "Plain keys only" check, add (Alt alone; ⌥ on macOS):

```dart
    final keyboard0 = HardwareKeyboard.instance;
    if (keyboard0.isAltPressed &&
        !keyboard0.isControlPressed &&
        !keyboard0.isMetaPressed &&
        !keyboard0.isShiftPressed &&
        (key == LogicalKeyboardKey.arrowUp ||
            key == LogicalKeyboardKey.arrowDown)) {
      final id = state.selectedId;
      final tab = id == null
          ? null
          : state.tabs.where((t) => t.id == id).firstOrNull;
      if (tab == null) return KeyEventResult.ignored;
      final workspaces = ref.read(sidebarWorkspacesProvider.notifier);
      if (key == LogicalKeyboardKey.arrowUp) {
        workspaces.moveUp(tab.id);
      } else {
        workspaces.moveDown(tab.id);
      }
      _announceMove(tab);
      return KeyEventResult.handled;
    }
```

and in the plain-key `switch` add:

```dart
      case LogicalKeyboardKey.f2:
        final id = state.selectedId;
        if (id == null) return KeyEventResult.ignored;
        ref.read(sidebarWorkspacesProvider.notifier).startRename(RenameTab(id));
```

In `_reveal`, replace the fixed-height arithmetic with summed heights:

```dart
    final scaler = MediaQuery.textScalerOf(context);
    final rows = _visibleTabs();
    final index = rows.indexWhere((t) => t.id == id);
    if (index < 0) return;
    var top = ShellxSizes.listTop;
    for (var i = 0; i < index; i++) {
      top += SessionTabRow.heightFor(scaler, context: rows[i].hasContext) +
          ShellxSizes.rowGap;
    }
    final bottom =
        top + SessionTabRow.heightFor(scaler, context: rows[index].hasContext);
```

(keep the rest of `_reveal` unchanged).

In `build`, pass to each `SessionTabRow`:

```dart
                          renaming: sidebar.renaming == RenameTab(tab.id),
                          home: ref.watch(homeDirectoryProvider),
                          onStartRename: () => ref
                              .read(sidebarWorkspacesProvider.notifier)
                              .startRename(RenameTab(tab.id)),
                          onRename: (text) => _commitTabName(tab.id, text),
                          onCancelRename: () => ref
                              .read(sidebarWorkspacesProvider.notifier)
                              .endRename(),
                          onOpenPort: _openPort,
                          onMenu: (at) => _rowMenu(tab, at),
                          extraActions: {
                            CustomSemanticsAction(label: l10n.tabRename): () =>
                                ref
                                    .read(sidebarWorkspacesProvider.notifier)
                                    .startRename(RenameTab(tab.id)),
                            CustomSemanticsAction(label: l10n.tabMoveTo): () =>
                                _moveToMenu(tab, _rowAnchor(tab.id)),
                            for (final port in tab.exited ? const <int>[] : tab.ports)
                              CustomSemanticsAction(
                                label: l10n.tabOpenPort(port),
                              ): () => _openPort(port),
                          },
```

with `final sidebar = ref.watch(sidebarWorkspacesProvider);` at the top of `build`, and:

```dart
  /// Below the row's left edge (where Shift+F10 opens menus).
  Offset _rowAnchor(int id) {
    final box =
        _rows[id]?.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return Offset.zero;
    return box.localToGlobal(Offset(ShellxSpace.s8, box.size.height));
  }
```

In `_openMenu(int id)` (Shift+F10) keep calling `_rows[id]?.currentState?.openMenu()` — `openMenu` now goes through `onMenu`, so the keyboard gets the new menu too.

The workspace page's selection listener already skips `focusTerminal` while a rename is open (Task 7), so a rename started by the second click of a double-click keeps the keyboard.

- [ ] **Step 7: Run the tests**

Run: `cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test`
Expected: PASS (A1 sidebar/menu tests included: `menu.closeTab` keeps its key).

- [ ] **Step 8: Format, analyze, commit**

```bash
cd apps/desktop
~/fvm/versions/3.41.4/bin/dart format --set-exit-if-changed lib test
PATH=~/fvm/versions/3.41.4/bin:$PATH flutter analyze
cd ../..
git add apps/desktop/lib/src/ui/theme/shellx_desktop_theme.dart apps/desktop/lib/src/terminal/context_line.dart apps/desktop/lib/src/ui/terminal/inline_name_field.dart apps/desktop/lib/src/ui/terminal/shellx_menu.dart apps/desktop/lib/src/ui/terminal/session_tab_row.dart apps/desktop/lib/src/ui/terminal/session_sidebar.dart apps/desktop/test/terminal/context_line_test.dart apps/desktop/test/ui/sidebar_test_harness.dart apps/desktop/test/ui/sidebar_rows_test.dart
git commit -m "feat(desktop): sidebar context line with port links, inline tab rename and the A2 row menu (C6, C7)"
```

---

### Task 9: Desktop — workspace headers, keyboard tree, drag-and-drop

The sidebar shows workspace headers (UI-A2 §3) once there are two workspaces, empty-workspace hints (§3.4), the header menu (§5.2), drag-and-drop with drop lines, header targets, auto-expand and auto-scroll (§6), and the keyboard tree (§8, D14).

**Files:**
- Create: `apps/desktop/lib/src/ui/terminal/workspace_header.dart`
- Modify: `apps/desktop/lib/src/ui/terminal/session_sidebar.dart`
- Create: `apps/desktop/test/ui/sidebar_workspaces_ui_test.dart`

**Interfaces:**
- Consumes: everything from Task 7 (`SidebarState`, `SidebarWorkspaces`, `Workspace`, `RenameWorkspace`, `kDefaultWorkspaceId`) and Task 8 (`InlineNameField`, `SessionTabRow` params, `showShellxMenu` with `dividerBefore`, `ShellxSizes`/`ShellxMotion` A2 constants, `sidebar_test_harness.dart`).
- Produces:
  - `class WorkspaceHeader extends StatefulWidget` — `WorkspaceHeader({Key? key, required String name, required int count, required bool collapsed, required bool containsSelected, required bool focused, required bool renaming, required bool dropTarget, required bool deletable, required VoidCallback onToggle, required VoidCallback onStartRename, required void Function(String) onRename, required VoidCallback onCancelRename, required VoidCallback onNewTab, required void Function(Offset at) onMenu, required VoidCallback onDelete})`, `static double heightFor(TextScaler)`
  - Widget keys: `ws.<workspaceId>` (header), `header.add`, `header.collapsedMark`, `empty.<workspaceId>` (the header's `InlineNameField` has the key `row.renameField`; tests find it under `ws.<id>`), `drop.line`, `menu.ws.newTab`, `menu.ws.rename`, `menu.ws.toggle`, `menu.ws.delete`

- [ ] **Step 1: Write the failing widget tests**

Create `apps/desktop/test/ui/sidebar_workspaces_ui_test.dart`:

```dart
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_desktop/src/terminal/sidebar_workspaces.dart';
import 'package:shellx_desktop/src/terminal/terminal_tabs.dart';
import 'package:shellx_desktop/src/ui/terminal/terminal_workspace_page.dart';
import 'package:shellx_desktop/src/ui/terminal/workspace_header.dart';
import 'package:shellx_desktop/src/ui/theme/shellx_desktop_theme.dart';

import 'sidebar_test_harness.dart';

Finder header(String id) => find.byKey(ValueKey('ws.$id'));

/// Default [1, 2] and "Workspace 2" [100] (selected).
Future<String> twoWorkspaces(WidgetTester tester) async {
  local
    ..add(local.summary(1, origin: SessionOrigin.desktop))
    ..add(local.summary(2, origin: SessionOrigin.desktop));
  await pumpSidebar(tester);
  await workspaces().create();
  workspaces().endRename();
  // No name field was built, so nothing handed the keyboard back yet.
  tester
      .state<TerminalWorkspacePageState>(find.byType(TerminalWorkspacePage))
      .focusTerminal();
  await tester.pumpAndSettle();
  return sidebar().workspaces.last.id;
}

Future<TestGesture> startDrag(WidgetTester tester, Finder from) async {
  final gesture = await tester.startGesture(
    tester.getCenter(from),
    kind: PointerDeviceKind.mouse,
  );
  await gesture.moveBy(const Offset(0, 8));
  await tester.pump();
  return gesture;
}

Future<void> hover(WidgetTester tester, TestGesture g, Offset at) async {
  await g.moveTo(at);
  await tester.pump();
  await g.moveTo(at + const Offset(0, 1));
  await tester.pump();
}

Future<void> sendChord(
  WidgetTester tester,
  List<LogicalKeyboardKey> held,
  LogicalKeyboardKey key,
) async {
  for (final k in held) {
    await tester.sendKeyDownEvent(k);
  }
  await tester.sendKeyEvent(key);
  for (final k in held.reversed) {
    await tester.sendKeyUpEvent(k);
  }
  await tester.pump();
}

void main() {
  setUpSidebar();

  testSidebar('one workspace looks like A1: no header (D10)', (tester) async {
    local.add(local.summary(1, origin: SessionOrigin.desktop));
    await pumpSidebar(tester);
    expect(find.byType(WorkspaceHeader), findsNothing);
    expect(row(1), findsOneWidget);
  });

  testSidebar('headers show name and count; a click collapses and hides '
      'the rows; a collapsed group holding the selected tab is marked '
      '(UI-A2 §3)', (tester) async {
    final ws = await twoWorkspaces(tester);
    final def = header(kDefaultWorkspaceId);
    expect(find.descendant(of: def, matching: find.text('Default')), findsOneWidget);
    expect(find.descendant(of: def, matching: find.text('2')), findsOneWidget);
    expect(
      find.descendant(of: header(ws), matching: find.text('Workspace 2')),
      findsOneWidget,
    );
    expect(tester.getSize(def).height, ShellxSizes.workspaceHeader);
    container.read(terminalTabsProvider.notifier).select(1);
    await tester.pump();
    await tester.tap(find.descendant(of: def, matching: find.text('Default')));
    await tester.pump(kDoubleTapTimeout);
    await tester.pumpAndSettle();
    expect(sidebar().workspace(kDefaultWorkspaceId)!.collapsed, isTrue);
    expect(row(1), findsNothing);
    expect(find.byKey(const Key('header.collapsedMark')), findsOneWidget);
    expect(tabs().selectedId, 1); // the terminal still shows it
  });

  testSidebar('double-click on the name renames the workspace; Enter keeps',
      (tester) async {
    final ws = await twoWorkspaces(tester);
    final name = find.descendant(of: header(ws), matching: find.text('Workspace 2'));
    await tester.tap(name);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(name);
    await tester.pumpAndSettle();
    final field = find.descendant(
      of: header(ws),
      matching: find.byKey(const Key('row.renameField')),
    );
    expect(field, findsOneWidget);
    await tester.enterText(field, 'Backend');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(sidebar().workspace(ws)!.name, 'Backend');
    expect(sidebar().workspace(ws)!.collapsed, isFalse); // no toggle
  });

  testSidebar('header menu: Delete is disabled for Default; deleting moves '
      'the tabs and shows the neutral toast (D11, D16)', (tester) async {
    final ws = await twoWorkspaces(tester);
    await tester.tap(header(kDefaultWorkspaceId), buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    final delete = tester.widget<PopupMenuItem<Object?>>(
      find.byKey(const Key('menu.ws.delete')),
    );
    expect(delete.enabled, isFalse);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await tester.tap(header(ws), buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('menu.ws.delete')));
    await tester.pumpAndSettle();
    expect(sidebar().workspaces, hasLength(1));
    expect(sidebar().tabsOf(kDefaultWorkspaceId), [1, 2, 100]);
    expect(
      find.text('Deleted workspace “Workspace 2”. Its tabs moved to Default.'),
      findsOneWidget,
    );
    expect(find.byType(WorkspaceHeader), findsNothing);
  });

  testSidebar('the header + (shown on hover) opens a tab in that workspace',
      (tester) async {
    final ws = await twoWorkspaces(tester);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: tester.getCenter(header(ws)));
    await tester.pump();
    await tester.tap(
      find.descendant(of: header(ws), matching: find.byKey(const Key('header.add'))),
    );
    await tester.pumpAndSettle();
    expect(sidebar().tabsOf(ws), hasLength(2));
    await mouse.removePointer();
  });

  testSidebar('dragging a row onto the lower half of another reorders it; a '
      'drop line shows meanwhile (D18, UI-A2 §6)', (tester) async {
    await twoWorkspaces(tester);
    final g = await startDrag(tester, row(1));
    await hover(tester, g, tester.getBottomLeft(row(2)) + const Offset(30, -4));
    expect(find.byKey(const Key('drop.line')), findsOneWidget);
    await g.up();
    await tester.pumpAndSettle();
    expect(sidebar().tabsOf(kDefaultWorkspaceId), [2, 1]);
    expect(find.byKey(const Key('drop.line')), findsNothing);
  });

  testSidebar('dragging onto a collapsed header expands it after 600 ms and '
      'drops at its end', (tester) async {
    final ws = await twoWorkspaces(tester);
    workspaces().setCollapsed(ws, true);
    await tester.pumpAndSettle();
    final g = await startDrag(tester, row(1));
    await hover(tester, g, tester.getCenter(header(ws)));
    await tester.pump(const Duration(milliseconds: 650));
    expect(sidebar().workspace(ws)!.collapsed, isFalse);
    await hover(tester, g, tester.getCenter(header(ws)));
    await g.up();
    await tester.pumpAndSettle();
    expect(sidebar().tabsOf(ws), [100, 1]);
  });

  testSidebar('an empty workspace shows its hint and accepts a drop', (
    tester,
  ) async {
    final ws = await twoWorkspaces(tester);
    workspaces().moveTab(100, kDefaultWorkspaceId);
    await tester.pumpAndSettle();
    final hint = find.byKey(ValueKey('empty.$ws'));
    expect(
      find.descendant(
        of: hint,
        matching: find.text('Empty. Drag a tab here or press +.'),
      ),
      findsOneWidget,
    );
    final g = await startDrag(tester, row(2));
    await hover(tester, g, tester.getCenter(hint));
    await g.up();
    await tester.pumpAndSettle();
    expect(sidebar().tabsOf(ws), [2]);
  });

  testSidebar('keyboard tree: ↑ from a group\'s first row reaches its header '
      'without changing the tab; Enter collapses, → expands, ↑ selects the '
      'row above (D14)', (tester) async {
    final ws = await twoWorkspaces(tester); // tab 100 selected
    await sendChord(tester, [LogicalKeyboardKey.controlLeft], LogicalKeyboardKey.f6);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(tabs().selectedId, 100);
    expect(
      find.byWidgetPredicate((w) => w is WorkspaceHeader && w.focused),
      findsOneWidget,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(sidebar().workspace(ws)!.collapsed, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(sidebar().workspace(ws)!.collapsed, isFalse);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(tabs().selectedId, 2);
  });

  testSidebar('⌘⇧N opens the new header\'s name field; Enter names it and '
      'gives the keyboard back to the terminal (D15)', (tester) async {
    local.add(local.summary(1, origin: SessionOrigin.desktop));
    await pumpSidebar(tester);
    await sendChord(tester, [
      LogicalKeyboardKey.metaLeft,
      LogicalKeyboardKey.shiftLeft,
    ], LogicalKeyboardKey.keyN);
    await tester.pumpAndSettle();
    final ws = sidebar().workspaces.last.id;
    final field = find.descendant(
      of: header(ws),
      matching: find.byKey(const Key('row.renameField')),
    );
    expect(field, findsOneWidget);
    await tester.enterText(field, 'Ops');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(sidebar().workspace(ws)!.name, 'Ops');
    expect(FocusManager.instance.primaryFocus?.debugLabel, isNot('inline name'));
  });

  testSidebar('header semantics: name, count, expanded state (UI-A2 §8)', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await twoWorkspaces(tester);
    expect(find.bySemanticsLabel('Workspace Default, 2 tabs'), findsOneWidget);
    expect(
      find.bySemanticsLabel(RegExp(r'tab 1 of 2 in Default$')),
      findsOneWidget,
    );
    handle.dispose();
  });
}
```

Run: `cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/ui/sidebar_workspaces_ui_test.dart`
Expected: FAIL — `workspace_header.dart` does not exist.

- [ ] **Step 2: Write `WorkspaceHeader`**

Create `apps/desktop/lib/src/ui/terminal/workspace_header.dart`:

```dart
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../../../l10n/app_localizations.dart';
import '../theme/shellx_desktop_theme.dart';
import 'inline_name_field.dart';

/// UI-A2 §3: a workspace's header row — chevron, name, tab count, `+` on
/// hover/focus; click toggles, double-click renames, secondary click /
/// Shift+F10 opens the menu (the sidebar owns the menu and the keys).
class WorkspaceHeader extends StatefulWidget {
  const WorkspaceHeader({
    super.key,
    required this.name,
    required this.count,
    required this.collapsed,
    required this.containsSelected,
    required this.focused,
    required this.renaming,
    required this.dropTarget,
    required this.deletable,
    required this.onToggle,
    required this.onStartRename,
    required this.onRename,
    required this.onCancelRename,
    required this.onNewTab,
    required this.onMenu,
    required this.onDelete,
  });

  final String name;
  final int count;
  final bool collapsed;

  /// Collapsed and holding the selected tab: accent mark, brighter name.
  final bool containsSelected;

  /// Keyboard focus ring (the list's cursor is on this header, D14).
  final bool focused;
  final bool renaming;

  /// A dragged tab is over this header (UI-A2 §3.2).
  final bool dropTarget;
  final bool deletable;
  final VoidCallback onToggle;
  final VoidCallback onStartRename;
  final void Function(String text) onRename;
  final VoidCallback onCancelRename;
  final VoidCallback onNewTab;
  final void Function(Offset at) onMenu;
  final VoidCallback onDelete;

  /// UI-A2 §1.3: max(28, 16·s + 12).
  static double heightFor(TextScaler scaler) => max(
    ShellxSizes.workspaceHeader,
    scaler.scale(ShellxSizes.workspaceHeaderText) + 12,
  );

  @override
  State<WorkspaceHeader> createState() => WorkspaceHeaderState();
}

class WorkspaceHeaderState extends State<WorkspaceHeader> {
  bool _hover = false;
  bool _pressed = false;

  /// Shift+F10 from the sidebar: the menu under the header's left edge.
  void openMenu() {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    widget.onMenu(box.localToGlobal(Offset(ShellxSpace.s8, box.size.height)));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scaler = MediaQuery.textScalerOf(context);
    final height = WorkspaceHeader.heightFor(scaler);
    final nameStyle = ShellxText.small.copyWith(
      fontWeight: FontWeight.w600,
      color: widget.containsSelected
          ? ShellxDesktopColors.textPrimary
          : ShellxDesktopColors.textSecondary,
    );
    final background = widget.dropTarget
        ? ShellxDesktopColors.primarySoft
        : _pressed
        ? ShellxDesktopColors.rowPressed
        : _hover
        ? ShellxDesktopColors.rowHover
        : Colors.transparent;
    final showAdd = !widget.renaming && (_hover || widget.focused);
    final label = [
      l10n.workspaceHeaderSemantics(widget.name, widget.count),
      if (widget.containsSelected) l10n.workspaceContainsSelected,
    ].join(', ');

    return Semantics(
      header: true,
      button: true,
      expanded: !widget.collapsed,
      label: label,
      onTap: widget.onToggle,
      customSemanticsActions: {
        CustomSemanticsAction(label: l10n.workspaceRename): widget.onStartRename,
        CustomSemanticsAction(label: l10n.workspaceNewTab): widget.onNewTab,
        if (widget.deletable)
          CustomSemanticsAction(label: l10n.workspaceDelete): widget.onDelete,
      },
      excludeSemantics: !widget.renaming,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          // onDoubleTap delays a single click by the double-tap timeout:
          // accepted here (UI-A2 §3.3) — collapsing is not as time-critical
          // as switching tabs, and the first click must not collapse.
          onTap: widget.renaming ? null : widget.onToggle,
          onDoubleTap: widget.renaming ? null : widget.onStartRename,
          onTapDown: (_) => setState(() => _pressed = true),
          onTapUp: (_) => setState(() => _pressed = false),
          onTapCancel: () => setState(() => _pressed = false),
          onSecondaryTapUp: (d) => widget.onMenu(d.globalPosition),
          child: AnimatedContainer(
            duration: ShellxMotion.of(context, ShellxMotion.fast),
            curve: ShellxMotion.fastCurve,
            height: height,
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(ShellxRadius.r6),
              border: widget.dropTarget
                  ? Border.all(color: ShellxDesktopColors.accent)
                  : null,
            ),
            foregroundDecoration: widget.focused
                ? BoxDecoration(
                    borderRadius: BorderRadius.circular(ShellxRadius.r6),
                    border: Border.all(
                      color: ShellxDesktopColors.accent,
                      width: ShellxSizes.focusRing,
                    ),
                  )
                : null,
            child: Stack(
              children: [
                if (widget.collapsed && widget.containsSelected)
                  Positioned(
                    left: 0,
                    top: (height - ShellxSizes.collapsedMarkHeight) / 2,
                    child: Container(
                      key: const Key('header.collapsedMark'),
                      width: ShellxSizes.selectedBarWidth,
                      height: ShellxSizes.collapsedMarkHeight,
                      decoration: BoxDecoration(
                        color: ShellxDesktopColors.accent,
                        borderRadius: BorderRadius.circular(ShellxRadius.r4),
                      ),
                    ),
                  ),
                Row(
                  children: [
                    const SizedBox(width: ShellxSpace.s4),
                    SizedBox(
                      width: ShellxSizes.chevronHit,
                      child: AnimatedRotation(
                        turns: widget.collapsed ? 0 : 0.25,
                        duration: ShellxMotion.of(context, ShellxMotion.base),
                        curve: ShellxMotion.baseCurve,
                        child: const Icon(
                          Icons.chevron_right,
                          size: ShellxSizes.mark,
                          color: ShellxDesktopColors.textSecondary,
                        ),
                      ),
                    ),
                    const SizedBox(width: ShellxSpace.s4),
                    Expanded(
                      child: widget.renaming
                          ? InlineNameField(
                              initial: widget.name,
                              style: nameStyle,
                              label: l10n.workspaceNameField,
                              onCommit: widget.onRename,
                              onCancel: widget.onCancelRename,
                            )
                          : Text(
                              widget.name,
                              style: nameStyle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                    ),
                    const SizedBox(width: ShellxSpace.s4),
                    Visibility(
                      visible: !widget.renaming,
                      maintainSize: true,
                      maintainAnimation: true,
                      maintainState: true,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                          minWidth: ShellxSizes.headerCountMin,
                        ),
                        child: Text(
                          '${widget.count}',
                          textAlign: TextAlign.right,
                          style: ShellxText.caption.copyWith(
                            color: ShellxDesktopColors.textSecondary,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: ShellxSpace.s2),
                    Visibility(
                      visible: showAdd,
                      maintainSize: true,
                      maintainAnimation: true,
                      maintainState: true,
                      child: _HeaderAdd(
                        tooltip: l10n.workspaceNewTab,
                        onPressed: widget.onNewTab,
                      ),
                    ),
                    const SizedBox(width: ShellxSpace.s4),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// UI-A2 §3.1 `+`: 24 hit, 20 visual (`r4`), `Icons.add` 14.
class _HeaderAdd extends StatefulWidget {
  const _HeaderAdd({required this.tooltip, required this.onPressed});
  final String tooltip;
  final VoidCallback onPressed;

  @override
  State<_HeaderAdd> createState() => _HeaderAddState();
}

class _HeaderAddState extends State<_HeaderAdd> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: widget.tooltip,
    excludeFromSemantics: true,
    child: MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        key: const Key('header.add'),
        behavior: HitTestBehavior.opaque,
        onTap: widget.onPressed,
        child: SizedBox.square(
          dimension: ShellxSizes.headerAddHit,
          child: Center(
            child: AnimatedContainer(
              duration: ShellxMotion.of(context, ShellxMotion.fast),
              width: ShellxSizes.headerAddVisual,
              height: ShellxSizes.headerAddVisual,
              decoration: BoxDecoration(
                color: _hover
                    ? ShellxDesktopColors.rowPressed
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(ShellxRadius.r4),
              ),
              child: Icon(
                Icons.add,
                size: ShellxSizes.mark,
                color: _hover
                    ? ShellxDesktopColors.textPrimary
                    : ShellxDesktopColors.textSecondary,
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
```

(`Icons.chevron_right` turned a quarter is the "expanded" chevron of UI-A2 §3.1, so one icon animates between both states.)

- [ ] **Step 3: The sidebar — items, headers, empty hints**

In `apps/desktop/lib/src/ui/terminal/session_sidebar.dart` (import `dart:math`, `workspace_header.dart`), add at file level:

```dart
/// What the list shows, top to bottom (UI-A2 §3, §3.4).
sealed class _Item {
  const _Item();
}

final class _HeaderItem extends _Item {
  const _HeaderItem(this.workspace, this.count, this.containsSelected);
  final Workspace workspace;
  final int count;
  final bool containsSelected;
}

final class _RowItem extends _Item {
  const _RowItem(this.tab, this.workspaceId, this.index, this.count);
  final TerminalTab tab;
  final String workspaceId;

  /// Place in its workspace, and the workspace's tab count.
  final int index;
  final int count;
}

final class _EmptyItem extends _Item {
  const _EmptyItem(this.workspaceId);
  final String workspaceId;
}

enum _HeaderAction { newTab, rename, toggle, delete }

/// UI-A2 §6: 2 px `accent`, radius 1.
class _DropLine extends StatelessWidget {
  const _DropLine();
  @override
  Widget build(BuildContext context) => Container(
    key: const Key('drop.line'),
    height: ShellxSizes.dropLine,
    decoration: BoxDecoration(
      color: ShellxDesktopColors.accent,
      borderRadius: BorderRadius.circular(ShellxSizes.dropLine / 2),
    ),
  );
}

/// UI-A2 §6 drag feedback: the row's title on a lifted `rowSelected` card.
class _DragFeedback extends StatelessWidget {
  const _DragFeedback(this.tab);
  final TerminalTab tab;

  @override
  Widget build(BuildContext context) => Material(
    type: MaterialType.transparency,
    child: Opacity(
      opacity: 0.92,
      child: Container(
        width: ShellxSizes.sidebarWidth - 2 * ShellxSizes.listMarginH,
        height: ShellxSizes.row,
        padding: const EdgeInsets.symmetric(horizontal: ShellxSpace.s8),
        alignment: Alignment.centerLeft,
        decoration: BoxDecoration(
          color: ShellxDesktopColors.rowSelected,
          border: Border.all(color: ShellxDesktopColors.border),
          borderRadius: BorderRadius.circular(ShellxRadius.r6),
          boxShadow: ShellxShadows.e1,
        ),
        child: Text(
          tab.label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: ShellxText.body.copyWith(
            color: ShellxDesktopColors.textPrimary,
          ),
        ),
      ),
    ),
  );
}
```

Add state to `_SessionSidebarState`:

```dart
  /// D14: the list's keyboard cursor is on this workspace header (null:
  /// on the selected row, as in A1).
  String? _headerCursor;

  /// A rename started from the keyboard returns the keyboard to the list.
  bool _renameFromList = false;

  /// UI-A2 §6 drag state: the slot (workspace, index) under the pointer,
  /// or a header / empty hint (`empty.<id>`) under it.
  (String, int)? _drop;
  String? _dropTarget;
  bool _dragging = false;
  Timer? _scrollTimer;
  Timer? _expandTimer;
  double _scrollVelocity = 0;
  final _listKey = GlobalKey();
  final _headerKeys = <String, GlobalKey<WorkspaceHeaderState>>{};
```

Change `_refresh` to drop the header cursor when the list loses the keyboard:

```dart
  void _refresh() {
    if (!widget.focusNode.hasFocus) _headerCursor = null;
    if (mounted) setState(() {});
  }
```

and cancel the timers in `dispose()` (`_scrollTimer?.cancel(); _expandTimer?.cancel();`).

Add:

```dart
  List<_Item> _items() {
    final s = ref.read(sidebarWorkspacesProvider);
    final tabsState = ref.read(terminalTabsProvider);
    final byId = {for (final t in tabsState.tabs) t.id: t};
    final items = <_Item>[];
    for (final w in s.workspaces) {
      final tabs = [
        for (final id in s.tabsOf(w.id)) ?byId[id],
      ];
      if (s.showHeaders) {
        items.add(
          _HeaderItem(
            w,
            tabs.length,
            w.collapsed && tabs.any((t) => t.id == tabsState.selectedId),
          ),
        );
        if (w.collapsed) continue;
        if (tabs.isEmpty) {
          items.add(_EmptyItem(w.id));
          continue;
        }
      }
      for (final (i, tab) in tabs.indexed) {
        items.add(_RowItem(tab, w.id, i, tabs.length));
      }
    }
    return items;
  }

  /// Space above item [i]: 8 above a header (none for the first item),
  /// else the A1 row gap.
  double _gapBefore(List<_Item> items, int i) => i == 0
      ? 0
      : items[i] is _HeaderItem
      ? ShellxSizes.workspaceHeaderTop
      : ShellxSizes.rowGap;

  double _extent(_Item item, TextScaler scaler) => switch (item) {
    _HeaderItem() => WorkspaceHeader.heightFor(scaler),
    _RowItem(:final tab) => SessionTabRow.heightFor(
      scaler,
      context: tab.hasContext,
    ),
    _EmptyItem() => max(
      ShellxSizes.emptyWorkspaceRow,
      scaler.scale(ShellxSizes.contextLine) + 16,
    ),
  };

  /// Headers and rows the keyboard walks (D14): workspace ids and tab ids.
  List<Object> _navigation() => [
    for (final item in _items())
      switch (item) {
        _HeaderItem(:final workspace) => workspace.id,
        _RowItem(:final tab) => tab.id,
        _EmptyItem() => null,
      },
  ].nonNulls.toList();
```

Rewrite `_reveal` to walk the items (rows have different heights, headers sit between them):

```dart
  /// Scrolls the item of [target] (a tab id, or a workspace id for a
  /// header) fully into view.
  void _reveal(Object target, {int retries = 2}) {
    final controller = widget.scrollController;
    if (!mounted || !controller.hasClients) return;
    final scaler = MediaQuery.textScalerOf(context);
    final items = _items();
    var top = ShellxSizes.listTop;
    double? found;
    double extent = 0;
    for (final (i, item) in items.indexed) {
      top += _gapBefore(items, i);
      extent = _extent(item, scaler);
      final matches = switch (item) {
        _HeaderItem(:final workspace) => workspace.id == target,
        _RowItem(:final tab) => tab.id == target,
        _EmptyItem() => false,
      };
      if (matches) {
        found = top;
        break;
      }
      top += extent;
    }
    if (found == null) return;
    final bottom = found + extent;
    final position = controller.position;
    final viewport = position.viewportDimension;
    double? jump;
    if (found - ShellxSizes.listTop < position.pixels) {
      jump = found - ShellxSizes.listTop;
    } else if (bottom + ShellxSizes.listBottom > position.pixels + viewport) {
      jump = bottom + ShellxSizes.listBottom - viewport;
    }
    if (jump == null) return;
    controller.jumpTo(
      jump.clamp(position.minScrollExtent, position.maxScrollExtent),
    );
    if (jump > position.maxScrollExtent && retries > 0) {
      WidgetsBinding.instance
        ..addPostFrameCallback((_) => _reveal(target, retries: retries - 1))
        ..ensureVisualUpdate();
    }
  }
```

(Task 8's summed-height `_reveal` is replaced by this one; `_visibleTabs()` stays for End.)

- [ ] **Step 4: The sidebar — header menu, rename focus, drag-and-drop**

Add:

```dart
  Offset _headerAnchor(String id) {
    final box =
        _headerKeys[id]?.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return Offset.zero;
    return box.localToGlobal(Offset(ShellxSpace.s8, box.size.height));
  }

  Future<void> _headerMenu(Workspace w, Offset at) async {
    final l10n = AppLocalizations.of(context);
    final choice = await showShellxMenu<_HeaderAction>(
      context: context,
      at: at,
      entries: [
        ShellxMenuEntry(
          key: const Key('menu.ws.newTab'),
          value: _HeaderAction.newTab,
          label: l10n.workspaceNewTab,
        ),
        ShellxMenuEntry(
          key: const Key('menu.ws.rename'),
          value: _HeaderAction.rename,
          label: l10n.workspaceRename,
          shortcut: renameShortcutLabel(),
        ),
        ShellxMenuEntry(
          key: const Key('menu.ws.toggle'),
          value: _HeaderAction.toggle,
          label: w.collapsed ? l10n.workspaceExpand : l10n.workspaceCollapse,
          shortcut: w.collapsed ? '→' : '←',
        ),
        ShellxMenuEntry(
          key: const Key('menu.ws.delete'),
          value: _HeaderAction.delete,
          label: l10n.workspaceDelete,
          enabled: !w.isDefault,
          dividerBefore: true,
        ),
      ],
    );
    if (!mounted || choice == null) return;
    final workspaces = ref.read(sidebarWorkspacesProvider.notifier);
    switch (choice) {
      case _HeaderAction.newTab:
        await workspaces.openTabIn(w.id);
      case _HeaderAction.rename:
        workspaces.startRename(RenameWorkspace(w.id));
      case _HeaderAction.toggle:
        workspaces.toggleCollapsed(w.id);
      case _HeaderAction.delete:
        workspaces.delete(w.id);
    }
  }

  /// UI-A2 §4: the keyboard goes back where the rename started.
  void _afterRename() {
    final fromList = _renameFromList;
    _renameFromList = false;
    if (fromList) {
      widget.focusNode.requestFocus();
    } else {
      widget.onEscape(); // the terminal
    }
  }

  // ---- drag and drop (UI-A2 §6) ---------------------------------------

  void _dragStarted() => setState(() => _dragging = true);

  void _stopDrag() {
    _scrollTimer?.cancel();
    _scrollTimer = null;
    _expandTimer?.cancel();
    _expandTimer = null;
    if (!mounted) return;
    setState(() {
      _dragging = false;
      _drop = null;
      _dropTarget = null;
    });
  }

  void _autoScroll(Offset global) {
    final box = _listKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final y = box.globalToLocal(global).dy;
    const zone = ShellxSizes.dragAutoScrollZone;
    _scrollVelocity = y < zone
        ? -ShellxSizes.dragAutoScrollSpeed
        : y > box.size.height - zone
        ? ShellxSizes.dragAutoScrollSpeed
        : 0;
    if (_scrollVelocity == 0) {
      _scrollTimer?.cancel();
      _scrollTimer = null;
      return;
    }
    _scrollTimer ??= Timer.periodic(const Duration(milliseconds: 16), (_) {
      final controller = widget.scrollController;
      if (!controller.hasClients) return;
      final p = controller.position;
      controller.jumpTo(
        (p.pixels + _scrollVelocity * 0.016).clamp(
          p.minScrollExtent,
          p.maxScrollExtent,
        ),
      );
    });
  }

  void _hoverRow(_RowItem item, Offset global) {
    final box =
        _rows[item.tab.id]?.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final before = box.globalToLocal(global).dy < box.size.height / 2;
    final slot = (item.workspaceId, item.index + (before ? 0 : 1));
    if (slot != _drop || _dropTarget != null) {
      setState(() {
        _drop = slot;
        _dropTarget = null;
      });
    }
  }

  void _hoverTarget(String target, {Workspace? collapsedHeader}) {
    if (_dropTarget == target) return;
    _expandTimer?.cancel();
    _expandTimer = null;
    final header = collapsedHeader;
    if (header != null && header.collapsed) {
      _expandTimer = Timer(ShellxMotion.dragExpandDelay, () {
        if (mounted) {
          ref
              .read(sidebarWorkspacesProvider.notifier)
              .setCollapsed(header.id, false);
        }
      });
    }
    setState(() {
      _dropTarget = target;
      _drop = null;
    });
  }

  void _leaveTarget(String target) {
    if (_dropTarget != target) return;
    _expandTimer?.cancel();
    _expandTimer = null;
    setState(() => _dropTarget = null);
  }

  /// A tab closed mid-drag is simply not moved (moveTab ignores it).
  void _dropAt(int tabId, String workspaceId, [int? index]) {
    ref
        .read(sidebarWorkspacesProvider.notifier)
        .moveTab(tabId, workspaceId, index);
    _stopDrag();
  }

  Widget _draggable(TerminalTab tab, Widget row) => Draggable<int>(
    data: tab.id,
    dragAnchorStrategy: pointerDragAnchorStrategy,
    feedback: _DragFeedback(tab),
    childWhenDragging: Opacity(
      opacity: ShellxDesktopColors.disabledOpacity,
      child: row,
    ),
    onDragStarted: _dragStarted,
    onDragUpdate: (d) => _autoScroll(d.globalPosition),
    onDragEnd: (_) => _stopDrag(),
    onDraggableCanceled: (_, _) => _stopDrag(),
    child: row,
  );

  Widget _rowTarget(_RowItem item, Widget child) => DragTarget<int>(
    onMove: (d) => _hoverRow(item, d.offset),
    onAcceptWithDetails: (d) {
      final drop = _drop;
      if (drop != null) {
        _dropAt(d.data, drop.$1, drop.$2);
      } else {
        _stopDrag();
      }
    },
    builder: (context, _, _) {
      final drop = _drop;
      final here = drop != null && drop.$1 == item.workspaceId;
      final before = here && drop.$2 == item.index;
      final after =
          here && drop.$2 == item.count && item.index == item.count - 1;
      return Stack(
        clipBehavior: Clip.none,
        children: [
          child,
          if (before)
            const Positioned(
              left: 0,
              right: 0,
              top: -ShellxSizes.dropLine,
              child: _DropLine(),
            ),
          if (after)
            const Positioned(
              left: 0,
              right: 0,
              bottom: -ShellxSizes.dropLine,
              child: _DropLine(),
            ),
        ],
      );
    },
  );
```

- [ ] **Step 5: The sidebar — keys (D14) and `build`**

Replace `_onKey` with:

```dart
  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    final state = ref.read(terminalTabsProvider);
    final s = ref.read(sidebarWorkspacesProvider);
    final workspaces = ref.read(sidebarWorkspacesProvider.notifier);
    final keyboard = HardwareKeyboard.instance;
    final cursor = _headerCursor;
    final header = cursor == null ? null : s.workspace(cursor);
    final menu =
        key == LogicalKeyboardKey.contextMenu ||
        (key == LogicalKeyboardKey.f10 && keyboard.isShiftPressed);
    if (menu) {
      if (event is KeyRepeatEvent) return KeyEventResult.handled;
      if (header != null) {
        _headerMenu(header, _headerAnchor(header.id));
        return KeyEventResult.handled;
      }
      final id = state.selectedId;
      if (id == null) return KeyEventResult.ignored;
      _openMenu(id);
      return KeyEventResult.handled;
    }
    final alone =
        !keyboard.isControlPressed &&
        !keyboard.isMetaPressed &&
        !keyboard.isShiftPressed;
    if (keyboard.isAltPressed &&
        alone &&
        (key == LogicalKeyboardKey.arrowUp ||
            key == LogicalKeyboardKey.arrowDown)) {
      if (header != null) return KeyEventResult.handled; // headers stay
      final id = state.selectedId;
      final tab = id == null
          ? null
          : state.tabs.where((t) => t.id == id).firstOrNull;
      if (tab == null) return KeyEventResult.ignored;
      if (key == LogicalKeyboardKey.arrowUp) {
        workspaces.moveUp(tab.id);
      } else {
        workspaces.moveDown(tab.id);
      }
      _announceMove(tab);
      WidgetsBinding.instance.addPostFrameCallback((_) => _reveal(tab.id));
      return KeyEventResult.handled;
    }
    if (!alone || keyboard.isAltPressed) return KeyEventResult.ignored;

    final nav = s.showHeaders ? _navigation() : const <Object>[];
    final at = header != null
        ? nav.indexOf(header.id)
        : nav.indexOf(state.selectedId ?? -1);
    void go(int i) {
      if (nav.isEmpty) return;
      final target = nav[i.clamp(0, nav.length - 1)];
      if (target is String) {
        setState(() => _headerCursor = target);
      } else {
        setState(() => _headerCursor = null);
        ref.read(terminalTabsProvider.notifier).select(target as int);
      }
      WidgetsBinding.instance.addPostFrameCallback((_) => _reveal(target));
    }

    switch (key) {
      case LogicalKeyboardKey.arrowDown:
        s.showHeaders ? go(at < 0 ? 0 : at + 1) : workspaces.step(1);
      case LogicalKeyboardKey.arrowUp:
        s.showHeaders ? go(at < 0 ? 0 : at - 1) : workspaces.step(-1);
      case LogicalKeyboardKey.home:
        s.showHeaders ? go(0) : workspaces.selectVisible(1);
      case LogicalKeyboardKey.end:
        s.showHeaders
            ? go(nav.length - 1)
            : workspaces.selectVisible(_visibleTabs().length);
      case LogicalKeyboardKey.arrowLeft:
        if (!s.showHeaders) return KeyEventResult.ignored;
        if (header == null) {
          final ws = s.workspaceOf(state.selectedId ?? -1);
          if (ws != null) setState(() => _headerCursor = ws);
        } else if (!header.collapsed) {
          workspaces.setCollapsed(header.id, true);
        }
      case LogicalKeyboardKey.arrowRight:
        if (header == null) return KeyEventResult.ignored;
        if (header.collapsed) {
          workspaces.setCollapsed(header.id, false);
        } else if (s.tabsOf(header.id).firstOrNull case final first?) {
          go(nav.indexOf(first));
        }
      case LogicalKeyboardKey.enter ||
          LogicalKeyboardKey.numpadEnter ||
          LogicalKeyboardKey.space:
        if (header != null) {
          workspaces.toggleCollapsed(header.id);
        } else {
          final id = state.selectedId;
          if (id == null) return KeyEventResult.ignored;
          widget.onSelected(id); // selects + focuses the terminal
        }
      case LogicalKeyboardKey.f2:
        _renameFromList = true;
        if (header != null) {
          workspaces.startRename(RenameWorkspace(header.id));
        } else if (state.selectedId case final id?) {
          workspaces.startRename(RenameTab(id));
        }
      case LogicalKeyboardKey.escape:
        setState(() => _headerCursor = null);
        widget.onEscape();
      default:
        return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }
```

Change `_commitTabName` (Task 8) to end with `_afterRename();`, and the row's `onCancelRename` to `() { ref.read(sidebarWorkspacesProvider.notifier).endRename(); _afterRename(); }`.

In `build`, replace the `ListView.separated(...)` (and the `rows`/`ids` bookkeeping before it) with:

```dart
    final sidebar = ref.watch(sidebarWorkspacesProvider);
    final items = _items();
    final rowIds = {
      for (final item in items)
        if (item is _RowItem) item.tab.id,
    };
    _rows.removeWhere((id, _) => !rowIds.contains(id));
    _headerKeys.removeWhere((id, _) => sidebar.workspace(id) == null);
    final scaler = MediaQuery.textScalerOf(context);
    final home = ref.watch(homeDirectoryProvider);
    final workspaces = ref.read(sidebarWorkspacesProvider.notifier);

    Widget buildItem(_Item item) => switch (item) {
      _HeaderItem(:final workspace, :final count, :final containsSelected) =>
        KeyedSubtree(
          key: ValueKey('ws.${workspace.id}'),
          child: DragTarget<int>(
            onMove: (_) =>
                _hoverTarget(workspace.id, collapsedHeader: workspace),
            onLeave: (_) => _leaveTarget(workspace.id),
            onAcceptWithDetails: (d) => _dropAt(d.data, workspace.id),
            builder: (context, _, _) => WorkspaceHeader(
              key: _headerKeys.putIfAbsent(workspace.id, GlobalKey.new),
              name: workspace.displayName(l10n),
              count: count,
              collapsed: workspace.collapsed,
              containsSelected: containsSelected,
              focused: _showFocus && _headerCursor == workspace.id,
              renaming: sidebar.renaming == RenameWorkspace(workspace.id),
              dropTarget: _dropTarget == workspace.id,
              deletable: !workspace.isDefault,
              onToggle: () => workspaces.toggleCollapsed(workspace.id),
              onStartRename: () =>
                  workspaces.startRename(RenameWorkspace(workspace.id)),
              onRename: (text) {
                workspaces
                  ..rename(workspace.id, text)
                  ..endRename();
                _afterRename();
              },
              onCancelRename: () {
                workspaces.endRename();
                _afterRename();
              },
              onNewTab: () => unawaited(workspaces.openTabIn(workspace.id)),
              onMenu: (at) => _headerMenu(workspace, at),
              onDelete: () => workspaces.delete(workspace.id),
            ),
          ),
        ),
      _EmptyItem(:final workspaceId) => DragTarget<int>(
        onMove: (_) => _hoverTarget('empty.$workspaceId'),
        onLeave: (_) => _leaveTarget('empty.$workspaceId'),
        onAcceptWithDetails: (d) => _dropAt(d.data, workspaceId, 0),
        builder: (context, _, _) {
          final over = _dropTarget == 'empty.$workspaceId';
          return Container(
            key: ValueKey('empty.$workspaceId'),
            height: _extent(item, scaler),
            padding: const EdgeInsets.only(left: ShellxSizes.contextInset),
            alignment: Alignment.centerLeft,
            decoration: over
                ? BoxDecoration(
                    color: ShellxDesktopColors.primarySoft,
                    border: Border.all(color: ShellxDesktopColors.accent),
                    borderRadius: BorderRadius.circular(ShellxRadius.r6),
                  )
                : null,
            child: ExcludeSemantics(
              child: Text(
                l10n.workspaceEmptyHint,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: ShellxText.caption.copyWith(
                  color: ShellxDesktopColors.textSecondary,
                ),
              ),
            ),
          );
        },
      ),
      _RowItem(:final tab, :final index, :final count, :final workspaceId) =>
        KeyedSubtree(
          key: ValueKey('tab.${tab.id}'),
          child: _rowTarget(
            item,
            _draggable(
              tab,
              SessionTabRow(
                key: _rows.putIfAbsent(tab.id, GlobalKey.new),
                tab: tab,
                selected: tab.id == state.selectedId,
                focused:
                    tab.id == state.selectedId &&
                    _showFocus &&
                    _headerCursor == null,
                position: index + 1,
                count: count,
                positionLabel: sidebar.showHeaders
                    ? l10n.sidebarPositionInWorkspace(
                        index + 1,
                        count,
                        workspaces.displayName(workspaceId),
                      )
                    : null,
                // (every other argument exactly as in Task 8: onSelect,
                // onClose, renaming, home, onStartRename, onRename,
                // onCancelRename, onOpenPort, onMenu, extraActions)
                home: home,
                onSelect: () {
                  setState(() => _headerCursor = null);
                  widget.onSelected(tab.id);
                },
                onClose: () => widget.onClose(tab),
                renaming: sidebar.renaming == RenameTab(tab.id),
                onStartRename: () =>
                    workspaces.startRename(RenameTab(tab.id)),
                onRename: (text) => _commitTabName(tab.id, text),
                onCancelRename: () {
                  workspaces.endRename();
                  _afterRename();
                },
                onOpenPort: _openPort,
                onMenu: (at) => _rowMenu(tab, at),
                extraActions: {
                  CustomSemanticsAction(label: l10n.tabRename): () =>
                      workspaces.startRename(RenameTab(tab.id)),
                  CustomSemanticsAction(label: l10n.tabMoveTo): () =>
                      _moveToMenu(tab, _rowAnchor(tab.id)),
                  if (workspaces.canMoveUp(tab.id))
                    CustomSemanticsAction(label: l10n.tabMoveUp): () =>
                        workspaces.moveUp(tab.id),
                  if (workspaces.canMoveDown(tab.id))
                    CustomSemanticsAction(label: l10n.tabMoveDown): () =>
                        workspaces.moveDown(tab.id),
                  for (final port in tab.exited ? const <int>[] : tab.ports)
                    CustomSemanticsAction(label: l10n.tabOpenPort(port)): () =>
                        _openPort(port),
                },
              ),
            ),
          ),
        ),
    };
```

and the list itself:

```dart
                child: MouseRegion(
                  cursor: _dragging
                      ? SystemMouseCursors.grabbing
                      : MouseCursor.defer,
                  child: ShellxScrollbar(
                    controller: widget.scrollController,
                    showOnHover: true,
                    child: ListView.builder(
                      key: _listKey,
                      controller: widget.scrollController,
                      padding: const EdgeInsets.fromLTRB(
                        ShellxSizes.listMarginH,
                        ShellxSizes.listTop,
                        ShellxSizes.listMarginH,
                        ShellxSizes.listBottom,
                      ),
                      itemCount: items.length,
                      itemBuilder: (context, i) => Padding(
                        padding: EdgeInsets.only(top: _gapBefore(items, i)),
                        child: buildItem(items[i]),
                      ),
                    ),
                  ),
                ),
```

The `Focus` around it keeps `canRequestFocus: items.isNotEmpty` and `skipTraversal: items.isEmpty`. The `ref.listen(... selectedId ...)` that reveals the selected row stays (`_reveal(id)` now takes an `Object`).

- [ ] **Step 6: Run the tests**

Run: `cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test`
Expected: PASS — all A1 tests (one workspace: no headers, same spacing as `ListView.separated` gave), `sidebar_rows_test`, `sidebar_workspaces_ui_test`.

- [ ] **Step 7: Format, analyze, commit**

```bash
cd apps/desktop
~/fvm/versions/3.41.4/bin/dart format --set-exit-if-changed lib test
PATH=~/fvm/versions/3.41.4/bin:$PATH flutter analyze
cd ../..
git add apps/desktop/lib/src/ui/terminal/workspace_header.dart apps/desktop/lib/src/ui/terminal/session_sidebar.dart apps/desktop/test/ui/sidebar_workspaces_ui_test.dart
git commit -m "feat(desktop): workspace headers, keyboard tree and drag-and-drop in the sidebar (C5, D14, D18)"
```

---

### Task 10: Docs — protocol note, HANDOFF §12, manual checklist

**Files:**
- Modify: `docs/superpowers/specs/2026-09-25-shellx-v1-design.md` (the `session.list.result` row, line ~246)
- Modify: `docs/superpowers/HANDOFF.md` (new §12 after §11)

**Interfaces:**
- Consumes: the final behaviour of Tasks 1–9.
- Produces: documentation only.

- [ ] **Step 1: Amend the protocol table**

In `2026-09-25-shellx-v1-design.md`, the `session.list.result` row's payload cell becomes:

```
`sessions: [{id, index, shell, created_at, attached, cwd?, branch?}]` — `cwd`/`branch` (A2, tuỳ chọn) chỉ gửi cho điện thoại đã `session.list {desktop: true}`; bộ giải mã bỏ qua khoá lạ nên app cũ không bị ảnh hưởng
```

- [ ] **Step 2: Add HANDOFF §12**

Insert after §11 (before "## Voice input" if that heading follows §11 in the file, otherwise at the end):

```markdown
## 12. Sidebar giàu thông tin — A2 (2026-10-07)

- Spec: `docs/superpowers/specs/2026-10-07-desktop-sidebar-a2-design.md`; UI: `docs/superpowers/design/2026-10-07-shellx-desktop-ui-a2.md`; plan: `docs/superpowers/plans/2026-10-07-desktop-sidebar-a2.md`.
- Trạng thái: <điền khi merge: nhánh, số test agent/core/desktop>.
- Hook shell (zsh/bash/pwsh) nay phát OSC 7 ở mỗi prompt; `term/shell/block.*` đổi theo (D1). Ai đã bật chia sẻ terminal chỉ có OSC 7 sau khi bật lại.
- Quyền riêng tư: thư mục và nhánh tới điện thoại (đã opt-in `desktop: true`) qua kênh mã hoá đầu cuối như mọi `SessionInfo`; relay không đọc được; cổng không gửi. Không cần sửa trang privacy.
- Agent chạy `lsof`/`ps` (macOS) hoặc `netstat`/`powershell` (Windows) mỗi 3 s **chỉ khi cửa sổ hiện**; không bao giờ chạy `git`.

### Thử tay — macOS
- [ ] 1. Tab mới: dòng thứ hai hiện `~` ngay prompt đầu; `cd ~/Documents/"Tài liệu"` → `~/Documents/Tài liệu` (đúng dấu, không `%20`).
- [ ] 2. `cd` vào repo → nhánh hiện ≤ 300 ms; `git switch -c test-a2` → nhánh mới; `git checkout HEAD~1` → SHA 7 ký tự; worktree (`git worktree add ../wt`) và submodule đúng nhánh của chính nó.
- [ ] 3. `python3 -m http.server 8000` → `:8000` ≤ 4 s; bấm mở `http://localhost:8000/` trong trình duyệt, tab không đổi; Ctrl+C → biến mất ≤ 4 s. `npm run dev` (Vite) → `:5173`. Bốn server → 3 cổng + `+1`, tooltip liệt kê đủ.
- [ ] 4. Ẩn cửa sổ (nút đỏ) → `sudo fs_usage -w -f exec | grep -E 'lsof|ps'` không còn dòng nào trong 30 s; mở lại → cổng cập nhật ngay.
- [ ] 5. 10 tab, cửa sổ hiện, để yên 1 phút → CPU ShellX trung bình ≤ 2 % (Activity Monitor); ghi số đo vào đây.
- [ ] 6. Thư mục trên ổ mạng (SMB) và một monorepo lớn → UI không khựng; nhánh hiện hoặc không, không treo.
- [ ] 7. `ssh` vào máy có tích hợp OSC 7 → thư mục và nhánh biến mất; thoát ssh → hiện lại.
- [ ] 8. ⌘⇧N → "Workspace 2" có một tab, ô tên mở sẵn; gõ "Backend" Enter → bàn phím về terminal. Double-click tên → đổi tên; menu → Xóa (Mặc định: mục mờ); tab về Mặc định, toast trung tính.
- [ ] 9. Kéo tab giữa hai workspace và trong một workspace (vạch thả hiện đúng chỗ), kéo lên tiêu đề nhóm thu gọn → 0,6 s tự mở; kéo gần mép → tự cuộn.
- [ ] 10. ⌘1…⌘9 theo thứ tự nhìn thấy (bỏ nhóm thu gọn); Ctrl+Tab cũng vậy; Ctrl+F6 vào danh sách, ↑/↓ qua tiêu đề, ←/→ thu gọn/mở, F2 đổi tên, ⌥↑/⌥↓ chuyển tab.
- [ ] 11. Thoát app, mở lại → các workspace, tên, trạng thái thu gọn còn; tab mới vào Mặc định.
- [ ] 12. Điện thoại mở phiên → tab vào Mặc định, không được chọn. Điện thoại (bản có `desktop: true`) thấy `cwd`/`branch` trong danh sách (kiểm bằng log debug của app mobile); app mobile cũ vẫn liệt kê bình thường.
- [ ] 13. VoiceOver: dòng tab đọc "…, nhánh main, thư mục ~/…, cổng 3000, tab 2 trên 3 trong Backend"; tiêu đề đọc tên, số tab, trạng thái mở/thu gọn; actions "Đổi tên tab", "Chuyển tới workspace…", "Mở cổng …" chạy được. Bật "Giảm chuyển động" → chevron không xoay.

### Thử tay — Windows
- [ ] 1. PowerShell: `cd C:\Users\<bạn>\Tài liệu` → `~\Tài liệu`; ổ khác `D:\src` giữ nguyên; thư mục UNC hiện đường dẫn, không có nhánh.
- [ ] 2. `python -m http.server 8000` → `:8000` (Windows tiếng Đức/Pháp: vẫn đúng — không dựa chữ LISTENING); tiến trình `powershell` CIM chỉ chạy khi có cổng mới (Process Monitor).
- [ ] 3. Mục 2, 3, 5, 8–11, 13 (Narrator) của macOS với Ctrl+Shift+N, Ctrl+Alt+1…9, Alt+↑/↓.
```

- [ ] **Step 3: Commit**

```bash
git add docs/superpowers/specs/2026-09-25-shellx-v1-design.md docs/superpowers/HANDOFF.md
git commit -m "docs: A2 protocol note (SessionInfo cwd/branch) and HANDOFF §12 manual checklist"
```

---

## Self-Review

**1. Spec coverage**

| Spec item | Task |
|---|---|
| C1 OSC 7 hooks + parsing, `~`, middle-ellipsis | 1, 2 (hooks), 8 (`displayPath`, `ellipsizePath`) |
| C2 branch in pure Dart, worktrees/submodules, detached SHA, cache, refresh on cwd and 133;D, bounded async IO | 3, 5 |
| C3 ports per process tree, PID, lsof/ps, netstat/CIM, 3 s only while visible with sessions, 3 + "+N", click opens browser | 4, 5, 6 (`watchPorts`, `openLocalPort`), 8 (layout, links) |
| C4 `SessionSummary` fields; optional `SessionInfo.cwd/branch` only for `desktop: true`; rule stated | 5, 10 |
| C5 workspaces: headers, counts, Default, ⌘⇧N, rename, delete → Default, menu + drag move, new tabs in current, phone tabs in Default, persistence, ⌘1–9 visible order | 7, 8 (menu), 9 (headers, DnD) |
| C6 tab rename (double-click/menu, name wins, empty restores, desktop only) | 6, 8 |
| C7 row with one context line, height grows, semantics vi/en, contrast, reduced motion | 8, 9; tokens from UI-A2 §1.1 |
| C8 A1 unchanged | every task runs the A1 suites; Task 7 keeps the A1 key paths when headers are hidden |
| D2 remote host clears | 1, 5 |
| D5/D6 schedule, backoff, failures, lsof exit 1 | 4 |
| D7 Windows locale-independent netstat, no wmic | 4 |
| D8 visible = shown | 6 |
| D10 no headers with one workspace | 7 (`showHeaders`), 9 (test) |
| D14 keyboard tree | 9 |
| D15 new workspace flow | 7, 9 |
| D16 delete without confirm + toast | 6 (notice), 7, 9 |
| D17 settings key | 7 |
| D18 reorder + non-drag alternatives | 7, 8, 9 |
| D19 64 chars | 6, 7 |
| Spec §5 edge cases (no hooks, huge repo, permission denied, slow lsof, UNC, corrupt settings, tab closed mid-drag) | 3, 4, 5, 7, 9 |
| Spec §6 manual tests | 10 |

**2. Placeholder scan** — the only fill-in is HANDOFF §12's "Trạng thái" line, which records numbers that exist only after merging (same practice as A1's §11). Every code step has code.

**3. Type consistency** — checked across tasks: `CwdReported(url)`, `parseCwdUrl` → `LocalCwd`/`RemoteCwd`; `GitBranchLookup.branchFor(directory, {refresh})`; `PortWatcher.setVisible/sessionsChanged/dispose`; `PtyProcessId.processId`; `SessionSummary.cwd/gitBranch/ports`; `LocalSessions.watchPorts`; `SessionInfo.cwd/branch`; `TerminalTab.customTitle/label/automaticLabel/hasContext`; `TerminalTabs.rename/showNotice`; `kDefaultWorkspaceId`; `SidebarWorkspaces.create({moveTab})/openTabIn/rename/toggleCollapsed/setCollapsed/delete/moveTab/moveUp/moveDown/canMoveUp/canMoveDown/selectVisible/step/startRename/endRename/displayName`; `RenameTab`/`RenameWorkspace`; `SessionTabRow.heightFor(scaler, {context})`; `WorkspaceHeader.heightFor`; `InlineNameField(initial, style, label, onCommit, onCancel)`; `ShellxMenuEntry.dividerBefore`.

**4. Review Focus** — each line has its test: (1) `cwd_url_test` + `hook_cwd_test`; (2) `git_head_test` coalescing/timeout + `session_context_test` stale answer; (3) `port_watcher_test` nested/removal/hidden + `session_context_test` `watchPorts`; (4) `sidebar_workspaces_test` reconcile test; (5) `loadWorkspaces` tests.

**Execution:** Tasks 1–5 (agent/core) and 6–9 (desktop) are sequential: each desktop task consumes the previous one's names. Task 5 leaves the desktop uncompiled until Task 6 Step 1 — run them back to back.
