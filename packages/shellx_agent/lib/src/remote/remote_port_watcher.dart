import 'dart:async';

import 'remote_probe.dart';
import 'ssh_control.dart';
import 'ssh_target.dart';

/// A remote session the watcher may probe: it said hello and its pid.
final class RemoteShell {
  const RemoteShell({required this.target, required this.pid});
  final SshTarget target;
  final int pid;
}

final class _Host {
  _Host(this.target);
  final SshTarget target;
  Timer? timer;
  bool running = false;
  bool stopped = false;
  int failures = 0;
}

/// A8 D18: listening ports on servers, one probe per server, only while
/// the window is shown. Logs never name the server (D37).
final class RemotePortWatcher {
  RemotePortWatcher({
    required SshControl control,
    required Map<int, RemoteShell> Function() shells,
    required void Function(Map<int, List<int>> ports) onPorts,
    this.interval = const Duration(seconds: 5),
    this.slowInterval = const Duration(seconds: 60),
    this.signInRetry = const Duration(minutes: 5),
    this.timeout = const Duration(seconds: 4),
    this.maxHosts = 16,
    void Function(String message)? log,
  }) : _control = control,
       _shells = shells,
       _onPorts = onPorts,
       _log = log;

  final SshControl _control;
  final Map<int, RemoteShell> Function() _shells;
  final void Function(Map<int, List<int>> ports) _onPorts;
  final void Function(String message)? _log;
  final Duration interval;
  final Duration slowInterval;

  /// A stopped (needs sign-in) host is tried again this often while visible.
  final Duration signInRetry;
  final Duration timeout;
  final int maxHosts;

  final _hosts = <String, _Host>{};
  bool _visible = false;
  bool _disposed = false;

  void setVisible(bool visible) {
    _visible = visible;
    if (visible) {
      sessionsChanged();
      return;
    }
    for (final host in _hosts.values) {
      host.timer?.cancel();
      host.timer = null;
    }
  }

  /// A session of [target] said hello again: probe it again (D18).
  void resume(SshTarget target) {
    final host = _hosts[target.key];
    if (host == null) return;
    host.stopped = false;
    host.failures = 0;
    if (!host.running) {
      host.timer?.cancel();
      host.timer = null;
    }
    sessionsChanged();
  }

  void sessionsChanged() {
    if (_disposed) return;
    final targets = <String, SshTarget>{
      for (final shell in _shells().values) shell.target.key: shell.target,
    };
    for (final key in _hosts.keys.toList()) {
      if (!targets.containsKey(key)) _hosts.remove(key)!.timer?.cancel();
    }
    if (!_visible) return;
    for (final entry in targets.entries.take(maxHosts)) {
      final host = _hosts.putIfAbsent(entry.key, () => _Host(entry.value));
      if (host.running || host.timer != null) continue;
      host.timer = Timer(
        host.stopped ? signInRetry : Duration.zero,
        () => _probe(entry.key),
      );
    }
  }

  Future<void> _probe(String key) async {
    final host = _hosts[key];
    if (host == null || _disposed) return;
    host.timer = null;
    host.running = true;
    final result = await _control.runRemote(
      host.target,
      remoteProbeScript,
      timeout: timeout,
    );
    host.running = false;
    if (_disposed || !identical(_hosts[key], host)) return;
    final shells = {
      for (final e in _shells().entries)
        if (e.value.target.key == key) e.key: e.value,
    };
    if (result.exitCode == 255 && !result.timedOut) {
      host.stopped = true;
      _log?.call('ssh probe: needs sign-in');
      _onPorts({for (final id in shells.keys) id: const <int>[]});
      if (_visible && shells.isNotEmpty) {
        host.timer = Timer(signInRetry, () => _probe(key));
      }
      return;
    }
    if (result.exitCode != 0 || result.timedOut) {
      host.failures++;
      _log?.call(
        'ssh probe: failed (${result.timedOut ? 'timeout' : 'exit ${result.exitCode}'})',
      );
    } else {
      host.failures = 0;
      host.stopped = false;
      final byPid = parseRemoteProbe(
        result.stdout,
        shells.values.map((s) => s.pid),
      );
      _onPorts({
        for (final e in shells.entries)
          e.key: byPid[e.value.pid] ?? const <int>[],
      });
    }
    if (_visible && shells.isNotEmpty) {
      host.timer = Timer(
        host.failures >= 3 ? slowInterval : interval,
        () => _probe(key),
      );
    }
  }

  /// Process shutdown only: the tray's "Close all" ends sessions, not the
  /// watcher, and new sessions need it again.
  void dispose() {
    _disposed = true;
    for (final host in _hosts.values) {
      host.timer?.cancel();
    }
    _hosts.clear();
  }
}
