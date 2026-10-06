import 'dart:async';
import 'dart:ui';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/l10n/app_localizations.dart';
import 'package:shellx_desktop/src/agent/desktop_services.dart'
    show clockProvider;
import 'package:shellx_desktop/src/platform/settings_store.dart';
import 'package:shellx_desktop/src/restore/restore_persistence.dart';
import 'package:shellx_desktop/src/restore/restore_snapshot.dart';
import 'package:shellx_desktop/src/restore/restore_store.dart';
import 'package:shellx_desktop/src/terminal/local_sessions_provider.dart';
import 'package:shellx_desktop/src/terminal/sidebar_workspaces.dart';
import 'package:shellx_desktop/src/terminal/terminal_tabs.dart';

import '../support/fake_local_sessions.dart';
import '../support/restore_fakes.dart';

late FakeLocalSessions local;
late RecordingFiles files;
late InMemorySettingsStore settings;
late ProviderContainer c;

RestorePersistence persistence() => c.read(restorePersistenceProvider.notifier);
TerminalTabs tabs() => c.read(terminalTabsProvider.notifier);
RestoreStripState? strip() => c.read(restoreStripProvider);

void boot({bool start = true}) {
  c = ProviderContainer.test(
    overrides: [
      localSessionsProvider.overrideWithValue(local),
      settingsStoreProvider.overrideWithValue(settings),
      restoreStoreProvider.overrideWithValue(files),
      clockProvider.overrideWithValue(() => DateTime(2026, 10, 7, 15)),
      appL10nProvider.overrideWithValue(
        lookupAppLocalizations(const Locale('vi')),
      ),
    ],
  );
  c.read(sidebarWorkspacesProvider);
  if (start) persistence().start();
}

final key = 'e' * 32;

RestoreSnapshot saved({bool cleanExit = false, String cwd = '/w'}) =>
    RestoreSnapshot(
      savedAt: DateTime(2026, 10, 7, 14, 31),
      cleanExit: cleanExit,
      selectedTab: key,
      workspaces: [
        SavedWorkspace(id: 'default', tabs: [key]),
      ],
      tabs: [
        SavedTab(
          key: key,
          focused: key,
          layout: SavedPane(key: key, cwd: cwd),
        ),
      ],
    );

String screen(TerminalTab tab) => [
  for (var i = 0; i < tab.terminal.mainBuffer.lines.length; i++)
    tab.terminal.mainBuffer.lines[i].getText().trimRight(),
].join('\n');

