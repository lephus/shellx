import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shellx_core/shellx_core.dart';

import '../agent/agent_controller.dart';
import '../agent/agent_state.dart';
import '../agent/desktop_services.dart';
import '../cli/cli_install.dart';
import '../cli/cli_service.dart';
import '../cli/cli_settings.dart';
import '../restore/restore_persistence.dart';
import '../startup.dart';
import '../config/config_controller.dart' show shellxConfigProvider;
import '../terminal/terminal_tabs.dart';
import '../terminal_sharing/confirm_text.dart';
import '../ui/activation.dart';
import '../ui/terminal/close_tab.dart';
import '../ui/window_router.dart';
import 'tray_action.dart';
import 'tray_menu.dart';

final trayActionsProvider = Provider<TrayActions>(TrayActions.new);

/// The tray's "Terminal" submenu (A5a D13). The switch lives in the
/// settings: invalidated after [ToggleRestoreScrollback]. The "Dòng lệnh"
/// settings (A7) are watched.
final trayLocalStateProvider = Provider<TrayLocalState>((ref) {
  final cli = ref.watch(cliSettingsProvider);
  return TrayLocalState(
    restoreScrollback: ref
        .read(restorePersistenceProvider.notifier)
        .scrollbackEnabled,
    hasSavedScrollback: ref.watch(savedScrollbackProvider),
    cliControlEnabled: cli.controlEnabled,
    cliAllowExternal: cli.allowExternal,
    cliPathInstalled: cli.pathInstalled,
  );
});

/// A7 D26: what "Sao chép lệnh cài skill cho agent" copies.
const kSkillsInstallCommand = 'shellx skills install';

/// Executes tray menu actions, asking for confirmation where an action is
/// destructive or disconnects a phone.
final class TrayActions {
  TrayActions(this._ref);

  final Ref _ref;

  /// Set once a quit is confirmed: a ⌘Q or "Thoát" while shutting down
  /// must not ask again (A1 D10: exactly one confirmation).
  bool _quitting = false;

  /// Ruling M3: an install or removal (maybe a password prompt) in flight.
  bool _cliPathBusy = false;

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
      case OpenTerminalWindow():
        await openTerminalWindow(
          router: _router,
          tabs: _ref.read(terminalTabsProvider.notifier),
        );
      case ToggleRemoteAccess():
        // A1 D7: turning off only disconnects phones; ask only when a phone
        // is connected right now.
        if (state.remoteAccess && state.activeChannels > 0) {
          final ok = await _router.confirm(
            ConfirmRequest(
              title: l10n.confirmRemoteOffTitle,
              body: l10n.confirmRemoteOffBody,
              confirmLabel: l10n.confirmRemoteOffAction,
            ),
          );
          if (!ok) return;
        }
        await _agent.setRemoteAccess(!state.remoteAccess);
      case CloseSession(:final id):
        await _closeSession(id);
      case CloseAllSessions():
        // Ruling I2: every shell goes, so always ask, with the count.
        final count = state.sessions.length;
        if (count == 0) return;
        final ok = await _router.confirm(
          ConfirmRequest(
            title: l10n.confirmCloseAllTitle(count),
            body: l10n.confirmCloseAllBody,
            confirmLabel: l10n.confirmCloseAllAction,
          ),
        );
        if (!ok) return;
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
      case SetNotifyThreshold(:final seconds):
        await _agent.setNotifyThreshold(seconds);
      case ToggleDesktopNotifications():
        await _agent.setDesktopNotifications(!state.desktopNotifications);
      case ToggleDesktopNotificationsOnlyUnfocused():
        await _agent.setDesktopNotificationsOnlyUnfocused(
          !state.desktopNotificationsOnlyUnfocused,
        );
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
      // UI-A5 §3: both apply at once, without asking.
      case ToggleRestoreScrollback():
        final restore = _ref.read(restorePersistenceProvider.notifier);
        try {
          await restore.setScrollbackEnabled(!restore.scrollbackEnabled);
        } finally {
          // Failed or not, the menu shows what is stored.
          _ref.invalidate(trayLocalStateProvider);
        }
      case ClearSavedScrollback():
        await _ref.read(restorePersistenceProvider.notifier).clearScrollback();
      // A7 D26, amendment: at once, without asking; the host rechecks.
      case ToggleCliControl():
        final cli = _ref.read(cliSettingsProvider.notifier);
        await cli.setControlEnabled(
          !_ref.read(cliSettingsProvider).controlEnabled,
        );
      case ToggleCliAllowExternal():
        final cli = _ref.read(cliSettingsProvider.notifier);
        await cli.setAllowExternal(
          !_ref.read(cliSettingsProvider).allowExternal,
        );
      case ToggleCliPath():
        await _toggleCliPath();
      case CopySkillsCommand():
        await _ref.read(cliClipboardProvider)(kSkillsInstallCommand);
        _ref
            .read(terminalTabsProvider.notifier)
            .showNotice(const CliSkillsCopiedNotice());
      case Quit(:final confirm):
        if (_quitting) return;
        if (confirm && state.sessions.isNotEmpty) {
          final ok = await _router.confirm(
            ConfirmRequest(
              title: l10n.confirmQuitTitle,
              body: l10n.confirmQuitBody(state.sessions.length),
              confirmLabel: l10n.confirmQuitAction,
            ),
          );
          if (!ok || _quitting) return;
        }
        _quitting = true;
        // Ruling M6: no command-line request may act while the shells
        // close: the host stops first.
        await runBounded(
          _ref.read(cliHostControlProvider).stopNow,
          timeout: const Duration(seconds: 2),
          label: 'stopping the command-line host',
        );
        // A5a D12: the last save is clean, contents included, and final:
        // the sessions the shutdown closes, or a late "power-off
        // cancelled", must not change it.
        await runBounded(
          () => _ref.read(restorePersistenceProvider.notifier).flushForQuit(),
          timeout: const Duration(seconds: 2),
          label: 'saving the session layout',
        );
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

