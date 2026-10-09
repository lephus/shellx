import 'package:flutter/foundation.dart' show TargetPlatform, immutable;

import '../../l10n/app_localizations.dart';
import '../platform/settings_store.dart';
import '../tray/tray_action.dart';
import '../ui/config/command_palette.dart' show matchScore;
import 'config_paths.dart';
import 'config_state.dart';

/// A11 D4: who owns a setting. Exactly one.
/// - [file]: a key of the configuration file. Settings reads `ConfigState`
///   and writes the file (`applyKeyEdits`).
/// - [app]: a switch of `SettingsStore` / the service. Settings calls the
///   same `TrayActions.handle(TrayAction)` as the tray and reads the same
///   providers. [SettingDef.storeKey] names the stored key.
enum SettingOwner { file, app }

enum SettingPage {
  general,
  appearance,
  terminal,
  keys,
  agents,
  phone,
  advanced,
}

enum SettingControl {
  toggle,
  slider,
  segmented,
  choice,
  text,
  color,
  hotkey,
  action,
  path,
}

String settingPageLabel(SettingPage page, AppLocalizations l10n) =>
    switch (page) {
      SettingPage.general => l10n.settingsPageGeneral,
      SettingPage.appearance => l10n.settingsPageAppearance,
      SettingPage.terminal => l10n.settingsPageTerminal,
      SettingPage.keys => l10n.settingsPageKeys,
      SettingPage.agents => l10n.settingsPageAgents,
      SettingPage.phone => l10n.settingsPagePhone,
      SettingPage.advanced => l10n.settingsPageAdvanced,
    };

/// A choice of a segmented or choice control: the wire value (what goes in
/// the file) and its label.
@immutable
final class SettingChoice {
  const SettingChoice(this.wire, this.label);
  final String wire;
  final String Function(AppLocalizations l10n) label;
}

/// A value the round-trip test writes ([raw]) and, when [shown] is not
/// null, expects `shellx config show` to print.
@immutable
final class SettingSample {
  const SettingSample(this.raw, [this.shown]);
  final String raw;
  final String? shown;
}

@immutable
final class SettingDef {
  const SettingDef({
    required this.id,
    required this.owner,
    required this.page,
    required this.control,
    required this.label,
    this.fileKey,
    this.toggle,
    this.storeKey,
    this.daemonOwned = false,
    this.appDefault,
    this.min,
    this.max,
    this.step,
    this.choices,
    this.sampleValues = const [],
    this.keywords = const [],
    this.onlyOn,
    this.description,
  });

  /// Unique; a file setting's id is its key.
  final String id;
  final SettingOwner owner;
  final SettingPage page;
  final SettingControl control;
  final String Function(AppLocalizations l10n) label;
  final String Function(AppLocalizations l10n)? description;

  /// [SettingOwner.file] only.
  final String? fileKey;

  /// [SettingOwner.app] only: the action the tray also uses (a
  /// representative one for a multi-valued switch, `SetNotifyThreshold`,
  /// `SetAppLanguage`).
  final TrayAction? toggle;

  /// [SettingOwner.app], UI-owned switches only: the `SettingKeys` value
  /// (a `UiSettingKeys` key). The UI never names a daemon key (A5b D13):
  /// those switches are [daemonOwned], read from `AgentViewState` and
  /// written through `TrayActions.handle`; `settings_schema_test` maps each
  /// to its `DaemonSettingKeys` entry.
  final String? storeKey;

  /// [SettingOwner.app]: the daemon owns the stored value (no [storeKey]).
  final bool daemonOwned;

  /// [SettingOwner.app] only, when the store's default is not "off".
  final bool? appDefault;

  final double? min, max, step;
  final List<SettingChoice>? choices;
  final List<SettingSample> sampleValues;

  /// Extra words that find the row (English and Vietnamese).
  final List<String> keywords;

  /// The row exists on this platform only.
  final TargetPlatform? onlyOn;
}