void main() {
  setUp(() {
    local = FakeLocalSessions();
    files = RecordingFiles();
    settings = InMemorySettingsStore();
  });

  test('the default store keeps nothing and building starts no timer', () {
    final container = ProviderContainer.test();
    expect(container.read(restoreStoreProvider), isA<NullRestoreFiles>());
    fakeAsync((async) {
      local.add(local.summary(1));
      boot(start: false);
      c.read(restorePersistenceProvider);
      expect(async.pendingTimers, isEmpty);
    });
  });

  test(
    'layout: one write 1 s after a burst of changes; none when equal',
    () => fakeAsync((async) {
      local.add(local.summary(1));
      boot();
      async.flushMicrotasks();
      tabs().rename(1, 'a');
      async.elapse(const Duration(milliseconds: 500));
      tabs().rename(1, 'b');
      async.elapse(const Duration(milliseconds: 999));
      expect(files.layouts, isEmpty);
      async.elapse(const Duration(milliseconds: 2));
      expect(files.layouts.single.tabs.single.name, 'b');
      expect(files.layouts.single.cleanExit, isFalse); // D12 while running
      tabs().select(1); // no layout change
      async.elapse(const Duration(seconds: 2));
      expect(files.layouts, hasLength(1));
    }),
  );

  test(
    'a failed layout write (disk full) is retried at the next save (§5)',
    () => fakeAsync((async) {
      local.add(local.summary(1));
      boot();
      tabs().rename(1, 'a');
      async.elapse(const Duration(seconds: 2));
      expect(files.layouts.single.tabs.single.name, 'a');
      files.failLayoutWrites = true;
      tabs().rename(1, 'b');
      async.elapse(const Duration(seconds: 2));
      expect(files.layouts, hasLength(1));
      files.failLayoutWrites = false;
      // Nothing changed since, yet the next save writes it.
      async.elapse(RestorePersistence.scrollbackPeriod);
      expect(files.layouts.last.tabs.single.name, 'b');
    }),
  );

  test(
    'scrollback: only dirty panes, every 60 s (D4)',
    () => fakeAsync((async) {
      local.add(local.summary(1));
      local.add(local.summary(2));
      boot();
      async.flushMicrotasks();
      local.views[1]!.emit('hello\r\n');
      async.elapse(const Duration(seconds: 60));
      expect(files.scrollbacks.keys, [persistence().keyOf(1)]);
      expect(files.scrollbacks.values.single, 'hello\r\n');
      files.scrollbacks.clear();
      async.elapse(const Duration(seconds: 60));
      expect(files.scrollbacks, isEmpty); // nothing new
    }),
  );

  test(
    'a failed scrollback write keeps the pane dirty (§5)',
    () => fakeAsync((async) {
      local.add(local.summary(1));
      boot();
      async.flushMicrotasks();
      local.views[1]!.emit('hello\r\n');
      files.failScrollbackWrites = true;
      async.elapse(const Duration(seconds: 60));
      expect(files.scrollbacks, isEmpty);
      files.failScrollbackWrites = false;
      async.elapse(const Duration(seconds: 60));
      expect(files.scrollbacks.values.single, 'hello\r\n');
    }),
  );

  test(
    'flushAll(clean: true) writes layout with cleanExit and dirty panes',
    () async {
      local.add(local.summary(1));
      boot();
      local.views[1]!.emit('x\r\n');
      await pumpEventQueue();
      await persistence().flushAll(clean: true);
      expect(files.layouts.last.cleanExit, isTrue);
      expect(files.scrollbacks, isNotEmpty);
    },
  );

  test(
    'after flushAll(clean: true) nothing is written or deleted any more, '
    'even as every pane closes (D12, Quit)',
    () => fakeAsync((async) {
      local.add(local.summary(1));
      local.add(local.summary(2));
      boot();
      async.flushMicrotasks();
      local.views[1]!.emit('x\r\n');
      async.flushMicrotasks();
      unawaited(persistence().flushAll(clean: true));
      async.flushMicrotasks();
      expect(files.layouts.single.cleanExit, isTrue);
      expect(files.layouts.single.tabs, hasLength(2));
      final scrollbacks = Map.of(files.scrollbacks);
      // The agent shuts down: every session ends.
      local.views[2]!.emit('more\r\n');
      local.close(1);
      local.close(2);
      async.elapse(const Duration(seconds: 120));
      expect(files.layouts, hasLength(1));
      expect(files.deleted, isEmpty);
      expect(files.scrollbacks, scrollbacks);
      // A later flush (power-off after Quit) changes nothing either.
      unawaited(persistence().flushAll(clean: false));
      async.flushMicrotasks();
      expect(files.layouts, hasLength(1));
    }),
  );

  test('switch off: deletes everything now and stops writing (D13)', () async {
    local.add(local.summary(1));
    boot();
    await persistence().setScrollbackEnabled(false);
    expect(settings.values[SettingKeys.terminalRestoreScrollback], isFalse);
    expect(persistence().scrollbackEnabled, isFalse);
    expect(files.clears, 1);
    local.views[1]!.emit('x\r\n');
    await pumpEventQueue();
    await persistence().flushAll(clean: true);
    expect(files.scrollbacks, isEmpty);
    expect(files.layouts, isNotEmpty); // the layout is still saved
  });

  test('switched off: startup reads no saved text (D13)', () async {
    settings.values[SettingKeys.terminalRestoreScrollback] = false;
    files.stored = {key: 'old\r\n'};
    boot();
    await persistence().restoreAtStartup(RestoreLoad(snapshot: saved()));
    expect(files.reads, isEmpty);
    expect(
      screen(c.read(terminalTabsProvider).tabs.single),
      isNot(contains('old')),
    );
  });

  test(
    'closing a pane deletes its file at the next layout write (D15)',
    () => fakeAsync((async) {
      local.add(local.summary(1));
      local.add(local.summary(2));
      boot();
      async.flushMicrotasks();
      final key = persistence().keyOf(2);
      tabs().close(2);
      async.elapse(const Duration(seconds: 2));
      expect(files.deleted, [key]);
      expect(files.layouts.last.paneKeys, isNot(contains(key)));
      // Only once.
      tabs().rename(1, 'x');
      async.elapse(const Duration(seconds: 2));
      expect(files.deleted, [key]);
    }),
  );

  test(
    'a pane closed after a layout write loses its file too (D15)',
    () => fakeAsync((async) {
      local.add(local.summary(1));
      local.add(local.summary(2));
      boot();
      tabs().rename(1, 'a');
      async.elapse(const Duration(seconds: 2));
      final key = persistence().keyOf(2);
      expect(files.layouts.single.paneKeys, contains(key));
      tabs().close(2);
      async.elapse(const Duration(seconds: 2));
      expect(files.deleted, [key]);
    }),
  );

  test('restoreAtStartup: plan with text + divider, keys kept, strip after an '
      'unclean exit, orphans removed (D8, D12, D14, D15, D23)', () async {
    files.stored = {key: 'old\r\n'};
    boot();
    await persistence().restoreAtStartup(RestoreLoad(snapshot: saved()));
    final tab = c.read(terminalTabsProvider).tabs.single;
    expect(persistence().keyOf(tab.id), key);
    expect(screen(tab), contains('old\n— Phiên được khôi phục · 14:32 —'));
    expect(strip()!.tabs, 1);
    expect(strip()!.contentsAt, DateTime(2026, 10, 7, 14, 32));
    expect(files.keptOrphans, {key});
    persistence().dismissStrip();
    expect(strip(), isNull);
  });

  test('the divider gets its own line when the saved text does not end a '
      'line; the text goes through the sanitizer (D6, D8)', () async {
    // A clear-screen would wipe "old" if it reached the terminal.
    files.stored = {key: 'old\r\n\x1b[2J\x1b[Hlast'};
    boot();
    await persistence().restoreAtStartup(RestoreLoad(snapshot: saved()));
    final tab = c.read(terminalTabsProvider).tabs.single;
    expect(
      screen(tab),
      contains('old\nlast\n— Phiên được khôi phục · 14:32 —'),
    );
  });

  test('restore after a clean exit shows no strip (D12)', () async {
    boot();
    await persistence().restoreAtStartup(
      RestoreLoad(snapshot: saved(cleanExit: true)),
    );
    expect(c.read(terminalTabsProvider).tabs, hasLength(1));
    expect(strip(), isNull);
  });

  test('nothing restored → no strip; every saved file is an orphan', () async {
    boot();
    await persistence().restoreAtStartup(const RestoreLoad());
    expect(strip(), isNull);
    expect(files.keptOrphans, isEmpty);
  });

  test(
    'an activation while the layout still loads adds no tab (D16)',
    () async {
      boot();
      final load = Completer<RestoreLoad>();
      final restoring = persistence().restoreAtStartup(load.future);
      final activation = tabs().ensureTab();
      await pumpEventQueue();
      expect(c.read(terminalTabsProvider).tabs, isEmpty);
      load.complete(RestoreLoad(snapshot: saved()));
      await restoring;
      await activation;
      expect(c.read(terminalTabsProvider).tabs, hasLength(1));
      expect(local.openCwds, ['/w']);
    },
  );

  test('panes open at the area grid reported while the layout loaded '
      '(D17)', () async {
    boot();
    final load = Completer<RestoreLoad>();
    final restoring = persistence().restoreAtStartup(load.future);
    tabs().reportGrid((cols: 120, rows: 40)); // the first layout
    load.complete(RestoreLoad(snapshot: saved()));
    await restoring;
    expect(local.opens, [(120, 40)]);
  });

  test(
    'a pending layout write is dropped when a restore starts; the restored '
    'layout is written after it (I7)',
    () => fakeAsync((async) {
      local.add(local.summary(1));
      boot();
      tabs().rename(1, 'a'); // debounce pending
      local.openGate = Completer<void>();
      unawaited(persistence().restoreAtStartup(RestoreLoad(snapshot: saved())));
      async.elapse(const Duration(seconds: 5));
      expect(files.layouts, isEmpty);
      local.openGate!.complete();
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 2));
      final written = files.layouts.single;
      expect(written.tabs, hasLength(2));
      expect(written.paneKeys, contains(key));
    }),
  );

  test('Quit during a restore keeps the saved files (D16)', () async {
    boot();
    local.openGate = Completer<void>();
    final restoring = persistence().restoreAtStartup(
      RestoreLoad(snapshot: saved()),
    );
    await pumpEventQueue();
    await persistence().flushAll(clean: true);
    expect(files.layouts, isEmpty);
    expect(files.deleted, isEmpty);
    local.openGate!.complete();
    await restoring;
    expect(files.keptOrphans, isNull); // frozen: nothing removed
  });
}
