import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/l10n/app_localizations.dart';
import 'package:shellx_desktop/src/agent/agent_state.dart';
import 'package:shellx_desktop/src/agent/desktop_services.dart';
import 'package:shellx_desktop/src/config/config_controller.dart';
import 'package:shellx_desktop/src/config/config_opener.dart';
import 'package:shellx_desktop/src/restore/restore_persistence.dart';
import 'package:shellx_desktop/src/tray/tray_action.dart';
import 'package:shellx_desktop/src/tray/tray_actions.dart';
import 'package:shellx_desktop/src/tray/tray_menu.dart';
import 'package:shellx_desktop/src/ui/config/config_ui_request.dart';
import 'package:shellx_desktop/src/ui/window_router.dart';
import 'package:tray_manager/tray_manager.dart';

import '../support/config_harness.dart';
import '../support/fakes.dart';
import '../support/memory_config_fs.dart';
import '../support/restore_fakes.dart';

final vi = lookupAppLocalizations(const Locale('vi'));
final en = lookupAppLocalizations(const Locale('en'));

MenuItem? find(List<MenuItem> items, String key) {
  for (final i in items) {
    if (i.key == key) return i;
    final sub = i.submenu?.items;
    if (sub != null) {
      final hit = find(sub, key);
      if (hit != null) return hit;
    }
  }
  return null;
}

List<MenuItem> menu(
  AgentViewState state,
  AppLocalizations l10n, {
  int problems = 0,
}) => buildTrayMenu(
  state,
  l10n,
  TrayMenuIds(),
  local: TrayLocalState(configProblemCount: problems),
).items!;

final class RecordingOpener extends ConfigFileOpener {
  RecordingOpener() : super(windows: false);
  final opened = <String>[];

  @override
  Future<bool> open(String path, {required String Function() template}) async {
    opened.add(path);
    return true;
  }
}

