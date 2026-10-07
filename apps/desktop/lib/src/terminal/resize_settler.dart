import 'dart:async';

/// A10 D20: what the PTY is told about a pane's size. xterm resizes its own
/// grid at once (the screen is right); the session hears the size only
/// after it stayed the same for [settle] — never every frame of a window
/// or divider drag — or sooner when something needs it right (typing,
/// [flush]). Per pane (session id).
final class ResizeSettler {
  ResizeSettler({this.settle = const Duration(milliseconds: 80)});

  /// Zero sends at once (tests that do not care).
  final Duration settle;
  final _pending = <int, _Pending>{};
  bool _disposed = false;

  bool hasPending(int id) => _pending.containsKey(id);

  /// Remembers the latest size of pane [id]; [send] is called with it once
  /// it settles.
  void request(int id, int cols, int rows, void Function(int, int) send) {
    if (_disposed) return;
    if (settle == Duration.zero) {
      send(cols, rows);
      return;
    }
    _pending[id]?.timer.cancel();
    late final _Pending entry;
    entry = _Pending(
      cols,
      rows,
      send,
      Timer(settle, () {
        if (identical(_pending[id], entry)) _pending.remove(id);
        send(cols, rows);
      }),
    );
    _pending[id] = entry;
  }

  /// Sends pane [id]'s waiting size now (before a key reaches the PTY, when
  /// the pane becomes visible). True when there was one.
  bool flush(int id) {
    final entry = _pending.remove(id);
    if (entry == null) return false;
    entry.timer.cancel();
    entry.send(entry.cols, entry.rows);
    return true;
  }

  void flushAll() {
    for (final id in _pending.keys.toList()) {
      flush(id);
    }
  }

  /// The pane closed or ended: nothing is sent for it any more.
  void cancel(int id) => _pending.remove(id)?.timer.cancel();

  void dispose() {
    _disposed = true;
    for (final e in _pending.values) {
      e.timer.cancel();
    }
    _pending.clear();
  }
}

final class _Pending {
  _Pending(this.cols, this.rows, this.send, this.timer);
  final int cols;
  final int rows;
  final void Function(int, int) send;
  final Timer timer;
}