final List<SettingDef> kSettings = List.unmodifiable([
  // Appearance
  SettingDef(
    id: 'theme',
    owner: SettingOwner.file,
    page: SettingPage.appearance,
    control: SettingControl.choice,
    fileKey: 'theme',
    label: (l) => l.settingsTheme,
    keywords: const ['color scheme', 'dark', 'light', 'màu', 'giao diện'],
    sampleValues: const [SettingSample('Dracula')],
  ),
  SettingDef(
    id: 'font-family',
    owner: SettingOwner.file,
    page: SettingPage.appearance,
    control: SettingControl.text,
    fileKey: 'font-family',
    label: (l) => l.settingsFontFamily,
    keywords: const ['typeface', 'phông', 'chữ'],
    sampleValues: const [SettingSample('Menlo', 'Menlo')],
  ),
  SettingDef(
    id: 'font-size',
    owner: SettingOwner.file,
    page: SettingPage.appearance,
    control: SettingControl.slider,
    fileKey: 'font-size',
    min: 9,
    max: 28,
    step: 0.5,
    label: (l) => l.settingsFontSize,
    keywords: const ['text size', 'zoom', 'cỡ', 'to', 'nhỏ'],
    sampleValues: const [
      SettingSample('15', '15'),
      SettingSample('9.5', '9.5'),
      SettingSample('28', '28'),
    ],
  ),
  SettingDef(
    id: 'font-weight',
    owner: SettingOwner.file,
    page: SettingPage.appearance,
    control: SettingControl.segmented,
    fileKey: 'font-weight',
    label: (l) => l.settingsFontWeight,
    keywords: const ['bold', 'thin', 'light', 'đậm', 'nhẹ'],
    choices: [
      SettingChoice('light', (l) => l.settingsFontWeightLight),
      SettingChoice('regular', (l) => l.settingsFontWeightRegular),
    ],
    sampleValues: const [
      SettingSample('regular', 'regular'),
      SettingSample('light', 'light'),
    ],
  ),
  SettingDef(
    id: 'adjust-cell-height',
    owner: SettingOwner.file,
    page: SettingPage.appearance,
    control: SettingControl.slider,
    fileKey: 'adjust-cell-height',
    min: -10,
    max: 50,
    step: 1,
    label: (l) => l.settingsCellHeight,
    keywords: const ['line spacing', 'leading', 'dòng', 'giãn'],
    sampleValues: const [
      SettingSample('15%', '15%'),
      SettingSample('-5%', '-5%'),
      SettingSample('50', '50%'),
    ],
  ),
  SettingDef(
    id: 'window-padding-x',
    owner: SettingOwner.file,
    page: SettingPage.appearance,
    control: SettingControl.slider,
    fileKey: 'window-padding-x',
    min: 0,
    max: 64,
    step: 1,
    label: (l) => l.settingsPadding,
    keywords: const ['margin', 'horizontal', 'ngang', 'viền'],
    sampleValues: const [
      SettingSample('10,20', '10,20'),
      SettingSample('8', '8'),
    ],
  ),
  SettingDef(
    id: 'window-padding-y',
    owner: SettingOwner.file,
    page: SettingPage.appearance,
    control: SettingControl.slider,
    fileKey: 'window-padding-y',
    min: 0,
    max: 64,
    step: 1,
    label: (l) => l.settingsPadding,
    keywords: const ['margin', 'vertical', 'dọc', 'viền'],
    sampleValues: const [
      SettingSample('6,12', '6,12'),
      SettingSample('0', '0'),
    ],
  ),
  SettingDef(
    id: 'cursor-style',
    owner: SettingOwner.file,
    page: SettingPage.appearance,
    control: SettingControl.segmented,
    fileKey: 'cursor-style',
    label: (l) => l.settingsCursorStyle,
    keywords: const ['caret', 'block', 'bar', 'underline', 'trỏ'],
    choices: [
      SettingChoice('block', (l) => l.settingsCursorBlock),
      SettingChoice('bar', (l) => l.settingsCursorBar),
      SettingChoice('underline', (l) => l.settingsCursorUnderline),
    ],
    sampleValues: const [
      SettingSample('bar', 'bar'),
      SettingSample('underline', 'underline'),
      SettingSample('block', 'block'),
    ],
  ),
  SettingDef(
    id: 'cursor-style-blink',
    owner: SettingOwner.file,
    page: SettingPage.appearance,
    control: SettingControl.toggle,
    fileKey: 'cursor-style-blink',
    label: (l) => l.settingsCursorBlink,
    keywords: const ['blink', 'flash', 'nhấp nháy', 'trỏ'],
    sampleValues: const [
      SettingSample('true', 'true'),
      SettingSample('false', 'false'),
    ],
  ),
  SettingDef(
    id: 'background',
    owner: SettingOwner.file,
    page: SettingPage.appearance,
    control: SettingControl.color,
    fileKey: 'background',
    label: (l) => l.settingsBackground,
    keywords: const ['color', 'màu', 'nền'],
    sampleValues: const [SettingSample('#102030')],
  ),
  SettingDef(
    id: 'foreground',
    owner: SettingOwner.file,
    page: SettingPage.appearance,
    control: SettingControl.color,
    fileKey: 'foreground',
    label: (l) => l.settingsForeground,
    keywords: const ['color', 'text', 'màu', 'chữ'],
    sampleValues: const [SettingSample('#d0e0f0')],
  ),
  SettingDef(
    id: 'cursor-color',
    owner: SettingOwner.file,
    page: SettingPage.appearance,
    control: SettingControl.color,
    fileKey: 'cursor-color',
    label: (l) => l.settingsCursorColor,
    keywords: const ['caret', 'màu', 'trỏ'],
    sampleValues: const [SettingSample('#ff0000', '#ff0000')],
  ),
  SettingDef(
    id: 'selection-background',
    owner: SettingOwner.file,
    page: SettingPage.appearance,
    control: SettingControl.color,
    fileKey: 'selection-background',
    label: (l) => l.settingsSelectionColor,
    keywords: const ['highlight', 'select', 'màu', 'chọn'],
    sampleValues: const [SettingSample('#00ff80', '#00ff80')],
  ),
  // Terminal
  SettingDef(
    id: 'scrollback-limit',
    owner: SettingOwner.file,
    page: SettingPage.terminal,
    control: SettingControl.slider,
    fileKey: 'scrollback-limit',
    min: 1000,
    max: 100000,
    step: 1000,
    label: (l) => l.settingsScrollback,
    keywords: const ['history', 'buffer', 'lịch sử', 'cuộn'],
    sampleValues: const [
      SettingSample('5000', '5000'),
      SettingSample('100000', '100000'),
    ],
  ),
  SettingDef(
    id: 'working-directory',
    owner: SettingOwner.file,
    page: SettingPage.terminal,
    control: SettingControl.path,
    fileKey: 'working-directory',
    label: (l) => l.settingsWorkingDir,
    keywords: const ['folder', 'cwd', 'home', 'thư mục'],
    sampleValues: const [
      SettingSample('inherit', 'inherit'),
      SettingSample('home', 'home'),
      SettingSample('/tmp', '/tmp'),
    ],
  ),
  SettingDef(
    id: 'macos-option-as-alt',
    owner: SettingOwner.file,
    page: SettingPage.terminal,
    control: SettingControl.choice,
    fileKey: 'macos-option-as-alt',
    onlyOn: TargetPlatform.macOS,
    label: (l) => l.settingsOptionAsAlt,
    keywords: const ['meta', 'alt', 'option', 'mac'],
    sampleValues: const [
      SettingSample('left', 'left'),
      SettingSample('true', 'true'),
      SettingSample('right', 'right'),
      SettingSample('false', 'false'),
    ],
  ),
  SettingDef(
    id: 'confirm-close-surface',
    owner: SettingOwner.file,
    page: SettingPage.terminal,
    control: SettingControl.segmented,
    fileKey: 'confirm-close-surface',
    label: (l) => l.settingsConfirmClose,
    keywords: const ['quit', 'close', 'confirm', 'đóng', 'xác nhận'],
    choices: [
      SettingChoice('true', (l) => l.settingsConfirmCloseRunning),
      SettingChoice('false', (l) => l.settingsConfirmCloseNever),
      SettingChoice('always', (l) => l.settingsConfirmCloseAlways),
    ],
    sampleValues: const [
      SettingSample('always', 'always'),
      SettingSample('false', 'false'),
      SettingSample('true', 'true'),
    ],
  ),
  SettingDef(
    id: 'global-hotkey',
    owner: SettingOwner.file,
    page: SettingPage.terminal,
    control: SettingControl.hotkey,
    fileKey: 'global-hotkey',
    label: (l) => l.settingsGlobalHotkey,
    keywords: const [
      'shortcut',
      'show',
      'hide',
      'toggle',
      'quake',
      'phím tắt',
      'ẩn',
      'hiện',
    ],
    sampleValues: const [
      SettingSample('ctrl+alt+j', 'ctrl+alt+j'),
      SettingSample('ctrl+alt+shift+f5', 'ctrl+alt+shift+f5'),
    ],
  ),
  // Advanced
  SettingDef(
    id: 'ghostty-config',
    owner: SettingOwner.file,
    page: SettingPage.advanced,
    control: SettingControl.toggle,
    fileKey: 'ghostty-config',
    label: (l) => l.settingsGhosttyConfig,
    keywords: const ['import', 'ghostty'],
    sampleValues: const [
      SettingSample('false', 'false'),
      SettingSample('true', 'true'),
    ],
  ),
  // App switches: the tray's, one row each.
  SettingDef(
    id: 'app-language',
    owner: SettingOwner.app,
    page: SettingPage.general,
    control: SettingControl.choice,
    toggle: const SetAppLanguage('system'),
    storeKey: SettingKeys.appLanguage,
    label: (l) => l.settingLanguage,
    keywords: const [
      'language',
      'english',
      'vietnamese',
      'locale',
      'ngôn ngữ',
      'tiếng việt',
      'tiếng anh',
    ],
    choices: [
      SettingChoice('system', (l) => l.settingLanguageSystem),
      SettingChoice('en', (l) => l.settingLanguageEn),
      SettingChoice('vi', (l) => l.settingLanguageVi),
    ],
  ),
  SettingDef(
    id: 'launch-at-startup',
    owner: SettingOwner.app,
    page: SettingPage.general,
    control: SettingControl.toggle,
    toggle: const ToggleLaunchAtStartup(),
    daemonOwned: true,
    label: (l) => l.trayLaunchAtStartup,
    keywords: const ['login', 'boot', 'khởi động'],
  ),
  SettingDef(
    id: 'keep-awake',
    owner: SettingOwner.app,
    page: SettingPage.general,
    control: SettingControl.toggle,
    toggle: const ToggleKeepAwake(),
    daemonOwned: true,
    label: (l) => l.trayKeepAwake,
    keywords: const ['sleep', 'caffeinate', 'ngủ'],
  ),
  SettingDef(
    id: 'background-service',
    owner: SettingOwner.app,
    page: SettingPage.general,
    control: SettingControl.toggle,
    toggle: const ToggleBackgroundService(),
    storeKey: SettingKeys.backgroundService,
    appDefault: SettingKeys.backgroundServiceDefault,
    label: (l) => l.trayBackgroundService,
    keywords: const ['daemon', 'service', 'dịch vụ nền'],
  ),
  SettingDef(
    id: 'restore-scrollback',
    owner: SettingOwner.app,
    page: SettingPage.terminal,
    control: SettingControl.toggle,
    toggle: const ToggleRestoreScrollback(),
    storeKey: SettingKeys.terminalRestoreScrollback,
    label: (l) => l.trayRestoreScrollback,
    keywords: const ['restore', 'save', 'lưu', 'khôi phục'],
  ),
  SettingDef(
    id: 'desktop-notifications',
    owner: SettingOwner.app,
    page: SettingPage.agents,
    control: SettingControl.toggle,
    toggle: const ToggleDesktopNotifications(),
    daemonOwned: true,
    label: (l) => l.trayDesktopNotifications,
    keywords: const ['notify', 'alert', 'thông báo'],
  ),
  SettingDef(
    id: 'desktop-notifications-only-unfocused',
    owner: SettingOwner.app,
    page: SettingPage.agents,
    control: SettingControl.toggle,
    toggle: const ToggleDesktopNotificationsOnlyUnfocused(),
    daemonOwned: true,
    label: (l) => l.trayDesktopNotificationsUnfocused,
    keywords: const ['notify', 'background', 'thông báo', 'nền'],
  ),
  SettingDef(
    id: 'agent-resume',
    owner: SettingOwner.file,
    page: SettingPage.agents,
    control: SettingControl.segmented,
    fileKey: 'agent-resume',
    label: (l) => l.settingAgentResume,
    description: (l) => l.settingAgentResumeDesc,
    keywords: const ['restart', 'session', 'claude', 'tiếp tục', 'phiên'],
    choices: [
      SettingChoice('ask', (l) => l.settingAgentResumeAsk),
      SettingChoice('off', (l) => l.settingAgentResumeOff),
    ],
    sampleValues: const [
      SettingSample('off', 'off'),
      SettingSample('ask', 'ask'),
    ],
  ),
  SettingDef(
    id: 'pr-status',
    owner: SettingOwner.file,
    page: SettingPage.agents,
    control: SettingControl.toggle,
    fileKey: 'pr-status',
    label: (l) => l.settingPrStatus,
    description: (l) => l.settingPrStatusDesc,
    keywords: const ['github', 'gh', 'pull request', 'ci', 'checks'],
    sampleValues: const [
      SettingSample('true', 'true'),
      SettingSample('false', 'false'),
    ],
  ),
  SettingDef(
    id: 'notify-threshold',
    owner: SettingOwner.app,
    page: SettingPage.agents,
    control: SettingControl.choice,
    toggle: const SetNotifyThreshold(0),
    daemonOwned: true,
    label: (l) => l.trayNotifyThreshold,
    keywords: const ['long command', 'finish', 'lệnh chạy lâu', 'xong'],
  ),
  SettingDef(
    id: 'cli-control',
    owner: SettingOwner.app,
    page: SettingPage.agents,
    control: SettingControl.toggle,
    toggle: const ToggleCliControl(),
    daemonOwned: true,
    label: (l) => l.trayCliControl,
    keywords: const ['shellx command', 'cli', 'dòng lệnh'],
  ),
  SettingDef(
    id: 'cli-allow-external',
    owner: SettingOwner.app,
    page: SettingPage.agents,
    control: SettingControl.toggle,
    toggle: const ToggleCliAllowExternal(),
    daemonOwned: true,
    label: (l) => l.trayCliAllowExternal,
    keywords: const ['cli', 'other terminals', 'dòng lệnh'],
  ),
  SettingDef(
    id: 'cli-path',
    owner: SettingOwner.app,
    page: SettingPage.agents,
    control: SettingControl.toggle,
    toggle: const ToggleCliPath(),
    storeKey: SettingKeys.cliPathInstalled,
    label: (l) => l.trayCliInstallPath,
    keywords: const ['cli', 'path', 'install', 'cài', 'dòng lệnh'],
  ),
  SettingDef(
    id: 'ssh-hook',
    owner: SettingOwner.app,
    page: SettingPage.agents,
    control: SettingControl.toggle,
    toggle: const ToggleSshHook(),
    daemonOwned: true,
    appDefault: true,
    label: (l) => l.sshTrayHook,
    keywords: const ['ssh', 'server', 'máy chủ'],
  ),
  SettingDef(
    id: 'remote-access',
    owner: SettingOwner.app,
    page: SettingPage.phone,
    control: SettingControl.toggle,
    toggle: const ToggleRemoteAccess(),
    daemonOwned: true,
    label: (l) => l.trayRemoteAccess,
    keywords: const ['phone', 'mobile', 'điện thoại', 'từ xa'],
  ),
  SettingDef(
    id: 'terminal-sharing',
    owner: SettingOwner.app,
    page: SettingPage.phone,
    control: SettingControl.toggle,
    toggle: const ToggleTerminalSharing(),
    daemonOwned: true,
    label: (l) => l.trayTerminalSharing,
    keywords: const ['phone', 'mirror', 'điện thoại', 'chia sẻ'],
  ),
]);

