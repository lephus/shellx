import 'dart:async';

import '../../l10n/app_localizations.dart';
import 'notifier.dart';

/// Tells the user when processes of a terminal session may be left running
/// (`FlutterPtyFactory.onProblem`: a tree kill failed, or on Windows a shell
/// runs without a job object).
///
/// Coalesces bursts — closing every session after `ps` broke fails every
/// kill at once: the first problem opens a [window], and one notification
/// then lists each pid reported during it. The notification holds pids only;
/// the reason stays in the debug log (`onError`). Never throws.
final class TerminalProblemNotifier {
  TerminalProblemNotifier({
    required SystemNotifier notifier,
    required AppLocalizations l10n,
    this.window = const Duration(seconds: 3),
  }) : _notifier = notifier,
       _l10n = l10n;

  final SystemNotifier _notifier;
  final AppLocalizations _l10n;
  final Duration window;
  final Set<int> _pids = <int>{};
  Timer? _timer;

  void report(int pid) {
    _pids.add(pid);
    _timer ??= Timer(window, _flush);
  }

  void _flush() {
    _timer = null;
    final pids = _pids.toList();
    _pids.clear();
    if (pids.isNotEmpty) unawaited(_show(pids));
  }

  Future<void> _show(List<int> pids) async {
    try {
      await _notifier.show(
        title: _l10n.notifyTerminalProblemTitle,
        body: _l10n.notifyTerminalProblemBody(pids.length, pids.join(', ')),
      );
    } catch (_) {
      // Best effort: the problem is in the debug log already.
    }
  }
}
