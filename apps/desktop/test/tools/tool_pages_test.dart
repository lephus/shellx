import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/l10n/app_localizations.dart';
import 'package:shellx_desktop/src/agent/desktop_services.dart'
    show clockProvider;
import 'package:shellx_desktop/src/platform/settings_store.dart';
import 'package:shellx_desktop/src/terminal/local_sessions_provider.dart';
import 'package:shellx_desktop/src/terminal/sidebar_workspaces.dart';
import 'package:shellx_desktop/src/terminal/terminal_tabs.dart';
import 'package:shellx_desktop/src/tools/tool_dock.dart';
import 'package:shellx_desktop/src/tools/tool_entry.dart';
import 'package:shellx_desktop/src/tools/tool_pages.dart';
import 'package:shellx_desktop/src/tools/tool_registry.dart';

import '../support/config_harness.dart';
import '../support/fake_browser_engine.dart';
import '../support/fake_local_sessions.dart';
import '../support/memory_config_fs.dart';

void main() {
  late ProviderContainer c;
  late MemoryConfigFs fs;
  final engines = <String, FakeBrowserEngine>{};
  var next = 0;

  setUp(() async {
    next = 0;
    engines.clear();
    fs = MemoryConfigFs();
    c = ProviderContainer.test(
      overrides: [
        localSessionsProvider.overrideWithValue(FakeLocalSessions()),
        settingsStoreProvider.overrideWithValue(InMemorySettingsStore()),
        clockProvider.overrideWithValue(() => DateTime(2026, 10, 15, 9)),
        appL10nProvider.overrideWithValue(
          lookupAppLocalizations(const Locale('en')),
        ),
        toolIdSourceProvider.overrideWithValue(
          () => 'tool${(next++).toString().padLeft(6, '0')}',
        ),
        toolEngineFactoryProvider.overrideWithValue(
          (tool, _) => engines[tool.id] = FakeBrowserEngine(key: tool.id),
        ),
        toolKnockProvider.overrideWithValue((_, _) async => false),
        ...configOverrides(fs),
      ],
    );
    await loadConfig(c);
    c.read(sidebarWorkspacesProvider);
    c.read(toolDockProvider);
    c.read(toolPagesProvider);
  });

  ToolEntry add(int port) => c
      .read(toolRegistryProvider.notifier)
      .add(ws: kDefaultWorkspaceId, name: 'T$port', url: 'localhost:$port')!;
  ToolPages pages() => c.read(toolPagesProvider.notifier);
  void openChip(ToolEntry t) =>
      c.read(toolDockProvider.notifier).open(kDefaultWorkspaceId, t.id);

  test('a page is made once and gets the forwarded chords (D10)', () {
    final t = add(1);
    openChip(t);
    final p = pages().open(t);
    expect(pages().open(t), same(p));
    expect(c.read(toolPagesProvider), {t.id});
    expect(engines[t.id]!.forwarded, contains('super+t'));
    expect(engines[t.id]!.loads, isEmpty, reason: 'loads when shown');
  });

  test('the ninth page unloads the one unseen longest; its chip stays and '
      'a toast says so (D5)', () {
    final tools = [for (var i = 1; i <= 9; i++) add(i)];
    for (final t in tools) {
      openChip(t);
      pages().open(t).setShown(true);
      pages().existing(t.id)!.setShown(false);
    }
    expect(c.read(toolPagesProvider), hasLength(kMaxLiveToolPages));
    expect(pages().existing(tools.first.id), isNull);
    expect(engines[tools.first.id]!.disposed, isTrue);
    expect(
      c.read(toolDockProvider).of(kDefaultWorkspaceId).tools,
      contains(tools.first.id),
    );
    final notice = c.read(terminalTabsProvider).notice;
    expect(notice, isA<ToolUnloadedNotice>());
    expect((notice! as ToolUnloadedNotice).name, 'T1');
  });

  test('the page on screen is never the one unloaded', () {
    final tools = [for (var i = 1; i <= 9; i++) add(i)];
    openChip(tools.first);
    pages().open(tools.first).setShown(true);
    for (final t in tools.skip(1)) {
      openChip(t);
      pages().open(t);
    }
    expect(pages().existing(tools.first.id), isNotNull);
    expect(pages().existing(tools[1].id), isNull);
  });

  test('a closed chip or a deleted tool takes its page (D5, D23)', () {
    final a = add(1), b = add(2);
    openChip(a);
    openChip(b);
    pages().open(a);
    pages().open(b);
    c.read(toolDockProvider.notifier).closeTool(kDefaultWorkspaceId, a.id);
    expect(pages().existing(a.id), isNull);
    expect(engines[a.id]!.disposed, isTrue);
    c.read(toolRegistryProvider.notifier).remove(b.id);
    expect(pages().existing(b.id), isNull);
    expect(c.read(toolPagesProvider), isEmpty);
  });

  test('closing the dock keeps the pages (D5)', () {
    final a = add(1);
    openChip(a);
    pages().open(a);
    c.read(toolDockProvider.notifier).close(kDefaultWorkspaceId);
    expect(pages().existing(a.id), isNotNull);
  });

  test('an edited URL reloads the open page there (D23)', () {
    final a = add(1);
    openChip(a);
    pages().open(a).setShown(true);
    c
        .read(toolRegistryProvider.notifier)
        .update(a.copyWith(url: 'localhost:2'));
    expect(engines[a.id]!.loads.last, Uri.parse('http://localhost:2/'));
  });

  test('a reload of the keys reaches every live page (D10)', () async {
    final a = add(1);
    openChip(a);
    pages().open(a);
    fs.write(testConfigPaths().shellx, 'keybind = super+shift+j=new_tab\n');
    await loadConfig(c);
    expect(engines[a.id]!.forwarded, contains('shift+super+j'));
  });

  test('toString shows a count only (D24)', () {
    final a = add(1), b = add(2);
    openChip(a);
    openChip(b);
    pages().open(a);
    pages().open(b);
    expect(pages().toString(), 'ToolPages(2)');
  });
}