/// The rows whose label, key name or keywords match [query] (the command
/// palette's matcher), best first, ties in catalogue order. Empty query: none.
List<SettingDef> searchSettings(String query, AppLocalizations l10n) {
  final q = query.trim();
  if (q.isEmpty) return const [];
  final scored = <(SettingDef, int, int)>[];
  for (var i = 0; i < kSettings.length; i++) {
    final d = kSettings[i];
    final best = [
      matchScore(q, d.label(l10n)),
      if (d.fileKey != null) matchScore(q, d.fileKey!, subsequence: false),
      matchScore(q, d.id, subsequence: false),
      ?_minus(matchScore(q, d.keywords.join(' '), subsequence: false), 300),
    ].nonNulls.fold<int?>(null, (a, s) => a == null || s > a ? s : a);
    if (best != null) scored.add((d, best, i));
  }
  scored.sort((a, b) {
    final s = b.$2.compareTo(a.$2);
    return s != 0 ? s : a.$3.compareTo(b.$3);
  });
  return [for (final s in scored) s.$1];
}

int? _minus(int? v, int by) => v == null ? null : v - by;

/// Where a file setting's effective value comes from (A11 D5.2–4).
sealed class SettingSource {
  const SettingSource();
}

/// A line inside ShellX's own settings block: ShellX wrote it.
final class OwnSource extends SettingSource {
  const OwnSource();
}

