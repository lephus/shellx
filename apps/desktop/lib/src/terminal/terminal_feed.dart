import 'dart:async';
import 'dart:convert';

/// Turns one tab's output bytes into xterm writes the UI can keep up with
/// (spec criterion 8, Review Focus 2): UTF-8 is decoded across chunk
/// boundaries; the first chunk after a quiet period is written at once,
/// then output is coalesced into at most [budget] characters per [tick];
/// when more than [cap] characters wait (a flood while the window is hidden
/// or the tab is not selected), only the newest [keep] — cut at a line
/// start — are kept, like the agent's ring buffer drops the oldest bytes.
final class TerminalFeed {
  TerminalFeed(
    this._write, {
    this.budget = 256 * 1024,
    this.cap = 1024 * 1024,
    this.keep = 512 * 1024,
    this.tick = const Duration(milliseconds: 16),
  }) {
    _decoder = const Utf8Decoder(
      allowMalformed: true,
    ).startChunkedConversion(StringConversionSink.fromStringSink(_pending));
  }

  final void Function(String text) _write;
  final int budget;
  final int cap;
  final int keep;
  final Duration tick;
  final _pending = StringBuffer();
  late final ByteConversionSink _decoder;
  Timer? _timer;
  bool _disposed = false;

  /// How many times older pending output was dropped.
  int dropped = 0;

  void add(List<int> bytes) {
    if (_disposed) return;
    _decoder.add(bytes);
    _trim();
    if (_timer == null) _flush();
  }

  /// Writes everything pending now (before the exit line, D14).
  void drain() {
    _timer?.cancel();
    _timer = null;
    if (_pending.isEmpty) return;
    final text = _pending.toString();
    _pending.clear();
    _write(text);
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _timer = null;
  }

  void _flush() {
    _timer = null;
    if (_disposed || _pending.isEmpty) return;
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
    _timer = Timer(tick, _flush);
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

  /// Where the kept tail begins, at or after [from]: the next line start;
  /// without one (full-screen redraws, `\r` progress bars) the next escape
  /// sequence or carriage return, so the tail never starts inside an escape
  /// sequence; failing those, never on the low half of a surrogate pair.
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
