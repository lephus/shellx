import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shellx_core/shellx_core.dart';

import '../agent/agent_controller.dart';
import '../agent/agent_state.dart';
import '../agent/desktop_services.dart';
import '../ui/window_router.dart';
import 'tray_action.dart';

final trayActionsProvider = Provider<TrayActions>(TrayActions.new);

/// Executes tray menu actions, asking for confirmation where an action is
/// destructive (spec §8.3: turning remote access off with open sessions).
final class TrayActions {
  TrayActions(this._ref);

  final Ref _ref;

  AgentController get _agent => _ref.read(agentControllerProvider.notifier);
  AgentViewState get _state => _ref.read(agentControllerProvider);
  WindowRouter get _router => _ref.read(windowRouterProvider.notifier);
  DesktopServices get _services => _ref.read(desktopServicesProvider);

  /// [TrayPresenter.onMenuItemClick] fire-and-forgets this call (binding
  /// ruling, Task 9), so it must never throw: any failure is caught here and
  /// surfaced as a system notification instead of becoming an unhandled
  /// Future error.
  Future<void> handle(TrayAction action) async {
    try {
      await _dispatch(action);
    } catch (error) {
      await _reportFailure(error);
    }
  }

  Future<void> _dispatch(TrayAction action) async {
    final l10n = _services.l10n;
    final state = _state;
    switch (action) {
      case ToggleRemoteAccess():
        if (state.remoteAccess && state.sessions.isNotEmpty) {
          final ok = await _router.confirm(
            ConfirmRequest(
              title: l10n.confirmRemoteOffTitle,
              body: l10n.confirmRemoteOffBody(state.sessions.length),
              confirmLabel: l10n.confirmRemoteOffAction,
            ),
          );
          if (!ok) return;
        }
        await _agent.setRemoteAccess(!state.remoteAccess);
      case CloseSession(:final id):
        _agent.closeSession(id);
      case CloseAllSessions():
        _agent.closeAllSessions();
      case PairPhone():
        if (_agent.startPairing() != null) _router.open(const PairingRoute());
      case RevokeDevice(:final mobileId):
        final matches = state.trusted.where((d) => d.mobileId == mobileId);
        final name = matches.isEmpty ? mobileId : matches.first.name;
        final ok = await _router.confirm(
          ConfirmRequest(
            title: l10n.confirmRevokeTitle(name),
            body: l10n.confirmRevokeBody,
            confirmLabel: l10n.confirmRevokeAction,
          ),
        );
        if (!ok) return;
        await _agent.revoke(mobileId);
      case ToggleKeepAwake():
        await _agent.setKeepAwake(!state.keepAwake);
      case ToggleLaunchAtStartup():
        await _agent.setLaunchAtStartup(!state.launchAtStartup);
      case OpenChangePassword():
        _router.open(const ChangePasswordRoute());
      case SignOut():
        final ok = await _router.confirm(
          ConfirmRequest(
            title: l10n.confirmSignOutTitle,
            body: l10n.confirmSignOutBody,
            confirmLabel: l10n.confirmSignOutAction,
          ),
        );
        if (!ok) return;
        await _agent.signOut();
      case SignIn():
        _router.open(const LoginRoute());
      case DownloadUpdate():
        final update = state.update;
        if (update != null) await _services.urlOpener.open(update.url);
      case Reconnect():
        // Binding ruling (Task 8): the only way back after a 4001
        // (`replaced`) close, since spec §12 forbids the relay from
        // reconnecting on its own then. No confirmation needed.
        _agent.reconnect();
      case Quit():
        if (state.sessions.isNotEmpty) {
          final ok = await _router.confirm(
            ConfirmRequest(
              title: l10n.confirmQuitTitle,
              body: l10n.confirmQuitBody(state.sessions.length),
              confirmLabel: l10n.confirmQuitAction,
            ),
          );
          if (!ok) return;
        }
        await _agent.shutdown();
        await _services.quitApp?.call();
    }
  }

  /// Never throws itself: a broken notifier must not turn a caught failure
  /// into a new unhandled one. Never shows tokens, passwords or pairing
  /// codes — only [ApiException.code] (e.g. `network`) or a generic code.
  Future<void> _reportFailure(Object error) async {
    final code = error is ApiException ? error.code : 'internal';
    try {
      await _services.notifier.show(
        title: _services.l10n.errorUnexpected(code),
      );
    } catch (_) {
      // Nothing else to do here.
    }
  }
}
