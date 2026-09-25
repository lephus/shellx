import 'package:shellx_core/shellx_core.dart';
import 'package:tray_manager/tray_manager.dart';

import '../../l10n/app_localizations.dart';
import '../agent/agent_state.dart';
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

/// Builds the tray menu of spec §8.3 (signed in) or a minimal one (signed out).
Menu buildTrayMenu(
  AgentViewState state,
  AppLocalizations l10n,
  TrayMenuIds ids,
) {
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

  if (!state.signedIn) {
    return Menu(
      items: [
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
  final update = state.update;
  // Binding ruling (Task 8): spec §12 forbids automatic reconnect after a
  // 4001 (`replaced`) close, so the tray offers this explicit way back.
  final replaced = state.relay == RelayConnectionState.replaced;

  return Menu(
    items: [
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
      item(TrayKeys.pair, l10n.trayPairPhone, disabled: !state.remoteAccess),
      sub(TrayKeys.devices, l10n.trayPairedDevices, deviceItems),
      sep(),
      check(TrayKeys.keepAwake, l10n.trayKeepAwake, state.keepAwake),
      check(
        TrayKeys.launchAtStartup,
        l10n.trayLaunchAtStartup,
        state.launchAtStartup,
      ),
      item(TrayKeys.changePassword, l10n.trayChangePassword),
      item(TrayKeys.signOut, l10n.traySignOut),
      item(TrayKeys.quit, l10n.trayQuit),
    ],
  );
}
