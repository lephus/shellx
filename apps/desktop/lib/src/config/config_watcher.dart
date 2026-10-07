import 'dart:async';

import 'config_files.dart';

/// D9: polls the stamps of the files the last load looked at every
/// [interval]; a change calls [onChange] once the files have been quiet
/// for [settle]. Stamps are cheap `stat`s (never a read), and a path that
/// can't be stat'ed is missing, so polling never blocks or throws.
final class ConfigWatcher {
  ConfigWatcher({
    required this.fs,
    required this.onChange,
    this.interval = const Duration(seconds: 1),
    this.settle = const Duration(milliseconds: 250),
  });

  final ConfigFs fs;
  final void Function() onChange;
  final Duration interval;
  final Duration settle;

  Map<String, FileStamp> _stamps = const {};
  Timer? _poll;
  Timer? _settle;
  bool _busy = false;
  bool _stopped = false;

  /// Watches [files] from now on and (re)starts polling. A file already
  /// watched keeps the stamp this watcher last saw (taken when it noticed a
  /// change, before the load that change caused): a save made while that
  /// load ran still differs and is reported. A new file is stamped now.
  Future<void> watch(Iterable<String> files) async {
    _stopped = false;
    final stamps = <String, FileStamp>{};
    for (final f in files.toSet()) {
      stamps[f] = _stamps[f] ?? await fs.stamp(f);
    }
    if (_stopped) return;
    _stamps = stamps;
    _poll ??= Timer.periodic(interval, (_) => unawaited(_tick()));
  }

  /// The current stamps, and whether any differs from what was seen.
  Future<(Map<String, FileStamp>, bool)> _restamp() async {
    final watched = _stamps;
    final now = <String, FileStamp>{};
    var changed = false;
    for (final MapEntry(key: path, value: before) in watched.entries) {
      final stamp = await fs.stamp(path);
      now[path] = stamp;
      if (stamp != before) changed = true;
    }
    return (now, changed);
  }

  Future<void> _tick() async {
    if (_busy || _stopped) return;
    _busy = true;
    try {
      final (now, changed) = await _restamp();
      if (!changed || _stopped) return;
      _stamps = now;
      _armSettle();
    } finally {
      _busy = false;
    }
  }

  void _armSettle() {
    _settle?.cancel();
    _settle = Timer(settle, () => unawaited(_settled()));
  }

  /// Fires [onChange] only when nothing changed during the settle window;
  /// a file still being written waits another [settle].
  Future<void> _settled() async {
    if (_stopped) return;
    final (now, changed) = await _restamp();
    if (_stopped) return;
    if (changed) {
      _stamps = now;
      _armSettle();
      return;
    }
    onChange();
  }

  void stop() {
    _stopped = true;
    _poll?.cancel();
    _poll = null;
    _settle?.cancel();
    _settle = null;
  }
}
