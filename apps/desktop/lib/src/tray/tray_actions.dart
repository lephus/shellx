import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shellx_core/shellx_core.dart';

import '../agent/agent_controller.dart';
import '../agent/agent_state.dart';
import '../agent/desktop_services.dart';
import '../startup.dart';
import '../terminal_sharing/confirm_text.dart';
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
      case ToggleTerminalSharing():
        if (state.terminalSharing.enabled) {
          await _agent.disableTerminalSharing();
        } else {
          await _setUpTerminalSharing();
        }
      case SetUpTerminalSharing():
        await _setUpTerminalSharing();
      case DisconnectDesktopPhone(:final id):
        _agent.disconnectDesktopPhone(id);
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
        // Bounded: Quit must always reach exit (quitApp), even if closing
        // the sessions or the relay link hangs.
        await runBounded(
          _agent.shutdown,
          timeout: _services.shutdownTimeout,
          label: 'shutting down',
        );
        await _services.quitApp?.call();
    }
  }

  /// Spec §10.1: confirm with the exact files, then (Windows, a PowerShell
  /// whose scripts are blocked) offer to allow local scripts — only on that
  /// button — then install.
  Future<void> _setUpTerminalSharing() async {
    final setup = _services.terminalSharing;
    if (setup == null || _state.terminalSharing.busy) return;
    final plan = await _agent.prepareTerminalSharing();
    if (plan == null) return;
    final l10n = _services.l10n;
    final ok = await _router.confirm(
      ConfirmRequest(
        title: l10n.confirmSharingTitle,
        body: sharingConfirmBody(
          plan,
          l10n,
          windows: setup.windows,
          binaryPath: setup.paths.binary,
        ),
        confirmLabel: l10n.confirmSharingAction,
        long: true,
        destructive: false,
      ),
    );
    if (!ok) return;
    final fixable = setup.windows ? fixablePowerShells(plan) : const [];
    if (fixable.isNotEmpty) {
      final allow = await _router.confirm(
        ConfirmRequest(
          title: l10n.confirmAllowScriptsTitle,
          body: l10n.confirmAllowScriptsBody(
            fixable.map((s) => s.name).join(', '),
          ),
          confirmLabel: l10n.confirmAllowScriptsAction,
          long: true,
          destructive: false,
        ),
      );
      if (allow) {
        for (final shell in fixable) {
          if (!await setup.allowLocalScripts(shell)) {
            await _services.notifier.show(
              title: l10n.notifyAllowScriptsFailedTitle(shell.name),
            );
          }
        }
      }
    }
    await _agent.enableTerminalSharing(plan);
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
