import 'dart:async';

import 'desktop_terminal.dart';

/// A11 D17: blinks one terminal's cursor every [period] (530 ms) through
/// [DesktopTerminal.applyBlinkPhase] and a repaint of the [controller]. The
/// program's own cursor visibility (DECTCEM) is never overridden and a
/// stopped blinker has no timer. Two repaint requests per second at most.
final class CursorBlinker {
  CursorBlinker({
    required this.terminal,
    required this.controller,
    this.period = const Duration(milliseconds: 530),
  });

  final DesktopTerminal terminal;
  final DesktopTerminalController controller;
  final Duration period;

  Timer? _timer;
  var _on = true;

  bool get running => _timer != null;

  void start() {
    if (_timer != null) return;
    _on = true;
    _timer = Timer.periodic(period, (_) => _apply(!_on));
  }

  /// Cancels the timer and leaves the cursor as the program wants it.
  void stop() {
    final t = _timer;
    if (t == null) return;
    t.cancel();
    _timer = null;
    _apply(true);
  }

  /// A key was typed: solid now, and for a full period.
  void bump() {
    if (_timer == null) return;
    _timer!.cancel();
    _timer = Timer.periodic(period, (_) => _apply(!_on));
    _apply(true);
  }

  void dispose() => stop();

  void _apply(bool on) {
    final changed = _on != on;
    _on = on;
    terminal.applyBlinkPhase(on);
    if (changed) controller.repaint();
  }
}
