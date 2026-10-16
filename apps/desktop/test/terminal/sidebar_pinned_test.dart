import 'dart:ui';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/widgets.dart' show StringCharacters;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_desktop/l10n/app_localizations.dart';
import 'package:shellx_desktop/src/platform/settings_store.dart';
import 'package:shellx_desktop/src/restore/restore_capture.dart';
import 'package:shellx_desktop/src/terminal/local_sessions_provider.dart';
import 'package:shellx_desktop/src/terminal/sidebar_workspaces.dart';
import 'package:shellx_desktop/src/terminal/tab_meta.dart';
import 'package:shellx_desktop/src/terminal/terminal_tabs.dart';

import '../support/fake_local_sessions.dart';

void main() {
  late FakeLocalSessions local;
  late ProviderContainer container;

  SidebarWorkspaces sidebar() =>
      container.read(sidebarWorkspacesProvider.notifier);
  List<int> order([String ws = kDefaultWorkspaceId]) =>
      container.read(sidebarWorkspacesProvider).tabsOf(ws);
  TerminalTabs tabs() => container.read(terminalTabsProvider.notifier);
  void pin(int id, {bool pinned = true}) =>
      tabs().setMeta(id, (m) => m.copyWith(pinned: pinned));

  void boot() {
    container = ProviderContainer.test(
      overrides: [
        localSessionsProvider.overrideWithValue(local),
        appL10nProvider.overrideWithValue(
          lookupAppLocalizations(const Locale('en')),
        ),
        settingsStoreProvider.overrideWithValue(InMemorySettingsStore()),
      ],
    );
    container.read(sidebarWorkspacesProvider);
  }

  setUp(() async {
    local = FakeLocalSessions();
    for (final id in [1, 2, 3]) {
      local.add(local.summary(id, origin: SessionOrigin.desktop));
    }
    boot();
    await pumpEventQueue();
  });

  test('pinning tab 3 moves it first; unpinning puts it after the pinned', () {
    expect(order(), [1, 2, 3]);
    pin(3);
    expect(order(), [3, 1, 2]);
    pin(2);
    expect(order(), [3, 2, 1], reason: 'pinned keep their relative order');
    pin(3, pinned: false);
    expect(order(), [2, 3, 1], reason: 'right after the remaining pinned');
  });

  test('an unpinned tab cannot be dropped above a pinned one', () {
    pin(3); // 3 1 2
    sidebar().moveTab(2, kDefaultWorkspaceId, 0);
    expect(order(), [3, 2, 1]);
  });

  test('a pinned tab cannot be dropped below an unpinned one', () {
    pin(1);
    pin(2); // 1 2 3
    sidebar().moveTab(1, kDefaultWorkspaceId, 3);
    expect(order(), [2, 1, 3]);
  });

  test(
    'moving a pinned tab to another workspace keeps it first there',
    () async {
      await sidebar().create(); // workspace with tab 100
      final other = container
          .read(sidebarWorkspacesProvider)
          .workspaces
          .last
          .id;
      pin(1);
      sidebar().moveTab(1, other);
      expect(order(other), [1, 100]);
      pin(100);
      expect(order(other), [1, 100]);
      pin(1, pinned: false);
      expect(order(other), [100, 1]);
    },
  );

  test('moveUp / moveDown do not cross the pin boundary', () {
    pin(1); // 1 | 2 3
    expect(sidebar().canMoveUp(2), isFalse);
    expect(sidebar().canMoveDown(1), isFalse);
    expect(sidebar().canMoveDown(2), isTrue);
  });

  test('closing a pinned tab keeps the order of the rest', () {
    pin(2); // 2 1 3
    tabs().close(2);
    expect(order(), [1, 3]);
  });

  test('the description is cleaned when set and never exceeds 120', () {
    tabs().setMeta(1, (m) => m.copyWith(description: 'a\nb${'x' * 300}'));
    final d = container.read(terminalTabsProvider).tabs.first.meta.description;
    expect(d.startsWith('a b'), isTrue);
    expect(d.characters.length, 120);
    expect(TabMeta.empty.isEmpty, isTrue);
  });

  test('privacy: no log line carries a description', () async {
    final lines = <String>[];
    final old = debugPrint;
    debugPrint = (String? m, {int? wrapWidth}) => lines.add(m ?? '');
    addTearDown(() => debugPrint = old);
    tabs().setMeta(1, (m) => m.copyWith(description: 'hunter2-secret'));
    pin(1);
    final snapshot = captureSnapshot(
      tabs: container.read(terminalTabsProvider),
      sidebar: container.read(sidebarWorkspacesProvider),
      keyOf: (id) => id.toRadixString(16).padLeft(32, '0'),
      now: DateTime.utc(2026),
      cleanExit: true,
    );
    expect(snapshot.tabs.first.description, 'hunter2-secret');
    expect('${snapshot.tabs.first.meta}', '…');
    tabs().close(1);
    await pumpEventQueue();
    expect(lines.where((l) => l.contains('hunter2')), isEmpty);
  });
}
