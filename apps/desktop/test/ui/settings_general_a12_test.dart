import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/platform/settings_store.dart';
import 'package:shellx_desktop/src/terminal/sidebar_workspaces.dart'
    show settingsStoreProvider;
import 'package:shellx_desktop/src/ui/settings/settings_overlay.dart';

import '../support/config_workspace.dart';

const cmd = LogicalKeyboardKey.metaLeft;

Future<void> openGeneral(WidgetTester t) async {
  await t.sendKeyDownEvent(cmd);
  await t.sendKeyEvent(LogicalKeyboardKey.comma);
  await t.sendKeyUpEvent(cmd);
  await t.pumpAndSettle();
  expect(find.byType(SettingsOverlay), findsOneWidget);
  await t.tap(find.byKey(const Key('settings.page.general')));
  await t.pumpAndSettle();
}

Finder opt(String wire) => find.byKey(Key('setting.app-language.opt.$wire'));

bool selected(WidgetTester t, String wire) =>
    t.widget<ChoiceChip>(opt(wire)).selected;

void main() {
  final mac = TargetPlatformVariant.only(TargetPlatform.macOS);

  group('language', () {
    testWidgets('three choices; the system one is selected at first', (
      t,
    ) async {
      final w = await pumpConfiguredWorkspace(t);
      await openGeneral(t);
      expect(find.text('Language'), findsOneWidget);
      expect(find.text('System default'), findsOneWidget);
      expect(find.text('English'), findsOneWidget);
      expect(find.text('Tiếng Việt'), findsOneWidget);
      expect(selected(t, 'system'), isTrue);
      expect(selected(t, 'en'), isFalse);
      expect(selected(t, 'vi'), isFalse);
      // Nothing is said before something is chosen.
      expect(
        find.byKey(const Key('setting.app-language.restart')),
        findsNothing,
      );
      await disposeWorkspace(t, w.container);
    }, variant: mac);

    testWidgets('choosing Tiếng Việt stores [vi] and says when it applies', (
      t,
    ) async {
      final w = await pumpConfiguredWorkspace(t);
      await openGeneral(t);
      await t.tap(opt('vi'));
      await t.pumpAndSettle();
      final store = w.container.read(settingsStoreProvider);
      expect(store.getStrings(SettingKeys.appLanguage), ['vi']);
      expect(selected(t, 'vi'), isTrue);
      expect(selected(t, 'system'), isFalse);
      expect(
        find.text('Takes effect after you restart ShellX.'),
        findsOneWidget,
      );
      // The running window does not change.
      expect(find.text('Language'), findsOneWidget);
      await disposeWorkspace(t, w.container);
    }, variant: mac);

    testWidgets('and back to the system default', (t) async {
      final w = await pumpConfiguredWorkspace(t);
      await openGeneral(t);
      await t.tap(opt('en'));
      await t.pumpAndSettle();
      await t.tap(opt('system'));
      await t.pumpAndSettle();
      final store = w.container.read(settingsStoreProvider);
      expect(store.getStrings(SettingKeys.appLanguage), ['system']);
      expect(selected(t, 'system'), isTrue);
      await disposeWorkspace(t, w.container);
    }, variant: mac);

    testWidgets('a stored value nobody knows reads as the system default', (
      t,
    ) async {
      final w = await pumpConfiguredWorkspace(t);
      (w.container.read(settingsStoreProvider) as InMemorySettingsStore)
          .strings[SettingKeys.appLanguage] = [
        'klingon',
      ];
      await openGeneral(t);
      expect(selected(t, 'system'), isTrue);
      await disposeWorkspace(t, w.container);
    }, variant: mac);

    testWidgets('Vietnamese labels and note', (t) async {
      final w = await pumpConfiguredWorkspace(t, locale: const Locale('vi'));
      await openGeneral(t);
      expect(find.text('Ngôn ngữ'), findsOneWidget);
      expect(find.text('Theo hệ thống'), findsOneWidget);
      await t.tap(opt('en'));
      await t.pumpAndSettle();
      expect(
        find.text('Có hiệu lực sau khi bạn khởi động lại ShellX.'),
        findsOneWidget,
      );
      await disposeWorkspace(t, w.container);
    }, variant: mac);

    testWidgets('the row is found by search, in either language', (t) async {
      final w = await pumpConfiguredWorkspace(t);
      await openGeneral(t);
      await t.enterText(find.byType(TextField).first, 'ngon ngu');
      await t.pumpAndSettle();
      expect(find.byKey(const Key('setting.app-language')), findsOneWidget);
      await disposeWorkspace(t, w.container);
    }, variant: mac);
  });
}