/// A line the user wrote in the ShellX file: edited in place.
final class UserLineSource extends SettingSource {
  const UserLineSource(this.file, this.line);
  final String file;
  final int line;
}

/// From a Ghostty file: a change here overrides it for ShellX.
final class GhosttySource extends SettingSource {
  const GhosttySource();
}

/// From an included file: the row is read-only.
final class IncludeSource extends SettingSource {
  const IncludeSource(this.file, this.line);
  final String file;
  final int line;
}

/// `font-family` on several lines: edited in the file only.
final class MultiLineSource extends SettingSource {
  const MultiLineSource();
}

final class DefaultSource extends SettingSource {
  const DefaultSource();
}

/// [ownBlock] is the 1-based line range of the settings block in
/// [ConfigPaths.shellx] (`settingsBlockLines` of its text), or null.
SettingSource settingSource(
  SettingDef def,
  ConfigState state,
  ConfigPaths paths, {
  ({int first, int last})? ownBlock,
}) {
  final key = def.fileKey;
  if (key == null) return const DefaultSource();
  if (key == 'font-family' && state.config.fontFamilyOrigins.length > 1) {
    return const MultiLineSource();
  }
  final origin = state.config.origins[key];
  if (origin == null) return const DefaultSource();
  if (origin.file == paths.shellx) {
    if (ownBlock != null &&
        origin.line > ownBlock.first &&
        origin.line < ownBlock.last) {
      return const OwnSource();
    }
    return UserLineSource(origin.file, origin.line);
  }
  if (paths.ghostty.contains(origin.file)) return const GhosttySource();
  return IncludeSource(origin.file, origin.line);
}
