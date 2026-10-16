import 'dart:convert';
import 'dart:ui';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/l10n/app_localizations.dart';
import 'package:shellx_desktop/src/agent/desktop_services.dart'
    show clockProvider;
import 'package:shellx_desktop/src/platform/settings_store.dart';
import 'package:shellx_desktop/src/restore/restore_capture.dart';
import 'package:shellx_desktop/src/restore/restore_persistence.dart';
import 'package:shellx_desktop/src/restore/restore_snapshot.dart';
import 'package:shellx_desktop/src/restore/restore_store.dart';
import 'package:shellx_desktop/src/terminal/local_sessions_provider.dart';
import 'package:shellx_desktop/src/terminal/sidebar_workspaces.dart';
import 'package:shellx_desktop/src/terminal/terminal_tabs.dart';
import 'package:shellx_desktop/src/tools/tool_dock.dart';
import 'package:shellx_desktop/src/tools/tool_entry.dart';
import 'package:shellx_desktop/src/tools/tool_registry.dart';

import '../support/ai_tabs.dart';
import '../support/fake_local_sessions.dart';
import '../support/restore_fakes.dart';
import 'v1/restore_snapshot_v1.dart' as v1;
import 'v2_0/restore_snapshot_v2_0.dart' as v20;

void main() {
  late RecordingFiles files;
  late ProviderContainer c;
  var next = 0;

  setUp(() {
    next = 0;
    files = RecordingFiles();
    c = ProviderContainer.test(
      overrides: [
        localSessionsProvider.overrideWithValue(FakeLocalSessions()),
        settingsStoreProvider.overrideWithValue(InMemorySettingsStore()),
        restoreStoreProvider.overrideWithValue(files),
        clockProvider.overrideWithValue(() => DateTime(2026, 10, 15, 9)),
        appL10nProvider.overrideWithValue(
          lookupAppLocalizations(const Locale('en')),
        ),
        toolIdSourceProvider.overrideWithValue(
          () => 'tool${(next++).toString().padLeft(6, '0')}',
        ),
      ],
    );
    c.read(sidebarWorkspacesProvider);
    c.read(toolDockProvider);
  });

  final termKey = 'b' * 32;
  final aiKey = 'a' * 32;

  ToolEntry add(int port) => c
      .read(toolRegistryProvider.notifier)
      .add(ws: kDefaultWorkspaceId, name: 'T$port', url: 'localhost:$port')!;

  RestoreSnapshot capture() => captureSnapshot(
    tabs: c.read(terminalTabsProvider),
    sidebar: c.read(sidebarWorkspacesProvider),
    keyOf: (_) => termKey,
    now: DateTime(2026, 10, 15, 9),
    cleanExit: true,
    aiKeyOf: (_) => aiKey,
    toolDock: c.read(toolDockProvider.notifier).saved,
  );

  Future<ToolEntry> withDock() async {
    await c.read(terminalTabsProvider.notifier).openTab();
    final t = add(5173);
    c.read(toolDockProvider.notifier).open(kDefaultWorkspaceId, t.id);
    c.read(toolDockProvider.notifier).setWidth(kDefaultWorkspaceId, 0.5);
    return t;
  }

  test('the docks are saved under a top-level toolDock (D14)', () async {
    final t = await withDock();
    final json = jsonDecode(capture().encode()) as Map<String, Object?>;
    expect(json['v'], 1);
    expect(json['toolDock'], {
      kDefaultWorkspaceId: {
        'open': true,
        'zoom': false,
        'width': 0.5,
        'active': t.id,
        'tools': [t.id],
      },
    });
  });

  test('without a dock there is no toolDock key at all', () async {
    await c.read(terminalTabsProvider.notifier).openTab();
    final json = jsonDecode(capture().encode()) as Map<String, Object?>;
    expect(json.containsKey('toolDock'), isFalse);
  });

  test('round trip: what was written reads back', () async {
    final t = await withDock();
    final back = RestoreSnapshot.tryParse(capture().encode())!;
    expect(back.toolDock[kDefaultWorkspaceId]!.tools, [t.id]);
    expect(back.toolDock[kDefaultWorkspaceId]!.width, 0.5);
    expect(back.tabs, hasLength(1));
  });

  test('a damaged dock is dropped, never the file (D14)', () async {
    await withDock();
    final json = jsonDecode(capture().encode()) as Map<String, Object?>;
    json['toolDock'] = {
      kDefaultWorkspaceId: 'nope',
      '': {'open': true},
      'w2': {'tools': 'x'},
    };
    final back = RestoreSnapshot.tryParse(jsonEncode(json))!;
    expect(back.toolDock, isEmpty);
    expect(back.tabs, hasLength(1));
    json['toolDock'] = 42;
    expect(RestoreSnapshot.tryParse(jsonEncode(json))!.tabs, hasLength(1));
  });

  test('V1 compatibility: the V1 parser keeps the tabs and ignores '
      'toolDock (no .bak)', () async {
    await withDock();
    final old = v1.RestoreSnapshot.tryParse(capture().encode());
    expect(old, isNotNull);
    expect(old!.tabs.map((t) => t.key), [termKey]);
  });

  test('V2.0 compatibility: the V2.0 parser keeps the terminal and AI tabs '
      'and ignores toolDock (no .bak)', () async {
    await withDock();
    openTestAiTab(c, title: 'Fix login', cwd: '/w/shop');
    final text = capture().encode();
    expect(text, contains('"toolDock"'));
    final old = v20.RestoreSnapshot.tryParse(text);
    expect(old, isNotNull);
    expect(old!.tabs.map((t) => t.key), [termKey]);
    expect(old.aiTabs.single.key, aiKey);
  });

  test('persistence writes a dock change and the startup restore brings it '
      'back (D14)', () async {
    final persistence = c.read(restorePersistenceProvider.notifier)..start();
    final t = await withDock();
    await persistence.flushAll(clean: false);
    final written = files.layouts.last;
    expect(written.toolDock[kDefaultWorkspaceId]!.active, t.id);

    // A new run: same settings (the tool), the file just written.
    final settings = c.read(settingsStoreProvider);
    c.dispose();
    c = ProviderContainer.test(
      overrides: [
        localSessionsProvider.overrideWithValue(FakeLocalSessions()),
        settingsStoreProvider.overrideWithValue(settings),
        restoreStoreProvider.overrideWithValue(RecordingFiles()),
        clockProvider.overrideWithValue(() => DateTime(2026, 10, 15, 10)),
        appL10nProvider.overrideWithValue(
          lookupAppLocalizations(const Locale('en')),
        ),
      ],
    );
    c.read(sidebarWorkspacesProvider);
    await c
        .read(restorePersistenceProvider.notifier)
        .restoreAtStartup(RestoreLoad(snapshot: written));
    final dock = c.read(toolDockProvider).of(kDefaultWorkspaceId);
    expect([dock.open, dock.active, dock.width], [true, t.id, 0.5]);
  });

  test('a dock change alone schedules a write (D14)', () {
    fakeAsync((async) {
      c.read(restorePersistenceProvider.notifier).start();
      final t = add(5173);
      final dock = c.read(toolDockProvider.notifier);
      async.elapse(const Duration(seconds: 2));
      expect(files.layouts, isEmpty); // a tool alone is not in the layout

      // Opened: written 1 s after the change, not before.
      dock.open(kDefaultWorkspaceId, t.id);
      async.elapse(const Duration(milliseconds: 999));
      expect(files.layouts, isEmpty);
      async.elapse(const Duration(milliseconds: 2));
      expect(files.layouts, hasLength(1));
      expect(files.layouts.last.toolDock[kDefaultWorkspaceId]!.open, isTrue);

      // Resized, zoomed: each is a layout change of its own.
      dock.setWidth(kDefaultWorkspaceId, 0.6);
      async.elapse(const Duration(seconds: 2));
      expect(files.layouts, hasLength(2));
      expect(files.layouts.last.toolDock[kDefaultWorkspaceId]!.width, 0.6);
      dock.setZoom(kDefaultWorkspaceId, true);
      async.elapse(const Duration(seconds: 2));
      expect(files.layouts, hasLength(3));
      expect(files.layouts.last.toolDock[kDefaultWorkspaceId]!.zoom, isTrue);

      // Back to the default: the key leaves the file.
      dock.closeTool(kDefaultWorkspaceId, t.id);
      dock.setWidth(kDefaultWorkspaceId, 0.45);
      async.elapse(const Duration(seconds: 2));
      expect(files.layouts, hasLength(4));
      expect(files.layouts.last.toolDock, isEmpty);
      expect(files.layouts.last.encode(), isNot(contains('toolDock')));

      // Nothing changed: nothing is written.
      dock.close(kDefaultWorkspaceId);
      async.elapse(const Duration(seconds: 2));
      expect(files.layouts, hasLength(4));
    });
  });
}
