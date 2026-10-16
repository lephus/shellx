import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shellx_agent/shellx_agent.dart';

import '../config/config_controller.dart';
import '../config/config_problem.dart';
import '../config/config_show.dart';
import '../config/config_template.dart';

/// A9 D39: the `ui.config.*` requests (`shellx config check|reload|show`).
/// They take no target, so they set no Agent mark (A7 D27), and like every
/// `ui.*` they only get here when the client may use the API and
/// `cli_control_enabled` is on (A7 D26; both checked by `CliHost`).
///
/// Answers carry problem fields (file, line, code, key, message) and the
/// values in effect; never the text of a file (D40). Nothing is logged.
final class ConfigCommands {
  ConfigCommands(this._ref);
  final Ref _ref;

  ConfigController get _config => _ref.read(shellxConfigProvider.notifier);

  Map<String, Object?> _problems(List<ConfigProblem> list, int generation) => {
    'problems': [
      for (final p in list)
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

  /// The problems of the files as they are now; nothing is applied.
  Future<Map<String, Object?>> check() async => _problems(
    await _config.check(),
    _ref.read(shellxConfigProvider).generation,
  );

  /// Loads now (as ⌘⇧, does) and answers with the new problems.
  Future<Map<String, Object?>> reload() async {
    final s = await _config.load(manual: true);
    return _problems(s.problems, s.generation);
  }

  Future<Map<String, Object?>> show(MuxMessage r) async {
    final state = _ref.read(shellxConfigProvider);
    if (r.fields['defaults'] == true) {
      return {'template': shellxTemplate(_ref.read)};
    }
    final paths = _ref.read(configPathsProvider);
    return {
      'values': configShowValues(state),
      'files': {
        'shellx': paths.shellx,
        'ghostty': [
          for (final f in paths.ghostty)
            if (state.ghosttyUsed && state.files.contains(f)) f,
        ],
      },
    };
  }
}
