import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shellx_agent/shellx_agent.dart';

import '../agent/agent_controller_base.dart';
import '../agent/desktop_services.dart';
import '../cli/ui_command_handler.dart';
import '../restore/restore_persistence.dart';
import '../restore/restore_store.dart' show RestoreLoad;
import '../startup.dart';
import '../terminal/local_sessions_provider.dart';
import '../ui/window_router.dart';
import 'daemon_launcher.dart';
import 'ui_mux_responder.dart';

/// What the window needs from [DaemonLauncher] (a fake in tests).
abstract interface class DaemonConnector {
  Future<DaemonConnection> connect();
  Future<DaemonConnection> replaceIncompatible(Incompatible old);
}

/// True when this window attaches to the background service (A5b; the
/// "Giữ shell chạy khi đóng cửa sổ" switch was on at launch). False: the
/// shells and the agent run in this process, as before A5b.
final daemonModeProvider = Provider<bool>((_) => false);

final daemonConnectorProvider = Provider<DaemonConnector?>((_) => null);

/// Answers the service's `ui.*` requests; bound to each new connection.
final uiMuxResponderProvider = Provider<UiMuxResponder?>((_) => null);

/// The window's live connection to the background service: its sessions
/// and the proof of which service instance it is.
final class DaemonLink {
  DaemonLink({required this.sessions, required this.info});
  final RemoteLocalSessions sessions;
  final MuxPeerInfo info;
  MuxClient get client => sessions.client;
  String? get instance => info.instance;
}

/// Null until the first connection, and in a process that owns its shells.
final daemonLinkProvider = NotifierProvider<DaemonLinkNotifier, DaemonLink?>(
  DaemonLinkNotifier.new,
);

class DaemonLinkNotifier extends Notifier<DaemonLink?> {
  @override
  DaemonLink? build() => null;

  // ignore: use_setters_to_change_properties
  void set(DaemonLink? link) => state = link;
}

/// UI-A5 §7.5.
enum DaemonStrip { restarted, lost }

@immutable
final class DaemonUiState {
  const DaemonUiState({
    this.strip,
    this.retrying = false,
    this.waiting = false,
  });

  /// The strip over the terminal; null: none.
  final DaemonStrip? strip;

  /// "Thử lại" is working (spinner in place of its label).
  final bool retrying;

  /// No connection yet (start, a dialog open): the empty state says so and
  /// offers no new tab (UI-A5 §7.4).
  final bool waiting;

  DaemonUiState copyWith({
    Object? strip = _keep,
    bool? retrying,
    bool? waiting,
  }) => DaemonUiState(
    strip: identical(strip, _keep) ? this.strip : strip as DaemonStrip?,
    retrying: retrying ?? this.retrying,
    waiting: waiting ?? this.waiting,
  );

  @override
  bool operator ==(Object other) =>
      other is DaemonUiState &&
      other.strip == strip &&
      other.retrying == retrying &&
      other.waiting == waiting;

  @override
  int get hashCode => Object.hash(strip, retrying, waiting);
}

const Object _keep = Object();

final daemonStateProvider =
    NotifierProvider<DaemonStateNotifier, DaemonUiState>(
      DaemonStateNotifier.new,
    );

/// A5b D15, D16, D19 (UI side): attaches to the background service, and when
/// it goes away restores the window's work in a new one.
///
/// Never logs messages, paths or text: error types only.
class DaemonStateNotifier extends Notifier<DaemonUiState> {
  /// UI-A5 §7.5: a restart that takes longer than this shows the strip.
  static const Duration restartGrace = Duration(seconds: 3);

  bool _quitting = false;
  bool _recovering = false;
  Timer? _slow;

  @override
  DaemonUiState build() {
    ref.onDispose(() => _slow?.cancel());
    return DaemonUiState(waiting: ref.read(daemonModeProvider));
  }

  DaemonConnector get _connector => ref.read(daemonConnectorProvider)!;

  /// The first connection (UI-A5 §7.3, §7.4: the dialogs over the window).
  /// Null: the user chose to leave; the caller quits the window.
  Future<DaemonLink?> connectAtStartup() async {
    final attached = await _obtain(dialogs: true);
    if (attached == null) return null;
    return _adopt(attached);
  }

  /// `connect()`, with the outdated-service and start-failed dialogs when
  /// [dialogs]. Null: gave up (no dialogs: start failed; dialogs: the user
  /// left, or a failed start with no dialog to ask).
  Future<Attached?> _obtain({required bool dialogs}) async {
    final l10n = ref.read(appL10nProvider);
    final version = ref.read(desktopServicesProvider).appVersion;
    final router = ref.read(windowRouterProvider.notifier);
    var result = await _connector.connect();
    while (ref.mounted) {
      switch (result) {
        case final Attached a:
          return a;
        case final Incompatible old:
          // UI-A5 §7.3: only the user decides to stop shells.
          final request = ConfirmRequest(
            title: l10n.daemonOldTitle,
            body: l10n.daemonOldBody(
              version,
              old.info.app,
              old.info.sessions ?? 0,
            ),
            confirmLabel: l10n.daemonOldRestart,
            cancelLabel: l10n.daemonOldLater,
            onConfirm: () async {
              result = await _connector.replaceIncompatible(old);
              return true;
            },
          );
          if (!await router.confirm(request)) {
            unawaited(old.client.close().catchError((Object _) {}));
            return null;
          }
        case StartFailed():
          if (!dialogs) return null;
          // UI-A5 §7.4: no way to stay; Esc does nothing.
          final request = ConfirmRequest(
            title: l10n.daemonStartFailedTitle,
            body: l10n.daemonStartFailedBody,
            confirmLabel: l10n.daemonRetry,
            cancelLabel: l10n.quitUiAction,
            destructive: false,
            escapeCloses: false,
            onConfirm: () async {
              result = await _connector.connect();
              return true;
            },
          );
          if (!await router.confirm(request)) return null;
      }
    }
    return null;
  }

