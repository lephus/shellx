import 'package:shellx_core/shellx_core.dart';
import 'package:tray_manager/tray_manager.dart';

import '../../l10n/app_localizations.dart';
import '../agent/agent_state.dart';
import '../agent/notify_threshold.dart';
import '../terminal_sharing/attach_throttle.dart';
import 'tray_action.dart';

enum TrayIconState { normal, offline, active }

/// Spec §8.3: grey when not connected, highlighted while a phone has an open
/// encrypted channel, normal otherwise.
TrayIconState trayIconFor(AgentViewState state) {
  if (!state.signedIn ||
      !state.remoteAccess ||
      state.relay != RelayConnectionState.connected) {
    return TrayIconState.offline;
  }
  return state.activeChannels > 0 ? TrayIconState.active : TrayIconState.normal;
}

/// macOS uses PNG (template images for normal/offline), Windows needs ICO.
String trayIconAsset(TrayIconState icon, {required bool windows}) =>
    'assets/tray/tray_${icon.name}.${windows ? 'ico' : 'png'}';

/// Stable menu item ids per key. menu_base hands out a fresh id for every
/// MenuItem, so a click on a menu that was rebuilt while open would not be
/// found; reusing ids per key keeps such clicks working.
final class TrayMenuIds {
  final Map<String, int> _ids = {};
  int _next = 1024;
  int _separators = 0;

  int idFor(String key) => _ids.putIfAbsent(key, () => _next++);

  MenuItem assign(MenuItem item) {
    item.id = idFor(item.key ?? 'separator:${_separators++}');
    return item;
  }

  void startBuild() => _separators = 0;
}

/// What the tray shows that the UI process owns (A5a D13; with A5b the
/// agent state comes from the daemon and cannot carry UI settings).
final class TrayLocalState {
  const TrayLocalState({
    this.restoreScrollback = true,
    this.hasSavedScrollback = false,
    this.cliControlEnabled = true,
    this.cliAllowExternal = false,
    this.cliPathInstalled = false,
  });
  final bool restoreScrollback;
  final bool hasSavedScrollback;

  /// A7 D26, amendment, D8: the "Dòng lệnh" submenu.
  final bool cliControlEnabled;
  final bool cliAllowExternal;
  final bool cliPathInstalled;

  @override
  bool operator ==(Object other) =>
      other is TrayLocalState &&
      other.restoreScrollback == restoreScrollback &&
      other.hasSavedScrollback == hasSavedScrollback &&
      other.cliControlEnabled == cliControlEnabled &&
      other.cliAllowExternal == cliAllowExternal &&
      other.cliPathInstalled == cliPathInstalled;

  @override
  int get hashCode => Object.hash(
    restoreScrollback,
    hasSavedScrollback,
    cliControlEnabled,
    cliAllowExternal,
    cliPathInstalled,
  );
}

/// "Tắt", "10 giây", "1 phút"… (push spec §7).
String notifyThresholdLabel(int seconds, AppLocalizations l10n) {
  if (seconds == 0) return l10n.trayNotifyOff;
  if (seconds % 60 == 0) return l10n.trayNotifyMinutes(seconds ~/ 60);
  return l10n.trayNotifySeconds(seconds);
}

String _statusLine(AgentViewState state, AppLocalizations l10n) {
  final email = state.email ?? '';
  if (!state.remoteAccess) return '○ ${l10n.trayStatusRemoteOff}';
  return switch (state.relay) {
    RelayConnectionState.connected => '● ${l10n.trayStatusConnected(email)}',
    RelayConnectionState.connecting => '○ ${l10n.trayStatusConnecting(email)}',
    RelayConnectionState.replaced => '○ ${l10n.trayStatusReplaced}',
    _ => '○ ${l10n.trayStatusReconnecting}',
  };
}

