import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/config/config_problem.dart';
import 'package:shellx_desktop/src/config/config_syntax.dart';
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
}
