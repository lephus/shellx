import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/config/config_key_edits.dart';
import 'package:shellx_desktop/src/config/config_problem.dart';
import 'package:shellx_desktop/src/config/config_show.dart';
import 'package:shellx_desktop/src/config/config_state.dart';
import 'package:shellx_desktop/src/config/config_syntax.dart';
import 'package:shellx_desktop/src/config/config_theme.dart';
import 'package:shellx_desktop/src/config/keybindings.dart';
import 'package:shellx_desktop/src/config/setting_validation.dart';
import 'package:shellx_desktop/src/config/settings_schema.dart';
import 'package:shellx_desktop/src/config/shellx_config.dart';
import 'package:flutter/foundation.dart' show TargetPlatform;

({bool ok, ConfigProblem? problem}) v(String key, String raw) =>
    validateSetting(key, raw, macos: true, home: '/Users/me');

void main() {
  test('good values pass', () {
    for (final (k, r) in [
      ('font-size', '15'),
      ('cursor-style', 'bar'),
      ('background', '#ff0000'),
      ('working-directory', '/tmp'),
      ('working-directory', 'inherit'),
      ('window-padding-x', '10,20'),
      ('adjust-cell-height', '15%'),
      ('font-size', ''),
    ]) {
      expect(v(k, r).ok, isTrue, reason: '$k = $r');
    }
  });

  test('what the loader flags is refused, with its own problem', () {
    expect(v('font-size', 'abc').problem!.code, ConfigProblemCode.badValue);
    expect(v('font-size', '99').problem!.code, ConfigProblemCode.outOfRange);
    expect(v('cursor-style', 'wavy').problem!.code, ConfigProblemCode.badValue);
    expect(
      v('scrollback-limit', '500').problem!.code,
      ConfigProblemCode.outOfRange,
    );
    expect(v('background', 'red').problem!.code, ConfigProblemCode.badValue);
    expect(
      v('working-directory', 'relative/path').problem!.code,
      ConfigProblemCode.badValue,
    );
    expect(v('adjust-cell-height', '90%').ok, isFalse);
    expect(v('no-such-key', '1').ok, isFalse);
  });

  test('a value with a line break would write a second line: refused', () {
    expect(v('font-family', 'A\nkeybind = x=ignore').ok, isFalse);
    expect(v('font-family', 'A\rB').ok, isFalse);
  });

  test('an info note (a value ShellX cannot draw) is not a refusal', () {
    expect(v('cursor-style', 'block_hollow').ok, isTrue);
  });

  test('the platform decides: option-as-alt off the Mac is only a note', () {
    expect(
      validateSetting(
        'macos-option-as-alt',
        'true',
        macos: false,
        home: '/home/me',
      ).ok,
      isTrue,
    );
  });

  test('Windows paths go through the same rule', () {
    expect(
      validateSetting(
        'working-directory',
        r'C:\Users\me',
        macos: false,
        home: r'C:\Users\me',
        windows: true,
      ).ok,
      isTrue,
    );
    expect(
      validateSetting(
        'working-directory',
        '/tmp',
        macos: false,
        home: r'C:\Users\me',
        windows: true,
      ).ok,
      isFalse,
    );
  });

  group('round trip: every catalogue sample, written then loaded', () {
    final samples = [
      for (final d in kSettings)
        for (final s in d.sampleValues) (d, s),
    ];

    test('every file setting has at least one sample', () {
      for (final d in kSettings.where((d) => d.fileKey != null)) {
        expect(d.sampleValues, isNotEmpty, reason: d.id);
      }
    });

    for (final (d, s) in samples) {
      test('${d.fileKey} = ${s.raw}', () {
        final key = d.fileKey!;
        final text = applyKeyEdits('', [SetKey(key, s.raw)]);
        final entries = parseConfigText(text, file: '/c', problems: []);
        final problems = <ConfigProblem>[];
        final config = buildShellxConfig(
          ghostty: const [],
          shellx: entries,
          problems: problems,
          macos: true,
          home: '/Users/me',
        );
        expect(problems, isEmpty);
        expect(config.origins[key]?.value, s.raw);
        if (s.shown != null) {
          final state = ConfigState(
            config: config,
            theme: ResolvedTheme.defaults,
            bindings: KeyBindings.defaults(TargetPlatform.macOS),
            loadProblems: const [],
            generation: 1,
            files: const [],
            ghosttyUsed: false,
          );
          final row = configShowValues(
            state,
          ).firstWhere((r) => r['key'] == key);
          expect(row['value'], s.shown);
        }
        expect(
          validateSetting(key, s.raw, macos: true, home: '/Users/me').ok,
          isTrue,
        );
      });
    }
  });
}