  /// The tray's "Đóng" on one session: the same rules as ⌘W (D15: asks
  /// while a command runs). The tray lists sessions, and a split tab holds
  /// several (A3 D1, final ruling I-1): one pane of a split tab closes as
  /// that pane (the pane dialog); a one-pane tab as the tab (A1's dialog).
  /// A session the window has no tab for yet closes at once.
  Future<void> _closeSession(int id) async {
    final tabs = _ref.read(terminalTabsProvider.notifier);
    final tab = _ref.read(terminalTabsProvider).tabOfSession(id);
    if (tab == null) {
      _agent.closeSession(id);
      return;
    }
    await closePaneWithConfirm(
      tabs: tabs,
      router: _router,
      l10n: _services.l10n,
      tab: tab,
      paneId: id,
      confirm: _ref.read(shellxConfigProvider).config.confirmClose,
    );
  }

  /// A7 D8: installs or removes `shellx` for other terminals. Never at
  /// startup. Stored only when it worked; a cancelled password prompt
  /// changes nothing and says nothing; the result shows in the window.
  Future<void> _toggleCliPath() async {
    final installer = _ref.read(cliPathInstallerProvider);
    final paths = _ref.read(cliPathsProvider);
    if (installer == null || paths == null || _cliPathBusy) return;
    _cliPathBusy = true;
    try {
      await _runCliPath(installer, paths);
    } finally {
      _cliPathBusy = false;
    }
  }

  Future<void> _runCliPath(PathInstaller installer, CliPaths paths) async {
    final cli = _ref.read(cliSettingsProvider.notifier);
    final removing = _ref.read(cliSettingsProvider).pathInstalled;
    PathInstallResult result;
    try {
      result = removing
          ? await installer.uninstall()
          : await installer.install();
    } on Object catch (e) {
      debugPrint('ShellX: shellx PATH install failed: ${e.runtimeType}');
      result = PathInstallResult.failed;
    }
    if (result == PathInstallResult.cancelled) return;
    if (result == PathInstallResult.installed) {
      await cli.setPathInstalled(!removing);
    }
    // Ruling M10: installed where the login shell does not look.
    final hint = result == PathInstallResult.installed && !removing
        ? await _loginPathHint()
        : null;
    final notice = switch ((result, removing)) {
      (PathInstallResult.installed, false) when hint != null =>
        CliPathNotOnPathNotice(hint),
      (PathInstallResult.installed, false) => const CliPathInstalledNotice(),
      (PathInstallResult.installed, true) => null,
      (_, false) => CliPathFailedNotice(paths.dir),
      (_, true) => CliPathRemoveFailedNotice(
        paths.windows ? paths.dir : paths.systemLink,
      ),
    };
    if (notice == null) return;
    _router.showTerminal();
    _ref.read(terminalTabsProvider.notifier).showNotice(notice);
  }

  Future<LoginPathHint?> _loginPathHint() async {
    final check = _ref.read(cliLoginPathCheckProvider);
    if (check == null) return null;
    try {
      return await check();
    } on Object catch (e) {
      debugPrint('ShellX: login PATH check failed: ${e.runtimeType}');
      return null;
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
