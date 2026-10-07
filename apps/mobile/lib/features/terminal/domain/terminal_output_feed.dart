import 'dart:async';
import 'dart:collection';

/// Output of one tab on its way to xterm (A10 D29): the foreground tab is written at once and then
/// at most [activeBudget] characters per [activeTick]; a tab in the background is written every
/// [idleTick], at most [idleBudget] characters at a time, so a burst in one terminal costs the
/// others (and the keyboard) little. The echo of what the user just typed is never held back.
///
/// When more than [cap] characters wait, only the newest [keep] are kept (cut at a line start), as
/// the agent's ring buffer drops the oldest bytes. A copy of the desktop's `TerminalFeed` for text
/// that is already decoded, plus the two priorities; the apps share no package with xterm.
final class TerminalOutputFeed {
  TerminalOutputFeed(
    this._write, {
    this.activeBudget = 128 * 1024,
    this.activeTick = const Duration(milliseconds: 16),
    this.idleBudget = 64 * 1024,
    this.idleTick = const Duration(milliseconds: 250),
    this.cap = 2 * 1024 * 1024,
    this.keep = 1024 * 1024,
    this.echoWindow = const Duration(milliseconds: 50),
    this.echoMaxPerSecond = 10,
    this.echoMax = 4096,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final void Function(String text) _write;
  final int activeBudget;
  final Duration activeTick;
  final int idleBudget;
  final Duration idleTick;
  final int cap;
  final int keep;
  final Duration echoWindow;
  final int echoMax;

  /// At most this many writes per second skip the queue as an echo (a held key or a flood of
  /// small writes after one keystroke must not bypass the budget).
  final int echoMaxPerSecond;
  final DateTime Function() _now;

  // Chunks in arrival order; a flush takes up to the budget from the front without copying the rest.
  final Queue<String> _pending = Queue<String>();
  int _pendingLength = 0;
  final Queue<DateTime> _echoes = Queue<DateTime>();
  Timer? _timer;
  bool _active = true;
  bool _disposed = false;
  DateTime? _typedAt;

  /// How many times older pending output was dropped.
  int dropped = 0;

  /// Characters waiting.
  int get pendingLength => _pendingLength;

  bool get isActive => _active;

  /// The tab came to the front (true) or went to the back (false).
  set isActive(bool value) {
    if (_active == value) return;
    _active = value;
    if (_disposed) return;
    _timer?.cancel();
    _timer = null;
    if (_pendingLength == 0) return;
    // To the front: what waits goes at once. To the back: the slow tick takes over.
    if (_active) {
      _flush();
    } else {
      _timer = Timer(idleTick, _flush);
    }
  }

  /// The user typed in this tab: output that follows at once is its echo.
  void noteInput() => _typedAt = _now();

  void add(String text) {
    if (_disposed || text.isEmpty) return;
    final typed = _typedAt;
    final now = _now();
    while (_echoes.isNotEmpty && now.difference(_echoes.first) >= const Duration(seconds: 1)) {
      _echoes.removeFirst();
    }
    final echo =
        _active &&
        _pendingLength == 0 &&
        text.length <= echoMax &&
        typed != null &&
        now.difference(typed) <= echoWindow &&
        _echoes.length < echoMaxPerSecond;
    if (echo) {
      _echoes.addLast(now);
      _write(text);
      return;
    }
    _pending.addLast(text);
    _pendingLength += text.length;
    _trim();
    if (_timer != null) return;
    // The foreground tab writes the first piece at once; one in the background waits a tick.
    if (_active) {
      _flush();
    } else {
      _timer = Timer(idleTick, _flush);
    }
  }

  /// Writes everything waiting now (before an exit banner).
  void drain() {
    _timer?.cancel();
    _timer = null;
    if (_pendingLength == 0) return;
    final text = _pending.join();
    _pending.clear();
    _pendingLength = 0;
    _write(text);
  }

  /// A screen reset: what waits belongs to the old screen.
  void clear() {
    _timer?.cancel();
    _timer = null;
    _pending.clear();
    _pendingLength = 0;
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _timer = null;
    _pending.clear();
    _pendingLength = 0;
  }

  void _flush() {
    _timer = null;
    if (_disposed || _pendingLength == 0) return;
    final budget = _active ? activeBudget : idleBudget;
    final out = StringBuffer();
    var taken = 0;
    while (_pending.isNotEmpty && taken < budget) {
      final chunk = _pending.removeFirst();
      final room = budget - taken;
      if (chunk.length <= room) {
        out.write(chunk);
        taken += chunk.length;
        continue;
      }
      var cut = room;
      // Never split a surrogate pair between two writes.
      final unit = chunk.codeUnitAt(cut - 1);
      if (unit >= 0xD800 && unit <= 0xDBFF) cut--;
      out.write(chunk.substring(0, cut));
      taken += cut;
      _pending.addFirst(chunk.substring(cut));
      break;
    }
    _pendingLength -= taken;
    if (taken > 0) _write(out.toString());
    if (_pendingLength > 0) _timer = Timer(_active ? activeTick : idleTick, _flush);
  }

  void _trim() {
    if (_pendingLength <= cap) return;
    final text = _pending.join();
    final start = _cutPoint(text, text.length - keep);
    final kept = text.substring(start);
    _pending
      ..clear()
      ..addLast(kept);
    _pendingLength = kept.length;
    dropped++;
  }

  static int _cutPoint(String text, int from) {
    final newline = text.indexOf('\n', from);
    if (newline != -1 && newline < text.length - 1) return newline + 1;
    final escape = text.indexOf('\x1b', from);
    if (escape != -1) return escape;
    final carriageReturn = text.indexOf('\r', from);
    if (carriageReturn != -1) return carriageReturn;
    final unit = text.codeUnitAt(from);
    return unit >= 0xDC00 && unit <= 0xDFFF ? from + 1 : from;
  }
}
