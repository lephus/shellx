import 'dart:convert';
import 'dart:ui';

import 'package:flutter/foundation.dart' show TargetPlatform;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/l10n/app_localizations.dart';
import 'package:shellx_desktop/src/agent/desktop_services.dart'
    show clockProvider;
import 'package:shellx_desktop/src/platform/settings_store.dart';
import 'package:shellx_desktop/src/terminal/local_sessions_provider.dart';
import 'package:shellx_desktop/src/terminal/sidebar_workspaces.dart';
import 'package:shellx_desktop/src/terminal/terminal_tabs.dart';
import 'package:shellx_desktop/src/tools/tool_dock.dart';
import 'package:shellx_desktop/src/tools/tool_dock_state.dart';
import 'package:shellx_desktop/src/tools/tool_embed.dart';
import 'package:shellx_desktop/src/tools/tool_entry.dart';
import 'package:shellx_desktop/src/tools/tool_registry.dart';

import '../support/fake_local_sessions.dart';

void main() {
  late ProviderContainer c;
  var next = 0;

  /// The dock controller over a fresh window; `tool-embed = auto` embeds
  /// (macOS) unless [extra] says otherwise.
  ProviderContainer start({List<Override> extra = const []}) {
    final container = ProviderContainer.test(
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
        toolPlatformProvider.overrideWithValue(TargetPlatform.macOS),
        ...extra,
      ],
    );
    container.read(sidebarWorkspacesProvider);
    container.read(toolDockProvider);
    return container;
  }

  setUp(() {
    next = 0;
    c = start();
  });

  ToolDockController dock() => c.read(toolDockProvider.notifier);
  ToolDocks docks() => c.read(toolDockProvider);
  ToolEntry add(String ws, int port) => c
      .read(toolRegistryProvider.notifier)
      .add(ws: ws, name: '', url: 'localhost:$port')!;

  test('open, activate, close a chip, close and reopen the dock (D4, D5)', () {
    final a = add(kDefaultWorkspaceId, 1), b = add(kDefaultWorkspaceId, 2);
    dock().open(kDefaultWorkspaceId, a.id);
    dock().open(kDefaultWorkspaceId, b.id);
    expect(docks().of(kDefaultWorkspaceId).tools, [a.id, b.id]);
    dock().activate(kDefaultWorkspaceId, a.id);
    expect(docks().of(kDefaultWorkspaceId).active, a.id);
    dock().close(kDefaultWorkspaceId);
    expect(docks().of(kDefaultWorkspaceId).open, isFalse);
    expect(docks().of(kDefaultWorkspaceId).tools, [a.id, b.id], reason: 'D5');
    expect(dock().reopen(kDefaultWorkspaceId), isTrue);
    expect(docks().of(kDefaultWorkspaceId).active, a.id);
    dock().closeTool(kDefaultWorkspaceId, a.id);
    dock().closeTool(kDefaultWorkspaceId, b.id);
    expect(docks().of(kDefaultWorkspaceId).open, isFalse);
    expect(dock().reopen(kDefaultWorkspaceId), isFalse);
  });

  test('zoom and width are the workspace\'s own (D3)', () {
    final a = add(kDefaultWorkspaceId, 1);
    final ws2 = c.read(sidebarWorkspacesProvider.notifier).createFor(name: 'B');
    final b = add(ws2, 2);
    dock().open(kDefaultWorkspaceId, a.id);
    dock().open(ws2, b.id);
    dock().setZoom(ws2, true);
    dock().setWidth(kDefaultWorkspaceId, 0.6);
    expect(docks().of(ws2).zoom, isTrue);
    expect(docks().of(kDefaultWorkspaceId).zoom, isFalse);
    expect(docks().of(kDefaultWorkspaceId).width, 0.6);
    expect(docks().of(ws2).width, kToolDockDefaultWidth);
  });

  test('a deleted tool leaves every dock (D23)', () {
    final a = add(kDefaultWorkspaceId, 1), b = add(kDefaultWorkspaceId, 2);
    dock().open(kDefaultWorkspaceId, a.id);
    dock().open(kDefaultWorkspaceId, b.id);
    c.read(toolRegistryProvider.notifier).remove(b.id);
    expect(docks().of(kDefaultWorkspaceId).tools, [a.id]);
    expect(docks().of(kDefaultWorkspaceId).active, a.id);
    c.read(toolRegistryProvider.notifier).remove(a.id);
    expect(docks().of(kDefaultWorkspaceId).open, isFalse);
  });

  test('a deleted workspace takes its dock and its tools (D2, §8)', () {
    final side = c.read(sidebarWorkspacesProvider.notifier);
    final ws2 = side.createFor(name: 'B');
    final b = add(ws2, 2);
    final a = add(kDefaultWorkspaceId, 1);
    dock().open(ws2, b.id);
    side.delete(ws2);
    expect(docks().byWorkspace.containsKey(ws2), isFalse);
    expect(c.read(toolRegistryProvider), [a]);
  });

  test('loose: shown until a tab is selected (D4)', () async {
    final side = c.read(sidebarWorkspacesProvider.notifier);
    await c.read(terminalTabsProvider.notifier).openTab();
    final ws2 = side.createFor(name: 'B');
    dock().showLoose(ws2);
    expect(docks().loose, ws2);
    await side.openTabIn(ws2);
    expect(docks().loose, isNull);
  });

  test('the last tab of each workspace is remembered (D4)', () async {
    final tabs = c.read(terminalTabsProvider.notifier);
    await tabs.openTab();
    await tabs.openTab();
    final first = c.read(terminalTabsProvider).tabs.first.id;
    tabs.select(first);
    expect(dock().lastTabOf(kDefaultWorkspaceId), first);
  });

  test('restore keeps known workspaces and tools; saved skips defaults '
      '(D14)', () {
    final a = add(kDefaultWorkspaceId, 1);
    dock().restore({
      kDefaultWorkspaceId: ToolDockState(
        open: true,
        active: a.id,
        tools: [a.id, 'zzzzzzzzzz'],
      ),
      'gone': ToolDockState(open: true, tools: [a.id]),
    });
    expect(docks().of(kDefaultWorkspaceId).tools, [a.id]);
    expect(docks().byWorkspace.containsKey('gone'), isFalse);
    expect(dock().saved.keys, [kDefaultWorkspaceId]);
    dock().closeTool(kDefaultWorkspaceId, a.id);
    expect(dock().saved, isEmpty);
  });

  // V1 and V2.0 delete a workspace without touching `workspace_tools`, so
  // the tools of such a workspace are still stored when this build starts.
  test('the tools of a workspace the sidebar lacks are dropped after the '
      'controller starts (D2, §8)', () async {
    String stored(String id, String ws) => jsonEncode(
      ToolEntry(id: id, ws: ws, name: id, url: 'http://localhost:1/').toJson(),
    );
    InMemorySettingsStore seeded() {
      final settings = InMemorySettingsStore();
      settings.strings[SettingKeys.terminalWorkspaces] = [
        const Workspace(id: 'w1', name: 'B').encode(),
      ];
      settings.strings[SettingKeys.workspaceTools] = [
        stored('aaaaaaaaaa', kDefaultWorkspaceId),
        stored('bbbbbbbbbb', 'w1'),
        stored('cccccccccc', 'deleted-by-an-older-build'),
      ];
      return settings;
    }

    ProviderContainer start(InMemorySettingsStore settings) =>
        ProviderContainer.test(
          overrides: [
            localSessionsProvider.overrideWithValue(FakeLocalSessions()),
            settingsStoreProvider.overrideWithValue(settings),
            clockProvider.overrideWithValue(() => DateTime(2026, 10, 15, 9)),
            appL10nProvider.overrideWithValue(
              lookupAppLocalizations(const Locale('en')),
            ),
          ],
        );

    final settings = seeded();
    final fresh = start(settings);
    fresh.read(toolDockProvider);
    await Future<void>.delayed(Duration.zero);
    expect(
      [for (final t in fresh.read(toolRegistryProvider)) t.id],
      ['aaaaaaaaaa', 'bbbbbbbbbb'],
    );
    expect(
      [
        for (final s in settings.getStrings(SettingKeys.workspaceTools))
          (jsonDecode(s) as Map<String, Object?>)['id'],
      ],
      ['aaaaaaaaaa', 'bbbbbbbbbb'],
      reason: 'saved too',
    );

    // A container gone before the prune runs is left alone.
    final other = seeded();
    start(other)
      ..read(toolDockProvider)
      ..dispose();
    await Future<void>.delayed(Duration.zero);
    expect(other.getStrings(SettingKeys.workspaceTools), hasLength(3));
  });

  test('the panes are covered by the shown workspace\'s dock zoomed, or by '
      'a workspace shown without a tab; never by a dock beside them or by '
      'another workspace\'s (V2-3 D3, D4)', () async {
    bool covered() => c.read(toolPanesCoveredProvider);
    final side = c.read(sidebarWorkspacesProvider.notifier);
    await c.read(terminalTabsProvider.notifier).openTab();
    final a = add(kDefaultWorkspaceId, 1);
    expect(covered(), isFalse, reason: 'no dock');
    dock().open(kDefaultWorkspaceId, a.id);
    expect(covered(), isFalse, reason: 'beside the panes');
    dock().setZoom(kDefaultWorkspaceId, true);
    expect(covered(), isTrue, reason: 'zoomed');
    final ws2 = side.createFor(name: 'B');
    final b = add(ws2, 2);
    dock().open(ws2, b.id);
    dock().setZoom(ws2, true);
    dock().setZoom(kDefaultWorkspaceId, false);
    expect(covered(), isFalse, reason: "another workspace's dock");
    dock().showLoose(ws2);
    expect(covered(), isTrue, reason: 'loose, its dock zoomed');
    dock().setZoom(ws2, false);
    expect(covered(), isTrue, reason: 'loose, its dock beside');
    dock().clearLoose();
    expect(covered(), isFalse);
    dock().close(kDefaultWorkspaceId);
    expect(covered(), isFalse, reason: 'closed');

    // `tool-embed = off`: no dock is drawn, zoomed or not.
    final off = start(extra: [toolsEmbeddedProvider.overrideWithValue(false)]);
    await off.read(terminalTabsProvider.notifier).openTab();
    final t = off
        .read(toolRegistryProvider.notifier)
        .add(ws: kDefaultWorkspaceId, name: '', url: 'localhost:3')!;
    off.read(toolDockProvider.notifier)
      ..open(kDefaultWorkspaceId, t.id)
      ..setZoom(kDefaultWorkspaceId, true);
    expect(off.read(toolPanesCoveredProvider), isFalse);
  });

  test('ToolDocks.toString() shows a count only (D24)', () {
    final ws2 = c.read(sidebarWorkspacesProvider.notifier).createFor(name: 'B');
    final a = add(kDefaultWorkspaceId, 1), b = add(ws2, 2);
    dock().open(kDefaultWorkspaceId, a.id);
    dock().open(ws2, b.id);
    dock().showLoose(ws2);
    expect(docks().byWorkspace, hasLength(2));
    final text = docks().toString();
    expect(text, 'ToolDocks(2)');
    for (final id in [kDefaultWorkspaceId, ws2, a.id, b.id]) {
      expect(text, isNot(contains(id)));
    }
  });
}
