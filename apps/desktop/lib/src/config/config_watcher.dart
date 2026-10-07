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

  /// The latest watch() call; an older one that finishes late is dropped.
  int _watchGeneration = 0;

  /// Watches [files] from now on and (re)starts polling. A file already
  /// watched keeps the stamp this watcher last saw (taken when it noticed a
  /// change, before the load that change caused): a save made while that
  /// load ran still differs and is reported. A new file is stamped now.
  Future<void> watch(Iterable<String> files) async {
    _stopped = false;
    final generation = ++_watchGeneration;
    final stamps = <String, FileStamp>{};
    for (final f in files.toSet()) {
      stamps[f] = _stamps[f] ?? await fs.stamp(f);
    }
    if (_stopped || generation != _watchGeneration) return;
    _stamps = stamps;
    // A poll or settle check still running compared the old list: its
    // result is dropped (see _restamp), and a pending report waits for
    // the new list's polls instead.
    _settle?.cancel();
    _settle = null;
    _poll ??= Timer.periodic(interval, (_) => unawaited(_tick()));
  }

  /// The current stamps and whether any differs from what was seen; null
  /// when watch() replaced the list meanwhile (the result is stale).
  Future<(Map<String, FileStamp>, bool)?> _restamp() async {
    final watched = _stamps;
    final now = <String, FileStamp>{};
    var changed = false;
    for (final MapEntry(key: path, value: before) in watched.entries) {
      final stamp = await fs.stamp(path);
      now[path] = stamp;
      if (stamp != before) changed = true;
    }
    if (_stopped || !identical(watched, _stamps)) return null;
    return (now, changed);
  }

  Future<void> _tick() async {
    if (_busy || _stopped) return;
    _busy = true;
    try {
      final result = await _restamp();
      if (result == null || !result.$2) return;
      _stamps = result.$1;
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
    final result = await _restamp();
    if (result == null) return;
    if (result.$2) {
      _stamps = result.$1;
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
