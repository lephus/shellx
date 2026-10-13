import 'package:flutter/painting.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../../agent/agent_state.dart';
import '../../config/config_controller.dart';
import '../../config/config_syntax.dart' show decodeConfigBytes;
import '../../config/config_key_edits.dart' show settingsBlockLines;
import '../../config/config_writer.dart';
import '../../config/keybind_trigger.dart' show chordConfigText;
import '../../config/settings_schema.dart';
import '../../config/shellx_config.dart';
import '../../terminal/terminal_tabs.dart';
import '../../tray/tray_menu.dart' show TrayLocalState;
import '../../terminal/terminal_style.dart' show kTerminalFontSizeDefault;
import 'settings_writer.dart';

String _num(double v) =>
    v == v.roundToDouble() ? v.toInt().toString() : v.toString();

String _hex(Color? c) {
  if (c == null) return '';
  String h(double v) => (v * 255).round().toRadixString(16).padLeft(2, '0');
  return '#${h(c.r)}${h(c.g)}${h(c.b)}';
}

String _pair(double a, double b) => a == b ? _num(a) : '${_num(a)},${_num(b)}';

/// The effective value of a file setting as the text the file would hold
/// (what the row's control shows). Read from the loaded [ShellxConfig]; the
/// window keeps no copy. [liveFontSize] is the size the panes use when the
/// file sets none (the saved ⌘+/⌘− size).
String fileSettingText(
  SettingDef def,
  ShellxConfig c, {
  double? liveFontSize,
}) => switch (def.fileKey) {
  'theme' => c.theme ?? '',
  'font-family' => c.fontFamilies.isEmpty ? '' : c.fontFamilies.first,
  'font-size' => _num(c.fontSize ?? liveFontSize ?? kTerminalFontSizeDefault),
  'font-weight' => c.fontWeight.name,
  'adjust-cell-height' => _num(c.cellHeightPercent),
  'window-padding-x' => _pair(c.padding.left, c.padding.right),
  'window-padding-y' => _pair(c.padding.top, c.padding.bottom),
  'cursor-style' => c.cursorShape.name,
  'cursor-style-blink' => '${c.cursorBlink}',
  'background' => _hex(c.background),
  'foreground' => _hex(c.foreground),
  'cursor-color' => _hex(c.cursorColor),
  'selection-background' => _hex(c.selectionBackground),
  'scrollback-limit' => '${c.scrollbackLimit}',
  'working-directory' => switch (c.workingDirectory.kind) {
    WorkingDirectoryKind.home => 'home',
    WorkingDirectoryKind.inherit => 'inherit',
    WorkingDirectoryKind.path => c.workingDirectory.path ?? 'home',
  },
  'macos-option-as-alt' => switch (c.optionAsAlt) {
    OptionAsAlt.off => 'false',
    OptionAsAlt.both => 'true',
    OptionAsAlt.left => 'left',
    OptionAsAlt.right => 'right',
  },
  'confirm-close-surface' => switch (c.confirmClose) {
    ConfirmClose.whenRunning => 'true',
    ConfirmClose.never => 'false',
    ConfirmClose.always => 'always',
  },
  'ghostty-config' => '${c.ghosttyConfig}',
  'agent-resume' => c.agentResume.name,
  'link-editor' => c.linkEditor.name,
  'pr-status' => '${c.prStatus}',
  'global-hotkey' =>
    c.globalHotkey == null ? '' : chordConfigText(c.globalHotkey!) ?? '',
  _ => '',
};

/// The state of an app switch, from what the tray reads (`AgentViewState`
/// for the daemon's switches, `TrayLocalState` for the UI's own).
bool appSwitchValue(SettingDef def, AgentViewState a, TrayLocalState l) =>
    switch (def.id) {
      'launch-at-startup' => a.launchAtStartup,
      'keep-awake' => a.keepAwake,
      'background-service' => l.backgroundService,
      'restore-scrollback' => l.restoreScrollback,
      'desktop-notifications' => a.desktopNotifications,
      'desktop-notifications-only-unfocused' =>
        a.desktopNotificationsOnlyUnfocused,
      'cli-control' => l.cliControlEnabled,
      'cli-allow-external' => l.cliAllowExternal,
      'cli-path' => l.cliPathInstalled,
      'ssh-hook' => l.sshHook,
      'remote-access' => a.remoteAccess,
      'terminal-sharing' => a.terminalSharing.enabled,
      _ => false,
    };

/// The row's label; the two padding rows tell X from Y.
String settingLabel(SettingDef def, AppLocalizations l10n) =>
    switch (def.fileKey) {
      'window-padding-x' => '${def.label(l10n)} · X',
      'window-padding-y' => '${def.label(l10n)} · Y',
      _ => def.label(l10n),
    };

/// The marker lines of Settings' own block in the ShellX file as last
/// loaded (for [settingSource]): re-read when a load happens.
final settingsOwnBlockProvider =
    FutureProvider.autoDispose<({int first, int last})?>((ref) async {
      ref.watch(shellxConfigProvider.select((s) => s.generation));
      try {
        final bytes = await ref
            .read(configFileStoreProvider)
            .read(ref.read(configPathsProvider).shellx);
        return bytes == null
            ? null
            : settingsBlockLines(decodeConfigBytes(bytes));
      } catch (_) {
        return null; // Unreadable: every line shows as the user's own.
      }
    });

/// The last write that did not work and is still worth a line at the foot of
/// the window (a toast may sit under the window's scrim).
final settingsStatusProvider =
    NotifierProvider.autoDispose<SettingsStatus, SettingsWrite?>(
      SettingsStatus.new,
    );

class SettingsStatus extends Notifier<SettingsWrite?> {
  @override
  SettingsWrite? build() => null;

  void report(SettingsWrite? write) => state = write;
}

/// What a write's result asks of the window besides the row's own error
/// line: the toast of spec §4.1 and the footer line.
void reportWrite(WidgetRef ref, SettingsWrite result) {
  final notice = writeNotice(result);
  if (notice != null) {
    ref.read(terminalTabsProvider.notifier).showNotice(notice);
  }
  switch (result) {
    case Saved():
      ref.read(settingsStatusProvider.notifier).report(null);
    case Invalid():
      break;
    case Changed() || Refused():
      ref.read(settingsStatusProvider.notifier).report(result);
  }
}

/// The toast a write's result asks for, or null when it asks for none.
TabNotice? writeNotice(SettingsWrite result) => switch (result) {
  Saved() || Invalid() => null,
  Changed() => const SettingsFileChangedNotice(),
  Refused(:final why) when why == ConfigWriteRefusal.damagedBlock =>
    const SettingsFileDamagedNotice(),
  Refused() => const SettingsFileUnwritableNotice(),
};
