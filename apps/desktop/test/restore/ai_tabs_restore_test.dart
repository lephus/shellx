import 'dart:convert';
import 'dart:ui';

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
import 'package:shellx_desktop/src/terminal/tab_meta.dart';
import 'package:shellx_desktop/src/terminal/terminal_tabs.dart';

import '../support/ai_tabs.dart';
import '../support/fake_local_sessions.dart';
import '../support/restore_fakes.dart';
import 'v1/restore_snapshot_v1.dart' as v1;

void main() {
  late FakeLocalSessions local;
  late RecordingFiles files;
  late ProviderContainer c;

  void boot() {
    c = ProviderContainer.test(
      overrides: [
        localSessionsProvider.overrideWithValue(local),
        settingsStoreProvider.overrideWithValue(InMemorySettingsStore()),
        restoreStoreProvider.overrideWithValue(files),
        clockProvider.overrideWithValue(() => DateTime(2026, 10, 14, 9)),
        appL10nProvider.overrideWithValue(
          lookupAppLocalizations(const Locale('en')),
        ),
      ],
    );
    c.read(sidebarWorkspacesProvider);
  }

  setUp(() {
    local = FakeLocalSessions();
    files = RecordingFiles();
    boot();
  });

  final aiKey = 'a' * 32;
  final termKey = 'b' * 32;

  RestoreSnapshot capture({bool withAi = true}) {
    final keys = <int, String>{};
    return captureSnapshot(
      tabs: c.read(terminalTabsProvider),
      sidebar: c.read(sidebarWorkspacesProvider),
      keyOf: (id) => keys.putIfAbsent(id, () => termKey),
      now: DateTime(2026, 10, 14, 9),
      cleanExit: true,
      aiKeyOf: withAi ? (_) => aiKey : null,
    );
  }

  Future<TerminalTab> twoTabs() async {
    await c.read(terminalTabsProvider.notifier).openTab(); // 100
    final ai = openTestAiTab(
      c,
      title: 'Fix login',
      cwd: '/w/shop',
      sessionId: 'sess-1',
    );
    c.read(terminalTabsProvider.notifier).rename(ai.id, 'Mine');
    return ai;
  }

  test(
    'an AI tab is saved in aiTabs; its key sits in its workspace (D14)',
    () async {
      await twoTabs();
      final s = capture();
      expect(s.tabs.map((t) => t.key), [termKey]);
      final ai = s.aiTabs.single;
      expect(
        [ai.key, ai.title, ai.name, ai.agent, ai.agentName, ai.session, ai.cwd],
        [aiKey, 'Fix login', 'Mine', 'claude', 'Claude', 'sess-1', '/w/shop'],
      );
      expect(s.workspaces.single.tabs, [termKey, aiKey]);
      expect(s.selectedTab, aiKey);
      final json = jsonDecode(s.encode()) as Map<String, Object?>;
      expect(json['v'], 1);
      final entry = (json['aiTabs']! as List).single as Map<String, Object?>;
      expect(entry['layout'], {'ai': aiKey});
      expect(entry['focused'], aiKey);
      expect(entry.containsKey('zoomed'), isTrue);
      expect(s.encode(), isNot(contains('Claude Code')));
    },
  );

  test('without AI tabs the layout has no aiTabs key at all', () async {
    await c.read(terminalTabsProvider.notifier).openTab();
    final json = jsonDecode(capture().encode()) as Map<String, Object?>;
    expect(json.containsKey('aiTabs'), isFalse);
  });

  test('round trip: what was written reads back', () async {
    await twoTabs();
    final back = RestoreSnapshot.tryParse(capture().encode())!;
    final ai = back.aiTabs.single;
    expect([ai.title, ai.session, ai.cwd], ['Fix login', 'sess-1', '/w/shop']);
    expect(back.selectedTab, aiKey);
    expect(back.workspaces.single.tabs, [termKey, aiKey]);
    expect(back.hasTabs, isTrue);
  });

  test('V1 compatibility: the V1 parser keeps the terminal tabs, ignores '
      'aiTabs and the AI keys, and never fails (no .bak)', () async {
    await twoTabs();
    final old = v1.RestoreSnapshot.tryParse(capture().encode());
    expect(old, isNotNull);
    expect(old!.tabs.map((t) => t.key), [termKey]);
    expect(old.workspaces.single.tabs, [termKey]);
    expect(old.selectedTab, isNull, reason: 'it was the AI tab');
  });

  test('a damaged AI tab is dropped, the file still loads', () async {
    await c.read(terminalTabsProvider.notifier).openTab();
    final json = jsonDecode(capture().encode()) as Map<String, Object?>;
    json['aiTabs'] = [
      {'key': 'nope'},
      {'key': aiKey, 'agent': 'claude', 'layout': <String, Object?>{}},
      42,
    ];
    final back = RestoreSnapshot.tryParse(jsonEncode(json))!;
    expect(back.aiTabs, isEmpty);
    expect(back.tabs, hasLength(1));
  });

  test('a layout with only AI tabs is the one restored (Review Focus 2)', () {
    final aiOnly = RestoreSnapshot(
      savedAt: DateTime(2026, 10, 14),
      cleanExit: false,
      workspaces: const [],
      tabs: const [],
      aiTabs: [
        SavedAiTab(
          key: aiKey,
          title: 'Fix login',
          agent: 'claude',
          agentName: 'Claude',
        ),
      ],
    );
    final older = RestoreSnapshot(
      savedAt: DateTime(2026, 10, 13),
      cleanExit: true,
      workspaces: const [],
      tabs: [
        SavedTab(
          key: termKey,
          focused: termKey,
          layout: SavedPane(key: termKey, cwd: '/w'),
        ),
      ],
    );
    final pick = pickSnapshot(current: aiOnly, generations: [older]);
    expect(pick.snapshot, same(aiOnly));
    expect(pick.recovered, isFalse);
  });

  test(
    'restore reopens AI tabs as saved, selected, and starts nothing',
    () async {
      final snapshot = RestoreSnapshot(
        savedAt: DateTime(2026, 10, 14),
        cleanExit: true,
        selectedTab: aiKey,
        workspaces: [
          SavedWorkspace(id: 'default', tabs: [aiKey]),
        ],
        tabs: const [],
        aiTabs: [
          SavedAiTab(
            key: aiKey,
            title: 'Fix login',
            name: 'Mine',
            agent: 'claude',
            agentName: 'Claude',
            session: 'sess-1',
            cwd: '/w/shop',
            pinned: true,
            status: TabStatus.inProgress,
          ),
        ],
      );
      final outcome = await c
          .read(terminalTabsProvider.notifier)
          .restore(RestorePlan(snapshot: snapshot, textByKey: const {}));
      final tabs = c.read(terminalTabsProvider);
      final tab = tabs.tabs.single;
      expect(tab.isAi, isTrue);
      expect(tab.label, 'Mine');
      expect(tab.meta.pinned, isTrue);
      expect(tab.meta.status, TabStatus.inProgress);
      expect(
        [tab.ai!.title, tab.ai!.sessionId, tab.ai!.cwd],
        ['Fix login', 'sess-1', '/w/shop'],
      );
      expect(tabs.selectedId, tab.id);
      expect(outcome.tabIdByKey[aiKey], tab.id);
      expect(outcome.aiKeyByPane[tab.ai!.id], aiKey);
      expect(local.opens, isEmpty, reason: 'no shell, no agent');
    },
  );

  test('persistence writes AI tabs with keys stable across writes', () async {
    c.read(restorePersistenceProvider.notifier).start();
    await twoTabs();
    await c.read(restorePersistenceProvider.notifier).flushAll(clean: false);
    final first = files.layouts.last.aiTabs.single.key;
    c
        .read(terminalTabsProvider.notifier)
        .rename(c.read(terminalTabsProvider).selectedId!, 'Other');
    await c.read(restorePersistenceProvider.notifier).flushAll(clean: false);
    expect(files.layouts.last.aiTabs.single.key, first);
    expect(files.layouts.last.aiTabs.single.name, 'Other');
  });
}
