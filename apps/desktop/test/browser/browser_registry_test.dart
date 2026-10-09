import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/l10n/app_localizations.dart';
import 'package:shellx_desktop/src/browser/browser_controller.dart';
import 'package:shellx_desktop/src/browser/browser_engine.dart';
import 'package:shellx_desktop/src/browser/browser_registry.dart';
import 'package:shellx_desktop/src/terminal/local_sessions_provider.dart';
import 'package:shellx_desktop/src/terminal/terminal_tabs.dart';

import '../support/fake_browser_engine.dart';
import '../support/fake_local_sessions.dart';

late FakeLocalSessions local;
late ProviderContainer container;
late Map<int, FakeBrowserEngine> engines;

TerminalTabs tabs() => container.read(terminalTabsProvider.notifier);
TerminalTabsState state() => container.read(terminalTabsProvider);
BrowserRegistry registry() => container.read(browserRegistryProvider.notifier);

void boot() {
  engines = {};
  container = ProviderContainer.test(
    overrides: [
      localSessionsProvider.overrideWithValue(local),
      appL10nProvider.overrideWithValue(
        lookupAppLocalizations(const Locale('en')),
      ),
      browserEngineFactoryProvider.overrideWithValue(
        (id) => engines[id] = FakeBrowserEngine(),
      ),
    ],
  );
  state();
  container.read(browserRegistryProvider);
}

void main() {
  setUp(() => local = FakeLocalSessions());

  test(
    'a browser pane of the selected tab gets an engine and loads its URL',
    () async {
      local.add(local.summary(1, ports: [3000]));
      boot();
      final id = tabs().openBrowser();
      await pumpEventQueue();
      expect(engines[id]!.loads.single.toString(), 'http://localhost:3000/');
      engines[id]!.emit(const TitleChanged('Vite'));
      expect(state().tabs.single.browsers[id]!.title, 'Vite');
      expect(container.read(browserRegistryProvider), {id});
    },
  );

  test(
    'about:blank loads nothing; panes of hidden tabs load lazily (D29)',
    () async {
      local.add(local.summary(1));
      local.add(local.summary(2));
      boot();
      final blank = tabs().openBrowser(tabId: 1);
      final hidden = tabs().openBrowser(
        tabId: 2,
        url: Uri.parse('http://localhost:8000/'),
        focus: false,
      );
      await pumpEventQueue();
      expect(engines[blank]!.loads, isEmpty);
      expect(engines.containsKey(hidden), isFalse);
      expect(
        registry().controller(hidden),
        isA<BrowserController>(),
      ); // on demand (A7)
      await pumpEventQueue();
      expect(
        engines[hidden]!.loads.single.toString(),
        'http://localhost:8000/',
      );
    },
  );

  test('closing the pane disposes its controller and engine (D34)', () async {
    local.add(local.summary(1));
    boot();
    final id = tabs().openBrowser();
    await pumpEventQueue();
    tabs().closePane(id);
    await pumpEventQueue();
    expect(engines[id]!.disposed, isTrue);
    expect(registry().controller(id), isNull);
  });

  test(
    'notices, shortcuts and clicks are re-published with the pane id',
    () async {
      local.add(local.summary(1));
      boot();
      final id = tabs().openBrowser();
      await pumpEventQueue();
      final notices = <BrowserNotice>[];
      final shortcuts = <BrowserShortcut>[];
      final clicks = <int>[];
      registry().notices.listen(notices.add);
      registry().shortcuts.listen(shortcuts.add);
      registry().contentClicks.listen(clicks.add);
      engines[id]!
        ..emit(const DownloadBlocked())
        ..emit(const ShortcutForwarded('meta+l'))
        ..emit(const ContentClicked());
      await pumpEventQueue();
      expect(notices, [BrowserNotice.downloadBlocked]);
      expect(shortcuts.single.paneId, id);
      expect(shortcuts.single.chord, 'meta+l');
      expect(clicks, [id]);
    },
  );
}
