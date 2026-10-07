import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../platform/settings_store.dart';
import '../terminal/sidebar_workspaces.dart' show settingsStoreProvider;

/// The tray's "Dòng lệnh" settings (A7 D26, D8, amendment), UI-owned.
@immutable
final class CliSettingsState {
  const CliSettingsState({
    this.controlEnabled = true,
    this.allowExternal = false,
    this.pathInstalled = false,
  });

  /// `cli_control_enabled`, default on.
  final bool controlEnabled;

  /// `cli_allow_external` ("Allow other terminals"), default off.
  final bool allowExternal;

  /// `cli_path_installed`: the item reads "Remove…" instead of "Install…".
  final bool pathInstalled;

  @override
  bool operator ==(Object other) =>
      other is CliSettingsState &&
      other.controlEnabled == controlEnabled &&
      other.allowExternal == allowExternal &&
      other.pathInstalled == pathInstalled;

  @override
  int get hashCode => Object.hash(controlEnabled, allowExternal, pathInstalled);
}

final cliSettingsProvider = NotifierProvider<CliSettings, CliSettingsState>(
  CliSettings.new,
);

/// Reads and writes the three settings; the tray menu watches it. The host
/// reads the store itself on every request; [onChanged] lets it apply a
/// change of the switch or of "Allow other terminals" to open connections
/// at once (`CliHost.recheck`).
class CliSettings extends Notifier<CliSettingsState> {
  /// Set by `CliService` while the host runs.
  void Function()? onChanged;

  SettingsStore get _store => ref.read(settingsStoreProvider);

  @override
  CliSettingsState build() => _from(ref.watch(settingsStoreProvider));

  static CliSettingsState _from(SettingsStore s) => CliSettingsState(
    controlEnabled: s.getBool(
      SettingKeys.cliControlEnabled,
      defaultValue: true,
    ),
    allowExternal: s.getBool(SettingKeys.cliAllowExternal, defaultValue: false),
    pathInstalled: s.getBool(SettingKeys.cliPathInstalled, defaultValue: false),
  );

  Future<void> setControlEnabled(bool value) => _apply(
    () => _store.setBool(SettingKeys.cliControlEnabled, value),
    recheck: true,
  );

  Future<void> setAllowExternal(bool value) => _apply(
    () => _store.setBool(SettingKeys.cliAllowExternal, value),
    recheck: true,
  );

  Future<void> setPathInstalled(bool value) => _apply(
    () => _store.setBool(SettingKeys.cliPathInstalled, value),
    recheck: false,
  );

  /// Failed or not, the state (and the menu) shows what is stored, and the
  /// host applies it.
  Future<void> _apply(
    Future<void> Function() write, {
    required bool recheck,
  }) async {
    try {
      await write();
    } finally {
      state = _from(_store);
      if (recheck) onChanged?.call();
    }
  }
}
