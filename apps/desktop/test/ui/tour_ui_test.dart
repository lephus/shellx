import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/agent/tour_state.dart';
import 'package:shellx_desktop/src/config/config_controller.dart';
import 'package:shellx_desktop/src/platform/settings_store.dart';
import 'package:shellx_desktop/src/terminal/sidebar_workspaces.dart'
    show settingsStoreProvider;
import 'package:shellx_desktop/src/terminal/terminal_tabs.dart';

import '../support/config_harness.dart';
import '../support/config_workspace.dart';

const _notes =
    '{"1.2.0":{"en":["Faster search","Pinned tabs"],"vi":["Tìm nhanh hơn"]}}';

typedef Rig = ({
  ProviderContainer container,
  dynamic fs,
  InMemorySettingsStore store,
});

Future<Rig> pump(
  WidgetTester t, {
  InMemorySettingsStore? store,
  String config = '',
  String version = '1.2.0',
  String notes = _notes,
  Locale locale = const Locale('en'),
}) async {
  final s = store ?? InMemorySettingsStore();
  final w = await pumpConfiguredWorkspace(
    t,
    config: config,
    locale: locale,
    extra: [
      settingsStoreProvider.overrideWithValue(s),
      currentVersionProvider.overrideWithValue(version),
      whatsNewSourceProvider.overrideWithValue(() async => notes),
    ],
  );
  await t.pumpAndSettle();
  return (container: w.container, fs: w.fs, store: s);
}

Future<void> key(WidgetTester t, LogicalKeyboardKey k) async {
  await t.sendKeyEvent(k);
  await t.pumpAndSettle();
}

String bodyText(WidgetTester t) =>
    t.widget<Text>(find.byKey(const Key('tour.body'))).data!;

String titleText(WidgetTester t) =>
    t.widget<Text>(find.byKey(const Key('tour.title'))).data!;