void main() {
  const signedOut = AgentViewState(phase: AuthPhase.signedOut);
  const signedIn = AgentViewState(phase: AuthPhase.signedIn, email: 'a@b.c');

  for (final state in [signedOut, signedIn]) {
    test(
      '"Cấu hình" after "Dòng lệnh" and "SSH" (signed in: ${state.signedIn}), '
      'no problems',
      () {
        for (final l10n in [en, vi]) {
          final items = menu(state, l10n);
          final cli = items.indexWhere((i) => i.key == TrayKeys.commandLine);
          expect(cli, greaterThanOrEqualTo(0));
          expect(items[cli + 1].key, TrayKeys.ssh); // A8
          expect(items[cli + 2].key, TrayKeys.config);
          final sub = items[cli + 2];
          expect(sub.label, l10n.trayConfig);
          expect(sub.submenu!.items!.map((i) => i.key), [
            TrayKeys.configSettings,
            TrayKeys.configOpen,
            TrayKeys.configReload,
            TrayKeys.configShortcuts,
          ]);
        }
        final items = menu(state, en);
        expect(find(items, TrayKeys.config)!.label, 'Configuration');
        expect(find(items, TrayKeys.configSettings)!.label, 'Settings…');
        expect(
          find(menu(state, vi), TrayKeys.configSettings)!.label,
          'Cài đặt…',
        );
        expect(
          find(items, TrayKeys.configOpen)!.label,
          'Open configuration file',
        );
        expect(
          find(items, TrayKeys.configReload)!.label,
          'Reload configuration',
        );
        expect(
          find(items, TrayKeys.configShortcuts)!.label,
          'Keyboard shortcuts…',
        );
        expect(find(items, TrayKeys.configProblems), isNull);
        expect(find(menu(state, vi), TrayKeys.config)!.label, 'Cấu hình');
      },
    );

    test('with problems the last item, after a separator, counts them '
        '(signed in: ${state.signedIn})', () {
      final sub = find(menu(state, en, problems: 2), TrayKeys.config)!;
      final items = sub.submenu!.items!;
      expect(items.map((i) => i.key), [
        TrayKeys.configSettings,
        TrayKeys.configOpen,
        TrayKeys.configReload,
        TrayKeys.configShortcuts,
        null,
        TrayKeys.configProblems,
      ]);
      expect(items[4].type, 'separator');
      expect(items.last.label, '⚠ 2 configuration problems…');
      expect(
        find(menu(state, en, problems: 1), TrayKeys.configProblems)!.label,
        '⚠ 1 configuration problem…',
      );
      expect(
        find(menu(state, vi, problems: 3), TrayKeys.configProblems)!.label,
        '⚠ 3 vấn đề cấu hình…',
      );
    });
  }

  test('keys map to actions', () {
    expect(trayActionForKey(TrayKeys.configSettings), isA<OpenSettings>());
    expect(trayActionForKey(TrayKeys.configOpen), isA<OpenConfigFile>());
    expect(trayActionForKey(TrayKeys.configReload), isA<ReloadConfig>());
    expect(
      trayActionForKey(TrayKeys.configShortcuts),
      isA<ShowShortcutsFromTray>(),
    );
    expect(
      trayActionForKey(TrayKeys.configProblems),
      isA<ShowConfigProblemsFromTray>(),
    );
  });

  group('actions', () {
    late TestHarness h;
    late ProviderContainer c;
    late MemoryConfigFs fs;
    late RecordingOpener opener;

    setUp(() async {
      h = TestHarness();
      fs = MemoryConfigFs();
      opener = RecordingOpener();
      c = ProviderContainer.test(
        overrides: [
          restoreStoreProvider.overrideWithValue(RecordingFiles()),
          desktopServicesProvider.overrideWithValue(h.services()),
          ...configOverrides(fs),
          configFileOpenerProvider.overrideWithValue(opener),
        ],
      );
      c.listen(trayLocalStateProvider, (_, _) {});
      await loadConfig(c);
    });

    Future<void> tap(TrayAction a) => c.read(trayActionsProvider).handle(a);

    test('Open: the window, then the ShellX file in the editor', () async {
      await tap(const OpenConfigFile());
      expect(c.read(windowRouterProvider).visible, isTrue);
      expect(opener.opened, [testConfigPaths().shellx]);
    });

    test('Reload: a manual load', () async {
      final before = c.read(shellxConfigProvider).generation;
      await tap(const ReloadConfig());
      final after = c.read(shellxConfigProvider);
      expect(after.generation, before + 1);
      expect(after.lastLoad!.manual, isTrue);
      expect(c.read(windowRouterProvider).visible, isTrue);
    });

    test('Settings: the window, then a request', () async {
      await tap(const OpenSettings());
      expect(c.read(configUiRequestProvider)!.$1, ConfigUiRequest.settings);
      expect(c.read(windowRouterProvider).visible, isTrue);
    });

    test('Shortcuts and problems: the window, then a request', () async {
      expect(c.read(configUiRequestProvider), isNull);
      await tap(const ShowShortcutsFromTray());
      final first = c.read(configUiRequestProvider)!;
      expect(first.$1, ConfigUiRequest.shortcuts);
      expect(c.read(windowRouterProvider).visible, isTrue);
      await tap(const ShowConfigProblemsFromTray());
      final second = c.read(configUiRequestProvider)!;
      expect(second.$1, ConfigUiRequest.problems);
      expect(second.$2, greaterThan(first.$2));
      // The same request twice is two requests.
      await tap(const ShowConfigProblemsFromTray());
      expect(c.read(configUiRequestProvider)!.$2, greaterThan(second.$2));
    });

    test('the tray counts errors and warnings, never notes', () async {
      expect(c.read(trayLocalStateProvider).configProblemCount, 0);
      fs.write(
        testConfigPaths().shellx,
        'font-size = to\nkeybind = ctrl+c=new_tab\n',
      );
      await loadConfig(c);
      expect(c.read(trayLocalStateProvider).configProblemCount, 1);
    });
  });
}
