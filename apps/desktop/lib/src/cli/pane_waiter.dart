import 'dart:async';

import 'package:shellx_agent/shellx_agent.dart';
import 'package:xterm/xterm.dart';

import 'pane_text.dart';

/// What a wait needs to know about one terminal pane.
abstract interface class PaneProbe {
  /// The shell reported a cwd (OSC 7): its hooks run (A2 C1).
  bool get hooked;

  /// A4 `runningCommand`.
  bool get running;
  bool get exited;
  int? get exitCode;

  /// Fires after the pane's terminal received output.
  Stream<void> get output;

  /// Fires when [hooked]/[running]/[exited] may have changed.
  Stream<void> get changes;
  Terminal get terminal;
}

/// The client that asked went away (D21); nobody reads this answer.
const kWaitCancelled = 'cancelled';

const _unhookedQuiet = Duration(seconds: 2);
const _matchThrottle = Duration(milliseconds: 100);
const _matchMaxLines = 2000;
const _matchMaxChars = 262144;

const _exited = CliFailure(CliError.exited, 'the pane exited');

typedef _Done = Completer<Map<String, Object?>>;

/// Ends at [timeout] (`timeout`), when [cancelled] completes, or when
/// [arm]'s watchers complete `done`; then everything [arm] set up goes
/// (the cleanup it returns).
Future<Map<String, Object?>> _race(
  Duration timeout,
  Future<void>? cancelled,
  void Function() Function(_Done done) arm,
) {
  final done = _Done();
  void cancel() {
    if (!done.isCompleted) {
      done.completeError(
        const CliFailure(kWaitCancelled, 'the client went away'),
      );
    }
  }

  final timer = Timer(timeout, () {
    if (!done.isCompleted) {
      done.completeError(const CliFailure(CliError.timeout, 'timed out'));
    }
  });
  cancelled?.then<void>((_) => cancel(), onError: (Object _) => cancel());
  final cleanup = arm(done);
  return done.future.whenComplete(() {
    timer.cancel();
    cleanup();
  });
}

void Function() _cancelAll(List<StreamSubscription<void>> subs) => () {
  for (final s in subs) {
    unawaited(s.cancel());
  }
};

/// D21 idle: a hooked shell runs no command and printed nothing for
/// [quiet]; a shell without hooks printed nothing for 2 s. Only output, or
/// a change of what the shell does, starts the quiet time again.
Future<Map<String, Object?>> waitIdle(
  PaneProbe p, {
  required Duration quiet,
  required Duration timeout,
  Future<void>? cancelled,
}) => _race(timeout, cancelled, (done) {
  Timer? q;
  bool busy() => p.hooked && p.running;
  void arm() {
    q?.cancel();
    q = null;
    if (busy()) return;
    q = Timer(p.hooked ? quiet : _unhookedQuiet, () {
      if (!done.isCompleted && !p.exited && !busy()) done.complete(const {});
    });
  }

  var was = (p.hooked, busy());
  bool gone() {
    if (!p.exited) return false;
    if (!done.isCompleted) done.completeError(_exited);
    return true;
  }

  final subs = [
    p.output.listen((_) {
      if (!gone()) arm();
    }),
    p.changes.listen((_) {
      if (gone()) return;
      final now = (p.hooked, busy());
      if (now == was) return;
      was = now;
      arm();
    }),
  ];
  if (!gone()) arm();
  final cancelSubs = _cancelAll(subs);
  return () {
    q?.cancel();
    cancelSubs();
  };
});

/// D21 exit: `{exitCode}` once the session ended.
Future<Map<String, Object?>> waitExit(
  PaneProbe p, {
  required Duration timeout,
  Future<void>? cancelled,
}) => _race(timeout, cancelled, (done) {
  void check() {
    if (!done.isCompleted && p.exited) done.complete({'exitCode': p.exitCode});
  }

  final subs = [p.changes.listen((_) => check())];
  check();
  return _cancelAll(subs);
});

/// D21 match: [re] on the last 2000 logical lines (≤ 256 KiB) now and
/// after output, at most every 100 ms; with [fromNow] only the lines from
/// the cursor's row at the start on. `{match, line}`.
Future<Map<String, Object?>> waitMatch(
  PaneProbe p,
  RegExp re, {
  required bool fromNow,
  required Duration timeout,
  Future<void>? cancelled,
}) {
  final start = p.terminal.buffer;
  // Follows its row as the scrollback moves; gone once the row left it.
  final anchor = fromNow ? start.createAnchorFromCursor() : null;
  return _race(timeout, cancelled, (done) {
    Timer? pending;
    void scan() {
      pending = null;
      if (done.isCompleted) return;
      final buffer = p.terminal.buffer;
      int? from;
      if (anchor != null) {
        // Another buffer (the alt screen) holds only what came after.
        from = identical(buffer, start) && anchor.attached ? anchor.y : 0;
      }
      final lines = logicalLines(buffer, last: _matchMaxLines, fromRow: from);
      var text = lines.join('\n');
      if (text.length > _matchMaxChars) {
        final cut = text.indexOf('\n', text.length - _matchMaxChars);
        text = cut < 0
            ? text.substring(text.length - _matchMaxChars)
            : text.substring(cut + 1);
      }
      final m = re.firstMatch(text);
      if (m != null) {
        final lineStart = text.lastIndexOf('\n', m.start) + 1;
        final lineEnd = text.indexOf('\n', m.end);
        done.complete({
          'match': m.group(0),
          'line': text.substring(
            lineStart,
            lineEnd < 0 ? text.length : lineEnd,
          ),
        });
      } else if (p.exited) {
        done.completeError(_exited);
      }
    }

    void soon() {
      pending ??= Timer(_matchThrottle, scan);
    }

    final subs = [
      p.output.listen((_) => soon()),
      p.changes.listen((_) => soon()),
    ];
    soon();
    final cancelSubs = _cancelAll(subs);
    return () {
      pending?.cancel();
      anchor?.dispose();
      cancelSubs();
    };
  });
}

/// D16: types `--cmd` (pasted, then Enter) once the new shell is ready:
/// when it first reports a cwd (its first prompt), or, for a shell without
/// hooks, after 1.5 s without output; at the latest after 5 s. Nothing is
/// typed into a shell that already ended.
final class CommandInjector {
  CommandInjector(this._probe, this._paste);
  final PaneProbe Function(int pane) _probe;
  final void Function(int pane, String text) _paste;

  static const quiet = Duration(milliseconds: 1500);
  static const cap = Duration(seconds: 5);

  void inject(int pane, String cmd) {
    final p = _probe(pane);
    final subs = <StreamSubscription<void>>[];
    Timer? q;
    Timer? capTimer;
    var sent = false;
    void send() {
      if (sent) return;
      sent = true;
      q?.cancel();
      capTimer?.cancel();
      _cancelAll(subs)();
      if (!p.exited) _paste(pane, cmd);
    }

    if (p.hooked || p.exited) {
      send();
      return;
    }
    capTimer = Timer(cap, send);
    subs
      ..add(
        p.changes.listen((_) {
          if (p.hooked || p.exited) send();
        }),
      )
      ..add(
        p.output.listen((_) {
          q?.cancel();
          q = Timer(quiet, send);
        }),
      );
  }
}
