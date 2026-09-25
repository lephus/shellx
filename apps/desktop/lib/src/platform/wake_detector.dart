import 'dart:async';

/// Detects that the computer slept: Dart timers run on a monotonic clock that
/// stops during sleep while the wall clock keeps going, so after wake the gap
/// between two ticks is much larger than [interval].
final class WakeDetector {
  WakeDetector({
    required this.onWake,
    DateTime Function()? now,
    this.interval = const Duration(seconds: 5),
    this.tolerance = const Duration(seconds: 15),
  }) : _now = now ?? DateTime.now;

  final void Function() onWake;
  final DateTime Function() _now;
  final Duration interval;
  final Duration tolerance;
  Timer? _timer;
  DateTime? _last;

  void start() {
    _last = _now();
    _timer ??= Timer.periodic(interval, (_) => check());
  }

  /// One tick; public so tests can drive it with a fake clock.
  void check() {
    final now = _now();
    final last = _last;
    _last = now;
    if (last != null && now.difference(last) > interval + tolerance) {
      onWake();
    }
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }
}
