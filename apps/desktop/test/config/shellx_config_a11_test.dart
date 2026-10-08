import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/config/config_problem.dart';
import 'package:shellx_desktop/src/config/config_syntax.dart';
import 'package:shellx_desktop/src/config/keybind_trigger.dart';
import 'package:shellx_desktop/src/config/shellx_config.dart';

({ShellxConfig config, List<ConfigProblem> problems}) build(
  Map<String, String> kv,
) {
  final problems = <ConfigProblem>[];
  var n = 0;
  final config = buildShellxConfig(
    ghostty: const [],
    shellx: [
      for (final e in kv.entries)
        ConfigEntry(file: '/c', line: ++n, key: e.key, value: e.value),
    ],
    problems: problems,
    macos: true,
    home: '/Users/me',
  );
  return (config: config, problems: problems);
}

void main() {
  test('adjust-cell-height takes N% or N, −10…50, default 0', () {
    expect(build({'adjust-cell-height': '15%'}).config.cellHeightPercent, 15);
    expect(build({'adjust-cell-height': '15'}).config.cellHeightPercent, 15);
    expect(build({'adjust-cell-height': '-5%'}).config.cellHeightPercent, -5);
    expect(build({}).config.cellHeightPercent, 0);
    expect(build({'adjust-cell-height': ''}).config.cellHeightPercent, 0);
  });

  test('adjust-cell-height out of range is clamped with a note; junk is an '
      'error', () {
    final r = build({'adjust-cell-height': '90%'});
    expect(r.config.cellHeightPercent, 50);
    expect(r.problems.single.code, ConfigProblemCode.outOfRange);
    expect(
      build({'adjust-cell-height': 'tall'}).problems.single.code,
      ConfigProblemCode.badValue,
    );
  });

  test('cursor-style-blink is supported now: true blinks, no unsupported '
      'note', () {
    final r = build({'cursor-style-blink': 'true'});
    expect(r.config.cursorBlink, isTrue);
    expect(r.problems, isEmpty);
    expect(build({}).config.cursorBlink, isFalse);
    expect(
      build({'cursor-style-blink': 'maybe'}).problems.single.code,
      ConfigProblemCode.badValue,
    );
  });

  test('cursor-style-blink in a Ghostty file is still ignored', () {
    expect(kGhosttyKeys.contains('cursor-style-blink'), isFalse);
  });

  test('font-feature is accepted with an info note: no ligatures', () {
    final r = build({'font-feature': '-calt'});
    expect(r.problems.single.severity, ConfigSeverity.info);
    expect(r.problems.single.code, ConfigProblemCode.unsupportedValue);
  });

  group('global-hotkey (A11 D22)', () {
    test('needs a modifier; shift alone is refused; ctrl+space (input '
        'source) is reserved', () {
      expect(
        build({'global-hotkey': 'j'}).problems.single.code,
        ConfigProblemCode.plainKeyTrigger,
      );
      expect(
        build({'global-hotkey': 'shift+j'}).problems.single.code,
        ConfigProblemCode.plainKeyTrigger,
      );
      // A function key passes the keybind rule without a modifier; a global
      // key must have one.
      expect(
        build({'global-hotkey': 'f5'}).problems.single.code,
        ConfigProblemCode.plainKeyTrigger,
      );
      expect(
        build({'global-hotkey': 'ctrl+space'}).problems.single.code,
        ConfigProblemCode.reservedTrigger,
      );
      expect(
        build({'global-hotkey': 'ctrl+alt+j'}).config.globalHotkey,
        parseKeyChord('ctrl+alt+j'),
      );
      expect(build({}).config.globalHotkey, isNull);
      expect(build({}).problems, isEmpty);
    });

    test('junk, a sequence and a key with no spelling are bad values; the '
        'chord is dropped', () {
      for (final v in ['', 'ctrl+alt', 'ctrl+a>b', 'ctrl+alt+nonsense']) {
        final r = build({'global-hotkey': v});
        expect(r.config.globalHotkey, isNull, reason: v);
        if (v.isNotEmpty) {
          expect(r.problems.single.code, ConfigProblemCode.badValue, reason: v);
        } else {
          expect(r.problems, isEmpty);
        }
      }
    });

    test('an empty value resets; the last line wins', () {
      final problems = <ConfigProblem>[];
      final config = buildShellxConfig(
        ghostty: const [],
        shellx: const [
          ConfigEntry(
            file: '/c',
            line: 1,
            key: 'global-hotkey',
            value: 'ctrl+alt+j',
          ),
          ConfigEntry(file: '/c', line: 2, key: 'global-hotkey', value: ''),
        ],
        problems: problems,
        macos: true,
        home: '/Users/me',
      );
      expect(config.globalHotkey, isNull);
      expect(problems, isEmpty);
    });

    test('Ghostty files cannot set it', () {
      expect(kGhosttyKeys.contains('global-hotkey'), isFalse);
    });

    test('on Windows the Win key is reserved like in keybinds', () {
      final problems = <ConfigProblem>[];
      buildShellxConfig(
        ghostty: const [],
        shellx: const [
          ConfigEntry(
            file: '/c',
            line: 1,
            key: 'global-hotkey',
            value: 'super+j',
          ),
        ],
        problems: problems,
        macos: false,
        home: r'C:\Users\me',
        windows: true,
      );
      expect(problems.single.code, ConfigProblemCode.reservedTrigger);
    });
  });
}
