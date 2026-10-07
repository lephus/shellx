import 'dart:async';

import 'package:shellx_agent/shellx_agent.dart';
import 'package:xterm/xterm.dart';

import 'match_scanner.dart';
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

const _unhookedQuiet = Duration(seconds: 2);
const _matchThrottle = Duration(milliseconds: 100);
const _matchMaxLines = 2000;
const _matchMaxChars = 262144;

/// Final ruling I1: `match` and `line` of a `wait --match` answer are at
/// most this many UTF-16 code units each (well under the 64 KiB frame).
const kMatchAnswerMaxUnits = 4096;

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
        const CliFailure(CliError.cancelled, 'the client went away'),
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

/// D21 match: [scanner] (the client's pattern, off the UI isolate) on the
/// last 2000 logical lines (≤ 256 KiB) now and after output, at most every
/// 100 ms and only when output came since the last look; with [fromNow]
/// only what the pane shows from the cursor's row at the start on — in
/// either buffer: text the main buffer held before the wait never counts.
/// `{match, line}`. [scanner] is closed when the wait ends.
Future<Map<String, Object?>> waitMatch(
  PaneProbe p,
  MatchScanner scanner, {
  required bool fromNow,
  required Duration timeout,
  Future<void>? cancelled,
}) {
  final t = p.terminal;
  final startedOnAlt = t.isUsingAltBuffer;
  // Anchors follow their rows as the scrollback moves; detached once the
  // row left the buffer (then all that is left came after the start).
  final mainAnchor = fromNow ? t.mainBuffer.createAnchorFromCursor() : null;
  final altAnchor = fromNow && startedOnAlt
      ? t.altBuffer.createAnchorFromCursor()
      : null;
  int? fromRow() {
    if (!fromNow) return null;
    final anchor = t.isUsingAltBuffer ? altAnchor : mainAnchor;
    // The alt screen entered after the start holds only what came after.
    if (anchor == null || !anchor.attached) return 0;
    return anchor.y;
  }

  return _race(timeout, cancelled, (done) {
    Timer? pending;
    var scanning = false;
    var fresh = true; // output since the last look (the start counts)
    late final void Function() soon;
    Future<void> scan() async {
      pending = null;
      if (done.isCompleted || scanning) return;
      if (!fresh) {
        if (p.exited) done.completeError(_exited);
        return;
      }
      fresh = false;
      var text = matchLines(
        t.buffer,
        last: _matchMaxLines,
        fromRow: fromRow(),
      ).join('\n');
      if (text.length > _matchMaxChars) {
        final cut = text.indexOf('\n', text.length - _matchMaxChars);
        text = cut < 0
            ? text.substring(text.length - _matchMaxChars)
            : text.substring(cut + 1);
      }
      scanning = true;
      final MatchSpan? m;
      try {
        m = await scanner.scan(text);
      } on Object catch (e) {
        if (!done.isCompleted) done.completeError(e);
        return;
      } finally {
        scanning = false;
      }
      if (done.isCompleted) return;
      if (m != null) {
        done.complete(matchAnswer(text, m.start, m.end));
      } else if (fresh) {
        soon(); // output came while the scanner looked
      } else if (p.exited) {
        done.completeError(_exited);
      }
    }

    soon = () {
      pending ??= Timer(_matchThrottle, () => unawaited(scan()));
    };

    final subs = [
      p.output.listen((_) {
        fresh = true;
        soon();
      }),
      p.changes.listen((_) {
        if (p.exited) soon();
      }),
    ];
    soon();
    final cancelSubs = _cancelAll(subs);
    return () {
      pending?.cancel();
      mainAnchor?.dispose();
      altAnchor?.dispose();
      cancelSubs();
      scanner.close();
    };
  });
}

/// D21 `{match, line}` for the match [start]–[end] of [text], each at most
/// [kMatchAnswerMaxUnits] (final ruling I1): a longer match keeps its
/// start; a longer line becomes a window centred on the match. Cuts never
/// split a surrogate pair. `clipped: true` when anything was cut.
Map<String, Object?> matchAnswer(String text, int start, int end) {
  const max = kMatchAnswerMaxUnits;
  var clipped = false;
  var mEnd = end;
  if (mEnd - start > max) {
    mEnd = _before(text, start + max);
    clipped = true;
  }
  final lineStart = text.lastIndexOf('\n', start) + 1;
  final nl = text.indexOf('\n', end);
  final lineEnd = nl < 0 ? text.length : nl;
  var from = lineStart;
  var to = lineEnd;
  if (to - from > max) {
    final margin = (max - (mEnd - start)) ~/ 2;
    from = start - margin < lineStart ? lineStart : start - margin;
    to = from + max > lineEnd ? lineEnd : from + max;
    if (to - from < max) from = to - max < lineStart ? lineStart : to - max;
    from = _after(text, from);
    to = _before(text, to);
    clipped = true;
  }
  return {
    'match': text.substring(start, mEnd),
    'line': text.substring(from, to),
    if (clipped) 'clipped': true,
  };
}

bool _low(int unit) => unit & 0xFC00 == 0xDC00;

/// A cut at [i] moved back so it does not end on a lone high surrogate.
int _before(String s, int i) =>
    i > 0 && i < s.length && _low(s.codeUnitAt(i)) ? i - 1 : i;

/// A cut at [i] moved on so it does not start on a lone low surrogate.
int _after(String s, int i) =>
    i > 0 && i < s.length && _low(s.codeUnitAt(i)) ? i + 1 : i;

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
