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

typedef _Key = (String host, int port);

/// State: (host key, remote port) → local port.
final remotePortForwardsProvider =
    NotifierProvider<RemotePortForwards, Map<(String, int), int>>(
      RemotePortForwards.new,
    );

/// A8 D19: a port on a server opens here through an SSH forward. Never
/// logs a host or a port (D37).
class RemotePortForwards extends Notifier<Map<(String, int), int>> {
  final _inFlight = <_Key, Future<int?>>{};

  @override
  Map<(String, int), int> build() {
    ref.listen<TerminalTabsState>(
      terminalTabsProvider,
      (_, tabs) => _prune(tabs),
    );
    return const {};
  }

  SshControl? get _control => ref.read(remoteToolsProvider).control;

  int? forwarded(String hostKey, int port) => state[(hostKey, port)];

  /// The port to open on this computer: [port] for a local pane, the
  /// forwarded one for an SSH pane; null after the failure toast. Callers
  /// asking for the same port at once share one request.
  Future<int?> localPort(PaneSession pane, int port) {
    final host = pane.remote?.launch.host;
    if (host == null) return Future.value(port);
    final key = (host.key, port);
    return _inFlight[key] ??= _forward(host, port).whenComplete(() {
      _inFlight.remove(
        key,
      ); // a block: returning the future would wait on itself
    });
  }

  Future<int?> _forward(SshTarget host, int port) async {
    final tabs = ref.read(terminalTabsProvider.notifier);
    final control = _control;
    if (control == null) {
      tabs.showNotice(const SshUnavailableNotice());
      return null;
    }
    int local;
    try {
      local = await control.forward(host, port);
    } catch (_) {
      // ForwardFailedException, or ssh could not even start.
      if (ref.mounted) tabs.showNotice(RemotePortForwardFailedNotice(port));
      return null;
    }
    if (!ref.mounted) return null;
    if (!_live(ref.read(terminalTabsProvider)).contains(host.key)) {
      // The last pane went while this was starting: nothing keeps it.
      unawaited(control.cancelForwards(host).catchError((_) {}));
      return null;
    }
    state = {...state, (host.key, port): local};
    return local;
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

  /// Host keys with a pane still connected or connecting.
  Set<String> _live(TerminalTabsState tabs) => {
    for (final tab in tabs.tabs)
      for (final pane in tab.panes.values)
        if (pane.remote?.launch.host != null && !pane.exited)
          pane.remote!.launch.host!.key,
  };

  /// D19: forwards of a server with no live pane left are cancelled. A lost
  /// (disconnected) pane is not live, so its forwards go with the
  /// connection; opening the port again makes a new one.
  void _prune(TerminalTabsState tabs) {
    final live = _live(tabs);
    final gone = {
      for (final key in state.keys)
        if (!live.contains(key.$1)) key.$1,
    };
    if (gone.isEmpty) return;
    state = {
      for (final e in state.entries)
        if (!gone.contains(e.key.$1)) e.key: e.value,
    };
    final control = _control;
    if (control == null) return;
    for (final host in gone) {
      final target = SshTarget.parseKey(host);
      if (target != null) {
        unawaited(control.cancelForwards(target).catchError((_) {}));
      }
    }
  }
}
