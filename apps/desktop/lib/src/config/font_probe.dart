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
    const samples = ['iiiiiiiiii', 'MMMMMMMMMM', 'Wg0@#&'];
    final found = samples.any((s) => _width(family, s) != _width(_missing, s));
    final monospace = _width(family, samples[0]) == _width(family, samples[1]);
    return (found: found, monospace: monospace);
  }
}

final fontProbeProvider = Provider<FontProbe>(
  (ref) => const TextPainterFontProbe(),
);

/// The codes [fontProblems] owns in `reportRuntimeProblems`.
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
      continue; // D11: a probe failure never becomes a problem
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
