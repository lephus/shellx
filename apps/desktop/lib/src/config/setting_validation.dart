import 'config_problem.dart';
import 'config_syntax.dart';
import 'shellx_config.dart';

/// A11 D6: the one validator is the loader. [raw] goes through the real
/// [buildShellxConfig] as a line of the ShellX file; whatever it flags
/// (an error, a warning such as a clamped number or an unknown key) is
/// refused. An `info` note (a value ShellX accepts but cannot draw) is fine.
///
/// An empty [raw] is a reset and always passes. [raw] with a line break is
/// refused: it would write a second line.
({bool ok, ConfigProblem? problem}) validateSetting(
  String key,
  String raw, {
  required bool macos,
  required String home,
  bool windows = false,
}) {
  final value = raw.trim();
  if (value.contains(RegExp(r'[\r\n]'))) {
    return (
      ok: false,
      problem: ConfigProblem(
        file: '<settings>',
        line: 1,
        severity: ConfigSeverity.error,
        code: ConfigProblemCode.badValue,
        key: key,
      ),
    );
  }
  final problems = <ConfigProblem>[];
  buildShellxConfig(
    ghostty: const [],
    shellx: [ConfigEntry(file: '<settings>', line: 1, key: key, value: value)],
    problems: problems,
    macos: macos,
    home: home,
    windows: windows,
  );
  final bad = problems
      .where((p) => p.key == key && p.severity != ConfigSeverity.info)
      .firstOrNull;
  return (ok: bad == null, problem: bad);
}