void main() {
  final mac = TargetPlatformVariant.only(TargetPlatform.macOS);

  testWidgets('a fresh install opens the tour with four steps', (t) async {
    final r = await pump(t);
    expect(find.byKey(const Key('tour.card')), findsOneWidget);
    expect(titleText(t), 'Tabs and panes');
    expect(find.bySemanticsLabel('1 of 4'), findsOneWidget);
    expect(r.store.values.containsKey(SettingKeys.tourDone), isFalse);
    await disposeWorkspace(t, r.container);
  }, variant: mac);

  testWidgets('step 1 shows the current chords; a reload changes them', (
    t,
  ) async {
    final r = await pump(t);
    expect(bodyText(t), contains('⌘T'));
    r.fs.write(testConfigPaths().shellx, 'keybind = super+k=new_tab\n');
    await r.container.read(shellxConfigProvider.notifier).load(manual: true);
    await t.pumpAndSettle();
    expect(bodyText(t), contains('⌘K'));
    expect(bodyText(t), isNot(contains('⌘T')));
    await disposeWorkspace(t, r.container);
  }, variant: mac);

  testWidgets('an unbound action leaves no empty gap or parentheses', (
    t,
  ) async {
    final r = await pump(t, config: 'keybind = super+t=unbind\n');
    final body = bodyText(t);
    expect(body, isNot(contains('()')));
    expect(body, isNot(contains('  ')));
    expect(body, isNot(contains(' .')));
    expect(body, contains('New tab'));
    await disposeWorkspace(t, r.container);
  }, variant: mac);

  testWidgets('arrow keys move, Enter is Next and then Done', (t) async {
    final r = await pump(t);
    await key(t, LogicalKeyboardKey.arrowRight);
    expect(titleText(t), 'Know when an agent needs you');
    await key(t, LogicalKeyboardKey.arrowLeft);
    expect(titleText(t), 'Tabs and panes');
    await key(t, LogicalKeyboardKey.arrowLeft);
    expect(titleText(t), 'Tabs and panes', reason: 'no step before the first');
    await key(t, LogicalKeyboardKey.enter);
    await key(t, LogicalKeyboardKey.enter);
    expect(titleText(t), 'Find your way');
    await key(t, LogicalKeyboardKey.enter);
    expect(titleText(t), 'Make it yours');
    expect(find.text('Done'), findsOneWidget);
    expect(find.bySemanticsLabel('4 of 4'), findsOneWidget);
    await key(t, LogicalKeyboardKey.enter);
    expect(find.byKey(const Key('tour.card')), findsNothing);
    expect(r.store.values[SettingKeys.tourDone], isTrue);
    expect(r.store.strings[SettingKeys.lastSeenVersion], ['1.2.0']);
    await disposeWorkspace(t, r.container);
  }, variant: mac);

  testWidgets('Esc skips and counts as done; the keyboard goes back to the '
      'terminal', (t) async {
    final r = await pump(t);
    await key(t, LogicalKeyboardKey.escape);
    expect(find.byKey(const Key('tour.card')), findsNothing);
    expect(r.store.values[SettingKeys.tourDone], isTrue);
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      isNot(contains('tour')),
    );
    await disposeWorkspace(t, r.container);
  }, variant: mac);

  testWidgets('the Skip button skips', (t) async {
    final r = await pump(t);
    await t.tap(find.byKey(const Key('tour.skip')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('tour.card')), findsNothing);
    expect(r.store.values[SettingKeys.tourDone], isTrue);
    await disposeWorkspace(t, r.container);
  }, variant: mac);

  testWidgets('no second tour after a restart (same store, new window)', (
    t,
  ) async {
    final first = await pump(t);
    await key(t, LogicalKeyboardKey.escape);
    await disposeWorkspace(t, first.container);
    final second = await pump(t, store: first.store);
    expect(find.byKey(const Key('tour.card')), findsNothing);
    expect(find.byKey(const Key('whatsnew.card')), findsNothing);
    await disposeWorkspace(t, second.container);
  }, variant: mac);

  testWidgets('quitting mid-tour does not repeat it (it stays in Settings)', (
    t,
  ) async {
    final first = await pump(t);
    await disposeWorkspace(t, first.container);
    final second = await pump(t, store: first.store);
    expect(find.byKey(const Key('tour.card')), findsNothing);
    await disposeWorkspace(t, second.container);
  }, variant: mac);

  testWidgets('the tour is a labelled dialog with the focus inside', (t) async {
    final r = await pump(t);
    expect(find.bySemanticsLabel('ShellX tour'), findsOneWidget);
    expect(find.byKey(const Key('tour.next')), findsOneWidget);
    final focus = FocusManager.instance.primaryFocus!.context!;
    var inside = false;
    focus.visitAncestorElements((e) {
      if (e.widget.key == const Key('tour.card')) inside = true;
      return !inside;
    });
    expect(inside, isTrue);
    await disposeWorkspace(t, r.container);
  }, variant: mac);

  testWidgets('Vietnamese copy', (t) async {
    final r = await pump(t, locale: const Locale('vi'));
    expect(titleText(t), 'Tab và pane');
    expect(find.text('Bỏ qua'), findsOneWidget);
    await disposeWorkspace(t, r.container);
  }, variant: mac);

  testWidgets('the tour never touches the tabs', (t) async {
    final r = await pump(t);
    expect(r.container.read(terminalTabsProvider).tabs, hasLength(1));
    await key(t, LogicalKeyboardKey.escape);
    expect(r.container.read(terminalTabsProvider).tabs, hasLength(1));
    await disposeWorkspace(t, r.container);
  }, variant: mac);

  group('what is new', () {
    InMemorySettingsStore upgraded({String from = '1.1.0'}) =>
        InMemorySettingsStore({SettingKeys.tourDone: true})
          ..strings[SettingKeys.lastSeenVersion] = [from];

    testWidgets('a version bump with notes shows the card once', (t) async {
      final store = upgraded();
      final r = await pump(t, store: store);
      expect(find.byKey(const Key('whatsnew.card')), findsOneWidget);
      expect(find.text('What’s new in 1.2.0'), findsOneWidget);
      expect(find.text('Faster search'), findsOneWidget);
      expect(find.text('Pinned tabs'), findsOneWidget);
      expect(find.byKey(const Key('tour.card')), findsNothing);
      // Written at once: a crash with the card up does not repeat it.
      expect(store.strings[SettingKeys.lastSeenVersion], ['1.2.0']);
      await t.tap(find.text('Got it'));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('whatsnew.card')), findsNothing);
      await disposeWorkspace(t, r.container);
      final again = await pump(t, store: store);
      expect(find.byKey(const Key('whatsnew.card')), findsNothing);
      await disposeWorkspace(t, again.container);
    }, variant: mac);

    testWidgets('Vietnamese notes follow the locale', (t) async {
      final r = await pump(t, store: upgraded(), locale: const Locale('vi'));
      expect(find.text('Tìm nhanh hơn'), findsOneWidget);
      expect(find.text('Có gì mới ở bản 1.2.0'), findsOneWidget);
      await disposeWorkspace(t, r.container);
    }, variant: mac);

    testWidgets('Esc closes it', (t) async {
      final r = await pump(t, store: upgraded());
      await key(t, LogicalKeyboardKey.escape);
      expect(find.byKey(const Key('whatsnew.card')), findsNothing);
      await disposeWorkspace(t, r.container);
    }, variant: mac);

    testWidgets('a release without notes shows nothing but is remembered', (
      t,
    ) async {
      final store = upgraded();
      final r = await pump(t, store: store, notes: '{}');
      expect(find.byKey(const Key('whatsnew.card')), findsNothing);
      expect(store.strings[SettingKeys.lastSeenVersion], ['1.2.0']);
      await disposeWorkspace(t, r.container);
    }, variant: mac);

    testWidgets('the build number after + is not an upgrade', (t) async {
      final store = upgraded(from: '1.2.0+3');
      final r = await pump(t, store: store, version: '1.2.0+9');
      expect(find.byKey(const Key('whatsnew.card')), findsNothing);
      await disposeWorkspace(t, r.container);
    }, variant: mac);

    testWidgets('someone who used the app before A11 gets "what is new", '
        'not the tour', (t) async {
      final store = InMemorySettingsStore()
        ..ints[SettingKeys.windowWidth] = 900;
      final r = await pump(t, store: store);
      expect(find.byKey(const Key('tour.card')), findsNothing);
      expect(find.byKey(const Key('whatsnew.card')), findsOneWidget);
      await disposeWorkspace(t, r.container);
    }, variant: mac);

    testWidgets('a new install never sees "what is new"', (t) async {
      final r = await pump(t);
      expect(find.byKey(const Key('whatsnew.card')), findsNothing);
      await disposeWorkspace(t, r.container);
    }, variant: mac);

    testWidgets('the notes are not logged', (t) async {
      final logged = <String>[];
      final old = debugPrint;
      debugPrint = (String? m, {int? wrapWidth}) => logged.add(m ?? '');
      try {
        final r = await pump(t, store: upgraded());
        expect(logged.join(), isNot(contains('Faster search')));
        await disposeWorkspace(t, r.container);
      } finally {
        debugPrint = old;
      }
    }, variant: mac);
  });

  group('opened by hand', () {
    testWidgets('the show_tour action opens the tour again', (t) async {
      final store = InMemorySettingsStore({SettingKeys.tourDone: true})
        ..strings[SettingKeys.lastSeenVersion] = ['1.2.0'];
      final r = await pump(
        t,
        store: store,
        config: 'keybind = super+u=show_tour\n',
      );
      expect(find.byKey(const Key('tour.card')), findsNothing);
      await t.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await t.sendKeyEvent(LogicalKeyboardKey.keyU);
      await t.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await t.pumpAndSettle();
      expect(find.byKey(const Key('tour.card')), findsOneWidget);
      await disposeWorkspace(t, r.container);
    }, variant: mac);

    testWidgets('show_whats_new opens the card for the running version', (
      t,
    ) async {
      final store = InMemorySettingsStore({SettingKeys.tourDone: true})
        ..strings[SettingKeys.lastSeenVersion] = ['1.2.0'];
      final r = await pump(
        t,
        store: store,
        config: 'keybind = super+u=show_whats_new\n',
      );
      await t.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await t.sendKeyEvent(LogicalKeyboardKey.keyU);
      await t.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await t.pumpAndSettle();
      expect(find.byKey(const Key('whatsnew.card')), findsOneWidget);
      expect(find.text('Faster search'), findsOneWidget);
      await disposeWorkspace(t, r.container);
    }, variant: mac);

    testWidgets('Settings › General has "Show the tour again"', (t) async {
      final store = InMemorySettingsStore({SettingKeys.tourDone: true})
        ..strings[SettingKeys.lastSeenVersion] = ['1.2.0'];
      final r = await pump(t, store: store);
      await t.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await t.sendKeyEvent(LogicalKeyboardKey.comma);
      await t.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('settings.page.general')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('settings.tour')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('tour.card')), findsOneWidget);
      expect(find.byKey(const Key('settings.close')), findsNothing);
      await key(t, LogicalKeyboardKey.escape);
      expect(find.byKey(const Key('tour.card')), findsNothing);
      await disposeWorkspace(t, r.container);
    }, variant: mac);
  });
}
