import 'dart:async';
import 'dart:convert';

import 'package:tray_manager/tray_manager.dart';

import '../../l10n/app_localizations.dart';
import '../agent/agent_state.dart';
import 'tray_action.dart';
import 'tray_menu.dart';

abstract interface class TrayHost {
  Future<void> setIcon(String asset, {required bool isTemplate});
  Future<void> setToolTip(String text);
  Future<void> setMenu(Menu menu);
}

/// Mirrors [AgentViewState] into the tray icon and menu; routes clicks.
final class TrayPresenter {
  TrayPresenter({
    required TrayHost host,
    required AppLocalizations l10n,
    required bool isWindows,
    required Future<void> Function(TrayAction action) onAction,
  }) : _host = host,
       _l10n = l10n,
       _isWindows = isWindows,
       _onAction = onAction;

  final TrayHost _host;
  final AppLocalizations _l10n;
  final bool _isWindows;
  final Future<void> Function(TrayAction action) _onAction;
  final TrayMenuIds _ids = TrayMenuIds();
  TrayIconState? _icon;

  /// The last menu set, as its JSON: a state change the menu does not show
  /// (a tab title, a running command, a phone typing) must not rebuild the
  /// native menu (ruling I3; an open menu would also flicker).
  String? _menu;
  AgentViewState? _pending;
  bool _busy = false;

  /// Coalesces bursts of state changes into the latest one.
  Future<void> render(AgentViewState state) async {
    _pending = state;
    if (_busy) return;
    _busy = true;
    try {
      while (_pending != null) {
        final next = _pending!;
        _pending = null;
        await _render(next);
      }
    } finally {
      _busy = false;
    }
  }

  Future<void> _render(AgentViewState state) async {
    final icon = trayIconFor(state);
    if (icon != _icon) {
      await _host.setIcon(
        trayIconAsset(icon, windows: _isWindows),
        isTemplate: !_isWindows && icon != TrayIconState.active,
      );
      // Only once it is set: a failed setIcon is retried on the next render.
      _icon = icon;
      await _host.setToolTip(_l10n.trayTooltip);
    }
    final menu = buildTrayMenu(state, _l10n, _ids);
    final json = jsonEncode(menu.toJson());
    if (json == _menu) return;
    await _host.setMenu(menu);
    // Only once it is set: a failed setMenu is retried on the next render.
    _menu = json;
  }

  void onMenuItemClick(MenuItem item) {
    final action = trayActionForKey(item.key);
    if (action != null) unawaited(_onAction(action));
  }
}

/// [TrayHost] over package tray_manager. Left and right click open the menu.
final class TrayManagerHost with TrayListener implements TrayHost {
  TrayManagerHost({required void Function(MenuItem item) onClick})
    : _onClick = onClick {
    trayManager.addListener(this);
  }

  final void Function(MenuItem item) _onClick;

  @override
  Future<void> setIcon(String asset, {required bool isTemplate}) =>
      trayManager.setIcon(asset, isTemplate: isTemplate);

  @override
  Future<void> setToolTip(String text) => trayManager.setToolTip(text);

  @override
  Future<void> setMenu(Menu menu) => trayManager.setContextMenu(menu);

  @override
  void onTrayIconMouseDown() => trayManager.popUpContextMenu();

  @override
  void onTrayIconRightMouseDown() => trayManager.popUpContextMenu();

  @override
  void onTrayMenuItemClick(MenuItem menuItem) => _onClick(menuItem);

  Future<void> destroy() async {
    trayManager.removeListener(this);
    await trayManager.destroy();
  }
}
