import 'dart:async';

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
    this.echoWindow = const Duration(milliseconds: 250),
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
  final DateTime Function() _now;

  final _pending = StringBuffer();
  Timer? _timer;
  bool _active = true;
  bool _disposed = false;
  DateTime? _typedAt;

  /// How many times older pending output was dropped.
  int dropped = 0;

  /// Characters waiting.
  int get pendingLength => _pending.length;

  bool get isActive => _active;

  /// The tab came to the front (true) or went to the back (false).
  set isActive(bool value) {
    if (_active == value) return;
    _active = value;
    if (_disposed) return;
    _timer?.cancel();
    _timer = null;
    if (_pending.isEmpty) return;
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
    final echo =
        _active &&
        _pending.isEmpty &&
        text.length <= echoMax &&
        typed != null &&
        _now().difference(typed) <= echoWindow;
    if (echo) {
      _write(text);
      return;
    }
    _pending.write(text);
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
    if (_pending.isEmpty) return;
    final text = _pending.toString();
    _pending.clear();
    _write(text);
  }

  /// A screen reset: what waits belongs to the old screen.
  void clear() {
    _timer?.cancel();
    _timer = null;
    _pending.clear();
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _timer = null;
    _pending.clear();
  }

  void _flush() {
    _timer = null;
    if (_disposed || _pending.isEmpty) return;
    final budget = _active ? activeBudget : idleBudget;
    var text = _pending.toString();
    _pending.clear();
    if (text.length > budget) {
      var cut = budget;
      // Never split a surrogate pair between two writes.
      final unit = text.codeUnitAt(cut - 1);
      if (unit >= 0xD800 && unit <= 0xDBFF) cut--;
      _pending.write(text.substring(cut));
      text = text.substring(0, cut);
    }
    _write(text);
    if (_pending.isNotEmpty) _timer = Timer(_active ? activeTick : idleTick, _flush);
  }

  void _trim() {
    if (_pending.length <= cap) return;
    final text = _pending.toString();
    final start = _cutPoint(text, text.length - keep);
    _pending
      ..clear()
      ..write(text.substring(start));
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
