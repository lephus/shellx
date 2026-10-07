import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;

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
  ///
  /// Nothing pending for [key]: nothing to cancel, and no stale mark is left
  /// to cancel the next paste.
  void cancel(int key) {
    if (_tails.containsKey(key)) _cancelled.add(key);
  }

  /// Completes when every paste queued for pane [key] so far has ended; a
  /// caller that types after a paste (keys, Enter) waits for it.
  Future<void> whenIdle(int key) => _tails[key] ?? Future<void>.value();

  /// Pastes [text] into [sink] for pane [key]. [confirm] is asked (with the
  /// size in bytes) above [confirmAbove]. Never throws: a failing write ends the paste as
  /// [PasteOutcome.cancelled].
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
      } on Object catch (error) {
        // A write or the confirmation failed: the paste ends, quietly.
        debugPrint('paste: failed (${error.runtimeType})');
        done.complete(PasteOutcome.cancelled);
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
    var opened = false;
    try {
      if (bracketed) {
        sink.send(_start);
        opened = true;
      }
      var at = 0;
      while (at < text.length) {
        if (!sink.alive) return PasteOutcome.cancelled;
        if (_cancelled.contains(key)) {
          if (bracketed) sink.send(_end);
          return PasteOutcome.cancelled;
        }
        final end = _pieceEnd(text, at);
        sink.send(text.substring(at, end));
        at = end;
        if (at < text.length) await Future<void>.delayed(gap);
      }
      if (bracketed) sink.send(_end);
      return PasteOutcome.sent;
    } on Object catch (error) {
      // A write failed (the pane's session went away): close the bracket
      // if we can so the program is not left in paste mode. Never logs text.
      debugPrint('paste: write failed (${error.runtimeType})');
      if (opened) {
        try {
          sink.send(_end);
        } on Object {
          // Nothing more to do for a pane that cannot be written to.
        }
      }
      return PasteOutcome.cancelled;
    }
  }

  /// The end of the piece starting at [from]: at most [piece] UTF-8 bytes,
  /// never between the two halves of a code point.
  int _pieceEnd(String text, int from) {
    var at = from;
    var bytes = 0;
    while (at < text.length) {
      final unit = text.codeUnitAt(at);
      final isPair =
          unit >= 0xD800 &&
          unit <= 0xDBFF &&
          at + 1 < text.length &&
          (text.codeUnitAt(at + 1) & 0xFC00) == 0xDC00;
      final width = isPair
          ? 4
          : unit < 0x80
          ? 1
          : unit < 0x800
          ? 2
          : 3;
      if (bytes + width > piece && at > from) break;
      bytes += width;
      at += isPair ? 2 : 1;
    }
    return at;
  }
}
