import 'dart:async';
import 'dart:convert';

import 'terminal_input.dart' show normalizePastedText;

/// What [PasteSender] writes to: one pane's terminal (A10 D13). The sink is
/// built from the pane that was focused when the user pasted, **before** the
/// clipboard was read.
abstract interface class PasteSink {
  /// The pane still exists, has not exited, and is still the same session.
  bool get alive;

  /// The program turned bracketed paste on.
  bool get bracketed;

  /// A small paste: `Terminal.paste` (brackets it itself).
  void paste(String text);

  /// Raw typed bytes: the markers and the pieces of a large paste.
  void send(String data);
}

enum PasteOutcome { sent, empty, tooLarge, declined, cancelled }

/// A10 D13: pastes in order, per pane; a large one goes in pieces so the
/// PTY's 1 MiB input queue never overflows (it drops what does not fit).
final class PasteSender {
  PasteSender({
    this.direct = 64 * 1024,
    this.piece = 32 * 1024,
    this.gap = const Duration(milliseconds: 8),
    this.confirmAbove = 1024 * 1024,
    this.maxBytes = 16 * 1024 * 1024,
  });

  /// Up to this many bytes go in one write.
  final int direct;
  final int piece;
  final Duration gap;
  final int confirmAbove;
  final int maxBytes;

  static const String _start = '\x1b[200~';
  static const String _end = '\x1b[201~';

  final _tails = <int, Future<void>>{};
  final _cancelled = <int>{};

  /// Stops pane [key]'s running and queued pastes after the piece being
  /// written; a bracketed one is closed first so the program leaves paste
  /// mode.
  void cancel(int key) => _cancelled.add(key);

  /// Pastes [text] into [sink] for pane [key]. [confirm] is asked (with the
  /// size in bytes) above [confirmAbove]. Never throws for a gone pane.
  Future<PasteOutcome> send(
    int key,
    String text,
    PasteSink sink, {
    Future<bool> Function(int bytes)? confirm,
  }) {
    final done = Completer<PasteOutcome>();
    final previous = _tails[key] ?? Future<void>.value();
    final run = previous.then((_) async {
      try {
        done.complete(await _run(key, text, sink, confirm));
      } on Object catch (error, stack) {
        done.completeError(error, stack);
      }
    });
    _tails[key] = run.whenComplete(() {
      if (_tails[key] == run) {
        _tails.remove(key);
        _cancelled.remove(key);
      }
    });
    return done.future;
  }

  Future<PasteOutcome> _run(
    int key,
    String raw,
    PasteSink sink,
    Future<bool> Function(int bytes)? confirm,
  ) async {
    if (raw.isEmpty) return PasteOutcome.empty;
    final text = normalizePastedText(raw);
    if (text.isEmpty) return PasteOutcome.empty;
    final bytes = text.length <= direct ~/ 4
        ? text.length
        : utf8.encode(text).length;
    if (bytes > maxBytes) return PasteOutcome.tooLarge;
    if (!sink.alive || _cancelled.contains(key)) return PasteOutcome.cancelled;
    if (bytes > confirmAbove && confirm != null) {
      if (!await confirm(bytes)) return PasteOutcome.declined;
      if (!sink.alive || _cancelled.contains(key)) {
        return PasteOutcome.cancelled;
      }
    }
    if (bytes <= direct) {
      sink.paste(text);
      return PasteOutcome.sent;
    }
    final bracketed = sink.bracketed;
    if (bracketed) sink.send(_start);
    var at = 0;
    while (at < text.length) {
      if (!sink.alive) return PasteOutcome.cancelled;
      if (_cancelled.contains(key)) {
        if (bracketed) sink.send(_end);
        return PasteOutcome.cancelled;
      }
      var end = at + piece;
      if (end >= text.length) {
        end = text.length;
      } else {
        final unit = text.codeUnitAt(end - 1);
        // Never split a surrogate pair between two writes.
        if (unit >= 0xD800 && unit <= 0xDBFF) end--;
      }
      sink.send(text.substring(at, end));
      at = end;
      if (at < text.length) await Future<void>.delayed(gap);
    }
    if (bracketed) sink.send(_end);
    return PasteOutcome.sent;
  }
}