/// Builds the tray menu of spec §8.3 (signed in) or a minimal one (signed
/// out), both led by "Mở cửa sổ terminal" (A1 D11, UI §5).
Menu buildTrayMenu(
  AgentViewState state,
  AppLocalizations l10n,
  TrayMenuIds ids, {
  TrayLocalState local = const TrayLocalState(),
}) {
  ids.startBuild();
  MenuItem sep() => ids.assign(MenuItem.separator());
  MenuItem item(String key, String label, {bool disabled = false}) =>
      ids.assign(MenuItem(key: key, label: label, disabled: disabled));
  MenuItem check(
    String key,
    String label,
    bool checked, {
    bool disabled = false,
  }) => ids.assign(
    MenuItem.checkbox(
      key: key,
      label: label,
      checked: checked,
      disabled: disabled,
    ),
  );
  MenuItem sub(
    String key,
    String label,
    List<MenuItem> children, {
    bool disabled = false,
  }) => ids.assign(
    MenuItem.submenu(
      key: key,
      label: label,
      disabled: disabled,
      submenu: Menu(items: children),
    ),
  );

  // A4 D20: in both menus; the long-command threshold moved in here (it
  // now works signed out too, push §7 amended).
  MenuItem notifications() =>
      sub(TrayKeys.notifications, l10n.trayNotifications, [
        check(
          TrayKeys.desktopNotifications,
          l10n.trayDesktopNotifications,
          state.desktopNotifications,
        ),
        check(
          TrayKeys.desktopNotificationsOnlyUnfocused,
          l10n.trayDesktopNotificationsUnfocused,
          state.desktopNotificationsOnlyUnfocused,
          disabled: !state.desktopNotifications,
        ),
        sep(),
        sub(TrayKeys.notifyThreshold, l10n.trayNotifyThreshold, [
          for (final seconds in kNotifyThresholdChoices)
            check(
              TrayKeys.notifyThresholdChoice(seconds),
              notifyThresholdLabel(seconds, l10n),
              seconds == state.notifyThresholdSeconds,
            ),
        ]),
      ]);

  // A5a D13, UI-A5 §3: right before "Thông báo", in both menus.
  MenuItem terminal() => sub(TrayKeys.terminal, l10n.trayTerminal, [
    check(
      TrayKeys.restoreScrollback,
      l10n.trayRestoreScrollback,
      local.restoreScrollback,
    ),
    item(
      TrayKeys.clearSavedScrollback,
      l10n.trayClearSavedScrollback,
      disabled: !local.hasSavedScrollback,
    ),
  ]);

  // A7 D26: right after "Thông báo" in both menus (A6's "Trình duyệt",
  // when it lands, goes before it). Toggles apply at once, never ask.
  MenuItem commandLine() => sub(TrayKeys.commandLine, l10n.trayCommandLine, [
    check(TrayKeys.cliControl, l10n.trayCliControl, local.cliControlEnabled),
    check(
      TrayKeys.cliAllowExternal,
      l10n.trayCliAllowExternal,
      local.cliAllowExternal,
    ),
    item(
      TrayKeys.cliPath,
      local.cliPathInstalled ? l10n.trayCliRemovePath : l10n.trayCliInstallPath,
    ),
    item(TrayKeys.cliSkills, l10n.trayCliCopySkills),
  ]);

  if (!state.signedIn) {
    return Menu(
      items: [
        item(TrayKeys.openTerminal, l10n.trayOpenTerminal),
        sep(),
        // UI-A4 §7: after the window item, before the status line.
        terminal(),
        notifications(),
        commandLine(),
        sep(),
        item(TrayKeys.status, '○ ${l10n.trayStatusSignedOut}', disabled: true),
        sep(),
        item(TrayKeys.signIn, l10n.traySignIn),
        item(TrayKeys.quit, l10n.trayQuit),
      ],
    );
  }

  final names = {for (final d in state.trusted) d.mobileId: d.name};
  final sessionItems = [
    for (final s in state.sessions)
      sub(
        TrayKeys.session(s.id),
        s.attachedMobileId == null
            ? l10n.traySessionItem(s.shell, s.index)
            : l10n.traySessionItemAttached(
                s.shell,
                s.index,
                names[s.attachedMobileId] ?? s.attachedMobileId!,
              ),
        [item(TrayKeys.closeSession(s.id), l10n.traySessionClose)],
      ),
    if (state.sessions.isNotEmpty) sep(),
    if (state.sessions.isNotEmpty) item(TrayKeys.closeAll, l10n.trayCloseAll),
  ];
  final deviceItems = state.trusted.isEmpty
      ? [item(TrayKeys.noDevices, l10n.trayNoDevices, disabled: true)]
      : [
          for (final d in state.trusted)
            sub(TrayKeys.device(d.mobileId), d.name, [
              item(TrayKeys.revoke(d.mobileId), l10n.trayRevoke),
            ]),
        ];
  final sharing = state.terminalSharing;
  final terminalItems = [
    for (final t in sharing.sessions)
      sub(
        TrayKeys.desktopTerminal(t.id),
        t.attachedMobileId == null
            ? desktopTerminalLabel(t)
            : '${desktopTerminalLabel(t)} 📱',
        [
          // Spec §7.6: no item ends the terminal.
          item(
            TrayKeys.disconnectPhone(t.id),
            l10n.trayDisconnectPhone,
            disabled: t.attachedMobileId == null,
          ),
        ],
      ),
  ];
  final update = state.update;
  // Binding ruling (Task 8): spec §12 forbids automatic reconnect after a
  // 4001 (`replaced`) close, so the tray offers this explicit way back.
  final replaced = state.relay == RelayConnectionState.replaced;

  return Menu(
    items: [
      // UI §5: the terminal window first, then the status line.
      item(TrayKeys.openTerminal, l10n.trayOpenTerminal),
      sep(),
      item(TrayKeys.status, _statusLine(state, l10n), disabled: true),
      if (replaced) item(TrayKeys.reconnect, l10n.trayReconnect),
      if (update != null)
        item(TrayKeys.downloadUpdate, l10n.trayDownloadUpdate(update.version)),
      sep(),
      check(TrayKeys.remoteAccess, l10n.trayRemoteAccess, state.remoteAccess),
      sub(
        TrayKeys.sessions,
        l10n.traySessions(state.sessions.length),
        sessionItems,
        disabled: state.sessions.isEmpty,
      ),
      if (sharing.available && sharing.enabled)
        sub(
          TrayKeys.desktopTerminals,
          l10n.trayDesktopTerminals(sharing.sessions.length),
          terminalItems,
          disabled: sharing.sessions.isEmpty,
        ),
      item(TrayKeys.pair, l10n.trayPairPhone, disabled: !state.remoteAccess),
      sub(TrayKeys.devices, l10n.trayPairedDevices, deviceItems),
      sep(),
      check(TrayKeys.keepAwake, l10n.trayKeepAwake, state.keepAwake),
      check(
        TrayKeys.launchAtStartup,
        l10n.trayLaunchAtStartup,
        state.launchAtStartup,
      ),
      if (sharing.available)
        check(
          TrayKeys.terminalSharing,
          l10n.trayTerminalSharing,
          sharing.enabled,
          disabled: sharing.busy,
        ),
      if (sharing.available && sharing.enabled && sharing.needsSetup)
        item(
          TrayKeys.terminalSharingSetup,
          '⚠ ${l10n.trayTerminalSharingNeedsSetup}',
          disabled: sharing.busy,
        ),
      // UI-A4 §7: where push §7's threshold submenu was.
      terminal(),
      notifications(),
      commandLine(),
      item(TrayKeys.changePassword, l10n.trayChangePassword),
      item(TrayKeys.signOut, l10n.traySignOut),
      item(TrayKeys.quit, l10n.trayQuit),
    ],
  );
}
