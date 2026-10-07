import 'package:flutter/foundation.dart' show TargetPlatform;
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/l10n/app_localizations_en.dart';
import 'package:shellx_desktop/l10n/app_localizations_vi.dart';
import 'package:shellx_desktop/src/config/config_key_edits.dart';
import 'package:shellx_desktop/src/config/config_paths.dart';
import 'package:shellx_desktop/src/config/config_state.dart';
import 'package:shellx_desktop/src/config/config_syntax.dart';
import 'package:shellx_desktop/src/config/config_theme.dart';
import 'package:shellx_desktop/src/config/keybindings.dart';
import 'package:shellx_desktop/src/config/settings_schema.dart';
import 'package:shellx_desktop/src/config/shellx_config.dart';
import 'package:shellx_desktop/src/platform/settings_store.dart';
import 'package:shellx_desktop/src/tray/tray_action.dart';

void main() {
  final en = AppLocalizationsEn();
  final vi = AppLocalizationsVi();

  test('every def has a unique id and exactly one owner', () {
    final ids = kSettings.map((d) => d.id).toList();
    expect(ids.toSet().length, ids.length);
    for (final d in kSettings) {
      if (d.owner == SettingOwner.file) {
        expect(d.fileKey, isNotNull, reason: d.id);
        expect(d.toggle, isNull, reason: d.id);
        expect(d.storeKey, isNull, reason: d.id);
      } else {
        expect(d.toggle, isNotNull, reason: d.id);
        expect(d.fileKey, isNull, reason: d.id);
        // Exactly one process owns the stored value.
        expect(d.daemonOwned != (d.storeKey != null), isTrue, reason: d.id);
      }
    }
  });

  test(
    'no config key is offered twice and none is also an app switch (D4)',
    () {
      final keys = [
        for (final d in kSettings)
          if (d.fileKey != null) d.fileKey!,
      ];
      expect(keys.toSet().length, keys.length);
      final stored = [
        for (final d in kSettings)
          if (d.storeKey != null) d.storeKey!,
      ];
      expect(stored.toSet().length, stored.length);
      expect(keys.toSet().intersection(SettingKeys.all), isEmpty);
    },
  );

  test('every app row names its owner process: UI keys by store key, daemon '
      'keys by the mapping here (the UI code never spells them)', () {
    const daemonKeyOf = {
      'launch-at-startup': SettingKeys.launchAtStartup,
      'keep-awake': SettingKeys.keepAwake,
      'desktop-notifications': SettingKeys.desktopNotifications,
      'desktop-notifications-only-unfocused':
          SettingKeys.desktopNotificationsOnlyUnfocused,
      'notify-threshold': SettingKeys.notifyThreshold,
      'cli-control': SettingKeys.cliControlEnabled,
      'cli-allow-external': SettingKeys.cliAllowExternal,
      'ssh-hook': SettingKeys.sshRemoteHook,
      'remote-access': SettingKeys.remoteAccess,
      'terminal-sharing': SettingKeys.terminalSharing,
    };
    for (final d in kSettings.where((d) => d.owner == SettingOwner.app)) {
      if (d.daemonOwned) {
        expect(
          DaemonSettingKeys.all.contains(daemonKeyOf[d.id]),
          isTrue,
          reason: d.id,
        );
        expect(UiSettingKeys.all.contains(daemonKeyOf[d.id]), isFalse);
      } else {
        expect(UiSettingKeys.all.contains(d.storeKey), isTrue, reason: d.id);
        expect(DaemonSettingKeys.all.contains(d.storeKey), isFalse);
      }
    }
    expect({
      for (final d in kSettings)
        if (d.daemonOwned) d.id,
    }, daemonKeyOf.keys.toSet());
    expect(DaemonSettingKeys.all.intersection(UiSettingKeys.all), isEmpty);
  });

  test('the background service row has the store\'s one default', () {
    final d = kSettings.firstWhere((d) => d.id == 'background-service');
    expect(d.appDefault, SettingKeys.backgroundServiceDefault);
    expect(d.storeKey, SettingKeys.backgroundService);
  });

  test('every scalar key the loader knows has a row, or is listed as '
      'intentionally absent', () {
    const intentionallyAbsent = {
      'palette',
      'keybind',
      'command',
      'snippet',
      'config-file',
      'font-feature',
      'cursor-color-text',
    };
    const loaderScalarKeys = {
      'font-family',
      'font-size',
      'font-weight',
      'theme',
      'background',
      'foreground',
      'cursor-color',
      'selection-background',
      'cursor-style',
      'cursor-style-blink',
      'scrollback-limit',
      'window-padding-x',
      'window-padding-y',
      'macos-option-as-alt',
      'confirm-close-surface',
      'working-directory',
      'adjust-cell-height',
      'ghostty-config',
    };
    final have = {
      for (final d in kSettings)
        if (d.fileKey != null) d.fileKey!,
    };
    expect(loaderScalarKeys.difference(have), isEmpty);
    expect(have.difference(loaderScalarKeys), isEmpty);
    expect(intentionallyAbsent.intersection(have), isEmpty);
  });

  test('every tray switch has exactly one Settings row (D4)', () {
    const trayToggles = {
      ToggleRemoteAccess,
      ToggleKeepAwake,
      ToggleLaunchAtStartup,
      ToggleTerminalSharing,
      ToggleDesktopNotifications,
      ToggleDesktopNotificationsOnlyUnfocused,
      ToggleRestoreScrollback,
      ToggleBackgroundService,
      ToggleCliControl,
      ToggleCliAllowExternal,
      ToggleCliPath,
      ToggleSshHook,
      SetNotifyThreshold,
    };
    final used = [
      for (final d in kSettings)
        if (d.toggle != null) d.toggle!.runtimeType,
    ];
    for (final t in trayToggles) {
      expect(used.where((u) => u == t), hasLength(1), reason: '$t');
    }
    expect(used.toSet().length, used.length);
    expect(used.toSet().difference(trayToggles), isEmpty);
  });

  test('every row has an English and a Vietnamese label', () {
    for (final d in kSettings) {
      expect(d.label(en).trim(), isNotEmpty, reason: d.id);
      expect(d.label(vi).trim(), isNotEmpty, reason: d.id);
    }
    for (final p in SettingPage.values) {
      expect(settingPageLabel(p, en), isNotEmpty);
      expect(settingPageLabel(p, vi), isNotEmpty);
    }
    for (final d in kSettings.where((d) => d.choices != null)) {
      for (final c in d.choices!) {
        expect(c.label(en), isNotEmpty);
        expect(c.label(vi), isNotEmpty);
      }
    }
  });

  test('sliders have a range and a step; only the Mac sees option-as-alt', () {
    for (final d in kSettings.where(
      (d) => d.control == SettingControl.slider,
    )) {
      expect(d.min, isNotNull, reason: d.id);
      expect(d.max! > d.min!, isTrue, reason: d.id);
      expect(d.step, greaterThan(0), reason: d.id);
    }
    expect(kSettings.where((d) => d.onlyOn != null).map((d) => d.id), [
      'macos-option-as-alt',
    ]);
  });

  test('search finds by English label, Vietnamese label, key name and '
      'keyword', () {
    expect(
      searchSettings('cursor', en).map((d) => d.id),
      contains('cursor-style'),
    );
    expect(
      searchSettings('con trỏ', vi).map((d) => d.id),
      contains('cursor-style'),
    );
    expect(
      searchSettings('con tro', vi).map((d) => d.id),
      contains('cursor-style'),
    );
    expect(searchSettings('font-size', en).first.id, 'font-size');
    expect(
      searchSettings('nhấp nháy', vi).map((d) => d.id),
      contains('cursor-style-blink'),
    );
    expect(
      searchSettings('daemon', en).map((d) => d.id),
      contains('background-service'),
    );
    expect(searchSettings('zzzz', en), isEmpty);
    expect(searchSettings('  ', en), isEmpty);
  });

  group('settingSource', () {
    const paths = ConfigPaths(
      shellx: '/c/shellx',
      ghostty: ['/c/ghostty'],
      themeDirs: [],
      home: '/h',
      windows: false,
    );
    ConfigState stateOf(
      Map<String, (String, int)> origins, {
      int families = 0,
    }) {
      final entries = <ConfigEntry>[
        for (final e in origins.entries)
          ConfigEntry(
            file: e.value.$1,
            line: e.value.$2,
            key: e.key,
            value: 'x',
          ),
      ];
      final cfg = ShellxConfig(
        origins: {for (final e in entries) e.key: e},
        fontFamilyOrigins: [
          for (var i = 0; i < families; i++)
            ConfigEntry(
              file: '/c/shellx',
              line: i + 1,
              key: 'font-family',
              value: 'F$i',
            ),
        ],
      );
      return ConfigState(
        config: cfg,
        theme: ResolvedTheme.defaults,
        bindings: KeyBindings.defaults(TargetPlatform.macOS),
        loadProblems: const [],
        generation: 1,
        files: const [],
        ghosttyUsed: false,
      );
    }

    SettingDef def(String id) => kSettings.firstWhere((d) => d.id == id);

    test('default, own, user line, ghostty, include, multi-line', () {
      expect(
        settingSource(def('font-size'), stateOf({}), paths),
        isA<DefaultSource>(),
      );
      final text = applyKeyEdits('# a\n', [const SetKey('font-size', '15')]);
      final block = settingsBlockLines(text);
      expect(block, isNotNull);
      final line = text.split('\n').indexOf('font-size = 15') + 1;
      expect(
        settingSource(
          def('font-size'),
          stateOf({'font-size': ('/c/shellx', line)}),
          paths,
          ownBlock: block,
        ),
        isA<OwnSource>(),
      );
      expect(
        settingSource(
          def('font-size'),
          stateOf({'font-size': ('/c/shellx', 1)}),
          paths,
          ownBlock: block,
        ),
        isA<UserLineSource>(),
      );
      expect(
        settingSource(
          def('font-size'),
          stateOf({'font-size': ('/c/ghostty', 3)}),
          paths,
        ),
        isA<GhosttySource>(),
      );
      final inc = settingSource(
        def('font-size'),
        stateOf({'font-size': ('/c/extra', 7)}),
        paths,
      );
      expect(inc, isA<IncludeSource>());
      expect((inc as IncludeSource).line, 7);
      expect(
        settingSource(def('font-family'), stateOf({}, families: 2), paths),
        isA<MultiLineSource>(),
      );
    });

    test('settingsBlockLines is null for no block and for a damaged one', () {
      expect(settingsBlockLines('a = 1\n'), isNull);
      expect(settingsBlockLines('$kSettingsStart\n'), isNull);
    });
  });
}
