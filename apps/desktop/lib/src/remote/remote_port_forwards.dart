import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shellx_agent/shellx_agent.dart';

import '../agent/desktop_services.dart';
import '../terminal/terminal_tabs.dart';
import 'remote_tools_provider.dart';

/// UI-A2 §2.4: `http://localhost:<port>/` in the system browser.
final portOpenerProvider = Provider<Future<void> Function(int port)>(
  (ref) => ref.watch(desktopServicesProvider).urlOpener.openLocalPort,
);

/// State: `'<hostKey>\u0000<remotePort>' → localPort`.
final remotePortForwardsProvider =
    NotifierProvider<RemotePortForwards, Map<String, int>>(
      RemotePortForwards.new,
    );

String _key(String host, int port) => '$host\u0000$port';

String _hostOfKey(String key) => key.split('\u0000').first;

/// A8 D19: a port on a server opens here through an SSH forward. Never
/// logs a host or a port (D37).
class RemotePortForwards extends Notifier<Map<String, int>> {
  @override
  Map<String, int> build() {
    ref.listen<TerminalTabsState>(
      terminalTabsProvider,
      (_, tabs) => _prune(tabs),
    );
    return const {};
  }

  SshControl? get _control => ref.read(remoteToolsProvider).control;

  int? forwarded(String hostKey, int port) => state[_key(hostKey, port)];

  /// The port to open on this computer: [port] for a local pane, the
  /// forwarded one for an SSH pane; null after the failure toast.
  Future<int?> localPort(PaneSession pane, int port) async {
    final host = pane.remote?.launch.host;
    if (host == null) return port;
    final tabs = ref.read(terminalTabsProvider.notifier);
    final control = _control;
    if (control == null) {
      tabs.showNotice(const SshUnavailableNotice());
      return null;
    }
    try {
      final local = await control.forward(host, port);
      if (ref.mounted) state = {...state, _key(host.key, port): local};
      return local;
    } on ForwardFailedException {
      if (ref.mounted) tabs.showNotice(RemotePortForwardFailedNotice(port));
      return null;
    }
  }

  /// The sidebar's port link (UI-A8 §2.1).
  Future<void> open(PaneSession pane, int port) async {
    final local = await localPort(pane, port);
    if (local == null || !ref.mounted) return;
    try {
      await ref.read(portOpenerProvider)(local);
    } catch (_) {
      if (ref.mounted) {
        ref
            .read(terminalTabsProvider.notifier)
            .showNotice(const PortOpenFailedNotice());
      }
    }
  }

  /// D19: forwards of a server with no live pane left are cancelled. A lost
  /// (disconnected) pane is not live, so its forwards go with the
  /// connection; opening the port again makes a new one.
  void _prune(TerminalTabsState tabs) {
    final live = <String>{};
    final hosts = <String, SshTarget>{};
    for (final tab in tabs.tabs) {
      for (final pane in tab.panes.values) {
        final host = pane.remote?.launch.host;
        if (host == null) continue;
        hosts[host.key] = host;
        if (!pane.exited) live.add(host.key);
      }
    }
    final gone = {
      for (final key in state.keys)
        if (!live.contains(_hostOfKey(key))) _hostOfKey(key),
    };
    if (gone.isEmpty) return;
    state = {
      for (final e in state.entries)
        if (!gone.contains(_hostOfKey(e.key))) e.key: e.value,
    };
    final control = _control;
    if (control == null) return;
    for (final host in gone) {
      final target = hosts[host] ?? SshTarget.parse(host);
      if (target != null) unawaited(control.cancelForwards(target));
    }
  }
}
