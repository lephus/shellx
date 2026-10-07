import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../agent/agent_controller_base.dart';
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

/// The tray's "Dòng lệnh" settings. `cli_control_enabled` and
/// `cli_allow_external` belong to the process that runs the host (A5b D13):
/// they are read from, and toggled through, the agent, which rechecks the
/// host's open connections itself. `cli_path_installed` is the UI's own.
class CliSettings extends Notifier<CliSettingsState> {
  SettingsStore get _store => ref.read(settingsStoreProvider);

  @override
  CliSettingsState build() {
    final agent = ref.watch(
      agentControllerProvider.select(
        (s) => (s.cliControlEnabled, s.cliAllowExternal),
      ),
    );
    return CliSettingsState(
      controlEnabled: agent.$1,
      allowExternal: agent.$2,
      pathInstalled: ref
          .watch(settingsStoreProvider)
          .getBool(SettingKeys.cliPathInstalled, defaultValue: false),
    );
  }

  AgentControllerBase get _agent => ref.read(agentControllerProvider.notifier);

  Future<void> setControlEnabled(bool value) =>
      _agent.setCliControlEnabled(value);

  Future<void> setAllowExternal(bool value) =>
      _agent.setCliAllowExternal(value);

  /// Failed or not, the state (and the menu) shows what is stored.
  Future<void> setPathInstalled(bool value) async {
    try {
      await _store.setBool(SettingKeys.cliPathInstalled, value);
    } finally {
      state = CliSettingsState(
        controlEnabled: state.controlEnabled,
        allowExternal: state.allowExternal,
        pathInstalled: _store.getBool(
          SettingKeys.cliPathInstalled,
          defaultValue: false,
        ),
      );
    }
  }
}
