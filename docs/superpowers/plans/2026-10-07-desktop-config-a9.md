# ShellX Desktop A9 — Ghostty-style Config File, Custom Keybindings, Command Palette and Config Skill Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Users configure ShellX with one plain-text Ghostty-syntax file (`~/.config/shellx/config`, plus the user's existing Ghostty config for fonts and colours): font, size, theme/palette, cursor, scrollback, padding, Option-as-Alt, close confirmation, new-tab directory, every keyboard shortcut (Ghostty `keybind` syntax, two-step sequences), and their own commands/snippets — applied live on save with per-line problem reports that never crash ShellX; plus a ⌘⇧P command palette, an in-app shortcut editor that writes a managed block, `shellx config …` CLI commands and a `shellx-config` agent skill installed by A7's existing installer.

**Architecture:** A pure-Dart pipeline in `apps/desktop/lib/src/config/` (decode → parse lines → follow `config-file` includes → layer Ghostty keys under ShellX keys → resolve theme files → resolve keybindings against a data table that reproduces today's A1–A6 shortcut maps exactly) feeds one Riverpod `ConfigController` (`shellxConfigProvider`) that loads at startup, polls file stamps every second, and publishes an immutable `ConfigState` (config, `ResolvedTheme`, `KeyBindings`, problems, generation). Terminal views read `terminalAppearanceProvider`; the workspace builds its `Shortcuts` maps from `KeyBindings`; new overlays (command palette, problems panel, shortcut sheet) live in the workspace `Stack` beside A4's notifications panel. A7's `UiCommandHandler` gains `ui.config.*`; the Rust CLI gains `config path|check|reload|show` and embeds a second skill.

**Tech Stack:** Dart ^3.11 / Flutter 3.41.4 via fvm (`PATH=~/fvm/versions/3.41.4/bin:$PATH flutter`), flutter_riverpod 3, xterm 4.0.0, `package:path`, `fake_async`, `flutter_test`; Rust 2021 (`~/.cargo/bin/cargo`) in `term/` with existing deps only.

**Spec:** `docs/superpowers/specs/2026-10-07-desktop-config-a9-design.md` (binding; D1–D46 are final). UI: `docs/superpowers/design/2026-10-07-shellx-desktop-ui-a9.md` (binding for visuals, copy, accessibility). Read alongside: A3 spec D20 + `terminal_shortcuts.dart`, A6 plan Task 6 (`browserPaneShortcuts`, `browserForwardedChords`, `_forwardMaps`) and Task 3 (`activeTerminalPane`), A7 plan Tasks 2, 6, 10 (`kCliCaps`, `UiCommandHandler`, `openTabFor`, `skills.rs`).

## Prerequisite: A3, A4, A5a, A6, A7 merged; A5b and A8 optional

Start `feat/desktop-a9` from `main` **after A3, A4, A5a, A6 and A7 are merged** (spec D1). Check once:

```bash
git log --oneline main | head -20
test -f apps/desktop/lib/src/cli/ui_command_handler.dart && echo "A7 merged" || echo "A7 NOT merged"
grep -q "browserForwardedChords" apps/desktop/lib/src/ui/terminal/terminal_shortcuts.dart && echo "A6 merged" || echo "A6 NOT merged"
```

Record the answers in `docs/superpowers/ledgers/a1-desktop-terminal.md` under a new heading `## A9 (config) — execution`. If A6 is not merged, Task 4 drops the browser bindings and Task 8 drops the forwarded-chord step ("browser pending A6" in the ledger). If A7 is not merged, Task 13 is deferred and Task 7's `newTabCwd` is wired into A3's `openTab` only.

Tasks marked **⚠ MANUAL** need a real Mac (macOS 13+) and a real Windows 10 1809+/11 machine; an executor without the machine records "pending manual" in the ledger section and continues — **the branch is not merged until every ⚠ step is recorded as passed.**

Baseline before Task 1 (record the counts in the ledger):

```bash
cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test && cd ../..
cd term && ~/.cargo/bin/cargo test --features test-hooks && cd ..
```

## Global Constraints

- The spec wins. User-facing app strings in vi + en ARB (`apps/desktop/lib/l10n/app_{en,vi}.arb`, then `PATH=~/fvm/versions/3.41.4/bin:$PATH flutter gen-l10n` in `apps/desktop`); keys and texts exactly as UI-A9 §7. In Vietnamese keep "pane", "tab", "workspace", "Agent" in English. The config template, CLI output and English problem messages for the CLI are **English only**.
- **No behaviour change without a config file (spec criterion 1).** Every existing test of A1–A7 stays green unmodified, except where a task explicitly edits a call site's types (`String?` shortcut labels, Task 8).
- **Phone protocol unchanged:** no edits to `packages/shellx_core/lib/src/protocol/messages.dart`, `apps/mobile`, `relay/`. No new dependencies in any `pubspec.yaml` or `term/Cargo.toml`.
- Config limits: file ≤ 262,144 bytes; include depth ≤ 4; `font-size` 9–28; `scrollback-limit` 1,000–100,000 lines (default 10,000); padding 0–64 (default x 10/10, y 6/6); ≤ 200 commands+snippets, name 1–64 chars without `=`, text ≤ 16,384 chars; `text:`/`csi:`/`esc:` ≤ 4,096 chars decoded; sequences ≤ 2 steps; font step 0.5–8.
- Reload: poll every 1 s, settle 250 ms; startup load bounded to 1 s.
- Paths (spec D3/D4/D13): ShellX `$XDG_CONFIG_HOME/shellx/config` › macOS `~/.config/shellx/config` › Windows `%APPDATA%\ShellX\config`; Ghostty files in order `<xdg>/ghostty/config.ghostty`, `<xdg>/ghostty/config`, macOS `~/Library/Application Support/com.mitchellh.ghostty/config.ghostty`, `…/config`.
- Ghostty layer keys only: `font-family`, `font-size`, `theme`, `background`, `foreground`, `palette`, `cursor-color`, `cursor-style`, `selection-background`, `macos-option-as-alt` (+ `config-file`).
- Settings key added: `config_ghostty_notice_shown` (bool, default false).
- **Never throw from config code into the UI** (D10): every load/apply path catches and reports `ConfigProblemCode.internal`.
- Privacy (D40): never log file contents, values, command texts or user paths — only line numbers, problem codes, `runtimeType`.
- Every interface gaining members updates **every** implementer in the same task.
- Code style as in A1–A7. Every task ends green (its tests + the full `apps/desktop` suite; `term/` suite for Rust tasks), `dart format --set-exit-if-changed lib test`, `flutter analyze`, `cargo fmt --check` + `cargo clippy --all-targets -- -D warnings` for Rust, and a commit containing only the listed files — never `git add -A`.

## Review Focus

1. **A broken or hostile config file** (half-saved line, 10 MB file, UTF-16 without BOM, include loop, unknown keys, `keybind = super+q=…`, a theme file that is a binary) — ShellX keeps running, keeps sessions, shows file/line problems and applies every valid line. Pinned by `config_files_test`, `shellx_config_test`, `keybindings_test` (Tasks 1, 2, 4) and `config_controller_test` "an unreadable file keeps the previous configuration" / "a parser error is internal, never thrown" (Task 5).
2. **Defaults drift** — with no file, any shortcut, colour, padding, cursor, font or close prompt differs from A1–A6. Pinned by the golden fixtures generated from the pre-A9 code (`shortcut_golden_test`, Task 4) and `terminal_appearance_test` "no file looks like A1" (Task 6).
3. **Typing broken by a binding** (plain keys, F6, AltGr on German layouts, Option characters, ⌃Space input switching) — rules D25/D26 reject or annotate, and right-Alt always lets the key through on Windows. Pinned by `keybindings_test` "D25 rules" (Task 4) and `config_shortcuts_test` "AltGr+Q types while Ctrl+Alt+Q is bound" (Task 8).
4. **The managed-block writer corrupts the user's file** (CRLF, BOM, file edited between read and write, missing file, no trailing newline) — bytes outside the block are identical. Pinned by `config_writer_test` (Task 12).
5. **Live reload races** (save during a load, a palette/sequence/recorder open during reload, a terminal created mid-reload) — loads are serialized, overlays refresh, new panes read the new `scrollback-limit`. Pinned by `config_controller_test` "loads run one at a time" (Task 5), `key_sequence_test` "a reload cancels a pending sequence" (Task 9).

---

## File Structure

| File | Responsibility |
|---|---|
| Create `apps/desktop/lib/src/config/config_problem.dart` | `ConfigSeverity`, `ConfigProblemCode`, `ConfigProblem`, `configProblemEnglish` (D8, D39) |
| Create `apps/desktop/lib/src/config/config_syntax.dart` | `ConfigEntry`, `parseConfigText`, `decodeConfigBytes`, `decodeZigString` (D5, D31) |
| Create `apps/desktop/lib/src/config/config_files.dart` | `ConfigFs`, `IoConfigFs`, `FileStamp`, `ConfigChain`, `loadConfigChain`, `expandConfigPath` (D6, D9) |
| Create `apps/desktop/lib/src/config/config_paths.dart` | `ConfigPaths`, `configPathsFor` (D3, D4, D13) |
| Create `apps/desktop/lib/src/config/config_color.dart` | `parseConfigColor`, `contrastRatio` (D14, D15) |
| Create `apps/desktop/lib/src/config/shellx_config.dart` | `ShellxConfig` and its enums, `buildShellxConfig`, `ghosttyEnabled`, `kGhosttyKeys` (D4, D7, D11–D21, D35) |
| Create `apps/desktop/lib/src/config/config_theme.dart` | `ResolvedTheme`, `resolveTheme` (D13–D15) |
| Create `apps/desktop/lib/src/config/keybind_trigger.dart` | `KeyChord`, parse/label/config text/activator/event (D22, D25, D29) |
| Create `apps/desktop/lib/src/config/keybind_actions.dart` | `KeyAction`, `ActionSpec`, `kActionSpecs`, `parseKeyAction`, `intentForAction`, `describeIntent` (D23) |
| Create `apps/desktop/lib/src/config/keybindings.dart` | `KeyBinding`, `KeyBindings`, `defaultKeyBindings`, `resolveKeyBindings`, `labelBindings` (D24–D29) |
| Create `apps/desktop/lib/src/config/config_watcher.dart` | `ConfigWatcher` (D9) |
| Create `apps/desktop/lib/src/config/config_controller.dart` | `ConfigState`, `ConfigLoad`, `ConfigController`, providers (D8–D10, D36, D41) |
| Create `apps/desktop/lib/src/config/config_template.dart` | `configTemplate` (D37) |
| Create `apps/desktop/lib/src/config/config_opener.dart` | `ConfigFileOpener` (D37) |
| Create `apps/desktop/lib/src/config/config_writer.dart` | managed keybind block, atomic write (D32) |
| Create `apps/desktop/lib/src/config/font_probe.dart` | `FontProbe`, `TextPainterFontProbe` (D11) |
| Create `apps/desktop/lib/src/terminal/terminal_appearance.dart` | `TerminalAppearance`, `terminalAppearanceProvider` |
| Create `apps/desktop/lib/src/terminal/user_commands.dart` | `runUserCommand`, `sendTextToFocused`, `commandTarget` (D31, D35) |
| Create `apps/desktop/lib/src/ui/terminal/terminal_intents.dart` | every window `Intent` (moved from `terminal_shortcuts.dart`, re-exported) + A9 intents |
| Create `apps/desktop/lib/src/ui/terminal/key_sequence.dart` | `KeySequenceController`, `SequenceIndicator` (D28) |
| Create `apps/desktop/lib/src/ui/config/command_palette.dart` | palette overlay + `paletteEntries` + `matchScore` (D33) |
| Create `apps/desktop/lib/src/ui/config/config_problems_panel.dart` | problems panel (D36) |
| Create `apps/desktop/lib/src/ui/config/shortcuts_sheet.dart` | shortcut editor (D32) |
| Create `apps/desktop/lib/src/ui/config/action_labels.dart` | localized action names + `problemText` |
| Modify `apps/desktop/lib/src/ui/terminal/terminal_shortcuts.dart` | maps built from `KeyBindings`; A6 chords from bindings |
| Modify `apps/desktop/lib/src/ui/terminal/shortcut_labels.dart` | labels from effective bindings (`String?`) |
| Modify `apps/desktop/lib/src/ui/terminal/terminal_workspace_page.dart` | bindings, AltGr guard, A9 actions, overlays, toasts |
| Modify `apps/desktop/lib/src/ui/terminal/terminal_pane.dart`, `pane_tree_view.dart` | appearance (theme, cursor, padding, font, outline), sequence indicator |
| Modify `apps/desktop/lib/src/ui/terminal/terminal_overlays.dart` | config notices, toast action button |
| Modify `apps/desktop/lib/src/ui/terminal/close_tab.dart` | `confirm-close-surface` (D20) |
| Modify `apps/desktop/lib/src/terminal/{terminal_style,terminal_font_size,terminal_input,desktop_terminal,terminal_tabs}.dart` | font families, D12, Option-as-Alt, `sendUserText`, scrollback, new-tab cwd |
| Modify `apps/desktop/lib/src/browser/…` (A6 `BrowserPaneView`) | forwarded chords from bindings, re-sent on reload (D30) |
| Modify `apps/desktop/lib/src/platform/settings_store.dart` | `configGhosttyNoticeShown` |
| Modify `apps/desktop/lib/src/tray/{tray_action,tray_menu,tray_actions,tray_presenter}.dart` | "Cấu hình" submenu (D45) |
| Modify `apps/desktop/lib/src/cli/ui_command_handler.dart`, `packages/shellx_agent/lib/src/mux/cli_wire.dart` | `ui.config.*`, cap `ui.config` (D39) |
| Modify `apps/desktop/lib/main.dart` | load + watch at startup |
| Modify `apps/desktop/lib/l10n/app_en.arb`, `app_vi.arb` (+ generated) | strings |
| Create `term/src/api/config_path.rs`; modify `term/src/api/{mod,args,run,skills}.rs` | `shellx config …`, two skills (D34, D39) |
| Create `agent-skills/shellx-config/SKILL.md`; modify `agent-skills/shellx/reference.md` | config skill |
| Create `apps/desktop/test/config/**`, `apps/desktop/test/support/{memory_config_fs,config_harness}.dart`, `apps/desktop/test/ui/fixtures/shortcuts_*.txt`, `apps/desktop/test/ui/{shortcut_golden,config_shortcuts,key_sequence,command_palette,config_problems_ui,shortcuts_sheet}_test.dart` | tests |
| Modify `docs/superpowers/HANDOFF.md`, ledger | manual checklist |

---

### Task 1: Problems, line syntax, file chains (D5, D6, D8, D31)

**Files:**
- Create: `apps/desktop/lib/src/config/config_problem.dart`, `apps/desktop/lib/src/config/config_syntax.dart`, `apps/desktop/lib/src/config/config_files.dart`
- Create: `apps/desktop/test/support/memory_config_fs.dart`
- Test: `apps/desktop/test/config/config_syntax_test.dart`, `apps/desktop/test/config/config_files_test.dart`

**Interfaces:**
- Consumes: nothing new (`dart:convert`, `package:path`).
- Produces:
  - `enum ConfigSeverity { error, warning, info }`; `enum ConfigProblemCode { syntax, badKey, unknownKey, badValue, outOfRange, duplicate, includeMissing, includeCycle, includeDepth, unreadable, notUtf8, tooLarge, themeNotFound, fontNotFound, fontNotMonospace, lowContrast, unsupportedValue, notOnThisPlatform, badTrigger, unknownAction, badActionParam, reservedTrigger, plainKeyTrigger, regionTrigger, shellKeyTrigger, optionKeyTrigger, altGrTrigger, missionControlTrigger, unsupportedPrefix, sequenceTooLong, sequencePrefixShadows, unknownCommand, commandLimit, internal }`.
  - `final class ConfigProblem { file, line (0 = whole file), severity, code, key?, value?, hint?, detail? }` with value equality; `String configProblemEnglish(ConfigProblem p)`.
  - `final class ConfigEntry { file, line, key, value }`; `List<ConfigEntry> parseConfigText(String text, {required String file, required List<ConfigProblem> problems})`; `String decodeConfigBytes(Uint8List bytes)` (throws `FormatException`); `String? decodeZigString(String s)`.
  - `const int kConfigMaxBytes = 262144; const int kConfigMaxIncludeDepth = 4;` `final class FileStamp { exists, size, modifiedMs }`; `abstract interface class ConfigFs { Future<Uint8List?> read(String path); Future<FileStamp> stamp(String path); }`; `final class ConfigTooLarge implements Exception`; `final class IoConfigFs implements ConfigFs`; `final class ConfigChain { entries, files, readable }`; `Future<ConfigChain> loadConfigChain(String path, {required ConfigFs fs, required String home, required List<ConfigProblem> problems, bool windows = false, bool quiet = false, bool Function(String key)? keep})`; `String expandConfigPath(String value, {required String baseDir, required String home, bool windows = false})`.
  - Test support: `MemoryConfigFs implements ConfigFs` (`write`, `writeBytes`, `delete`, `unreadable`, `reads`).

- [ ] **Step 1: Write the failing tests**

Create `apps/desktop/test/support/memory_config_fs.dart`:

```dart
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:shellx_desktop/src/config/config_files.dart';

/// A9: an in-memory [ConfigFs]; every write bumps a fake modification time.
final class MemoryConfigFs implements ConfigFs {
  final Map<String, Uint8List> files = {};
  final Map<String, int> _modified = {};
  final Set<String> unreadable = {};
  int _clock = 0;
  int reads = 0;

  /// When set, [read] throws it (a bug in the platform layer, D10).
  Object? readError;

  void write(String path, String text) =>
      writeBytes(path, utf8.encode(text));

  void writeBytes(String path, List<int> bytes) {
    files[path] = Uint8List.fromList(bytes);
    _modified[path] = ++_clock;
  }

  void delete(String path) {
    files.remove(path);
    _modified.remove(path);
  }

  String text(String path) => utf8.decode(files[path]!);

  @override
  Future<Uint8List?> read(String path) async {
    reads++;
    final error = readError;
    if (error != null) throw error;
    if (unreadable.contains(path)) {
      throw FileSystemException('denied', path);
    }
    final bytes = files[path];
    if (bytes != null && bytes.length > kConfigMaxBytes) {
      throw const ConfigTooLarge();
    }
    return bytes;
  }

  @override
  Future<FileStamp> stamp(String path) async {
    final bytes = files[path];
    return bytes == null
        ? const FileStamp.missing()
        : FileStamp(exists: true, size: bytes.length, modifiedMs: _modified[path]!);
  }
}
```

Create `apps/desktop/test/config/config_syntax_test.dart`:

```dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/config/config_problem.dart';
import 'package:shellx_desktop/src/config/config_syntax.dart';

List<ConfigEntry> parse(String text, List<ConfigProblem> problems) =>
    parseConfigText(text, file: '/c/config', problems: problems);

void main() {
  group('parseConfigText (D5)', () {
    test('key = value, whole-line comments, blanks, CRLF, quotes', () {
      final problems = <ConfigProblem>[];
      final entries = parse(
        '# comment\r\n'
        '\r\n'
        'font-size = 14\r\n'
        '  font-family = "Fira Code"  \n'
        'keybind=super+d=new_split:right\n'
        'theme = a # not a comment\n',
        problems,
      );
      expect(problems, isEmpty);
      expect([for (final e in entries) (e.line, e.key, e.value)], [
        (3, 'font-size', '14'),
        (4, 'font-family', 'Fira Code'),
        (5, 'keybind', 'super+d=new_split:right'),
        (6, 'theme', 'a # not a comment'),
      ]);
      expect(entries.first.file, '/c/config');
    });

    test('an empty value is kept: it resets the key', () {
      final problems = <ConfigProblem>[];
      final entries = parse('font-family =\nfont-family = ""\n', problems);
      expect([for (final e in entries) e.value], ['', '']);
      expect(problems, isEmpty);
    });

    test('a line without "=" is a syntax error, a bad key is badKey, '
        'the other lines still parse', () {
      final problems = <ConfigProblem>[];
      final entries = parse(
        'font-size 14\nFont-Size = 3\nfont_size = 2\ncursor-style = bar\n',
        problems,
      );
      expect([for (final e in entries) e.key], ['cursor-style']);
      expect(
        [for (final p in problems) (p.line, p.code, p.severity, p.key)],
        [
          (1, ConfigProblemCode.syntax, ConfigSeverity.error, null),
          (2, ConfigProblemCode.badKey, ConfigSeverity.error, 'Font-Size'),
          (3, ConfigProblemCode.badKey, ConfigSeverity.error, 'font_size'),
        ],
      );
    });

    test('a lone quote is not stripped', () {
      final entries = parse('theme = "\n', []);
      expect(entries.single.value, '"');
    });
  });

  group('decodeConfigBytes (D5)', () {
    test('UTF-8 with and without BOM', () {
      expect(decodeConfigBytes(Uint8List.fromList(utf8.encode('a = é'))), 'a = é');
      expect(
        decodeConfigBytes(
          Uint8List.fromList([0xEF, 0xBB, 0xBF, ...utf8.encode('a = 1')]),
        ),
        'a = 1',
      );
    });

    test('UTF-16 with a BOM, both byte orders', () {
      expect(
        decodeConfigBytes(Uint8List.fromList([0xFF, 0xFE, 0x61, 0x00, 0x3D, 0x00])),
        'a=',
      );
      expect(
        decodeConfigBytes(Uint8List.fromList([0xFE, 0xFF, 0x00, 0x61, 0x00, 0x3D])),
        'a=',
      );
    });

    test('bytes that are not UTF-8, and odd UTF-16, throw FormatException', () {
      expect(
        () => decodeConfigBytes(Uint8List.fromList([0x61, 0xC3, 0x28])),
        throwsFormatException,
      );
      expect(
        () => decodeConfigBytes(Uint8List.fromList([0xFF, 0xFE, 0x61])),
        throwsFormatException,
      );
    });
  });

  group('decodeZigString (D31)', () {
    test('escapes', () {
      expect(decodeZigString(r'git status\n'), 'git status\n');
      expect(decodeZigString(r'\x1b[A'), '\x1b[A');
      expect(decodeZigString(r'\u{1F600}'), '😀');
      expect(decodeZigString(r"""a\\b\"c\'d\te\r"""), 'a\\b"c\'d\te\r');
      expect(decodeZigString('plain'), 'plain');
    });

    test('invalid escapes give null', () {
      for (final bad in [
        r'\q',
        r'\x1',
        r'\xzz',
        r'\u{110000}',
        r'\u{D800}',
        r'\u1234',
        r'\u{12',
        r'abc\',
      ]) {
        expect(decodeZigString(bad), isNull, reason: bad);
      }
    });
  });

  test('ConfigProblem has value equality (the toast compares sets, D36)', () {
    const a = ConfigProblem(
      file: '/c',
      line: 1,
      severity: ConfigSeverity.error,
      code: ConfigProblemCode.syntax,
    );
    const b = ConfigProblem(
      file: '/c',
      line: 1,
      severity: ConfigSeverity.error,
      code: ConfigProblemCode.syntax,
    );
    expect(a, b);
    expect({a, b}, hasLength(1));
  });

  test('configProblemEnglish fills every placeholder', () {
    final text = configProblemEnglish(
      const ConfigProblem(
        file: '/c',
        line: 3,
        severity: ConfigSeverity.error,
        code: ConfigProblemCode.badValue,
        key: 'font-size',
        value: 'to',
        hint: '9–28',
      ),
    );
    expect(text, 'font-size: “to” is not valid (expected 9–28)');
    for (final code in ConfigProblemCode.values) {
      final message = configProblemEnglish(
        ConfigProblem(
          file: '/c',
          line: 1,
          severity: ConfigSeverity.error,
          code: code,
          key: 'k',
          value: 'v',
          hint: 'h',
          detail: 'd',
        ),
      );
      expect(message, isNot(contains('{')), reason: code.name);
      expect(message, isNotEmpty);
    }
  });
}
```

Create `apps/desktop/test/config/config_files_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/config/config_files.dart';
import 'package:shellx_desktop/src/config/config_problem.dart';

import '../support/memory_config_fs.dart';

void main() {
  late MemoryConfigFs fs;
  setUp(() => fs = MemoryConfigFs());

  Future<(ConfigChain, List<ConfigProblem>)> load(
    String path, {
    bool quiet = false,
    bool Function(String key)? keep,
  }) async {
    final problems = <ConfigProblem>[];
    final chain = await loadConfigChain(
      path,
      fs: fs,
      home: '/home/me',
      problems: problems,
      quiet: quiet,
      keep: keep,
    );
    return (chain, problems);
  }

  test('a missing root file is readable and empty', () async {
    final (chain, problems) = await load('/c/config');
    expect(chain.readable, isTrue);
    expect(chain.entries, isEmpty);
    expect(chain.files, ['/c/config']);
    expect(problems, isEmpty);
  });

  test('includes are read after the whole file, relative to it (D6)', () async {
    fs
      ..write('/c/config', 'font-size = 10\nconfig-file = more\nfont-size = 11\n')
      ..write('/c/more', 'font-size = 12\n');
    final (chain, problems) = await load('/c/config');
    expect([for (final e in chain.entries) e.value], ['10', '11', '12']);
    expect(chain.entries.last.file, '/c/more');
    expect(chain.files, ['/c/config', '/c/more']);
    expect(problems, isEmpty);
  });

  test('"~/" expands; "?" makes a missing include silent', () async {
    fs
      ..write('/c/config', 'config-file = ~/x\nconfig-file = ?nope\n')
      ..write('/home/me/x', 'theme = a\n');
    final (chain, problems) = await load('/c/config');
    expect(chain.entries.single.value, 'a');
    expect(chain.files, contains('/c/nope'));
    expect(problems, isEmpty);
  });

  test('a missing include is a warning at its line', () async {
    fs.write('/c/config', '\nconfig-file = gone\n');
    final (_, problems) = await load('/c/config');
    final p = problems.single;
    expect((p.line, p.code, p.severity, p.value), (
      2,
      ConfigProblemCode.includeMissing,
      ConfigSeverity.warning,
      'gone',
    ));
  });

  test('a loop is reported once and skipped', () async {
    fs
      ..write('/c/a', 'config-file = b\nfont-size = 1\n')
      ..write('/c/b', 'config-file = a\nfont-size = 2\n');
    final (chain, problems) = await load('/c/a');
    expect([for (final e in chain.entries) e.value], ['1', '2']);
    expect(problems.single.code, ConfigProblemCode.includeCycle);
    expect(problems.single.file, '/c/b');
  });

  test('more than 4 levels is includeDepth', () async {
    for (var i = 0; i < 6; i++) {
      fs.write('/c/f$i', 'config-file = f${i + 1}\nfont-size = $i\n');
    }
    final (chain, problems) = await load('/c/f0');
    expect([for (final e in chain.entries) e.value], ['0', '1', '2', '3', '4']);
    expect(problems.single.code, ConfigProblemCode.includeDepth);
    expect(problems.single.file, '/c/f4');
  });

  test('an unreadable, too large or non-UTF-8 root is not readable (D8)', () async {
    fs.unreadable.add('/c/config');
    fs.write('/c/config', 'font-size = 1\n');
    var (chain, problems) = await load('/c/config');
    expect(chain.readable, isFalse);
    expect(problems.single.code, ConfigProblemCode.unreadable);
    expect(problems.single.severity, ConfigSeverity.error);

    fs.unreadable.clear();
    fs.write('/c/config', 'a' * (kConfigMaxBytes + 1));
    (chain, problems) = await load('/c/config');
    expect(chain.readable, isFalse);
    expect(problems.single.code, ConfigProblemCode.tooLarge);

    fs.writeBytes('/c/config', [0x61, 0xC3, 0x28]);
    (chain, problems) = await load('/c/config');
    expect(chain.readable, isFalse);
    expect(problems.single.code, ConfigProblemCode.notUtf8);
  });

  test('quiet (Ghostty): syntax and include problems are dropped, '
      'read problems are warnings, keep filters keys', () async {
    fs
      ..write('/g/config', 'oops\nfont-size = 3\nwindow-padding-x = 9\nconfig-file = nope\n')
      ..unreadable.add('/g/locked');
    final (chain, problems) = await load(
      '/g/config',
      quiet: true,
      keep: (k) => k == 'font-size',
    );
    expect([for (final e in chain.entries) e.key], ['font-size']);
    expect(problems, isEmpty);
    fs.write('/g/locked', 'x = 1');
    final (locked, lockedProblems) = await load('/g/locked', quiet: true);
    expect(locked.readable, isFalse);
    expect(lockedProblems.single.severity, ConfigSeverity.warning);
  });

  test('expandConfigPath on Windows', () {
    expect(
      expandConfigPath(
        r'..\themes\x',
        baseDir: r'C:\Users\me\AppData\Roaming\ShellX',
        home: r'C:\Users\me',
        windows: true,
      ),
      r'C:\Users\me\AppData\Roaming\themes\x',
    );
    expect(
      expandConfigPath(r'~\y', baseDir: r'C:\a', home: r'C:\Users\me', windows: true),
      r'C:\Users\me\y',
    );
  });

  test('IoConfigFs stamps a missing file as missing', () async {
    final stamp = await const IoConfigFs().stamp('/definitely/not/here/shellx-a9');
    expect(stamp.exists, isFalse);
  });
}
```

- [ ] **Step 2: Run the tests to see them fail**

Run: `cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/config/config_syntax_test.dart test/config/config_files_test.dart`
Expected: FAIL — `config_problem.dart`, `config_syntax.dart`, `config_files.dart` do not exist.

- [ ] **Step 3: Implement**

Create `apps/desktop/lib/src/config/config_problem.dart`:

```dart
import 'package:flutter/foundation.dart';

/// A9 spec D8: how much a problem matters. Notes never raise a toast (D36).
enum ConfigSeverity { error, warning, info }

/// A9 spec D8 / UI-A9 §7.2: one message per code.
enum ConfigProblemCode {
  syntax,
  badKey,
  unknownKey,
  badValue,
  outOfRange,
  duplicate,
  includeMissing,
  includeCycle,
  includeDepth,
  unreadable,
  notUtf8,
  tooLarge,
  themeNotFound,
  fontNotFound,
  fontNotMonospace,
  lowContrast,
  unsupportedValue,
  notOnThisPlatform,
  badTrigger,
  unknownAction,
  badActionParam,
  reservedTrigger,
  plainKeyTrigger,
  regionTrigger,
  shellKeyTrigger,
  optionKeyTrigger,
  altGrTrigger,
  missionControlTrigger,
  unsupportedPrefix,
  sequenceTooLong,
  sequencePrefixShadows,
  unknownCommand,
  commandLimit,
  internal,
}

/// One problem in one file: where, how bad, what. [line] is 1-based; 0
/// means the whole file. [key], [value], [hint], [detail] fill the
/// message's placeholders (UI-A9 §7.2); [hint] is literal syntax and is
/// never translated.
@immutable
final class ConfigProblem {
  const ConfigProblem({
    required this.file,
    required this.line,
    required this.severity,
    required this.code,
    this.key,
    this.value,
    this.hint,
    this.detail,
  });

  final String file;
  final int line;
  final ConfigSeverity severity;
  final ConfigProblemCode code;
  final String? key;
  final String? value;
  final String? hint;
  final String? detail;

  @override
  bool operator ==(Object other) =>
      other is ConfigProblem &&
      other.file == file &&
      other.line == line &&
      other.severity == severity &&
      other.code == code &&
      other.key == key &&
      other.value == value &&
      other.hint == hint &&
      other.detail == detail;

  @override
  int get hashCode =>
      Object.hash(file, line, severity, code, key, value, hint, detail);

  @override
  String toString() => 'ConfigProblem(${code.name} $file:$line)';
}

/// The English message (CLI output, A7 D11). Must equal the en ARB text
/// of the same code (checked by `config_problems_ui_test`, Task 10).
String configProblemEnglish(ConfigProblem p) {
  final key = p.key ?? '';
  final value = p.value ?? '';
  final hint = p.hint ?? '';
  final detail = p.detail ?? '';
  return switch (p.code) {
    ConfigProblemCode.syntax => 'Line has no “=” (expected key = value)',
    ConfigProblemCode.badKey => '“$key” is not a valid key name',
    ConfigProblemCode.unknownKey => 'ShellX has no key “$key”',
    ConfigProblemCode.badValue => '$key: “$value” is not valid (expected $hint)',
    ConfigProblemCode.outOfRange =>
      '$key: $value is outside $hint, using $detail',
    ConfigProblemCode.duplicate => '$key: replaces line $detail',
    ConfigProblemCode.includeMissing => 'File “$value” not found',
    ConfigProblemCode.includeCycle =>
      '“$value” is already loaded (config-file loop)',
    ConfigProblemCode.includeDepth =>
      'config-file is nested more than 4 levels',
    ConfigProblemCode.unreadable =>
      "Can't read the file — keeping the previous configuration",
    ConfigProblemCode.notUtf8 =>
      "The file isn't UTF-8 — keeping the previous configuration",
    ConfigProblemCode.tooLarge =>
      'The file is larger than 256 KiB — keeping the previous configuration',
    ConfigProblemCode.themeNotFound => 'Theme “$value” not found',
    ConfigProblemCode.fontNotFound =>
      'Font “$value” not found — using JetBrains Mono',
    ConfigProblemCode.fontNotMonospace =>
      "Font “$value” isn't monospaced — columns may not line up",
    ConfigProblemCode.lowContrast =>
      'Low text/background contrast ($detail:1, aim for 4.5:1)',
    ConfigProblemCode.unsupportedValue =>
      "$key = $value isn't supported (using $hint)",
    ConfigProblemCode.notOnThisPlatform => '$key only has an effect on macOS',
    ConfigProblemCode.badTrigger => '“$value” is not a valid key combination',
    ConfigProblemCode.unknownAction => "There's no action “$value”",
    ConfigProblemCode.badActionParam => '“$value” is not valid (expected $hint)',
    ConfigProblemCode.reservedTrigger => '$value is reserved by the system',
    ConfigProblemCode.plainKeyTrigger =>
      '$value is for typing — add Ctrl, Alt or ⌘',
    ConfigProblemCode.regionTrigger =>
      'F6 and Shift+F6 always move between regions',
    ConfigProblemCode.shellKeyTrigger => '$value will no longer reach the shell',
    ConfigProblemCode.optionKeyTrigger =>
      '$value will no longer type its Option character',
    ConfigProblemCode.altGrTrigger =>
      '$value works with the left Alt only; AltGr still types characters',
    ConfigProblemCode.missionControlTrigger => 'Mission Control may take $value',
    ConfigProblemCode.unsupportedPrefix =>
      "The “$value” prefix isn't supported",
    ConfigProblemCode.sequenceTooLong => 'Key sequences have at most 2 steps',
    ConfigProblemCode.sequencePrefixShadows =>
      '$value starts a key sequence, so it no longer works on its own',
    ConfigProblemCode.unknownCommand => "There's no command “$value”",
    ConfigProblemCode.commandLimit =>
      'More than 200 commands — the rest are ignored',
    ConfigProblemCode.internal =>
      'Unexpected error — keeping the previous configuration',
  };
}
```

Create `apps/desktop/lib/src/config/config_syntax.dart`:

```dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import 'config_problem.dart';

/// One `key = value` line (A9 spec D5).
@immutable
final class ConfigEntry {
  const ConfigEntry({
    required this.file,
    required this.line,
    required this.key,
    required this.value,
  });

  final String file;
  final int line;
  final String key;
  final String value;

  @override
  String toString() => 'ConfigEntry($key @ $file:$line)';
}

final RegExp _keyPattern = RegExp(r'^[a-z0-9][a-z0-9-]*$');

/// D5: whole-line `#` comments, the first `=` splits, both sides trimmed,
/// one pair of surrounding double quotes stripped (no escapes). Bad lines
/// are reported and skipped; the others are returned in order.
List<ConfigEntry> parseConfigText(
  String text, {
  required String file,
  required List<ConfigProblem> problems,
}) {
  final entries = <ConfigEntry>[];
  final lines = text.split('\n');
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i].trim(); // also drops a CR
    if (line.isEmpty || line.startsWith('#')) continue;
    final eq = line.indexOf('=');
    if (eq < 0) {
      problems.add(
        ConfigProblem(
          file: file,
          line: i + 1,
          severity: ConfigSeverity.error,
          code: ConfigProblemCode.syntax,
        ),
      );
      continue;
    }
    final key = line.substring(0, eq).trim();
    if (!_keyPattern.hasMatch(key)) {
      problems.add(
        ConfigProblem(
          file: file,
          line: i + 1,
          severity: ConfigSeverity.error,
          code: ConfigProblemCode.badKey,
          key: key,
        ),
      );
      continue;
    }
    entries.add(
      ConfigEntry(
        file: file,
        line: i + 1,
        key: key,
        value: unquoteConfigValue(line.substring(eq + 1).trim()),
      ),
    );
  }
  return entries;
}

String unquoteConfigValue(String value) =>
    value.length >= 2 && value.startsWith('"') && value.endsWith('"')
    ? value.substring(1, value.length - 1)
    : value;

/// D5: UTF-8 (a BOM is skipped) or UTF-16 with a BOM. Anything else throws
/// [FormatException].
String decodeConfigBytes(Uint8List bytes) {
  if (bytes.length >= 3 &&
      bytes[0] == 0xEF &&
      bytes[1] == 0xBB &&
      bytes[2] == 0xBF) {
    return utf8.decode(bytes.sublist(3));
  }
  if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE) {
    return _utf16(bytes.sublist(2), little: true);
  }
  if (bytes.length >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF) {
    return _utf16(bytes.sublist(2), little: false);
  }
  return utf8.decode(bytes);
}

String _utf16(Uint8List bytes, {required bool little}) {
  if (bytes.length.isOdd) throw const FormatException('odd UTF-16 length');
  final units = List<int>.generate(
    bytes.length ~/ 2,
    (i) => little
        ? bytes[2 * i] | (bytes[2 * i + 1] << 8)
        : (bytes[2 * i] << 8) | bytes[2 * i + 1],
  );
  return String.fromCharCodes(units);
}

final RegExp _twoHex = RegExp(r'^[0-9a-fA-F]{2}$');
final RegExp _hexRun = RegExp(r'^[0-9a-fA-F]{1,6}$');

/// D31: Zig string-literal escapes (`\n \r \t \\ \" \' \xHH \u{H…}`).
/// Null when an escape is invalid.
String? decodeZigString(String s) {
  final out = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    final c = s[i];
    if (c != r'\') {
      out.write(c);
      continue;
    }
    i++;
    if (i >= s.length) return null;
    switch (s[i]) {
      case 'n':
        out.write('\n');
      case 'r':
        out.write('\r');
      case 't':
        out.write('\t');
      case r'\':
        out.write(r'\');
      case '"':
        out.write('"');
      case "'":
        out.write("'");
      case 'x':
        if (i + 3 > s.length) return null;
        final hex = s.substring(i + 1, i + 3);
        if (!_twoHex.hasMatch(hex)) return null;
        out.writeCharCode(int.parse(hex, radix: 16));
        i += 2;
      case 'u':
        if (i + 1 >= s.length || s[i + 1] != '{') return null;
        final end = s.indexOf('}', i + 2);
        if (end < 0) return null;
        final hex = s.substring(i + 2, end);
        if (!_hexRun.hasMatch(hex)) return null;
        final cp = int.parse(hex, radix: 16);
        if (cp > 0x10FFFF || (cp >= 0xD800 && cp <= 0xDFFF)) return null;
        out.writeCharCode(cp);
        i = end;
      default:
        return null;
    }
  }
  return out.toString();
}
```

Create `apps/desktop/lib/src/config/config_files.dart`:

```dart
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'config_problem.dart';
import 'config_syntax.dart';

/// D5: a bigger file is not read.
const int kConfigMaxBytes = 256 * 1024;

/// D6: `config-file` nesting below the root.
const int kConfigMaxIncludeDepth = 4;

/// What the watcher compares (D9).
@immutable
final class FileStamp {
  const FileStamp({
    required this.exists,
    required this.size,
    required this.modifiedMs,
  });
  const FileStamp.missing() : exists = false, size = 0, modifiedMs = 0;

  final bool exists;
  final int size;
  final int modifiedMs;

  @override
  bool operator ==(Object other) =>
      other is FileStamp &&
      other.exists == exists &&
      other.size == size &&
      other.modifiedMs == modifiedMs;

  @override
  int get hashCode => Object.hash(exists, size, modifiedMs);
}

final class ConfigTooLarge implements Exception {
  const ConfigTooLarge();
}

/// The file system as the config code sees it (tests use a memory one).
abstract interface class ConfigFs {
  /// Null when [path] does not exist. Throws [ConfigTooLarge] above
  /// [kConfigMaxBytes] and [FileSystemException] when it can't be read.
  Future<Uint8List?> read(String path);

  /// Never throws: a path that can't be stat'ed is missing.
  Future<FileStamp> stamp(String path);
}

final class IoConfigFs implements ConfigFs {
  const IoConfigFs();

  @override
  Future<Uint8List?> read(String path) async {
    final file = File(path);
    if (!await file.exists()) return null;
    if (await file.length() > kConfigMaxBytes) throw const ConfigTooLarge();
    return file.readAsBytes();
  }

  @override
  Future<FileStamp> stamp(String path) async {
    try {
      final stat = await FileStat.stat(path);
      if (stat.type == FileSystemEntityType.notFound) {
        return const FileStamp.missing();
      }
      return FileStamp(
        exists: true,
        size: stat.size,
        modifiedMs: stat.modified.millisecondsSinceEpoch,
      );
    } on FileSystemException {
      return const FileStamp.missing();
    }
  }
}

/// A root file and its includes.
final class ConfigChain {
  ConfigChain(this.entries, this.files, {required this.readable});

  /// Every entry except `config-file`, in effective order (D6).
  final List<ConfigEntry> entries;

  /// Every path looked at, existing or not (the watcher's list, D9).
  final List<String> files;

  /// False when the root exists but could not be read (D8).
  final bool readable;
}

p.Context _context(bool windows) => windows ? p.windows : p.posix;

/// D6: `~` / `~/…` from [home]; relative to [baseDir]; normalised.
String expandConfigPath(
  String value, {
  required String baseDir,
  required String home,
  bool windows = false,
}) {
  final ctx = _context(windows);
  var path = value.trim();
  if (path == '~') {
    path = home;
  } else if (path.startsWith('~/') || (windows && path.startsWith(r'~\'))) {
    path = ctx.join(home, path.substring(2));
  }
  return ctx.normalize(ctx.isAbsolute(path) ? path : ctx.join(baseDir, path));
}

/// Reads [path] and its `config-file` includes (D5, D6). [quiet] is the
/// Ghostty layer (D4): its syntax and include problems are not ShellX's to
/// report, and a read problem is only a warning. [keep] filters keys.
Future<ConfigChain> loadConfigChain(
  String path, {
  required ConfigFs fs,
  required String home,
  required List<ConfigProblem> problems,
  bool windows = false,
  bool quiet = false,
  bool Function(String key)? keep,
}) async {
  final entries = <ConfigEntry>[];
  final files = <String>[];
  var readable = true;
  final ctx = _context(windows);
  final readSeverity = quiet ? ConfigSeverity.warning : ConfigSeverity.error;

  void fileProblem(String file, ConfigProblemCode code, int depth) {
    problems.add(
      ConfigProblem(file: file, line: 0, severity: readSeverity, code: code),
    );
    if (depth == 0) readable = false;
  }

  Future<void> visit(
    String file,
    int depth,
    List<String> stack, {
    ConfigEntry? from,
    bool optional = false,
  }) async {
    files.add(file);
    final Uint8List? bytes;
    try {
      bytes = await fs.read(file);
    } on ConfigTooLarge {
      return fileProblem(file, ConfigProblemCode.tooLarge, depth);
    } on FileSystemException {
      return fileProblem(file, ConfigProblemCode.unreadable, depth);
    }
    if (bytes == null) {
      if (from != null && !optional && !quiet) {
        problems.add(
          ConfigProblem(
            file: from.file,
            line: from.line,
            severity: ConfigSeverity.warning,
            code: ConfigProblemCode.includeMissing,
            key: 'config-file',
            value: from.value,
          ),
        );
      }
      return;
    }
    final String text;
    try {
      text = decodeConfigBytes(bytes);
    } on FormatException {
      return fileProblem(file, ConfigProblemCode.notUtf8, depth);
    }
    final syntax = quiet ? <ConfigProblem>[] : problems;
    final own = parseConfigText(text, file: file, problems: syntax);
    final includes = <ConfigEntry>[];
    for (final entry in own) {
      if (entry.key == 'config-file') {
        if (entry.value.isNotEmpty) includes.add(entry);
      } else if (keep == null || keep(entry.key)) {
        entries.add(entry);
      }
    }
    for (final include in includes) {
      final optionalInclude = include.value.startsWith('?');
      final target = expandConfigPath(
        optionalInclude ? include.value.substring(1) : include.value,
        baseDir: ctx.dirname(file),
        home: home,
        windows: windows,
      );
      ConfigProblemCode? refused;
      if (stack.contains(target)) {
        refused = ConfigProblemCode.includeCycle;
      } else if (depth + 1 > kConfigMaxIncludeDepth) {
        refused = ConfigProblemCode.includeDepth;
      }
      if (refused != null) {
        if (!quiet) {
          problems.add(
            ConfigProblem(
              file: include.file,
              line: include.line,
              severity: ConfigSeverity.warning,
              code: refused,
              key: 'config-file',
              value: include.value,
            ),
          );
        }
        continue;
      }
      await visit(
        target,
        depth + 1,
        [...stack, target],
        from: include,
        optional: optionalInclude,
      );
    }
  }

  await visit(path, 0, [path]);
  return ConfigChain(entries, files, readable: readable);
}
```

- [ ] **Step 4: Run the tests**

Run: `cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/config/`
Expected: PASS (config_syntax_test 10, config_files_test 10). Then `dart format --set-exit-if-changed lib test && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter analyze` — clean.

- [ ] **Step 5: Commit**

```bash
git add apps/desktop/lib/src/config/config_problem.dart apps/desktop/lib/src/config/config_syntax.dart apps/desktop/lib/src/config/config_files.dart apps/desktop/test/support/memory_config_fs.dart apps/desktop/test/config/config_syntax_test.dart apps/desktop/test/config/config_files_test.dart
git commit -m "feat(desktop): config line syntax, UTF-8/16 decoding, Zig escapes, config-file includes with depth and loop checks, problem model (A9 D5, D6, D8, D31)"
```

---

### Task 2: Paths, colours, the effective `ShellxConfig` (D3, D4, D7, D11–D21, D35)

**Files:**
- Create: `apps/desktop/lib/src/config/config_paths.dart`, `apps/desktop/lib/src/config/config_color.dart`, `apps/desktop/lib/src/config/shellx_config.dart`
- Test: `apps/desktop/test/config/config_paths_test.dart`, `apps/desktop/test/config/shellx_config_test.dart`

**Interfaces:**
- Consumes: Task 1 `ConfigEntry`, `ConfigProblem`, `decodeZigString`, `expandConfigPath`.
- Produces:
  - `final class ConfigPaths { shellx, ghostty (List), themeDirs (List), home, windows; String get shellxDir }`; `ConfigPaths configPathsFor({required bool windows, required Map<String, String> env, required String home})`.
  - `Color? parseConfigColor(String value)`; `double contrastRatio(Color a, Color b)`.
  - `enum CursorShape { block, bar, underline }`, `enum OptionAsAlt { off, both, left, right }`, `enum ConfirmClose { whenRunning, never, always }`, `enum WorkingDirectoryKind { home, inherit, path }`, `final class WorkingDirectory { kind, path }`, `final class UserCommand { name, text, enter, origin }`, `final class KeybindEntry { value, origin }`.
  - `final class ShellxConfig` (fields per spec §3.1 + `fontFamilyOrigins`, `origins`), `static const ShellxConfig defaults`.
  - `const Set<String> kGhosttyKeys`; `bool ghosttyEnabled(List<ConfigEntry> shellx)`; `ShellxConfig buildShellxConfig({required List<ConfigEntry> ghostty, required List<ConfigEntry> shellx, required List<ConfigProblem> problems, required bool macos, required String home, bool windows = false})`.
  - Constants: `kDefaultTerminalPadding = EdgeInsets.fromLTRB(10, 6, 10, 6)`, `kScrollbackDefault = 10000`, `kScrollbackMin = 1000`, `kScrollbackMax = 100000`, `kFontSizeMin = 9`, `kFontSizeMax = 28`, `kPaddingMax = 64`, `kMaxUserCommands = 200`, `kMaxCommandName = 64`, `kMaxCommandText = 16384`.

- [ ] **Step 1: Write the failing tests**

Create `apps/desktop/test/config/config_paths_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/config/config_paths.dart';

/// These strings are pinned: `term/src/api/config_path.rs` (Task 13) must
/// print the same for the same environment (spec D39).
void main() {
  test('macOS without XDG', () {
    final paths = configPathsFor(windows: false, env: const {}, home: '/Users/me');
    expect(paths.shellx, '/Users/me/.config/shellx/config');
    expect(paths.shellxDir, '/Users/me/.config/shellx');
    expect(paths.ghostty, [
      '/Users/me/.config/ghostty/config.ghostty',
      '/Users/me/.config/ghostty/config',
      '/Users/me/Library/Application Support/com.mitchellh.ghostty/config.ghostty',
      '/Users/me/Library/Application Support/com.mitchellh.ghostty/config',
    ]);
    expect(paths.themeDirs, [
      '/Users/me/.config/shellx/themes',
      '/Users/me/.config/ghostty/themes',
      '/Users/me/Library/Application Support/com.mitchellh.ghostty/themes',
      '/Applications/Ghostty.app/Contents/Resources/ghostty/themes',
    ]);
  });

  test('XDG_CONFIG_HOME wins (absolute only)', () {
    final paths = configPathsFor(
      windows: false,
      env: const {'XDG_CONFIG_HOME': '/x/cfg'},
      home: '/Users/me',
    );
    expect(paths.shellx, '/x/cfg/shellx/config');
    expect(paths.ghostty.first, '/x/cfg/ghostty/config.ghostty');
    final relative = configPathsFor(
      windows: false,
      env: const {'XDG_CONFIG_HOME': 'cfg'},
      home: '/Users/me',
    );
    expect(relative.shellx, '/Users/me/.config/shellx/config');
  });

  test('Windows: %APPDATA%\\ShellX\\config; Ghostty only under XDG', () {
    final paths = configPathsFor(
      windows: true,
      env: const {'APPDATA': r'C:\Users\me\AppData\Roaming'},
      home: r'C:\Users\me',
    );
    expect(paths.shellx, r'C:\Users\me\AppData\Roaming\ShellX\config');
    expect(paths.ghostty, [
      r'C:\Users\me\.config\ghostty\config.ghostty',
      r'C:\Users\me\.config\ghostty\config',
    ]);
    expect(paths.themeDirs, [
      r'C:\Users\me\AppData\Roaming\ShellX\themes',
      r'C:\Users\me\.config\ghostty\themes',
    ]);
    final noAppData = configPathsFor(windows: true, env: const {}, home: r'C:\Users\me');
    expect(noAppData.shellx, r'C:\Users\me\AppData\Roaming\ShellX\config');
  });
}
```

Create `apps/desktop/test/config/shellx_config_test.dart`:

```dart
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/config/config_color.dart';
import 'package:shellx_desktop/src/config/config_problem.dart';
import 'package:shellx_desktop/src/config/config_syntax.dart';
import 'package:shellx_desktop/src/config/shellx_config.dart';
import 'package:shellx_desktop/src/ui/theme/shellx_desktop_theme.dart';

const _shellx = '/home/me/.config/shellx/config';
const _ghostty = '/home/me/.config/ghostty/config';

List<ConfigEntry> lines(String text, {String file = _shellx}) =>
    parseConfigText(text, file: file, problems: []);

(ShellxConfig, List<ConfigProblem>) build(
  String shellx, {
  String ghostty = '',
  bool macos = true,
}) {
  final problems = <ConfigProblem>[];
  final config = buildShellxConfig(
    ghostty: lines(ghostty, file: _ghostty),
    shellx: lines(shellx),
    problems: problems,
    macos: macos,
    home: '/home/me',
  );
  return (config, problems);
}

void main() {
  test('nothing set: today\'s behaviour (criterion 1)', () {
    final (c, problems) = build('');
    expect(problems, isEmpty);
    expect(c.fontFamilies, isEmpty);
    expect(c.fontSize, isNull);
    expect(c.theme, isNull);
    expect(c.palette, isEmpty);
    expect(c.cursorShape, CursorShape.block);
    expect(c.scrollbackLimit, 10000);
    expect(c.padding, const EdgeInsets.fromLTRB(10, 6, 10, 6));
    expect(c.padding, ShellxSizes.terminalPadding);
    expect(c.optionAsAlt, OptionAsAlt.off);
    expect(c.confirmClose, ConfirmClose.whenRunning);
    expect(c.workingDirectory.kind, WorkingDirectoryKind.home);
    expect(c.keybinds, isEmpty);
    expect(c.commands, isEmpty);
    expect(c.ghosttyConfig, isTrue);
  });

  group('values (D7, D11–D21)', () {
    test('valid values', () {
      final (c, problems) = build('''
font-family = Fira Code
font-family = Symbols Nerd Font
font-size = 13.5
theme = Dracula
background = #282a36
foreground = f8f8f2
cursor-color = #fff
selection-background = #44475a
palette = 1=#ff5555
palette = 9 = #ff6e6e
cursor-style = bar
scrollback-limit = 20000
window-padding-x = 4,8
window-padding-y = 2
macos-option-as-alt = left
confirm-close-surface = always
working-directory = ~/work
''');
      expect(problems, isEmpty);
      expect(c.fontFamilies, ['Fira Code', 'Symbols Nerd Font']);
      expect(c.fontSize, 13.5);
      expect(c.theme, 'Dracula');
      expect(c.background, const Color(0xFF282A36));
      expect(c.foreground, const Color(0xFFF8F8F2));
      expect(c.cursorColor, const Color(0xFFFFFFFF));
      expect(c.selectionBackground, const Color(0xFF44475A));
      expect(c.palette, {1: const Color(0xFFFF5555), 9: const Color(0xFFFF6E6E)});
      expect(c.cursorShape, CursorShape.bar);
      expect(c.scrollbackLimit, 20000);
      expect(c.padding, const EdgeInsets.fromLTRB(4, 2, 8, 2));
      expect(c.optionAsAlt, OptionAsAlt.left);
      expect(c.confirmClose, ConfirmClose.always);
      expect(c.workingDirectory.kind, WorkingDirectoryKind.path);
      expect(c.workingDirectory.path, '/home/me/work');
      expect(c.origins['font-size']!.line, 3);
      expect([for (final o in c.fontFamilyOrigins) o.line], [1, 2]);
    });

    test('bad values are errors with a literal hint; the key keeps its '
        'earlier value (D8)', () {
      final (c, problems) = build('''
font-size = 15
font-size = to
background = red
cursor-style = beam
confirm-close-surface = yes
working-directory = work
macos-option-as-alt = maybe
''');
      expect(c.fontSize, 15);
      expect(c.background, isNull);
      expect(
        [for (final p in problems) (p.line, p.code, p.severity, p.key, p.value, p.hint)],
        [
          (2, ConfigProblemCode.badValue, ConfigSeverity.error, 'font-size', 'to', '9–28'),
          (3, ConfigProblemCode.badValue, ConfigSeverity.error, 'background', 'red', '#RRGGBB'),
          (4, ConfigProblemCode.badValue, ConfigSeverity.error, 'cursor-style', 'beam', 'block, bar, underline'),
          (5, ConfigProblemCode.badValue, ConfigSeverity.error, 'confirm-close-surface', 'yes', 'true, false, always'),
          (6, ConfigProblemCode.badValue, ConfigSeverity.error, 'working-directory', 'work', 'home, inherit or an absolute path'),
          (7, ConfigProblemCode.badValue, ConfigSeverity.error, 'macos-option-as-alt', 'maybe', 'true, false, left, right'),
        ],
      );
    });

    test('out of range: clamped with a warning', () {
      final (c, problems) = build(
        'font-size = 40\nscrollback-limit = 10\nwindow-padding-x = 100\n',
      );
      expect(c.fontSize, 28);
      expect(c.scrollbackLimit, 1000);
      expect(c.padding.left, 64);
      expect([for (final p in problems) (p.code, p.severity, p.hint, p.detail)], [
        (ConfigProblemCode.outOfRange, ConfigSeverity.warning, '9–28', '28'),
        (ConfigProblemCode.outOfRange, ConfigSeverity.warning, '1000–100000', '1000'),
        (ConfigProblemCode.outOfRange, ConfigSeverity.warning, '0–64', '64'),
      ]);
    });

    test('an empty value resets to the default; a list key is cleared', () {
      final (c, _) = build('''
font-size = 20
font-size =
font-family = A
font-family =
font-family = B
palette = 2=#00ff00
palette =
''');
      expect(c.fontSize, isNull);
      expect(c.fontFamilies, ['B']);
      expect(c.palette, isEmpty);
    });

    test('notes: block_hollow, blink, palette 16+, option-as-alt on Windows', () {
      final (c, problems) = build(
        'cursor-style = block_hollow\ncursor-style-blink = true\npalette = 20=#000000\nmacos-option-as-alt = true\n',
        macos: false,
      );
      expect(c.cursorShape, CursorShape.block);
      expect(c.optionAsAlt, OptionAsAlt.both);
      expect([for (final p in problems) (p.code, p.severity)], [
        (ConfigProblemCode.unsupportedValue, ConfigSeverity.info),
        (ConfigProblemCode.unsupportedValue, ConfigSeverity.info),
        (ConfigProblemCode.unsupportedValue, ConfigSeverity.info),
        (ConfigProblemCode.notOnThisPlatform, ConfigSeverity.info),
      ]);
    });

    test('an unknown key in the ShellX file is a warning', () {
      final (_, problems) = build('copy-on-select = true\n');
      expect(problems.single.code, ConfigProblemCode.unknownKey);
      expect(problems.single.severity, ConfigSeverity.warning);
      expect(problems.single.key, 'copy-on-select');
    });

    test('inherit and home', () {
      expect(build('working-directory = inherit').$1.workingDirectory.kind,
          WorkingDirectoryKind.inherit);
      expect(build('working-directory = home').$1.workingDirectory.kind,
          WorkingDirectoryKind.home);
    });
  });

  group('the Ghostty layer (D4)', () {
    test('only drawing/typing keys; the rest is silent; ShellX wins', () {
      final (c, problems) = build(
        'font-size = 15\n',
        ghostty: '''
font-family = JetBrains Mono
font-size = 12
theme = Dracula
window-padding-x = 30
scrollback-limit = 10000000
keybind = super+d=new_split:left
confirm-close-surface = false
macos-option-as-alt = true
whatever = 1
''',
      );
      expect(problems, isEmpty);
      expect(c.fontFamilies, ['JetBrains Mono']);
      expect(c.fontSize, 15);
      expect(c.theme, 'Dracula');
      expect(c.padding, kDefaultTerminalPadding);
      expect(c.scrollbackLimit, 10000);
      expect(c.keybinds, isEmpty);
      expect(c.confirmClose, ConfirmClose.whenRunning);
      expect(c.optionAsAlt, OptionAsAlt.both);
    });

    test('a bad value of a taken key is a warning at the Ghostty line', () {
      final (_, problems) = build('', ghostty: '\nbackground = nope\n');
      expect((problems.single.file, problems.single.line, problems.single.severity), (
        _ghostty,
        2,
        ConfigSeverity.warning,
      ));
    });

    test('the first ShellX font-family replaces the Ghostty list (D11)', () {
      final (c, _) = build(
        'font-family = Menlo\nfont-family = Symbols\n',
        ghostty: 'font-family = Fira Code\nfont-family = Noto\n',
      );
      expect(c.fontFamilies, ['Menlo', 'Symbols']);
    });

    test('ghosttyEnabled reads the last valid ghostty-config line', () {
      expect(ghosttyEnabled(lines('')), isTrue);
      expect(ghosttyEnabled(lines('ghostty-config = false')), isFalse);
      expect(ghosttyEnabled(lines('ghostty-config = false\nghostty-config = nope')), isFalse);
      expect(ghosttyEnabled(lines('ghostty-config = false\nghostty-config =')), isTrue);
    });
  });

  group('commands and snippets (D35)', () {
    test('name = text; quoted text uses escapes; enter only for command', () {
      final (c, problems) = build(r'''
command = Lint = npm run lint
snippet = Status = "git status\n"
command = Deploy = make deploy -- a=b
''');
      expect(problems, isEmpty);
      expect([for (final x in c.commands) (x.name, x.text, x.enter)], [
        ('Lint', 'npm run lint', true),
        ('Status', 'git status\n', false),
        ('Deploy', 'make deploy -- a=b', true),
      ]);
    });

    test('bad shapes, duplicates and the 200 limit', () {
      final many = [for (var i = 0; i < 201; i++) 'command = c$i = echo $i'].join('\n');
      final (c, problems) = build('''
command = no text here
command = = echo
command = ${'n' * 65} = echo
command = Lint = a
snippet = Lint = b
$many
''');
      expect(c.commands.where((x) => x.name == 'Lint').single.text, 'b');
      expect(c.commands, hasLength(200));
      expect([for (final p in problems) p.code], [
        ConfigProblemCode.badValue,
        ConfigProblemCode.badValue,
        ConfigProblemCode.badValue,
        ConfigProblemCode.duplicate,
        ConfigProblemCode.commandLimit,
      ]);
      expect(problems[3].detail, '4');
    });

    test('an empty command line clears commands, not snippets', () {
      final (c, _) = build('command = A = a\nsnippet = B = b\ncommand =\n');
      expect([for (final x in c.commands) x.name], ['B']);
    });
  });

  test('keybind lines are kept in order for the resolver (Task 4)', () {
    final (c, _) = build('keybind = super+t=new_tab\nkeybind = clear\nkeybind =\nkeybind = super+y=new_tab\n');
    expect([for (final k in c.keybinds) k.value], ['super+y=new_tab']);
  });

  group('colours', () {
    test('parseConfigColor', () {
      expect(parseConfigColor('#1d1f21'), const Color(0xFF1D1F21));
      expect(parseConfigColor('1D1F21'), const Color(0xFF1D1F21));
      expect(parseConfigColor('#abc'), const Color(0xFFAABBCC));
      expect(parseConfigColor('red'), isNull);
      expect(parseConfigColor('#12345'), isNull);
    });

    test('contrastRatio (WCAG)', () {
      expect(contrastRatio(const Color(0xFF000000), const Color(0xFFFFFFFF)),
          closeTo(21, 0.01));
      expect(contrastRatio(const Color(0xFFD4E1E4), const Color(0xFF0B1215)),
          greaterThan(4.5));
    });
  });
}
```

- [ ] **Step 2: Run the tests to see them fail**

Run: `cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/config/config_paths_test.dart test/config/shellx_config_test.dart`
Expected: FAIL — files missing.

- [ ] **Step 3: Implement**

Create `apps/desktop/lib/src/config/config_paths.dart`:

```dart
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

/// Where the configuration lives (A9 spec D3, D4, D13). Pinned by
/// `config_paths_test`; the Rust CLI mirrors it (Task 13).
@immutable
final class ConfigPaths {
  const ConfigPaths({
    required this.shellx,
    required this.ghostty,
    required this.themeDirs,
    required this.home,
    required this.windows,
  });

  final String shellx;

  /// Read in this order; a later file overrides an earlier one (D4).
  final List<String> ghostty;
  final List<String> themeDirs;
  final String home;
  final bool windows;

  String get shellxDir => (windows ? p.windows : p.posix).dirname(shellx);
}

ConfigPaths configPathsFor({
  required bool windows,
  required Map<String, String> env,
  required String home,
}) {
  final ctx = windows ? p.windows : p.posix;
  final xdg = env['XDG_CONFIG_HOME'];
  final xdgBase = xdg != null && xdg.isNotEmpty && ctx.isAbsolute(xdg)
      ? xdg
      : null;
  final appData = env['APPDATA'];
  final shellxDir = xdgBase != null
      ? ctx.join(xdgBase, 'shellx')
      : windows
      ? ctx.join(
          appData != null && appData.isNotEmpty
              ? appData
              : ctx.join(home, 'AppData', 'Roaming'),
          'ShellX',
        )
      : ctx.join(home, '.config', 'shellx');
  final ghosttyXdg = ctx.join(xdgBase ?? ctx.join(home, '.config'), 'ghostty');
  final macGhostty = ctx.join(
    home,
    'Library',
    'Application Support',
    'com.mitchellh.ghostty',
  );
  return ConfigPaths(
    shellx: ctx.join(shellxDir, 'config'),
    ghostty: [
      ctx.join(ghosttyXdg, 'config.ghostty'),
      ctx.join(ghosttyXdg, 'config'),
      if (!windows) ...[
        ctx.join(macGhostty, 'config.ghostty'),
        ctx.join(macGhostty, 'config'),
      ],
    ],
    themeDirs: [
      ctx.join(shellxDir, 'themes'),
      ctx.join(ghosttyXdg, 'themes'),
      if (!windows) ...[
        ctx.join(macGhostty, 'themes'),
        '/Applications/Ghostty.app/Contents/Resources/ghostty/themes',
      ],
    ],
    home: home,
    windows: windows,
  );
}
```

Create `apps/desktop/lib/src/config/config_color.dart`:

```dart
import 'dart:math' as math;

import 'package:flutter/painting.dart';

final RegExp _hex = RegExp(r'^#?([0-9a-fA-F]{6}|[0-9a-fA-F]{3})$');

/// D14: `#RRGGBB`, `RRGGBB` or `#RGB`; anything else (X11 names) is null.
Color? parseConfigColor(String value) {
  final match = _hex.firstMatch(value.trim());
  if (match == null) return null;
  var hex = match.group(1)!;
  if (hex.length == 3) hex = [for (final c in hex.split('')) '$c$c'].join();
  return Color(0xFF000000 | int.parse(hex, radix: 16));
}

double _channel(double v) => v <= 0.03928
    ? v / 12.92
    : math.pow((v + 0.055) / 1.055, 2.4).toDouble();

double _luminance(Color c) =>
    0.2126 * _channel(c.r) + 0.7152 * _channel(c.g) + 0.0722 * _channel(c.b);

/// WCAG 2.x contrast ratio, 1–21.
double contrastRatio(Color a, Color b) {
  final x = _luminance(a);
  final y = _luminance(b);
  return (math.max(x, y) + 0.05) / (math.min(x, y) + 0.05);
}
```

Create `apps/desktop/lib/src/config/shellx_config.dart`:

```dart
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import 'config_color.dart';
import 'config_files.dart';
import 'config_problem.dart';
import 'config_syntax.dart';

const EdgeInsets kDefaultTerminalPadding = EdgeInsets.fromLTRB(10, 6, 10, 6);
const int kScrollbackDefault = 10000;
const int kScrollbackMin = 1000;
const int kScrollbackMax = 100000;
const double kFontSizeMin = 9;
const double kFontSizeMax = 28;
const double kPaddingMax = 64;
const int kMaxUserCommands = 200;
const int kMaxCommandName = 64;
const int kMaxCommandText = 16384;

enum CursorShape { block, bar, underline }

/// D19. `both` = Ghostty's `true`.
enum OptionAsAlt { off, both, left, right }

/// D20. `whenRunning` = Ghostty's `true`.
enum ConfirmClose { whenRunning, never, always }

enum WorkingDirectoryKind { home, inherit, path }

@immutable
final class WorkingDirectory {
  const WorkingDirectory.home() : kind = WorkingDirectoryKind.home, path = null;
  const WorkingDirectory.inherit()
    : kind = WorkingDirectoryKind.inherit,
      path = null;
  const WorkingDirectory.at(String this.path)
    : kind = WorkingDirectoryKind.path;

  final WorkingDirectoryKind kind;
  final String? path;
}

/// D35: a `command` (paste + Enter) or a `snippet` (paste only).
@immutable
final class UserCommand {
  const UserCommand({
    required this.name,
    required this.text,
    required this.enter,
    required this.origin,
  });
  final String name;
  final String text;
  final bool enter;
  final ConfigEntry origin;
}

/// A raw `keybind` value, resolved in `keybindings.dart` (D22).
@immutable
final class KeybindEntry {
  const KeybindEntry(this.value, this.origin);
  final String value;
  final ConfigEntry origin;
}

/// D4: what ShellX takes from a Ghostty file.
const Set<String> kGhosttyKeys = {
  'font-family',
  'font-size',
  'theme',
  'background',
  'foreground',
  'palette',
  'cursor-color',
  'cursor-style',
  'selection-background',
  'macos-option-as-alt',
};

/// The effective configuration (spec §3.1). Defaults = today's behaviour.
@immutable
final class ShellxConfig {
  const ShellxConfig({
    this.fontFamilies = const [],
    this.fontFamilyOrigins = const [],
    this.fontSize,
    this.theme,
    this.background,
    this.foreground,
    this.cursorColor,
    this.selectionBackground,
    this.palette = const {},
    this.cursorShape = CursorShape.block,
    this.scrollbackLimit = kScrollbackDefault,
    this.padding = kDefaultTerminalPadding,
    this.optionAsAlt = OptionAsAlt.off,
    this.confirmClose = ConfirmClose.whenRunning,
    this.workingDirectory = const WorkingDirectory.home(),
    this.keybinds = const [],
    this.commands = const [],
    this.ghosttyConfig = true,
    this.origins = const {},
  });

  static const ShellxConfig defaults = ShellxConfig();

  final List<String> fontFamilies;

  /// The line of each [fontFamilies] entry (font probe problems, D11).
  final List<ConfigEntry> fontFamilyOrigins;
  final double? fontSize;
  final String? theme;
  final Color? background;
  final Color? foreground;
  final Color? cursorColor;
  final Color? selectionBackground;
  final Map<int, Color> palette;
  final CursorShape cursorShape;
  final int scrollbackLimit;
  final EdgeInsets padding;
  final OptionAsAlt optionAsAlt;
  final ConfirmClose confirmClose;
  final WorkingDirectory workingDirectory;
  final List<KeybindEntry> keybinds;
  final List<UserCommand> commands;
  final bool ghosttyConfig;

  /// Key → the line that set its effective value (`shellx config show`).
  final Map<String, ConfigEntry> origins;
}

bool? _bool(String v) => switch (v) {
  'true' => true,
  'false' => false,
  _ => null,
};

/// D4: the last valid `ghostty-config` line of the ShellX chain (an empty
/// value resets to the default, true).
bool ghosttyEnabled(List<ConfigEntry> shellx) {
  var enabled = true;
  for (final e in shellx) {
    if (e.key != 'ghostty-config') continue;
    if (e.value.isEmpty) {
      enabled = true;
    } else {
      enabled = _bool(e.value) ?? enabled;
    }
  }
  return enabled;
}

/// D4/D7: Ghostty lines (only [kGhosttyKeys]) then ShellX lines, as one
/// sequence; later lines win, list keys accumulate, empty resets.
ShellxConfig buildShellxConfig({
  required List<ConfigEntry> ghostty,
  required List<ConfigEntry> shellx,
  required List<ConfigProblem> problems,
  required bool macos,
  required String home,
  bool windows = false,
}) {
  final b = _Builder(problems, macos: macos, home: home, windows: windows);
  for (final e in ghostty) {
    if (kGhosttyKeys.contains(e.key)) b.apply(e, fromGhostty: true);
  }
  for (final e in shellx) {
    b.apply(e, fromGhostty: false);
  }
  return b.build();
}

String _num(double v) =>
    v == v.roundToDouble() ? v.toInt().toString() : v.toString();

final class _Builder {
  _Builder(
    this.problems, {
    required this.macos,
    required this.home,
    required this.windows,
  });

  final List<ConfigProblem> problems;
  final bool macos;
  final String home;
  final bool windows;

  var families = <String>[];
  var familyOrigins = <ConfigEntry>[];
  var familiesFromGhostty = false;
  double? fontSize;
  String? theme;
  Color? background, foreground, cursorColor, selectionBackground;
  final palette = <int, Color>{};
  var cursorShape = CursorShape.block;
  var scrollback = kScrollbackDefault;
  var padX = (kDefaultTerminalPadding.left, kDefaultTerminalPadding.right);
  var padY = (kDefaultTerminalPadding.top, kDefaultTerminalPadding.bottom);
  var optionAsAlt = OptionAsAlt.off;
  var confirmClose = ConfirmClose.whenRunning;
  WorkingDirectory workingDirectory = const WorkingDirectory.home();
  final keybinds = <KeybindEntry>[];
  final commands = <UserCommand>[];
  var commandLimitReported = false;
  var ghosttyConfig = true;
  final origins = <String, ConfigEntry>{};

  ConfigSeverity _bad(bool fromGhostty) =>
      fromGhostty ? ConfigSeverity.warning : ConfigSeverity.error;

  void _problem(
    ConfigEntry e,
    ConfigSeverity severity,
    ConfigProblemCode code, {
    String? value,
    String? hint,
    String? detail,
  }) => problems.add(
    ConfigProblem(
      file: e.file,
      line: e.line,
      severity: severity,
      code: code,
      key: e.key,
      value: value ?? e.value,
      hint: hint,
      detail: detail,
    ),
  );

  void _badValue(ConfigEntry e, bool g, String hint) =>
      _problem(e, _bad(g), ConfigProblemCode.badValue, hint: hint);

  double? _ranged(
    ConfigEntry e,
    String raw,
    double min,
    double max,
    bool g, {
    bool integer = false,
  }) {
    final v = integer ? int.tryParse(raw)?.toDouble() : double.tryParse(raw);
    final hint = '${_num(min)}–${_num(max)}';
    if (v == null || v.isNaN) {
      _badValue(e, g, hint);
      return null;
    }
    final clamped = v.clamp(min, max).toDouble();
    if (clamped != v) {
      _problem(
        e,
        ConfigSeverity.warning,
        ConfigProblemCode.outOfRange,
        value: raw,
        hint: hint,
        detail: _num(clamped),
      );
    }
    return clamped;
  }

  (double, double)? _pair(ConfigEntry e, bool g) {
    final parts = e.value.split(',');
    if (parts.length > 2) {
      _badValue(e, g, 'N or A,B (0–64)');
      return null;
    }
    final values = <double>[];
    for (final part in parts) {
      final v = _ranged(e, part.trim(), 0, kPaddingMax, g);
      if (v == null) return null;
      values.add(v);
    }
    return (values.first, values.last);
  }

  void apply(ConfigEntry e, {required bool fromGhostty}) {
    final g = fromGhostty;
    final v = e.value;
    switch (e.key) {
      case 'font-family':
        if (!g && familiesFromGhostty) {
          families = [];
          familyOrigins = [];
          familiesFromGhostty = false;
        }
        if (v.isEmpty) {
          families = [];
          familyOrigins = [];
        } else {
          families.add(v);
          familyOrigins.add(e);
          if (g) familiesFromGhostty = true;
        }
      case 'font-size':
        if (v.isEmpty) {
          fontSize = null;
        } else {
          final size = _ranged(e, v, kFontSizeMin, kFontSizeMax, g);
          if (size == null) return;
          fontSize = size;
        }
      case 'theme':
        theme = v.isEmpty ? null : v;
      case 'background' ||
          'foreground' ||
          'cursor-color' ||
          'selection-background':
        Color? color;
        if (v.isNotEmpty) {
          color = parseConfigColor(v);
          if (color == null) return _badValue(e, g, '#RRGGBB');
        }
        switch (e.key) {
          case 'background':
            background = color;
          case 'foreground':
            foreground = color;
          case 'cursor-color':
            cursorColor = color;
          default:
            selectionBackground = color;
        }
      case 'palette':
        if (v.isEmpty) {
          palette.clear();
        } else {
          final eq = v.indexOf('=');
          final index = eq < 0 ? null : int.tryParse(v.substring(0, eq).trim());
          final color = eq < 0 ? null : parseConfigColor(v.substring(eq + 1));
          if (index == null || color == null || index < 0 || index > 255) {
            return _badValue(e, g, 'N=#RRGGBB');
          }
          if (index > 15) {
            return _problem(
              e,
              ConfigSeverity.info,
              ConfigProblemCode.unsupportedValue,
              hint: '0–15',
            );
          }
          palette[index] = color;
        }
      case 'cursor-style':
        switch (v) {
          case '' || 'block':
            cursorShape = CursorShape.block;
          case 'bar':
            cursorShape = CursorShape.bar;
          case 'underline':
            cursorShape = CursorShape.underline;
          case 'block_hollow':
            cursorShape = CursorShape.block;
            _problem(
              e,
              ConfigSeverity.info,
              ConfigProblemCode.unsupportedValue,
              hint: 'block',
            );
          default:
            return _badValue(e, g, 'block, bar, underline');
        }
      case 'cursor-style-blink':
        final blink = v.isEmpty ? false : _bool(v);
        if (blink == null) return _badValue(e, g, 'true, false');
        if (blink) {
          _problem(
            e,
            ConfigSeverity.info,
            ConfigProblemCode.unsupportedValue,
            hint: 'false',
          );
        }
      case 'scrollback-limit':
        if (v.isEmpty) {
          scrollback = kScrollbackDefault;
        } else {
          final lines = _ranged(
            e,
            v,
            kScrollbackMin.toDouble(),
            kScrollbackMax.toDouble(),
            g,
            integer: true,
          );
          if (lines == null) return;
          scrollback = lines.toInt();
        }
      case 'window-padding-x':
        if (v.isEmpty) {
          padX = (kDefaultTerminalPadding.left, kDefaultTerminalPadding.right);
        } else {
          final pair = _pair(e, g);
          if (pair == null) return;
          padX = pair;
        }
      case 'window-padding-y':
        if (v.isEmpty) {
          padY = (kDefaultTerminalPadding.top, kDefaultTerminalPadding.bottom);
        } else {
          final pair = _pair(e, g);
          if (pair == null) return;
          padY = pair;
        }
      case 'macos-option-as-alt':
        final mode = switch (v) {
          '' || 'false' => OptionAsAlt.off,
          'true' => OptionAsAlt.both,
          'left' => OptionAsAlt.left,
          'right' => OptionAsAlt.right,
          _ => null,
        };
        if (mode == null) return _badValue(e, g, 'true, false, left, right');
        optionAsAlt = mode;
        if (!macos && !g && mode != OptionAsAlt.off) {
          _problem(e, ConfigSeverity.info, ConfigProblemCode.notOnThisPlatform);
        }
      case 'confirm-close-surface':
        final mode = switch (v) {
          '' || 'true' => ConfirmClose.whenRunning,
          'false' => ConfirmClose.never,
          'always' => ConfirmClose.always,
          _ => null,
        };
        if (mode == null) return _badValue(e, g, 'true, false, always');
        confirmClose = mode;
      case 'working-directory':
        if (v.isEmpty || v == 'home') {
          workingDirectory = const WorkingDirectory.home();
        } else if (v == 'inherit') {
          workingDirectory = const WorkingDirectory.inherit();
        } else {
          final absolute =
              v.startsWith('~') ||
              v.startsWith('/') ||
              (windows && RegExp(r'^[A-Za-z]:[\\/]').hasMatch(v));
          if (!absolute) {
            return _badValue(e, g, 'home, inherit or an absolute path');
          }
          workingDirectory = WorkingDirectory.at(
            expandConfigPath(v, baseDir: home, home: home, windows: windows),
          );
        }
      case 'keybind':
        if (v.isEmpty) {
          keybinds.clear();
        } else {
          keybinds.add(KeybindEntry(v, e));
        }
      case 'command' || 'snippet':
        _command(e, enter: e.key == 'command');
      case 'ghostty-config':
        final on = v.isEmpty ? true : _bool(v);
        if (on == null) return _badValue(e, g, 'true, false');
        ghosttyConfig = on;
      default:
        if (!g) {
          _problem(e, ConfigSeverity.warning, ConfigProblemCode.unknownKey);
        }
        return;
    }
    origins[e.key] = e;
  }

  void _command(ConfigEntry e, {required bool enter}) {
    final v = e.value;
    if (v.isEmpty) {
      commands.removeWhere((c) => c.enter == enter);
      return;
    }
    const hint = 'name = text';
    final eq = v.indexOf('=');
    if (eq < 0) return _badValue(e, false, hint);
    final name = v.substring(0, eq).trim();
    var text = v.substring(eq + 1).trim();
    if (text.length >= 2 && text.startsWith('"') && text.endsWith('"')) {
      final decoded = decodeZigString(text.substring(1, text.length - 1));
      if (decoded == null) return _badValue(e, false, hint);
      text = decoded;
    }
    if (name.isEmpty ||
        name.length > kMaxCommandName ||
        text.isEmpty ||
        text.length > kMaxCommandText) {
      return _badValue(e, false, '$hint, name ≤ 64, text ≤ 16 KiB');
    }
    final previous = commands.indexWhere((c) => c.name == name);
    if (previous >= 0) {
      _problem(
        e,
        ConfigSeverity.info,
        ConfigProblemCode.duplicate,
        detail: '${commands[previous].origin.line}',
      );
      commands.removeAt(previous);
    } else if (commands.length >= kMaxUserCommands) {
      if (!commandLimitReported) {
        commandLimitReported = true;
        _problem(e, ConfigSeverity.warning, ConfigProblemCode.commandLimit);
      }
      return;
    }
    commands.add(UserCommand(name: name, text: text, enter: enter, origin: e));
  }

  ShellxConfig build() => ShellxConfig(
    fontFamilies: List.unmodifiable(families),
    fontFamilyOrigins: List.unmodifiable(familyOrigins),
    fontSize: fontSize,
    theme: theme,
    background: background,
    foreground: foreground,
    cursorColor: cursorColor,
    selectionBackground: selectionBackground,
    palette: Map.unmodifiable(palette),
    cursorShape: cursorShape,
    scrollbackLimit: scrollback,
    padding: EdgeInsets.fromLTRB(padX.$1, padY.$1, padX.$2, padY.$2),
    optionAsAlt: optionAsAlt,
    confirmClose: confirmClose,
    workingDirectory: workingDirectory,
    keybinds: List.unmodifiable(keybinds),
    commands: List.unmodifiable(commands),
    ghosttyConfig: ghosttyConfig,
    origins: Map.unmodifiable(origins),
  );
}
```

Note on `keybind = clear`: the builder keeps it as an entry (the resolver handles it, Task 4); but the test above expects `keybind = clear` followed by `keybind =` to leave only later lines — `keybind =` clears the list, which also drops the `clear` entry, i.e. defaults return (Ghostty: an empty value resets to the default). That is the intended reading.

- [ ] **Step 4: Run the tests**

Run: `cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/config/`
Expected: PASS. Format + analyze clean.

- [ ] **Step 5: Commit**

```bash
git add apps/desktop/lib/src/config/config_paths.dart apps/desktop/lib/src/config/config_color.dart apps/desktop/lib/src/config/shellx_config.dart apps/desktop/test/config/config_paths_test.dart apps/desktop/test/config/shellx_config_test.dart
git commit -m "feat(desktop): config paths (XDG, macOS, Windows APPDATA, Ghostty order), hex colours, the effective ShellxConfig with a Ghostty layer, commands and snippets (A9 D3, D4, D7, D11-D21, D35)"
```

---

### Task 3: Themes → `TerminalTheme`, terminal background, focus outline, contrast (D13–D15)

**Files:**
- Create: `apps/desktop/lib/src/config/config_theme.dart`
- Test: `apps/desktop/test/config/config_theme_test.dart`

**Interfaces:**
- Consumes: Tasks 1–2; `TerminalColors.theme` (A1), `ShellxDesktopColors.accent/bgTerminal/textTitle`.
- Produces:
  - `final class ResolvedTheme { TerminalTheme terminal; Color background; Color focusOutline; String? name; static final ResolvedTheme defaults }`.
  - `Future<({ResolvedTheme theme, List<String> files})> resolveTheme(ShellxConfig config, ConfigPaths paths, {required ConfigFs fs, required List<ConfigProblem> problems})`.
  - `String? themeNameFor(String value)` (`light:A,dark:B` → `B`).
  - `Color focusOutlineFor(Color background)`.

- [ ] **Step 1: Write the failing tests**

Create `apps/desktop/test/config/config_theme_test.dart`:

```dart
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/config/config_paths.dart';
import 'package:shellx_desktop/src/config/config_problem.dart';
import 'package:shellx_desktop/src/config/config_syntax.dart';
import 'package:shellx_desktop/src/config/config_theme.dart';
import 'package:shellx_desktop/src/config/shellx_config.dart';
import 'package:shellx_desktop/src/ui/theme/shellx_desktop_theme.dart';
import 'package:shellx_desktop/src/ui/theme/terminal_colors.dart';

import '../support/memory_config_fs.dart';

final paths = configPathsFor(windows: false, env: const {}, home: '/home/me');
const dracula = '''
palette = 0=#21222c
palette = 1=#ff5555
background = #282a36
foreground = #f8f8f2
cursor-color = #f8f8f2
selection-background = #44475a
window-padding-x = 99
''';

ShellxConfig configOf(String text) => buildShellxConfig(
  ghostty: const [],
  shellx: parseConfigText(text, file: paths.shellx, problems: []),
  problems: [],
  macos: true,
  home: '/home/me',
);

void main() {
  late MemoryConfigFs fs;
  setUp(() => fs = MemoryConfigFs());

  Future<(ResolvedTheme, List<String>, List<ConfigProblem>)> resolve(
    String text,
  ) async {
    final problems = <ConfigProblem>[];
    final r = await resolveTheme(configOf(text), paths, fs: fs, problems: problems);
    return (r.theme, r.files, problems);
  }

  test('no theme: A1 colours exactly', () async {
    final (theme, files, problems) = await resolve('');
    expect(problems, isEmpty);
    expect(files, isEmpty);
    expect(theme.terminal.background, TerminalColors.theme.background);
    expect(theme.terminal.red, TerminalColors.theme.red);
    expect(theme.terminal.selection, TerminalColors.theme.selection);
    expect(theme.terminal.cursor, TerminalColors.theme.cursor);
    expect(theme.background, TerminalColors.background);
    expect(theme.focusOutline, ShellxDesktopColors.accent);
  });

  test('search order: ShellX themes, then Ghostty themes (D13)', () async {
    fs
      ..write('/home/me/.config/ghostty/themes/Dracula', dracula)
      ..write('/Applications/Ghostty.app/Contents/Resources/ghostty/themes/Dracula', 'background = #000000\n');
    var (theme, files, problems) = await resolve('theme = Dracula');
    expect(problems, isEmpty);
    expect(theme.background, const Color(0xFF282A36));
    expect(theme.terminal.black, const Color(0xFF21222C));
    expect(theme.terminal.red, const Color(0xFFFF5555));
    expect(theme.terminal.green, TerminalColors.theme.green); // not in the theme
    expect(theme.name, 'Dracula');
    expect(files, contains('/home/me/.config/ghostty/themes/Dracula'));
    expect(files, contains('/home/me/.config/shellx/themes/Dracula'));

    fs.write('/home/me/.config/shellx/themes/Dracula', 'background = #111111\n');
    (theme, files, problems) = await resolve('theme = Dracula');
    expect(theme.background, const Color(0xFF111111));
  });

  test('explicit colours beat the theme; selection is drawn at 40 %', () async {
    fs.write('/t/dracula', dracula);
    final (theme, _, _) = await resolve(
      'theme = /t/dracula\nbackground = #000000\npalette = 1=#00ff00\n',
    );
    expect(theme.background, const Color(0xFF000000));
    expect(theme.terminal.red, const Color(0xFF00FF00));
    expect(theme.terminal.selection, const Color(0x6644475A));
    expect(theme.terminal.searchHitBackground, theme.terminal.yellow);
    expect(theme.terminal.searchHitForeground, theme.background);
  });

  test('light:/dark: picks dark; "ShellX" is the built-in palette', () async {
    expect(themeNameFor('light:Solarized Light,dark:Dracula'), 'Dracula');
    expect(themeNameFor('dark:A,light:B'), 'A');
    expect(themeNameFor('light:Only'), 'Only');
    expect(themeNameFor('Plain'), 'Plain');
    final (theme, files, problems) = await resolve('theme = ShellX');
    expect(problems, isEmpty);
    expect(files, isEmpty);
    expect(theme.background, TerminalColors.background);
  });

  test('not found: a warning at the theme line, default colours kept', () async {
    final (theme, _, problems) = await resolve('\ntheme = Nope\nforeground = #ffffff\n');
    expect(theme.background, TerminalColors.background);
    expect(theme.terminal.foreground, const Color(0xFFFFFFFF));
    expect((problems.single.code, problems.single.line, problems.single.value), (
      ConfigProblemCode.themeNotFound,
      2,
      'Nope',
    ));
  });

  test('a theme file that is not UTF-8 counts as not found', () async {
    fs.writeBytes('/t/bin', [0xC3, 0x28]);
    final (_, _, problems) = await resolve('theme = /t/bin');
    expect(problems.single.code, ConfigProblemCode.themeNotFound);
  });

  test('a light background moves the focus outline off accent (D15)', () async {
    final (light, _, problems) = await resolve(
      'background = #fdf6e3\nforeground = #657b83\n',
    );
    expect(light.focusOutline, isNot(ShellxDesktopColors.accent));
    expect(focusOutlineFor(const Color(0xFFFDF6E3)), ShellxDesktopColors.bgTerminal);
    // Solarized light text is 4.1:1 — a warning, still applied.
    expect(problems.single.code, ConfigProblemCode.lowContrast);
    expect(problems.single.severity, ConfigSeverity.warning);
    expect(problems.single.detail, '4.1');
  });
}
```

- [ ] **Step 2: Run the tests to see them fail**

Run: `cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/config/config_theme_test.dart`
Expected: FAIL — `config_theme.dart` missing.

- [ ] **Step 3: Implement**

Create `apps/desktop/lib/src/config/config_theme.dart`:

```dart
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/painting.dart';
import 'package:path/path.dart' as p;
import 'package:xterm/xterm.dart';

import '../ui/theme/shellx_desktop_theme.dart';
import '../ui/theme/terminal_colors.dart';
import 'config_color.dart';
import 'config_files.dart';
import 'config_paths.dart';
import 'config_problem.dart';
import 'config_syntax.dart';
import 'shellx_config.dart';

/// What the terminal area draws with (D13–D15).
final class ResolvedTheme {
  const ResolvedTheme({
    required this.terminal,
    required this.background,
    required this.focusOutline,
    this.name,
  });

  static const ResolvedTheme defaults = ResolvedTheme(
    terminal: TerminalColors.theme,
    background: TerminalColors.background,
    focusOutline: ShellxDesktopColors.accent,
  );

  final TerminalTheme terminal;

  /// The terminal area behind and around panes (padding included).
  final Color background;

  /// A3 D16's outline, readable on [background] (D15).
  final Color focusOutline;

  /// The theme name or path in use; null for the built-in palette.
  final String? name;
}

/// `light:A,dark:B` → `B` (ShellX is dark-only); a plain value as is.
String? themeNameFor(String value) {
  if (!value.contains('light:') && !value.contains('dark:')) {
    return value.trim();
  }
  String? light;
  String? dark;
  for (final part in value.split(',')) {
    final t = part.trim();
    if (t.startsWith('dark:')) dark = t.substring(5).trim();
    if (t.startsWith('light:')) light = t.substring(6).trim();
  }
  return dark ?? light;
}

/// D15: `accent` when it reaches 3:1, otherwise the most readable of the
/// dark terminal colour and the title text.
Color focusOutlineFor(Color background) {
  const accent = ShellxDesktopColors.accent;
  if (contrastRatio(accent, background) >= 3) return accent;
  const dark = ShellxDesktopColors.bgTerminal;
  const light = ShellxDesktopColors.textTitle;
  return contrastRatio(dark, background) >= contrastRatio(light, background)
      ? dark
      : light;
}

List<Color> _defaultPalette() {
  const t = TerminalColors.theme;
  return [
    t.black, t.red, t.green, t.yellow, t.blue, t.magenta, t.cyan, t.white,
    t.brightBlack, t.brightRed, t.brightGreen, t.brightYellow,
    t.brightBlue, t.brightMagenta, t.brightCyan, t.brightWhite,
  ];
}

final class _Colors {
  Color? background, foreground, cursor, selection;
  final Map<int, Color> palette = {};
}

void _applyThemeLine(ConfigEntry e, _Colors c) {
  switch (e.key) {
    case 'background':
      c.background = parseConfigColor(e.value) ?? c.background;
    case 'foreground':
      c.foreground = parseConfigColor(e.value) ?? c.foreground;
    case 'cursor-color':
      c.cursor = parseConfigColor(e.value) ?? c.cursor;
    case 'selection-background':
      c.selection = parseConfigColor(e.value) ?? c.selection;
    case 'palette':
      final eq = e.value.indexOf('=');
      if (eq < 0) return;
      final index = int.tryParse(e.value.substring(0, eq).trim());
      final color = parseConfigColor(e.value.substring(eq + 1));
      if (index != null && index >= 0 && index < 16 && color != null) {
        c.palette[index] = color;
      }
  }
}

Future<_Colors?> _readTheme(String path, ConfigFs fs) async {
  try {
    final Uint8List? bytes = await fs.read(path);
    if (bytes == null) return null;
    final entries = parseConfigText(
      decodeConfigBytes(bytes),
      file: path,
      problems: [], // D13: a theme's own problems are not reported
    );
    final colors = _Colors();
    for (final e in entries) {
      _applyThemeLine(e, colors);
    }
    return colors;
  } on FormatException {
    return null;
  } on ConfigTooLarge {
    return null;
  } on FileSystemException {
    return null;
  }
}

Future<({ResolvedTheme theme, List<String> files})> resolveTheme(
  ShellxConfig config,
  ConfigPaths paths, {
  required ConfigFs fs,
  required List<ConfigProblem> problems,
}) async {
  final files = <String>[];
  final ctx = paths.windows ? p.windows : p.posix;
  _Colors? fromTheme;
  String? used;
  final raw = config.theme;
  final name = raw == null ? null : themeNameFor(raw);
  if (name != null && name.isNotEmpty && name.toLowerCase() != 'shellx') {
    final candidates = name.startsWith('~') || ctx.isAbsolute(name)
        ? [expandConfigPath(name, baseDir: paths.home, home: paths.home, windows: paths.windows)]
        : [for (final dir in paths.themeDirs) ctx.join(dir, name)];
    for (final path in candidates) {
      files.add(path);
      fromTheme = await _readTheme(path, fs);
      if (fromTheme != null) {
        used = name;
        break;
      }
    }
    if (fromTheme == null) {
      final at = config.origins['theme'];
      problems.add(
        ConfigProblem(
          file: at?.file ?? paths.shellx,
          line: at?.line ?? 0,
          severity: ConfigSeverity.warning,
          code: ConfigProblemCode.themeNotFound,
          key: 'theme',
          value: name,
        ),
      );
    }
  }

  const base = TerminalColors.theme;
  final palette = _defaultPalette();
  fromTheme?.palette.forEach((i, c) => palette[i] = c);
  config.palette.forEach((i, c) => palette[i] = c);
  final background =
      config.background ?? fromTheme?.background ?? base.background;
  final foreground =
      config.foreground ?? fromTheme?.foreground ?? base.foreground;
  final cursor = config.cursorColor ?? fromTheme?.cursor ?? foreground;
  final selectionSource = config.selectionBackground ?? fromTheme?.selection;
  final selection = selectionSource?.withAlpha(0x66) ?? base.selection;

  final terminal = TerminalTheme(
    cursor: cursor,
    selection: selection,
    foreground: foreground,
    background: background,
    black: palette[0],
    red: palette[1],
    green: palette[2],
    yellow: palette[3],
    blue: palette[4],
    magenta: palette[5],
    cyan: palette[6],
    white: palette[7],
    brightBlack: palette[8],
    brightRed: palette[9],
    brightGreen: palette[10],
    brightYellow: palette[11],
    brightBlue: palette[12],
    brightMagenta: palette[13],
    brightCyan: palette[14],
    brightWhite: palette[15],
    searchHitBackground: palette[3],
    searchHitBackgroundCurrent: palette[6],
    searchHitForeground: background,
  );

  final ratio = contrastRatio(foreground, background);
  if (ratio < 4.5) {
    final at =
        config.origins['foreground'] ??
        config.origins['background'] ??
        config.origins['theme'];
    problems.add(
      ConfigProblem(
        file: at?.file ?? paths.shellx,
        line: at?.line ?? 0,
        severity: ConfigSeverity.warning,
        code: ConfigProblemCode.lowContrast,
        detail: ratio.toStringAsFixed(1),
      ),
    );
  }

  return (
    theme: ResolvedTheme(
      terminal: terminal,
      background: background,
      focusOutline: focusOutlineFor(background),
      name: used,
    ),
    files: files,
  );
}
```

If `TerminalColors.theme` is not `const`-constructible as `ResolvedTheme.defaults` requires (it is `static const` in A1, so it is), keep `defaults` as `static const`. `TerminalTheme`'s constructor parameters are all named and required in xterm 4.0.0 — the list above is the complete set; if the analyzer reports another required field, copy it from `TerminalColors.theme`.

- [ ] **Step 4: Run the tests**

Run: `cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/config/`
Expected: PASS. Format + analyze clean. (If the Solarized ratio prints `4.2` on this Flutter version's colour rounding, update the expected `detail` to the printed value — the assertion is about the warning, not the third digit.)

- [ ] **Step 5: Commit**

```bash
git add apps/desktop/lib/src/config/config_theme.dart apps/desktop/test/config/config_theme_test.dart
git commit -m "feat(desktop): Ghostty theme files (ShellX and Ghostty theme dirs, light:/dark:, paths), explicit colours over themes, readable focus outline, low-contrast warning (A9 D13-D15)"
```

---
### Task 4: Key chords, actions, the default table as data, resolved bindings; shortcut maps built from them (D22–D27, D29)

**Files:**
- Create: `apps/desktop/lib/src/config/keybind_trigger.dart`, `apps/desktop/lib/src/config/keybind_actions.dart`, `apps/desktop/lib/src/config/keybindings.dart`, `apps/desktop/lib/src/ui/terminal/terminal_intents.dart`
- Modify: `apps/desktop/lib/src/ui/terminal/terminal_shortcuts.dart`
- Create (generated in Step 1, then committed): `apps/desktop/test/ui/fixtures/shortcuts_{desktop,view,browser}_{mac,win}.txt`
- Test: `apps/desktop/test/ui/shortcut_golden_test.dart`, `apps/desktop/test/config/keybind_trigger_test.dart`, `apps/desktop/test/config/keybindings_test.dart`

**Interfaces:**
- Consumes: Tasks 1–2 (`ConfigEntry`, `ConfigProblem`, `KeybindEntry`, `OptionAsAlt`, `decodeZigString`); A3/A6 intents and `chordsOf`/`intentForChord` (A6 `lib/src/browser/browser_chords.dart`).
- Produces:
  - `keybind_trigger.dart`: `final class KeyChord { key, control, alt, shift, meta }` (value equality); `KeyChord? parseKeyChord(String text)`; `String chordLabel(KeyChord c, {required bool mac})`; `String sequenceLabel(List<KeyChord> s, {required bool mac})`; `String? chordConfigText(KeyChord c)`; `SingleActivator chordActivator(KeyChord c, {required bool repeats})`; `KeyChord? chordOfEvent(KeyEvent event, HardwareKeyboard keyboard)`; `bool isFunctionKey(LogicalKeyboardKey k)`; `bool isPrintableKey(LogicalKeyboardKey k)`; `String describeActivator(ShortcutActivator a)`.
  - `keybind_actions.dart`: `enum KeyScope { window, browser }`; `enum ActionGroup { tabs, panes, notifications, editing, font, browser, window, config, commands }`; `final class KeyAction { name, param; String get text }`; `final class ActionSpec`; `final Map<String, ActionSpec> kActionSpecs`; `({KeyAction? action, ConfigProblemCode? problem, String? hint}) parseKeyAction(String text)`; `Intent intentForAction(KeyAction a)`; `String describeIntent(Intent i)`.
  - `keybindings.dart`: `final class KeyBinding { sequence, action, origin; spec; scope }`; `final class KeyBindings { platform, all; factory defaults(platform); Map<ShortcutActivator, Intent> map(KeyScope); List<KeyBinding> get sequences; List<List<KeyChord>> triggersOf(KeyAction); String? labelOf(KeyAction); KeyBinding? find(List<KeyChord>, KeyScope) }`; `List<KeyBinding> defaultKeyBindings(TargetPlatform)`; `({String trigger, String action})? splitKeybind(String value)`; `KeyBindings resolveKeyBindings({required TargetPlatform platform, required List<KeybindEntry> entries, required Set<String> commandNames, required OptionAsAlt optionAsAlt, required List<ConfigProblem> problems})`; `({ConfigProblemCode? error, List<ConfigProblemCode> notes}) checkTrigger(List<KeyChord> seq, KeyAction action, {required bool mac, required OptionAsAlt optionAsAlt})`; global `KeyBindings? labelBindings`.
  - `terminal_intents.dart`: every window intent (moved from `terminal_shortcuts.dart`, which re-exports it) plus `CloseWholeTabIntent`, `ReloadConfigIntent`, `OpenConfigIntent`, `CommandPaletteIntent`, `ShowShortcutsIntent`, `ShowConfigProblemsIntent`, `RunUserCommandIntent(String name)`, `SendTextIntent(String text)`, `IgnoreKeyIntent`; `FontBiggerIntent({double step = 1})`, `FontSmallerIntent({double step = 1})`.
  - `terminal_shortcuts.dart`: `desktopShortcuts(platform, {KeyBindings? bindings})`, `terminalViewShortcuts(platform, {bindings})`, `browserPaneShortcuts(platform, {bindings})`, `browserForwardedChords(platform, {required bool loading, KeyBindings? bindings})`, `intentForForwardedChord(chord, platform, {KeyBindings? bindings})` — `bindings == null` = defaults = today's maps.

- [ ] **Step 1: Freeze today's maps (before touching any shortcut code)**

Create `apps/desktop/test/ui/shortcut_golden_test.dart`:

```dart
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/ui/terminal/terminal_shortcuts.dart';

/// Spec D24 / criterion 1: the default tables after A9 are today's tables
/// (plus A9's three new chords, Step 5). The fixtures are written once,
/// from the code as it was before A9 (`WRITE_GOLDEN=1`).
String _activator(ShortcutActivator a) {
  final s = a as SingleActivator;
  return [
        if (s.control) 'ctrl',
        if (s.alt) 'alt',
        if (s.shift) 'shift',
        if (s.meta) 'meta',
        s.trigger.keyId.toRadixString(16),
      ].join('+') +
      (s.includeRepeats ? '' : ' norepeat');
}

String _describe(Intent i) => switch (i) {
  SelectTabIntent(:final position) => 'SelectTabIntent($position)',
  SplitPaneIntent(:final axis) => 'SplitPaneIntent(${axis.name})',
  FocusPaneIntent(:final direction) => 'FocusPaneIntent(${direction.name})',
  ResizePaneIntent(:final direction) => 'ResizePaneIntent(${direction.name})',
  SelectAllIntent(:final fromMenu) =>
    fromMenu ? 'SelectAllIntent(menu)' : 'SelectAllIntent',
  _ => i.runtimeType.toString(),
};

Set<String> signatures(Map<ShortcutActivator, Intent> map) => {
  for (final e in map.entries) '${_activator(e.key)} -> ${_describe(e.value)}',
};

/// Chords A9 adds on purpose (spec D24); empty until Step 5.
Set<String> a9Additions(String map, String platform) => const {};

void main() {
  final maps = <String, Map<ShortcutActivator, Intent> Function(TargetPlatform)>{
    'desktop': desktopShortcuts,
    'view': terminalViewShortcuts,
    'browser': browserPaneShortcuts,
  };
  for (final (name, platform) in [
    ('mac', TargetPlatform.macOS),
    ('win', TargetPlatform.windows),
  ]) {
    for (final MapEntry(key: map, value: build) in maps.entries) {
      test('$map / $name equals the pre-A9 table (D24)', () {
        final file = File('test/ui/fixtures/shortcuts_${map}_$name.txt');
        final actual = signatures(build(platform)).toList()..sort();
        // Two activators for one chord would make a map lookup ambiguous.
        expect(actual.map((s) => s.split(' -> ').first).toSet(), hasLength(actual.length));
        if (Platform.environment['WRITE_GOLDEN'] == '1') {
          file
            ..createSync(recursive: true)
            ..writeAsStringSync('${actual.join('\n')}\n');
        }
        final expected = file
            .readAsLinesSync()
            .where((l) => l.isNotEmpty)
            .toSet();
        expect(actual.toSet(), expected.union(a9Additions(map, name)));
      });
    }
  }
}
```

Run, on the unmodified A1–A7 code: `cd apps/desktop && WRITE_GOLDEN=1 PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/ui/shortcut_golden_test.dart && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/ui/shortcut_golden_test.dart`
Expected: both runs PASS (6 tests); six fixture files exist. Review them by eye (`cat test/ui/fixtures/shortcuts_desktop_mac.txt`): ⌘T `meta+74 norepeat -> NewTabIntent`, F6 `75 -> NextRegionIntent` only in `desktop`, A6's ⌘⇧B present. If A6 registered ⌘⇧B **with** key repeat (`meta+shift+62 -> OpenBrowserPaneIntent` without `norepeat`), A6 spec D7 says "không lặp": edit that one fixture line to add ` norepeat` and record "A6 ⌘⇧B repeat fixed to spec D7" in the ledger. **Do not regenerate the fixtures after this step.**

- [ ] **Step 2: Write the failing tests for the new model**

Create `apps/desktop/test/config/keybind_trigger_test.dart`:

```dart
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/config/keybind_trigger.dart';
import 'package:shellx_desktop/src/config/keybindings.dart';

void main() {
  group('parseKeyChord (D22)', () {
    test('modifier aliases', () {
      const d = KeyChord(LogicalKeyboardKey.keyD, meta: true, shift: true);
      expect(parseKeyChord('super+shift+d'), d);
      expect(parseKeyChord('cmd+shift+d'), d);
      expect(parseKeyChord('Command+Shift+D'), d);
      expect(
        parseKeyChord('control+opt+x'),
        const KeyChord(LogicalKeyboardKey.keyX, control: true, alt: true),
      );
      expect(parseKeyChord('ctrl+option+x'), parseKeyChord('control+alt+x'));
    });

    test('characters and names', () {
      expect(parseKeyChord('super+='), const KeyChord(LogicalKeyboardKey.equal, meta: true));
      expect(parseKeyChord('super+equal'), parseKeyChord('super+='));
      expect(parseKeyChord('ctrl++'), const KeyChord(LogicalKeyboardKey.add, control: true));
      expect(parseKeyChord('ctrl+plus'), parseKeyChord('ctrl++'));
      expect(parseKeyChord('super+,'), parseKeyChord('super+comma'));
      expect(parseKeyChord('arrow_left'), const KeyChord(LogicalKeyboardKey.arrowLeft));
      expect(parseKeyChord('left'), parseKeyChord('arrow_left'));
      expect(parseKeyChord('kp_enter'), const KeyChord(LogicalKeyboardKey.numpadEnter));
      expect(parseKeyChord('f12'), const KeyChord(LogicalKeyboardKey.f12));
      expect(parseKeyChord('digit_1'), parseKeyChord('1'));
      expect(parseKeyChord('return'), parseKeyChord('enter'));
      expect(parseKeyChord('ctrl+ö')!.key.keyId, 0xf6);
      expect(parseKeyChord('ctrl+Ö'), parseKeyChord('ctrl+ö'));
    });

    test('invalid', () {
      for (final bad in ['', 'ctrl+', 'hyper+a', 'ctrl+foo', 'ctrl+a+b', 'ctrl+ab']) {
        expect(parseKeyChord(bad), isNull, reason: bad);
      }
    });
  });

  group('labels (D29; same text as A1–A6 labels)', () {
    String mac(String t) => chordLabel(parseKeyChord(t)!, mac: true);
    String win(String t) => chordLabel(parseKeyChord(t)!, mac: false);
    test('macOS', () {
      expect(mac('super+t'), '⌘T');
      expect(mac('super+shift+d'), '⌘⇧D');
      expect(mac('super+ctrl+='), '⌘⌃=');
      expect(mac('super+shift+enter'), '⌘⇧↩');
      expect(mac('alt+up'), '⌥↑');
      expect(mac('ctrl+a'), '⌃A');
      expect(mac('super+,'), '⌘,');
      expect(sequenceLabel([parseKeyChord('ctrl+a')!, parseKeyChord('c')!], mac: true), '⌃A C');
    });
    test('Windows', () {
      expect(win('ctrl+shift+t'), 'Ctrl+Shift+T');
      expect(win('ctrl+shift+alt+d'), 'Ctrl+Shift+Alt+D');
      expect(win('ctrl+shift+alt+='), 'Ctrl+Shift+Alt+=');
      expect(win('ctrl+shift+enter'), 'Ctrl+Shift+Enter');
      expect(win('alt+up'), 'Alt+↑');
      expect(win('ctrl+,'), 'Ctrl+,');
      expect(win('f5'), 'F5');
    });
  });

  test('config text round-trips every default chord', () {
    for (final platform in [TargetPlatform.macOS, TargetPlatform.windows]) {
      for (final b in defaultKeyBindings(platform)) {
        for (final c in b.sequence) {
          final text = chordConfigText(c);
          expect(text, isNotNull, reason: '$c');
          expect(parseKeyChord(text!), c, reason: text);
        }
      }
    }
    expect(chordConfigText(const KeyChord(LogicalKeyboardKey.keyN, control: true, alt: true)), 'ctrl+alt+n');
    expect(chordConfigText(const KeyChord(LogicalKeyboardKey.comma, meta: true, shift: true)), 'shift+super+comma');
  });

  test('chordActivator carries the modifiers and the repeat flag', () {
    final a = chordActivator(
      const KeyChord(LogicalKeyboardKey.keyD, meta: true, shift: true),
      repeats: false,
    );
    expect((a.trigger, a.meta, a.shift, a.control, a.alt, a.includeRepeats), (
      LogicalKeyboardKey.keyD,
      true,
      true,
      false,
      false,
      false,
    ));
    expect(describeActivator(a), 'shift+meta+64 norepeat');
  });

  test('key classes', () {
    expect(isFunctionKey(LogicalKeyboardKey.f6), isTrue);
    expect(isFunctionKey(LogicalKeyboardKey.keyF), isFalse);
    expect(isPrintableKey(LogicalKeyboardKey.keyQ), isTrue);
    expect(isPrintableKey(LogicalKeyboardKey.comma), isTrue);
    expect(isPrintableKey(LogicalKeyboardKey.arrowLeft), isFalse);
  });
}
```

Create `apps/desktop/test/config/keybindings_test.dart`:

```dart
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/config/config_problem.dart';
import 'package:shellx_desktop/src/config/config_syntax.dart';
import 'package:shellx_desktop/src/config/keybind_actions.dart';
import 'package:shellx_desktop/src/config/keybind_trigger.dart';
import 'package:shellx_desktop/src/config/keybindings.dart';
import 'package:shellx_desktop/src/config/shellx_config.dart';
import 'package:shellx_desktop/src/terminal/pane_layout.dart';
import 'package:shellx_desktop/src/ui/terminal/terminal_intents.dart';

const mac = TargetPlatform.macOS;
const win = TargetPlatform.windows;

(KeyBindings, List<ConfigProblem>) resolve(
  String text, {
  TargetPlatform platform = mac,
  Set<String> commands = const {},
  OptionAsAlt option = OptionAsAlt.off,
}) {
  final problems = <ConfigProblem>[];
  final entries = [
    for (final e in parseConfigText(text, file: '/c', problems: []))
      if (e.key == 'keybind') KeybindEntry(e.value, e),
  ];
  final b = resolveKeyBindings(
    platform: platform,
    entries: entries,
    commandNames: commands,
    optionAsAlt: option,
    problems: problems,
  );
  return (b, problems);
}

Intent? lookup(KeyBindings b, String chord, {KeyScope scope = KeyScope.window}) {
  final c = parseKeyChord(chord)!;
  for (final e in b.map(scope).entries) {
    final a = e.key as SingleActivator;
    if (a.trigger == c.key &&
        a.control == c.control &&
        a.alt == c.alt &&
        a.shift == c.shift &&
        a.meta == c.meta) {
      return e.value;
    }
  }
  return null;
}

List<(int, ConfigProblemCode, ConfigSeverity)> codes(List<ConfigProblem> p) => [
  for (final x in p) (x.line, x.code, x.severity),
];

void main() {
  test('no lines: the defaults', () {
    final (b, problems) = resolve('');
    expect(problems, isEmpty);
    expect(b.all, hasLength(defaultKeyBindings(mac).length));
    expect(lookup(b, 'super+t'), isA<NewTabIntent>());
    expect(lookup(b, 'super+shift+p'), isA<CommandPaletteIntent>());
    expect(lookup(b, 'super+,'), isA<OpenConfigIntent>());
    expect(lookup(b, 'super+shift+,'), isA<ReloadConfigIntent>());
    expect(lookup(b, 'super+l', scope: KeyScope.browser), isA<BrowserFocusAddressIntent>());
    final (w, _) = resolve('', platform: win);
    expect(lookup(w, 'ctrl+shift+p'), isA<CommandPaletteIntent>());
    expect(lookup(w, 'ctrl+,'), isA<OpenConfigIntent>());
  });

  test('a new chord adds; the default stays (criterion 5)', () {
    final (b, problems) = resolve('keybind = super+shift+t=new_split:down');
    expect(problems, isEmpty);
    expect(lookup(b, 'super+shift+t'), isA<SplitPaneIntent>().having((i) => i.axis, 'axis', SplitAxis.column));
    expect(lookup(b, 'super+shift+d'), isA<SplitPaneIntent>());
    expect(b.labelOf(const KeyAction('new_split', 'down')), '⌘⇧D');
  });

  test('unbind, clear, ignore, empty value', () {
    var (b, _) = resolve('keybind = super+d=unbind');
    expect(lookup(b, 'super+d'), isNull);
    expect(b.labelOf(const KeyAction('new_split', 'right')), isNull);
    (b, _) = resolve('keybind = clear\nkeybind = super+k=new_tab');
    expect(b.all, hasLength(1));
    expect(lookup(b, 'super+t'), isNull);
    (b, _) = resolve('keybind = super+k=ignore');
    expect(lookup(b, 'super+k'), isA<IgnoreKeyIntent>());
  });

  test('later lines win; two user lines on one chord leave a note (D27)', () {
    final (b, problems) = resolve(
      'keybind = super+k=new_tab\nkeybind = super+k=new_workspace\nkeybind = super+t=new_workspace',
    );
    expect(lookup(b, 'super+k'), isA<NewWorkspaceIntent>());
    expect(lookup(b, 'super+t'), isA<NewWorkspaceIntent>());
    expect(codes(problems), [(2, ConfigProblemCode.duplicate, ConfigSeverity.info)]);
    expect(problems.single.detail, '1');
  });

  test('D25 errors drop the line', () {
    final (b, problems) = resolve('''
keybind = super+q=new_tab
keybind = ctrl+space=new_tab
keybind = a=new_tab
keybind = shift+a=new_tab
keybind = f6=new_tab
keybind = shift+f6=new_tab
keybind = escape=new_tab
keybind = f1=new_tab
keybind = escape=browser_stop
''');
    expect(codes(problems), [
      (1, ConfigProblemCode.reservedTrigger, ConfigSeverity.error),
      (2, ConfigProblemCode.reservedTrigger, ConfigSeverity.error),
      (3, ConfigProblemCode.plainKeyTrigger, ConfigSeverity.error),
      (4, ConfigProblemCode.plainKeyTrigger, ConfigSeverity.error),
      (5, ConfigProblemCode.regionTrigger, ConfigSeverity.error),
      (6, ConfigProblemCode.regionTrigger, ConfigSeverity.error),
      (7, ConfigProblemCode.plainKeyTrigger, ConfigSeverity.error),
    ]);
    expect(problems.first.value, '⌘Q');
    expect(lookup(b, 'f1'), isA<NewTabIntent>());
    expect(lookup(b, 'super+q'), isNull);
    final (_, w) = resolve('keybind = super+d=new_tab\nkeybind = alt+f4=new_tab', platform: win);
    expect(codes(w), [
      (1, ConfigProblemCode.reservedTrigger, ConfigSeverity.error),
      (2, ConfigProblemCode.reservedTrigger, ConfigSeverity.error),
    ]);
  });

  test('D25 notes keep the binding', () {
    final (b, problems) = resolve(
      'keybind = ctrl+c=new_tab\nkeybind = alt+e=new_tab\nkeybind = ctrl+left=new_tab',
    );
    expect(codes(problems), [
      (1, ConfigProblemCode.shellKeyTrigger, ConfigSeverity.info),
      (2, ConfigProblemCode.optionKeyTrigger, ConfigSeverity.info),
      (3, ConfigProblemCode.missionControlTrigger, ConfigSeverity.info),
    ]);
    expect(lookup(b, 'ctrl+c'), isA<NewTabIntent>());
    final (_, withAlt) = resolve('keybind = alt+e=new_tab', option: OptionAsAlt.both);
    expect(withAlt, isEmpty);
    final (_, altGr) = resolve('keybind = ctrl+alt+q=new_tab', platform: win);
    expect(codes(altGr), [(1, ConfigProblemCode.altGrTrigger, ConfigSeverity.info)]);
  });

  test('bad triggers, actions, parameters, prefixes', () {
    final (b, problems) = resolve('''
keybind = super+foo=new_tab
keybind = super+k=frobnicate
keybind = super+k=new_split:left
keybind = super+k=new_tab:x
keybind = global:super+k=new_tab
keybind = performable:super+j=new_tab
keybind = super+k
keybind = super+k=increase_font_size:9
''');
    expect(codes(problems), [
      (1, ConfigProblemCode.badTrigger, ConfigSeverity.error),
      (2, ConfigProblemCode.unknownAction, ConfigSeverity.error),
      (3, ConfigProblemCode.badActionParam, ConfigSeverity.error),
      (4, ConfigProblemCode.badActionParam, ConfigSeverity.error),
      (5, ConfigProblemCode.unsupportedPrefix, ConfigSeverity.error),
      (6, ConfigProblemCode.unsupportedPrefix, ConfigSeverity.info),
      (7, ConfigProblemCode.badTrigger, ConfigSeverity.error),
      (8, ConfigProblemCode.badActionParam, ConfigSeverity.error),
    ]);
    expect(problems[2].hint, 'right, down');
    expect(lookup(b, 'super+j'), isA<NewTabIntent>());
  });

  test('sequences: two steps, too long, a prefix shadows a single chord', () {
    final (b, problems) = resolve('''
keybind = ctrl+a=new_workspace
keybind = ctrl+a>c=new_tab
keybind = ctrl+a>b>c=new_tab
''');
    expect(b.sequences.single.sequence, [parseKeyChord('ctrl+a'), parseKeyChord('c')]);
    expect(lookup(b, 'ctrl+a'), isNull);
    expect(b.labelOf(const KeyAction('new_tab')), '⌘T');
    expect(codes(problems), [
      (1, ConfigProblemCode.shellKeyTrigger, ConfigSeverity.info),
      (2, ConfigProblemCode.shellKeyTrigger, ConfigSeverity.info),
      (3, ConfigProblemCode.sequenceTooLong, ConfigSeverity.error),
      (2, ConfigProblemCode.sequencePrefixShadows, ConfigSeverity.warning),
    ]);
    expect(problems.last.value, '⌃A');
  });

  test('run_command, text, csi, esc, resize amount, font step', () {
    final (b, problems) = resolve(
      r'''
keybind = super+l=run_command:Lint
keybind = super+m=run_command:Nope
keybind = ctrl+g=text:git status\n
keybind = super+u=csi:A
keybind = super+i=esc:b
keybind = super+o=text:\q
keybind = super+alt+left=resize_split:left,10
keybind = super+9=increase_font_size:2
''',
      commands: {'Lint'},
    );
    expect(lookup(b, 'super+l'), isA<RunUserCommandIntent>().having((i) => i.name, 'name', 'Lint'));
    expect(lookup(b, 'ctrl+g'), isA<SendTextIntent>().having((i) => i.text, 'text', 'git status\n'));
    expect(lookup(b, 'super+u'), isA<SendTextIntent>().having((i) => i.text, 'text', '\x1b[A'));
    expect(lookup(b, 'super+i'), isA<SendTextIntent>().having((i) => i.text, 'text', '\x1bb'));
    expect(lookup(b, 'super+alt+left'), isA<ResizePaneIntent>());
    expect(lookup(b, 'super+9'), isA<FontBiggerIntent>().having((i) => i.step, 'step', 2));
    expect(codes(problems), [
      (2, ConfigProblemCode.unknownCommand, ConfigSeverity.warning),
      (3, ConfigProblemCode.shellKeyTrigger, ConfigSeverity.info),
      (6, ConfigProblemCode.badActionParam, ConfigSeverity.error),
      (7, ConfigProblemCode.unsupportedValue, ConfigSeverity.info),
    ]);
  });

  test('splitKeybind splits at the first "=" not right after "+" or ">"', () {
    expect(splitKeybind('super+==increase_font_size'), (trigger: 'super+=', action: 'increase_font_size'));
    expect(splitKeybind('ctrl+a>==new_tab'), (trigger: 'ctrl+a>=', action: 'new_tab'));
    expect(splitKeybind('ctrl+g=text:a=b'), (trigger: 'ctrl+g', action: 'text:a=b'));
    expect(splitKeybind('nothing'), isNull);
    expect(splitKeybind('ctrl+g='), isNull);
  });

  test('labels on Windows; sequences', () {
    final (b, _) = resolve('keybind = ctrl+shift+k>n=new_tab', platform: win);
    expect(b.labelOf(const KeyAction('new_tab')), 'Ctrl+Shift+T');
    expect(sequenceLabel(b.sequences.single.sequence, mac: false), 'Ctrl+Shift+K N');
  });
}
```

- [ ] **Step 3: Run the tests to see them fail**

Run: `cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/config/keybind_trigger_test.dart test/config/keybindings_test.dart`
Expected: FAIL — files missing.

- [ ] **Step 4: Implement**

Create `apps/desktop/lib/src/ui/terminal/terminal_intents.dart`: **move** every `class …Intent extends Intent` from `terminal_shortcuts.dart` into it verbatim (A1–A4: `NewTabIntent` … `PreviousRegionIntent`; A3: `SplitPaneIntent`, `FocusPaneIntent`, `TogglePaneZoomIntent`, `EqualizePanesIntent`, `ResizePaneIntent`; A6: `OpenBrowserPaneIntent`, `BrowserFocusAddressIntent`, `BrowserReloadIntent`, `BrowserBackIntent`, `BrowserForwardIntent`, `BrowserStopIntent`), keeping their doc comments, with the import `import '../../terminal/pane_layout.dart';`. Then change the two font intents and append the A9 intents:

```dart
class FontBiggerIntent extends Intent {
  const FontBiggerIntent({this.step = 1});

  /// Points (A9 D12: `increase_font_size:N`).
  final double step;
}

class FontSmallerIntent extends Intent {
  const FontSmallerIntent({this.step = 1});
  final double step;
}

/// A9 D23 `close_tab`: every pane of the selected tab (A3 D6's row ×).
class CloseWholeTabIntent extends Intent {
  const CloseWholeTabIntent();
}

/// A9 D9 ⌘⇧, / Ctrl+Shift+,.
class ReloadConfigIntent extends Intent {
  const ReloadConfigIntent();
}

/// A9 D37 ⌘, / Ctrl+,.
class OpenConfigIntent extends Intent {
  const OpenConfigIntent();
}

/// A9 D33 ⌘⇧P / Ctrl+Shift+P.
class CommandPaletteIntent extends Intent {
  const CommandPaletteIntent();
}

/// A9 D32: the shortcut editor (no default chord).
class ShowShortcutsIntent extends Intent {
  const ShowShortcutsIntent();
}

/// A9 D36: the problems panel (no default chord).
class ShowConfigProblemsIntent extends Intent {
  const ShowConfigProblemsIntent();
}

/// A9 D35 `run_command:<name>`.
class RunUserCommandIntent extends Intent {
  const RunUserCommandIntent(this.name);
  final String name;
}

/// A9 D31 `text:` / `csi:` / `esc:` — already decoded.
class SendTextIntent extends Intent {
  const SendTextIntent(this.text);
  final String text;
}

/// A9 D22 `ignore`: the key is swallowed.
class IgnoreKeyIntent extends Intent {
  const IgnoreKeyIntent();
}
```

Create `apps/desktop/lib/src/config/keybind_trigger.dart`:

```dart
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// One key combination (A9 D22). [meta] is super: ⌘ on macOS, Win on
/// Windows.
@immutable
final class KeyChord {
  const KeyChord(
    this.key, {
    this.control = false,
    this.alt = false,
    this.shift = false,
    this.meta = false,
  });

  final LogicalKeyboardKey key;
  final bool control;
  final bool alt;
  final bool shift;
  final bool meta;

  bool get hasCommandModifier => control || alt || meta;

  @override
  bool operator ==(Object other) =>
      other is KeyChord &&
      other.key == key &&
      other.control == control &&
      other.alt == alt &&
      other.shift == shift &&
      other.meta == meta;

  @override
  int get hashCode => Object.hash(key, control, alt, shift, meta);

  @override
  String toString() => chordConfigText(this) ?? 'KeyChord(${key.debugName})';
}

const _digits = [
  LogicalKeyboardKey.digit0, LogicalKeyboardKey.digit1, LogicalKeyboardKey.digit2,
  LogicalKeyboardKey.digit3, LogicalKeyboardKey.digit4, LogicalKeyboardKey.digit5,
  LogicalKeyboardKey.digit6, LogicalKeyboardKey.digit7, LogicalKeyboardKey.digit8,
  LogicalKeyboardKey.digit9,
];

const _numpadDigits = [
  LogicalKeyboardKey.numpad0, LogicalKeyboardKey.numpad1, LogicalKeyboardKey.numpad2,
  LogicalKeyboardKey.numpad3, LogicalKeyboardKey.numpad4, LogicalKeyboardKey.numpad5,
  LogicalKeyboardKey.numpad6, LogicalKeyboardKey.numpad7, LogicalKeyboardKey.numpad8,
  LogicalKeyboardKey.numpad9,
];

const _functionKeys = [
  LogicalKeyboardKey.f1, LogicalKeyboardKey.f2, LogicalKeyboardKey.f3,
  LogicalKeyboardKey.f4, LogicalKeyboardKey.f5, LogicalKeyboardKey.f6,
  LogicalKeyboardKey.f7, LogicalKeyboardKey.f8, LogicalKeyboardKey.f9,
  LogicalKeyboardKey.f10, LogicalKeyboardKey.f11, LogicalKeyboardKey.f12,
  LogicalKeyboardKey.f13, LogicalKeyboardKey.f14, LogicalKeyboardKey.f15,
  LogicalKeyboardKey.f16, LogicalKeyboardKey.f17, LogicalKeyboardKey.f18,
  LogicalKeyboardKey.f19, LogicalKeyboardKey.f20, LogicalKeyboardKey.f21,
  LogicalKeyboardKey.f22, LogicalKeyboardKey.f23, LogicalKeyboardKey.f24,
];

/// Canonical config names first: [chordConfigText] writes the first name
/// of each key.
final List<(String, LogicalKeyboardKey)> _names = [
  ('enter', LogicalKeyboardKey.enter),
  ('return', LogicalKeyboardKey.enter),
  ('tab', LogicalKeyboardKey.tab),
  ('escape', LogicalKeyboardKey.escape),
  ('space', LogicalKeyboardKey.space),
  ('backspace', LogicalKeyboardKey.backspace),
  ('delete', LogicalKeyboardKey.delete),
  ('insert', LogicalKeyboardKey.insert),
  ('home', LogicalKeyboardKey.home),
  ('end', LogicalKeyboardKey.end),
  ('page_up', LogicalKeyboardKey.pageUp),
  ('page_down', LogicalKeyboardKey.pageDown),
  ('arrow_left', LogicalKeyboardKey.arrowLeft),
  ('left', LogicalKeyboardKey.arrowLeft),
  ('arrow_right', LogicalKeyboardKey.arrowRight),
  ('right', LogicalKeyboardKey.arrowRight),
  ('arrow_up', LogicalKeyboardKey.arrowUp),
  ('up', LogicalKeyboardKey.arrowUp),
  ('arrow_down', LogicalKeyboardKey.arrowDown),
  ('down', LogicalKeyboardKey.arrowDown),
  ('equal', LogicalKeyboardKey.equal),
  ('minus', LogicalKeyboardKey.minus),
  ('plus', LogicalKeyboardKey.add),
  ('comma', LogicalKeyboardKey.comma),
  ('period', LogicalKeyboardKey.period),
  ('slash', LogicalKeyboardKey.slash),
  ('backslash', LogicalKeyboardKey.backslash),
  ('semicolon', LogicalKeyboardKey.semicolon),
  ('quote', LogicalKeyboardKey.quote),
  ('backquote', LogicalKeyboardKey.backquote),
  ('grave', LogicalKeyboardKey.backquote),
  ('bracket_left', LogicalKeyboardKey.bracketLeft),
  ('bracket_right', LogicalKeyboardKey.bracketRight),
  ('kp_enter', LogicalKeyboardKey.numpadEnter),
  ('kp_add', LogicalKeyboardKey.numpadAdd),
  ('kp_subtract', LogicalKeyboardKey.numpadSubtract),
  for (var i = 0; i <= 9; i++) ('kp_$i', _numpadDigits[i]),
  for (var i = 0; i <= 9; i++) ('digit_$i', _digits[i]),
  for (var i = 1; i <= 24; i++) ('f$i', _functionKeys[i - 1]),
];

final Map<String, LogicalKeyboardKey> _byName = {
  for (final (name, key) in _names) name: key,
};

final Map<LogicalKeyboardKey, String> _nameOf = () {
  final map = <LogicalKeyboardKey, String>{};
  for (final (name, key) in _names) {
    map.putIfAbsent(key, () => name);
  }
  // Letters and digits are written as themselves.
  for (var i = 0; i <= 9; i++) {
    map[_digits[i]] = '$i';
  }
  return map;
}();

const Map<String, LogicalKeyboardKey> _punctuation = {
  '=': LogicalKeyboardKey.equal,
  '-': LogicalKeyboardKey.minus,
  '[': LogicalKeyboardKey.bracketLeft,
  ']': LogicalKeyboardKey.bracketRight,
  ';': LogicalKeyboardKey.semicolon,
  "'": LogicalKeyboardKey.quote,
  ',': LogicalKeyboardKey.comma,
  '.': LogicalKeyboardKey.period,
  '/': LogicalKeyboardKey.slash,
  r'\': LogicalKeyboardKey.backslash,
  '`': LogicalKeyboardKey.backquote,
  '+': LogicalKeyboardKey.add,
};

LogicalKeyboardKey? _keyForToken(String token) {
  final lower = token.toLowerCase();
  final named = _byName[lower];
  if (named != null) return named;
  if (token.runes.length != 1) return null;
  final punct = _punctuation[token];
  if (punct != null) return punct;
  final cp = lower.runes.single;
  if (cp >= 0x61 && cp <= 0x7a) return LogicalKeyboardKey.findKeyByKeyId(cp);
  if (cp >= 0x30 && cp <= 0x39) return _digits[cp - 0x30];
  if (cp < 0x80) return null; // other ASCII: not a key token
  return LogicalKeyboardKey(cp); // layout characters (ö, é…), like Ghostty
}

/// D22: `mod+mod+key`; `+` itself as `ctrl++` or `plus`.
KeyChord? parseKeyChord(String text) {
  final step = text.trim();
  if (step.isEmpty) return null;
  final String keyToken;
  final List<String> mods;
  if (step == '+') {
    keyToken = '+';
    mods = const [];
  } else if (step.endsWith('++')) {
    keyToken = '+';
    mods = step.substring(0, step.length - 2).split('+');
  } else {
    final parts = step.split('+');
    keyToken = parts.last;
    mods = parts.sublist(0, parts.length - 1);
  }
  if (keyToken.isEmpty) return null;
  var control = false, alt = false, shift = false, meta = false;
  for (final m in mods) {
    switch (m.toLowerCase()) {
      case 'ctrl' || 'control':
        control = true;
      case 'alt' || 'opt' || 'option':
        alt = true;
      case 'shift':
        shift = true;
      case 'super' || 'cmd' || 'command':
        meta = true;
      default:
        return null;
    }
  }
  final key = _keyForToken(keyToken);
  if (key == null) return null;
  return KeyChord(key, control: control, alt: alt, shift: shift, meta: meta);
}

bool isFunctionKey(LogicalKeyboardKey k) => _functionKeys.contains(k);

bool isPrintableKey(LogicalKeyboardKey k) {
  if (k == LogicalKeyboardKey.space) return true;
  if (_punctuation.containsValue(k)) return true;
  final id = k.keyId;
  return id >= 0x21 && id < 0x110000 && k.keyLabel.runes.length == 1;
}

String _keyLabel(LogicalKeyboardKey k, {required bool mac}) {
  final special = <LogicalKeyboardKey, String>{
    LogicalKeyboardKey.enter: mac ? '↩' : 'Enter',
    LogicalKeyboardKey.numpadEnter: mac ? '⌤' : 'Num Enter',
    LogicalKeyboardKey.tab: 'Tab',
    LogicalKeyboardKey.escape: 'Esc',
    LogicalKeyboardKey.space: 'Space',
    LogicalKeyboardKey.backspace: mac ? '⌫' : 'Backspace',
    LogicalKeyboardKey.delete: mac ? '⌦' : 'Delete',
    LogicalKeyboardKey.insert: 'Insert',
    LogicalKeyboardKey.home: 'Home',
    LogicalKeyboardKey.end: 'End',
    LogicalKeyboardKey.pageUp: 'PgUp',
    LogicalKeyboardKey.pageDown: 'PgDn',
    LogicalKeyboardKey.arrowLeft: '←',
    LogicalKeyboardKey.arrowRight: '→',
    LogicalKeyboardKey.arrowUp: '↑',
    LogicalKeyboardKey.arrowDown: '↓',
    LogicalKeyboardKey.add: '+',
    LogicalKeyboardKey.numpadAdd: 'Num+',
    LogicalKeyboardKey.numpadSubtract: 'Num−',
  };
  final s = special[k];
  if (s != null) return s;
  final fn = _functionKeys.indexOf(k);
  if (fn >= 0) return 'F${fn + 1}';
  final pad = _numpadDigits.indexOf(k);
  if (pad >= 0) return 'Num$pad';
  final label = k.keyLabel;
  return label.isEmpty ? (k.debugName ?? '?') : label.toUpperCase();
}

/// D29: macOS ⌘⌃⌥⇧ then the key (the order A1–A6 labels already use:
/// "⌘⇧D", "⌘⌃="); Windows Ctrl+Shift+Alt+Win+key ("Ctrl+Shift+Alt+D").
String chordLabel(KeyChord c, {required bool mac}) {
  final key = _keyLabel(c.key, mac: mac);
  if (mac) {
    return '${c.meta ? '⌘' : ''}${c.control ? '⌃' : ''}'
        '${c.alt ? '⌥' : ''}${c.shift ? '⇧' : ''}$key';
  }
  return [
    if (c.control) 'Ctrl',
    if (c.shift) 'Shift',
    if (c.alt) 'Alt',
    if (c.meta) 'Win',
    key,
  ].join('+');
}

String sequenceLabel(List<KeyChord> s, {required bool mac}) =>
    s.map((c) => chordLabel(c, mac: mac)).join(' ');

/// The config spelling (`ctrl+alt+shift+super+key`); null for a key with
/// no spelling (the recorder refuses it).
String? chordConfigText(KeyChord c) {
  var name = _nameOf[c.key];
  if (name == null) {
    final id = c.key.keyId;
    if (id >= 0x61 && id <= 0x7a) {
      name = String.fromCharCode(id);
    } else if (id >= 0x80 && id < 0x110000 && c.key.keyLabel.isNotEmpty) {
      name = String.fromCharCode(id);
    } else {
      return null;
    }
  }
  return [
    if (c.control) 'ctrl',
    if (c.alt) 'alt',
    if (c.shift) 'shift',
    if (c.meta) 'super',
    name,
  ].join('+');
}

SingleActivator chordActivator(KeyChord c, {required bool repeats}) =>
    SingleActivator(
      c.key,
      control: c.control,
      alt: c.alt,
      shift: c.shift,
      meta: c.meta,
      includeRepeats: repeats,
    );

/// The golden fixtures' spelling of an activator (Task 4 Step 1).
String describeActivator(ShortcutActivator a) {
  final s = a as SingleActivator;
  return [
        if (s.control) 'ctrl',
        if (s.alt) 'alt',
        if (s.shift) 'shift',
        if (s.meta) 'meta',
        s.trigger.keyId.toRadixString(16),
      ].join('+') +
      (s.includeRepeats ? '' : ' norepeat');
}

final Set<LogicalKeyboardKey> _modifierKeys = {
  LogicalKeyboardKey.shiftLeft, LogicalKeyboardKey.shiftRight,
  LogicalKeyboardKey.controlLeft, LogicalKeyboardKey.controlRight,
  LogicalKeyboardKey.altLeft, LogicalKeyboardKey.altRight,
  LogicalKeyboardKey.metaLeft, LogicalKeyboardKey.metaRight,
  LogicalKeyboardKey.shift, LogicalKeyboardKey.control,
  LogicalKeyboardKey.alt, LogicalKeyboardKey.meta,
  LogicalKeyboardKey.capsLock, LogicalKeyboardKey.fn,
};

/// The chord a key-down makes; null for a modifier on its own.
KeyChord? chordOfEvent(KeyEvent event, HardwareKeyboard keyboard) {
  if (_modifierKeys.contains(event.logicalKey)) return null;
  return KeyChord(
    event.logicalKey,
    control: keyboard.isControlPressed,
    alt: keyboard.isAltPressed,
    shift: keyboard.isShiftPressed,
    meta: keyboard.isMetaPressed,
  );
}
```

Create `apps/desktop/lib/src/config/keybind_actions.dart`:

```dart
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../terminal/pane_layout.dart';
import '../ui/terminal/terminal_intents.dart';
import 'config_problem.dart';
import 'config_syntax.dart';

enum KeyScope { window, browser }

/// UI-A9 §4.1 groups, in display order.
enum ActionGroup {
  tabs,
  panes,
  notifications,
  editing,
  font,
  browser,
  window,
  config,
  commands,
}

/// `name` or `name:param` (D23).
@immutable
final class KeyAction {
  const KeyAction(this.name, [this.param]);
  final String name;
  final String? param;

  String get text => param == null ? name : '$name:$param';

  @override
  bool operator ==(Object other) =>
      other is KeyAction && other.name == name && other.param == param;

  @override
  int get hashCode => Object.hash(name, param);

  @override
  String toString() => text;
}

/// [param] normalises a parameter (null = invalid); it receives null when
/// the action is written without ':'. A spec with no [param] takes none.
final class ActionSpec {
  const ActionSpec(
    this.name,
    this.group, {
    this.scope = KeyScope.window,
    this.repeats = false,
    this.param,
    this.paramHint,
    this.inPalette = true,
  });

  final String name;
  final ActionGroup group;
  final KeyScope scope;
  final bool repeats;
  final String? Function(String? raw)? param;
  final String? paramHint;
  final bool inPalette;
}

String? _oneOf(Set<String> allowed, String? raw) =>
    raw != null && allowed.contains(raw.trim()) ? raw.trim() : null;

String? _direction(String? raw) {
  if (raw == null) return null;
  final first = raw.split(',').first.trim();
  return switch (first) {
    'left' || 'right' || 'up' || 'down' => first,
    'top' => 'up',
    'bottom' => 'down',
    _ => null,
  };
}

String _num(double v) =>
    v == v.roundToDouble() ? v.toInt().toString() : v.toString();

String? _fontStep(String? raw) {
  if (raw == null) return '1';
  final v = double.tryParse(raw.trim());
  if (v == null || v < 0.5 || v > 8) return null;
  return _num(v);
}

String? _tabNumber(String? raw) {
  final n = int.tryParse(raw?.trim() ?? '');
  return n != null && n >= 1 && n <= 9 ? '$n' : null;
}

String? _name(String? raw) =>
    raw == null || raw.trim().isEmpty ? null : raw.trim();

String? _escaped(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  final decoded = decodeZigString(raw);
  return decoded == null || decoded.length > 4096 ? null : raw;
}

const _textHint = r'a Zig string, e.g. text:ls\n';

final Map<String, ActionSpec> kActionSpecs = {
  for (final s in <ActionSpec>[
    const ActionSpec('new_tab', ActionGroup.tabs),
    const ActionSpec('close_surface', ActionGroup.tabs),
    const ActionSpec('close_tab', ActionGroup.tabs),
    const ActionSpec('new_workspace', ActionGroup.tabs),
    const ActionSpec('goto_tab', ActionGroup.tabs,
        repeats: true, param: _tabNumber, paramHint: '1–9', inPalette: false),
    const ActionSpec('next_tab', ActionGroup.tabs, repeats: true),
    const ActionSpec('previous_tab', ActionGroup.tabs, repeats: true),
    ActionSpec('new_split', ActionGroup.panes,
        param: (r) => _oneOf({'right', 'down'}, r), paramHint: 'right, down'),
    const ActionSpec('goto_split', ActionGroup.panes,
        repeats: true, param: _direction, paramHint: 'left, right, up, down'),
    const ActionSpec('resize_split', ActionGroup.panes,
        repeats: true, param: _direction, paramHint: 'left, right, up, down'),
    const ActionSpec('toggle_split_zoom', ActionGroup.panes),
    const ActionSpec('equalize_splits', ActionGroup.panes),
    const ActionSpec('toggle_notifications', ActionGroup.notifications),
    const ActionSpec('jump_to_unread', ActionGroup.notifications),
    const ActionSpec('copy_to_clipboard', ActionGroup.editing, repeats: true),
    const ActionSpec('paste_from_clipboard', ActionGroup.editing, repeats: true),
    const ActionSpec('select_all', ActionGroup.editing, repeats: true),
    const ActionSpec('increase_font_size', ActionGroup.font,
        repeats: true, param: _fontStep, paramHint: '0.5–8'),
    const ActionSpec('decrease_font_size', ActionGroup.font,
        repeats: true, param: _fontStep, paramHint: '0.5–8'),
    const ActionSpec('reset_font_size', ActionGroup.font, repeats: true),
    const ActionSpec('open_browser', ActionGroup.browser),
    const ActionSpec('browser_focus_address', ActionGroup.browser,
        scope: KeyScope.browser, repeats: true),
    const ActionSpec('browser_reload', ActionGroup.browser,
        scope: KeyScope.browser, repeats: true),
    const ActionSpec('browser_back', ActionGroup.browser,
        scope: KeyScope.browser, repeats: true),
    const ActionSpec('browser_forward', ActionGroup.browser,
        scope: KeyScope.browser, repeats: true),
    const ActionSpec('browser_stop', ActionGroup.browser,
        scope: KeyScope.browser, repeats: true),
    const ActionSpec('next_region', ActionGroup.window, repeats: true),
    const ActionSpec('previous_region', ActionGroup.window, repeats: true),
    const ActionSpec('toggle_command_palette', ActionGroup.window, inPalette: false),
    const ActionSpec('reload_config', ActionGroup.config),
    const ActionSpec('open_config', ActionGroup.config),
    const ActionSpec('show_shortcuts', ActionGroup.config),
    const ActionSpec('show_config_problems', ActionGroup.config),
    const ActionSpec('run_command', ActionGroup.commands,
        param: _name, paramHint: 'a command name', inPalette: false),
    const ActionSpec('text', ActionGroup.commands,
        repeats: true, param: _escaped, paramHint: _textHint, inPalette: false),
    const ActionSpec('csi', ActionGroup.commands,
        repeats: true, param: _escaped, paramHint: _textHint, inPalette: false),
    const ActionSpec('esc', ActionGroup.commands,
        repeats: true, param: _escaped, paramHint: _textHint, inPalette: false),
    const ActionSpec('ignore', ActionGroup.commands, repeats: true, inPalette: false),
  ])
    s.name: s,
};

/// D23. Exactly one of `action` / `problem` is set.
({KeyAction? action, ConfigProblemCode? problem, String? hint}) parseKeyAction(
  String text,
) {
  final colon = text.indexOf(':');
  final name = (colon < 0 ? text : text.substring(0, colon)).trim();
  final raw = colon < 0 ? null : text.substring(colon + 1);
  final spec = kActionSpecs[name];
  if (spec == null) {
    return (action: null, problem: ConfigProblemCode.unknownAction, hint: null);
  }
  final check = spec.param;
  if (check == null) {
    return raw == null
        ? (action: KeyAction(name), problem: null, hint: null)
        : (
            action: null,
            problem: ConfigProblemCode.badActionParam,
            hint: 'no parameter',
          );
  }
  final param = check(raw);
  if (param == null) {
    return (
      action: null,
      problem: ConfigProblemCode.badActionParam,
      hint: spec.paramHint,
    );
  }
  return (action: KeyAction(name, param), problem: null, hint: null);
}

PaneDirection _dir(String p) => PaneDirection.values.byName(p);

/// The window or browser intent an action stands for.
Intent intentForAction(KeyAction a) => switch (a.name) {
  'new_tab' => const NewTabIntent(),
  'close_surface' => const CloseTabIntent(),
  'close_tab' => const CloseWholeTabIntent(),
  'new_workspace' => const NewWorkspaceIntent(),
  'goto_tab' => SelectTabIntent(int.parse(a.param!)),
  'next_tab' => const NextTabIntent(),
  'previous_tab' => const PreviousTabIntent(),
  'new_split' => SplitPaneIntent(
    a.param == 'down' ? SplitAxis.column : SplitAxis.row,
  ),
  'goto_split' => FocusPaneIntent(_dir(a.param!)),
  'resize_split' => ResizePaneIntent(_dir(a.param!)),
  'toggle_split_zoom' => const TogglePaneZoomIntent(),
  'equalize_splits' => const EqualizePanesIntent(),
  'toggle_notifications' => const ToggleNotificationsPanelIntent(),
  'jump_to_unread' => const JumpToNextUnreadIntent(),
  'copy_to_clipboard' => const CopySelectionIntent(),
  'paste_from_clipboard' => const PasteClipboardIntent(),
  'select_all' => const SelectAllIntent(),
  'increase_font_size' => FontBiggerIntent(step: double.parse(a.param ?? '1')),
  'decrease_font_size' => FontSmallerIntent(step: double.parse(a.param ?? '1')),
  'reset_font_size' => const FontResetIntent(),
  'open_browser' => const OpenBrowserPaneIntent(),
  'browser_focus_address' => const BrowserFocusAddressIntent(),
  'browser_reload' => const BrowserReloadIntent(),
  'browser_back' => const BrowserBackIntent(),
  'browser_forward' => const BrowserForwardIntent(),
  'browser_stop' => const BrowserStopIntent(),
  'next_region' => const NextRegionIntent(),
  'previous_region' => const PreviousRegionIntent(),
  'toggle_command_palette' => const CommandPaletteIntent(),
  'reload_config' => const ReloadConfigIntent(),
  'open_config' => const OpenConfigIntent(),
  'show_shortcuts' => const ShowShortcutsIntent(),
  'show_config_problems' => const ShowConfigProblemsIntent(),
  'run_command' => RunUserCommandIntent(a.param!),
  'text' => SendTextIntent(decodeZigString(a.param!)!),
  'csi' => SendTextIntent('\x1b[${decodeZigString(a.param!)!}'),
  'esc' => SendTextIntent('\x1b${decodeZigString(a.param!)!}'),
  'ignore' => const IgnoreKeyIntent(),
  _ => throw ArgumentError.value(a.name, 'action'),
};

/// The golden fixtures' spelling of an intent (Task 4 Step 1).
String describeIntent(Intent i) => switch (i) {
  SelectTabIntent(:final position) => 'SelectTabIntent($position)',
  SplitPaneIntent(:final axis) => 'SplitPaneIntent(${axis.name})',
  FocusPaneIntent(:final direction) => 'FocusPaneIntent(${direction.name})',
  ResizePaneIntent(:final direction) => 'ResizePaneIntent(${direction.name})',
  SelectAllIntent(:final fromMenu) =>
    fromMenu ? 'SelectAllIntent(menu)' : 'SelectAllIntent',
  FontBiggerIntent(:final step) when step != 1 => 'FontBiggerIntent($step)',
  FontSmallerIntent(:final step) when step != 1 => 'FontSmallerIntent($step)',
  RunUserCommandIntent(:final name) => 'RunUserCommandIntent($name)',
  _ => i.runtimeType.toString(),
};
```

(If the A6 intent class names differ from `OpenBrowserPaneIntent`/`Browser…Intent` as merged, use the merged names here and in `terminal_intents.dart`; record any rename in the ledger.)

Create `apps/desktop/lib/src/config/keybindings.dart`:

```dart
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'config_problem.dart';
import 'config_syntax.dart';
import 'keybind_actions.dart';
import 'keybind_trigger.dart';
import 'shellx_config.dart';

/// One trigger (one chord, or a two-step sequence, D28) and its action.
@immutable
final class KeyBinding {
  const KeyBinding(this.sequence, this.action, {this.origin});
  final List<KeyChord> sequence;
  final KeyAction action;

  /// The config line; null for a default.
  final ConfigEntry? origin;

  ActionSpec get spec => kActionSpecs[action.name]!;
  KeyScope get scope => spec.scope;
}

/// The effective table of one platform (spec §3.2).
final class KeyBindings {
  KeyBindings(this.platform, Iterable<KeyBinding> all)
    : all = List.unmodifiable(all);

  factory KeyBindings.defaults(TargetPlatform platform) => _defaults.putIfAbsent(
    platform,
    () => KeyBindings(platform, defaultKeyBindings(platform)),
  );

  static final Map<TargetPlatform, KeyBindings> _defaults = {};

  final TargetPlatform platform;
  final List<KeyBinding> all;

  bool get _mac => platform == TargetPlatform.macOS;

  Map<ShortcutActivator, Intent> map(KeyScope scope) => {
    for (final b in all)
      if (b.sequence.length == 1 && b.scope == scope)
        chordActivator(b.sequence.single, repeats: b.spec.repeats):
            intentForAction(b.action),
  };

  List<KeyBinding> get sequences => [
    for (final b in all)
      if (b.sequence.length == 2) b,
  ];

  List<List<KeyChord>> triggersOf(KeyAction a) => [
    for (final b in all)
      if (b.action == a) b.sequence,
  ];

  /// D29: the first trigger's label; null when the action is unbound.
  String? labelOf(KeyAction a) {
    final t = triggersOf(a);
    return t.isEmpty ? null : sequenceLabel(t.first, mac: _mac);
  }

  KeyBinding? find(List<KeyChord> sequence, KeyScope scope) => all
      .where((b) => b.scope == scope && listEquals(b.sequence, sequence))
      .firstOrNull;
}

/// D29: the table shortcut labels read. The config controller sets it after
/// every load and clears it when disposed; null = the platform defaults.
KeyBindings? labelBindings;

const _arrows = [
  (LogicalKeyboardKey.arrowLeft, 'left'),
  (LogicalKeyboardKey.arrowRight, 'right'),
  (LogicalKeyboardKey.arrowUp, 'up'),
  (LogicalKeyboardKey.arrowDown, 'down'),
];

const _digitKeys = [
  LogicalKeyboardKey.digit1, LogicalKeyboardKey.digit2, LogicalKeyboardKey.digit3,
  LogicalKeyboardKey.digit4, LogicalKeyboardKey.digit5, LogicalKeyboardKey.digit6,
  LogicalKeyboardKey.digit7, LogicalKeyboardKey.digit8, LogicalKeyboardKey.digit9,
];

/// D24: A1–A6's tables, chord for chord (pinned by the golden fixtures),
/// then A9's three chords. Plain F6 / Shift+F6 are not bindings (D25):
/// `desktopShortcuts` adds them.
List<KeyBinding> defaultKeyBindings(TargetPlatform platform) {
  final mac = platform == TargetPlatform.macOS;
  KeyChord primary(LogicalKeyboardKey k) => mac
      ? KeyChord(k, meta: true)
      : KeyChord(k, control: true, shift: true);
  KeyChord shifted(LogicalKeyboardKey k) => mac
      ? KeyChord(k, meta: true, shift: true)
      : KeyChord(k, control: true, shift: true);
  KeyChord font(LogicalKeyboardKey k, {bool shift = false}) => mac
      ? KeyChord(k, meta: true, shift: shift)
      : KeyChord(k, control: true, shift: shift);
  KeyBinding b(KeyChord c, String name, [String? param]) =>
      KeyBinding([c], KeyAction(name, param));
  return [
    b(primary(LogicalKeyboardKey.keyT), 'new_tab'),
    b(primary(LogicalKeyboardKey.keyW), 'close_surface'),
    b(shifted(LogicalKeyboardKey.keyN), 'new_workspace'),
    b(shifted(LogicalKeyboardKey.keyI), 'toggle_notifications'),
    b(shifted(LogicalKeyboardKey.keyU), 'jump_to_unread'),
    b(primary(LogicalKeyboardKey.keyC), 'copy_to_clipboard'),
    b(primary(LogicalKeyboardKey.keyV), 'paste_from_clipboard'),
    b(primary(LogicalKeyboardKey.keyA), 'select_all'),
    for (var i = 0; i < _digitKeys.length; i++)
      b(
        mac
            ? KeyChord(_digitKeys[i], meta: true)
            : KeyChord(_digitKeys[i], control: true, alt: true),
        'goto_tab',
        '${i + 1}',
      ),
    b(const KeyChord(LogicalKeyboardKey.tab, control: true), 'next_tab'),
    b(
      const KeyChord(LogicalKeyboardKey.tab, control: true, shift: true),
      'previous_tab',
    ),
    b(
      mac
          ? const KeyChord(LogicalKeyboardKey.keyD, meta: true)
          : const KeyChord(LogicalKeyboardKey.keyD, control: true, shift: true),
      'new_split',
      'right',
    ),
    b(
      mac
          ? const KeyChord(LogicalKeyboardKey.keyD, meta: true, shift: true)
          : const KeyChord(
              LogicalKeyboardKey.keyD,
              control: true,
              shift: true,
              alt: true,
            ),
      'new_split',
      'down',
    ),
    for (final (key, dir) in _arrows) ...[
      b(
        mac
            ? KeyChord(key, meta: true, alt: true)
            : KeyChord(key, control: true, alt: true),
        'goto_split',
        dir,
      ),
      b(
        mac
            ? KeyChord(key, meta: true, control: true)
            : KeyChord(key, control: true, shift: true, alt: true),
        'resize_split',
        dir,
      ),
    ],
    for (final enter in [
      LogicalKeyboardKey.enter,
      LogicalKeyboardKey.numpadEnter,
    ])
      b(
        mac
            ? KeyChord(enter, meta: true, shift: true)
            : KeyChord(enter, control: true, shift: true),
        'toggle_split_zoom',
      ),
    b(
      mac
          ? const KeyChord(LogicalKeyboardKey.equal, meta: true, control: true)
          : const KeyChord(
              LogicalKeyboardKey.equal,
              control: true,
              shift: true,
              alt: true,
            ),
      'equalize_splits',
    ),
    b(font(LogicalKeyboardKey.equal), 'increase_font_size', '1'),
    b(font(LogicalKeyboardKey.equal, shift: true), 'increase_font_size', '1'),
    b(font(LogicalKeyboardKey.add), 'increase_font_size', '1'),
    b(font(LogicalKeyboardKey.numpadAdd), 'increase_font_size', '1'),
    b(font(LogicalKeyboardKey.minus), 'decrease_font_size', '1'),
    b(font(LogicalKeyboardKey.numpadSubtract), 'decrease_font_size', '1'),
    b(font(LogicalKeyboardKey.digit0), 'reset_font_size'),
    b(font(LogicalKeyboardKey.numpad0), 'reset_font_size'),
    b(const KeyChord(LogicalKeyboardKey.f6, control: true), 'next_region'),
    b(
      const KeyChord(LogicalKeyboardKey.f6, control: true, shift: true),
      'previous_region',
    ),
    // A6 W1 / D15.
    b(
      mac
          ? const KeyChord(LogicalKeyboardKey.keyB, meta: true, shift: true)
          : const KeyChord(
              LogicalKeyboardKey.keyB,
              control: true,
              shift: true,
              alt: true,
            ),
      'open_browser',
    ),
    if (mac) ...[
      b(const KeyChord(LogicalKeyboardKey.keyL, meta: true), 'browser_focus_address'),
      b(const KeyChord(LogicalKeyboardKey.keyR, meta: true), 'browser_reload'),
      b(const KeyChord(LogicalKeyboardKey.bracketLeft, meta: true), 'browser_back'),
      b(const KeyChord(LogicalKeyboardKey.bracketRight, meta: true), 'browser_forward'),
    ] else ...[
      b(const KeyChord(LogicalKeyboardKey.keyL, control: true), 'browser_focus_address'),
      b(const KeyChord(LogicalKeyboardKey.keyR, control: true), 'browser_reload'),
      b(const KeyChord(LogicalKeyboardKey.f5), 'browser_reload'),
      b(const KeyChord(LogicalKeyboardKey.arrowLeft, alt: true), 'browser_back'),
      b(const KeyChord(LogicalKeyboardKey.arrowRight, alt: true), 'browser_forward'),
    ],
    b(const KeyChord(LogicalKeyboardKey.escape), 'browser_stop'),
    // A9 D24.
    b(
      mac
          ? const KeyChord(LogicalKeyboardKey.comma, meta: true, shift: true)
          : const KeyChord(LogicalKeyboardKey.comma, control: true, shift: true),
      'reload_config',
    ),
    b(
      mac
          ? const KeyChord(LogicalKeyboardKey.comma, meta: true)
          : const KeyChord(LogicalKeyboardKey.comma, control: true),
      'open_config',
    ),
    b(shifted(LogicalKeyboardKey.keyP), 'toggle_command_palette'),
  ];
}

/// D22: split at the first `=` that is not right after `+` or `>` (so
/// `super+==…` binds the `=` key).
({String trigger, String action})? splitKeybind(String value) {
  for (var i = 1; i < value.length; i++) {
    if (value[i] == '=' && value[i - 1] != '+' && value[i - 1] != '>') {
      final trigger = value.substring(0, i).trim();
      final action = value.substring(i + 1).trim();
      if (trigger.isEmpty || action.isEmpty) return null;
      return (trigger: trigger, action: action);
    }
  }
  return null;
}

final Set<KeyChord> _reservedMac = {
  for (final t in [
    'super+q', 'super+h', 'super+alt+h', 'super+m', 'super+tab',
    'super+shift+tab', 'super+space', 'ctrl+space', 'ctrl+super+space',
    'super+grave', 'super+shift+grave', 'super+alt+escape', 'ctrl+super+q',
    'ctrl+super+f', 'super+shift+3', 'super+shift+4', 'super+shift+5',
  ])
    parseKeyChord(t)!,
};

final Set<KeyChord> _reservedWindows = {
  for (final t in [
    'alt+f4', 'alt+tab', 'alt+shift+tab', 'alt+escape', 'ctrl+escape',
    'ctrl+shift+escape', 'alt+space', 'ctrl+alt+delete',
  ])
    parseKeyChord(t)!,
};

bool _reserved(KeyChord c, {required bool mac}) =>
    mac ? _reservedMac.contains(c) : (c.meta || _reservedWindows.contains(c));

bool _isLetter(LogicalKeyboardKey k) => k.keyId >= 0x61 && k.keyId <= 0x7a;

bool _isArrow(LogicalKeyboardKey k) =>
    k == LogicalKeyboardKey.arrowLeft ||
    k == LogicalKeyboardKey.arrowRight ||
    k == LogicalKeyboardKey.arrowUp ||
    k == LogicalKeyboardKey.arrowDown;

/// D25: an error drops the binding; notes keep it.
({ConfigProblemCode? error, List<ConfigProblemCode> notes}) checkTrigger(
  List<KeyChord> seq,
  KeyAction action, {
  required bool mac,
  required OptionAsAlt optionAsAlt,
}) {
  for (final c in seq) {
    if (_reserved(c, mac: mac)) {
      return (error: ConfigProblemCode.reservedTrigger, notes: const []);
    }
  }
  final c = seq.first;
  if (c.key == LogicalKeyboardKey.f6 && !c.control && !c.alt && !c.meta) {
    return (error: ConfigProblemCode.regionTrigger, notes: const []);
  }
  if (!c.hasCommandModifier) {
    final allowed =
        isFunctionKey(c.key) ||
        (c.key == LogicalKeyboardKey.escape && action.name == 'browser_stop');
    if (!allowed) {
      return (error: ConfigProblemCode.plainKeyTrigger, notes: const []);
    }
  }
  final notes = <ConfigProblemCode>[];
  if (c.control && !c.alt && !c.meta && !c.shift && _isLetter(c.key)) {
    notes.add(ConfigProblemCode.shellKeyTrigger);
  }
  if (mac &&
      c.alt &&
      !c.control &&
      !c.meta &&
      isPrintableKey(c.key) &&
      optionAsAlt == OptionAsAlt.off) {
    notes.add(ConfigProblemCode.optionKeyTrigger);
  }
  if (!mac && c.control && c.alt && isPrintableKey(c.key)) {
    notes.add(ConfigProblemCode.altGrTrigger);
  }
  if (mac && c.control && !c.meta && !c.alt && _isArrow(c.key)) {
    notes.add(ConfigProblemCode.missionControlTrigger);
  }
  return (error: null, notes: notes);
}

final RegExp _prefix = RegExp(r'^(global|all|unconsumed|performable):');

/// D22–D27: the defaults, then each `keybind` line in order.
KeyBindings resolveKeyBindings({
  required TargetPlatform platform,
  required List<KeybindEntry> entries,
  required Set<String> commandNames,
  required OptionAsAlt optionAsAlt,
  required List<ConfigProblem> problems,
}) {
  final mac = platform == TargetPlatform.macOS;
  final slots = <KeyBinding>[...defaultKeyBindings(platform)];

  void report(
    ConfigEntry at,
    ConfigSeverity severity,
    ConfigProblemCode code, {
    String? value,
    String? hint,
    String? detail,
  }) => problems.add(
    ConfigProblem(
      file: at.file,
      line: at.line,
      severity: severity,
      code: code,
      key: 'keybind',
      value: value,
      hint: hint,
      detail: detail,
    ),
  );

  for (final entry in entries) {
    final at = entry.origin;
    final text = entry.value.trim();
    if (text == 'clear') {
      slots.clear();
      continue;
    }
    final split = splitKeybind(text);
    if (split == null) {
      report(at, ConfigSeverity.error, ConfigProblemCode.badTrigger, value: text);
      continue;
    }
    var trigger = split.trigger;
    var refused = false;
    for (var m = _prefix.firstMatch(trigger); m != null; m = _prefix.firstMatch(trigger)) {
      final prefix = m.group(1)!;
      if (prefix == 'global') {
        report(at, ConfigSeverity.error, ConfigProblemCode.unsupportedPrefix,
            value: 'global:');
        refused = true;
        break;
      }
      report(at, ConfigSeverity.info, ConfigProblemCode.unsupportedPrefix,
          value: '$prefix:');
      trigger = trigger.substring(m.end);
    }
    if (refused) continue;
    final steps = trigger.split('>');
    if (steps.length > 2) {
      report(at, ConfigSeverity.error, ConfigProblemCode.sequenceTooLong);
      continue;
    }
    final seq = [for (final s in steps) parseKeyChord(s)];
    if (seq.any((c) => c == null)) {
      report(at, ConfigSeverity.error, ConfigProblemCode.badTrigger, value: trigger);
      continue;
    }
    final sequence = seq.cast<KeyChord>();
    if (split.action == 'unbind') {
      slots.removeWhere((b) => listEquals(b.sequence, sequence));
      continue;
    }
    final parsed = parseKeyAction(split.action);
    final action = parsed.action;
    if (action == null) {
      report(at, ConfigSeverity.error, parsed.problem!,
          value: split.action, hint: parsed.hint);
      continue;
    }
    if (action.name == 'run_command' && !commandNames.contains(action.param)) {
      report(at, ConfigSeverity.warning, ConfigProblemCode.unknownCommand,
          value: action.param);
      continue;
    }
    final label = sequenceLabel(sequence, mac: mac);
    final rule = checkTrigger(sequence, action, mac: mac, optionAsAlt: optionAsAlt);
    if (rule.error != null) {
      report(at, ConfigSeverity.error, rule.error!, value: label);
      continue;
    }
    for (final note in rule.notes) {
      report(at, ConfigSeverity.info, note, value: label);
    }
    if (action.name == 'resize_split' && split.action.contains(',')) {
      report(at, ConfigSeverity.info, ConfigProblemCode.unsupportedValue,
          value: split.action, hint: '5 %');
    }
    final scope = kActionSpecs[action.name]!.scope;
    bool same(KeyBinding b) => b.scope == scope && listEquals(b.sequence, sequence);
    final previous = slots.where(same).firstOrNull;
    if (previous?.origin != null && previous!.action != action) {
      report(at, ConfigSeverity.info, ConfigProblemCode.duplicate,
          detail: '${previous.origin!.line}');
    }
    slots
      ..removeWhere(same)
      ..add(KeyBinding(sequence, action, origin: at));
  }

  // D27: a sequence's first step no longer works on its own.
  for (final s in [...slots.where((b) => b.sequence.length == 2)]) {
    final prefix = [s.sequence.first];
    final shadowed = slots
        .where((b) => b.sequence.length == 1 && listEquals(b.sequence, prefix))
        .toList();
    if (shadowed.isEmpty) continue;
    slots.removeWhere(shadowed.contains);
    if (s.origin != null) {
      report(s.origin!, ConfigSeverity.warning,
          ConfigProblemCode.sequencePrefixShadows,
          value: chordLabel(prefix.single, mac: mac));
    }
  }
  return KeyBindings(platform, slots);
}
```

Now rewrite `apps/desktop/lib/src/ui/terminal/terminal_shortcuts.dart`. Keep A6's chord helpers and `_pageKeeps` as merged; the file becomes:

```dart
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../browser/browser_chords.dart';
import '../../config/keybind_actions.dart';
import '../../config/keybindings.dart';
import 'terminal_intents.dart';

export 'terminal_intents.dart';

KeyBindings _table(KeyBindings? bindings, TargetPlatform platform) =>
    bindings ?? KeyBindings.defaults(platform);

/// Spec criterion 2 and UI §3.6: the workspace's `Shortcuts`. Built from
/// the effective bindings (A9 D24; null = the defaults, A1–A6 exactly).
/// Plain F6 / Shift+F6 are fixed here (A9 D25): outside the terminal they
/// always cycle regions.
Map<ShortcutActivator, Intent> desktopShortcuts(
  TargetPlatform platform, {
  KeyBindings? bindings,
}) => {
  ..._table(bindings, platform).map(KeyScope.window),
  const SingleActivator(LogicalKeyboardKey.f6): const NextRegionIntent(),
  const SingleActivator(LogicalKeyboardKey.f6, shift: true):
      const PreviousRegionIntent(),
};

/// What every `TerminalView` gets: the window bindings without plain F6
/// (it belongs to the shell: htop, mc).
Map<ShortcutActivator, Intent> terminalViewShortcuts(
  TargetPlatform platform, {
  KeyBindings? bindings,
}) => _table(bindings, platform).map(KeyScope.window);

/// A6 UI-A6 §4.1: keys of a focused browser pane (toolbar or page).
Map<ShortcutActivator, Intent> browserPaneShortcuts(
  TargetPlatform platform, {
  KeyBindings? bindings,
}) => _table(bindings, platform).map(KeyScope.browser);

/// A6 D15 (unchanged) + A9: text sent to a terminal and ignored keys stay
/// with the page.
bool _pageKeeps(Intent intent) =>
    intent is CopySelectionIntent ||
    intent is PasteClipboardIntent ||
    intent is SelectAllIntent ||
    intent is FontBiggerIntent ||
    intent is FontSmallerIntent ||
    intent is FontResetIntent ||
    intent is SendTextIntent ||
    intent is IgnoreKeyIntent;

List<Map<ShortcutActivator, Intent>> _forwardMaps(
  TargetPlatform platform,
  KeyBindings? bindings,
) => [
  browserPaneShortcuts(platform, bindings: bindings),
  desktopShortcuts(platform, bindings: bindings),
  terminalViewShortcuts(platform, bindings: bindings),
];

final RegExp _plainFunctionKey = RegExp(r'^f\d+$');

/// A6 D15 / A9 D30: the chords native code hands back to Flutter while web
/// content has the keyboard. Unmodified keys stay with the page except
/// function keys bound by ShellX and — while loading — Esc.
List<String> browserForwardedChords(
  TargetPlatform platform, {
  required bool loading,
  KeyBindings? bindings,
}) => chordsOf(
  _forwardMaps(platform, bindings),
  keep: (intent) =>
      !_pageKeeps(intent) && (loading || intent is! BrowserStopIntent),
).where((c) => c.contains('+') || _plainFunctionKey.hasMatch(c) || c == 'escape').toList();

/// The intent a forwarded [chord] stands for (`null`: not ShellX's).
Intent? intentForForwardedChord(
  String chord,
  TargetPlatform platform, {
  KeyBindings? bindings,
}) {
  final intent = intentForChord(chord, _forwardMaps(platform, bindings));
  return intent == null || _pageKeeps(intent) ? null : intent;
}
```

(Before A9, plain F6 was in `desktopShortcuts` and therefore forwarded from a browser page as `f6`; with the regex it still is, so A6's Ctrl+F6/F6 behaviour in the page is unchanged. `_plainFunctionKey` replaces A6's `c == 'f5'`.)

- [ ] **Step 5: Register A9's additions in the golden test**

In `shortcut_golden_test.dart` replace `_describe` with `describeIntent` (import `package:shellx_desktop/src/config/keybind_actions.dart`) and `_activator` with `describeActivator` (import `keybind_trigger.dart`), and replace `a9Additions`:

```dart
/// Chords A9 adds on purpose (spec D24).
Set<String> a9Additions(String map, String platform) {
  if (map == 'browser') return const {};
  return platform == 'mac'
      ? const {
          'shift+meta+2c norepeat -> ReloadConfigIntent',
          'meta+2c norepeat -> OpenConfigIntent',
          'shift+meta+70 norepeat -> CommandPaletteIntent',
        }
      : const {
          'ctrl+shift+2c norepeat -> ReloadConfigIntent',
          'ctrl+2c norepeat -> OpenConfigIntent',
          'ctrl+shift+70 norepeat -> CommandPaletteIntent',
        };
}
```

- [ ] **Step 6: Run the tests**

Run: `cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/config/ test/ui/shortcut_golden_test.dart test/ui/terminal_shortcuts_test.dart test/ui/pane_shortcuts_test.dart`
Expected: PASS — the golden test proves the defaults equal the pre-A9 tables plus exactly three A9 chords per window map. Then the full suite: `PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test` — PASS (every A1–A7 test unchanged). Format + analyze clean.

- [ ] **Step 7: Commit**

```bash
git add apps/desktop/lib/src/config/keybind_trigger.dart apps/desktop/lib/src/config/keybind_actions.dart apps/desktop/lib/src/config/keybindings.dart apps/desktop/lib/src/ui/terminal/terminal_intents.dart apps/desktop/lib/src/ui/terminal/terminal_shortcuts.dart apps/desktop/test/ui/shortcut_golden_test.dart apps/desktop/test/ui/fixtures apps/desktop/test/config/keybind_trigger_test.dart apps/desktop/test/config/keybindings_test.dart
git commit -m "feat(desktop): keybindings as data — Ghostty trigger syntax, action table, defaults equal to the A1-A6 shortcut maps (golden fixtures), D25 trigger rules, sequences, resolved bindings drive every Shortcuts map (A9 D22-D27, D29)"
```

---
### Task 5: `ConfigController` — load, serialize, poll, keep the last good config, publish; startup wiring (D8–D10, D36, D41)

**Files:**
- Create: `apps/desktop/lib/src/config/config_watcher.dart`, `apps/desktop/lib/src/config/config_controller.dart`
- Modify: `apps/desktop/lib/src/platform/settings_store.dart`, `apps/desktop/lib/main.dart`
- Create: `apps/desktop/test/support/config_harness.dart`
- Test: `apps/desktop/test/config/config_watcher_test.dart`, `apps/desktop/test/config/config_controller_test.dart`

**Interfaces:**
- Consumes: Tasks 1–4; `homeDirectoryProvider` (`terminal/local_sessions_provider.dart`), `desktopServicesProvider` (settings), `runBounded` (`startup.dart`).
- Produces:
  - `final class ConfigWatcher { ConfigWatcher({required ConfigFs fs, required void Function() onChange, Duration interval = const Duration(seconds: 1), Duration settle = const Duration(milliseconds: 250)}); Future<void> watch(Iterable<String> files); void stop(); }`.
  - `final configFsProvider = Provider<ConfigFs>`, `final configPathsProvider = Provider<ConfigPaths>`, `final configPlatformProvider = Provider<TargetPlatform>`.
  - `final class ConfigLoad { manual, problemsChanged, firstGhostty }`; `final class ConfigState { config, theme, bindings, problems, generation, files, ghosttyUsed, lastLoad; int get errorCount; int get visibleProblemCount; ConfigState copyWith(...) }`.
  - `final shellxConfigProvider = NotifierProvider<ConfigController, ConfigState>`; `ConfigController.load({bool manual = false}) → Future<ConfigState>`; `check() → Future<List<ConfigProblem>>`; `startWatching({Duration interval})`; `reportRuntimeProblems(int generation, Set<ConfigProblemCode> codes, List<ConfigProblem> problems)`.
  - `SettingKeys.configGhosttyNoticeShown = 'config_ghostty_notice_shown'`.
  - Test support `config_harness.dart`: `const kTestHome`, `ConfigPaths testConfigPaths({bool windows = false})`, `List<Override> configOverrides(MemoryConfigFs fs, {TargetPlatform platform = TargetPlatform.macOS})`, `Future<ConfigState> loadConfig(ProviderContainer c)`.

- [ ] **Step 1: Write the failing tests**

Create `apps/desktop/test/support/config_harness.dart`:

```dart
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shellx_desktop/src/config/config_controller.dart';
import 'package:shellx_desktop/src/config/config_paths.dart';

import 'memory_config_fs.dart';

const kTestHome = '/home/me';

ConfigPaths testConfigPaths({bool windows = false}) =>
    configPathsFor(windows: windows, env: const {}, home: kTestHome);

/// A9: every test that loads a configuration reads [fs], never the
/// developer's real `~/.config/shellx/config`.
List<Override> configOverrides(
  MemoryConfigFs fs, {
  TargetPlatform platform = TargetPlatform.macOS,
}) => [
  configFsProvider.overrideWithValue(fs),
  configPathsProvider.overrideWithValue(testConfigPaths()),
  configPlatformProvider.overrideWithValue(platform),
];

Future<ConfigState> loadConfig(ProviderContainer container) =>
    container.read(shellxConfigProvider.notifier).load();
```

Create `apps/desktop/test/config/config_watcher_test.dart`:

```dart
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/config/config_watcher.dart';

import '../support/memory_config_fs.dart';

void main() {
  test('a change is reported once, 250 ms after the poll that saw it (D9)', () {
    fakeAsync((async) {
      final fs = MemoryConfigFs();
      var changes = 0;
      final watcher = ConfigWatcher(fs: fs, onChange: () => changes++);
      watcher.watch(['/c/config', '/c/missing']);
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 3));
      expect(changes, 0);
      fs.write('/c/config', 'font-size = 14');
      async.elapse(const Duration(milliseconds: 1100));
      expect(changes, 0);
      async.elapse(const Duration(milliseconds: 300));
      expect(changes, 1);
      // Until watch() is called again with fresh stamps, the same change
      // is seen again — the controller always re-arms after a load.
      watcher.watch(['/c/config', '/c/missing']);
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 3));
      expect(changes, 1);
      fs.write('/c/missing', 'x = 1'); // a file that appears counts
      async.elapse(const Duration(milliseconds: 1300));
      expect(changes, 2);
      watcher.stop();
      fs.write('/c/config', 'font-size = 15');
      async.elapse(const Duration(seconds: 3));
      expect(changes, 2);
    });
  });
}
```

Create `apps/desktop/test/config/config_controller_test.dart`:

```dart
import 'package:fake_async/fake_async.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/agent/desktop_services.dart';
import 'package:shellx_desktop/src/config/config_controller.dart';
import 'package:shellx_desktop/src/config/config_problem.dart';
import 'package:shellx_desktop/src/config/keybind_actions.dart';
import 'package:shellx_desktop/src/config/keybindings.dart';
import 'package:shellx_desktop/src/platform/settings_store.dart';

import '../support/config_harness.dart';
import '../support/fakes.dart';
import '../support/memory_config_fs.dart';

void main() {
  late MemoryConfigFs fs;
  late TestHarness h;
  late ProviderContainer container;
  final paths = testConfigPaths();

  setUp(() {
    fs = MemoryConfigFs();
    h = TestHarness();
    container = ProviderContainer(
      overrides: [
        desktopServicesProvider.overrideWithValue(h.services()),
        ...configOverrides(fs),
      ],
    );
  });
  tearDown(() => container.dispose());

  ConfigController controller() => container.read(shellxConfigProvider.notifier);
  ConfigState state() => container.read(shellxConfigProvider);

  test('before any load: the defaults, generation 0', () {
    expect(state().generation, 0);
    expect(state().config.fontSize, isNull);
    expect(state().bindings.labelOf(const KeyAction('new_tab')), '⌘T');
  });

  test('no files: defaults, no problems, the files to watch', () async {
    final s = await controller().load();
    expect(s.generation, 1);
    expect(s.problems, isEmpty);
    expect(s.files, containsAll([paths.shellx, ...paths.ghostty]));
    expect(s.lastLoad!.problemsChanged, isFalse);
    expect(labelBindings, same(s.bindings));
  });

  test('values, theme and bindings are published together', () async {
    fs.write(paths.shellx, 'font-size = 16\nbackground = #000000\nkeybind = super+k=new_tab\n');
    final s = await controller().load();
    expect(s.config.fontSize, 16);
    expect(s.theme.background, const Color(0xFF000000));
    expect(s.bindings.labelOf(const KeyAction('new_tab')), '⌘T');
    expect(s.bindings.triggersOf(const KeyAction('new_tab')), hasLength(2));
  });

  test('an unreadable file keeps the previous configuration (D8)', () async {
    fs.write(paths.shellx, 'font-size = 16\n');
    await controller().load();
    fs.unreadable.add(paths.shellx);
    final s = await controller().load();
    expect(s.config.fontSize, 16);
    expect(s.problems.single.code, ConfigProblemCode.unreadable);
    expect(s.lastLoad!.problemsChanged, isTrue);
    expect(s.generation, 2);
  });

  test('a parser error is internal, never thrown (D10)', () async {
    fs.write(paths.shellx, 'font-size = 16\n');
    await controller().load();
    fs.readError = StateError('boom');
    final s = await controller().load();
    expect(s.config.fontSize, 16);
    expect(s.problems.single.code, ConfigProblemCode.internal);
  });

  test('problemsChanged only when the set changes (D36)', () async {
    fs.write(paths.shellx, 'font-size = to\n');
    expect((await controller().load()).lastLoad!.problemsChanged, isTrue);
    expect((await controller().load()).lastLoad!.problemsChanged, isFalse);
    expect((await controller().load(manual: true)).lastLoad!.manual, isTrue);
    fs.write(paths.shellx, 'font-size = 12\n');
    expect((await controller().load()).lastLoad!.problemsChanged, isTrue);
  });

  test('Ghostty: read when enabled, a one-time notice, off with ghostty-config = false', () async {
    fs.write(paths.ghostty[1], 'font-family = Fira Code\n');
    var s = await controller().load();
    expect(s.config.fontFamilies, ['Fira Code']);
    expect(s.ghosttyUsed, isTrue);
    expect(s.lastLoad!.firstGhostty, isTrue);
    expect(h.settings.values[SettingKeys.configGhosttyNoticeShown], isTrue);
    s = await controller().load();
    expect(s.lastLoad!.firstGhostty, isFalse);
    fs.write(paths.shellx, 'ghostty-config = false\n');
    final reads = fs.reads;
    s = await controller().load();
    expect(s.config.fontFamilies, isEmpty);
    expect(s.ghosttyUsed, isFalse);
    expect(fs.reads - reads, 1); // only the ShellX file
  });

  test('check() reports without applying', () async {
    fs.write(paths.shellx, 'font-size = 16\n');
    await controller().load();
    fs.write(paths.shellx, 'font-size = to\n');
    final problems = await controller().check();
    expect(problems.single.code, ConfigProblemCode.badValue);
    expect(state().config.fontSize, 16);
    expect(state().problems, isEmpty);
  });

  test('loads run one at a time, in order', () async {
    fs.write(paths.shellx, 'font-size = 14\n');
    final first = controller().load();
    fs.write(paths.shellx, 'font-size = 15\n');
    final second = controller().load();
    final results = await Future.wait([first, second]);
    expect(results.map((s) => s.generation), [1, 2]);
    expect(state().config.fontSize, 15);
  });

  test('runtime problems (font probe) join the current generation only', () async {
    await controller().load();
    const font = ConfigProblem(
      file: '/f',
      line: 1,
      severity: ConfigSeverity.warning,
      code: ConfigProblemCode.fontNotFound,
      value: 'Nope',
    );
    controller().reportRuntimeProblems(1, {ConfigProblemCode.fontNotFound}, [font]);
    expect(state().problems, [font]);
    expect(state().lastLoad!.problemsChanged, isTrue);
    controller().reportRuntimeProblems(1, {ConfigProblemCode.fontNotFound}, [font]);
    expect(state().lastLoad!.problemsChanged, isFalse);
    controller().reportRuntimeProblems(0, {ConfigProblemCode.fontNotFound}, const []);
    expect(state().problems, [font]); // stale generation ignored
  });

  test('watching reloads after a save (D9)', () {
    fakeAsync((async) {
      controller().load();
      async.flushMicrotasks();
      controller().startWatching();
      async.flushMicrotasks();
      fs.write(paths.shellx, 'font-size = 18\n');
      async.elapse(const Duration(milliseconds: 1300));
      async.flushMicrotasks();
      expect(state().config.fontSize, 18);
    });
  });

  test('disposing clears the label table', () async {
    await controller().load();
    container.dispose();
    expect(labelBindings, isNull);
    container = ProviderContainer(overrides: configOverrides(fs));
  });
}
```

- [ ] **Step 2: Run the tests to see them fail**

Run: `cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/config/config_watcher_test.dart test/config/config_controller_test.dart`
Expected: FAIL — files missing.

- [ ] **Step 3: Implement**

In `apps/desktop/lib/src/platform/settings_store.dart` add to `SettingKeys` and to `all`:

```dart
  /// A9 D4: "Đang dùng font và màu từ cấu hình Ghostty" was shown once.
  static const String configGhosttyNoticeShown = 'config_ghostty_notice_shown';
```

Create `apps/desktop/lib/src/config/config_watcher.dart`:

```dart
import 'dart:async';

import 'config_files.dart';

/// D9: polls the stamps of the files the last load looked at; a change
/// calls [onChange] once the files have been quiet for [settle].
final class ConfigWatcher {
  ConfigWatcher({
    required this.fs,
    required this.onChange,
    this.interval = const Duration(seconds: 1),
    this.settle = const Duration(milliseconds: 250),
  });

  final ConfigFs fs;
  final void Function() onChange;
  final Duration interval;
  final Duration settle;

  Map<String, FileStamp> _stamps = const {};
  Timer? _poll;
  Timer? _settle;
  bool _busy = false;
  bool _stopped = false;

  /// Takes fresh stamps of [files] and (re)starts polling.
  Future<void> watch(Iterable<String> files) async {
    _stopped = false;
    final stamps = <String, FileStamp>{};
    for (final f in files.toSet()) {
      stamps[f] = await fs.stamp(f);
    }
    _stamps = stamps;
    _settle?.cancel();
    _poll ??= Timer.periodic(interval, (_) => unawaited(_tick()));
  }

  Future<void> _tick() async {
    if (_busy || _stopped) return;
    _busy = true;
    try {
      for (final MapEntry(key: path, value: before) in _stamps.entries) {
        if (await fs.stamp(path) != before) {
          _settle?.cancel();
          _settle = Timer(settle, () {
            if (!_stopped) onChange();
          });
          return;
        }
      }
    } finally {
      _busy = false;
    }
  }

  void stop() {
    _stopped = true;
    _poll?.cancel();
    _poll = null;
    _settle?.cancel();
  }
}
```

Create `apps/desktop/lib/src/config/config_controller.dart`:

```dart
import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../agent/desktop_services.dart';
import '../platform/settings_store.dart';
import '../terminal/local_sessions_provider.dart';
import 'config_files.dart';
import 'config_paths.dart';
import 'config_problem.dart';
import 'config_syntax.dart';
import 'config_theme.dart';
import 'config_watcher.dart';
import 'keybindings.dart';
import 'shellx_config.dart';

final configFsProvider = Provider<ConfigFs>((ref) => const IoConfigFs());

final configPathsProvider = Provider<ConfigPaths>(
  (ref) => configPathsFor(
    windows: Platform.isWindows,
    env: Platform.environment,
    home: ref.watch(homeDirectoryProvider),
  ),
);

final configPlatformProvider = Provider<TargetPlatform>(
  (ref) => defaultTargetPlatform,
);

/// What the last load means for the UI (toasts, D36).
@immutable
final class ConfigLoad {
  const ConfigLoad({
    required this.manual,
    required this.problemsChanged,
    required this.firstGhostty,
  });
  final bool manual;
  final bool problemsChanged;
  final bool firstGhostty;
}

@immutable
final class ConfigState {
  const ConfigState({
    required this.config,
    required this.theme,
    required this.bindings,
    required this.problems,
    required this.generation,
    required this.files,
    required this.ghosttyUsed,
    this.lastLoad,
  });

  factory ConfigState.initial(TargetPlatform platform) => ConfigState(
    config: ShellxConfig.defaults,
    theme: ResolvedTheme.defaults,
    bindings: KeyBindings.defaults(platform),
    problems: const [],
    generation: 0,
    files: const [],
    ghosttyUsed: false,
  );

  final ShellxConfig config;
  final ResolvedTheme theme;
  final KeyBindings bindings;
  final List<ConfigProblem> problems;
  final int generation;
  final List<String> files;
  final bool ghosttyUsed;
  final ConfigLoad? lastLoad;

  int get errorCount =>
      problems.where((p) => p.severity == ConfigSeverity.error).length;

  /// Errors and warnings: what the toast and the tray count (D36, D45).
  int get visibleProblemCount =>
      problems.where((p) => p.severity != ConfigSeverity.info).length;

  ConfigState copyWith({
    List<ConfigProblem>? problems,
    int? generation,
    List<String>? files,
    ConfigLoad? lastLoad,
  }) => ConfigState(
    config: config,
    theme: theme,
    bindings: bindings,
    problems: problems ?? this.problems,
    generation: generation ?? this.generation,
    files: files ?? this.files,
    ghosttyUsed: ghosttyUsed,
    lastLoad: lastLoad ?? this.lastLoad,
  );
}

final shellxConfigProvider = NotifierProvider<ConfigController, ConfigState>(
  ConfigController.new,
);

final class _Read {
  _Read({
    required this.problems,
    required this.files,
    this.config,
    this.theme,
    this.bindings,
    this.ghosttyUsed = false,
  });

  final ShellxConfig? config;
  final ResolvedTheme? theme;
  final KeyBindings? bindings;
  final List<ConfigProblem> problems;
  final List<String> files;
  final bool ghosttyUsed;

  /// D8: the ShellX file could not be read, or loading failed.
  bool get keepPrevious => config == null;
}

/// A9: the one owner of the configuration. Never loads on its own: startup
/// calls [load] (tests that don't, get the defaults and never touch the
/// real file system).
class ConfigController extends Notifier<ConfigState> {
  ConfigWatcher? _watcher;
  Future<ConfigState>? _queue;

  @override
  ConfigState build() {
    ref.onDispose(() {
      _watcher?.stop();
      labelBindings = null;
    });
    return ConfigState.initial(ref.read(configPlatformProvider));
  }

  /// Reads every file and publishes the result. Never throws (D10); loads
  /// run one after another.
  Future<ConfigState> load({bool manual = false}) {
    final previous = _queue ?? Future<ConfigState>.value(state);
    final next = previous.then((_) => _load(manual));
    _queue = next;
    return next;
  }

  /// `shellx config check` (D39): the problems of the files as they are
  /// now, without applying anything.
  Future<List<ConfigProblem>> check() async {
    try {
      return (await _read()).problems;
    } catch (error) {
      debugPrint('ShellX: config check failed: ${error.runtimeType}');
      return [_internal()];
    }
  }

  void startWatching({Duration interval = const Duration(seconds: 1)}) {
    _watcher ??= ConfigWatcher(
      fs: ref.read(configFsProvider),
      interval: interval,
      onChange: () => unawaited(load()),
    );
    unawaited(_watcher!.watch(state.files));
  }

  /// Problems only the UI can find (the font probe, D11), for [generation].
  /// Replaces earlier problems with the same [codes].
  void reportRuntimeProblems(
    int generation,
    Set<ConfigProblemCode> codes,
    List<ConfigProblem> problems,
  ) {
    if (generation != state.generation) return;
    final next = [
      ...state.problems.where((p) => !codes.contains(p.code)),
      ...problems,
    ];
    state = state.copyWith(
      problems: next,
      lastLoad: ConfigLoad(
        manual: false,
        problemsChanged: !_same(next, state.problems),
        firstGhostty: false,
      ),
    );
  }

  ConfigProblem _internal() => ConfigProblem(
    file: ref.read(configPathsProvider).shellx,
    line: 0,
    severity: ConfigSeverity.error,
    code: ConfigProblemCode.internal,
  );

  static bool _same(List<ConfigProblem> a, List<ConfigProblem> b) =>
      setEquals(a.toSet(), b.toSet());

  Future<ConfigState> _load(bool manual) async {
    _Read read;
    try {
      read = await _read();
    } catch (error) {
      debugPrint('ShellX: config load failed: ${error.runtimeType}');
      read = _Read(problems: [_internal()], files: state.files);
    }
    if (!ref.mounted) return state;
    final settings = ref.read(desktopServicesProvider).settings;
    final firstGhostty =
        read.ghosttyUsed &&
        !settings.getBool(
          SettingKeys.configGhosttyNoticeShown,
          defaultValue: false,
        );
    if (firstGhostty) {
      unawaited(
        settings
            .setBool(SettingKeys.configGhosttyNoticeShown, true)
            .catchError(
              (Object e) => debugPrint(
                'ShellX: ghostty notice flag not saved: ${e.runtimeType}',
              ),
            ),
      );
    }
    final load = ConfigLoad(
      manual: manual,
      problemsChanged: !_same(read.problems, state.problems),
      firstGhostty: firstGhostty,
    );
    state = read.keepPrevious
        ? state.copyWith(
            problems: read.problems,
            generation: state.generation + 1,
            files: read.files.isEmpty ? state.files : read.files,
            lastLoad: load,
          )
        : ConfigState(
            config: read.config!,
            theme: read.theme!,
            bindings: read.bindings!,
            problems: List.unmodifiable(read.problems),
            generation: state.generation + 1,
            files: List.unmodifiable(read.files),
            ghosttyUsed: read.ghosttyUsed,
            lastLoad: load,
          );
    labelBindings = state.bindings;
    final watcher = _watcher;
    if (watcher != null) unawaited(watcher.watch(state.files));
    return state;
  }

  Future<_Read> _read() async {
    final fs = ref.read(configFsProvider);
    final paths = ref.read(configPathsProvider);
    final platform = ref.read(configPlatformProvider);
    final problems = <ConfigProblem>[];
    final files = <String>[];
    final shellx = await loadConfigChain(
      paths.shellx,
      fs: fs,
      home: paths.home,
      windows: paths.windows,
      problems: problems,
    );
    files.addAll(shellx.files);
    if (!shellx.readable) {
      return _Read(problems: problems, files: [...files, ...paths.ghostty]);
    }
    final ghostty = <ConfigEntry>[];
    if (ghosttyEnabled(shellx.entries)) {
      for (final path in paths.ghostty) {
        final chain = await loadConfigChain(
          path,
          fs: fs,
          home: paths.home,
          windows: paths.windows,
          problems: problems,
          quiet: true,
          keep: kGhosttyKeys.contains,
        );
        ghostty.addAll(chain.entries);
        files.addAll(chain.files);
      }
    }
    final config = buildShellxConfig(
      ghostty: ghostty,
      shellx: shellx.entries,
      problems: problems,
      macos: platform == TargetPlatform.macOS,
      home: paths.home,
      windows: paths.windows,
    );
    final theme = await resolveTheme(config, paths, fs: fs, problems: problems);
    files.addAll(theme.files);
    final bindings = resolveKeyBindings(
      platform: platform,
      entries: config.keybinds,
      commandNames: {for (final c in config.commands) c.name},
      optionAsAlt: config.optionAsAlt,
      problems: problems,
    );
    return _Read(
      config: config,
      theme: theme.theme,
      bindings: bindings,
      problems: problems,
      files: files,
      ghosttyUsed: ghostty.isNotEmpty,
    );
  }
}
```

(`ghostty-config = false` reads only the ShellX file — the test counts one read — and the watcher then watches only the ShellX chain, which is enough: turning it back on is an edit of that file.)

In `apps/desktop/lib/main.dart`, right after the `container = ProviderContainer(...)` statement:

```dart
  // A9 D10: the configuration before the first frame, at most 1 s; a slow
  // disk finishes in the background and applies when done.
  await runBounded(
    () => container.read(shellxConfigProvider.notifier).load(),
    timeout: const Duration(seconds: 1),
    label: 'reading the configuration',
  );
  container.read(shellxConfigProvider.notifier).startWatching();
```

(import `src/config/config_controller.dart`; `runBounded` is already imported from `src/startup.dart`.)

- [ ] **Step 4: Run the tests**

Run: `cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/config/ && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test`
Expected: PASS (full suite unchanged: nothing reads the provider yet). Format + analyze clean.

- [ ] **Step 5: Commit**

```bash
git add apps/desktop/lib/src/config/config_watcher.dart apps/desktop/lib/src/config/config_controller.dart apps/desktop/lib/src/platform/settings_store.dart apps/desktop/lib/main.dart apps/desktop/test/support/config_harness.dart apps/desktop/test/config/config_watcher_test.dart apps/desktop/test/config/config_controller_test.dart
git commit -m "feat(desktop): config controller — serialized loads, last good config on unreadable files, internal errors never thrown, 1 s stamp polling with 250 ms settle, startup load bounded to 1 s (A9 D8-D10, D36, D41)"
```

---

### Task 6: Appearance — font families and size, theme, cursor, padding, terminal background, focus outline; font probe (D11, D12, D15, D16, D18)

**Files:**
- Create: `apps/desktop/lib/src/terminal/terminal_appearance.dart`, `apps/desktop/lib/src/config/font_probe.dart`
- Modify: `apps/desktop/lib/src/terminal/terminal_style.dart`, `apps/desktop/lib/src/terminal/terminal_font_size.dart`, `apps/desktop/lib/src/ui/terminal/terminal_pane.dart`, `apps/desktop/lib/src/ui/terminal/pane_tree_view.dart`, `apps/desktop/lib/src/ui/terminal/terminal_workspace_page.dart`
- Test: `apps/desktop/test/terminal/terminal_appearance_test.dart`, `apps/desktop/test/terminal/terminal_font_size_config_test.dart`, `apps/desktop/test/config/font_probe_test.dart`

**Interfaces:**
- Consumes: Task 5 `shellxConfigProvider`, `ConfigState`; A3 `PaneTerminal`, `PaneTreeView`, `TerminalPane`.
- Produces:
  - `final class TerminalAppearance { theme, background, focusOutline, cursor (TerminalCursorType), padding, families }`; `final terminalAppearanceProvider = Provider<TerminalAppearance>`.
  - `TerminalStyle desktopTerminalStyle(double fontSize, {List<String> families = const []})`.
  - `TerminalFontSize`: `increase([double step = 1])`, `decrease([double step = 1])`, `reset()` follows D12.
  - `abstract interface class FontProbe { ({bool found, bool monospace}) probe(String family); }`, `final class TextPainterFontProbe implements FontProbe`, `final fontProbeProvider = Provider<FontProbe>`; `List<ConfigProblem> fontProblems(ShellxConfig config, FontProbe probe)`.
  - `PaneTerminal` gains `theme`, `cursorType`, `padding` (required).

- [ ] **Step 1: Write the failing tests**

Create `apps/desktop/test/config/font_probe_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/config/config_problem.dart';
import 'package:shellx_desktop/src/config/config_syntax.dart';
import 'package:shellx_desktop/src/config/font_probe.dart';
import 'package:shellx_desktop/src/config/shellx_config.dart';

final class FakeProbe implements FontProbe {
  FakeProbe(this.answers);
  final Map<String, ({bool found, bool monospace})> answers;
  @override
  ({bool found, bool monospace}) probe(String family) =>
      answers[family] ?? (found: true, monospace: true);
}

void main() {
  test('missing and proportional fonts are warnings at their lines (D11)', () {
    final config = buildShellxConfig(
      ghostty: const [],
      shellx: parseConfigText(
        'font-family = Nope\nfont-family = Helvetica\nfont-family = Menlo\n',
        file: '/c',
        problems: [],
      ),
      problems: [],
      macos: true,
      home: '/h',
    );
    final problems = fontProblems(
      config,
      FakeProbe({
        'Nope': (found: false, monospace: true),
        'Helvetica': (found: true, monospace: false),
      }),
    );
    expect([for (final p in problems) (p.line, p.code, p.severity, p.value)], [
      (1, ConfigProblemCode.fontNotFound, ConfigSeverity.warning, 'Nope'),
      (2, ConfigProblemCode.fontNotMonospace, ConfigSeverity.warning, 'Helvetica'),
    ]);
  });

  test('a probe that throws reports nothing', () {
    final config = buildShellxConfig(
      ghostty: const [],
      shellx: parseConfigText('font-family = X\n', file: '/c', problems: []),
      problems: [],
      macos: true,
      home: '/h',
    );
    expect(fontProblems(config, _Throwing()), isEmpty);
  });
}

final class _Throwing implements FontProbe {
  @override
  ({bool found, bool monospace}) probe(String family) => throw StateError('x');
}
```

Create `apps/desktop/test/terminal/terminal_appearance_test.dart` (reuse the pump helper pattern of `test/ui/terminal_shortcuts_test.dart`):

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/l10n/app_localizations.dart';
import 'package:shellx_desktop/src/agent/agent_controller.dart';
import 'package:shellx_desktop/src/agent/desktop_services.dart';
import 'package:shellx_desktop/src/config/config_controller.dart';
import 'package:shellx_desktop/src/config/font_probe.dart';
import 'package:shellx_desktop/src/terminal/local_sessions_provider.dart';
import 'package:shellx_desktop/src/terminal/terminal_style.dart';
import 'package:shellx_desktop/src/ui/terminal/terminal_workspace_page.dart';
import 'package:shellx_desktop/src/ui/theme/shellx_desktop_theme.dart';
import 'package:shellx_desktop/src/ui/theme/terminal_colors.dart';
import 'package:shellx_desktop/src/ui/window_router.dart';
import 'package:xterm/xterm.dart';

import '../config/font_probe_test.dart' show FakeProbe;
import '../support/config_harness.dart';
import '../support/fake_local_sessions.dart';
import '../support/fakes.dart';
import '../support/memory_config_fs.dart';

late ProviderContainer container;

Future<void> pump(
  WidgetTester tester,
  MemoryConfigFs fs, {
  String? config,
  FontProbe? probe,
}) async {
  if (config != null) fs.write(testConfigPaths().shellx, config);
  final h = TestHarness(settings: {'onboarding_done': true});
  final local = FakeLocalSessions()..addSession(id: 1, title: 'zsh');
  container = ProviderContainer(
    overrides: [
      desktopServicesProvider.overrideWithValue(h.services()),
      localSessionsProvider.overrideWithValue(local),
      fontProbeProvider.overrideWithValue(probe ?? FakeProbe(const {})),
      ...configOverrides(fs),
    ],
  );
  await h.seedSignedIn();
  await container.read(agentControllerProvider.notifier).bootstrap(watchForWake: false);
  await loadConfig(container);
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

Future<void> finish(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  container.dispose();
}

void main() {
  testWidgets('no file looks like A1 (criterion 1)', (tester) async {
    await pump(tester, MemoryConfigFs());
    final view = tester.widget<TerminalView>(find.byType(TerminalView));
    expect(view.textStyle.fontFamily, kTerminalFontFamily);
    expect(view.textStyle.fontSize, 13);
    expect(view.theme.background, TerminalColors.theme.background);
    expect(view.cursorType, TerminalCursorType.block);
    expect(view.padding, ShellxSizes.terminalPadding);
    await finish(tester);
  });

  testWidgets('font, size, colours, cursor, padding from the file (criterion 2)', (tester) async {
    final fs = MemoryConfigFs();
    await pump(
      tester,
      fs,
      config: 'font-family = Menlo\nfont-size = 16\nbackground = #fdf6e3\nforeground = #002b36\ncursor-style = bar\nwindow-padding-x = 4\n',
    );
    var view = tester.widget<TerminalView>(find.byType(TerminalView));
    expect(view.textStyle.fontFamily, 'Menlo');
    expect(view.textStyle.fontFamilyFallback.first, kTerminalFontFamily);
    expect(view.textStyle.fontSize, 16);
    expect(view.theme.background, const Color(0xFFFDF6E3));
    expect(view.cursorType, TerminalCursorType.verticalBar);
    expect(view.padding, const EdgeInsets.fromLTRB(4, 6, 4, 6));
    // The terminal area behind the pane follows the theme (D15).
    expect(
      tester.widgetList<ColoredBox>(find.byKey(const ValueKey('terminal.area'))).single.color,
      const Color(0xFFFDF6E3),
    );
    // Live: a reload changes the view without reopening the tab.
    fs.write(testConfigPaths().shellx, 'cursor-style = underline\n');
    await loadConfig(container);
    await tester.pumpAndSettle();
    view = tester.widget<TerminalView>(find.byType(TerminalView));
    expect(view.cursorType, TerminalCursorType.underline);
    expect(view.textStyle.fontFamily, kTerminalFontFamily);
    await finish(tester);
  });

  testWidgets('a missing font is reported after the load (D11)', (tester) async {
    final probe = FakeProbe({'Nope': (found: false, monospace: true)});
    await pump(tester, MemoryConfigFs(), config: 'font-family = Nope\n', probe: probe);
    final problems = container.read(shellxConfigProvider).problems;
    expect(problems.map((p) => (p.code.name, p.value)), [('fontNotFound', 'Nope')]);
    await finish(tester);
  });
}
```

(`FakeLocalSessions.addSession` is the existing helper used by A1–A3 widget tests to add a desktop session; use its real name/signature from `test/support/fake_local_sessions.dart`.)

Create `apps/desktop/test/terminal/terminal_font_size_config_test.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/agent/desktop_services.dart';
import 'package:shellx_desktop/src/platform/settings_store.dart';
import 'package:shellx_desktop/src/terminal/terminal_font_size.dart';

import '../support/config_harness.dart';
import '../support/fakes.dart';
import '../support/memory_config_fs.dart';

void main() {
  late MemoryConfigFs fs;
  late TestHarness h;
  late ProviderContainer c;
  setUp(() {
    fs = MemoryConfigFs();
    h = TestHarness();
    c = ProviderContainer(
      overrides: [
        desktopServicesProvider.overrideWithValue(h.services()),
        ...configOverrides(fs),
      ],
    );
    c.listen(terminalFontSizeProvider, (_, _) {});
  });
  tearDown(() => c.dispose());

  double size() => c.read(terminalFontSizeProvider);
  TerminalFontSize notifier() => c.read(terminalFontSizeProvider.notifier);

  test('no font-size: today (persisted ⌘+, default 13)', () async {
    await loadConfig(c);
    expect(size(), 13);
    notifier().increase();
    expect(size(), 14);
    expect(h.settings.ints[SettingKeys.terminalFontSize], 14);
  });

  test('font-size wins at load; ⌘+ is not persisted; ⌘0 returns to it (D12)', () async {
    h.settings.ints[SettingKeys.terminalFontSize] = 20;
    fs.write(testConfigPaths().shellx, 'font-size = 15\n');
    await loadConfig(c);
    expect(size(), 15);
    notifier().increase(2);
    expect(size(), 17);
    expect(h.settings.ints[SettingKeys.terminalFontSize], 20);
    notifier().reset();
    expect(size(), 15);
  });

  test('another edit keeps ⌘+; a new font-size replaces it', () async {
    fs.write(testConfigPaths().shellx, 'font-size = 15\n');
    await loadConfig(c);
    notifier().increase();
    fs.write(testConfigPaths().shellx, 'font-size = 15\ncursor-style = bar\n');
    await loadConfig(c);
    expect(size(), 16);
    fs.write(testConfigPaths().shellx, 'font-size = 12\n');
    await loadConfig(c);
    expect(size(), 12);
  });
}
```

- [ ] **Step 2: Run the tests to see them fail**

Run: `cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/config/font_probe_test.dart test/terminal/terminal_appearance_test.dart test/terminal/terminal_font_size_config_test.dart`
Expected: FAIL — `font_probe.dart`, `terminalAppearanceProvider` missing; `increase(2)` has no parameter.

- [ ] **Step 3: Implement**

Create `apps/desktop/lib/src/config/font_probe.dart`:

```dart
import 'package:flutter/painting.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'config_problem.dart';
import 'shellx_config.dart';

/// D11: is a font family installed, and is it monospaced?
abstract interface class FontProbe {
  ({bool found, bool monospace}) probe(String family);
}

/// Measures with the engine's fonts: a family that is not installed lays
/// out like a family that cannot exist.
final class TextPainterFontProbe implements FontProbe {
  const TextPainterFontProbe();

  static const _missing = 'ShellX-No-Such-Font-7f3a';

  double _width(String family, String text) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(fontFamily: family, fontSize: 20),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final width = painter.width;
    painter.dispose();
    return width;
  }

  @override
  ({bool found, bool monospace}) probe(String family) {
    const samples = ['mmmmmmmmmm', 'iiiiiiiiii', 'Wg0@#&'];
    final found = samples.any((s) => _width(family, s) != _width(_missing, s));
    final monospace = _width(family, samples[0]) == _width(family, samples[1]);
    return (found: found, monospace: monospace);
  }
}

final fontProbeProvider = Provider<FontProbe>(
  (ref) => const TextPainterFontProbe(),
);

const Set<ConfigProblemCode> kFontProblemCodes = {
  ConfigProblemCode.fontNotFound,
  ConfigProblemCode.fontNotMonospace,
};

/// One warning per family that is missing or proportional, at its line.
List<ConfigProblem> fontProblems(ShellxConfig config, FontProbe probe) {
  final problems = <ConfigProblem>[];
  for (var i = 0; i < config.fontFamilies.length; i++) {
    final family = config.fontFamilies[i];
    final at = config.fontFamilyOrigins[i];
    final ({bool found, bool monospace}) answer;
    try {
      answer = probe.probe(family);
    } catch (_) {
      continue; // D10: a probe failure never becomes a problem
    }
    final code = !answer.found
        ? ConfigProblemCode.fontNotFound
        : !answer.monospace
        ? ConfigProblemCode.fontNotMonospace
        : null;
    if (code == null) continue;
    problems.add(
      ConfigProblem(
        file: at.file,
        line: at.line,
        severity: ConfigSeverity.warning,
        code: code,
        key: 'font-family',
        value: family,
      ),
    );
  }
  return problems;
}
```

Create `apps/desktop/lib/src/terminal/terminal_appearance.dart`:

```dart
import 'package:flutter/painting.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:xterm/xterm.dart';

import '../config/config_controller.dart';
import '../config/shellx_config.dart';

/// What every pane draws with (A9 D11, D15, D16, D18).
final class TerminalAppearance {
  const TerminalAppearance({
    required this.theme,
    required this.background,
    required this.focusOutline,
    required this.cursor,
    required this.padding,
    required this.families,
  });

  final TerminalTheme theme;
  final Color background;
  final Color focusOutline;
  final TerminalCursorType cursor;
  final EdgeInsets padding;
  final List<String> families;
}

final terminalAppearanceProvider = Provider<TerminalAppearance>((ref) {
  final s = ref.watch(shellxConfigProvider);
  return TerminalAppearance(
    theme: s.theme.terminal,
    background: s.theme.background,
    focusOutline: s.theme.focusOutline,
    cursor: switch (s.config.cursorShape) {
      CursorShape.block => TerminalCursorType.block,
      CursorShape.bar => TerminalCursorType.verticalBar,
      CursorShape.underline => TerminalCursorType.underline,
    },
    padding: s.config.padding,
    families: s.config.fontFamilies,
  );
});
```

In `apps/desktop/lib/src/terminal/terminal_style.dart` replace `desktopTerminalStyle`:

```dart
/// D11: [families] first (primary, then fallbacks), then the bundled
/// JetBrains Mono, then xterm's own fallbacks. No families = A1 exactly.
TerminalStyle desktopTerminalStyle(
  double fontSize, {
  List<String> families = const [],
}) => TerminalStyle(
  fontSize: fontSize,
  height: 1.2,
  fontFamily: families.isEmpty ? kTerminalFontFamily : families.first,
  fontFamilyFallback: families.isEmpty
      ? const TerminalStyle().fontFamilyFallback
      : [
          ...families.skip(1),
          kTerminalFontFamily,
          ...const TerminalStyle().fontFamilyFallback,
        ],
);
```

Replace the body of `TerminalFontSize` in `apps/desktop/lib/src/terminal/terminal_font_size.dart`:

```dart
/// ⌘+ / ⌘− / ⌘0 (spec criterion 2, UI §1.3). A9 D12: a `font-size` in the
/// configuration sets the size at load and whenever it changes, and ⌘+/−
/// are then not persisted; without one, today's persisted size.
class TerminalFontSize extends Notifier<double> {
  double? _configured;

  @override
  double build() {
    _configured = ref.watch(
      shellxConfigProvider.select((s) => s.config.fontSize),
    );
    final configured = _configured;
    if (configured != null) return _clamp(configured);
    final stored = ref
        .watch(desktopServicesProvider)
        .settings
        .getInt(SettingKeys.terminalFontSize);
    return _clamp((stored ?? kTerminalFontSizeDefault).toDouble());
  }

  void increase([double step = 1]) => _set(state + step);
  void decrease([double step = 1]) => _set(state - step);
  void reset() => _set(_configured ?? kTerminalFontSizeDefault);

  void _set(double value) {
    final next = _clamp(value);
    if (next == state) return;
    state = next;
    if (_configured != null) return; // D12: the file owns the size
    final settings = ref.read(desktopServicesProvider).settings;
    unawaited(
      settings
          .setInt(SettingKeys.terminalFontSize, next.round())
          .catchError(
            (Object e) =>
                debugPrint('terminal font size not saved: ${e.runtimeType}'),
          ),
    );
  }

  static double _clamp(double value) =>
      value.clamp(kTerminalFontSizeMin, kTerminalFontSizeMax).toDouble();
}
```

(import `../config/config_controller.dart`.) In `terminal_workspace_page.dart` the font actions pass the step: `FontBiggerIntent: run<FontBiggerIntent>((i) => ref.read(terminalFontSizeProvider.notifier).increase(i.step))`, same for `FontSmallerIntent`.

`apps/desktop/lib/src/ui/terminal/terminal_pane.dart` (`TerminalPaneState.build`):

```dart
    final appearance = ref.watch(terminalAppearanceProvider);
    final style = desktopTerminalStyle(fontSize, families: appearance.families);
```

and in the same method replace **every** `ShellxSizes.terminalPadding` (the grid measure and `reportPaneMetrics`' `minPane`) with `appearance.padding`. Wrap the `Expanded(child: LayoutBuilder(...))` child — the terminal area only, not the macOS 28 px title band nor the signed-out strip — in

```dart
ColoredBox(key: const ValueKey('terminal.area'), color: appearance.background, child: …)
```

The outer `ColoredBox(color: ShellxDesktopColors.bgTerminal)` stays (chrome, D15).

`apps/desktop/lib/src/ui/terminal/pane_tree_view.dart`:
- `PaneTerminal` gains `required this.theme`, `required this.cursorType`, `required this.padding` and passes them to `TerminalView(theme: theme, cursorType: cursorType, padding: padding, …)` instead of `TerminalColors.theme` / `ShellxSizes.terminalPadding`.
- Every place that builds a `PaneTerminal` reads `final appearance = ref.watch(terminalAppearanceProvider);` (the widget is a `ConsumerWidget`/`ConsumerStatefulWidget` already, or becomes one) and passes `theme: appearance.theme, cursorType: appearance.cursor, padding: appearance.padding`.
- Replace other `ShellxSizes.terminalPadding` uses in the file (the driver-pill offset "past the terminal's own top padding") with `appearance.padding`.
- The focus outline (A3 D16, search `paneFocusOutline`) uses `appearance.focusOutline` instead of `ShellxDesktopColors.accent`.

Font probe: in `TerminalWorkspacePageState.initState` (a manual listener, so `fireImmediately` runs once — the startup load finished before the first frame — and never again on rebuilds):

```dart
    // A9 D11: probe the configured families once per load (needs the
    // engine's fonts, so it runs here, not in the controller).
    ref.listenManual(
      shellxConfigProvider.select((s) => (s.generation, s.config)),
      (_, next) {
        final (generation, config) = next;
        if (generation == 0) return;
        final problems = fontProblems(config, ref.read(fontProbeProvider));
        ref
            .read(shellxConfigProvider.notifier)
            .reportRuntimeProblems(generation, kFontProblemCodes, problems);
      },
      fireImmediately: true,
    );
```

(`reportRuntimeProblems` changes neither `generation` nor `config`, so the listener does not re-fire.)

- [ ] **Step 4: Run the tests**

Run: `cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/config/font_probe_test.dart test/terminal/ && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test`
Expected: PASS; every A1–A7 widget test unchanged (no config loaded → defaults). Format + analyze clean.

- [ ] **Step 5: ⚠ MANUAL (macOS + Windows)**

With `~/.config/shellx/config` (Windows `%APPDATA%\ShellX\config`) containing `font-family = Menlo` (Windows `Cascadia Mono`), `font-size = 15`: text draws in that font, `tput cols` matches the pane; `font-family = Nope` → toast after Task 10 (here: `shellx config check` after Task 13, or the debugger) lists `fontNotFound`; `font-family = Helvetica` → `fontNotMonospace`. Record in the ledger.

- [ ] **Step 6: Commit**

```bash
git add apps/desktop/lib/src/terminal/terminal_appearance.dart apps/desktop/lib/src/config/font_probe.dart apps/desktop/lib/src/terminal/terminal_style.dart apps/desktop/lib/src/terminal/terminal_font_size.dart apps/desktop/lib/src/ui/terminal/terminal_pane.dart apps/desktop/lib/src/ui/terminal/pane_tree_view.dart apps/desktop/lib/src/ui/terminal/terminal_workspace_page.dart apps/desktop/test/config/font_probe_test.dart apps/desktop/test/terminal/terminal_appearance_test.dart apps/desktop/test/terminal/terminal_font_size_config_test.dart
git commit -m "feat(desktop): terminals draw with the configured fonts, size, theme, cursor and padding live; terminal area follows the theme with a readable focus outline; font probe warnings (A9 D11, D12, D15, D16, D18)"
```

---
### Task 7: Behaviour — Option as Alt, scrollback for new panes, new-tab directory, close confirmation, user text and commands (D17, D19–D21, D31, D35)

**Files:**
- Create: `apps/desktop/lib/src/terminal/user_commands.dart`
- Modify: `apps/desktop/lib/src/terminal/terminal_input.dart`, `apps/desktop/lib/src/terminal/desktop_terminal.dart`, `apps/desktop/lib/src/terminal/terminal_tabs.dart`, `apps/desktop/lib/src/ui/terminal/close_tab.dart`, `apps/desktop/lib/src/ui/terminal/terminal_workspace_page.dart`, `apps/desktop/lib/src/tray/tray_actions.dart`, `apps/desktop/lib/l10n/app_en.arb`, `apps/desktop/lib/l10n/app_vi.arb` (+ `flutter gen-l10n`)
- Test: `apps/desktop/test/terminal/option_as_alt_test.dart`, `apps/desktop/test/terminal/config_behaviour_test.dart`, `apps/desktop/test/ui/confirm_close_config_test.dart`

**Interfaces:**
- Consumes: Tasks 2, 5 (`OptionAsAlt`, `ConfirmClose`, `WorkingDirectoryKind`, `UserCommand`, `shellxConfigProvider`); A6 `TerminalTab.focused` (= active terminal pane); A7 `TerminalTabs.openTabFor({String? cwd, bool select})`.
- Produces:
  - `final class OptionAsAltInputHandler implements TerminalInputHandler { OptionAsAltInputHandler(OptionAsAlt Function() mode, {Set<LogicalKeyboardKey> Function()? pressed}) }`; `TerminalInputHandler desktopInputHandlerWith(OptionAsAlt Function() optionAsAlt)`.
  - `DesktopTerminal({int maxLines = 10000, TerminalTargetPlatform platform, TerminalInputHandler? inputHandler})`; `void DesktopTerminal.sendUserText(String data)`.
  - `String? TerminalTabs.newTabCwd()`; terminals created with `maxLines = config.scrollbackLimit` and the Option-as-Alt handler.
  - `closeTabWithConfirm(…, ConfirmClose confirm = ConfirmClose.whenRunning)`, `closePaneWithConfirm(…, ConfirmClose confirm = ConfirmClose.whenRunning)`.
  - `enum CommandRun { ran, noTerminal }`; `PaneSession? commandTarget(TerminalTabsState state)`; `CommandRun runUserCommand(TerminalTabsState state, UserCommand command)`; `CommandRun sendTextToFocused(TerminalTabsState state, String text)`.
  - ARB: `confirmCloseAlwaysBody`, `confirmCloseAlwaysPanesBody`, `confirmClosePaneAlwaysBody`.

- [ ] **Step 1: Write the failing tests**

Create `apps/desktop/test/terminal/option_as_alt_test.dart`:

```dart
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/config/shellx_config.dart';
import 'package:shellx_desktop/src/terminal/terminal_input.dart';
import 'package:xterm/core.dart';

TerminalKeyboardEvent key(
  TerminalKey k, {
  bool alt = true,
  bool shift = false,
  bool ctrl = false,
  TerminalTargetPlatform platform = TerminalTargetPlatform.macos,
  bool altBuffer = false,
}) => TerminalKeyboardEvent(
  key: k,
  shift: shift,
  ctrl: ctrl,
  alt: alt,
  state: Terminal(),
  altBuffer: altBuffer,
  platform: platform,
);

void main() {
  test('off (default): Option keys are left to the IME, as today', () {
    final h = OptionAsAltInputHandler(() => OptionAsAlt.off);
    expect(h(key(TerminalKey.keyF)), isNull);
  });

  test('both: ESC + the base character; Shift makes it upper case (D19)', () {
    final h = OptionAsAltInputHandler(() => OptionAsAlt.both);
    expect(h(key(TerminalKey.keyF)), '\x1bf');
    expect(h(key(TerminalKey.keyF, shift: true)), '\x1bF');
    expect(h(key(TerminalKey.digit1)), '\x1b1');
    expect(h(key(TerminalKey.digit1, shift: true)), '\x1b!');
    expect(h(key(TerminalKey.period)), '\x1b.');
    expect(h(key(TerminalKey.keyF, alt: false)), isNull);
    expect(h(key(TerminalKey.keyF, ctrl: true)), isNull);
    expect(h(key(TerminalKey.keyF, platform: TerminalTargetPlatform.windows)), isNull);
    expect(h(key(TerminalKey.arrowLeft)), isNull);
  });

  test('left / right follow the Option key held', () {
    var pressed = <LogicalKeyboardKey>{LogicalKeyboardKey.altLeft};
    final left = OptionAsAltInputHandler(() => OptionAsAlt.left, pressed: () => pressed);
    final right = OptionAsAltInputHandler(() => OptionAsAlt.right, pressed: () => pressed);
    expect(left(key(TerminalKey.keyB)), '\x1bb');
    expect(right(key(TerminalKey.keyB)), isNull);
    pressed = {LogicalKeyboardKey.altRight};
    expect(left(key(TerminalKey.keyB)), isNull);
    expect(right(key(TerminalKey.keyB)), '\x1bb');
  });

  test('the cascade keeps Option+←/→ moving by word at the shell', () {
    final cascade = desktopInputHandlerWith(() => OptionAsAlt.both);
    expect(cascade(key(TerminalKey.arrowLeft)), '\x1bb');
    expect(cascade(key(TerminalKey.keyX)), '\x1bx');
  });
}
```

Create `apps/desktop/test/terminal/config_behaviour_test.dart` (follow `test/terminal/terminal_tabs_panes_test.dart` for the container and `FakeLocalSessions`):

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/agent/desktop_services.dart';
import 'package:shellx_desktop/src/config/config_controller.dart';
import 'package:shellx_desktop/src/config/config_syntax.dart';
import 'package:shellx_desktop/src/config/shellx_config.dart';
import 'package:shellx_desktop/src/terminal/local_sessions_provider.dart';
import 'package:shellx_desktop/src/terminal/terminal_tabs.dart';
import 'package:shellx_desktop/src/terminal/user_commands.dart';

import '../support/config_harness.dart';
import '../support/fake_local_sessions.dart';
import '../support/fakes.dart';
import '../support/memory_config_fs.dart';

void main() {
  late MemoryConfigFs fs;
  late FakeLocalSessions local;
  late ProviderContainer c;

  setUp(() {
    fs = MemoryConfigFs();
    local = FakeLocalSessions();
    c = ProviderContainer(
      overrides: [
        desktopServicesProvider.overrideWithValue(TestHarness().services()),
        localSessionsProvider.overrideWithValue(local),
        ...configOverrides(fs),
      ],
    );
    c.listen(terminalTabsProvider, (_, _) {});
  });
  tearDown(() => c.dispose());

  TerminalTabs tabs() => c.read(terminalTabsProvider.notifier);
  TerminalTabsState state() => c.read(terminalTabsProvider);
  Future<void> config(String text) async {
    fs.write(testConfigPaths().shellx, text);
    await loadConfig(c);
  }

  test('scrollback-limit applies to panes opened after the load (D17)', () async {
    await tabs().openTab();
    expect(state().selected!.focused.terminal.maxLines, 10000);
    await config('scrollback-limit = 2000\n');
    await tabs().openTab();
    expect(state().selected!.focused.terminal.maxLines, 2000);
    expect(state().tabs.first.focused.terminal.maxLines, 10000);
  });

  test('working-directory: home, a path, inherit (D21)', () async {
    await tabs().openTab();
    expect(local.openCwds.last, isNull);
    await config('working-directory = /tmp/w\n');
    await tabs().openTab();
    expect(local.openCwds.last, '/tmp/w');
    await config('working-directory = inherit\n');
    local.setCwd(state().selected!.focused.id, '/repo'); // A2 OSC 7 in the fake
    await tabs().openTab();
    expect(local.openCwds.last, '/repo');
  });

  test('user commands paste and press Enter; snippets only paste (D35)', () async {
    await tabs().openTab();
    final id = state().selected!.focused.id;
    final entry = ConfigEntry(file: '/c', line: 1, key: 'command', value: '');
    expect(
      runUserCommand(state(), UserCommand(name: 'Lint', text: 'npm run lint', enter: true, origin: entry)),
      CommandRun.ran,
    );
    expect(local.views[id]!.writes.join(), 'npm run lint\r');
    local.views[id]!.writes.clear();
    runUserCommand(state(), UserCommand(name: 'S', text: 'git status\n', enter: false, origin: entry));
    expect(local.views[id]!.writes.join(), 'git status\r');
  });

  test('no live terminal: noTerminal', () async {
    final entry = ConfigEntry(file: '/c', line: 1, key: 'command', value: '');
    expect(
      runUserCommand(state(), UserCommand(name: 'L', text: 'x', enter: true, origin: entry)),
      CommandRun.noTerminal,
    );
    expect(sendTextToFocused(state(), 'x'), CommandRun.noTerminal);
  });

  test('text: bytes go out raw, as typed input (D31)', () async {
    await tabs().openTab();
    final id = state().selected!.focused.id;
    expect(sendTextToFocused(state(), '\x1b[A'), CommandRun.ran);
    expect(local.views[id]!.writes.join(), '\x1b[A');
  });

  test('Option as Alt is read at key time (live)', () async {
    await tabs().openTab();
    expect(c.read(shellxConfigProvider).config.optionAsAlt, OptionAsAlt.off);
    await config('macos-option-as-alt = true\n');
    expect(c.read(shellxConfigProvider).config.optionAsAlt, OptionAsAlt.both);
  });
}
```

(`FakeLocalSessions.setCwd` — use the existing helper that updates a session's `cwd` and emits `changes` (A2 tests use it to drive the context line); if its name differs, use the real one.)

Create `apps/desktop/test/ui/confirm_close_config_test.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/l10n/app_localizations.dart';
import 'package:shellx_desktop/src/agent/desktop_services.dart';
import 'package:shellx_desktop/src/config/shellx_config.dart';
import 'package:shellx_desktop/src/terminal/local_sessions_provider.dart';
import 'package:shellx_desktop/src/terminal/terminal_tabs.dart';
import 'package:shellx_desktop/src/ui/terminal/close_tab.dart';
import 'package:shellx_desktop/src/ui/window_router.dart';

import '../support/fake_local_sessions.dart';
import '../support/fakes.dart';

void main() {
  late FakeLocalSessions local;
  late ProviderContainer c;
  final l10n = lookupAppLocalizations(const Locale('en'));

  setUp(() async {
    local = FakeLocalSessions();
    c = ProviderContainer(
      overrides: [
        desktopServicesProvider.overrideWithValue(TestHarness().services()),
        localSessionsProvider.overrideWithValue(local),
      ],
    );
    c.listen(terminalTabsProvider, (_, _) {});
    await c.read(terminalTabsProvider.notifier).openTab();
  });
  tearDown(() => c.dispose());

  TerminalTab tab() => c.read(terminalTabsProvider).selected!;
  Future<void> close(ConfirmClose mode) => closeTabWithConfirm(
    tabs: c.read(terminalTabsProvider.notifier),
    router: c.read(windowRouterProvider.notifier),
    l10n: l10n,
    tab: tab(),
    confirm: mode,
  );

  test('never: a running command closes without asking (D20)', () async {
    final id = tab().id;
    local.setRunning(id, true); // A4 OSC 133;C in the fake
    await close(ConfirmClose.never);
    expect(local.closed, contains(id));
    expect(c.read(windowRouterProvider).confirm, isNull);
  });

  test('always: an idle tab asks with the new body', () async {
    final id = tab().id;
    final pending = close(ConfirmClose.always);
    await Future<void>.delayed(Duration.zero);
    final request = c.read(windowRouterProvider).confirm!;
    expect(request.body, l10n.confirmCloseAlwaysBody);
    request.complete(true);
    await pending;
    expect(local.closed, contains(id));
  });

  test('whenRunning (default) keeps A1: idle closes, running asks', () async {
    final id = tab().id;
    await close(ConfirmClose.whenRunning);
    expect(local.closed, contains(id));
  });
}
```

(`FakeLocalSessions.setRunning` — the helper A4/A3 tests use to mark a session's command running; use its real name.)

- [ ] **Step 2: Run the tests to see them fail**

Run: `cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/terminal/option_as_alt_test.dart test/terminal/config_behaviour_test.dart test/ui/confirm_close_config_test.dart`
Expected: FAIL — symbols missing.

- [ ] **Step 3: Implement**

Append to `apps/desktop/lib/src/terminal/terminal_input.dart` (import `package:flutter/services.dart` and `../config/shellx_config.dart`):

```dart
const Map<TerminalKey, (String, String)> _optionKeys = {
  TerminalKey.digit1: ('1', '!'), TerminalKey.digit2: ('2', '@'),
  TerminalKey.digit3: ('3', '#'), TerminalKey.digit4: ('4', r'$'),
  TerminalKey.digit5: ('5', '%'), TerminalKey.digit6: ('6', '^'),
  TerminalKey.digit7: ('7', '&'), TerminalKey.digit8: ('8', '*'),
  TerminalKey.digit9: ('9', '('), TerminalKey.digit0: ('0', ')'),
  TerminalKey.minus: ('-', '_'), TerminalKey.equal: ('=', '+'),
  TerminalKey.bracketLeft: ('[', '{'), TerminalKey.bracketRight: (']', '}'),
  TerminalKey.backslash: (r'\', '|'), TerminalKey.semicolon: (';', ':'),
  TerminalKey.quote: ("'", '"'), TerminalKey.backquote: ('`', '~'),
  TerminalKey.comma: (',', '<'), TerminalKey.period: ('.', '>'),
  TerminalKey.slash: ('/', '?'), TerminalKey.space: (' ', ' '),
};

String? _optionCharacter(TerminalKey key, {required bool shift}) {
  final i = key.index - TerminalKey.keyA.index;
  if (i >= 0 && i < 26) {
    final c = String.fromCharCode(0x61 + i);
    return shift ? c.toUpperCase() : c;
  }
  final pair = _optionKeys[key];
  return pair == null ? null : (shift ? pair.$2 : pair.$1);
}

/// A9 D19: macOS Option as Meta (`ESC` + the base character, US layout
/// shifts). Runs after [CursorKeysInputHandler], so Option+←/→ keep moving
/// by word, and before xterm's defaults. [mode] is read at key time, so a
/// reload applies at once.
final class OptionAsAltInputHandler implements TerminalInputHandler {
  OptionAsAltInputHandler(
    this.mode, {
    Set<LogicalKeyboardKey> Function()? pressed,
  }) : _pressed =
           pressed ?? (() => HardwareKeyboard.instance.logicalKeysPressed);

  final OptionAsAlt Function() mode;
  final Set<LogicalKeyboardKey> Function() _pressed;

  @override
  String? call(TerminalKeyboardEvent event) {
    if (event.platform != TerminalTargetPlatform.macos ||
        !event.alt ||
        event.ctrl) {
      return null;
    }
    switch (mode()) {
      case OptionAsAlt.off:
        return null;
      case OptionAsAlt.left:
        if (!_pressed().contains(LogicalKeyboardKey.altLeft)) return null;
      case OptionAsAlt.right:
        if (!_pressed().contains(LogicalKeyboardKey.altRight)) return null;
      case OptionAsAlt.both:
        break;
    }
    final c = _optionCharacter(event.key, shift: event.shift);
    return c == null ? null : '\x1b$c';
  }
}

/// [desktopInputHandler] with A9 D19 in between.
TerminalInputHandler desktopInputHandlerWith(
  OptionAsAlt Function() optionAsAlt,
) => CascadeInputHandler([
  const CursorKeysInputHandler(),
  OptionAsAltInputHandler(optionAsAlt),
  defaultInputHandler,
]);
```

In `apps/desktop/lib/src/terminal/desktop_terminal.dart`:

```dart
  DesktopTerminal({
    super.maxLines = 10000,
    super.platform,
    TerminalInputHandler? inputHandler,
  }) : super(inputHandler: inputHandler ?? desktopInputHandler) {
    onOutput = _route;
  }

  /// A9 D31: bytes from the user's own key binding (`text:`, `csi:`,
  /// `esc:`), sent as typed input — the desktop takes the driver (A1 D6) —
  /// and, like Ghostty, not filtered: the configuration is the user's.
  void sendUserText(String data) => _asUser(() => onOutput?.call(data));
```

In `apps/desktop/lib/src/terminal/terminal_tabs.dart`:
- A field `late final TerminalInputHandler _inputHandler;` set in `build()`:

```dart
    _inputHandler = desktopInputHandlerWith(
      () => ref.mounted
          ? ref.read(shellxConfigProvider).config.optionAsAlt
          : OptionAsAlt.off,
    );
```

  (if `build()` can run more than once, make it a plain `late TerminalInputHandler`.)
- In `_attach`: `final terminal = DesktopTerminal(platform: _platform(), maxLines: ref.read(shellxConfigProvider).config.scrollbackLimit, inputHandler: _inputHandler);`
- Add:

```dart
  /// A9 D21: where a new tab's shell starts (null = home). Checked by the
  /// agent like every cwd (A3 D17).
  String? newTabCwd() {
    final wd = ref.read(shellxConfigProvider).config.workingDirectory;
    return switch (wd.kind) {
      WorkingDirectoryKind.home => null,
      WorkingDirectoryKind.path => wd.path,
      WorkingDirectoryKind.inherit => state.selected?.focused.cwd,
    };
  }
```

- `openTab()` passes it: with A7 merged, `openTab()` calls `openTabFor(select: true)` — change that call to `openTabFor(cwd: newTabCwd(), select: true)`; without A7, change `_local.open(cols: _grid.cols, rows: _grid.rows)` to `_local.open(cols: _grid.cols, rows: _grid.rows, cwd: newTabCwd())`. Splits are unchanged (A3 P4).

Create `apps/desktop/lib/src/terminal/user_commands.dart`:

```dart
import 'package:xterm/core.dart';

import '../config/shellx_config.dart';
import 'terminal_tabs.dart';

enum CommandRun { ran, noTerminal }

/// D35: the selected tab's terminal pane that has the keyboard — with a
/// browser pane focused, the tab's active terminal pane (A6 makes
/// `focused` return it) — while its shell lives.
PaneSession? commandTarget(TerminalTabsState state) {
  final pane = state.selected?.focused;
  return pane == null || pane.exited ? null : pane;
}

/// D35: a command is pasted (A1's filtered paste, bracketed when the shell
/// asks) then Enter; a snippet only pasted.
CommandRun runUserCommand(TerminalTabsState state, UserCommand command) {
  final pane = commandTarget(state);
  if (pane == null) return CommandRun.noTerminal;
  pane.terminal.paste(command.text);
  if (command.enter) pane.terminal.keyInput(TerminalKey.enter);
  return CommandRun.ran;
}

/// D31: `text:` / `csi:` / `esc:` bytes, raw.
CommandRun sendTextToFocused(TerminalTabsState state, String text) {
  final pane = commandTarget(state);
  if (pane == null) return CommandRun.noTerminal;
  pane.terminal.sendUserText(text);
  return CommandRun.ran;
}
```

(`PaneSession.terminal` is the `DesktopTerminal` A3 stores per pane; if the field is typed `Terminal`, type it `DesktopTerminal` — it always is one.)

`apps/desktop/lib/src/ui/terminal/close_tab.dart`:

```dart
Future<void> closeTabWithConfirm({
  required TerminalTabs tabs,
  required WindowRouter router,
  required AppLocalizations l10n,
  required TerminalTab tab,
  ConfirmClose confirm = ConfirmClose.whenRunning,
}) async {
  final running = tabs.runningPaneCount(tab.id);
  // A9 D20: Ghostty's confirm-close-surface; `true` = A1 D15 / A3 D28.
  final ask = switch (confirm) {
    ConfirmClose.never => false,
    ConfirmClose.always => true,
    ConfirmClose.whenRunning => running > 0,
  };
  if (ask) {
    final ok = await router.confirm(
      ConfirmRequest(
        title: l10n.confirmCloseRunningTitle(tab.label),
        body: running > 0
            ? (tab.isSplit
                  ? l10n.confirmCloseRunningPanesBody(running)
                  : l10n.confirmCloseRunningBody)
            : (tab.isSplit
                  ? l10n.confirmCloseAlwaysPanesBody(tab.paneCount)
                  : l10n.confirmCloseAlwaysBody),
        confirmLabel: l10n.confirmCloseRunningAction,
      ),
    );
    if (!ok) return;
  }
  tabs.close(tab.id);
}

Future<void> closePaneWithConfirm({
  required TerminalTabs tabs,
  required WindowRouter router,
  required AppLocalizations l10n,
  required TerminalTab tab,
  required int paneId,
  ConfirmClose confirm = ConfirmClose.whenRunning,
}) async {
  final pane = tab.panes[paneId];
  if (pane == null) return;
  if (!tab.isSplit) {
    return closeTabWithConfirm(
      tabs: tabs,
      router: router,
      l10n: l10n,
      tab: tab,
      confirm: confirm,
    );
  }
  final running = tabs.needsPaneCloseConfirm(paneId);
  final ask = switch (confirm) {
    ConfirmClose.never => false,
    ConfirmClose.always => true,
    ConfirmClose.whenRunning => running,
  };
  if (ask) {
    final ok = await router.confirm(
      ConfirmRequest(
        title: l10n.confirmCloseRunningTitle(pane.automaticLabel),
        body: running
            ? l10n.confirmCloseRunningPaneBody
            : l10n.confirmClosePaneAlwaysBody,
        confirmLabel: l10n.confirmCloseRunningPaneAction,
      ),
    );
    if (!ok) return;
  }
  tabs.closePane(paneId);
}
```

(If A6 changed `closePaneWithConfirm` for browser panes — negative ids, no shell — keep A6's branch first and apply `confirm` only to terminal panes.) Callers pass the setting: in `terminal_workspace_page.dart` `closeTab`/`closePane` add `confirm: ref.read(shellxConfigProvider).config.confirmClose`; same in `tray_actions.dart` where it calls `closePaneWithConfirm`/`closeTabWithConfirm` (it has a `Ref`: `ref.read(shellxConfigProvider)…`). The CLI's `ui.close` (A7 D18) is untouched.

ARB (`app_en.arb`, after `confirmCloseRunningPaneAction`):

```json
  "confirmCloseAlwaysBody": "The shell in this tab will close.",
  "@confirmCloseAlwaysBody": {"description": "A9 D20 confirm-close-surface = always, idle one-pane tab"},
  "confirmCloseAlwaysPanesBody": "{count, plural, =1{1 pane in this tab will close.} other{{count} panes in this tab will close.}}",
  "@confirmCloseAlwaysPanesBody": {"description": "A9 D20, idle split tab", "placeholders": {"count": {"type": "int"}}},
  "confirmClosePaneAlwaysBody": "The shell in this pane will close.",
  "@confirmClosePaneAlwaysBody": {"description": "A9 D20, idle pane"},
```

`app_vi.arb`:

```json
  "confirmCloseAlwaysBody": "Shell trong tab này sẽ đóng.",
  "confirmCloseAlwaysPanesBody": "{count, plural, other{{count} pane trong tab này sẽ đóng.}}",
  "confirmClosePaneAlwaysBody": "Shell trong pane này sẽ đóng.",
```

Run `cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter gen-l10n`.

- [ ] **Step 4: Run the tests**

Run: `cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/terminal/ test/ui/confirm_close_config_test.dart && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test`
Expected: PASS. Format + analyze clean.

- [ ] **Step 5: ⚠ MANUAL (macOS)**

`macos-option-as-alt = true`: in `emacs -nw` Option+X opens `M-x`; in zsh Option+B/F move by word; Option+←/→ still move by word; with `left`, right-Option+E still types the `´` dead key. `false`: Option+2 types `™` (today's behaviour). Record in the ledger.

- [ ] **Step 6: Commit**

```bash
git add apps/desktop/lib/src/terminal/user_commands.dart apps/desktop/lib/src/terminal/terminal_input.dart apps/desktop/lib/src/terminal/desktop_terminal.dart apps/desktop/lib/src/terminal/terminal_tabs.dart apps/desktop/lib/src/ui/terminal/close_tab.dart apps/desktop/lib/src/ui/terminal/terminal_workspace_page.dart apps/desktop/lib/src/tray/tray_actions.dart apps/desktop/lib/l10n apps/desktop/test/terminal/option_as_alt_test.dart apps/desktop/test/terminal/config_behaviour_test.dart apps/desktop/test/ui/confirm_close_config_test.dart
git commit -m "feat(desktop): macOS Option as Alt, scrollback for new panes, new-tab working directory, confirm-close-surface, user commands and raw key text (A9 D17, D19-D21, D31, D35)"
```

---

### Task 8: Live keybindings in the window — maps from the config, AltGr for every chord, A9 actions, labels, open-config with a template, browser forwarding (D24–D26, D29–D31, D37, D46)

**Files:**
- Create: `apps/desktop/lib/src/config/config_template.dart`, `apps/desktop/lib/src/config/config_opener.dart`
- Create: `apps/desktop/test/support/config_workspace.dart`
- Modify: `apps/desktop/lib/src/ui/terminal/terminal_workspace_page.dart`, `apps/desktop/lib/src/ui/terminal/shortcut_labels.dart` (+ every call site the analyzer flags), `apps/desktop/lib/src/terminal/terminal_tabs.dart` (notices), `apps/desktop/lib/src/ui/terminal/terminal_overlays.dart`, A6's browser pane view (`apps/desktop/lib/src/browser/browser_pane_view.dart` or wherever `_syncForwarded` lives), `apps/desktop/lib/l10n/app_{en,vi}.arb`
- Test: `apps/desktop/test/config/config_template_test.dart`, `apps/desktop/test/config/config_opener_test.dart`, `apps/desktop/test/ui/config_shortcuts_test.dart`, `apps/desktop/test/browser/browser_forwarded_config_test.dart`

**Interfaces:**
- Consumes: Tasks 4–7.
- Produces:
  - `String configTemplate({required bool mac, required List<String> ghosttyFiles})`.
  - `typedef ProcessStarter = Future<void> Function(String executable, List<String> arguments)`; `final class ConfigFileOpener { ConfigFileOpener({required bool windows, ProcessStarter? start}); Future<bool> open(String path, {required String template}) }`; `final configFileOpenerProvider = Provider<ConfigFileOpener>`; `Future<bool> openShellxConfig(T Function<T>(ProviderListenable<T>) read)` (creates from the template when missing, toast on failure; callers pass `ref.read`).
  - `TabNotice`s: `NoTerminalForCommandNotice`, `ConfigOpenFailedNotice(String path)`.
  - `shortcut_labels.dart`: `String? actionShortcutLabel(KeyAction a)`; every existing `…ShortcutLabel()` of a bindable action returns `String?`.
  - Workspace: `_invoke(Intent)`; actions for `CloseWholeTabIntent`, `ReloadConfigIntent`, `OpenConfigIntent`, `RunUserCommandIntent`, `SendTextIntent`, `IgnoreKeyIntent`; `CommandPaletteIntent`, `ShowShortcutsIntent`, `ShowConfigProblemsIntent` registered **disabled** until Tasks 10–12.
  - Test support: `Future<({ProviderContainer container, FakeLocalSessions local, MemoryConfigFs fs})> pumpConfiguredWorkspace(WidgetTester tester, {String config = '', TargetPlatform? platform, List<Override> extra = const []})`, `Future<void> disposeWorkspace(WidgetTester, ProviderContainer)`.
  - ARB: `userCommandNoTerminal`, `configOpenFailed`.

- [ ] **Step 1: Write the failing tests**

Create `apps/desktop/test/support/config_workspace.dart`:

```dart
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/l10n/app_localizations.dart';
import 'package:shellx_desktop/src/agent/agent_controller.dart';
import 'package:shellx_desktop/src/agent/desktop_services.dart';
import 'package:shellx_desktop/src/terminal/local_sessions_provider.dart';
import 'package:shellx_desktop/src/terminal/terminal_tabs.dart';
import 'package:shellx_desktop/src/ui/terminal/terminal_workspace_page.dart';
import 'package:shellx_desktop/src/ui/theme/shellx_desktop_theme.dart';
import 'package:shellx_desktop/src/ui/window_router.dart';

import 'config_harness.dart';
import 'fake_local_sessions.dart';
import 'fakes.dart';
import 'memory_config_fs.dart';

/// The workspace with one open tab and [config] loaded (A9 tests).
Future<({ProviderContainer container, FakeLocalSessions local, MemoryConfigFs fs})>
pumpConfiguredWorkspace(
  WidgetTester tester, {
  String config = '',
  List<Override> extra = const [],
}) async {
  final fs = MemoryConfigFs();
  if (config.isNotEmpty) fs.write(testConfigPaths().shellx, config);
  final local = FakeLocalSessions();
  final h = TestHarness(settings: {'onboarding_done': true});
  final container = ProviderContainer(
    overrides: [
      desktopServicesProvider.overrideWithValue(h.services()),
      localSessionsProvider.overrideWithValue(local),
      ...configOverrides(fs, platform: defaultTargetPlatform),
      ...extra,
    ],
  );
  await h.seedSignedIn();
  await container.read(agentControllerProvider.notifier).bootstrap(watchForWake: false);
  await loadConfig(container);
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
  await container.read(terminalTabsProvider.notifier).openTab();
  await tester.pumpAndSettle();
  return (container: container, local: local, fs: fs);
}

/// Bootstrap starts timers: tear the tree down before the test ends.
Future<void> disposeWorkspace(WidgetTester tester, ProviderContainer c) async {
  await tester.pumpWidget(const SizedBox());
  c.dispose();
}
```

Create `apps/desktop/test/ui/config_shortcuts_test.dart`:

```dart
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/config/config_controller.dart';
import 'package:shellx_desktop/src/config/config_opener.dart';
import 'package:shellx_desktop/src/terminal/pane_layout.dart';
import 'package:shellx_desktop/src/terminal/terminal_tabs.dart';
import 'package:shellx_desktop/src/ui/terminal/shortcut_labels.dart';

import '../support/config_harness.dart';
import '../support/config_workspace.dart';

Future<void> chord(WidgetTester tester, List<LogicalKeyboardKey> mods, LogicalKeyboardKey key) async {
  for (final m in mods) {
    await tester.sendKeyDownEvent(m);
  }
  await tester.sendKeyEvent(key);
  for (final m in mods.reversed) {
    await tester.sendKeyUpEvent(m);
  }
  await tester.pumpAndSettle();
}

const cmd = LogicalKeyboardKey.metaLeft;
const shift = LogicalKeyboardKey.shiftLeft;
const ctrl = LogicalKeyboardKey.controlLeft;

final class RecordingOpener implements ConfigFileOpener {
  final opened = <String>[];
  @override
  Future<bool> open(String path, {required String template}) async {
    opened.add(path);
    return true;
  }
}

void main() {
  testWidgets('a custom chord splits; the default still works; labels follow (criterion 5)',
      variant: TargetPlatformVariant.only(TargetPlatform.macOS), (tester) async {
    final w = await pumpConfiguredWorkspace(tester, config: 'keybind = super+shift+t=new_split:down\nkeybind = super+shift+d=unbind\n');
    expect(splitDownShortcutLabel(), '⌘⇧T');
    await chord(tester, [cmd, shift], LogicalKeyboardKey.keyT);
    final tab = w.container.read(terminalTabsProvider).selected!;
    expect(tab.isSplit, isTrue);
    expect((tab.layout as PaneSplit).axis, SplitAxis.column);
    await chord(tester, [cmd, shift], LogicalKeyboardKey.keyD); // unbound
    expect(w.container.read(terminalTabsProvider).selected!.paneCount, 2);
    await disposeWorkspace(tester, w.container);
  });

  testWidgets('a reload applies new chords at once (criterion 2)',
      variant: TargetPlatformVariant.only(TargetPlatform.macOS), (tester) async {
    final w = await pumpConfiguredWorkspace(tester);
    w.fs.write(testConfigPaths().shellx, 'keybind = super+k=new_tab\n');
    await chord(tester, [cmd, shift], LogicalKeyboardKey.comma); // reload_config
    final before = w.container.read(terminalTabsProvider).tabs.length;
    await chord(tester, [cmd], LogicalKeyboardKey.keyK);
    expect(w.container.read(terminalTabsProvider).tabs.length, before + 1);
    expect(w.container.read(shellxConfigProvider).lastLoad!.manual, isTrue);
    await disposeWorkspace(tester, w.container);
  });

  testWidgets('AltGr+Q types while Ctrl+Alt+Q is bound (D26)',
      variant: TargetPlatformVariant.only(TargetPlatform.windows), (tester) async {
    final w = await pumpConfiguredWorkspace(tester, config: 'keybind = ctrl+alt+q=new_tab\n');
    final tabs = w.container.read(terminalTabsProvider).tabs.length;
    await chord(tester, [ctrl, LogicalKeyboardKey.altRight], LogicalKeyboardKey.keyQ);
    expect(w.container.read(terminalTabsProvider).tabs.length, tabs);
    await chord(tester, [ctrl, LogicalKeyboardKey.altLeft], LogicalKeyboardKey.keyQ);
    expect(w.container.read(terminalTabsProvider).tabs.length, tabs + 1);
    await disposeWorkspace(tester, w.container);
  });

  testWidgets('text:, ignore and run_command reach the focused terminal (D31, D35)',
      variant: TargetPlatformVariant.only(TargetPlatform.macOS), (tester) async {
    final w = await pumpConfiguredWorkspace(
      tester,
      config: r'''
keybind = ctrl+g=text:ls\n
keybind = ctrl+b=ignore
command = Lint = npm run lint
keybind = super+l=run_command:Lint
''',
    );
    final id = w.container.read(terminalTabsProvider).selected!.focused.id;
    final writes = w.local.views[id]!.writes;
    await chord(tester, [ctrl], LogicalKeyboardKey.keyG);
    expect(writes.join(), 'ls\n');
    writes.clear();
    await chord(tester, [ctrl], LogicalKeyboardKey.keyB);
    expect(writes, isEmpty);
    await chord(tester, [cmd], LogicalKeyboardKey.keyL);
    expect(writes.join(), 'npm run lint\r');
    await disposeWorkspace(tester, w.container);
  });

  testWidgets('⌘, opens the ShellX file (D37)',
      variant: TargetPlatformVariant.only(TargetPlatform.macOS), (tester) async {
    final opener = RecordingOpener();
    final w = await pumpConfiguredWorkspace(
      tester,
      extra: [configFileOpenerProvider.overrideWithValue(opener)],
    );
    await chord(tester, [cmd], LogicalKeyboardKey.comma);
    expect(opener.opened, [testConfigPaths().shellx]);
    await disposeWorkspace(tester, w.container);
  });

  testWidgets('no config: the A1-A6 shortcuts are unchanged',
      variant: TargetPlatformVariant.only(TargetPlatform.macOS), (tester) async {
    final w = await pumpConfiguredWorkspace(tester);
    expect(newTabShortcutLabel(), '⌘T');
    await chord(tester, [cmd], LogicalKeyboardKey.keyD);
    expect(w.container.read(terminalTabsProvider).selected!.paneCount, 2);
    await disposeWorkspace(tester, w.container);
  });
}
```

Create `apps/desktop/test/config/config_template_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/config/config_problem.dart';
import 'package:shellx_desktop/src/config/config_syntax.dart';
import 'package:shellx_desktop/src/config/config_template.dart';
import 'package:shellx_desktop/src/config/shellx_config.dart';

void main() {
  for (final mac in [true, false]) {
    test('the template is all comments: it changes nothing (mac: $mac)', () {
      final text = configTemplate(mac: mac, ghosttyFiles: const ['/h/.config/ghostty/config']);
      final problems = <ConfigProblem>[];
      expect(parseConfigText(text, file: '/c', problems: problems), isEmpty);
      expect(problems, isEmpty);
      expect(text, contains('/h/.config/ghostty/config'));
      expect(text, contains(mac ? 'super+shift+t=new_split:down' : 'ctrl+shift+alt+t=new_split:down'));
    });
  }

  test('every commented "# key = value" example parses without problems', () {
    final text = configTemplate(mac: true, ghosttyFiles: const []);
    final examples = [
      for (final line in text.split('\n'))
        if (RegExp(r'^# [a-z-]+ = ').hasMatch(line)) line.substring(2).split('  (').first,
    ].join('\n');
    final problems = <ConfigProblem>[];
    buildShellxConfig(
      ghostty: const [],
      shellx: parseConfigText(examples, file: '/c', problems: problems),
      problems: problems,
      macos: true,
      home: '/h',
    );
    expect(problems.where((p) => p.severity == ConfigSeverity.error), isEmpty);
  });
}
```

Create `apps/desktop/test/config/config_opener_test.dart`:

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/config/config_opener.dart';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('shellx-a9-open'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('a missing file is created from the template, then opened (D37)', () async {
    final runs = <List<String>>[];
    final opener = ConfigFileOpener(
      windows: false,
      start: (exe, args) async => runs.add([exe, ...args]),
    );
    final path = '${dir.path}/shellx/config';
    expect(await opener.open(path, template: '# hi\n'), isTrue);
    expect(File(path).readAsStringSync(), '# hi\n');
    expect(runs.single, ['/usr/bin/open', '-t', path]);
    // An existing file is never rewritten.
    File(path).writeAsStringSync('font-size = 14\n');
    await opener.open(path, template: '# hi\n');
    expect(File(path).readAsStringSync(), 'font-size = 14\n');
  });

  test('Windows: Notepad', () async {
    final runs = <List<String>>[];
    final opener = ConfigFileOpener(windows: true, start: (exe, args) async => runs.add([exe, ...args]));
    await opener.open('${dir.path}/c', template: '');
    expect(runs.single.first, 'notepad.exe');
  });

  test('a failure returns false, never throws', () async {
    final opener = ConfigFileOpener(windows: false, start: (_, _) async => throw const OSError('no'));
    expect(await opener.open('${dir.path}/x', template: ''), isFalse);
  });
}
```

Create `apps/desktop/test/browser/browser_forwarded_config_test.dart`:

```dart
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/config/config_problem.dart';
import 'package:shellx_desktop/src/config/config_syntax.dart';
import 'package:shellx_desktop/src/config/keybindings.dart';
import 'package:shellx_desktop/src/config/shellx_config.dart';
import 'package:shellx_desktop/src/ui/terminal/terminal_shortcuts.dart';

KeyBindings bindings(String text) => resolveKeyBindings(
  platform: TargetPlatform.macOS,
  entries: [
    for (final e in parseConfigText(text, file: '/c', problems: []))
      KeybindEntry(e.value, e),
  ],
  commandNames: const {},
  optionAsAlt: OptionAsAlt.off,
  problems: <ConfigProblem>[],
);

void main() {
  test('forwarded chords follow the bindings (D30)', () {
    final defaults = browserForwardedChords(TargetPlatform.macOS, loading: false);
    expect(defaults, contains('meta+l'));
    final custom = browserForwardedChords(
      TargetPlatform.macOS,
      loading: false,
      bindings: bindings('keybind = super+l=unbind\nkeybind = super+k=browser_focus_address\nkeybind = f2=new_tab\nkeybind = ctrl+g=text:x'),
    );
    expect(custom, isNot(contains('meta+l')));
    expect(custom, contains('meta+k'));
    expect(custom, contains('f2'));
    expect(custom, isNot(contains('ctrl+g'))); // text: stays with the page
  });
}
```

(The chord spellings are A6's `chordOf` format — modifiers in A6's order, then the key; adjust the expected strings to that format if A6 orders modifiers differently. Add a widget test next to A6's `browser_pane_view_test` that a reload re-sends the list: load a config, `await loadConfig(container)`, pump, and assert A6's fake engine received a second `setForwardedChords` call containing `meta+k` — use the fake's real recording field.)

- [ ] **Step 2: Run the tests to see them fail**

Run: `cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/ui/config_shortcuts_test.dart test/config/config_template_test.dart test/config/config_opener_test.dart test/browser/browser_forwarded_config_test.dart`
Expected: FAIL.

- [ ] **Step 3: Implement**

Create `apps/desktop/lib/src/config/config_template.dart`:

```dart
/// D37: the file "Open configuration file" creates — every line a comment,
/// so it changes nothing until the user uncomments one. English, like the
/// CLI (A7 D11).
String configTemplate({required bool mac, required List<String> ghosttyFiles}) {
  final reload = mac ? 'Cmd+Shift+,' : 'Ctrl+Shift+,';
  final split = mac ? 'super+shift+t' : 'ctrl+shift+alt+t';
  final unbind = mac ? 'super+d' : 'ctrl+shift+d';
  final run = mac ? 'super+shift+l' : 'ctrl+shift+alt+l';
  final ghostty = ghosttyFiles.isEmpty
      ? ['#   (none found)']
      : [for (final f in ghosttyFiles) '#   $f'];
  return [
    '# ShellX configuration. Ghostty syntax: key = value; lines starting with # are comments.',
    '# Saved changes apply within a second; reload now with $reload.',
    '# Problems: Command palette → "Show configuration problems", or `shellx config check`.',
    '#',
    '# ShellX also reads fonts and colours from your Ghostty configuration:',
    ...ghostty,
    '# Turn that off with: ghostty-config = false',
    '',
    '# --- Text ---',
    '# font-family = JetBrains Mono',
    '# font-size = 13  (9–28)',
    '',
    '# --- Colours (hex) ---',
    '# theme = Dracula  (a file in the themes folder next to this file, or a Ghostty theme)',
    '# background = #0b1215',
    '# foreground = #d4e1e4',
    '# palette = 1=#f07178',
    '# cursor-color = #d4e1e4',
    '# selection-background = #5fd4e2',
    '# cursor-style = block  (block, bar, underline)',
    '',
    '# --- Terminal ---',
    '# scrollback-limit = 10000  (lines, for new panes)',
    '# window-padding-x = 10',
    '# window-padding-y = 6',
    '# macos-option-as-alt = false  (true, left, right)',
    '# confirm-close-surface = true  (false, always)',
    '# working-directory = home  (inherit, or an absolute path)',
    '',
    '# --- Keys (Ghostty keybind syntax; later lines win) ---',
    '# keybind = $split=new_split:down',
    '# keybind = ctrl+a>c=new_tab',
    '# keybind = $unbind=unbind',
    '# keybind = $run=run_command:Lint',
    '',
    '# --- Your commands (Command palette) ---',
    '# command = Lint = npm run lint',
    r'# snippet = Status = "git status\n"',
    '',
  ].join('\n');
}
```

Create `apps/desktop/lib/src/config/config_opener.dart`:

```dart
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

typedef ProcessStarter =
    Future<void> Function(String executable, List<String> arguments);

Future<void> _detached(String exe, List<String> args) async {
  await Process.start(exe, args, mode: ProcessStartMode.detached);
}

/// D37: creates the file from the template when missing, then opens it in
/// the default text editor (macOS `open -t`, Windows Notepad).
class ConfigFileOpener {
  ConfigFileOpener({required this.windows, ProcessStarter? start})
    : _start = start ?? _detached;

  final bool windows;
  final ProcessStarter _start;

  Future<bool> open(String path, {required String template}) async {
    try {
      final file = File(path);
      if (!await file.exists()) {
        await file.parent.create(recursive: true);
        await file.writeAsString(template, flush: true);
      }
      if (windows) {
        await _start('notepad.exe', [path]);
      } else {
        await _start('/usr/bin/open', ['-t', path]);
      }
      return true;
    } catch (error) {
      debugPrint('ShellX: opening the config failed: ${error.runtimeType}');
      return false;
    }
  }
}

final configFileOpenerProvider = Provider<ConfigFileOpener>(
  (ref) => ConfigFileOpener(windows: Platform.isWindows),
);
```

Add a shared helper in the same file (it needs Riverpod and the paths):

```dart
/// ⌘,, the palette, the tray, the problems panel (D37). Shows
/// [ConfigOpenFailedNotice] on failure. Takes `ref.read` so both a
/// `WidgetRef` (window) and a `Ref` (tray) can call it.
Future<bool> openShellxConfig(
  T Function<T>(ProviderListenable<T> provider) read,
) async {
  final paths = read(configPathsProvider);
  final state = read(shellxConfigProvider);
  final ok = await read(configFileOpenerProvider).open(
    paths.shellx,
    template: configTemplate(
      mac: read(configPlatformProvider) == TargetPlatform.macOS,
      ghosttyFiles: [
        for (final f in paths.ghostty)
          if (state.ghosttyUsed && state.files.contains(f)) f,
      ],
    ),
  );
  if (!ok) {
    read(terminalTabsProvider.notifier)
        .showNotice(ConfigOpenFailedNotice(paths.shellx));
  }
  return ok;
}
```

(imports: `config_controller.dart`, `config_template.dart`, `../terminal/terminal_tabs.dart`.)

In `apps/desktop/lib/src/terminal/terminal_tabs.dart`, next to the other notices:

```dart
/// A9 D35: a command with no live terminal to run in (neutral).
final class NoTerminalForCommandNotice extends TabNotice {
  const NoTerminalForCommandNotice();
}

/// A9 D37: the configuration file could not be opened (error).
final class ConfigOpenFailedNotice extends TabNotice {
  const ConfigOpenFailedNotice(this.path);
  final String path;
}
```

In `terminal_overlays.dart` `NoticeToast`: `_neutral` adds `|| widget.notice is NoTerminalForCommandNotice`; `_text` adds `NoTerminalForCommandNotice() => l10n.userCommandNoTerminal, ConfigOpenFailedNotice(:final path) => l10n.configOpenFailed(path),`.

ARB en / vi:

```json
  "userCommandNoTerminal": "There's no terminal to run this in",
  "@userCommandNoTerminal": {"description": "UI-A9 §7.1"},
  "configOpenFailed": "Couldn't open {path}",
  "@configOpenFailed": {"description": "UI-A9 §7.1", "placeholders": {"path": {"type": "String"}}},
```

```json
  "userCommandNoTerminal": "Không có terminal để chạy lệnh này",
  "configOpenFailed": "Không mở được {path}",
```

`apps/desktop/lib/src/ui/terminal/shortcut_labels.dart` becomes:

```dart
import 'package:flutter/foundation.dart';

import '../../config/keybind_actions.dart';
import '../../config/keybindings.dart';

/// macOS shows ⌘ shortcuts; Windows Ctrl+Shift (spec criterion 2). Labels
/// are built from the platform, never translated (UI §5).
bool get isMacDesktop => defaultTargetPlatform == TargetPlatform.macOS;

KeyBindings get _bindings =>
    labelBindings ?? KeyBindings.defaults(defaultTargetPlatform);

/// A9 D29: the first trigger in effect; null when the action is unbound
/// (callers then show no hint).
String? actionShortcutLabel(KeyAction action) => _bindings.labelOf(action);

String? newTabShortcutLabel() => actionShortcutLabel(const KeyAction('new_tab'));
String? closeTabShortcutLabel() =>
    actionShortcutLabel(const KeyAction('close_surface'));
String? copyShortcutLabel() =>
    actionShortcutLabel(const KeyAction('copy_to_clipboard'));
String? pasteShortcutLabel() =>
    actionShortcutLabel(const KeyAction('paste_from_clipboard'));
String? selectAllShortcutLabel() =>
    actionShortcutLabel(const KeyAction('select_all'));
String? newWorkspaceShortcutLabel() =>
    actionShortcutLabel(const KeyAction('new_workspace'));
String? notificationsShortcutLabel() =>
    actionShortcutLabel(const KeyAction('toggle_notifications'));
String? nextUnreadShortcutLabel() =>
    actionShortcutLabel(const KeyAction('jump_to_unread'));
String? splitRightShortcutLabel() =>
    actionShortcutLabel(const KeyAction('new_split', 'right'));
String? splitDownShortcutLabel() =>
    actionShortcutLabel(const KeyAction('new_split', 'down'));
String? zoomPaneShortcutLabel() =>
    actionShortcutLabel(const KeyAction('toggle_split_zoom'));
String? equalizePanesShortcutLabel() =>
    actionShortcutLabel(const KeyAction('equalize_splits'));
String? closePaneShortcutLabel() => closeTabShortcutLabel();
String? openBrowserShortcutLabel() =>
    actionShortcutLabel(const KeyAction('open_browser'));

// Sidebar-local keys (A2), not configurable.
String renameShortcutLabel() => 'F2';
String moveUpShortcutLabel() => isMacDesktop ? '⌥↑' : 'Alt+↑';
String moveDownShortcutLabel() => isMacDesktop ? '⌥↓' : 'Alt+↓';
```

Keep A6's browser label functions, re-expressed as `actionShortcutLabel(const KeyAction('browser_reload'))` etc. (`browser_focus_address`, `browser_reload`, `browser_back`, `browser_forward`). Then run `flutter analyze` and fix every call site it reports: where the value goes to a nullable `shortcut:` parameter, pass it through; where it is concatenated (tooltips such as `'${l10n.newTab}  ${newTabShortcutLabel()}'`, A4's `notificationsPanelTooltip`, A6's `browserBack(shortcut)`), use `[text, ?label].join('  ')` or pass `label ?? ''` to an ARB placeholder **and** drop the two spaces when empty: `l10n.browserBack(label ?? '').trimRight()`. No label is ever shown for an unbound action (D29).

`apps/desktop/lib/src/ui/terminal/terminal_workspace_page.dart`:

```dart
  KeyBindings? _shortcutsFor;

  void _buildShortcuts(TargetPlatform platform, KeyBindings bindings) {
    if (_shortcutsPlatform == platform &&
        identical(_shortcutsFor, bindings) &&
        terminalShortcuts != null) {
      return;
    }
    _shortcutsPlatform = platform;
    _shortcutsFor = bindings;
    terminalShortcuts = terminalViewShortcuts(platform, bindings: bindings);
    _workspaceShortcuts = desktopShortcuts(platform, bindings: bindings);
  }
```

and in `build`: `_buildShortcuts(defaultTargetPlatform, ref.watch(shellxConfigProvider.select((s) => s.bindings)));` (replacing the one-argument call).

`_WindowAction`: every window shortcut yields to AltGr on Windows (D26):

```dart
  @override
  bool isEnabled(T intent) => !_altGrHeld() && (_enabled?.call(intent) ?? true);

  /// A9 D26 (A1, A3 D20 for every chord): with the right Alt held on
  /// Windows (AltGr = Ctrl+right Alt) the key is the keyboard layout's.
  static bool _altGrHeld() =>
      defaultTargetPlatform == TargetPlatform.windows &&
      HardwareKeyboard.instance.logicalKeysPressed.contains(
        LogicalKeyboardKey.altRight,
      );
```

Add to `_actions()`:

```dart
      CloseWholeTabIntent: run<CloseWholeTabIntent>((_) {
        closePanel();
        final selected = ref.read(terminalTabsProvider).selected;
        if (selected != null) unawaited(closeTab(selected));
      }, enabled: (_) => ref.read(terminalTabsProvider).selected != null),
      ReloadConfigIntent: run<ReloadConfigIntent>(
        (_) => unawaited(ref.read(shellxConfigProvider.notifier).load(manual: true)),
      ),
      OpenConfigIntent: run<OpenConfigIntent>((_) {
        closePanel();
        unawaited(openShellxConfig(ref.read));
      }),
      RunUserCommandIntent: run<RunUserCommandIntent>((intent) => _runCommand(intent.name)),
      // Only while a terminal has the keyboard: in the sidebar the key is
      // the sidebar's.
      SendTextIntent: run<SendTextIntent>(
        (intent) => sendTextToFocused(ref.read(terminalTabsProvider), intent.text),
        enabled: (_) => terminalFocus.hasFocus,
      ),
      IgnoreKeyIntent: run<IgnoreKeyIntent>((_) {}),
      // Tasks 10–12 enable these.
      CommandPaletteIntent: run<CommandPaletteIntent>((_) {}, enabled: (_) => false),
      ShowShortcutsIntent: run<ShowShortcutsIntent>((_) {}, enabled: (_) => false),
      ShowConfigProblemsIntent: run<ShowConfigProblemsIntent>((_) {}, enabled: (_) => false),
```

and the font actions use the step (Task 6). Add the helpers:

```dart
  /// D35: a `command`/`snippet` by name; with no live terminal, a toast.
  void _runCommand(String name) {
    final command = ref
        .read(shellxConfigProvider)
        .config
        .commands
        .where((c) => c.name == name)
        .firstOrNull;
    if (command == null) return;
    closePanel();
    final ran = runUserCommand(ref.read(terminalTabsProvider), command);
    if (ran == CommandRun.noTerminal) {
      ref.read(terminalTabsProvider.notifier).showNotice(const NoTerminalForCommandNotice());
    } else {
      focusTerminal();
    }
  }

  /// Runs [intent] through this window's actions when it is enabled (the
  /// palette and key sequences, Tasks 9 and 11).
  bool _invoke(Intent intent) {
    final action = _actionsMap[intent.runtimeType];
    if (action == null || !action.isEnabled(intent)) return false;
    action.invoke(intent);
    return true;
  }
```

A6's browser pane view: `_onChord` uses `intentForForwardedChord(chord, defaultTargetPlatform, bindings: ref.read(shellxConfigProvider).bindings)`; `_syncForwarded` passes the same `bindings:`; and in its `build` (or `initState` via `ref.listenManual`):

```dart
    // A9 D30: new bindings → the native side gets the new list.
    ref.listen(shellxConfigProvider.select((s) => s.bindings), (_, _) {
      _forwardedLoading = null; // force the next sync
      final state = ref.read(<A6's browser pane state provider>(widget.paneId));
      if (state != null) _syncForwarded(state);
    });
```

(`_forwardedLoading` becomes `bool?` if A6 typed it `bool`; use A6's real state provider name.)

- [ ] **Step 4: Run the tests**

Run: `cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/ui/config_shortcuts_test.dart test/config/ test/browser/ && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test`
Expected: PASS, including A3's `pane_shortcuts_test` AltGr tests and A6's browser tests. Format + analyze clean.

- [ ] **Step 5: ⚠ MANUAL**

macOS: ⌘, opens the file in TextEdit (or the default text editor) and is **not** swallowed by `MainMenu.xib`'s "Preferences…" (D46; if it is, delete `keyEquivalent=","` from that `menuItem`, rebuild, re-check, and add the xib to this task's commit). Windows: Ctrl+, opens Notepad; Notepad saving `font-size = 16` applies within ~1.5 s; German layout: AltGr+Q types `@` with `keybind = ctrl+alt+q=new_tab` set, left Ctrl+Alt+Q opens a tab. A browser pane: `keybind = super+k=browser_focus_address` + reload → ⌘K in a page text field focuses the address bar. Record in the ledger.

- [ ] **Step 6: Commit**

```bash
git add apps/desktop/lib/src/config/config_template.dart apps/desktop/lib/src/config/config_opener.dart apps/desktop/lib/src/ui/terminal/terminal_workspace_page.dart apps/desktop/lib/src/ui/terminal/shortcut_labels.dart apps/desktop/lib/src/terminal/terminal_tabs.dart apps/desktop/lib/src/ui/terminal/terminal_overlays.dart apps/desktop/lib/src/browser apps/desktop/lib/src/ui apps/desktop/lib/l10n apps/desktop/test/support/config_workspace.dart apps/desktop/test/ui/config_shortcuts_test.dart apps/desktop/test/config/config_template_test.dart apps/desktop/test/config/config_opener_test.dart apps/desktop/test/browser/browser_forwarded_config_test.dart
git commit -m "feat(desktop): live keybindings — window and browser maps from the config, AltGr yields for every chord, close_tab/reload/open config/text/ignore/run_command actions, labels from the bindings, config template (A9 D24-D26, D29-D31, D37)"
```

(`git add apps/desktop/lib/src/ui` picks up the label call sites the analyzer made you touch; check `git status` first that nothing else is staged.)

---

### Task 9: Two-step key sequences (D28)

**Files:**
- Create: `apps/desktop/lib/src/ui/terminal/key_sequence.dart`
- Modify: `apps/desktop/lib/src/ui/terminal/terminal_workspace_page.dart`, `apps/desktop/lib/src/ui/terminal/terminal_pane.dart`, `apps/desktop/lib/src/ui/terminal/pane_tree_view.dart`, `apps/desktop/lib/l10n/app_{en,vi}.arb`
- Test: `apps/desktop/test/ui/key_sequence_test.dart`

**Interfaces:**
- Consumes: Task 4 `KeyBindings.sequences`, `chordOfEvent`, `chordLabel`; Task 8 `_invoke`, `sendTextToFocused`.
- Produces:
  - `final keySequenceProvider = NotifierProvider<KeySequence, KeyChord?>`; `KeySequence.handle(KeyEvent event, {required bool Function(Intent) invoke, required void Function(KeyChord prefix) sendPrefix, HardwareKeyboard? keyboard}) → KeyEventResult`; `KeySequence.cancel()`.
  - `String? prefixText(KeyChord c)` (Ctrl/Alt + letter → the bytes; else null).
  - `class SequenceIndicator extends ConsumerWidget` (UI-A9 §5).
  - `PaneTerminal`/`TerminalPane` gain `KeyEventResult Function(KeyEvent)? onKeyEvent`.
  - ARB: `sequencePending`, `sequencePendingAnnounce`.

- [ ] **Step 1: Write the failing tests**

Create `apps/desktop/test/ui/key_sequence_test.dart`:

```dart
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/config/keybind_trigger.dart';
import 'package:shellx_desktop/src/terminal/terminal_tabs.dart';
import 'package:shellx_desktop/src/ui/terminal/key_sequence.dart';

import '../support/config_harness.dart';
import '../support/config_workspace.dart';

const ctrl = LogicalKeyboardKey.controlLeft;

Future<void> ctrlA(WidgetTester tester) async {
  await tester.sendKeyDownEvent(ctrl);
  await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
  await tester.sendKeyUpEvent(ctrl);
  await tester.pump();
}

void main() {
  final mac = TargetPlatformVariant.only(TargetPlatform.macOS);

  testWidgets('prefix, then the second key runs the action; the indicator shows meanwhile', variant: mac, (tester) async {
    final w = await pumpConfiguredWorkspace(tester, config: 'keybind = ctrl+a>c=new_tab\n');
    final tabs = w.container.read(terminalTabsProvider).tabs.length;
    await ctrlA(tester);
    expect(w.container.read(keySequenceProvider), parseKeyChord('ctrl+a'));
    expect(find.text('⌃A …'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    await tester.pumpAndSettle();
    expect(w.container.read(terminalTabsProvider).tabs.length, tabs + 1);
    expect(w.container.read(keySequenceProvider), isNull);
    expect(find.text('⌃A …'), findsNothing);
    await disposeWorkspace(tester, w.container);
  });

  testWidgets('Esc cancels silently; the prefix never reached the shell', variant: mac, (tester) async {
    final w = await pumpConfiguredWorkspace(tester, config: 'keybind = ctrl+a>c=new_tab\n');
    final id = w.container.read(terminalTabsProvider).selected!.focused.id;
    await ctrlA(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(w.container.read(keySequenceProvider), isNull);
    expect(w.local.views[id]!.writes.join(), isNot(contains('\x01')));
    expect(w.local.views[id]!.writes.join(), isNot(contains('\x1b')));
    await disposeWorkspace(tester, w.container);
  });

  testWidgets('the prefix twice types the prefix (send-prefix)', variant: mac, (tester) async {
    final w = await pumpConfiguredWorkspace(tester, config: 'keybind = ctrl+a>c=new_tab\n');
    final id = w.container.read(terminalTabsProvider).selected!.focused.id;
    await ctrlA(tester);
    await ctrlA(tester);
    expect(w.local.views[id]!.writes.join(), '\x01');
    expect(w.container.read(keySequenceProvider), isNull);
    await disposeWorkspace(tester, w.container);
  });

  testWidgets('another key cancels and goes on as usual', variant: mac, (tester) async {
    final w = await pumpConfiguredWorkspace(tester, config: 'keybind = ctrl+a>c=new_tab\n');
    final id = w.container.read(terminalTabsProvider).selected!.focused.id;
    final tabs = w.container.read(terminalTabsProvider).tabs.length;
    await ctrlA(tester);
    // Ctrl+E is not a second step: the sequence ends and the key reaches
    // the shell as xterm encodes it (^E).
    await tester.sendKeyDownEvent(ctrl);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyE);
    await tester.sendKeyUpEvent(ctrl);
    await tester.pump();
    expect(w.container.read(keySequenceProvider), isNull);
    expect(w.local.views[id]!.writes.join(), '\x05');
    expect(w.container.read(terminalTabsProvider).tabs.length, tabs);
    await disposeWorkspace(tester, w.container);
  });

  testWidgets('a text field keeps Ctrl+A (D28)', variant: mac, (tester) async {
    final w = await pumpConfiguredWorkspace(tester, config: 'keybind = ctrl+a>c=new_tab\n');
    // F2 on the selected row opens A2's inline rename field.
    // Ctrl+F6: terminal → sidebar (plain F6 is the shell's inside a pane).
    await tester.sendKeyDownEvent(ctrl);
    await tester.sendKeyEvent(LogicalKeyboardKey.f6);
    await tester.sendKeyUpEvent(ctrl);
    await tester.sendKeyEvent(LogicalKeyboardKey.f2);
    await tester.pumpAndSettle();
    expect(find.byType(EditableText), findsOneWidget);
    await ctrlA(tester);
    expect(w.container.read(keySequenceProvider), isNull);
    await disposeWorkspace(tester, w.container);
  });

  testWidgets('a reload cancels a pending sequence', variant: mac, (tester) async {
    final w = await pumpConfiguredWorkspace(tester, config: 'keybind = ctrl+a>c=new_tab\n');
    await ctrlA(tester);
    w.fs.write(testConfigPaths().shellx, 'keybind = ctrl+a>d=new_tab\n');
    await loadConfig(w.container);
    await tester.pump();
    expect(w.container.read(keySequenceProvider), isNull);
    await disposeWorkspace(tester, w.container);
  });

  test('prefixText', () {
    expect(prefixText(parseKeyChord('ctrl+a')!), '\x01');
    expect(prefixText(parseKeyChord('ctrl+b')!), '\x02');
    expect(prefixText(parseKeyChord('alt+a')!), '\x1ba');
    expect(prefixText(parseKeyChord('super+a')!), isNull);
    expect(prefixText(parseKeyChord('ctrl+shift+a')!), isNull);
  });
}
```

(Ctrl+letter is used for the pass-through check because xterm encodes it as a key — plain letters arrive through the text-input connection, which widget tests do not drive.)

- [ ] **Step 2: Run the tests to see them fail**

Run: `cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/ui/key_sequence_test.dart`
Expected: FAIL — `key_sequence.dart` missing.

- [ ] **Step 3: Implement**

Create `apps/desktop/lib/src/ui/terminal/key_sequence.dart`:

```dart
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../../config/config_controller.dart';
import '../../config/keybind_actions.dart';
import '../../config/keybind_trigger.dart';
import '../theme/shellx_desktop_theme.dart';

final keySequenceProvider = NotifierProvider<KeySequence, KeyChord?>(
  KeySequence.new,
);

/// A9 D28: the pending first step of a two-step binding (null: none).
class KeySequence extends Notifier<KeyChord?> {
  @override
  KeyChord? build() {
    ref.listen(shellxConfigProvider.select((s) => s.bindings), (_, _) => cancel());
    return null;
  }

  void cancel() {
    if (state != null) state = null;
  }

  KeyEventResult handle(
    KeyEvent event, {
    required bool Function(Intent intent) invoke,
    required void Function(KeyChord prefix) sendPrefix,
    HardwareKeyboard? keyboard,
  }) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final hk = keyboard ?? HardwareKeyboard.instance;
    final chord = chordOfEvent(event, hk);
    if (chord == null) return KeyEventResult.ignored; // a modifier alone
    final sequences = ref.read(shellxConfigProvider).bindings.sequences;
    final pending = state;
    if (pending == null) {
      if (event is KeyRepeatEvent) return KeyEventResult.ignored;
      // D26: AltGr is the layout's.
      if (defaultTargetPlatform == TargetPlatform.windows &&
          hk.logicalKeysPressed.contains(LogicalKeyboardKey.altRight)) {
        return KeyEventResult.ignored;
      }
      if (sequences.any((b) => b.sequence.first == chord)) {
        state = chord;
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    state = null;
    if (chord.key == LogicalKeyboardKey.escape &&
        !chord.hasCommandModifier &&
        !chord.shift) {
      return KeyEventResult.handled;
    }
    if (chord == pending) {
      sendPrefix(pending);
      return KeyEventResult.handled;
    }
    final match = sequences
        .where((b) => b.sequence.first == pending && b.sequence[1] == chord)
        .firstOrNull;
    if (match != null) {
      invoke(intentForAction(match.action));
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }
}

/// What "the prefix twice" types: Ctrl+letter → its control character,
/// Alt+letter → ESC + letter (tmux/screen prefixes); other prefixes are
/// only consumed.
String? prefixText(KeyChord c) {
  final id = c.key.keyId;
  final letter = id >= 0x61 && id <= 0x7a;
  if (!letter || c.meta || c.shift) return null;
  if (c.control && !c.alt) return String.fromCharCode(id - 0x60);
  if (c.alt && !c.control) return '\x1b${String.fromCharCode(id)}';
  return null;
}

/// UI-A9 §5: "⌃A …" bottom-right of the terminal area while pending.
class SequenceIndicator extends ConsumerWidget {
  const SequenceIndicator({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pending = ref.watch(keySequenceProvider);
    if (pending == null) return const SizedBox.shrink();
    final label = chordLabel(
      pending,
      mac: defaultTargetPlatform == TargetPlatform.macOS,
    );
    return ExcludeSemantics(
      child: Container(
        height: ShellxSizes.sequenceIndicatorHeight,
        padding: const EdgeInsets.symmetric(horizontal: ShellxSpace.s10),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: ShellxDesktopColors.surface,
          borderRadius: BorderRadius.circular(ShellxRadius.pill),
          border: Border.all(color: ShellxDesktopColors.accent),
        ),
        child: Text(
          AppLocalizations.of(context).sequencePending(label),
          style: ShellxText.small.copyWith(
            color: ShellxDesktopColors.textPrimary,
          ),
        ),
      ),
    );
  }
}
```

Add to `ShellxSizes`: `static const double sequenceIndicatorHeight = 28;` and, if `ShellxSpace` has no `s10`, use `ShellxSpace.s8 + ShellxSpace.s2` — do not add a spacing token.

Wiring:
- `PaneTerminal` gains `final KeyEventResult Function(KeyEvent event)? onKeyEvent;` and passes `onKeyEvent: onKeyEvent == null ? null : (_, event) => onKeyEvent!(event)` to `TerminalView`. `PaneTreeView` and `TerminalPane` pass it through (new constructor parameter on each).
- `TerminalPane`'s terminal-area `Stack` gets, last: `const Positioned(right: ShellxSpace.s12, bottom: ShellxSpace.s12, child: SequenceIndicator())`.
- `TerminalWorkspacePageState`:

```dart
  KeyEventResult _sequenceKey(KeyEvent event) {
    // D28: never inside a text field (inline rename, palette, search):
    // Ctrl+A there is the field's.
    final context = FocusManager.instance.primaryFocus?.context;
    if (context != null &&
        (context.widget is EditableText ||
            context.findAncestorWidgetOfExactType<EditableText>() != null)) {
      return KeyEventResult.ignored;
    }
    final result = ref.read(keySequenceProvider.notifier).handle(
      event,
      invoke: _invoke,
      sendPrefix: (prefix) {
        final text = prefixText(prefix);
        if (text != null) sendTextToFocused(ref.read(terminalTabsProvider), text);
      },
    );
    return result;
  }
```

  pass `onKeyEvent: _sequenceKey` to `TerminalPane`; wrap `_body()` inside the `FocusScope` in `Focus(canRequestFocus: false, skipTraversal: true, onKeyEvent: (_, e) => _sequenceKey(e), child: …)` so the sidebar has sequences too. Announce when a sequence starts and cancel on focus/pointer changes:

```dart
  @override
  void initState() {
    super.initState();
    FocusManager.instance.addListener(_cancelSequenceOnFocus);
  }

  FocusNode? _sequenceFocus;
  void _cancelSequenceOnFocus() {
    final now = FocusManager.instance.primaryFocus;
    if (!identical(now, _sequenceFocus)) {
      _sequenceFocus = now;
      ref.read(keySequenceProvider.notifier).cancel();
    }
  }
```

  (remove the listener in `dispose`), in `build`:

```dart
    ref.listen(keySequenceProvider, (_, pending) {
      if (pending == null) return;
      _announce(
        AppLocalizations.of(context).sequencePendingAnnounce(
          chordLabel(pending, mac: isMacDesktop),
        ),
      );
    });
```

  and wrap the `Stack` child of the `FocusScope` in `Listener(onPointerDown: (_) => ref.read(keySequenceProvider.notifier).cancel(), child: …)`. Opening the notifications panel, the palette, the problems panel or the shortcut sheet calls `cancel()` too (they move the focus, which the focus listener already handles).

ARB en / vi:

```json
  "sequencePending": "{shortcut} …",
  "@sequencePending": {"description": "UI-A9 §5", "placeholders": {"shortcut": {"type": "String"}}},
  "sequencePendingAnnounce": "{shortcut} pressed, waiting for the next key",
  "@sequencePendingAnnounce": {"description": "UI-A9 §8", "placeholders": {"shortcut": {"type": "String"}}},
```

```json
  "sequencePending": "{shortcut} …",
  "sequencePendingAnnounce": "Đã bấm {shortcut}, chờ phím tiếp theo",
```

- [ ] **Step 4: Run the tests**

Run: `cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/ui/key_sequence_test.dart && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test`
Expected: PASS. Format + analyze clean.

- [ ] **Step 5: Commit**

```bash
git add apps/desktop/lib/src/ui/terminal/key_sequence.dart apps/desktop/lib/src/ui/terminal/terminal_workspace_page.dart apps/desktop/lib/src/ui/terminal/terminal_pane.dart apps/desktop/lib/src/ui/terminal/pane_tree_view.dart apps/desktop/lib/src/ui/theme/shellx_desktop_theme.dart apps/desktop/lib/l10n apps/desktop/test/ui/key_sequence_test.dart
git commit -m "feat(desktop): two-step key sequences — prefix indicator and announcement, Esc cancels, prefix twice sends it, other keys pass through, reload/focus/click cancel (A9 D28)"
```

---
### Task 10: Problems you can see — toasts, the problems panel, tray "Cấu hình", localized messages (D4, D8, D9, D36, D45)

**Files:**
- Create: `apps/desktop/lib/src/ui/config/action_labels.dart` (problem texts now; action names in Task 11), `apps/desktop/lib/src/ui/config/config_problems_panel.dart`, `apps/desktop/lib/src/ui/config/config_ui_request.dart`
- Modify: `apps/desktop/lib/src/terminal/terminal_tabs.dart` (notices), `apps/desktop/lib/src/ui/terminal/terminal_overlays.dart` (toast action), `apps/desktop/lib/src/ui/terminal/terminal_pane.dart` (passes the action), `apps/desktop/lib/src/ui/terminal/terminal_workspace_page.dart` (toasts, overlay slot), `apps/desktop/lib/src/tray/{tray_action,tray_menu,tray_actions,tray_presenter}.dart`, `apps/desktop/lib/l10n/app_{en,vi}.arb`
- Test: `apps/desktop/test/ui/config_problems_ui_test.dart`, `apps/desktop/test/tray/tray_config_menu_test.dart`

**Interfaces:**
- Consumes: Tasks 5, 8 (`ConfigState.lastLoad`, `visibleProblemCount`, `errorCount`, `openShellxConfig`).
- Produces:
  - `String problemText(AppLocalizations l10n, ConfigProblem p)`; `String problemLocation(AppLocalizations l10n, ConfigProblem p)`.
  - Notices: `ConfigProblemsNotice(int count, {required bool hasErrors})`, `ConfigReloadedNotice`, `ConfigGhosttyNotice`.
  - `NoticeToast({…, VoidCallback? onAction})` — a "Show" button for `ConfigProblemsNotice`.
  - `enum ConfigUiRequest { palette, problems, shortcuts }`; `final configUiRequestProvider = NotifierProvider<ConfigUiRequests, (ConfigUiRequest, int)?>`; `ConfigUiRequests.request(ConfigUiRequest)`.
  - `class ConfigProblemsPanel extends ConsumerWidget { ConfigProblemsPanel({required VoidCallback onClose, required VoidCallback onOpenFile, required VoidCallback onReload}) }`.
  - Workspace: `enum A9Overlay { palette, problems, shortcuts }`, `A9Overlay? overlay`, `openOverlay(A9Overlay)`, `closeOverlay({bool restoreFocus = true})`; `ShowConfigProblemsIntent` enabled when there are problems or the user asks from the palette.
  - Tray: `TrayKeys.config`, `configOpen`, `configReload`, `configShortcuts`, `configProblems`; actions `OpenConfigFile`, `ReloadConfig`, `ShowShortcutsFromTray`, `ShowConfigProblemsFromTray`; the tray view state gains `int configProblemCount`.
  - ARB: every key of UI-A9 §7.1, §7.2 and the tray keys of §7.4.

- [ ] **Step 1: Write the failing tests**

Create `apps/desktop/test/ui/config_problems_ui_test.dart`:

```dart
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/l10n/app_localizations.dart';
import 'package:shellx_desktop/src/config/config_controller.dart';
import 'package:shellx_desktop/src/config/config_problem.dart';
import 'package:shellx_desktop/src/ui/config/action_labels.dart';
import 'package:shellx_desktop/src/ui/config/config_problems_panel.dart';

import '../support/config_harness.dart';
import '../support/config_workspace.dart';

void main() {
  test('the en ARB says exactly what the CLI says (D39)', () {
    final en = lookupAppLocalizations(const Locale('en'));
    final vi = lookupAppLocalizations(const Locale('vi'));
    for (final code in ConfigProblemCode.values) {
      final p = ConfigProblem(
        file: '/c/config',
        line: 2,
        severity: ConfigSeverity.error,
        code: code,
        key: 'font-size',
        value: 'to',
        hint: '9–28',
        detail: '4.1',
      );
      expect(problemText(en, p), configProblemEnglish(p), reason: code.name);
      expect(problemText(vi, p), isNot(contains('{')), reason: code.name);
    }
    final p = ConfigProblem(file: '/c/config', line: 3, severity: ConfigSeverity.error, code: ConfigProblemCode.syntax);
    expect(problemLocation(en, p), 'config, line 3');
    expect(problemLocation(vi, p), 'config, dòng 3');
    expect(
      problemLocation(en, ConfigProblem(file: '/c/config', line: 0, severity: ConfigSeverity.error, code: ConfigProblemCode.unreadable)),
      'config',
    );
  });

  final mac = TargetPlatformVariant.only(TargetPlatform.macOS);

  testWidgets('an error raises an error toast; Show opens the panel (criterion 4)', variant: mac, (tester) async {
    final w = await pumpConfiguredWorkspace(tester, config: 'font-size = to\nkeybind = super+q=new_tab\n');
    expect(find.text('2 problems in the configuration'), findsOneWidget);
    await tester.tap(find.text('Show'));
    await tester.pumpAndSettle();
    expect(find.byType(ConfigProblemsPanel), findsOneWidget);
    expect(find.text('config, line 1'), findsOneWidget);
    expect(find.text('font-size: “to” is not valid (expected 9–28)'), findsOneWidget);
    expect(find.text('⌘Q is reserved by the system'), findsOneWidget);
    // Fixing the file and reloading empties the panel in place.
    w.fs.write(testConfigPaths().shellx, 'font-size = 14\n');
    await tester.tap(find.text('Reload configuration'));
    await tester.pumpAndSettle();
    expect(find.text('No problems in the configuration.'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(ConfigProblemsPanel), findsNothing);
    await disposeWorkspace(tester, w.container);
  });

  testWidgets('notes alone raise no toast; a manual reload says so', variant: mac, (tester) async {
    final w = await pumpConfiguredWorkspace(tester, config: 'keybind = ctrl+c=new_tab\n');
    expect(find.textContaining('in the configuration'), findsNothing);
    await w.container.read(shellxConfigProvider.notifier).load(manual: true);
    await tester.pumpAndSettle();
    expect(find.text('Configuration reloaded'), findsOneWidget);
    await disposeWorkspace(tester, w.container);
  });

  testWidgets('the same problems again raise no second toast; a fix dismisses it', variant: mac, (tester) async {
    final w = await pumpConfiguredWorkspace(tester, config: 'font-size = to\n');
    final notifier = w.container.read(shellxConfigProvider.notifier);
    await tester.tap(find.byTooltip('Close')); // the toast ×
    await tester.pumpAndSettle();
    await notifier.load();
    await tester.pumpAndSettle();
    expect(find.text('1 problem in the configuration'), findsNothing);
    w.fs.write(testConfigPaths().shellx, 'font-size = 20\nfont-size = x\n');
    await notifier.load();
    await tester.pumpAndSettle();
    expect(find.text('1 problem in the configuration'), findsOneWidget);
    w.fs.write(testConfigPaths().shellx, 'font-size = 20\n');
    await notifier.load();
    await tester.pumpAndSettle();
    expect(find.textContaining('in the configuration'), findsNothing);
    await disposeWorkspace(tester, w.container);
  });

  testWidgets('Ghostty: a one-time neutral notice (D4)', variant: mac, (tester) async {
    final w = await pumpConfiguredWorkspace(tester);
    w.fs.write(testConfigPaths().ghostty[1], 'font-family = Fira Code\n');
    await w.container.read(shellxConfigProvider.notifier).load();
    await tester.pumpAndSettle();
    expect(find.textContaining('Ghostty config'), findsOneWidget);
    await disposeWorkspace(tester, w.container);
  });
}
```

(The toast close button's tooltip is A1's — use its real text in `find.byTooltip`.)

Create `apps/desktop/test/tray/tray_config_menu_test.dart` following A7's `tray_cli_menu_test.dart`: build the menu with `configProblemCount: 0` and assert a submenu `TrayKeys.config` labelled "Configuration" right after A7's "Command line" submenu, with items `configOpen` "Open configuration file", `configReload` "Reload configuration", `configShortcuts` "Keyboard shortcuts…", and no `configProblems`; with `configProblemCount: 2` the last item (after a separator) is "⚠ 2 configuration problems…". Then the action handler: `OpenConfigFile` shows the window and calls the (overridden, recording) `ConfigFileOpener` with the ShellX path; `ReloadConfig` makes `shellxConfigProvider` reach generation + 1 with `lastLoad.manual`; `ShowShortcutsFromTray` / `ShowConfigProblemsFromTray` set `configUiRequestProvider` to `(ConfigUiRequest.shortcuts, n)` / `(ConfigUiRequest.problems, n)` and show the window. The submenu is present in the signed-out menu too.

- [ ] **Step 2: Run the tests to see them fail**

Run: `cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/ui/config_problems_ui_test.dart test/tray/tray_config_menu_test.dart`
Expected: FAIL.

- [ ] **Step 3: Strings**

Add to `apps/desktop/lib/l10n/app_en.arb` (placeholders always declared in the order key, value, hint, detail so the generated methods are `(String key, String value, String hint, String detail)` minus the unused ones):

```json
  "configProblemsToast": "{count, plural, =1{1 problem in the configuration} other{{count} problems in the configuration}}",
  "@configProblemsToast": {"description": "UI-A9 §3.1", "placeholders": {"count": {"type": "int"}}},
  "configProblemsShow": "Show",
  "@configProblemsShow": {"description": "UI-A9 §3.1 toast button"},
  "configReloaded": "Configuration reloaded",
  "@configReloaded": {"description": "UI-A9 §3.1"},
  "configGhosttyNotice": "Using fonts and colours from your Ghostty config (turn off with ghostty-config = false)",
  "@configGhosttyNotice": {"description": "A9 D4, shown once"},
  "configProblemsTitle": "Configuration problems",
  "@configProblemsTitle": {"description": "UI-A9 §3.2"},
  "configProblemsNone": "No problems in the configuration.",
  "@configProblemsNone": {"description": "UI-A9 §3.2"},
  "configProblemWhere": "{file}, line {line}",
  "@configProblemWhere": {"description": "UI-A9 §3.2", "placeholders": {"file": {"type": "String"}, "line": {"type": "int"}}},
  "configSeverityError": "Error",
  "@configSeverityError": {"description": "UI-A9 §3.2"},
  "configSeverityWarning": "Warning",
  "@configSeverityWarning": {"description": "UI-A9 §3.2"},
  "configSeverityInfo": "Note",
  "@configSeverityInfo": {"description": "UI-A9 §3.2"},
  "configOpenFile": "Open configuration file",
  "@configOpenFile": {"description": "UI-A9 §3.2"},
  "configReload": "Reload configuration",
  "@configReload": {"description": "UI-A9 §3.2"},
  "configProblemSyntax": "Line has no “=” (expected key = value)",
  "@configProblemSyntax": {"description": "UI-A9 §7.2"},
  "configProblemBadKey": "“{key}” is not a valid key name",
  "@configProblemBadKey": {"description": "UI-A9 §7.2", "placeholders": {"key": {"type": "String"}}},
  "configProblemUnknownKey": "ShellX has no key “{key}”",
  "@configProblemUnknownKey": {"description": "UI-A9 §7.2", "placeholders": {"key": {"type": "String"}}},
  "configProblemBadValue": "{key}: “{value}” is not valid (expected {hint})",
  "@configProblemBadValue": {"description": "UI-A9 §7.2", "placeholders": {"key": {"type": "String"}, "value": {"type": "String"}, "hint": {"type": "String"}}},
  "configProblemOutOfRange": "{key}: {value} is outside {hint}, using {detail}",
  "@configProblemOutOfRange": {"description": "UI-A9 §7.2", "placeholders": {"key": {"type": "String"}, "value": {"type": "String"}, "hint": {"type": "String"}, "detail": {"type": "String"}}},
  "configProblemDuplicate": "{key}: replaces line {detail}",
  "@configProblemDuplicate": {"description": "UI-A9 §7.2", "placeholders": {"key": {"type": "String"}, "detail": {"type": "String"}}},
  "configProblemIncludeMissing": "File “{value}” not found",
  "@configProblemIncludeMissing": {"description": "UI-A9 §7.2", "placeholders": {"value": {"type": "String"}}},
  "configProblemIncludeCycle": "“{value}” is already loaded (config-file loop)",
  "@configProblemIncludeCycle": {"description": "UI-A9 §7.2", "placeholders": {"value": {"type": "String"}}},
  "configProblemIncludeDepth": "config-file is nested more than 4 levels",
  "@configProblemIncludeDepth": {"description": "UI-A9 §7.2"},
  "configProblemUnreadable": "Can't read the file — keeping the previous configuration",
  "@configProblemUnreadable": {"description": "UI-A9 §7.2"},
  "configProblemNotUtf8": "The file isn't UTF-8 — keeping the previous configuration",
  "@configProblemNotUtf8": {"description": "UI-A9 §7.2"},
  "configProblemTooLarge": "The file is larger than 256 KiB — keeping the previous configuration",
  "@configProblemTooLarge": {"description": "UI-A9 §7.2"},
  "configProblemThemeNotFound": "Theme “{value}” not found",
  "@configProblemThemeNotFound": {"description": "UI-A9 §7.2", "placeholders": {"value": {"type": "String"}}},
  "configProblemFontNotFound": "Font “{value}” not found — using JetBrains Mono",
  "@configProblemFontNotFound": {"description": "UI-A9 §7.2", "placeholders": {"value": {"type": "String"}}},
  "configProblemFontNotMonospace": "Font “{value}” isn't monospaced — columns may not line up",
  "@configProblemFontNotMonospace": {"description": "UI-A9 §7.2", "placeholders": {"value": {"type": "String"}}},
  "configProblemLowContrast": "Low text/background contrast ({detail}:1, aim for 4.5:1)",
  "@configProblemLowContrast": {"description": "UI-A9 §7.2", "placeholders": {"detail": {"type": "String"}}},
  "configProblemUnsupportedValue": "{key} = {value} isn't supported (using {hint})",
  "@configProblemUnsupportedValue": {"description": "UI-A9 §7.2", "placeholders": {"key": {"type": "String"}, "value": {"type": "String"}, "hint": {"type": "String"}}},
  "configProblemNotOnThisPlatform": "{key} only has an effect on macOS",
  "@configProblemNotOnThisPlatform": {"description": "UI-A9 §7.2", "placeholders": {"key": {"type": "String"}}},
  "configProblemBadTrigger": "“{value}” is not a valid key combination",
  "@configProblemBadTrigger": {"description": "UI-A9 §7.2", "placeholders": {"value": {"type": "String"}}},
  "configProblemUnknownAction": "There's no action “{value}”",
  "@configProblemUnknownAction": {"description": "UI-A9 §7.2", "placeholders": {"value": {"type": "String"}}},
  "configProblemBadActionParam": "“{value}” is not valid (expected {hint})",
  "@configProblemBadActionParam": {"description": "UI-A9 §7.2", "placeholders": {"value": {"type": "String"}, "hint": {"type": "String"}}},
  "configProblemReservedTrigger": "{value} is reserved by the system",
  "@configProblemReservedTrigger": {"description": "UI-A9 §7.2", "placeholders": {"value": {"type": "String"}}},
  "configProblemPlainKeyTrigger": "{value} is for typing — add Ctrl, Alt or ⌘",
  "@configProblemPlainKeyTrigger": {"description": "UI-A9 §7.2", "placeholders": {"value": {"type": "String"}}},
  "configProblemRegionTrigger": "F6 and Shift+F6 always move between regions",
  "@configProblemRegionTrigger": {"description": "UI-A9 §7.2"},
  "configProblemShellKeyTrigger": "{value} will no longer reach the shell",
  "@configProblemShellKeyTrigger": {"description": "UI-A9 §7.2", "placeholders": {"value": {"type": "String"}}},
  "configProblemOptionKeyTrigger": "{value} will no longer type its Option character",
  "@configProblemOptionKeyTrigger": {"description": "UI-A9 §7.2", "placeholders": {"value": {"type": "String"}}},
  "configProblemAltGrTrigger": "{value} works with the left Alt only; AltGr still types characters",
  "@configProblemAltGrTrigger": {"description": "UI-A9 §7.2", "placeholders": {"value": {"type": "String"}}},
  "configProblemMissionControlTrigger": "Mission Control may take {value}",
  "@configProblemMissionControlTrigger": {"description": "UI-A9 §7.2", "placeholders": {"value": {"type": "String"}}},
  "configProblemUnsupportedPrefix": "The “{value}” prefix isn't supported",
  "@configProblemUnsupportedPrefix": {"description": "UI-A9 §7.2", "placeholders": {"value": {"type": "String"}}},
  "configProblemSequenceTooLong": "Key sequences have at most 2 steps",
  "@configProblemSequenceTooLong": {"description": "UI-A9 §7.2"},
  "configProblemSequencePrefixShadows": "{value} starts a key sequence, so it no longer works on its own",
  "@configProblemSequencePrefixShadows": {"description": "UI-A9 §7.2", "placeholders": {"value": {"type": "String"}}},
  "configProblemUnknownCommand": "There's no command “{value}”",
  "@configProblemUnknownCommand": {"description": "UI-A9 §7.2", "placeholders": {"value": {"type": "String"}}},
  "configProblemCommandLimit": "More than 200 commands — the rest are ignored",
  "@configProblemCommandLimit": {"description": "UI-A9 §7.2"},
  "configProblemInternal": "Unexpected error — keeping the previous configuration",
  "@configProblemInternal": {"description": "UI-A9 §7.2"},
  "trayConfig": "Configuration",
  "@trayConfig": {"description": "UI-A9 §6"},
  "trayConfigOpen": "Open configuration file",
  "@trayConfigOpen": {"description": "UI-A9 §6"},
  "trayConfigReload": "Reload configuration",
  "@trayConfigReload": {"description": "UI-A9 §6"},
  "trayConfigShortcuts": "Keyboard shortcuts…",
  "@trayConfigShortcuts": {"description": "UI-A9 §6"},
  "trayConfigProblems": "{count, plural, =1{⚠ 1 configuration problem…} other{⚠ {count} configuration problems…}}",
  "@trayConfigProblems": {"description": "UI-A9 §6", "placeholders": {"count": {"type": "int"}}},
```

`apps/desktop/lib/l10n/app_vi.arb` — same keys, texts from UI-A9 §7.1/§7.2/§7.4 vi column:

```json
  "configProblemsToast": "{count, plural, other{Cấu hình có {count} vấn đề}}",
  "configProblemsShow": "Xem",
  "configReloaded": "Đã tải lại cấu hình",
  "configGhosttyNotice": "Đang dùng font và màu từ cấu hình Ghostty (tắt bằng ghostty-config = false)",
  "configProblemsTitle": "Vấn đề trong cấu hình",
  "configProblemsNone": "Cấu hình không có vấn đề.",
  "configProblemWhere": "{file}, dòng {line}",
  "configSeverityError": "Lỗi",
  "configSeverityWarning": "Cảnh báo",
  "configSeverityInfo": "Ghi chú",
  "configOpenFile": "Mở file cấu hình",
  "configReload": "Tải lại cấu hình",
  "configProblemSyntax": "Dòng không có dấu “=” (dạng đúng: khoá = giá trị)",
  "configProblemBadKey": "“{key}” không phải tên khoá hợp lệ",
  "configProblemUnknownKey": "ShellX không có khoá “{key}”",
  "configProblemBadValue": "{key}: “{value}” không hợp lệ (cần {hint})",
  "configProblemOutOfRange": "{key}: {value} nằm ngoài {hint}, đã dùng {detail}",
  "configProblemDuplicate": "{key}: thay cho dòng {detail}",
  "configProblemIncludeMissing": "Không tìm thấy file “{value}”",
  "configProblemIncludeCycle": "“{value}” đã được nạp (vòng lặp config-file)",
  "configProblemIncludeDepth": "config-file lồng quá 4 tầng",
  "configProblemUnreadable": "Không đọc được file — đang giữ cấu hình trước",
  "configProblemNotUtf8": "File không phải UTF-8 — đang giữ cấu hình trước",
  "configProblemTooLarge": "File lớn hơn 256 KiB — đang giữ cấu hình trước",
  "configProblemThemeNotFound": "Không tìm thấy chủ đề “{value}”",
  "configProblemFontNotFound": "Không tìm thấy font “{value}” — dùng JetBrains Mono",
  "configProblemFontNotMonospace": "Font “{value}” không đơn cách — cột có thể lệch",
  "configProblemLowContrast": "Chữ và nền tương phản thấp ({detail}:1, nên từ 4,5:1)",
  "configProblemUnsupportedValue": "{key} = {value} chưa được hỗ trợ (dùng {hint})",
  "configProblemNotOnThisPlatform": "{key} chỉ có tác dụng trên macOS",
  "configProblemBadTrigger": "“{value}” không phải tổ hợp phím hợp lệ",
  "configProblemUnknownAction": "Không có action “{value}”",
  "configProblemBadActionParam": "“{value}” không hợp lệ (cần {hint})",
  "configProblemReservedTrigger": "Hệ điều hành giữ {value}",
  "configProblemPlainKeyTrigger": "{value} dùng để gõ chữ — thêm Ctrl, Alt hoặc ⌘",
  "configProblemRegionTrigger": "F6 và Shift+F6 luôn dùng để chuyển vùng",
  "configProblemShellKeyTrigger": "{value} sẽ không còn tới shell",
  "configProblemOptionKeyTrigger": "{value} sẽ không còn gõ ký tự Option",
  "configProblemAltGrTrigger": "{value} chỉ chạy với Alt trái; AltGr vẫn gõ ký tự",
  "configProblemMissionControlTrigger": "Mission Control có thể giữ {value}",
  "configProblemUnsupportedPrefix": "Tiền tố “{value}” không được hỗ trợ",
  "configProblemSequenceTooLong": "Chuỗi phím tối đa 2 bước",
  "configProblemSequencePrefixShadows": "{value} là đầu một chuỗi phím nên không còn chạy một mình",
  "configProblemUnknownCommand": "Không có lệnh “{value}”",
  "configProblemCommandLimit": "Quá 200 lệnh — bỏ phần sau",
  "configProblemInternal": "Lỗi không mong đợi — đang giữ cấu hình trước",
  "trayConfig": "Cấu hình",
  "trayConfigOpen": "Mở file cấu hình",
  "trayConfigReload": "Tải lại cấu hình",
  "trayConfigShortcuts": "Phím tắt…",
  "trayConfigProblems": "{count, plural, other{⚠ {count} vấn đề cấu hình…}}",
```

Run `PATH=~/fvm/versions/3.41.4/bin:$PATH flutter gen-l10n` and `flutter test test/l10n/l10n_test.dart` (A1's key-parity test).

- [ ] **Step 4: Implement**

Create `apps/desktop/lib/src/ui/config/action_labels.dart`:

```dart
import 'package:path/path.dart' as p;

import '../../../l10n/app_localizations.dart';
import '../../config/config_problem.dart';

/// UI-A9 §7.2: the localized message of [problem] (en = the CLI's text).
String problemText(AppLocalizations l10n, ConfigProblem problem) {
  final key = problem.key ?? '';
  final value = problem.value ?? '';
  final hint = problem.hint ?? '';
  final detail = problem.detail ?? '';
  return switch (problem.code) {
    ConfigProblemCode.syntax => l10n.configProblemSyntax,
    ConfigProblemCode.badKey => l10n.configProblemBadKey(key),
    ConfigProblemCode.unknownKey => l10n.configProblemUnknownKey(key),
    ConfigProblemCode.badValue => l10n.configProblemBadValue(key, value, hint),
    ConfigProblemCode.outOfRange =>
      l10n.configProblemOutOfRange(key, value, hint, detail),
    ConfigProblemCode.duplicate => l10n.configProblemDuplicate(key, detail),
    ConfigProblemCode.includeMissing => l10n.configProblemIncludeMissing(value),
    ConfigProblemCode.includeCycle => l10n.configProblemIncludeCycle(value),
    ConfigProblemCode.includeDepth => l10n.configProblemIncludeDepth,
    ConfigProblemCode.unreadable => l10n.configProblemUnreadable,
    ConfigProblemCode.notUtf8 => l10n.configProblemNotUtf8,
    ConfigProblemCode.tooLarge => l10n.configProblemTooLarge,
    ConfigProblemCode.themeNotFound => l10n.configProblemThemeNotFound(value),
    ConfigProblemCode.fontNotFound => l10n.configProblemFontNotFound(value),
    ConfigProblemCode.fontNotMonospace =>
      l10n.configProblemFontNotMonospace(value),
    ConfigProblemCode.lowContrast => l10n.configProblemLowContrast(detail),
    ConfigProblemCode.unsupportedValue =>
      l10n.configProblemUnsupportedValue(key, value, hint),
    ConfigProblemCode.notOnThisPlatform =>
      l10n.configProblemNotOnThisPlatform(key),
    ConfigProblemCode.badTrigger => l10n.configProblemBadTrigger(value),
    ConfigProblemCode.unknownAction => l10n.configProblemUnknownAction(value),
    ConfigProblemCode.badActionParam =>
      l10n.configProblemBadActionParam(value, hint),
    ConfigProblemCode.reservedTrigger => l10n.configProblemReservedTrigger(value),
    ConfigProblemCode.plainKeyTrigger => l10n.configProblemPlainKeyTrigger(value),
    ConfigProblemCode.regionTrigger => l10n.configProblemRegionTrigger,
    ConfigProblemCode.shellKeyTrigger => l10n.configProblemShellKeyTrigger(value),
    ConfigProblemCode.optionKeyTrigger =>
      l10n.configProblemOptionKeyTrigger(value),
    ConfigProblemCode.altGrTrigger => l10n.configProblemAltGrTrigger(value),
    ConfigProblemCode.missionControlTrigger =>
      l10n.configProblemMissionControlTrigger(value),
    ConfigProblemCode.unsupportedPrefix =>
      l10n.configProblemUnsupportedPrefix(value),
    ConfigProblemCode.sequenceTooLong => l10n.configProblemSequenceTooLong,
    ConfigProblemCode.sequencePrefixShadows =>
      l10n.configProblemSequencePrefixShadows(value),
    ConfigProblemCode.unknownCommand => l10n.configProblemUnknownCommand(value),
    ConfigProblemCode.commandLimit => l10n.configProblemCommandLimit,
    ConfigProblemCode.internal => l10n.configProblemInternal,
  };
}

/// "config, line 3" — the file's base name; the whole file: the name only.
String problemLocation(AppLocalizations l10n, ConfigProblem problem) {
  final name = p.basename(problem.file.replaceAll(r'\', '/'));
  return problem.line == 0 ? name : l10n.configProblemWhere(name, problem.line);
}

String severityText(AppLocalizations l10n, ConfigSeverity s) => switch (s) {
  ConfigSeverity.error => l10n.configSeverityError,
  ConfigSeverity.warning => l10n.configSeverityWarning,
  ConfigSeverity.info => l10n.configSeverityInfo,
};
```

Create `apps/desktop/lib/src/ui/config/config_ui_request.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum ConfigUiRequest { palette, problems, shortcuts }

/// The tray (and the CLI, later) asks the window to open an A9 surface;
/// the counter makes two equal requests distinct.
final configUiRequestProvider =
    NotifierProvider<ConfigUiRequests, (ConfigUiRequest, int)?>(
      ConfigUiRequests.new,
    );

class ConfigUiRequests extends Notifier<(ConfigUiRequest, int)?> {
  int _n = 0;

  @override
  (ConfigUiRequest, int)? build() => null;

  void request(ConfigUiRequest kind) => state = (kind, ++_n);
}
```

Create `apps/desktop/lib/src/ui/config/config_problems_panel.dart`:

```dart
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../../config/config_controller.dart';
import '../../config/config_problem.dart';
import '../theme/shellx_desktop_theme.dart';
import 'action_labels.dart';

int _rank(ConfigSeverity s) => switch (s) {
  ConfigSeverity.error => 0,
  ConfigSeverity.warning => 1,
  ConfigSeverity.info => 2,
};

/// UI-A9 §3.2. Lives in the workspace overlay slot; reads the problems
/// live, so a reload updates it in place.
class ConfigProblemsPanel extends ConsumerWidget {
  const ConfigProblemsPanel({
    super.key,
    required this.onClose,
    required this.onOpenFile,
    required this.onReload,
  });

  final VoidCallback onClose;
  final VoidCallback onOpenFile;
  final VoidCallback onReload;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(shellxConfigProvider);
    final paths = ref.watch(configPathsProvider);
    final problems = [...state.problems]
      ..sort((a, b) {
        final s = _rank(a.severity).compareTo(_rank(b.severity));
        if (s != 0) return s;
        final f = a.file.compareTo(b.file);
        return f != 0 ? f : a.line.compareTo(b.line);
      });
    String home(String path) => path.startsWith(paths.home)
        ? '~${path.substring(paths.home.length)}'
        : path;
    final ghostty = [
      for (final f in paths.ghostty)
        if (state.ghosttyUsed && state.files.contains(f)) home(f),
    ];
    final size = MediaQuery.sizeOf(context);
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): onClose,
      },
      child: FocusScope(
        child: Semantics(
          scopesRoute: true,
          namesRoute: true,
          explicitChildNodes: true,
          label: l10n.configProblemsTitle,
          child: Container(
            width: math.min(ShellxSizes.problemsWidth, size.width - 48),
            constraints: BoxConstraints(
              maxHeight: math.min(ShellxSizes.problemsMaxHeight, size.height - 96),
            ),
            decoration: BoxDecoration(
              color: ShellxDesktopColors.surface,
              borderRadius: BorderRadius.circular(ShellxRadius.r8),
              border: Border.all(color: ShellxDesktopColors.border),
              boxShadow: ShellxShadows.e1,
            ),
            child: Material(
              type: MaterialType.transparency,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            l10n.configProblemsTitle,
                            style: ShellxText.bodyStrong.copyWith(
                              color: ShellxDesktopColors.textPrimary,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                          icon: const Icon(Icons.close, size: 16),
                          onPressed: onClose,
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: Text(
                      [
                        home(paths.shellx),
                        if (ghostty.isNotEmpty) 'Ghostty: ${ghostty.join(', ')}',
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: ShellxText.caption.copyWith(
                        color: ShellxDesktopColors.textSecondary,
                      ),
                    ),
                  ),
                  const Divider(height: 1, color: ShellxDesktopColors.line),
                  Flexible(
                    child: problems.isEmpty
                        ? Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(
                              l10n.configProblemsNone,
                              textAlign: TextAlign.center,
                              style: ShellxText.body.copyWith(
                                color: ShellxDesktopColors.textSecondary,
                              ),
                            ),
                          )
                        : ListView(
                            shrinkWrap: true,
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            children: [
                              for (final p in problems) _ProblemRow(problem: p),
                            ],
                          ),
                  ),
                  const Divider(height: 1, color: ShellxDesktopColors.line),
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        OutlinedButton(
                          onPressed: onReload,
                          child: Text(l10n.configReload),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          autofocus: true,
                          onPressed: onOpenFile,
                          child: Text(l10n.configOpenFile),
                        ),
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

class _ProblemRow extends StatelessWidget {
  const _ProblemRow({required this.problem});
  final ConfigProblem problem;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final (icon, color) = switch (problem.severity) {
      ConfigSeverity.error => (Icons.error_outline, ShellxDesktopColors.err),
      ConfigSeverity.warning => (Icons.warning_amber, ShellxDesktopColors.warn),
      ConfigSeverity.info => (Icons.info_outline, ShellxDesktopColors.textSecondary),
    };
    final severity = severityText(l10n, problem.severity);
    final where = problemLocation(l10n, problem);
    final message = problemText(l10n, problem);
    return MergeSemantics(
      child: Semantics(
        label: '$severity, $where, $message',
        excludeSemantics: true,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 96,
                child: Row(
                  children: [
                    Icon(icon, size: 14, color: color),
                    const SizedBox(width: 6),
                    Text(severity, style: ShellxText.small.copyWith(color: color)),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      where,
                      style: ShellxText.small.copyWith(
                        color: ShellxDesktopColors.textSecondary,
                      ),
                    ),
                    Text(
                      message,
                      style: ShellxText.body.copyWith(
                        color: ShellxDesktopColors.textPrimary,
                      ),
                    ),
                  ],
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

Add to `ShellxSizes` (UI-A9 §1.2): `paletteWidth = 560`, `paletteTop = 56`, `paletteMaxHeight = 420`, `paletteRow = 36`, `paletteField = 40`, `problemsWidth = 600`, `problemsMaxHeight = 480`, `problemRow = 52`, `shortcutsWidth = 720`, `shortcutsHeight = 600`, `shortcutsRow = 40`, `keycapHeight = 20`, `keycapGap = 4`.

Notices in `terminal_tabs.dart`:

```dart
/// A9 D36: errors → error toast; warnings only → neutral.
final class ConfigProblemsNotice extends TabNotice {
  const ConfigProblemsNotice(this.count, {required this.hasErrors});
  final int count;
  final bool hasErrors;
}

/// A9 D9: a reload the user asked for found nothing wrong (neutral).
final class ConfigReloadedNotice extends TabNotice {
  const ConfigReloadedNotice();
}

/// A9 D4: the first time Ghostty's fonts/colours are used (neutral).
final class ConfigGhosttyNotice extends TabNotice {
  const ConfigGhosttyNotice();
}
```

`terminal_overlays.dart` `NoticeToast`: new optional `final VoidCallback? onAction;`; `_neutral` adds `ConfigReloadedNotice`, `ConfigGhosttyNotice`, and `ConfigProblemsNotice(hasErrors: false)`; `_text` adds `ConfigProblemsNotice(:final count) => l10n.configProblemsToast(count)`, `ConfigReloadedNotice() => l10n.configReloaded`, `ConfigGhosttyNotice() => l10n.configGhosttyNotice`. When `widget.notice is ConfigProblemsNotice && widget.onAction != null`, put a `TextButton(onPressed: () { widget.onAction!(); _close(); }, child: Text(l10n.configProblemsShow))` before the close button (UI-A9 §3.1: neutral → `accent` w600; error → `noticeText` underlined; hit 28, padding 0/8). Where `TerminalPane` builds the `NoticeToast`, pass `onAction: widget.onShowConfigProblems` (new `VoidCallback? onShowConfigProblems` on `TerminalPane`).

Workspace page:

```dart
enum A9Overlay { palette, problems, shortcuts }

  A9Overlay? overlay;
  FocusNode? _beforeOverlay;

  void openOverlay(A9Overlay next) {
    closePanel(restoreFocus: false);
    ref.read(keySequenceProvider.notifier).cancel();
    _beforeOverlay ??= FocusManager.instance.primaryFocus;
    setState(() => overlay = next);
  }

  void closeOverlay({bool restoreFocus = true}) {
    if (overlay == null) return;
    final before = _beforeOverlay;
    _beforeOverlay = null;
    setState(() => overlay = null);
    if (!restoreFocus) return;
    if (before != null && before.context != null && before.canRequestFocus) {
      before.requestFocus();
      FocusManager.instance.applyFocusChangesIfNeeded();
    } else {
      focusTerminal();
    }
  }
```

`closePanel()` also calls `closeOverlay(restoreFocus: restoreFocus)` first, so every window shortcut that closes the A4 panel closes an A9 overlay too (UI-A9 §2.2). Replace the disabled `ShowConfigProblemsIntent` action with `run<ShowConfigProblemsIntent>((_) => openOverlay(A9Overlay.problems))` (always enabled: the palette lists it only when there are problems, D33). In the `Stack`, after the notifications slot:

```dart
              if (overlay == A9Overlay.problems)
                Positioned(
                  key: const ValueKey('a9.problems'),
                  left: ShellxSizes.sidebarWidth + 1,
                  right: 0,
                  top: (isMacDesktop ? ShellxSizes.paneHeaderMac : 0) + ShellxSizes.paletteTop,
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: ConfigProblemsPanel(
                      onClose: closeOverlay,
                      onOpenFile: () {
                        closeOverlay();
                        unawaited(openShellxConfig(ref.read));
                      },
                      onReload: () => unawaited(
                        ref.read(shellxConfigProvider.notifier).load(manual: true),
                      ),
                    ),
                  ),
                ),
```

Toasts: in `initState`, as a manual listener with `fireImmediately: true` — the startup load (and a test's `loadConfig`) completes before the first frame, so the first call shows its problems; a listener registered in `build` would re-fire on every rebuild:

```dart
    // A9 D36: toasts follow the loads.
    ref.listenManual<ConfigState>(shellxConfigProvider, (previous, next) {
      final load = next.lastLoad;
      if (load == null || identical(previous?.lastLoad, load)) return;
      final tabs = ref.read(terminalTabsProvider.notifier);
      final count = next.visibleProblemCount;
      if (count > 0 && (load.problemsChanged || load.manual)) {
        tabs.showNotice(ConfigProblemsNotice(count, hasErrors: next.errorCount > 0));
      } else if (count == 0 &&
          ref.read(terminalTabsProvider).notice is ConfigProblemsNotice) {
        tabs.dismissNotice();
        if (load.manual) tabs.showNotice(const ConfigReloadedNotice());
      } else if (load.manual && count == 0) {
        tabs.showNotice(const ConfigReloadedNotice());
      } else if (load.firstGhostty) {
        tabs.showNotice(const ConfigGhosttyNotice());
      }
    }, fireImmediately: true);
```

The UI requests (tray), in `build` next to the other listeners:

```dart
    ref.listen(configUiRequestProvider, (_, next) {
      if (next == null) return;
      openOverlay(switch (next.$1) {
        ConfigUiRequest.palette => A9Overlay.palette,
        ConfigUiRequest.problems => A9Overlay.problems,
        ConfigUiRequest.shortcuts => A9Overlay.shortcuts,
      });
    });
```

Pass `onShowConfigProblems: () => openOverlay(A9Overlay.problems)` to `TerminalPane`. Wrap `_body()`'s `ExcludeSemantics(excluding: panelOpen, …)` as `excluding: panelOpen || overlay != null`.

Tray: in `tray_action.dart` add `final class OpenConfigFile extends TrayAction { const OpenConfigFile(); }`, `ReloadConfig`, `ShowShortcutsFromTray`, `ShowConfigProblemsFromTray`. In `tray_menu.dart` add the keys to `TrayKeys` (`config = 'config'`, `configOpen = 'config.open'`, `configReload = 'config.reload'`, `configShortcuts = 'config.shortcuts'`, `configProblems = 'config.problems'`) and the submenu, placed right after A7's "Dòng lệnh" submenu in **both** menus:

```dart
  MenuItem config() => sub(TrayKeys.config, l10n.trayConfig, [
    item(TrayKeys.configOpen, l10n.trayConfigOpen),
    item(TrayKeys.configReload, l10n.trayConfigReload),
    item(TrayKeys.configShortcuts, l10n.trayConfigShortcuts),
    if (state.configProblemCount > 0) ...[
      sep(),
      item(TrayKeys.configProblems, l10n.trayConfigProblems(state.configProblemCount)),
    ],
  ]);
```

Map the keys to the actions where A7 mapped its keys; `tray_presenter.dart` feeds `configProblemCount` from `shellxConfigProvider.select((s) => s.visibleProblemCount)` the way A7 feeds `cliControlEnabled` (add the field to the presenter's view state with default 0). In `tray_actions.dart`, each action first does what `OpenTerminalWindow` does (show + raise), then: `OpenConfigFile` → `openShellxConfig(ref.read)`; `ReloadConfig` → `ref.read(shellxConfigProvider.notifier).load(manual: true)`; the two others → `ref.read(configUiRequestProvider.notifier).request(ConfigUiRequest.shortcuts / .problems)`.

- [ ] **Step 5: Run the tests**

Run: `cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/ui/config_problems_ui_test.dart test/tray/ test/l10n/ && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test`
Expected: PASS. Format + analyze clean.

- [ ] **Step 6: Commit**

```bash
git add apps/desktop/lib/src/ui/config apps/desktop/lib/src/terminal/terminal_tabs.dart apps/desktop/lib/src/ui/terminal/terminal_overlays.dart apps/desktop/lib/src/ui/terminal/terminal_pane.dart apps/desktop/lib/src/ui/terminal/terminal_workspace_page.dart apps/desktop/lib/src/ui/theme/shellx_desktop_theme.dart apps/desktop/lib/src/tray apps/desktop/lib/l10n apps/desktop/test/ui/config_problems_ui_test.dart apps/desktop/test/tray/tray_config_menu_test.dart
git commit -m "feat(desktop): configuration problems you can see — toast with Show, problems panel that updates in place, reload and Ghostty notices, tray Configuration submenu, vi/en messages equal to the CLI's (A9 D4, D8, D9, D36, D45)"
```

---
### Task 11: Command palette — every action, your commands and snippets, config entries (D33, D35, D44)

**Files:**
- Create: `apps/desktop/lib/src/ui/config/command_palette.dart`
- Modify: `apps/desktop/lib/src/ui/config/action_labels.dart` (`actionLabel`), `apps/desktop/lib/src/ui/terminal/terminal_workspace_page.dart`, `apps/desktop/lib/l10n/app_{en,vi}.arb`
- Test: `apps/desktop/test/config/palette_match_test.dart`, `apps/desktop/test/ui/command_palette_test.dart`

**Interfaces:**
- Consumes: Tasks 4, 8, 10 (`kActionSpecs`, `intentForAction`, `KeyBindings.labelOf`, `_invoke`, `openOverlay`/`closeOverlay`).
- Produces:
  - `String foldForSearch(String s)`; `int? matchScore(String query, String text)`.
  - `enum PaletteKind { action, command, snippet, config }`; `final class PaletteEntry { id, title, subtitle, kind, shortcut, intent }`; `List<PaletteEntry> paletteEntries({required AppLocalizations l10n, required ConfigState config, required bool Function(Intent) enabled})`; `List<PaletteEntry> filterPalette(List<PaletteEntry> entries, String query, List<String> recent)`.
  - `class CommandPalette extends StatefulWidget { CommandPalette({required List<PaletteEntry> entries, required List<String> recent, required void Function(PaletteEntry) onRun, required VoidCallback onClose}) }`.
  - `String actionLabel(AppLocalizations l10n, KeyAction a)`.
  - ARB: UI-A9 §7.3 (`palette*`, `action*`).

- [ ] **Step 1: Write the failing tests**

Create `apps/desktop/test/config/palette_match_test.dart`:

```dart
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/ui/config/command_palette.dart';

PaletteEntry e(String id, String title, {String? subtitle}) => PaletteEntry(
  id: id,
  title: title,
  subtitle: subtitle,
  kind: PaletteKind.action,
  shortcut: null,
  intent: const DoNothingIntent(),
);

void main() {
  test('folding: case and Vietnamese marks (D33)', () {
    expect(foldForSearch('Chia xuống dưới'), 'chia xuong duoi');
    expect(foldForSearch('Đóng cả TAB'), 'dong ca tab');
    expect(foldForSearch('Tải lại cấu hình'), 'tai lai cau hinh');
    // Decomposed input (combining marks) folds the same way.
    expect(foldForSearch('xuống'), 'xuong');
  });

  test('prefix > word start > inside > subsequence; no match is null', () {
    final prefix = matchScore('chia', 'Chia sang phải')!;
    final word = matchScore('phai', 'Chia sang phải')!;
    final inside = matchScore('ang', 'Chia sang phải')!;
    final sub = matchScore('csp', 'Chia sang phải')!;
    expect(prefix, greaterThan(word));
    expect(word, greaterThan(inside));
    expect(inside, greaterThan(sub));
    expect(matchScore('zz', 'Chia sang phải'), isNull);
    expect(matchScore('', 'anything'), 0);
  });

  test('empty query: recent first, then the original order', () {
    final entries = [e('a', 'A'), e('b', 'B'), e('c', 'C')];
    expect(filterPalette(entries, '', ['c']).map((x) => x.id), ['c', 'a', 'b']);
  });

  test('a query ranks by score, then recency; commands match their text too', () {
    final entries = [
      e('split', 'Chia sang phải'),
      e('down', 'Chia xuống dưới'),
      e('lint', 'Lint', subtitle: 'npm run lint'),
    ];
    expect(filterPalette(entries, 'chia xuong', const []).first.id, 'down');
    expect(filterPalette(entries, 'chia', ['down']).map((x) => x.id), ['down', 'split']);
    expect(filterPalette(entries, 'npm', const []).single.id, 'lint');
  });
}
```

Create `apps/desktop/test/ui/command_palette_test.dart`:

```dart
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/terminal/terminal_tabs.dart';
import 'package:shellx_desktop/src/ui/config/command_palette.dart';

import '../support/config_workspace.dart';

const cmd = LogicalKeyboardKey.metaLeft;
const shift = LogicalKeyboardKey.shiftLeft;

Future<void> openPalette(WidgetTester tester) async {
  await tester.sendKeyDownEvent(cmd);
  await tester.sendKeyDownEvent(shift);
  await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
  await tester.sendKeyUpEvent(shift);
  await tester.sendKeyUpEvent(cmd);
  await tester.pumpAndSettle();
}

void main() {
  final mac = TargetPlatformVariant.only(TargetPlatform.macOS);

  testWidgets('⌘⇧P, type, Enter runs; the keyboard returns to the terminal (criterion 7)', variant: mac, (tester) async {
    final w = await pumpConfiguredWorkspace(tester);
    await openPalette(tester);
    expect(find.byType(CommandPalette), findsOneWidget);
    expect(find.bySemanticsLabel('Search commands'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'split d');
    await tester.pumpAndSettle();
    expect(
      tester.widget<Text>(find.descendant(of: find.byKey(const ValueKey('palette.row.0')), matching: find.byType(Text)).first).data,
      'Split down',
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.byType(CommandPalette), findsNothing);
    expect(w.container.read(terminalTabsProvider).selected!.paneCount, 2);
    await disposeWorkspace(tester, w.container);
  });

  testWidgets('hidden when not applicable; commands run in the focused pane', variant: mac, (tester) async {
    final w = await pumpConfiguredWorkspace(tester, config: 'command = Lint = npm run lint\n');
    await openPalette(tester);
    expect(find.text('Zoom or unzoom pane'), findsNothing); // one pane
    await tester.enterText(find.byType(TextField), 'lint');
    await tester.pumpAndSettle();
    expect(find.text('Your command'), findsOneWidget);
    expect(find.text('npm run lint'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    final id = w.container.read(terminalTabsProvider).selected!.focused.id;
    expect(w.local.views[id]!.writes.join(), 'npm run lint\r');
    await disposeWorkspace(tester, w.container);
  });

  testWidgets('Esc clears, then closes; ↓ wraps; ⌘⇧P closes too', variant: mac, (tester) async {
    final w = await pumpConfiguredWorkspace(tester);
    await openPalette(tester);
    await tester.enterText(find.byType(TextField), 'tab');
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, isEmpty);
    expect(find.byType(CommandPalette), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp); // wraps to the last
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(CommandPalette), findsNothing);
    await openPalette(tester);
    await openPalette(tester);
    expect(find.byType(CommandPalette), findsNothing);
    await disposeWorkspace(tester, w.container);
  });

  testWidgets('a problem adds "Show configuration problems"', variant: mac, (tester) async {
    final w = await pumpConfiguredWorkspace(tester, config: 'font-size = x\n');
    await openPalette(tester);
    expect(find.text('Show configuration problems'), findsOneWidget);
    await disposeWorkspace(tester, w.container);
  });
}
```

- [ ] **Step 2: Run the tests to see them fail**

Run: `cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/config/palette_match_test.dart test/ui/command_palette_test.dart`
Expected: FAIL.

- [ ] **Step 3: Strings**

`app_en.arb` (UI-A9 §7.3):

```json
  "paletteTitle": "Command palette",
  "@paletteTitle": {"description": "UI-A9 §2"},
  "paletteSearchLabel": "Search commands",
  "@paletteSearchLabel": {"description": "UI-A9 §2"},
  "paletteSearchHint": "Type a command…",
  "@paletteSearchHint": {"description": "UI-A9 §2"},
  "paletteNoResults": "No matching commands",
  "@paletteNoResults": {"description": "UI-A9 §2"},
  "paletteResultCount": "{count, plural, =1{1 command} other{{count} commands}}",
  "@paletteResultCount": {"description": "UI-A9 §8", "placeholders": {"count": {"type": "int"}}},
  "paletteKindUserCommand": "Your command",
  "@paletteKindUserCommand": {"description": "UI-A9 §2"},
  "paletteKindSnippet": "Snippet",
  "@paletteKindSnippet": {"description": "UI-A9 §2"},
  "paletteKindConfig": "Configuration",
  "@paletteKindConfig": {"description": "UI-A9 §2"},
  "actionNewTab": "New tab",
  "@actionNewTab": {"description": "UI-A9 §7.3"},
  "actionCloseSurface": "Close pane or tab",
  "@actionCloseSurface": {"description": "UI-A9 §7.3"},
  "actionCloseTab": "Close whole tab",
  "@actionCloseTab": {"description": "UI-A9 §7.3"},
  "actionNewWorkspace": "New workspace",
  "@actionNewWorkspace": {"description": "UI-A9 §7.3"},
  "actionToggleNotifications": "Notifications",
  "@actionToggleNotifications": {"description": "UI-A9 §7.3"},
  "actionJumpToUnread": "Jump to unread",
  "@actionJumpToUnread": {"description": "UI-A9 §7.3"},
  "actionCopy": "Copy",
  "@actionCopy": {"description": "UI-A9 §7.3"},
  "actionPaste": "Paste",
  "@actionPaste": {"description": "UI-A9 §7.3"},
  "actionSelectAll": "Select all",
  "@actionSelectAll": {"description": "UI-A9 §7.3"},
  "actionGotoTab": "Go to tab {n}",
  "@actionGotoTab": {"description": "UI-A9 §7.3", "placeholders": {"n": {"type": "String"}}},
  "actionNextTab": "Next tab",
  "@actionNextTab": {"description": "UI-A9 §7.3"},
  "actionPreviousTab": "Previous tab",
  "@actionPreviousTab": {"description": "UI-A9 §7.3"},
  "actionSplitRight": "Split right",
  "@actionSplitRight": {"description": "UI-A9 §7.3"},
  "actionSplitDown": "Split down",
  "@actionSplitDown": {"description": "UI-A9 §7.3"},
  "actionFocusPane": "{direction, select, left{Focus pane on the left} right{Focus pane on the right} up{Focus pane above} other{Focus pane below}}",
  "@actionFocusPane": {"description": "UI-A9 §7.3", "placeholders": {"direction": {"type": "String"}}},
  "actionResizePane": "{direction, select, left{Move divider left} right{Move divider right} up{Move divider up} other{Move divider down}}",
  "@actionResizePane": {"description": "UI-A9 §7.3", "placeholders": {"direction": {"type": "String"}}},
  "actionToggleZoom": "Zoom or unzoom pane",
  "@actionToggleZoom": {"description": "UI-A9 §7.3"},
  "actionEqualize": "Equalize panes",
  "@actionEqualize": {"description": "UI-A9 §7.3"},
  "actionFontBigger": "Bigger text",
  "@actionFontBigger": {"description": "UI-A9 §7.3"},
  "actionFontSmaller": "Smaller text",
  "@actionFontSmaller": {"description": "UI-A9 §7.3"},
  "actionFontReset": "Default text size",
  "@actionFontReset": {"description": "UI-A9 §7.3"},
  "actionNextRegion": "Next region",
  "@actionNextRegion": {"description": "UI-A9 §7.3"},
  "actionPreviousRegion": "Previous region",
  "@actionPreviousRegion": {"description": "UI-A9 §7.3"},
  "actionOpenBrowser": "Open browser pane",
  "@actionOpenBrowser": {"description": "UI-A9 §7.3"},
  "actionBrowserFocusAddress": "Go to address bar",
  "@actionBrowserFocusAddress": {"description": "UI-A9 §7.3"},
  "actionBrowserReload": "Reload page",
  "@actionBrowserReload": {"description": "UI-A9 §7.3"},
  "actionBrowserBack": "Back",
  "@actionBrowserBack": {"description": "UI-A9 §7.3"},
  "actionBrowserForward": "Forward",
  "@actionBrowserForward": {"description": "UI-A9 §7.3"},
  "actionBrowserStop": "Stop loading",
  "@actionBrowserStop": {"description": "UI-A9 §7.3"},
  "actionReloadConfig": "Reload configuration",
  "@actionReloadConfig": {"description": "UI-A9 §7.3"},
  "actionOpenConfig": "Open configuration file",
  "@actionOpenConfig": {"description": "UI-A9 §7.3"},
  "actionCommandPalette": "Command palette",
  "@actionCommandPalette": {"description": "UI-A9 §7.3"},
  "actionShowShortcuts": "Keyboard shortcuts…",
  "@actionShowShortcuts": {"description": "UI-A9 §7.3"},
  "actionShowConfigProblems": "Show configuration problems",
  "@actionShowConfigProblems": {"description": "UI-A9 §7.3"},
  "actionRunCommand": "Run “{name}”",
  "@actionRunCommand": {"description": "UI-A9 §7.3", "placeholders": {"name": {"type": "String"}}},
  "actionSendText": "Send text to the terminal",
  "@actionSendText": {"description": "UI-A9 §7.3"},
  "actionIgnore": "Ignore key",
  "@actionIgnore": {"description": "UI-A9 §7.3"},
```

`app_vi.arb`:

```json
  "paletteTitle": "Bảng lệnh",
  "paletteSearchLabel": "Tìm lệnh",
  "paletteSearchHint": "Gõ tên lệnh…",
  "paletteNoResults": "Không có lệnh nào khớp",
  "paletteResultCount": "{count, plural, other{{count} lệnh}}",
  "paletteKindUserCommand": "Lệnh của bạn",
  "paletteKindSnippet": "Đoạn chữ",
  "paletteKindConfig": "Cấu hình",
  "actionNewTab": "Tab mới",
  "actionCloseSurface": "Đóng pane hoặc tab",
  "actionCloseTab": "Đóng cả tab",
  "actionNewWorkspace": "Workspace mới",
  "actionToggleNotifications": "Bảng thông báo",
  "actionJumpToUnread": "Tới thông báo chưa đọc",
  "actionCopy": "Sao chép",
  "actionPaste": "Dán",
  "actionSelectAll": "Chọn tất cả",
  "actionGotoTab": "Tới tab {n}",
  "actionNextTab": "Tab sau",
  "actionPreviousTab": "Tab trước",
  "actionSplitRight": "Chia sang phải",
  "actionSplitDown": "Chia xuống dưới",
  "actionFocusPane": "{direction, select, left{Sang pane bên trái} right{Sang pane bên phải} up{Lên pane trên} other{Xuống pane dưới}}",
  "actionResizePane": "{direction, select, left{Dời đường chia sang trái} right{Dời đường chia sang phải} up{Dời đường chia lên} other{Dời đường chia xuống}}",
  "actionToggleZoom": "Phóng to / bỏ phóng to pane",
  "actionEqualize": "Cân bằng pane",
  "actionFontBigger": "Chữ to hơn",
  "actionFontSmaller": "Chữ nhỏ hơn",
  "actionFontReset": "Cỡ chữ mặc định",
  "actionNextRegion": "Vùng tiếp theo",
  "actionPreviousRegion": "Vùng trước",
  "actionOpenBrowser": "Mở pane trình duyệt",
  "actionBrowserFocusAddress": "Tới ô địa chỉ",
  "actionBrowserReload": "Tải lại trang",
  "actionBrowserBack": "Trang trước",
  "actionBrowserForward": "Trang sau",
  "actionBrowserStop": "Dừng tải",
  "actionReloadConfig": "Tải lại cấu hình",
  "actionOpenConfig": "Mở file cấu hình",
  "actionCommandPalette": "Bảng lệnh",
  "actionShowShortcuts": "Phím tắt…",
  "actionShowConfigProblems": "Xem vấn đề cấu hình",
  "actionRunCommand": "Chạy “{name}”",
  "actionSendText": "Gửi chữ vào terminal",
  "actionIgnore": "Bỏ qua phím",
```

`flutter gen-l10n`.

- [ ] **Step 4: Implement**

Append to `apps/desktop/lib/src/ui/config/action_labels.dart` (import `../../config/keybind_actions.dart`):

```dart
/// UI-A9 §7.3: the palette / shortcut-sheet name of an action.
String actionLabel(AppLocalizations l10n, KeyAction a) => switch (a.name) {
  'new_tab' => l10n.actionNewTab,
  'close_surface' => l10n.actionCloseSurface,
  'close_tab' => l10n.actionCloseTab,
  'new_workspace' => l10n.actionNewWorkspace,
  'toggle_notifications' => l10n.actionToggleNotifications,
  'jump_to_unread' => l10n.actionJumpToUnread,
  'copy_to_clipboard' => l10n.actionCopy,
  'paste_from_clipboard' => l10n.actionPaste,
  'select_all' => l10n.actionSelectAll,
  'goto_tab' => l10n.actionGotoTab(a.param ?? ''),
  'next_tab' => l10n.actionNextTab,
  'previous_tab' => l10n.actionPreviousTab,
  'new_split' => a.param == 'down' ? l10n.actionSplitDown : l10n.actionSplitRight,
  'goto_split' => l10n.actionFocusPane(a.param ?? 'down'),
  'resize_split' => l10n.actionResizePane(a.param ?? 'down'),
  'toggle_split_zoom' => l10n.actionToggleZoom,
  'equalize_splits' => l10n.actionEqualize,
  'increase_font_size' => l10n.actionFontBigger,
  'decrease_font_size' => l10n.actionFontSmaller,
  'reset_font_size' => l10n.actionFontReset,
  'next_region' => l10n.actionNextRegion,
  'previous_region' => l10n.actionPreviousRegion,
  'open_browser' => l10n.actionOpenBrowser,
  'browser_focus_address' => l10n.actionBrowserFocusAddress,
  'browser_reload' => l10n.actionBrowserReload,
  'browser_back' => l10n.actionBrowserBack,
  'browser_forward' => l10n.actionBrowserForward,
  'browser_stop' => l10n.actionBrowserStop,
  'reload_config' => l10n.actionReloadConfig,
  'open_config' => l10n.actionOpenConfig,
  'toggle_command_palette' => l10n.actionCommandPalette,
  'show_shortcuts' => l10n.actionShowShortcuts,
  'show_config_problems' => l10n.actionShowConfigProblems,
  'run_command' => l10n.actionRunCommand(a.param ?? ''),
  'text' || 'csi' || 'esc' => l10n.actionSendText,
  'ignore' => l10n.actionIgnore,
  _ => a.text,
};

/// The parameter values a row/palette entry is shown for.
List<String?> actionVariants(ActionSpec spec) => switch (spec.name) {
  'goto_tab' => [for (var i = 1; i <= 9; i++) '$i'],
  'new_split' => ['right', 'down'],
  'goto_split' || 'resize_split' => ['left', 'right', 'up', 'down'],
  'increase_font_size' || 'decrease_font_size' => ['1'],
  _ => [null],
};
```

Create `apps/desktop/lib/src/ui/config/command_palette.dart`:

```dart
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

import '../../../l10n/app_localizations.dart';
import '../../config/config_controller.dart';
import '../../config/keybind_actions.dart';
import '../terminal/terminal_intents.dart';
import '../theme/shellx_desktop_theme.dart';
import 'action_labels.dart';

final Map<String, String> _fold = {
  for (final (chars, base) in const [
    ('àáạảãâầấậẩẫăằắặẳẵ', 'a'),
    ('èéẹẻẽêềếệểễ', 'e'),
    ('ìíịỉĩ', 'i'),
    ('òóọỏõôồốộổỗơờớợởỡ', 'o'),
    ('ùúụủũưừứựửữ', 'u'),
    ('ỳýỵỷỹ', 'y'),
    ('đ', 'd'),
  ])
    for (final c in chars.split('')) c: base,
};

/// D33: lower case, Vietnamese marks removed (precomposed or combining).
String foldForSearch(String s) {
  final out = StringBuffer();
  for (final rune in s.toLowerCase().runes) {
    if (rune >= 0x300 && rune <= 0x36F) continue; // combining marks
    final c = String.fromCharCode(rune);
    out.write(_fold[c] ?? c);
  }
  return out.toString();
}

/// Higher is better; null = no match. Prefix > word start > inside >
/// subsequence (fewer gaps first).
int? matchScore(String query, String text) {
  final q = foldForSearch(query.trim());
  if (q.isEmpty) return 0;
  final t = foldForSearch(text);
  if (t.startsWith(q)) return 4000 - t.length;
  final at = t.indexOf(q);
  if (at > 0 && t[at - 1] == ' ') return 3000 - at;
  if (at >= 0) return 2000 - at;
  var from = 0;
  var last = -1;
  var gaps = 0;
  for (final ch in q.split('')) {
    if (ch == ' ') continue;
    final found = t.indexOf(ch, from);
    if (found < 0) return null;
    if (last >= 0) gaps += found - last - 1;
    last = found;
    from = found + 1;
  }
  return 1000 - gaps;
}

enum PaletteKind { action, command, snippet, config }

@immutable
final class PaletteEntry {
  const PaletteEntry({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.kind,
    required this.shortcut,
    required this.intent,
  });

  final String id;
  final String title;
  final String? subtitle;
  final PaletteKind kind;
  final String? shortcut;
  final Intent intent;
}

/// D33: every applicable action (not `goto_tab`, `text`, `csi`, `esc`,
/// `ignore`, `run_command` — those are bindings), then your commands and
/// snippets. [enabled] is the window's own check (inapplicable → hidden).
List<PaletteEntry> paletteEntries({
  required AppLocalizations l10n,
  required ConfigState config,
  required bool Function(Intent intent) enabled,
}) {
  final entries = <PaletteEntry>[];
  for (final spec in kActionSpecs.values) {
    if (!spec.inPalette) continue;
    if (spec.scope != KeyScope.window) continue; // browser keys act on a page
    for (final param in actionVariants(spec)) {
      final action = KeyAction(spec.name, param);
      final intent = spec.name == 'select_all'
          ? const SelectAllIntent(fromMenu: true)
          : intentForAction(action);
      if (!enabled(intent)) continue;
      entries.add(
        PaletteEntry(
          id: action.text,
          title: actionLabel(l10n, action),
          subtitle: null,
          kind: spec.group == ActionGroup.config
              ? PaletteKind.config
              : PaletteKind.action,
          shortcut: config.bindings.labelOf(action),
          intent: intent,
        ),
      );
    }
  }
  for (final c in config.config.commands) {
    entries.add(
      PaletteEntry(
        id: 'command:${c.name}',
        title: c.name,
        subtitle: c.text.replaceAll('\n', '⏎'),
        kind: c.enter ? PaletteKind.command : PaletteKind.snippet,
        shortcut: config.bindings.labelOf(KeyAction('run_command', c.name)),
        intent: RunUserCommandIntent(c.name),
      ),
    );
  }
  return entries;
}

List<PaletteEntry> filterPalette(
  List<PaletteEntry> entries,
  String query,
  List<String> recent,
) {
  int recency(PaletteEntry e) {
    final i = recent.indexOf(e.id);
    return i < 0 ? recent.length : i;
  }

  if (query.trim().isEmpty) {
    final order = {for (var i = 0; i < entries.length; i++) entries[i]: i};
    return [...entries]..sort((a, b) {
      final r = recency(a).compareTo(recency(b));
      return r != 0 ? r : order[a]!.compareTo(order[b]!);
    });
  }
  final scored = <(PaletteEntry, int, int)>[];
  for (var i = 0; i < entries.length; i++) {
    final e = entries[i];
    final title = matchScore(query, e.title);
    final sub = e.subtitle == null ? null : matchScore(query, e.subtitle!);
    final score = [?title, if (sub != null) sub - 500].fold<int?>(
      null,
      (best, s) => best == null || s > best ? s : best,
    );
    if (score != null) scored.add((e, score, i));
  }
  scored.sort((a, b) {
    final s = b.$2.compareTo(a.$2);
    if (s != 0) return s;
    final r = recency(a.$1).compareTo(recency(b.$1));
    return r != 0 ? r : a.$3.compareTo(b.$3);
  });
  return [for (final s in scored) s.$1];
}

/// UI-A9 §2: the ⌘⇧P overlay.
class CommandPalette extends StatefulWidget {
  const CommandPalette({
    super.key,
    required this.entries,
    required this.recent,
    required this.onRun,
    required this.onClose,
  });

  final List<PaletteEntry> entries;
  final List<String> recent;
  final void Function(PaletteEntry entry) onRun;
  final VoidCallback onClose;

  @override
  State<CommandPalette> createState() => _CommandPaletteState();
}

class _CommandPaletteState extends State<CommandPalette> {
  final _query = TextEditingController();
  final _field = FocusNode(debugLabel: 'palette search');
  final _scroll = ScrollController();
  late List<PaletteEntry> _results = filterPalette(widget.entries, '', widget.recent);
  int _cursor = 0;
  Timer? _announce;

  @override
  void dispose() {
    _announce?.cancel();
    _query.dispose();
    _field.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _filter(String query) {
    setState(() {
      _results = filterPalette(widget.entries, query, widget.recent);
      _cursor = 0;
    });
    _announce?.cancel();
    _announce = Timer(const Duration(milliseconds: 500), () {
      if (!mounted) return;
      final l10n = AppLocalizations.of(context);
      unawaited(
        SemanticsService.sendAnnouncement(
          View.of(context),
          _results.isEmpty ? l10n.paletteNoResults : l10n.paletteResultCount(_results.length),
          Directionality.of(context),
        ),
      );
    });
  }

  void _move(int step) {
    if (_results.isEmpty) return;
    setState(() => _cursor = (_cursor + step) % _results.length);
    final offset = _cursor * ShellxSizes.paletteRow;
    if (_scroll.hasClients) {
      _scroll.jumpTo(offset.clamp(0, _scroll.position.maxScrollExtent).toDouble());
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final k = event.logicalKey;
    final ctrl = HardwareKeyboard.instance.isControlPressed;
    if (k == LogicalKeyboardKey.arrowDown || (ctrl && k == LogicalKeyboardKey.keyN)) {
      _move(1);
    } else if (k == LogicalKeyboardKey.arrowUp || (ctrl && k == LogicalKeyboardKey.keyP)) {
      _move(-1);
    } else if (k == LogicalKeyboardKey.pageDown) {
      _move(8);
    } else if (k == LogicalKeyboardKey.pageUp) {
      _move(-8);
    } else if (k == LogicalKeyboardKey.enter || k == LogicalKeyboardKey.numpadEnter) {
      if (_results.isNotEmpty) widget.onRun(_results[_cursor]);
    } else if (k == LogicalKeyboardKey.escape) {
      if (_query.text.isNotEmpty) {
        _query.clear();
        _filter('');
      } else {
        widget.onClose();
      }
    } else if (k == LogicalKeyboardKey.tab) {
      // Focus stays in the field (UI-A9 §2.2).
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  String? _kind(AppLocalizations l10n, PaletteKind kind) => switch (kind) {
    PaletteKind.action => null,
    PaletteKind.command => l10n.paletteKindUserCommand,
    PaletteKind.snippet => l10n.paletteKindSnippet,
    PaletteKind.config => l10n.paletteKindConfig,
  };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final size = MediaQuery.sizeOf(context);
    return Semantics(
      scopesRoute: true,
      namesRoute: true,
      explicitChildNodes: true,
      label: l10n.paletteTitle,
      child: Container(
        width: math.min(ShellxSizes.paletteWidth, size.width - 48),
        constraints: BoxConstraints(
          maxHeight: math.min(ShellxSizes.paletteMaxHeight, size.height - 96),
        ),
        padding: const EdgeInsets.all(ShellxSpace.s6),
        decoration: BoxDecoration(
          color: ShellxDesktopColors.surface,
          borderRadius: BorderRadius.circular(ShellxRadius.r8),
          border: Border.all(color: ShellxDesktopColors.border),
          boxShadow: ShellxShadows.e1,
        ),
        child: Material(
          type: MaterialType.transparency,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Focus(
                onKeyEvent: _onKey,
                child: SizedBox(
                  height: ShellxSizes.paletteField,
                  // The field's accessible name (UI-A9 §8).
                  child: Semantics(
                    textField: true,
                    label: l10n.paletteSearchLabel,
                    child: TextField(
                      controller: _query,
                      focusNode: _field,
                      autofocus: true,
                      onChanged: _filter,
                      style: ShellxText.body.copyWith(
                        color: ShellxDesktopColors.textPrimary,
                      ),
                      decoration: InputDecoration(
                        hintText: l10n.paletteSearchHint,
                        prefixIcon: const Icon(Icons.search, size: 16),
                        filled: true,
                        fillColor: ShellxDesktopColors.surfaceInset,
                        isDense: true,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: ShellxSpace.s6),
              const Divider(height: 1, color: ShellxDesktopColors.line),
              Flexible(
                child: _results.isEmpty
                    ? SizedBox(
                        height: ShellxSizes.paletteRow,
                        child: Center(
                          child: Text(
                            l10n.paletteNoResults,
                            style: ShellxText.body.copyWith(color: ShellxDesktopColors.textSecondary),
                          ),
                        ),
                      )
                    : ListView.builder(
                        controller: _scroll,
                        shrinkWrap: true,
                        itemCount: _results.length,
                        itemBuilder: (context, i) => _row(l10n, i),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _row(AppLocalizations l10n, int i) {
    final e = _results[i];
    final selected = i == _cursor;
    final kind = _kind(l10n, e.kind);
    return Semantics(
      key: ValueKey('palette.row.$i'),
      button: true,
      selected: selected,
      label: [e.title, ?kind, ?e.shortcut].join(', '),
      excludeSemantics: true,
      child: InkWell(
        onTap: () => widget.onRun(e),
        borderRadius: BorderRadius.circular(ShellxRadius.r6),
        child: Container(
          constraints: BoxConstraints(
            minHeight: e.subtitle == null ? ShellxSizes.paletteRow : 48,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: selected ? ShellxDesktopColors.rowSelected : null,
            borderRadius: BorderRadius.circular(ShellxRadius.r6),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      e.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: ShellxText.body.copyWith(color: ShellxDesktopColors.textPrimary),
                    ),
                    if (e.subtitle != null)
                      Text(
                        e.subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: ShellxText.small.copyWith(color: ShellxDesktopColors.textSecondary),
                      ),
                  ],
                ),
              ),
              if (kind != null) ...[
                const SizedBox(width: ShellxSpace.s8),
                Text(kind, style: ShellxText.caption.copyWith(color: ShellxDesktopColors.textSecondary)),
              ],
              if (e.shortcut != null) ...[
                const SizedBox(width: ShellxSpace.s8),
                Keycaps(label: e.shortcut!),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// UI-A9 §1.2 keycap: the label as one chip ("⌘⇧D", "Ctrl+Shift+D").
class Keycaps extends StatelessWidget {
  const Keycaps({super.key, required this.label, this.dashed = false});
  final String label;
  final bool dashed;

  @override
  Widget build(BuildContext context) => Container(
    height: ShellxSizes.keycapHeight,
    padding: const EdgeInsets.symmetric(horizontal: ShellxSpace.s6),
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: ShellxDesktopColors.surfaceInset,
      borderRadius: BorderRadius.circular(ShellxRadius.r4),
      border: Border.all(
        color: dashed ? ShellxDesktopColors.dim : ShellxDesktopColors.border,
      ),
    ),
    child: Text(label, style: ShellxText.small.copyWith(color: ShellxDesktopColors.textPrimary)),
  );
}
```

(The `palette.row.0` test reads the first `Text` under the row — the title.)

Workspace page:

```dart
  final List<String> _recent = [];

  void _runPalette(PaletteEntry entry) {
    closeOverlay();
    _recent
      ..remove(entry.id)
      ..insert(0, entry.id);
    if (_recent.length > 8) _recent.removeLast();
    _invoke(entry.intent);
  }
```

Replace the disabled `CommandPaletteIntent` action with `run<CommandPaletteIntent>((_) => overlay == A9Overlay.palette ? closeOverlay() : openOverlay(A9Overlay.palette))`. `openOverlay(A9Overlay.palette)` computes the entries **before** the focus moves (enabled checks such as copy-with-selection read the current focus):

```dart
  List<PaletteEntry> _paletteEntries = const [];

  // in openOverlay, before setState:
    if (next == A9Overlay.palette) {
      final state = ref.read(shellxConfigProvider);
      _paletteEntries = paletteEntries(
        l10n: AppLocalizations.of(context),
        config: state,
        enabled: (intent) {
          if (intent is ShowConfigProblemsIntent) return state.visibleProblemCount > 0;
          if (intent is CommandPaletteIntent) return false;
          final action = _actionsMap[intent.runtimeType];
          return action != null && action.isEnabled(intent);
        },
      );
    }
```

and the overlay slot:

```dart
              if (overlay == A9Overlay.palette)
                Positioned(
                  key: const ValueKey('a9.palette'),
                  left: ShellxSizes.sidebarWidth + 1,
                  right: 0,
                  top: (isMacDesktop ? ShellxSizes.paneHeaderMac : 0) + ShellxSizes.paletteTop,
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: TapRegion(
                      onTapOutside: (_) => closeOverlay(),
                      child: CommandPalette(
                        entries: _paletteEntries,
                        recent: _recent,
                        onRun: _runPalette,
                        onClose: closeOverlay,
                      ),
                    ),
                  ),
                ),
```

(`SelectAllIntent(fromMenu: true)` is enabled from the palette because A1 lets the menu path through; `SendTextIntent` never appears — `text` is not in the palette.)

- [ ] **Step 5: Run the tests**

Run: `cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/config/palette_match_test.dart test/ui/command_palette_test.dart && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test`
Expected: PASS. Format + analyze clean.

- [ ] **Step 6: ⚠ MANUAL**

VoiceOver (macOS) and Narrator (Windows): ⌘⇧P / Ctrl+Shift+P → "Search commands, edit text" is read; typing "chia" (Vietnamese UI) reads the result count once; ↓ reads the selected entry with its shortcut; Esc returns to the terminal and VoiceOver says so. Telex IME composing "xuống" in the field filters correctly. Record in the ledger.

- [ ] **Step 7: Commit**

```bash
git add apps/desktop/lib/src/ui/config apps/desktop/lib/src/ui/terminal/terminal_workspace_page.dart apps/desktop/lib/l10n apps/desktop/test/config/palette_match_test.dart apps/desktop/test/ui/command_palette_test.dart
git commit -m "feat(desktop): command palette — every applicable action with its shortcut, your commands and snippets, config entries; diacritic-insensitive matching, recent first, keyboard and screen-reader complete (A9 D33, D35, D44)"
```

---

### Task 12: The shortcut editor and the managed block writer (D32, D44)

**Files:**
- Create: `apps/desktop/lib/src/config/config_writer.dart`, `apps/desktop/lib/src/ui/config/shortcuts_sheet.dart`
- Modify: `apps/desktop/test/support/memory_config_fs.dart` (also a `ConfigFileStore`), `apps/desktop/test/support/config_harness.dart` (override the store), `apps/desktop/lib/src/terminal/terminal_tabs.dart` (`ConfigWriteFailedNotice`), `apps/desktop/lib/src/ui/terminal/terminal_overlays.dart`, `apps/desktop/lib/src/ui/terminal/terminal_workspace_page.dart`, `apps/desktop/lib/l10n/app_{en,vi}.arb`
- Test: `apps/desktop/test/config/config_writer_test.dart`, `apps/desktop/test/ui/shortcuts_sheet_test.dart`

**Interfaces:**
- Consumes: Tasks 4, 5, 8, 10, 11 (`checkTrigger`, `chordOfEvent`, `chordConfigText`, `actionLabel`, `actionVariants`, `Keycaps`, `problemText`, `configTemplate`).
- Produces:
  - `const kManagedStart = '# >>> shellx-managed keybinds >>>'`, `const kManagedEnd = '# <<< shellx-managed keybinds <<<'`.
  - `sealed class BindingEdit`; `AddBinding(KeyChord chord, KeyAction action)`; `RemoveBinding(KeyChord chord, {required bool isDefault})`; `ResetAction(KeyAction action, List<KeyChord> defaultChords)`.
  - `String applyBindingEdits(String text, List<BindingEdit> edits)`; `({int first, int last})? managedLineRange(String text)` (1-based marker lines).
  - `abstract interface class ConfigFileStore { Future<Uint8List?> read(String path); Future<void> replace(String path, Uint8List bytes); }`; `final class IoConfigFileStore implements ConfigFileStore` (symlinks followed, temp + rename); `final configFileStoreProvider`; `final class ConfigFileWriter { ConfigFileWriter(ConfigFileStore store); Future<void> edit(String path, List<BindingEdit> edits, {required String template}) }` (throws `ConfigWriteRefused` for UTF-16 files); `final configFileWriterProvider`.
  - `class ShortcutsSheet extends ConsumerStatefulWidget { ShortcutsSheet({required VoidCallback onClose, required VoidCallback onOpenFile}) }`.
  - `ConfigWriteFailedNotice(String path)`.
  - ARB: UI-A9 §7.4 `shortcuts*`, `configWriteFailed`.

- [ ] **Step 1: Write the failing tests**

Create `apps/desktop/test/config/config_writer_test.dart`:

```dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/config/config_writer.dart';
import 'package:shellx_desktop/src/config/keybind_actions.dart';
import 'package:shellx_desktop/src/config/keybind_trigger.dart';

import '../support/memory_config_fs.dart';

KeyChord c(String t) => parseKeyChord(t)!;

void main() {
  const user = '# mine\nfont-size = 14\r\nkeybind = super+k=new_tab\n';

  test('add appends a managed block; bytes before it are untouched (D32)', () {
    final out = applyBindingEdits(user, [AddBinding(c('ctrl+alt+n'), const KeyAction('new_tab'))]);
    expect(out.startsWith(user), isTrue);
    expect(out.substring(user.length), '$kManagedStart\r\nkeybind = ctrl+alt+n=new_tab\r\n$kManagedEnd\r\n');
  });

  test('a file without a final newline gets one before the block', () {
    final out = applyBindingEdits('font-size = 14', [AddBinding(c('ctrl+alt+n'), const KeyAction('new_tab'))]);
    expect(out, 'font-size = 14\n$kManagedStart\nkeybind = ctrl+alt+n=new_tab\n$kManagedEnd\n');
  });

  test('the same chord again replaces its line; remove; unbind for defaults', () {
    var text = applyBindingEdits('', [AddBinding(c('ctrl+alt+n'), const KeyAction('new_tab'))]);
    text = applyBindingEdits(text, [AddBinding(c('ctrl+alt+n'), const KeyAction('new_workspace'))]);
    expect('keybind'.allMatches(text).length, 1);
    expect(text, contains('keybind = ctrl+alt+n=new_workspace'));
    text = applyBindingEdits(text, [RemoveBinding(c('ctrl+alt+n'), isDefault: false)]);
    expect(text, isEmpty); // the block disappears with its last line
    text = applyBindingEdits('', [RemoveBinding(c('super+t'), isDefault: true)]);
    expect(text, contains('keybind = super+t=unbind'));
  });

  test('remove writes an unbind when a user line outside the block binds the chord', () {
    final text = applyBindingEdits(user, [RemoveBinding(c('super+k'), isDefault: false)]);
    expect(text, contains('keybind = super+k=unbind'));
    expect(text.startsWith(user), isTrue);
  });

  test('reset drops the action\'s lines and the unbinds of its defaults', () {
    var text = applyBindingEdits('', [
      RemoveBinding(c('super+t'), isDefault: true),
      AddBinding(c('ctrl+alt+n'), const KeyAction('new_tab')),
      AddBinding(c('ctrl+alt+w'), const KeyAction('new_workspace')),
    ]);
    text = applyBindingEdits(text, [ResetAction(const KeyAction('new_tab'), [c('super+t')])]);
    expect(text, isNot(contains('super+t')));
    expect(text, isNot(contains('ctrl+alt+n')));
    expect(text, contains('ctrl+alt+w=new_workspace'));
  });

  test('an existing block in the middle stays in place', () {
    final text = 'a = 1\n$kManagedStart\nkeybind = super+j=new_tab\n$kManagedEnd\nb = 2\n';
    final out = applyBindingEdits(text, [AddBinding(c('super+y'), const KeyAction('new_tab'))]);
    expect(out, 'a = 1\n$kManagedStart\nkeybind = super+j=new_tab\nkeybind = super+y=new_tab\n$kManagedEnd\nb = 2\n');
    expect(managedLineRange(out), (first: 2, last: 5));
  });

  group('ConfigFileWriter', () {
    test('creates from the template; keeps a UTF-8 BOM; refuses UTF-16', () async {
      final fs = MemoryConfigFs();
      final writer = ConfigFileWriter(fs);
      await writer.edit('/c/config', [AddBinding(c('ctrl+alt+n'), const KeyAction('new_tab'))], template: '# template\n');
      expect(fs.text('/c/config'), startsWith('# template\n$kManagedStart'));
      fs.writeBytes('/c/bom', [0xEF, 0xBB, 0xBF, ...utf8.encode('a = 1\n')]);
      await writer.edit('/c/bom', [AddBinding(c('ctrl+alt+n'), const KeyAction('new_tab'))], template: '');
      expect(fs.files['/c/bom']!.sublist(0, 3), [0xEF, 0xBB, 0xBF]);
      fs.writeBytes('/c/u16', [0xFF, 0xFE, 0x61, 0x00]);
      await expectLater(
        writer.edit('/c/u16', [AddBinding(c('ctrl+alt+n'), const KeyAction('new_tab'))], template: ''),
        throwsA(isA<ConfigWriteRefused>()),
      );
      expect(fs.files['/c/u16'], Uint8List.fromList([0xFF, 0xFE, 0x61, 0x00]));
    });
  });
}
```

Create `apps/desktop/test/ui/shortcuts_sheet_test.dart`:

```dart
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/config/config_controller.dart';
import 'package:shellx_desktop/src/config/keybind_actions.dart';
import 'package:shellx_desktop/src/ui/config/config_ui_request.dart';
import 'package:shellx_desktop/src/ui/config/shortcuts_sheet.dart';

import '../support/config_harness.dart';
import '../support/config_workspace.dart';

const cmd = LogicalKeyboardKey.metaLeft;
const ctrl = LogicalKeyboardKey.controlLeft;
const alt = LogicalKeyboardKey.altLeft;

Future<void> press(WidgetTester tester, List<LogicalKeyboardKey> mods, LogicalKeyboardKey key) async {
  for (final m in mods) {
    await tester.sendKeyDownEvent(m);
  }
  await tester.sendKeyEvent(key);
  for (final m in mods.reversed) {
    await tester.sendKeyUpEvent(m);
  }
  await tester.pumpAndSettle();
}

Finder row(String action) => find.byKey(ValueKey('shortcuts.row.$action'));

void main() {
  final mac = TargetPlatformVariant.only(TargetPlatform.macOS);

  Future<({dynamic w})> open(WidgetTester tester, {String config = ''}) async {
    final w = await pumpConfiguredWorkspace(tester, config: config);
    w.container.read(configUiRequestProvider.notifier).request(ConfigUiRequest.shortcuts);
    await tester.pumpAndSettle();
    expect(find.byType(ShortcutsSheet), findsOneWidget);
    return (w: w);
  }

  testWidgets('record a chord: the file gets one managed line and it works (criterion 8)', variant: mac, (tester) async {
    final (:w) = await open(tester, config: '# keep me\n');
    await tester.tap(find.descendant(of: row('new_tab'), matching: find.text('Add shortcut')));
    await tester.pumpAndSettle();
    expect(find.text('Press a key combination… (Esc to cancel)'), findsOneWidget);
    await press(tester, [ctrl, alt], LogicalKeyboardKey.keyN);
    final text = w.fs.text(testConfigPaths().shellx);
    expect(text, startsWith('# keep me\n'));
    expect(text, contains('keybind = ctrl+alt+n=new_tab'));
    expect(
      w.container.read(shellxConfigProvider).bindings.triggersOf(const KeyAction('new_tab')),
      hasLength(2),
    );
    await disposeWorkspace(tester, w.container);
  });

  testWidgets('a taken chord asks; Replace moves it', variant: mac, (tester) async {
    final (:w) = await open(tester);
    await tester.tap(find.descendant(of: row('new_tab'), matching: find.text('Add shortcut')));
    await tester.pumpAndSettle();
    await press(tester, [cmd], LogicalKeyboardKey.keyD);
    expect(find.text('⌘D is used by “Split right”.'), findsOneWidget);
    await tester.tap(find.text('Replace'));
    await tester.pumpAndSettle();
    expect(w.fs.text(testConfigPaths().shellx), contains('keybind = super+d=new_tab'));
    expect(w.container.read(shellxConfigProvider).bindings.labelOf(const KeyAction('new_split', 'right')), isNull);
    await disposeWorkspace(tester, w.container);
  });

  testWidgets('Esc cancels recording; F6 and plain keys are refused in place', variant: mac, (tester) async {
    final (:w) = await open(tester);
    await tester.tap(find.descendant(of: row('new_tab'), matching: find.text('Add shortcut')));
    await tester.pumpAndSettle();
    await press(tester, const [], LogicalKeyboardKey.f6);
    expect(find.text('F6 and Shift+F6 always move between regions'), findsOneWidget);
    await press(tester, const [], LogicalKeyboardKey.keyA);
    expect(find.text('A is for typing — add Ctrl, Alt or ⌘'), findsOneWidget);
    await press(tester, const [], LogicalKeyboardKey.escape);
    expect(find.text('Press a key combination… (Esc to cancel)'), findsNothing);
    expect(find.byType(ShortcutsSheet), findsOneWidget); // Esc only left recording
    expect(w.fs.files.containsKey(testConfigPaths().shellx), isFalse);
    await disposeWorkspace(tester, w.container);
  });

  testWidgets('remove a default and reset it', variant: mac, (tester) async {
    final (:w) = await open(tester);
    await tester.tap(find.descendant(of: row('new_tab'), matching: find.bySemanticsLabel('Remove ⌘T')));
    await tester.pumpAndSettle();
    expect(w.fs.text(testConfigPaths().shellx), contains('keybind = super+t=unbind'));
    expect(find.descendant(of: row('new_tab'), matching: find.text('Not set')), findsOneWidget);
    await tester.tap(find.descendant(of: row('new_tab'), matching: find.text('Reset')));
    await tester.pumpAndSettle();
    expect(w.fs.text(testConfigPaths().shellx), isNot(contains('super+t')));
    expect(w.container.read(shellxConfigProvider).bindings.labelOf(const KeyAction('new_tab')), '⌘T');
    await disposeWorkspace(tester, w.container);
  });
}
```

- [ ] **Step 2: Run the tests to see them fail**

Run: `cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/config/config_writer_test.dart test/ui/shortcuts_sheet_test.dart`
Expected: FAIL.

- [ ] **Step 3: Implement**

Create `apps/desktop/lib/src/config/config_writer.dart`:

```dart
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import 'config_syntax.dart';
import 'keybind_actions.dart';
import 'keybind_trigger.dart';
import 'keybindings.dart';

const kManagedStart = '# >>> shellx-managed keybinds >>>';
const kManagedEnd = '# <<< shellx-managed keybinds <<<';

sealed class BindingEdit {
  const BindingEdit();
}

final class AddBinding extends BindingEdit {
  const AddBinding(this.chord, this.action);
  final KeyChord chord;
  final KeyAction action;
}

/// [isDefault]: the chord is one of the platform defaults (then an
/// `unbind` line is needed to take it away).
final class RemoveBinding extends BindingEdit {
  const RemoveBinding(this.chord, {required this.isDefault});
  final KeyChord chord;
  final bool isDefault;
}

final class ResetAction extends BindingEdit {
  const ResetAction(this.action, this.defaultChords);
  final KeyAction action;
  final List<KeyChord> defaultChords;
}

typedef _Line = ({String trigger, String action});

_Line? _parse(String line) {
  final t = line.trim();
  if (!t.startsWith('keybind')) return null;
  final eq = t.indexOf('=');
  if (eq < 0 || t.substring(0, eq).trim() != 'keybind') return null;
  final split = splitKeybind(t.substring(eq + 1).trim());
  return split == null ? null : (trigger: split.trigger, action: split.action);
}

/// 1-based lines of the two markers, or null.
({int first, int last})? managedLineRange(String text) {
  final lines = text.split('\n');
  final first = lines.indexWhere((l) => l.trim() == kManagedStart);
  if (first < 0) return null;
  final last = lines.indexWhere((l) => l.trim() == kManagedEnd, first + 1);
  return last < 0 ? null : (first: first + 1, last: last + 1);
}

bool _sameChord(String trigger, KeyChord chord) => parseKeyChord(trigger) == chord;

/// D32: edits only the managed block (appended at the end when missing,
/// removed when it ends up empty); every other byte stays.
String applyBindingEdits(String text, List<BindingEdit> edits) {
  final eol = text.contains('\r\n') ? '\r\n' : '\n';
  final start = text.indexOf(kManagedStart);
  final end = start < 0 ? -1 : text.indexOf(kManagedEnd, start);
  final hasBlock = start >= 0 && end >= 0;
  String head;
  String tail;
  final block = <_Line>[];
  if (hasBlock) {
    var after = end + kManagedEnd.length;
    if (text.startsWith('\r\n', after)) {
      after += 2;
    } else if (text.startsWith('\n', after)) {
      after += 1;
    }
    head = text.substring(0, start);
    tail = text.substring(after);
    for (final raw in text.substring(start + kManagedStart.length, end).split('\n')) {
      final line = _parse(raw);
      if (line != null) block.add(line);
    }
  } else {
    head = text;
    tail = '';
  }
  // Lines outside the block that bind a chord (for RemoveBinding).
  final outside = [
    for (final raw in '$head$tail'.split('\n')) ?_parse(raw),
  ];

  for (final edit in edits) {
    switch (edit) {
      case AddBinding(:final chord, :final action):
        final trigger = chordConfigText(chord)!;
        block
          ..removeWhere((l) => _sameChord(l.trigger, chord))
          ..add((trigger: trigger, action: action.text));
      case RemoveBinding(:final chord, :final isDefault):
        block.removeWhere((l) => _sameChord(l.trigger, chord));
        final boundOutside = outside.any(
          (l) => _sameChord(l.trigger, chord) && l.action != 'unbind',
        );
        if (isDefault || boundOutside) {
          block.add((trigger: chordConfigText(chord)!, action: 'unbind'));
        }
      case ResetAction(:final action, :final defaultChords):
        block.removeWhere(
          (l) =>
              l.action == action.text ||
              (l.action == 'unbind' &&
                  defaultChords.any((c) => _sameChord(l.trigger, c))),
        );
    }
  }

  if (block.isEmpty) return head + tail;
  final body = [
    kManagedStart,
    for (final l in block) 'keybind = ${l.trigger}=${l.action}',
    kManagedEnd,
  ].join(eol);
  if (hasBlock) return '$head$body$eol$tail';
  final sep = head.isEmpty || head.endsWith('\n') ? '' : eol;
  return '$head$sep$body$eol';
}

abstract interface class ConfigFileStore {
  Future<Uint8List?> read(String path);

  /// Replaces [path] atomically (a temporary file renamed over it).
  Future<void> replace(String path, Uint8List bytes);
}

final class IoConfigFileStore implements ConfigFileStore {
  const IoConfigFileStore();

  @override
  Future<Uint8List?> read(String path) async {
    final file = File(path);
    return await file.exists() ? file.readAsBytes() : null;
  }

  @override
  Future<void> replace(String path, Uint8List bytes) async {
    // A symlinked config (dotfiles) is written through the link: the link
    // stays a link.
    var target = path;
    if (await FileSystemEntity.isLink(path)) {
      target = await File(path).resolveSymbolicLinks();
    }
    await Directory(p.dirname(target)).create(recursive: true);
    final temp = File('$target.shellx-tmp-$pid');
    await temp.writeAsBytes(bytes, flush: true);
    await temp.rename(target);
  }
}

final class ConfigWriteRefused implements Exception {
  const ConfigWriteRefused();
}

final class ConfigFileWriter {
  ConfigFileWriter(this.store);
  final ConfigFileStore store;

  /// Reads the file now (not the copy from the last load), applies
  /// [edits], writes it back with the same BOM and line endings.
  Future<void> edit(
    String path,
    List<BindingEdit> edits, {
    required String template,
  }) async {
    final bytes = await store.read(path);
    var bom = false;
    String text;
    if (bytes == null) {
      text = template;
    } else {
      if (bytes.length >= 2 &&
          ((bytes[0] == 0xFF && bytes[1] == 0xFE) ||
              (bytes[0] == 0xFE && bytes[1] == 0xFF))) {
        throw const ConfigWriteRefused(); // UTF-16: edit by hand
      }
      bom = bytes.length >= 3 &&
          bytes[0] == 0xEF &&
          bytes[1] == 0xBB &&
          bytes[2] == 0xBF;
      text = decodeConfigBytes(bytes);
    }
    final next = applyBindingEdits(text, edits);
    await store.replace(
      path,
      Uint8List.fromList([if (bom) ...[0xEF, 0xBB, 0xBF], ...utf8.encode(next)]),
    );
  }
}

final configFileStoreProvider = Provider<ConfigFileStore>(
  (ref) => const IoConfigFileStore(),
);

final configFileWriterProvider = Provider<ConfigFileWriter>(
  (ref) => ConfigFileWriter(ref.watch(configFileStoreProvider)),
);

/// The defaults of [action] on [platform] (single chords), for reset.
List<KeyChord> defaultChordsOf(KeyAction action, TargetPlatform platform) => [
  for (final b in defaultKeyBindings(platform))
    if (b.action == action && b.sequence.length == 1) b.sequence.single,
];
```

`MemoryConfigFs` (test support) also implements `ConfigFileStore`:

```dart
final class MemoryConfigFs implements ConfigFs, ConfigFileStore {
  …
  @override
  Future<void> replace(String path, Uint8List bytes) async =>
      writeBytes(path, bytes);
}
```

and `configOverrides` adds `configFileStoreProvider.overrideWithValue(fs)`.

`terminal_tabs.dart`: `final class ConfigWriteFailedNotice extends TabNotice { const ConfigWriteFailedNotice(this.path); final String path; }`; `terminal_overlays.dart` `_text`: `ConfigWriteFailedNotice(:final path) => l10n.configWriteFailed(path)` (error style).

Create `apps/desktop/lib/src/ui/config/shortcuts_sheet.dart`:

```dart
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../../config/config_controller.dart';
import '../../config/config_problem.dart';
import '../../config/config_template.dart';
import '../../config/config_writer.dart';
import '../../config/keybind_actions.dart';
import '../../config/keybind_trigger.dart';
import '../../config/keybindings.dart';
import '../../terminal/terminal_tabs.dart';
import '../theme/shellx_desktop_theme.dart';
import 'action_labels.dart';
import 'command_palette.dart' show Keycaps, matchScore;

/// UI-A9 §4: every action, its chords, add / remove / reset.
class ShortcutsSheet extends ConsumerStatefulWidget {
  const ShortcutsSheet({super.key, required this.onClose, required this.onOpenFile});
  final VoidCallback onClose;
  final VoidCallback onOpenFile;

  @override
  ConsumerState<ShortcutsSheet> createState() => _ShortcutsSheetState();
}

class _ShortcutsSheetState extends ConsumerState<ShortcutsSheet> {
  final _search = TextEditingController();
  final _recorder = FocusNode(debugLabel: 'shortcut recorder');
  String _query = '';
  KeyAction? _recording;
  String? _error;
  ({KeyChord chord, KeyAction other})? _conflict;

  @override
  void dispose() {
    _search.dispose();
    _recorder.dispose();
    super.dispose();
  }

  bool get _mac => ref.read(configPlatformProvider) == TargetPlatform.macOS;

  List<(ActionGroup, KeyAction)> _rows(ConfigState s) => [
    for (final spec in kActionSpecs.values)
      if (!const {'text', 'csi', 'esc', 'ignore', 'run_command'}.contains(spec.name))
        for (final param in actionVariants(spec)) (spec.group, KeyAction(spec.name, param)),
    for (final c in s.config.commands)
      (ActionGroup.commands, KeyAction('run_command', c.name)),
  ];

  void _announce(String message) => unawaited(
    SemanticsService.sendAnnouncement(View.of(context), message, Directionality.of(context)),
  );

  void _startRecording(KeyAction action) {
    setState(() {
      _recording = action;
      _error = null;
      _conflict = null;
    });
    // The recorder's Focus is built in this frame; focus it after.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _recorder.requestFocus();
    });
  }

  void _stopRecording() => setState(() {
    _recording = null;
    _error = null;
    _conflict = null;
  });

  KeyEventResult _onRecordKey(FocusNode node, KeyEvent event) {
    final action = _recording;
    if (action == null || event is KeyUpEvent) return KeyEventResult.ignored;
    final chord = chordOfEvent(event, HardwareKeyboard.instance);
    if (chord == null) return KeyEventResult.handled; // a modifier alone
    final plain = !chord.hasCommandModifier;
    if (plain && !chord.shift && chord.key == LogicalKeyboardKey.escape) {
      _stopRecording();
      return KeyEventResult.handled;
    }
    if (plain && chord.key == LogicalKeyboardKey.tab) {
      _stopRecording();
      return KeyEventResult.ignored; // the focus moves on (WCAG 2.1.2)
    }
    unawaited(_accept(action, chord));
    return KeyEventResult.handled;
  }

  Future<void> _accept(KeyAction action, KeyChord chord) async {
    final l10n = AppLocalizations.of(context);
    final state = ref.read(shellxConfigProvider);
    final label = chordLabel(chord, mac: _mac);
    final rule = checkTrigger([chord], action, mac: _mac, optionAsAlt: state.config.optionAsAlt);
    if (rule.error != null || chordConfigText(chord) == null) {
      final code = rule.error ?? ConfigProblemCode.badTrigger;
      setState(
        () => _error = problemText(
          l10n,
          ConfigProblem(file: '', line: 0, severity: ConfigSeverity.error, code: code, value: label),
        ),
      );
      _announce(_error!);
      return;
    }
    final scope = kActionSpecs[action.name]!.scope;
    final existing = state.bindings.find([chord], scope);
    if (existing != null && existing.action == action) {
      _stopRecording();
      return;
    }
    if (existing != null) {
      setState(() => _conflict = (chord: chord, other: existing.action));
      _announce(l10n.shortcutsConflict(label, actionLabel(l10n, existing.action)));
      return;
    }
    await _write(
      [AddBinding(chord, action)],
      l10n.shortcutsAssigned(label, actionLabel(l10n, action)),
    );
  }

  Future<void> _write(List<BindingEdit> edits, String announcement) async {
    final paths = ref.read(configPathsProvider);
    try {
      await ref.read(configFileWriterProvider).edit(
        paths.shellx,
        edits,
        template: configTemplate(mac: _mac, ghosttyFiles: const []),
      );
    } catch (error) {
      debugPrint('ShellX: shortcut not saved: ${error.runtimeType}');
      ref.read(terminalTabsProvider.notifier).showNotice(ConfigWriteFailedNotice(paths.shellx));
      return;
    }
    if (!mounted) return;
    _stopRecording();
    await ref.read(shellxConfigProvider.notifier).load();
    if (mounted) _announce(announcement);
  }

  bool _isDefault(KeyChord chord) => defaultKeyBindings(ref.read(configPlatformProvider))
      .any((b) => b.sequence.length == 1 && b.sequence.single == chord);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(shellxConfigProvider);
    final size = MediaQuery.sizeOf(context);
    final rows = [
      for (final (group, action) in _rows(state))
        if (_query.isEmpty || matchScore(_query, actionLabel(l10n, action)) != null)
          (group, action),
    ];
    final shellx = ref.read(configPathsProvider).shellx;
    ActionGroup? lastGroup;
    final children = <Widget>[];
    for (final (group, action) in rows) {
      if (group != lastGroup) {
        lastGroup = group;
        children.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(
              l10n.shortcutsGroup(group.name).toUpperCase(),
              style: ShellxText.caption.copyWith(
                color: ShellxDesktopColors.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        );
      }
      children.add(_row(l10n, state, action, shellx));
    }
    return Semantics(
      scopesRoute: true,
      namesRoute: true,
      explicitChildNodes: true,
      label: l10n.shortcutsTitle,
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): () {
            if (_recording == null) widget.onClose();
          },
        },
        child: FocusScope(
          autofocus: true,
          child: Container(
            width: math.min(ShellxSizes.shortcutsWidth, size.width - 48),
            height: math.min(ShellxSizes.shortcutsHeight, size.height - 64),
            decoration: BoxDecoration(
              color: ShellxDesktopColors.surface,
              borderRadius: BorderRadius.circular(ShellxRadius.r8),
              border: Border.all(color: ShellxDesktopColors.border),
              boxShadow: ShellxShadows.e1,
            ),
            child: Material(
              type: MaterialType.transparency,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            l10n.shortcutsTitle,
                            style: ShellxText.bodyStrong.copyWith(color: ShellxDesktopColors.textPrimary),
                          ),
                        ),
                        IconButton(
                          tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                          icon: const Icon(Icons.close, size: 16),
                          onPressed: widget.onClose,
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Semantics(
                      textField: true,
                      label: l10n.shortcutsSearchLabel,
                      child: TextField(
                        controller: _search,
                        autofocus: true,
                        onChanged: (v) => setState(() => _query = v),
                        decoration: InputDecoration(
                          hintText: l10n.shortcutsSearchLabel,
                          prefixIcon: const Icon(Icons.search, size: 16),
                          isDense: true,
                        ),
                      ),
                    ),
                  ),
                  Expanded(child: ListView(children: children)),
                  const Divider(height: 1, color: ShellxDesktopColors.line),
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            l10n.shortcutsFooter,
                            style: ShellxText.small.copyWith(color: ShellxDesktopColors.textSecondary),
                          ),
                        ),
                        FilledButton(onPressed: widget.onOpenFile, child: Text(l10n.configOpenFile)),
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

  Widget _row(AppLocalizations l10n, ConfigState state, KeyAction action, String shellx) {
    final name = actionLabel(l10n, action);
    final bindings = [
      for (final b in state.bindings.all)
        if (b.action == action && b.sequence.length == 1) b,
    ];
    final defaults = defaultChordsOf(action, state.bindings.platform);
    final changed = !listEquals(
      [for (final b in bindings) b.sequence.single],
      defaults,
    );
    final recording = _recording == action;
    final labels = [for (final b in bindings) chordLabel(b.sequence.single, mac: _mac)];
    return Semantics(
      key: ValueKey('shortcuts.row.${action.text}'),
      container: true,
      label: labels.isEmpty ? name : '$name, ${labels.join(', ')}',
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: ShellxSizes.shortcutsRow,
              child: Row(
                children: [
                  SizedBox(
                    width: 280,
                    child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: ShellxText.body.copyWith(color: ShellxDesktopColors.textPrimary)),
                  ),
                  Expanded(
                    child: recording
                        ? Focus(
                            focusNode: _recorder,
                            onKeyEvent: _onRecordKey,
                            child: Semantics(
                              liveRegion: true,
                              child: Container(
                                height: ShellxSizes.keycapHeight + 8,
                                alignment: Alignment.centerLeft,
                                padding: const EdgeInsets.symmetric(horizontal: 8),
                                decoration: BoxDecoration(
                                  color: ShellxDesktopColors.surfaceInset,
                                  borderRadius: BorderRadius.circular(ShellxRadius.r4),
                                  border: Border.all(
                                    color: _error == null ? ShellxDesktopColors.accent : ShellxDesktopColors.err,
                                  ),
                                ),
                                child: Text(l10n.shortcutsRecording,
                                    style: ShellxText.small.copyWith(color: ShellxDesktopColors.textPrimary)),
                              ),
                            ),
                          )
                        : Wrap(
                            spacing: ShellxSizes.keycapGap,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              if (bindings.isEmpty)
                                Text(l10n.shortcutsNone,
                                    style: ShellxText.small.copyWith(color: ShellxDesktopColors.textSecondary)),
                              for (final b in bindings)
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Tooltip(
                                      message: b.origin == null || b.origin!.file != shellx
                                          ? ''
                                          : l10n.shortcutsFromFile(b.origin!.line),
                                      child: Keycaps(
                                        label: chordLabel(b.sequence.single, mac: _mac),
                                        dashed: b.origin != null,
                                      ),
                                    ),
                                    Semantics(
                                      button: true,
                                      label: l10n.shortcutsRemove(chordLabel(b.sequence.single, mac: _mac)),
                                      excludeSemantics: true,
                                      child: InkResponse(
                                        radius: 10,
                                        onTap: () => unawaited(_write(
                                          [RemoveBinding(b.sequence.single, isDefault: _isDefault(b.sequence.single))],
                                          l10n.shortcutsRemoved(chordLabel(b.sequence.single, mac: _mac)),
                                        )),
                                        child: const Padding(
                                          padding: EdgeInsets.all(4),
                                          child: Icon(Icons.close, size: 12, color: ShellxDesktopColors.textSecondary),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                            ],
                          ),
                  ),
                  if (recording)
                    TextButton(onPressed: _stopRecording, child: Text(l10n.shortcutsCancel))
                  else ...[
                    Semantics(
                      label: l10n.shortcutsAddFor(name),
                      button: true,
                      excludeSemantics: true,
                      child: TextButton(
                        onPressed: () => _startRecording(action),
                        child: Text(l10n.shortcutsAdd),
                      ),
                    ),
                    if (changed)
                      TextButton(
                        onPressed: () => unawaited(_write(
                          [ResetAction(action, defaults)],
                          l10n.shortcutsResetDone(name),
                        )),
                        child: Text(l10n.shortcutsReset),
                      ),
                  ],
                ],
              ),
            ),
            if (recording && _error != null)
              Text(_error!, style: ShellxText.small.copyWith(color: ShellxDesktopColors.err)),
            if (recording && _conflict != null)
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: ShellxDesktopColors.warnBg,
                  border: Border.all(color: ShellxDesktopColors.warnBorder),
                  borderRadius: BorderRadius.circular(ShellxRadius.r6),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        l10n.shortcutsConflict(
                          chordLabel(_conflict!.chord, mac: _mac),
                          actionLabel(l10n, _conflict!.other),
                        ),
                        style: ShellxText.small.copyWith(color: ShellxDesktopColors.textPrimary),
                      ),
                    ),
                    TextButton(onPressed: _stopRecording, child: Text(l10n.shortcutsCancel)),
                    FilledButton(
                      autofocus: true,
                      onPressed: () => unawaited(_write(
                        [AddBinding(_conflict!.chord, action)],
                        l10n.shortcutsAssigned(chordLabel(_conflict!.chord, mac: _mac), name),
                      )),
                      child: Text(l10n.shortcutsReplace),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
```

(Keycaps are dashed for any chord set in a file; the tooltip names the line only for the ShellX file.)

Workspace page: replace the disabled `ShowShortcutsIntent` action with `run<ShowShortcutsIntent>((_) => openOverlay(A9Overlay.shortcuts))`, and add the slot (full window, `scrim` behind, the sheet blocks the window — window shortcuts do not run while it is open, UI-A9 §4.2):

```dart
              if (overlay == A9Overlay.shortcuts) ...[
                const Positioned.fill(
                  child: ModalBarrier(color: ShellxDesktopColors.scrim, dismissible: false),
                ),
                Positioned.fill(
                  key: const ValueKey('a9.shortcuts'),
                  child: Center(
                    child: ShortcutsSheet(
                      onClose: closeOverlay,
                      onOpenFile: () {
                        closeOverlay();
                        unawaited(openShellxConfig(ref.read));
                      },
                    ),
                  ),
                ),
              ],
```

To keep window shortcuts from running under the sheet, the workspace `Shortcuts` gets `shortcuts: overlay == A9Overlay.shortcuts ? const {} : _workspaceShortcuts!`, and `TerminalPane` receives `shortcuts: overlay == A9Overlay.shortcuts ? const {} : terminalShortcuts` (the terminal is not focused meanwhile anyway).

ARB en (UI-A9 §7.4):

```json
  "shortcutsTitle": "Keyboard shortcuts",
  "@shortcutsTitle": {"description": "UI-A9 §4"},
  "shortcutsSearchLabel": "Search shortcuts",
  "@shortcutsSearchLabel": {"description": "UI-A9 §4"},
  "shortcutsGroup": "{group, select, tabs{Tabs} panes{Panes} notifications{Notifications} editing{Editing} font{Text size} browser{Browser} window{Window} config{Configuration} other{Your commands}}",
  "@shortcutsGroup": {"description": "UI-A9 §4.1", "placeholders": {"group": {"type": "String"}}},
  "shortcutsAdd": "Add shortcut",
  "@shortcutsAdd": {"description": "UI-A9 §4.1"},
  "shortcutsAddFor": "Add a shortcut for “{action}”",
  "@shortcutsAddFor": {"description": "UI-A9 §8", "placeholders": {"action": {"type": "String"}}},
  "shortcutsReset": "Reset",
  "@shortcutsReset": {"description": "UI-A9 §4.1"},
  "shortcutsRemove": "Remove {shortcut}",
  "@shortcutsRemove": {"description": "UI-A9 §8", "placeholders": {"shortcut": {"type": "String"}}},
  "shortcutsNone": "Not set",
  "@shortcutsNone": {"description": "UI-A9 §4.1"},
  "shortcutsRecording": "Press a key combination… (Esc to cancel)",
  "@shortcutsRecording": {"description": "UI-A9 §4.1"},
  "shortcutsConflict": "{shortcut} is used by “{action}”.",
  "@shortcutsConflict": {"description": "UI-A9 §4.1", "placeholders": {"shortcut": {"type": "String"}, "action": {"type": "String"}}},
  "shortcutsReplace": "Replace",
  "@shortcutsReplace": {"description": "UI-A9 §4.1"},
  "shortcutsCancel": "Cancel",
  "@shortcutsCancel": {"description": "UI-A9 §4.1"},
  "shortcutsFromFile": "Set in the configuration file, line {line}",
  "@shortcutsFromFile": {"description": "UI-A9 §4.1", "placeholders": {"line": {"type": "int"}}},
  "shortcutsAssigned": "{shortcut} now runs “{action}”",
  "@shortcutsAssigned": {"description": "UI-A9 §8", "placeholders": {"shortcut": {"type": "String"}, "action": {"type": "String"}}},
  "shortcutsRemoved": "Removed {shortcut}",
  "@shortcutsRemoved": {"description": "UI-A9 §8", "placeholders": {"shortcut": {"type": "String"}}},
  "shortcutsResetDone": "“{action}” reset",
  "@shortcutsResetDone": {"description": "UI-A9 §8", "placeholders": {"action": {"type": "String"}}},
  "shortcutsFooter": "Shortcuts written in the file are kept.",
  "@shortcutsFooter": {"description": "UI-A9 §4.1"},
  "configWriteFailed": "Couldn't save the shortcut to {path}",
  "@configWriteFailed": {"description": "UI-A9 §7.1", "placeholders": {"path": {"type": "String"}}},
```

vi:

```json
  "shortcutsTitle": "Phím tắt",
  "shortcutsSearchLabel": "Tìm phím tắt",
  "shortcutsGroup": "{group, select, tabs{Tab} panes{Pane} notifications{Thông báo} editing{Chỉnh sửa} font{Cỡ chữ} browser{Trình duyệt} window{Cửa sổ} config{Cấu hình} other{Lệnh của bạn}}",
  "shortcutsAdd": "Thêm phím",
  "shortcutsAddFor": "Thêm phím cho “{action}”",
  "shortcutsReset": "Đặt lại",
  "shortcutsRemove": "Bỏ {shortcut}",
  "shortcutsNone": "Chưa gán",
  "shortcutsRecording": "Bấm tổ hợp phím… (Esc để huỷ)",
  "shortcutsConflict": "{shortcut} đang dùng cho “{action}”.",
  "shortcutsReplace": "Thay thế",
  "shortcutsCancel": "Huỷ",
  "shortcutsFromFile": "Đặt trong file cấu hình, dòng {line}",
  "shortcutsAssigned": "Đã gán {shortcut} cho “{action}”",
  "shortcutsRemoved": "Đã bỏ {shortcut}",
  "shortcutsResetDone": "Đã đặt lại “{action}”",
  "shortcutsFooter": "Phím viết tay trong file vẫn được giữ.",
  "configWriteFailed": "Không lưu được phím tắt vào {path}",
```

`flutter gen-l10n`.

- [ ] **Step 4: Run the tests**

Run: `cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/config/config_writer_test.dart test/ui/shortcuts_sheet_test.dart && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test`
Expected: PASS. Format + analyze clean.

- [ ] **Step 5: ⚠ MANUAL**

macOS + Windows: record ⌃⌥N for "Tab mới" with the config file a **symlink** into a dotfiles folder → the link stays a link (`ls -l`), the target gains the block; with the file open in an editor that has unsaved changes, the editor reports the external change (no silent loss). Windows: a CRLF file stays CRLF (`file`/Notepad status bar), a UTF-8 BOM stays; `rename` over the existing file succeeds. VoiceOver/Narrator: recording reads the held chord and "⌘⇧T now runs …". Record in the ledger.

- [ ] **Step 6: Commit**

```bash
git add apps/desktop/lib/src/config/config_writer.dart apps/desktop/lib/src/ui/config/shortcuts_sheet.dart apps/desktop/lib/src/terminal/terminal_tabs.dart apps/desktop/lib/src/ui/terminal/terminal_overlays.dart apps/desktop/lib/src/ui/terminal/terminal_workspace_page.dart apps/desktop/lib/l10n apps/desktop/test/support/memory_config_fs.dart apps/desktop/test/support/config_harness.dart apps/desktop/test/config/config_writer_test.dart apps/desktop/test/ui/shortcuts_sheet_test.dart
git commit -m "feat(desktop): shortcut editor — record, conflict and replace, remove, reset; edits only a managed block written atomically through symlinks, keeping BOM and line endings (A9 D32, D44)"
```

---
### Task 13: `shellx config path|check|reload|show`, `ui.config.*`, new-tab directory over the CLI, the `shellx-config` skill in A7's installer (D21, D34, D39, D40)

**Files:**
- Create: `apps/desktop/lib/src/config/config_show.dart`, `term/src/api/config_path.rs`, `agent-skills/shellx-config/SKILL.md`
- Modify: `packages/shellx_agent/lib/src/mux/cli_wire.dart` (types, cap), `apps/desktop/lib/src/cli/ui_command_handler.dart`, `term/src/api/mod.rs`, `term/src/api/args.rs`, `term/src/api/run.rs`, `term/src/api/client.rs` (`ApiError::Exit`), `term/src/api/skills.rs`, `agent-skills/shellx/reference.md`, `agent-skills/shellx/SKILL.md` (one pointer line)
- Test: `apps/desktop/test/cli/ui_command_handler_config_test.dart`, Rust unit tests in `config_path.rs`, `skills.rs`, `args.rs`

**Interfaces:**
- Consumes: Tasks 5, 7, 8 (`ConfigController.load/check`, `TerminalTabs.newTabCwd`, `configTemplate`); A7 `UiCommandHandler`, `CliType`, `kCliCaps`, `MuxMessage`, Rust `Api`, `Parsed`, `Ctx`, `Value`, `to_json`, `output::result_json`, `skills::{SKILL, REFERENCE, install, print}`.
- Produces:
  - Dart: `CliType.uiConfigCheck = 'ui.config.check'`, `uiConfigReload = 'ui.config.reload'`, `uiConfigShow = 'ui.config.show'`; `kCliCaps` gains `'ui.config'`; `List<Map<String, String>> configShowValues(ConfigState s)`; `UiCommandHandler` answers `ui.config.check` → `{problems: [{file, line, severity, code, key?, message}], generation}` (message = `configProblemEnglish`), `ui.config.reload` (same shape, after a manual load), `ui.config.show{defaults?}` → `{values: [{key, value, source}], files: {shellx, ghostty: [...]}}` or `{template}`; `ui.tab.new` without `cwd` uses `newTabCwd()`.
  - Rust: `pub struct ConfigPaths { pub shellx: String, pub ghostty: Vec<String> }`; `pub fn config_paths(env: &dyn Fn(&str) -> Option<String>, windows: bool) -> Option<ConfigPaths>`; `pub fn print_path(p: &Parsed, ctx: &mut Ctx) -> Result<(), ApiError>`; `pub fn render(path: &str, json: bool, result: &Value) -> (String, i32)`; `ApiError::Exit(i32)`; skills: `pub const CONFIG_SKILL: &str`, `pub const SKILLS: &[(&str, &[(&str, &str)])]`; `shellx skills print config`.

- [ ] **Step 1: Write the failing tests**

Create `apps/desktop/test/cli/ui_command_handler_config_test.dart` (container set-up as in A7's `ui_command_handler_test.dart`):

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_desktop/src/agent/desktop_services.dart';
import 'package:shellx_desktop/src/cli/ui_command_handler.dart';
import 'package:shellx_desktop/src/config/config_controller.dart';
import 'package:shellx_desktop/src/terminal/local_sessions_provider.dart';
import 'package:shellx_desktop/src/terminal/terminal_tabs.dart';

import '../support/config_harness.dart';
import '../support/fake_local_sessions.dart';
import '../support/fakes.dart';
import '../support/memory_config_fs.dart';

void main() {
  late MemoryConfigFs fs;
  late FakeLocalSessions local;
  late ProviderContainer c;
  final paths = testConfigPaths();

  setUp(() {
    fs = MemoryConfigFs();
    local = FakeLocalSessions();
    c = ProviderContainer(
      overrides: [
        desktopServicesProvider.overrideWithValue(TestHarness().services()),
        localSessionsProvider.overrideWithValue(local),
        ...configOverrides(fs),
      ],
    );
    c.listen(terminalTabsProvider, (_, _) {});
  });
  tearDown(() => c.dispose());

  Future<Map<String, Object?>> call(String type, [Map<String, Object?> fields = const {}]) =>
      c.read(uiCommandHandlerProvider).handle(MuxMessage(type, q: 1, fields: fields));

  test('the cap is advertised (A7 D4)', () {
    expect(kCliCaps, contains('ui.config'));
  });

  test('check reports the files as they are, without applying (D39)', () async {
    fs.write(paths.shellx, 'font-size = to\n');
    final r = await call(CliType.uiConfigCheck);
    final p = (r['problems']! as List).single as Map;
    expect(p['file'], paths.shellx);
    expect(p['line'], 1);
    expect(p['severity'], 'error');
    expect(p['code'], 'badValue');
    expect(p['key'], 'font-size');
    expect(p['message'], 'font-size: “to” is not valid (expected 9–28)');
    expect(c.read(shellxConfigProvider).generation, 0);
  });

  test('reload applies and answers with the new problems', () async {
    fs.write(paths.shellx, 'font-size = 16\n');
    final r = await call(CliType.uiConfigReload);
    expect(r['problems'], isEmpty);
    expect(r['generation'], 1);
    expect(c.read(shellxConfigProvider).config.fontSize, 16);
    expect(c.read(shellxConfigProvider).lastLoad!.manual, isTrue);
  });

  test('show: values with their source; --defaults: the template', () async {
    fs.write(paths.shellx, '\nfont-size = 16\n');
    await call(CliType.uiConfigReload);
    final r = await call(CliType.uiConfigShow);
    final values = (r['values']! as List).cast<Map>();
    final size = values.firstWhere((v) => v['key'] == 'font-size');
    expect(size['value'], '16');
    expect(size['source'], '${paths.shellx}:2');
    expect(values.firstWhere((v) => v['key'] == 'cursor-style')['source'], 'default');
    expect((r['files']! as Map)['shellx'], paths.shellx);
    final d = await call(CliType.uiConfigShow, {'defaults': true});
    expect(d['template'], contains('# font-size = 13'));
  });

  test('new-tab without --cwd follows working-directory (D21)', () async {
    fs.write(paths.shellx, 'working-directory = /tmp/w\n');
    await call(CliType.uiConfigReload);
    await call(CliType.uiTabNew);
    expect(local.openCwds.last, '/tmp/w');
  });
}
```

Rust — create `term/src/api/config_path.rs` with its tests at the bottom (the implementation follows in Step 3):

```rust
#[cfg(test)]
mod tests {
    use super::*;
    use crate::api::value::Value;

    fn env<'a>(pairs: &'a [(&'a str, &'a str)]) -> impl Fn(&str) -> Option<String> + 'a {
        move |k| pairs.iter().find(|(n, _)| *n == k).map(|(_, v)| v.to_string())
    }

    // The same strings as apps/desktop/test/config/config_paths_test.dart.
    #[test]
    fn macos_without_xdg() {
        let p = config_paths(&env(&[("HOME", "/Users/me")]), false).unwrap();
        assert_eq!(p.shellx, "/Users/me/.config/shellx/config");
        assert_eq!(
            p.ghostty,
            vec![
                "/Users/me/.config/ghostty/config.ghostty",
                "/Users/me/.config/ghostty/config",
                "/Users/me/Library/Application Support/com.mitchellh.ghostty/config.ghostty",
                "/Users/me/Library/Application Support/com.mitchellh.ghostty/config",
            ]
        );
    }

    #[test]
    fn xdg_absolute_only() {
        let p = config_paths(&env(&[("HOME", "/Users/me"), ("XDG_CONFIG_HOME", "/x/cfg")]), false).unwrap();
        assert_eq!(p.shellx, "/x/cfg/shellx/config");
        assert_eq!(p.ghostty[0], "/x/cfg/ghostty/config.ghostty");
        let r = config_paths(&env(&[("HOME", "/Users/me"), ("XDG_CONFIG_HOME", "cfg")]), false).unwrap();
        assert_eq!(r.shellx, "/Users/me/.config/shellx/config");
    }

    #[test]
    fn windows_appdata() {
        let p = config_paths(
            &env(&[("USERPROFILE", r"C:\Users\me"), ("APPDATA", r"C:\Users\me\AppData\Roaming")]),
            true,
        )
        .unwrap();
        assert_eq!(p.shellx, r"C:\Users\me\AppData\Roaming\ShellX\config");
        assert_eq!(p.ghostty, vec![r"C:\Users\me\.config\ghostty\config.ghostty", r"C:\Users\me\.config\ghostty\config"]);
        let q = config_paths(&env(&[("USERPROFILE", r"C:\Users\me")]), true).unwrap();
        assert_eq!(q.shellx, r"C:\Users\me\AppData\Roaming\ShellX\config");
        assert!(config_paths(&env(&[]), true).is_none());
    }

    fn problem(sev: &str, line: i64) -> Value {
        Value::map(vec![
            ("file", Value::text("/c/config")),
            ("line", Value::Int(line)),
            ("severity", Value::text(sev)),
            ("code", Value::text("badValue")),
            ("message", Value::text("font-size: “to” is not valid (expected 9–28)")),
        ])
    }

    #[test]
    fn check_prints_file_line_severity_and_exits_1_on_errors() {
        let v = Value::map(vec![
            ("problems", Value::Array(vec![problem("error", 3), problem("warning", 0)])),
            ("generation", Value::Int(1)),
        ]);
        let (out, code) = render("config check", false, &v);
        assert_eq!(
            out,
            "/c/config:3: error: font-size: “to” is not valid (expected 9–28)\n/c/config: warning: font-size: “to” is not valid (expected 9–28)\n"
        );
        assert_eq!(code, 1);
        let (json, code) = render("config check", true, &v);
        assert_eq!(json.lines().count(), 1);
        assert!(json.starts_with('{'));
        assert_eq!(code, 1);
    }

    #[test]
    fn clean_check_and_reload() {
        let v = Value::map(vec![("problems", Value::Array(vec![])), ("generation", Value::Int(2))]);
        assert_eq!(render("config check", false, &v), ("no problems\n".to_string(), 0));
        assert_eq!(render("config reload", false, &v), (String::new(), 0));
        let warn = Value::map(vec![("problems", Value::Array(vec![problem("warning", 1)]))]);
        assert_eq!(render("config reload", false, &warn).1, 0);
    }

    #[test]
    fn show_values_and_template() {
        let v = Value::map(vec![(
            "values",
            Value::Array(vec![Value::map(vec![
                ("key", Value::text("font-size")),
                ("value", Value::text("16")),
                ("source", Value::text("/c/config:2")),
            ])]),
        )]);
        assert_eq!(render("config show", false, &v), ("font-size = 16  # /c/config:2\n".to_string(), 0));
        let t = Value::map(vec![("template", Value::text("# hi\n"))]);
        assert_eq!(render("config show", false, &t), ("# hi\n".to_string(), 0));
    }
}
```

In `term/src/api/skills.rs` tests add:

```rust
    #[test]
    fn installs_both_skills_and_prints_config() {
        let home = temp_home("both");
        assert_eq!(run_skills(&["skills", "install", "--claude"], &home, "", false).0, 0);
        assert!(home.join(".claude/skills/shellx/SKILL.md").exists());
        assert!(home.join(".claude/skills/shellx-config/SKILL.md").exists());
        let (code, out, _) = run_skills(&["skills", "print", "config"], &home, "", false);
        assert_eq!(code, 0);
        assert!(out.starts_with("---\nname: shellx-config"));
    }
```

(`temp_home`/`run_skills` are A7's helpers in that test module; use their real names.) In `term/src/api/args.rs` tests add: `parse(["config", "path", "--ghostty"])` resolves to the `config path` spec with the flag; `parse(["config", "show", "--defaults"])`; `help_text()` lists all four `config` commands; every completion script contains `config`.

- [ ] **Step 2: Run the tests to see them fail**

Run: `cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/cli/ui_command_handler_config_test.dart; cd ../../term && ~/.cargo/bin/cargo test api::config_path api::skills api::args`
Expected: FAIL (missing types, module, commands).

- [ ] **Step 3: Implement — Dart**

`packages/shellx_agent/lib/src/mux/cli_wire.dart`: add to `CliType`:

```dart
  /// A9 D39.
  static const uiConfigCheck = 'ui.config.check';
  static const uiConfigReload = 'ui.config.reload';
  static const uiConfigShow = 'ui.config.show';
```

and `'ui.config'` to `kCliCaps` (after `'ui.browser'`). In `api.call` on the Rust side the cap of every `ui.config.*` type is `ui.config` (Step 4).

Create `apps/desktop/lib/src/config/config_show.dart`:

```dart
import 'package:flutter/painting.dart';

import 'config_controller.dart';
import 'shellx_config.dart';

String _n(double v) => v == v.roundToDouble() ? v.toInt().toString() : '$v';
String _hex(Color c) =>
    '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

/// `shellx config show` (D39): every key in effect and where it comes from.
List<Map<String, String>> configShowValues(ConfigState s) {
  final c = s.config;
  String source(String key) {
    final o = c.origins[key];
    return o == null ? 'default' : '${o.file}:${o.line}';
  }

  Map<String, String> v(String key, String value) =>
      {'key': key, 'value': value, 'source': source(key)};
  String pair(double a, double b) => a == b ? _n(a) : '${_n(a)},${_n(b)}';
  return [
    v('font-family', c.fontFamilies.isEmpty ? 'JetBrains Mono' : c.fontFamilies.join(', ')),
    v('font-size', c.fontSize == null ? '13 (or the size set with Cmd/Ctrl +/-)' : _n(c.fontSize!)),
    v('theme', s.theme.name ?? 'ShellX'),
    v('background', _hex(s.theme.background)),
    v('foreground', _hex(s.theme.terminal.foreground)),
    v('cursor-style', c.cursorShape.name),
    v('scrollback-limit', '${c.scrollbackLimit}'),
    v('window-padding-x', pair(c.padding.left, c.padding.right)),
    v('window-padding-y', pair(c.padding.top, c.padding.bottom)),
    v('macos-option-as-alt', switch (c.optionAsAlt) {
      OptionAsAlt.off => 'false',
      OptionAsAlt.both => 'true',
      OptionAsAlt.left => 'left',
      OptionAsAlt.right => 'right',
    }),
    v('confirm-close-surface', switch (c.confirmClose) {
      ConfirmClose.whenRunning => 'true',
      ConfirmClose.never => 'false',
      ConfirmClose.always => 'always',
    }),
    v('working-directory', switch (c.workingDirectory.kind) {
      WorkingDirectoryKind.home => 'home',
      WorkingDirectoryKind.inherit => 'inherit',
      WorkingDirectoryKind.path => c.workingDirectory.path!,
    }),
    v('ghostty-config', '${c.ghosttyConfig}'),
    for (final k in c.keybinds)
      {'key': 'keybind', 'value': k.value, 'source': '${k.origin.file}:${k.origin.line}'},
    for (final u in c.commands)
      {
        'key': u.enter ? 'command' : 'snippet',
        'value': '${u.name} = ${u.text.replaceAll('\n', r'\n')}',
        'source': '${u.origin.file}:${u.origin.line}',
      },
  ];
}
```

`apps/desktop/lib/src/cli/ui_command_handler.dart` — in `handle`'s switch:

```dart
      CliType.uiConfigCheck => _configCheck(),
      CliType.uiConfigReload => _configReload(),
      CliType.uiConfigShow => _configShow(r),
```

and the methods (imports: `../config/config_controller.dart`, `../config/config_problem.dart`, `../config/config_show.dart`, `../config/config_template.dart`):

```dart
  ConfigController get _config => _ref.read(shellxConfigProvider.notifier);

  /// D39: English messages (A7 D11); contents never logged (D40).
  Map<String, Object?> _problems(List<ConfigProblem> problems, int generation) => {
    'problems': [
      for (final p in problems)
        {
          'file': p.file,
          'line': p.line,
          'severity': p.severity.name,
          'code': p.code.name,
          'key': ?p.key,
          'message': configProblemEnglish(p),
        },
    ],
    'generation': generation,
  };

  Future<Map<String, Object?>> _configCheck() async =>
      _problems(await _config.check(), _ref.read(shellxConfigProvider).generation);

  Future<Map<String, Object?>> _configReload() async {
    final s = await _config.load(manual: true);
    return _problems(s.problems, s.generation);
  }

  Future<Map<String, Object?>> _configShow(MuxMessage r) async {
    final paths = _ref.read(configPathsProvider);
    final state = _ref.read(shellxConfigProvider);
    final ghostty = [
      for (final f in paths.ghostty)
        if (state.ghosttyUsed && state.files.contains(f)) f,
    ];
    if (r.fields['defaults'] == true) {
      return {
        'template': configTemplate(
          mac: _ref.read(configPlatformProvider) == TargetPlatform.macOS,
          ghosttyFiles: ghostty,
        ),
      };
    }
    return {
      'values': configShowValues(state),
      'files': {'shellx': paths.shellx, 'ghostty': ghostty},
    };
  }
```

`_tabNew` (A7 Task 6): where it passes `cwd` to `openTabFor`, use `cwd ?? _tabs.newTabCwd()` (D21; a `--cwd` from the CLI still wins).

These requests take no target, so they set no Agent mark (A7 D27) and follow `cli_control_enabled` like every `ui.*` (A7 D26) — nothing to add in `CliHost`.

- [ ] **Step 4: Implement — Rust**

`term/src/api/mod.rs`: `pub mod config_path;`.

`term/src/api/client.rs`: add the variant `Exit(i32)` to `ApiError` (doc: "the output is already written; exit with this code") and in `exit_code()` the arm `ApiError::Exit(c) => *c`. In `run.rs` `run()`, handle it before printing: `Err(ApiError::Exit(code)) => code,`; in `describe()` add `ApiError::Exit(c) => ("exit".into(), format!("exit {c}")),` (never printed).

`term/src/api/args.rs`, in `COMMANDS` after the `skills` entries:

```rust
    CommandSpec { needs_ui: false, ..c(&["config", "path"], &[], &[f("ghostty", "also print the Ghostty files ShellX reads")], "print the configuration file's path") },
    c(&["config", "check"], &[], &[], "check the configuration files; exit 1 on errors"),
    c(&["config", "reload"], &[], &[], "reload the configuration now"),
    c(&["config", "show"], &[], &[f("defaults", "print a commented file with every key at its default")], "print the configuration in effect and where each value comes from"),
```

and teach the completion generator the new sub-command group: in `completion_script` add `config:{}` (with `words_after(&["config"]).join(",")`) to the `subs` string, and `config` to `case "$w1" in workspace|browser|skills)` (zsh and bash) and to the PowerShell list `('workspace','browser','skills','config')`.

`term/src/api/run.rs`, in `execute` before `prepare`:

```rust
        "config path" => return config_path::print_path(p, ctx),
        "config check" | "config reload" | "config show" => return config_remote(p, ctx, &path),
```

and below `execute`:

```rust
/// A9 D39: `ui.config.*` (needs ShellX); the text is rendered by
/// [config_path::render] so it can be tested without a session.
fn config_remote(p: &Parsed, ctx: &mut Ctx, path: &str) -> Result<(), ApiError> {
    let mut api = Api::open(p, ctx)?;
    let (t, fields) = match path {
        "config check" => ("ui.config.check", vec![]),
        "config reload" => ("ui.config.reload", vec![]),
        _ => ("ui.config.show", vec![("defaults", flag(p, "defaults"))]),
    };
    let r = api.call(t, fields)?;
    let (out, code) = config_path::render(path, p.json, &output::result_json(&r));
    write!(ctx.out, "{out}").map_err(|e| ApiError::Io(e.to_string()))?;
    if code == 0 { Ok(()) } else { Err(ApiError::Exit(code)) }
}
```

In `Api::call`, map the cap: `let cap = if t.starts_with("ui.browser.") { "ui.browser" } else if t.starts_with("ui.config.") { "ui.config" } else { t };`.

`term/src/api/config_path.rs` (above the tests from Step 1):

```rust
//! A9 D39: where ShellX's configuration lives (the rule of
//! apps/desktop/lib/src/config/config_paths.dart; both test suites pin the
//! same strings) and how `shellx config …` prints.

use super::args::Parsed;
use super::client::ApiError;
use super::run::Ctx;
use super::value::{to_json, Value};
use std::io::Write;

pub struct ConfigPaths {
    pub shellx: String,
    pub ghostty: Vec<String>,
}

pub fn config_paths(env: &dyn Fn(&str) -> Option<String>, windows: bool) -> Option<ConfigPaths> {
    let sep = if windows { '\\' } else { '/' };
    let join = |base: &str, parts: &[&str]| {
        let mut s = base.trim_end_matches(['/', '\\']).to_string();
        for part in parts {
            s.push(sep);
            s.push_str(part);
        }
        s
    };
    let absolute = |p: &str| {
        if windows {
            let b = p.as_bytes();
            (b.len() >= 3 && b[1] == b':' && (b[2] == b'\\' || b[2] == b'/')) || p.starts_with(r"\\")
        } else {
            p.starts_with('/')
        }
    };
    let home = env(if windows { "USERPROFILE" } else { "HOME" }).filter(|h| !h.is_empty())?;
    let xdg = env("XDG_CONFIG_HOME").filter(|x| !x.is_empty() && absolute(x));
    let shellx_dir = match (&xdg, windows) {
        (Some(x), _) => join(x, &["shellx"]),
        (None, true) => {
            let app = env("APPDATA")
                .filter(|a| !a.is_empty())
                .unwrap_or_else(|| join(&home, &["AppData", "Roaming"]));
            join(&app, &["ShellX"])
        }
        (None, false) => join(&home, &[".config", "shellx"]),
    };
    let base = xdg.clone().unwrap_or_else(|| join(&home, &[".config"]));
    let ghostty_xdg = join(&base, &["ghostty"]);
    let mut ghostty = vec![join(&ghostty_xdg, &["config.ghostty"]), join(&ghostty_xdg, &["config"])];
    if !windows {
        let mac = join(&home, &["Library", "Application Support", "com.mitchellh.ghostty"]);
        ghostty.push(join(&mac, &["config.ghostty"]));
        ghostty.push(join(&mac, &["config"]));
    }
    Some(ConfigPaths { shellx: join(&shellx_dir, &["config"]), ghostty })
}

/// `shellx config path [--ghostty]` — local, ShellX need not run.
pub fn print_path(p: &Parsed, ctx: &mut Ctx) -> Result<(), ApiError> {
    let paths = config_paths(ctx.env, cfg!(windows))
        .ok_or_else(|| ApiError::Usage("HOME is not set".into()))?;
    if p.json {
        let v = Value::map(vec![
            ("shellx", Value::text(paths.shellx.clone())),
            ("ghostty", Value::Array(paths.ghostty.iter().map(|g| Value::text(g.clone())).collect())),
        ]);
        writeln!(ctx.out, "{}", to_json(&v)).ok();
        return Ok(());
    }
    writeln!(ctx.out, "{}", paths.shellx).ok();
    if p.has("ghostty") {
        for g in &paths.ghostty {
            writeln!(ctx.out, "{g}").ok();
        }
    }
    Ok(())
}

fn field<'a>(v: &'a Value, key: &str) -> Option<&'a Value> {
    match v {
        Value::Map(m) => m.iter().find(|(k, _)| k == key).map(|(_, v)| v),
        _ => None,
    }
}

fn text<'a>(v: &'a Value, key: &str) -> &'a str {
    field(v, key).and_then(Value::as_str).unwrap_or("")
}

/// The stdout text and exit code of `config check|reload|show` for a
/// result; with `--json` exactly one JSON object (A7 D11).
pub fn render(path: &str, json: bool, result: &Value) -> (String, i32) {
    let problems: Vec<&Value> = field(result, "problems")
        .and_then(Value::as_array)
        .map(|a| a.iter().collect())
        .unwrap_or_default();
    let errors = problems.iter().filter(|p| text(p, "severity") == "error").count();
    let code = if errors > 0 { 1 } else { 0 };
    if json {
        return (format!("{}\n", to_json(result)), code);
    }
    let mut out = String::new();
    if path == "config show" {
        if let Some(t) = field(result, "template").and_then(Value::as_str) {
            return (t.to_string(), 0);
        }
        for v in field(result, "values").and_then(Value::as_array).into_iter().flatten() {
            out.push_str(&format!("{} = {}  # {}\n", text(v, "key"), text(v, "value"), text(v, "source")));
        }
        return (out, 0);
    }
    for p in &problems {
        let line = field(p, "line").and_then(Value::as_i64).unwrap_or(0);
        let place = if line > 0 { format!("{}:{line}", text(p, "file")) } else { text(p, "file").to_string() };
        out.push_str(&format!("{place}: {}: {}\n", text(p, "severity"), text(p, "message")));
    }
    if problems.is_empty() && path == "config check" {
        out.push_str("no problems\n");
    }
    (out, code)
}
```

(If A7's `Value::as_array` returns `Option<&[Value]>` the `.iter()` calls are unchanged; if `Ctx::env` has another type, pass it the way `notify` reads `SHELLX_PANE_ID`.)

`term/src/api/skills.rs`:

```rust
pub const CONFIG_SKILL: &str = include_str!("../../../agent-skills/shellx-config/SKILL.md");

/// A9 D34: every skill `install` writes (one installer, A7 D35).
pub const SKILLS: &[(&str, &[(&str, &str)])] = &[
    ("shellx", &[("SKILL.md", SKILL), ("reference.md", REFERENCE)]),
    ("shellx-config", &[("SKILL.md", CONFIG_SKILL)]),
];
```

In `install`, replace the per-base body `let dir = base.join("shellx"); for (name, text) in [("SKILL.md", SKILL), ("reference.md", REFERENCE)] { … }` with `for (skill, files) in SKILLS { let dir = base.join(skill); for (name, text) in files.iter() { … } }` (the inner body — compare, ask, write — unchanged). In `print`, add `Some("config") | Some("shellx-config") => CONFIG_SKILL,` and change the usage message to `(SKILL.md, reference or config)`. In `args.rs` the `skills print` summary becomes `"print SKILL.md (or 'reference', 'config')"` and the `skills install` flags' help texts say "~/.claude/skills/shellx and shellx-config".

Create `agent-skills/shellx-config/SKILL.md`:

````markdown
---
name: shellx-config
description: Change ShellX for the user — fonts, colours and themes, cursor, padding, scrollback, Option-as-Alt, close confirmation, new-tab folder, keyboard shortcuts (Ghostty keybind syntax) and command-palette commands — by editing ShellX's plain-text config file and reloading it. Use when the user asks to change a ShellX shortcut, font, theme or behaviour, or to add a command to ShellX's command palette.
---

# Configuring ShellX

ShellX reads one plain-text file in Ghostty syntax: `key = value`, `#` starts a comment line. It also takes fonts and colours from the user's Ghostty config unless the file says `ghostty-config = false`.

## Steps

1. Find the file: `shellx config path` (add `--ghostty` to also list the Ghostty files ShellX reads). It may not exist yet — create it and its folder.
2. See what is in effect and where each value comes from: `shellx config show`. Every key with its default: `shellx config show --defaults`.
3. Edit by appending lines, or changing lines the user agreed to change. Later lines win; `keybind`, `command`, `snippet`, `palette` and `font-family` add up; `key =` (empty) resets a key.
4. **Never edit between** `# >>> shellx-managed keybinds >>>` and `# <<< shellx-managed keybinds <<<` — ShellX's shortcut editor owns that block, and it comes last, so it wins. Put your lines above it; if the user wants a chord that the block also sets, tell them to change it in ShellX (Command palette → "Keyboard shortcuts…").
5. Check, then apply: `shellx config check` (exit 1 = errors; each problem is printed as `file:line: severity: message`), fix what you introduced, then `shellx config reload`. ShellX also reloads by itself about a second after a save.
6. Tell the user what you changed and how to undo it (delete the line).

## Keys

| Key | Values | Default |
|---|---|---|
| `font-family` | a font name; repeat for fallbacks | JetBrains Mono |
| `font-size` | 9–28 | 13 (or the size set with Cmd/Ctrl +/−) |
| `theme` | a name (file in `themes/` next to the config, or a Ghostty theme), a path, or `light:A,dark:B` | ShellX |
| `background`, `foreground`, `cursor-color`, `selection-background` | `#RRGGBB` | ShellX colours |
| `palette` | `N=#RRGGBB`, N 0–15 | ShellX colours |
| `cursor-style` | `block`, `bar`, `underline` | `block` |
| `scrollback-limit` | 1000–100000 lines (new panes) | 10000 |
| `window-padding-x`, `window-padding-y` | `N` or `A,B`, 0–64 | 10 / 6 |
| `macos-option-as-alt` | `false`, `true`, `left`, `right` | `false` |
| `confirm-close-surface` | `true` (ask while a command runs), `false`, `always` | `true` |
| `working-directory` | `home`, `inherit`, an absolute path (new tabs) | `home` |
| `keybind` | `trigger=action` (below) | ShellX's shortcuts |
| `command`, `snippet` | `Name = text` (below) | none |
| `ghostty-config` | `true`, `false` | `true` |
| `config-file` | another file to read (relative, `~/`, `?` = optional) | — |

## Keyboard shortcuts

`keybind = <trigger>=<action>`. Modifiers: `ctrl`, `alt` (`opt`), `shift`, `super` (`cmd`). Keys: a letter or digit, `= - [ ] ; ' , . / \` `` ` ``, or a name: `enter`, `tab`, `escape`, `space`, `backspace`, `delete`, `home`, `end`, `page_up`, `page_down`, `left`, `right`, `up`, `down`, `f1`–`f24`, `comma`, `period`, `plus`, `minus`, `equal`. Two steps: `ctrl+a>c=new_tab`. `keybind = <trigger>=unbind` frees a chord; `keybind = clear` drops every default.

ShellX refuses (and `shellx config check` reports): plain keys without ctrl/alt/super (except F1–F24), F6 and Shift+F6, chords the system owns (⌘Q, ⌘Tab, ⌘Space, ⌃Space, ⌘H, ⌘M; Alt+F4, Alt+Tab, anything with the Windows key). Avoid chords the shell needs (Ctrl+C, Ctrl+D, Ctrl+R, Ctrl+A…) unless the user asks.

Actions: `new_tab`, `close_surface` (pane, or the tab when it has one pane), `close_tab`, `new_workspace`, `goto_tab:1`…`9`, `next_tab`, `previous_tab`, `new_split:right|down`, `goto_split:left|right|up|down`, `resize_split:left|right|up|down`, `toggle_split_zoom`, `equalize_splits`, `toggle_notifications`, `jump_to_unread`, `copy_to_clipboard`, `paste_from_clipboard`, `select_all`, `increase_font_size:N`, `decrease_font_size:N`, `reset_font_size`, `next_region`, `previous_region`, `open_browser`, `browser_focus_address`, `browser_reload`, `browser_back`, `browser_forward`, `browser_stop`, `reload_config`, `open_config`, `toggle_command_palette`, `show_shortcuts`, `show_config_problems`, `run_command:<Name>`, `text:<Zig string>`, `csi:<…>`, `esc:<…>`, `ignore`, `unbind`.

## Commands and snippets

`command = Lint = npm run lint` appears in ShellX's command palette (⌘⇧P / Ctrl+Shift+P) and runs in the focused pane (pasted, then Enter). `snippet = Name = text` pastes without Enter. Quote the text to use escapes: `snippet = Status = "git status\n"`. Give one a key: `keybind = super+shift+l=run_command:Lint`.

## Etiquette

- Ask before changing a line the user wrote; prefer appending.
- Keep defaults unless asked.
- Never leave errors: run `shellx config check` after every edit.
````

In `agent-skills/shellx/SKILL.md` add one line under its "Rules" (A7 Task 10): `To change ShellX itself (shortcuts, fonts, themes, palette commands) use the shellx-config skill.` In `agent-skills/shellx/reference.md` add a `config` section in `COMMANDS` order: the four usages, flags, the JSON shapes of `check`/`reload` (`{"problems":[{"file","line","severity","code","key"?,"message"}],"generation"}`) and `show` (`{"values":[{"key","value","source"}],"files":{"shellx","ghostty":[…]}}` or `{"template"}`), exit codes (check/reload: 1 with errors; 3 when ShellX is not running except `config path`; 7 on a ShellX older than A9).

- [ ] **Step 5: Run the tests**

Run: `cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/cli/ && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test && cd ../../packages/shellx_agent && ~/fvm/versions/3.41.4/bin/dart test && cd ../../term && ~/.cargo/bin/cargo test --features test-hooks && ~/.cargo/bin/cargo fmt --check && ~/.cargo/bin/cargo clippy --all-targets -- -D warnings`
Expected: PASS everywhere; A7's contract suite (`cli_api_contract_test`) still green with the new cap.

- [ ] **Step 6: ⚠ MANUAL**

macOS + Windows, inside a ShellX pane: `shellx config path` prints the path of D3; `echo 'font-size = to' >> "$(shellx config path)"` → `shellx config check` exits 1 with `…/config:N: error: font-size: “to” is not valid (expected 9–28)`; fix the line → `shellx config reload` exits 0 and the window updates; `shellx config show | grep font-size` shows the source line. `shellx skills install --claude` installs `~/.claude/skills/shellx-config/SKILL.md`; in Claude Code: "make ⌘⇧T split down in ShellX" → it appends a `keybind` line, runs `config check` and `reload`, and does not touch the managed block. Record in the ledger.

- [ ] **Step 7: Commit**

```bash
git add packages/shellx_agent/lib/src/mux/cli_wire.dart apps/desktop/lib/src/config/config_show.dart apps/desktop/lib/src/cli/ui_command_handler.dart apps/desktop/test/cli/ui_command_handler_config_test.dart term/src/api agent-skills
git commit -m "feat: shellx config path/check/reload/show over ui.config.*, CLI new tabs follow working-directory, shellx-config agent skill installed by the A7 installer (A9 D21, D34, D39, D40)"
```

---

### Task 14: HANDOFF, manual verification, final check (D43, D46, every ⚠)

**Files:**
- Modify: `docs/superpowers/HANDOFF.md` (new section "§18 A9 — cấu hình, phím tắt, bảng lệnh"), `docs/superpowers/ledgers/a1-desktop-terminal.md` (section `## A9 (config) — execution`)

- [ ] **Step 1: HANDOFF §18**

Add, in the style of A3–A7's HANDOFF sections: where the files live (D3/D4), the key table (spec §3.1), how to reload (⌘⇧, / Ctrl+Shift+, / `shellx config reload` / automatic), the command palette, the shortcut editor and its managed block, how problems are shown, `shellx config …`, the `shellx-config` skill, and the manual checklist below.

- [ ] **Step 2: ⚠ MANUAL checklist (macOS 13+ and Windows 10 1809+/11)**

Run every item; record pass/fail with the date in the ledger section:

1. Criterion 1: no file → screenshots before/after A9 identical; ⌘T/⌘D/⌘W/⌘1/⌘⇧U/⌘⇧I/⌘+ behave as before; Windows Ctrl+Shift+T/D, Ctrl+Alt+1.
2. Criterion 2: `font-size = 16` saved from TextEdit / Notepad → applies in ≤ 1.5 s; `tput cols` correct in every pane; `vim` redraws.
3. Criterion 3 (macOS): Ghostty installed with `theme = Dracula` and `font-family = Fira Code` in `~/.config/ghostty/config` → first start shows them and the one-time notice; `ghostty-config = false` reverts.
4. Criterion 4: a broken file (`font-size = to`, `keybind = super+q=new_tab`, a half-saved line) → toast, panel lists file/line; sessions keep running; fixing the file clears the toast.
5. Criterion 5: `keybind = super+shift+t=new_split:down`, `super+d=unbind`, `ctrl+a>c=new_tab` (indicator, VoiceOver announcement, ⌃A ⌃A sends ⌃A to `cat -v`).
6. Criterion 6 (Windows, German and Polish layouts): AltGr+Q types `@`, AltGr+digits type `{ [ ] }` with chords bound on Ctrl+Alt; left Ctrl+Alt runs them.
7. Criterion 7: palette with VoiceOver/Narrator; Telex in the search field; `command = …` runs in the focused pane; a browser pane focused → runs in the tab's terminal pane.
8. Criterion 8: shortcut editor on a symlinked, CRLF, BOM file; conflict/replace; reset.
9. Criterion 9: `shellx config …` in a ShellX pane; `shellx skills install`; Claude Code adds a keybind with the skill.
10. Criterion 10: keyboard-only pass through palette, problems panel, shortcut editor; F6/Shift+F6 never recordable; Esc/Tab never trapped.
11. D15: a light theme (`theme` = Solarized Light from Ghostty) → focus outline visible on split panes; chrome stays dark; `lowContrast` warning shown.
12. D19: Option-as-Alt in `emacs -nw`, zsh word moves.
13. D46: ⌘, opens the file (not swallowed by the app menu).
14. Performance (D42): a 1,000-line config file (`for i in $(seq 1000); do echo "keybind = ctrl+alt+shift+f12=new_tab"; done`) reloads in ≤ 20 ms (Dart DevTools timeline or a `Stopwatch` debug print removed after).

- [ ] **Step 3: Final verification**

```bash
cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter analyze && dart format --set-exit-if-changed lib test && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test && cd ../..
cd packages/shellx_agent && ~/fvm/versions/3.41.4/bin/dart test && cd ../..
cd term && ~/.cargo/bin/cargo test --features test-hooks && ~/.cargo/bin/cargo clippy --all-targets -- -D warnings && cd ..
cd apps/mobile && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test && cd ../..
git diff main --stat -- packages/shellx_core/lib/src/protocol apps/mobile relay term/src/proto term/shell
```

Expected: everything green, counts ≥ baseline + the new tests; the last command prints nothing (phone protocol, mobile, relay, terminal-sharing link untouched). The branch merges only after every ⚠ item is recorded as passed.

- [ ] **Step 4: Commit**

```bash
git add docs/superpowers/HANDOFF.md docs/superpowers/ledgers/a1-desktop-terminal.md
git commit -m "docs: A9 handoff — configuration, shortcuts, palette, CLI; manual checklist results"
```

---

## Self-review notes (for the executor)

- **Spec coverage:** D1 → Prerequisite; D2/D5/D6 → Task 1; D3/D4/D7/D11–D21/D35 → Task 2 (values), Tasks 6–7 (applied), D4 notice → Tasks 5, 10; D8/D10 → Tasks 1, 5; D9 → Task 5 (watcher), Task 8 (⌘⇧,), Task 10 (tray), Task 13 (CLI); D13–D15 → Tasks 3, 6; D16/D18 → Tasks 2, 6; D17/D19–D21 → Task 7 (D21 over the CLI: Task 13); D22–D27 → Task 4 (D26 in the window: Task 8; in sequences: Task 9); D28 → Task 9; D29/D30 → Task 8; D31 → Tasks 4, 7, 8; D32 → Task 12; D33 → Task 11; D34 → Tasks 11 (commands), 13 (skill); D36 → Task 10; D37 → Task 8 (+ palette/tray entries in Tasks 10–11); D38 → no migration code by design (Task 6 keeps `terminal_font_size`); D39/D40 → Task 13 (+ logging rule in every task); D41 → Task 5 (UI-only controller); D42 → Task 14 ⚠; D43 → Tasks 8, 12, 14 ⚠; D44 → Tasks 9, 11, 12; D45 → Task 10; D46 → Task 8 ⚠.
- **Criteria:** 1 → golden fixtures (Task 4) + appearance defaults (Task 6); 2 → Tasks 5–6; 3 → Tasks 2, 3, 5, 10; 4 → Tasks 1, 5, 10; 5 → Tasks 4, 8, 9; 6 → Task 8; 7 → Task 11; 8 → Task 12; 9 → Task 13; 10 → Tasks 9–12; 11 → every task's full-suite run.
- **Names used across tasks:** `ConfigProblem`/`ConfigProblemCode`/`ConfigSeverity`/`configProblemEnglish`, `ConfigEntry`/`parseConfigText`/`decodeConfigBytes`/`decodeZigString`, `ConfigFs`/`FileStamp`/`loadConfigChain`/`expandConfigPath` (Task 1); `ConfigPaths`/`configPathsFor`, `parseConfigColor`/`contrastRatio`, `ShellxConfig`/`buildShellxConfig`/`ghosttyEnabled`/`kGhosttyKeys`/`KeybindEntry`/`UserCommand`/`OptionAsAlt`/`ConfirmClose`/`WorkingDirectoryKind` (Task 2); `ResolvedTheme`/`resolveTheme`/`focusOutlineFor` (Task 3); `KeyChord`/`parseKeyChord`/`chordLabel`/`sequenceLabel`/`chordConfigText`/`chordActivator`/`chordOfEvent`, `KeyAction`/`kActionSpecs`/`parseKeyAction`/`intentForAction`/`describeIntent`, `KeyBinding`/`KeyBindings`/`defaultKeyBindings`/`resolveKeyBindings`/`checkTrigger`/`splitKeybind`/`labelBindings` (Task 4); `ConfigWatcher`, `ConfigState`/`ConfigLoad`/`ConfigController`/`shellxConfigProvider`/`configFsProvider`/`configPathsProvider`/`configPlatformProvider` (Task 5); `TerminalAppearance`/`terminalAppearanceProvider`, `FontProbe`/`fontProbeProvider`/`fontProblems`/`kFontProblemCodes` (Task 6); `OptionAsAltInputHandler`/`desktopInputHandlerWith`, `DesktopTerminal.sendUserText`, `TerminalTabs.newTabCwd`, `runUserCommand`/`sendTextToFocused`/`CommandRun` (Task 7); `configTemplate`, `ConfigFileOpener`/`configFileOpenerProvider`/`openShellxConfig`, `actionShortcutLabel` (Task 8); `keySequenceProvider`/`KeySequence`/`prefixText`/`SequenceIndicator` (Task 9); `problemText`/`problemLocation`/`severityText`, `ConfigUiRequest`/`configUiRequestProvider`, `ConfigProblemsPanel`, `A9Overlay`/`openOverlay`/`closeOverlay` (Task 10); `actionLabel`/`actionVariants`, `foldForSearch`/`matchScore`/`PaletteEntry`/`paletteEntries`/`filterPalette`/`CommandPalette`/`Keycaps` (Task 11); `applyBindingEdits`/`managedLineRange`/`AddBinding`/`RemoveBinding`/`ResetAction`/`ConfigFileStore`/`ConfigFileWriter`/`defaultChordsOf`, `ShortcutsSheet` (Task 12); `configShowValues`, `CliType.uiConfig*`, Rust `config_path::{config_paths, print_path, render}`, `skills::{CONFIG_SKILL, SKILLS}`, `ApiError::Exit` (Task 13).
- **Where this plan names A3–A7 internals** (`FakeLocalSessions.addSession/setCwd/setRunning`, A6's browser pane view and its state provider, A6's fake engine recording, A7's `skills` test helpers, `Value::as_array`'s exact type, `Ctx::env`), look the real name up in that plan's Interfaces block or the merged code before inventing one; record any rename in the ledger.
- **Known judgement calls an executor may question** (all are spec decisions, do not re-decide): Ghostty layer on by default (D4); a font-size in the file stops ⌘+/− from persisting (D12); `text:` bypasses paste filtering (D31); the managed block is the only place the app writes (D32); plain F-keys bindable, plain letters not (D25).