  /// Makes [attached] the window's connection: sessions, agent, and the
  /// command line's `ui.*` requests all go through it from now on.
  Future<DaemonLink?> _adopt(Attached attached) async {
    final sessions = RemoteLocalSessions(attached.client);
    try {
      await sessions.ready;
    } on Object catch (error) {
      debugPrint('ShellX: background service not usable: ${error.runtimeType}');
      await attached.client.close().catchError((Object _) {});
      return null;
    }
    final link = DaemonLink(sessions: sessions, info: attached.info);
    ref.read(restorePersistenceProvider.notifier).currentDaemon = link.instance;
    ref.read(daemonLinkProvider.notifier).set(link);
    // The agent rebuilds against the new connection and reads its state.
    ref.invalidate(agentControllerProvider);
    unawaited(
      ref
          .read(agentControllerProvider.notifier)
          .bootstrap()
          .then(
            (_) {},
            onError: (Object e) =>
                debugPrint('ShellX: agent state not read: ${e.runtimeType}'),
          ),
    );
    ref
        .read(uiMuxResponderProvider)
        ?.bind(ref.read(uiCommandHandlerProvider), link.client);
    state = state.copyWith(waiting: false);
    unawaited(sessions.disconnected.then((_) => _onDisconnected(link)));
    return link;
  }

  void _onDisconnected(DaemonLink link) {
    if (_quitting || !ref.mounted) return;
    if (!identical(ref.read(daemonLinkProvider), link)) return;
    unawaited(lost());
  }

  /// D15: the background service went away. The window's work is saved
  /// first (not clean: the shells are gone), then a new service is started
  /// and the saved tabs are reopened in it; the shells that ran are not
  /// coming back, their folders and recent text are.
  Future<void> lost() async {
    if (_quitting || _recovering || !ref.mounted) return;
    _recovering = true;
    _slow = Timer(restartGrace, () {
      if (ref.mounted) {
        state = state.copyWith(strip: DaemonStrip.lost, retrying: true);
      }
    });
    try {
      final restore = ref.read(restorePersistenceProvider.notifier);
      await runBounded(
        () => restore.flushAll(clean: false),
        timeout: const Duration(seconds: 2),
        label: 'saving before restarting the service',
      );
      final load = await ref.read(restoreStoreProvider).loadLayout();
      final attached = await _obtain(dialogs: false);
      final link = attached == null ? null : await _adopt(attached);
      if (!ref.mounted) return;
      if (link == null) {
        state = state.copyWith(strip: DaemonStrip.lost, retrying: false);
        return;
      }
      // The save was "not clean" only because the service died: not an
      // abnormal end of the window (no A5a strip on top of this one).
      final saved = load.snapshot;
      await restore.restoreAtStartup(
        RestoreLoad(snapshot: saved?.copyWith(cleanExit: true)),
        daemonInstance: link.instance,
      );
      if (ref.mounted) {
        state = state.copyWith(strip: DaemonStrip.restarted, retrying: false);
      }
    } on Object catch (error) {
      debugPrint('ShellX: restart failed: ${error.runtimeType}');
      if (ref.mounted) {
        state = state.copyWith(strip: DaemonStrip.lost, retrying: false);
      }
    } finally {
      _slow?.cancel();
      _recovering = false;
    }
  }

  /// "Thử lại" on the lost strip.
  Future<void> retry() async {
    state = state.copyWith(retrying: true);
    await lost();
  }

  void dismissStrip() => state = state.copyWith(strip: null, retrying: false);

  /// The window is going away: a closing connection is not a lost service.
  void markQuitting() => _quitting = true;

  /// "Thoát hoàn toàn": asks the service to stop. True when it answered, or
  /// the link ended right after we asked (the service exits as it replies);
  /// false when it did not answer in [wait].
  Future<bool> quitDaemon({Duration wait = const Duration(seconds: 4)}) async {
    _quitting = true;
    final link = ref.read(daemonLinkProvider);
    if (link == null) return true;
    try {
      await link.client.request(MuxType.daemonQuit).timeout(wait);
      return true;
    } on MuxRemoteException catch (e) {
      return e.code == 'disconnected';
    } on Object {
      return false;
    }
  }

  /// "Thoát": the window ends its connection; the service and its shells
  /// stay.
  Future<void> disconnect() async {
    _quitting = true;
    final link = ref.read(daemonLinkProvider);
    if (link == null) return;
    await link.client.close().catchError((Object _) {});
  }
}
