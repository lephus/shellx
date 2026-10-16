import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/config/config_problem.dart';
import 'package:shellx_desktop/src/config/config_syntax.dart';
import 'package:shellx_desktop/src/config/font_probe.dart';
import 'package:shellx_desktop/src/config/shellx_config.dart';

final class FakeProbe implements FontProbe {
  FakeProbe(this.answers);
  final Map<String, ({bool found, bool monospace})> answers;
  final probed = <String>[];
  @override
  ({bool found, bool monospace}) probe(String family) {
    probed.add(family);
    return answers[family] ?? (found: true, monospace: true);
  }
}

ShellxConfig _config(String text) => buildShellxConfig(
  ghostty: const [],
  shellx: parseConfigText(text, file: '/c', problems: []),
  problems: [],
  macos: true,
  home: '/h',
);

void main() {
  test('missing and proportional fonts are warnings at their lines (D11)', () {
    final config = _config(
      'font-family = Nope\nfont-family = Helvetica\nfont-family = Menlo\n',
    );
    final problems = fontProblems(
      config,
      FakeProbe({
        'Nope': (found: false, monospace: true),
        'Helvetica': (found: true, monospace: false),
      }),
    );
    expect(
      [for (final p in problems) (p.file, p.line, p.code, p.severity, p.value)],
      [
        (
          '/c',
          1,
          ConfigProblemCode.fontNotFound,
          ConfigSeverity.warning,
          'Nope',
        ),
        (
          '/c',
          2,
          ConfigProblemCode.fontNotMonospace,
          ConfigSeverity.warning,
          'Helvetica',
        ),
      ],
    );
    expect(problems.every((p) => p.key == 'font-family'), isTrue);
  });

  test('a probe that throws reports nothing', () {
    expect(fontProblems(_config('font-family = X\n'), _Throwing()), isEmpty);
  });

  test('no families: nothing probed', () {
    final probe = FakeProbe(const {});
    expect(fontProblems(_config(''), probe), isEmpty);
    expect(probe.probed, isEmpty);
  });

  testWidgets('the engine probe finds the bundled font and not a made-up one', (
    tester,
  ) async {
    const probe = TextPainterFontProbe();
    // The test engine has no system fonts: an unknown family lays out like
    // the made-up one; Flutter's test font is not the made-up one.
    expect(probe.probe('ShellX-Surely-Missing-Family').found, isFalse);
    expect(probe.probe('ShellX-Surely-Missing-Family').monospace, isTrue);
  });
}

final class _Throwing implements FontProbe {
  @override
  ({bool found, bool monospace}) probe(String family) => throw StateError('x');
}
